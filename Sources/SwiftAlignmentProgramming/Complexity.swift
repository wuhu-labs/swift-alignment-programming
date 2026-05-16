import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - Complexity report model

public struct ComplexityReport: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var root: String
    public var configuration: ComplexityMetricConfiguration
    public var summary: ComplexitySummary
    public var targets: [ComplexityTargetReport]
    public var files: [ComplexityFileReport]

    public init(
        schemaVersion: Int = 1,
        root: String,
        configuration: ComplexityMetricConfiguration,
        summary: ComplexitySummary,
        targets: [ComplexityTargetReport],
        files: [ComplexityFileReport]
    ) {
        self.schemaVersion = schemaVersion
        self.root = root
        self.configuration = configuration
        self.summary = summary
        self.targets = targets
        self.files = files
    }
}

public struct ComplexitySummary: Codable, Sendable, Equatable {
    public var rawScore: Double
    public var weightedScore: Double
    public var targets: Int
    public var files: Int
    public var lines: Int

    public init(rawScore: Double, weightedScore: Double, targets: Int, files: Int, lines: Int) {
        self.rawScore = rawScore
        self.weightedScore = weightedScore
        self.targets = targets
        self.files = files
        self.lines = lines
    }
}

public struct ComplexityTargetReport: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var sourceRoot: String
    public var rawScore: Double
    public var weightedScore: Double
    public var files: Int
    public var lines: Int

    public init(name: String, sourceRoot: String, rawScore: Double, weightedScore: Double, files: Int, lines: Int) {
        self.name = name
        self.sourceRoot = sourceRoot
        self.rawScore = rawScore
        self.weightedScore = weightedScore
        self.files = files
        self.lines = lines
    }
}

public struct ComplexityFileReport: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public var path: String
    public var target: String
    public var rawScore: Double
    public var weightedScore: Double
    public var lines: Int
    public var declarations: [ComplexityDeclarationReport]
    public var lineComplexity: [LineComplexity]

    public init(
        path: String,
        target: String,
        rawScore: Double,
        weightedScore: Double,
        lines: Int,
        declarations: [ComplexityDeclarationReport],
        lineComplexity: [LineComplexity]
    ) {
        self.path = path
        self.target = target
        self.rawScore = rawScore
        self.weightedScore = weightedScore
        self.lines = lines
        self.declarations = declarations
        self.lineComplexity = lineComplexity
    }
}

public struct ComplexityDeclarationReport: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(kind):\(name):\(startLine):\(endLine)" }
    public var kind: String
    public var name: String
    public var access: String
    public var startLine: Int
    public var endLine: Int
    public var rawScore: Double
    public var weightedScore: Double
    public var multipliers: [String: Double]

    public init(
        kind: String,
        name: String,
        access: String,
        startLine: Int,
        endLine: Int,
        rawScore: Double,
        weightedScore: Double,
        multipliers: [String: Double]
    ) {
        self.kind = kind
        self.name = name
        self.access = access
        self.startLine = startLine
        self.endLine = endLine
        self.rawScore = rawScore
        self.weightedScore = weightedScore
        self.multipliers = multipliers
    }
}

public struct LineComplexity: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { line }
    public var line: Int
    public var rawScore: Double
    public var weightedScore: Double
    public var events: [ComplexityEvent]

    public init(line: Int, rawScore: Double, weightedScore: Double, events: [ComplexityEvent]) {
        self.line = line
        self.rawScore = rawScore
        self.weightedScore = weightedScore
        self.events = events
    }
}

public struct ComplexityEvent: Codable, Sendable, Equatable {
    public var kind: String
    public var label: String
    public var rawScore: Double
    public var weightedScore: Double
    public var multipliers: [String: Double]

    public init(kind: String, label: String, rawScore: Double, weightedScore: Double, multipliers: [String: Double] = [:]) {
        self.kind = kind
        self.label = label
        self.rawScore = rawScore
        self.weightedScore = weightedScore
        self.multipliers = multipliers
    }
}

// MARK: - Metric configuration

public struct ComplexityMetricConfiguration: Codable, Sendable, Equatable {
    public var accessMultipliers: [String: Double]
    public var typeKindMultipliers: [String: Double]
    public var letPropertyScore: Double
    public var varPropertyScore: Double
    public var localLetScore: Double
    public var localVarScore: Double
    public var storedPropertyMultiplier: Double
    public var computedPropertyMultiplier: Double
    public var methodEffectMultipliers: [String: Double]
    public var decisionScore: Double
    public var declarationScore: Double
    public var closureScore: Double

