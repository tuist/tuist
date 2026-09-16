# TuistCache (Cache Integration)

This module handles CLI integration with the cache service and cache features.

## Responsibilities
- Compute cache content hashes for graph targets.
- Define cache versioning and invalidation boundaries.
- Support selective testing by identifying cached tests.

## Generated client
- `OpenAPI/cache.yml`, `Types.swift` and `Client.swift` are generated from Kura's HTTP API definition (`kura/openapi/cache.yml`) with `mise run generate-cli-client` from `kura/`. Change the definition there, not these files.

## Related Context
- Kura: `kura/AGENTS.md`
- Cache service: `cache/AGENTS.md`

## Invariants
- Only cacheable products are hashed (frameworks, static frameworks, static libraries, dynamic libraries, bundles, macros).
- Test bundles are excluded from binary cache hashing, but test-support frameworks and libraries that link XCTest or Swift Testing can be hashed.
- Explicit cache warm target selection scopes transitive cache candidates from non-test roots only.
- Caller-owned cache-warm scratch directories reject foreign build misses because their scripts control output locations.
- Cache version bumps invalidate incompatible artifacts.
- XCFramework compatibility fingerprints are per SDK variant and independent of unrelated consumers. Initial coverage is iOS device/simulator, Catalyst, and macOS using standard architectures; other platforms and custom architecture settings use exact-target REAPI actions.
- Per-SDK REAPI action results reference immutable output trees. All required SDK results must exist before materializing an XCFramework. Verify CAS digests, directory safety, and actual slice coverage before reuse; do not publish subset indexes.
- XCFramework coverage is read through `XCFrameworkCoverageServicing`, implemented by the filesystem-backed `Services/XCFrameworkCoverageService.swift`. It reads declared architectures and checks binary existence; binary integrity validation is separate.
- Action records live under `Binaries/action-<digest>/result.pb`, sharing the binary-cache budget and cleanup with CAS blobs and materialized outputs.
- All modern binary products use REAPI/CAS. Non-sliceable outputs retain their complete artifact tree under an exact-target action. Old module archives are cold misses; selective-test storage and explicit legacy mode keep their existing implementations.
