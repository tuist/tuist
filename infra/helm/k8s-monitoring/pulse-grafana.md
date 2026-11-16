# Pulse storage with Grafana Cloud dashboards and alerts

Keep Grafana Cloud as the UI, Grafana-managed alert evaluator and notification
router, and point its data sources at Pulse. Pulse does not implement the
Mimir/Loki ruler or Alertmanager APIs, nor Loki's or Tempo's query APIs.

## Data sources

Grafana reaches each environment's Pulse at `pulse.observability.svc.cluster.local`
through that environment's PDC network, and only on the ports listed in the Tuist
chart's `pdcAgent.permitRemoteOpen`. Keep query APIs private and do not widen the
tunnel to `*`. Production's live sources, all on the production PDC network:

| Source | UID | Type | Endpoint |
| --- | --- | --- | --- |
| Tuist Pulse Metrics | `cg3i1jh2k1v5sb` | Prometheus | `:4000/v1/prometheus` |
| Tuist Pulse Traces | `cg3i1ttjazsaof` | Jaeger | `:4000/v1/jaeger` |
| Tuist Pulse SQL | `pulse-sql` | PostgreSQL | `:4003`, database `public` |

[`pulse-datasources.json`](pulse-datasources.json) holds their Grafana HTTP API
bodies (`PUT /api/datasources/uid/<uid>`); Grafana Cloud does not import it.
Tuist Pulse Logs (`fg3i1s2e8w4qof`, Loki) cannot work and only remains for the
November 6 test rules.

**Credentials are deliberately absent.** Every source logs in as the read-only
`dashboard` user with the environment's `PULSE_TOKEN/password`, entered by a
person in Grafana's secure fields (Basic Auth password for HTTP sources,
password for PostgreSQL). Agents do not read that Secret. Never put credentials
in this JSON, dashboards, Git Sync, query parameters or PRs.

`manageAlerts: false` disables the unsupported data source-managed ruler, not
Grafana-managed alerting. Grafana writes recording rules to
`<url>/api/v1/write`, but Pulse accepts remote write only at
`/v1/prometheus/write` and only for the write-only `tuist` user, so the four
`kura:*` recordings cannot target Pulse yet and their 16 dependent rules return
nothing there. Fix the write path in the fork or inline the recordings before
moving those rules.

## Shadow rules

The `pulse-shadow` folder (**Pulse shadow (silent)**) holds copies of the
PromQL rules that can move today, titled `[Pulse] <title>` with a
`pulse_shadow_of` label naming the original. They read Tuist Pulse Metrics and
notify the receiver without integrations (`Pulse lifecycle silent ...`), so
they never page. Switch an original's data source only after its copy has
matched it, and long-window rules only once Pulse holds their whole window.
Copies also measure Pulse under Grafana's real evaluation load: datanodes fail
a scan immediately when their scan memory budget (25% of the pod limit) is
exhausted. Delete a copy once its original reads Pulse.

Not shadowed: the `kura:*` dependents, rules on senders that write only to
Grafana Cloud (the external cache VMs, management's collectors, Synthetic
Monitoring), and rules that Pulse 1.3.0-1 fails to evaluate:

- `or` and `and on (...)` between operands with different label sets
  ("combine two tables with different column sets": `afx2w05l6se0wc`,
  `bfxmy59vtljpca`).
- `a * on() b unless on() c` ("No field named ...pulse_timestamp": `eg1eawacfhkaoe`).
- `label_replace(vector(...), ...)` ("Error parsing timestamp": `fg1c6ql650pvka`).
- `max by (...)` over a `__name__=~"a|b"` selector keeps one series per metric
  instead of merging them, so `kura-thin-pool-degraded`'s shadow errors with
  duplicate labels.

## Log alert rules use SQL

Pulse accepts Loki pushes but serves no Loki query API, and only Jaeger's trace
API, so Grafana's Loki and Tempo sources cannot read it. Log alert rules move to
a Grafana **PostgreSQL** data source on Pulse's PostgreSQL port 4003, which the
chart opens per environment (`pulse.postgres` in
`infra/helm/pulse/templates/_helpers.tpl`: production only). Connect it over
the same environment's PDC network, host `pulse.observability.svc.cluster.local:4003`,
database `public`, user `dashboard` with the tenant token as password, TLS
disabled inside the tunnel. Only the PDC agent may reach that port.

