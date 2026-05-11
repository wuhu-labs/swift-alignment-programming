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
            SnapshotCommand.self,
        ]
    )
}

// MARK: - alignment interface

struct InterfaceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "interface",
        abstract: "Generate a readable pseudo-Swift public interface for a SwiftPM target"
    )

    @Option(help: "SwiftPM target name")
    var target: String

    @Option(help: "Path to the Swift package root (defaults to current directory)")
    var packagePath: String = "."

    @Option(help: "Use an existing symbol graph directory instead of building the target")
    var symbolGraphDir: String?

    @Option(help: "Write the rendered pseudo-Swift interface to this file instead of stdout")
    var output: String?

    @Option(help: "Path to .alignment-sections file for section-based output")
    var sections: String?

    func run() throws {
        let pkgURL = URL(fileURLWithPath: packagePath).standardizedFileURL

        let sgDir: URL
        if let dir = symbolGraphDir {
            sgDir = URL(fileURLWithPath: dir).standardizedFileURL
        } else {
            sgDir = try buildSymbolGraph(packagePath: pkgURL, target: target)
        }

        let outline = try buildOutline(from: sgDir, module: target)

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
            let outputURL = URL(fileURLWithPath: outputPath, relativeTo: pkgURL).standardizedFileURL
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try output.write(to: outputURL, atomically: true, encoding: .utf8)
            print("Wrote interface to \(outputURL.path)")
        } else {
            print(output)
        }
    }
}

// MARK: - Symbol Graph Building (subprocess)

private func buildSymbolGraph(packagePath: URL, target: String) throws -> URL {
    let artifactDir = packagePath
        .appendingPathComponent(".build")
        .appendingPathComponent("public-interface-artifacts")
        .appendingPathComponent("symbolgraphs")

    try? FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)

    // Only clean if the source has actually changed (simple check: no symbols at all)
    let existingSymbols = (try? FileManager.default.contentsOfDirectory(at: artifactDir, includingPropertiesForKeys: nil))
        .flatMap { $0.filter { $0.lastPathComponent.hasPrefix("\(target)") && $0.pathExtension == "json" } }
        ?? []
    if existingSymbols.isEmpty {
        // No existing symbols — need a full build
    }
    // Don't clean existing symbols; incremental build will update them if needed

    let tmpDir = FileManager.default.temporaryDirectory
    let stdoutFile = tmpDir.appendingPathComponent("alignment-build-out-\(UUID().uuidString).log")
    let stderrFile = tmpDir.appendingPathComponent("alignment-build-err-\(UUID().uuidString).log")
    defer {
        try? FileManager.default.removeItem(at: stdoutFile)
        try? FileManager.default.removeItem(at: stderrFile)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")

    // Detect build system: Xcode-style layout uses swiftbuild
    let buildSystem = detectBuildSystem(packagePath: packagePath)
    let args = [
        "swift", "build",
        "--build-system", buildSystem,
        "--package-path", packagePath.path,
        "--target", target,
        "-Xswiftc", "-emit-symbol-graph",
        "-Xswiftc", "-emit-symbol-graph-dir",
        "-Xswiftc", artifactDir.path,
        "-Xswiftc", "-symbol-graph-minimum-access-level",
        "-Xswiftc", "public",
    ]
    process.arguments = args

    // Create temp output files
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

    let generated = (try? FileManager.default.contentsOfDirectory(at: artifactDir, includingPropertiesForKeys: nil))
        .flatMap { $0.filter { $0.lastPathComponent.hasPrefix(target) && $0.pathExtension == "json" } }
        ?? []

    guard !generated.isEmpty else {
        throw ValidationError("No symbol graph JSON files generated for target \(target) in \(artifactDir.path)")
    }

    return artifactDir
}

