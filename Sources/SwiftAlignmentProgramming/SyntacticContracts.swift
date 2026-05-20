import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - Contract IR

public struct ContractModule: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var module: String
    public var symbols: [ContractSymbol]

    public init(schemaVersion: Int = 1, module: String, symbols: [ContractSymbol]) {
        self.schemaVersion = schemaVersion
        self.module = module
        self.symbols = symbols
    }
}

public struct ContractSymbol: Codable, Sendable, Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var kind: String
    public var access: String
    public var path: [String]
    public var declaration: String
    public var parentKey: String?
    public var extendedType: String?
    public var isExtensionMember: Bool

    public init(
        key: String,
        kind: String,
        access: String,
        path: [String],
        declaration: String,
        parentKey: String? = nil,
        extendedType: String? = nil,
        isExtensionMember: Bool = false
    ) {
        self.key = key
        self.kind = kind
        self.access = access
        self.path = path
        self.declaration = declaration
        self.parentKey = parentKey
        self.extendedType = extendedType
        self.isExtensionMember = isExtensionMember
    }
}

public enum ContractError: Error, CustomStringConvertible {
    case noSources(String)
    case inferredStoredProperty(file: String, declaration: String)
    case targetNotFound(String)
    case invalidAccess(String)
    case processFailed(String)

    public var description: String {
        switch self {
        case .noSources(let path):
            "No Swift source files found at \(path)"
        case .inferredStoredProperty(let file, let declaration):
            "Contract-visible stored property requires an explicit type in \(file): \(declaration)"
        case .targetNotFound(let target):
            "Target not found: \(target)"
        case .invalidAccess(let access):
            "Invalid access level: \(access)"
        case .processFailed(let message):
            message
        }
    }
}

public struct ContractConfiguration: Sendable, Equatable {
    public var accessLevels: Set<String>
    public var includeGlobs: [String]
    public var excludeGlobs: [String]
    public var respectGitIgnore: Bool

    public init(
        accessLevels: Set<String> = ["open", "public", "package"],
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        respectGitIgnore: Bool = true
    ) {
        self.accessLevels = accessLevels
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.respectGitIgnore = respectGitIgnore
    }
}

// MARK: - Extraction

public struct ContractExtractor: Sendable {
    public var configuration: ContractConfiguration

    public init(configuration: ContractConfiguration = ContractConfiguration()) {
        self.configuration = configuration
    }

    public func extractModule(module: String, files: [(path: String, source: String)]) throws -> ContractModule {
        var symbols: [ContractSymbol] = []
        for file in files.sorted(by: { $0.path < $1.path }) {
            let tree = Parser.parse(source: file.source)
            let visitor = ContractSyntaxVisitor(
                module: module,
                file: file.path,
                visibleAccess: configuration.accessLevels
            )
            visitor.walk(tree)
            if let diagnostic = visitor.diagnostics.first {
                throw diagnostic
            }
            symbols.append(contentsOf: visitor.symbols)
        }

        let sorted = symbols
            .uniquedByKey()
            .sorted { lhs, rhs in
                if lhs.key != rhs.key { return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending }
                return lhs.declaration < rhs.declaration
            }
        return ContractModule(module: module, symbols: sorted)
    }
}

private struct ContractContext {
    var name: String?
    var path: [String]
    var effectiveAccess: String
    var defaultAccess: String
    var kind: String?
    var isExtension: Bool
    var extendedType: String?

    var parentKey: String? {
        guard let kind, let name else { return nil }
        if kind == "extension" { return "extension \(name)" }
        return "type \(path.joined(separator: "."))"
    }
}

private final class ContractSyntaxVisitor: SyntaxVisitor {
    let module: String
    let file: String
    let visibleAccess: Set<String>
    var contexts: [ContractContext] = [
        ContractContext(
            name: nil,
            path: [],
            effectiveAccess: "public",
            defaultAccess: "internal",
            kind: nil,
            isExtension: false,
            extendedType: nil
        ),
    ]
    var symbols: [ContractSymbol] = []
    var diagnostics: [ContractError] = []

    init(module: String, file: String, visibleAccess: Set<String>) {
        self.module = module
        self.file = file
        self.visibleAccess = visibleAccess
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(kind: "struct", name: node.name.text, modifiers: node.modifiers, declaration: nominalDeclaration(node, keyword: "struct"))
    }

