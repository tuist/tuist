# Rate-Limit Backends

`Tuist.RateLimit.hit/2` owns backend selection and shared-store failure handling. Which callers opt into which policy is documented with the web limiters in `server/lib/tuist_web/rate_limit/AGENTS.md`.

## Shared-store failure policy

- Valkey is authoritative when configured. A real shared denial never falls back. Backend errors, exits and unexpected responses use an explicit outage policy.
- Deny by default. `fallback: false` returns `{:error, :unavailable}` on backend failure instead of a denial, overrides any local policy, never admits via local counters, and emits shared-failure telemetry with the deny policy and error outcome. Healthy shared denials retain their retry interval.
- Fallback is fixed-window only and requires `failure_policy: :local`. Use `InMemory.Local` directly with `{:fallback, key}`; do not broadcast outage counts through PubSub. Token buckets always deny on shared-store failure.
- Divide the limit by the larger of the configured replica allowance and observed connected-node count. `Tuist.Environment.rate_limit_fallback_replicas/0` reads `Application.get_env(:tuist, :rate_limit_fallback_replicas, 5)`; integers of at least five are valid. Invalid configuration, a zero divided budget or an unavailable local table deny. Deployments expecting more disconnected serving replicas must increase the allowance before scaling.
- This is not an exact global quota: the local allowance is additional to healthy shared admission, restarts reset local counters, and disconnected fleets larger than the allowance can multiply admission. Do not reset fallback counters on backend recovery or changes of failure policy.
- Emit shared-failure telemetry with only algorithm, policy and admission outcome. `Tuist.PromEx.RateLimit` exports the counter without keys, subjects or addresses.

## Backends

- The Valkey key prefixes stay `TuistWeb.RateLimit.PersistentFixedWindow` and `TuistWeb.RateLimit.PersistentTokenBucket` even though the modules moved. Changing them orphans live counters and splits admission between old and new replicas during a rolling upgrade. The in-memory PubSub topic (`"__ratelimit"`) and its message tuples are a cross-version contract for the same reason.
- Fixed-window limits and token buckets retain their healthy-store semantics. Each persistent limiter uses a four-client `PartitionSupervisor`, selected directly by caller PID through `RedisPool`; there is no checkout mailbox, decision cache, quota reservation or failover retry. Every request still executes Hammer's original algorithm against the same shared namespace, with the original 500 ms timeout. Fixed-window get/inc/set and token-bucket get retain their existing contracts so mixed versions share counters.
- Installations without Valkey retain the existing approximate, eventually consistent in-memory admission. PubSub does not make that a strict shared budget.
- Redis clients start before the endpoint, Oban and gRPC ingress, and stop after them. This is lifecycle ordering, not a backend-readiness gate. Both limiter pools together open eight backend connections per process instead of two; the unrelated general Redis client is unchanged. Each pool retains the previous client's five-second shutdown budget rather than multiplying it across connections. Missing pools and client-generation races must follow the existing unavailable policy, never become uncoordinated admissions.
