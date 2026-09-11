# Server Private Assets (Migrations, Seeds)

This directory contains database migrations and other private assets.

## Responsibilities
- PostgreSQL migrations: `server/priv/repo/migrations`
- ClickHouse migrations: `server/priv/ingest_repo/migrations`
- Marketing changelog entries: `server/priv/marketing/changelog`
- All served raster images under `priv/static` are checked by
  `mise run marketing:image-budget` (requires ImageMagick).
  Signup artwork is WebP at twice its rendered width; keep replacements within
  the 500 KiB static-image budget (GIFs allow 3200 KiB).
- Shared `hero-background*` images have a stricter 20 KiB budget and a maximum
  of 1024 pixels per dimension. Served derivatives are 960px desktop and 480px
  mobile; regeneration sources live outside the served tree in
  `server/assets/marketing/source-images`. Open Graph assets are resized to
  1200px wide while retaining their aspect ratio.

## Demo Data
- Gradle build seeds populate requested tasks from their generated task list, preferring assemble entry points. Keep build metadata consistent with the tasks shown in analytics.
- The standard `repo/seeds.exs` creates `tuist/xcode-comparison` and `tuist/bazel-comparison` with matching test histories, including healthy, flaky, muted, and skipped cases. Keep their scenarios aligned for visual comparison; rerunning seeds preserves existing comparison runs.

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

- GitLab runner assignments retain encrypted execution payloads temporarily; migration changes must preserve the documented cleanup and disjoint job-ID range. Connections are unique per account and instance URL; routing errors are retained as non-secret assignment metadata.

- Gradle build start timestamps are nullable for backward compatibility and use `Nullable(DateTime64(6))` in ClickHouse. They align recorded operations and machine samples; no upload-time backfill is valid.

- GitLab live-assignment expiry and connection lookups use concurrent partial indexes restricted to `payload IS NOT NULL`; retain historical metadata without making polling scan completed jobs.

- Migration versions must be unique within each repository even when already applied. The GitLab routing migration uses `20260911080000`; its prototype `20260910160000` collided with main’s Bazel profile migration. Any prototype database needs its version history reconciled against the actual schema before migrating.
