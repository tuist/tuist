# Marketing (Web Layer)

This area owns marketing controllers and components for the public site.

## Responsibilities
- Keep individual changelog entries, including their localized URLs, in the marketing sitemap. Shared canonical URLs must not retain tracking or filtering parameters.
- Browser newsletter issue documents include the shared analytics component; their email versions must omit scripts.
- Render marketing pages and UI components.
- Bridge marketing content from `Tuist.Marketing` into controllers/views.
- Anonymous marketing responses are `public` and stored by shared caches without `Set-Cookie`, so the CSRF token embedded in the HTML (`<meta name="csrf-token">`, hidden `_csrf_token` inputs) belongs to whichever session produced the cached copy and never validates for anyone else. Do not add a CSRF-protected POST that depends on a token from a cacheable page. Endpoints submitted from these pages (newsletter signup and confirm, the One Tap start request) are routed through the `:same_origin_csrf_exemption` pipeline, where `TuistWeb.Plugs.SameOriginCSRFExemptionPlug` accepts browser-proven same-origin requests instead; keep that pipeline on scopes holding only the routes meant to be exempt.
- The newsletter verify pages render the visitor's email and signed token, so `MarketingController` marks them `private, no-store` regardless of sign-in state.
- `TuistWeb.GoogleOneTap` adds Google's browser-mediated account chooser to signed-out marketing pages when Google authentication is configured and enabled. Challenge state and a fresh CSRF token are fetched through an uncacheable same-origin request rather than embedded in cacheable page content.
- Interactive blog diagrams live in `components/` with colocated hooks and styles. `CacheLatencyLab` illustrates one round trip plus transfer time per artifact; keep its assumptions visible and its controls usable with a keyboard.
- `/globe` is the public cache activity display. It follows the marketing page frame (the cache hero skeleton, hairline rows, Noora tokens) but stands alone: no shared navbar, footer or CTA, only the wordmark linking home. The globe is the cache page's `DitherGlobe` hook. `?demo=true` explicitly selects illustrative data; live mode must never fall back to fabricated counts. Reported arcs use backend-estimated country-level origins only for frozen cells first released with at least three contributing accounts and no account supplying more than half the volume, and replay complete reporting windows at least five minutes behind real time. The page also opts into a separate illustrative animation baseline for recently serving regions, independent of measured request volume and backend country-cell publication. Use neutral public copy describing cache activity and measured metrics, never claiming decorative arcs are individual transfers, verified request locations or reported playback. Keep all arc arrivals separate from measured daily counters. Illustrative arcs dispatch no arrivals; only explicit demo arrivals advance illustrative totals. Hit-rate rows consume the snapshot breakdown, preserving dashes for caches without reported opportunities.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.
- The shared `header_background` uses compact derivatives of the original
  soft artwork (960px desktop, 480px mobile). Avoid high-density variants for
  this decorative image: they add transfer and decode cost without useful
  detail. Keep its separate mobile artwork and the shared shell intact.
- Post components must follow the marketing page's color scheme, including
  interactive states. The new Tuist post's Slack card uses `light-dark()` to
  preserve its light palette and adapt to the reader's selected or system theme.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
