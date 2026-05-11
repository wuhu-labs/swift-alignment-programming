import Foundation

// MARK: - Symbol Graph JSON Model

/// Top-level symbol graph file (one per module + per extension module).
/// See: https://github.com/swiftlang/swift/blob/main/docs/ABI/StabilityManifest.md
struct SymbolGraph: Decodable {
    struct Metadata: Decodable {
        struct FormatVersion: Decodable {
            let major: Int
            let minor: Int?
        }
        let formatVersion: FormatVersion
    }

    struct Module: Decodable {
        let name: String
    }

    struct Symbol: Decodable {
        struct Kind: Decodable {
            let identifier: String
        }

        struct Identifier: Decodable {
            let precise: String
        }

        struct Location: Decodable {
            let uri: String?
        }

        struct SwiftExtension: Decodable {
            let extendedModule: String?
            let typeKind: String?
            let constraints: [Constraint]?

            struct Constraint: Decodable {
                let kind: String?
                let lhs: String?
                let rhs: String?
            }
        }

        struct AvailabilityEntry: Decodable {
            let domain: String?
            let introduced: Version?
            let deprecated: Version?
            let obsoleted: Version?

            struct Version: Decodable {
                let major: Int
                let minor: Int?
                let patch: Int?
            }
        }

        let kind: Kind
        let identifier: Identifier
        let pathComponents: [String]?
        let accessLevel: String?
        let declarationFragments: [DeclarationFragment]?
        let swiftExtension: SwiftExtension?
        let location: Location?
        let availability: [AvailabilityEntry]?
    }

    struct DeclarationFragment: Decodable {
        let kind: String?
        let spelling: String?
    }

    struct Relationship: Decodable {
        let kind: String?
        let source: String?
        let target: String?
        let targetFallback: String?
    }

    let metadata: Metadata
    let module: Module
    let symbols: [Symbol]
    let relationships: [Relationship]?
}
