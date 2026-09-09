# Server Private Assets (Migrations, Seeds)

This directory contains database migrations and other private assets.

## Responsibilities
- PostgreSQL migrations: `server/priv/repo/migrations`
- ClickHouse migrations: `server/priv/ingest_repo/migrations`
- Marketing changelog entries: `server/priv/marketing/changelog`
- Marketing and app image assets are checked by `mise run marketing:image-budget`.
  Signup artwork is WebP at twice its rendered width; keep replacements within
  the static-image budget.
- The shared marketing header keeps the original `hero-background.webp` and
  `hero-background-sm.webp` artwork as regeneration sources, with compact
  derivatives at 960px desktop and 480px mobile. Regenerate from those originals
  with `magick INPUT -resize WIDTHx -quality 85 -define webp:method=6 OUTPUT`.

## Demo Data
- Gradle build seeds populate requested tasks from their generated task list, preferring assemble entry points. Keep build metadata consistent with the tasks shown in analytics.

## Guardrails
- If you change stored customer data, update `server/data-export.md`.
- Use `:timestamptz` for migration timestamps (per Credo rules).
- Bound ClickHouse `INSERT SELECT` backfills with explicit read/insert thread,
  block-size, and query-memory settings, including catch-up passes. Copying
  one partition at a time alone does not bound their peak memory usage.
- Add marketing changelog entries only for customer-facing product changes that are ready to announce.
- Do not add product changelog entries for ops-only, admin-only, internal rollout, infrastructure-only, or otherwise unannounced functionality.

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`
