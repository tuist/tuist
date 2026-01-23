# TuistCore (Domain Core)

This module contains core domain abstractions and shared models used across the CLI.

## Responsibilities
- Cross-cutting domain models for command runs and analytics (e.g., `CommandEvent`, `RunGraph`).
- Shared run metadata and cache-related telemetry types.

## Boundaries
- Avoid direct dependency on CLI command wiring (`TuistKit`) or entry points.
- Keep IO-heavy or integration-specific logic in feature modules (HTTP, Server, Cache).

## Invariants
- Analytics types are Codable and designed for transport to the server.
- Models encode run metadata (command args, environment, git info, cache endpoints).

## Related Context
- Shared utilities: `cli/Sources/TuistSupport/AGENTS.md`
- Project generation: `cli/Sources/TuistGenerator/AGENTS.md`
