import Foundation

// MARK: - Constants

private let modulePrefixes = [
    "Swift.",
    "Foundation.",
    "SwiftUICore.",
    "SwiftUI.",
    "_Concurrency.",
]

private let synthesizedPatterns: [@Sendable (String) -> Bool] = [
    { $0.hasPrefix("func encode(to ") },
    { $0.hasPrefix("func hash(into ") },
    { $0.hasPrefix("static func == ") },
    { $0.hasPrefix("static func != ") },
    { $0.hasPrefix("init(from decoder: ") },
    { $0.hasPrefix("init?(rawValue: ") },
    { $0.hasPrefix("typealias AllCases = ") },
    { $0.hasPrefix("typealias RawValue = ") },
    { $0.hasPrefix("static var allCases: ") },
    { $0.hasPrefix("var hashValue: ") },
    { $0.hasPrefix("var rawValue: ") },
]

private let containerKindIDs: Set<String> = [
    "swift.struct", "swift.enum", "swift.protocol", "swift.class",
]

private let availabilityDomainOrder: [String: Int] = [
    "macOS": 0, "iOS": 1, "tvOS": 2, "watchOS": 3, "visionOS": 4, "Mac Catalyst": 5,
]

// MARK: - Normalization

func collapseWhitespace(_ text: String) -> String {
    text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
}

func normalizeText(_ text: String, module: String) -> String {
    var result = text
    result = result.replacing("\(module).", with: "")
    for prefix in modulePrefixes {
        result = result.replacing(prefix, with: "")
    }
    result = result.replacing("@_Concurrency.MainActor", with: "@MainActor")
    result = result.replacing("@preconcurrency ", with: "")
    result = collapseWhitespace(result)
    result = result.replacing(/\s+:\s+/, with: ": ")
    result = result.replacing(/\s+,\s+/, with: ", ")
    result = result.replacing("( ", with: "(")
    result = result.replacing(" )", with: ")")
    return result
}

func fragmentsText(_ fragments: [SymbolGraph.DeclarationFragment]?,
                   namesTitle: String?,
                   module: String) -> String {
    if let fragments, !fragments.isEmpty {
        let spelling = fragments.compactMap(\.spelling).joined()
        return normalizeText(spelling, module: module)
    }
    return normalizeText(namesTitle ?? "", module: module)
}

// MARK: - Availability

func formatAvailability(_ entries: [SymbolGraph.Symbol.AvailabilityEntry]?) -> String? {
    guard let entries, !entries.isEmpty else { return nil }
    let sorted = entries.sorted { a, b in
        let orderA = availabilityDomainOrder[a.domain ?? ""] ?? 999
        let orderB = availabilityDomainOrder[b.domain ?? ""] ?? 999
        return orderA < orderB
    }
    let parts: [String] = sorted.compactMap { entry -> String? in
        guard let domain = entry.domain,
              let introduced = entry.introduced else { return nil }
        let minor = introduced.minor ?? 0
        let patch = introduced.patch
        var version = "\(introduced.major).\(minor)"
        if let patch, patch != 0 { version += ".\(patch)" }
        return "\(domain) \(version)"
    }
    guard !parts.isEmpty else { return nil }
    return "@available(" + parts.joined(separator: ", ") + ", *)"
}

// MARK: - Access keyword insertion

func insertAccessKeyword(_ declaration: String, accessLevel: String) -> String {
    if declaration.hasPrefix("public ") || declaration.hasPrefix("open ")
        || declaration.hasPrefix("case ") || declaration.hasPrefix("extension ") {
        return declaration
    }
    guard accessLevel == "public" || accessLevel == "open" else { return declaration }
    if declaration.hasPrefix("@") {
        guard let spaceIdx = declaration.firstIndex(of: " ") else { return declaration }
        let afterAt = declaration.index(after: spaceIdx)
        return String(declaration[..<afterAt]) + accessLevel + " " + String(declaration[afterAt...])
    }
    return "\(accessLevel) \(declaration)"
}

