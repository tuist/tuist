# TuistHTTP (CLI Module)

This module provides HTTP client helpers used by server and cache integrations.

## Responsibilities
- Implement HTTP client helpers used by server and cache integrations.
- Keep the module cohesive around its named concern

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistServer/AGENTS.md
- cli/Sources/TuistCache/AGENTS.md
