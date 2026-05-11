import Foundation

// MARK: - Section Configuration

/// Parsed .alignment-sections configuration.
/// Lives next to .alignment in a target's source directory.
///
/// Format (simple INI-like):
/// ```
/// [Section Name]
/// symbols = Foo, Bar, Baz
///
/// [Another Section]
/// auto = true
/// ```
public struct SectionConfig: Sendable, Equatable {
    public let name: String
    public let auto: Bool
    public let symbols: [String]

    public init(name: String, auto: Bool, symbols: [String]) {
        self.name = name
        self.auto = auto
        self.symbols = symbols
    }

    /// Parse a .alignment-sections file.
    /// Returns sections in file order, or nil if the file doesn't exist.
    public static func parse(_ content: String) throws -> [SectionConfig] {
        var sections: [SectionConfig] = []
        var currentName: String? = nil
        var currentAuto = false
        var currentSymbols: [String] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Section header
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                // Save previous section
                if let name = currentName {
                    sections.append(SectionConfig(name: name, auto: currentAuto, symbols: currentSymbols))
                }
                currentName = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                currentAuto = false
                currentSymbols = []
                continue
            }

            guard currentName != nil else {
                throw SectionParseError.unexpectedContent(String(line))
            }

            // Parse key = value
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else {
                throw SectionParseError.invalidLine(String(line))
            }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "symbols":
                currentSymbols = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            case "auto":
                currentAuto = value.lowercased() == "true"
            default:
                throw SectionParseError.unknownKey(key)
            }
        }

        // Save final section
        if let name = currentName {
            sections.append(SectionConfig(name: name, auto: currentAuto, symbols: currentSymbols))
        }

        // Validate: at most one auto section
        let autoCount = sections.filter { $0.auto }.count
        if autoCount > 1 {
            throw SectionParseError.multipleAutoSections
        }

        return sections
    }
}

public enum SectionParseError: Error, CustomStringConvertible {
    case unexpectedContent(String)
    case invalidLine(String)
    case unknownKey(String)
    case multipleAutoSections

    public var description: String {
        switch self {
        case .unexpectedContent(let line):
            "Content outside of any section: \(line)"
        case .invalidLine(let line):
            "Invalid line (expected 'key = value'): \(line)"
        case .unknownKey(let key):
            "Unknown key '\(key)' (expected 'symbols' or 'auto')"
        case .multipleAutoSections:
            "Multiple sections have auto = true (at most one allowed)"
        }
    }
}

// MARK: - Section-aware rendering

/// A rendered interface organized by sections.
public struct SectionedInterface: Sendable {
    public let module: String
    public let sections: [(config: SectionConfig, items: [String])]
    public let sectionedText: String
    public let fullInterface: String
    public let indexMarkdown: String

    public init(module: String, sections: [(config: SectionConfig, items: [String])], sectionedText: String, fullInterface: String, indexMarkdown: String) {
        self.module = module
        self.sections = sections
        self.sectionedText = sectionedText
        self.fullInterface = fullInterface
        self.indexMarkdown = indexMarkdown
    }
}

