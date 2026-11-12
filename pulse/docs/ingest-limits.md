# Ingest request limits

Pulse bounds individual ingest requests independently of rate limiting or queue
admission. These limits apply to OTLP/HTTP JSON/protobuf logs (`/v1/logs`), OTLP/HTTP
JSON/protobuf traces (`/v1/traces`), OTLP/HTTP JSON/protobuf metrics (`/v1/metrics`), Loki JSON and
Snappy protobuf (`/loki/api/v1/push`), and Prometheus remote write v1
(`/api/v1/write`). They are conservative safety defaults, not measured capacity
or a guarantee that every request within the limits can be served concurrently.

Sentry JSON errors reuse the structural budgets (`max_depth`, `max_nodes`,
`max_attributes`, `max_key_bytes`), with a separate 1 MiB event byte cap, at most
one event and 100 envelope items. See [error tracking](error-tracking.md) for the
receiver's complete contract.

## Defaults and configuration

Configure `Pulse.IngestLimits` through Elixir configuration or the optional
runtime environment variables below. Environment variables override only the
specified settings. Values must be integers in `1..2147483647`; zero and
`infinity` do not disable a limit. Invalid environment values fail at startup.

| Setting | Default | Environment variable |
| --- | ---: | --- |
| `max_records` | 10,000 | `PULSE_INGEST_MAX_RECORDS` |
| `max_attributes` | 128 | `PULSE_INGEST_MAX_ATTRIBUTES` |
| `max_key_bytes` | 256 | `PULSE_INGEST_MAX_KEY_BYTES` |
| `max_value_bytes` | 16,384 (16 KiB) | `PULSE_INGEST_MAX_VALUE_BYTES` |
| `max_attribute_bytes` | 65,536 (64 KiB) | `PULSE_INGEST_MAX_ATTRIBUTE_BYTES` |
| `max_depth` | 16 | `PULSE_INGEST_MAX_DEPTH` |
| `max_nodes` | 1,024 | `PULSE_INGEST_MAX_NODES` |
| `max_trace_nodes` | 262,144 | `PULSE_INGEST_MAX_TRACE_NODES` |
| `max_otlp_nodes` | 262,144 | `PULSE_INGEST_MAX_OTLP_NODES` |

For example, in `config/config.exs`:

```elixir
config :pulse, Pulse.IngestLimits,
  max_records: 5_000,
  max_attributes: 64,
  max_attribute_bytes: 32_768
```

Or set `PULSE_INGEST_MAX_RECORDS=5000` for a release. Changing these settings does
not change the existing default body caps: 4 MiB on the wire and 16 MiB
expanded. Uncompressed JSON also has the 4 MiB parser cap. Gzip expansion is incremental and
cumulatively bounded across at most **64 concatenated members**, including empty
members. More members fail whole with 413 even when expanded output is tiny;
this bounds per-member work as well as bytes. Snappy checks the declared expanded length before
allocating its output buffer. Measure memory and decode cost before raising
limits; these are node-wide settings, not per-tenant quotas.

## What is counted

- **Records:** supplied OTLP `logRecords`, spans or metric data points, Loki `values`/entries, or remote-write
  samples, accumulated across the entire request. Malformed or subsequently
  rejected records still count. Empty containers also consume a separate work
  budget: `max_records` Loki streams or remote-write series, or
  `2 × max_records` combined OTLP resource and scope groups (each OTLP record
  can need both groups). Trace events and links each have a separate request-wide
  `max_records` budget, even when their containing span is invalid. This prevents
  empty-container and nested metadata floods. Metrics additionally count descriptors,
  with a combined `3 × max_records` resource/scope/descriptor group cap and a
  separate `max_records` exemplar cap. Unsupported metric types still count.
  OTLP distributions also independently cap **expanded float samples** at
  `max_records`, across the request, before constructing their projected rows.
  Histogram bucket/bound primitives and summary quantile messages consume the
  request-node budget. The unchanged 16 MiB additive metadata ceiling charges
  complete source envelopes per projected row, so a source point that fits
  record/node caps can still fail whole with 413. See [metrics](metrics.md).
