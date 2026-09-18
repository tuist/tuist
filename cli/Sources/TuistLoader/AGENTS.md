# TuistLoader (Manifest Loading)

This module loads and evaluates Tuist manifests (e.g., `Project.swift`, `Workspace.swift`).

## Responsibilities
- Discover manifest files and validate root manifests exist.
- Load manifests via `ManifestLoader`, handling sandboxing and caching.
- Build `ProjectDescription` helpers and decode JSON manifest output.
- Translate Swift Package Manager metadata into external dependency projects.

## Related Context
- Core domain models: `cli/Sources/TuistCore/AGENTS.md`
- Project generation: `cli/Sources/TuistGenerator/AGENTS.md`

## Invariants
- Manifest loading emits clear `FatalError` types for missing or malformed manifests.
- Swift package bundle identifiers preserve underscores as hyphens, including leading, trailing, and repeated underscores, so targets such as `IssueReporting` and `_IssueReporting` can coexist as embedded dynamic frameworks.
- `ManifestLoader` uses start/end tokens to parse manifest output and caches results.
- Swift package targets using tools version 5.9 or newer carry their package name compiler argument in target settings so graph transformations preserve package access.
- Opted-in local package test targets may reference external products resolved from `Tuist/Package.swift`; map these through the same dependency path as production targets. Remote package tests remain excluded. Missing external products on tagged local package tests identify the test and product and direct users to declare the providing package in `Tuist/Package.swift` and run `tuist install`.
