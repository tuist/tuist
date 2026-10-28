# Grafana data source

Go backend and React editors for Bazel, Once, Gradle, and Xcode build health and
test durations, including series, period statistics, tables, and alerts. Aggregation
belongs in the server; this plugin shapes requests and Grafana frames.

## Development

Run from `grafana-datasource/`:

- Backend: `mage -v` to build; `go test ./...` to test.
- Frontend: `npm install`, then `npm run typecheck`, `npm run lint`,
  `npm run test:ci`, and `npm run build`.
- Keep the plugin's own `go.work` separate from the root infra workspace; its
  Grafana SDK dependency graph must not force upgrades on the infra controllers.
- `.config/` is managed by `@grafana/create-plugin`; update with
  `npx @grafana/create-plugin@latest update` rather than editing it manually.
- `CHANGELOG.md` is generated and gitignored. The prebuild hook supplies a local
  stub; releases generate the real file. Do not commit it.

## API and credentials

- `TuistWeb.API.MetricsController` is the API source of truth. Keep
  `pkg/plugin/models.go` and `pkg/plugin/client.go` aligned with its routes and
  response shapes; these endpoints are not part of the generated CLI client.
- Time ranges and response dates are Unix seconds; duration values are
  milliseconds. The server chooses bucket granularity; do not send an interval.
- Store account tokens only in `secureJsonData`, never return them to the browser.
  Dropdowns use backend `CallResource` requests, not direct frontend API calls.
- Keep plugin ID `tuist-metrics-datasource` and executable
  `gpx_tuist_datasource` aligned with packaging. Release automation lives in
  `.github/workflows/grafana-datasource-release.yml`.

## Build-health compatibility

- `/builds/metrics/health` and its dimension-values endpoint dispatch by the authorized project's build system; `/gradle/builds/metrics` and its dimensions remain compatible. Views are `series`, `total`, `workloads`, `failures`, and `recent_failures`; standard queries are `buildHealth`, `buildWorkloads`, `buildFailureReasons`, and `buildRecentFailures`. Retain legacy Gradle query types/metric keys and existing duration defaults, fields, and variables.
- Period statistics aggregate builds directly. Durations use milliseconds, rates use 0–100, counts are zero for empty cohorts, and missing duration/rate/savings evidence remains null. Count failed-or-slow builds once; success rates exclude cancellations. Once savings stay null and absent actors stay Unknown; Bazel user comes from the tool, Once actor from stream-admission credentials.
- Tables carry `build_system` for links. Generic failure tables add an all row; legacy Gradle tables keep three rows. Filter the compatibility all row out of the Failure categories chart.
- `src/dashboards/build-health.json` is standard; keep `gradle-build-health.json` and its identifier/queries as a compatibility download. Label automatic percentile counts Failed or slow builds neutrally; explicit duration targets remain configurable. Group Gradle cumulative-task-time savings with their coverage and reported elapsed savings with theirs, without changing frames/keys.
- Variable All uses `__tuist_all__`, omitted from frontend filters and normalized by the backend. Alerts require fixed values and reject unresolved dashboard variables. Automatic Gradle estimates use separate generic metrics.
- Organize docs around metric tables, with build-system differences, query options, and setup in separate sections.
