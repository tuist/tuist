# TuistCore (Domain Core)

This module contains core domain abstractions and shared models used across the CLI.

## Responsibilities
- Core types and protocols shared by higher-level modules.
- Cross-cutting domain logic that is not tied to a single feature area.

## Boundaries
- Avoid direct dependency on CLI command wiring (`TuistKit`) or entry points.
- Prefer keeping IO-heavy or integration-specific logic in feature modules.

## Related Context
- Shared utilities: `cli/Sources/TuistSupport/AGENTS.md`
- Project generation: `cli/Sources/TuistGenerator/AGENTS.md`
