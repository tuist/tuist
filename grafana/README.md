# Tuist Grafana app plugin

Grafana app plugin for the Tuist per-account `/metrics` endpoint. Bundles:

1. A configuration page that collects the Tuist server URL, account handle,
   `account:metrics:read` token, and target Prometheus datasource.
2. A scrape-snippet generator that emits a ready-to-paste Grafana Alloy (and
   Grafana Agent flow-mode) configuration.
3. Two curated dashboards — **Tuist Xcode** and **Tuist Gradle** — each
   organised into Overview / Builds / Tests / Cache rows that mirror the
   Tuist dashboard's project pages.

The plugin itself does not scrape. Grafana Alloy / Agent does, and remote-writes
into the Prometheus datasource configured here.

## Development

All tasks live under [`grafana/mise/tasks/`](mise/tasks) and are scoped to
this directory — `cd grafana` first, then:

```bash
mise run build    # one-off build into ./dist
mise run dev      # Prometheus + Grafana in docker, webpack watch, plugin mounted
mise run lint     # lint (add --fix to auto-correct)
mise run test     # typecheck + jest
mise run bundle   # build + sign + zip for upload
```

The tasks pin node/pnpm through [grafana/mise.toml](mise.toml), so run them
under mise rather than reaching for system node.

## Publishing

Every push to `main` that includes a `(grafana)`-scoped commit triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml), which:

1. bumps `grafana/package.json`,
2. regenerates `grafana/CHANGELOG.md`,
3. runs `mise run bundle -- --signature-type community` (community-signed,
   so any Grafana instance can install it),
4. publishes a GitHub release that attaches the signed zip.

`mise run bundle` also works locally:

```bash
export GRAFANA_ACCESS_POLICY_TOKEN="..."
mise run bundle -- --signature-type community   # public, catalogue-ready
mise run bundle -- --skip-sign                  # unsigned, local dev only
```

The unsigned zip loads only in a Grafana started with
`GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-tuist-app`.

### Grafana plugin catalogue

The plugin reaches any Grafana instance through the public catalogue. On
first release we submit once via
<https://grafana.com/auth/sign-in?redirectPath=/plugins/submit> (choose
*Public (free)*, point it at the GitHub release's zip URL). Grafana
reviews in 1–3 business days.

After that first approval, every subsequent tagged release triggers the
catalogue to pick up the new version automatically — no manual resubmit.

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
