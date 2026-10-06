# Tuist Grafana data source plugin

A backend Grafana data source plugin (Go + React) that exposes build-health metrics across Bazel, Once, Gradle and Xcode, plus test durations as Grafana time series, whole-period statistics and tables. It declares backend alert support. It is a thin client over the Tuist
server's public metrics API — no aggregation happens here.

## Layout

- `pkg/main.go` — entry point; `datasource.Manage("tuist-metrics-datasource", …)`.
- `pkg/plugin/datasource.go` — `QueryData`, `CheckHealth`, `CallResource`.
- `pkg/plugin/client.go` — HTTP client for the Tuist API (Bearer account token).
- `pkg/plugin/models.go` — query model, settings, and response structs.
- `pkg/plugin/frames.go` — `DurationMetrics` → wide time-series `data.Frame`.
- `src/` — React editors (`ConfigEditor`, `QueryEditor`), `datasource.ts`,
  `module.ts`, `types.ts`, and `plugin.json`.

## Server API contract (source of truth: `server/`)

All endpoints are under `/api/projects/:account_handle/:project_handle` and are
authorized for account tokens via `project:builds:read` / `project:tests:read`
(`TuistWeb.API.MetricsController`).

- `GET /builds/metrics/duration?from&to&is_ci&scheme&configuration&category&status`
- `GET /tests/metrics/duration?from&to&is_ci&scheme`
  - Response (`DurationMetrics`): `{ dates: [unix_seconds], average:{values,total}, p50:{…}, p90:{…}, p99:{…}, trend }`, durations in milliseconds.
- `GET /builds/metrics/dimensions/{dimension}/values` (dimension: `scheme` | `configuration`) and `GET /tests/metrics/dimensions/{dimension}/values` (dimension: `scheme`) → `{ values: [string] }`. Prometheus-style metadata endpoint backing the filter dropdowns; the plugin proxies it via the `dimension-values` resource.
- `GET /gradle/builds/metrics?from&to&is_ci&git_branch&workload&status&view&slow_build_threshold_ms` → series/totals or rows. Views: `series`, `total`, `workloads`, `failures`, `recent_failures`. Durations are milliseconds; rates are 0–100; missing duration/rate/savings evidence remains null. Counts are zero for empty cohorts. Whole-period statistics aggregate builds directly. Attention counts failed-or-slow builds once. Success rate excludes cancelled builds.
- `GET /gradle/builds/metrics/dimensions/{dimension}/values` (`git_branch` | `workload`) backs Gradle variables and dropdowns.
- `GET /builds/metrics/health` and `/builds/metrics/health/dimensions/{dimension}/values` share the Gradle metric contract and dispatch from the authorized project's build system. Standard queries are `buildHealth`, `buildWorkloads`, `buildFailureReasons`, and `buildRecentFailures`. The legacy Gradle query types remain readable for saved panels. Tables include `build_system` to route links to the correct detail page. Once cache savings remain null because its reports do not contain elapsed savings; missing actor data remains Unknown. Generic failure tables add an all row; legacy Gradle tables retain three rows. Bazel user is reported by the tool; Once actor is the credential account captured at stream admission.
- `src/dashboards/build-health.json` is the standard dashboard; keep `gradle-build-health.json` with its original identifier and Gradle queries as a compatibility download. Existing duration defaults, query identifiers, response fields, filter variables and secure `apiToken` settings must stay unchanged; variable All values use `__tuist_all__`, which the frontend omits from filter requests. Alerts require fixed values instead of dashboard variables.
- `GET /api/projects` (account-level) → `{ projects: [{ full_name: "account/project" }] }` — backs the project dropdown.

`from`/`to` are Unix seconds taken from Grafana's panel time range. The server
derives bucket granularity (hour/day/month) from the range, which bounds the
point count; the plugin does not send an interval.

If the server's response shape or routes change, update `pkg/plugin/models.go`
and `pkg/plugin/client.go` to match. These endpoints are server-side OpenApiSpex
only — they are intentionally not part of the generated CLI client.

## Build & test

- Backend: `mage -v` (build), `go test ./...` (unit tests). The plugin has its
  own `go.work` (`use .`), intentionally separate from the repo-root infra
  workspace, so it tracks the latest `grafana-plugin-sdk-go` + go 1.26.3 without
  forcing those versions onto the infra controllers.
- Frontend: `npm install` then `npm run typecheck` / `npm run lint` /
  `npm run build` (outputs `dist/`). Node is pinned to 24 via `mise.toml`. The
  `.config/` harness is committed and managed by `@grafana/create-plugin` —
  update it with `npx @grafana/create-plugin@latest update`, don't hand-edit.

## Releasing / publishing

- Releases follow the repo convention: `.github/workflows/grafana-datasource-release.yml`
  triggers on push to `main` touching `grafana-datasource/**`, computes the next
  version with git-cliff via `mise run release:check grafana-datasource` (config in
  `cliff.toml`, registered in `mise/tasks/release/components.json`), and — when there
  are releasable commits — stamps the version, builds the frontend + multi-platform Go
  binaries, signs (when `GRAFANA_ACCESS_POLICY_TOKEN` is set), validates, tags
  `grafana-datasource@x.y.z`, and publishes a GitHub release with the zip + SHA1 for
  catalog submission. The release only tags + publishes — it never commits to `main`.
- `CHANGELOG.md` is git-cliff-generated at release time (into the dist) and is
  **not committed** — it's gitignored. Don't add it back to the repo. The webpack
  copy step requires the file to exist, so the `ensure:changelog` prebuild hook
  writes a stub when it's absent (the release generates the real one first, so the
  stub only ever appears in local/CI builds).
- Catalog readiness was checked with `@grafana/plugin-validator`. The plugin runs
  the **latest** `grafana-plugin-sdk-go` on go 1.26.3 (in its own `go.work`),
  which clears the validator's "SDK older than 5 months" check and the
  grpc/otel/kin-openapi CVEs. The latest SDK pulls k8s app-platform deps; those
  stay inside this plugin's workspace and do not reach the infra controllers —
  the reason the plugin is deliberately not in the repo-root `go.work`.
- Remaining validator notes are non-blocking: a `serialize-javascript` advisory
  in a webpack build-time dep (not shipped; refreshed by `create-plugin update`),
  and a "Go manifest not found" line that is an artifact of running the validator
  locally with a `file://` source URI — it resolves when submitting with the
  public repo URL.

## Conventions

- Keep all aggregation server-side; this plugin only shapes requests and frames.
- The account token lives in `secureJsonData` and must never be returned to the
  browser — dropdown data flows through `CallResource`, not direct frontend calls.
- Plugin id `tuist-metrics-datasource`; backend executable `gpx_tuist_datasource`.

- Keep Grafana documentation organized around metric tables, with build-system differences, query options, and setup in separate sections.

Backend health queries reject unresolved dashboard variables in alert filters and normalize the All sentinel before querying. Automatic Gradle cache estimates use separate generic metrics; legacy Gradle responses retain their original metric keys.