// MARK: - Sort keys

func memberSortKey(_ declaration: String) -> (Int, String) {
    let stripped = declaration
        .replacingOccurrences(of: "public ", with: "")
        .replacingOccurrences(of: "open ", with: "")
    if stripped.hasPrefix("static let ") || stripped.hasPrefix("class let ") {
        return (2, declaration.lowercased())
    }
    if stripped.hasPrefix("let ") || stripped.hasPrefix("var ")
        || stripped.hasPrefix("static var ") || stripped.hasPrefix("class var ") {
        return (1, declaration.lowercased())
    }
    if stripped.hasPrefix("init") {
        return (3, declaration.lowercased())
    }
    if stripped.hasPrefix("func ") || stripped.hasPrefix("@MainActor ")
        || stripped.hasPrefix("@MainActor public func") {
        return (4, declaration.lowercased())
    }
    if stripped.hasPrefix("subscript") {
        return (5, declaration.lowercased())
    }
    return (6, declaration.lowercased())
}

public func typeSortKey(_ node: TypeNode) -> (String, String) {
    let kindRank: [String: Int] = [
        "swift.protocol": 0, "swift.struct": 1, "swift.enum": 2, "swift.class": 3,
    ]
    return (node.name.lowercased(), String(kindRank[node.kindID, default: 9]))
}

func topLevelSortKey(_ declaration: String) -> (String, String) {
    let prefixes = [
        "public typealias ", "public let ", "public var ", "@MainActor public var ",
        "public func ", "@MainActor public func ",
    ]
    var name = declaration
    for prefix in prefixes {
        if declaration.hasPrefix(prefix) {
            name = String(declaration.dropFirst(prefix.count))
            break
        }
    }
    return (name.lowercased(), declaration.lowercased())
}

// MARK: - Synthesized detection

func isProbablySynthesized(_ symbol: ResolvedSymbol) -> Bool {
    if symbol.isExplicitlySynthesized { return true }
    var core = symbol.declaration
    for prefix in ["public ", "open ", "@MainActor "] {
        if core.hasPrefix(prefix) { core = String(core.dropFirst(prefix.count)) }
    }
    return synthesizedPatterns.contains { $0(core) }
}

// MARK: - Raw type extraction

func parseRawType(_ declaration: String) -> String? {
    let pattern = /init\?\(rawValue:\s+([^)]+)\)/
    guard let match = declaration.firstMatch(of: pattern) else { return nil }
    return String(match.output.1).trimmingCharacters(in: .whitespaces)
}

// MARK: - Conformance normalization

func normalizeConformanceName(_ target: String,
                              preciseToPath: [String: String],
                              module: String) -> String {
    if let path = preciseToPath[target] {
        return normalizeText(path, module: module)
    }
    return normalizeText(target, module: module)
}

func finalizeConformances(kindID: String,
                          conformances: [String],
                          rawType: String?) -> [String] {
    let allNames = Set(conformances)
    let filtered = conformances.filter {
        !["SendableMetatype", "Decodable", "Encodable", "Equatable", "Hashable", "RawRepresentable"].contains($0)
    }

    var ordered: [String] = []
    var seen: Set<String> = []

    func add(_ item: String) {
        guard !item.isEmpty, !seen.contains(item) else { return }
        ordered.append(item)
        seen.insert(item)
    }

    if let rawType { add(rawType) }

    let builtinNames: Set<String> = ["Sendable", "Hashable", "Codable", "Decodable", "Encodable", "CaseIterable"]
    let customProtocols = filtered.filter { !builtinNames.contains($0) }
    for item in customProtocols.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
        add(item)
    }

    if allNames.contains("Sendable") { add("Sendable") }
    let keepHashable = kindID != "swift.enum" || rawType == nil
    if keepHashable && allNames.contains("Hashable") { add("Hashable") }

    if allNames.contains("Decodable") && allNames.contains("Encodable") {
        add("Codable")
    } else if allNames.contains("Decodable") {
        add("Decodable")
    } else if allNames.contains("Encodable") {
        add("Encodable")
    }

    if allNames.contains("CaseIterable") { add("CaseIterable") }
    return ordered
}

