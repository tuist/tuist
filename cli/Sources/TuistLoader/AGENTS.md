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
- `ManifestLoader` uses start/end tokens to parse manifest output and caches results.
- Swift package targets using tools version 5.9 or newer carry their package name compiler argument in target settings so graph transformations preserve package access.
