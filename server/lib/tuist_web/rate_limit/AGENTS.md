# Rate Limit (Web Layer)

This area owns request rate limiting helpers.

## Shared-store failure policy

- Valkey is authoritative when configured. A real shared denial never falls back. Backend errors, exits and unexpected responses use an explicit outage policy.
- Deny by default. Password login, agent authentication/registration, signup, the pre-authentication Once address guard, Atlas, SCIM, metrics, authorization-denial accounting and public-page challenge verification do not opt into fallback. SCIM and metrics deliberately remain strict even though authenticated.
- Only dashboard checks (including anonymous per-scope aggregation) and authenticated MCP select `failure_policy: :local`. The MCP router authenticates before this limiter; its anonymous branch is a defensive direct-call guard, not pre-authentication credential protection.
- Fallback is fixed-window only. Use `InMemory.Local` directly with `{:fallback, key}`; do not broadcast outage counts through PubSub. Token buckets always deny on shared-store failure.
- Divide the limit by the larger of the configured replica allowance and observed connected-node count. `Tuist.Environment.rate_limit_fallback_replicas/0` reads `Application.get_env(:tuist, :rate_limit_fallback_replicas, 5)`; integers of at least five are valid. Invalid configuration, a zero divided budget or an unavailable local table deny. Deployments expecting more disconnected serving replicas must increase the allowance before scaling.
- This is not an exact global quota: the local allowance is additional to healthy shared admission, restarts reset local counters, and disconnected fleets larger than the allowance can multiply admission. Do not reset fallback counters on backend recovery or changes of failure policy.
- Emit shared-failure telemetry with only algorithm, policy and admission outcome. `Tuist.PromEx.RateLimit` exports the counter without keys, subjects or addresses. Preserve existing HTTP 429/gRPC resource-exhausted response contracts.

## Other responsibilities

- Fixed-window limits and token buckets retain their healthy-store semantics. Each persistent limiter uses a four-client `PartitionSupervisor`, selected directly by caller PID through `RedisPool`; there is no checkout mailbox, decision cache, quota reservation or failover retry. Every request still executes Hammer's original algorithm against the same shared namespace, with the original 500 ms timeout. Fixed-window get/inc/set and token-bucket get retain their existing contracts so mixed versions share counters.
- Installations without Valkey retain the existing approximate, eventually consistent in-memory admission. PubSub does not make that a strict shared budget.
- Redis clients start before the endpoint, Oban and gRPC ingress, and stop after them. This is lifecycle ordering, not a backend-readiness gate. Both limiter pools together open eight backend connections per process instead of two; the unrelated general Redis client is unchanged. Each pool retains the previous client's five-second shutdown budget rather than multiplying it across connections. Missing pools and client-generation races must follow the existing unavailable policy, never become uncoordinated admissions.
- Compute keys using trusted client addresses and authenticated subjects. Account subjects use `AuthenticatedAccount.account.id`, not a nonexistent wrapper `id`.

## Boundaries

- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context

- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
