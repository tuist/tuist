# Marketing (Context)

This context owns marketing content aggregation (blog posts, case studies, changelogs).

## Responsibilities
- Load and aggregate content entries, categories, and metadata.
- Provide helpers for blog, case study, and changelog content rendering.
- Provide reusable Open Graph image template components without mapping routes to templates or variables.
- `CacheGlobe` aggregates managed public-region download requests from existing Kura usage rollups and daily hit rates from command events, Gradle build summaries and Bazel action-cache lookups. Weight the overall rate by opportunities and preserve missing rates as unavailable. `CacheGlobeRefreshWorker` (Oban unique, hosted cron) is the sole ClickHouse writer into `KeyValueStore`; `Stats` only reads that cache about every 30 seconds and publishes on the separate `cache_globe` topic. Keep customer identifiers out of this public snapshot; see [cache-globe.md](cache-globe.md) for metric semantics and visual references.
- `Overdrive` curates popular open source projects that Tuist forked and wired up to Tuist (`/overdrive`). Entries live in the module and name their upstream repository; copy must present them as Tuist's showcase forks, never as projects the upstream maintainers run on Tuist. An entry only appears while its Tuist project is public. Stats are the fork's last 30 days, cached for an hour, and zeros read as missing. `Overdrive.OgImage` is the per-project share card; its numbers are part of the image key so the card re-renders when they change.

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
