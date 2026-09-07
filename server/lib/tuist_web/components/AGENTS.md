# Components (Web Layer)

This area owns shared UI components for LiveView and templates.

## Responsibilities
- Provide reusable UI components (navigation, auth components, forms).
- `BuildTimeline` uses Noora cards, search, and empty states around the Xcode build timeline hook, with translated controls and accessible step details in a resizable right-hand inspector shown only when a step is selected, including its recorded log loaded on demand.
- Keep rendering logic here; avoid domain logic.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
