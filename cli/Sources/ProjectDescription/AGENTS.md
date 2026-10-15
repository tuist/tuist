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
- Native `.package(product:)` dependencies may use `runtimeDynamic` or `runtimeDynamicEmbedded` as explicit linkage hints for hosted tests. Xcode still resolves their build type; existing `runtime` and `runtimeEmbedded` declarations retain their behavior. `.external(name:)` dependencies become Tuist-generated targets with linkage represented by their product types, so they do not require these native-package hints.
- `Project` maps 1:1 to `Project.swift` manifests and includes targets, schemes, settings, and packages.
- `enableCachingPrefixMapping` defaults to `true` and only controls Tuist-injected compilation-cache mappings. Its explicit opt-out preserves user mappings and keeps caching available with path-dependent keys. Missing serialized values decode to `true`; keep deprecated options overloads on the existing default. Retain the original modern factory signature, and disfavor the new required-flag overload so typed and inferred function references remain source-compatible.
- `enableCoveragePrefixMapping` is an explicit opt-in for teams remapping coverage with tools such as `llvm-cov`. It requires both `enableCaching` and `enableCachingPrefixMapping`; the default stays compatible with `xccov`.

## Related Context
- cli/Sources/TuistLoader/AGENTS.md
- cli/Sources/TuistGenerator/AGENTS.md
- `includeLocalPackageTestTargets` opts local path package tests into generation, including cross-package products available through `Tuist/Package.swift`; remote package tests stay excluded.
