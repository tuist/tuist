# Self-monitoring Pulse

Scrape `GET /metrics` on **every node**, not a load-balanced service address that
alternates nodes. Send scrapes to a separate monitoring system (for example an existing
Prometheus), **not back into Pulse**. The endpoint exports
Prometheus text format 0.0.4 without content negotiation or caching. It reads only
node-local counters, registry metadata, mailbox lengths, and VM statistics. It
never queries or appends to signal storage or waits for manifest owners blocked
in native I/O. Counter updates use ETS directly, without an exporter queue.

Counters reset on node or counter-process restart; use `rate`/`increase` to handle
resets. Canonical counters are initialized at zero; detailed series appear when
first observed. Gauges are always present. Observations and scrapes are not
transactions with storage and can be lost during process/node failure. These are
operational signals, not accounting ledgers or deployment-readiness gates.

## Exposure and independent collection

The endpoint does not authenticate with tenant ingest tokens and shares the
listener with ingest and MCP. Keep the **entire listener private**.
Port-level network policy cannot isolate `/metrics` from ingest on that port.
If ingest or MCP is exposed outside the trusted monitoring network, a path-aware
proxy **must deny `/metrics` on that ingress**, or require separate monitoring
authentication for it. Deny router-equivalent paths too, including percent-encoded
segments, duplicate slashes, and trailing slashes. Scrapers may use the private
node listener or a separately authenticated proxy route. For a normalizing Nginx
public proxy, a `location ^~ /metrics { return 404; }` block denies the metrics
path and its suffixes; verify normalization and test aliases before exposing it.
Network policy alone is not an alternative to that rule.

Labels use fixed vocabularies. No tenant identifiers, credentials, query text,
object keys, incoming telemetry labels, or raw error messages are exported.
User-controlled inputs cannot grow the number of time series.

