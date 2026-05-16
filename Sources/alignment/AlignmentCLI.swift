import ArgumentParser
import Foundation
import SwiftAlignmentProgramming

@main
struct AlignmentCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alignment",
        abstract: "Swift alignment programming toolkit",
        subcommands: [
            InterfaceCommand.self,
            ScoreCommand.self,
            DashboardCommand.self,
            ComplexityCommand.self,
            ComplexitySummaryCommand.self,
            ComplexityDashboardCommand.self,
        ]
    )
}

// MARK: - alignment interface

struct InterfaceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "interface",
        abstract: "Generate a readable pseudo-Swift public interface for a SwiftPM package"
    )

    @Option(help: "SwiftPM target name. If omitted, generates interfaces for all non-test targets.")
    var target: String?

    @Option(help: "Path to the Swift package root (defaults to current directory)")
    var packagePath: String = "."

    @Option(help: "Use an existing symbol graph directory instead of building the target")
    var symbolGraphDir: String?

    @Option(help: "Write output to this file (single target) or directory (all targets). Defaults to stdout for single target, .build/alignment-interfaces/ for all targets.")
    var output: String?

    @Option(help: "Path to .alignment-sections file for section-based output (single target only)")
    var sections: String?

    @Option(help: "Build system: native or swiftbuild (default: native)")
    var buildSystem: String = "native"

    func validate() throws {
        let valid = ["native", "swiftbuild"]
        guard valid.contains(buildSystem) else {
            throw ValidationError("--build-system must be 'native' or 'swiftbuild', got '\(buildSystem)'")
        }
        if target == nil && sections != nil {
            throw ValidationError("--sections can only be used with --target (single target mode)")
        }
    }

    func run() throws {
        let pkgURL = URL(fileURLWithPath: packagePath).standardizedFileURL

        guard target != nil || symbolGraphDir != nil else {
            // All-targets mode: build + render every non-test target
            try runAllTargets(pkgURL: pkgURL)
            return
        }

        // Single-target mode
        let targetName = target!
        let sgDir: URL
        if let dir = symbolGraphDir {
            sgDir = URL(fileURLWithPath: dir).standardizedFileURL
        } else {
            sgDir = try buildSymbolGraphs(packagePath: pkgURL, target: targetName, buildSystem: buildSystem)
        }

        let outline = try buildOutline(from: sgDir, module: targetName)

        let output: String
        if let sectionPath = sections {
            let sectionContent = try String(contentsOfFile: sectionPath, encoding: .utf8)
            let sectionConfigs = try SectionConfig.parse(sectionContent)
            let sectioned = assignSections(outline: outline, sections: sectionConfigs)
            output = sectioned.sectionedText + "\n\n" + sectioned.indexMarkdown
        } else {
            output = renderOutline(outline)
        }

        if let outputPath = self.output {
            let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try output.write(to: outputURL, atomically: true, encoding: .utf8)
            print("Wrote interface to \(outputURL.path)")
        } else {
            print(output)
        }
    }

    private func runAllTargets(pkgURL: URL) throws {
        let fm = FileManager.default
        let targets = try listInterfaceTargets(packagePath: pkgURL)

        guard !targets.isEmpty else {
            print("No interface-eligible targets found in \(pkgURL.path)")
            return
        }

        let sgDir = try buildSymbolGraphs(packagePath: pkgURL, target: nil, buildSystem: buildSystem)

        let outputDirURL: URL
        if let out = output {
            outputDirURL = URL(fileURLWithPath: out).standardizedFileURL
        } else {
            outputDirURL = pkgURL
                .appendingPathComponent(".build")
                .appendingPathComponent("alignment-interfaces")
        }
        try fm.createDirectory(at: outputDirURL, withIntermediateDirectories: true)

        var successCount = 0
        var skipCount = 0
        for target in targets {
            do {
                let rendered = try renderFromSymbolGraphDirectory(sgDir, module: target)
                let outFile = outputDirURL.appendingPathComponent("\(target).swift")
                try rendered.write(to: outFile, atomically: true, encoding: .utf8)
                print("  \(target) -> \(outFile.path)")
                successCount += 1
            } catch {
                print("  ⚠ skipped \(target): \(error)")
                skipCount += 1
            }
        }
        print("Interfaces: \(successCount) generated, \(skipCount) skipped → \(outputDirURL.path)")
    }
}

