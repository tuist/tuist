# TuistOIDC (CLI Module)

This module provides OIDC auth helpers for CLI/server integration.

## Responsibilities
- Fetch OIDC tokens using a bearer request token and audience.
- Validate token request URLs and surface request failures.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistServer/AGENTS.md

## Invariants
- OIDC token fetch expects HTTP 200 and a JSON payload with `value`.
