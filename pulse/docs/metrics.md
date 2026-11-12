# OpenTelemetry metrics

`POST /v1/metrics` accepts OTLP/HTTP JSON and protobuf, optionally gzip-compressed.
It uses the same tenant bearer token and `X-Scope-OrgID` header as other receivers.
The opt-in [OTLP/gRPC receiver](otlp-grpc.md) accepts the same metrics over gRPC. The receiver supports scalar points, cumulative explicit histograms
and summaries under bounded conversion. It is not yet full OpenTelemetry metric
or Prometheus OTLP translation compatibility; see [protocol coverage](protocol-coverage.md).

## Supported data

| Kind | Behavior |
| --- | --- |
| Gauge | Accepts signed int64 and IEEE double points |
| Cumulative sum, monotonic or non-monotonic | Accepts scalar points; monotonic sums become counter-named series |
| Delta sum, monotonic or non-monotonic | Stores each point's value as reported for its interval, without accumulation; monotonic deltas are **not** given the `_total` counter name. Query with `sum_over_time` (see [delta temporality](#delta-temporality)) |
| Unspecified sum temporality | Rejects each supplied point |
| Cumulative or delta explicit histogram | Retains the complete source point; projects cumulative classic `_bucket`, `_count` and optional `_sum` samples |
| Summary | Retains the complete source point; projects quantile, `_count` and `_sum` samples |
| Cumulative or delta exponential histogram | Retains the complete source point; projects classic cumulative `_bucket` (`le`), `_count` and optional `_sum` samples (see [exponential histograms](#exponential-histograms)) |
| Unspecified histogram temporality | Rejects each supplied point |
| Exemplars on supported scalar and histogram points | Retains typed values, source time, filtered attributes and trace/span IDs in the point's `otlp` metadata, and stores each as a Prometheus exemplar (`trace_id`, `span_id` and filtered attributes as labels) on the sample, or for histograms on the `_bucket` series whose bound holds its value, queryable through `/api/v1/query_exemplars`. Label sets over Prometheus' 128-character limit stay in the metadata only |

A point requires a nonzero source `timeUnixNano` in the signed int64 timestamp
range. There is no receive-time fallback. `startTimeUnixNano` defaults to zero
and cannot exceed the point time. Monotonic sums reject negative values. The
no-recorded-value flag publishes a stale marker, retaining any supplied source
value in metadata. NaN and infinities remain distinct from stale markers.
Exemplar context IDs remain source metadata, not a guarantee of valid span
association. Zero IDs from always-on exporters outside spans are retained and do
not discard the scalar.
Scalar int64 values convert to the float sample model used by PromQL, so values
above its exact integer range may round; their original decimal int64 remains
exact in the typed envelope.

Resource/scope attributes, schema URLs, descriptor name/description/unit/metadata,
point attributes, source times, temporality, monotonicity, flags and exemplars are
stored in the nullable `otlp` envelope. Types, attribute order and signed zero are
preserved. `query_metrics` returns this envelope; legacy remote-write samples
have `otlp: null`. Both `deployment.environment` and
`deployment.environment.name` remain untouched in resource metadata.

## Histograms and summaries

An explicit histogram's bucket counts are **non-cumulative within the source
point**. Pulse prefix-sums them into classic Prometheus `_bucket{le="..."}`
samples, adds `_count`, and emits `_sum` only when the optional source sum is
present. Missing sum, present zero and negative zero stay distinct. Optional
`min` and `max` remain metadata, not invented sample families. Even with omitted
bucket arrays, the total count proves one universal `le="+Inf"` sample; no finite
buckets are inferred. Bounds must strictly increase, counts must match their
shape and total, and every count must fit uint64. An explicit final `+Inf` is
coalesced with the universal bucket only if its following bucket is empty
(or values are ignored on a staleness marker); contradictory duplicate identities
reject an ordinary point. Leading `-Inf` is retained.
NaN bounds and duplicate bounds, including adjacent -0/+0, reject the point.

A summary emits the original metric name with a `quantile` label, plus `_count`
and `_sum`. Quantiles are ordered distinct fractions in [0,1], not recomputed
from buckets. Ordinary values are nonnegative or NaN; negative values reject the point.
Summary quantiles describe the producer's window and must **not** be added or
averaged across producers. Summary count/sum retain their cumulative semantics.
For ordinary points, a zero count requires a zero sum when present. Non-finite sums/values preserve
their IEEE classes; a negative histogram sum does not become a monotonic counter.

The original count and bucket counts remain **exact decimal uint64 strings**,
including values above signed int64. Float projections can round above 2^53.
Bounds and quantile labels use fixed-decimal shortest-roundtrip Go spelling
(`1`, `0.5`, `-0`, `+Inf`), pinned against actual Go output. They are series
identities, not display formatting. The no-recorded-value flag makes each
available projected component stale while retaining its source fields. Value
consistency checks (bucket totals, zero-count sum, nonnegative summary values)
are ignored for these markers, so a placeholder NaN sum does not leave old data
visible. Typed field ranges, cumulative temporality, bucket/bound shape and
label-defining bounds/quantile ordering still validate. Exemplars stay in the source envelope
and are also stored as Prometheus exemplars (see [querying](querying.md#datasource-metadata)).

Each projected row carries the **entire** normalized point and an `otlp.projection`
descriptor (`component` and, when relevant, `le`/`quantile`). `query_metrics` can
recover bucket counts, optional fields and quantiles without inferring originals
from float samples. Parquet and compaction preserve this metadata. This repeats
source bytes per component: large single distributions can exceed the 16 MiB
metadata ceiling even when they fit source-point and expanded-sample limits.
For example 1,800 finite bounds with zero counts and otherwise sparse metadata
already exceed it; there is no universal safe bucket count because attribute
bytes, numeric spellings and optional fields also contribute. Source semantic
validation is stricter than translators that tolerate malformed bucket shapes or
inconsistent totals; successful Prometheus ingestion alone does not prove a
point meets the OTLP contract. Min/max are retained, not cross-checked against
observations or bounds.
There is no point-reference store or separate mutable distribution authority.

## Series identity and naming

The queryable Prometheus label projection is intentionally narrower than the
source envelope:

- Metric names replace non-ASCII Prometheus-name characters with `_`; leading
  digits gain `_`. Monotonic sums gain `_total` unless already suffixed.
- Point attribute keys are normalized to ASCII label names. Scalar strings stay
  strings; other projected values use JSON spelling.
- Resource `service.namespace` and `service.name` become `job` (namespace/name,
  or just name). `service.instance.id` becomes `instance`.
- Scope name/version become `otel_scope_name` / `otel_scope_version`.
- Normalized point-key collisions or conflicting promoted labels reject the
  point rather than overwrite it. A point attribute named `__name__` is invalid.
- Histogram point labels must not define `le`; summary point labels must not
  define `quantile`, even when a particular point omits finite buckets/quantiles.
- Within one request, a projected distribution family must not alias a different
  original instrument, unit or typed resource/scope/point owner. Conflicting
  complete distribution envelopes at the same projected identity/time also
  reject the **whole request** with 400; identical copies are allowed. This is
  bounded request validation, not a cross-request schema registry.

**Ensure every independent metric stream has distinct labels.** In particular,
set a stable, unique `service.instance.id` per independently accumulating
producer, or supply equivalent distinguishing point labels. Two pods with the
same service and no unique labels otherwise interleave cumulative counters;
`rate()` cannot repair that ambiguity. Other resource attributes (including
environment and Kubernetes metadata) are retained, but are **not automatically
promoted to labels**. Isolate environments by tenant or explicit point labels.
Pulse does not establish producer uniqueness or resolve overlapping output
ownership for you.

Unit suffix translation, target-info synthesis and **cross-request** collision
detection are not implemented. Scalar-only instrument collisions retain their
existing behavior. For example a monotonic `requests` and a gauge
`requests_total` have the same projected name. Check actual name/label contracts
before switching an existing dashboard. Keep a remote-write pipeline when its
Collector translation is required; direct OTLP ingestion does not promise the
same names as Prometheus's OTLP receiver.

## Manifest segment pruning

Before any object is downloaded, each metric segment's manifest entry can carry
complete value sets for its metric names (up to 128) and for up to 16 other
labels (up to 32 values each, `""` for samples that lack the label). Labels are
chosen across every sample in the segment, fewest distinct values first, so
mixed remote-write batches keep selective labels such as `job`, `namespace` or
`env`. A segment is skipped only when one of these complete sets proves that a
selector matcher cannot match:

- `=` and `!=`.
- `=~` and `!~` with literal values, alternations of literals (`a|b|c`,
  `(a|b)`, `(?:a|b)`) and empty alternatives, such as Grafana variable
  expansions. Matching is fully anchored as in Prometheus, so `=~"api"` does not
  match `api-1`.
- Literal prefixes. `=~"tuist-macos-.*"` is decided exactly. For other suffixes,
  such as `=~"kura-(.*)-.*"`, the literal prefix still excludes segments with no
  value starting with `kura-`.
- `=~".*"` adds no constraint. `!~".*"` matches nothing.
- `__name__` regex and prefix matchers, such as `{__name__=~"prefix_.*"}`.

Matchers on the same label must accept the **same value**. For example,
`queue=~"process_build|default",queue!="default"` skips a segment whose complete
queue set is only `""` and `"default"`, before byte admission or object GETs.
Different labels are still independent: their value sets cannot prove that
values belong to the same sample. Unknown summaries or unrecognized regex
shapes never supply exclusion evidence. This changes query planning only;
stored summaries, safety limits and charging for retained sources are unchanged.

A remote-write batch often holds more than 128 metric names. Its entry then
carries a bloom filter of up to 2,048 names instead (16 bits per name, at most
1 KiB, so no larger than the list it replaces). The filter decides `__name__`
equality and literal alternations only: a segment is skipped when none of the
accepted names can be present. False positives (under 0.1%, about 2% at the
1 KiB cap) only add reads. Because a batch holds the targets scraped around its
send time, a selector of a metric exposed by few targets reads only the batches
around those scrapes, not every batch of the window. Segments written before
this filter existed have no filter and are scanned for name matchers.

The exact-name dictionary has a separate 64 KiB manifest budget. When a complete
set of at most 128 names cannot fit, new manifest writes retain the same bounded
bloom representation instead of discarding name pruning (64–256 bytes before
base64 per affected segment). This adds hashing work and per-segment manifest
metadata, without increasing the dictionary or query scan limits. Existing
entries whose names were already omitted remain unknown until rewritten from
complete summaries, for example by compaction; readers cannot reconstruct them.
Older readers already understand this bloom field, and older writers may drop
it without changing stored samples.

Flags such as `(?i)`, `\Q...\E`, and patterns with no literal prefix (such as
`.+suffix`) never prune. Segments without summaries (older writers, high
cardinality, long values) are always scanned. Every selector still filters
rows after download. Pruning only avoids reading segments that cannot match.
The segments that remain count against the per-query budget of 1,024 segments.

## Bounded PromQL aggregation

Aggregates over a selector or supported range function fold one series at a
time into per-group, per-step state. The same path handles a direct selector
compared with a literal scalar on either side, using `==`, `!=`, `<`, `>`, `<=`
or `>=`, with or without `bool`. This includes the Pulse page's health widgets
`sum(up == bool 1)` / `sum(up == bool 0)` and Grafana filtered counts such as
`count(up{job="tuist-macos-tart-kubelet"} == 1)`.

Comparisons reuse normal scalar/vector semantics: filters retain sample values
and metric names; `bool` returns zero/one and drops the metric name. Invalid
histogram comparisons retain their notices and do not become zero-valued
samples. Potential output-label collisions use the materialized path so
duplicate-label errors cannot disappear inside an aggregate.

This avoids retaining a full series-by-step comparison matrix. It does not
stream samples out of storage, save object GETs or bytes, change scan/sample/
work/deadline/result limits, or remove the heap ceiling. Per-series comparison
work remains charged and can be higher than evaluating one shared scalar
vector. More complex arithmetic, vector joins and nonliteral scalar expressions
are unchanged; this is not a general expression-fusion or capacity guarantee.

## Bounded native query acceleration

New **unkeyed** metric segments and fresh compaction outputs can contain an
optional label-to-series postings index inside the Parquet footer. Exact
positive label equalities intersect complete canonical series identities before
Arrow decoding, then select only potentially relevant row groups. For example,
`host="a",environment="production"` can prove an empty intersection even when
both individual values exist on different series. Missing labels match `""`,
just as in Prometheus; hash collisions never merge series identities. Regex and
negative matchers still filter surviving rows normally.

This is automatic and bounded, not a new service or operator-tuned index:

- At most 512 distinct canonical series, 100,000 source rows and 128 row groups
  per indexed segment. Exceeding a bound omits the index, not the data.
- Try `__name__` first, then byte-ordered names, examining at most 16 names of
  at most 256 bytes. A selected label's complete value partition, including
  missing/empty values, must fit; values over 256 bytes or exhausted space omit
  that label, never truncate its values. Later names beyond those 16 are unknown.
- The complete footer value is at most 64 KiB (hex encoding of at most 32 KiB).
  Optional construction caps unique canonical bytes at 128 KiB, each canonical
  set at 4 KiB, and label-byte dictionary probes at 16 MiB. Consecutive shared
  label buffers avoid repeated byte probes; fixed per-row work remains bounded.
  These are index bounds, not new ingestion limits or total native-memory caps.

**By default this saves native decode work, not provider reads.** Metric queries GET
whole objects. Optional [footer-first pruning](metric-footer-pruning.md) can avoid
the body GET for proven-empty sources; other candidates still need whole objects. Provider bytes, manifest admission and source row budgets do not
shrink, even for an index-proven empty result. Footer bytes add download and
metadata-parsing overhead, including on queries without exact equalities.
High-cardinality segments frequently omit some or all postings. No representative
cold-cache, broad-history or multi-instance capacity claim follows from this
optimization; external posting sidecars and selected-column/row-group range reads remain unimplemented.

Absent, unrecognized, duplicate or malformed index metadata falls back to scanning.
Readers check checksum, complete disjoint value partitions and actual row-group
geometry. As with Parquet statistics, semantic coverage derives from the trusted
writer; the noncryptographic checksum detects accidental corruption, not forged
metadata. Filtering is **not an integrity scrub**: groups excluded by postings or
time statistics do not have their columns decoded and validated.

The index has the same immutable object and manifest publication/retirement as
its samples, with no separate upload, cleanup or mutable authority. Keyed appends
retain their pre-index encoder bytes so retries do not overwrite an acknowledged
object with a differently sized footer under the same deterministic key. Such
objects can acquire postings only through compaction under a fresh key. This
protects **this footer change**, not arbitrary later encoder/dependency upgrades:
keyed uploads now use conditional creation and exact-byte streaming verification.
Different bytes fail permanently with HTTP409, even if logically equivalent.
Keep byte-compatible keyed writers and review Parquet/compression changes;
automatic semantic cross-encoder recovery remains unimplemented. See
[keyed ingestion](keyed-ingestion.md). Existing
and older-compatible readers can ignore the footer; index-free writers only lose
acceleration. This release's local native startup check requires metric API tuple
`{2,2,1,1,1,1}` (metadata/start timestamps, OTLP, postings, discovery, footer planning, streaming reads). That check does not fence other serving nodes;
the separate all-participant rich-metadata upgrade requirements below still apply.

### Bounded metric decoding

PromQL's ordinary S3 selector scans fold at most 4,096 input rows per native
decode call instead of materializing a whole compacted object as records.
This reduces transient query-heap pressure without increasing any sample,
work, scan, result, heap or deadline limit. Matching samples remain charged
across chunks and selectors; exhausting a budget fails the whole query.
Time/postings pruning, stored samples and keyed encoder bytes are unchanged.
Arrow buffers and retained series still consume memory, so bounded decoding
does not guarantee that every admitted query fits its heap.

Streaming reads require metric reader capability 1 in each serving app/native
pair. Rebuild or install matching artifacts before starting the application.
This addition alone has no stored-format migration; earlier source-start and
keyed-publication upgrade requirements still apply. The optional single-selector
footer-first path and rollup decoding are not changed by this streaming path.

## Discover labels and series

`discover_metrics` and the Prometheus-compatible `/api/v1/labels`,
`/api/v1/label/<name>/values` and `/api/v1/series` routes return bounded complete
retained-sample dictionaries. Empty-valued labels project as absent; raw records
remain unchanged. See [metric discovery](metric-discovery.md) for selector OR,
time bounds, form POSTs, resource limits, errors and TSDB differences. With
metrics compaction enabled, discovery reads hourly series catalogs, so its cost
grows with series rather than samples; data newer than about one compaction
interval is read from samples.

## Exponential histograms

Exponential histogram points are expanded into classic cumulative buckets so
`histogram_quantile` and existing dashboards work unchanged. Bucket boundaries
follow the point's base-2 exponential layout: negative buckets, then the zero
bucket (whose `le` is the zero threshold), then positive buckets and `+Inf`.
Points with a finer scale than 3 (about 9% bucket width) are merged down to
scale 3, and further when they would still produce more than 160 buckets, so
series usually share boundaries and `sum by (le)` works. Series whose scales
differ after this still produce valid but differently spaced buckets; aggregate
such series with care. Quantiles interpolate within a bucket as for any classic
histogram. The original scale, zero bucket and bucket arrays are kept in the
point's `otlp` metadata. Empty buckets are not projected.

Supported source scales are -10 through 20. Conversion admits at most 65,536
supplied counts per positive/negative side and at most 160 populated bins after
coarsening. If the latter cannot fit at scale -10, or a side exceeds its conversion
ceiling, the request fails whole with 413, including any otherwise valid neighbors.
The independent supplied-point, expanded-sample, request-node and fixed 16 MiB
repeated-metadata ceilings still apply. There is no limit increase.

Finite boundaries between `2^1023` and `2^1024` remain finite. Subnormal/zero
boundaries that round to the same float coalesce **at that boundary**, with the
complete cumulative count; negative infinite bounds remain `le="-Inf"`.
Projected zero uses `le="0"`, while the original threshold's signed-zero bits
remain in metadata. A populated ordinary bucket wholly inside the closed zero
region is contradictory and rejects the source point (a keyed batch fails whole).
Partial negative overlap clips to the negative zero threshold; stale markers still
ignore numerical population relationships while retaining their supplied source.

Classic projection is an approximation, not a lossless native histogram: negative
OTLP buckets have exclusive upper endpoints whereas classic `le` is inclusive,
and a nonzero zero region has unknown internal distribution. Rounded subnormal
bounds and per-point coarsening also reduce geometry. The retained source is the
faithful view. Pulse uses the mathematical exponential overflow boundary, not
Prometheus native histograms' special maximum-finite sentinel.

**Upgrade:** upgrade every serving ingress application, HTTP and gRPC, together
and drain affected keyed retries beforehand. This correction changes projected
labels/counts for extreme, rounded and zero-overlap cases; previously acknowledged
keys can therefore return permanent `409 keyed_content_mismatch`. Do not delete,
overwrite, change keys or resend unkeyed/subsets to bypass this. Historical
projections are not repaired automatically. Parquet/envelope formats, shared wire
capability 3 are unchanged by that projection correction; the current metric codec
tuple is `{2,2,1,1,1,1}` including remote-write source starts and streaming reads. Local native
checks cannot fence an older application implementing the previous projection.

## Delta temporality

Pulse never converts delta points to cumulative: that needs per-series state
shared by every instance, which Pulse deliberately does not keep. Each delta
point is stored with the value its producer reported for its interval, and its
`otlp` metadata records `aggregationTemporality: 1`. Query deltas with
`sum_over_time`, for example `sum_over_time(requests[5m])` for the requests in
five minutes, `sum_over_time(requests[5m]) / 300` for a per-second rate, or
`histogram_quantile(0.99, sum by (le) (sum_over_time(latency_bucket[5m])))`.
Do not use `rate` or `increase` on delta series. Avoid sending the same metric
with both temporalities.

## Collector bridge and batching

Cumulative temporality remains the most portable choice for Prometheus-style
queries, for example `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=CUMULATIVE`
where your SDK supports it. Don't route an entire mixed metric pipeline here
without inspecting partial-success counts.

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
processors:
  batch:
    send_batch_size: 128
    send_batch_max_size: 128
exporters:
  otlphttp/pulse:
    endpoint: http://pulse.observability.svc:4000
    compression: gzip
    headers:
      Authorization: "Bearer ${env:PULSE_TOKEN}"
      X-Scope-OrgID: example-production
service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlphttp/pulse]
```

This example is configuration guidance, not a live Collector/SDK acceptance
result. Restrict receiver network exposure. Configure producer identity at the
SDK or with your normal resource-processing pipeline.

**A source-point cap is not an expanded-sample or metadata-byte cap.** Both
supplied points and the sum of their projected samples independently obey
`PULSE_INGEST_MAX_RECORDS` (10,000 by default). Overflow rejects the whole request
with 413, never a valid subset. Each stored sample repeats its
resource, scope, descriptor and complete point metadata. The fixed 16 MiB additive metadata
ceiling applies after normalization and JSON escaping, across the entire
request. A Collector's default 8,192-point batch can exceed it even when the
compressed payload is small. Start with small hard-capped batches, then measure
complete normalized metadata; 128 points is not universally safe for very rich
resources. Reduce batches further when necessary. A source envelope averaging
4 KiB already consumes roughly 32 MiB at 8,192 scalar points, before other fields.
For distributions, multiply source-envelope bytes by projected components, then
sum across all points. A 50-bound histogram with a present sum projects 53 rows;
128 such points with 4 KiB envelopes exceed 26 MiB. Bucket arrays repeated on
bucket rows can grow quadratically. Smaller batches cannot fix an oversized
single point: reduce producer bucket/metadata breadth or keep that instrument
on a compatible backend. Limits are not silently raised.

The shared limits also bound 10,000 supplied points, attribute sets, nested
values, exemplars and 262,144 request nodes by default. Unsupported points still
count. Wire/expanded body caps are 4/16 MiB. Raising configurable node or record
limits does not raise the metadata ceiling. Ordinary remote-write/recording
scalar and label columns do not acquire this additive metadata cap. Raw metric
query JSON has a separate 16 MiB **full result** ceiling. See [ingest limits](ingest-limits.md)
and [query limits](querying.md).

## Responses, retries and durability

- `200`: complete success or partial success. JSON partial responses contain
  decimal-string `partialSuccess.rejectedDataPoints`; protobuf uses the OTLP
  metrics response. Counts refer to **source points**, not projected bucket/quantile
  samples. Inspect these counts; unsupported data is not stored.
- `400`: malformed request/resource/scope/descriptor, invalid protobuf/gzip,
  invalid tenant, a conflicting distribution identity, or a keyed batch containing any rejected point. Keyed batches
  are never rewritten into their valid subset.
- `401` / `415`: failed authentication or unsupported media/encoding.
- `409`: permanent `keyed_content_mismatch`; no overwrite, new registration,
  valid subset or `Retry-After`. OTLP status code6; see [keyed recovery](keyed-ingestion.md).
- `413`: whole-request safety violation. Nothing is appended; reduce the batch
  or metadata before retrying. These permanent failures can be dropped by
  exporters rather than retried.
- `429` / `503`: capacity/storage/publication failures, with retry guidance.

Responses mirror JSON/protobuf request encoding, without a charset parameter.
Malformed points can be rejected individually on unkeyed requests; malformed
resource/scope/descriptor metadata rejects the request. Singular protobuf
messages merge under cumulative owner budgets; Metric data and scalar/exemplar
values follow protobuf oneof selection. Discarded data points and overwritten
attribute contents still consume source admission. Singular scalar fields retain
last-occurrence semantics; packed and unpacked bucket/bound occurrences concatenate
in source order. Exact quoted and schema-scoped unquoted decimal/exponent integers
are supported without float rounding or fractional underflow. Numeric tokens retain
their scalar node/eight-byte admission cost. Known duplicate JSON fields reject the whole request, including null/escaped
members and repeated-field containers; unknown fields remain ignored in the
metrics schema. Shared OTLP wire capability 3 is required separately from metric
decoder capability 2; see [wire semantics and upgrade rules](otlp-wire.md).

An acknowledgment waits for segment upload and manifest conditional publication.
Any instance can accept the request; no sticky routing or local cumulative
state is required. A repeated `Idempotency-Key` with identical normalized content
is deduplicated across instances. The key is **content-addressed**, not an
exclusive reservation: different content with the same key is a different
publication. Unkeyed lost-response retries may duplicate samples. Per-request
limits and local admission do not establish deployment-wide capacity.

## Remote Write 2.0 start timestamps

`POST /api/v1/write` (also `/api/prom/push` and `/api/v1/push`) accepts
Snappy-compressed `io.prometheus.write.v2.Request` with the corresponding
`Content-Type: application/x-protobuf;proto=io.prometheus.write.v2.Request`.
The source start time is retained for float and native-histogram samples:

- Prometheus 3.8.0 / Remote Write 2.0-rc.4: `Sample.start_timestamp` (field 3)
  and `Histogram.start_timestamp` (field 17), independently per sample.
- Compatibility with Prometheus 3.5.0 / rc.3: `TimeSeries.created_timestamp`
  (field 6) applies to every sample/histogram in that series entry.
- Zero means **unset**, not the Unix epoch. Missing/zero becomes `null` in stored
  records; raw `query_metrics` omits the field when unset. Other signed int64
  values survive exactly as `start_timestamp_ms`, in **milliseconds**, avoiding
  overflow from conversion to nanoseconds. Do not treat a start later than its
  sample as a valid cumulative interval: this is source retention, not interval
  validation or conversion. Negative, equal and later starts are retained too.
- For a hybrid message carrying both experimental layouts, a present per-point
  field wins, including explicit zero; otherwise the legacy field applies.
  Repeated singular scalar fields use protobuf's last occurrence. This hybrid
  precedence is Pulse's compatibility policy, not an upstream schema guarantee.

This matches the **default receiver behavior with zero-injection disabled** in
the two pinned Prometheus releases: no synthetic zero samples and no extra
written counts. Prometheus's optional `created-timestamp-zero-ingestion` feature,
start-aware rates/resets and delta-to-cumulative processing are **not implemented**.
No mutable series history, sticky routing, local reset cache or additional S3
authority is introduced. Starts are not labels, sample timestamps, manifest time
bounds, retention clocks or query-window bounds. Exemplars retain their own time.
Existing sample-count/body/attribute bounds remain; one supplied point is still
one stored sample. Malformed start wire fields **and malformed sample/histogram
protobuf framing, even without starts,** fail the whole v2 request before
samples or metadata publish; exceeded ingestion budgets still return 413.
Well-framed semantic errors (for example invalid histogram buckets) retain the
existing partial-acceptance policy for unkeyed requests; keyed rejections append
nothing. Treating malformed v2 point framing as whole-request corruption is
stricter than the older Pulse decoder and matches public protobuf unmarshaling.

Parquet adds a nullable signed `Int64 start_timestamp_ms` column **only when any
row has a start**; legacy segments read as unset/unknown, never reconstructed.
Compaction preserves starts and mixed null rows. Non-null starts participate in
keyed content fingerprints; absent starts keep existing keyed fingerprints and
encoder bytes. Acknowledgment still requires immutable PUT and manifest CAS,
and existing exact-byte conflict responses remain permanent 409s.

**This requires a fleet-wide maintenance upgrade, not a rolling deployment under
traffic.** Start retention is active immediately after upgrade; senders can
already populate these fields and there is no opt-in retention switch. Pause
exporter delivery/queue unsent data, block all metric ingestion at the routing
boundary, drain in-flight requests and finish pending keyed retries on the old
fleet. Stop **all** old metric writers (including recording evaluators), readers
and compactors before starting any upgraded participant. Do not leave an old
compactor running against the shared bucket. Resume delivery only after every
participant has matching app/native metric tuple `{2,2,1,1,1,1}`. Pausing only
compaction does not prevent mixed-ingress keyed duplicates, and a per-node
`Recreate` restart does not coordinate a multi-deployment fleet.

Metadata/start capability 2 also fences the changed v2 decoder result. Old readers
drop the column and old compactors can erase it. Drain pending start-bearing
keyed requests before upgrading: older ingress discarded the field, so a retry
can otherwise select a different content-derived object key and duplicate data.
Do not change keys, overwrite objects or resend unkeyed to bypass a conflict.
Past discarded starts cannot be recovered. Roll back only to compatible readers,
writers and compactors, or after a separately validated migration. Startup only
checks the local artifact, not another running pool.

The [public specification](https://prometheus.io/docs/specs/prw/remote_write_spec_2_0/)
is still experimental. The pinned
[3.5.0 schema](https://github.com/prometheus/prometheus/blob/v3.5.0/prompb/io/prometheus/write/v2/types.proto),
[3.8.0 schema](https://github.com/prometheus/prometheus/blob/v3.8.0/prompb/io/prometheus/write/v2/types.proto)
and real receivers supply independent wire, written-count and stored-query
evidence for 56 offline-replayed cases. Starts come from public schema
marshal/unmarshal, not a live sender/exporter or a TSDB start-retention query.
This is not full TSDB, newer `stateless` mode validation, public compliance-suite,
deployed-client or provider-capacity acceptance.

## Upgrade and rollback

**Upgrade every metric reader, writer and compactor before enabling rich OTLP
metric writes.** Older readers omit the nullable metadata column and older
compactors can permanently erase it while producing otherwise valid samples.
Stop or drain incompatible compaction during the transition. Matching native
artifacts and application code are required; startup capability checks fence
obsolete codec artifacts, not older running application versions.

Before sending histograms/summaries, upgrade **every serving ingestion instance**
to the application/native pair requiring OTLP metric decoder capability 2
(current metric tuple `{2,2,1,1,1,1}`). An older application may reject these points
rather than store them, so a load balancer can otherwise make acceptance depend
on routing. Startup checks only fence the local artifact, not another pool.
The OTLP decoder addition did not change the Parquet schema or scalar keyed encoder.
Metadata/start capability 2 is now required separately for remote-write source
starts above. Readers/compactors that already preserve the full metadata envelope
retain these new source fields, but the earlier all-participant rich-metadata
upgrade requirement still applies to older codecs.

Existing six-column metric segments remain readable with a null envelope;
a present malformed envelope fails closed. A downgrade is safe only to a
version that preserves the new column, or after a validated migration. Retain
coherent versioned backups and test restore/rollback. Keep keyed retry content
stable across versions; semantic changes can create a different fingerprint.
No automatic metadata recovery or reverse migration is performed.