// MARK: - Symbol Graph Building

/// Build symbol graphs for a package.  If `target` is nil, builds all targets
/// in one invocation (no `--target` flag).
private func buildSymbolGraphs(packagePath: URL, target: String?, buildSystem: String) throws -> URL {
    let artifactDir = packagePath
        .appendingPathComponent(".build")
        .appendingPathComponent("public-interface-artifacts")
        .appendingPathComponent("symbolgraphs")

    try? FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)

    // Selective clean for native builds: remove own-target artifacts so
    // the compiler re-emits fresh symbol graphs, while keeping dependency
    // artifacts cached.
    if buildSystem == "native" {
        cleanOwnTargets(packagePath: packagePath)
    }

    let tmpDir = FileManager.default.temporaryDirectory
    let stdoutFile = tmpDir.appendingPathComponent("alignment-build-out-\(UUID().uuidString).log")
    let stderrFile = tmpDir.appendingPathComponent("alignment-build-err-\(UUID().uuidString).log")
    defer {
        try? FileManager.default.removeItem(at: stdoutFile)
        try? FileManager.default.removeItem(at: stderrFile)
    }

    let process = Process()
#if os(Linux)
    process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    var args = ["build"]
#else
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    var args = ["swift", "build", "--build-system", buildSystem]
#endif
    args.append(contentsOf: [
        "--package-path", packagePath.path,
    ])
    if let target {
        args.append(contentsOf: ["--target", target])
    }
    args.append(contentsOf: [
        "-Xswiftc", "-emit-symbol-graph",
        "-Xswiftc", "-emit-symbol-graph-dir",
        "-Xswiftc", artifactDir.path,
        "-Xswiftc", "-symbol-graph-minimum-access-level",
        "-Xswiftc", "public",
    ])
    process.arguments = args

    FileManager.default.createFile(atPath: stdoutFile.path, contents: nil)
    FileManager.default.createFile(atPath: stderrFile.path, contents: nil)
    guard let outFH = try? FileHandle(forWritingTo: stdoutFile),
          let errFH = try? FileHandle(forWritingTo: stderrFile) else {
        throw ValidationError("Failed to create temp files for build output")
    }
    process.standardOutput = outFH
    process.standardError = errFH

    try process.run()
    process.waitUntilExit()

    try outFH.synchronize()
    try errFH.synchronize()
    try outFH.close()
    try errFH.close()

    if process.terminationStatus != 0 {
        if let outStr = try? String(contentsOf: stdoutFile, encoding: .utf8), !outStr.isEmpty {
            FileHandle.standardError.write(Data(outStr.utf8))
        }
        if let errStr = try? String(contentsOf: stderrFile, encoding: .utf8), !errStr.isEmpty {
            FileHandle.standardError.write(Data(errStr.utf8))
        }
        throw ExitCode(process.terminationStatus)
    }

    // Validate: at least one symbol graph was produced
    let prefix = target ?? ""
    let generated = (try? FileManager.default.contentsOfDirectory(at: artifactDir, includingPropertiesForKeys: nil))
        .flatMap { $0.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" } }
        ?? []

    guard !generated.isEmpty else {
        let label = target ?? "<all targets>"
        throw ValidationError("No symbol graph JSON files generated for \(label) in \(artifactDir.path)")
    }

    return artifactDir
}

// MARK: - Target discovery

