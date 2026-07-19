# Marketing (Context)

This context owns marketing content aggregation (blog posts, case studies, changelogs).

## Responsibilities
- Load and aggregate content entries, categories, and metadata.
- Provide helpers for blog, case study, and changelog content rendering.
- Resolve marketing Open Graph image paths into runtime rendering specifications. Rendering inputs must be part of the
  content key so changes produce a new immutable URL.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- If changes add or modify stored customer data, update `server/data-export.md`.
- Keep generated images out of the application release. The first request renders and stores the image through
  `Tuist.OpenGraphImages`; later requests stream the stored object.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