    override func visitPost(_ node: StructDeclSyntax) {
        contexts.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(kind: "enum", name: node.name.text, modifiers: node.modifiers, declaration: nominalDeclaration(node, keyword: "enum"))
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        contexts.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(kind: "class", name: node.name.text, modifiers: node.modifiers, declaration: nominalDeclaration(node, keyword: "class"))
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        contexts.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(kind: "actor", name: node.name.text, modifiers: node.modifiers, declaration: nominalDeclaration(node, keyword: "actor"))
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        contexts.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        enterNominal(kind: "protocol", name: node.name.text, modifiers: node.modifiers, declaration: nominalDeclaration(node, keyword: "protocol"))
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        contexts.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let declared = declaredAccess(node.modifiers)
        let inherited = current.effectiveAccess
        let effective = declared.map { effectiveAccess($0, inside: inherited) } ?? inherited
        let extendedType = node.extendedType.trimmedDescription
        let defaultAccess = declared ?? "internal"
        let whereClause = node.genericWhereClause.map { " " + $0.trimmedDescription } ?? ""
        let declaration = "\(attributesText(node.attributes))\(modifiersText(node.modifiers))extension \(extendedType)\(whereClause)"

        if isVisible(effective) {
            symbols.append(ContractSymbol(
                key: "extension \(extendedType)\(whereClause)",
                kind: "extension",
                access: effective,
                path: [extendedType],
                declaration: normalizeDeclaration(declaration),
                extendedType: extendedType
            ))
        }

        contexts.append(ContractContext(
            name: extendedType,
            path: [extendedType],
            effectiveAccess: effective,
            defaultAccess: defaultAccess,
            kind: "extension",
            isExtension: true,
            extendedType: extendedType
        ))
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        contexts.removeLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        addCallable(
            kind: "func",
            name: node.name.text,
            modifiers: node.modifiers,
            declaration: functionDeclaration(node),
            labels: parameterLabels(node.signature.parameterClause.parameters)
        )
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        addCallable(
            kind: "init",
            name: "init",
            modifiers: node.modifiers,
            declaration: initializerDeclaration(node),
            labels: parameterLabels(node.signature.parameterClause.parameters)
        )
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        addCallable(
            kind: "subscript",
            name: "subscript",
            modifiers: node.modifiers,
            declaration: subscriptDeclaration(node),
            labels: parameterLabels(node.parameterClause.parameters)
        )
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let declared = declaredAccess(node.modifiers)
        let access = effectiveAccess(declared ?? current.defaultAccess, inside: current.effectiveAccess)
        guard isVisible(access) else { return .skipChildren }

        for binding in node.bindings {
            let propertyName = binding.pattern.trimmedDescription
            let isStored = binding.accessorBlock == nil
            if isStored && binding.typeAnnotation == nil {
                diagnostics.append(.inferredStoredProperty(file: file, declaration: "\(node.bindingSpecifier.text) \(propertyName)"))
                return .skipChildren
            }
            let declaration = variableDeclaration(node, binding: binding)
            addSymbol(
                kind: node.bindingSpecifier.text,
                name: propertyName,
                access: access,
                declaration: declaration,
                labelSignature: nil
            )
        }
        return .skipChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = effectiveAccess(declaredAccess(node.modifiers) ?? current.defaultAccess, inside: current.effectiveAccess)
        guard isVisible(access) else { return .skipChildren }
        addSymbol(kind: "typealias", name: node.name.text, access: access, declaration: node.trimmedDescription, labelSignature: nil)
        return .skipChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = effectiveAccess(declaredAccess(node.modifiers) ?? current.defaultAccess, inside: current.effectiveAccess)
        guard isVisible(access) else { return .skipChildren }
        addSymbol(kind: "associatedtype", name: node.name.text, access: access, declaration: node.trimmedDescription, labelSignature: nil)
        return .skipChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        let defaultAccess = current.kind == "enum" ? current.effectiveAccess : current.defaultAccess
        let access = effectiveAccess(declaredAccess(node.modifiers) ?? defaultAccess, inside: current.effectiveAccess)
        guard isVisible(access) else { return .skipChildren }
        for element in node.elements {
            let name = element.name.text
            let declaration = "\(attributesText(node.attributes))case \(element.trimmedDescription.trimmingCharacters(in: CharacterSet(charactersIn: ",")))"
            addSymbol(kind: "case", name: name, access: access, declaration: declaration, labelSignature: nil)
        }
        return .skipChildren
    }

