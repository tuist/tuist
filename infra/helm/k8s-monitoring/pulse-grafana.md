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

Staging and canary each have a metrics source on their own PDC network:
`Tuist Pulse Metrics (staging)` (`pulse-metrics-staging`) and `(canary)`
(`pulse-metrics-canary`), same endpoint. Management's own Pulse is
`Tuist Pulse Metrics (management)` (`pulse-metrics-management`) on the
`pdc-tuist-management` network, served by `infra/flux/pulse-pdc`.

[`pulse-datasources.json`](pulse-datasources.json) holds their Grafana HTTP API
bodies (`PUT /api/datasources/uid/<uid>`); Grafana Cloud does not import it.
Tuist Pulse Logs (`fg3i1s2e8w4qof`, Loki) cannot work and no rule reads it
since the November 6 test rules were deleted.

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

## Metric rules on Pulse

Since November 16, 2026, the production-only PromQL rules read Tuist Pulse
Metrics: every rule whose queries select only `tuist-production` series and
look back at most six hours. Their labels, thresholds, pending periods,
no-data states and routing did not change. Each had run for a night as a
silent copy whose alerts matched the original's.

### Rules that span environments

A rule whose queries cover several clusters runs as one copy per Pulse
metrics source, with the original UID plus `-prod`, `-stg` or `-can`
(`remote-execution-vm-preparation-fail-stg` and `-can` are shortened to fit
Grafana's 40-character limit). Each copy keeps the original's query; the
source decides the environment. Staging copies add the label `env=staging`
so the existing staging notification route takes them. When management or
external senders still report to Grafana Cloud, the original stays on
`grafanacloud-prom` with `cluster!~"tuist-production|tuist-staging|tuist-canary"`
added to every selector (`k8s_cluster_name` for CNPG Postgres Instance Down),
so no environment is evaluated twice. Rules whose metrics only production
emits today stay on production Pulse under their own UID and get `-stg` and
`-can` copies with **No Data: Normal**, so they start alerting once those
environments emit them. [`test-pulse-environment-copies.sh`](test-pulse-environment-copies.sh)
checks the committed rule files for this layout.

### Error states

Pulse data source rules use **Error: Keep last state**. A query that fails
(a datanode restart, a scan rejected for memory, a tunnel blip) keeps the
rule's last state instead of raising `DatasourceError`. Rules that already
treated errors as Normal kept that. Seven rules that page through IRM keep
**Error: Error**, so a Pulse outage still reaches the on-call: `tuist-production-http-5xx`,
`runner-cache-volume-saves-failing`, `dfkmt5dtpx43kb`, `cfl2e4b9eg8aoc`,
`ffxqtj0ye58g0b`, `tuist-production-vm-allocator-burst` and
`ffz1ualjy8fswd-prod`.

Because Keep last state hides an unreachable Pulse, four watchdogs in group
**Pulse** alert on it, each pending five minutes with no-data and error set
to Alerting:

| Rule | Source | Condition | Severity |
| --- | --- | --- | --- |
| `pulse-production-unavailable` | production metrics | `count(up{cluster="tuist-production"})` < 100 | critical, Incidents |
| `pulse-sql-unavailable` | Pulse SQL | no log rows in the last 5 minutes | critical, Incidents |
| `pulse-staging-unavailable` | staging metrics | `count(up)` < 1 | warning |
| `pulse-canary-unavailable` | canary metrics | `count(up)` < 1 | warning |

The 16 rules that read the `kura:*` recordings inline them instead, because
Grafana writes recordings to `<url>/api/v1/write` and Pulse accepts remote
write only at `/v1/prometheus/write` for the write-only `tuist` user. The four
recordings were deleted on November 17, since no alert read them.
Inlined, `topk by (...) (1, timestamp(kura:...))` compares evaluation times
rather than sample times, which only differs while a pool changes region.

Pulse 1.3.0 fails to plan `a or b` when `b` contains a vector join
(`* on (...) group_left`, `!= on`) and `a` is empty or a different table. Put
the join on the left of `or`, or apply it after the union, as
`Kura - pod OOM-killed` (`cfx21glh3ufb4b`) and `Rack power draw near its
contracted limit` (`eg1eawacfhkaoe`) now do. `and on (...)` against an empty
right side fails the same way; `Linux fleet cannot seat a shape`
(`bfxmy59vtljpca`) multiplies by `(... == bool 0)` instead.

`absent()` and `absent_over_time()` return nothing on Pulse where Prometheus
returns 1, so a missing-telemetry rule on Pulse never fires. Count the series
instead and alert below 1:

```promql
(sum(count_over_time(up{job="kura"}[15m])) or vector(0)) + 0
```

`+ 0` drops the metric name Pulse leaves on `sum()`. Since November 16 the
Kura (`ffvvcpp359qm8d`) and xcresult guest (`dg1ew04a5qfwge`) telemetry rules
run this way once per environment, with a static `cluster` label, and
`Remote processing queue telemetry missing` (`bg1ewhe80qosgc`) counts each
queue in its own query and fires when either is 0.

### Management

Management's CAPI, Flux, node-memory and control-plane rules, and Pod
CrashLoop (whose only non-workload series were management's), read
`pulse-metrics-management` since November 17. Management's Pulse is one pod on
`tuist-mgmt`, so its three telemetry-missing rules (`cfxcyc9xtvlkwc`,
`efxczczr9xlhcd`, `efxdevi9ry5mob`) keep **Error: Alerting**: an unreachable
Pulse pages instead of silencing them. Like the workload copies, they count
the series with `(sum(count_over_time(sel[w])) or vector(0)) + 0 < 1`,
because Pulse's `absent_over_time` returns nothing for a missing series.

### Still on Grafana Cloud

- `Host NIC Carrier Flap` (`cfsogu69cr1fkc`), narrowed to `cluster=""`: the
  cache VMs, which write only to Grafana Cloud. Management's nodes are
  `cfsogu69cr1fkc-mgmt` on management's Pulse.
- `Pulse rejecting scans for lack of memory` and the paused `Pulse datanode
  telemetry missing`, until the `pulse-datanode` scrape reaches Pulse. Their
  per-environment twins (`-prod`, `-stg`, `-can`) already read each
  environment's Pulse; delete the Cloud originals once
  `count(up{job="pulse-datanode"})` returns the datanodes there.
- Long windows Pulse does not hold yet: `cfyi8f0lyqayof`, `dfygid92hevi8d` (3
  days) and `fg1c6ql650pvka` (7 days, also `label_replace(vector(...))`, which
  Pulse rejects).
- Senders that write only to Grafana Cloud (the external cache VMs, Synthetic
  Monitoring) and the Grafana Cloud usage rules.

On November 17 the Cloud halves of split rules whose selectors matched no
series outside the three workload clusters over 7 days were deleted (13, then
23 more), as were the four `kura:*` recording rules, which no alert read. Two
rules also left this list. `kura-thin-pool-metrics-missing` became
one rule per environment (`-stg` and `-can` copies), whose `unless` gets its
label columns from a never-matching `or (READY < -1)` branch while Pulse
images without the `and`/`unless` fix in `FORK.md` still run. `Kura - egress
shaping integrity` (`afx2w05l6se0wc`) reads production Pulse with the
`kura:node_region` recording inlined.

The silent copies in the `pulse-shadow` folder were deleted on November 16
once their originals were cut over or split.

### Reduce scan width before increasing memory

[`pulse-metric-alert-queries.json`](pulse-metric-alert-queries.json) holds
**proposed, not applied** replacements for query A of the two retention shadow
rules. Sum each bucket's `increase` by `(cluster, pod, le)` before joining
region/tenant metadata. This lets Pulse push the aggregation into the datanode
and omit scrape labels from the historical scan. Keep `increase` inside the
sum so independent counter resets remain correct. Keep the original one-/three-day
windows, fullness gate, output labels, threshold and pending period. Both
shadows were deleted on November 16 with the rest of the folder; their
originals (`afx2mswafmvi8a`, `dfygid92hevi8d`) still read Grafana Cloud, so
apply these queries when a Pulse copy of them is created.

Run `bash infra/helm/k8s-monitoring/test-pulse-metric-alerts.sh` with `promtool`
on PATH for offline parity checks, including independent counter resets and
missing metadata. Profile the complete expression on the deployed Pulse too:

```sql
EXPLAIN ANALYZE VERBOSE
WITH q AS (
  TQL EVAL (1794836760, 1794836760, '60s') <expression>
)
SELECT * FROM q LIMIT 1000;
```

Choose a retained, fixed evaluation timestamp and compare old/new sequentially.
Compare projected columns, scan output bytes, file/range counts and returned
labels/values. Output bytes are cumulative throughput, not peak scan reservations;
do not report their reduction as a measured reduction in peak memory. Compaction
and cache warmth can change timings between runs. For result comparisons, use
`AS retention` after the TQL expression and cast that value to string in SQL so
histogram NaNs survive Grafana's JSON transport.

These are query-only replacements, not provisioning payloads. Before applying
them, read each complete live rule and change only its matching query model's
`expr`; preserve data sources, other queries, condition, labels, routing and
evaluation settings. Publishing Grafana changes requires separate approval.
Do not repoint the original Cloud rules as part of the optimization. The daily
rule was retired (see `alerts.md`); separately review whether its remaining
shadow is still useful rather than silently deleting it.

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
regular expressions instead of `| logfmt` and `| json`. Faro's browser lines
(`service_name="tuist-web"`) land in their own `tuist_web_logs` table instead,
with a 30-day TTL set when Pulse creates it (`loki.write "pulse_web_logs"` in
`values.yaml`), so the web-vitals queries read a few thousand lines a day
rather than every cluster log. A quoted logfmt value
containing a space yields only its first word; no rule reads such a field. Two
rules stay on Grafana Cloud because their logs never reach Pulse: cache-nginx
502 (the cache hosts) and Synthetic Monitoring's failed executions.

Nine log rules read Pulse SQL. Only production's Pulse serves SQL, so these
target production. Three groups stay on Grafana Cloud Loki:

- `CNPG Replication Link Break` (`cfsogt8cgh14wc`) for staging and canary,
  which have no SQL source yet. Production's half is `cfsogt8cgh14wc-prod` on
  Pulse SQL, and the Cloud rule excludes `k8s_cluster_name="tuist-production"`.
- The 15 web-vitals rules (groups **Browser RUM quality** and **Web
  performance**): filtering every log line in `opentelemetry_logs` for
  Faro's overran Pulse's datanode scan memory and failed other reads, so they
  went back to Loki at a one-minute interval. Their queries now read
  `tuist_web_logs`; they move once that table holds the rules' longest
  window, 24 hours, of lines.
- Cache-nginx 502 and Synthetic Monitoring failures, whose logs never reach
  Pulse (above).

Paging log rules follow the error states above, and `pulse-sql-unavailable`
watches the SQL path.

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

Stopping Cloud log ingestion also shortens the kubectl access trail outside
production. Staging's and canary's Pulse keep seven days, against Cloud Loki's
thirty, and Grafana has no SQL source for them, so their Pomerium logs (the only
trail for staging writes; see `infra/AGENTS.md`, Forensic trail) would be short
and readable only from inside the cluster. Decide whether to raise their TTL for
the `pomerium` logs and add their SQL sources first.

Only after acceptance, remove Cloud ingestion for all senders while preserving
Pulse forwarding, labels, sampling and metric identity. Keep old data sources
available for retained-history queries and rollback. Do not delete Cloud data,
credentials or notification services as part of a storage switch. The existing
runbook calls for a shadow week and two further weeks of dual-writing; a next-day
shutdown needs an explicit risk decision, not a claim that these gates passed.
