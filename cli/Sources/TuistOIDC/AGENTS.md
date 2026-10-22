# TuistOIDC (CLI Module)

This module provides OIDC auth helpers for CLI/server integration.

## Responsibilities
- Fetch OIDC tokens using a bearer request token and audience.
- Accept an explicit `TUIST_OIDC_TOKEN` before provider detection, reject empty values, and keep token contents out of diagnostics. This supports account-configured workload providers with account-wide CI access to current/future projects without provider-specific networking in the CLI. Callers obtain the identity token and set `TUIST_OIDC_ACCOUNT` for custom providers; the server requires an exact issuer/JWKS/audience/claims trust policy. Fly Machines are one example, minting audience `tuist` tokens through their local API.
- Validate token request URLs and surface request failures.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistServer/AGENTS.md

## Invariants
- GitHub Actions OIDC token fetch expects HTTP 200 and a JSON payload with `value`. Explicit workload tokens are supplied directly, not decoded or verified by the CLI; the server enforces provider trust.
- Bearer-token requests use the policy-protected `URLSession.tuistDefault`, not `URLSession.shared`. TLS failures must never trigger plaintext or weaker-session retries.
