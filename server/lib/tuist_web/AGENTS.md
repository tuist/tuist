# TuistWeb (Controllers, LiveView, API)

- Keep request handling, rendering, and UI state here; delegate domain operations to `server/lib/tuist` contexts. JS/CSS belongs in `server/assets`.
- Authorize channel access via `Tuist.Authorization`.

## Public representations

- Marketing landing-page URLs negotiate authored English decision guides with `Accept: text/markdown`; `/marketing-markdown[/<page>]` offers discoverable, header-free access. Legal wording is preserved and `/marketing-markdown/source/<page>` exposes original statements where guides replace company-page copy. Keep these routes ahead of dynamic account/project scopes, with marketing robots metadata and on-premise forwarding. Public project Markdown requires a separate authorized data-snapshot design, not static marketing overrides.
- Controllers and LiveViews choose their Open Graph image template and variables. The shared image route only verifies
  the signed variables, renders on a cache miss, and serves the content-addressed object.

## Route metadata

- `server/lib/tuist_web/router.ex` route metadata feeds the runtime `robots.txt` Content-Usage and Disallow entries.
- When adding or changing public marketing/docs routes, keep `metadata: %{type: :marketing}` or `:docs` accurate.
- For public `GET` routes that should appear in `robots.txt` Content-Usage, define that configuration in the router with `metadata: %{robots_txt: [train_ai: true, search: true]}`.
- Routes without `:robots_txt` metadata default to `Disallow` entries derived from the router.
- If a route should not contribute any `robots.txt` entry, opt it out explicitly with `metadata: %{robots_txt: false}`.

## Search Indexing
- Only public-project overview roots opt in with `public_project: true, robots_txt: false` metadata. Visibility and authorization still decide whether a response can be indexed. Deeper dashboards, analytics, previews, settings and downloads remain noindex and retain their challenge gates; the project sitemap lists overview roots only.
- Public HTML `lang`, `hreflang` and structured-data language values use `Locale.language_tag/1`, keeping Gettext locale names and existing URLs unchanged. Documentation article alternates must come from exact available slugs, not English fallback lookups; only emit English `x-default` when that article exists. `DocsLive` redirects untranslated article requests to their English source while preserving the query, rather than indexing English under another language's URL. Documentation overview alternates remain independent of article availability.

## Request Privacy
- `Endpoint.scrub_sentry_headers/1` excludes credentials, operator grants, and `x-tuist-actor-id` from Sentry request contexts. Actor labels are unverified, potentially personal metadata and must not enter error-tracker request headers.

## Browser Telemetry
- `BrowserTelemetry.Enrichment` adds reserved measurement context using route metadata and gateway-observed authentication. Browser URL/session/navigation fields remain untrusted; never equate authentication or metadata completeness with humanity.
- Preserve raw LCP values and attribution. Keep the schema contract and staged alert rollout in `infra/helm/k8s-monitoring/browser-rum.md` aligned.

## Public Project Overview
- `PublicOverviewCache` serves the same default public project overview to anonymous humans and crawlers, including resolved data in the initial HTML. Signed-in users always use fresh, connected-only dashboard loading and do not share the anonymous admission pool. Use bounded read-through caching, never scheduled prefetches or request-derived filter keys. Tracking parameters do not change cached data; filtered roots and `/analytics` remain challenged for unverified anonymous visitors.
- Private accounts with enforced SSO are not eligible for the anonymous root bypass, even if the project is public. Public accounts retain the existing anonymous SSO exemption.
- Keys include stable project ID, build system, current handles and locale. Authorize current project visibility before serving cached content; connected overview patches reauthorize before the scope challenge check as well as before loading, so project visibility or account/SSO transitions cannot expose warmed data or switch an exempt socket into uncached loading.
- Store widget values through `Tuist.KeyValueStore` with a 10-minute TTL and explicit shared Redis selection. The Cachex fallback uses the evented LRW eviction policy with a 256-entry target; skip caching values above 128 KiB (~32 MiB serialized data at the target, excluding cache overhead and transient pruning overshoot). Redis capacity follows its configured eviction policy. Misses use a separate `LoadLimiter`: two workers, bounded pending jobs/waiters, 30-second queue waits and ten-second soft worker waits. The longer queue budget lets cold pages resolve their widget groups without competing themselves out of the initial HTML, while query concurrency remains capped at two. Never run database work outside admission on cache failure.
- Dispatch initial widget loads together. Connected widgets retry transient overload/timeouts with bounded backoff for 30 seconds and recheck current authorization/public eligibility before retrying. Loader exceptions are reported once per coalesced load. If synchronous bundle app options fail admission, retry the bounded lookup inside the already-admitted bundle loader rather than replaying the captured error or acquiring a nested slot.
- Reject non-default mount parameters and the `:analytics` live action before layout initialization, so unverified joins cannot trigger selected-run lookups. Signed image URLs remain protected by signature/visibility checks and an origin rate limit.

## Asynchronous Loading
- Let a failing load fail. A function that raises leaves the assign in
  `AsyncResult.failed`, which the template renders with
  `TuistWeb.Components.ErrorCardSection` and which reaches the error tracker.
  Returning an empty result instead renders an empty page that no alert sees.

## OpenAPI generation

- Update controller schemas, then run `mise run generate-api-cli-code` from `server/` to export the spec and regenerate the Swift client.
- Do not hand-edit `cli/Sources/TuistServer/OpenAPI/server.yml` or the generated `Types.swift` / `Client.swift`.

## Focused guidance

- Public schema compatibility: [api/AGENTS.md](api/AGENTS.md).
- Request/authentication boundaries: [controllers/AGENTS.md](controllers/AGENTS.md), [plugs/AGENTS.md](plugs/AGENTS.md), [rate_limit/AGENTS.md](rate_limit/AGENTS.md).
- UI behavior: [components/AGENTS.md](components/AGENTS.md), [live/AGENTS.md](live/AGENTS.md), [marketing/AGENTS.md](marketing/AGENTS.md).
- Browser telemetry: [browser_telemetry/AGENTS.md](browser_telemetry/AGENTS.md).
