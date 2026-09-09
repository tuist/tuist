# Marketing (Web Layer)

This area owns marketing controllers and components for the public site.

## Responsibilities
- Render marketing pages and UI components.
- Bridge marketing content from `Tuist.Marketing` into controllers/views.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.
- The shared `header_background` component selects responsive WebP derivatives
  with `srcset` and `sizes="100vw"`; keep the separate mobile artwork and the
  shared shell intact when tuning image delivery.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
