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
- With `enableCaching` on Xcode 27+, `XcodeCachePrefixMappingWorkspaceMapper` gives every project `SWIFT_OTHER_PREFIX_MAPPINGS`/`CLANG_OTHER_PREFIX_MAPPINGS` for the SwiftPM scratch directory (`/^spm`) and the Tuist root directory (`/^root`, located from the workspace path like the scratch directory, so a workspace generated below the root still keeps `Tuist/.build` relative). Project prefix mapping covers only `PROJECT_DIR`, and an external package's `PROJECT_DIR` is `tuist-derived/Projects/<name>` while its sources stay in `checkouts/`. The root directory goes in `TUIST_PREFIX_MAPPING_ROOT_DIR` and each mapping is a quoted `"$(TUIST_PREFIX_MAPPING_ROOT_DIR)/…=/^…"` token: Xcode splits unquoted list elements at spaces, and the compilers match prefixes as strings, so the expanded paths must be absolute and normalized.
- Generated `.xctestplan` files are written by a side effect that runs *after* the owning `.xcodeproj`, because the plan embeds PBX blueprint identifiers that are only stable once the project has been written. Mapper side effects, including the derived-directory cleanup, execute later still, so anything that prunes `Derived/` must preserve `TestPlans` or it deletes the plans that were just generated.
- Files a scheme references but does not own — StoreKit configurations, GPX files and `.xctestplan` files — need an explicit element in `ProjectFileElements` to appear in Xcode's navigator. A scheme reference alone does not surface them.
