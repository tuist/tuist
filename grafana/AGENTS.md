# Tuist Grafana app plugin

Consumes the `/api/accounts/:handle/metrics` endpoint exposed by
[`server/`](../server/AGENTS.md). Ships configuration UI, scrape-snippet
generator, and four dashboards.

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

## Related context
- Server-side schema: [`server/lib/tuist/metrics/schema.ex`](../server/lib/tuist/metrics/schema.ex)
- Endpoint controller: [`server/lib/tuist_web/controllers/api/metrics_controller.ex`](../server/lib/tuist_web/controllers/api/metrics_controller.ex)
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
  `supervisord/`, `entrypoint.sh`. We use our own top-level
  `docker-compose.yml` that also runs Prometheus scraping staging,
  so the template's container stack would just be dead weight.
- `.config/bundler/externals.ts` had unexpanded Handlebars conditionals
  for Rspack mode; we keep the webpack-only form.
