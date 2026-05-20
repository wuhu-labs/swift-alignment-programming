# Syntactic Contracts Progress Log

Branch: `features/syntactic-contracts-4-8`

## 2026-05-20

- Read `docs/syntactic-contract-interface.md` and GitHub issues #4, #5, #6, #7, and #8.
- Created the feature branch from `main`.
- Added a SwiftSyntax-backed contract IR and extractor for `open`, `public`, and `package` API.
- Added deterministic pseudo-Swift rendering from the contract IR.
- Added source discovery using SwiftPM package metadata with aligned-layout fallback, include/exclude globs, and `.gitignore` filtering.
- Added contract diffing for added, removed, and changed symbols.
- Added the `alignment contracts` CLI command for snapshot generation and git-ref guard checks.
- Added focused tests for extraction, rendering, diagnostics, diffing, and source discovery.
- Cloned `wuhu-app`, checked out `dd59fcdd21d9e32be2d7223047838c743bcdb5f4`, generated syntactic contracts for the targets that pass explicit stored-type enforcement, and documented the comparison in `docs/wuhu-contract-verification.md`.
- Merged the self-contained Phase 1 work through PR #9, then opened follow-up branch `features/contracts-followup-verification`.
- Merged Wuhu PR #389 to add explicit type annotations for contract-visible stored values and document the SwiftGen local build step in Wuhu's `AGENTS.md`.
- Corrected enum default-access handling so cases inherit the enum's access while other enum members still default to `internal`.
- Re-ran syntactic contract generation against current Wuhu `main`; all non-test WuhuCoreKit and WuhuAppKit targets generated successfully.
