import Foundation
import Testing
@testable import SwiftAlignmentProgramming

@Test func syntacticContractsExtractAndRenderVisibleSurface() throws {
    let source = """
    @propertyWrapper
    public struct Wrapped<Value> {
      public var wrappedValue: Value
    }

    public protocol Service {
      associatedtype Output
      var state: String { get }
      func fetch(id: String) async throws -> Output
    }

    @Observable
    public struct Client: Service {
      @Wrapped public var token: String
      public let id: UUID
      package struct Configuration {
        public let name: String
      }
      public enum Mode {
        case enabled
        case disabled(Int)
      }
    }

    extension Client {
      public func reset() {}
    }

    public extension Client {
      struct Input {
        public let value: String
      }
      func ping(value: Int) {}
    }

    public extension String {
      func externalThing() {}
    }

    #if os(macOS)
    public struct MacOnly {}
    #else
    package struct LinuxOnly {}
    #endif

    #Preview {
      Client(id: UUID())
    }
    """

    let module = try ContractExtractor().extractModule(module: "Demo", files: [("Demo.swift", source)])
    let keys = Set(module.symbols.map(\.key))

    #expect(keys.contains("type Client"))
    #expect(keys.contains("type Client.Configuration"))
    #expect(keys.contains("type Client.Input"))
    #expect(keys.contains("case Client.Mode.enabled"))
    #expect(keys.contains("case Client.Mode.disabled"))
    #expect(keys.contains("func Client.reset()"))
    #expect(keys.contains("func Client.ping(value:)"))
    #expect(keys.contains("func String.externalThing()"))
    #expect(keys.contains("type MacOnly"))
    #expect(keys.contains("type LinuxOnly"))
    #expect(!module.symbols.contains { $0.declaration.contains("#Preview") })

    let rendered = ContractRenderer().render(module)
    #expect(rendered.contains("@Observable public struct Client: Service {"))
    #expect(rendered.contains("@Wrapped public var token: String"))
    #expect(rendered.contains("package struct Configuration {"))
    #expect(rendered.contains("public func reset()"))
    #expect(rendered.contains("public extension String {"))
    #expect(rendered.contains("func externalThing()"))
}

@Test func syntacticContractsRejectVisibleStoredPropertiesWithInferredTypes() throws {
    let source = """
    public struct Client {
      public let id = UUID()
    }
    """

    #expect(throws: ContractError.self) {
        _ = try ContractExtractor().extractModule(module: "Demo", files: [("Demo.swift", source)])
    }
}

@Test func contractDiffReportsAddedRemovedAndChangedSymbols() {
    let old = ContractModule(module: "Demo", symbols: [
        ContractSymbol(key: "type Client", kind: "struct", access: "public", path: ["Client"], declaration: "public struct Client"),
        ContractSymbol(key: "func Client.reset()", kind: "func", access: "public", path: ["Client", "reset"], declaration: "public func reset()", parentKey: "type Client"),
    ])
    let new = ContractModule(module: "Demo", symbols: [
        ContractSymbol(key: "type Client", kind: "struct", access: "public", path: ["Client"], declaration: "public struct Client: Sendable"),
        ContractSymbol(key: "func Client.start()", kind: "func", access: "public", path: ["Client", "start"], declaration: "public func start()", parentKey: "type Client"),
    ])

    let diff = diffContracts(old: old, new: new)

    #expect(diff.added.map(\.key) == ["func Client.start()"])
    #expect(diff.removed.map(\.key) == ["func Client.reset()"])
    #expect(diff.changed.map(\.before.key) == ["type Client"])
}

@Test func contractSourceCollectorUsesAlignedLayoutAndGlobs() throws {
    let root = try ContractTemporaryDirectory()
    try root.write("Targets/App/Sources/App.swift", "public struct App {}\n")
    try root.write("Targets/App/Sources/App.generated.swift", "public struct Generated {}\n")
    try root.write("Targets/App/Tests/AppTests.swift", "public struct Ignored {}\n")

    let collector = ContractSourceCollector(configuration: ContractConfiguration(excludeGlobs: ["*.generated.swift"], respectGitIgnore: false))
    let targets = try collector.collect(in: root.url)

    #expect(targets.map(\.name) == ["App"])
    #expect(targets[0].files == ["Targets/App/Sources/App.swift"])
}

private struct ContractTemporaryDirectory {
    var url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-alignment-programming-contract-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ relativePath: String, _ content: String) throws {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
