# Key Value Store (Context)

This context owns key-value caching with Redis and in-memory fallbacks.

## Responsibilities
- Provide `get_or_update` with optional locking.
- Use Redis when available, falling back to Cachex on connection failure. `get/2` and `put/3` handle both raised and returned `Redix.ConnectionError`s, preserving the selected Cachex fallback and TTL.
- Manage cache TTL and key normalization. Redis is explicitly selected with `persist_across_deployments: true`; `cache:` names the Cachex fallback.
- `LoadLimiter` is a storage-independent, bounded pool for expensive misses. It coalesces same-key callers, bounds pending jobs/waiters, inherits `$callers`, and retains running slots after soft timeouts. Never release a slot while remote database work may still be running; workers may write through `KeyValueStore` after callers time out.

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

Display invalidation is broadcast to connected nodes. On node join/leave, clear the display cache and FunWithFlags membership cache, never the dedicated immutable token-proof or license caches. Persistent-key invalidation also removes the shared Redis value. These are regenerable views, not authoritative authorization state.