func appendConformances(_ baseDeclaration: String, _ conformances: [String]) -> String {
    guard !conformances.isEmpty else { return baseDeclaration }
    if baseDeclaration.contains(":") {
        return baseDeclaration + ", " + conformances.joined(separator: ", ")
    }
    return baseDeclaration + ": " + conformances.joined(separator: ", ")
}

// MARK: - Extension header

func renderExtensionHeader(_ symbol: ResolvedSymbol, module: String) -> String {
    let base = "extension \(normalizeText(symbol.pathComponents[0], module: module))"
    let constraints = symbol.swiftExtension?.constraints ?? []
    var rendered: [String] = []
    for c in constraints {
        guard let kind = c.kind, let lhs = c.lhs, let rhs = c.rhs else { continue }
        let l = normalizeText(lhs, module: module)
        let r = normalizeText(rhs, module: module)
        if kind == "sameType" {
            rendered.append("\(l) == \(r)")
        } else if kind == "conformance" {
            rendered.append("\(l): \(r)")
        }
    }
    if !rendered.isEmpty {
        return base + " where " + rendered.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }).joined(separator: ", ") + " {"
    }
    return base + " {"
}

// MARK: - Symbol loading

struct LoadedSymbols {
    let symbols: [ResolvedSymbol]
    let conformanceTargets: [String: [String]]
    let preciseToPath: [String: String]
    let rawTypes: [String: String]
}

