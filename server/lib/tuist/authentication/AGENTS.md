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
- Production-cost proof-cache coverage runs in ExUnit using an explicit rounds-12 hash and exactly one real verification for 2,000 lookups at concurrency 64. Keep shared bcrypt configuration unchanged; use `Mimic.call_original/3`, not VM-wide tracing or latency assertions.
- If changes add or modify stored customer data, update `server/data-export.md`.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`

## Replica-safety rollout

The dedicated node-local `token_verification` cache stores successful bcrypt proofs only, keyed by the full verification input and stored hash. Its one-minute TTL, per-key single-flight, failure rejection and scheduled 10,000-entry pruning must remain covered by call-count regressions. The initial proof-cache rollout deliberately keeps the HTTP subject cache unchanged; it does not yet promise immediate HTTP revocation. Authentication PromEx metrics count uncached bcrypt calls and duration per replica without credential labels. Authorization-result caching is removed in this first rollout: account-based keys can let one credential borrow another credential's scopes/project grants. Keep the same-account read/write credential regression. Subject caching still protects warm token reads; user permission checks may perform role queries and require observation.
