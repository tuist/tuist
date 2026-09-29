# Rate Limit (Web Layer)

This area owns request rate limiting helpers.

## Responsibilities
- Apply all request rate limits through Valkey with a matching in-memory fallback.
- Preserve fixed-window and token-bucket policies across both backends.
- Compute rate limit keys using client addresses and authenticated subjects.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
