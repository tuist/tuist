# Tuist cutover runbook: Grafana Cloud stores to Pulse

Status: prepared, not executed. Read-only inspection is not cutover acceptance.
Production mutations need explicit human authorization and the access tier
required by `infra/AGENTS.md`. Decisions below were made on 2026-10-19 and
reviewed with Codex;
see [grafana-replacement.md](grafana-replacement.md) for the evidence behind
them.

## Current readiness

The November 6, 2026 Grafana read API lists 22 datasources, **none pointing to
Pulse**, and 174 Grafana-managed rules (170 alerting, four recording). All four
active Kura recordings still use `grafanacloud-prom` for both query and output.
The older rule/dashboard counts below are historical inventories, not today's
complete migration scope. Refresh the export before moving consumers.

The local compatibility suite exercises the supported Prometheus, Loki and
Tempo read contracts through native Parquet and an owned loopback object store;
it does not establish production query parity, retained history, provider
capacity, recording write-back or notification delivery. No gate below is
marked passed by that suite. In particular, an empty query result is not proof
that ingestion or historical coverage is complete.

Use the [private connection and datasource procedure](../../infra/helm/k8s-monitoring/pulse-grafana.md)
for the existing `pulse` release in namespace `observability`, secure credentials,
PDC allowlisting and separate `pulse-*` datasource UIDs. Deploy the tested app
and native artifacts together (trace `{2,1,3,10,13}`, trace metrics `7`). Do not
create another bucket or redirect existing dashboards as a connectivity test.

This replacement covers stored metrics, logs and traces. It does not implement
Pyroscope profile storage or replace SQL, Sentry, synthetic monitoring, Grafana
Cloud's own usage/billing telemetry, or alert-state-history storage. Grafana
currently lists those additional source types; their presence alone does not
prove active ingestion. Inventory any actual use before claiming that all Cloud
storage can be stopped. Keeping Grafana-managed alerts also keeps its alert
configuration/state and notification services, not only a stateless renderer.

The checked-in collector/storage configuration also leaves these gates open:

- Staging, canary and production write to **separate environment-local Pulse
  stores**. The production PDC connection does not federate them. Provide
  private datasource access to each required store, or explicitly design and
  validate consolidated ingestion before using cross-cluster queries.
- Management remains Cloud-only by design, and `cache/platform/alloy.nix`
  configures an external Cloud-only sender. Confirm actual sender/retirement
  status, including pentest, and give every required sender a replacement.
- Cloud and Pulse destination processing are not identical: Cloud normalizes
  Kura `instance` labels, drops more non-production metrics and tail-samples
  traces. Cloud-generated `traces_service_graph_*` metrics do not traverse
  Alloy at all. Preserve intentional label/query semantics and replace any
  used derived metrics; do not assume that dual-write means identical data.
- Configured observe-mode retention does not prove historical samples exist.
  The replacement volume rules need a 7-day range offset by 12 hours (7.5 days
  of baseline); each other query needs its own range-plus-offset coverage.
- Keep Pulse health collection/probes outside Pulse's storage failure domain.
  Existing Cloud scrapes cannot simply be removed or redirected into the
  store they monitor. Prove the surviving no-data/error paging path.
- Provider-backed capacity and recovery gates remain unverified. Simulated
  S3 latency is not a Tigris acceptance run. The old p99-ingest-under-1-second
  gate also needs an explicit SLO decision with the current 2-second ingest
  coalescing window; do not quietly mark that threshold passed.

These are desired-state findings, not a fresh Kubernetes rollout check. The
November 6 view-tier checks required interactive sign-in, so live fleet,
ingestion, history and recovery status could not be established.

## Decisions

