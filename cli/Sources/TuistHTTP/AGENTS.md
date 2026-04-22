# TuistHTTP (CLI Module)

This module provides HTTP client helpers used by server and cache integrations.

## Responsibilities
- Provide file upload/download client (`FileClient`) with explicit error modeling.
- Provide middleware and auth helpers for API clients (request IDs, output warnings).

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistServer/AGENTS.md
- cli/Sources/TuistCache/AGENTS.md

## Invariants
- File transfers treat non-2xx responses as fatal errors.
- Default URL session uses explicit request/resource timeouts.
- Default proxy mode comes from runtime HTTP settings, and explicit overrides are resolved when a URL session is created.