func loadSymbols(from symbolGraphDir: URL, module: String) throws -> LoadedSymbols {
    let fm = FileManager.default
    let files = try fm.contentsOfDirectory(at: symbolGraphDir, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("\(module)") && $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    var symbols: [ResolvedSymbol] = []
    var conformanceTargets: [String: [String]] = [:]
    var preciseToPath: [String: String] = [:]
    var rawTypes: [String: String] = [:]

    let decoder = JSONDecoder()

    for file in files {
        let data = try Data(contentsOf: file)
        let graph = try decoder.decode(SymbolGraph.self, from: data)

        for rawSymbol in graph.symbols {
            let accessLevel = rawSymbol.accessLevel ?? "public"
            let preciseID = rawSymbol.identifier.precise
            let pathComponents = rawSymbol.pathComponents ?? []
            let namesTitle = rawSymbol.identifier.precise.components(separatedBy: ":").last
                .flatMap { String($0) }
            let declaration = fragmentsText(
                rawSymbol.declarationFragments,
                namesTitle: namesTitle,
                module: module
            )

            let availability = formatAvailability(rawSymbol.availability)

            let symbol = ResolvedSymbol(
                preciseID: preciseID,
                kindID: rawSymbol.kind.identifier,
                accessLevel: accessLevel,
                pathComponents: pathComponents,
                declaration: declaration,
                availability: availability,
                hasLocation: rawSymbol.location?.uri != nil,
                swiftExtension: rawSymbol.swiftExtension
            )
            symbols.append(symbol)

            if !preciseID.isEmpty && !pathComponents.isEmpty {
                preciseToPath[preciseID] = pathComponents.joined(separator: ".")
            }
            if symbol.kindID == "swift.init", let parent = symbol.parentPath {
                if let rawType = parseRawType(symbol.declaration) {
                    rawTypes[parent] = rawType
                }
            }
        }

        for rel in graph.relationships ?? [] {
            guard rel.kind == "conformsTo", let source = rel.source else { continue }
            let target = rel.targetFallback ?? rel.target ?? ""
            conformanceTargets[source, default: []].append(target)
        }
    }

    return LoadedSymbols(
        symbols: symbols,
        conformanceTargets: conformanceTargets,
        preciseToPath: preciseToPath,
        rawTypes: rawTypes
    )
}

// MARK: - Outline building

public func buildOutline(from symbolGraphDir: URL, module: String) throws -> ModuleOutline {
    let loaded = try loadSymbols(from: symbolGraphDir, module: module)
    var outline = ModuleOutline(module: module)
    var typeNodes: [String: TypeNode] = [:]
    var extensionGroups: [String: ExtensionGroup] = [:]

    // Filter symbols
    let keptSymbols = loaded.symbols.filter { symbol in
        guard symbol.accessLevel == "public" || symbol.accessLevel == "open" else { return false }
        if isProbablySynthesized(symbol) && !symbol.hasLocation { return false }
        return true
    }

    // First pass: collect container types
    for symbol in keptSymbols {
        guard containerKindIDs.contains(symbol.kindID), symbol.swiftExtension == nil else { continue }

        let conformanceNames = loaded.conformanceTargets[symbol.preciseID]?.map {
            normalizeConformanceName($0, preciseToPath: loaded.preciseToPath, module: module)
        } ?? []

        let node = TypeNode(
            name: symbol.shortName,
            path: symbol.fullPath,
            accessLevel: symbol.accessLevel,
            kindID: symbol.kindID,
            declaration: symbol.declaration,
            availability: symbol.availability,
            conformances: finalizeConformances(
                kindID: symbol.kindID,
                conformances: conformanceNames,
                rawType: loaded.rawTypes[symbol.fullPath]
            ),
            rawType: loaded.rawTypes[symbol.fullPath]
        )
        typeNodes[symbol.fullPath] = node
    }

    // Build parent-child relationships
    for node in typeNodes.values {
        let parts = node.path.split(separator: ".").map(String.init)
        if parts.count > 1, let parent = typeNodes[parts.dropLast().joined(separator: ".")] {
            parent.childTypes.append(node)
        } else {
            outline.types.append(node)
        }
    }

    // Second pass: collect members, extensions, typealiases, globals
    for symbol in keptSymbols {
        // Skip container types (already handled)
        if containerKindIDs.contains(symbol.kindID) && symbol.swiftExtension == nil {
            continue
        }

        // Extensions
        if symbol.swiftExtension != nil {
            // Skip inherited protocol defaults on concrete types
            if let ext = symbol.swiftExtension,
               ext.typeKind == "swift.protocol",
               let typeName = symbol.pathComponents.first,
               let parentNode = typeNodes[typeName],
               parentNode.kindID != "swift.protocol" {
                // Inherited protocol default on a concrete type.
                // Already rendered on the protocol's own extension block.
                continue
            }
            let header = renderExtensionHeader(symbol, module: module)
            let key = "\(header)|\(symbol.availability ?? "nil")"
            var group = extensionGroups[key] ?? ExtensionGroup(header: header, availability: symbol.availability, members: [])
            group.members.append(insertAccessKeyword(symbol.declaration, accessLevel: symbol.accessLevel))
            extensionGroups[key] = group
            continue
        }

        // Top-level typealiases
        if symbol.kindID == "swift.typealias" && symbol.parentPath == nil {
            outline.typealiases.append(insertAccessKeyword(symbol.declaration, accessLevel: symbol.accessLevel))
            continue
        }

        // Enum cases
        if symbol.kindID == "swift.enum.case", let parent = symbol.parentPath, let parentNode = typeNodes[parent] {
            parentNode.cases.append(symbol.declaration)
            continue
        }

        // Nested members
        if let parent = symbol.parentPath, let parentNode = typeNodes[parent] {
            let isProtocol = parentNode.kindID == "swift.protocol"
            let rendered: String
            if symbol.kindID == "swift.typealias" {
                rendered = insertAccessKeyword(symbol.declaration, accessLevel: symbol.accessLevel)
            } else if isProtocol {
                rendered = symbol.declaration
            } else {
                rendered = insertAccessKeyword(symbol.declaration, accessLevel: symbol.accessLevel)
            }
            parentNode.members.append(rendered)
            continue
        }

        // Globals
        let rendered = insertAccessKeyword(symbol.declaration, accessLevel: symbol.accessLevel)
        if ["swift.var", "swift.func", "swift.init", "swift.property", "swift.method", "swift.subscript"].contains(symbol.kindID) {
            outline.globals.append(rendered)
        } else if symbol.kindID == "swift.typealias" {
            outline.typealiases.append(rendered)
        } else {
            outline.globals.append(rendered)
        }
    }

    // Sort everything
    outline.typealiases.sort(by: { topLevelSortKey($0) < topLevelSortKey($1) })
    outline.globals.sort(by: { topLevelSortKey($0) < topLevelSortKey($1) })
    outline.extensions = extensionGroups.values.sorted { a, b in
        if a.header.localizedCaseInsensitiveCompare(b.header) != .orderedSame {
            return a.header.localizedCaseInsensitiveCompare(b.header) == .orderedAscending
        }
        return (a.availability ?? "").localizedCaseInsensitiveCompare(b.availability ?? "") == .orderedAscending
    }
    for i in outline.extensions.indices {
        outline.extensions[i].members.sort(by: { memberSortKey($0) < memberSortKey($1) })
    }

    return outline
}

// MARK: - Type rendering

public func renderType(_ node: TypeNode, indent: Int = 0) -> [String] {
    var lines: [String] = []
    let prefix = String(repeating: " ", count: indent)
    let baseDeclaration = insertAccessKeyword(node.declaration, accessLevel: node.accessLevel)
    let header = appendConformances(baseDeclaration, node.conformances) + " {"

    if let availability = node.availability {
        lines.append(prefix + availability)
    }
    lines.append(prefix + header)

    var children: [String] = []

    // Child types sorted
    for child in node.childTypes.sorted(by: { typeSortKey($0) < typeSortKey($1) }) {
        if !children.isEmpty { children.append("") }
        children.append(contentsOf: renderType(child, indent: indent + 2))
    }

    // Cases
    if !node.cases.isEmpty {
        if !children.isEmpty { children.append("") }
        children.append(contentsOf: node.cases.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
            .map { String(repeating: " ", count: indent + 2) + $0 })
    }

    // Members
    if !node.members.isEmpty {
        if !children.isEmpty { children.append("") }
        children.append(contentsOf: node.members
            .sorted(by: { memberSortKey($0) < memberSortKey($1) })
            .map { String(repeating: " ", count: indent + 2) + $0 })
    }

    lines.append(contentsOf: children)
    lines.append(prefix + "}")
    return lines
}

// MARK: - Outline rendering

public func renderOutline(_ outline: ModuleOutline) -> String {
    var lines = ["// \(outline.module) public API outline", ""]

    var sections: [[String]] = []
    if !outline.typealiases.isEmpty { sections.append(outline.typealiases) }
    if !outline.globals.isEmpty { sections.append(outline.globals) }

    if !outline.types.isEmpty {
        let typeLines = outline.types
            .sorted(by: { typeSortKey($0) < typeSortKey($1) })
            .flatMap { renderType($0) + [""] }
            .dropLast()
        sections.append(Array(typeLines))
    }

    for group in outline.extensions {
        var section: [String] = []
        if let av = group.availability { section.append(av) }
        section.append(group.header)
        section.append(contentsOf: group.members.map { "  " + $0 })
        section.append("}")
        sections.append(section)
    }

    for (index, section) in sections.enumerated() {
        if index > 0 { lines.append("") }
        lines.append(contentsOf: section)
    }

    lines.append("")
    return lines.joined(separator: "\n")
}

// MARK: - Public API

/// Render a pseudo-Swift public interface from a directory of symbol graph JSON files.
public func renderFromSymbolGraphDirectory(_ symbolGraphDir: URL, module: String) throws -> String {
    let outline = try buildOutline(from: symbolGraphDir, module: module)
    return renderOutline(outline)
}

/// Build a ModuleOutline from symbol graphs (for programmatic use with sections).
public func buildOutlineFromSymbolGraphs(_ symbolGraphDir: URL, module: String) throws -> ModuleOutline {
    try buildOutline(from: symbolGraphDir, module: module)
}
