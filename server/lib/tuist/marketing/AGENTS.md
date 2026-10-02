# Marketing (Context)

This context owns marketing content aggregation (blog posts, case studies, changelogs).

## Responsibilities
- Load and aggregate content entries, categories, and metadata.
- Provide helpers for blog, case study, and changelog content rendering.
- Provide reusable Open Graph image template components without mapping routes to templates or variables.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- If changes add or modify stored customer data, update `server/data-export.md`.
- Keep generated images out of the application release. The first request renders and stores the image through
  `Tuist.OpenGraphImages`; later requests stream the stored object.
- Controllers and LiveViews own the template choice and variables for their routes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
