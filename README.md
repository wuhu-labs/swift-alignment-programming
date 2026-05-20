# swift-alignment-programming

Generate readable pseudo-Swift **public interfaces** for SwiftPM targets using
**symbol graphs only**.  Also computes alignment scores from `.alignment` files
and produces dashboards.

## Install

```bash
swift build -c release
cp .build/release/alignment /usr/local/bin/
```

## Commands

### `alignment interface`

Generate pseudo-Swift public interfaces for a package.

```bash
# All non-test targets in the current package
alignment interface

# All targets, explicit package path, write to directory
alignment interface --package-path /path/to/package --output /tmp/interfaces

# Single target
alignment interface --target MyTarget

# Override build system (default: native)
alignment interface --build-system swiftbuild

# Reuse existing symbol graphs (skip build)
alignment interface --target MyTarget --symbol-graph-dir /path/to/symbolgraphs

# Section-based output (single target only)
alignment interface --target MyTarget --sections .alignment-sections
```

### `alignment score`

Compute alignment scores from `.alignment` files.

```bash
alignment score
alignment score --root /path/to/repo
alignment score --json --output score.json
```

### `alignment dashboard`

Generate an HTML dashboard from score JSON and interface files.

```bash
alignment dashboard \
  --score-json score.json \
  --interfaces-dir interfaces/ \
  --output-dir dashboard/ \
  --title "My Project"
```

### `alignment complexity`

Measure Swift-oriented weighted complexity for non-test source targets. The
collector uses SwiftPM target metadata and has built-in support for the aligned
`Targets/<target>/Sources` layout, filtering out `Targets/<target>/Tests` by
path rather than test-file naming conventions.

```bash
# Write a detailed JSON report with per-file and sparse per-line complexity
alignment complexity --root /path/to/package --output complexity.json

# Limit the scan to one target, folder, or file
alignment complexity --root /path/to/package \
  --target ServerDependencies \
  --path Targets/ServerDependencies/Sources/FileIO \
  --output fileio-complexity.json

# Print target or file summaries from the JSON
alignment complexity-summary --input complexity.json --by target
alignment complexity-summary --input complexity.json --by file --top 50
alignment complexity-summary --input complexity.json \
  --by file \
  --path Targets/ServerDependencies/Sources/FileIO

# Print an ASCII tree: target → folders → files
alignment complexity-summary --input complexity.json --by tree

# Compare before/after reports and fail unless weighted complexity decreases
alignment complexity-diff \
  --before before.json \
  --after after.json \
  --path Targets/ServerDependencies/Sources/FileIO \
  --must-decrease

# Generate an HTML dashboard with target/file tables and a treemap
alignment complexity-dashboard \
  --input complexity.json \
  --output-dir complexity-dashboard \
  --title "My Project"
```

The report includes both raw and weighted scores. The default weighting models
Swift maintenance cost: broader access (`public`, `package`, `internal`,
`fileprivate`, `private`), reference/concurrency types (`class`, `final class`,
`actor`), mutable/stored properties, and `async`/`throws` methods.

### `alignment contracts`

Generate fast SwiftSyntax-based contract interfaces without running
`swift build`, macro expansion, build plugins, or symbol graph emission.

```bash
# Print the rendered contract for one target
alignment contracts --target MyTarget

# Write JSON IR and rendered pseudo-Swift
alignment contracts \
  --target MyTarget \
  --json .build/contracts/MyTarget.contract.json \
  --render .build/contracts/MyTarget.swift

# Generate all package targets into .build/contracts/
alignment contracts --package-path /path/to/package

# Compare the current checkout against a git ref and reject added API
alignment contracts --target MyTarget --against main --no-additions
```

The default access scope is `open,public,package`. Source discovery uses SwiftPM
metadata when available, falls back to `Targets/<target>/Sources`, respects
`.gitignore` by default, and supports repeated `--include` / `--exclude` globs.
Contract-visible stored properties and constants must have explicit type
annotations; inferred stored types fail generation with a diagnostic.

## Monorepo CI recipe

```bash
WS=".ci/alignment"
mkdir -p "$WS/interfaces"

# Score
alignment score --root . --json --output "$WS/score.json"

# Interfaces per package
for pkg in Packages/*/; do
  pkg_name=$(basename "$pkg")
  build_system=native
  [ "$pkg_name" = "WuhuAppKit" ] && build_system=swiftbuild
  alignment interface \
    --package-path "$pkg" \
    --build-system "$build_system" \
    --output "$WS/interfaces/$pkg_name"
done

# Dashboard
alignment dashboard \
  --score-json "$WS/score.json" \
  --interfaces-dir "$WS/interfaces" \
  --output-dir "$WS" \
  --no-open
```

## How it works

1. `swift build` with `-emit-symbol-graph` creates symbol graph JSON for each
   compiled Swift file.
2. The renderer reads those JSON files and produces a pseudo-Swift outline
   sorted for readability (not source order), with synthesized declarations
   suppressed.
3. Interfaces can optionally be organized into named sections via a
   `.alignment-sections` config file.

## Notes

- Generated symbol graphs land in `.build/public-interface-artifacts/symbolgraphs/`
- The build system defaults to `native`; pass `--build-system swiftbuild` for
  Xcode-style packages
- No `.swiftinterface` or library evolution mode required
