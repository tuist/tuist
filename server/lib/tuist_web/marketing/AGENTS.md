# Marketing (Web Layer)

This area owns marketing controllers and components for the public site.

## Responsibilities
- Render marketing pages and UI components.
- Bridge marketing content from `Tuist.Marketing` into controllers/views.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.
- The shared `header_background` uses compact derivatives of the original
  soft artwork (960px desktop, 480px mobile). Avoid high-density variants for
  this decorative image: they add transfer and decode cost without useful
  detail. Keep its separate mobile artwork and the shared shell intact.
- Post components must follow the marketing page's color scheme, including
  interactive states. The new Tuist post's Slack card uses `light-dark()` to
  preserve its light palette and adapt to the reader's selected or system theme.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
