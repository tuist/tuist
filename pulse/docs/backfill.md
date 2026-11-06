# Historical backfill

Pulse can ingest historical records through its normal authenticated receivers.
There is no Cloud bucket importer, TSDB block upload API, or automatic historical
exporter. Loki chunks/indexes and Mimir/Thanos TSDB blocks are not Pulse Parquet
segments. Never copy them into `tenants/` or construct manifest entries by hand.

## Establish the boundary first

Record the source instance, destination instance and tenant, exact selectors,
timestamps and source retention/export entitlement. Measure earliest visible data
separately for each signal and sender. Deployment creation time is corroboration,
not a storage watermark. Query emptiness does not prove physical absence: inspect
the authoritative manifest and committed retention floor through an authorized
read-only operator path before declaring data deleted or a read defect repaired.
Do not extract storage credentials from a running workload for this purpose.

Configured retention is not the committed floor. Positive durations start the
worker even when `PULSE_RETENTION_ENABLED=false`; `observe` previews advancement,
but already committed floors still reject older records. `paused` also does not
rewind them. See [retention](retention.md). No import bypasses a floor. If required
history predates one, use a separately approved archive tenant/instance with an
appropriate policy rather than editing the manifest or resurrecting objects.
Durations are instance-wide per signal, not per tenant. A different archive
retention policy requires a separate instance/bucket, not just a new tenant name.

Choose either an approved backfill or a deliberate warm-up interval with Cloud
history still readable. Keep dual-writing until overlap reconciliation passes.
An environment-local Pulse instance is not a federation of every environment
that a Cloud datasource contains; preserve environment and tenant isolation.

## Logs: prepare a bounded saved response

Export a **raw stream selector**, without line/label transformations, using Loki
`query_range`, exact nanosecond bounds, no sampling interval and a known limit of
at most 10,000. Preserve the request alongside the response. Partition into
disjoint half-open time windows and, where needed, disjoint stream selectors.
Check the source's end-bound convention; prepared entries must be in `[start,end)`.

Compile first so build output does not enter the batch file. Then prepare one
saved response locally (no network or application startup):

```sh
mix compile
mix pulse.backfill.loki --input export.json --tenant archive \
  --start-ns 1700000000000000000 --end-ns 1700000001000000000 \
  --limit 5000 > batch.json
```

The task rejects duplicate JSON object keys (including escaped equivalents),
warnings, non-stream responses, malformed values, entries outside
the window, responses reaching the declared request limit, and inputs/push bodies
over 4 MiB. It applies the local Pulse ingest limits and decoder; destination
configuration and its committed floor still need separate verification. Decimal
nanoseconds, stream labels, structured metadata, order and duplicate entries are
preserved. The envelope contains the body, tenant, bounds, row count, source hash
and an idempotency key. The task does **not** verify that the source selector was
raw, unsampled, correctly partitioned, or that the declared limit matches its
request. Review that evidence before accepting a batch. An empty batch alone is
not evidence that a sender had no logs.

If a response reaches its limit, export narrower windows or disjoint selectors.
Do not page by adding one nanosecond to the last returned entry: multiple entries
can share that timestamp. If one timestamp in one stream exceeds the source cap,
stop and obtain an uncapped provider/archive export; this tool cannot recover it.
Never deduplicate legitimate identical records to work around a cap.

After separate destination-write approval, send only `body` to
`POST /loki/api/v1/push` with the envelope's tenant bound by destination auth and
its `Idempotency-Key`. Require 204 and no positive `X-Pulse-Rejected-Records`.
The task intentionally does not send requests or collect credentials. Freeze
the batch, source, window partition, encoder version and journal before upload.
Retry the exact batch with the same key after an ambiguous/retryable failure;
never repartition, change keys or switch to unkeyed delivery to escape a 409.
See [keyed ingestion](keyed-ingestion.md): keys are content-addressed, not
exclusive reservations. Different or overlapping batches can duplicate records
even when each batch is individually retry-safe. A local Memory-adapter replay
does not establish S3 retry safety; validate against an isolated S3 test prefix.

## Metrics: require raw samples, not evaluated graphs

The destination accepts Snappy-block-compressed Prometheus remote-write 1.0 and
2.0 protobuf at `POST /api/v1/write`. Source timestamps are **milliseconds**;
Pulse stores nanoseconds. Existing ingest accepts old samples subject to the
committed floor, not a special migration wall-clock age limit.

