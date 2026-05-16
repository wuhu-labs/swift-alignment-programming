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

private struct ComplexityDashboardFileSummary: Codable {
    var path: String
    var target: String
    var rawScore: Double
    var weightedScore: Double
    var lines: Int

    init(file: ComplexityFileReport) {
        path = file.path
        target = file.target
        rawScore = file.rawScore
        weightedScore = file.weightedScore
        lines = file.lines
    }
}

public struct ComplexityDashboardHTMLGenerator: Sendable {
    public init() {}

    public func generate(report: ComplexityReport, title: String) throws -> String {
        let tree = ComplexityTreemapBuilder().build(report: report)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let treeJSON = String(data: try encoder.encode(tree), encoding: .utf8) ?? "{}"
        let dashboardFiles = report.files
            .sorted { $0.weightedScore > $1.weightedScore }
            .map(ComplexityDashboardFileSummary.init(file:))
        let fileJSON = String(data: try encoder.encode(dashboardFiles), encoding: .utf8) ?? "[]"
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
            #treemap svg { display: block; width: 100%; height: 100%; }
            .treemap-toolbar { display: flex; align-items: center; gap: 10px; margin: -4px 0 10px; color: #94a3b8; font-size: 13px; }
            .treemap-toolbar button { background: #111827; color: #e5e7eb; border: 1px solid #334155; border-radius: 8px; padding: 7px 10px; cursor: pointer; }
            .treemap-toolbar button:disabled { opacity: .45; cursor: default; }
            .breadcrumb a { color: #7dd3fc; cursor: pointer; text-decoration: none; }
            .breadcrumb a:hover { text-decoration: underline; }
            .treemap-node { cursor: zoom-in; }
            .treemap-node.leaf { cursor: pointer; }
            .treemap-node rect { stroke: rgba(2, 6, 23, .88); stroke-width: 1.25; }
            .treemap-node:hover rect { stroke: #7dd3fc; stroke-width: 2.5; }
            .treemap-label { fill: white; font-size: 12px; font-weight: 650; pointer-events: none; text-shadow: 0 1px 2px rgba(0,0,0,.72); }
            .treemap-metric { fill: rgba(255,255,255,.82); font-size: 11px; pointer-events: none; text-shadow: 0 1px 2px rgba(0,0,0,.72); }
            .treemap-empty { padding: 18px; color: #94a3b8; }
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
          <div class="treemap-toolbar">
            <button id="treemap-up" disabled>Back</button>
            <span id="treemap-breadcrumb" class="breadcrumb"></span>
          </div>
          <div id="treemap" aria-label="Complexity treemap"></div>

          <h2>Targets</h2>
          <table><thead><tr><th>Target</th><th>Weighted</th><th>Raw</th><th>Files</th><th>Lines</th></tr></thead><tbody>
          \(targetRows)
          </tbody></table>

          <h2>Files</h2>
          <input id="filter" placeholder="Filter files or targets…">
          <table><thead><tr><th>File</th><th>Target</th><th>Weighted</th><th>Raw</th><th>Lines</th></tr></thead><tbody id="files"></tbody></table>

          <script src="https://cdn.jsdelivr.net/npm/d3@7"></script>
          <script>
            const tree = \(treeJSON);
            const files = \(fileJSON);
            const fmt = new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 });
            let currentPath = [tree];
            function color(depth, value, max) {
              const hue = (214 + depth * 29) % 360;
              const lightness = 22 + Math.min(28, (value / Math.max(max, 1)) * 28);
              return `hsl(${hue} 72% ${lightness}%)`;
            }
            function renderBreadcrumb() {
              const breadcrumb = document.getElementById('treemap-breadcrumb');
              breadcrumb.innerHTML = currentPath.map((node, index) => {
                const label = escapeHTML(node.name || 'root');
                return index === currentPath.length - 1
                  ? `<strong>${label}</strong>`
                  : `<a data-index="${index}">${label}</a>`;
              }).join(' / ');
              breadcrumb.querySelectorAll('a').forEach(anchor => {
                anchor.addEventListener('click', event => {
                  currentPath = currentPath.slice(0, Number(event.currentTarget.dataset.index) + 1);
                  renderTreemap();
                });
              });
              document.getElementById('treemap-up').disabled = currentPath.length <= 1;
            }
            function renderTreemap() {
              const container = document.getElementById('treemap');
              container.innerHTML = '';
              renderBreadcrumb();
              if (!window.d3) {
                container.innerHTML = '<div class="treemap-empty">D3.js failed to load, so the zoomable treemap cannot be rendered.</div>';
                return;
              }
              const current = currentPath[currentPath.length - 1];
              if (!current.children || current.children.length === 0) {
                container.innerHTML = '<div class="treemap-empty">No child nodes to display.</div>';
                return;
              }
              const width = Math.max(1, container.clientWidth);
              const height = Math.max(1, container.clientHeight);
              const root = d3.hierarchy(current)
                .sum(node => node.children && node.children.length ? 0 : Math.max(0, node.weightedScore || 0))
                .sort((a, b) => b.value - a.value || d3.ascending(a.data.name, b.data.name));
              d3.treemap()
                .tile(d3.treemapSquarify.ratio(1.25))
                .size([width, height])
                .paddingOuter(4)
                .paddingInner(3)
                .round(true)(root);

              const svg = d3.select(container)
                .append('svg')
                .attr('viewBox', `0 0 ${width} ${height}`)
                .attr('role', 'img')
                .attr('aria-label', `Complexity treemap zoomed to ${current.name}`);
              const maxValue = root.children ? d3.max(root.children, child => child.value) || 1 : 1;
              const nodes = svg.selectAll('g')
                .data(root.children || [])
                .join('g')
                .attr('class', d => `treemap-node${d.data.children && d.data.children.length ? '' : ' leaf'}`)
                .attr('transform', d => `translate(${d.x0},${d.y0})`)
                .on('click', (event, d) => {
                  event.stopPropagation();
                  if (d.data.children && d.data.children.length) {
                    currentPath.push(d.data);
                    renderTreemap();
                  } else {
                    const filter = d.data.path || d.data.name;
                    document.getElementById('filter').value = filter;
                    renderFiles(filter);
                    document.getElementById('filter').scrollIntoView({ behavior: 'smooth', block: 'center' });
                  }
                });
              nodes.append('title')
                .text(d => `${d.data.path || d.data.name}\nweighted ${fmt.format(d.data.weightedScore)} raw ${fmt.format(d.data.rawScore)}\nfiles ${d.data.files} lines ${d.data.lines}`);
              nodes.append('rect')
                .attr('width', d => Math.max(0, d.x1 - d.x0))
                .attr('height', d => Math.max(0, d.y1 - d.y0))
                .attr('rx', 7)
                .attr('fill', d => color(d.depth + currentPath.length, d.value, maxValue));
              nodes.filter(d => (d.x1 - d.x0) > 72 && (d.y1 - d.y0) > 30)
                .append('text')
                .attr('class', 'treemap-label')
                .attr('x', 7)
                .attr('y', 17)
                .text(d => d.data.name);
              nodes.filter(d => (d.x1 - d.x0) > 72 && (d.y1 - d.y0) > 48)
                .append('text')
                .attr('class', 'treemap-metric')
                .attr('x', 7)
                .attr('y', 34)
                .text(d => fmt.format(d.data.weightedScore));
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
            document.getElementById('treemap-up').addEventListener('click', () => {
              if (currentPath.length > 1) {
                currentPath.pop();
                renderTreemap();
              }
            });
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
