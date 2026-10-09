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

- The proof cache uses `SingleFlight`, not Cachex's shared Courier. Warm reads access ETS directly; atomic ETS claims elect an independent coordinator/fill worker per cold key. The claims-table GenServer is lifecycle-only and receives no request messages. Monitors share results without a central dispatch/fan-out mailbox. A finite fill deadline, worker/owner failure cleanup and generation-specific claim-table IDs prevent stuck or orphaned work. No failed result is retained. Cache and claim ownership restart together. Structural coverage suspends both the table owner and Courier while 64 different cold keys and warm hits complete. This removes the shared mailbox, not finite ETS/CPU capacity.

- A proof-cache timeout, restart window or failed fill raises `UnavailableError`, never a computed mismatch. Propagate it as HTTP 503 / gRPC unavailable without direct bcrypt fallback. A waiter can retry another flight's failure within its own original budget, with finite retries. Publication checks the claim and deadline in the worker and writes through the captured data-table ID, not a reusable name; a stalled coordinator cannot publish across restart. Cancellation still discards unfinished work, and cold-work reuse is a separate measured policy decision.