/// Assign top-level symbols from a ModuleOutline into sections.
public func assignSections(
    outline: ModuleOutline,
    sections: [SectionConfig]
) -> SectionedInterface {
    // Build lookup: symbol name → section index
    var symbolToSection: [String: Int] = [:]
    var autoIndex: Int? = nil
    for (idx, section) in sections.enumerated() {
        if section.auto { autoIndex = idx }
        for sym in section.symbols {
            symbolToSection[sym] = idx
        }
    }
    if autoIndex == nil {
        // If no auto section, add an implicit "General" at the end
        autoIndex = sections.count
    }

    // Build sectioned output
    var sectionItems: [(config: SectionConfig, items: [String])] = sections.map { ($0, []) }

    // Helper to assign a declaration to a section
    func assign(_ name: String, _ lines: [String]) {
        let idx = symbolToSection[name] ?? autoIndex!
        while sectionItems.count <= idx {
            // auto section or implicit
            sectionItems.append((SectionConfig(name: "General", auto: true, symbols: []), []))
        }
        sectionItems[idx].items.append(contentsOf: lines)
    }

    // Typealiases
    for decl in outline.typealiases {
        let name = decl.replacingOccurrences(of: "public typealias ", with: "")
            .replacingOccurrences(of: "open typealias ", with: "")
        assign(name, [decl])
    }

    // Globals
    for decl in outline.globals {
        let name = extractName(from: decl)
        assign(name, [decl])
    }

    // Types (with their nested content)
    for type in outline.types.sorted(by: { typeSortKey($0) < typeSortKey($1) }) {
        let typeLines = renderType(type)
        assign(type.name, typeLines)
    }

    // Extensions — follow their base type
    for group in outline.extensions {
        let baseType = extractExtensionBase(from: group.header)
        var lines: [String] = []
        if let av = group.availability { lines.append(av) }
        lines.append(group.header)
        lines.append(contentsOf: group.members.map { "  " + $0 })
        lines.append("}")
        assign(baseType, lines)
    }

    // Generate full flat interface (unchanged, for diff compatibility)
    let fullInterface = renderOutline(outline)

    // Generate index markdown
    var mdLines = ["# \(outline.module)", ""]
    mdLines.append("| Section | Types |")
    mdLines.append("|---|---|")
    for (config, _) in sectionItems {
        let typeNames = config.symbols.sorted().joined(separator: ", ")
        mdLines.append("| \(config.name) | \(typeNames) |")
    }
    let indexMarkdown = mdLines.joined(separator: "\n") + "\n"

    // Generate sectioned interface text
    var sectionedLines: [String] = []
    for (idx, (config, items)) in sectionItems.enumerated() {
        guard !items.isEmpty else { continue }
        if idx > 0 { sectionedLines.append("") }
        sectionedLines.append("// ── \(config.name) ──")
        sectionedLines.append(contentsOf: items)
    }

    return SectionedInterface(
        module: outline.module,
        sections: sectionItems,
        sectionedText: sectionedLines.joined(separator: "\n") + "\n",
        fullInterface: fullInterface,
        indexMarkdown: indexMarkdown
    )
}

// MARK: - Helpers

private func extractName(from declaration: String) -> String {
    let stripped = declaration
        .replacingOccurrences(of: "public ", with: "")
        .replacingOccurrences(of: "open ", with: "")
        .replacingOccurrences(of: "@MainActor ", with: "")

    // Extract the first identifier-like token after keywords
    // For "func foo(...)" → "foo"
    // For "var x: ..." → "x"
    // For "let x = ..." → "x"
    if let funcRange = stripped.range(of: "func ") {
        let after = stripped[funcRange.upperBound...]
        if let paren = after.firstIndex(of: "(") {
            return String(after[..<paren]).trimmingCharacters(in: .whitespaces)
        }
    }
    if let varRange = stripped.range(of: "var ") {
        let after = stripped[varRange.upperBound...]
        if let colon = after.firstIndex(of: ":") {
            return String(after[..<colon]).trimmingCharacters(in: .whitespaces)
        }
    }
    if let letRange = stripped.range(of: "let ") {
        let after = stripped[letRange.upperBound...]
        if let colon = after.firstIndex(of: ":") {
            return String(after[..<colon]).trimmingCharacters(in: .whitespaces)
        }
        if let eq = after.firstIndex(of: "=") {
            return String(after[..<eq]).trimmingCharacters(in: .whitespaces)
        }
    }
    if let typealiasRange = stripped.range(of: "typealias ") {
        let after = stripped[typealiasRange.upperBound...]
        if let eq = after.firstIndex(of: "=") {
            return String(after[..<eq]).trimmingCharacters(in: .whitespaces)
        }
    }
    return stripped
}

private func extractExtensionBase(from header: String) -> String {
    // "extension Foo {" or "extension Foo where ... {" → "Foo"
    let stripped = header
        .replacingOccurrences(of: "extension ", with: "")
        .replacingOccurrences(of: " {", with: "")
    if let whereIdx = stripped.range(of: " where ") {
        return String(stripped[..<whereIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
    }
    return stripped.trimmingCharacters(in: .whitespaces)
}