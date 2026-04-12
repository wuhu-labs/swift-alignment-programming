# swift-alignment-programming

Generate a readable pseudo-Swift **public interface** for a SwiftPM target.

## What it does

The script builds a target, emits its raw `.swiftinterface`, then filters that into a more review-friendly outline that feels closer to Xcode's generated interface view.

## Language

This tool is written in **Python 3**.

## Usage

Run it from the same directory as your `Package.swift`:

```bash
/path/to/generate_public_interface --target MyTarget
```

If the script is in the package root, that usually means:

```bash
./generate_public_interface --target MyTarget
```

You can also point it at another package root:

```bash
./generate_public_interface --package-path /path/to/package --target MyTarget
```

## Write output to a file

```bash
./generate_public_interface --target MyTarget --output MyTarget.public.swift
```

## Build logs

By default, the script keeps stdout clean so you can pipe the pseudo-Swift output directly into a file.

If you want to see the underlying `swift build` logs, use:

```bash
./generate_public_interface --target MyTarget --verbose-build
```

## Notes

- raw `.swiftinterface` output is written under `.build/public-interface-artifacts/`
- the rendered output is intended for **human review**
- it intentionally suppresses a chunk of compiler-synthesized noise
- this is best suited for codebases you control, where a pragmatic interface view is more valuable than universal perfection
