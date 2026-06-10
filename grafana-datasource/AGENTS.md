# Tuist Grafana data source plugin

A backend Grafana data source plugin (Go + React) that exposes Tuist build and
test duration metrics as Grafana time series. It is a thin client over the Tuist
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
- `GET /builds/metrics/schemes`, `GET /builds/metrics/configurations`, `GET /tests/metrics/schemes` → `{ schemes | configurations: [string] }`.
- `GET /api/projects` (account-level) → `{ projects: [{ full_name: "account/project" }] }` — backs the project dropdown.

`from`/`to` are Unix seconds taken from Grafana's panel time range. The server
derives bucket granularity (hour/day/month) from the range, which bounds the
point count; the plugin does not send an interval.

If the server's response shape or routes change, update `pkg/plugin/models.go`
and `pkg/plugin/client.go` to match. These endpoints are server-side OpenApiSpex
only — they are intentionally not part of the generated CLI client.

## Build & test

- Backend: `mage -v` (build), `go test ./...` (unit tests). The Go module is part
  of the repo `go.work`.
- Frontend: `npm install` then `npm run typecheck` / `npm run lint` /
  `npm run build` (outputs `dist/`). Node is pinned to 24 via `mise.toml`. The
  `.config/` harness is committed and managed by `@grafana/create-plugin` —
  update it with `npx @grafana/create-plugin@latest update`, don't hand-edit.

## Releasing / publishing

- `.github/workflows/grafana-datasource-release.yml` builds the frontend +
  multi-platform Go binaries, signs (when `GRAFANA_ACCESS_POLICY_TOKEN` is set),
  validates, and (on a `grafana-datasource-v*` tag) publishes a GitHub release
  with the zip + SHA1 for catalog submission.
- Catalog readiness was checked with `@grafana/plugin-validator`. Outstanding
  item: the validator wants the **latest** `grafana-plugin-sdk-go` (clears the
  "SDK older than 5 months" check and the grpc/otel CVEs). The latest SDK cannot
  be adopted from inside this monorepo for two reasons, both verified:
  1. It requires **go 1.26.3**, so `go.work` would have to move off go 1.25.
  2. Even on go 1.26, it pulls newer k8s/transitive deps (e.g. structured-merge-diff
     v6, newer grpc) that the shared `go.work` then forces onto every module via
     MVS, which breaks the infra controllers' build (the `infra/tart-kubelet`
     build fails with a `structured-merge-diff` v4-vs-v6 type error).
  So the SDK update requires an **isolated module graph** — extract this plugin
  into its own repository (also the cleaner home for the release/signing cadence)
  before submitting to the catalog. This is a pre-submission step, not in-monorepo
  development. The plugin builds and works on the pinned v0.250.0 + go 1.25 today.

## Conventions

- Keep all aggregation server-side; this plugin only shapes requests and frames.
- The account token lives in `secureJsonData` and must never be returned to the
  browser — dropdown data flows through `CallResource`, not direct frontend calls.
- Plugin id `tuist-metrics-datasource`; backend executable `gpx_tuist_datasource`.
