# Key Value Store (Context)

This context owns key-value caching with Redis and in-memory fallbacks.

## Responsibilities
- Provide `get_or_update` with optional locking.
- Use Redis when available, falling back to Cachex on connection failure.
- Manage cache TTL and key normalization.

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
