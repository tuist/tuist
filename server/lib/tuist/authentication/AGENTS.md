# Authentication (Context)

This context owns authentication flows and token handling.

## Responsibilities
- Resolve authenticated subjects from JWTs, user tokens, and account/project tokens.
- `TokenVerificationCache` caches successful bcrypt proofs only, keyed by the SHA-256 digest of the complete verification input and stored hash. Token rows, expiry, activity, scopes and authorization remain authoritative per request. Never cache subjects or failed proofs here. The dedicated local cache coalesces concurrent misses, expires proofs after a minute, caps retained entries, and is not cleared by display-cache invalidation or cluster membership changes.
- Refresh tokens while updating `preferred_username` claims.
- Encode/sign tokens with recent accessible project handles.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- If changes add or modify stored customer data, update `server/data-export.md`.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