    public init(
        accessMultipliers: [String: Double] = [
            "public": 3,
            "package": 2.5,
            "internal": 2,
            "fileprivate": 1.5,
            "private": 1,
            "open": 3,
        ],
        typeKindMultipliers: [String: Double] = [
            "non_final_class": 5,
            "final_class": 3,
            "actor": 2,
            "protocol": 2,
            "struct": 1,
            "enum": 1.2,
            "extension": 1,
        ],
        letPropertyScore: Double = 0.25,
        varPropertyScore: Double = 1,
        localLetScore: Double = 0.05,
        localVarScore: Double = 0.5,
        storedPropertyMultiplier: Double = 1.5,
        computedPropertyMultiplier: Double = 1,
        methodEffectMultipliers: [String: Double] = [
            "plain": 1,
            "async": 1.25,
            "throws": 1.25,
            "rethrows": 1.15,
            "async_throws": 1.5,
            "async_rethrows": 1.4,
        ],
        decisionScore: Double = 1,
        declarationScore: Double = 1,
        closureScore: Double = 1
    ) {
        self.accessMultipliers = accessMultipliers
        self.typeKindMultipliers = typeKindMultipliers
        self.letPropertyScore = letPropertyScore
        self.varPropertyScore = varPropertyScore
        self.localLetScore = localLetScore
        self.localVarScore = localVarScore
        self.storedPropertyMultiplier = storedPropertyMultiplier
        self.computedPropertyMultiplier = computedPropertyMultiplier
        self.methodEffectMultipliers = methodEffectMultipliers
        self.decisionScore = decisionScore
        self.declarationScore = declarationScore
        self.closureScore = closureScore
    }

    public func accessMultiplier(_ access: String) -> Double {
        accessMultipliers[access, default: accessMultipliers["internal", default: 2]]
    }

    public func typeKindMultiplier(_ kind: String) -> Double {
        typeKindMultipliers[kind, default: 1]
    }

    public func methodEffectMultiplier(async: Bool, throwsKind: String?) -> (key: String, value: Double) {
        let key: String
        if async, let throwsKind {
            key = "async_\(throwsKind)"
        } else if async {
            key = "async"
        } else if let throwsKind {
            key = throwsKind
        } else {
            key = "plain"
        }
        return (key, methodEffectMultipliers[key, default: 1])
    }
}

// MARK: - Source discovery

public struct ComplexitySourceTarget: Sendable, Equatable {
    public var name: String
    public var sourceRoot: String
    public var files: [String]

    public init(name: String, sourceRoot: String, files: [String]) {
        self.name = name
        self.sourceRoot = sourceRoot
        self.files = files
    }
}

public enum ComplexityError: Error, CustomStringConvertible {
    case notADirectory(String)
    case noSwiftSources(String)
    case invalidReport(String)

    public var description: String {
        switch self {
        case .notADirectory(let path):
            "Not a directory: \(path)"
        case .noSwiftSources(let path):
            "No non-test Swift sources found under \(path)"
        case .invalidReport(let path):
            "Invalid complexity report at \(path)"
        }
    }
}

public struct ComplexitySourceCollector: Sendable {
    public var excludedDirs: Set<String>

    public init(excludedDirs: Set<String> = [".git", ".build", ".swiftpm", ".ci"] ) {
        self.excludedDirs = excludedDirs
    }

