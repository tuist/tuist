# TuistOIDC (CLI Module)

This module provides OIDC auth helpers for CLI/server integration.

## Responsibilities
- Fetch OIDC tokens using a bearer request token and audience.
- Validate token request URLs and surface request failures.
- Report whether the CI provider can mint a new OIDC token mid-job (`canFetchFreshOIDCToken`, GitHub Actions only); providers that expose one token per job (CircleCI, Bitrise) can't renew an exchanged account token.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistServer/AGENTS.md

## Invariants
- OIDC token fetch expects HTTP 200 and a JSON payload with `value`.
