# Key Value Store

- The cache is ephemeral; never rely on it for durable state. Redis is explicitly selected with `persist_across_deployments: true`; `cache:` names the Cachex fallback.
- `get/2` and `put/3` handle raised and returned `Redix.ConnectionError`s, preserving the selected fallback and TTL.
- `LoadLimiter` is a storage-independent bounded pool for expensive misses. Coalesce same-key callers, bound pending jobs/waiters and inherit `$callers`. Retain running slots after soft timeouts while remote database work may still run; workers may write through after callers time out. A fill inherits only its first caller's allowlisted observability snapshot, not request metadata, and retains it through `on_error`; the coordinator never adopts tenant context. Isolate tenants in keys; coalesced waiters must not replace the fill's target.

## Replica safety

- Broadcast only `cache: :display` invalidations; prepaid balance reads/refreshes use that dedicated cache. On node join/leave, clear it and the FunWithFlags membership cache, never general `:tuist` request/integration or authentication/license caches.
- Lost broadcasts and fills racing deletion are bounded by display TTL, not strong consistency. Persistent invalidation reports failed Redis deletion after evicting/broadcasting fallback copies.
- `cache_errors: false` excludes `{:error, reason}` results on locked, unlocked and persistent paths. Preserve arbitrary values, including literal `{:ignore, value}` tuples.
- License validation has a separate ten-second retry entry; successful licenses retain normal TTL. These are regenerable views, not authoritative authorization state.
