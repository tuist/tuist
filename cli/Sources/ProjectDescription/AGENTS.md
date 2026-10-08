# ProjectDescription (CLI Module)

This module provides manifest-facing types used to describe projects, targets, and settings.

## Responsibilities
- Define the public manifest DSL: `Project`, `Target`, `Scheme`, actions, settings, and resource definitions.
- Encode manifest structures as `Codable` so they can be loaded and serialized by `TuistLoader`.

## Boundaries
- Manifest loading/evaluation lives in `cli/Sources/TuistLoader`.
- Graph and generation logic lives in `cli/Sources/TuistGenerator`/`TuistCore`.

## Invariants
- Manifest types are `Codable`/`Equatable` and designed to be stable across versions.
- Native package dependencies may use `runtimeDynamic` or `runtimeDynamicEmbedded` as explicit linkage hints for hosted tests. These do not change SwiftPM product linkage; existing `runtime` and `runtimeEmbedded` declarations retain their behavior.
- `Project` maps 1:1 to `Project.swift` manifests and includes targets, schemes, settings, and packages.

## Related Context
- cli/Sources/TuistLoader/AGENTS.md
- cli/Sources/TuistGenerator/AGENTS.md
- `includeLocalPackageTestTargets` opts local path package tests into generation, including cross-package products available through `Tuist/Package.swift`; remote package tests stay excluded.
