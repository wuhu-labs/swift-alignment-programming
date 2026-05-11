import Foundation

// MARK: - SVG Bar Generator

/// Generate an alignment status SVG bar chart.
public struct SVGBarGenerator: Sendable {

    public init() {}

    /// Generate an SVG string for the given alignment score.
    public func generate(score: AlignmentScore, width: Int = 720, height: Int = 90) -> String {
        let barHeight = 44
        let padding = 8
        let innerWidth = width - padding * 2
        let barY = 12
        var x = padding

        var segments: [String] = []

        for (index, grade) in AlignmentGrade.allCases.enumerated() {
            let loc = score.grades[grade, default: 0]
            guard score.totalLOC > 0 else {
                segments.append(makeSegment(x: x, grade: grade, width: innerWidth, barHeight: barHeight, label: "\(grade.rawValue) 100%"))
                break
            }

            let segmentWidth: Int
            if index == AlignmentGrade.allCases.count - 1 {
                segmentWidth = width - padding - x
            } else {
                segmentWidth = Int((Double(innerWidth) * Double(loc) / Double(score.totalLOC)).rounded())
            }
            guard segmentWidth > 0 else { continue }

            let pct = Int((Double(loc) / Double(score.totalLOC) * 100).rounded())
            var text = ""
            if segmentWidth >= 52 {
                text = """
                <text x="\(x + segmentWidth / 2)" y="37" \
                font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif" \
                font-size="14" font-weight="700" text-anchor="middle" fill="\(grade.textColor)">\(grade.rawValue) \(pct)%</text>
                """
            }
            segments.append("""
            <rect x="\(x)" y="\(barY)" width="\(segmentWidth)" height="\(barHeight)" fill="\(grade.color)" rx="6" ry="6" />\(text)
            """)
            x += segmentWidth
        }

        let totalLOCFormatted = formatInt(score.totalLOC)

        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)" role="img" aria-labelledby="title desc">
          <title id="title">Alignment status</title>
          <desc id="desc">Alignment score \(score.score) percent. LOC distribution across grades A, B, C, and D.</desc>
          <rect x="8" y="\(barY)" width="\(innerWidth)" height="\(barHeight)" rx="6" ry="6" fill="#111827" stroke="#374151" />
          \(segments.joined(separator: "\n          "))
          <text x="8" y="78" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif" font-size="13" fill="#6B7280">Score \(score.score)% • Tracked Swift LOC \(totalLOCFormatted)</text>
        </svg>
        """
    }

    private func makeSegment(x: Int, grade: AlignmentGrade, width: Int, barHeight: Int, label: String) -> String {
        """
        <rect x="\(x)" y="12" width="\(width)" height="\(barHeight)" fill="\(grade.color)" rx="6" ry="6" />
        <text x="\(x + width / 2)" y="37" \
        font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif" \
        font-size="14" font-weight="700" text-anchor="middle" fill="\(grade.textColor)">\(label)</text>
        """
    }

    private func formatInt(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
