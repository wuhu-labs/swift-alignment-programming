# swift-alignment-programming: Design Spec

## Overview

A Swift toolkit for alignment programming: generate readable pseudo-Swift public
interfaces, compute alignment scores, build dashboards, and (later) custom linting
— all from one unified `alignment` CLI and library.

The Python tools in this repo are the legacy v0. The Swift rewrite is v1.

## Goals

1. **Unified CLI.** One `alignment` binary with subcommands replaces 8+ scripts.
2. **Swift library surface.** Downstream packages can call the renderer, scorer,
   and dashboard generator as library APIs — no subprocess needed.
3. **Section-based interface output.** Optional `.alignment-sections` config
   organizes the public interface into named topic groups, with an index.
4. **Hash-based build cache.** Skip swift-build when source hasn't changed.
5. **Local snapshot workflow.** `alignment snapshot` does everything:
   build → render → score → dashboard → open browser.
6. **Agent-friendly.** JSON output mode for machine consumption.

## Non-Goals (v1)

- Custom linting (SwiftSyntax + JS engine) — this is phase 2
- R2 / GitHub Pages publishing — phase 3
- Git integration — phase 3
- SPM command plugin — future consideration

## Architecture

```
┌─────────────────────────────────────────────┐
│  alignment (executable)                      │
│  CLI entry point, file IO, subprocess calls  │
├─────────────────────────────────────────────┤
│  SwiftAlignmentProgramming (library)         │
│  Pure transformations, no IO                 │
│  ┌───────────┐ ┌──────────┐ ┌────────────┐  │
│  │ Renderer  │ │ Scorer   │ │ Dashboard  │  │
│  └───────────┘ └──────────┘ └────────────┘  │
│  ┌───────────┐ ┌──────────┐                 │
│  │ Sections  │ │ Cache    │                 │
│  └───────────┘ └──────────┘                 │
└─────────────────────────────────────────────┘
```

### Library Target: `SwiftAlignmentProgramming`

Pure transformations. No FileManager, no subprocess, no URLSession.
Consumers import this to build their own tooling.

Key types:

```
SymbolGraph           — Codable model of symbol-graph JSON
ModuleOutline         — Intermediate representation of a module's public API
SectionConfig         — Parsed .alignment-sections TOML
InterfaceRenderer     — ModuleOutline → pseudo-Swift text
AlignmentScorer       — [FileStat] → AlignmentScore
DashboardGenerator    — data → HTML/SVG strings
BuildCache            — Hash-based skip logic (pure key computation)
```

### Executable Target: `alignment`

Imperative shell. Handles file IO, subprocess (`swift build`), argument parsing.
Thin wrappers around the library types.

## Interface Sections

Optional `.alignment-sections` file (TOML) next to `.alignment`:

```toml
[Protocols]
symbols = ["ModelEndpoint", "Dialect"]

["Streaming Events"]
symbols = ["AssistantMessageEvent"]

["Built-In Endpoints"]
symbols = ["AnthropicEndpoint", "OpenAIGPTEndpoint", "DeepSeekChatEndpoint"]

[General]
auto = true
```

Rules:
- Sections appear in config file order
- `auto = true` on exactly one section: catch-all for unmatched symbols
- Without `auto`, unmatched symbols are dropped from sectioned output
- Extensions follow their base type's section
- Nested types stay with their parent (existing tree structure preserved)
- When no `.alignment-sections` exists: single implicit "General" section (flat output)

Output: full `.swift` file (for diffs) + `.index.md` (navigable table of contents).

## Cache Design

Per-target cache, stored in `.build/alignment-cache/cache.json`:

```json
{
  "version": 1,
  "targets": {
    "JiuziAI": {
      "key": "sha256:abc123...",
      "interface_path": "interfaces/Jiuzi/JiuziAI.swift"
    }
  }
}
```

Cache key = SHA256 of concatenated:
- All source file contents in target's Sources/ directory (sorted by path)
- Package.swift dependency graph for this target (resolved dependencies list)

Content-hashing: moving or cloning doesn't invalidate. Same code = same hash = skip build.
Symbol graphs themselves live in `.build/` which `swift package clean` wipes, so we
store the rendered interface output (small text file) separately and key on source hash.

