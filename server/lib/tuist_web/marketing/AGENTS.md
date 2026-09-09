# Marketing (Web Layer)

This area owns marketing controllers and components for the public site.

## Responsibilities
- Render marketing pages and UI components.
- Bridge marketing content from `Tuist.Marketing` into controllers/views.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.
- `/newsletter/verify` uses `newsletter_root` for confirmation, success, and
  error responses. Keep this transactional page independent of the full
  marketing navigation, decorative image background, and third-party widgets.
  Its native POST form must retain the signed token and CSRF protection.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
