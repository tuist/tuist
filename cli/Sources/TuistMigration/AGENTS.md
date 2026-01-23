# TuistMigration (CLI Module)

This module provides migration helpers for evolving manifests or workflows.

## Responsibilities
- Validate and extract settings during migrations (e.g., detect empty build settings).
- Provide utilities to evolve or analyze Xcode projects during migrations.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistLoader/AGENTS.md
- cli/Sources/TuistKit/AGENTS.md

## Invariants
- Migration utilities fail with `FatalError` when required Xcode project data is missing or invalid.
