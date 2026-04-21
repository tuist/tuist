# Tuist Grafana app plugin

Grafana app plugin for the Tuist per-account `/metrics` endpoint. Bundles:

1. A configuration page that collects the Tuist server URL, account handle,
   `account:metrics:read` token, and target Prometheus datasource.
2. A scrape-snippet generator that emits a ready-to-paste Grafana Alloy (and
   Grafana Agent flow-mode) configuration.
3. Four curated dashboards: Xcode build performance, Xcode test reliability,
   binary cache effectiveness, and CLI usage.

The plugin itself does not scrape. Grafana Alloy / Agent does, and remote-writes
into the Prometheus datasource configured here.

## Development

```bash
pnpm install          # from the repo root
cd grafana
npm run dev           # webpack watch build into ./dist
npm run typecheck
npm run lint
npm run test:ci
```

To try the plugin against a local Grafana:

```bash
# 1. Build it
npm run build

# 2. Mount ./dist into a Grafana container as the plugin dir
docker run --rm -p 3000:3000 \
  -e GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-tuist-app \
  -v "$PWD/dist:/var/lib/grafana/plugins/tuist-tuist-app" \
  grafana/grafana:latest

# 3. In Grafana: Administration -> Plugins -> Tuist -> Configuration
```

## Publishing

The plugin is published to the
[Grafana plugin catalogue](https://grafana.com/grafana/plugins/) as
`tuist-tuist-app`. Release flow:

1. Bump the version in [package.json](package.json) and
   [src/plugin.json](src/plugin.json) (`%VERSION%` placeholder is replaced by
   the build).
2. `npm run build`
3. `npm run sign` (requires `GRAFANA_ACCESS_POLICY_TOKEN` for the Tuist org)
4. Upload the signed zip through the catalogue's UI.

## Architecture

The plugin is intentionally thin. Everything that could go stale (metric
names, bucket schedules, label vocabularies) lives on the server side in
[`Tuist.Metrics.Schema`](../server/lib/tuist/metrics/schema.ex). The plugin
only knows about three things:

- The per-account scrape URL template (`/api/accounts/:handle/metrics`).
- The scope name (`account:metrics:read`).
- The metric names used in the bundled dashboards.

If you add a new metric on the server, the plugin does not need to change —
you only update or add a dashboard that references the new series.
