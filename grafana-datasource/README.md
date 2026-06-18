# Tuist data source for Grafana

Chart your build and test durations from [Tuist](https://tuist.dev) in Grafana. This data source turns the p50/p90/p99 and average build and test times you see in your Tuist dashboard into native Grafana time series, so build performance can live next to the rest of your observability.

![A Grafana dashboard with Project and Environment dropdowns showing Tuist build and test duration percentiles over the last 30 days](https://raw.githubusercontent.com/tuist/tuist/main/grafana-datasource/src/img/screenshot-dashboard.png)

## What you can query

- **Build durations** and **Test durations**, each as `average`, `p50`, `p90`, and `p99` series over the dashboard's time range.
- Filter by **Environment** (CI or local), **scheme**, and (for builds) **configuration**.
- **Project**, scheme, and configuration values come from the server, so they also work as dashboard template variables. One dashboard can therefore serve every project the token can access.

All aggregation happens server-side; the plugin is a thin client over the Tuist API.

## Requirements

- Grafana 10.4 or newer.
- A Tuist **account token** with the `project:builds:read` and `project:tests:read` scopes (both covered by the `mcp` scope group) and access to the projects you want to chart.

## Configuration

Add the data source and set:

| Field | Notes |
| --- | --- |
| Server URL | Your Tuist server. Defaults to `https://tuist.dev`. |
| Account token | Stored encrypted (`secureJsonData`); never sent to the browser. |

Then "Save & test" lists your projects to confirm the connection.

## Installation

### From the Grafana catalog

Once published, install it like any other data source from **Connections → Add new connection → Tuist**, or with `grafana-cli plugins install tuist-metrics-datasource`.

### Before it is published (self-hosted Grafana)

The plugin is unsigned until it is approved for the catalog. On a self-hosted instance you can either:

- **Allow it unsigned** — add `tuist-metrics-datasource` to `allow_loading_unsigned_plugins` (or `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-metrics-datasource`) and drop the built plugin into your plugins directory.
- **Privately sign it** for your instances — `npm run sign -- --rootUrls https://grafana.example.com` (the URL must match the instance `root_url`), then distribute the zip.

Grafana Cloud does not run unsigned or self-installed third-party plugins, so Cloud users need the catalog release.

## Development

```bash
npm install
npm run typecheck && npm run lint && npm run build   # frontend
mage -v                                              # Go backend binaries
go test ./...                                        # backend tests
npm run server                                       # Grafana + the plugin via docker compose
```

Node is pinned to 24 via `mise.toml`. See [AGENTS.md](https://github.com/tuist/tuist/blob/main/grafana-datasource/AGENTS.md) for the architecture and the server-side API contract.
