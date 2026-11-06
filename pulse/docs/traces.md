# OpenTelemetry traces

Pulse accepts **OTLP/HTTP traces** at `POST /v1/traces` on its existing HTTP
listener. It stores acknowledged spans in Parquet in the same object-storage
bucket as logs and metrics, with separate tenant/signal manifests. No additional
service, port, database, or trace-specific configuration is required.

This is **experimental trace support**, not a production Tempo replacement.
Read the [typed-metadata upgrade boundary](#typed-metadata-upgrade-boundary)
before allowing upgraded writers to ingest into an existing bucket.
Read spans through `query_traces`, assemble all stored spans for one trace
through `get_trace`, or search distinct window-local traces through
[`search_traces`](#search-distinct-traces), on the Model Context Protocol
interface. The search accepts a small string-selector grammar, not full TraceQL
or a verified Tempo implementation. A separate, **disabled-by-default**
[experimental Tempo-shaped search](#experimental-tempo-search) uses complete
retained trace context, not window-local aggregates. OTLP/gRPC export is available
through the opt-in [gRPC receiver](otlp-grpc.md). stored span-duration intrinsic values, exact upstream filtered-name omissions/dynamic dedicated-column parity, full TraceQL, deployed Grafana datasource
compatibility and dedicated trace-ID/attribute postings are not implemented. Experimental Tempo v1/v2 exact-ID
lookup is available; see [its contract](#tempo-v1-trace-lookup). Native compaction and shared event-time retention
are separate opt-ins. Retention-managed scopes have bounded paged catalogs;
flat catalogs remain unbounded without enforcement. Bounded service and
trace-ID bloom summaries reduce candidate scans; they are not a complete index.

## Connect an SDK or collector

The receiver accepts `application/x-protobuf` and `application/json`, with no
compression or `Content-Encoding: gzip`. OTLP JSON uses camelCase fields,
**hexadecimal** trace/span IDs (not base64), integer enum values, and decimal
strings for 64-bit nanosecond timestamps. Protobuf responses use protobuf;
JSON responses use JSON.

Configure the tenant with `X-Scope-OrgID` and authenticate with
`Authorization: Bearer <token>`, as described in [configuration](configuration.md#tenants-and-tokens).
If the tenant header is omitted, the tenant is `default`; production still
requires that tenant's token. Use TLS at the ingress and keep the listener
private, including its unauthenticated `/metrics` endpoint.

For SDKs that honor the standard environment variables:

```sh
OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://pulse.example.com/v1/traces
OTEL_EXPORTER_OTLP_TRACES_HEADERS="Authorization=Bearer%20<TOKEN>,X-Scope-OrgID=production"
OTEL_EXPORTER_OTLP_TRACES_COMPRESSION=gzip
OTEL_BSP_MAX_EXPORT_BATCH_SIZE=100
```

Check your SDK's configuration precedence and header encoding. SDKs that only
export gRPC can send directly to the opt-in [OTLP/gRPC receiver](otlp-grpc.md), or
through an OpenTelemetry Collector or Alloy receiver exporting OTLP/HTTP. A pinned local Go SDK/Collector
profile now exercises this bridge, but it found upstream link-tracestate and
batch-split schema losses. Two pinned [Erlang/Elixir client profiles](trace-elixir-clients.md)
also exercise direct HTTP and gRPC bridging, with actual Phoenix/Bandit/Finch
instrumentation; that exporter changes boolean types and drops event/link counters
before sending. A pinned [Rust SDK/tracing component](trace-rust-clients.md)
also exercises direct HTTP and gRPC bridging, retaining booleans, link tracestate
and event/link counters in that profile. Its programmatic HTTP endpoint needs the
full `/v1/traces` path; environment headers override programmatic ones. None of
these component tests accepts a full application or deployed Alloy pipeline.
Read [bridge compatibility](trace-collector-bridge.md) before adding processors
or claiming transparent forwarding.

This illustrative private-sidecar shape avoids Collector re-batching and queues:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:4317
exporters:
  otlphttp/pulse:
    endpoint: https://pulse.example.com
    compression: gzip
    headers:
      Authorization: "Bearer ${env:PULSE_TOKEN}"
      X-Scope-OrgID: production
    sending_queue:
      enabled: false
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: []
      exporters: [otlphttp/pulse]
```

The exporter appends `/v1/traces` to `endpoint`. Expose receivers only to trusted
senders, with authentication/TLS where required; static headers are not a public
multi-tenant gateway. With no Collector queue, outages pressure SDK queues.
Enabling buffering/re-batching requires its own fidelity and crash/durability
acceptance. The example uses Collector retry defaults, unlike the conformance
run's five-second budget with 100–200 ms intervals. The local run is not that
acceptance or a deployed TLS
profile. Small SDK batches and gzip still need measured attribute/event/link
budgets; a span count alone is never a universal safe batch size. Pulse does not
change SDK sampling or generate spans itself.

For Alloy, the analogous unvalidated wiring is directly from the existing OTLP
receiver's trace output to `otelcol.exporter.otlphttp.pulse.input`. Its exporter
uses a base URL, not `/v1/traces`. Do not assume an Alloy version, batch processor
or exporter queue preserves metadata merely because it can forward OTLP; validate
the actual pipeline, receiver security, queue behavior and downstream headers.

Keep your existing tracing destination during evaluation. Pulse does not yet
provide the lifecycle management or query breadth required for a full cutover.

## Acknowledgments and limits

HTTP **200** means the accepted spans are durable: the segment PUT and manifest
conditional write have both succeeded. Invalid individual spans are omitted and
reported through `partialSuccess.rejectedSpans`. Its `errorMessage` lists the
rejected counts by reason, for example
`invalid records rejected: end_before_start=2, invalid_span_id=1`. For JSON,
this count is a decimal string, as required for an int64 OTLP field. Do not retry
partial-success responses as if the whole batch failed.

Each rejection also increments
`pulse_ingest_rejected_records_total{signal="traces",reason=...}` (see
[self-monitoring](self-monitoring.md)), and Pulse logs one warning per reason per
minute with the count, tenant and up to five `service.name` values. Payload
contents and credentials are never logged. Reasons: `invalid_span`,
`invalid_trace_id`, `invalid_span_id`, `invalid_parent_span_id`,
`invalid_start_time`, `invalid_end_time`, `end_before_start`, `invalid_name`,
`invalid_trace_state`, `invalid_kind`, `invalid_status`, `empty_attribute_key`,
`invalid_attribute_value` (including duplicate keys inside a kvlist value),
`invalid_flags`, `invalid_dropped_count`, `invalid_event`, `invalid_link` and,
with enforced retention, `retention_expired`.

Repeated attribute keys on a resource, scope, span, event or link are accepted,
as the Collector and Tempo accept them, although OTLP asks for unique keys. Common
SDKs emit them: the Erlang SDK exports both `:"client.address"` (set by
instrumentation) and `"client.address"` (set by an application), and the Rust SDK
appends a `tracing` field recorded twice. Pulse keeps the **last** occurrence of
each key and adds the discarded ones to that owner's `droppedAttributesCount`.
Earlier releases rejected these spans.

- **400**: invalid tenant, malformed OTLP/protobuf/gzip, invalid input, a keyed
  batch with any rejected span (`invalid_keyed_batch`), or a keyed batch containing
  expired spans (`retention_expired`). Keyed failures append no valid subset.
  Unkeyed expired spans use OTLP partial success instead.
- **401**: missing or invalid tenant credentials.
- **409**: permanent `keyed_content_mismatch` (OTLP code6), without `Retry-After`.
  Existing bytes are never overwritten; no new registration or valid subset.
  See [keyed ingestion](keyed-ingestion.md) for exact-byte streaming recovery,
  all-writer upgrades, costs and retention/compaction interaction.
- **413**: body, span/event/link count, attribute, or structure budget exceeded.
  Nothing from the request is appended; reduce the batch or attributes.
- **415**: unsupported content type or encoding.
- **429**: ingest backpressure. Retry with backoff.
- **503**: transient storage failure. Retry with backoff.

The default caps are 4 MiB on the wire, 16 MiB after gzip expansion, 10,000
supplied spans, and separate request-wide budgets of 10,000 events and 10,000
links. Resource/scope container and attribute budgets also apply, before
record expansion. Traces additionally cap supplied JSON-shaped nodes at 262,144
per request (`PULSE_INGEST_MAX_TRACE_NODES`), and a Parquet segment's total
normalized JSON payload at 16 MiB, proven before appending to any backend. Both
query-friendly projections and the new typed envelope count, including repeated
owner attributes. The envelope roughly doubles attribute bytes and adds pair/tag
overhead: previously accepted near-ceiling batches may now receive permanent 413
responses. Halving a previous batch is only a starting point, not a safe guarantee;
measure the richest normalized payload and use small hard-capped collector batches.
Compaction and full query/assembly responses also reach their unchanged byte
ceilings sooner. Node-budget failures use
`too_many_trace_nodes`, independently of per-attribute limits.
Repeated resource/scope metadata counts toward that normalized payload ceiling,
even when supplied only once on the wire. Trace requests also have a
16-million-word process heap cap, including shared binaries, starting before
JSON parsing. Exceeding the heap cap can close the connection rather than
produce an OTLP response. If a heap kill happens after publication but before
acknowledgment, an unkeyed retry can duplicate spans. These are per-request
safeguards, not node-wide
ingest admission or a guaranteed capacity. See [ingest limits](ingest-limits.md).
Authentication precedes semantic validation; JSON parsing and gzip inflation
by the JSON parser still happen before authentication under the body/heap caps.

**A single oversized attribute rejects the entire export batch with 413.**
Collectors normally treat 400/413 as permanent failures, not retryable errors.
SQL instrumentation can emit statements above the default 16 KiB value limit.
Drop or truncate such attributes in your exporter/collector, or explicitly tune
`PULSE_INGEST_MAX_VALUE_BYTES` and `PULSE_INGEST_MAX_ATTRIBUTE_BYTES` for the
metadata you retain. Reducing span count alone cannot fix an oversized value.
Pulse never silently truncates safety-budget violations.

An optional `Idempotency-Key` deduplicates retries of the same tenant, key, and
decoded batch. Without it, a lost-response retry can create duplicate spans.
Queries preserve duplicates rather than claiming trace completeness or ingest
deduplication. A failed request is not an assertion that storage published
nothing: retry after ambiguous storage responses using the same key and content.

## Stored span data

Pulse retains trace, span and parent IDs; trace state and flags; name and kind;
start/end nanosecond timestamps; status code/message; typed span and resource
attributes; instrumentation scope name/version/attributes; events and links;
dropped-attribute/event/link counters; resource dropped-attribute counts; and
resource/scope schema URLs. `service.name` is promoted for searching. Events and
links remain nested metadata, not independent signals. Query-friendly attribute
maps still project bytes to base64 strings. New spans additionally expose `otlp`,
a version-1 typed envelope with ordered `resource`, `scope`, and `attributes`
KeyValue lists, plus `events`/`links` lists of attribute lists aligned by position
with the corresponding stored events/links. Each AnyValue retains its OTLP tag:
bytes remain `bytesValue`, strings `stringValue`, int64 values canonical decimal
`intValue` strings, and doubles `doubleValue` numbers (including signed zero) or the three canonical
non-finite OTLP JSON strings.
Arrays, kvlists, booleans and empty AnyValues retain their nested structure and
pair order. Default full queries and assembly include this envelope; use
`fields: ["otlp"]` to project it explicitly.

Legacy spans have no envelope (internally nil); their query-friendly strings
cannot prove original byte/string identity. Readers and compaction never invent
it. `get_trace` reports their IDs in `metadata_unknown_span_ids`. Legacy/rich
copies with identical projections are duplicates, not proven conflicts; distinct
projections or disagreement between known typed copies are conflicts.

IDs must have 32 hex digits for traces and 16 for spans, and be nonzero. Accepted
IDs normalize to lowercase. Missing/empty parent IDs represent roots. Times must
be nonnegative signed-64-bit nanoseconds, with end greater than or equal to
start; missing protobuf scalar times default to zero. Unsupported enum values,
malformed IDs, attributes, events, or links reject their containing span rather
than silently dropping its metadata. Invalid resource/scope metadata rejects
the request. Unknown protocol fields are ignored for forward compatibility.
Non-finite doubles are retained at all owners and nested values as typed
`doubleValue` with canonical `NaN`, `Infinity`, `-Infinity` spellings. Query
projections show strings; protobuf export preserves the class with canonical
quiet-NaN bits, not NaN sign/payload/signaling state. Only original string
`service.name` values promote to the service field. See [OTel fidelity and
remaining Tempo-replacement gaps](trace-otel-compatibility.md). Protobuf
string fields must be valid UTF-8; malformed wire strings reject the request.
Repeated singular protobuf messages merge recursively under cumulative owner
budgets, without silently overwriting nested metadata or refunding discarded
attribute contents. Exact quoted and unquoted decimal/exponent int64 values and
source times are supported without float rounding or fractional underflow; numeric
32-bit fields also retain their exact integral token values. Trace uint32 counts
and fixed32 flags accept exact quoted forms in `0..4294967295` at every owner.
Enums still require numeric JSON tokens: quoted digits and names reject.
Stored counts/flags match numeric JSON/protobuf. Invalid resource/scope counts
reject the request; invalid span/event/link fields reject their containing span.
Keyed requests never publish a valid subset.
Shared OTLP wire capability 3 is required, with the updated ingress application
on every serving instance before producers use quoted trace counts/flags.
Known duplicate JSON fields reject the whole request, including escaped/null-valued
fields; unknown fields remain ignored in the traces schema. Remaining
null/presence handling is a separate gap.
See [wire semantics and upgrade rules](otlp-wire.md). Resource entity references
remain unsupported.

## Typed-metadata upgrade boundary

Current required native trace tuple is `{2,1,3,10,13}`. Before accepting non-finite
values, upgrade all participants; old readers/compactors reject them. NaN
normalizes by class, not payload bits. Service promotion now requires original
`stringValue`, also removing prior byte-service promotion; drain those keyed
retries because normalized fingerprints change. Old/new copies of the same
byte-service span also conflict permanently at stored-trace assembly/Tempo lookup;
keyed draining does not repair unkeyed duplicates. Avoid mixed writers/resends of
those inputs. Ordinary finite records with string services remain unchanged. See [full compatibility contract](trace-otel-compatibility.md).

Upgrade **every trace reader, writer and compactor**, with matching native
artifacts, before any upgraded writer accepts traffic against a shared bucket.
Pause ingress and drain outstanding operations/retries under the old version,
then replace all old processes before resuming. A `Recreate` rollout can stop old
pods in one release, but does not coordinate other releases or independent nodes;
verify the complete deployment. The physical Parquet columns are unchanged, but
the full payload, fingerprints and reconciliation contract have changed.

Drain legacy keyed retries before the boundary: enriched records have different
content fingerprints even with the same request key. A replay can create another
stored copy. Its legacy metadata remains unknown rather than becoming a fabricated
typed value. The startup capability check rejects stale native artifacts, but it
cannot stop already running old instances.

Keep a compatible image and native artifacts for rollback/restore. Older readers
can hide the envelope, and old decode/re-encode writers can erase it. Do not roll
back to an incompatible version after rich writes; retain a compatible reader or
perform a separately validated migration/restore. Back up manifests/pages and
segments coherently. Disabling compaction or retention does not undo the richer
payloads, and bucket lifecycle rules must not delete referenced objects.

## Query spans

### Experimental Tempo search

**Disabled by default.** Set `PULSE_TEMPO_SEARCH_ENABLED=true` or Helm
`tempoSearch.enabled: true` only after verifying retained tenant cardinality,
scan bytes and aggregate provider pressure. This enables `GET /api/search` and
MCP `search_trace_metadata`; it does not change `search_traces` or exact-ID
lookup. Disabled HTTP search returns `501`; MCP returns `tempo_search_disabled`.

Each spanset's predicates match one span. Results are always the
most recent matching traces, so `with (most_recent=true)` is optional; Grafana
omits it by default, and real Tempo may return any matching traces without it. Positive original-string equality/anchored-regex AND selectors
retain native source planning. [Bounded boolean expressions](trace-query-expressions.md)
add empty spansets, typed bool/double/int64 comparisons, all five original owner
scopes, quoted keys, Grafana's 25 intrinsic spellings (including root fields,
IDs, instrumentation and event timing), own-span and retained-trace duration,
negated strings, AND/OR and parentheses, without that planner. Bounded structural
operators and one trailing `select` are also supported. Other TraceQL queries
fail, never approximate. Tags-style search,
other pipelines, variable expansion and streaming endpoints remain unsupported.
Separate [tag discovery](#experimental-scoped-tag-discovery) is available behind
the same default-off gate with its own filter/value contract.

HTTP accepts only `q`, paired decimal `start` and `end` (uint32 Unix
**seconds**, positive start ≤ end), `limit` (1–1000, default 100), and `spss`
(sampled spans per spanset, 1–100, default 3). Omit both time bounds or supply
`start=0&end=0` to search all retained context under the same admission and scan
ceilings. This differs from Tempo's ingester-only default routing: Pulse has no
separate ingester data tier. Partial or mixed-zero windows still reject.
Tenant/auth rules match trace lookup.
Both JSON and exact `Accept: application/protobuf` responses are supported.
MCP requires positive `start_ts_ns`/`end_ts_ns`, `tenant` and `query`, with the
same optional `limit` and `spss`. HTTP endpoints become exact nanosecond
boundaries: `end=40` includes a start at `40.000000000`, not `40.500000000`.
This is the tested upstream contract, not an implicit full-final-second window.

HTTP search-limit rejections identify zero as `invalid limit: must be a positive
number`. Malformed or uint32-overflowing values within the existing ten-byte
input bound return `invalid limit: strconv.ParseUint: parsing ...` with syntax
or range details. Values above the operator cap of 1000, and longer inputs,
retain the generic policy error. Existing numeric admission, authentication and
window-validation precedence are unchanged. Upgrade query-serving applications;
no native or storage-format change is required.

Malformed or uint32-overflowing HTTP `spss` values within the same ten-byte bound
also identify their parameter: `invalid spss: strconv.ParseUint: parsing ...`.
Parsed zero, values above the sampling cap of 100, and longer inputs retain
generic policy errors. The default remains 3 and sampling still follows full
trace matching; accepted numeric grammar and auth/window/limit precedence do
not change. This is a diagnostic change, not expanded sampling admission.

Paired HTTP search bounds also identify malformed or uint32-overflowing
`start`/`end` values within the ten-byte input bound. Start parses before end,
with messages such as `invalid start: strconv.ParseUint: parsing ...`.
Partial bounds, mixed zero/positive bounds, reversed windows, plus-prefixed
numeric bounds and longer inputs still receive generic policy errors. Numeric
acceptance, retained-context selection and window-before-limit precedence are
unchanged; no native or storage-format upgrade is required.

```bash
curl -G -H 'Authorization: Bearer <token>' -H 'X-Scope-OrgID: <tenant>' \
  --data-urlencode 'q={ resource.service.name = "worker" } with (most_recent=true)' \
  --data-urlencode 'start=1710000000' --data-urlencode 'end=1710000600' \
  --data-urlencode 'limit=100' --data-urlencode 'spss=3' \
  'https://pulse.example.com/api/search'
```

Search first aggregates **every retained span for each candidate trace in the tenant snapshot**, then
selects traces whose earliest stored start ≤ request end and latest stored end
≥ request start. A matching span can be outside the request window; traces
whose envelope overlaps only across a gap still match. Root names, duration
and service/error counts use complete **retained stored** context. This is not
exporter completeness or a pre-retention history reconstruction. The response
header states `all-visible-stored-context; exporter-completeness-unknown`.
Trace start descending ordering precedes limiting; equal-start trace-ID
ascending ordering is a deterministic extension of upstream's unspecified
ties. Sample order is deterministic start/ID ascending, not a claim about all
upstream sampling choices. JSON contains `traces` (including an empty array),
compact hex trace IDs, root metadata where known, uint32 millisecond duration,
`spanSet` and `spanSets`, full `matched` counts and sampled spans, plus
`serviceStats`. Int64 nanosecond times/durations are quoted JSON strings.
Duplicate rows count in matching and statistics; samples do not establish
trace completeness. Unknown inspection metrics are omitted, not invented.

### Bounded boolean expressions

Retained-context search supports `{}`, original-string `!=`/`!~`, original-int64
and float64 comparisons, original booleans, `name`/`span:name` strings,
`kind`/`span:kind` and `status`/`span:status` enums, and own-span
`duration`/`span:duration`, combined with `&&`, `||` and parentheses.
Grafana's migrated min/max filters also work: `traceDuration` and `trace:duration`
compare the **complete retained trace** max-end minus min-start, not the root's
or selected span's duration. This search mode recovers context outside the
ordinary one-hour horizon, then replays already captured bytes for final matching;
it retains every existing input/group/sample/work ceiling and can reject whole
requests for broad histories. Trace metrics and legacy filters do not gain this
trace-wide semantic. It is not exporter completeness.
TraceQL gives AND/OR equal precedence and groups left-to-right. Missing or
mismatched types do not match even negative predicates; no inferred/coerced data.
Int and float literals target different original types, including above 2^53;
this is typed Parquet predicate behavior, not full TraceQL numeric arithmetic.
Name is the intrinsic span name, not an attribute; kind uses the six OTel enums.
Empty spansets can be structural operands but do not broaden structural metrics.
Original link/instrumentation attributes and double-quoted key segments retain
their types and owner boundaries. Root name/service predicates recover complete
retained context; event/link/instrumentation intrinsics use their original owner
metadata. ID predicates retain the pinned engine/Parquet normalization caveats,
and event/link conjunctions require a single repeated owner. These are verified
bounded forms, not full TraceQL or arbitrary existential event expressions.
Expressions skip summary pruning but use the same newest-first planning, plus an
additional 20M prefilter work ceiling per scan attempt. Window-local search,
exact-ID filters, metrics and discovery keep separate capabilities. Read [expression semantics, costs and
upgrade requirements](trace-query-expressions.md) before use.

### Candidate pruning and newest-first planning

Search returns the most recent `limit` matching traces, so S3 search plans
candidate sources newest first instead of reading every retained source. For an
original positive-string AND selector, a source is a candidate unless its
published summary proves it cannot hold a matching span: its complete
`resource.service.name` set, or its bounded resource/span attribute value sets
(the same sets `query_traces` uses, see [Query spans](#query-spans)),
exclude a predicate's value or pattern. Paged-manifest leaves prune the same way
from their union summaries. New encoders and compactors publish the proof that
allows this only when **every row has known typed metadata, valid core fields,
agreeing payload/columns, and every original string service.name is represented
by its promoted service column**. Unproven sources, legacy rows, unknown
summaries, keys past the value-set bounds, non-string values and flat manifests
never prune; a projected legacy string is never inferred to be an original
string. Compaction recomputes the proof from bytes, so it can prove old rich
sources but never reconstruct missing original types. No compaction is required
for correctness. Expressions do not prune but use the same planning.

Planning runs in rounds. A round discovers matching-or-legacy-unknown candidate
IDs in the newest 4 candidates by `max_ts` (including matches outside the
requested time window), replaying their exact admitted bytes locally without a
second GET. Candidate IDs then select additional context sources through complete
SHA-256-prefix sets or versioned canonical ID blooms, and paged-manifest leaves
through their ID blooms, **without a service or request-time filter**, among the
sources within the [context horizon](#search-context-horizon) of the round's
candidates (one hour by default). Earlier roots, other services and nonmatching
spans of those IDs within it are recovered before overlap, order or limit. A trace that an unread candidate could still add starts
no later than that candidate's `max_ts`, so when the round's `limit`th trace
starts after the newest unread candidate, the round's answer is the answer.
Otherwise the next round plans four times as many candidates, reusing (up to 64
MiB) the objects earlier rounds read. A search that stops early never reads the
older candidates, so their legacy rows or root conflicts do not fail it.
Unknown ID summaries read conservatively; collisions/false positives only add
reads. A separate **2,000,000 native index-probe ceiling** falls back to reading
all remaining sources, never clipping IDs or context. Read context validates every
visible payload; a new potential ID in a pruned source after candidates are
sealed rejects the whole query rather than silently expanding an incomplete
trace. This violation currently shares the generic invalid-stored-data error,
not a distinct diagnostic metric.

This is **not an integrity scrub of pruned objects**: a missing/corrupt object
proven irrelevant at publication can go unread, unlike an unplanned full scan.
Keep coherent manifest/page/segment backups (manifest backups or bucket versioning). It is not a
posting index, a global query cache, full TraceQL or representative workload/deployed
client acceptance. Discovery and window-local `search_traces` do **not** use this
plan; their existing raw source/header costs remain unchanged.

Context planning inspects the retained catalog of leaves that may hold a
candidate ID, under unchanged metadata byte/page bounds (8 MiB default), BEAM
query-heap admission and a separate hard **8192-reference ceiling**. Metadata or
heap bounds can bind well before 8192; it is not a promised catalog capacity.
Old/unproven sources still consume data reads even under highly selective
filters, and a search with fewer matches than its limit visits every candidate.

Potential matching/legacy IDs count toward **65,536 candidates**. Actual fetched
sources of a round cumulatively count toward **1024 inputs / 32 MiB compressed input /
1,000,000 raw footer rows**, even after captured input memory is freed. Lower caller
limits remain lower; bounded GETs and actual footer checks cover lying sizes/counts.
Both native passes independently cap one million rows. Context can consume the
remaining budget before failing: a small first pass does not reserve capacity for
all context. Failures reject whole, never return partial traces. A missing-object
retry aborts native state before a fresh snapshot/plan; prior provider/byte/row
work remains spent. Candidate IDs add roughly 4–6 MiB of native bookkeeping,
with up to 512 KiB native hash prefixes and a temporary 2 MiB ID binary. Strings/
samples and output keep independent **16 MiB** ceilings. These are tighter than
the general 128 MiB scan ceiling and not a capacity gain for every workload.
Record-based reference adapters have no source indexes or native compressed-input
owner caps. Dirty native work can outlive deadlines; exceptions/panics rely on
resource cleanup and lock contention remains a generic resource error.

Require complete-context search capability **10**, current tuple **`{2,1,3,10,13}`**, on
all serving application/native artifacts before use; discovery capability is
**13**. Startup verifies only local artifacts, not other running nodes. Smaller
windows/result limits do not themselves reduce retained context. Broad, legacy,
dense or retain-forever histories can still exhaust catalog/input/group bounds.
Representative posting/index planning and provider/capacity validation remain
outstanding. Do not authorize deletion to make an experimental query work.

Native candidate/group/map bookkeeping, Arrow, retained input, output and scratch allocations are
outside the BEAM heap limit; group bookkeeping alone can add roughly 15–20 MiB
at the ID cap, on top of the charged string/sample budget. These are not
node/deployment-wide memory or provider-traffic guarantees. Aggregate pressure
across replicas and concurrent queries remains an operational acceptance gate.

Any overlapping legacy-unknown trace fails with `409 trace_metadata_unknown`,
even if its projections appear nonmatching. Compaction cannot recover original
types. Use post-upgrade history and keep the old backend for incompatible
history. Matched zero-start traces fail `409 trace_timestamp_unknown`; unrelated
known nonmatches with zero starts do not poison a search. Conflicting matched
root summaries fail `409 trace_root_conflict` rather than choosing or hiding a
root. Matched durations beyond uint32 milliseconds fail
`422 trace_duration_limit` rather than wrapping. Group/scan/byte bounds also
return `422`, admission `429`, deadlines `504`, corrupt data `500`, and storage
unavailability `503`. All failures reject the complete response, never clip
context or return partial results.

The source-window overlap, root/duration/statistics, hint/limit, sample count,
empty response and final-second boundary fixtures were generated by **actual
public Tempo v2.9.0 Parquet blocks and its TraceQL search engine**. That is
independent executable subset evidence, not full TraceQL, deployed-version
Grafana frame conversion, client acceptance, residency, capacity or cutover
approval. Discovery APIs, representative indexed planning and live-client
acceptance remain pending. The existing window-local MCP search stays separate.

### Experimental scoped tag discovery

The same default-off `PULSE_TEMPO_SEARCH_ENABLED` / `tempoSearch.enabled` gate
also enables the following **retained-snapshot discovery subset**, plus the
separate static intrinsic vocabulary described below:

| HTTP route | Required target | Response |
|---|---|---|
| `/api/search/tags` | Optional `scope` (omitted/empty/`none` combines scopes) | `tagNames` string list |
| `/api/v2/search/tags` | Optional `scope` (omitted/empty/`none` combines scopes) | `scopes` with `name` and `tags` |
| `/api/search/tag/<target>/values` | Bare original key (e.g. `service.name`), explicit `<scope>.<key>` or unscoped `.<key>` | `tagValues` string list |
| `/api/v2/search/tag/<scope.key>/values` | Explicit `<scope>.<key>` or unscoped `.<key>` | Typed `tagValues` with `type` and `value` |

V1 bare keys search the same three original owners as unscoped values below.
Existing canonical scoped and intrinsic targets retain precedence, so this is
not full legacy-v1 alias/collision parity. V2 still requires a scoped/unscoped
attribute identifier or one of the supported intrinsic names.

Attribute targets accept JSON-compatible double-quoted keys, for example
`span."http route"` or `resource."attr=equals"`. URL-encode the target when
building requests. Slashes inside keys work both as `%2F` and as literal path
separators; only the final `/values` is the route suffix. Percent sequences are
URL-decoded once, so a literal `%20` in a key must travel as `%2520`. Invalid
quotes/escapes and keys beyond 256 decoded UTF-8 bytes reject with `400` rather
than returning an empty dictionary. This identifier support does not expand
the separate supported filter grammar.

Targets also accept dot-separated quoted and ordinary portions, such as
`span."bar z".foo` for the single attribute key `bar z.foo`, or
`.foo."bar baz"` for unscoped `foo.bar baz`. Mixed quoted portions decode
only escaped quote/backslash; fully quoted keys retain their existing
JSON-compatible escapes. Quoted dots are literal key bytes, not nested-object
traversal. Normalization inputs cap at 2048 bytes and decoded keys at 256 UTF-8
bytes. Adjacent quotes, suffix text after a quoted portion and malformed mixed
escapes reject. Upgrade query-serving applications consistently; no native or
storage-format change is required for target parsing. Retained-context search
and expression discovery also accept quoted keys; metrics and legacy filters
retain their separate grammars.

Supported explicit scopes are **resource, span, instrumentation, event and link**.
Each searches only original attributes of that owner: instrumentation does not
invent `name`/`version` keys from scope fields; event names/timestamps and link IDs
are not attributes. Repeated events/links contribute their own attributes without
flattening them into span attributes. Empty nested-owner lists contribute no keys.

MCP `discover_trace_tags` requires `tenant`; omit `scope` or use `"none"` for
combined names. `discover_trace_tag_values` still requires an explicit `scope` and a nonempty `key` of at most 256 UTF-8 bytes and accepts an
optional `query`. Both return v2-shaped JSON. HTTP accepts the target plus
optional `q`; absent, empty or exactly `{}` means unfiltered. JSON and exact
`Accept: application/protobuf` are supported. Value routes also accept the
supported filtered selector below; name routes accept it with the distinct
**complete name-hint** semantics below.
Tenant/auth rules match lookup. Disabled queries return HTTP `501` or MCP
`tempo_search_disabled` without storage reads.

### Grafana query-builder filters and stored IDs

Discovery accepts the single-spanset search expression grammar: typed string,
int64, boolean and float predicates, AND/OR/groups, quoted keys, all five
attribute scopes and the advertised intrinsic spellings. Repeated event/link
conjunctions require one owner; values preserve original types. Structural
operators, `select`, hints, malformed/incomplete expressions and one-sided or
zero-sentinel discovery windows still reject rather than dropping filters.

The five ID targets `trace:id`, `span:id`, `span:parentID`, `link:traceID` and
`link:spanID` now return stored string dictionaries, not static empty results.
Root and duration predicates recover complete retained context before matching
parents in selected source envelopes. Duration is retained max-end minus
min-start, not own-span or window-clipped duration. Root ambiguity and unknown
original root service fail whole when root evidence is required; span-local or
duration-only queries do not require a root.

Expression discovery requires capability **13**, search **10**, metrics **7**:
startup tuple `{{2,1,3,10,13},7}`. Upgrade every serving application/native pair.
Custom adapters need `tempo_expression_discovery_json/5` or the bounded complete
reference fallback; old callbacks never receive new programs. Flat references
cannot implement source windows. Retained inputs cap at 1024 objects / 32 MiB /
1M physical rows, with independent replay, context, work, dictionary and output
limits. Captured inputs replay without another provider GET. Stored/keyed bytes
are unchanged.

The following string-AND descriptions document the preserved fast path, not
the whole expression grammar. Same-target original-string equality remains
rejected on that path rather than returning a query literal as stored evidence.
Expression queries always project stored values. The existing complete name-hint
and static-vocabulary distinctions still apply. Valid filters on static
vocabularies are syntax-checked but do not make them stored-value evidence.

Pinned upstream engine/Parquet probes cover 53 discovery cases: 46 exact
dictionaries and seven explicitly documented complete-filter/stored-ID
extensions. Upstream omissions remain unchanged in the oracle. Native/reference,
legacy-adapter and authenticated OTLP → Parquet → owned S3 HTTP replays cover
these cases; they do not establish real-provider capacity or deployed Grafana
acceptance. See the [fixture ledger](../test/fixtures/traces/tempo_integration/README.md).

The string fast path accepts a nonempty `{ resource.<key> = "string" &&
span.<key> =~ "pattern" }` selector: 1–16 AND-combined original-string equality
or fully anchored RE2-subset predicates, at most eight regexes. All predicates
must match the **same parent span**, not different siblings under a resource.
For instrumentation/event/link value targets, these resource/span filters select
parents, then union the selected parents' original target-owner attributes.
Instrumentation/event/link predicates use expression discovery instead;
no cross-event or cross-link predicate matching is inferred. Typed
boolean/integer/bytes projections never become strings for filtering. Query size
is at most 16,384 UTF-8 bytes; keys/exact values/patterns have the same 256/4096/
1024-byte limits as trace selectors. Regexes compile once per admitted query.

**Same-target equality in value discovery is explicitly rejected.** Tempo can return a query's
literal value without checking whether it exists in storage (even alongside an
impossible filter). Pulse's endpoint promises stored values, so it rejects that
shortcut rather than fabricating presence. Use another attribute as the filter,
or use same-target regex for **original string targets** when appropriate (it
cannot select int64/bool targets, even though those appear unfiltered).
Invalid/incomplete selectors also reject; there is no upstream-style fallback
to unfiltered results. Grafana can send the editor's half-typed query while
suggesting values; these requests return `400` until a complete supported
selector is supplied, rather than extracting/guessing partial conditions.

**No one-sided/zero-sentinel time ranges, TraceQL hints, structural
operators, `scope=all` or remaining
stored span-duration intrinsic values are supported. Default combined names and static intrinsic vocabulary are
explicit exceptions described below.** Such requests reject with
`400`, never silently drop filters or approximate autocomplete. Grafana may
send these automatically, so its autocomplete can be partial or error. These
routes do not establish complete Grafana datasource parity. Ingress must expose
both exact `/api/{v2/}search/tags` routes and Prefix `/api/{v2/}search/tag` routes.

Unfiltered explicitly scoped names include every original stored attribute key, including
keys with unsupported value types. Values support **original string, signed
int64, boolean and float values**, including non-finite double classes. V2 keeps types separate even when spellings match;
V1 inherently flattens/deduplicates spellings as that older protocol does. V1
name responses also omit the scope; v2 retains it. Default name lookup combines
scopes without flattening them in v2. Values from multiple events/links are unioned,
without identifying which nested owner supplied a value, matching Tempo.
V2 omits `value` for an empty string as the protobuf default; V1 retains the
empty string entry. Values order lexicographically by type then value, not
numerically. Finite floats use TraceQL's Go-style shortest round-trip text: `1.0`
retains float identity, `-0.0` remains distinct from `0.0`, and scientific notation
uses the upstream exponent thresholds. This changes prior float targets from
`422` to successful typed results. V1 can merge a float and original string with
the same spelling. Non-finite doubles use Tempo's `NaN.0`, `+Inf.0`, `-Inf.0`
autocomplete spellings; these are not OTLP input spellings or proof of string type.
On matching spans, targeted bytes, arrays, kvlists or empty AnyValues reject
the **whole** request with `422 unsupported_trace_tag_type`, never coerce or
omit members. An absent target succeeds with an empty list only when every
retained row's typed metadata is known.

#### Default names combine scopes, not value semantics

Omit HTTP `scope`, send an empty value, or use `scope=none` to discover names in
**all five stored namespaces in one retained-snapshot scan**. MCP omits scope or
uses `"none"`. V2 retains each namespace separately and always adds the 25 static
intrinsic suggestions, even for empty retained context. V1 flattens/deduplicates
stored names and **excludes** intrinsic suggestions; explicit `scope=intrinsic`
remains available for v1 vocabulary. Scope and key order are deterministic
lexical extensions, not an upstream ordering guarantee.

Default names are **hints even without a filter**: when any visible parent exists,
Tempo's required `resource.service.name` column contributes `service.name` even
if no original attribute exists. Other original keys remain complete. Filtered
default names additionally use the fixed promotion hints described below.
Expired rows supply no hints; empty visible context has only v2 static suggestions.
The HTTP coverage header is `stored-context-name-hints-and-static-vocabulary;
not-key-presence` for v2 and `stored-context-name-hints; not-key-presence` for v1.
Explicitly scoped unfiltered lookup retains its original-key-only behavior;
merging those results therefore need not reproduce default names. Default v2
names cannot be used to test whether a tenant has data.

This is **not five independent query budgets**. One million parent rows, **2M
work units across ALL five scopes**, 5000 distinct **scope/name pairs including
25 reserved intrinsic entries**, and independent 1 MiB dictionary/result limits
apply to the combined canonical result. Dictionary bytes include scope strings plus per-entry headroom; explicitly scoped
name queries now charge their scope bytes too and can reject slightly earlier
near that limit. The 25-entry reservation and scoped-pair accounting also apply before v1 flattens/deduplicates, so a small v1 result can
still fail. Empty resource/span/instrumentation owners alone cost three units
per parent; nested owners and all their attributes add work before filtering.
A key occurring in all five scopes costs five entries even when v1 emits it once;
only 4,975 entries remain for stored scope/name pairs. With 20 resource, 15 span
and two instrumentation attributes and no nested owners, each row costs 40 units,
so the work cap permits at most 50,000 parents even if the dictionary is tiny.
A combined query can fail where five separately admitted scoped queries succeed.
Adding static suggestions never bypasses storage, tenant/auth, admission, floors
or legacy/corruption checks: failure rejects the **whole** response, not a partial
intrinsic dictionary. Intrinsic-only requests remain independently storage-free.
No new storage format, mutable index or cross-instance authority is introduced.

### Grafana discovery transport parameters

Names endpoints accept and ignore `limit`, matching the pinned Tempo parser.
Values endpoints accept a decimal uint32 `limit` of at most ten bytes:
omitted, empty or zero means no output cap **within existing safety budgets**.
A positive limit caps the final values after the complete bounded scan and v1
conversion/deduplication; it does not reduce provider, row, dictionary or work
charges, suppress errors or authorize partial results. The
`x-pulse-trace-discovery-limit` header reports the effective policy.

Values endpoints also accept Grafana's redundant encoded `tag` query parameter;
the path target always wins, including when the two disagree. The datasource's
default `limit=5000` and retained `tag` no longer reject autocomplete requests.
Filter support is described above; transport compatibility does not establish
deployed Grafana acceptance. See the [actual pinned parser/HTTP
evidence](../test/fixtures/traces/tempo_integration/README.md#basic-same-span-search-and-discovery-transport).

Independent public Tempo execution establishes 15 combined cases: 12 exact, three
complete conservative supersets rather than upstream shared-key omissions. Actual
frontend HTTP handlers were also exercised on 90 requests with **owned stub
metadata responses**, proving version/omitted-empty-none-scope vocabulary behavior,
not a running datasource or real provider acceptance.

**Unscoped values** are available at `/tag/.shared/values` and MCP
`scope: "none", key: "shared"`. They union original typed values from **resource,
span and instrumentation only**, not event/link owners or intrinsic fields.
A bare `shared` is not a valid HTTP target; `.name` is an attribute named `name`,
while bare `name` means the stored intrinsic span name. Reserved legacy aliases
`.root.name` and `.root.service.name` reject rather than guessing trace context;
an original attr with that spelling remains available through an explicit scope.
No missing service.name column value is invented: this endpoint promises original
attributes, not materialized storage defaults or dynamic dedicated-column parity.
Paired time bounds select sources, not parent predicates, and also work here.

Unscoped values share a **single** 2M owner+attribute work budget across their three
owners, 5000 typed entries and independent 1 MiB dictionary/output bounds. The
owners' attributes are charged before selection even when the requested key is
absent; three empty owners cost three units per visible parent. This can reject
where separate scope queries succeed. Whole legacy/corrupt/scan failures remain.
Optional `q` / MCP `query` now accepts the same bounded resource/span original-string
AND equality/regex predicates, all on **one parent**. Once a parent matches, collect
that parent's resource, span and instrumentation values for the requested key.
This is a **complete filtered extension**, not parity with Tempo's mingled-condition
fast path that silently ignores the filter. Original typed values from other owners
need not equal a filter literal or match its regex: predicates select the parent,
not each returned value. No event/link value, intrinsic, name hint or missing
service.name default is invented. Equality on the requested key in any resource/span
namespace remains deliberately unsupported to avoid the upstream literal-shortcut
contract, not because other-owner values are impossible to compute. Same-key
original-string regex is the fast-path workaround. Instrumentation/nested/intrinsic
predicates use expression discovery; malformed/hinted/partial selectors still
reject, never degrade to unfiltered execution.

Every selected visible parent validates even when it does not match. All three
requested owners and **all their attributes** spend the shared work budget before
filtering, including absent keys, empty owners and repeated instrumentation. A
matching targeted bytes/array/kvlist/empty AnyValue fails whole with 422; unsupported
target types on proven nonmatching parents need not appear, but malformed or legacy
metadata always fails. Empty matches return an empty list only after the admitted
scan completes. Source routing/windows and raw provider/footer bounds are unchanged;
this does not use metadata search's service/ID optimizer.

Require discovery capability **13**, tuple **`{2,1,3,10,13}`**, across all serving apps
and native artifacts. Non-window adapters need explicit query-aware unscoped
execution or a bounded reference scan; old unfiltered callbacks cannot receive
queries. Windowed filtered-unscoped execution requires separate explicit support,
not an old window callback that predates this mode. Unsupported adapters reject.
Static/intrinsic and all other window modes retain their separate contracts.

Independent actual Tempo execution records **36 cases**: engine-selected parent
IDs plus original producer fields establish the complete three-owner result;
18 differ from the ignored-filter/raw dictionary and two reject matching complex
targets. Public protobuf decoders consumed all 34 successful cases in both v1/v2
(68 native-result messages). V1 can coalesce float/string spellings. These are
scoped helper/engine/decoder proofs, not deployed Grafana/frontend/provider parity.
Dynamic columns, exact upstream physical layout and full client acceptance remain
pending.

#### Filtered names are complete hints, not matching-key proofs

With a nonempty supported `q` / MCP `query`, generic names come from matching
parents in the requested scope. Fixed promoted-column hints additionally come
from **all retained visible context**, even if no parent matches:

| Scope | Global hint condition |
|---|---|
| resource | `service.name` whenever any visible parent exists, reflecting Tempo's required ServiceName column even without an original attribute |
| resource | Original string `cluster`, `namespace`, `pod`, `container`, `k8s.cluster.name`, `k8s.namespace.name`, `k8s.pod.name`, `k8s.container.name` |
| span | Original string `http.method` / `http.url`, or original int64 `http.status_code` |

Empty promoted strings still count; wrong-type originals remain generic and
only contribute when their parent matches. Instrumentation/event/link names have
no such global promotions: only requested-owner keys of matching parents contribute. Dynamic Tempo dedicated-column configuration is not
implemented. Expired rows cannot supply hints. An empty visible snapshot returns
no hints, including no `service.name`. Unfiltered names remain original keys;
**value discovery never inherits these shortcuts or invents values**. Adding a
filter can therefore add `service.name` to names that were absent unfiltered,
while a subsequent value lookup can still return `[]`.

HTTP coverage is `stored-context-name-hints; not-matching-key-presence`.
A listed key does not prove that any matching span, or even an original resource
attribute in the required `service.name` case, contains that key. Do not use
these dictionaries as data-presence tests.

Pulse deliberately returns an order/partition-independent **complete conservative
extension**, not exact Tempo name-iterator omission parity. Actual upstream
execution can drop shared keys after seeing them on earlier nonmatching rows.
Pulse retains every matching original key plus the fixed global hints. Independent
fixtures keep both raw upstream dictionaries and a complete oracle derived from
actual engine-matched span IDs and original producer attributes: 64 of 75 cases
are exact and 11 return additional complete keys. Public protobuf decoders also
consume all 75 complete responses. This does not establish full Grafana
Autocomplete compatibility; clients can receive more suggestions than Tempo.

Every retained tenant row is scanned, with the shared authoritative retention
floor hiding expired rows. There is no 65,536 trace-group cap because discovery
unions attributes directly, but **1,000,000 scanned parent rows**, an independent
**2,000,000 discovery work units per scan attempt** (one per visible requested-scope
owner plus one per attribute in that owner, charged before filtering), shared object/page/
byte/deadline/admission budgets, **5,000 distinct scope/name pairs or typed values**, a
**1 MiB charged dictionary** and an independent **1 MiB encoded result** ceiling
still apply. JSON escaping can exhaust output bytes before the dictionary cap.
Native set/node/scratch/Arrow/input/output allocations are outside BEAM heap
limits; these ceilings are not deployment-wide capacity guarantees. Neither a
selective filter nor a smaller result dictionary reduces scan/provider cost.
A filter can reduce dictionary size, never erase scanned-row or owner/attribute
work accounting. This work ceiling applies to all five scopes; dense rows can now
fail earlier even under the previous resource/span contract. For a flat owner
with `A` attributes per parent, capacity is at most `floor(2,000,000 / (1 + A))`
parents: about 95,238 at 20 attributes, 64,516 at 30, before other bounds.
Instrumentation attributes are charged again for every stored parent span even
when the original owner repeats across a batch; there is no deduplication or
identity inference. Exhaustion returns `422 trace_discovery_work_limit`, distinct
from row, dictionary and encoded-output limits. A fresh scan retry starts a new
work/dictionary budget; earlier provider/byte/row work remains cumulatively
charged under bounded retries. These are safety bounds, not a capacity improvement. Native validation and temporary
per-row parser allocations also remain outside the BEAM heap guard. Legacy history
can block unwindowed discovery indefinitely under retain-forever; a window only
helps if legacy sources do not select under the envelope contract below; do not guess original types,
rewrite compaction history or authorize deletion merely to make queries work.

Any selected visible legacy row fails the whole query with `409 trace_metadata_unknown`,
even if the target seems absent or a filter appears not to match. Every selected visible
row is validated before attribute filtering, so corrupt nonmatching context also fails.
Corrupt rows fail `500`; unsupported targeted
types and exhausted budgets fail `422`, availability `503`, admission `429`
and deadlines `504`. Failure detection stops at the first error, so when several
independent violations coexist, the tagged reason can depend on scan order.
No partial dictionary is returned. Retries use fresh native state and spent
scan work stays charged.

Independent fixtures come from **actual public Tempo v2.9.0 Parquet block
`SearchTags` / `SearchTagValuesV2` execution**, including int64 extremes, Unicode,
empty/absent values and bool/string spellings under one key. Ordinary replay
uses Elixir/Rust only. Additional actual `traceql.Engine.ExecuteTagValues` →
Parquet `FetchTagValues` execution establishes 18 filtered cases over three spans,
including sibling separation, cross-scope filters, original typed comparisons,
regex, int64 extremes, empty/absent values and no matches. A separate recorded
case demonstrates the upstream query-literal shortcut Pulse refuses. This is
scoped name/scalar and string-filtered-value subset evidence, not time-filtered
autocomplete parity, unsupported-type parity, deployed Grafana frames,
provider capacity, migration or cutover acceptance. An additional 68 actual
Parquet/engine cases cover all five scopes, shared keys with different owners,
multiple events/links under one parent, typed extremes/empty values and parent
filters. Actual public protobuf decoders also consumed all 68 current results.
Install matching native artifacts: discovery capability is **13** (startup
tuple `{2,1,3,10,13}`); no physical column changes are introduced. Upgrade/drain every
instance serving discovery before clients use event-time/filtered-unscoped/time-windowed/float/stored-intrinsic values through a shared pool.
Startup only checks the local artifact; it does not fence older running nodes.

### Time bounds select whole retained segment envelopes

HTTP names and values accept **both** `start` and `end` as positive uint32 decimal
seconds, ordered inclusively. MCP accepts paired positive int64
`start_ts_ns`/`end_ts_ns`. Omit both for the full-retained scan. Zero sentinels,
one-sided bounds, signs, decimals and reversed windows reject. **Discovery HTTP
seconds route whole-second envelopes:** `end=20` includes a source starting at
`20.5s`, equivalent to an upper bound of `20.999999999s`. Actual upstream
distributor start/end conversion and BlockMeta/frontend routing establish this
truncation contract. This intentionally differs from exact-end `/api/search`
trace metadata search. MCP nanosecond bounds remain exact, without expansion.

This is **block-oriented discovery, not strict span-start filtering**. Pulse reads
actual start/end columns of each immutable Parquet source and computes minimum
start / maximum span end of retention-visible parents. Select the whole source
when that envelope overlaps `[max(start, retention_floor), end]`; an empty visible
source or `end < floor` never selects. Every retention-visible parent in a selected
source contributes, including outside-window parents and gaps with no span in the
window. Expired starts never contribute or widen envelopes. Long spans can select
sources even when every start precedes the window; neither manifest max-start
fields nor footer time statistics substitute for reading actual end columns.

Results depend on **Pulse's segment layout**: separate objects can yield no gap
suggestions while a merged object does. Compaction/coalescing can broaden dictionaries **or turn success into `409`** by
merging previously excluded legacy context into a selected source. Newly selected
corrupt payloads fail `500`; compaction itself rejects corrupt sources rather than
publishing them.
Actual Tempo also routes whole blocks, but its blocks/lifecycle/cache can differ.
Independent frontend routing helpers cover five inclusive/exclusive boundaries;
actual public Parquet lookup supplies the selected-block values. These composed
fixtures are not full HTTP frontend/provider execution, proof of automatic
upstream metadata construction, identical physical-layout or deployed parity.

Temporal routing precedes typed payload validation. Every selected visible parent
validates even under an impossible attribute predicate; selected legacy/corrupt
rows fail whole. Valid legacy sources outside the selected envelope no longer
block a newer typed window. **Unselected payload metadata is not decoded: this
is not an integrity scrub of excluded payloads.** Every source must still have required trace-ID/payload Utf8 columns and its time
columns must be nonnull int64, with nonnegative start and `end >= start`. Malformed
headers, provider errors and exhausted bounds fail the whole request, even when
the source would not select.

This is **not indexed I/O planning**. Every retained source is still fetched;
every actual raw header row charges provider/byte/one-million-row budgets, even
when nothing selects or manifest counts lie. Narrow windows do not reduce this all-source native header decoding, GET count
or bytes. Selected sources add a second local
Arrow pass over the **same immutable admitted binary**, never another GET. The
2M owner+attribute work budget applies to selected context before attribute
filtering. Both passes/parser/Arrow/native memory remain outside BEAM heap limits;
per-instance bounds do not establish deployment capacity. No cross-window value
cache is used: each request uses its admitted snapshot and fresh counters.

Default v2 names retain static suggestions when nothing selects; failures never
become partial suggestions. Explicit static vocabulary stays window-independent,
authenticated/admitted and storage-free. `X-Pulse-Trace-Discovery-Window` reports
`retention-visible-segment-envelope; not-span-time-filter` for windowed data,
`static-protocol-vocabulary; window-independent` for windowed static vocabulary,
and `all-retained` for unwindowed stored-data requests. Static-only vocabulary
reports its window-independent mode even without a window.

Storage adapters need explicit window-aware execution. The established window
callback handles default five-scope names/static seeds, **unfiltered** three-owner
values, filtered scoped names/values and stored intrinsic strings. New filtered
unscoped values and event-time offsets each require their **own dedicated window
support**; they never pass through that older generic callback. Non-window callback
support does not establish window support. Flat-record/old adapters reject rather
than ignore time or invent segment boundaries. There is no storage-format or
mutable coordination change. Upgrade/drain **every** serving app/native participant
to capability **13**, tuple **`{2,1,3,10,13}`**, before use.

### Stored intrinsic string values

Seven canonical intrinsic targets now read stored fields under the same default-off
gate, authentication, raw admission and retained-snapshot/floor guarantees:

| Targets | Effective stored string |
|---|---|
| `name`, `span:name` | Span name |
| `statusMessage`, `span:statusMessage` | Status message |
| `instrumentation:name`, `instrumentation:version` | Instrumentation scope fields, not attrs |
| `event:name` | Each event's name, not a flattened span attribute |

Use the bare canonical target in HTTP `/api/v2/search/tag/<target>/values`, or MCP
`scope: "intrinsic"` and exact `key`. V1 uses the same canonical target semantics
in a legacy string-list **envelope**; this is not compatibility with Tempo v1's
older alias/original-attribute interpretation. Static v1 keyword shortcuts remain
rejected to avoid that conflation; they are not stored-field reads.

Missing protobuf string fields use their effective `""` default; no events means
no event-name values, not a fabricated empty event. These are not original
attribute-presence proofs. Filtering accepts the normal bounded resource/span
original-string AND predicates on **one parent**; it does not enable intrinsic
predicates or allow event/link attributes to satisfy the filter. All matching
field strings are returned even when upstream distinct iterators omit later
matching duplicates. Independent producer evidence preserves both raw and complete
answers: 30 of 42 cases are exact, 12 are deliberate complete supersets, established
from actual engine-matched IDs and original producer fields, not Pulse expectations.
This is a disclosed complete-value extension, not raw omission parity.

All visible rows/envelopes validate before predicates. Any legacy uncertainty,
corruption, storage failure or exhausted bound rejects the whole response; there
is no static fallback. Work charges before filtering: one requested owner plus
its attrs for span/scope fields; event names charge one parent **plus every event
and its attrs**. The same 2M-work, one-million-row, 5000-entry and independent
1 MiB dictionary/output limits apply, including empty/false-filter scans. Predicate
map construction and full envelope validation are not instruction-counted by that
requested-owner counter; native/parser scratch and aggregate node CPU/memory still
require capacity validation. These are not node-wide admission guarantees.
HTTP coverage is `stored-intrinsic-values; exporter-completeness-unknown`.

Actual public Parquet/engine execution also establishes 20 unfiltered/scalar cases
and 273 finite IEEE spellings including both zeros, subnormals and exponent edges.
Public protobuf decoders consumed all 62 current native-result Elixir responses
in **each of v1 and v2** (124 wire messages). This verifies envelopes and values,
not legacy v1 target-alias interpretation.
These are repository interoperability fixtures, not running Grafana acceptance.
Root/service-root/trace-duration dictionaries use the separate context paths below;
unknown targets fail, never guessed empty. No storage format changes are required.

### Stored event-time offsets are integer nanoseconds

`GET /api/{v2/}search/tag/event:timeSinceStart/values` and MCP intrinsic key
`event:timeSinceStart` now read each event's timestamp minus its **own parent
span's source start**. V2 emits type **`int`**, with exact signed decimal
nanoseconds, matching actual unfiltered Tempo Parquet value discovery. These are
**not duration strings**, float milliseconds, source-clock corrections or an
original AnyValue attribute. V1 wraps the same canonical values as strings, not
old target-alias behavior. `event.timeSinceStart` remains an original event
attribute, never this intrinsic.

Nonnegative int64 source times make the subtraction exact without overflow;
negative offsets (an event before its parent start) are valid. Ingest normalizes
an omitted protobuf event time to an **explicitly stored zero**, so it can yield
a negative offset (minus the parent start), not an invented zero offset. A missing stored timestamp
is malformed and fails rather than guessing that default; null, string, float,
exponent, negative and out-of-range stored fields also fail. No event means **no
value**. Event clock accuracy, exporter completeness and nonnegative offsets are
not promised. Both actual source time fields must be valid, even on a parent
proven not to match. Legacy metadata remains unknown. Values sort **lexicographically,
not numerically** (`"10"` precedes `"9"`); equal offsets across events/parents
coalesce as dictionary entries in both versions. V1 is a string list, not counts
or event provenance.

Optional bounded original-string resource/span AND filters select **one parent**
before collecting all its event offsets. This is a **complete filtered extension**:
actual Tempo's public parent-filtered event-time path returned empty results for
five nonempty fixture selections. We do not copy that omission or claim filtered
backend parity. Intrinsic/event predicates use expression discovery; hints,
partial grammar and type coercion still reject. Fast-path work charges
**one parent plus every event and its attrs
before filtering**, even an empty event list/impossible predicate; 2M work, 1M
raw rows, 5000 typed values and independent 1MiB dictionary/result limits remain.
Window bounds select whole **parent-span source envelopes**, not event times;
events need not be inside the span or request window. Coalescing/compaction can
broaden values as it does other discovery. Raw provider/header costs remain,
excluded payloads are not integrity-scrubbed, and no service/ID plan is used.

**Expect high cardinality:** nanosecond offsets can be nearly unique per event.
An unfiltered retain-forever dictionary will commonly exceed 5000 distinct values
and return **422**, not partial suggestions, sampling or corruption recovery.
Use a selective parent filter and a narrow source window; this is not a guarantee
because windows include whole sources and compaction can broaden them. Filters
reduce returned values but **not** requested-owner work or provider/header costs.
Inspect the tagged reason: dictionary/row/work exhaustion is not stored corruption.

Requires current discovery **13**, tuple **`{2,1,3,10,13}`**, on every serving app/native
participant. Explicit event-time execution or a bounded reference is required;
old stored-string callbacks cannot receive the new target. Windowed event-time
execution needs separate explicit support and cannot use an old generic window
callback. Missing support rejects, never returns static empty vocabulary. No
new format or authority is introduced; rollback must keep matching artifacts.

Independent actual public Tempo v2.9.0 block/engine execution covers **280 parents,
seven cases**: one exact unfiltered integer dictionary, five complete filtered
supersets over actual engine-selected parent IDs/original timestamps, and one
empty selection. Actual public protobuf decoders consumed **14 current native-result
v1/v2 messages**. Owned HTTP tests cover gzip→four S3 objects→restart→both versions,
MCP/exact-nanosecond windows, auth, parent filters and footer rejection. Native/
reference tests vary layouts/repetition and reject unknown/corrupt nonmatches,
2M prefilter work and 5001 entries. These fixtures are not deployed datasource,
physical block layout, real provider/capacity or cutover acceptance.

### Complete retained root names and services

Canonical HTTP targets `rootName` / `trace:rootName` and `rootServiceName` /
`trace:rootService` now return typed **string** dictionaries. MCP uses these keys
with `scope: "intrinsic"`. Both v1 string lists and v2 typed values use the same
canonical semantics, not historical unscoped alias behavior. `.root.name` and
`.root.service.name` remain rejected reserved aliases; explicit scoped attributes
with those spellings are still just original attributes.

Optional `q` / MCP `query` uses the same bounded original-string resource/span
AND equality/anchored-regex predicates. A matching **parent span selects its trace**;
then recover all retained spans for that ID before proving its root. The root
need not match the predicate or belong to the selected source envelope. This is
not returning a child span's own name/service or the first span encountered.
Intrinsic/nonstring predicates use expression discovery; structural predicates
remain unsupported.

A root has no parent ID and no original string `opentracing.ref_type="child_of"`
link. Identical root copies with the same span ID/name/original service coalesce.
Two different root IDs, differing root name/service tuples, or the same ID
classified both as root and non-root fail the **whole response with 409**. A
selected trace with no retained root also fails 409 (`trace_root_unknown`). Root
service discovery additionally requires an original **string** `service.name` on
that root. An absent/nonstring attribute does not become `unknown_service`, a
promoted column default or an empty guess. A proven empty string is a value;
protobuf's normalized empty span name remains a valid name. These checks establish
root evidence only, not faithful export, every span-ID conflict or exporter completeness.

**Operational limitation:** this strict fail-closed policy is intentional, not a
skip-incomplete mode. Children commonly arrive before their root finishes/exports,
so live/recent dictionaries can return 409 during ordinary ingestion. Retention
also removes roots by span start while leaving later children, and multi-root
instrumentation fails the dictionary even if both roots have equal names. Narrow
parent filters and source windows ending sufficiently before now and away from
the retention floor can help, but do not guarantee success: no completeness
watermark is available and compaction broadens source envelopes. An unfiltered
tenant dictionary may be unusable until such cases are excluded by an explicit
supported selector. Pulse never silently drops those traces or returns partial
suggestions. Do not enable this as a transparent production autocomplete replacement.

Windows select candidate **sources**, using the same HTTP final-whole-second and
MCP exact-nanosecond bounds described above, then recover complete retained context
without a trace-time postfilter. Window responses declare
`X-Pulse-Trace-Discovery-Window: retained-source-candidates-with-complete-trace-context; not-trace-time-filter`
and all root responses declare
`X-Pulse-Trace-Coverage: complete-retained-trace-roots; exporter-completeness-unknown`.

**S3 capacity is whole-retained-tenant, not window-sized:** every retained source
is fetched and captured, at most **1024 objects / 32 MiB compressed / 1,000,000
actual source rows**. Larger retained inputs reject even for a tiny window or
empty selector result. Root discovery does not use metadata search's service/ID
planner. Captured immutable bytes replay locally without a second GET. With any
candidate, replay decodes all retained sources' Arrow columns, even unselected
ones; noncandidate JSON metadata is not integrity-scrubbed. Body/header row counts
are cross-checked for every replayed source. Native replay has a separate 1M-row
ceiling. All raw provider/header costs remain charged.

Candidates cap at 65,536 trace IDs; root bookkeeping has an independent 16 MiB
charge ceiling outside the BEAM heap guarantee. Work is **2 + resource attributes
+ span attributes + each link owner and its attributes** per visible selected-source
parent, charged before its predicate. Candidate context recovered from unselected
sources spends the same work once; already-selected rows are not charged twice.
The global **2M work / 5000 values / independent 1 MiB dictionary and encoded-result**
limits still reject whole requests. Filters do not evade prefilter work or raw I/O.
No native bound is a node/deployment-wide capacity guarantee.

Requires current discovery **13**, tuple **`{2,1,3,10,13}`**, across every serving
app/native participant. New explicit root execution or bounded complete reference
is required; windowed roots need dedicated window-aware support with source
boundaries. Old span-local string or generic window callbacks never receive
these targets. Flat references reject windows and use a sentinel against record
truncation. No new storage format, mutable authority or migration is introduced.

The pinned public Tempo v2.9.0 producer records **44 cases** over four targets:
22 successful dictionaries exactly match the exercised public block results;
22 deliberately reject missing/ambiguous roots or missing original root service
instead of adopting upstream empty/default/arbitrary-root behavior. Expected
complete sets use actual engine-selected trace IDs plus original source fields.
This is scoped fixture evidence, not general physical-layout, running datasource,
provider/capacity or cutover parity.

### Complete retained trace-duration values

HTTP `GET /api/{v2/}search/tag/trace:duration/values` and MCP intrinsic key
`trace:duration` now discover **max retained span end minus min retained span
start**, after selecting trace IDs through optional same-parent original-string
resource/span equality/anchored-regex AND filters. All retained candidate context
is recovered before aggregation, even outside predicates/source windows.

**The wire vocabulary depends on filters**, following the exercised upstream paths:

- Absent/empty/`{}` query: v2 type **`int`**, exact decimal nanoseconds, e.g. `1500000`.
- Any supported nonempty parent filter: v2 type **`duration`**, integer-only Go
  `time.Duration.String` text, e.g. `1.5ms`, `1µs` (U+00B5), or `1h0m0s`.
- V1 returns those same spellings in its legacy string list. Both forms sort
  **lexically**, not numerically, and equal values coalesce without provenance.

Clients must not reuse/cache an integer dictionary as a filtered duration-string
vocabulary. No float milliseconds, precision rounding or 32-bit-ms clamping is
used: nonnegative signed-int64 source times subtract without overflow. Missing
stored timestamps, invalid core headers and unknown legacy metadata fail whole,
including nonmatching parents in selected sources. Unsupported intrinsic/nonstring
predicates and hints reject; they never become unfiltered scans.

**Retained duration is not exporter duration.** Unlike root discovery, missing or
ambiguous roots do not prevent a retained envelope from being measured. In-flight
spans arriving later can widen it; retention can shorten it by removing the earliest
span, even while that expired row is physically still in a source. There is no
completeness watermark or inference of missing spans. A successful response can
therefore be shorter than the eventual/full exported trace. It declares
`X-Pulse-Trace-Coverage: complete-retained-trace-duration; exporter-completeness-unknown`.
Window responses use the same complete-trace-context source-window header as roots;
this is not trace-time or matching-span-only filtering.

As with roots, **all retained S3 inputs** must fit 1024 sources / 32 MiB compressed /
1M actual rows regardless of window/matches; every admitted source replays locally
without another GET or service/ID planner, with body/header row-count agreement
and an independent 1M replay-row cap. Arrow decoding can touch noncandidate sources;
noncandidate JSON is not integrity-scrubbed. Candidate IDs cap at 65,536, with an 80-byte
summary charge per trace under an independent 16 MiB charge ceiling, not a total
native-memory/BEAM guarantee. Input/group/Arrow/parser/container overhead remains
separate. Work is **2 + resource attributes + span attributes** per selected-source
parent before filtering and once on additional candidate context. Events/links
are not requested owners for this duration mode; all typed envelopes still validate.
The global 2M work / 5000 values / independent 1 MiB dictionary and encoded-result bounds
reject whole requests, never sample or truncate.

**Expect high cardinality:** nanosecond durations can be nearly unique; broad or
retain-forever dictionaries commonly fail 422 above 5000. Selective parent filters
and narrow source windows can help without a guarantee, and do not avoid raw
provider/header costs or prefilter work. Compaction can broaden candidate sources.
This is not representative indexed capacity or transparent production autocomplete.

Current discovery **13**, tuple **`{2,1,3,10,13}`**, is required across every serving
app/native participant. New explicit trace-duration execution or a bounded complete
sentinel reference is required; windows need dedicated support preserving source
boundaries. Old root/string/generic-window callbacks never receive this mode.
Flat references reject windows. No new storage format or mutable authority.

This does **not** change the v2 static empty vocabularies `duration`, `span:duration`
or `traceDuration`; those are protocol suggestions, not stored span-duration data.
Only canonical `trace:duration` is newly data-backed. Public Tempo 2.9 execution
establishes six exact dictionaries over 280 traces / 560 spans, including rootless/
multi-root traces, zero, values beyond 2^53 and signed-int64 boundaries. Go supplies
1047 boundary/randomized formatter spellings independently replayed in Rust/Elixir.
This is scoped evidence, not generalized physical-layout/deployed-client parity.

### Static intrinsic vocabulary

The discovery gate also enables explicit `scope=intrinsic` name lookup on both
`/api/search/tags` and `/api/v2/search/tags`, and the same MCP scope. This returns
Tempo's 25 intrinsic names as **protocol vocabulary**, not evidence that a tenant
has those fields. Selecting suggestions does not broaden the supported grammar.
The single-spanset builder forms are supported as described above. In particular,
`link:spanID`, `link:traceID`, `span:id`, `span:parentID` and `trace:id` are name
suggestions whose value requests now scan stored IDs. Canonical intrinsic targets
route to these dictionaries; arbitrary v1 bare keys retain attribute lookup.

The vocabulary follows the pinned newer Tempo integration profile, superseding
the 20-name v2.9 snapshot. Combined default discovery reserves all 25 entries
inside the existing global 5,000-pair ceiling, even for v1 before intrinsic names
are removed from the response; near-cap requests can therefore reject five keys
earlier. With only the required resource `service.name` hint, 4,974 distinct span
keys fit and 4,975 reject whole. Upgrade all query-serving applications and their
native artifacts together for consistent names and admission. The current native
tuple is `{2,1,3,10,13}`; storage/keyed bytes, overall dictionary/byte/work ceilings
and seven static value vocabularies are unchanged. No stored-data migration or
keyed-retry drain is required for this read-only increment.

V2 static value lookup accepts these canonical targets (without an attribute-scope
prefix), for example `/api/v2/search/tag/span:kind/values`:

| Target | Static result |
|---|---|
| `status`, `span:status` | `keyword` values `error`, `ok`, `unset` |
| `kind`, `span:kind` | `keyword` values `client`, `consumer`, `internal`, `producer`, `server`, `unspecified` |
| `duration`, `span:duration`, `traceDuration` | Empty value vocabulary; not an assertion that stored durations are absent |

MCP `discover_trace_tag_values` uses `scope: "intrinsic"` and the exact target as
`key`. The seven stored string targets and integer event-time offsets above use
separate data scans, not these shortcuts. Root fields, canonical `trace:duration`
and the five IDs likewise use the stored-data paths described above.
Dotted attribute targets such as `span.kind` remain original stored attributes,
not intrinsic keywords. `intrinsic.kind` is not an HTTP target alias.

These dictionaries require authorization, a valid tenant, the default-off gate
and ordinary query admission, but perform **no storage I/O**. Under query load,
HTTP vocabulary polling can still receive `429` (MCP `query_overloaded`); static
lookups are not an admission bypass. They remain static
even when the tenant has no data, legacy metadata or unavailable storage; they
are not stored-value proofs. HTTP coverage is
`static-protocol-vocabulary; not-stored-values`. Valid nonempty `q`/MCP `query`
filters are validated but do not restrict static vocabulary; malformed,
structural, selected or hinted filters reject. Absent, empty or exactly `{}` is
unfiltered. Valid paired time bounds
are window-independent here, not stored-data evidence. V1 value
shortcuts reject because that protocol conflates attributes with intrinsics;
its explicit intrinsic-name lookup and the canonical stored string-list envelopes
above are separate from static keyword shortcuts.

The 2M work/row/dictionary limits above govern stored-attribute discovery, not
this tiny fixed vocabulary. Values sort lexically, provider metrics are omitted,
and known empty repeated fields use `[]`. Actual public Tempo querier execution
without backend clients established the seven v2 static shortcuts and public
protobuf decoders consumed all eight name/value responses. This is not a running
Grafana/Tempo deployment acceptance result. Upgrade every instance serving
discovery before clients use the new mode in a shared pool. Matching native
artifacts require tuple `{2,1,3,10,13}`; static vocabulary itself does not alter
native or storage formats. Startup does not fence older application nodes.

### Tempo v1 trace lookup

`GET /api/traces/<trace-id>` returns a bounded Tempo v1 trace body. Authenticate
with the tenant bearer token and `X-Scope-OrgID`; if the tenant header is absent,
it uses `default`. IDs accept 1–32 hex digits, pad on the left to 32, normalize
case and reject zero/invalid IDs. Repeated or empty tenant headers reject.
Expose `/api/traces` and `/api/v2/traces` as **Prefix** ingress routes if these
APIs are needed; neither is covered by `/api/v1`.

With `Accept: application/protobuf`, the response is the `tempopb.Trace` wire
shape (field 1 repeated OTLP ResourceSpans). JSON is the default, using Tempo
v1's historical **`batches`** root. IDs in this response are **base64**, not the
hex convention of OTLP/HTTP JSON ingest. Times and AnyValue int64 values are
quoted decimal strings, kind/status enums use names, and original typed
resource/scope/span/event/link values, flags, schema URLs and dropped counts
are retained. Identical resource/scope/schema owners are grouped losslessly;
owner identity includes typed values and their pair order, not just promoted
service/query projections. Spans remain ordered deterministically within owners.
Do not feed the JSON response directly to `/v1/traces` without converting IDs.

`GET /api/v2/traces/<trace-id>` applies the same completeness, auth, bounds and
error contract, but returns `TraceByIDResponse`: protobuf wraps the Trace as
field 1; JSON uses `{"trace":{"resourceSpans":[...]}}`. Its omitted/default
`status` is protocol `COMPLETE` **for the stored query**, not exporter completeness
or pre-retention coverage. Failed/oversized queries never become `PARTIAL`
success. Query metrics are omitted/unknown rather than inventing inspected byte
counts. Public Grafana v12.3.0's datasource requests v2 with exact
`Accept: application/protobuf` and falls back to v1 only on 404; both paths now
have local HTTP/S3 and independent serialization fixture coverage. This is source
and local contract evidence, not deployed-client acceptance. Actual public Grafana
v12.3.0 `TraceToFrame` and search transformation functions have also consumed the
current Pulse protobuf and independent expected responses in an isolated one-off
consumer harness. One rich lookup and eight search cases produced equal actual
frames, including nested spans and empty tables. This is conversion-function
execution, not a running Grafana datasource/browser, autocomplete, deployed
version or operational acceptance.

```sh
curl -H 'Authorization: Bearer <token>' -H 'X-Scope-OrgID: example' \
  -H 'Accept: application/protobuf' \
  'https://pulse.example.com/api/traces/0123456789abcdef0123456789abcdef'
```

`start` and `end`, if supplied, are decimal uint32 **seconds** and checked for
order. They are routing hints in this lookup contract, not span filters: Pulse
always reads all visible stored spans for that ID, including outside those
hints. Only `mode=all` (default) and `allowPartialTrace=false` (default) are
accepted. Ingesters/backends-only modes, block UUID selectors, error-truncated output
and unknown query parameters reject rather than approximate another backend.
Exact `Accept: application/protobuf` selects protobuf; JSON/no Accept/`*/*`
or a single explicitly empty `Accept` value selects JSON. Unsupported media
types return 406; protobuf quality/list variants are not yet negotiated like a
general-purpose HTTP server.

V2 additionally accepts an explicit same-span `q` filter using the documented
[bounded expression grammar](trace-query-expressions.md): original resource/span
strings and int64s, status, own-span duration and boolean groups. An unscoped
key uses span-over-resource presence precedence. Structural/spanset operations
remain unsupported. An omitted/blank `q` ignores filtering options; `{}` matches
every span. Filters do not change time-hint semantics or reduce storage reads.

- `match_depth` includes descendants of each match: default `0`, `-1` unbounded,
  or a nonnegative signed-int64 hop count.
- `keep_hierarchy=true` includes ancestors: `ancestor_depth` defaults to `-1`,
  or accepts the same hop counts. Without hierarchy, this parameter is ignored,
  even if malformed. Ancestor and descendant expansion start independently at
  matches; including an ancestor never pulls in its other children.
- If filtering removes any unique stored span, HTTP 200 carries `status: PARTIAL`
  and a message identifying the explicit subset. No matches produce an empty
  trace with `PARTIAL`, not 404. Selecting the whole trace retains the protocol's
  omitted/default `COMPLETE`. V1 does not accept these filter parameters.

The complete trace is loaded, deduplicated and validated **before filtering**:
nonmatching legacy/conflicting copies still return 409, and malformed stored
owners, spans, events or links still return 500. Incomplete reads and exhausted
budgets never become a partial success. Filtering expands the bounded assembly
into the supervised task's BEAM heap, unlike native unfiltered export. All stored
fields undergo type, range and ID validation before selection, but only selected
spans become export maps and encoded timestamps/IDs. There is no discarded full
conversion pass or second whole-trace response binary. Protobuf encoding packs
each span individually instead of retaining every span's complete nested
intermediate tree until the response is finished. Account for the memory and
CPU of decoding and validating the complete assembly even for empty results.
Expression evaluation charges all spans under the existing 20-million-work
ceiling. Each directional graph walk visits each ID/edge at most once, tolerates
cycles and never invents missing parents.
The 5,000-stored-span and 16 MiB assembly/key/result bounds remain; a small
selection cannot make an over-budget trace readable. The HTTP request-line
ceiling may reject a large URL with 414 before query parsing returns 400.
Upgrade all query-serving applications before clients rely on filtering under
non-sticky routing; older applications reject these parameters. Filtering
itself changes no stored bytes or native capability requirement.

Lookup uses the same admitted, supervised all-stored assembly as `get_trace`:
maximum 5,000 stored spans, independent 16 MiB payload/key/result budgets, shared
scan/deadline/heap limits and authoritative retention floor. It never truncates
an oversized trace. A second 16 MiB owner-key budget bounds grouping; protobuf
uses resource-local scratch and bounded message-size plans. Native memory is
outside the BEAM heap cap: account for assembly/input binaries, full/owner keys,
output, scratch and plans in per-instance capacity, not just task heap words.
Admission and aggregate provider pressure remain per-instance/deployment concerns.
Grafana's v2-then-v1-on-404 fallback can scan a missing trace twice; account for
negative lookups and native-plan fallback work when sizing query/provider capacity.

- **200:** every visible stored span can be represented faithfully. Exactly
  identical known copies under one span ID are deduplicated in this compatibility
  response only. V2 can then return an explicitly filtered subset as above.
  `get_trace` still preserves all duplicate rows and diagnoses them.
- **404:** successful complete stored lookup found no span at the retention floor.
- **409 `trace_metadata_unknown`:** any legacy/nil copy prevents faithful export,
  even alongside a projection-identical rich copy. Compaction cannot infer types.
  Use `get_trace` for native legacy diagnosis, or keep the existing backend for
  historical client access; do not guess byte/string types.
- **409 `trace_span_id_conflict`:** different known full copies share a span ID.
  Pulse does not silently choose a copy or rewrite IDs/parents. In particular,
  Tempo/Zipkin client-server shared-span-ID rewriting is **not** implemented.
- **400/401/406:** invalid/unsupported parameters or tenant, unauthorized access,
  or unsupported response format.
- **422/429/504:** complete lookup exhausted safety bounds, admission is busy
  (`Retry-After: 1`), or the query timed out. No partial trace is returned.
- **500/503:** malformed stored export data/internal failure versus unavailable
  storage authority/provider. Neither returns a clipped success.

`X-Pulse-Trace-Coverage` states all visible stored spans, or an explicit filtered
subset, and unknown exporter completeness. Retention can remove early spans/roots; this header does not claim
an exporter-complete or pre-retention trace. These lookup APIs are not Tempo search/tag compatibility,
full shared-span-ID handling, Grafana datasource validation or production readiness.
Lookup always emits a status message, including empty `{}` / zero-length protobuf
status for UNSET. Actual Tempo v2.9.0 stored Parquet conversion materializes this
message; Grafana v12.3.0 dereferences it and crashes on a missing status. Default
code/message semantics are unchanged, and rich AnyValues stay lossless on Pulse's
wire. The client conversion itself is not lossless: this Grafana version renders
bytes as empty string, projects nanosecond times to float milliseconds and exposes
large int64s to downstream JavaScript-number limitations. Keep Pulse metadata/wire
as the fidelity boundary rather than treating a frame as an original OTLP record.
Install matching native artifacts: complete-context search capability is **10**
(metadata 2/export 3/discovery 13), tuple `{2,1,3,10,13}`. Startup checks reject
previous bindings; unscoped search adds no storage-format change. Upgrade or drain **every node serving
Tempo endpoints** before pointing Grafana at the pool: a rolling mix with the
previous exporter can still omit default status and intermittently crash client
conversion. Startup checks only the local artifact; they cannot fence old nodes.

Independent protoc wire and public Tempo v2.9.0 jsonpb fixtures establish the
bounded serialization slice only; live deployed-version/SDK/client/load/restore
acceptance remains required. Matching native export artifacts are required at
startup, and the all-participant typed metadata upgrade boundary still applies.

### Search distinct traces

`search_traces` requires `tenant`, `query`, `start_ts_ns` and `end_ts_ns`.
Times are nonnegative signed-64 nanoseconds. The inclusive window selects by
**span start**, not span-end overlap. `limit` defaults to 100 and accepts 1–1,000
**distinct traces**, never spans.

Accepted syntax is one nonempty selector with 1–16 `resource.<key>` or
`span.<key>` predicates, string `=` or fully anchored string `=~`, joined by
`&&`. Attribute keys start with an ASCII letter/underscore and contain ASCII
letters/digits, dots, underscores or hyphens. Quoted attribute identifiers,
nonstring literals, negative predicates, OR, intrinsics, pipelines, structural
operators and other hints are unsupported and reject. A selector may end with
`with (most_recent=true)`; omission uses the same native deterministic ordering.
No client variables are expanded: `${environment:regex}` must be expanded by
the client before it reaches Pulse.

```json
{
  "tenant": "example",
  "query": "{ resource.service.namespace = \"example\" && resource.service.name = \"api\" && resource.deployment.environment =~ \"(production|staging)\" } with (most_recent=true)",
  "start_ts_ns": 1700000000000000000,
  "end_ts_ns": 1700000300000000000,
  "limit": 100
}
```

All predicates must match **the same stored span**, against its original typed
string values. A byte value never matches an identical base64 string, and bools,
integers, arrays and missing keys do not become strings. Regex is dot-all and
fully anchored, using the bounded RE2-compatible subset described below. Input
is at most 16,384 UTF-8 bytes, keys 256 bytes, exact literals 4,096 bytes, regex
patterns 1,024 bytes and at most eight compiled regex programs.

Trace regex predicates share the [query regex profile](querying.md#shared-query-regex-semantics),
including `\Q...\E` literal quoting and Unicode-valued octal escapes. An omitted
terminal `\E` does not weaken whole-value anchoring. These forms also work in
retained-context search, filtered discovery and raw trace regex filters, within
their existing feature gates and input/resource bounds. Counted bounds and
nested products follow Go's 1,000-copy limit; malformed or leading-zero counts
are literal text, not quantifiers. Repeated `&&` and `~~` inside classes are
ordinary members, never Rust set operators. Opening brackets are literal class
members except in complete POSIX named classes; hyphens form Go's left-to-right
scalar ranges, not set subtraction. Invalid ranges and raw capture/modifier
headers reject before literal decoding. Empty/repeated inline flags retain
scope, atom binding and greediness. Numeric/repeated capture names and
flag-separated repetition of already quantified atoms remain unsupported.
Upgrade every serving
app/native pair; no trace capability tuple, storage format or keyed bytes change.

The native search visits every candidate object in the admitted snapshot and
groups **all** window spans by trace ID, including nonmatching context. Only
then does it select matching traces and apply the trace limit. One trace with
5,001 matching spans cannot hide a second trace. Results order by the earliest
**window-stored** span start descending, then trace ID ascending. Each row has
`trace_id`, `start_timestamp_ns`, `end_timestamp_ns`, `duration_ns`,
`stored_span_count` and `matching_span_count`. Counts preserve duplicate rows;
end is the latest stored end, so it can exceed the window end. The envelope
reports `matched_trace_count` before the limit, `effective_start_ts_ns`,
`end_ts_ns` and `coverage: "window_stored_spans"`.

**This is a native window-local contract.** It is not Tempo's trace-wide start,
duration, root metadata, spanset sampling, time-overlap or `most_recent`
implementation. Roots or spans outside the start window are not fetched.
Retention raises the effective start to its authoritative floor. Coverage is
acknowledged stored data in that snapshot/window, not exporter completeness or
an atomic snapshot across tenants/signals. Use `get_trace` for all-stored exact
ID assembly; Tempo APIs/client compatibility and discovery remain unimplemented.

#### Search failures and window sizing

- **`:trace_metadata_unknown`:** any scanned in-window legacy/nil envelope fails
  the entire search, even on a nonmatching span. Pulse cannot prove original
  string versus bytes from old projections. Compaction preserves that unknown
  state; it does **not** upgrade old types. An existing bucket may therefore be
  unable to search windows before its typed-writer cutover indefinitely when
  retention is disabled, or until retention removes that history. Choose a
  window entirely after all writers were upgraded, or keep the existing backend
  for historical typed search. Do not delete history or guess/backfill types to
  make a search succeed.
- **`:trace_group_limit`:** all distinct stored trace IDs in the window count
  toward the fixed 65,536 group ceiling, including traces that do not match.
  Narrowing the selector alone does not reduce this cost. Narrow the **time
  window** instead. A rough upper bound is `65,536 / new_trace_ids_per_second`
  seconds, with headroom for bursts and traces crossing the boundary. At 100
  new trace IDs/second, even an approximately eleven-minute window can exhaust
  it. Measure stored cardinality; this formula is not a capacity guarantee.
- **`:query_scan_limit`:** whole-snapshot and actual segment/byte/row budgets
  apply, including retries. Native search additionally caps scanned rows at
  1,000,000. A small result limit does not permit a partial scan. Managed page
  collection is bounded by the segment cap too. Footer counts are charged before
  native row expansion, including when old manifest counts are absent or wrong.
- **`:query_resource_limit`**, timeout, malformed metadata and missing objects
  are whole-query failures, never clipped aggregates. Group state is disposable
  and poisoned after a native failure. Results are bounded fixed-width IDs and
  integer aggregates (less than 1 MiB at 1,000 traces), not full span payloads.

Search shares ordinary interactive/raw admission, task/heap/deadline and S3
snapshot/retry behavior. These bounds are per instance, not deployment-wide
provider admission. No trace postings/indexes or scale/readiness claim is added.
Matching native artifacts are required; stale search artifacts fail startup.

### Query spans

`query_traces` takes `tenant` plus any of:

- `trace_id`, `span_id`, and/or `parent_span_id` for exact lowercase or uppercase
  hex lookup. `root_only: true` selects spans without a parent. It does not mean
  every server request: a server span with a propagated remote parent is not a
  root. Use `kind: 2` for server requests.
- `service`, `name`, `kind` (`0` unspecified, `1` internal, `2` server,
  `3` client, `4` producer, `5` consumer), or `status_code` (`0` unset,
  `1` OK, `2` error).
- `attributes` and `resource` maps for exact **query-projection typed** matches.
  These retain the existing normalized semantics, not strict OTLP type predicates:
  bytes and strings with identical base64 text share the projection. Inspect
  `otlp` to distinguish their original type on new records. All entries and
  all filters are combined with AND. A missing attribute does not match null;
  an integer attribute does not match a string or a floating-point value.
- `attributes_regex` and `resource_regex`: maps from keys to fully anchored,
  dot-all RE2-subset patterns, AND with all other filters. Only present string
  values match; missing, finite-numeric, boolean and nested values never match. At most
  eight patterns combined, each up to 1,024 bytes; keys up to 256 bytes. Native
  queries compile patterns once and inspect only requested fields before term
  expansion. OTLP bytes normalize to base64 strings and non-finite doubles to
  `NaN`/`Infinity`/`-Infinity`, so their regex matching
  uses that encoding; byte/string identity is not retained.
  The typed envelope does not change this compatibility predicate into a strict
  OTLP-string predicate. Invalid/unsupported patterns fail before scanning. For example,
  `"resource_regex": {"deployment.environment": "production|staging"}`.
- `min_duration_ns` / `max_duration_ns`: inclusive bounds on `end - start`.
- `start_ts_ns` / `end_ts_ns`: inclusive bounds on the **span start time**, not
  duration overlap. Omitting them considers the full tenant trace manifest.
  Prefer bounds when you know the timestamp; old/unknown summaries and bloom
  false positives can still exceed scan budgets.
- `fields`: an optional list of returned fields, for example
  `["trace_id", "span_id", "name", "duration_ns"]`. Omit it for full spans.
  Projected queries retain only the requested fields of each candidate, plus a
  fixed-size digest of its complete sort key, so the 16 MiB candidate budgets
  count what the result can contain: narrow fields fit 5,000 wide spans that
  full results cannot. When two different stored copies of one span (same start,
  trace ID and span ID) are retained, the query reruns once with complete sort
  keys and full-payload budgets, reading its sources again, so results keep the
  same order as full queries.
- `limit`: `1..5000`. Results sort by start time descending with deterministic
  tie breaking. Without a limit, more than 5,000 matching spans returns an error.

Example tool arguments for a trace lookup:

```json
{"tenant":"production","trace_id":"0123456789abcdef0123456789abcdef","start_ts_ns":1700000000000000000,"end_ts_ns":1700000060000000000}
```

A complete HTTP call for that lookup (set `PULSE_TOKEN` to the tenant's plaintext
token, and replace the host, trace ID, and time bounds with your own):

```sh
curl https://pulse.example.com/mcp \
  -H "Authorization: Bearer $PULSE_TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2026-07-28' \
  -H 'Mcp-Method: tools/call' \
  -H 'Mcp-Name: query_traces' \
  --data '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "curl", "version": "1"}
      },
      "name": "query_traces",
      "arguments": {
        "tenant": "production",
        "trace_id": "0123456789abcdef0123456789abcdef",
        "start_ts_ns": 1700000000000000000,
        "end_ts_ns": 1700000060000000000
      }
    }
  }'
```

The JSON-RPC response wraps the JSON span array in `result.content[0].text`.
Check `result.isError` before decoding that text. No `initialize` handshake is
needed. You can change `method`/`Mcp-Method` to `tools/list` and omit the tool name,
`Mcp-Name`, and arguments to discover the current input schema. Older
initialize-based MCP clients need a protocol update; they are not compatible
with this endpoint.

Example search for failed requests within one service:

```json
{
  "tenant": "production",
  "service": "api",
  "status_code": 2,
  "attributes": {"http.response.status_code": 500},
  "limit": 100
}
```

Example search for slow server requests, keeping the response small:

```json
{
  "tenant": "production",
  "service": "api",
  "kind": 2,
  "min_duration_ns": 1000000000,
  "start_ts_ns": 1700000000000000000,
  "end_ts_ns": 1700000060000000000,
  "limit": 20,
  "fields": ["trace_id", "span_id", "name", "timestamp_ns", "duration_ns", "status"]
}
```

The response is a JSON array of spans, with `timestamp_ns` representing start,
`end_timestamp_ns` representing end, and derived `duration_ns` representing their
difference. Request-wide query concurrency, time, heap, object-byte,
segment-count and row-count budgets are shared with other raw query tools.
Trace candidate/result metadata additionally has independent byte ceilings;
large records can return `query_resource_limit` even below the record limit.
5,000 is a schema maximum, not a capacity guarantee: wide, full-metadata
responses can still hit memory budgets. Prefer smaller limits, output
projections, and narrow time windows when necessary.
On object storage, selection and JSON projection stay in Rust until the final
response binary, rather than expanding all retained spans into runtime maps.
An explicit limit uses bounded newest-first selection, not an unlimited
materialization followed by trimming. Limited searches charge visited
segments/rows/bytes and may stop once all older segment time bounds are strictly
below the retained results. Equal-time ties and unknown bounds still require
scanning; budget exhaustion is an error, never a partial success.
Trace-ID blooms and complete service summaries prune new segments. Managed
active-leaf references also summarize IDs/services, so exact lookup can skip
irrelevant leaves before reading metadata. Complete ID-hash sets cover at most
256 distinct IDs per segment. Larger batches and compaction outputs instead
carry a versioned fixed 2 KiB bloom; leaves combine only identical geometries,
rebuilding small complete hash sets at that same geometry. Leaf blooms cap at
2 KiB and their independent complete service sets at 512 encoded bytes. Missing
summaries never authorize pruning. Older 8 KiB segment
blooms remain readable. Truly unknown or legacy sets always scan; collisions
and saturation only add reads. `query_traces` `resource` string equality and
`resource_regex` patterns on `service.name` also skip segments, and leaves
written by this release, whose complete service sets prove that every row's
original string `service.name` is one of them and none satisfies the filter.
Segments and leaves without that proof are read.

Segments written by this release also carry bounded value sets of their string
resource and span attributes, for example `service.namespace`, `http.route` and
`http.request.method`. Up to 64 keys per owner keep up to 8 distinct values of
at most 96 bytes each, within 384 encoded bytes per segment. Leaves keep the
union within 512 bytes, and a key with more values stays known only by its
name. So `query_traces` `attributes`/`resource` string equality and
`attributes_regex`/`resource_regex` patterns skip segments and leaves that
cannot hold a match. Keys and values past these bounds, non-string values,
legacy segments and flat (`PULSE_MANIFEST_FORMAT=flat`) manifests never prune.
On segments with few spans per push this adds about 350 bytes to each manifest
entry. Paged manifest pages and inline tails fill sooner, and there are more
leaf pages per hour. Trace compaction unions source sets.

Limited `query_traces` scans on paged manifests plan the newest 64 candidates
first, reading only the leaves that can hold them. They plan four times as many
whenever the scan needs more. A query whose newest segments already fill its
limit no longer reads every leaf of the range. Limited scans that keep
going read further ahead, up to 32 segments within 16 MiB in flight. Exact-ID lookup reserves 64 KiB per overlapping
live bucket in addition to its 8 MiB metadata-byte default, capped at 32 MiB;
an explicit configured byte limit is never raised. Other searches and
maintenance retain their 8 MiB default. Lookup still reads live bucket indexes,
and dense/unknown metadata can still exhaust budgets.
Dedicated trace-ID sidecars are not available yet. A result
limit or a time range can omit spans in the same trace. Pulse does not claim a
complete trace tree, and absence is not proof that the SDK sampled or exported
nothing. Use the returned trace IDs to correlate with logs from the same tenant,
provided your logging pipeline actually exports trace IDs.

## Assemble a stored trace

Call `get_trace` with only `tenant` and a 32-character hex `trace_id`. It returns
an object with `trace_id`, `coverage`, `retention_floor_ns`, `span_count`, `spans`,
`root_span_ids`, `missing_parent_span_ids`, `duplicate_span_ids`,
`conflicting_span_ids`, and `metadata_unknown_span_ids`. Without enforced retention, coverage is
`"all_stored_spans"` and the floor is null. On retention-managed storage it is
`"all_stored_spans_at_or_above_floor"`, with the snapshot's committed floor in
nanoseconds. Expired spans are intentionally excluded, including parents inside
mixed-age segments. An unknown trace has zero spans and empty ID arrays.

The tool scans all matching active segments in the selected storage snapshot;
it does not accept time bounds, projection, a result limit, or pagination that
could silently omit part of the trace. More than 5,000 stored spans, exhausted
scan/deadline budgets, or excessive result/metadata bytes return an error, not a
partial trace. The span cap stops the scan as soon as the 5,001st stored span
is read. MCP error text names the bound that fired and suggests `query_traces`
with `trace_id`, a time window and a `limit` instead. On S3 the reconciliation
and response remain native until the final response binary. Complete stored-span coverage does not guarantee every
span was exported: sampling, delayed delivery, retention, and missing parents
can still leave an incomplete application trace.

Duplicates are retained, not silently merged. Repeated span IDs are reported;
IDs with different projections/timing or disagreement between known typed
copies are marked conflicting. Any legacy copy adds the ID to
`metadata_unknown_span_ids`; projection-identical legacy/rich copies are not
proof of a typed conflict.
Roots have no parent ID; missing-parent IDs reference absent spans. ID arrays are
sorted deterministically. The response does not pick an arbitrary winning span,
construct a potentially cyclic tree, or implement the Tempo trace-response API.
Trace-ID posting indexes are still absent, so a large historical lookup may
exhaust scan budgets even when its final trace is small.

## Operating the experimental backend

Prefer enforcing a positive trace duration before first ingestion into a new
scope. Flat roots omit ID-hash sets used only for leaf construction; conversion
therefore scans that older small-batch history conservatively until it expires.
This can exhaust exact lookup budgets during the first retained window.

Every append adds a segment. Without enforced retention, each publication
rewrites a growing flat catalog; compaction reduces active objects but its
retirement tombstones remain permanent. With enforcement, bounded immutable
pages and time buckets replace that catalog and historical metadata is reclaimed
with expired buckets. Page, byte and bucket limits still fail explicitly under
excessive density or cleanup backlog, rather than silently dropping references.
There is no promised safe ingestion duration or production throughput for this slice.
Monitor publication latency, errors, and manifest-owner queue depth through
[self-monitoring](self-monitoring.md).

Small exporter batches are needed for safety but increase segment counts.
Optional `PULSE_INGEST_FLUSH_INTERVAL_MS` coalesces **concurrent** unkeyed appends
on one node; it does not combine widely spaced sequential exporter flushes,
compact old segments, or bound manifest growth. A larger batch is not a substitute
for lifecycle management.

### Native compaction

On by default (`PULSE_TRACE_COMPACTION_ENABLED`, Helm `traceCompaction.enabled`).
Without it every ingest flush stays its own segment: at one flush every 2 s an
hour holds thousands of objects, and Tempo search and TraceQL metrics over an
hour exceed the query segment budget or time out.

Every maintenance pass (once a minute on the rendezvous owner of each tenant)
rewrites the oldest settled flushes (30 s after their newest span), up to 512
segments and 60,000 spans at a time, together with the same hour's merged
objects that are not full yet. The merge splits the hour's spans into objects
that each hold one service, one class (spans with error status or events, or
the others) and at most 256 trace IDs, in start order. Each object's manifest
entry lists its exact trace-ID hashes, its services and attribute value sets,
its status codes and whether any span has an event, so:

- service and attribute selectors read only the objects of matching services
  and values;
- `status = error`, `event.*` predicates and their `rate()` metrics read only
  the error/event objects;
- a candidate trace's other spans are read only from the objects listing it.

Nothing is dropped or aggregated: every span, duplicate and metadata field
survives. Spans that cannot merge faithfully (`trace_projection_invalid`, a
size mismatch) stay active and queryable, and their hour is set aside on that
node for an hour so the others keep merging.

Publication uploads the outputs before one conditional manifest write retires
their sources. Sources are deleted after a one-hour grace period, and only
once a [manifest backup](configuration.md#manifest-backups) records their
retirement, the same model as logs and metrics. It is therefore safe on object
stores without bucket versioning, such as Tigris. Keep manifest backups on.
Prefixes with bucketed (`PULSE_RETENTION_MANIFEST_FORMAT=bucketed`) retention
keep a simpler 32-segment merge and are not backed up; keep versioning there.

Merged objects are readable by every release that reads format-4 manifests;
older releases ignore the new summary fields and read more objects. Before
1.38, releases with trace compaction enabled merge differently; upgrade every
pod writing to the bucket before relying on the pruning above.

#### Search context horizon

Tempo search reads a candidate trace's other spans from sources overlapping
the candidates' segments widened by `PULSE_TRACE_SEARCH_CONTEXT_HORIZON_MS`
(Helm `tempoSearch.contextHorizonMs`, default one hour). Traces shorter than
the horizon are complete. Spans of longer traces outside it are not read, so
their reported duration and matched span count can be smaller. Set `0` to read
every retained source, which on long retention is slow.

### Retention

Traces use the same [event-time retention](retention.md) as logs and metrics.
Set `PULSE_TRACES_RETENTION_DAYS=7` (Helm `retention.tracesDays: 7`) to configure
seven days based on **span starts**, and follow the documented observe-first
rollout before switching `PULSE_RETENTION_MODE=enforce`. Durations are whole
days in `0..3650`; zero keeps data indefinitely unless a floor was previously
committed. Modes, deletion grace, future skew, sweep limits and recovery
procedures are shared across signals. Retention does not require compaction.

Enforcement converts the trace catalog to the bounded, checksummed format-3
root and immutable pages. The root's floor never rewinds. Search and assembly
hide starts below it even inside mixed-age segments; spans exactly at the floor
stay visible. Whole expired buckets are deleted after the configured grace
(one hour by default), including their metadata and compaction tombstones.
Bounded orphan sweeps and durable catch-up cover unpublished uploads. Without
enforced retention, flat catalogs and permanent compaction tombstones remain
unbounded. Retention is explicit authorization to delete acknowledged data,
not a precise physical-erasure deadline.

After whole-request safety preflight, unkeyed OTLP traces report expired or
excessively future-dated spans individually through `partialSuccess`, keeping
valid siblings. Keyed payloads are never filtered, because that would change
their durable fingerprint. Expired/future keyed batches and direct appends fail
whole with HTTP 400 (OTLP code 3); migration, capacity and storage failures use
retryable 503 (code 14). The default future allowance is ten minutes.

**Publication checks the latest committed floor**, not a frozen admission
clock. If the floor advances while a batch is queued or uploading, even an
unkeyed OTLP request receives a retryable 503 rather than a permanent failure
that would discard fresh siblings. Its next attempt filters expired spans
individually against the newer floor. Keyed expiry remains permanent 400;
callers cannot bypass the floor with an old cutoff. Choose retention longer than exporter delays and normal span lifetimes.
Retries of compacted keys are idempotent while retained. Once their bucket has
expired, retries are permanently rejected instead of acknowledged or resurrected.

Upgrade every reader/writer and preserve coherent root/page backups (bucket
versioning or Pulse's manifest backups) before enforcement. Never remove `.managed` markers or
manifests to force LIST reconstruction. Disabling retention or rolling back
an image cannot undo its format or floor. Do not use bucket lifecycle deletion
for referenced trace objects. Keep existing production tracing authoritative
until lifecycle capacity, required queries, provider faults and recovery have
been validated against your workload.