/// Detect whether a package uses the Xcode-style (swiftbuild) or native SPM layout.
private func detectBuildSystem(packagePath: URL) -> String {
    let fm = FileManager.default

    // Check if the package's Package.swift uses custom target paths.
    // If it does AND we're in a monorepo with xcodegen, use swiftbuild.
    let pkgSwift = packagePath.appendingPathComponent("Package.swift")
    let usesCustomPaths = (try? String(contentsOf: pkgSwift, encoding: .utf8))?.contains("path:") ?? false
    guard usesCustomPaths else { return "native" }

    // Check up to 2 parent levels for a project.yml (xcodegen)
    var dir = packagePath
    for _ in 0...2 {
        if fm.fileExists(atPath: dir.appendingPathComponent("project.yml").path) {
            return "swiftbuild"
        }
        dir = dir.deletingLastPathComponent()
    }
    return "native"
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

    func run() throws {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        let collector = GradeCollector()

        let statsByTarget = try collector.collect(in: rootURL)

        if json || output != nil {
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
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
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

// MARK: - alignment snapshot

struct SnapshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "All-in-one: build interfaces, score, and open a local dashboard"
    )

    @Option(help: "Path to the package root (defaults to current directory)")
    var packagePath: String = "."

    @Option(help: "Output directory for generated files")
    var outputDir: String = ".alignment-snapshot"

    @Flag(help: "Skip opening the dashboard in browser")
    var noOpen: Bool = false

    @Flag(help: "JSON output format")
    var json: Bool = false

    func run() async throws {
        let rootURL = URL(fileURLWithPath: packagePath).standardizedFileURL
        let outURL = rootURL.appendingPathComponent(outputDir).standardizedFileURL
        let fm = FileManager.default

        try? fm.removeItem(at: outURL)
        try fm.createDirectory(at: outURL, withIntermediateDirectories: true)
        let interfacesDir = outURL.appendingPathComponent("interfaces")
        try fm.createDirectory(at: interfacesDir, withIntermediateDirectories: true)

        // Phase 1: Score
        print("→ Scoring alignment…")
        let collector = GradeCollector()
        let statsByTarget = try collector.collect(in: rootURL)

        // Phase 2: Generate interfaces
        var interfaceResults: [String: String] = [:]
        let packageDirs = try findPackageDirs(in: rootURL)
        for pkgDir in packageDirs {
            let packageName = pkgDir.lastPathComponent
            let pkgInterfacesDir = interfacesDir.appendingPathComponent(packageName)
            try fm.createDirectory(at: pkgInterfacesDir, withIntermediateDirectories: true)
            let targets = try discoverTargets(in: pkgDir)
            for target in targets {
                print("  building interfaces for \(packageName)/\(target)…")
                do {
                    let sgDir = try buildSymbolGraph(packagePath: pkgDir, target: target)
                    let rendered = try renderFromSymbolGraphDirectory(sgDir, module: target)
                    let outFile = pkgInterfacesDir.appendingPathComponent("\(target).swift")
                    try rendered.write(to: outFile, atomically: true, encoding: .utf8)
                    interfaceResults["\(packageName)/\(target)"] = rendered
                } catch {
                    print("  ⚠ skipped \(target): \(error)")
                }
            }
        }

        // Phase 3: Dashboard
        print("→ Generating dashboard…")
        let svgGen = SVGBarGenerator()
        let svgsDir = outURL.appendingPathComponent("svgs")
        try fm.createDirectory(at: svgsDir, withIntermediateDirectories: true)

        var aggregations: [(label: String, score: AlignmentScore)] = []
        for (target, stats) in statsByTarget.sorted(by: { $0.key < $1.key }) {
            let score = AlignmentScore.compute(from: stats)
            aggregations.append((target, score))
            let svg = svgGen.generate(score: score)
            let safe = target.replacingOccurrences(of: "/", with: "_")
            try svg.write(to: svgsDir.appendingPathComponent("\(safe).svg"), atomically: true, encoding: .utf8)
        }

        let allStats = statsByTarget.values.flatMap { $0 }
        let overallScore = AlignmentScore.compute(from: allStats)
        try svgGen.generate(score: overallScore)
            .write(to: outURL.appendingPathComponent("status.svg"), atomically: true, encoding: .utf8)

        var gradeDict: [String: Int] = [:]
        for g in AlignmentGrade.allCases { gradeDict[g.rawValue] = overallScore.grades[g, default: 0] }
        let scoreJSON: [String: Any] = ["score": overallScore.score, "total_loc": overallScore.totalLOC, "grades": gradeDict]
        try JSONSerialization.data(withJSONObject: scoreJSON, options: .prettyPrinted)
            .write(to: outURL.appendingPathComponent("score.json"))

        let html = generateDashboardHTML(
            title: rootURL.lastPathComponent,
            overallScore: overallScore,
            aggregations: aggregations,
            interfaceResults: interfaceResults
        )
        try html.write(to: outURL.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        // Output
        if json {
            var result: [String: Any] = ["root": rootURL.path, "overall_score": overallScore.score, "overall_total_loc": overallScore.totalLOC, "overall_grades": gradeDict, "targets": [:]]
            var targetsDict: [String: Any] = [:]
            for (label, score) in aggregations {
                var gd: [String: Int] = [:]
                for g in AlignmentGrade.allCases { gd[g.rawValue] = score.grades[g, default: 0] }
                targetsDict[label] = ["score": score.score, "total_loc": score.totalLOC, "grades": gd, "interface": interfaceResults[label] ?? ""]
            }
            result["targets"] = targetsDict
            print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
        } else {
            print("\nDone! Alignment snapshot at \(outURL.path)")
            print("  overall: \(overallScore.score)% across \(overallScore.totalLOC) LOC")
            if !noOpen {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = [outURL.appendingPathComponent("index.html").path]
                try? process.run()
            }
        }
    }
}

// Helpers

private func findPackageDirs(in root: URL) throws -> [URL] {
    let fm = FileManager.default
    if fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path) { return [root] }
    let pkgs = root.appendingPathComponent("Packages")
    guard fm.fileExists(atPath: pkgs.path) else { return [] }
    return try fm.contentsOfDirectory(at: pkgs, includingPropertiesForKeys: [.isDirectoryKey])
        .filter { fm.fileExists(atPath: $0.appendingPathComponent("Package.swift").path) }
}

private func discoverTargets(in packageDir: URL) throws -> [String] {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    proc.arguments = ["swift", "package", "--package-path", packageDir.path, "dump-package"]
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

private func generateDashboardHTML(
    title: String, overallScore: AlignmentScore,
    aggregations: [(label: String, score: AlignmentScore)],
    interfaceResults: [String: String]
) -> String {
    let te = title.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    var rows = ""
    for (label, score) in aggregations {
        let safe = label.replacingOccurrences(of: "/", with: "_")
        let link = interfaceResults[label] != nil
            ? "<a href=\"interfaces/\(escaped(safe)).swift\">\(escaped(label))</a>"
            : escaped(label)
        rows += "<tr><td>\(link)</td><td>\(score.score)%</td><td>\(score.totalLOC)</td>" +
            "<td>\(AlignmentGrade.allCases.map { "\($0.rawValue):\(score.grades[$0, default: 0])" }.joined(separator: " "))</td>" +
            "<td><img src=\"svgs/\(safe).svg\" style=\"height:22px\" alt=\"bar\"></td></tr>\n"
    }
    return """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><title>\(te) · alignment</title>
    <style>body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;background:#0b0f17;color:#e5e7eb;margin:0;padding:32px;max-width:960px}h1{font-size:24px;margin:0 0 4px}.subtitle{color:#6b7280;font-size:13px;margin-bottom:24px}table{width:100%;border-collapse:collapse;font-size:13px;margin-top:24px}th,td{padding:8px 12px;text-align:left;border-bottom:1px solid #1f2937}th{color:#9ca3af;font-weight:500;font-size:11px;text-transform:uppercase;letter-spacing:.06em}a{color:#7dd3fc;text-decoration:none}a:hover{text-decoration:underline}.score{font-size:48px;font-weight:600}img{max-width:100%}</style></head><body>
    <h1>\(te)</h1><p class="subtitle">Alignment snapshot</p>
    <div class="score">\(overallScore.score)<span style="font-size:18px;color:#9ca3af;margin-left:4px">%</span></div>
    <img src="status.svg" alt="alignment bar" style="margin:12px 0">
    <table><thead><tr><th>Target</th><th>Score</th><th>LOC</th><th>Grades</th><th></th></tr></thead><tbody>\(rows)</tbody></table></body></html>
    """
}

private func escaped(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
}
