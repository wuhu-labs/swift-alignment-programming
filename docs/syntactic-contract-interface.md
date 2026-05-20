# Syntactic Contract Interfaces

## Motivation

`alignment interface` currently uses compiler-emitted symbol graphs. That output is
semantically useful, but the build loop is too slow for tight LLM-assisted
iteration. We want a fast local guardrail that lets agents check, before they
commit, that they have not accidentally expanded a target's `public`, `open`, or
`package` API surface.

The long-term north star is that a target can be regenerated from:

1. its public contract interface, and
2. black-box contract tests that do **not** use `@testable import`.

Implementation sources and `@testable import` tests should be treated as
replaceable implementation detail. The checked contract is the stable artifact.

## Product definition

A syntactic contract interface is a source-derived API outline generated without
building the package. It parses checked-in Swift source with SwiftSyntax, extracts
contract-visible declarations, emits a stable JSON IR, and renders a readable
pseudo-Swift outline for review and diffing.

This is intentionally not a Swift compiler or a replacement for CI. Traditional
build/test CI remains the verifier for semantic correctness. The syntactic
contract interface is optimized for speed, determinism, and catching accidental
source-written API changes.

## Core principles

- **No build in the hot loop.** The syntactic command must not run `swift build`,
  expand macros, run build plugins, or inspect compiler outputs.
- **Source-written surface is truth.** If a declaration is not written in source,
  it is not part of the syntactic interface.
- **Public API must be explicit.** Contract-visible stored properties/constants
  must have explicit type annotations. If their type must be inferred, generation
  fails with a diagnostic.
- **All conditional branches count.** Public/package declarations under `#if`,
  `#elseif`, and `#else` are included as a union of possible platform/config API.
  This is desirable for an aggressive guardrail.
- **Preserve written type spelling.** Do not canonicalize aliases or module
  qualifications beyond minimal formatting. The contract should reflect what the
  author wrote.
- **Attach local extensions to local types.** Extension members for types declared
  in the same module should be merged into the type's contract node. Extensions of
  external types remain extension groups.
- **Macros and property wrappers are preserved, not expanded.** Attached macros
  and wrappers are rendered as written. Freestanding macros are ignored unless a
  later phase deliberately models them.
- **External registries are optional.** The system must work with no registry.
  External module data can improve classification/linking later, but missing data
  must not block contract generation.

## Access scope

The default contract scope for guardrails should include:

- `open`
- `public`
- `package`

`internal` is not a primary goal. It may be useful in future modes, but the main
contract surface is what black-box clients can rely on, plus explicit package API
when a package chooses to treat same-package clients as stable.

Effective access should be computed from lexical context. For example, a `public`
member inside a `package` type is effectively `package` for contract purposes.

## IR before rendering

The SwiftSyntax frontend should produce a richer IR than the existing string-only
`ModuleOutline`. Rendering and diffing should be separate concerns.

The IR should contain stable symbol keys, declaration text, nesting, access, and
metadata. Example keys:

```text
type Client
type Client.Configuration
func Client.fetch(id:)
var Client.state
case Mode.enabled
subscript Collection.(_:)
```

The JSON contract artifact should be stable enough for machine diffing and future
regeneration workflows. The existing pseudo-Swift renderer can be adapted from
this IR for human review.

## Source selection

Source discovery should use SwiftPM target metadata where available, with support
for the aligned `Targets/<target>/Sources` layout. It should respect `.gitignore`
by default and support explicit include/exclude globs. Generated source should be
excluded by policy unless a future workflow deliberately runs a generator such as
SwiftGen and feeds its output to the parser.

Build plugins are out of scope for the hot path.

## Relationship to the existing symbol-graph interface

The current `alignment interface` output remains a verifier and comparison goal.
For real packages, syntactic output should be close enough to existing
symbol-graph output that differences are explainable and useful.

A concrete verification target is the Wuhu app alignment snapshot at:

<https://wuhu.ai/alignment/commit/dd59fcdd21d9e32be2d7223047838c743bcdb5f4/>

Expected intentional differences include:

- synthesized members are absent unless written in source;
- macro-generated declarations are absent;
- all conditional-compilation branches are included;
- extension members for local types are attached to those types;
- written type spelling is preserved rather than semantically canonicalized.

## Phased implementation plan

### Phase 1: Contract IR and SwiftSyntax extractor

Build the pure frontend.

Acceptance criteria:

- parse Swift source files with SwiftSyntax;
- collect `open`, `public`, and `package` declarations;
- compute effective access from nesting;
- produce stable JSON contract IR with symbol keys;
- include declarations from all conditional-compilation branches;
- preserve attached attributes, macros, and property wrappers;
- ignore freestanding macros;
- require explicit type annotations for contract-visible stored properties and
  constants;
- build a local symbol table sufficient to attach extensions to local types.

### Phase 2: Renderer for syntactic contracts

Render the contract IR to readable pseudo-Swift.

Acceptance criteria:

- deterministic sorting and formatting;
- local extension members appear under their local type;
- extensions of external types remain extension groups;
- written type spelling is preserved;
- snapshots cover nominal types, nested types, extensions, protocols, enum cases,
  properties, functions, subscripts, attributes, macros, wrappers, and `#if`
  branches.

### Phase 3: CLI snapshot command

Expose the fast path through the CLI without invoking the build system.

Possible command shape:

```bash
alignment contract --target Foo --access open,public,package \
  --json .build/contracts/Foo.contract.json \
  --render .build/contracts/Foo.swift
```

Acceptance criteria:

- no `swift build` in the command path;
- target source discovery via SwiftPM metadata and aligned-layout fallback;
- include/exclude glob options;
- `.gitignore` respected by default;
- JSON and rendered outputs are both available.

### Phase 4: Diff and guard command

Make the tool directly useful to agents.

Possible command shape:

```bash
alignment contract-guard --against main --access open,public,package --no-additions
```

Acceptance criteria:

- compare current checkout against a git ref;
- report added, removed, and changed contract symbols;
- exit nonzero when forbidden changes are present;
- emit output suitable for LLM self-checking, for example:

  ```text
  Added public/package API:
    public struct NewThing
    package func Client.reset()
  ```

### Phase 5: Real-world verification against current alignment output

Compare syntactic contracts with existing symbol-graph interfaces on a real Wuhu
checkout.

Acceptance criteria:

- use `wuhu-app@dd59fcdd21d9e32be2d7223047838c743bcdb5f4` as a comparison case;
- generate existing `alignment interface` outputs;
- generate syntactic contract outputs;
- produce a report of matched, syntax-only, and symbolgraph-only symbols;
- document intentional differences and unexpected gaps.

### Later: local and external semantic classification

After the fast guardrail works, add optional classification layers:

1. local protocol requirement matching for protocols declared in the same module;
2. a small built-in registry for common Swift protocols such as `Equatable`,
   `Hashable`, `Encodable`, `Decodable`, `RawRepresentable`, and `Identifiable`;
3. an optional external module registry generated offline from symbol graphs,
   `.swiftinterface` files, or source.

These layers should classify and link protocol witnesses conservatively. They
should not be required for contract generation, and rendering should decide
separately whether classified witnesses are shown, hidden, or annotated.
