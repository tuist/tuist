# TuistCAS (CLI Module)

This module provides content-addressable storage (CAS) helpers used by cache features.

## Responsibilities
- Implement content-addressable storage (CAS) helpers used by cache features.
- Keep the module cohesive around its named concern

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistCache/AGENTS.md
