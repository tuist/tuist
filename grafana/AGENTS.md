# Tuist Grafana app plugin

Consumes the `/api/accounts/:handle/metrics` endpoint exposed by
[`server/`](../server/AGENTS.md). Ships configuration UI, scrape-snippet
generator, and two dashboards. User-facing docs live at
[`server/priv/docs/en/guides/integrations/grafana.md`](../server/priv/docs/en/guides/integrations/grafana.md).

## Responsibilities
- Configure how Grafana Alloy / Agent scrapes the Tuist server.
- Ship dashboards that query the metric names defined in
  `Tuist.Metrics.Schema` on the server.
- Stay thin: the plugin must not know the metric vocabulary beyond what the
  dashboards reference directly.

## Boundaries
- The plugin does not call ClickHouse, Postgres, or any other backing store
  directly — its only contract with Tuist is the `/metrics` endpoint.
- The plugin is the only place in the repo that produces Grafana JSON
  dashboards. Do not add dashboards here that target metrics that are not
  exposed by the scrape endpoint.

## Conventions
- Dashboards use the `${DS_PROMETHEUS}` datasource variable so they can be
  imported into any Prometheus-compatible backend.
- Label queries (`label_values(...)`) must filter down by `project` so the
  plugin works cleanly when one Grafana org scrapes multiple accounts.
- Keep the bundled dashboards opinionated and short. Users can fork the JSON
  if they need more panels.

## Development

All tasks live in [`grafana/mise/tasks/`](mise/tasks) and are scoped to this
directory — `cd grafana` first, then:

```bash
mise run build    # one-off build into ./dist
mise run lint     # lint (add --fix to auto-correct)
mise run test     # typecheck + jest
mise run bundle   # build + sign + zip for upload
```

`grafana/mise.toml` pins node + pnpm and runs `pnpm install --prefer-offline`
via a `[hooks] postinstall`, so `mise install` bootstraps dependencies in
one shot.

To iterate on the plugin UI against a local Grafana:

```bash
cd grafana
mise run build   # or `pnpm run dev` for webpack watch
docker run --rm -p 3000:3000 \
  -e GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-tuist-app \
  -e GF_AUTH_ANONYMOUS_ENABLED=true \
  -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
  -v "$PWD/dist:/var/lib/grafana/plugins/tuist-tuist-app" \
  grafana/grafana:latest
```

Open <http://localhost:3000/plugins/tuist-tuist-app> and configure it
against a running Tuist instance. You'll also want a Prometheus
instance that scrapes the `/metrics` endpoint — add it as a datasource
inside Grafana.

## Publishing

Every push to `main` containing a `(grafana)`-scoped commit triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml), which:

1. bumps `grafana/package.json`,
2. regenerates `grafana/CHANGELOG.md`,
3. runs `mise run bundle --signature-type community` (community-signed so
   any Grafana can install it),
4. publishes a GitHub release with the signed zip attached.

The access-policy token is read at build time from
`op://tuist/TUIST_GRAFANA_PLUGIN_TOKEN/password`. Create one at
<https://grafana.com/orgs/tuist/access-policies> with the `plugins:write`
scope on the `tuist (all stacks)` realm.

The first release of the plugin needs a one-time submission to the public
Grafana plugin catalogue via
<https://grafana.com/auth/sign-in?redirectPath=/plugins/submit> (choose
*Public (free)*, paste the GitHub release's zip URL). Grafana reviews in
1–3 business days. Subsequent releases are ingested automatically.

### Local signing / bundling

```bash
cd grafana
export GRAFANA_ACCESS_POLICY_TOKEN="..."
mise run bundle --signature-type community   # catalogue-ready
mise run bundle --skip-sign                  # unsigned, local dev only
```

The unsigned zip loads only in a Grafana started with
`GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-tuist-app`.

## Related context
- Server-side schema: [`server/lib/tuist/metrics/schema.ex`](../server/lib/tuist/metrics/schema.ex)
- Endpoint controller: [`server/lib/tuist_web/controllers/api/metrics_controller.ex`](../server/lib/tuist_web/controllers/api/metrics_controller.ex)
- User-facing docs: [`server/priv/docs/en/guides/integrations/grafana.md`](../server/priv/docs/en/guides/integrations/grafana.md)
- Metrics reference: [`server/priv/docs/en/references/metrics.md`](../server/priv/docs/en/references/metrics.md)
- RFC: <https://community.tuist.dev/t/per-account-metrics-endpoint-and-grafana-integration/974>

## Upgrading `@grafana/create-plugin`

The `.config/` tree and parts of `package.json` are owned code scaffolded
from [`@grafana/create-plugin`](https://github.com/grafana/plugin-tools).
To pull upstream improvements:

```bash
cd grafana
pnpm dlx @grafana/create-plugin@latest update --force
```

Then bump `.config/.cprc.json` to the new version so the next run sees us
as synced.

Deliberate deviations from the scaffold — worth re-stripping after any
update:

- The template ships `.config/Dockerfile`, `docker-compose-base.yaml`,
  `supervisord/`, `entrypoint.sh`. We don't ship a dev-stack docker
  compose, so those files are dead weight.
- `.config/bundler/externals.ts` had unexpanded Handlebars conditionals
  for Rspack mode; we keep the webpack-only form.
