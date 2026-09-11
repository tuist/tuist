# Server Assets (JS/CSS)

This directory contains frontend assets for the Phoenix app (LiveView, marketing, apidocs).

## Responsibilities

- Expanded Xcode cache task rows append CAS outputs with a Noora Load more button; the build-run stylesheet adds spacing around the control. Loading and pagination are managed by LiveView; output IDs are not embedded in the initial table.

- Timeline summary values (elapsed time, step count and target count) use small decorative separator dots.
- Timeline metrics use a responsive 2×2 grid with independent 120px plots and subtle 2px card corners; the build-step viewport stays 600px tall. Search and the step legend sit above the step lanes below the metric grid, outside chart gesture handling, with a time ruler for each section.
- The inspector and its resize divider align with the top of the step chart section (including search and legend) and span that section only, keeping details below the metric grid. Step and metric charts share the same Noora border with a 2px radius.
- `BuildTimelineMetrics.mjs` renders CPU, memory, network and disk tracks using the same time range as build steps; each plot has its own time ruler, synchronized cursor and range-selection overlay, with coordinates scaled to its own width. Noora-styled chart cards use taller line plots, horizontal gridlines, and purple/blue series. Metric hover values appear only in each chart’s top-right readout, including both network/disk directions; floating tooltips are reserved for build steps. The initial and maximum zoom-out both show the entire build. Failed hook initialization cleans up listeners and indicators and hides partially mounted content. Samples are loaded once, culled by binary search, and keep stable scales across zooms; missing samples and collection gaps are not shown as zero readings.

- JS/CSS sources built by esbuild.
- `marketing/source-images` keeps the original shared header artwork outside
  the served `priv/static` tree. Regenerate its 960px desktop and 480px mobile
  WebP derivatives with
  `magick INPUT -resize WIDTHx -quality 85 -define webp:method=6 OUTPUT`;
  served `hero-background*` images must stay within
  20 KiB and 1024 pixels per dimension, enforced by `marketing:image-budget`.
- `app/js/BuildTimeline.js` renders the Xcode timeline with a viewport height independent of content, viewport culling, horizontal scrolling with an always-visible Noora indicator shared with tables (a full-width thumb when the build fits), and readable lanes within the fixed viewport without vertical scrolling; `BuildTimelineDensity.mjs` preserves individual overlap lanes, compressing excess concurrency below the readable upper lanes, compact execution lanes that repack for the selected interval, drag-to-focus selection on the chart and ruler (via `BuildTimelineFocus.mjs`), pointer-anchored trackpad pinch zoom (via `BuildTimelineZoom.mjs`), a cursor time guide, local search across the already-loaded full-build metadata, preserving the current range without repeated payload downloads, keyboard inspection, and debounced, asynchronous plain-text step logs with stale-response protection. `BuildTimelineResize.mjs` lets users drag or keyboard-adjust the inspector divider while keeping space for the chart. Its pure interval layout lives in `BuildTimelineModel.mjs` and is tested in server CI with `node --test assets/app/js/*.test.mjs`. `BuildTimelineInteractions.mjs` provides cancellable debounce and lane-indexed hit testing, while keyboard navigation uses the scoped server neighbor query. Theme tokens are cached until the theme or fonts change. All recorded step metadata arrives through an abortable, compressed HTTP download while a separate hook reply initializes machine metrics; there is no range cache, prefetcher, or range endpoint. Zoom, pan, and search operate locally, while logs remain separate asynchronous requests. The step skeleton remains below interactive metrics until the metadata download completes; builds with metrics but no recorded steps show that fact rather than a filter-mismatch message.
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

- Xcode, Gradle and Bazel share the same abortable HTTP step download and separate metric bootstrap reply. No full step payload travels over LiveView. Opaque string operation IDs sort deterministically; Gradle/Bazel navigate filtered metadata locally. Apply log availability from the completed metadata response, since Bazel action enrichment happens there. Gradle categories and outcomes retain their source meaning; Bazel unknown outcomes must not appear as successful.

- Timeline metrics accept a real sample with a negative offset as the preceding neighbor for the zero boundary. Clip the plotted segment to the viewport and preserve gap detection; never backdate or extrapolate a first reading.

- Bazel profiles expose native CPU counters in cores; prefer normalized percentages with a fixed 0–100 scale when CPU-count metadata is available, and otherwise retain cores. Memory scales to recorded usage when total machine memory is absent. Hide tracks with no recorded values; never draw zero-filled substitutes for missing counters.
- Bazel's CPU chart spans the full metric grid width, with memory and network beneath it. Bazel has no Disk I/O track because native profiles do not supply disk throughput; Gradle and Xcode keep their four-chart layout.
- Timeline categories are source-aware. Bazel groups Compilation, Linking, Scripts, File preparation, Fetching, Analysis/setup and Other. Classify file staging and native analysis/fetch categories explicitly; mixed general-information spans and unknown mnemonics stay Other. Gradle separately identifies Configuration, Artifact transforms, Testing and Packaging from the recorded operation/task type. Original mnemonics and task types remain in details.
- Gradle/Bazel legends are accessible single-group toggle filters, including Failed as an outcome filter, with compact spacing and button padding. Search matches original categories and translated group labels as well as step/target/project names. Search and category selection intersect, preserve the current range, and use cached steps for keyboard navigation. Clicking the active group clears it. Xcode keeps its existing legend and search semantics.
- Metrics with explicit `duration_ms` represent native Bazel counter buckets. Render horizontal segments and return the bucket value on hover throughout that interval, preserving gaps and the original start. Point samples from Xcode and Gradle retain their existing interpolation and collection bounds.
- Profile-based timelines use the profile duration and recorded event bounds, not the longer BEP invocation clock. Adjacent metric intervals tolerate sub-microsecond floating-point rounding when connecting their segments; real collection gaps stay blank.

- Hash-input detail values wrap long values within the cache and selective-testing tables.

- Direct dependency links wrap within expanded target rows in both cache tabs.

- Timeline step and target counts use Noora’s shared `formatNumber` (10,000+ uses K/M/B/T), matching dashboard charts and server-rendered counts.

- Runner integration cards share the Buildkite/GitLab settings layout in `app/css/pages/integrations.css`. Shared connection-modal spacing must target both modal IDs; connected GitLab forms use the same field and action spacing as Buildkite. The GitLab connection modal has a responsive 520px width so its description cannot stretch the two-field form, with its Connect action aligned right.
