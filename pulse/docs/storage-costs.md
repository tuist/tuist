# Object storage costs

Pulse does not charge per active series or ingested record. Your object-storage
provider and the machines running Pulse still do. Lossless storage cannot have a
fixed cost for unlimited retained data: compressed bytes grow with data volume,
retention, and entropy. High cardinality can reduce compression and make queries
more expensive, even without a per-series price.

## What to measure

Track these independently, rather than using raw ingest volume as a proxy:

- Retained object bytes, including manifests, superseded objects awaiting cleanup,
  object versions, soft-deleted data, and orphaned uploads.
- Successful PUT and LIST requests, conditional-write conflicts, and retries.
- GET and HEAD requests, conditional-read outcomes, and downloaded bytes.
- Compaction reads, replacement writes, temporary storage overlap, and cleanup.
- Node CPU, memory, query latency, and rejected deliveries. Cheaper storage is not
  a saving if it requires substantially more compute or silently loses data.

[Self-monitoring](self-monitoring.md) reports logical object operations and
successful body bytes, not a billing ledger. Native retries and provider-side
versions need provider usage metering. Do not add the two overlapping Pulse
metrics views together.

## Tigris example

The published [Tigris pricing page](https://www.tigrisdata.com/pricing/) and
[Markdown pricing page](https://www.tigrisdata.com/pricing.md) both list these
Global/Standard marginal rates:

| Driver | Rate |
| --- | --- |
| Retained storage | $0.02 per binary GiB-month |
| Class A: PUT, COPY, POST, LIST | $0.005 per 1,000 requests |
| Class B: GET, HEAD and other reads | $0.0005 per 1,000 requests |
| DELETE, CANCEL | Free |
| Standard retrieval and egress | Free |

Tigris states that 304 Not Modified and 412 Precondition Failed responses are
not charged. Conditional reads still consume network round trips and node time.
Storage billing uses the average daily peak, not cumulative uploaded bytes.
Monthly account allowances are 5 GiB of Standard storage, 10,000 Class A and
100,000 Class B requests. Model marginal costs without those allowances when
comparing scaling behavior.

For Global/Standard, a useful approximation is:

```text
monthly storage bill ≈ 0.02 × average_daily_peak_GiB
                     + 0.000005 × billable_Class_A_requests
                     + 0.0000005 × billable_Class_B_requests
```

Apply the account allowances separately. Add notification charges if configured;
Tigris lists $0.01 per 1,000 events, not per webhook delivery. Confirm current
pricing and your contract before budgeting. The HTML and Markdown pages disagree
about multi-region and dual-region rates; the rates above are not a claim about
those configurations.

At these rates, two PUTs per second cost about $25.92 per 30 days before free
allowances. This can dwarf storage for small batches. A stored GiB held for a
month costs $0.02 regardless of whether it represents logs or metric samples.
Neither figure includes Pulse compute.

[Keyed retries](keyed-ingestion.md) now use conditional creates and streaming GET
verification after a failed create, including lost responses. A normal successful
first create needs no verification GET; retries can add up to two create/verify
rounds, with provider SDK retries additional. All instances contribute pressure.
A size-header mismatch can avoid consuming the streamed body but still incurs a
provider GET and transport traffic. Budget provider operations independently of
node-local consumed-byte counters.

Optional [metric footer-first pruning](metric-footer-pruning.md) can avoid
full-body bytes for proven-empty sources. Matching sources still GET the whole
object and can add one or two suffix GETs; small complete suffixes are reused.
Strong ETags/Range/If-Match support is required. Scan admission charges at least
full logical source sizes, even when downloaded bytes fall, and extra traffic
can hit limits sooner. Discovery remains whole-object. Measure the actual query
mix across all instances, not just native decode savings.

## Cost model

Requests, not bytes, dominate the bill of a busy Pulse deployment on a provider
that charges per request: one Class A request costs as much as storing about
270 KB for a month. Every acknowledged push waits for a Parquet segment PUT and a
conditional PUT of the signal's manifest root, so what matters is how many of
those each push causes.

### Requests

Per instance that receives a signal, with `W` the
[coalescing window](configuration.md#ingest-coalescing) in seconds:

| Request | Window off (`0`) | Window `W` |
| --- | --- | --- |
| Segment PUT | one per push | about `1/W`, more only when a window fills a quarter of its buffer (8 MiB of input terms, 100,000 rows or 512 requests); never more than one per push |
| Manifest root PUT | one per publication; publications run back to back, so at most about one per root write latency (0.3 to 0.6 s on Tigris) | at most `1/W`, shared by every push, keyed or not |
| Manifest page PUT | about one per 450 segments | the same, so about `1/(450 W)` |

Requests with an `Idempotency-Key` always upload their own segment but share
the root writes. Add per tenant:

- maintenance: each compaction merge is one PUT for up to 32 segments, plus the
  manifest pages its leaf rewrite needs. With the window on, merges, cleanup
  batches, rollups and finalizations of paged roots add no root writes of their
  own: they wait for the next ingest publication and share its conditional
  write (an idle prefix publishes them alone after two windows). Without the
  window each is one more root write;
- [metric hour finalization](configuration.md#long-dashboard-and-alert-ranges):
  its metric-grouped segments and rollups per settled hour, and
  [manifest backups](configuration.md#manifest-backups): one PUT per compacted
  prefix per backup interval;
- [alerting](alerting.md#record-a-rule-group): every evaluation pass on every
  evaluating instance LISTs the tenants and each tenant's rules (one Class A
  request each per `PULSE_ALERTING_POLL_INTERVAL_MS`); a recording group tick adds
  at most four Class A requests, a single recording rule five;
- periodic LISTs: tenant discovery at most every 10 minutes per instance, and the
  readiness probe only while the instance makes no other successful request;
- Class B: query segment and page GETs, compaction source GETs, and conditional
  root reads that return a changed root. The [object cache](configuration.md#object-cache)
  serves repeated query reads and maintenance reads of segments the instance
  uploaded itself. `304 Not Modified` and `412` conflicts are free on Tigris.

Every instance that receives a signal runs its own window and publications,
so ingest request cost scales with the number of ingest instances. Conflicting
root writes between instances return free `412`s but are retried with one more
PUT. Run as few ingest instances as availability allows, or route each signal
to its own instances.

Monthly cost then follows directly; on Tigris Standard, with 2,592,000 seconds
in 30 days:

```text
monthly ≈ 12.96 × ClassA_per_second + 1.30 × ClassB_per_second
        + 0.02 × average stored GiB (live data + soft-deleted data)
```

Watch the actual rates with `pulse_object_requests_total{class,purpose}` and
storage with `pulse_manifest_referenced_bytes{signal,age}` (see
[self-monitoring](self-monitoring.md)). For example:

```promql
# Projected monthly request cost in USD at Tigris Standard rates
12.96 * sum(rate(pulse_object_requests_total{class="A"}[1h]))
  + 1.30 * sum(rate(pulse_object_requests_total{class="B"}[1h]))
```

The counters see one logical request per call: native client retries and
additional LIST pages are not counted, so compare against the provider's usage
report.

### Storage

Stored bytes are the compressed bytes ingested per second times the retention
period, plus what soft delete keeps:

```text
stored GiB ≈ Σ signal (segment_bytes_per_second × retention_seconds) / 2^30
           + (deleted_bytes_per_second + overwritten_bytes_per_second) × soft_delete_seconds / 2^30
```

Without [retention](retention.md) the first term grows every month for as long
as the bucket exists. Compaction rewrites data once and deletes the sources
after its grace period, and each root write replaces the previous root. With a
soft-delete window (7 days, for example), those deleted sources and superseded
roots stay billable for the window. Coalescing shrinks the second term: fewer
root writes overwrite fewer root bytes.

### Storage tiers

Tigris lifecycle rules can move objects to Infrequent Access ($0.01/GiB-month,
$0.01/GiB retrieval, 30-day minimum) or Archive Instant Retrieval ($0.004,
$0.03/GiB retrieval, 90-day minimum) by object age and key prefix. Pulse reads
any tier transparently, except Archive, which needs a restore first and is not
supported. Only segments are good candidates: limit rules to the prefix
`tenants/<tenant>/v4/signal=<signal>/date=`, which excludes manifest roots,
pages and backups that Pulse rewrites or reads constantly.

Transition only data you keep well past the minimum. An object deleted by
retention earlier than 30 days after its transition is still charged the full
30 days: moving segments at 30 days saves money only with more than 45 days of
retention, and every query over old data pays the retrieval fee on whole
segments. At $0.01/GiB-month saved, tiering is worth it only for large,
rarely-read history; requests usually matter more.

### Retention

At 1.3 TB of new segments per month (the production-shaped load test below:
metrics 1.04 TB, logs 0.22 TB, traces 0.08 TB), retain-forever storage adds
about $25/month to the bill every month: $300/month after a year. Choose
retention per signal from how far back people query, for example 30 days of
logs, 14 days of traces and 90 days of metrics (hourly rollups make long metric
ranges cheap to read), which caps storage near 3.4 TB ≈ $63/month at that
volume; metrics dominate, so their retention is the lever.

Enforced retention keeps the paged (format 4) manifest, so
[manifest backups](configuration.md#manifest-backups) and hour finalization
keep working on object stores without versioning, such as Tigris. Expired
segments are deleted after the grace period and a backup that records their
retirement; with 7-day soft delete they stay billable for 7 more days, about
a week of new data (≈ 0.3 TB, $6/month at that volume).

Trace compaction (on by default) merges each hour's flushes into objects of one
service, error/event class and bounded trace IDs, and uses the same manifest
backups and held cleanup as logs and metrics, so it is safe on Tigris without
bucket versioning. Its requests follow the flush rate, not span volume: with
2 s flushes, the production load script (1,000 spans/s) measured about 0.4
extra Class A and 2.9 extra Class B requests per second, about $5 and $4 a
month. In exchange, hour-long trace searches read a few objects instead of
thousands.

### Production settings for Tigris

```yaml
ingestBatching:
  flushIntervalMs: 2000        # 4000 saves ~$15/month; see "Longer ingest windows"
  maxConcurrentRequests: 256   # the derived 28 slots return 429s at 70 pushes/s
  maxPendingBytes: 67108864    # 167772160 with a 4000 ms window
metricsCompaction:
  enabled: true
  finalize: true
logCompaction:
  enabled: true
traceCompaction:
  enabled: true
manifestBackups:
  enabled: true
objectCache:
  memoryMb: 64
  disk:
    enabled: true
    sizeMb: 8192               # about two hours of segments at production volume
retention:
  mode: enforce                # after every node runs 1.32 or later
  manifestFormat: paged
  logsDays: 30
  tracesDays: 14
  metricsDays: 90
```

On a 2 GiB node, size query budgets for 1-hour dashboards over hundreds of
thousands of series (`rate(m[5m])` over an hour selects about 130 samples per
series; 1,000 series exceed the 100,000-sample default):

```yaml
resources:
  limits:
    memory: 2Gi
extraEnv:
  - {name: PULSE_QUERY_MAX_CONCURRENT, value: "3"}       # plus 2 background workers: 5 heaps of 160 MiB
  - {name: PULSE_QUERY_QUEUE_MS, value: "5000"}          # dashboards send panels at once; wait, do not 429
  - {name: PULSE_QUERY_MAX_HEAP_MB, value: "160"}
  - {name: PULSE_QUERY_MAX_SAMPLES, value: "300000"}     # about 450 B of heap each
  - {name: PULSE_QUERY_MAX_SCAN_BYTES, value: "268435456"}
  - {name: PULSE_QUERY_TIMEOUT_MS, value: "15000"}
```

Five full query heaps (800 MiB) plus the ~660 MiB peak the load test measured
stay below the 85% memory-pressure threshold of 2 GiB. Raise
`PULSE_QUERY_MAX_CONCURRENT` only with memory.

### Measured at production volume

A production-shaped load test (`scripts/production_load.exs`) sent 400,000
active series scraped every 30 s in 20 remote writes/s, 3,400 log lines/s in 40
Loki pushes/s, 1,000 spans/s in 10 OTLP exports/s, and dashboard queries every
30 s, to one Pulse node with 2 vCPU and a 2 GiB budget, against an object store
with Tigris latency (GET 140–190 ms, PUT 220–350 ms):

| | 1.29.9, window off (10 min) | Window 2 s (10 min) | Window 2 s, metrics compaction and finalization (75 min) |
| --- | --- | --- | --- |
| Pushes acknowledged (70/s offered) | 50/s; 102,000 `429` responses, 12,000 pushes dropped after retries | 70/s; no `429`, none dropped | 70/s; no `429`, none dropped |
| Acknowledgment p50 / p99 | 3.7–5.9 s / 5.4–14.4 s | 1.9–2.9 s / 3.2–4.5 s | 1.9–2.8 s / 3.1–4.8 s |
| Class A requests/s | 58 (1.17 per push) | 3.2 (0.05 per push) | 3.6 (0.05 per push) |
| Class A per month | $756 | $42 | $47 |
| Class B per month | $5 | $22 | $7 |
| Segment objects written per hour | 182,000 | 5,700 | 6,300 |
| Root bytes overwritten | 536 KB/s (7-day soft delete: $6/month) | 95 KB/s ($1/month) | 127 KB/s plus 89 KB/s of deleted compaction sources ($2/month) |
| Memory (RSS p50 / max) | 388 MiB max | 501 MiB max | 468 MiB / 1,011 MiB |
| Dashboard queries | all failed: thousands of segments per hour exceed the query segment budget | most answered; one-hour log volume, PromQL rate and Tempo search panels often hit query limits (`422`) | same |

With the window off, every push encoded and published its own segment, which
saturated both cores. The window turns per-push work into per-window work, so
the same node kept up with production volume. Live metric bytes grew faster
in the compaction run (725 KB/s against 401 KB/s), because compaction sources
stay referenced for the one-hour grace period and finalized hours add rollups.
A 75-minute run does not separate those two effects, so treat 2 TB/month as an
upper bound on storage growth and watch `pulse_manifest_referenced_bytes` in
production.

1.33 groups the current hour's settled metric batches by name, writes log
minute rollups and queues queries for a slot. With the settings above, a
60-minute run (crossing an hour boundary) answered every one-hour dashboard
panel (out of 120 each):

| Panel | 1.31.0 (20 min) | 1.33 (60 min) |
| --- | --- | --- |
| `sum by (job) (rate(m[5m]))`, 1 h at 60 s | 10/40, p50 2.3 s (`max_scan_bytes`) | 120/120, p50 2.2 s, p99 10.5 s |
| `topk(10, sum by (instance) (rate(m[5m])))` | 33/40, p50 2.7 s | 120/120, p50 1.1 s, p99 3.7 s |
| `count(m)` | 33/40, p50 2.7 s | 120/120, p50 0.9 s, p99 2.1 s |
| `sum by (detected_level) (count_over_time(...[1m]))`, 1 h | 8/40, p50 2.8 s (`max_scan_rows`) | 120/120, p50 1.6 s, p99 2.8 s |
| `{service_name=...} \|= "level=error"`, 15 min | 40/40, p50 0.2 s | 120/120, p50 0.2 s |

Ingest stayed fully acknowledged (p99 2.8–4.4 s), RSS p50 496 MiB and max 660
MiB, at 4.3 Class A requests/s.

1.36 adds the node-local [object cache](configuration.md#object-cache) and folds
maintenance root writes into ingest publications. Two 75-minute runs with the
settings above, retention enforced, and the second with an 8 GiB disk tier
(`objectCache.disk.enabled: true`):

| | 1.34.0 | 1.36, disk cache 8 GiB |
| --- | --- | --- |
| Class A requests/s | 4.34 ($56/month) | 3.96 ($51/month) |
| Root writes/s | 1.66 | 1.47 |
| LIST/s | 0.19 | 0.01 |
| Class B requests/s | 10.7 ($14/month) | 0.64 ($1/month) |
| Segment GETs/s | 9.9 | 0 (every read a memory or disk hit) |
| `sum by (job) (rate(m[5m]))` p50 / p99 | 5.0 s / 12.7 s | 5.9 s / 14.6 s |
| `topk(10, ...)` p50 / p99 | 2.2 s / 6.6 s | 1.7 s / 4.9 s |
| `count(m)` p50 / p99 | 1.9 s / 6.8 s | 1.6 s / 5.1 s |
| Log volume by level p50 / p99 | 2.7 s / 5.1 s | 1.5 s / 3.4 s |
| Error lines, 15 min, p50 | 0.25 s | 0.10 s |
| Tempo search p50 / p99 | 2.2 s / 10.5 s | 4.8 s / 12.1 s |
| RSS p50 / max | 561 / 718 MiB | 668 / 884 MiB |

Ingest stayed fully acknowledged in both runs. The disk tier held 3.6 GiB after
an hour: about one hour of this node's segments. Both runs saturate two vCPU;
the two slower panels are CPU-bound, and without GET waits compaction got
through more work in the same time (0.21 against 0.16 merge PUTs/s), which
likely took CPU from them. More CPU, not a larger cache, is the lever there.

### Longer ingest windows

With the object cache, writes dominate the request bill, and the window sets
the write rate. The same 75-minute load on 1.36, disk cache on, trace
compaction off, at three windows:

| | 2 s | 4 s, pending 64 MiB | 4 s, pending 160 MiB | 5 s, pending 160 MiB |
| --- | --- | --- | --- | --- |
| Class A requests/s | 3.96 ($51/month) | 2.72 ($35/month) | 2.76 ($36/month) | 3.28 ($42/month) |
| Root writes/s | 1.47 | 0.74 | 0.74 | 0.60 |
| Ingest segment PUTs/s | 1.52 | 1.08 | 1.06 | 1.81 |
| Retryable `429`s (75 min) | 0 | 6,300 | 0 | 0 |
| Acknowledgment p99, worst signal | 4.8 s | 7.8 s | 7.6 s | 9.9 s |
| Slowest acknowledgment | 6.2 s | 10.6 s | 10.2 s | 11.7 s |
| Log volume by level p50 | 1.5 s (150/150) | 1.5 s (150/150) | 1.5 s (150/150) | 1.8 s (119/150, `max_scan_rows`) |
| Tempo search p50 (failures) | 4.8 s (9) | 7.2 s (16) | 7.6 s (10) | 5.1 s (34) |
| RSS p50 / max | 668 / 884 MiB | 748 / 959 MiB | 736 / 941 MiB | 837 / 1,068 MiB |

The two 4 s runs differ in admission: 256 slots and the default 64 MiB
pending budget, against 512 slots and 160 MiB
(`ingestBatching.maxConcurrentRequests`, `ingestBatching.maxPendingBytes`).
Requests wait longer for publication; once the 64 MiB budget was full they
kept their slots, filled all 256 and drew `429`s. With 160 MiB at most 71
slots were in use, which points to the pending budget. 5 s buys fewer root writes but more segment PUTs, so
Class A rises again, and its slowest acknowledgments exceed the 10 s default
timeout of OTLP exporters.

Use 4 s with a 160 MiB pending budget when a few seconds of extra ingest
delay are acceptable: it saves about $15 a month per ingest node at this
volume. Data then becomes queryable, and alert rules see it, about 2 s
later; raise OTLP exporter timeouts to 30 s. During an incident, a shorter
window needs a rollout, so keep 2 s if fresh data matters more than cost.

### Parsed-field log alerts

Alerts and panels that parse lines (`| logfmt | kind="measurement" | ...`)
over hours of one service used to fail: every log segment holds a slice of
time of every stream, and `PULSE_QUERY_MAX_SCAN_ROWS` was charged with every
stored line of every segment read. 1.37 charges only the lines the stream
selector and leading line filters select, and
[stream-grouped log segments](configuration.md#stream-grouped-log-segments)
let a service selector skip other services' segments once an hour is settled.
The table below replays Tuist's web-vitals alerts (logfmt over
`{service_name="tuist-web"}`, 2 of about 52 lines/s) and docker cache-usage
panels against a Tigris-latency store (140–190 ms per GET), 24 hours at canary
volume (4.5 million lines), cold reads:

| Query | 1.34 | 1.37, before hours are grouped | 1.37, grouped |
| --- | --- | --- | --- |
| 24 h web-vitals alerts (11) | `422 max_scan_rows` | 2.3–4.8 s, 48 GETs, 91 MB | 1.4–2.7 s, 24 GETs, 4 MB |
| 6 h web-vitals alerts (9) | `422 max_scan_rows` | 0.8–0.9 s, 12 GETs, 23 MB | 0.6 s, 6 GETs, 1 MB |
| Cache-usage panels, 1 h | 0.6 s, 2 GETs | 0.6 s, 2 GETs | 0.5 s, 1 GET |
| Cache-usage panels, 6 h / 24 h | `422 max_scan_rows` | 1.7–2.1 s / 6.4–7.1 s | 1.5–1.9 s / 5.8–8.1 s |

The cache-usage panels select every line of the docker streams (about 12
lines/s) with a line filter and the `pattern` parser, which runs in Elixir, so
their 24 h range stays close to the 10 s query timeout.

Grouping an hour reads it once and rewrites it once: 24 canary hours took 48
GETs and 183 PUTs (about 8 Class A requests an hour). At 53 times that
volume an hour of 9.9 million lines took 36 s, 230 GETs and 154 PUTs: about
$0.60 a month of Class A and $0.10 of Class B requests. The rewritten
originals are deleted after the compaction grace, so storage does not grow.

Grouping does not change how many lines such a query must read. At 53 times
canary volume one hour of the web-vitals service is 381,000 lines (8 MB),
read natively in about 2.5 s: a 6 h alert selects 2.3 million lines and a
24 h alert 9.2 million, beyond the default row budget and the 10 s query
timeout. Windows that long at that volume need precomputed results, such as
metrics recorded from the logs, not a larger budget.

### What metrics compaction and finalization cost

`test/pulse/promql/tuist_history_bench_test.exs` counts the requests the
maintenance worker makes per hour over a remote-write history, one segment per
2-second batch (about 3,640 Class A requests an hour for ingest either way):

| Metrics volume | Maintenance Class A per hour | Class B per hour | Per month |
| --- | ---: | ---: | ---: |
| 150,000 series every 60 s (about 5,000 samples per batch) | 1,300 | 2,800 | $4.70 + $1.00 |
| 400,000 series every 30 s (about 26,000 samples per batch) | 3,800–4,400 | 4,500–6,000 | $14–16 + $1.60–2.20 |

The second volume was measured over less than two hours, hence the ranges.
These counts predate the [object cache](configuration.md#object-cache): with
it, maintenance reads of recently written segments are cache hits rather than
Class B requests.
Queries pay it back in Class B: a 1-hour panel that read 65 to 1,690 segments
without compaction reads 14 to 28 with it.

## Avoiding amplification

By default Pulse writes one immutable Parquet segment per nonempty append and
acknowledges only after publishing it in the manifest. Concurrent manifest
registrations can share a conditional write. [Ingest coalescing](configuration.md#ingest-coalescing)
lets unkeyed requests share the segment PUT within bounded node-local buffers
and spaces root writes one window apart. It is disabled by default; keyed
requests and buffer overflow upload their own segment. Batch at the collector
within Pulse's [ingest limits](ingest-limits.md), and measure delivery latency
and memory as well as requests. A larger batch or coalescing window is not
permission to acknowledge before durable publication.

Use bounded time ranges and exact metric-name, metric-label, or log service selectors.
New metric segments retain complete value sets for a few low-cardinality labels;
exact mismatches skip downloads. High-cardinality, unknown, and over-budget sets
still scan, including older segments. Compaction rebuilds these summaries without
aggregation or data loss. New log
segments with a complete small set of nonempty promoted services can be skipped
before download for exact `service`/`service_name` selectors. Old segments, large
service sets, and records needing resource-label fallback are still scanned.
These optimizations do not drop data or change query results. Other log labels,
regular expressions, and line filters still require segment reads.

[Metrics compaction](configuration.md#metrics-compaction) reduces small-object
query fan-out but adds reads, writes, and a grace-period storage overlap. It does
not reduce initial ingest PUTs. Test total lifecycle costs against the query mix
before enabling it. Manifests and permanent ingest-retry tombstones still grow;
compaction is not a bound on lifetime metadata.

Experimental [event-time retention](retention.md) is implemented for logs,
metrics and traces. Managed scopes add immutable metadata pages, cleanup requests
and a grace-period storage overlap; measure the full lifecycle, not just ingest
PUTs. Flat retain-forever catalogs and their tombstones still grow without bound.
Do not apply bucket lifecycle
deletion to referenced segments or pages: it leaves dangling manifest references.
Recovery requires coherent manifest, metadata-page and segment backups.
Infrequent Access adds retrieval charges and a 30-day minimum; Archive Instant
Retrieval adds retrieval charges and a 90-day minimum. Archive requires a restore
before reading. Tiering mutable manifests or short-lived compaction sources can
cost more than Standard, and automatic archive restoration is not supported.

## Correctness before cost

Do not remove labels and assume collisions will be aggregated elsewhere. Pulse
preserves supplied samples, including duplicates; conflicting metric values at
the same timestamp are resolved deterministically at query time with a warning,
not summed during ingest. It does not implement adaptive aggregation, log
sampling, or trace ingestion. Source-side sampling is an explicit data-loss
policy, not a storage optimization.

Rejected requests still consume network and compute, and some providers charge
for them. Monitor rejection rates separately from acknowledged deliveries and
check the provider's actual response-code billing rules.
