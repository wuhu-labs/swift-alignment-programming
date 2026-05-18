import Foundation
import Testing
@testable import SwiftAlignmentProgramming

private let fixturesURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("fixtures")

@Test func rendererMatchesBirdShapeFixture() throws {
    let rendered = try renderFromSymbolGraphDirectory(
        fixturesURL.appendingPathComponent("bird-shape-symbolgraphs"),
        module: "BirdShapeKit"
    )
    let expected = try String(
        contentsOf: fixturesURL.appendingPathComponent("BirdShapeKit.public.swift"),
        encoding: .utf8
    )
    #expect(rendered == expected)
}

@Test func rendererNestsTypesDeclaredInPublicExtensions() throws {
    let rendered = try renderFromSymbolGraphDirectory(
        fixturesURL.appendingPathComponent("extension-nesting-symbolgraphs"),
        module: "ExtensionNesting"
    )
    let expected = try String(
        contentsOf: fixturesURL.appendingPathComponent("ExtensionNesting.public.swift"),
        encoding: .utf8
    )
    #expect(rendered == expected)
    #expect(!rendered.contains("public struct Input\n"))
    #expect(!rendered.contains("public func execute(input: Input) -> Result\n\npublic struct Outer"))
}