    private var current: ContractContext {
        contexts.last ?? contexts[0]
    }

    private func enterNominal(kind: String, name: String, modifiers: DeclModifierListSyntax, declaration: String) -> SyntaxVisitorContinueKind {
        let declared = declaredAccess(modifiers)
        let access = effectiveAccess(declared ?? current.defaultAccess, inside: current.effectiveAccess)
        let path = current.path + [name]
        let key = "type \(path.joined(separator: "."))"
        if isVisible(access) {
            symbols.append(ContractSymbol(
                key: key,
                kind: kind,
                access: access,
                path: path,
                declaration: normalizeDeclaration(declaration),
                parentKey: current.isExtension ? "extension \(current.extendedType ?? "")" : current.parentKey
            ))
        }
        let childDefault = kind == "protocol" ? access : "internal"
        contexts.append(ContractContext(
            name: name,
            path: path,
            effectiveAccess: access,
            defaultAccess: childDefault,
            kind: kind,
            isExtension: false,
            extendedType: nil
        ))
        return .visitChildren
    }

    private func addCallable(kind: String, name: String, modifiers: DeclModifierListSyntax, declaration: String, labels: String) {
        let access = effectiveAccess(declaredAccess(modifiers) ?? current.defaultAccess, inside: current.effectiveAccess)
        guard isVisible(access) else { return }
        addSymbol(kind: kind, name: name, access: access, declaration: declaration, labelSignature: labels)
    }

    private func addSymbol(kind: String, name: String, access: String, declaration: String, labelSignature: String?) {
        let path = current.path
        let base = path.isEmpty ? name : path.joined(separator: ".") + "." + name
        let key: String
        switch kind {
        case "func":
            key = "func \(base)(\(labelSignature ?? ""))"
        case "init":
            key = "init \(path.joined(separator: ".")).init(\(labelSignature ?? ""))"
        case "subscript":
            key = "subscript \(path.joined(separator: ".")).(\(labelSignature ?? ""))"
        case "var", "let":
            key = "var \(base)"
        case "case":
            key = "case \(base)"
        case "typealias", "associatedtype":
            key = "\(kind) \(base)"
        default:
            key = "\(kind) \(base)"
        }
        symbols.append(ContractSymbol(
            key: key,
            kind: kind,
            access: access,
            path: path + [name],
            declaration: normalizeDeclaration(declaration),
            parentKey: current.parentKey,
            extendedType: current.extendedType,
            isExtensionMember: current.isExtension
        ))
    }

    private func isVisible(_ access: String) -> Bool {
        visibleAccess.contains(access)
    }
}

// MARK: - Rendering

public struct ContractRenderer: Sendable {
    public init() {}

