import Foundation

// MARK: - Alignment Types

public enum AlignmentGrade: String, CaseIterable, Sendable, Comparable {
    case A, B, C, D

    public static func < (lhs: AlignmentGrade, rhs: AlignmentGrade) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    public var score: Int {
        switch self {
        case .A: 100
        case .B: 66
        case .C: 33
        case .D: 0
        }
    }

    public var color: String {
        switch self {
        case .A: "#7DD3FC"
        case .B: "#22C55E"
        case .C: "#FACC15"
        case .D: "#EF4444"
        }
    }

    public var textColor: String {
        switch self {
        case .A: "#082F49"
        case .B: "#052E16"
        case .C: "#422006"
        case .D: "#FFFFFF"
        }
    }
}

/// One source file with its alignment grade and LOC.
public struct FileStat: Sendable {
    public let path: String
    public let grade: AlignmentGrade
    public let loc: Int

    public init(path: String, grade: AlignmentGrade, loc: Int) {
        self.path = path
        self.grade = grade
        self.loc = loc
    }
}

/// Alignment score summary for a package or repo.
public struct AlignmentScore: Sendable {
    public let score: Int
    public let totalLOC: Int
    public let grades: [AlignmentGrade: Int]

    public init(score: Int, totalLOC: Int, grades: [AlignmentGrade: Int]) {
        self.score = score
        self.totalLOC = totalLOC
        self.grades = grades
    }

    /// Compute score from file stats.
    public static func compute(from stats: [FileStat]) -> AlignmentScore {
        var totals: [AlignmentGrade: Int] = [:]
        for grade in AlignmentGrade.allCases {
            totals[grade] = 0
        }
        var totalLOC = 0
        for stat in stats {
            totals[stat.grade, default: 0] += stat.loc
            totalLOC += stat.loc
        }
        let weighted = totals.reduce(0) { $0 + $1.value * $1.key.score }
        let score = totalLOC > 0 ? Int((Double(weighted) / Double(totalLOC)).rounded()) : 0
        return AlignmentScore(score: score, totalLOC: totalLOC, grades: totals)
    }
}

// MARK: - Grade Collector

/// Scans a directory tree for `.alignment` files and computes LOC per grade.
public struct GradeCollector: Sendable {
    /// Directories to skip during scanning.
    public var excludedDirs: Set<String>

    public init(excludedDirs: Set<String> = [".git", ".build", ".swiftpm", ".ci", "interfaces"]) {
        self.excludedDirs = excludedDirs
    }

    /// Walk `root` and collect alignment stats for all Swift source files.
    /// Returns FileStat values keyed by the package/target they belong to.
    public func collect(in root: URL) throws -> [String: [FileStat]] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw AlignmentError.notADirectory(root.path)
        }

        var statsByTarget: [String: [FileStat]] = [:]

        for case let fileURL as URL in enumerator {
            // Skip excluded directories
            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            let parts = relativePath.split(separator: "/").map(String.init)
            if parts.contains(where: { excludedDirs.contains($0) }) {
                if fileURL.hasDirectoryPath {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard fileURL.pathExtension == "swift" || fileURL.lastPathComponent == "Package.swift" else { continue }

            let loc = try countLOC(fileURL)
            guard loc > 0 else { continue }

            let grade = try gradeForFile(fileURL, root: root)
            let groupKey = groupKeyForFile(relativePath)

            statsByTarget[groupKey, default: []].append(
                FileStat(path: relativePath, grade: grade, loc: loc)
            )
        }

        return statsByTarget
    }

    /// Compute a single score for the whole tree (legacy aggregate).
    public func collectFlat(in root: URL) throws -> AlignmentScore {
        let allStats = try collect(in: root).values.flatMap { $0 }
        return AlignmentScore.compute(from: allStats)
    }

    // MARK: - Internal

    private func countLOC(_ url: URL) throws -> Int {
        let content = try String(contentsOf: url, encoding: .utf8)
        return content.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    private func gradeForFile(_ fileURL: URL, root: URL) throws -> AlignmentGrade {
        var dir = fileURL.deletingLastPathComponent()
        while dir.path.hasPrefix(root.path) {
            let marker = dir.appendingPathComponent(".alignment")
            if fm.fileExists(atPath: marker.path) {
                let content = try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard let grade = AlignmentGrade(rawValue: content) else {
                    throw AlignmentError.invalidGrade(content, marker.path)
                }
                return grade
            }
            if dir.path == root.path { break }
            dir = dir.deletingLastPathComponent()
        }
        return .D  // default: ungraded = D
    }

    private var fm: FileManager { FileManager.default }

    private func groupKeyForFile(_ relativePath: String) -> String {
        // Extract package/target from path like "Packages/Jiuzi/Targets/JiuziAI/Sources/..."
        let parts = relativePath.split(separator: "/").map(String.init)
        if let pkgIdx = parts.firstIndex(of: "Packages"), pkgIdx + 1 < parts.count {
            let pkg = parts[pkgIdx + 1]
            if let targetsIdx = parts.firstIndex(of: "Targets"), targetsIdx + 1 < parts.count {
                return "\(pkg)/\(parts[targetsIdx + 1])"
            }
            return pkg
        }
        // For standalone packages: use first directory as group
        if let first = parts.first, !first.hasSuffix(".swift") {
            return first
        }
        return "root"
    }
}

// MARK: - Errors

public enum AlignmentError: Error {
    case notADirectory(String)
    case invalidGrade(String, String)
    case noAlignmentFiles(String)
}

extension AlignmentError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notADirectory(let path):
            "Not a directory: \(path)"
        case .invalidGrade(let grade, let path):
            "Invalid alignment grade '\(grade)' in \(path)"
        case .noAlignmentFiles(let path):
            "No .alignment files found under \(path)"
        }
    }
}
