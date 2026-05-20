# Wuhu Syntactic Contract Verification

Verification date: 2026-05-20

Comparison target:

- Repository: `github.com/wuhu-labs/wuhu-app`
- Checkout: `dd59fcdd21d9e32be2d7223047838c743bcdb5f4`
- Published symbol-graph artifact: <https://wuhu.ai/alignment/commit/dd59fcdd21d9e32be2d7223047838c743bcdb5f4/>

## Commands Run

```bash
git clone https://github.com/wuhu-labs/wuhu-app.git ~/Developer/wuhu-app
git -C ~/Developer/wuhu-app switch --detach dd59fcdd21d9e32be2d7223047838c743bcdb5f4

.build/debug/alignment contracts \
  --package-path ~/Developer/wuhu-app/Packages/WuhuCoreKit \
  --target <target> \
  --json /tmp/wuhu-contracts-json/WuhuCoreKit/<target>.contract.json \
  --render /tmp/wuhu-contracts/WuhuCoreKit/<target>.swift

.build/debug/alignment contracts \
  --package-path ~/Developer/wuhu-app/Packages/WuhuAppKit \
  --target <target> \
  --json /tmp/wuhu-contracts-json/WuhuAppKit/<target>.contract.json \
  --render /tmp/wuhu-contracts/WuhuAppKit/<target>.swift
```

The existing symbol-graph interface artifacts were downloaded from the published
alignment page above.

## Generated Syntactic Contracts

The syntactic command generated contracts for these targets:

| Package | Target |
| --- | --- |
| WuhuCoreKit | SQLiteMigrations |
| WuhuCoreKit | ServeExtras |
| WuhuCoreKit | ServerMessageBusFeature |
| WuhuCoreKit | ServerTimerFeature |
| WuhuCoreKit | WorkspaceEngine |
| WuhuCoreKit | WorkspaceScanner |
| WuhuCoreKit | WuhuAI |
| WuhuCoreKit | WuhuCLIKit |
| WuhuCoreKit | WuhuClient |
| WuhuCoreKit | WuhuRunner |
| WuhuCoreKit | WuhuServer |
| WuhuCoreKit | wuhu |

The following targets intentionally failed because Phase 1 requires explicit
types for contract-visible stored properties/constants:

| Package | Target | Diagnostic |
| --- | --- | --- |
| WuhuCoreKit | WorkspaceContracts | `Targets/WorkspaceContracts/Sources/Kind.swift: let document` |
| WuhuCoreKit | WuhuCore | `Targets/WuhuCore/Sources/WuhuBookOfWuhu.swift: let readmePath` |
| WuhuCoreKit | ServerDependencies | `Targets/ServerDependencies/Sources/FileIO/NIOAsyncFileIO.swift: let shared` |
| WuhuCoreKit | ServerLibraryFeature | `Targets/ServerLibraryFeature/Sources/WuhuLibraryURL.swift: let scheme` |
| WuhuCoreKit | ServerSessionFeature | `Targets/ServerSessionFeature/Sources/WuhuLLMProviderConfiguration.swift: let empty` |
| WuhuCoreKit | ToolExecution | `Targets/ToolExecution/Sources/Tools/ToolTruncation.swift: let defaultMaxLines` |
| WuhuCoreKit | WuhuAPI | `Targets/WuhuAPI/Sources/WorkspaceImportPayload.swift: let scheme` |
| WuhuAppKit | CanopyKit | `Targets/CanopyKit/Sources/Layouts/ContentAlignment.swift: let topLeading` |
| WuhuAppKit | WuhuShared | `Targets/WuhuShared/Sources/APIClientInterface.swift: let testValue` |
| WuhuAppKit | DocFeatureKit | `Targets/DocFeatureKit/Sources/DocClient.swift: let testValue` |
| WuhuAppKit | SessionFeatureKit | `Targets/SessionFeatureKit/Sources/CurrentUsernameClient.swift: let liveValue` |
| WuhuAppKit | App | `Targets/App/Sources/AppRuntime.swift: let buildFlavorInfoKey` |
| WuhuAppKit | ServerEmbeddedApp | `Targets/ServerEmbeddedApp/Sources/AppDelegate.swift: let updater` |
| WuhuAppKit | MarkdownKit | `Targets/MarkdownKit/Sources/MarkdownDocumentComponent.swift: let default` |