/// Return the names of all non-test SwiftPM targets in a package.
private func listInterfaceTargets(packagePath: URL) throws -> [String] {
    let proc = Process()
#if os(Linux)
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    proc.arguments = ["package", "--package-path", packagePath.path, "dump-package"]
#else
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    proc.arguments = ["swift", "package", "--package-path", packagePath.path, "dump-package"]
#endif
    let pipe = Pipe(); proc.standardOutput = pipe
    try proc.run(); proc.waitUntilExit()
    guard proc.terminationStatus == 0,
          let json = try JSONSerialization.jsonObject(with: pipe.fileHandleForReading.readDataToEndOfFile()) as? [String: Any],
          let targets = json["targets"] as? [[String: Any]] else { return [] }
    let valid: Set<String> = ["regular", "executable", "macro"]
    return targets.compactMap { t in
        guard valid.contains(t["type"] as? String ?? ""), let name = t["name"] as? String else { return nil }
        return name
    }
}

// MARK: - Selective clean (native only)

/// Remove build artifacts for the package's own targets while keeping
/// dependency artifacts cached.
private func cleanOwnTargets(packagePath: URL) {
    let fm = FileManager.default
    let ownTargets = listAllTargets(packagePath: packagePath)
    guard !ownTargets.isEmpty else { return }

    guard let buildDir = findBuildDir(packagePath: packagePath) else { return }

    // Remove build.db so llbuild re-generates its plan
    let buildDB = packagePath.appendingPathComponent(".build/build.db")
    try? fm.removeItem(at: buildDB)

    for name in ownTargets {
        let targetBuild = buildDir.appendingPathComponent("\(name).build")
        if fm.fileExists(atPath: targetBuild.path) {
            for artifact in (try? fm.contentsOfDirectory(at: targetBuild, includingPropertiesForKeys: nil)) ?? [] {
                guard !artifact.hasDirectoryPath else { continue }
                let name = artifact.lastPathComponent
                let suffixes = [".o", ".d", ".dia", ".swiftdeps", ".priors"]
                if suffixes.contains(where: { name.hasSuffix($0) })
                    || name.hasSuffix(".swift.o")
                    || name.hasSuffix(".swiftmodule.o")
                    || name.hasSuffix(".emit-module.d")
                    || name.hasSuffix(".emit-module.dia") {
                    try? fm.removeItem(at: artifact)
                }
            }
        }

        let modulesDir = buildDir.appendingPathComponent("Modules")
        for ext in [".swiftmodule", ".swiftdoc", ".swiftsourceinfo", ".o"] {
            try? fm.removeItem(at: modulesDir.appendingPathComponent("\(name)\(ext)"))
        }

        try? fm.removeItem(at: buildDir.appendingPathComponent(name))
    }
}

private func listAllTargets(packagePath: URL) -> [String] {
    let proc = Process()
#if os(Linux)
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    proc.arguments = ["package", "--package-path", packagePath.path, "dump-package"]
#else
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    proc.arguments = ["swift", "package", "--package-path", packagePath.path, "dump-package"]
#endif
    let pipe = Pipe(); proc.standardOutput = pipe
    try? proc.run(); proc.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let targets = json["targets"] as? [[String: Any]] else { return [] }
    return targets.compactMap { $0["name"] as? String }
}

private func findBuildDir(packagePath: URL) -> URL? {
    let dotBuild = packagePath.appendingPathComponent(".build")
    guard FileManager.default.fileExists(atPath: dotBuild.path) else { return nil }

    let debugLink = dotBuild.appendingPathComponent("debug")
    if FileManager.default.fileExists(atPath: debugLink.path) {
        return debugLink.resolvingSymlinksInPath()
    }

    if let contents = try? FileManager.default.contentsOfDirectory(at: dotBuild, includingPropertiesForKeys: nil) {
        for dir in contents where dir.hasDirectoryPath {
            let debugDir = dir.appendingPathComponent("debug")
            if FileManager.default.fileExists(atPath: debugDir.path) {
                return debugDir
            }
        }
    }
    return nil
}

// MARK: - alignment score

