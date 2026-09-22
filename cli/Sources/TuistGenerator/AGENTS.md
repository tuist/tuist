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
- Preserve real directories for generated sources, Info.plists, and entitlements during early Derived cleanup so unchanged files retain their mtimes. Unlink directory symlinks, including dangling links, before writing generated files; never clean through a symlink root. After their generating mappers run, describe stale-file cleanup from the mapped targets; execution removes only obsolete Tuist-owned files and compares active paths using the volume's case-sensitivity.
- Targets with buildable folders exclude `.gitkeep` and `.DS_Store` through Xcode build settings, preserving existing exclusions. Xcode enumerates synchronized folders independently of Tuist's filtered globs, including files added after generation.
