# Marketing (Web Layer)

This area owns marketing controllers and components for the public site.

## Responsibilities
- Render marketing pages and UI components.
- Bridge marketing content from `Tuist.Marketing` into controllers/views.
- Interactive blog diagrams live in `components/` with colocated hooks and styles. `CacheLatencyLab` illustrates one round trip plus transfer time per artifact; keep its assumptions visible and its controls usable with a keyboard.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.
- The shared `header_background` uses compact derivatives of the original
  soft artwork (960px desktop, 480px mobile). Avoid high-density variants for
  this decorative image: they add transfer and decode cost without useful
  detail. Keep its separate mobile artwork and the shared shell intact.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