struct ScoreCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "score",
        abstract: "Compute alignment score from .alignment files"
    )

    @Option(help: "Root directory to scan (defaults to current directory)")
    var root: String = "."

    @Option(help: "Output JSON to file instead of printing")
    var output: String?

    @Flag(help: "JSON output format")
    var json: Bool = false

    @Flag(help: "Output overall summary instead of per-target breakdown")
    var summary: Bool = false

    func run() throws {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        let collector = GradeCollector()
        let statsByTarget = try collector.collect(in: rootURL)

        if json || output != nil {
            let data: Data
            if summary {
                // Overall format: {"score": N, "total_loc": N, "grades": {...}}
                let allStats = statsByTarget.values.flatMap { $0 }
                let score = AlignmentScore.compute(from: allStats)
                var gradeDict: [String: Int] = [:]
                for grade in AlignmentGrade.allCases {
                    gradeDict[grade.rawValue] = score.grades[grade, default: 0]
                }
                let result: [String: Any] = [
                    "score": score.score,
                    "total_loc": score.totalLOC,
                    "grades": gradeDict,
                ]
                data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            } else {
                // Per-target format: {"Target": {"score": N, "total_loc": N, "grades": {...}}, ...}
                var result: [String: Any] = [:]
                for (target, stats) in statsByTarget {
                    let score = AlignmentScore.compute(from: stats)
                    var gradeDict: [String: Int] = [:]
                    for grade in AlignmentGrade.allCases {
                        gradeDict[grade.rawValue] = score.grades[grade, default: 0]
                    }
                    result[target] = [
                        "score": score.score,
                        "total_loc": score.totalLOC,
                        "grades": gradeDict,
                    ]
                }
                data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            }
            if let outputPath = output {
                try data.write(to: URL(fileURLWithPath: outputPath))
                print("Wrote score to \(outputPath)")
            } else {
                print(String(data: data, encoding: .utf8)!)
            }
        } else {
            for (target, stats) in statsByTarget.sorted(by: { $0.key < $1.key }) {
                let score = AlignmentScore.compute(from: stats)
                print("\(target): score=\(score.score)% total_loc=\(score.totalLOC) " +
                      AlignmentGrade.allCases.map { "\($0.rawValue)=\(score.grades[$0, default: 0])" }.joined(separator: " "))
            }
        }
    }
}

// MARK: - alignment dashboard