[`pulse-log-alert-queries.json`](pulse-log-alert-queries.json) holds the SQL for
each Loki query of the live rules, keyed by rule UID and ref ID. Each query
returns its LogQL grouping labels as string columns and one numeric `value`
column, so the rules' expressions, thresholds, pending periods, labels and IRM
routing stay as they are; cutting a rule over replaces only those queries'
data source and model (`rawSql`, `format: table`). The windows are written into
the SQL and match the LogQL ranges. Logs land in `opentelemetry_logs`: Loki
labels are in the `resource_attributes` JSON, structured metadata such as `pod`
in `log_attributes`, and the line in `body`, which the queries parse with
regular expressions instead of `| logfmt` and `| json`. A quoted logfmt value
containing a space yields only its first word; no rule reads such a field. Two
rules stay on Grafana Cloud because their logs never reach Pulse: cache-nginx
502 (the cache hosts) and Synthetic Monitoring's failed executions.

The production queries target production's Pulse. `CNPG Replication Link Break`
groups by cluster across environments, so it needs one copy per environment's
data source, like the metric rules that span clusters.

Paging rules then depend on Pulse and the tunnel. Set **Error** to **Error** on
rules routed to IRM, so an unreachable Pulse raises `DatasourceError` through
the same policy instead of reading as healthy, and keep a heartbeat outside
Pulse's failure domain.

Validated on staging on November 15, 2026: all 43 queries run on Pulse 1.3.0-1
with the expected columns; the infrastructure queries, rewritten for staging,
matched Grafana Cloud Loki on the same staging logs (Kura ingress lines per
upstream, Postgres and server line counts, server pods, and each rule's own
condition); exact `percentile_cont` matches Loki's `quantile_over_time`; and the
Faro field extraction was checked against a production web-vitals line.
Staging has no Faro data, so compare the browser rules against production
before cutting them over.

## Verify before moving consumers

1. Save & test all three sources from Grafana Cloud, not just from a pod.
   Confirm `count by (cluster) (up)` and a recent labeled metric range on Pulse
   Metrics. Check metric-name/label/series discovery and a histogram percentile.
   On Pulse SQL, run a nonempty count over recent `opentelemetry_logs`. On Pulse
   Traces, search a service and open a recently ingested trace ID.
   A successful health check or an empty result alone is not acceptance.
2. Inventory **current** complete rules and dashboards. The November 5 query
   corpus covers 170 rule definitions and 31 dashboards, but is not a complete
   lifecycle/routing export. Leave SQL, ClickHouse, Cloud billing/usage, synthetic monitoring
   and other non-replaced sources alone.
3. Compare the same production queries and time windows in both stores, with
   the production panel's variable selections. An unset matcher variable
   broadens to a regex and is not proof of a particular panel's parity.
4. Shadow the four `kura:*` recordings with distinct names or an isolated tenant.
   Verify their outputs in Pulse, including dependent `kura:pool_region` and
   `kura:node_region`. When cutting over, update **both** each query's
   `datasourceUid`/nested model datasource and `record.target_datasource_uid`.
   Do not run competing producers for the same metric in one tenant. Keep the
   existing Grafana evaluation groups and cadence; switching to a native Pulse
   recording group changes dependency timing.
5. Compare Grafana alert states using the new sources without paging twice.
   Preserve UIDs, expressions, thresholds, pending/recovery periods, no-data and
   error policies, labels, contact points, silences and routing. Test a firing
   and resolved notification through each existing receiver before relying on it.
   Migrate dashboard fixed UIDs, variable selections, links and correlations
   deliberately; Git Sync definitions still reference the Cloud sources until
   changed. Do not bulk-repoint the default source and assume this is sufficient.

## Stopping Cloud storage is a separate decision

The live production collectors were observed dual-writing metrics/logs/traces on
November 5. That is not proof of coverage in staging, canary, management or
external senders, nor of sufficient retained history or query capacity. The
current managed deployment targets the existing `pulse` release in namespace
`observability`, preserving its bucket and credentials. Deploy through that
release path; do not create a second instance or bucket as a cutover shortcut.

Before stopping Cloud writes, pass the cutover gates
on the exact deployed version: provider-backed capacity, nonempty query parity,
alert transitions, recording publication, notification delivery and failure
recovery. Queries with week-long offsets need that history or a validated
backfill. The Pulse volume/cost replacement rules also need a prior-week baseline;
they cannot replace Cloud usage alerts after one day of data. Monitor Pulse failure/no-data from outside Pulse's own failure domain.

Only after acceptance, remove Cloud ingestion for all senders while preserving
Pulse forwarding, labels, sampling and metric identity. Keep old data sources
available for retained-history queries and rollback. Do not delete Cloud data,
credentials or notification services as part of a storage switch. The existing
runbook calls for a shadow week and two further weeks of dual-writing; a next-day
shutdown needs an explicit risk decision, not a claim that these gates passed.