Cache file path is configurable; defaults relative to the package root.

## CLI Subcommands

```
alignment interface   — Generate pseudo-Swift public interface
alignment score       — Compute alignment score from .alignment files
alignment snapshot    — All-in-one: interface + score + dashboard
alignment dashboard   — Generate dashboard HTML
alignment cache       — Manage build cache (status, clear)
```

### `alignment interface`

```
alignment interface --target <name> [--package-path <dir>] [--output <file>]
                    [--sections <file>] [--format text|json]
```

- Builds symbol graphs via `swift build -emit-symbol-graph` (cached)
- Renders pseudo-Swift interface
- Applies sections if config provided
- Outputs `.swift` file and `.index.md`

### `alignment snapshot`

```
alignment snapshot [--package-path <dir>] [--output-dir <dir>]
                   [--format text|json] [--no-open] [--no-cache]
```

All-in-one local workflow:
1. Discover targets in package
2. For each non-test target: build symbol graphs (cached), render interfaces
3. Scan .alignment files, compute scores
4. Generate local dashboard HTML
5. Open in browser (macOS: `open`)

## Implementation Plan

### Phase 1: Library Core
- [ ] SymbolGraph Codable types
- [ ] ModuleOutline IR
- [ ] InterfaceRenderer (port from Python renderer.py)
- [ ] SectionConfig parser
- [ ] Section-aware rendering

### Phase 2: CLI
- [ ] swift-argument-parser root command
- [ ] `alignment interface` subcommand
- [ ] Subprocess: `swift build -emit-symbol-graph`
- [ ] File IO for reading symbol graphs, writing output

### Phase 3: Scoring & Dashboard
- [ ] .alignment file scanning
- [ ] AlignmentScore computation
- [ ] SVG bar generation
- [ ] Dashboard HTML generation

### Phase 4: Snapshot & Cache
- [ ] `alignment snapshot` all-in-one command
- [ ] Hash-based cache with content-addressed keys
- [ ] Cache read/write/clear

### Phase 5: Integration
- [ ] Test against wuhu-app packages
- [ ] Backward-compat `generate_public_interface` wrapper
- [ ] Update wuhu-app CI to use new tool

## File Map (Sources/SwiftAlignmentProgramming/)

```
SymbolGraph.swift           — Codable types for symbol graph JSON format
ModuleOutline.swift         — TypeNode, ExtensionGroup, ModuleOutline IR
InterfaceRenderer.swift     — Outline → pseudo-Swift text rendering
SectionConfig.swift         — .alignment-sections parser and section assignment
AlignmentScore.swift        — Score, Grade, FileStat types
AlignmentScorer.swift       — Grade computation from file stats
SVGBar.swift               — SVG alignment bar generator
DashboardHTML.swift         — Dashboard and snapshot page HTML generator
Cache.swift                — BuildCache key computation and storage
```

## Symbol Graph JSON Schema (the parts we use)

```json
{
  "metadata": { "formatVersion": "major.minor" },
  "module": { "name": "TargetName", "platform": { "architecture": "..." } },
  "symbols": [
    {
      "kind": { "identifier": "swift.struct", "displayName": "Struct" },
      "identifier": { "precise": "s:8TargetName4FooV", "interfaceLanguage": "swift" },
      "pathComponents": ["TargetName", "Foo"],
      "names": { "title": "Foo" },
      "accessLevel": "public",
      "declarationFragments": [
        { "kind": "keyword", "spelling": "public" },
        { "kind": "text", "spelling": " " },
        { "kind": "keyword", "spelling": "struct" },
        { "kind": "text", "spelling": " " },
        { "kind": "identifier", "spelling": "Foo" }
      ],
      "swiftExtension": { "extendedModule": "TargetName", "constraints": [...] },
      "location": { "uri": "file:///...", "position": { "line": 1, "character": 1 } }
    }
  ],
  "relationships": [
    { "kind": "conformsTo", "source": "s:...", "target": "s:...", "targetFallback": "Equatable" }
  ]
}
```

`declarationFragments` is the primary text source. Fragment kinds are:
`keyword`, `text`, `identifier`, `typeIdentifier`, `genericParameter`,
`internalParam`, `externalParam`, `stringLiteral`, `numberLiteral`.

