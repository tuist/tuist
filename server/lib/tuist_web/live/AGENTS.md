# Live (Web Layer)

This area owns LiveView pages and components for the web UI.

## Responsibilities
- Render LiveView pages and handle UI events.
- Orchestrate UI state while delegating domain operations to `server/lib/tuist`.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