Prefer a provider-supported raw remote-read export or retained TSDB blocks,
converted by a validated protocol bridge into remote-write batches. Confirm the
Cloud account actually exposes/export-authorizes that API; self-hosted Mimir
support does not establish Cloud entitlement. Remote-read response bytes are not
remote-write request bytes. Reconcile labels and timestamp/value bits, stale NaN
markers, native histograms, exemplars and metadata separately. Verify bridge
support for each before selecting it. Adaptive Metrics may retain aggregated
series rather than discarded raw labels; those cannot be reconstructed by Pulse.

Do not import `query_range` output as raw history. Evaluations can repeat samples
via lookback, resample timestamps, omit stale markers or represent aggregates.
An instant range-vector selector can expose selected raw samples but is bounded
by query limits and does not prove complete discovery, histogram/metadata/export
fidelity. No metrics exporter/converter is provided here until a real source
export format and entitlement are established.

## Reconciliation and cutover gates

Maintain a durable, immutable journal per environment/tenant/signal/window:
source request and hash, export version, rows/series, min/max timestamps,
canonical record multiset digest, batch hash/key, destination version, response,
retries and read-back verdict. Do not put credentials or customer lines in the
journal's public summaries. ACK is publication evidence, not completeness.

1. Confirm required history horizons and actual source retention with the owner.
   Inventory every sender and environment; mark intentional exclusions explicitly.
2. Select a stable boundary before the earliest live destination records; isolate
   any archive/live overlap. Per-series/sender start times differ. Do not assume
   one deployment timestamp is a universal no-overlap watermark.
3. Reconcile exported raw records with destination read-back in small bounded
   windows, including first/last windows, same-timestamp duplicates, empty gaps,
   counter resets and stale samples. Compare log multisets including structured
   metadata, not only counts; compare metrics by complete labels/time/value bits.
   Use the same label projection on both sides and account for source-generated
   labels. Queries that truncate, time out or hit a budget fail reconciliation.
   Measure representative replay throughput, request/storage costs and query
   contention on an isolated S3 prefix before sizing or rate-limiting production
   work. Existing query capacity must leave headroom for live ingestion.
4. Exercise original dashboards, discovery and scheduled alert expressions over
   current, 24h, 7d and the full required horizon. Independently verify freshness,
   collector queue/retry/drop metrics and every sender's sustained overlap. Agree
   explicit zero-loss/value tolerances and latency/availability SLOs in advance.
5. Keep Cloud ingest and historical access until the backfill passes, or until
   the approved warm-up horizon has accumulated and older history is no longer
   needed. Do not conflate query cutover, stopping ingest, deleting history,
   cancelling Cloud, or changing Grafana IRM/notification services.
6. Require separate approvals for production migration, deployments, retention
   enforcement, datasource/alert cutover and Cloud disablement. Preserve a tested
   rollback datasource and routing configuration until the rollback window ends.

## External implementations informing this procedure

- [Loki v3.5.0 LogCLI query batching](https://github.com/grafana/loki/blob/v3.5.0/pkg/logcli/query/query.go)
  deliberately overlaps the boundary timestamp and refuses a batch dominated by
  overlapping entries. This motivates capped-response rejection rather than a
  naive last-timestamp cursor. No Loki implementation code is copied here.
- [Mimir 2.17.0 backfill command](https://github.com/grafana/mimir/blob/mimir-2.17.0/pkg/mimirtool/commands/backfill.go)
  delegates TSDB uploads to its backend-specific client. Its
  [block validation contract](https://grafana.com/docs/mimir/latest/configure/configure-tsdb-block-upload/)
  checks time bounds, retention and block validity. Pulse instead uses its own
  receiver validation and CAS publication; Mimir's uploader is not compatible.
- [VictoriaMetrics v1.122.0 raw remote-read client](https://github.com/VictoriaMetrics/VictoriaMetrics/blob/v1.122.0/app/vmctl/remoteread/remoteread.go)
  distinguishes sample and streamed-chunk modes and uses millisecond bounds.
  This informs raw protocol export, not evaluated query replay. Its destination
  importer is VictoriaMetrics-specific, not a drop-in Pulse uploader.
- [Cloud Logs Export](https://grafana.com/docs/grafana-cloud/send-data/logs/export/)
  exports Loki chunks/indexes, not Parquet; it requires the cell's provider and
  region (S3/Azure/GCS), starts syncing seven days after setup and documents a
  7-to-30-day sync window. It cannot immediately recover yesterday's logs, and
  does not document Tigris as a destination. Enablement is an external change
  requiring approval. Account entitlement, existing configuration and recoverable
  horizon must be verified, not inferred from the product's default retention.
