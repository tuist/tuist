# TuistOIDC (CLI Module)

This module provides OIDC auth helpers for CLI/server integration.

## Responsibilities
- Fetch OIDC tokens using a bearer request token and audience.
- Accept an explicit `TUIST_OIDC_TOKEN` before provider detection, reject empty values, and keep token contents out of diagnostics. This supports Fly Machines without requiring the CLI to talk to a Unix socket; callers mint tokens with audience `tuist` through Fly's local API.
- Validate token request URLs and surface request failures.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistServer/AGENTS.md

## Invariants
- GitHub Actions OIDC token fetch expects HTTP 200 and a JSON payload with `value`. Explicit workload tokens are supplied directly, not decoded or verified by the CLI; the server enforces provider trust.