    public func collect(in root: URL) throws -> [ComplexitySourceTarget] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ComplexityError.notADirectory(root.path)
        }

        let packageTargets = try swiftPackageTargets(in: root)
        let targets = packageTargets.isEmpty ? try alignedLayoutTargets(in: root) : packageTargets
        guard !targets.isEmpty else { throw ComplexityError.noSwiftSources(root.path) }
        return targets.sorted { $0.name < $1.name }
    }

    private func swiftPackageTargets(in root: URL) throws -> [ComplexitySourceTarget] {
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

        let nonTestTypes: Set<String> = ["regular", "executable", "macro", "plugin", "system"]
        var targets: [ComplexitySourceTarget] = []
        for target in targetObjects {
            guard let name = target["name"] as? String,
                  let type = target["type"] as? String,
                  nonTestTypes.contains(type) else { continue }

            let sourceRoot = (target["path"] as? String) ?? defaultSourceRoot(forTargetNamed: name, root: root)
            guard !sourceRoot.split(separator: "/").contains("Tests") else { continue }
            let files = swiftFiles(under: root.appendingPathComponent(sourceRoot), root: root)
            guard !files.isEmpty else { continue }
            targets.append(ComplexitySourceTarget(name: name, sourceRoot: sourceRoot, files: files))
        }
        return targets
    }

    private func defaultSourceRoot(forTargetNamed name: String, root: URL) -> String {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("Targets/\(name)/Sources").path) {
            return "Targets/\(name)/Sources"
        }
        return "Sources/\(name)"
    }

    private func alignedLayoutTargets(in root: URL) throws -> [ComplexitySourceTarget] {
        let targetsRoot = root.appendingPathComponent("Targets")
        guard FileManager.default.fileExists(atPath: targetsRoot.path) else { return [] }
        let children = try FileManager.default.contentsOfDirectory(at: targetsRoot, includingPropertiesForKeys: [.isDirectoryKey])
        var targets: [ComplexitySourceTarget] = []
        for child in children where child.hasDirectoryPath {
            let sourceRoot = "Targets/\(child.lastPathComponent)/Sources"
            let files = swiftFiles(under: root.appendingPathComponent(sourceRoot), root: root)
            guard !files.isEmpty else { continue }
            targets.append(ComplexitySourceTarget(name: child.lastPathComponent, sourceRoot: sourceRoot, files: files))
        }
        return targets
    }

    private func swiftFiles(under url: URL, root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var files: [String] = []
        for case let file as URL in enumerator {
            let relativePath = relativePath(from: root, to: file)
            let parts = relativePath.split(separator: "/").map(String.init)
            if parts.contains(where: { excludedDirs.contains($0) || $0 == "Tests" }) {
                if file.hasDirectoryPath { enumerator.skipDescendants() }
                continue
            }
            guard file.pathExtension == "swift" else { continue }
            files.append(relativePath)
        }
        return files.sorted()
    }
}

// MARK: - Analyzer

public struct ComplexityAnalyzer: Sendable {
    public var configuration: ComplexityMetricConfiguration
    public var sourceCollector: ComplexitySourceCollector

    public init(
        configuration: ComplexityMetricConfiguration = ComplexityMetricConfiguration(),
        sourceCollector: ComplexitySourceCollector = ComplexitySourceCollector()
    ) {
        self.configuration = configuration
        self.sourceCollector = sourceCollector
    }

    public func analyze(root: URL) throws -> ComplexityReport {
        let root = root.standardizedFileURL
        let targets = try sourceCollector.collect(in: root)
        let targetByFile = Dictionary(uniqueKeysWithValues: targets.flatMap { target in
            target.files.map { ($0, target) }
        })

        var fileReports: [ComplexityFileReport] = []
        for relativePath in targetByFile.keys.sorted() {
            guard let target = targetByFile[relativePath] else { continue }
            let url = root.appendingPathComponent(relativePath)
            let report = try analyzeFile(url: url, root: root, relativePath: relativePath, target: target.name)
            fileReports.append(report)
        }

        let targetReports = targets.map { target in
            let files = fileReports.filter { $0.target == target.name }
            return ComplexityTargetReport(
                name: target.name,
                sourceRoot: target.sourceRoot,
                rawScore: files.map(\.rawScore).reduce(0, +),
                weightedScore: files.map(\.weightedScore).reduce(0, +),
                files: files.count,
                lines: files.map(\.lines).reduce(0, +)
            )
        }.filter { $0.files > 0 }.sorted { $0.name < $1.name }

        let summary = ComplexitySummary(
            rawScore: fileReports.map(\.rawScore).reduce(0, +),
            weightedScore: fileReports.map(\.weightedScore).reduce(0, +),
            targets: targetReports.count,
            files: fileReports.count,
            lines: fileReports.map(\.lines).reduce(0, +)
        )

        return ComplexityReport(
            root: root.path,
            configuration: configuration,
            summary: summary,
            targets: targetReports,
            files: fileReports
        )
    }