struct DashboardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dashboard",
        abstract: "Generate an HTML alignment dashboard from score JSON and interface files"
    )

    @Option(help: "Path to score JSON (from 'alignment score --json --output')")
    var scoreJson: String

    @Option(help: "Directory containing generated interface .swift files")
    var interfacesDir: String

    @Option(help: "Output directory for dashboard files")
    var outputDir: String

    @Option(help: "Title for the dashboard page (default: directory name)")
    var title: String?

    @Flag(help: "Skip opening the dashboard in browser")
    var noOpen: Bool = false

    func run() throws {
        let fm = FileManager.default
        let scoreURL = URL(fileURLWithPath: scoreJson).standardizedFileURL
        let interfacesURL = URL(fileURLWithPath: interfacesDir).standardizedFileURL
        let outURL = URL(fileURLWithPath: outputDir).standardizedFileURL

        // Read score JSON
        let scoreData = try Data(contentsOf: scoreURL)
        guard let scoreDict = try JSONSerialization.jsonObject(with: scoreData) as? [String: Any] else {
            throw ValidationError("Invalid score JSON at \(scoreURL.path)")
        }

        // Create output directories (don't nuke — caller may have placed
        // score.json and interfaces/ here already)
        try fm.createDirectory(at: outURL, withIntermediateDirectories: true)
        let svgsDir = outURL.appendingPathComponent("svgs")
        try fm.createDirectory(at: svgsDir, withIntermediateDirectories: true)

        // Load interface texts (recursively, to handle subdirectory layout)
        var interfaceResults: [String: String] = [:]
        if fm.fileExists(atPath: interfacesURL.path) {
            if let enumerator = fm.enumerator(at: interfacesURL, includingPropertiesForKeys: nil) {
                for case let file as URL in enumerator {
                    guard file.pathExtension == "swift" else { continue }
                    var rel = file.path.replacingOccurrences(of: interfacesURL.path + "/", with: "")
                    rel = rel.replacingOccurrences(of: ".swift", with: "")
                    // Normalize: "WuhuAppKit/App" matches the label "WuhuAppKit/App"
                    if let content = try? String(contentsOf: file, encoding: String.Encoding.utf8) {
                        interfaceResults[rel] = content
                    }
                }
            }
        }

        // Generate SVGs and collect aggregations
        let svgGen = SVGBarGenerator()
        var aggregations: [(label: String, score: AlignmentScore)] = []

        for (target, value) in scoreDict.sorted(by: { $0.key < $1.key }) {
            guard let info = value as? [String: Any],
                  let score = info["score"] as? Int,
                  let totalLoc = info["total_loc"] as? Int,
                  let grades = info["grades"] as? [String: Int] else { continue }

            var gradeCounts: [AlignmentGrade: Int] = [:]
            for grade in AlignmentGrade.allCases {
                gradeCounts[grade] = grades[grade.rawValue] ?? 0
            }
            let alignmentScore = AlignmentScore(score: score, totalLOC: totalLoc, grades: gradeCounts)
            aggregations.append((target, alignmentScore))

            let svg = svgGen.generate(score: alignmentScore)
            let safe = target.replacingOccurrences(of: "/", with: "_")
            try svg.write(to: svgsDir.appendingPathComponent("\(safe).svg"), atomically: true, encoding: .utf8)
        }

        // Overall score
        let allScores = aggregations.map(\.score)
        let totalLOC = allScores.map(\.totalLOC).reduce(0, +)
        var overallGrades: [AlignmentGrade: Int] = [:]
        for grade in AlignmentGrade.allCases {
            overallGrades[grade] = allScores.map { $0.grades[grade, default: 0] }.reduce(0, +)
        }
        let overallScore = AlignmentScore(
            score: totalLOC > 0 ? (totalLOC - (overallGrades[.D] ?? 0)) * 100 / totalLOC : 0,
            totalLOC: totalLOC,
            grades: overallGrades
        )
        try svgGen.generate(score: overallScore)
            .write(to: outURL.appendingPathComponent("status.svg"), atomically: true, encoding: .utf8)

        // Generate HTML
        let pageTitle = title ?? outURL.lastPathComponent
        let html = generateDashboardHTML(
            title: pageTitle,
            overallScore: overallScore,
            aggregations: aggregations,
            interfaceResults: interfaceResults
        )
        try html.write(to: outURL.appendingPathComponent("index.html"), atomically: true, encoding: String.Encoding.utf8)

        print("Dashboard generated at \(outURL.path)")
        print("  overall: \(overallScore.score)% across \(overallScore.totalLOC) LOC")

        if !noOpen {
#if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [outURL.appendingPathComponent("index.html").path]
            try? process.run()
#endif
        }
    }
}


// MARK: - alignment complexity

struct ComplexityCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "complexity",
        abstract: "Measure Swift-oriented weighted complexity for non-test source targets"
    )

    @Option(help: "Root directory to scan (defaults to current directory)")
    var root: String = "."

    @Option(help: "Write JSON report to file instead of stdout")
    var output: String?

    func run() throws {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        let report = try ComplexityAnalyzer().analyze(root: rootURL)
        let data = try complexityJSONEncoder().encode(report)
        if let output {
            let outputURL = URL(fileURLWithPath: output).standardizedFileURL
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: outputURL)
            print("Wrote complexity report to \(outputURL.path)")
        } else {
            print(String(data: data, encoding: .utf8)!)
        }
    }
}

// MARK: - alignment complexity-summary

extension ComplexitySummaryGrouping: ExpressibleByArgument {}

struct ComplexitySummaryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "complexity-summary",
        abstract: "Print an ASCII summary from complexity JSON"
    )

    @Option(help: "Path to complexity JSON from 'alignment complexity --output'")
    var input: String

    @Option(help: "Summary grouping: target, file, or tree")
    var by: ComplexitySummaryGrouping = .target

    @Option(help: "Maximum number of top-level rows to show")
    var top: Int = 40

    func validate() throws {
        guard top > 0 else { throw ValidationError("--top must be greater than zero") }
    }

    func run() throws {
        let inputURL = URL(fileURLWithPath: input).standardizedFileURL
        let report = try readComplexityReport(inputURL)
        print(ComplexitySummaryRenderer().render(report: report, grouping: by, top: top), terminator: "")
    }
}