Example Prometheus job (replace the target with each node's private address):

```yaml
scrape_configs:
  - job_name: pulse
    scrape_interval: 15s
    scrape_timeout: 5s
    metrics_path: /metrics
    static_configs:
      - targets: [pulse-node-1.internal:4000]
```

A collector must retain its independent destination and retry policy. The
[Helm chart](deployment.md) can create a Prometheus Operator `ServiceMonitor`
for this endpoint.

## Canonical metric contract

The canonical families retain the contract already published by `Pulse.SelfMetrics`.
Their operation labels describe layers of work, and latency remains a summary
with count and sum only, without quantiles.

| Metric | Type | Labels | Meaning |
| --- | --- | --- | --- |
| `pulse_operations_total` | Counter | `layer`, `operation`, `outcome` | Completed operations; outcomes are `success`, `error`, and `exception` |
| `pulse_operation_duration_seconds_count`, `_sum` | Summary | Same as above | Operation latency count and sum, including failed operations |
| `pulse_ingest_records_total` | Counter | `signal`, `outcome` | `accepted`: valid decoded records whose append succeeded; `rejected`: decoder drops; `failed`: valid decoded records whose append failed |
| `pulse_ingest_rejected_records_total` | Counter | `signal`, `reason` | Records dropped from accepted (partial-success) requests, by fixed reason. Currently only traces report reasons; see [traces](traces.md#acknowledgments-and-limits). Services and tenants appear only in the rate-limited warning log, never as labels |
| `pulse_usage_dropped_total` | Counter | none | Usage counts dropped because the instance already tracks 200,000 tenant-hours. See [usage metering](tenants.md#usage-metering) |
| `pulse_tenant_purged_objects_total` | Counter | none | Objects deleted while purging deleted tenants. See [deletion](tenants.md#deletion) |
| `pulse_admission_rejections_total` | Counter | `layer`, `reason` | Requests refused with a retryable overload error. `layer="ingest"`: `tenant_concurrency`, `tenant_rate` (configured tenant limits; node and fair-share refusals are in `pulse_ingest_admission_total`). `layer="query"`: `node` (interactive slots busy), `tenant`, `class`, `memory` (refused under [memory pressure](scaling.md#memory-pressure)). Tenants never appear as labels |
| `pulse_object_payload_bytes_total` | Counter | `direction` (`read`, `write`) | Consumed successful GET body bytes (including keyed-verification mismatches) and PUT payload bytes, including manifests; not provider-billed wire traffic or SDK retries |
| `pulse_keyed_publication_conflicts_total` | Counter | None | Keyed appends permanently rejected because existing bytes differ; inspect writer compatibility and coherent storage history rather than retrying, overwriting or rotating keys. See [keyed ingestion](keyed-ingestion.md). |
| `pulse_compaction_segments_total` | Counter | None | Source segments merged by successful compactions |
| `pulse_compaction_deleted_objects_total` | Counter | None | Retirement deletions confirmed by successful cleanup calls |
| `pulse_manifest_queue_depth` | Gauge | None | Publication callers, including active flushes, plus manifest-owner mailbox messages |
| `pulse_ingest_admission_total` | Counter | `signal` (`metrics`, `logs`, `traces`), `outcome` (`admitted`, `rejected`, `tenant_limited`, `handed_off`) | Ingest requests given an admission slot, refused with `429`/`RESOURCE_EXHAUSTED` (`tenant_limited` is the subset refused while free slots were kept for other tenants), or moved from their slot to the pending budget while they wait for publication. See [ingest admission](configuration.md#ingest-admission) |
| `pulse_ingest_admission_active_tenants` | Gauge | `signal` | Tenants holding or recently requesting a slot on this node; no tenant labels |
| `pulse_ingest_admission_in_flight` | Gauge | `signal` | Ingest requests holding an admission slot |
| `pulse_ingest_admission_pending_bytes` | Gauge | None | Estimated memory of requests waiting for publication without a slot |
| `pulse_alert_evaluation_skips_total` | Counter | `reason` | Native alert/recording ticks deferred without checkpointing; fixed reasons `authority_missing`, `freshness_unavailable`, `capacity`, `timeout`, `budget`, `overrun` |

Alert skip counters do not retain tenant/rule/query/provider details. A missing
signal manifest, including a never-written signal, is distinct from a failed
freshness read. Skips preserve the last rule checkpoint and do not imply healthy
current data. Compare counter rates with the age of each rule's `completed_at_ns`
through authorized state reads. Counters reset on restart and are not a durable
progress journal; scrape every evaluator instance. Instance-count overflow instead
commits `error` health and is not counted as a transient skip.

Operation layers:

- `ingest`: `otlp` (logs), `otlp_traces`, `otlp_metrics`, `loki`, `remote_write`, `sentry`. Timing starts before body parsing and
  includes decoding, append, and response preparation. Partial-success responses
  remain successful requests, with decoder drops counted separately.
- `query`: `http` for compatibility queries/discovery; `mcp` for direct tool
  dispatch; `promql`, `logql_log`, and `logql_metric` for evaluators; and
  `storage_logs` / `storage_metrics` / `storage_traces` for scans through the storage dispatcher.
  These are **different layers of the same query**, not additive query counts.
  Choose one layer for a dashboard or alert. Authorization and validation errors
  count even when no scan starts.
- `object`: `put`, `put_if_match`, `put_if_none_match`, `get`,
  `get_if_none_match`, `delete`, `list`, `list_prefixes`. Each wrapper invocation
  counts once. A conditional GET returning not-modified is successful; conditional
  write conflicts are errors even if a higher layer later retries successfully.
- `compaction`: `compact`, `cleanup` measure maintenance calls;
  `worker_merge`, `worker_cleanup`, `worker_discovery` measure background workers'
  supervised waits, including deadline failures. These are separate layers, not
  additive counts. A task may publish successfully after its worker wait times
  out. No-op passes succeed without incrementing successful-progress counters.

## Detailed metric contract

The detailed view retains tool/route distinctions, object-purpose classifications,
latency histograms, and separate queue/runtime gauges. Families that would clash
with canonical names are explicitly namespaced. **Do not add canonical and
detailed counters together**: they observe the same work from different views.
Filter a single view, and a single query/maintenance layer, for each calculation.

| Metric | Type | Labels | Meaning |
| --- | --- | --- | --- |
| `pulse_detailed_operations_total` | Counter | `kind`, `operation`, `purpose`, `outcome` | Completed ingest requests, public queries, logical object calls, and maintenance attempts |
| `pulse_detailed_operation_duration_seconds` | Histogram | Same as above, plus bucket `le` | Operation duration; buckets at 5 ms, 10 ms, 50 ms, 100 ms, 500 ms, 1 s, 5 s, 10 s, and +Inf |
| `pulse_ingest_stage_duration_seconds` | Histogram | `signal`, `stage`, plus bucket `le` | Where ingest time goes. Per request: `decode` (receiver decoding after the body is read), `prepare` (OTLP log timestamp fill, trace retention filter, remote-write metadata publication) and `buffer_wait` (time in the coalescing window). Per published segment, which a coalesced flush shares: `encode` (Parquet), `summarize` (manifest summary), `segment_put`, `manifest_wait` (from handing the segment to the manifest owner until its publication starts, including queueing behind the publication in flight) and `manifest_commit` (merge, encode and conditional write of the manifest, including retries). Buckets at 1, 5, 10, 25, 50, 100, 250, 500 ms, 1, 2.5, 5 s and +Inf |
| `pulse_manifest_segments` | Gauge | `signal` | Segments listed in manifest roots cached on this node, summed over tenants; for retention-managed roots, only the inline recent tail |
| `pulse_manifest_bytes` | Gauge | `signal` | Encoded bytes of those cached manifest roots. A flat root is rewritten whole on every publication, so `manifest_commit` grows with it; a paged root stays small |
| `pulse_manifest_referenced_segments` | Gauge | `signal` | Active segments the cached roots reference, including through paged-manifest pages, summed over tenants; retention-managed roots count only their inline tail |
| `pulse_manifest_referenced_bytes` | Gauge | `signal`, `age` (`0-30d`, `30-90d`, `90d+`) | Stored bytes of those active segments by record age, summed over tenants. A page reference's bytes are spread evenly over its time range. Excludes manifests, pages, retired objects awaiting deletion and segments of unknown size; retention-managed roots count only their tail. Age approximates object age for lifecycle tiers: compaction rewrites objects shortly after their records' time |
| `pulse_manifest_referenced_unsized_segments` | Gauge | `signal` | Referenced segments whose size the cached roots do not record (pages written before 1.30, legacy segments); they are missing from `pulse_manifest_referenced_bytes` |
| `pulse_manifest_roots` | Gauge | `signal`, `format` (`flat`, `paged`, `retention`) | Cached manifest roots by format. A `flat` root that keeps growing is the history-dependent ingest cost described in [manifest format](configuration.md#manifest-format) |
| `pulse_manifest_commit_duration_seconds` | Histogram | `signal`, `format`, `root_bytes_le` (`65536`, `262144`, `1048576`, `4194304`, `16777216`, `+Inf`), plus bucket `le` | One manifest publication: building and encoding the root, writing any new pages and the conditional root write, including conflict retries. `root_bytes_le` is the encoded size of the written root, so commit time can be compared by manifest size. Same buckets as `pulse_ingest_stage_duration_seconds` |
| `pulse_manifest_page_cache_entries` | Gauge | None | Immutable manifest pages (paged and retention formats) cached on this node |
| `pulse_manifest_page_cache_bytes` | Gauge | None | Accounted size of that page cache; it is bounded at 16 MiB |
| `pulse_object_cache_entries` | Gauge | `tier` (`memory`, `disk`) | Segment objects in this node's [object cache](configuration.md#object-cache) |
| `pulse_object_cache_bytes` | Gauge | `tier` | Bytes of those objects |
| `pulse_object_cache_reads_total` | Counter | `result` (`memory_hit`, `disk_hit`, `miss`, `shared`) | Segment reads through the cache: served from memory or disk, misses that issued a GET, and misses that shared another read's GET |
| `pulse_ingest_delivery_records_total` | Counter | `signal`, `outcome` | Known receiver deliveries: `accepted` after append success; `rejected` combines decoder drops and decoded records whose append failed |
| `pulse_object_bytes_total` | Counter | `operation`, `purpose`, `direction` | Successful logical GET body bytes and PUT payload bytes, partitioned by purpose |
| `pulse_object_requests_total` | Counter | `class` (`A`, `B`, `free`), `purpose` | Logical object requests by billing class: PUT and LIST are `A`, GET is `B`; DELETE, `304 Not Modified` and `412`/`409` conflict responses are `free`, as on Tigris. Failed requests count in their class. Native retries and extra LIST pages are not counted. See [storage costs](storage-costs.md#cost-model) |
| `pulse_detailed_compaction_segments_total` | Counter | `operation` | Source segments merged by `compact`, or confirmed retirement deletions by `cleanup` |
| `pulse_compaction_timeouts_total` | Counter | `operation` | Worker deadlines exceeded for `merge`, `cleanup`, or `discovery`, even while native work remains in flight |
| `pulse_manifest_mailbox_messages` | Gauge | None | Sum of manifest-owner mailbox lengths |
| `pulse_manifest_pending_segments` | Gauge | None | Enqueued segments, including segments currently being published |
| `pulse_manifest_waiting_requests` | Gauge | None | Publication callers, including callers in the current flush |
| `pulse_ingest_buffers` | Gauge | None | Active optional node-local unkeyed ingest buffers |
| `pulse_ingest_buffer_reserved_calls` | Gauge | None | Queued and executing requests reserved in unkeyed buffers |
| `pulse_ingest_buffer_input_bytes` | Gauge | None | Estimated external-term bytes reserved in unkeyed buffers, not actual heap memory |
| `pulse_ingest_buffer_rows` | Gauge | None | Queued and executing rows reserved in unkeyed buffers |
| `pulse_query_occupied_slots` | Gauge | None | Registered PromQL tenant slots, including admitted native work that outlives the response deadline |
| `pulse_retention_root_capacity_ratio` | Gauge | None | Highest metadata capacity ratio among the retention-managed scopes cached on this node; `0` when none are cached |
| `pulse_retention_pending_buckets` | Gauge | None | Expired time buckets still awaiting cleanup, summed over cached retention-managed scopes |
| `pulse_retention_managed_scopes` | Gauge | None | Retention-managed tenant/signal scopes cached on this node |
| `pulse_vm_memory_bytes` | Gauge | None | Total BEAM-reported memory. Only part of what the container uses; see `pulse_memory_bytes` |
| `pulse_memory_bytes` | Gauge | `kind` | Node memory by kind; see [memory breakdown](scaling.md#memory-breakdown) |
| `pulse_memory_ets_bytes` | Gauge | `table` | ETS memory per table name, excluding the binaries the tables reference (those count under `pulse_memory_bytes{kind="binary"}`) |
| `pulse_memory_process_bytes` | Gauge | `group` | Process heap, stack and mailbox memory by group: `manifest_owner`, `append_buffer`, `ingest_flush`, `query`, `maintenance`, `http_connection` (request handling, including ingest decoding) and `other` |
| `pulse_memory_pressure` | Gauge | None | `1` while the node is under [memory pressure](scaling.md#memory-pressure) |
| `pulse_memory_pressure_limit_bytes` | Gauge | None | Limit the pressure monitor compares resident memory with; `0` when disabled or unknown |
| `pulse_memory_pressure_transitions_total` | Counter | `state` | Pressure state changes, by the state entered (`on`, `off`) |
| `pulse_manifest_cache_max_bytes` | Gauge | None | Byte bound on cached manifest roots |
| `pulse_manifest_cache_evictions_total` | Counter | None | Manifest roots evicted to stay within that bound |
| `pulse_manifest_cache_evicted_bytes_total` | Counter | None | Encoded root bytes evicted |
| `pulse_vm_run_queue` | Gauge | None | BEAM scheduler run-queue length |
| `pulse_ingest_inflight_requests` | Gauge | None | Ingest requests holding an admission slot |
| `pulse_ingest_max_concurrent_requests` | Gauge | None | Ingest admission slots on this node |
| `pulse_query_inflight` | Gauge | None | Interactive queries holding a slot |
| `pulse_query_max_concurrent` | Gauge | None | Interactive query slots on this node |
| `pulse_memory_budget_bytes` | Gauge | None | Memory budget that sized this node's slots, `0` when fixed defaults apply |

Slot occupancy divided by slots (for example
`pulse_ingest_inflight_requests / pulse_ingest_max_concurrent_requests`) is the
saturation signal to autoscale on; see [scaling](scaling.md).

Detailed operation labels:

- `kind=ingest`: `otlp` (logs), `otlp_traces`, `otlp_metrics`, `loki` (both formats), `remote_write`, `sentry`. HTTP 4xx are
  `rejected`; 5xx are `error` or `exception`; successful/partial responses are
  `ok`. Parser failures count before controllers run. Each request counts once.
- `kind=query`: `http_promql`, `http_logql`, `http_labels`, and tool names
  `query_logs`, `query_metrics`, `query_traces`, `query_logql`, `query_promql`,
  `discover_metrics`, `get_trace`, `search_traces`, `search_trace_metadata`, `traceql_metrics`,
  `discover_trace_tags`, `discover_trace_tag_values`, `query_errors`,
  `list_error_issues`, `list_error_changes`, `list_indexed_error_issues`. Capability-scoped alert tool
  attempts share the bounded label `alert_tool`, not user-supplied rule/tool names. Tool errors count
  as `error` even when the MCP transport returns HTTP 200. Direct `Tools.call`
  calls collapse unknown names to `unknown_tool`; the MCP dispatcher rejects
  unknown names before dispatch, so they are not tool attempts over MCP. Internal
  evaluator/storage calls are not additional detailed public queries.
- `kind=object`: the same eight object operations as the canonical view.
  Outcomes distinguish `ok`, `error`, `exception`, `conflict`, `not_found`, and
  `not_modified`. `purpose=manifest` identifies `/manifest.json` keys, `segment`
  identifies `.parquet` keys, `metadata_page` identifies manifest pages
  (`.json` objects under `index/` or `journal/`), `backup` identifies manifest
  backups (`backups/`), and `other` covers listings, markers, and other objects. Retention reads, paginated listings, tenant discovery, and admitted
  deletes reuse the `get_if_none_match`, `list`, `list_prefixes`, and `delete`
  operations. Other
  operation kinds use `purpose=none`. Only meaningful byte directions are emitted.
- `kind=compaction`: `compact`, `cleanup`, including explicit and background
  calls. No-op passes count operations but add no segments. The separate timeout
  counter increments when the worker stops waiting; a late success also increments
  the eventual operation-success counter. These are different events.
- `kind=retention`: `advance`, `cleanup`, `cleanup_retired`, `sweep`, including
  background passes and explicit calls such as `convert_offline`. `advance` also
  covers manifest conversion; `sweep` also covers an active catch-up job. A pass
  with nothing to do counts as `ok`. Retention has no canonical-view layer; use
  this detailed family and the retention gauges.

## Counting boundaries and limitations

For OTLP histograms/summaries, accepted/failed record counts describe **projected
float samples**, while decoder rejections describe **source points**. One source
point can produce many accepted rows. Detailed rejected-delivery counts can
therefore combine source-point rejections and projected failed rows; do not
interpret accepted-plus-rejected totals as a source-point rejection percentage.
Inspect the OTLP partial-success count and exporter evidence separately.

Record counters describe attempts, not unique stored records. Retried or
idempotently acknowledged batches count again. Canonical decoder rejection stays
separate from publication failure; the detailed receiver-delivery view combines
both as rejected deliveries. Direct storage appends contribute to canonical
accepted/failed counts, but not to the receiver-only delivery view. A storage
error can be ambiguous about publication: the counters describe acknowledgements,
not proof that nothing was written. Authentication, parsing, body/attribute/record
budgets, or decoding may fail before a complete count exists; those count requests,
not invented record estimates. Compare these signals with collectors' queues,
deliveries, and drops.

Object metrics are logical successful body bytes, not provider billing. They
exclude headers, listing response bodies, failed/ambiguous PUT payloads, native
client retries, provider pagination requests, and partial transfers. Conditional
GETs returning 304 add no body bytes; write conflicts add no successful bytes.
Application-level retries are new logical calls. Reconcile against provider
billing rather than deriving a bill solely from these counters.

A partially failed cleanup may have deleted objects. Object-operation counters
still show those attempts, but successful-cleanup progress excludes that pass.
Untrappable process termination cannot record completion. Durations end when the
underlying operation completes, while worker wait metrics and deadline counters
report timeouts immediately.

Retention gauges cover only managed scopes whose root this node has loaded
recently, through ingest, queries, or its own maintenance. A scope that no node
has touched lately is absent, so the gauges are not a cluster inventory. Take the
maximum ratio and the sum of pending buckets across nodes, and use
`Retention.inspect_policy/4` (see [retention](retention.md#operating-retention))
for an authoritative view of one tenant/signal.

Queue gauges are instantaneous snapshots, not admission guarantees. Mailbox
messages and publication batches are different stages; inspect both. Registry
cleanup removes terminated owners. Scrapes do not wait for native I/O. PromQL
slots do not describe all log/raw query concurrency. Optional [ingest coalescing](configuration.md#ingest-coalescing)
adds bounded unkeyed input buffers; their gauges read reservation tables directly,
including while publication is blocked. They include queued and executing inputs,
not just records waiting for the flush timer. Values are zero when no buffers are
active. Overflow/oversized input processed directly is not in these gauges.
There is still no node-wide ingest rate admission. Histogram updates and buffer
reservation attempts may be observed partway through an update; metric snapshots
are best effort.

## Useful queries

Keep the scrape job and node `instance` label in dashboards:

```promql
# Canonical published records per second by node.
sum by (instance, signal) (rate(pulse_ingest_records_total{outcome="accepted"}[5m]))

# Canonical MCP tool failures, without counting evaluator/storage layers again.
sum by (instance) (rate(pulse_operations_total{layer="query",operation="mcp",outcome="error"}[5m]))

# Canonical publication backlog.
pulse_manifest_queue_depth

# Detailed ingest p95, including failures.
histogram_quantile(0.95, sum by (instance, le, operation) (
  rate(pulse_detailed_operation_duration_seconds_bucket{kind="ingest"}[5m])
))

# Where ingest time goes: mean seconds per stage and signal. Request stages and
# segment stages have different counts when coalescing shares a segment.
sum by (signal, stage) (rate(pulse_ingest_stage_duration_seconds_sum[5m]))
  / sum by (signal, stage) (rate(pulse_ingest_stage_duration_seconds_count[5m]))

# Flat manifest size per signal, the main driver of manifest_commit.
pulse_manifest_bytes

# Manifest commit p90 by format and root size; flat roots grow, paged stay small.
histogram_quantile(0.9, sum by (le, signal, format, root_bytes_le) (rate(pulse_manifest_commit_duration_seconds_bucket[5m])))

# Roots still in the flat format.
sum by (signal) (pulse_manifest_roots{format="flat"})

# Resident memory not attributed to BEAM mappings or the C allocator: mapped
# code, thread stacks and anything unexpected.
pulse_memory_bytes{kind="rss"}
  - ignoring(kind) sum without(kind) (pulse_memory_bytes{kind=~"beam_mapped|malloc_in_use|malloc_free"})

# Where BEAM memory goes, and the largest process groups and ETS tables.
pulse_memory_bytes{kind=~"processes|binary|ets|code|atom|system_other"}
topk(5, pulse_memory_process_bytes)
topk(5, pulse_memory_ets_bytes)

# Detailed public query failures.
sum by (instance, operation, outcome) (
  rate(pulse_detailed_operations_total{kind="query",outcome!="ok"}[5m])
)

# Logical manifest write bytes and conditional conflicts.
sum by (instance) (rate(pulse_object_bytes_total{purpose="manifest",direction="write"}[5m]))
sum by (instance) (rate(pulse_detailed_operations_total{kind="object",outcome="conflict"}[5m]))

# Worker deadlines exceeded even while native work is still running.
sum by (instance, operation) (rate(pulse_compaction_timeouts_total[5m]))

# Retention: failing maintenance passes, closest scope to a metadata limit, and
# cleanup backlog across nodes.
sum by (instance, operation) (rate(pulse_detailed_operations_total{kind="retention",outcome!="ok"}[15m]))
max(pulse_retention_root_capacity_ratio)
sum(pulse_retention_pending_buckets)

# Retention manifest-page reads and their bytes.
sum by (instance, operation) (rate(pulse_detailed_operations_total{kind="object",purpose="metadata_page"}[5m]))
sum by (instance) (rate(pulse_object_bytes_total{purpose="metadata_page",direction="read"}[5m]))
```

Alert on scrape failure (`up == 0`) through the independent monitor. Choose
latency, queue, rejection-rate, compaction, and retention thresholds from your
measured load. For retention, alert well before the capacity ratio reaches `1.0`
and when pending buckets keep growing over several retention intervals. Instrumentation alone establishes neither safe capacity nor readiness.

## Alerts

The Helm chart ships alert rules for these metrics in
[`infra/helm/pulse/files/alerts.json`](../../infra/helm/pulse/files/alerts.json), a
Prometheus rule file (JSON is valid rule-file YAML):

- With the Prometheus Operator, set `prometheusRule.enabled=true` to install
  them as a `PrometheusRule`.
- With Grafana-managed alerting, import the file as Grafana-managed rules (in
  Grafana 12, **Alerting > Alert rules > Import**) and point it at the
  datasource holding these metrics.

Every expression runs on Pulse's own PromQL, so the metrics may be stored in
Pulse. In that case keep them in a dedicated tenant and set the rules'
no-data and error states to alerting: if Pulse is down, its own rules cannot
evaluate, and `PulseMetricsAbsent` only fires through that no-data handling.

| Alert | Fires when |
| --- | --- |
| `PulseIngestFailures` (critical) | Valid records of a signal have failed to append for 10 minutes. |
| `PulseIngestRejections` | Records of a signal have been rejected for an hour (invalid data, disabled features, out of retention). |
| `PulseIngestVolumeHigh`, `PulseIngestVolumeLow` | A signal's accepted rate over 12 hours is more than double, or less than half, the previous week's. |
| `PulseObjectStoreErrors` (critical) | Over 5% of object-store requests fail for 10 minutes. |
| `PulseObjectWritesHigh`, `PulseObjectRequestsHigh` | Object-store bytes written or requests over 12 hours doubled against the previous week: the storage bill follows. |
| `PulseManifestBacklog` | Over 100 callers wait on segment publication for 15 minutes on an instance. |
| `PulseCompactionTimeouts` | A compaction operation timed out more than 3 times in an hour. |
| `PulseRetentionCapacity`, `PulseRetentionCapacityCritical` | A retention-managed scope passes 80% (warning) or 95% (critical) of its metadata capacity. |
| `PulseKeyedPublicationConflicts` | A keyed append was rejected because stored bytes differ. |
| `PulseMetricsAbsent` (critical) | No instance has reported metrics for 10 minutes. |
| `PulseRunQueueHigh` | An instance's scheduler run queue stays above 50 for 15 minutes. |
| `PulseQueryErrors` | Over 10% of public queries fail for 15 minutes. |
| `PulseAlertEvaluationSkips` | Native alert evaluation keeps skipping ticks (native alerting only). |

Thresholds are starting points; tune them to your traffic. Pulse does not
export series counts (that would need cluster-wide, per-tenant state), so
volume alerts use accepted samples and stored bytes as the cost signals.
