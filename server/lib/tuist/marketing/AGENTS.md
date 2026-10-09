# Marketing (Context)

This context owns marketing content aggregation (blog posts, case studies, changelogs).

## Responsibilities
- Load and aggregate content entries, categories, and metadata.
- Provide helpers for blog, case study, and changelog content rendering.
- Provide reusable Open Graph image template components without mapping routes to templates or variables.
- `CacheGlobe` aggregates managed public-region daily download requests and bytes plus their five-minute totals from existing Kura usage rollups, supporting browser-side counter extrapolation without additional queries. It also aggregates daily hit rates from command events, Gradle build summaries and Bazel action-cache lookups. Weight the overall rate by opportunities and preserve missing rates as unavailable. `CacheGlobeRefreshWorker` (Oban unique, hosted cron) is the sole ClickHouse writer into `KeyValueStore`; `Stats` only reads that cache about every 30 seconds and publishes on the separate `cache_globe` topic. `CacheGlobeOrigins` allocates complete public download windows across each account's own seven-date origin mix (runs first, resolutions only when no runs exist), then strips account identifiers and collapses subdivisions to country anchors from `CacheGlobeLocations`. First publish only bounded country-to-region reporting-window cells with at least three distinct contributing accounts and no account above 50% of the estimated volume, never random fallback locations, raw IPs or customer identifiers. Stored unmapped labels and sparse cells are omitted; shares normalize only attributed observations, not unknown unrecorded traffic. The unique worker freezes released cells in a bounded 20-minute shared Redis journal before publishing; never revise their volume after late reports, use per-replica journal fallback, or re-release pre-watermark windows after journal loss. Without shared Redis, publish counters but no live country cells. Origin and journal failures must not block measured totals. The canvas replays each reporting window with a delay of `max(300, window_seconds + 240)` seconds, leaving at least four minutes after closing for the reporting pipeline; estimated arcs must not increment live counters. See [cache-globe.md](cache-globe.md) for metric semantics, query bounds and visual references.

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

## Replica-safety rollout

Expensive stats polling elects one connected global registrant. Resolve partition conflicts by deterministically selecting a pid and notifying the loser, never killing a supervised Stats process. Followers consume broadcasts; cache-globe polling remains read-only and keeps its existing behavior.
