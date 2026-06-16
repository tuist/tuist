# TuistCache (Cache Integration)

This module handles CLI integration with the cache service and cache features.

## Responsibilities
- Compute cache content hashes for graph targets.
- Define cache versioning and invalidation boundaries.
- Support selective testing by identifying cached tests.

## Related Context
- Cache service: `cache/AGENTS.md`

## Invariants
- Only cacheable products are hashed (frameworks, static frameworks, bundles, macros).
- Test bundles are excluded from binary cache hashing, but test-support frameworks that link XCTest or Swift Testing can be hashed.
- Explicit cache warm target selection scopes transitive cache candidates from non-test roots only.
- Cache version bumps invalidate incompatible artifacts.
