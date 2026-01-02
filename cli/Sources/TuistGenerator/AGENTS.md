# TuistGenerator (Project Generation)

This module implements the project generation pipeline (transforming manifests into Xcode projects/workspaces).

## Responsibilities
- Build descriptors (`ProjectDescriptor`, `WorkspaceDescriptor`, `SchemeDescriptor`) used to write `.xcodeproj`.
- Orchestrate side effects required for generation (e.g., writing schemes, side-effect descriptors).
- Translate `ProjectDescription`/graph models into `XcodeProj` structures.

## Related Context
- Core domain models: `cli/Sources/TuistCore/AGENTS.md`
- Manifest loading: `cli/Sources/TuistLoader/AGENTS.md`

## Invariants
- `ProjectDescriptor`/`WorkspaceDescriptor` are the handoff types to XcodeProj writers.
- Side effects are collected explicitly and executed outside pure mapping.
