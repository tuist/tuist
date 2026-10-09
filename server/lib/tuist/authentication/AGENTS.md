# Authentication (Context)

This context owns authentication flows and token handling.

## Responsibilities
- Resolve authenticated subjects from JWTs, user tokens, and account/project tokens.
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

## Replica-safety rollout

The dedicated node-local `token_verification` cache stores successful bcrypt proofs only, keyed by the full verification input and stored hash. Its one-minute TTL, per-key single-flight, failure rejection and scheduled 10,000-entry pruning must remain covered by call-count regressions. The initial proof-cache rollout deliberately keeps the HTTP subject cache unchanged; it does not yet promise immediate HTTP revocation. Authentication PromEx metrics count uncached bcrypt calls and duration per replica without credential labels.
