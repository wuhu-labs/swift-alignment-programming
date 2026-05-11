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
final class TypeNode {
    let name: String
    let path: String
    let accessLevel: String
    let kindID: String
    let declaration: String
    let availability: String?
    let conformances: [String]
    let rawType: String?

    var childTypes: [TypeNode] = []
    var cases: [String] = []
    var members: [String] = []

    init(
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
struct ExtensionGroup {
    let header: String
    let availability: String?
    var members: [String]
}

/// The complete public API outline for one Swift module.
struct ModuleOutline {
    let module: String
    var typealiases: [String] = []
    var globals: [String] = []
    var types: [TypeNode] = []
    var extensions: [ExtensionGroup] = []
}

// MARK: - Section Support

/// A parsed section from .alignment-sections configuration.
struct SectionConfig: Equatable {
    let name: String
    let auto: Bool
    let symbols: [String]
}

/// A rendered interface organized by sections.
struct SectionedInterface {
    let module: String
    /// Sections in display order. Each section has its config and rendered text lines.
    let sections: [(config: SectionConfig, items: [String])]
    /// Full flat interface (for diff compatibility).
    let fullInterface: String
    /// Index in markdown format.
    let indexMarkdown: String
}
