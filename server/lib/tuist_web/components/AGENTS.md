# Components (Web Layer)

This area owns shared UI components for LiveView and templates.

## Responsibilities
- Provide reusable UI components (navigation, auth components, forms).
- Keep rendering logic here; avoid domain logic.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
