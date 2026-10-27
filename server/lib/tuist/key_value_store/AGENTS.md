# Key Value Store (Context)

This context owns key-value caching with Redis and in-memory fallbacks.

## Responsibilities
- Provide `get_or_update` with optional locking.
- Use Redis when available, falling back to Cachex on connection failure. `get/2` and `put/3` handle both raised and returned `Redix.ConnectionError`s, preserving the selected Cachex fallback and TTL.
- Manage cache TTL and key normalization. Redis is explicitly selected with `persist_across_deployments: true`; `cache:` names the Cachex fallback.
- `LoadLimiter` is a storage-independent, bounded pool for expensive misses. It coalesces same-key callers, bounds pending jobs/waiters, inherits `$callers`, and retains running slots after soft timeouts. Never release a slot while remote database work may still be running; workers may write through `KeyValueStore` after callers time out. A fresh fill worker inherits only the first caller's allowlisted observability snapshot (not request metadata), retaining it through `on_error`; the admission coordinator never adopts tenant context. Keys must isolate tenants, and coalesced waiters must not replace the fill's target.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Cache is ephemeral; do not rely on it for durable state.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`

## Replica-safety rollout

Only `cache: :display` invalidations are broadcast to connected nodes. Prepaid balance reads and refreshes use that dedicated cache. On node join/leave, clear it and the FunWithFlags membership cache, never the general `:tuist` request/integration cache or dedicated authentication/license caches. Lost broadcasts and fills racing deletion remain bounded by the display value's TTL, not a strong consistency guarantee. Persistent-key invalidation reports failed Redis deletion after evicting/broadcasting fallback copies. `cache_errors: false` opts out of storing `{:error, reason}` callback results on locked, unlocked and persistent paths. Keep the default arbitrary-value contract, including literal `{:ignore, value}` tuples. License validation has a separate ten-second retry entry, while successful licenses keep their normal TTL. These are regenerable views, not authoritative authorization state.
