// MARK: - Intermediate Representation

/// A single symbol extracted from the symbol graph and normalized.
struct ResolvedSymbol {
    let preciseID: String
    let kindID: String
    let accessLevel: String
    let pathComponents: [String]
    let declaration: String
    let availability: String?
    let hasLocation: Bool
    let swiftExtension: SymbolGraph.Symbol.SwiftExtension?

    var fullPath: String { pathComponents.joined(separator: ".") }
    var shortName: String { pathComponents.last ?? fullPath }
    var parentPath: String? {
        pathComponents.count <= 1 ? nil : pathComponents.dropLast().joined(separator: ".")
    }

    var isExplicitlySynthesized: Bool {
        preciseID.contains("::SYNTHESIZED::")
    }
}

/// A container type (struct, enum, protocol, class) in the module outline.
public final class TypeNode {
    public let name: String
    public let path: String
    public let accessLevel: String
    public let kindID: String
    public let declaration: String
    public let availability: String?
    public let conformances: [String]
    public let rawType: String?

    public var childTypes: [TypeNode] = []
    public var cases: [String] = []
    public var members: [String] = []

    public init(
        name: String,
        path: String,
        accessLevel: String,
        kindID: String,
        declaration: String,
        availability: String?,
        conformances: [String],
        rawType: String?
    ) {
        self.name = name
        self.path = path
        self.accessLevel = accessLevel
        self.kindID = kindID
        self.declaration = declaration
        self.availability = availability
        self.conformances = conformances
        self.rawType = rawType
    }
}

/// A group of extension members with the same header and availability.
public struct ExtensionGroup {
    public let header: String
    public let availability: String?
    public var members: [String]

    public init(header: String, availability: String?, members: [String]) {
        self.header = header
        self.availability = availability
        self.members = members
    }
}

/// The complete public API outline for one Swift module.
public struct ModuleOutline {
    public let module: String
    public var typealiases: [String] = []
    public var globals: [String] = []
    public var types: [TypeNode] = []
    public var extensions: [ExtensionGroup] = []

    public init(module: String) {
        self.module = module
    }
}

