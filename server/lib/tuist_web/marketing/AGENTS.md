# Marketing (Web Layer)

This area owns marketing controllers and components for the public site.

## Responsibilities
- Render marketing pages and UI components.
- Bridge marketing content from `Tuist.Marketing` into controllers/views.
- `/globe` is the public conference cache display. It uses the marketing root layout without the standard navigation, footer, or support chat. `?demo=true` explicitly selects illustrative data; live mode must never fall back to fabricated counts.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