// MARK: - alignment complexity-dashboard

struct ComplexityDashboardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "complexity-dashboard",
        abstract: "Generate an HTML complexity dashboard from complexity JSON"
    )

    @Option(help: "Path to complexity JSON from 'alignment complexity --output'")
    var input: String

    @Option(help: "Output directory for dashboard files")
    var outputDir: String

    @Option(help: "Title for the dashboard page (default: report root directory name)")
    var title: String?

    @Flag(help: "Skip opening the dashboard in browser")
    var noOpen: Bool = false

    func run() throws {
        let inputURL = URL(fileURLWithPath: input).standardizedFileURL
        let outputURL = URL(fileURLWithPath: outputDir).standardizedFileURL
        let report = try readComplexityReport(inputURL)
        let pageTitle = title ?? URL(fileURLWithPath: report.root).lastPathComponent
        let html = try ComplexityDashboardHTMLGenerator().generate(report: report, title: pageTitle)

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let indexURL = outputURL.appendingPathComponent("index.html")
        try html.write(to: indexURL, atomically: true, encoding: .utf8)
        print("Complexity dashboard generated at \(indexURL.path)")
        print("  weighted=\(report.summary.weightedScore) raw=\(report.summary.rawScore) files=\(report.summary.files)")

        if !noOpen {
#if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [indexURL.path]
            try? process.run()
#endif
        }
    }
}

private func complexityJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
}

private func complexityJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}

private func readComplexityReport(_ url: URL) throws -> ComplexityReport {
    do {
        let data = try Data(contentsOf: url)
        return try complexityJSONDecoder().decode(ComplexityReport.self, from: data)
    } catch {
        throw ValidationError("Invalid complexity JSON at \(url.path): \(error)")
    }
}

// MARK: - Dashboard HTML generation

func generateDashboardHTML(
    title: String, overallScore: AlignmentScore,
    aggregations: [(label: String, score: AlignmentScore)],
    interfaceResults: [String: String]
) -> String {
    let te = title.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    var rows = ""
    for (label, score) in aggregations {
        let safe = label.replacingOccurrences(of: "/", with: "_")
        let link = interfaceResults[label] != nil
            ? "<a href=\"interfaces/\(escaped(label)).swift\">\(escaped(label))</a>"
            : escaped(label)
        rows += "<tr><td>\(link)</td><td>\(score.score)%</td><td>\(score.totalLOC)</td>" +
            "<td>\(AlignmentGrade.allCases.map { "\($0.rawValue):\(score.grades[$0, default: 0])" }.joined(separator: " "))</td>" +
            "<td><img src=\"svgs/\(safe).svg\" style=\"height:22px\" alt=\"bar\"></td></tr>\n"
    }
    return """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><title>\(te) · alignment</title>
    <style>body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;background:#0b0f17;color:#e5e7eb;margin:0;padding:32px;max-width:960px}h1{font-size:24px;margin:0 0 4px}.subtitle{color:#6b7280;font-size:13px;margin-bottom:24px}table{width:100%;border-collapse:collapse;font-size:13px;margin-top:24px}th,td{padding:8px 12px;text-align:left;border-bottom:1px solid #1f2937}th{color:#9ca3af;font-weight:500;font-size:11px;text-transform:uppercase;letter-spacing:.06em}a{color:#7dd3fc;text-decoration:none}a:hover{text-decoration:underline}.score{font-size:48px;font-weight:600}img{max-width:100%}</style></head><body>
    <h1>\(te)</h1><p class="subtitle">Alignment dashboard</p>
    <div class="score">\(overallScore.score)<span style="font-size:18px;color:#9ca3af;margin-left:4px">%</span></div>
    <img src="status.svg" alt="alignment bar" style="margin:12px 0">
    <table><thead><tr><th>Target</th><th>Score</th><th>LOC</th><th>Grades</th><th></th></tr></thead><tbody>\(rows)</tbody></table></body></html>
    """
}

private func escaped(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
}
