# Server Assets (JS/CSS)

This directory contains frontend assets for the Phoenix app (LiveView, marketing, apidocs).

## Responsibilities

- JS/CSS sources built by esbuild.
- Asset builds for development and production.
- Browser real user monitoring. `shared/js/analytics.js` initializes the Grafana
  Faro Web SDK from the `globalThis.analytics` config that
  `TuistWeb.LayoutComponents.head_analytics_scripts` renders, and every bundle
  calls `initAnalytics()`. The SDK is an npm dependency bundled into our own
  JavaScript rather than a script from a CDN, so the page loads no third-party
  origin and the Content Security Policy stays on `'self'`. Web vitals feed the
  LCP alerts documented in `infra/helm/k8s-monitoring/alerts.md`.

## Related Context

- Web layer: `server/lib/tuist_web/AGENTS.md`
