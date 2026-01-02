# TuistCASAnalytics (CLI Module)

This module provides CAS analytics storage helpers used by cache features.

## Responsibilities
- Persist metadata about CAS outputs and key-value entries.
- Provide stores for reading/writing metadata (e.g., `CASNodeStore`, `KeyValueMetadataStore`).

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistCAS/AGENTS.md
- cli/Sources/TuistCache/AGENTS.md
