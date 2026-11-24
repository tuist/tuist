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
treated errors as Normal kept that. The seven rules that page through IRM
(`tuist-production-http-5xx`, `runner-cache-volume-saves-failing`,
`dfkmt5dtpx43kb`, `cfl2e4b9eg8aoc`, `ffxqtj0ye58g0b`,
`tuist-production-vm-allocator-burst` and `ffz1ualjy8fswd-prod`) use
**Error: Normal**. They kept **Error: Error** until 2026-11-23, so that a Pulse
outage would reach the on-call through them, but then slow Pulse scans after a
rollout paged `runner-cache-volume-saves-failing` as a `DatasourceError`
incident while saves were healthy. A Pulse outage pages once, through the
watchdogs below, instead of as an incident on whichever rule failed to
evaluate. (Grafana's provisioning API accepts Keep last state, but the Atlas
Grafana tool only sets Normal, Alerting or Error.) The `-prod`, `-stg` and `-can` copies of
`pulse-scan-memory-rejections` and `pulse-datanode-telemetry-missing` also keep
**Error: Error**, since they watch Pulse itself.

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

On November 17 the collectors stopped writing to Grafana Cloud, and every rule
over the workload and management clusters moved to Pulse the same day. These
still read Cloud:

- Senders that write only to Grafana Cloud: the cache VMs (`Host NIC Carrier
  Flap` `cfsogu69cr1fkc`, narrowed to `cluster=""`; Cache CPU; Cache Node Disk
  Usage Watermark; cache-nginx 502) and Synthetic Monitoring.
- The Grafana Cloud usage rules (`Global Spend`, usage anomalies, cardinality
  explosion, duplicate timestamps), which now measure only those senders.