    public func render(_ module: ContractModule) -> String {
        let tree = ContractTree(module: module)
        var lines = ["// \(module.module) syntactic contract interface", ""]
        var sections: [[String]] = []

        let topLevelLoose = tree.topLevelLooseSymbols.map(\.declaration).sorted(by: compareDeclarations)
        if !topLevelLoose.isEmpty {
            sections.append(topLevelLoose)
        }

        let renderedTypes = tree.topLevelTypes
            .sorted(by: compareSymbols)
            .flatMap { renderType($0, tree: tree, indent: 0) + [""] }
            .dropLast()
        if !renderedTypes.isEmpty {
            sections.append(Array(renderedTypes))
        }

        for ext in tree.externalExtensions.sorted(by: compareSymbols) {
            var section = [ext.declaration + " {"]
            let members = tree.children(of: ext.key)
                .sorted(by: compareSymbols)
                .map { "  " + $0.declaration }
            section.append(contentsOf: members)
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

    private func renderType(_ symbol: ContractSymbol, tree: ContractTree, indent: Int) -> [String] {
        let prefix = String(repeating: " ", count: indent)
        var lines = [prefix + symbol.declaration + " {"]
        let childTypes = tree.children(of: symbol.key)
            .filter { ContractTree.typeKinds.contains($0.kind) }
            .sorted(by: compareSymbols)
        let members = tree.children(of: symbol.key)
            .filter { !ContractTree.typeKinds.contains($0.kind) && $0.kind != "extension" }
            .sorted(by: compareSymbols)

        var body: [String] = []
        for child in childTypes {
            if !body.isEmpty { body.append("") }
            body.append(contentsOf: renderType(child, tree: tree, indent: indent + 2))
        }
        if !members.isEmpty {
            if !body.isEmpty { body.append("") }
            body.append(contentsOf: members.map { String(repeating: " ", count: indent + 2) + $0.declaration })
        }
        lines.append(contentsOf: body)
        lines.append(prefix + "}")
        return lines
    }
}

private struct ContractTree {
    static let typeKinds: Set<String> = ["actor", "class", "enum", "protocol", "struct"]

    var byKey: [String: ContractSymbol]
    var childrenByParent: [String: [ContractSymbol]]
    var localTypeKeys: Set<String>
    var localTypeNames: Set<String>

    init(module: ContractModule) {
        byKey = Dictionary(uniqueKeysWithValues: module.symbols.map { ($0.key, $0) })
        localTypeKeys = Set(module.symbols.filter { Self.typeKinds.contains($0.kind) }.map(\.key))
        localTypeNames = Set(module.symbols.filter { Self.typeKinds.contains($0.kind) }.compactMap(\.path.last))
        childrenByParent = [:]

        for symbol in module.symbols {
            guard symbol.kind != "extension" else { continue }
            if let parent = effectiveParent(for: symbol) {
                childrenByParent[parent, default: []].append(symbol)
            }
        }
    }

    var topLevelTypes: [ContractSymbol] {
        byKey.values.filter { symbol in
            Self.typeKinds.contains(symbol.kind) && effectiveParent(for: symbol) == nil
        }
    }

    var topLevelLooseSymbols: [ContractSymbol] {
        byKey.values.filter { symbol in
            !Self.typeKinds.contains(symbol.kind)
                && symbol.kind != "extension"
                && effectiveParent(for: symbol) == nil
        }
    }

    var externalExtensions: [ContractSymbol] {
        byKey.values.filter { symbol in
            guard symbol.kind == "extension", let extended = symbol.extendedType else { return false }
            return !isLocalType(extended)
        }
    }

    func children(of parentKey: String) -> [ContractSymbol] {
        childrenByParent[parentKey, default: []]
    }

    private func effectiveParent(for symbol: ContractSymbol) -> String? {
        if symbol.isExtensionMember, let extended = symbol.extendedType, isLocalType(extended) {
            return "type \(extended)"
        }
        if let parent = symbol.parentKey, parent.hasPrefix("extension "), let extended = symbol.extendedType, isLocalType(extended) {
            return "type \(extended)"
        }
        return symbol.parentKey
    }

    private func isLocalType(_ type: String) -> Bool {
        localTypeKeys.contains("type \(type)") || localTypeNames.contains(type)
    }
}

// MARK: - Diffing

public struct ContractDiff: Sendable {
    public var added: [ContractSymbol]
    public var removed: [ContractSymbol]
    public var changed: [(before: ContractSymbol, after: ContractSymbol)]

    public var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && changed.isEmpty
    }
}

public func diffContracts(old: ContractModule, new: ContractModule) -> ContractDiff {
    let oldByKey = Dictionary(uniqueKeysWithValues: old.symbols.map { ($0.key, $0) })
    let newByKey = Dictionary(uniqueKeysWithValues: new.symbols.map { ($0.key, $0) })
    let added = new.symbols.filter { oldByKey[$0.key] == nil }.sorted(by: compareSymbols)
    let removed = old.symbols.filter { newByKey[$0.key] == nil }.sorted(by: compareSymbols)
    let changed = old.symbols.compactMap { before -> (before: ContractSymbol, after: ContractSymbol)? in
        guard let after = newByKey[before.key], before.declaration != after.declaration || before.access != after.access else { return nil }
        return (before, after)
    }.sorted { $0.before.key < $1.before.key }
    return ContractDiff(added: added, removed: removed, changed: changed)
}

public func renderContractDiff(_ diff: ContractDiff) -> String {
    if diff.isEmpty { return "No contract changes.\n" }
    var lines: [String] = []
    if !diff.added.isEmpty {
        lines.append("Added public/package/open API:")
        lines.append(contentsOf: diff.added.map { "  \($0.declaration)" })
    }
    if !diff.removed.isEmpty {
        if !lines.isEmpty { lines.append("") }
        lines.append("Removed public/package/open API:")
        lines.append(contentsOf: diff.removed.map { "  \($0.declaration)" })
    }
    if !diff.changed.isEmpty {
        if !lines.isEmpty { lines.append("") }
        lines.append("Changed public/package/open API:")
        for item in diff.changed {
            lines.append("  \((item.before.key))")
            lines.append("    - \(item.before.declaration)")
            lines.append("    + \(item.after.declaration)")
        }
    }
    lines.append("")
    return lines.joined(separator: "\n")
}

// MARK: - Source discovery

public struct ContractSourceTarget: Sendable, Equatable {
    public var name: String
    public var sourceRoot: String
    public var files: [String]

