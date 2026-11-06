# Pulse storage with Grafana Cloud dashboards and alerts

Keep Grafana Cloud as the UI, Grafana-managed alert evaluator and notification
router. Use its built-in Prometheus, Loki and Tempo data sources against Pulse.
Pulse does not implement the Mimir/Loki ruler or Alertmanager APIs. Do not move
production paging to its experimental native alert evaluator during this cutover.

## Private connection

The production service is `pulse.observability.svc.cluster.local:4000`. The
production `pdcAgent.permitRemoteOpen` list in the Tuist chart allows exactly
this host and port alongside the existing database targets. Apply that change
through the normal server deployment, or a narrowly scoped, human-elevated
production operation. Do not expose Pulse publicly or widen the tunnel to `*`.

`pulse-datasources.json` contains three **Grafana HTTP API request bodies**, not
a Helm resource or a file Grafana Cloud automatically imports. They use the
same production PDC network as Tuist Production DB, confirmed through Grafana's
read API on November 5, 2026. Reconfirm the network if that connection changes.
Create them separately with `POST /api/datasources`, or use the equivalent fields
in Connections → Data sources. Reuse existing `pulse-*` UIDs if a previous
attempt created them; do not create duplicates. They deliberately do not replace
the Cloud sources or become defaults.

**Credentials are deliberately absent.** For each source, enter the tenant's
raw token as the Basic Auth password in Grafana's secure configuration. The
username `tuist` selects the tenant. The token must match its configured digest
in Pulse; a `sha256$...` digest is not a usable password. Never put credentials
in this JSON, dashboards, Git Sync, query parameters or PRs. The metrics source
needs ingest permission as well as read permission if Grafana writes recordings
to it. Tenant shared-secret authentication currently grants both.

`manageAlerts: false` disables the unsupported **data source-managed** ruler
interface, not Grafana-managed alerting. Metrics explicitly allows recording
write-back. Grafana supports recording writes over PDC to Prometheus-compatible
sources ([documentation](https://grafana.com/docs/grafana/latest/datasources/prometheus/configure/));
Pulse accepts remote write at `/api/v1/write`. Prove the deployed writer uses
that endpoint before moving any dependent alerts. Tempo streaming is disabled
because Pulse's bounded HTTP APIs are not Tempo's streaming API.

Tempo search, discovery and TraceQL metrics also require Pulse's explicit
`tempoSearch.enabled: true` (`PULSE_TEMPO_SEARCH_ENABLED=true`) on every query
instance. They are disabled by default and enabled in the current managed
production overlay; confirm the deployed release uses that setting. A successful
trace-by-ID lookup does not prove that gate is enabled. Upgrade matching
application/native artifacts together and validate the bounded search workload
against the actual `observability` release.

## Verify before moving consumers

1. Save & test all three sources from Grafana Cloud, not just from a pod.
   Confirm `count by (cluster) (up)` and a recent labeled metric range on Pulse
   Metrics. Check metric-name/label/series discovery and a histogram percentile.
   On Pulse Logs, retrieve recent production lines and run a nonempty
   `count_over_time` query. On Pulse Traces, retrieve a known recently ingested
   trace ID, then test the actual dashboard search and TraceQL metric queries.
   A successful health check or an empty result alone is not acceptance.
2. Inventory **current** complete rules and dashboards. The November 5 query
   corpus covers 170 rule definitions and 31 dashboards, but is not a complete
   lifecycle/routing export. Older inventories in `pulse/plans/alerting` are
   historical. Leave SQL, ClickHouse, Cloud billing/usage, synthetic monitoring
   and other non-replaced sources alone.
3. Compare the same production queries and time windows in both stores. From
   `pulse/`, `mix pulse.parity` accepts Git Sync v1/v2 dashboard resources and
   the `queries` corpus envelope. Use `--scrape-interval 60` and explicit
   `--var name=value` settings for the production panel selection. It rejects
   files yielding zero queries. Inspect the reported count: this command covers
   PromQL/LogQL only, not SQL, TraceQL, dashboard rendering or alert lifecycle.
   The corpus preserves instant/range modes but does not automatically apply
   its per-dashboard variable defaults. Unset matcher variables still broaden
   to a regex and are not proof of a particular panel's parity.
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

Before stopping Cloud writes, pass the [cutover gates](../../../pulse/plans/tuist-cutover-runbook.md#gates)
on the exact deployed version: provider-backed capacity, nonempty query parity,
alert transitions, recording publication, notification delivery and failure
recovery. Queries with week-long offsets need that history or a validated
backfill. The Pulse volume/cost replacement rules also need a prior-week baseline;
they cannot replace Cloud usage alerts after one day of data. Import
`../pulse/files/alerts.json` as **Grafana-managed** rules with explicit no-data/error
behavior; this Prometheus-format file is not directly a Grafana provisioning API
payload. Monitor Pulse failure/no-data from outside Pulse's own failure domain.

Only after acceptance, remove Cloud ingestion for all senders while preserving
Pulse forwarding, labels, sampling and metric identity. Keep old data sources
available for retained-history queries and rollback. Do not delete Cloud data,
credentials or notification services as part of a storage switch. The existing
runbook calls for a shadow week and two further weeks of dual-writing; a next-day
shutdown needs an explicit risk decision, not a claim that these gates passed.
