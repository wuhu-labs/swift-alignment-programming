# swift-alignment-programming

Generate a readable pseudo-Swift **public interface** for a SwiftPM target, using **symbol graphs only**.

## What it does

The tool builds a target, emits symbol graph JSON, then renders that into a pseudo-Swift outline intended for **human API review**.

It does **not** depend on `.swiftinterface` generation or library evolution mode.

## Language

This tool is written in **Python 3**.

## Usage

Run it from the same directory as your `Package.swift`:

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

## Reuse an existing symbol graph directory

This is mostly useful for testing or custom pipelines:

```bash
./generate_public_interface --target MyTarget --symbol-graph-dir /path/to/symbolgraphs
```

## Build logs

By default, the script keeps stdout clean so you can pipe the pseudo-Swift output directly into a file.

If you want to see the underlying `swift build` logs, use:

```bash
./generate_public_interface --target MyTarget --verbose-build
```

## Testing

Run the basic test suite with:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

The tests use checked-in symbol graph fixtures from the sample `BirdShapeKit` target and compare the renderer output against a checked-in pseudo-Swift fixture.

## Notes

- generated symbol graphs are written under `.build/public-interface-artifacts/symbolgraphs/`
- declarations are rendered with a stable sort rather than source-file order
- the renderer tries to suppress obvious synthesized noise, but prefers staying reasonably faithful over being perfectly pretty
- this is best suited for codebases you control, where a pragmatic interface view is more valuable than universal perfection