- **Attributes:** each OTLP resource, scope, log/span/event/link/metric-point attribute list,
  descriptor metadata, exemplar filtered attributes, and nested
  key-value list; each Loki stream label set and entry metadata set; each
  remote-write series label set. The count is per set, not per request. Supplied
  duplicate entries count before normalization. OTLP logs and metrics reject empty/duplicate
  keys; trace and Loki attributes retain their existing last-wins normalization.
  Remote write rejects series with duplicate label names.
  JSON object duplicate keys have already been collapsed by the JSON parser.
  Loki `trace_id`/`span_id` metadata counts even though decoding promotes it to
  dedicated fields. Remote-write `__name__` counts as a label.
- **Bytes:** UTF-8 key/value bytes, not character counts. Each attribute set has
  an aggregate key/value budget including nested values. Strings contribute
  their byte length and non-string scalar values contribute eight bytes.
  OTLP protocol wrapper names are not attribute keys and do not consume this
  budget; `intValue` and base64 `bytesValue` strings are measured as supplied.
  Loki protobuf label values are measured after Go unescaping; the label parser
  also has a wire-size ceiling of `8 × max_attribute_bytes + 8 × max_attributes`
  to bound allocation on malformed or excessively padded label strings.
- **Structure:** JSON attribute trees have bounded depth and visited nodes
  (containers and scalar values; OTLP attribute keys also count as nodes).
  The root is depth zero. Each attribute set has its own node budget. OTLP
  structured bodies have the same structure limits; ordinary log messages do
  not receive the smaller attribute-value or aggregate-attribute byte caps.
  OTLP logs and metrics clamp logical depth to 32 even when configured higher, keeping
  their typed envelope readable under the native JSON codec's 256-level
  ceiling. The default remains 16.
  Loki/remote-write protobuf labels and metadata are flat, so depth/node limits do
  not apply there. OTLP log/metric/trace protobuf attributes are recursive and receive native
  depth/node preflight too, with an additional hard 64-level ceiling. Native
  preflight is conservative: encoded pair/value/container nodes count before
  normalization, integers contribute eight bytes and bytes values count their
  base64-expanded length. The resulting JSON-shaped terms must then pass the
  JSON attribute budgets before AnyValue conversion. Singular protobuf messages
  merge only through a bounded native plan after raw preflight. Counts, bytes and
  nodes accumulate across a logical owner's fragments, including overwritten
  AnyValues; discarded Metric data points still consume the source-record cap.
  Unknown wire occurrences also consume request nodes. These checks precede
  decoded BEAM expansion, so a later failure appends none of an earlier valid
  group. Shared OTLP wire capability 3 is required; see [wire semantics](otlp-wire.md).
  Schema-scoped raw integer numbers decode exactly without float rounding. Invalid
  fractions never underflow to zero; all raw numeric values retain one scalar
  node/eight admission bytes, not a cheaper string classification. Known duplicate
  JSON fields reject whole with 400 within the request limits, even when escaped
  or null-valued; no earlier valid resource subset is published. Signal-scoped
  unknown fields remain ignored. No limit increase or node-wide admission is added.
- **Trace request nodes:** an additional configurable ceiling of 262,144 total
  JSON-shaped map/list/scalar nodes bounds cross-set amplification. Protobuf
  counts before constructing intermediate terms; JSON counts before
  normalization. This is independent of per-set `max_nodes`. Exceeding it
  returns 413 (`too_many_trace_nodes`). The 10,000-span cap is an independent
  ceiling: rich batches can hit nodes or bytes first. Tune batches and measure
  memory before raising it, since the heap guard still applies.
- **Log/metric request nodes:** the same independent request-wide counting applies to
  JSON/protobuf logs and metrics, configured by `max_otlp_nodes`, returning 413
  (`too_many_otlp_nodes`). Unknown JSON fields and protobuf field occurrences
  still count before normalization.
- **Quoted OTLP doubles:** string spellings of numeric `doubleValue` have an
  independent fixed 1,024-byte ceiling before float conversion for log/metric/trace
  JSON AnyValues and metric `asDouble` values (including exemplars). Oversized spellings reject whole requests with 413
  (`attributes_too_large`); protobuf doubles are fixed-width.
- **Log normalized payload:** a fixed 16 MiB full-record JSON ceiling, including
  primary fields and the typed OTLP envelope, proved before storage and again
  before Parquet row allocation. Repeated resource/scope metadata and escaped
  strings count for each row. Exhaustion is 413 (`payload_too_large`), not a
  partial-success record drop. See [OTLP logs](logs.md).