    public func analyzeFile(url: URL, root: URL, relativePath: String, target: String) throws -> ComplexityFileReport {
        let source = try String(contentsOf: url, encoding: .utf8)
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: relativePath, tree: tree)
        let visitor = ComplexitySyntaxVisitor(
            configuration: configuration,
            sourceLocationConverter: converter
        )
        visitor.walk(tree)
        return visitor.fileReport(
            path: relativePath,
            target: target,
            lines: countLines(source)
        )
    }
}

private final class ComplexitySyntaxVisitor: SyntaxVisitor {
    struct Context {
        var multiplier: Double
        var multipliers: [String: Double]
    }

    let configuration: ComplexityMetricConfiguration
    let sourceLocationConverter: SourceLocationConverter
    var contexts: [Context] = [Context(multiplier: 1, multipliers: [:])]
    var callableDepth = 0
    var declarations: [ComplexityDeclarationReport] = []
    var eventsByLine: [Int: [ComplexityEvent]] = [:]

    init(configuration: ComplexityMetricConfiguration, sourceLocationConverter: SourceLocationConverter) {
        self.configuration = configuration
        self.sourceLocationConverter = sourceLocationConverter
        super.init(viewMode: .sourceAccurate)
    }

    var currentContext: Context { contexts.last ?? Context(multiplier: 1, multipliers: [:]) }

