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
