# TuistCache (Cache Integration)

This module handles CLI integration with the cache service and cache features.

## Responsibilities
- Compute cache content hashes for graph targets.
- Define cache versioning and invalidation boundaries.
- Support selective testing by identifying cached tests.

## Related Context
- Cache service: `cache/AGENTS.md`

## Invariants
- Only cacheable products are hashed (frameworks, static frameworks, static libraries, dynamic libraries, bundles, macros).
- Test bundles are excluded from binary cache hashing, but test-support frameworks and libraries that link XCTest or Swift Testing can be hashed.
- Explicit cache warm target selection scopes transitive cache candidates from non-test roots only.
- Caller-owned cache-warm scratch directories reject foreign build misses because their scripts control output locations.
- Cache version bumps invalidate incompatible artifacts.
- XCFramework compatibility fingerprints are per SDK variant and independent of unrelated consumers. Initial coverage is iOS device/simulator, Catalyst, and macOS using standard architectures; other platforms and custom architecture settings use exact-target REAPI actions.
- Per-SDK REAPI action results reference immutable output trees. All required SDK results must exist before materializing an XCFramework. Verify CAS digests, directory safety, and actual slice coverage before reuse; do not publish subset indexes.
- All modern binary products use REAPI/CAS. Non-sliceable outputs retain their complete artifact tree under an exact-target action. Old module archives are cold misses; selective-test storage and explicit legacy mode keep their existing implementations.

## HTTP client generation
- The selective-test HTTP client in `OpenAPI/` is generated from `kura/openapi/cache.yml` with `mise run generate-cli-client` in `kura/`. Keep the source specification and generated client together when integrating protocol changes.