    func fileReport(path: String, target: String, lines: Int) -> ComplexityFileReport {
        let lineComplexity = eventsByLine.keys.sorted().map { line in
            let events = eventsByLine[line, default: []]
            return LineComplexity(
                line: line,
                rawScore: events.map(\.rawScore).reduce(0, +),
                weightedScore: events.map(\.weightedScore).reduce(0, +),
                events: events
            )
        }
        return ComplexityFileReport(
            path: path,
            target: target,
            rawScore: lineComplexity.map(\.rawScore).reduce(0, +),
            weightedScore: lineComplexity.map(\.weightedScore).reduce(0, +),
            lines: lines,
            declarations: declarations,
            lineComplexity: lineComplexity
        )
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let isFinal = hasModifier("final", in: node.modifiers)
        enterType(
            node,
            kind: isFinal ? "final_class" : "non_final_class",
            labelKind: isFinal ? "final class" : "class",
            name: node.name.text,
            access: accessLevel(from: node.modifiers)
        )
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        contexts.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node, kind: "actor", labelKind: "actor", name: node.name.text, access: accessLevel(from: node.modifiers))
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        contexts.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node, kind: "struct", labelKind: "struct", name: node.name.text, access: accessLevel(from: node.modifiers))
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        contexts.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node, kind: "enum", labelKind: "enum", name: node.name.text, access: accessLevel(from: node.modifiers))
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        contexts.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node, kind: "protocol", labelKind: "protocol", name: node.name.text, access: accessLevel(from: node.modifiers))
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        contexts.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = accessLevel(from: node.modifiers)
        let accessMultiplier = configuration.accessMultiplier(access)
        let typeMultiplier = configuration.typeKindMultiplier("extension")
        let multipliers = currentContext.multipliers
            .merging(["access": accessMultiplier, "kind": typeMultiplier]) { _, rhs in rhs }
        let multiplier = currentContext.multiplier * accessMultiplier * typeMultiplier
        addDeclaration(
            syntax: node,
            kind: "extension",
            name: node.extendedType.trimmedDescription,
            access: access,
            rawScore: configuration.declarationScore,
            multiplier: multiplier,
            multipliers: multipliers
        )
        contexts.append(Context(multiplier: multiplier, multipliers: multipliers))
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        contexts.removeLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        enterCallable(
            node,
            kind: "function",
            name: node.name.text,
            access: accessLevel(from: node.modifiers),
            async: node.signature.effectSpecifiers?.asyncSpecifier != nil,
            throwsKind: throwsKind(from: node.signature.effectSpecifiers)
        )
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        exitCallable()
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        enterCallable(
            node,
            kind: "initializer",
            name: "init",
            access: accessLevel(from: node.modifiers),
            async: node.signature.effectSpecifiers?.asyncSpecifier != nil,
            throwsKind: throwsKind(from: node.signature.effectSpecifiers)
        )
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        exitCallable()
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        enterCallable(
            node,
            kind: "subscript",
            name: "subscript",
            access: accessLevel(from: node.modifiers),
            async: false,
            throwsKind: nil
        )
        return .visitChildren
    }

    override func visitPost(_ node: SubscriptDeclSyntax) {
        exitCallable()
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = accessLevel(from: node.modifiers)
        let isVar = node.bindingSpecifier.text == "var"
        if callableDepth > 0 {
            let raw = isVar ? configuration.localVarScore : configuration.localLetScore
            let multipliers = currentContext.multipliers.merging(["local": 1]) { _, rhs in rhs }
            for binding in node.bindings {
                let name = binding.pattern.trimmedDescription
                addDeclaration(
                    syntax: binding,
                    kind: isVar ? "local_var" : "local_let",
                    name: name,
                    access: access,
                    rawScore: raw,
                    multiplier: currentContext.multiplier,
                    multipliers: multipliers,
                    label: "local \(node.bindingSpecifier.text) \(name)"
                )
            }
            return .visitChildren
        }

        let propertyRaw = isVar ? configuration.varPropertyScore : configuration.letPropertyScore
        let accessMultiplier = configuration.accessMultiplier(access)
        for binding in node.bindings {
            let isComputed = binding.accessorBlock != nil
            let storageMultiplier = isComputed ? configuration.computedPropertyMultiplier : configuration.storedPropertyMultiplier
            let multiplier = currentContext.multiplier * accessMultiplier * storageMultiplier
            let multipliers = currentContext.multipliers.merging([
                "access": accessMultiplier,
                "storage": storageMultiplier,
            ]) { _, rhs in rhs }
            let name = binding.pattern.trimmedDescription
            addDeclaration(
                syntax: binding,
                kind: isVar ? "var" : "let",
                name: name,
                access: access,
                rawScore: propertyRaw,
                multiplier: multiplier,
                multipliers: multipliers,
                label: "\(access) \(node.bindingSpecifier.text) \(name)\(isComputed ? " { get }" : "")"
            )
        }
        return .visitChildren
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        let raw = configuration.declarationScore
        let multiplier = currentContext.multiplier
        addEvent(syntax: node, kind: "accessor", label: node.accessorSpecifier.text, rawScore: raw, multiplier: multiplier, multipliers: currentContext.multipliers)
        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        let raw = configuration.closureScore
        addEvent(syntax: node, kind: "closure", label: "closure", rawScore: raw, multiplier: currentContext.multiplier, multipliers: currentContext.multipliers)
        callableDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        callableDepth = max(0, callableDepth - 1)
    }

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        addDecision(node, kind: "if", label: "if")
        return .visitChildren
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        addDecision(node, kind: "guard", label: "guard")
        return .visitChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        addDecision(node, kind: "for", label: "for")
        return .visitChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        addDecision(node, kind: "while", label: "while")
        return .visitChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        addDecision(node, kind: "repeat", label: "repeat")
        return .visitChildren
    }

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        addDecision(node, kind: "switch", label: "switch")
        return .visitChildren
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        switch node.label {
        case .case:
            addDecision(node, kind: "case", label: "case")
        case .default:
            break
        }
        return .visitChildren
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        addDecision(node, kind: "catch", label: "catch")
        return .visitChildren
    }

    override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
        addDecision(node, kind: "ternary", label: "?:")
        return .visitChildren
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark != nil {
            addDecision(node, kind: "try", label: node.questionOrExclamationMark?.text == "!" ? "try!" : "try?")
        }
        return .visitChildren
    }

    override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
        let text = node.text
        if text == "&&" || text == "||" {
            addDecision(node, kind: "logical_operator", label: text)
        }
        return .visitChildren
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }

    private func enterType<T: SyntaxProtocol>(
        _ node: T,
        kind: String,
        labelKind: String,
        name: String,
        access: String
    ) {
        let accessMultiplier = configuration.accessMultiplier(access)
        let typeMultiplier = configuration.typeKindMultiplier(kind)
        let multipliers = currentContext.multipliers.merging([
            "access": accessMultiplier,
            "kind": typeMultiplier,
        ]) { _, rhs in rhs }
        let multiplier = currentContext.multiplier * accessMultiplier * typeMultiplier
        addDeclaration(
            syntax: node,
            kind: labelKind,
            name: name,
            access: access,
            rawScore: configuration.declarationScore,
            multiplier: multiplier,
            multipliers: multipliers,
            label: "\(access) \(labelKind) \(name)"
        )
        contexts.append(Context(multiplier: currentContext.multiplier * typeMultiplier, multipliers: currentContext.multipliers.merging(["type_kind": typeMultiplier]) { _, rhs in rhs }))
    }

    private func enterCallable<T: SyntaxProtocol>(
        _ node: T,
        kind: String,
        name: String,
        access: String,
        async: Bool,
        throwsKind: String?
    ) {
        let accessMultiplier = configuration.accessMultiplier(access)
        let effect = configuration.methodEffectMultiplier(async: async, throwsKind: throwsKind)
        let multiplier = currentContext.multiplier * accessMultiplier * effect.value
        let multipliers = currentContext.multipliers.merging([
            "access": accessMultiplier,
            "effects": effect.value,
        ]) { _, rhs in rhs }
        addDeclaration(
            syntax: node,
            kind: kind,
            name: name,
            access: access,
            rawScore: configuration.declarationScore,
            multiplier: multiplier,
            multipliers: multipliers,
            label: "\(access) \(kind) \(name)\(effect.key == "plain" ? "" : " [\(effect.key)]")"
        )
        contexts.append(Context(multiplier: multiplier, multipliers: multipliers))
        callableDepth += 1
    }

    private func exitCallable() {
        contexts.removeLast()
        callableDepth = max(0, callableDepth - 1)
    }

    private func addDecision<T: SyntaxProtocol>(_ node: T, kind: String, label: String) {
        addEvent(
            syntax: node,
            kind: kind,
            label: label,
            rawScore: configuration.decisionScore,
            multiplier: currentContext.multiplier,
            multipliers: currentContext.multipliers
        )
    }

    private func addDeclaration<T: SyntaxProtocol>(
        syntax: T,
        kind: String,
        name: String,
        access: String,
        rawScore: Double,
        multiplier: Double,
        multipliers: [String: Double],
        label: String? = nil
    ) {
        let start = startLine(of: syntax)
        let end = endLine(of: syntax)
        let weighted = rawScore * multiplier
        declarations.append(ComplexityDeclarationReport(
            kind: kind,
            name: name,
            access: access,
            startLine: start,
            endLine: end,
            rawScore: rawScore,
            weightedScore: weighted,
            multipliers: multipliers
        ))
        eventsByLine[start, default: []].append(ComplexityEvent(
            kind: "declaration",
            label: label ?? "\(access) \(kind) \(name)",
            rawScore: rawScore,
            weightedScore: weighted,
            multipliers: multipliers
        ))
    }

    private func addEvent<T: SyntaxProtocol>(
        syntax: T,
        kind: String,
        label: String,
        rawScore: Double,
        multiplier: Double,
        multipliers: [String: Double]
    ) {
        let weighted = rawScore * multiplier
        eventsByLine[startLine(of: syntax), default: []].append(ComplexityEvent(
            kind: kind,
            label: label,
            rawScore: rawScore,
            weightedScore: weighted,
            multipliers: multipliers
        ))
    }

    private func startLine<T: SyntaxProtocol>(of node: T) -> Int {
        sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }

    private func endLine<T: SyntaxProtocol>(of node: T) -> Int {
        sourceLocationConverter.location(for: node.endPositionBeforeTrailingTrivia).line
    }
}

