# Server Assets (JS/CSS)

This directory contains frontend assets for the Phoenix app (LiveView, marketing, apidocs).

## Responsibilities

- JS/CSS sources built by esbuild.
- Marketing imports only the Noora tooltip hook through the `noora/hooks` source
  alias. Add hooks as templates need them instead of importing the full runtime,
  which brings ECharts into pages without charts. Noora CSS remains shared.
  The Docker asset builder must copy Noora's node_modules from the npm stage
  alongside its built assets so those source imports resolve their dependencies.
- Asset builds for development and production.
- Newsletter verification uses its own `newsletter` esbuild entry, with Noora
  tokens and button styles only. It retains analytics but needs no LiveView
  runtime: confirmation is a regular POST form.
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