## Current Wuhu Main Follow-up

After the initial comparison, Wuhu PR
<https://github.com/wuhu-labs/wuhu-app/pull/389> added explicit type
annotations for the contract-visible stored values above and documented the
SwiftGen local build step in Wuhu's `AGENTS.md`.

Verification against `wuhu-app@2d8000a` generated syntactic contracts
successfully for every non-test target in both packages:

```bash
.build/debug/alignment contracts \
  --package-path ~/Developer/wuhu-app/Packages/WuhuCoreKit \
  --render /tmp/wuhu-contracts-current/WuhuCoreKit \
  --json /tmp/wuhu-contracts-json-current/WuhuCoreKit

.build/debug/alignment contracts \
  --package-path ~/Developer/wuhu-app/Packages/WuhuAppKit \
  --render /tmp/wuhu-contracts-current/WuhuAppKit \
  --json /tmp/wuhu-contracts-json-current/WuhuAppKit
```

Generated target coverage:

| Package | Targets |
| --- | --- |
| WuhuCoreKit | SQLiteMigrations, ServeExtras, ServerDependencies, ServerLibraryFeature, ServerMessageBusFeature, ServerSessionFeature, ServerTimerFeature, ToolExecution, WorkspaceContracts, WorkspaceEngine, WorkspaceScanner, WuhuAI, WuhuAPI, WuhuCLIKit, WuhuClient, WuhuCore, WuhuRunner, WuhuServer, wuhu |
| WuhuAppKit | App, CanopyKit, DocFeatureKit, MarkdownKit, ServerEmbeddedApp, SessionFeatureKit, WuhuShared |

## Declaration Overlap Report

This table compares normalized declaration text from generated syntactic
contracts against normalized declaration text from the published symbol-graph
interfaces. It is conservative: differences in conformance rendering,
synthesized declarations, and extension attachment lower the exact-match count
even when the API is explainably represented.

| Package | Target | Matched | Syntax-only | Symbolgraph-only | Syntax total | Symbolgraph total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| WuhuCoreKit | SQLiteMigrations | 0 | 11 | 13 | 11 | 13 |
| WuhuCoreKit | ServeExtras | 0 | 21 | 22 | 21 | 22 |
| WuhuCoreKit | ServerMessageBusFeature | 3 | 23 | 21 | 26 | 24 |
| WuhuCoreKit | ServerTimerFeature | 12 | 35 | 30 | 47 | 42 |
| WuhuCoreKit | WorkspaceEngine | 5 | 31 | 31 | 36 | 36 |
| WuhuCoreKit | WorkspaceScanner | 5 | 30 | 31 | 35 | 36 |
| WuhuCoreKit | WuhuAI | 37 | 103 | 109 | 140 | 146 |
| WuhuCoreKit | WuhuCLIKit | 3 | 26 | 41 | 29 | 44 |
| WuhuCoreKit | WuhuClient | 0 | 30 | 31 | 30 | 31 |
| WuhuCoreKit | WuhuRunner | 0 | 16 | 19 | 16 | 19 |
| WuhuCoreKit | WuhuServer | 10 | 61 | 63 | 71 | 73 |
| WuhuCoreKit | wuhu | 2 | 2 | 13 | 4 | 15 |

## Intentional Differences Observed

- Synthesized conformances and members from symbol graphs are absent from the
  syntactic contracts unless written in source.
- Macro-generated declarations are absent; attached macros and wrappers are
  preserved as written.
- Conditional compilation branches are included as a union of source-written API.
- Extension members for local types are attached under their local type in the
  rendered syntactic output.
- Written source spelling is preserved instead of canonicalizing aliases,
  module-qualified names, or inferred types.

## Unexpected Gaps / Follow-up

- The exact-match table is intentionally conservative and should be replaced by
  symbol-key comparison once the symbol-graph renderer also exposes stable keys.
- At the original `dd59fcdd21d9e32be2d7223047838c743bcdb5f4` checkout, several
  Wuhu targets needed explicit annotations on public/package stored constants
  before syntactic generation could complete. This was expected Phase 1
  behavior, not a parser failure, and has since been validated on current Wuhu
  `main`.
