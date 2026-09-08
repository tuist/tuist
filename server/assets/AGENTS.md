# Server Assets (JS/CSS)

This directory contains frontend assets for the Phoenix app (LiveView, marketing, apidocs).

## Responsibilities

- JS/CSS sources built by esbuild.
- `app/js/BuildTimeline.js` renders the Xcode timeline with a viewport height independent of content, viewport culling, horizontal scrolling with an always-visible Noora indicator shared with tables (a full-width thumb when the build fits), and readable lanes within the fixed viewport without vertical scrolling; `BuildTimelineDensity.mjs` groups dense overlaps into occupied time buckets by category, compact execution lanes that repack for the selected interval, drag-to-focus selection on the chart and ruler (via `BuildTimelineFocus.mjs`), pointer-anchored trackpad pinch zoom (via `BuildTimelineZoom.mjs`), a cursor time guide, server-side search and target selection across all steps, keyboard inspection, and bounded asynchronous range transport and debounced, asynchronous plain-text step logs with stale-response protection. `BuildTimelineResize.mjs` lets users drag or keyboard-adjust the inspector divider while keeping space for the chart. Its pure interval layout lives in `BuildTimelineModel.mjs` and is tested in server CI with `node --test assets/app/js/*.test.mjs`. `BuildTimelineInteractions.mjs` provides cancellable debounce, lane-indexed hit testing, and directional keyboard navigation. Theme tokens are cached until the theme or fonts change.
- Marketing imports only the Noora tooltip hook through the `noora/hooks` source
  alias. Add hooks as templates need them instead of importing the full runtime,
  which brings ECharts into pages without charts. Noora CSS remains shared.
  The Docker asset builder must copy Noora's node_modules from the npm stage
  alongside its built assets so those source imports resolve their dependencies.
- Asset builds for development and production.
- Timeline logs preserve source lines and scroll horizontally; their full height participates in the inspector's vertical scrolling.
- Timeline selection persists when scrolling or zooming moves the step outside the visible range, keeping its metadata and log open.
- Browser real user monitoring. `shared/js/analytics.js` initializes the Grafana
  Faro Web SDK from the `globalThis.analytics` config that
  `TuistWeb.LayoutComponents.head_analytics_scripts` renders, and every bundle
  calls `initAnalytics()`. The SDK is an npm dependency bundled into our own
  JavaScript rather than a script from a CDN, so the page loads no third-party
  origin and the Content Security Policy stays on `'self'`. Web vitals feed the
  LCP alerts documented in `infra/helm/k8s-monitoring/alerts.md`.

## Related Context

- Web layer: `server/lib/tuist_web/AGENTS.md`
