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
- Browser real user monitoring. `shared/js/analytics.js` initializes the Grafana
  Faro Web SDK from the `globalThis.analytics` config that
  `TuistWeb.LayoutComponents.head_analytics_scripts` renders, and every bundle
  calls `initAnalytics()`. The SDK is an npm dependency bundled into our own
  JavaScript rather than a script from a CDN, so the page loads no third-party
  origin and the Content Security Policy stays on `'self'`. Web vitals feed the
  LCP alerts documented in `infra/helm/k8s-monitoring/alerts.md`.
  `shared/js/browser-automation.mjs` excludes browsers reporting
  `navigator.webdriver`, Meta's explicit external-agent user agent, and the
  exact Linux crawler fingerprint observed in production (user agent, language,
  and viewport). These clients never initialize Faro. This is a telemetry
  heuristic, not comprehensive bot detection: the fingerprint can change and
  an ordinary browser matching it will also be excluded. Run its regression
  tests with `node --test assets/shared/js/browser-automation.test.mjs` from
  `server/`; the server workflow runs them alongside asset checks.

## Related Context

- Web layer: `server/lib/tuist_web/AGENTS.md`
