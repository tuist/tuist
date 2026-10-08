# TuistWeb (Controllers, LiveView, API)

This directory contains the web interface: Phoenix controllers, LiveView, and API endpoints.

## Responsibilities
- HTTP routing, controllers, and API surface.
- LiveView components for the UI and marketing site.
- Controllers and LiveViews choose their Open Graph image template and variables. The shared image route only verifies
  the signed variables, renders on a cache miss, and serves the content-addressed object.

## Route Metadata
- `server/lib/tuist_web/router.ex` route metadata feeds the runtime `robots.txt` Content-Usage and Disallow entries.
- When adding or changing public marketing/docs routes, keep `metadata: %{type: :marketing}` or `:docs` accurate.
- For public `GET` routes that should appear in `robots.txt` Content-Usage, define that configuration in the router with `metadata: %{robots_txt: [train_ai: true, search: true]}`.
- Routes without `:robots_txt` metadata default to `Disallow` entries derived from the router.
- If a route should not contribute any `robots.txt` entry, opt it out explicitly with `metadata: %{robots_txt: false}`.

## Search Indexing
- Informational public-project LiveViews opt in with `public_project: true, robots_txt: false` metadata. Visibility and authorization still decide whether a response can be indexed; do not opt settings, connection flows, or raw downloads into indexing.

## Browser Telemetry
- `BrowserTelemetry.Enrichment` adds reserved measurement context using route metadata and gateway-observed authentication. Browser URL/session/navigation fields remain untrusted; never equate authentication or metadata completeness with humanity.
- Preserve raw LCP values and attribution. Keep the schema contract and staged alert rollout in `infra/helm/k8s-monitoring/browser-rum.md` aligned.

## Public Project Overview
- `PublicOverviewCache` serves the same default public project overview to humans and crawlers, including resolved data in the initial HTML. Use bounded read-through caching, never scheduled prefetches or request-derived filter keys. Tracking parameters do not change cached data; filtered roots and `/analytics` remain challenged for unverified anonymous visitors.
- Private accounts with enforced SSO are not eligible for the anonymous root bypass, even if the project is public. Public accounts retain the existing anonymous SSO exemption.
- Keys include stable project ID, build system, current handles and locale. Authorize current project visibility before serving cached content; connected overview patches reauthorize before the scope challenge check as well as before loading, so project visibility or account/SSO transitions cannot expose warmed data or switch an exempt socket into uncached loading.
- Store widget values through `Tuist.KeyValueStore` with a 10-minute TTL and explicit shared Redis selection. The Cachex fallback uses the evented LRW eviction policy with a 256-entry target; skip caching values above 128 KiB (~32 MiB serialized data at the target, excluding cache overhead and transient pruning overshoot). Redis capacity follows its configured eviction policy. Misses use a separate `LoadLimiter`: two workers, bounded pending jobs/waiters, three-second queue waits and ten-second soft worker waits. Never run database work outside admission on cache failure.
- Dispatch initial widget loads together. Connected widgets retry transient overload/timeouts with bounded backoff for 30 seconds and recheck current authorization/public eligibility before retrying. Loader exceptions are reported once per coalesced load.
- Reject non-default mount parameters and the `:analytics` live action before layout initialization, so unverified joins cannot trigger selected-run lookups. Signed image URLs remain protected by signature/visibility checks and an origin rate limit.

## Asynchronous Loading
- Let a failing load fail. A function that raises leaves the assign in
  `AsyncResult.failed`, which the template renders with
  `TuistWeb.Components.ErrorCardSection` and which reaches the error tracker.
  Returning an empty result instead renders an empty page that no alert sees.

## Boundaries
- Business logic should remain in `server/lib/tuist`.
- Frontend assets (JS/CSS) are in `server/assets`.

## Related Context (Downlinks)
- Browser telemetry: `server/lib/tuist_web/browser_telemetry/AGENTS.md`
- Api: `server/lib/tuist_web/api/AGENTS.md`
- Channels: `server/lib/tuist_web/channels/AGENTS.md`
- Components: `server/lib/tuist_web/components/AGENTS.md`
- Controllers: `server/lib/tuist_web/controllers/AGENTS.md`
- Errors: `server/lib/tuist_web/errors/AGENTS.md`
- Helpers: `server/lib/tuist_web/helpers/AGENTS.md`
- Live: `server/lib/tuist_web/live/AGENTS.md`
- Marketing: `server/lib/tuist_web/marketing/AGENTS.md`
- Plugs: `server/lib/tuist_web/plugs/AGENTS.md`
- Rate Limit: `server/lib/tuist_web/rate_limit/AGENTS.md`
- Utilities: `server/lib/tuist_web/utilities/AGENTS.md`
- Websocks: `server/lib/tuist_web/websocks/AGENTS.md`

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`
- Assets pipeline: `server/assets/AGENTS.md`
