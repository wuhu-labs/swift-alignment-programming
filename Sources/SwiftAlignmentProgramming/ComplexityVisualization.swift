import Foundation

// MARK: - Complexity summary rendering

public enum ComplexitySummaryGrouping: String, CaseIterable, Sendable {
    case target
    case file
    case tree
}

public struct ComplexitySummaryRenderer: Sendable {
    public init() {}

    public func render(report: ComplexityReport, grouping: ComplexitySummaryGrouping, top: Int = 40) -> String {
        switch grouping {
        case .target:
            renderTargets(report: report, top: top)
        case .file:
            renderFiles(report: report, top: top)
        case .tree:
            renderTree(report: report, top: top)
        }
    }

    private func renderTargets(report: ComplexityReport, top: Int) -> String {
        let rows = report.targets.sorted { lhs, rhs in
            if lhs.weightedScore == rhs.weightedScore { return lhs.name < rhs.name }
            return lhs.weightedScore > rhs.weightedScore
        }.prefix(top)
        var lines = headerLines(report: report, label: "Per-target complexity")
        for row in rows {
            lines.append(summaryLine(
                label: row.name,
                raw: row.rawScore,
                weighted: row.weightedScore,
                lines: row.lines,
                maxValue: report.targets.map(\.weightedScore).max() ?? row.weightedScore
            ))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderFiles(report: ComplexityReport, top: Int) -> String {
        let rows = report.files.sorted { lhs, rhs in
            if lhs.weightedScore == rhs.weightedScore { return lhs.path < rhs.path }
            return lhs.weightedScore > rhs.weightedScore
        }.prefix(top)
        var lines = headerLines(report: report, label: "Per-file complexity")
        for row in rows {
            lines.append(summaryLine(
                label: row.path,
                raw: row.rawScore,
                weighted: row.weightedScore,
                lines: row.lines,
                maxValue: report.files.map(\.weightedScore).max() ?? row.weightedScore
            ))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderTree(report: ComplexityReport, top: Int) -> String {
        let tree = ComplexityTreemapBuilder().build(report: report)
        var lines = headerLines(report: report, label: "Complexity tree")
        lines.append("\(tree.name)  weighted=\(format(tree.weightedScore)) raw=\(format(tree.rawScore))")
        let sortedChildren = tree.children.sorted { $0.weightedScore > $1.weightedScore }.prefix(top)
        for (index, child) in sortedChildren.enumerated() {
            appendTree(child, prefix: "", isLast: index == sortedChildren.count - 1, lines: &lines)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func appendTree(_ node: ComplexityTreeNode, prefix: String, isLast: Bool, lines: inout [String]) {
        let connector = isLast ? "└─ " : "├─ "
        lines.append("\(prefix)\(connector)\(node.name)  weighted=\(format(node.weightedScore)) raw=\(format(node.rawScore))")
        let childPrefix = prefix + (isLast ? "   " : "│  ")
        let children = node.children.sorted { $0.weightedScore > $1.weightedScore }
        for (index, child) in children.enumerated() {
            appendTree(child, prefix: childPrefix, isLast: index == children.count - 1, lines: &lines)
        }
    }

    private func headerLines(report: ComplexityReport, label: String) -> [String] {
        [
            label,
            String(repeating: "=", count: label.count),
            "weighted=\(format(report.summary.weightedScore)) raw=\(format(report.summary.rawScore)) targets=\(report.summary.targets) files=\(report.summary.files) lines=\(report.summary.lines)",
            "",
        ]
    }

    private func summaryLine(label: String, raw: Double, weighted: Double, lines: Int, maxValue: Double) -> String {
        let barWidth = 28
        let filled = maxValue > 0 ? Int((weighted / maxValue * Double(barWidth)).rounded()) : 0
        let bar = String(repeating: "█", count: Swift.max(0, Swift.min(barWidth, filled)))
            + String(repeating: "░", count: Swift.max(0, barWidth - filled))
        return "\(bar)  weighted=\(padded(format(weighted), width: 8)) raw=\(padded(format(raw), width: 7)) lines=\(padded(String(lines), width: 5))  \(label)"
    }
}

// MARK: - Complexity tree

public struct ComplexityTreeNode: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var rawScore: Double
    public var weightedScore: Double
    public var files: Int
    public var lines: Int
    public var children: [ComplexityTreeNode]

    public init(name: String, path: String, rawScore: Double, weightedScore: Double, files: Int, lines: Int, children: [ComplexityTreeNode]) {
        self.name = name
        self.path = path
        self.rawScore = rawScore
        self.weightedScore = weightedScore
        self.files = files
        self.lines = lines
        self.children = children
    }
}

public struct ComplexityTreemapBuilder: Sendable {
    public init() {}

    public func build(report: ComplexityReport) -> ComplexityTreeNode {
        let root = MutableTreeNode(name: URL(fileURLWithPath: report.root).lastPathComponent, path: "")
        for file in report.files {
            let components = treeComponents(for: file)
            root.insert(components: components, file: file)
        }
        return root.frozen()
    }

    private func treeComponents(for file: ComplexityFileReport) -> [String] {
        var path = file.path
        let prefix = "Targets/\(file.target)/Sources/"
        if path.hasPrefix(prefix) {
            path = String(path.dropFirst(prefix.count))
        } else if path.hasPrefix("Sources/\(file.target)/") {
            path = String(path.dropFirst("Sources/\(file.target)/".count))
        }
        return [file.target] + path.split(separator: "/").map(String.init)
    }
}

private final class MutableTreeNode {
    var name: String
    var path: String
    var rawScore: Double = 0
    var weightedScore: Double = 0
    var files: Int = 0
    var lines: Int = 0
    var children: [String: MutableTreeNode] = [:]

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    func insert(components: [String], file: ComplexityFileReport) {
        rawScore += file.rawScore
        weightedScore += file.weightedScore
        files += 1
        lines += file.lines
        guard let head = components.first else { return }
        let childPath = path.isEmpty ? head : path + "/" + head
        let child = children[head] ?? MutableTreeNode(name: head, path: childPath)
        children[head] = child
        child.insert(components: Array(components.dropFirst()), file: file)
    }

    func frozen() -> ComplexityTreeNode {
        ComplexityTreeNode(
            name: name,
            path: path,
            rawScore: rawScore,
            weightedScore: weightedScore,
            files: files,
            lines: lines,
            children: children.values.map { $0.frozen() }.sorted {
                if $0.weightedScore == $1.weightedScore { return $0.name < $1.name }
                return $0.weightedScore > $1.weightedScore
            }
        )
    }
}

// MARK: - Dashboard HTML

public struct ComplexityDashboardHTMLGenerator: Sendable {
    public init() {}

    public func generate(report: ComplexityReport, title: String) throws -> String {
        let tree = ComplexityTreemapBuilder().build(report: report)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let treeJSON = String(data: try encoder.encode(tree), encoding: .utf8) ?? "{}"
        let fileJSON = String(data: try encoder.encode(report.files.sorted { $0.weightedScore > $1.weightedScore }), encoding: .utf8) ?? "[]"
        let targetRows = report.targets.sorted { $0.weightedScore > $1.weightedScore }.map { target in
            """
            <tr><td>\(escapeHTML(target.name))</td><td>\(format(target.weightedScore))</td><td>\(format(target.rawScore))</td><td>\(target.files)</td><td>\(target.lines)</td></tr>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(title)) · complexity</title>
          <style>
            :root { color-scheme: dark; }
            body { margin: 0; padding: 28px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif; background: #080b12; color: #e5e7eb; }
            h1 { margin: 0; font-size: 28px; }
            h2 { margin: 32px 0 12px; font-size: 16px; color: #cbd5e1; }
            .subtitle { color: #64748b; margin-top: 6px; }
            .cards { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; margin: 24px 0; }
            .card { background: #111827; border: 1px solid #1f2937; border-radius: 12px; padding: 16px; }
            .card .label { color: #94a3b8; font-size: 12px; text-transform: uppercase; letter-spacing: .08em; }
            .card .value { font-size: 26px; margin-top: 8px; font-weight: 650; }
            table { width: 100%; border-collapse: collapse; font-size: 13px; }
            th, td { border-bottom: 1px solid #1f2937; padding: 8px 10px; text-align: left; }
            th { color: #94a3b8; font-weight: 500; text-transform: uppercase; font-size: 11px; letter-spacing: .06em; }
            #treemap { position: relative; height: 620px; background: #020617; border: 1px solid #1f2937; border-radius: 14px; overflow: hidden; }
            .node { position: absolute; box-sizing: border-box; border: 1px solid rgba(15, 23, 42, .9); overflow: hidden; border-radius: 7px; padding: 6px; color: white; cursor: default; }
            .node:hover { outline: 2px solid #7dd3fc; z-index: 10; }
            .node .name { font-weight: 650; font-size: 12px; text-shadow: 0 1px 2px rgba(0,0,0,.6); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
            .node .metric { font-size: 11px; opacity: .85; margin-top: 2px; }
            input { width: 100%; box-sizing: border-box; background: #020617; color: #e5e7eb; border: 1px solid #334155; border-radius: 8px; padding: 10px; margin: 0 0 12px; }
            @media (max-width: 860px) { .cards { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
          </style>
        </head>
        <body>
          <h1>\(escapeHTML(title))</h1>
          <div class="subtitle">Swift-oriented weighted complexity. Scores are intentionally decomposed into raw and weighted values for later metric tuning.</div>
          <section class="cards">
            <div class="card"><div class="label">Weighted</div><div class="value">\(format(report.summary.weightedScore))</div></div>
            <div class="card"><div class="label">Raw</div><div class="value">\(format(report.summary.rawScore))</div></div>
            <div class="card"><div class="label">Targets</div><div class="value">\(report.summary.targets)</div></div>
            <div class="card"><div class="label">Files</div><div class="value">\(report.summary.files)</div></div>
          </section>

          <h2>Treemap</h2>
          <div id="treemap" aria-label="Complexity treemap"></div>

          <h2>Targets</h2>
          <table><thead><tr><th>Target</th><th>Weighted</th><th>Raw</th><th>Files</th><th>Lines</th></tr></thead><tbody>
          \(targetRows)
          </tbody></table>

          <h2>Files</h2>
          <input id="filter" placeholder="Filter files or targets…">
          <table><thead><tr><th>File</th><th>Target</th><th>Weighted</th><th>Raw</th><th>Lines</th></tr></thead><tbody id="files"></tbody></table>

          <script>
            const tree = \(treeJSON);
            const files = \(fileJSON);
            const fmt = new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 });
            function color(depth, value, max) {
              const hue = (215 + depth * 31) % 360;
              const lightness = 22 + Math.min(26, (value / Math.max(max, 1)) * 26);
              return `hsl(${hue} 72% ${lightness}%)`;
            }
            function layout(children, x, y, w, h) {
              const total = children.reduce((sum, child) => sum + child.weightedScore, 0) || 1;
              let cursor = 0;
              const horizontal = w >= h;
              return children.map((child, index) => {
                const share = child.weightedScore / total;
                let rect;
                if (horizontal) {
                  const cw = index === children.length - 1 ? w - cursor : w * share;
                  rect = { node: child, x: x + cursor, y, w: cw, h };
                  cursor += cw;
                } else {
                  const ch = index === children.length - 1 ? h - cursor : h * share;
                  rect = { node: child, x, y: y + cursor, w, h: ch };
                  cursor += ch;
                }
                return rect;
              });
            }
            function draw(node, container, x, y, w, h, depth, max) {
              if (!node.children || node.children.length === 0) return;
              for (const rect of layout(node.children, x, y, w, h)) {
                const el = document.createElement('div');
                el.className = 'node';
                el.style.left = `${rect.x}px`;
                el.style.top = `${rect.y}px`;
                el.style.width = `${Math.max(0, rect.w)}px`;
                el.style.height = `${Math.max(0, rect.h)}px`;
                el.style.background = color(depth, rect.node.weightedScore, max);
                el.title = `${rect.node.path || rect.node.name}\nweighted ${fmt.format(rect.node.weightedScore)} raw ${fmt.format(rect.node.rawScore)}\nfiles ${rect.node.files} lines ${rect.node.lines}`;
                if (rect.w > 82 && rect.h > 34) {
                  el.innerHTML = `<div class="name"></div><div class="metric">${fmt.format(rect.node.weightedScore)}</div>`;
                  el.querySelector('.name').textContent = rect.node.name;
                }
                container.appendChild(el);
                if (rect.w > 130 && rect.h > 90) {
                  draw(rect.node, container, rect.x + 5, rect.y + 28, Math.max(0, rect.w - 10), Math.max(0, rect.h - 33), depth + 1, max);
                }
              }
            }
            function renderTreemap() {
              const container = document.getElementById('treemap');
              container.innerHTML = '';
              draw(tree, container, 0, 0, container.clientWidth, container.clientHeight, 0, tree.weightedScore);
            }
            function renderFiles(filter = '') {
              const needle = filter.toLowerCase();
              const rows = files
                .filter(file => !needle || file.path.toLowerCase().includes(needle) || file.target.toLowerCase().includes(needle))
                .slice(0, 200)
                .map(file => `<tr><td>${escapeHTML(file.path)}</td><td>${escapeHTML(file.target)}</td><td>${fmt.format(file.weightedScore)}</td><td>${fmt.format(file.rawScore)}</td><td>${file.lines}</td></tr>`)
                .join('');
              document.getElementById('files').innerHTML = rows;
            }
            function escapeHTML(value) {
              return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
            }
            window.addEventListener('resize', renderTreemap);
            document.getElementById('filter').addEventListener('input', event => renderFiles(event.target.value));
            renderTreemap();
            renderFiles();
          </script>
        </body>
        </html>
        """
    }
}

// MARK: - Formatting helpers

private func format(_ value: Double) -> String {
    if value.rounded() == value { return String(Int(value)) }
    return String(format: "%.1f", value)
}

private func padded(_ value: String, width: Int) -> String {
    if value.count >= width { return value }
    return String(repeating: " ", count: width - value.count) + value
}

private func escapeHTML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}
