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

All tasks live under `mise run grafana:*`:

```bash
mise run grafana:build    # one-off build into ./dist
mise run grafana:dev      # webpack watch + Grafana in docker at :3000
mise run grafana:lint     # lint (add --fix to auto-correct)
mise run grafana:test     # typecheck + jest
mise run grafana:bundle   # build + sign + zip for upload
```

The tasks pin node/pnpm through [grafana/mise.toml](mise.toml), so run them
under mise rather than reaching for system node.

## Publishing

`mise run grafana:bundle` produces `tuist-tuist-app-<version>.zip`. Two modes:

1. **Private plugin for a specific Grafana Cloud stack** (what you want for
   staging validation):
   ```bash
   export GRAFANA_ACCESS_POLICY_TOKEN="..."
   mise run grafana:bundle -- --root-urls https://<your-stack>.grafana.net/
   ```
   Upload the resulting zip via *Grafana Cloud → your stack → Administration →
   Plugins → Upload private plugin*. No review wait.

2. **Public plugin in the Grafana catalogue** (wider release):
   ```bash
   export GRAFANA_ACCESS_POLICY_TOKEN="..."
   mise run grafana:bundle -- --signature-type community
   ```
   Upload the zip through the submission form at
   <https://grafana.com/auth/sign-in?redirectPath=/plugins/submit>. Review
   takes 1–3 business days.

3. **Unsigned local dev**:
   ```bash
   mise run grafana:bundle -- --skip-sign
   ```
   Only loads in Grafana started with
   `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-tuist-app`.

The access policy token is minted at
<https://grafana.com/orgs/tuist/access-policies> — one policy
(`tuist-plugin-publishing`) with the `plugins:write` scope.

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
