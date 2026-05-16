import Foundation
import Testing
@testable import SwiftAlignmentProgramming

@Test func complexityAnalyzerScoresSwiftOrientedEntities() throws {
    let root = try TemporaryDirectory()
    try root.write(
        "Targets/App/Sources/App.swift",
        """
        public actor Session {
            public let id: String
            var count: Int

            public init(id: String) {
                self.id = id
            }

            public func run() async throws {
                if count > 0 && id.isEmpty {
                    for item in [1] {
                        print(item)
                    }
                }
            }
        }

        final class Box {
            private var value = 0

            func plain() {
                guard value > 0 else { return }
            }
        }
        """
    )
    try root.write(
        "Targets/App/Tests/AppTests.swift",
        """
        public class IgnoredTestComplexity {
            public func noisy() {
                if true { if true { if true {} } }
            }
        }
        """
    )

    let report = try ComplexityAnalyzer().analyze(root: root.url)

    #expect(report.summary.targets == 1)
    #expect(report.summary.files == 1)
    #expect(report.targets.map(\.name) == ["App"])
    #expect(report.files.map(\.path) == ["Targets/App/Sources/App.swift"])
    #expect(report.files[0].path.contains("Tests") == false)
    #expect(report.summary.weightedScore > report.summary.rawScore)

    let declarations = report.files[0].declarations
    #expect(declarations.contains { $0.kind == "actor" && $0.name == "Session" && $0.access == "public" })
    #expect(declarations.contains { $0.kind == "final class" && $0.name == "Box" })
    #expect(declarations.contains { $0.kind == "function" && $0.name == "run" && $0.multipliers["effects"] == 1.5 })
    #expect(declarations.contains { $0.kind == "var" && $0.name == "value" && $0.multipliers["storage"] == 1.5 })
    #expect(report.files[0].lineComplexity.contains { line in
        line.events.contains { $0.kind == "logical_operator" && $0.label == "&&" }
    })
}

@Test func complexitySourceCollectorUsesAlignedLayoutSourcesOnly() throws {
    let root = try TemporaryDirectory()
    try root.write("Targets/Feature/Sources/Feature.swift", "struct Feature {}\n")
    try root.write("Targets/Feature/Tests/FeatureTests.swift", "struct FeatureTests {}\n")
    try root.write("Targets/Tool/Sources/main.swift", "print(\"hello\")\n")

    let targets = try ComplexitySourceCollector().collect(in: root.url)

    #expect(targets.map(\.name) == ["Feature", "Tool"])
    #expect(targets.flatMap(\.files).sorted() == [
        "Targets/Feature/Sources/Feature.swift",
        "Targets/Tool/Sources/main.swift",
    ])
}

@Test func complexityVisualizationRendersTreeAndDashboard() throws {
    let report = ComplexityReport(
        root: "/tmp/Demo",
        configuration: ComplexityMetricConfiguration(),
        summary: ComplexitySummary(rawScore: 3, weightedScore: 12, targets: 1, files: 1, lines: 10),
        targets: [
            ComplexityTargetReport(name: "Demo", sourceRoot: "Targets/Demo/Sources", rawScore: 3, weightedScore: 12, files: 1, lines: 10),
        ],
        files: [
            ComplexityFileReport(
                path: "Targets/Demo/Sources/Subdir/File.swift",
                target: "Demo",
                rawScore: 3,
                weightedScore: 12,
                lines: 10,
                declarations: [],
                lineComplexity: []
            ),
        ]
    )

    let summary = ComplexitySummaryRenderer().render(report: report, grouping: .tree)
    #expect(summary.contains("Demo"))
    #expect(summary.contains("Subdir"))
    #expect(summary.contains("File.swift"))

    let html = try ComplexityDashboardHTMLGenerator().generate(report: report, title: "Demo")
    #expect(html.contains("Treemap"))
    #expect(html.contains("Targets"))
    #expect(html.contains("Files"))
}

private struct TemporaryDirectory {
    var url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-alignment-programming-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ relativePath: String, _ content: String) throws {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
