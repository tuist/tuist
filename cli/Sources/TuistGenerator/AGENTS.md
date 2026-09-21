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
- Targets with buildable folders exclude `.gitkeep` and `.DS_Store` through Xcode build settings, preserving existing exclusions. Xcode enumerates synchronized folders independently of Tuist's filtered globs, including files added after generation.
- Generated `.xctestplan` files are written by a side effect that runs *after* the owning `.xcodeproj`, because the plan embeds PBX blueprint identifiers that are only stable once the project has been written. Mapper side effects, including the derived-directory cleanup, execute later still, so anything that prunes `Derived/` must preserve `TestPlans` or it deletes the plans that were just generated.
- Files a scheme references but does not own — StoreKit configurations, GPX files and `.xctestplan` files — need an explicit element in `ProjectFileElements` to appear in Xcode's navigator. A scheme reference alone does not surface them.
