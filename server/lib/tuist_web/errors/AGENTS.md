# Errors (Web Layer)

This area owns the web-facing errors concerns for the server.

## Responsibilities
- Implement errors for the Phoenix web layer.
- Keep web-specific behavior here, delegating business logic to `server/lib/tuist`.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
