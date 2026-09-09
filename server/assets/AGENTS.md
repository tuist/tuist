# Server Assets (JS/CSS)

This directory contains frontend assets for the Phoenix app (LiveView, marketing, apidocs).

## Responsibilities

- Timeline summary values (elapsed time, step count and target count) use small decorative separator dots.
- Timeline metrics use a responsive 2×2 grid with independent 120px plots and subtle 2px card corners; the build-step viewport stays 600px tall. Search and the step legend sit above the step lanes below the metric grid, outside chart gesture handling, with a time ruler for each section.
- The inspector and its resize divider align with the top of the step chart section (including search and legend) and span that section only, keeping details below the metric grid. Step and metric charts share the same Noora border with a 2px radius.
- `BuildTimelineMetrics.mjs` renders CPU, memory, network and disk tracks using the same time range as build steps; each plot has its own time ruler, synchronized cursor and range-selection overlay, with coordinates scaled to its own width. Noora-styled chart cards use taller line plots, horizontal gridlines, and purple/blue series. Metric hover values appear only in each chart’s top-right readout, including both network/disk directions; floating tooltips are reserved for build steps. The initial and maximum zoom-out both show the entire build. Failed hook initialization cleans up listeners and indicators and hides partially mounted content. Samples are loaded once, culled by binary search, and keep stable scales across zooms; missing samples and collection gaps are not shown as zero readings.

- JS/CSS sources built by esbuild.
- `app/js/BuildTimeline.js` renders the Xcode timeline with a viewport height independent of content, viewport culling, horizontal scrolling with an always-visible Noora indicator shared with tables (a full-width thumb when the build fits), and readable lanes within the fixed viewport without vertical scrolling; `BuildTimelineDensity.mjs` preserves individual overlap lanes, compressing excess concurrency below the readable upper lanes, compact execution lanes that repack for the selected interval, drag-to-focus selection on the chart and ruler (via `BuildTimelineFocus.mjs`), pointer-anchored trackpad pinch zoom (via `BuildTimelineZoom.mjs`), a cursor time guide, local search across the already-loaded full-build metadata, preserving the current range without repeated payload downloads, keyboard inspection, and debounced, asynchronous plain-text step logs with stale-response protection. `BuildTimelineResize.mjs` lets users drag or keyboard-adjust the inspector divider while keeping space for the chart. Its pure interval layout lives in `BuildTimelineModel.mjs` and is tested in server CI with `node --test assets/app/js/*.test.mjs`. `BuildTimelineInteractions.mjs` provides cancellable debounce and lane-indexed hit testing, while keyboard navigation uses the scoped server neighbor query. Theme tokens are cached until the theme or fonts change. The initial payload contains all recorded step metadata; there is no range cache, prefetcher, or range endpoint. Zoom, pan, and search operate locally, while logs remain separate asynchronous requests. The initial skeleton covers loading; builds with metrics but no recorded steps show that fact rather than a filter-mismatch message.
- Marketing imports only the Noora tooltip hook through the `noora/hooks` source
  alias. Add hooks as templates need them instead of importing the full runtime,
  which brings ECharts into pages without charts. Noora CSS remains shared.
  The Docker asset builder must copy Noora's node_modules from the npm stage
  alongside its built assets so those source imports resolve their dependencies.
- Asset builds for development and production.
- Step details show project and target separately, use Noora badges for type and outcome, and pair duration with the dashboard’s standard 16px history icon. The inspector has a small horizontal inset so its scroll boundary does not clip badge borders and shadows.
- Crosshair styling and synchronized hover time cursors activate only on plot canvases, not metric headings, rulers, controls or surrounding card space.
- Timeline logs preserve source lines and scroll horizontally; their full height participates in the inspector's vertical scrolling.
- Timeline selection persists when scrolling or zooming moves the step outside the visible range, keeping its metadata and log open.
- Browser real user monitoring. `shared/js/analytics.js` initializes the Grafana
  Faro Web SDK from the `globalThis.analytics` config that
  `TuistWeb.LayoutComponents.head_analytics_scripts` renders, and every bundle
  calls `initAnalytics()`. The SDK is an npm dependency bundled into our own
  JavaScript rather than a script from a CDN, so the page loads no third-party
  origin and the Content Security Policy stays on `'self'`. Web vitals feed the
  LCP alerts documented in `infra/helm/k8s-monitoring/alerts.md`.
  Browsers reporting `navigator.webdriver` are not instrumented at all, so
  crawlers and headless test runners neither emit web vitals nor page views.

## Related Context

- Web layer: `server/lib/tuist_web/AGENTS.md`
