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
- `enableCoveragePrefixMapping` is an explicit opt-in for teams remapping coverage with tools such as `llvm-cov`. It requires `enableCaching`; the default stays compatible with `xccov`.

- `InstallOptions.ManifestEnvironment.automatic` hides GitHub CI metadata and rotating credentials from cached manifest evaluation, preserving platform/toolchain and application inputs. Document that native SwiftPM resolution retains known credentials for fetching and evaluates manifests with them too. `.automatic(including:)` and `.all` restore intentional CI/credential-dependent manifest inputs; explicit exclusions affect native resolution as well.

## Related Context

- cli/Sources/TuistLoader/AGENTS.md
- cli/Sources/TuistGenerator/AGENTS.md
- `includeLocalPackageTestTargets` opts local path package tests into generation, including cross-package products available through `Tuist/Package.swift`; remote package tests stay excluded.