- **Metric metadata:** a fixed 16 MiB additive envelope JSON ceiling before storage
  and Parquet row allocation. Source metadata repeats per point, including
  exemplars, and JSON escaping counts. Exhaustion rejects the entire request
  with 413 (`payload_too_large`). Scalar/label-only metric writes do not acquire
  this metadata cap. Keep Collector batches small and hard-capped; see [metrics](metrics.md).
- **Trace segment payload:** a fixed 16 MiB ceiling on the cumulative normalized
  JSON payload, enforced while encoding before any segment PUT. Shared resource
  and scope metadata is repeated per span and counts each time. A small wire
  request can therefore exceed this ceiling. It returns 413 (`payload_too_large`).

## Rejection and authentication

A request exceeding the record/container budget returns HTTP **413** with
`{"error":"too_many_records"}`. Attribute or structure failures return **413**
with `{"error":"attributes_too_large"}` for Loki/remote write. OTLP logs, metrics and traces use an OTLP
`google.rpc.Status` message in JSON or protobuf, with the reason in `message`.
No records from that request are
appended, and no success or partial-success envelope is returned. Body-cap
failures keep their existing transport behavior (`payload_too_large` for
protobuf, parser errors for JSON). Existing in-budget
malformed-record rejection remains explicit. OTLP log metadata errors reject
whole requests; invalid unkeyed records produce partial success with a decimal
string count. Keyed log requests with any semantic rejection, or without an
event/observed timestamp, fail in full with 400. See [time, correlation and
rejection semantics](logs.md#time-and-correlation).

Prometheus remote write preserves stale markers, other not-a-number values,
and positive or negative infinity alongside finite samples, returning **204**.
Parquet and metrics compaction preserve those values. Instant selectors stop
at stale markers; range functions ignore them. The segment encoder still
refuses absent values.

Native histograms and exemplars are stored. Invalid histograms (spans that do
not cover their buckets, unknown schemas, integer histograms holding more than
their count) are counted in `X-Pulse-Rejected-Records`, including in mixed
batches where float samples are stored; invalid exemplars (label sets over 128
characters, duplicate names) are dropped without counting, as Prometheus
drops them. Both count against the supplied-record budget. Invalid series
contribute their supplied sample count and produce no stored series. Remote-write
label names and values must be valid UTF-8, and label names must be unique within
a series. Violations reject every sample in that series and count them in
`X-Pulse-Rejected-Records`; valid series in the same request are still stored.

Earlier releases could persist invalid UTF-8 metric labels. This validation does
not repair existing objects: such labels can still fail queries, and compaction
now refuses to rewrite them. A failing group can delay compaction for later
hours in that tenant. If affected, keep the original objects and a backup of the
manifest, then use a separately validated repair or re-ingestion procedure.
Do not delete segments directly from a live manifest or expect upgrading alone
to recover corrupted label identities.

**This is a storage compatibility boundary for upgrades from releases that
rejected non-finite samples.** Collectors send stale markers automatically, so
operators cannot delay the first incompatible write after a new writer starts.
Older readers and compactors fail on segments containing these values, even
though the Parquet schema has not changed. Use a non-overlapping upgrade and
read the [upgrade and rollback procedure](deployment.md#stale-sample-storage-compatibility).
Compare actual collector deliveries and staleness with the reference destination
during rollout.

Tenant validation and authentication precede these semantic checks. Snappy
protobuf preflight runs after one bounded decompression, before allocating
record/sample collections, deduplicating labels, hashing series, or constructing
Erlang record terms. OTLP log/metric/trace protobuf preflight runs after bounded gzip
inflation (when configured), before expanding resource/scope/record or attribute
terms. JSON preflight runs on the bounded parsed body before OTLP
AnyValue conversion or record expansion. JSON parsing and gzip expansion still
happen before controller authentication, under their body-size caps; this change
does not add a pre-parse authentication gate. Log/trace requests additionally cap
process heaps at 16 million words including shared binaries before parsing;
heap exhaustion can close the connection without an OTLP error response. This
is not node-wide admission, and native work can outlive a process timeout.

Collectors must reduce oversized batches or attributes rather than blindly
retrying them unchanged. A single value above its limit rejects the whole batch;
SQL instrumentation may require collector-side truncation or explicitly tuned
budgets. Typical Collector/Alloy exporters treat 400/413 as permanent failures.
Use gzip and small batches and inspect actual delivery behavior. This does not
establish per-tenant fairness, ingest concurrency, or bounded queueing. Those
require separate rollout verification and admission/backpressure work.
