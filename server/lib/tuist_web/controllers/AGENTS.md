# Controllers (Web Layer)

This area owns Phoenix controllers for HTML and API endpoints.

## Responsibilities
- `BuildController.timeline/2` returns full build step metadata without logs, scoped to the authorized project/build. Bandit negotiates HTTP compression; the response uses `private, no-store`.
- Handle request/response flow and rendering for controller actions.
- Delegate business logic to `server/lib/tuist` contexts.
- Keep the machine-readable auth.md document, discovery metadata, and agent-auth response envelopes synchronized when the protocol surface changes.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