| Area | Decision | Why |
| --- | --- | --- |
| Alerting | Keep Grafana-managed alerting (evaluator, routing, contact points, silences, templates) and point its rules at Pulse datasources. Pulse native alerting stays experimental and out of the cutover. | Grafana-managed rules can query external compatible datasources; this does not mean the deployed rules already query Pulse. Preserve their complete configuration and verify actual transitions and delivery. |
| Tempo search and TraceQL metrics | One flag, `PULSE_TEMPO_SEARCH_ENABLED` (`tempoSearch.enabled`), off by default, **on for Tuist** after the capacity check below. | Both serve the same exploration workflow; no need for separate switches yet. |
| Log query budgets | Log metric queries use their own `PULSE_QUERY_MAX_LOG_SAMPLES` budget (kept lines, enforced while reading), not PromQL's sample budget. | Kept lines still cost ~40 bytes each during a query, so memory is bounded, not flat. |
| Segment prefetch | Product default raised to `PULSE_QUERY_PREFETCH=4`; **8 for Tuist**, confirmed on real S3 at gate 5. | Measured 2026-10-20 (2M log lines in 1,000 segments, MinIO behind a 25 ms-per-request proxy): metric queries took 25-28 s at 1, 5.8-6.6 s at 4 and 2.8-3.3 s at 8, with no more object GETs (11,373 / 10,266 / 9,965 over the run) and no more memory (115 / 103 / 104 MiB peak). An early-stopping log query stayed at 0.04 s. |
| Query timeout | New `PULSE_QUERY_TIMEOUT_MS` (default 10 s, unchanged); **25 s for Tuist**. | Grafana's datasource timeout is 30 s; a 7-day dashboard panel over real S3 can need more than 10 s. Keep it below the client's. |
| Live tail | Best-effort manifest following on each instance with open tails (`PULSE_LOKI_TAIL_POLL_INTERVAL_MS`, 1 s), deduplicated against its own pushes. | This is not a durable changefeed: late publication, failed polls and compaction can hide originals before observation. Backlog exhaustion closes the stream explicitly. See `docs/querying.md`; do not infer completeness across instances from polling. |
| Self-monitoring | Import the chart's `files/alerts.json` as Grafana-managed rules using a metrics/probe source outside Pulse, with no-data and error states set to alerting. | Replaces storage-specific usage/spend alerts without depending solely on the failing Pulse store. Follow `docs/self-monitoring.md`; a separate tenant inside Pulse is not a separate failure domain. |
| Metric metadata | Keep Remote Write 1.0 for now. | Alloy sends metadata only over Remote Write 2.0 with `honor_metadata`, and the k8s-monitoring chart (4.0.3 and the latest 4.5.3) cannot set `honor_metadata` on the scrapes it generates; only Tuist's own `prometheus.scrape` blocks could. Experimental Alloy for partial metadata is not worth it. Revisit when the chart exposes it. |
| Native histograms and exemplars | Supported; leave Alloy's `send_native_histograms` and `send_exemplars` off at cutover, turn them on afterwards if wanted. | Tuist's dashboards and alerts use classic histograms and no exemplars, so the cutover should not change what is sent. Both verified against Prometheus 3.5.0 on the same data. |
| TraceQL `compare()` | Deferred. | Not used by Tuist dashboards or alerts; needs its own accumulator and upstream fixtures. |

## Starting configuration for Tuist

Set through the Helm chart (`extraEnv` where no chart value exists). Values
marked *measure* must be confirmed by the capacity run before production.

```
tempoSearch.enabled: true
logCompaction.enabled: true
metricsCompaction.enabled: true
traceCompaction.enabled: true
otlpGrpc.enabled: true                    # if Alloy exports OTLP over gRPC (port 4317)
PULSE_QUERY_MAX_LOG_SAMPLES=20000000      # measure: ~800 MB peak per query
PULSE_QUERY_MAX_WORK=200000000            # measure
PULSE_QUERY_MAX_SCAN_ROWS=50000000        # measure: ~2M log lines/hour today
PULSE_QUERY_MAX_SCAN_BYTES=4294967296     # measure
PULSE_QUERY_PREFETCH=8                    # confirm at gate 5 on real S3
PULSE_QUERY_TIMEOUT_MS=25000              # below Grafana's 30 s datasource timeout
```

Memory sizing: four concurrent queries per node, two per tenant. With the log
budget above, size each node for at least 4 × the measured peak query memory
plus ingest buffers.

## Metric metadata

`/api/v1/metadata` serves what remote-write senders report. Prometheus sends it
by default (verified with Prometheus 3.5.0). Alloy's `prometheus.remote_write`
builds its queue without a scrape manager, so it never sends Remote Write 1.0
metadata; it sends per-series metadata only over Remote Write 2.0 for scrapes
with `honor_metadata = true`. Pulse accepts 2.0, verified with Alloy 1.19.2
(179 families, no failed samples).

Checked 2026-10-20 in the k8s-monitoring chart Tuist pins (4.0.3) and the
latest release (4.5.3): the Prometheus destination can switch protocols
(`remoteWriteProtocol: 2`) and a collector can run experimental features
(`alloy.stabilityLevel: experimental`), but no chart feature can set
`honor_metadata` on the scrapes it generates (kubelet, cAdvisor,
kube-state-metrics, node exporter, annotation autodiscovery). Only Tuist's own
`prometheus.scrape` blocks in the chart's raw Alloy configuration could.

Decision: keep Remote Write 1.0. Partial metadata for a handful of custom
scrapes does not justify running Alloy in experimental mode; Grafana's metric
browser keeps its name-based hints. Revisit when the chart exposes
`honor_metadata`. Switching later needs no Pulse change.

## Gates

Each gate lists what must be measured and the threshold to pass. A failed gate
stops the cutover; nothing is switched until every gate passes.

1. **Shadow ingestion (1 week).** Alloy dual-writes metrics, logs and traces to
   Grafana Cloud and Pulse. Pass: zero sustained ingest errors on Pulse
   (`pulse_ingest_records_total{outcome="rejected"}` explained by known
   rejections only), no manifest or compaction backlog growth over the week,
   p99 push latency under 1 s.
