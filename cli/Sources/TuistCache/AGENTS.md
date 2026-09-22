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
