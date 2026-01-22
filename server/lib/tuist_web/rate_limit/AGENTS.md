# Rate Limit (Web Layer)

This area owns request rate limiting helpers.

## Responsibilities
- Apply auth rate limits with in-memory or Redis-backed token buckets.
- Compute rate limit keys using client IP.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