private func accessLevel(from modifiers: DeclModifierListSyntax) -> String {
    for modifier in modifiers {
        let name = modifier.name.text
        if ["open", "public", "package", "internal", "fileprivate", "private"].contains(name) {
            return name
        }
    }
    return "internal"
}

private func hasModifier(_ expected: String, in modifiers: DeclModifierListSyntax) -> Bool {
    modifiers.contains { $0.name.text == expected }
}

private func throwsKind(from effectSpecifiers: FunctionEffectSpecifiersSyntax?) -> String? {
    guard let throwsSpecifier = effectSpecifiers?.throwsClause?.throwsSpecifier else { return nil }
    let text = throwsSpecifier.text
    if text == "rethrows" { return "rethrows" }
    return "throws"
}

private func countLines(_ source: String) -> Int {
    guard !source.isEmpty else { return 0 }
    let count = source.split(separator: "\n", omittingEmptySubsequences: false).count
    return source.hasSuffix("\n") ? max(0, count - 1) : count
}

private func relativePath(from root: URL, to file: URL) -> String {
    let rootPath = root.standardizedFileURL.path
    let filePath = file.standardizedFileURL.path
    if filePath == rootPath { return "" }
    if filePath.hasPrefix(rootPath + "/") {
        return String(filePath.dropFirst(rootPath.count + 1))
    }
    return filePath
}