2. **Dashboard parity.** Run every current dashboard query (the October inventory
   had 370 PromQL, 16 LogQL, 1 TraceQL) against both stores over the same windows
   (1h, 6h, 24h, 7d).
   Pass: PromQL series sets identical and values within 1e-9 relative (counter
   resets and stale markers included); LogQL counts identical; quantiles within
   one bucket boundary. Run with `mix pulse.parity` (from a Pulse
   checkout; credentials in `PULSE_PARITY_REFERENCE_HEADERS` and
   `PULSE_PARITY_CANDIDATE_HEADERS`, one `Name: value` per line):

   ```
   mix pulse.parity dashboards/*.json --report dashboards-report.json \
     --reference-prometheus https://prometheus-prod-24-prod-eu-west-2.grafana.net/api/prom \
     --reference-loki https://logs-prod-012.grafana.net \
     --candidate-prometheus https://pulse.internal --candidate-loki https://pulse.internal
   ```

   Dashboards are the JSON exports of Tuist's Grafana dashboards. Give
   quantile panels a per-query `tolerance` in a plain query file when bucket
   interpolation differs. The TraceQL panel is compared by hand.
3. **Alert parity.** Refresh the inventory and evaluate all replaceable rules
   against both datasources every minute for the shadow week (Grafana rule test API or a shadow Grafana
   folder with notifications disabled). Pass: identical firing/resolved
   transitions, or each difference explained by data timing, documented.
   Spot-check each rule's queries first with `mix pulse.parity
   plans/alerting/grafana-rule-inventory.json --window 6h --datasource
   grafanacloud-logs=loki --datasource grafanacloud-prom=prometheus ...`.
   - Recording rules: `kura:pod_region`, `kura:node_pool`,
     `kura:pool_region`, `kura:node_region` read `kura_node_geo_info`,
     `kube_node_labels` and `kube_pod_info` and write back to the Prometheus
     datasource, with `kura:pool_region` and `kura:node_region` depending on
     the others. Keep them as Grafana recording rules targeting the Pulse
     datasource (written through remote write), in dependency order, and
     compare their outputs during the shadow week.
   - The October inventory's 9 rules not migrated stay on their current
     datasources; recheck this classification: ClickHouse
     SQL (`Xcode cache - CI remote reads slow for an account`,
     `Slow ClickHouse query`) and Grafana Cloud usage/billing
     (`Metrics samples rejected as duplicate timestamps`, `Cardinality
     explosion - rapid active series growth`, the two `Global Spend` rules
     and the three `Anomaly` rules). The usage and spend rules lose meaning
     once data leaves Grafana Cloud. Pulse's chart now ships replacements
     (`infra/helm/pulse/files/alerts.json`, see docs/self-monitoring.md#alerts):
     duplicate-timestamp discards map to `PulseIngestRejections`; active
     series growth and the metrics/logs/traces usage anomalies map to
     `PulseIngestVolumeHigh` and `PulseIngestVolumeLow` (per signal, 12 h
     against the previous week); the two spend rules map to
     `PulseObjectWritesHigh` and `PulseObjectRequestsHigh`. Pulse exports no
     series count, so cardinality shows up as accepted-sample growth. Import
     them before cutover.
4. **Notification verification.** With notifications routed to a test channel,
   confirm every contact point used today (`Slack #notifications 2`,
   `Incidents`) receives a firing and a resolved message from a rule on the
   Pulse datasource, with templates rendering the same fields.
5. **Capacity.** Replay one peak day of Tuist traffic (or 2× the measured
   peak) against a staging Pulse on the production object-store provider.
   Pass: dashboards and alert queries within their current latency (p95 under
   5 s), no query budget errors at the chosen budgets, node memory under 70%
   with four concurrent heavy queries, provider request costs within the
   storage-cost estimate. Run the prefetch benchmark here: adopt 4 only if p95
   query latency improves and peak memory and request counts stay within
   budget.
6. **Failure and restore drills.** Kill a node mid-ingest and mid-compaction;
   restart with cold caches; make the object store unavailable for 5 minutes.
   Pass: no acknowledged data lost, ingest recovers by itself, queries fail
   explicitly rather than return partial data. Restore a deleted tenant prefix
   from the bucket's versioning/backup and confirm dashboards return the same
   data.

## Cutover

1. Point the accepted dashboards and rules at the separate Pulse datasources
   (Prometheus, Loki, Tempo), including nested model references, variables,
   correlations and recording output targets. Preserve rule UIDs/lifecycle and
   leave the original Grafana Cloud datasources available for rollback/history.
2. Keep dual-writing for two more weeks.
3. Stop writing to Grafana Cloud once nothing has needed it for those two weeks.

## Rollback

Trigger: any alert misfire or miss attributable to Pulse, dashboard queries
failing for more than 10 minutes, or ingest rejecting data. Action: point the
datasources back at Grafana Cloud (still receiving data during the dual-write
period) and file the cause. Data written only to Pulse during the incident
stays in the bucket for later backfill.
