# TuistHasher (CLI Module)

This module provides hashing utilities used across CLI modules.

## Responsibilities
- Provide content hashing for files, strings, and structured inputs.
- Offer cached hashing (`CachedContentHasher`) to avoid recomputation.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistSupport/AGENTS.md

## Invariants
- Cached hashes are stored in-memory and keyed by absolute file path.
- Binary-cache fingerprints normalize destinations and deployment targets per compilation variant, hash applicable dependencies recursively, and keep macros on their host platform. Never remove platform identity without checking artifact coverage at lookup.
- SDK fingerprints reuse platform-independent subhashes from the exact-target pass (or the first SDK pass when used standalone). Only destinations, deployment targets, additional SDK strings, and dependency fingerprints are recomputed. Reuse is scoped to one graph and hashing invocation; preserve the existing hash composition.
- Record effective destinations and individual hash inputs at hashing time; diagnostics must not change hash composition.
- `SettingsContentHasher` drops `COMPILATION_CACHE_*` keys and `-cas-plugin-option` pairs, and `TUIST_PREFIX_MAPPING_WORKSPACE_DIR` (the checkout path the generated prefix mappings reference), so checkouts at different paths share binary-cache hashes. `SWIFT_OTHER_PREFIX_MAPPINGS`/`CLANG_OTHER_PREFIX_MAPPINGS` are hashed verbatim: both sides of a mapping reach the product. `*_ENABLE_*PREFIX_MAPPING` keys stay hashed: they change `#filePath` in the product.
