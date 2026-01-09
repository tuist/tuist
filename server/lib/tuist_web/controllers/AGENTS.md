# Controllers (Web Layer)

This area owns Phoenix controllers for HTML and API endpoints.

## Responsibilities
- Handle request/response flow and rendering for controller actions.
- Delegate business logic to `server/lib/tuist` contexts.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