    public init(name: String, sourceRoot: String, files: [String]) {
        self.name = name
        self.sourceRoot = sourceRoot
        self.files = files
    }
}

public struct ContractSourceCollector: Sendable {
    public var configuration: ContractConfiguration
    public var excludedDirs: Set<String>

    public init(
        configuration: ContractConfiguration = ContractConfiguration(),
        excludedDirs: Set<String> = [".git", ".build", ".swiftpm", ".ci"]
    ) {
        self.configuration = configuration
        self.excludedDirs = excludedDirs
    }

    public func collect(in root: URL) throws -> [ContractSourceTarget] {
        let packageTargets = try swiftPackageTargets(in: root)
        let targets = packageTargets.isEmpty ? try alignedLayoutTargets(in: root) : packageTargets
        guard !targets.isEmpty else { throw ContractError.noSources(root.path) }
        return targets.sorted { $0.name < $1.name }
    }

    private func swiftPackageTargets(in root: URL) throws -> [ContractSourceTarget] {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else { return [] }
        let process = Process()
#if os(Linux)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["package", "--package-path", root.path, "dump-package"]
#else
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swift", "package", "--package-path", root.path, "dump-package"]
#endif
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targetObjects = json["targets"] as? [[String: Any]] else { return [] }

        let sourceTypes: Set<String> = ["regular", "executable", "macro", "plugin"]
        var targets: [ContractSourceTarget] = []
        for target in targetObjects {
            guard let name = target["name"] as? String,
                  let type = target["type"] as? String,
                  sourceTypes.contains(type) else { continue }
            let sourceRoot = (target["path"] as? String) ?? defaultSourceRoot(forTargetNamed: name, root: root)
            guard !sourceRoot.split(separator: "/").contains("Tests") else { continue }
            let files = swiftFiles(under: root.appendingPathComponent(sourceRoot), root: root)
            guard !files.isEmpty else { continue }
            targets.append(ContractSourceTarget(name: name, sourceRoot: sourceRoot, files: files))
        }
        return targets
    }

    private func alignedLayoutTargets(in root: URL) throws -> [ContractSourceTarget] {
        let targetsRoot = root.appendingPathComponent("Targets")
        guard FileManager.default.fileExists(atPath: targetsRoot.path) else { return [] }
        let children = try FileManager.default.contentsOfDirectory(at: targetsRoot, includingPropertiesForKeys: [.isDirectoryKey])
        var targets: [ContractSourceTarget] = []
        for child in children where child.hasDirectoryPath {
            let sourceRoot = "Targets/\(child.lastPathComponent)/Sources"
            let files = swiftFiles(under: root.appendingPathComponent(sourceRoot), root: root)
            guard !files.isEmpty else { continue }
            targets.append(ContractSourceTarget(name: child.lastPathComponent, sourceRoot: sourceRoot, files: files))
        }
        return targets
    }

    private func defaultSourceRoot(forTargetNamed name: String, root: URL) -> String {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("Targets/\(name)/Sources").path) {
            return "Targets/\(name)/Sources"
        }
        return "Sources/\(name)"
    }

