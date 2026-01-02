# Plugs (Web Layer)

This area owns Plug middleware for request processing.

## Responsibilities
- Implement request/response middleware (auth, analytics, rate limiting).
- Enforce cross-cutting concerns before controllers/LiveViews.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
