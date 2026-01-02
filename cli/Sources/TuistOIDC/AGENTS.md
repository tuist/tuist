# TuistOIDC (CLI Module)

This module provides OIDC auth helpers for CLI/server integration.

## Responsibilities
- Implement OIDC auth helpers for CLI/server integration.
- Keep the module cohesive around its named concern

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistServer/AGENTS.md
