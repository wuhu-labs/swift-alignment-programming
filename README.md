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