    private func swiftFiles(under url: URL, root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var files: [String] = []
        for case let file as URL in enumerator {
            let relative = contractRelativePath(from: root, to: file)
            let parts = relative.split(separator: "/").map(String.init)
            if parts.contains(where: { excludedDirs.contains($0) || $0 == "Tests" }) {
                if file.hasDirectoryPath { enumerator.skipDescendants() }
                continue
            }
            guard file.pathExtension == "swift" else { continue }
            guard matchesGlobs(relative, include: configuration.includeGlobs, exclude: configuration.excludeGlobs) else { continue }
            guard !configuration.respectGitIgnore || !isGitIgnored(relative, root: root) else { continue }
            files.append(relative)
        }
        return files.sorted()
    }
}

public func loadContractModule(root: URL, target: ContractSourceTarget, configuration: ContractConfiguration = ContractConfiguration()) throws -> ContractModule {
    let files = try target.files.map { relative -> (path: String, source: String) in
        let source = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        return (relative, source)
    }
    return try ContractExtractor(configuration: configuration).extractModule(module: target.name, files: files)
}

// MARK: - Helpers

private let accessRank: [String: Int] = [
    "private": 0,
    "fileprivate": 1,
    "internal": 2,
    "package": 3,
    "public": 4,
    "open": 5,
]

private func declaredAccess(_ modifiers: DeclModifierListSyntax) -> String? {
    for modifier in modifiers {
        let text = modifier.name.text
        if accessRank[text] != nil { return text }
    }
    return nil
}

private func effectiveAccess(_ access: String, inside parent: String) -> String {
    let accessValue = accessRank[access, default: 2]
    let parentValue = accessRank[parent, default: 2]
    return accessValue <= parentValue ? access : parent
}

private func attributesText(_ attributes: AttributeListSyntax) -> String {
    let text = attributes.trimmedDescription
    return text.isEmpty ? "" : text + " "
}

private func modifiersText(_ modifiers: DeclModifierListSyntax) -> String {
    let text = modifiers.trimmedDescription
    return text.isEmpty ? "" : text + " "
}

private func nominalDeclaration(_ node: StructDeclSyntax, keyword: String) -> String {
    var parts = "\(attributesText(node.attributes))\(modifiersText(node.modifiers))\(keyword)"
    parts += " \(node.name.text)"
    if let generic = node.genericParameterClause { parts += generic.trimmedDescription }
    if let inheritance = node.inheritanceClause {
        parts += " " + inheritance.trimmedDescription
    }
    if let whereClause = node.genericWhereClause { parts += " " + whereClause.trimmedDescription }
    return parts
}

private func nominalDeclaration(_ node: EnumDeclSyntax, keyword: String) -> String {
    var parts = "\(attributesText(node.attributes))\(modifiersText(node.modifiers))\(keyword) \(node.name.text)"
    if let generic = node.genericParameterClause { parts += generic.trimmedDescription }
    if let inheritance = node.inheritanceClause { parts += " " + inheritance.trimmedDescription }
    if let whereClause = node.genericWhereClause { parts += " " + whereClause.trimmedDescription }
    return parts
}

private func nominalDeclaration(_ node: ClassDeclSyntax, keyword: String) -> String {
    var parts = "\(attributesText(node.attributes))\(modifiersText(node.modifiers))\(keyword) \(node.name.text)"
    if let generic = node.genericParameterClause { parts += generic.trimmedDescription }
    if let inheritance = node.inheritanceClause { parts += " " + inheritance.trimmedDescription }
    if let whereClause = node.genericWhereClause { parts += " " + whereClause.trimmedDescription }
    return parts
}

private func nominalDeclaration(_ node: ActorDeclSyntax, keyword: String) -> String {
    var parts = "\(attributesText(node.attributes))\(modifiersText(node.modifiers))\(keyword) \(node.name.text)"
    if let generic = node.genericParameterClause { parts += generic.trimmedDescription }
    if let inheritance = node.inheritanceClause { parts += " " + inheritance.trimmedDescription }
    if let whereClause = node.genericWhereClause { parts += " " + whereClause.trimmedDescription }
    return parts
}

private func nominalDeclaration(_ node: ProtocolDeclSyntax, keyword: String) -> String {
    var parts = "\(attributesText(node.attributes))\(modifiersText(node.modifiers))\(keyword) \(node.name.text)"
    if let inheritance = node.inheritanceClause { parts += " " + inheritance.trimmedDescription }
    if let whereClause = node.genericWhereClause { parts += " " + whereClause.trimmedDescription }
    return parts
}

