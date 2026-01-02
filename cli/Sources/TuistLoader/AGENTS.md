# TuistLoader (Manifest Loading)

This module loads and evaluates Tuist manifests (e.g., `Project.swift`, `Workspace.swift`).

## Responsibilities
- Discover manifest files in the repo.
- Load/evaluate manifests into in-memory models for downstream use.

## Related Context
- Core domain models: `cli/Sources/TuistCore/AGENTS.md`
- Project generation: `cli/Sources/TuistGenerator/AGENTS.md`