The long-window rules moved with less history than they look back over:
`cfyi8f0lyqayof` (3-day trend) and `dfygid92hevi8d` (3 days) read a few hours
less than Cloud held, and `fg1c6ql650pvka` (7 days) stays quiet until Pulse
holds the 3.5 days of `wan0` samples its gate requires, around November 21.
Pulse rejects its `label_replace(vector(...))` commit table, so it divides by
alder's commit directly (see `alerts.md`). `Kura - replication outbox
approaching its cap` (`afwtwlzgkderke`) read a metric retired in kura@0.46 and
was deleted.

Ten rules read metrics that only unmerged code emits, so they are paused with a
`paused_reason` annotation naming the pull request; unpause them once it is
deployed:

- `Runner egress gateway unusable` (`bg0q7eilnyj28c`), `Runner egress tunnel
  unhealthy on a host` (`fg0q7elkwllhcf`) and `Runner egress account job on a
  fleet it cannot use` (`cg0q7eop01k3kc`), with their `-stg` and `-can`
  copies: `tart_kubelet_runner_egress_tunnel_healthy` and
  `tuist_runners_dispatch_egress_held_count` come from draft
  [#14001](https://github.com/tuist/tuist/pull/14001).
- `Linux fleet cannot seat a shape` (`bfxmy59vtljpca`): the free seats per
  shape come from draft [#12991](https://github.com/tuist/tuist/pull/12991).

The Cloud originals of `pulse-scan-memory-rejections` and
`pulse-datanode-telemetry-missing` were deleted; their per-environment copies
read each Pulse, and the datanode copies stay paused until the `pulse-datanode`
scrape reaches each environment's Pulse.

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
the query A that the two retention rules (`afx2mswafmvi8a`, `dfygid92hevi8d`)
have used on production Pulse since November 17. Sum each bucket's `increase` by `(cluster, pod, le)` before joining
region/tenant metadata. This lets Pulse push the aggregation into the datanode
and omit scrape labels from the historical scan. Keep `increase` inside the
sum so independent counter resets remain correct. Keep the original one-/three-day
windows, fullness gate, output labels, threshold and pending period. On
November 17 the Pulse queries returned the same series as the Cloud originals
and neither fired.

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

These are query-only replacements, not provisioning payloads. To change them,
read each complete live rule and change only its matching query model's
`expr`; preserve data sources, other queries, condition, labels, routing and
evaluation settings.

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
target production, as do the 15 web-vitals rules (groups **Browser RUM
quality** and **Web performance**), which read `tuist_web_logs` since November
17. Filtering every log line in `opentelemetry_logs` for Faro's had overrun
Pulse's datanode scan memory and failed other reads. Cache-nginx 502 and
Synthetic Monitoring failures stay on Grafana Cloud Loki, since their logs never
reach Pulse (above).

`CNPG Replication Link Break` reads Pulse SQL in production
(`cfsogt8cgh14wc-prod`). Staging and canary have no SQL source, so their copies
(`-stg`, `-can`) read Pulse metrics instead: a replica's walsender on the
primary started in the last five minutes while neither instance's postmaster
restarted in the last fifteen.

```promql
sum by (k8s_cluster_name) (
  (time() - max by (k8s_cluster_name, application_name) (cnpg_pg_stat_replication_backend_start) < bool 300)
  * on (k8s_cluster_name, application_name)
  (time() - max by (k8s_cluster_name, application_name) (label_replace(cnpg_pg_postmaster_start_time, "application_name", "$1", "pod", "(.*)")) > bool 900)
  * on (k8s_cluster_name) group_left ()
  (time() - max by (k8s_cluster_name) (cnpg_pg_postmaster_start_time{instance_role="primary"}) > bool 900)
)
```

A reconnect shows up as a new `cnpg_pg_stat_replication_backend_start` series,
because the series carries the replica's `client_port`, so `changes()` never
sees it. Over the 7 days before November 17 this fired exactly for the two
staging timeouts on November 12 (07:06 and 08:26, as logged) and for none of
the five restarts in that week. A switchover can still fire it. The Cloud rule
was deleted.

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
   deliberately. Do not bulk-repoint the default source and assume this is sufficient.

## Dashboards

Since November 18, the Prometheus panels in `infra/grafana-dashboards/` read
Pulse. Their `$datasource` variables default to Tuist Pulse Metrics and offer
only `/^Tuist Pulse Metrics/` sources: select the staging, canary or
management source to view that environment. Every `A and on (L) B` became
`A * on (L) group_left () (max by (L) (B) * 0 + 1)`, because Pulse fails to plan
`and on` when either side is empty. These still read Grafana Cloud on purpose:
the cache VM dashboards (`cache-service`, `tuist-cache-server-overview`) and
the legacy cache half of the Kura adoption share panels, whose senders only
report to Cloud, plus the Loki and Tempo panels, which no Pulse source can
serve.

`page-load-apdex` reads Pulse SQL: the server's `request_kind=page_load`
`Request completed` lines in `opentelemetry_logs`, parsing `status` and
`duration_ms` and leaving out the `/ready` kubelet probe, which is most of
them. Its old LogQL parsed `Sent 200 in 12ms`, a format page loads stopped
logging before November 1, so it had shown nothing since. For November 16,
12:00 to 13:00, the SQL and Cloud Loki agree on 72 page loads and a P99 of
704.34 ms. The static-asset panels still parse `Sent N in Xms`, which
`MarketingStaticAssetObservabilityPlug` logs only when the origin serves an
asset; neither store had such a line in the 36 hours checked.

## Cloud storage stopped on November 17, 2026

The workload and management collectors write only to Pulse, as decided on
November 17 without the planned shadow and dual-write weeks. Production's Pulse
keeps everything it has received, while staging and canary keep 7 days. Rules
that look back further than a Pulse has data run on shorter history until it
fills (above). Cloud still
holds the earlier data until its retention ends; the `grafanacloud-*` sources,
Cloud credentials and notification services stay, both for that history and
for the senders listed under "Still on Grafana Cloud". To roll back, revert
the k8s-monitoring change that removed the `grafana-cloud-*` destinations and
point the moved rules back at `grafanacloud-prom` and `grafanacloud-logs`.