private func functionDeclaration(_ node: FunctionDeclSyntax) -> String {
    var text = "\(attributesText(node.attributes))\(modifiersText(node.modifiers))func \(node.name.text)"
    if let generic = node.genericParameterClause { text += generic.trimmedDescription }
    text += node.signature.trimmedDescription
    if let whereClause = node.genericWhereClause { text += " " + whereClause.trimmedDescription }
    return normalizeDeclaration(text)
}

private func initializerDeclaration(_ node: InitializerDeclSyntax) -> String {
    var text = "\(attributesText(node.attributes))\(modifiersText(node.modifiers))init"
    if let mark = node.optionalMark { text += mark.text }
    if let generic = node.genericParameterClause { text += generic.trimmedDescription }
    text += node.signature.trimmedDescription
    if let whereClause = node.genericWhereClause { text += " " + whereClause.trimmedDescription }
    return normalizeDeclaration(text)
}

private func subscriptDeclaration(_ node: SubscriptDeclSyntax) -> String {
    var text = "\(attributesText(node.attributes))\(modifiersText(node.modifiers))subscript"
    if let generic = node.genericParameterClause { text += generic.trimmedDescription }
    text += node.parameterClause.trimmedDescription
    text += " " + node.returnClause.trimmedDescription
    if let whereClause = node.genericWhereClause { text += " " + whereClause.trimmedDescription }
    return normalizeDeclaration(text)
}

private func variableDeclaration(_ node: VariableDeclSyntax, binding: PatternBindingSyntax) -> String {
    var text = "\(attributesText(node.attributes))\(modifiersText(node.modifiers))\(node.bindingSpecifier.text) \(binding.pattern.trimmedDescription)"
    if let typeAnnotation = binding.typeAnnotation {
        text += typeAnnotation.trimmedDescription
    }
    if binding.accessorBlock != nil {
        text += " { get }"
    }
    return normalizeDeclaration(text)
}

private func parameterLabels(_ parameters: FunctionParameterListSyntax) -> String {
    parameters.map { parameter in
        let first = parameter.firstName.text
        if first == "_" { return "_:" }
        return "\(first):"
    }.joined()
}

private func normalizeDeclaration(_ text: String) -> String {
    text.replacing(/\s+/, with: " ")
        .replacing(/\s+:\s+/, with: ": ")
        .replacing(/\s+,\s+/, with: ", ")
        .replacing("( ", with: "(")
        .replacing(" )", with: ")")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func compareSymbols(_ lhs: ContractSymbol, _ rhs: ContractSymbol) -> Bool {
    if lhs.key != rhs.key { return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending }
    return lhs.declaration < rhs.declaration
}

private func compareDeclarations(_ lhs: String, _ rhs: String) -> Bool {
    lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
}

private func matchesGlobs(_ path: String, include: [String], exclude: [String]) -> Bool {
    let included = include.isEmpty || include.contains { globMatches($0, path) }
    let excluded = exclude.contains { globMatches($0, path) }
    return included && !excluded
}

private func globMatches(_ pattern: String, _ path: String) -> Bool {
    var regex = "^"
    for character in pattern {
        switch character {
        case "*":
            regex += ".*"
        case "?":
            regex += "."
        case ".", "+", "(", ")", "[", "]", "{", "}", "^", "$", "|", "\\":
            regex += "\\\(character)"
        default:
            regex.append(character)
        }
    }
    regex += "$"
    return path.range(of: regex, options: .regularExpression) != nil
}

private func isGitIgnored(_ path: String, root: URL) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", root.path, "check-ignore", "-q", path]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

private func contractRelativePath(from root: URL, to file: URL) -> String {
    let rootPath = root.standardizedFileURL.path
    let filePath = file.standardizedFileURL.path
    if filePath.hasPrefix(rootPath + "/") {
        return String(filePath.dropFirst(rootPath.count + 1))
    }
    return filePath
}

private extension Array where Element == ContractSymbol {
    func uniquedByKey() -> [ContractSymbol] {
        var seen: Set<String> = []
        var result: [ContractSymbol] = []
        for symbol in self {
            guard !seen.contains(symbol.key) else { continue }
            seen.insert(symbol.key)
            result.append(symbol)
        }
        return result
    }
}
