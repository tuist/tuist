# Querying

Pulse has no user interface. Agents query it through the Model Context Protocol,
and dashboards or scripts use its Prometheus- and Loki-compatible HTTP APIs. Every
query is scoped to one tenant and authenticated with that tenant's bearer token.
See [tenants and tokens](configuration.md#tenants-and-tokens).

## Model Context Protocol

`POST /mcp` implements the stateless
[`2026-07-28`](https://modelcontextprotocol.io/specification/2026-07-28) revision
of the protocol over Streamable HTTP. There is no handshake or session: each
request carries its protocol version and client capabilities in
`params._meta` and mirrors them in the `MCP-Protocol-Version`, `Mcp-Method`, and,
for `tools/call`, `Mcp-Name` headers. Clients that only speak older revisions
receive `400` naming the supported version.

Send the tenant's token as `Authorization: Bearer <token>`. Browser clients must
also have their origin listed in `PULSE_MCP_ALLOWED_ORIGINS`.

The query tools below are read-only and take the tenant as an argument:

Experimental `list_reliability_signals`, `get_reliability_signal` and
`list_reliability_changes` expose periodic cross-signal model assessments and
their budgets/coverage. They use existing tenant authorization and do not start
investigations. See [durable replay and freshness rules](reliability.md#consume-signals).

| Tool | Purpose |
| --- | --- |
| `query_logs` | Return log records for a time range, optionally filtered by service, including their typed `otlp` envelope when present. |
| `query_logql` | Evaluate a LogQL expression and return the same envelope as `/loki/api/v1/query_range`. |
| `discover_metrics` | Complete retained-sample label names, values or series with OR selectors and exact time bounds. Empty-valued labels project as absent. Same contracts as the [Prometheus metadata APIs](metric-discovery.md); safety limits fail rather than truncate. |
| `query_metrics` | Return raw metric samples for a time range, filtered by label matchers. Optional exact-equality footer postings skip native row-group decoding, not whole-object GETs or source scan budgets. See [bounds and fallback](metrics.md#bounded-native-query-acceleration). |
| `get_trace` | Assemble all stored spans for one exact trace ID, with roots, missing parents and duplicate/conflict IDs. No truncation or time window; budget exhaustion is an error. See [traces](traces.md#assemble-a-stored-trace). |
| `discover_trace_tags`, `discover_trace_tag_values` | Default-off retained resource/span/instrumentation/event/link names and original string/int64/bool/float values (nonfinite classes included). Names/values accept optional original-string equality/anchored-regex AND `query`, on one parent span; nested predicates and value same-target equality reject. Filtered names include complete matching keys plus fixed all-visible-context promotion hints, not key-presence proofs; they can exceed raw upstream names. Omit name scope/use none to combine five namespaces plus 25 static intrinsic suggestions in v2; this shares one global work/pair/byte budget, not five query budgets, and any storage/metadata error fails whole. Combined names hint service.name for any visible parent even unfiltered/absent original. Scope-none values combine resource/span/instrumentation only, not events/links. Optional bounded resource/span strings select one parent then union its three original typed owners, a complete extension rather than Tempo's ignored-query fast path. Returned other-owner values need not themselves match the literal/regex. Same-key equality across resource/span and reserved root aliases reject. Requires discovery12 matching artifacts; query-aware unscoped execution or bounded reference, and separate explicit windowed-filtered-none support, never old callbacks. Floats retain type/signed zero using TraceQL text. Seven stored intrinsic strings (span name/status message, scope name/version, event names) accept parent filters under normal stored-data bounds; complete values may exceed upstream distinct-iterator omissions. event:timeSinceStart returns exact signed int nanoseconds, not duration strings: event time minus its own parent's start. Default event time0 can yield negative values; no events invent no values. Parent-string filtering is a complete extension versus upstream's empty filtered path. Every requested event time validates even on nonmatches; parent+all events/attrs spend work first. Separate event-time /4 or bounded reference plus dedicated windowed /6 fence old string/window callbacks. Requested-owner-plus-attribute work caps at 2,000,000 per scan attempt before filtering, so dense flat scopes can fail earlier. Values require scope (including explicit none); paired positive start_ts_ns/end_ts_ns select whole retention-visible source envelopes, not point-time rows; all raw source headers/provider costs still charge, no indexed-planning improvement. Compaction can broaden dictionaries; unselected payload metadata is not integrity-scrubbed. Explicit window-aware adapters or rejection, no silent flat approximation. No zero/one-sided windows or intrinsic predicates; whole legacy/type/scan/dictionary errors never truncate. Separate `intrinsic` scope returns static protocol names and seven keyword/empty v2 shortcuts without storage, not stored presence or full TraceQL support; static filters and stored span-duration intrinsic values reject. rootName/rootServiceName and trace:rootName/trace:rootService are stored root strings: matching parents select trace IDs then recover all retained context, even outside windows/predicates. Missing/ambiguous roots or missing original string root service fail409 whole, no defaults or skip-incomplete. In-flight/retention-straddling/multi-root traces can make broad/recent queries unusable. All retained root S3 input must fit1024 objects/32MiB compressed/1M rows regardless of window, with local all-source replay and no service/ID planner. 65,536 candidates/16MiB bookkeeping and2M resource/span/link owner+attr work plus standard dictionary/result bounds. Dedicated root/window support, not old span-local callbacks; proof is not full exporter/span-ID conflict or deployed-client parity. Canonical trace:duration now measures complete retained max-end/min-start without requiring roots; in-flight ingestion/retention change that envelope, not exporter completeness. Unfiltered returns int nanoseconds, supported filters return Go duration strings (µs), both lexical; keep caches separate across query/type changes. Same whole-tenant input/replay/group/dictionary bounds, with2M resource/span owner+attr work and80B-per-summary bookkeeping charges under16MiB, not a total native-memory guarantee. Broad nanosecond dictionaries commonly fail422; no samples/truncation. Dedicated duration/window support fences old callbacks. Static empty duration/span:duration/traceDuration remain unchanged. See [discovery subset](traces.md#experimental-scoped-tag-discovery). |
| `search_trace_metadata` | Disabled-by-default experimental Tempo-shaped search over complete retained context before inclusive trace overlap, ordering, limit and sampled spansets. Requires explicit `most_recent=true`; ALL retained tenant IDs/rows consume bounds even outside the window. See [opt-in and planning costs](traces.md#experimental-tempo-search). |
| `traceql_metrics` | Disabled-by-default TraceQL metrics, the same queries and JSON as Tempo `/api/metrics/query_range` (with `step_ns`) or `/api/metrics/query` (without), including `event.` predicates. Requires `PULSE_TEMPO_SEARCH_ENABLED`. See [trace query expressions](trace-query-expressions.md). |
| `search_traces` | Search distinct traces using bounded original-string resource/span AND selectors in an explicit span-start window. Groups before trace limits; unknown legacy types and all-window group/scan exhaustion fail. Native window-local aggregates, not a Tempo envelope. See [search limits and legacy history](traces.md#search-distinct-traces). |
| `query_traces` | Lookup spans by trace/span/parent ID or search by start time, service, name, kind, status, duration, roots and query-projection attributes, with optional output projection. See [traces](traces.md#query-spans). |
| `query_promql` | Evaluate a Prometheus Query Language expression, instant or range. |
| `query_errors` | Read Sentry error events and scrubbed payloads in a required time window. |
| `list_error_issues` | Group Sentry errors with exact window-scoped counts and first/last seen; see [error tracking](error-tracking.md). |
| `list_error_changes` | Poll the separately enabled experimental index for retained-history issue changes, measured error-rate increases with compact evidence, and explicit resets; save the cursor durably. See [detector semantics](error-monitoring.md#error-rate-findings-for-agent-workflows). |
| `list_indexed_error_issues` | Read compact deduplicated retained-history summaries and example references from that index; see [error monitoring](error-monitoring.md). |

`tools/list` returns each tool's full input schema. Invalid arguments, such as a
reversed time range, return an explicit error instead of an empty result.

`query_promql` and `query_logql` take queries as Prometheus and Loki receive
them, not as they are written in Grafana. Grafana replaces `$__rate_interval`,
`$__interval`, `$__interval_ms`, `$__auto` and `$__range` before it sends a
query, using its data source's scrape interval and the panel's step and time
range, which Pulse does not know. A query that still contains one is rejected
with an error naming the variable and what to put in its place, for example
`[1m]` for `$__rate_interval` with a 15 s scrape interval (Grafana uses
max(step + scrape interval, 4 × scrape interval)).

## Tempo trace lookup

`GET /api/traces/<hex-trace-id>` returns an experimental Tempo v1 trace envelope
(JSON `batches` or `application/protobuf`). `/api/v2/traces/<hex-trace-id>` returns
the v2 `TraceByIDResponse` wrapper. Both read all visible stored spans,
not a caller-truncated window. Typed metadata is required; legacy copies and
same-ID disagreements fail rather than guess values or rewrite IDs. See
[the full lookup contract and limitations](traces.md#tempo-v1-trace-lookup).
Search/discovery APIs and verified deployed Grafana datasource parity remain separate.

## TraceQL metrics

`GET /api/metrics/query_range` and `GET /api/metrics/query` evaluate TraceQL
metrics as Tempo does, for Grafana's Traces Drilldown and Tempo metrics panels.
They are disabled unless Tempo search is enabled (`PULSE_TEMPO_SEARCH_ENABLED`).
Queries take `q` (or `query`), `start`, `end` (Unix seconds, nanoseconds or
RFC3339; by default the hour before `end`, or `since`) and, for ranges, `step`
(seconds or a duration; by default about 240 points).
RFC3339 bounds preserve fractional nanoseconds, including digits beyond
microseconds and timezone offsets. Upgrade query-serving applications for this
boundary fix; numeric timestamp semantics, alignment and native metrics
capability 5 are unchanged.

Malformed metric `start`/`end` values return HTTP `400` naming the parameter:
`could not parse 'start' parameter` or `could not parse 'end' parameter`.
Malformed metric `since` values return `could not parse 'since' parameter:`.
Successfully parsed zero/negative `since` values and invalid windows retain
the existing generic rejection.
Parsing grammar, defaults and existing end-before-since-before-start validation
order are unchanged; complete upstream timestamp error text is not implemented.
Upgrade query-serving applications for consistent diagnostics.

Without `step`, windows shorter than one minute use multiples of 50 ms, with a
50 ms minimum. Longer windows use a one-second minimum and round the window's
1/240 baseline down at the largest applicable granularity: one hour, five
minutes, one minute, fifteen seconds, five seconds or one second. For example,
59 seconds defaults to 200 ms, six hours to one minute, and 24 hours to five
minutes. Rounding and boundary alignment can produce more than 240 points.
Explicit steps are unchanged. Upgrade every query-serving application before
relying on the default policy; no data migration or native ABI change is needed.

Supported: a selector of `{}`, `{true}` or the
[bounded expression grammar](trace-query-expressions.md), optionally combined
with `nestedSetParent<0` for root spans, piped into `rate()`,
`count_over_time()`, `min_over_time`, `max_over_time`, `sum_over_time`,
`avg_over_time`, `quantile_over_time(<attr>, <q>...)` or
`histogram_over_time(<attr>)` over `duration`, `span.<key>`, `resource.<key>` or
`.<key>`, with `by (...)` over up to five keys (attributes, `name`, `status`,
`kind` or the grouping-only `span:id`). As in Tempo, ranges are aligned to the
step with one extra leading interval, spans count by start time, durations
aggregate in seconds, and quantiles interpolate between power-of-two duration
buckets. `with (...)` hints
are accepted and ignored, so sampled queries return exact results. `| topk(n)` and
`| bottomk(n)` keep, at each interval, the `n` series with the largest or
smallest values. For homogeneous string-label groups, top-k ties favor earlier
labels and bottom-k ties favor later labels, as Tempo does. Full mixed-type/
multi-label comparator parity is not established.
A single finite scalar filter can precede ranking on an otherwise unranked
pipeline, for example `{} | rate() > 10 | topk(5)`. Filtering runs before
ranking, preserving qualifying values; ranking first can select different
series. Every finalized slot, including missing or rejected samples, spends
the same native work budget shared with selectors and other expression leaves.
Multiple prefilters, repeated ranking and ranking an arithmetic result remain
unsupported.
`compare()` is not supported.

Parenthesized metric pipelines compose with `+`, `-`, `*` and `/`, including
scalar constants on either side, for example
`100 * ({status=error} | count_over_time()) / ({} | count_over_time())`.
Multiplication/division bind before addition/subtraction. Integer-only constant
division truncates (`3/2` is 1); a float operand gives floating division.
Integer literals and folded results must fit signed int64; overflow rejects
rather than wrapping or silently becoming a float. Duration constants work as
filter thresholds, not arithmetic operands.

Scalar-right `=`, `!=`, `<`, `<=`, `>` and `>=` filter samples without changing
their values, and can chain: `({} | count_over_time()) >= 2 < 10`.
Runtime division by zero and failed comparisons produce missing samples, never
zero-filled arithmetic. NaNs propagate and fail every comparison, including
`!=`; responses omit NaNs and empty series. Nonfinite arithmetic results use
`"Infinity"`/`"-Infinity"` strings. Matching requires identical ordered, typed
group labels; only truly ungrouped series broadcast across grouped series.
Missing grouping values are not ungrouped broadcast series. Scalar operations
preserve names; two named operands combine their names.

Expression branches share one storage scan, provider reads and native budgets;
each unique pipeline still decodes the admitted segment separately. Limits are
128 expression nodes, nesting depth 32 and 16 unique pipelines. Across those
pipelines, native accumulation shares 10,000 series, 2,000,000 interval points,
20,000,000 selector work units and 64 MiB of retained group-value bytes.
Arithmetic additionally allows 2,000,000 points per intermediate and 20,000,000
point operations, inside the query worker's heap/deadline limits. Packed native
results and final response JSON each have a 64 MiB ceiling. A missing source,
corruption or exhausted budget fails the whole expression; no partial result
or fresh-budget retry is returned. Scalar-only queries, unary negation of a
metric pipeline, vector comparisons and PromQL matching modifiers reject.

Ungrouped `count_over_time()` and `rate()` return one zero-valued series when
no spans match, including empty tenants and windows. Range results include every
aligned interval; instant results contain one zero. No group labels or numeric,
histogram or quantile observations are invented for an empty selection. Storage,
metadata and budget errors still fail the whole query rather than becoming zeros.

Range requests reject HTTP `400` when integer division of the original
`end - start` by `step` exceeds 10,000, before alignment adds boundary intervals.
The diagnostic reports the requested step and minimum step for that range
(the original width divided by 10,000, rounded down). For example, a six-minute
range with `35ms` step reports a `36ms` minimum, without reading storage.
Negative range steps reject with `400` and `step must be positive`, before
reading storage. Zero and malformed steps retain their existing rejection policy;
this diagnostic change does not broaden duration grammar or change native metrics
capability 5. Upgrade query-serving applications for consistent diagnostics.
Alignment can therefore produce more than 10,000 output
points per series. Instant requests use one interval and ignore `step`.

Spans are reduced natively per stored segment without being decoded into
queryable records; the scan budgets of [query budgets](configuration.md#query-budgets)
apply, and results are capped at 10,000 series, 2,000,000 points and 64 MiB of response JSON. Windows must fit nonnegative signed 64-bit nanoseconds. These are independent work/result ceilings, not total native or process-memory bounds.

Original attribute grouping/values and selector programs fail the whole query
when in-window source rows have unknown legacy metadata; legacy attributes are
never invented as missing labels or silently excluded from averages. Unfiltered
core-only operations, such as counts grouped by span name, can still read those
rows.

`by (span:id)` reads the stored core span ID and returns it as a 16-character
lowercase hex string under the `span:id` label. `span.id` remains an ordinary
attribute; bare `id`, `trace:id` and numeric aggregation over span IDs are not
supported. Equal span IDs group together even across different traces; this is
an ID-value grouping, not a globally unique trace/span identity. Core-only
span-ID grouping can read legacy rows with valid core fields. The same five-key,
10,000-series and point/byte ceilings apply; exceeding them fails whole, never
truncates. There is no unlimited-series override. Upgrade every query-serving
app/native pair before relying on this syntax: startup requires trace metrics
capability **6**, independently of the trace search/export/discovery tuple.
Storage format and keyed encoder bytes are unchanged; no retry drain or data
migration is needed for this addition.

## Prometheus API

`GET|POST /api/v1/query` and `/api/v1/query_range` accept the standard Prometheus
parameters (`query`, `time`, or `start`/`end`/`step`) with the tenant in the
`X-Scope-OrgID` header. Timestamps accept Unix seconds or date-time strings with
a timezone; steps accept seconds or durations such as `15s`. Client `timeout`
values are capped at ten seconds. Results use Prometheus scalar, vector, and matrix
formats, plus string results for instant queries, so Grafana can use Pulse as a
Prometheus data source within the supported subset below.

Optional `limit` caps returned vector/matrix **series**, not samples per series.
Scalars and strings are unchanged. Omission, empty text and zero disable this
response cap; positive signed-int64 values preserve the evaluated result order
and emit `warnings: ["results truncated due to limit"]` only when truncating.
All evaluation, scan, sample and result budgets still apply to the complete
query before this cap. Label and series discovery support the same explicit
[HTTP response limit](metric-discovery.md), without changing complete MCP reads.

Grafana's optional query-statistics setting sends `stats=all` on instant and
range requests. This selector is accepted on GET and form POST, but responses
do not include JSON execution statistics. Query results and safety budgets are
unchanged; no synthetic statistics are reported.

Range requests return HTTP 400/`bad_data` with field-specific diagnostics for
invalid `start`, `end` or `step`, reversed bounds and zero/negative numeric steps.
The existing limit is 11,000 inclusive evaluation points, not 11,000 intervals;
an otherwise valid request exceeding it returns the maximum-resolution error.
Reflected parameter values are quoted and truncated after 128 input bytes.
Authorization runs before these diagnostics. Upgrade query-serving applications
for consistent error responses; timestamp/duration admission and resource limits
are unchanged. Other expression/instant-query diagnostics are not full Mimir
error-text parity.

Instant queries also accept top-level range selectors and subqueries, returning
a matrix with original sample or inner-grid timestamps, complete float/native
histogram values and metric names. Range windows exclude their lower boundary
and include their upper boundary; stale markers are omitted. Strings return
`resultType="string"` and `[evaluation_time, decoded_string]`, including empty
strings. Both result types share existing sample, work, intermediate and output
budgets. `/api/v1/query_range` accepts only scalar or instant-vector expressions,
even when `start=end`; strings, range selectors and subqueries return `400`
before reading storage. A top-level range selector or subquery reports
`invalid parameter "query": query expression produces a range vector, but expression for range queries must produce an instant vector or scalar`.
This does not change string-result or general parser diagnostics.
Upgrade every query-serving application before relying
on these instant results; storage, keyed bytes and native ABIs are unchanged.

`absent_over_time` tests whether any nonstale sample exists in each window,
including zero, NaN and native histograms. Distinct metrics sharing the same
other labels retain their source identities during this check; they must not
cause a duplicate-series error merely because their names differ. Only absent
windows emit `1`, with labels inferred from unambiguous equality matchers.
Sample/work limits still reject the whole query, including when its result
would be empty. Upgrade query-serving applications for the multi-metric fix;
storage, keyed bytes, native ABIs and limits are unchanged.

Selectors accept quoted UTF-8 metric and label names, for example
`{"utf_metric😀C", "utf8_label😀"="test"}`. A quoted metric name inside braces
is shorthand for `__name__="..."`; use quotes for non-ASCII names rather than
bare identifiers. Quotes and escapes follow PromQL string syntax. Empty names,
multiple shorthand metric names, malformed escapes and selectors whose matchers
all match empty values reject. Existing matcher-count, regex and query budgets
still apply. Nonempty quoted UTF-8 labels also work in `by`, `without`, `on`,
`ignoring`, `group_left` and `group_right`, with the same escapes and optional
trailing comma. Duplicate decoded names and overlapping `on`/included labels
still reject. `label_replace` accepts nonempty UTF-8 destination names too.
Formatting keeps names quoted when bare identifiers would change their meaning.
Upgrade all query-serving applications before using these forms;
ingestion already accepts UTF-8 names, with no new validation-mode setting,
stored format, native ABI or keyed-byte change.

Both query endpoints accept a positive `lookback_delta` in seconds or duration
syntax, for example `600` or `10m`. It changes how far instant selectors (including
`timestamp()` and selectors nested inside subqueries) look back from each
evaluation time; the default is five minutes. The lower boundary is exclusive.
Explicit range-vector windows such as `[10m]` are unaffected. Zero, negative,
malformed and signed-int64-nanosecond-overflowing values return `400`, rather than
silently selecting the default. Existing scan, sample, work, heap and timeout
budgets still apply, so longer lookbacks can fail on resource limits. Upgrade all
query-serving instances before clients send the parameter; older instances
reject it. No native artifact, stored format or ingest-byte change is required.

Remote-write labels are sorted and empty-valued labels are omitted before
series identity, same-label entry merging and storage. Duplicate label names,
empty label names and invalid UTF-8 still reject their complete series, even
when an offending label has an empty value. Supplied labels and points consume
the existing admission budgets before normalization. Valid sibling series are
stored: RW1 returns `204` with `X-Pulse-Rejected-Records`, while RW2 returns
`400` with that count and the valid written counts. An RW2 symbol table whose
first entry is nonempty rejects the whole request with `400`, zero written
counts and no sample or metadata publication.

Upgrade every receiving application/native codec pair together and drain keyed
remote-write retries containing empty-valued labels first. Their normalized
labels, series hashes, caller-content hashes and segment bytes change; replaying
across versions can derive different object keys and duplicate existing data.
This does not rewrite historical rows or change the storage format/native tuple.
Exact-byte verification at an existing derived key is unchanged; never bypass a
`409 keyed_content_mismatch`. Requests without empty-valued labels retain their
existing encoding. Label sorting alone was already supported.

Pulse implements a subset of the
[Prometheus Query Language](https://prometheus.io/docs/prometheus/latest/querying/basics/):

- Selectors with label matchers, signed `offset`, and numeric/`start()`/`end()` `@` anchors
- `rate`, `increase`, `irate`, `idelta`, `delta`, `changes`, `resets`, and `deriv`
- `sum_over_time`, `avg_over_time`, `min_over_time`, `max_over_time`, and
  `count_over_time`, `stddev_over_time`, `stdvar_over_time`, `mad_over_time`, `absent_over_time`,
  `present_over_time`, `first_over_time`, `last_over_time`, `ts_of_first_over_time`,
  `ts_of_last_over_time`, `ts_of_min_over_time`, `ts_of_max_over_time`,
  `predict_linear(range, horizon_seconds)`, and `quantile_over_time(q, range)`
- `double_exponential_smoothing(range, smoothing_factor, trend_factor)` and its
  legacy `holt_winters` alias
- Nested `sum`, `avg`, `min`, `max`, `count`, `group`, `stddev`, `stdvar`,
  `quantile(q, vector)` and `count_values(label, vector)` aggregations with
  `by` and `without` grouping; `topk` and `bottomk` reject NaN and ranking
  parameters at or above the signed int64 maximum; values below one yield no results.
  NaN ranking reports HTTP 422/`execution` with `parameter value is NaN for topk`
  or `bottomk`; sampling and overflow diagnostics are unchanged.
  Positive-`k` ranking ignores native histograms with query-local info notices;
  unexecuted zero-`k` filters emit none (a remaining range-query difference from Mimir)
- `min`, `max`, `stddev` and `stdvar` aggregations ignore native histograms with
  query-local info notices, including histogram-only groups that produce no
  sample. Float-only groups emit no histogram-ignored notice
- Value-independent `limitk(k, vector)` and `limit_ratio(r, vector)` sampling
  aggregations, preserving complete float/native-histogram samples and labels
- Scalar literals, unary signs, arithmetic (`+`, `-`, `*`, `/`, `%`, `^`, `atan2`),
  comparisons with optional `bool`, and `and`, `or`, and `unless`
- Scalar query-context `start()`, `end()`, `step()`, `range()`, and two-scalar
  `min_of(a, b)`/`max_of(a, b)`
- Vector matching with `on`, `ignoring`, `group_left`, and `group_right`;
  ambiguous matches and duplicate output series return explicit errors.
  One-to-one cardinality is checked at each evaluation step before comparison
  filtering: a false comparison cannot hide duplicate matching inputs. Inputs
  without a counterpart do not create many-side matching conflicts. Upgrade
  query-serving applications for consistent rejection; storage is unchanged
- Classic `histogram_quantile`, `clamp`, `clamp_min`, `clamp_max`, `label_replace`, `label_join`,
  `vector`, `scalar`, `time`, `pi`, `round`, `abs`, `floor`, `ceil`, `sqrt`, `exp`,
  `ln`, `log2`, `log10`, `deg`, `rad`, `asin`, `acos`, `atan`, `sin`, `cos`, `tan`,
  `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`, `sgn`, `timestamp`, `absent`, `sort`, `sort_desc`,
  `sort_by_label`, `sort_by_label_desc`, `year`, `month`, `day_of_month`,
  `day_of_week`, `day_of_year`, `days_in_month`, `hour`, and `minute`
  (`scalar` ignores native histograms and returns the sole float at each step,
  or NaN if there are zero or multiple floats)
- Subqueries such as `sum_over_time((max by(job)(gauge))[6h:5m])`;
  inner grids align independently to epoch multiples. Signed offsets and `@`
  anchors are supported. An omitted resolution (`[6h:]`) uses a fixed one-minute
  grid, independent of the outer step, window and nesting. Top-level subqueries
  return matrices through the instant query endpoint. Native-histogram subqueries
  clear explicit reset/no-reset hints on resampled points, so repeated selections
  of one source sample cannot repeat a reset and skipped source samples cannot
  suppress one. Gauge hints, floats and direct range-selector behavior remain
  unchanged. Upgrade all query-serving applications for corrected counter range
  results; no ingest/storage/native-format change or historical rewrite is needed
- Stale markers: instant selectors stop at the latest stale marker until a new
  sample arrives; range functions ignore stale markers
- IEEE-754 NaN and infinities, returned as `"NaN"`, `"+Inf"`, or `"-Inf"` in
  Prometheus result values

`start()` and `end()` return the requested outer query boundaries in Unix
seconds, including an end between evaluation steps. `step()` returns the
requested interval in seconds when the boundaries differ, even when only one
step fits; equal boundaries and instant queries return zero. `range()` returns
the boundary difference in seconds, saturating at the signed-int64 nanosecond
duration maximum (about 292 years). Instant queries use their evaluation time
for both boundaries, so their range is zero. Nested subqueries and offsets do
not change these constants. Each source in a query batch has its own context.
As with `time()`, Pulse retains nanosecond input precision before float-seconds
conversion; this is not Prometheus/Mimir's millisecond-quantization behavior.

`offset` shifts the data window backwards for positive values and forwards for
negative values. `metric @ 100` fixes the selection time at Unix second 100,
regardless of the evaluation step; `metric @ start()` and `metric @ end()` use
the requested outer boundaries, even inside nested subqueries. An unaligned
end is the requested end, not the last grid point. An instant query uses its
evaluation time for both boundaries. Each source in a query batch has its own
boundaries. `@` and `offset` may appear in either order; the offset always
subtracts from the anchor. Each modifier may appear only once per selector or
subquery. They cannot be applied to arbitrary function or aggregation results.

Range selectors and explicit-resolution subqueries accept these modifiers too:
`sum_over_time(metric[60] @ end() offset -10)` fixes the data window while the
surrounding query still evaluates at every output step. Scalar parameters such
as a quantile, smoothing factor or prediction horizon retain their own step
times. `timestamp(metric @ 100)` returns the selected source timestamp;
`timestamp(abs(metric @ 100))` returns the outer step timestamp. Staleness,
histogram types and left-open/right-closed windows remain unchanged.

Unitless durations are seconds, including decimal/exponent spellings such as
`[0.25]`, `[60:1e-3]` and `offset -0.5`. Leading-zero integer literals retain
PromQL octal interpretation (`010` means eight seconds). Windows/resolutions
must remain positive; windows and absolute offsets retain the one-year ceiling.
Numeric `@` anchors accept signed decimal/exponent seconds within int64
nanoseconds; duration-valued anchors such as `@ 2m` are also accepted. Time
literals use the HTTP timestamp parser's nanosecond rounding, retaining more
precision than upstream's millisecond timestamps. Formatting preserves the
exact admitted nanoseconds. Query time literals also accept hexadecimal integers
(`@ 0x10`, `[0x10:0xA]`) and digit separators (`offset 1_000`,
`@ 1_790_000_000.000_000_001`), including within duration arithmetic. Decimal
nanoseconds are parsed exactly, not rounded through a float. Malformed separators,
hexadecimal fractions/exponents, NaN/infinite anchors and repeated modifiers
reject. Unit-bearing durations do not accept separators (`1_000ms` rejects).
HTTP `time`/`start`/`end`/`step`/`lookback_delta` parameter grammar is unchanged;
these hexadecimal/separator extensions apply only inside PromQL expressions.
`anchored`/`smoothed` remain unsupported.

Duration arithmetic accepts `+`, `-`, `*`, `/`, `%`, `^`, parentheses and signed
operands in range windows, subquery windows/resolutions and offsets. For example:
`sum_over_time(metric[26m+4m])`, `sum_over_time(metric[30s:step()/2])`,
and `metric offset -(range()+1m)`.
`step()`, `range()`, and nested `min_of`/`max_of` use the requested outer query
context, including inside subqueries; each batch source resolves independently.
Instant/equal-bound queries have zero step/range, so use a positive floor when
needed, such as `metric[step()+1ms]` inside a range function. An unparenthesized
offset stops before arithmetic: `metric offset 100 + 2` adds two to the selected
value, while `metric offset (100 + 2)` shifts its source time by 102 seconds.

Expressions resolve before storage reads, including for empty selectors. Division
or modulo by zero, nonfinite results, nonpositive windows/resolutions and results
outside the one-year absolute limit reject the whole query. Numeric operands
retain subnanosecond fractions during arithmetic; the completed expression rounds
to the nearest nanosecond, ties away from zero, rather than upstream's millisecond
truncation. Bare time literals retain their existing exact decimal conversion.
Duration expressions share the query's expression-size and work ceilings; existing
scan/sample/intermediate/result limits and the 11,000-step subquery ceiling apply.
Only `step()`, `range()`, `min_of` and `max_of` are allowed in durations, not
`time()`, selectors or arbitrary scalar functions. HTTP `step` and `lookback_delta` parameters still
require literal durations. Unit-bearing scalar values such as `1h30m` also work
in ordinary arithmetic and function arguments as 5400 seconds, under the same
one-year literal ceiling. Upgrade all query-serving applications before using
this syntax; native artifacts, stored data and keyed bytes are unchanged.

Shifted storage windows intersect the supported int64 timestamp domain rather
than wrapping or moving observations to an endpoint; a disjoint window is
empty. Subquery grids outside that domain reject. Negative selection times do
not add negative-source-time ingestion to S3's existing nonnegative object-key
contract. Existing scan/sample/work/result/heap budgets apply to anchored and
forward-shifted queries, including repeated steps and batches. Upgrade all
query-serving applications; native artifacts, stored formats and keyed bytes
are unchanged.

`min_of` and `max_of` accept exactly two scalars, evaluated at each step. They
use Go `math.Min`/`math.Max` semantics: negative infinity wins `min_of` and
positive infinity wins `max_of`, even over NaN; otherwise NaN propagates.
Zero ties select negative zero for the minimum and positive zero for the
maximum, unless both inputs have the same sign. These differ from the
NaN-ignoring `min`/`max` aggregations. Scalar results have no labels; range
queries return an empty-label matrix. Existing work/result/heap budgets apply.
Upgrade all query-serving applications; native artifacts, storage and keyed
ingestion bytes are unchanged.

`stdvar` and `stddev` compute population variance and standard deviation across
the selected floats in each group at each step, using incremental Welford
updates. A finite singleton has zero variance; any NaN or infinite observation
makes its group NaN. Histograms are ignored with a query-local info annotation;
a histogram-only group has no output, not zero.

`quantile(q, vector)` sorts each group's floats with NaNs first, then linearly
interpolates the requested rank. Exact ranks read only that observation, avoiding
zero-weight contamination from adjacent infinities. `q` is a scalar evaluated
at every step, including when the vector is empty: invalid quantiles still emit
a warning. NaN/below-zero/above-one parameters yield NaN/-Inf/+Inf for nonempty
float groups. Histograms are ignored with an info annotation.

`count_values("value", vector)` counts each distinct value within the group,
returning float counts with an additional UTF-8 label. Float label values use
shortest fixed decimal, never exponent notation; `0` and `-0` remain distinct,
and exceptional values use `NaN`, `+Inf` and `-Inf`. Histograms are counted too,
using complete count/sum/populated-bucket text, including negative and custom
buckets. Histogram text uses general-format exponents and original bucket
bounds, not the HTTP envelope's zero-clipped bounds. The destination must be
nonempty valid UTF-8. Following Mimir, it is assigned **after** grouping,
overwriting an existing label and merging equal resulting identities. It is
retained even when named by `without`, unlike the pinned Prometheus engine.

These aggregations share existing scan/sample/work/result/heap limits. Sorting
charges group size times its logarithm; generated value-label bytes spend work before label
construction; high-cardinality queries can fail rather than return partial
counts. Query-batch limits accumulate and annotations stay source-local.
Upgrade every query-serving application; no native/storage/keyed-byte change
or migration is required. Full annotation source-position and cross-platform
floating-point bit parity remain unimplemented.

`limitk(k, vector)` keeps up to k present samples per `by`/`without` group at
each step, preserving all original labels, including the metric name. It
truncates finite k toward zero; values below one select nothing. NaN,
infinities and k outside the open signed-int64 bounds reject even for empty
input. Selection is deterministic by full-label hash, not largest/smallest
value, and includes native histograms and ordinary NaNs. Stale observations
remain absent. Mimir uses its input iteration order, so the chosen subset when
k binds is not guaranteed identical to Mimir's.

`limit_ratio(r, vector)` selects a deterministic approximate fraction, not an
exact count. The hash includes every current label and the metric name, after
any label rewrites; `by`/`without` never remove output labels or change ratio
membership. Nonnegative r keeps hash offsets below r. Negative r keeps offsets
at or above `1+r`, so `0.5` and `-0.5` partition the same input. Zero selects
nothing; `-1` selects all and `1` selects offsets below one. As upstream,
uint64-to-float rounding can yield exactly one at the extreme upper hash
boundary. NaN rejects. Ratios outside
[-1,1], including infinities, cap with a query-local warning, retaining the
first out-of-range value per direction for each operator over the range. Scalar
parameters evaluate at each step and validate even when the input is empty.

Ratio membership follows the pinned Mimir/Prometheus default length-prefixed
label hash. Upstream does not guarantee hash identity across versions or label
builds; do not use it as durable series ownership. Both samplers preserve
float values, zero signs and complete histograms, and share scan/sample/work/
result/heap limits. Hashing label bytes, sorting and grouping spend work;
sampling does not avoid scanning its input or provide indexed/high-cardinality
acceleration. Batch limits accumulate and notices stay source-local. Upgrade
every query-serving application before using these operators; no native ABI,
stored format, keyed ingest bytes or migration changes are required.

`year`, `month`, `day_of_month`, `day_of_week`, `day_of_year`, `days_in_month`,
`hour` and `minute` extract UTC calendar fields from float Unix seconds, not
the sample's storage timestamp. Each accepts an optional instant vector;
omitting it uses the query evaluation time at each step. Fractions truncate
toward zero, including negative inputs. Weekdays number Sunday as zero through
Saturday as six; day-of-year starts at one. Gregorian leap-century rules apply.
Histograms are silently omitted, metric names are removed and other labels
survive; resulting collisions reject the query.

Calendar conversion freezes Go 1.25 arm64 behavior for exceptional values:
NaN becomes epoch zero, positive overflow/infinity saturates to signed-int64
maximum seconds and negative overflow/infinity to its minimum. Go's absolute
UTC epoch wraps at these extremes, yielding very large positive years. This is
not a universal Go architecture/version promise; use finite, in-range Unix
seconds for portable calendar queries. Existing sample/work/result budgets
apply, including default-time queries. Upgrade all query-serving applications;
native artifacts, storage and keyed-ingest bytes are unchanged.

`sort_by_label(vector, "label", ...)` orders instant results by the supplied
label priorities; `sort_by_label_desc` reverses that order, including ties.
Zero label arguments are allowed. Requested values use case-sensitive natural
ordering of ASCII digit runs (`node2` before `node10`); only runs fitting int64
compare numerically, otherwise they compare lexically. Non-ASCII digits are
ordinary text. When all requested strings are identical, the full label set,
including the metric name, breaks ties lexically by sorted label name/value,
not by natural ordering or label count. Missing labels have empty values.
The pinned upstream comparator does not define a consistent order for unequal
strings with equivalent numeric chunks (such as leading zeros), or empty versus
nonempty values; do not rely on their relative order across implementations.

Label sorting preserves names, labels, floats, signed zeros, NaNs, infinities
and native histograms. Comparisons charge label lookup and inspected bytes to
the shared work budget. Range queries bypass sorting and retain their normal
label ordering. Value-based `sort` and `sort_desc` omit histogram-valued points
in both instant and range queries, including single-step ranges; mixed series
retain their float points and histogram-only series disappear. Range value
sorting still does not reorder results. All four sort functions emit a
deduplicated warning when range start and end differ, including empty inputs;
a one-time range has no warning.
Diagnostics omit upstream expression positions and remain local to each batch
source. Existing sample/result/heap limits apply. Upgrade all query-serving
applications; no native or stored-format change is required. Experimental
upstream function flags are not reproduced.

`y atan2 x` returns the quadrant-aware angle in radians, with the authored
operand order preserved for scalar/vector and grouped vector matches. It has
the same precedence as multiplication/division and associates left-to-right;
`bool` is invalid. Standard vector matching, uniqueness checks and arithmetic
metric-name removal apply. Explicit grouped inclusion of `__name__` can copy
the one-side name back after removal. Signed-zero quadrants, NaN and infinity
results remain samples; ordinary finite results use platform math and may differ
from Go by rounding. Any histogram operand omits only the matched result and
emits a deduplicated `infos` diagnostic naming both operand types in authored
order. Unmatched histograms emit nothing. Other unsupported histogram binary
combinations now emit the same type diagnostic instead of silently disappearing.
These infos omit expression positions. Existing instant/range and batch budgets
apply; upgrade all query-serving applications, without changing native artifacts,
storage or keyed-ingest bytes.

Grouped vector matching that produces the same final labels twice within one
matching group returns HTTP 422 with `errorType="execution"` and
`multiple matches for labels: grouping labels must ensure unique matches`.
Uniqueness checks run after filtering, independently at each evaluation step;
false `bool` samples still count as retained outputs. A collision fails the
whole query, not just that step. Ambiguous one-side matches and unrelated
duplicate output identities retain their existing diagnostics. Upgrade all
query-serving applications for consistent error responses; successful samples,
resource ceilings, native artifacts, storage and keyed bytes are unchanged.

Invalid bounded regexes in PromQL `label_replace` reject before storage with
`invalid regular expression in label_replace(): <pattern>`. The response
remains HTTP 400 with `errorType="bad_data"`; destination validation, regex
admission and resource ceilings are unchanged. This diagnostic does not imply
complete upstream parser-error or HTTP-status parity.

`label_join(vector, "destination", "separator", "source", ...)` joins source
label values in argument order. Missing source labels contribute empty strings;
repeated sources contribute repeatedly, including when the destination is a
source. Every source reads the original labels before the destination changes.
An empty joined value removes the destination label; supplying no source
arguments also removes it. Nonempty UTF-8 source and destination names are
accepted, including punctuation and Unicode. Empty or invalid UTF-8 names reject
with HTTP 400 during parsing; upstream execution-error wording is not reproduced.

Only labels change: float/histogram observations, NaN, signed zero and evaluation
timestamps are preserved. The metric name survives unless the destination is
`__name__`; it can be created, replaced or removed. Identical output labels merge
across disjoint evaluation times, but overlap at any step fails the whole query.
Delayed metric-name removal is not implemented, so an inner expression's label
collision cannot be repaired by an outer join.

Each join charges source lookups and joined UTF-8 bytes, including separators and
repeated values, against the existing work budget before constructing the label.
The work ceiling is shared with other operations and batch sources; existing
sample, result and query-heap limits also apply. Upgrade every query-serving
application; no native artifact, storage format or keyed-ingest byte change is
required.

`present_over_time(series[window])` returns `1` for each series with at least
one nonstale sample in `(evaluation time - window, evaluation time]`, adjusted
for any signed offset or `@` anchor. Zero, NaN, infinities, native histograms and mixed
float/histogram windows all count as present. Empty or stale-only windows omit
the series rather than returning zero; a stale marker does not erase earlier
nonstale samples still inside the window. The metric name is removed and other
labels are preserved; resulting label collisions fail the query. Explicit-resolution
subqueries are supported, with the usual sample/work/result limits. Upgrade
every query-serving application; no native artifact or storage-format change
is required.

`first_over_time(series[window])` and `last_over_time(series[window])` return the
earliest and newest nonstale samples, respectively, in the same left-open/right-closed
window, including signed offsets, `@` anchors and explicit-resolution subqueries. In mixed
float/histogram windows, the selected timestamp determines the returned type;
native histograms retain their observations and buckets. Unlike most range
functions, both preserve the metric name and all other labels.
Zero, NaN and infinities remain values, while empty/stale-only windows omit the
series. A stale marker does not hide an earlier valid observation still inside
the window. The output timestamp is the evaluation step, not the source sample
time. Existing sample/work/result limits apply. Upgrade every query-serving
application; no native artifact, storage format or keyed-ingest byte change is
required.

`ts_of_first_over_time(series[window])` and `ts_of_last_over_time(series[window])`
return the earliest/newest nonstale observation's source timestamp as a float
in seconds, including fractional seconds, for floats, histograms and mixed
windows. The result point itself is timestamped at the evaluation step. Both
drop the metric name and preserve other labels; resulting label collisions
fail the query. Empty/stale-only windows omit output, but epoch-zero timestamps,
NaN/infinite sample values and zero-valued samples remain eligible. Signed
offsets and `@` anchors change selection without shifting the returned source time.
For explicit-resolution subqueries, the selected timestamps come from the
inner evaluation grid, not the original storage rows. Existing window bounds,
floating-point timestamp precision and sample/work/result limits apply.
Upgrade every query-serving application; no native artifact, storage format or
keyed-ingest byte change is required.

`ts_of_min_over_time(series[window])` and `ts_of_max_over_time(series[window])`
return the source timestamp of the minimum/maximum nonstale float in seconds,
including fractional seconds. Equal values, including signed zeros, select the
newest observation. NaN loses to any non-NaN value; an all-NaN float window
selects its newest observation. Histograms are ignored, with a top-level `infos`
annotation in mixed windows; histogram-only, empty and stale-only windows omit
output silently. The result point is timestamped at the evaluation step, and the
metric name is removed, preserving other labels; resulting collisions fail.
Signed offsets and `@` anchors change the window, not the returned source time. Explicit-resolution
subqueries select inner-grid timestamps. Existing left-open/right-closed bounds,
floating-point timestamp precision and sample/work/result limits apply. Upgrade
every query-serving application; no native artifact, storage format or keyed-ingest
byte change is required.

`idelta(series[window])` subtracts the penultimate nonstale observation from the
newest one. It neither corrects resets, divides by elapsed time nor extrapolates
to the window boundaries. Fewer than two observations omit output. Only the last
pair determines the types and warnings: two floats subtract normally (including
NaNs/infinities), two native histograms subtract into a gauge histogram, and a
mixed pair is omitted with a warning. Histogram pairs with either observation
not marked as a gauge warn but still subtract. Exponential/custom pairs omit
with a warning. Differing custom bounds coarsen to their intersection, rolling
remaining upper buckets into `+Inf`, and report an info notice.

The metric name is removed; other labels and evaluation timestamps are preserved.
Signed offsets, `@` anchors and explicit-resolution subqueries use the ordinary
left-open/right-closed window. Native bucket/bound traversal spends shared query
work in addition to the existing sample/result budgets. Upgrade query-serving
applications; native artifacts, storage formats and keyed-ingest bytes are unchanged.

`irate` also reads only the last nonstale pair, but corrects counter resets and
divides the change by elapsed seconds. A gauge hint on either native histogram
warns without suppressing the result. For differing custom bounds, reset
detection compares plain bucket totals at common boundaries, including `+Inf`;
changed boundaries alone are not a reset. A reset uses the newest histogram
directly, so it reports no subtraction/schema-reconciliation notice.

`delta` extrapolates the first-to-last change over the requested window without
correcting counter resets. Any float/native mixture in that window omits the
series with a warning. For histogram-only windows, only the endpoints determine
schema compatibility and gauge warnings; middle histogram schemas/hints do not
change the subtraction. Differing endpoint custom bounds coarsen with an info
notice. Fewer than two observations produce neither output nor these notices.

`rate` and `increase` inspect every retained native observation. Gauge hints
warn; mixed float/native windows and unrecoverable bucket-family mixtures omit
the series with a warning. A first-pair reset can discard the first layout,
allowing an otherwise incompatible family transition. Original endpoint gauge
hints still warn. Custom reconciliation notices describe executed endpoint
subtraction or reset-recovery additions, not every intermediate layout change.
A failed middle-family check replaces that window's earlier gauge notices;
other windows and batch sources keep their own notices. Native bucket/bound
work charges the shared query/batch budget before reset detection and mapping.

When `rate` or `increase` produces a float result, a nonempty metric name not
ending in `_total`, `_sum`, `_count` or `_bucket` adds a deduplicated query-local
`infos` notice that it might not be a counter. This is a naming heuristic, not
counter-type validation. Histogram-only outputs, omitted windows and empty names
do not receive this notice; samples and arithmetic are unchanged. Upgrade
query-serving applications for consistent annotations; no native/storage change.

`changes(series[window])` counts unequal consecutive nonstale observations;
`resets(series[window])` counts counter resets. For floats, any decrease is a
reset, consecutive NaNs are not changes, comparisons involving NaN are not
resets, and positive/negative zero compare equal. For native histograms,
`changes` compares complete observations and bucket layouts, ignoring reset
hints; `resets` uses native-histogram reset detection, including count/bucket
decreases, incompatible schema/zero-threshold changes and reset hints. A sum-only
change is not itself a reset. Every float-to-histogram or histogram-to-float
transition counts for both functions, including transitions involving a NaN
float. Observations are compared in timestamp order, not separately by type.

Both functions remove the metric name and preserve other labels; resulting
collisions fail the query. A single nonstale observation returns zero;
empty/stale-only windows omit output. Stale markers are ignored rather than
breaking comparisons between valid observations. The same left-open/right-closed
windows, signed offsets, `@` anchors, explicit-resolution subqueries and sample/work/result
limits apply. Parentheses around a range argument and unitless windows are
accepted; `anchored` modifiers remain unsupported. Upgrade every query-serving
application; no native artifact, storage format or keyed-ingest byte change is
required.

`deriv(series[window])` returns the least-squares slope per second over the
window's nonstale float samples. It is for gauges: decreases remain decreases,
with no counter-reset correction or boundary extrapolation. At least two float
observations are required. Finite constant series return zero, including very
large values; NaN or infinite observations produce NaN. Actual sample times,
not sample indices or absolute floating-point epoch times, determine the slope.
The metric name is removed, other labels survive and resulting collisions fail
the query. Normal window bounds, signed offsets, `@` anchors, explicit-resolution subqueries
and sample/work/result limits apply.

`deriv` and `predict_linear` ignore histograms in mixed float/histogram windows
and return a top-level `infos` annotation, even if fewer than two floats remain
and the window produces no result. Histogram-only windows omit output silently;
stale histograms and histograms fetched outside evaluated windows do not create
notices. These mixed-range diagnostics include the quoted input metric name
(empty after name-removing expressions), deduplicate per metric name within a
query and do not leak between sources in a query batch. They omit upstream
expression positions; quoting for arbitrary names and the complete annotation
taxonomy are not full PromQL annotation parity. Upgrade every query-serving
application; no native artifact, storage format or keyed-ingest byte change is
required.

`mad_over_time(series[window])` returns the median of the absolute differences
from the window's median, over nonstale floats. This is median absolute
deviation, not mean absolute deviation or standard deviation; no scale factor
is applied. Even-sized medians average the two middle values using half-weighted
terms, avoiding overflow from adding large finite values first. A single finite
value returns positive zero. Any NaN input produces NaN; infinities follow
IEEE arithmetic, so an infinite median can produce NaN deviations rather than
being dropped or clamped.

Histograms in mixed windows are ignored with the same query-local `infos`
diagnostic as `deriv`; histogram-only and empty/stale-only windows omit output
silently. The metric name is removed, remaining labels survive and collisions
fail the query. Signed offsets, `@` anchors and explicit-resolution subqueries use the
usual window rules. In addition to scan and sample costs, both median sorts
reserve conservative logarithmic work against the existing query work ceiling,
shared across windows and batch sources; large windows may exhaust it before
the sample limit. Upgrade every query-serving application; no native artifact,
storage format or keyed-ingest byte change is required. Upstream expression-position
diagnostics and experimental-function feature flags are not reproduced.

`quantile_over_time(q, series[window])` gives equal weight to each nonstale float
observation, regardless of its timestamp spacing. It sorts values with NaNs
before all other values and interpolates between neighboring ranks at
`q * (sample_count - 1)`. Exact ranks return the observation directly, without
arithmetic with a neighboring NaN or infinity. Interpolation uses weighted
terms rather than subtracting endpoints; IEEE nonfinite arithmetic still applies.
NaNs do not necessarily poison higher quantiles when their ranks are not used.

The scalar `q` may vary per evaluation step. Signed range/subquery offsets and
`@` anchors change selected observations, not the scalar's evaluation time. A NaN quantile
returns NaN; quantiles below zero return negative infinity and those above one
return positive infinity, with a deduplicated top-level `warnings` annotation.
Warnings are emitted only for windows with at least one float and remain local
to each query-batch source. Exact upstream expression positions and diagnostic
number formatting are not reproduced.

Mixed float/histogram windows ignore histograms and include the metric-named
`infos` diagnostic described above; histogram-only, empty and stale-only windows
omit output silently. The metric name is removed, other labels survive and
collisions fail the whole query. Existing window bounds, explicit-resolution
subqueries, sample/result/heap limits and shared batch budgets apply. Every
nonempty float window reserves conservative logarithmic sorting work before
allocating the sorted values, including invalid quantiles. Upgrade every
query-serving application; no native artifact, storage format or keyed-ingest
byte change is required.

`double_exponential_smoothing(series[window], sf, tf)` smooths gauge observations
with a level and an estimated trend; `holt_winters` is an alias. Initial level
is the first float and initial trend is the second float minus the first.
Each later observation updates the level, with subsequent trends weighted by
`tf`. The recurrence advances once per observation, independent of timestamp
spacing. This is not a counter-reset correction or a time-based regression.
At least two nonstale floats are required to return a value.

Both scalar factors may vary at outer query steps; signed range/subquery
offsets and `@` anchors change observations, not factor evaluation. Factors must be strictly
between zero and one. A nonempty window with an out-of-range or infinite factor
fails the whole query with an execution error (HTTP 422), even if it contains
only histograms or a single float. Empty/stale-only windows omit output before
factor validation. NaN factors follow IEEE arithmetic rather than being rejected;
a NaN trend factor does not affect a two-float window because its initialized
trend is used directly. NaN/infinite observations are not discarded or clamped.

Mixed float/histogram windows ignore histograms with the metric-named `infos`
diagnostic described above, even when fewer than two floats remain.
Histogram-only windows with valid factors omit output silently. Metric names
are removed and resulting label collisions fail the query. Normal window bounds,
explicit-resolution subqueries and shared sample/work/result/heap budgets apply.
Upgrade every query-serving application; no native artifact, storage format or
keyed-ingest byte change is required. Upstream experimental-function feature
flags, expression-position annotations and exact diagnostic formatting for
arbitrary finite factors are not reproduced.

`clamp(vector, min, max)` accepts scalar bounds, including expressions that
change at each range-query step. An inverted interval (`min > max`) omits that
step's samples; equal finite bounds clamp to that value. Native histograms are
ignored and the metric name is removed, preserving other labels. Unless the
interval is inverted, NaN inputs or bounds produce NaN, including when combined
with infinities, following Mimir's built-in `min`/`max` semantics. Signed-zero
ties use the upper bound first, then the lower bound. All inputs still spend
the usual query budgets even when an inverted interval produces no output.
Upgrade every query-serving application; this function requires no native
artifact or storage-format change.

The basic math functions `ceil`, `sqrt`, `exp`, `ln`, `log2`, and `log10`
follow Prometheus 3.5.0 semantics. Each takes one instant vector, ignores native
histogram samples, removes the metric name, and preserves other labels. Negative
square roots and negative logarithm inputs return `NaN`; logarithms of either
signed zero return `-Inf`. `sqrt` preserves signed zero. `exp` overflows to
`+Inf` and underflows through subnormal values to positive zero. These values
are successful query results, not query errors. Instant and range queries use
the same sample/work/result limits as other vector transforms. The numerical
oracle is Prometheus 3.5.0 built with Go 1.24.5 on arm64. `exp` and `log2`
reproduce that implementation's reduction and scaling, including its early
underflow (`exp(-745)` returns zero rather than the smallest subnormal).
This is a compatibility choice, not a correctly rounded mathematics guarantee
or bit-identical parity with every Go version and architecture. Other finite
results can differ by floating-point rounding. Upgrade every query-serving
application before using these functions in dashboards or alert expressions;
no native artifact, storage format or keyed-ingest byte change is required.

`deg(vector)` converts radians to degrees; `rad(vector)` converts degrees to
radians. Both ignore native histograms, drop the metric name, preserve other
labels, and retain IEEE signed-zero/NaN/infinity behavior. Each multiplies by
one pre-rounded constant, avoiding intermediate overflow for large finite
conversions such as `rad(vector(1e308))` and `deg(vector(1e306))`. Actual overflow
returns signed infinity, not an execution error. `pi()` takes no arguments and
returns the scalar `3.141592653589793` at each evaluation step: an instant query
returns a scalar envelope, while a range query returns an empty-label matrix.
Use `vector(pi())` where an instant vector is required. Existing selector,
work and result budgets apply; constant-only queries read no stored samples.
Upgrade every query-serving application before relying on these functions;
no native artifact, storage format or keyed-ingest byte change is required.

`asin(vector)`, `acos(vector)` and `atan(vector)` return angles in radians.
`asin` and `acos` accept the closed interval [-1, 1]; values outside it,
including either infinity, return `NaN` for that sample without failing the
query. `atan(+Inf)` and `atan(-Inf)` return positive and negative π/2. All three
propagate NaN, ignore native histograms, remove the metric name and preserve
other labels. `asin` and `atan` preserve signed zero and tiny subnormal inputs;
`acos(1)` returns positive zero. Duplicate result identities fail whole.
Finite results use the platform math library and can differ from Go by
floating-point rounding; bit-identical parity across platforms is not promised.
Existing instant/range sample, work and result budgets apply, including nested
expressions, offsets and batches. Upgrade every query-serving application;
no native artifact, storage format or keyed-ingest byte change is required.

`sin(vector)`, `cos(vector)` and `tan(vector)` take angles in radians. Every
finite binary64 input is accepted; NaN and either infinity produce per-sample
`NaN`, not a query failure. Native histograms are ignored, the metric name is
removed, and other labels are preserved. `sin` and `tan` preserve signed zero
and tiny subnormal inputs; `cos(±0)` returns one. Duplicate result identities
fail whole. Finite results use platform math, including its argument reduction:
do not assume Go bit identity, clamp near-zero residuals to zero, or treat the
nearest floating-point value to π/2 as an exact pole. Existing instant/range,
nested-expression, offset and batch budgets still apply. Upgrade every
query-serving application; no native artifact, storage format or keyed-ingest
byte change is required.

`sinh(vector)`, `cosh(vector)` and `tanh(vector)` accept all finite values and
propagate NaN. `sinh(±Inf)` returns the same infinity; `cosh(±Inf)` returns
positive infinity; `tanh(±Inf)` returns ±1. `sinh` and `tanh` preserve signed
zero and tiny subnormals; `cosh(±0)` returns one. All three ignore native
histograms, remove metric names and preserve other labels. Duplicate result
identities fail whole. To match Go's observable overflow behavior, `sinh` and
`cosh` use `exp(abs(x)) / 2` for magnitudes above 21: magnitudes above
709.782712893384 overflow, including `sinh(710)` and `cosh(-710)`, even though
some platform libraries can return finite values there. Overflow produces
signed infinity for `sinh` and positive infinity for `cosh`, not an execution
error; `tanh` saturates to ±1. Other finite results use platform math and can
differ from Go by rounding, without a bit-identical guarantee across platforms.
Existing instant/range, expression, offset and batch budgets apply. Upgrade all
query-serving applications; native artifacts, storage and keyed-ingest bytes
are unchanged.

`asinh(vector)`, `acosh(vector)` and `atanh(vector)` return inverse hyperbolic
values. `asinh` accepts all finite inputs and preserves signed infinities;
`acosh` accepts values at least 1, returning positive zero at 1 and positive
infinity at `+Inf`. `atanh` accepts the closed interval [-1, 1], returning
signed infinity at its endpoints. Other out-of-domain values, including either
infinity for `atanh` and negative infinity for `acosh`, produce per-sample
`NaN` rather than query failure. All three propagate NaN, silently ignore native
histograms, remove metric names and preserve other labels. `asinh` and `atanh`
preserve signed zero and tiny subnormal inputs; `asinh` and valid `acosh`
remain finite even at the largest finite binary64 input. Duplicate result
identities fail whole. Finite results use platform math and can differ from Go
by rounding, without a cross-platform bit-identity promise. Existing instant/
range, expression, offset and batch budgets apply. Upgrade all query-serving
applications; native artifacts, storage and keyed-ingest bytes are unchanged.

```text
sum by (job) (rate(http_requests_total{job="api"}[5m]))
avg without (instance) (process_resident_memory_bytes)
```

```text
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
sum(rate(http_requests_total{status=~"5.."}[5m])) / clamp_min(sum(rate(http_requests_total[5m])), 0.001)
```

Classic histograms use ordinary float bucket series with a `le` label and a
`+Inf` bucket. Bounds accept Go floating-point spelling (including `.5`,
hexadecimal floats, and case-insensitive infinity). Missing, malformed and NaN
bounds are skipped with warnings. Quantiles outside [0,1], including NaN, warn
even on empty input. Decreasing counts are repaired with an info notice;
numerically insignificant changes in either direction are repaired silently.
The comparison handles very large finite and subnormal counts without
arithmetic errors; changes exactly at the tolerance are not silently repaired.
A missing positive-infinity final bucket returns NaN without a repair notice.
Histograms with different metric names remain distinct; use explicit aggregation
to combine them before computing quantiles. Sums and averages use compensated
summation to limit cancellation. Upgrade query applications for corrected
quantiles at these numerical extremes; storage and keyed bytes are unchanged.

`histogram_fraction(lower, upper, vector)` accepts classic bucket series as
well as native histograms. Classic fractions use linear interpolation and
require a final `+Inf` bucket. Zero totals, missing `+Inf` and NaN bounds return
NaN; otherwise lower ≥ upper returns zero. Duplicate bounds combine before
interpolation. Fractions do not apply quantile monotonicity repair or emit its
repair notice, so decreasing cumulative counts can produce negative fractions.

Custom-native fractions preserve the original custom bucket boundaries across
zero; they do not use exponential zero-bucket clipping. A first custom bucket
with a positive upper boundary begins at zero. A first bucket starting at `-Inf`
contributes its full population at finite interior bounds; a last bucket ending
at `+Inf` contributes none there. Linear interpolation computes the width
fraction before multiplying by the population, avoiding unnecessary intermediate
overflow or underflow. Upgrade query applications for these corrected fraction
answers; native artifacts, storage and keyed bytes are unchanged.

### Native histograms

Native histograms arrive over Remote Write 1.0 or 2.0 (Prometheus
`send_native_histograms: true`). Pulse uses Prometheus 3.5.0's semantics as its
base, with the NaN-sum quantile, counter extrapolation, negative-scaling gauge
identity, compensated aggregation and arithmetic/reset
corrections described below:

- Selectors return histograms, reported under `histogram` (instant vectors) or
  `histograms` (ranges) with Prometheus' bucket boundary rules
- `rate`, `increase` and `irate` handle counter resets, schema changes
  and zero-threshold changes; `delta` extrapolates endpoint differences without
  correcting resets; `sum_over_time` and `avg_over_time` combine
  histograms; `count_over_time` counts them
- `idelta` subtracts the last pair without reset correction, time scaling or extrapolation
- `sum` and `avg` combine histograms, `count` and `group` count them
- `histogram * scalar`, `scalar * histogram`, `histogram / scalar`, and `+`, `-`,
  `==`, `!=` between histograms
- Mimir histogram trims `histogram </ cutoff` and `histogram >/ cutoff`,
  with scalar or matched float-vector cutoffs
- Negative multiplication/division and unary negation produce gauge histograms.
  Later arithmetic preserves that gauge identity, including double negation.
  Positive factors, signed zero and NaN retain the input's reset hint;
  division by either zero removes all ordinary buckets without changing the hint.
- `histogram_quantile` and `histogram_quantiles` (native and classic series in one vector),
  `histogram_fraction`, `histogram_count`, `histogram_sum`, `histogram_avg`,
  `histogram_stddev` and `histogram_stdvar`

Native variance/deviation and histogram equality/inequality charge bucket slots
and custom bounds to the shared query/batch work ceiling before traversal,
including empty slots and false or `bool` comparisons. Exhaustion fails the
whole query or batch. Count/sum/average read stored totals without this traversal
charge. Multiplication, nonzero division and unary negation also charge bucket
slots before scaling, including empty slots and multiplication by zero.
Unary plus and division by zero do not traverse buckets; scaling does not read
or charge unused custom bounds. Repeated steps and query-batch sources share the
same work ceiling even beneath scalar property functions. Upgrade query-serving
applications for this stricter accounting; no native artifact, storage or
keyed-byte change is required.

Functions, aggregations and comparisons that only read floats (`min`, `max`,
`topk`, `abs`, `min_over_time`, `>`, and so on) leave histograms out, and
`min_over_time`/`max_over_time` retain float extrema with an info annotation
when a window also contains histograms. Histogram-only extrema are empty
without that notice. Operations requiring a single sample type, such as
`sum_over_time`, omit mixed windows instead. Custom-bucket histograms
(schema -53) are supported. Arithmetic mixing them with exponential ones has
no result; `irate` can instead treat a
changed bucket family as a reset and use the newest histogram directly.
`stddev_over_time`/`stdvar_over_time` likewise ignore histograms and add info only
for mixed windows, not histogram-only input. Upgrade query-serving applications
for these notices; numerical results are unchanged.

Native addition and subtraction reconcile differing custom layouts to their
common bounds, rolling remaining buckets into `+Inf` with source-ordered
compensated accumulation. Binary `+`/`-` and `idelta`/`irate`/`delta` report
executed reconciliations. Binary subtraction produces gauge histograms;
addition preserves the inputs' combined gauge/reset hints. Binary histogram
arithmetic charges bucket/bound work to the shared query/batch budget before
mapping. Incompatible exponential/custom pairs are omitted with an
incompatible-bucket-layout warning. Successful addition/subtraction of explicit
reset/no-reset hints retains its computed value with a conflicting-counter-reset
warning; unknown or gauge hints alone do not cause that warning. Schema rejection
precedes hint diagnostics. Notices deduplicate per query and remain isolated
between query-batch sources; expression positions are not included.
Native `sum`, `avg`, `sum_over_time` and `avg_over_time` report custom
reconciliation, conflicting original reset/no-reset hints and incompatible
families; mixed float/histogram inputs warn and omit their group or window.
An intervening gauge or unknown hint does not hide a reset conflict. Histogram
aggregation charges input buckets/bounds to the shared query/batch work limit;
exhaustion fails the whole query, not just a group. Notices stop at the first
incompatible family, retaining earlier notices. Counter range functions report
executed reconciliation separately. Histogram sums retain separate compensation
for counts, sums, zero buckets and both bucket sides, including resolution,
zero-threshold and custom-bound changes. Averages use direct compensated sums
until any histogram field would overflow, then use a weighted incremental mean.
Ordinary binary addition remains uncompensated. This follows the upstream
floating-point algorithm, not arbitrary-precision arithmetic; processing order
can still affect results. Implicit iterator-generated reset hints and complete
annotation parity remain open.
Custom-bound reset detection compares reconciled interval totals. Matching-layout
and exponential detection examine every remaining previous bucket after the
current buckets run out: zero-valued gaps cannot hide a disappeared populated
bucket. Zero-threshold widening uses the pinned upstream compensated traversal;
explicit reset/no-reset hints retain precedence. These corrections do not
establish full native arithmetic parity. Upgrade query-serving applications;
native artifacts, storage and keyed bytes are unchanged.

`histogram </ cutoff` removes observations above the cutoff; `histogram >/ cutoff`
removes observations below it. Split exponential buckets use logarithmic
interpolation; custom and zero buckets use linear interpolation. Retained sums
are estimated from bucket midpoints. Biased zero buckets and infinite endpoints
follow Mimir's rules. If no population changes, original count/sum remain exact;
otherwise totals are recomputed and empty buckets removed. Names and reset hints
survive trimming, subject to ordinary vector matching/grouping label rules.
Only histogram-left/float-right pairs return samples; other matched types are
omitted with an info notice. Trims share comparison precedence, associate left,
and reject `bool`. Scalar-only trims reject before storage rather than reaching
upstream's unsupported scalar execution. Bucket/bound work shares the existing
query/batch ceiling; exhaustion fails the whole operation. Arithmetic retains
Pulse's unfused histogram profile, not bit parity with Go builds using fused
multiply-add. Upgrade query-serving applications; no native/storage/keyed-byte
change is required.

`histogram_quantile` omits classic/native pairs with the same input metric name
and labels at an evaluation step, with a warning; unrelated groups still return.
Only valid classic bounds participate, and a native histogram's own `le` label
remains part of its identity. Native NaN observations report distinct quantile
NaN/skew and fraction-exclusion info notices. Notices are deduplicated within
each query and isolated between sources in a query batch. Diagnostics omit
upstream expression positions. Classic repair notices use the generic message,
as does the pinned Mimir streaming engine; expanded repair summaries belong to
its vendored Prometheus engine, not that Mimir compatibility target.
Multi-bucket NaN-sum quantiles interpolate within the bucket containing the
requested rank, following the corrected Mimir behavior rather than Prometheus
3.5.0's last-bucket quirk. A NaN sum caused by ±Inf observations alone does not
produce a NaN-observation notice. Other native arithmetic remains at its existing
compatibility level. Upgrade query-serving applications for these query changes;
no native or stored-format upgrade is needed.

Native counter `rate`/`increase` limit left-boundary extrapolation at the estimated
zero point of the histogram count, matching Mimir. The original first count and
reset-corrected count increase determine one shared factor for the entire
histogram, even if reset handling discards the first histogram. This does not
limit individual buckets or the sum at zero: their extrapolated values may
exceed the final observation. Gauge `delta` and instantaneous `irate` are unchanged.
Upgrade query-serving applications; storage and keyed bytes are unchanged.

`histogram_quantiles(vector, "label", q0, ...)` emits one labeled result per
quantile at each step. Quantiles may vary over time. The destination overwrites
an existing label; the metric name is removed, including when it is the
destination. Quantile labels use OpenMetrics formatting (`0.0`, `1.0`, `NaN`,
`+Inf`, `-Inf`); positive and negative zero share `0.0`. Duplicate resulting
labels at the same step fail the entire query; disjoint steps merge. Potential
fan-out spends the shared intermediate-sample budget before output construction.
Quantile bucket traversal and generated label bytes spend shared work. Ceilings
are unchanged, but large histogram queries may now reach the work cap earlier.

Within one remote-write request, a float sample wins over a native histogram
at the same series identity and timestamp, including across separate entries
with the same labels. The histogram is not stored, and exemplars still attach
to the surviving samples. This is request-local normalization, not a
cross-request conflict registry or a repair of previously stored collisions.
All supplied points still consume ingestion admission budgets. Before upgrading
receivers, drain keyed retries containing these collisions and replace every
receiving instance: their normalized caller content and segment bytes change.
Replaying them across versions can derive different object keys and duplicate
already stored data. Byte disagreements at the same derived key still return
`409 keyed_content_mismatch`, never an overwrite or a semantic-equivalence
shortcut. Ordinary noncolliding requests keep their existing encoding.

Not supported yet: `anchored`/`smoothed` modifiers,
and functions outside the lists above. Regular expressions use a
bounded RE2-compatible subset. Braced hexadecimal escapes support following
repetition, such as `\x{61}+` and `\x{61}{2}`; their braces are not repetition
counters. Literal quoting (`\Q...\E`) and octal escapes are supported, as
described under [shared query regex semantics](#shared-query-regex-semantics).
Unsupported constructs return errors, including lookarounds, backreferences,
and some character-class and capture-name forms. Full Prometheus language
compatibility is not claimed.
Unsupported expressions and parameters return an error. `timestamp(selector)`
returns the original sample time; `timestamp(derived_expression)` returns its
evaluation time. Millisecond-aligned timestamps match Prometheus conversion;
Pulse retains sub-millisecond precision for other inputs. Metric-name removal
merges disjoint lifetimes in range results, but simultaneous label collisions
remain errors.

For ambiguous mixed matchers on one label, `absent`/`absent_over_time` label
inference follows the local Prometheus TSDB's intersecting-before-subtracting
matcher order. Backends that do not mutate matcher order can differ. Prefer
one exact matcher per label for portable absent-instance identity; verify any
mixed-matcher rule against its former backend before migration. The inventoried
Tuist absence expressions do not use that ambiguous form.

Raw `query_metrics` results preserve storage markers as JSON strings:
`"stale"`, `"nan"`, `"infinity"`, and `"negative_infinity"`. These are distinct from
the Prometheus evaluator's string-valued result numbers.

### Datasource metadata

For Grafana's Prometheus datasource, `/api/v1/status/buildinfo` reports the
Prometheus API version Pulse follows. GET/form-POST `/api/v1/format_query`
validates and formats the supported PromQL subset without reading storage or
executing the query. For example, `count(up)by(foo)` becomes
`count by (foo) (up)`. Formatting normalizes spacing, grouping placement,
string quoting, durations and numeric literals while preserving evaluation
order, vector matching and selector order. Comments and redundant parentheses
are not retained. Output is single-line, not byte-for-byte Mimir/Prometheus
multiline pretty-printing; unsupported language features still return HTTP 400.
Both input and output must fit the existing 16 KiB query limit. A valid input
whose escaped strings or fixed-decimal literals expand beyond that limit also
returns HTTP 400, never an unusable formatted query. Authentication still applies.
Upgrade all query-serving applications for consistent formatting behind a load
balancer. No storage, native ABI, configuration or keyed-byte change is involved.

`/api/v1/query_exemplars` returns the exemplars of every series the query's
selectors select, with timestamps in `[start, end]` (`end` defaults to now,
`start` to an hour before it), as Prometheus does. Exemplars come from Remote
Write (`send_exemplars: true`) and OTLP metrics, where each point exemplar
becomes a Prometheus exemplar with `trace_id`, `span_id` and its filtered
attributes, on the `_bucket` series whose bound holds its value for
histograms. Exemplars are stored with their series' samples and expire with
them. As in Prometheus, label sets over 128 characters are dropped.

`/api/v1/metadata` returns the type, help and unit that remote-write senders
report for each metric family (Remote Write 1.0 metadata messages, or the
per-series metadata of Remote Write 2.0; Alloy sends it only over 2.0, see
[deployment](deployment.md)), with Prometheus's `metric`, `limit` and
`limit_per_metric` parameters. Every distinct variant a metric is reported with
is kept, most recently reported first. Variants unreported for 30 days expire;
each tenant keeps at most 8 variants per metric, 50,000 metrics and 8 MiB of
metadata, dropping the least recently reported first. Metadata is stored before
the request that carried it is acknowledged, so a failure returns HTTP 503 and
the sender retries without duplicating samples. Every instance serves the
latest stored metadata. OpenTelemetry metric descriptions and units are not
yet reported here. Tempo's `/api/echo` and `/api/status/buildinfo` answer Grafana's
Tempo health checks.

The 8 MiB metadata cap is checked on object-store reads as well as updates.
An oversized historical metadata object fails closed; Pulse does not download,
truncate or delete it automatically. Metadata queries and subsequent remote-write
metadata updates can remain unavailable until an operator arranges a coherent,
versioned backup/repair in a separate maintenance procedure. Preserve the original
object and version evidence; there is no automatic repair command.

## Loki API

`/loki/api/v1/query` and `/loki/api/v1/query_range` evaluate LogQL. They take
the tenant in the `X-Scope-OrgID` header, like Loki, or the username of HTTP
Basic credentials when the header is absent.

Raw-log `/query_range` windows are start-inclusive and end-exclusive:
`start <= timestamp < end`, before ordering and `limit`. A line exactly at
`end` is not returned; equal bounds produce no lines after normal validation.
Upgrade query-serving applications for consistent range boundaries. Metric
evaluation keeps its inclusive end; instant log queries, discovery/detected
APIs and MCP/shared storage bounds are unchanged. No native/storage-format change.

When a range query omits `step`, the resolution is the window duration divided
by 250, rounded down to whole seconds, with a one-second minimum, as in Loki.
Supply `step` explicitly when you need a finer grid: a coarse default grid may
not include observations near the end of the requested window.

Metric results use Loki's sample format: `[<Unix seconds as a JSON number>,
"<value>"]`, with values formatted as Prometheus and Loki do (`"8"`, not
`"8.0"`). Log results keep nanosecond timestamp strings.

Finite Loki read failures return JSON, not Loki's plaintext error-writer bodies.
Invalid queries and request-local interval limits return HTTP 400; query-worker
deadlines return 504, admission overload returns 429, and worker failures return
500. Storage failures return 503 with `storage_unavailable` and the fixed message
`Storage is unavailable.`; provider error terms are not included. Scan, sample,
work and result-budget rejections remain 422; worker heap kills return 500.
Failed requests return no partial query result.
These are Pulse's error contracts, not exact Loki error compatibility: client
cancellation/499 responses, internal gRPC status roundtrips and aggregate-error
precedence are not implemented. An omitted tenant still uses the default tenant
when authorized, rather than Loki's missing-org-ID error.

Literal-only instant expressions return `resultType="scalar"` with one
`[evaluation_time, value]` pair; `vector(2)` remains a vector. Range requests
return matrices for both forms. Scalar comparisons return 0/1 with or without
`bool`. Literals accept decimal/exponent forms, separators and hexadecimal
floats with a `p` exponent, not `0b`, `0o` or hexadecimal integers. Overflowing
or malformed literals reject. A sign applies only to a number (`-2^2` is 4),
not a vector or parenthesized expression; use `0 - expression` to negate one.
LogQL division by either signed zero returns NaN for scalar and vector operands;
PromQL retains its separate signed-infinity semantics. These queries still
require authorization and spend existing work/output budgets, including in
mixed-source batches, even when no storage is read. Upgrade all query-serving
applications before relying on the corrected wire types or arithmetic; there
is no native ABI, storage or keyed-byte change.

`approx_topk(k, expression)` is available for instant metric queries, using
**exact ranking under the ordinary query budgets**. It does not implement
Loki's count-min sketches, distributed sketch merging or high-cardinality
acceleration: reducing `k` does not reduce input scan/sample/intermediate-result
costs, and exhausted budgets fail the whole query. Use a positive signed-int64
integer literal for `k`; fractional, decimal/exponent and overflowing ranks
reject. Outer `by`/`without` grouping, including empty grouping, rejects; put
grouping in an inner aggregation such as `sum by (job) (...)`. Range queries
reject this operator, even inside another aggregation or arithmetic expression,
before reading storage. Existing `topk`/`bottomk` behavior is unchanged.
Upgrade every query-serving application instance before clients depend on the
new syntax behind non-sticky routing. No storage migration, native upgrade or
keyed-retry drain is required for this operator.

`label_replace(expression, "destination", "replacement", "source", "regex")`
rewrites the final labels of each instant or range metric result, including
structured metadata and parsed fields after collision resolution. The regex
matches the entire source value; a missing source is empty, and a nonmatch
leaves labels unchanged. Captures support `$1`, `${1}`, named references and
`$$` for a literal dollar. A matched empty replacement deletes the destination.
Unlike PromQL, `.` does not match newlines unless the pattern enables `(?s)`.
Rewriting labels does not aggregate sample values. Invalid regexes and nested
selector/range policies reject before storage; wrapping `approx_topk` does not
make it available to range queries. Existing work/result/heap bounds apply.
Upgrade all query-serving applications; no native, storage or keyed-byte change
is required. Full parser-error wording and distributed/client parity remain open.

`approx_count_distinct(field, {selector} | pipeline [range])` counts nonempty
string label or parsed-field values in instant and range metric queries.
Counting is **exact within existing query budgets**, not HyperLogLog or
distributed sketch merging. Repeated values count once across streams within
each output group and evaluation window; numeric-looking strings such as
`"01"`, `"1"` and `"1.0"` remain distinct. Missing and empty fields contribute
nothing, and empty windows emit no sample rather than zero.

Without grouping, output labels retain the pipeline labels except the counted
field. Use suffix `by (version)` to combine streams by selected labels, or
`by ()` for one unlabeled series. `without`, grouping by the counted field,
`unwrap` and nonpositive windows reject. Each window uses `(time - range, time]`,
shifted by an optional `offset`. Ordinary pipeline-error rejection still applies.

This operator retains detached string observations in the Elixir evaluator,
not native numeric samples. Every retained observation, including duplicates,
spends the existing selected-log-sample and materialized-sample budgets (the
latter defaults to 100,000); each window visit also spends work. Scan, result,
deadline and heap limits still apply and failures return no partial answer.
This is not high-cardinality acceleration or a dedicated string-byte memory
ceiling. Upgrade all query-serving applications before relying on the syntax;
no native/storage upgrade, migration or keyed-retry drain is required.

Pattern line filters (`|> "<_> level=error <_>"` and `!> "..."`) match lines
against a pattern in which `<_>` stands for any non-empty text, as in Loki: the
line must start and end where the pattern does, unless the pattern starts or
ends with `<_>`. Named placeholders and consecutive `<_><_>` are rejected.

Line filters accept `or` alternatives, for example `|= "error" or "warn"`,
`|~ "err.r" or "wa.n"` and `|> "level=error <_>" or "level=warn <_>"`.
Each alternative inherits the first operator. Positive operators keep a line
matching any alternative; negative operators (`!=`, `!~`, `!>`) drop a line
matching any alternative. Thus `!= "error" or "warn"` excludes both strings.
Adjacent filter groups still combine with AND and run at their authored pipeline
position, including after `line_format`. The `or` keyword is case-insensitive.
String and `ip(...)` alternatives can mix under `|=`/`!=`, not regex or pattern
operators. Every alternative validates before storage reads, even after an
always-matching alternative. Groups with alternatives run in the bounded Elixir
pipeline without native pushdown; existing expression, scan, work, sample,
result, deadline and heap ceilings apply. Upgrade query-serving applications;
no native/storage migration or keyed-retry drain is required.

`| decolorize` removes escape sequences matching Loki's ANSI-removal profile,
including ESC and Unicode U+009B markers and supported BEL-terminated forms.
Unmatched markers and following ordinary text are preserved. This is a specific
compatibility profile, not a general terminal-control sanitizer: some incomplete
numeric sequences match, while unsupported control forms remain in the line.
Later filters, parsers, templates and metric reductions see the rewritten line;
labels and source timestamps are unchanged. Existing query budgets still apply.
Upgrade query-serving applications for corrected escape handling; native
artifacts, storage/keyed bytes and resource ceilings are unchanged.

IP filters accept a single IPv4/IPv6 address, CIDR or inclusive same-family
range. Use `|= ip("192.0.2.1")` / `!= ip("192.0.2.0/24")` on the current line,
or `| remote_addr=ip("2001:db8::1-2001:db8::8")` / `!=ip(...)` on a label.
The `ip` keyword is case-insensitive and accepts whitespace before `(`.
Both forms search for embedded addresses, including inside a larger label
value; they are not whole-string equality. Label predicates can follow `unwrap`.
Missing labels fail both operators; a present empty label matches negation.
Prior pipeline errors pass IP label predicates unchanged and still require the
ordinary explicit error filtering before metric evaluation.

CIDRs mask host bits; IPv4-mapped IPv6 remains a separate family from IPv4.
The pinned Loki scanner recognizes bracketed IPv6 and short addresses such as
`::1`, but not a bare `::`. It consumes a maximal address candidate, so invalid
or port-bearing tokens do not imply retrying every suffix. Zoned single-address
patterns are accepted but cannot match the scanner's zone-free candidates;
ranges discard zones. Invalid addresses/prefixes, descending or mixed-family
ranges and unsupported operators reject with HTTP400 before storage reads.
Only line `|=`/`!=` and label `=`/`!=` are accepted, not `==`, regex or ordering
operators. IP filters use the bounded Elixir pipeline without native pushdown;
existing scan, work, retained-sample, result, deadline and heap limits still
apply. Upgrade query-serving applications; no native/storage migration or
keyed-retry drain is needed.

Pipeline label filters accept explicit `and`, comma-separated predicates and
adjacent predicates: `| level="error" and code="500"`,
`| level="error", code="500"` and `| level="error" code="500"` all require
both predicates. `and` and `or` are case-insensitive. Explicit `and` binds
tighter than `or`, but Loki's comma/adjacent forms attach the remaining
expression on their right: `| x="1", y="1" or z="1"` means
`x="1" and (y="1" or z="1")`, not `(x="1" and y="1") or z="1"`.
Use parentheses to make mixed expressions explicit. A new `|` starts a separate
pipeline stage. All conjunction forms evaluate both sides in order; `or`
skips its right side when its left side matches. Existing conversion-error,
validation and query-budget policies still apply. Upgrade query-serving
applications; no native/storage migration or keyed-retry drain is needed.

String and regex label matchers match the **whole** label value, as in Loki
and Prometheus:
`{app=~"api"}` selects `api` but not `api-gateway`; write `{app=~"api.*"}` for a
prefix. This applies to stream selectors, pipeline label filters
(`| pod=~"..."`) and `drop`/`keep` matchers. Line filters (`|~`) and the
`regexp` parser remain unanchored searches.

### Response encoding

Nonempty dedicated log `trace_id` and `span_id` fields are exposed as structured
metadata in LogQL. Explicit attributes with those names take precedence,
including empty attribute values; absent or empty dedicated IDs add no label.
Stream-label collisions use one `_extracted` suffix and preserve an already
occupied suffixed name. Parsers use the same metadata-name protection as other
attributes. Use pipeline filters such as `{app="api"} | trace_id="..."` or metric
grouping to query the IDs; they are not added to stream selectors or discovery.
This applies to already-stored logs too, without rewriting records. Upgrade all
query-serving app/native pairs to log codec tuple `{1,1,18}` before relying on
these labels; storage formats, keyed bytes and resource ceilings are unchanged.

Without an encoding header, log results keep merged stream, structured-metadata
and parser labels in `stream`, with `["<nanoseconds>", "<line>"]` values.
Send `X-Loki-Response-Encoding-Flags: categorize-labels` on either query endpoint
(GET or form POST) to separate labels by origin. Only surviving stream labels
remain in `stream`; each value has a third JSON object containing optional
`structuredMetadata` and `parsed` maps, or `{}` when both are empty:

```json
["1760000000000000000", "msg=ready", {"structuredMetadata":{"traceID":"123"},"parsed":{"msg":"ready"}}]
```

Parser writes and `label_format` destinations are parsed labels even when they
retain the previous value. `drop`, `keep` and renames remove the affected labels
from their original category too. Resource/promoted labels that survive without
such a rewrite remain stream labels. This changes grouping/encoding only, not
selectors, filtering, line formatting, global `limit` selection or stored data.

Exact `__error__` and `__error_details__` names received as structured metadata
use the `parsed` output category when they do not collide with stream labels.
Ordinary suffixed names such as `__error___extracted` remain metadata. Their
values and existing name protection are unchanged, as are unflagged responses
and metric-error admission; a `__preserve_error__` label never grants permission
to retain failed metric conversions.

The response echoes comma-separated, deduplicated flags in `data.encodingFlags`.
Tokens are exact and case-sensitive; unknown tokens are echoed without behavior.
An absent or empty header keeps the existing response unchanged. Metric samples
are unchanged by these flags. Categorized queries use extra per-label query
memory, and per-entry labels can enlarge the response; existing scan, timeout
and query-task heap bounds still apply and may reject an expensive request.
No storage-format migration or keyed-ingest retry drain is needed. Upgrade all
query-serving instances before relying on the header under non-sticky routing.

### Parser labels and quantities

When a parsed key collides with a current stream or structured-metadata name,
`json`, `logfmt`, `regexp`, `pattern` and `unpack` write `<name>_extracted`
instead. They append exactly one suffix, not a search for an unused name.
Structured metadata that collides with an original resource/promoted name gets
the same suffix at entry construction; an occupied suffix preserves its existing
owner. A parsed write can replace metadata at that suffix and changes its category.
Ordinary parsers keep the first parsed target, across later parser stages and
even after that target is dropped. Explicit JSON extraction can overwrite it.
Dropping or renaming a stream label releases its name for subsequent parsing.
For example, parsing `level=error` from a line whose promoted `level` is `info`
produces `level_extracted="error"`; filter that name to inspect the parsed value.

`label_format` destinations must be unique within one stage and cannot be
`__error__`; invalid destinations reject before storage, even after a filter
that cannot match. Renames execute in order, and `x=x` deletes `x`. Its parsed
write still counts as an earlier extraction, so ordinary parsers do not recreate
it later. Missing rename sources do not add empty labels. Templates within one
stage share the labels captured at its first template, after preceding renames;
later assignments do not change that snapshot. A later `label_format` stage
takes a new snapshot.

Active pipeline errors own their error/details independently of ordinary
same-named labels. Formatting `__error_details__` cannot hide an active parser
diagnostic in output or error-preserving metric groups. Dropping the active
details reveals any ordinary value beneath them; renames and ordinary details
filters read that ordinary value. General templates read the rendered active
diagnostic, except a single-field `line_format "{{.__error_details__}}"`, which
uses ordinary lookup. `keep` preserves both error names. A genuine later error
replaces the active diagnostic without destroying hidden ordinary labels.
These formatter pipelines use the bounded Elixir evaluator; existing work,
output and fail-whole limits remain. Upgrade query-serving applications for
consistent behavior; no native/storage-format change is required.

Both formatters support literal text, missing-as-empty `{{.label}}` lookups,
quoted string, boolean, `nil`, signed-int64 integer, finite float and rune constants, parenthesized
expressions and function pipelines. A pipeline passes its previous result as
the next function's last argument. Supported functions are `upper`, `lower`, `trim`, `trimPrefix`,
`trimSuffix`, `trimAll`, `replace`, `title`, `urlencode`, `urldecode`, `b64enc`, `b64dec`,
`repeat`, `indent`, `nindent`, `alignLeft`, `alignRight`, `trunc`, `substr`,
`contains`, `hasPrefix`, `hasSuffix`, `default`, `and`, `or`, `not`, `eq`, `ne`,
`lt`, `le`, `gt`, `ge`, `len`, `index`, `slice`, `int`, `add`, `sub`, `mul`, `div`, `mod`, `min`,
`max`, `float64`, `minf`, `maxf`, `ceil`, `floor`, `round`, `addf`, `subf`, `mulf`,
`divf`, `bytes`, `duration`, `duration_seconds`, `print`, `println`, `html`, `js`,
`urlquery`, `count`, `regexReplaceAll`, `regexReplaceAllLiteral`, `__line__`,
`__timestamp__`, `unixToTime`, `unixEpoch`, `unixEpochMillis`, `unixEpochNanos`, and the legacy
`ToUpper`, `ToLower`, `TrimSpace`, `TrimPrefix`, `TrimSuffix`, `Trim`, `TrimLeft`,
`TrimRight`, `Replace` names. Legacy trim functions take the input first, unlike
their lowercase counterparts. `trimAll`/`Trim` remove any character in the
supplied Unicode cutset from both ends; `TrimLeft`/`TrimRight` affect one end.
`replace old new text` replaces all nonoverlapping literal matches, with no
regular-expression or replacement-string expansion. An empty search inserts
the replacement before and after every Unicode scalar, including between
combining marks. `Replace text old new count` limits replacements: zero leaves
the input unchanged, and a negative count replaces all matches.

`__timestamp__` returns the entry's original timestamp as a typed time value,
not the current line, an extracted label or the query evaluation time. Line
rewrites do not change it. `unixEpoch`, `unixEpochMillis` and `unixEpochNanos`
accept time values and return decimal strings in seconds, milliseconds or
nanoseconds, respectively. Seconds and milliseconds round down, including
before the Unix epoch; nanosecond conversion retains Go's signed-int64 wrapping.
For example, `{{__timestamp__ | unixEpochNanos}}` retains source nanoseconds.

`unixToTime` accepts a signed decimal int64 string and chooses its units from
the string's byte length, including signs and leading zeros: 5 bytes are days,
10 seconds, 13 milliseconds, 16 microseconds and 19 nanoseconds. This follows
Loki's helper, not magnitude-based unit guessing. Millisecond/microsecond
multiplication wraps as signed int64 before time normalization. Other lengths,
invalid numbers, overflow and wrong argument types produce `TemplateFormatErr`
and preserve the original line or destination. Ordinary metric pipeline-error
guards and explicit error selection still apply.

Time values retain their type through variables, pipelines and `with` blocks;
they support equality and are truthy even at the Unix epoch. Plain rendering
uses `YYYY-MM-DD HH:MM:SS[.fraction] +0000 UTC`, retaining up to nine fractional
digits and trimming trailing zeros. Pulse always renders UTC, independent of
the host timezone; Loki's default time rendering instead uses its process-local
timezone. Arbitrary Go date layouts, named-zone conversion, time methods and
`now` remain unsupported. Upgrade query-serving applications; no native,
storage-format, keyed-ingest byte or resource-limit change is required.

`print`, `println`, `html`, `js` and `urlquery` accept zero or more existing template
values. `print` joins their default textual representations, inserting a space
only between adjacent nonstring values: `{{print 1 "x" 2 3}}` renders `1x2 3`.
`println` always separates arguments with spaces and appends a line feed,
including when there are no arguments. Empty strings remain string arguments;
they can suppress `print`'s separator without emitting text. Byte, complex,
float, boolean and root-map values retain their existing textual formats.

`html` applies `print`'s joining rules, then escapes ampersands, angle brackets
and quotes as `&amp;`, `&lt;`, `&gt;`, `&#34;` and `&#39;`; NUL becomes U+FFFD.
Existing entities are escaped again. This is explicit text escaping, not
context-aware HTML/JavaScript sanitization or automatic output escaping.
`urlquery` applies the same joining rules, then query-form URL escaping like
`urlencode`, including `+` for spaces. Unlike `urlencode`, it accepts typed
values and multiple arguments. Combined text and escaped output must fit the
existing 16 MiB cap before allocation; later trimming cannot hide overflow.
Oversized output fails the whole query, not as a preservable formatting error.
`printf` and Go pointer/typed-interface values remain unsupported. Upgrade
query-serving applications; no native/storage/keyed-byte change is required.

`js` uses Go's explicit JavaScript text escaping after joining its arguments.
It backslash-escapes quotes/backslashes, writes `<`, `>`, `&` and `=` as
uppercase hexadecimal escapes, and escapes C0 controls and nonprintable Unicode
scalars. Printable Unicode follows Go's Unicode 17 classification; DEL remains
literal. For example, `{{js "<x>&"}}` renders `\u003Cx\u003E\u0026`.
It neither adds quotes nor produces a JSON string: Go uses a minimum four-digit
`\u` spelling even for nonprintable scalars above U+FFFF, not surrogate pairs.
Use it for protocol-compatible text formatting, not context-aware sanitization.
The full escaped size must fit 16 MiB before output allocation; overflowing
intermediates fail whole even if a later function would shorten the result.

`nil` is an untyped empty value, distinct from a missing string label (`""`).
It is false in `and`/`or`/`not` and `default`, equals only another `nil`, and
converts to zero in `int`/`float64` and their arithmetic helpers. Ordered
comparisons, `len`, indexing/slicing nil and passing nil to typed string/integer
parameters produce `TemplateFormatErr`, preserving the original line/labels.
A bare nil command (`{{nil}}` or `{{if nil}}`) also fails at execution; a nil
command in an unselected branch does not fail. Nil returned by a function
renders `<no value>`, while `print nil` renders `<nil>` as a nonstring argument.
`html`, `js` and `urlquery` first turn nil into the string `<no value>`, then join
and escape it; this also suppresses separators beside nil in those functions.
For example, `{{html 1 nil 2}}` renders `1&lt;no value&gt;2`, while
`{{print 1 nil 2}}` renders `1 <nil> 2`. Existing output/resource limits apply.

`repeat count text` repeats the text, including an empty result for zero.
`indent count text` adds spaces before the first line and after every newline,
including empty and trailing lines. `nindent` additionally prepends a newline.
Negative repeat/indent counts produce `TemplateFormatErr`, even for empty text.
`alignLeft count text` and `alignRight count text` pad or truncate to the
requested Unicode-scalar width, not bytes or graphemes; a negative width leaves
the input unchanged. Integer literals accept signs, decimal, hexadecimal `0x`,
binary `0b`, octal `0o`/leading-zero forms and Go digit separators, within signed
int64 bounds. String-valued labels do not implicitly convert to these string
functions' integer arguments; use `int` to convert them explicitly.
Unsigned constants outside int64 reject before storage, rather than being
admitted for Go-style runtime overflow errors. `default` also treats integer
zero as empty.

Float constants accept decimal/scientific and hexadecimal `p`-exponent forms,
Go digit separators and signed zero. They retain their floating-point type:
`{{eq 2.0 2}}` produces `TemplateFormatErr`, while two floats compare normally.
A direct, exactly integral, in-range constant can satisfy an integer argument:
`{{repeat 2.0 "x"}}` renders `xx`. Parentheses or a pipeline produce a typed
float instead, so `{{repeat (2.0) "x"}}` requires an explicit `int` conversion.
Overflowing/nonfinite constants and malformed spellings reject before storage,
even inside skipped branches. Out-of-range conversions, including the rounded
positive int64 literal boundary, produce `TemplateFormatErr` rather than Go's
platform-dependent integer result.

Character constants inside templates denote integer Unicode code points:
`{{'a'}}` renders `97`, and `{{'\xFF'}}` renders `255`, not a byte string.
They accept one Unicode scalar or a Go named, three-digit octal, two-digit hex,
four/eight-digit Unicode escape. Only apostrophes may be escaped as quotes;
a double quote needs no escape inside a character constant. Empty/multiple
characters, literal line feeds, malformed escapes, surrogates and code points
above U+10FFFF reject before storage, including in skipped branches.
These constants use the existing integer arguments, arithmetic, comparisons
and zero truthiness/defaults. This does not enable single-quoted LogQL strings
outside templates or non-UTF-8 string values. Upgrade query-serving applications;
no additional native/storage/keyed-byte change is required.

Integer arithmetic helpers `add`, `sub`, `mul`, `div`, `mod`, `min` and `max`
coerce their arguments like `int`: booleans become 1/0; strings use base-zero
signed-int64 parsing, after truncating a decimal fraction without float rounding.
For example, `int "010.9"` returns 8, while invalid `"08.9"`, scientific
`"1e3"`, whitespace-padded and overflowing strings return zero. Invalid
conversions do not produce formatting errors. `add` accepts zero or more
arguments and returns zero for none; `mul`, `min` and `max` require at least one.
`sub`, `div` and `mod` require two, and `int` requires one. Arithmetic wraps
signed-int64 overflow at each operation. Division truncates toward zero;
remainder takes the numerator's sign. Division/remainder by zero produce
`TemplateFormatErr`, preserving the original input. These helpers return typed
integers, so `{{repeat (add 1 2) "x"}}` produces `xxx`. Floating-point helpers
are described below.

`bytes text` converts a go-humanize byte quantity to a float64 byte count;
`duration text` and its alias `duration_seconds text` convert a Go duration to
float64 seconds. They use the same runtime quantity profiles as `unwrap`,
including fractional rounding, both microsecond spellings and overflow checks.
Invalid or missing quantities produce `TemplateFormatErr`, not zero defaults.
For example, `{{bytes "3MB"}}` renders `3e+06`, while
`{{duration "3ms"}}` renders `0.003`. Rendering uses Go's shortest general
float format, including scientific notation for nonzero magnitudes below
0.0001 or at/above 1000000.

These results retain their floating-point type in pipelines: zero is false and
empty for `default`; comparisons accept two floats, not a float and an integer
or string. Use `int` before a string helper's integer argument, for example
`{{repeat (int (bytes "3B")) "x"}}`. Integer helpers truncate float arguments
toward zero within signed-int64 range. Out-of-range float-to-integer conversions
produce `TemplateFormatErr` instead of Go's implementation-dependent overflow
value. Large byte quantities still render without integer conversion; values
beyond float64's exact-integer range can round.

`float64` converts strings, integers and booleans to floating-point values;
invalid or overflowing numeric strings become zero. Numeric strings are not
whitespace-trimmed. Runtime `NaN`, `+Inf` and `-Inf` strings retain their
floating-point classes, unlike nonfinite template constants, which reject.
`minf`/`maxf` coerce their arguments the same way; `ceil`/`floor` round toward
positive/negative infinity. Signed zero and nonfinite results retain their Go
rendering. Float comparisons follow Go templates: `NaN` fails `eq`, `lt` and
`le`, but satisfies `ne`, `gt` and `ge` (the latter two use inverted tests).
Nonfinite float-to-integer conversions produce `TemplateFormatErr`.

`round value places [threshold ...]` takes an integer decimal precision and
optional floating-point thresholds. All thresholds must have float type; only
the first is used, defaulting to 0.5. It compares the signed fractional part,
so `{{round -1.2 0}}` renders `-2`, not `-1`. Decimal powers and fused fractional
residuals follow the pinned Go runtime profile: `{{round 123.5555 3}}` renders
`123.555`. Half-step results can differ from Go builds that do not fuse the
multiply/subtract. This is not decimal bankers' rounding or a cross-compiler
bit-parity guarantee.

`addf`, `subf`, `mulf` and `divf` first coerce each argument to float64, then
calculate using its shortest decimal representation. A function rounds back to
float64 only when it returns, not after each operand. For example,
`{{addf 0.1 0.2 0.3}}` renders `0.6` and `{{addf 1e16 1 -1e16}}` renders `1`.
Strings and integers beyond float64's exact range lose precision before decimal
arithmetic. Each `divf` step rounds to 16 decimal places, with halfway cases away
from zero: `{{divf "1e-16" 2}}` renders `1e-16`, while smaller quotients can
round to zero. Operands fold left to right; pipelines append their previous
result as the last operand. `addf` accepts no arguments and returns zero; the
other three require at least one. Exact decimal zero loses a negative-zero sign;
nonzero results can underflow to signed zero or overflow to infinity on return.
Zero division and nonfinite operands produce `TemplateFormatErr`, preserving
inputs. Invalid numeric strings still coerce to zero. Existing query-length,
heap, deadline and output limits remain authoritative.

`count pattern text` returns the integer number of non-overlapping regex
matches, not substring occurrences. For example, `{{count "a|b" "banana"}}`
renders `4`. Matching follows the existing Go-style query regex profile:
codepoint-aware Unicode text, ASCII Perl classes/word boundaries, strict
non-multiline end anchors and Unicode script rather than script-extension
properties. Empty matches advance by one Unicode scalar; an empty match
immediately adjoining a nonempty match is ignored. An empty pattern counts
one more than the number of Unicode scalars, including one for empty text.
Patterns may come from labels. Invalid patterns and wrong argument types/counts
produce `TemplateFormatErr` when executed, preserving inputs; skipped branches
do not compile or evaluate their regex arguments.

Counting uses bounded non-backtracking native matching without retaining a
list of matches. Each accepted match and one final probe spend work. Metric
expressions share their existing work budget; log streams share a request-local
counter across entries and actions under `PULSE_QUERY_MAX_WORK`. Exhaustion
fails the whole query with `query_work_limit`, even with explicit error
selection. Query deadlines, heap and scan limits still apply; this is not a
claim of full Go regexp syntax or unbounded regex capacity.

`regexReplaceAll pattern text replacement` replaces every non-overlapping match.
The replacement expands `$0`/`${0}` for the whole match, numbered and named
captures, and `$$` for a literal dollar. Missing/unmatched captures expand to
empty strings. Names consume the longest letter/digit/underscore sequence:
`$1x` names capture `1x`, while `${1}x` appends `x` to capture 1. Leading-zero
numbers are names rather than capture indices. Malformed references retain
their dollar literally. Backslashes are ordinary replacement text after
template string decoding, not capture-reference syntax.

Template regex helpers accept Go's ASCII capture names, including numeric
and repeated names, in both `(?P<name>...)` and `(?<name>...)` forms. A named
replacement selects the first participating capture with that name; a matched
empty capture wins over later captures. Ordinary numbered references retain
their original positions. Decimal references below one billion without leading
zeros select indices; other numeric spellings select names, as in Go.
The helpers also accept `\Q...\E` literal quoting, including an omitted closing
`\E` at the end of a pattern. Quantifiers after a quoted run apply to its last
character, not the entire run. Quoting is invalid inside character classes.
Octal escapes consume up to three digits and denote Unicode characters, not
raw bytes: `\141` matches `a`, and `\400` matches `Ā`. A leading zero may stand
alone; nonzero first digits require a second octal digit, so `\1` remains an
unsupported backreference. Octal escapes work inside character classes and
with quantifiers. Quoted runs and escaped backslashes retain literal digits.
Selectors, `label_replace` and `regexp` parsers also accept these quote/octal
forms through the shared query regex profile. Selectors and `label_replace`
accept numeric/repeated names too; parser destinations require unique raw names.

`regexReplaceAllLiteral pattern text replacement` inserts the replacement
verbatim, without expanding any dollar references. Both functions take the
replacement as their final argument, so `"x" | regexReplaceAll "a" "banana"`
produces `bxnxnx`. Matching uses the same profile and empty-match rules as
`count`, not PCRE. Lookarounds and backreferences
remain outside that bounded regex profile. Executed invalid patterns and
argument failures preserve inputs with `TemplateFormatErr`; skipped branches
do not execute them.

Replacement proves its complete output fits 16 MiB before allocating the
result, even when a later function would truncate it. It scans twice without
retaining matches: once for byte admission and once to write the result.
Each pass charges every accepted match, a final probe and each scanned dollar
reference/escape to the work budget shared with `count`. Capture names charge
at least their byte length, including unknown names that emit nothing.
Each additional duplicate capture examined also spends one work unit, even
when every candidate is unmatched and the reference emits no bytes.
Output/work exhaustion fails the whole query, never as a preservable formatting error. Matching
query-serving apps/native artifacts require log codec tuple `{1,1,18}` for
regex replacement; storage and keyed encoder bytes are unchanged.

`trunc count text` selects the first count bytes, or the final -count bytes for
a negative count; counts outside the string's byte length leave it unchanged.
`substr start end text` uses zero-based byte offsets with an exclusive end.
A negative start selects from zero with the original end; otherwise a negative
or oversized end selects through the string's end. Invalid bounds produce
`TemplateFormatErr`, rather than clamping every bound. Both functions match
Loki's public byte helpers, not Unicode character slicing. A slice that splits
a UTF-8 character produces `TemplateFormatErr` until byte-string handling is
supported, even if a later function could encode those bytes.

`slice text [start [end]]` uses Go's string-slicing rules: zero-based byte
offsets, an exclusive end, and defaults of zero and the string's byte length.
Unlike `substr`, it never adjusts negative or oversized bounds. Empty slices,
including at the string's end, succeed. Reversed bounds, past-end indices,
noninteger indices, a third index or a nonstring input produce
`TemplateFormatErr` when executed. Integer conversions and byte values returned
by `index` can supply indices; floating-point or complex constants cannot,
even when numerically integral. For example, `{{slice "aé🙂z" 3 7}}` renders
`🙂`. UTF-8-splitting slices retain the stricter rejection described above,
including before a later `b64enc`. Existing intermediate and final output caps
still apply. Upgrade query-serving applications; no native/storage/keyed-byte
change is required. Array slicing remains unsupported.

Case conversion follows Go's simple Unicode mapping: for example, `upper`
leaves `ß` unchanged. `title` preserves noninitial letters and
uses Go's historical ASCII-punctuation/Unicode-space word boundaries, not full
Unicode word segmentation. `__line__` reads the current line, including
rewrites by earlier stages, not a label named `__line__`.

`urlencode`/`urldecode` use query-form escaping: space becomes `+`, literal `+`
becomes `%2B`, and decoding accepts either hex case. Malformed percent escapes
produce `TemplateFormatErr`. Decoded non-UTF-8 byte strings also produce that
error until byte-string handling is supported; unlike Go, they are not passed
through. `b64enc` uses standard padded Base64. `b64dec` accepts that alphabet,
noncanonical padding bits and omitted padding when the original input byte
length modulo four is two or three. Padding is added before ignoring CR/LF;
other whitespace is invalid. Corrupt input returns the ordinary string
`illegal base64 data at input byte N`, not a formatting error; partial decoded
data is discarded. Successfully decoded non-UTF-8 values produce
`TemplateFormatErr`, as with URL decoding.

For example, `| line_format "{{.message | trim | upper}}"` trims and uppercases
the message label; `| label_format route="{{.route | default \"unknown\"}}"`
sets a fallback for a missing or empty route. Inner quoted strings follow Go
template escaping, separately from the outer LogQL literal; raw inner strings
discard carriage returns. Non-UTF-8 literal values reject before storage until
byte-string transport and downstream parsing are supported.

Unknown functions, unsupported syntax and unclosed actions reject before any
storage reads, including after an unreachable line filter. Wrong argument
counts/types attach `TemplateFormatErr`, preserve the original line or label
destination, and let later stages run. Metric queries fail on unselected errors;
use `| __error__=""` to discard them or explicitly select errors to retain their
unchanged inputs. Exact Go template error text/positions and general pipeline
error ownership remain incomplete.

Conditional actions support `{{if expression}}yes{{else if expression}}other{{else}}no{{end}}`,
including nested branches and omitted `else` branches. Empty/missing strings,
`false` and numeric zero are false; nonempty strings (including `"0"`) and
nonzero numbers are true. `and`/`or` return the first decisive operand or the
last operand, and skip remaining argument expressions. Earlier pipeline
commands still run before their result is passed to `and`/`or`.
`not` negates truthiness. `eq` accepts two or more arguments and compares the
first with successive candidates until one matches; its argument expressions
are evaluated before comparison. `ne` and ordered comparisons take exactly two
arguments. Comparisons require matching string, integer, float or boolean types;
booleans support only equality/inequality. Strings compare by bytes, and
`len` counts string bytes, not Unicode characters. Runtime argument failures
follow the same input-preservation/error-label policy as other functions.

`{{with expression}}…{{else with expression}}…{{else}}…{{end}}` uses the same
truthiness as `if`. In a successful branch, `.` becomes the expression's value;
the `else` branch and later actions keep the previous `.`. Nested `if` actions
do not change it. `$` initially refers to the formatter's original merged label
map, so `{{with .message}}{{upper .}} ({{$.service_name}}){{end}}` can format
a string while still looking up labels. `index $ "http.method"` supports keys
that are not identifiers. Missing root/map keys remain empty strings; looking
up a field on a scalar produces `TemplateFormatErr`. `else if` is shorthand
only inside `if`, and `else with` only inside `with`. Both branches validate
before storage; only the chosen branch executes.

`{{$name := expression}}` declares a variable without printing the value;
`{{$name = expression}}` updates the nearest existing binding. Both accept
pipelines, including `if`/`with` headers. Declarations last until the enclosing
block ends, shadow outer declarations and restore them afterward; assignments
to outer bindings survive the block. Header declarations also exist in `else`.
For example, `{{$x := .message}}{{with .message | upper}}{{.}} / {{$x}}{{end}}`
retains the original value alongside the uppercase output.
`$name.field` and `index $name "arbitrary.key"` read saved label maps. `$` itself
can be shadowed or reassigned without changing `.` or the underlying labels.
Each template/destination/entry starts with fresh bindings and the stage's
original label snapshot. Unknown references reject before storage. Go's
self-initialization, undefined assignment and references declared only in a
skipped branch can instead fail at runtime with `TemplateFormatErr` when
executed; skipped branches do not execute those failures. Parenthesized
pipelines can declare or assign variables too: `{{upper ($x := .message)}}/{{$x}}`
prints the uppercase and original values. Arguments evaluate left to right;
lazy `and`/`or` skips both the value and binding effects of unselected arguments.
Declarations become visible to later source expressions, but skipped declarations
do not create runtime values.

`{{range expression}}...{{else}}...{{end}}` iterates root/saved label maps or
decoded JSON objects in lexical key order, JSON arrays in element order, or
integers from zero up to (but excluding) their value.
Zero/negative integers and nil function results select `else`; strings, booleans,
floats and complex values are not iterable. Dot becomes the current element;
`$` still refers to the root. A single range variable receives the element;
two variables receive map key/value or array index/element. Integer ranges accept
only one variable, including when empty. Declarations are block-local and body
declarations reset each iteration; assignments update existing bindings. Headers initialize their
variables to the input before iteration, so empty-range `else` sees that input.
`break` exits the innermost loop; `continue` starts its next iteration. The
loop's `else` does not run after `break`, and loop control in an empty inner
loop's `else` refers to an enclosing loop, not the empty loop itself.
Each executed iteration consumes one metric query-work unit or one request-local
stream-template work unit, including empty bodies and `continue`, across entries,
formatters and regex counting/replacement.
Work exhaustion fails the whole query, never as a preservable formatting error.
An early `break` charges actual iterations, not the potential integer range.

`fromJson` decodes a JSON string into typed values, for example
`{{(fromJson .payload).user.name}}` or
`{{range $i, $v := (fromJson .items)}}{{$i}}:{{$v}} {{end}}`.
Objects support field/string-key lookup and arrays support integer/uint8 indexing;
`len`, `if`, `with`, `default`, printing and numeric conversions accept these
values. Object keys sort lexically when printed. Duplicate JSON keys keep their
last value, including replacement of an earlier object. All JSON numbers become
float64, not template integers: use `int` when a function requires an integer.
Signed zero and float64 rounding of large integers are preserved. Overflowing
numbers become zero, matching the pinned Loki/Go 1.27.3 runtime; this does not
promise older Go decoder behavior.

Malformed JSON, trailing non-whitespace content and JSON null return nil without
a formatting error. Missing JSON object keys also return nil, unlike missing
root-label keys, which return empty strings. Another field on a missing/null
object member fails with `TemplateFormatErr`; a nil function result can instead
propagate through fields. Lone escaped UTF-16 surrogates and malformed UTF-8
inside JSON strings become replacement characters; valid surrogate pairs decode
to one scalar. Invalid escapes and unescaped controls still invalidate the whole
document. Nulls inside printed containers use `<nil>`, versus `<no value>` for
a directly rendered nil result. Non-nil arrays/objects are not comparable to
one another; empty containers are false but do not equal nil.

Each executed `fromJson` call charges its complete input byte count to metric
query work or request-local stream-template work before normalization or term
expansion, including malformed documents. This allowance is shared across
entries, actions, loops and regex helpers. JSON input and normalized bytes each
cap at 16 MiB; decoded containers nest at most 64 levels. Normalization proves
growth before allocating it. These bounds and rendered-output overflow fail the
whole query, even with explicit error selection or a later shrinking function.
They are Pulse resource bounds, not upstream JSON capacity guarantees. Array
slicing follows the bounded profile below; channel/function iteration remains
unsupported.

`slice` also accepts decoded JSON arrays with zero to three integer/uint8 bounds:
`{{slice (fromJson `[3,4,5]`) 1 3}}` returns `[4 5]`. Start is inclusive, stop
exclusive; omitted start/stop default to zero/current length. The third bound
limits capacity, so later slices cannot recover values past that bound.
Two-bound slices retain access to decoded backing elements beyond their current
length: slicing `[3,4,5]` to `[3]` and then from one to three returns `[4 5]`.
Indexing, iteration, length, truthiness and printing use only the current view.
Slicing retains a view without copying the array; iteration still spends shared
work and complete rendered output is checked before later shrinking functions.

Initial array capacity equals its decoded element count. Pulse never exposes
Go's allocator-dependent spare cells after that count. Requests depending on
those cells fail with `TemplateFormatErr`, including third bounds reserving them;
this is a remaining compatibility difference, not exact Go capacity parity.
Wrong types, negative/reversed/out-of-capacity bounds and too many bounds also
preserve inputs with formatting errors. All resource ceilings remain unchanged.

Field chains can follow variables, functions and parenthesized results, such as
`{{(or false $).message}}`. They read map values, not flattened dotted label names;
use `index $ "http.method"` for a literal dotted key. Missing label-map keys
produce empty strings; accessing another field on that string is a formatting
error. A nil function result instead remains nil through further fields and
renders `<no value>`; field arguments are not executed on that nil receiver.
Parentheses matter: `{{(nil).field}}` executes an invalid bare nil command,
while `{{(and nil true).field}}` returns nil. Generic JSON objects, arrays and
their operations follow the typed rules above; object methods remain unsupported.

Whitespace trim markers `{{- expression}}` and `{{expression -}}` remove adjacent
literal spaces, tabs, carriage returns and newlines. A marker requires whitespace
beside the hyphen: `{{-3}}` instead renders negative three. Trimming never removes
Unicode spaces, vertical tabs, form feeds or whitespace produced by an earlier
action. It applies lexically, including to conditional delimiters and skipped
branches, not to the assembled output.

`{{/* comment */}}` emits nothing and ignores its contents, including apparent
actions or unknown functions. Comments close at the first `*/` and do not nest.
The opener must immediately follow `{{` or its two-byte trim marker; the closer
must immediately precede `}}` or a single whitespace-plus-`-}}` trim marker.
For example, `{{- /* comment */ -}}` trims both sides, while `{{ /* comment */}}`
and `{{/* comment */ }}` reject before storage. Comment text still counts toward
the query-length limit but never executes or consumes rendered-output budget.

Initially, `.` and `$` are the current merged label map, including structured
metadata and labels produced by earlier pipeline stages. `index . "http.method"`
accesses a string key without Go identifier restrictions; a missing key returns
an empty string. `len .` counts labels. Printing `.` renders `map[key:value …]`
in lexical key order under the same 16 MiB output cap. Templates within one
`label_format` stage still share that stage's first-template label snapshot,
including `$` lookups. A later formatter stage takes a fresh root snapshot.

`index text position` uses zero-based UTF-8 byte positions and returns an
unsigned byte, not a Unicode character: `index "é" 0` renders `195`.
Additional indices apply successively, so `index . "message" 0` reads the
first byte of the `message` label. Negative/out-of-range indices and wrong
types produce `TemplateFormatErr`; floating and complex indices are not
implicitly converted. Byte values compare with integers and support numeric
helpers, but typed integer arguments require explicit conversion:
`repeat (int (index "\x02" 0)) "x"` produces `xx`, whereas omitting `int`
fails. Generic arrays and JSON object values remain unsupported.

Finite complex template constants such as `4i` and `-1.2+4.2i` render as
`(0+4i)` and `(-1.2+4.2i)`. Components accept decimal/scientific/hexadecimal
floating syntax and separators; `073i` means decimal 73i, not octal 59i.
Both components retain signed zero. A complex value is false only when both
components are zero. Equality compares two complex values; ordering and
mixed complex/integer/float comparisons produce `TemplateFormatErr`, even
when the imaginary component is zero.

A directly supplied zero-imaginary constant can satisfy a typed numeric
argument: `repeat 2+0i "x"` produces `xx`, and `round 1.25 1 0.4+0i` produces
`1.3`. Parentheses or an earlier pipeline command produce a typed complex
value instead, so `repeat (2+0i) "x"` fails. Generic `int`/`float64` conversion
of a complex value returns zero, not its real component. Malformed or
overflowing components reject before storage, including in skipped branches.
Existing nonportable float-to-integer overflow exclusions still apply.

All branches validate before storage, even when unreachable. Only selected
branches and evaluated arguments execute; skipped expansions cannot consume
output budget. Each template may nest at most 64 combined branch, range and
parenthesized expressions and produce at most 16 MiB per entry, shared across
its selected branches. Replacement, repetition, indentation, alignment padding, URL
encoding and Base64 encoding enforce the same cap on their intermediate outputs
before allocating them, even when a later function would shrink the result.
Exceeding the output cap fails the whole query, even with explicit error
selection; it is not a preservable formatting
error. Existing query length, scan, work, deadline and heap limits still apply.
Channel/function iteration, date-layout/timezone functions beyond the timestamp
helpers above and other Go-template built-ins remain unsupported. Upgrade every
query-serving app/native pair to log tuple `{1,1,18}` for regex counting/replacement;
storage-format and keyed-ingest bytes are unchanged.

`| json` flattens nested object scalar fields with `_` separators, sanitizes
label names and skips arrays and nulls. Object fields are processed in source
order, so duplicate or colliding sanitized targets keep their first extraction.
Numbers retain their original text, including exponent spelling, signed zero
and integers beyond float64 precision. Replacement characters in string values
become spaces. Invalid object inputs attach `JSONParserErr`; use an error filter
to discard them or explicitly retain them in metric queries. Complete malformed
input/partial-extraction diagnostic parity and parser-hint early exits are not
supported. Explicit JSON extraction preserves an existing destination when the
source path is absent; a present null instead extracts an empty string.

Explicit paths accept dot access, quoted bracket keys and nonnegative int64
array indices, including a top-level array: `| json who="user.id", tag="tags[0]"`
or ``| json value=`["field with spaces"]` ``. Invalid paths reject before storage.
The inner field grammar does not decode another layer of string escapes.
Selected numbers keep their source spelling; selected objects keep original
whitespace and escapes. Selected arrays instead decode escapes across the
entire array text, matching Loki's string-valued extraction rather than a JSON
re-encoding. Duplicate paths take the first complete match; repeated destinations
follow source order, not expression order. An empty line adds no defaults.
A complete requested value can precede an unclosed outer object, so explicit
extraction is not whole-line JSON validation. Complete malformed-value/error
parity remains unsupported. These stages run under existing query-worker
timeouts/heaps and scan/work/result limits, without native pushdown.

`| regexp` requires at least one named capture. `| pattern` requires a named
capture and rejects duplicate names or adjacent captures; a short line retains
the captures found before a missing delimiter, including the remaining text in
the current named capture. Empty lines extract nothing.

`| unpack` accepts an object at byte zero containing a string `_entry`; that
value replaces the line, and only other string fields become labels. Without
that string, no fields are published. Empty lines pass unchanged; nonobjects
and malformed objects attach `JSONParserErr`. Same-object duplicates use the
last string value, while earlier parser extractions remain protected. Complete
malformed-input diagnostics and hint-driven early exits remain unsupported.

`| logfmt` skips malformed pairs and resumes at the next token. Add `--strict`
to stop at the first malformed pair, keep preceding fields and attach
`__error__="LogfmtParserErr"` with `__error_details__` identifying a one-based
byte position. Unterminated quoted values point one byte past the input end.
Use `| __error__=""` after strict parsing to exclude these lines; unpreserved
errors fail metric queries rather than returning partial aggregates.

Bare keys and empty values are omitted by default. `--keep-empty` retains them;
explicit field extraction also retains empty values. Without an explicit field
list, repeated normalized keys keep the first retained value, not the last.
Dots and other punctuation become underscores, and digit-leading keys gain an
underscore prefix. Quoted values
decode JSON-style escapes plus `\'`, including Unicode surrogate pairs;
literal controls remain literal. Extract-all parsing replaces replacement
characters with spaces; explicit extraction empties the entire affected value.
This log-line decoding differs from LogQL query-string literal decoding below.
Unflagged ASCII decoding can run natively; Unicode and flagged stages use the
bounded Elixir evaluator. Both paths preserve stream/metadata ownership and
first-extraction history. Hint-driven early exits remain incomplete Loki parity.

Explicit fields use normalized logfmt keys, not JSON paths: `| logfmt value="a_b"`
reads a line key named `a.b`. Source expressions use Loki's separate field-name
grammar; invalid expressions reject before storage, even after a nonmatching
line filter. A missing source creates an empty destination only when that name
is not already a stream or metadata label; it does not invent an empty
`_extracted` label for an absent value. Repeating a destination in the field list
uses its last source definition, but every definition must be valid. Matching
source keys are renamed first; otherwise keys named for a requested destination
are also captured. Later matching pairs overwrite earlier values, so
`source=one dst=two` with `logfmt dst="source"` yields `dst="two"`.
An already parsed colliding suffix stops explicit logfmt extraction, including
before a later strict-decoding error. Shared-source aliases select the
lexicographically first destination; other destinations remain empty unless
their own keys occur. Loki selects one alias through nondeterministic map
iteration, so exact alias-choice parity is not promised. Hint-dependent early
exits remain incomplete.
Explicit fields always use the bounded Elixir evaluator, never native pushdown.
Upgrade every query-serving app/native pair to log tuple `{1,1,8}` for these
ownership changes. Storage/keyed bytes and resource ceilings are unchanged.

Duration/byte filters and `unwrap duration(...)`, `duration_seconds(...)` and
`bytes(...)` follow Loki's runtime producer-value conversions. Durations use
signed-int64 nanoseconds, compound `ns`, `us`, `µs`, `μs`, `ms`, `s`, `m`, `h`
components, one leading sign and unitless zero. Fractional components use Go's
bounded float64 rounding: `0.3333333333333333333h` yields `1200000000000ns`.
Days, weeks and years are query-literal units only, not runtime duration units.
Unwrap returns seconds using separate whole-second and nanosecond-remainder
conversion, preserving Go's precision for large durations.

Runtime bytes use unsigned uint64 counts, unitless numbers, case-insensitive
decimal `k` through `e` or binary `ki` through `ei` suffixes, with optional `B`.
Whitespace around the suffix and commas in the numeric prefix are accepted.
Whole-number inputs retain exact uint64 precision; fractions round through
float64 before scaling and truncate to bytes. Thus `9007199254740993B` retains
its integer value but `9007199254740993.0B` becomes `9007199254740992`.
Negative/explicitly signed byte values, leading whitespace, scientific notation,
unknown units and overflow become conversion errors. This replaces Pulse's
earlier signed-byte and runtime-day extensions; upgrade query-serving
applications together for consistent answers.

Quantity thresholds now follow Loki's query-token conversions, separately from
runtime producer values and range windows. Duration thresholds and offsets first
accept ordered, unrepeated integer `y/w/d/h/m/s/ms` components; otherwise they
use Go duration conversion, including negative hours/seconds, repeated units,
fractions and `ns/us/µs`. Fractional days/weeks/years, explicit `+` signs and
Greek `μs` thresholds reject. Unitless `-0` is a duration threshold; ordinary
unitless zero remains numeric. Byte thresholds accept unsigned uint64 counts
with case-sensitive `B` or `k/K/M/G/T/P` suffixes; each prefix optionally adds
`i` for binary scaling and/or a final `B` (`ki`, `KiB`, `MB`, `PiB`, etc.).
Whole counts remain exact; fractional counts use the
runtime float64 rounding. Lowercase `mb`, exabytes, spaces, commas and signs
are runtime-only or invalid forms, not byte-threshold syntax.

Bracketed windows use only ordered, unrepeated integer `y/w/d/h/m/s/ms`
components, without spaces inside brackets. Fractional, signed, microsecond and
nanosecond windows now reject instead of using Pulse's former extensions;
nanosecond source/evaluation times and window-boundary comparisons are unchanged.
Pipelines may precede the bracket or follow the bracket and its optional
`offset`: `sum_over_time({job="api"}[1m] | json | unwrap latency)` is equivalent
to putting `| json | unwrap latency` before `[1m]`. Parentheses may enclose
the source or the complete range, including nested complete-range parentheses.
A parenthesized selector may be followed by a bracket and `unwrap`, but not
a new parser pipeline. Do not split a pipeline across the bracket. Post-unwrap
label filters keep their order, and existing expression/depth budgets apply.
Zero windows still reject during evaluation. `0B` remains a valid threshold,
matching Loki's lexer test despite a contradictory error from its pinned scanner.
This is not a claim of complete parser/diagnostic parity. Overflowing literals
reject the query; invalid runtime unwrap values fail an evaluated window, never
contribute a partial sum. Upgrade query-serving applications together. Native
requirements, storage formats, keyed bytes and query ceilings are unchanged.

Duration filter and `unwrap duration(...)` / `duration_seconds(...)` failures
expose Go-compatible `__error_details__`: invalid duration, missing unit, or
unknown unit, including overflow rejection and the original signed input.
Control and non-ASCII bytes use lowercase `\xNN` escapes, not JSON quoting.
For example, `foo="2weeeeee"` filtered by `foo>1s` yields
`time: unknown unit "weeeeee" in duration "2weeeeee"`.
Queries can select that exact text. Typed filters preserve the first nonempty
error; failed unwrap conversions set `SampleExtractionErr`. Selecting details
alone does not preserve failed metric samples: explicitly select `__error__`
too when retaining zero-valued error samples. Existing fail-whole guards and
budgets remain. Byte filters and `unwrap bytes(...)` likewise expose the
go-humanize errors: `strconv.ParseFloat: parsing "...": invalid syntax` or
`value out of range`, `unhandled size name: <normalized suffix>`, and
`too large: <original input>`. Malformed numbers report the scanned numeric
prefix after comma removal, not necessarily the whole label value. Numeric
parsing errors take precedence over unknown suffixes; uint64 overflow is checked
only after recognizing the suffix. Byte suffixes use Go's simple Unicode
lowercasing (`1KİB` is 1024 bytes). Replace selectors matching Pulse's former
generic duration/byte text and upgrade query-serving applications together.
Numeric filters and plain `unwrap foo` expose
`strconv.ParseFloat: parsing "...": invalid syntax` or `value out of range`,
with the complete original label value. Malformed input remains a syntax error
even if its numeric prefix overflows. Quoting follows Go's Unicode 17 printable
characters and named control, `\xNN`, `\uXXXX` and `\UXXXXXXXX` escapes, not
JSON quoting or the duration converter's byte-oriented quoting. Replace
selectors matching the former `invalid number value` text or unwrap overflow's
former `invalid syntax` reason when upgrading query-serving applications.
Missing/empty unwrap values still supply no sample; failed present values fail
evaluated windows unless filtered or explicitly preserved as described above.
LogQL strings use double quotes or raw backticks, not single quotes. Quoted
strings decode `\a\b\f\n\r\t\v`, `\\`, `\"`, exactly two hexadecimal byte
digits (`\xNN`), exactly three octal byte digits (`\000`–`\377`), and
fixed-width `\uXXXX`/`\UXXXXXXXX` escapes. Byte escapes preserve bytes:
`\xFF` is not the UTF-8 encoding of `ÿ`. Escaped NUL works in exact diagnostic
selectors, but literal NUL and invalid UTF-8 source reject. Literal newlines
reject inside double quotes; raw backticks preserve newlines, carriage returns
and backslashes. Literal carriage returns also survive double quotes.

Unicode decoding follows Loki's pinned Prometheus decoder, not Go's
`strconv.Unquote` or JSON: each escaped surrogate becomes U+FFFD, so a surrogate
pair produces two replacement characters. Non-surrogate values through U+10FFFF
encode as UTF-8. Positive out-of-range values reject; the pinned decoder's
signed-int32 overflow makes eight-digit `\U80000000`–`\UFFFFFFFF` escapes
produce their low byte, which Pulse also preserves. Unknown/incomplete escapes
and octal values above 255 reject. Regex backslashes must be doubled, as in
`|~ "\\d+"`, or use raw backticks, as in `` |~ `\d+` ``.

When upgrading query-serving applications, replace former single-quoted strings
and permissive unknown escapes with these forms. Surrogate, hex-byte and octal
selectors now use Loki's decoded values. Storage, native ABI, keyed bytes and
resource ceilings do not change. Exact parser-error wording and positions
remain a separate compatibility gap.

Numeric and duration/byte label filters accept both `=` and `==` for equality;
string filters, stream selectors and drop/keep matchers still use `=`. Numeric
label values use float64 comparisons, including NaN/infinities, hexadecimal
floats and digit separators. Integers beyond exact float precision can compare
equal after rounding. Duration/byte values keep the checked integer policy above.

A missing typed-filter label does not match. A present empty, malformed or
overflowing value keeps the line with `__error__="LabelFilterErr"` and
`__error_details__`, preserving an earlier nonempty error instead of replacing
it. Details use the Go conversion diagnostics described above.
Later `| __error__=""` filters can remove these lines; explicit error selection
can retain them. Unpreserved errors fail metric queries, even if grouping would
remove the error labels. Compound `and` evaluates both operands and threads
error labels through them; `or` skips its right operand when the left matches.
Normal decimal filters can run natively; values requiring conversion/error
handling fall back to the bounded Elixir pipeline. Filtered-out observations
still spend scan/work budgets, but not retained-sample quota.

The reserved `__error__` and `__error_details__` labels are strings. Comparing
either with a numeric, duration, byte or `ip(...)` operand returns HTTP 400
`parse_error` before storage access, including compound, nested metric and
post-unwrap expressions. Use string/regex comparisons instead; ordinary typed
labels and existing error-preservation rules are unchanged. Upgrade
query-serving applications for this error-classification fix. It changes no
native ABI, storage/keyed bytes or resource ceiling; exact general parser
wording and positions remain incomplete.

Upgrade every serving app/native pair together before relying on these parser
collision, logfmt, quantity and filter-error semantics. The required log codec
tuple is `{1,1,19}` (19 adds native `keep` and post-unwrap `__error__=""`
filters); older artifacts fail startup. They do not change stored
records or keyed encoder bytes.

### How log queries choose segments

Each log push becomes one stored segment, so query cost is mostly one object
GET per segment read. Pulse reads fewer segments in three ways:

- **Limited log queries stop early.** A log query with a `limit` (no
  `interval`) reads segments newest first for `direction=backward` and oldest
  first for `direction=forward`, and stops once no unread segment can hold an
  entry that would replace one of the `limit` it already has. The scan budgets
  count only segments actually read, so a long range no longer fails just
  because it contains many segments.
- **Stream labels prune segments.** Each new segment records the complete set
  of values of `cluster`, `namespace`, `container`, `service_name`, `env`,
  `job` and `pod` (plus `error_source`/`error_project`) in the manifest, when
  there are at most 32 values per label and they fit a 4 KiB summary; labels
  past that bound are omitted, and later names go first. A segment is skipped
  when a `=`, `!=`, `=~` or `!~` matcher on one of those labels matches none of
  its values (regex matchers use the same engine as row matching). A missing
  label counts as the empty value, as in LogQL. Segments written before this
  release, and labels a summary omits, are always read. Log compaction keeps the
  summaries of the segments it merges.
- **Stream labels prune manifest pages.** Planning reads the manifest pages
  covering the time range, up to 32 at once. Each page written by this release
  records the union of its segments' service and label sets (within 2 KiB), so
  a selector that none of a page's segments can match skips the whole page.
  Pages written by earlier releases are always read.
- **Scans read ahead.** Metric queries and unlimited log queries read up to 32
  segments ahead while those segments keep at most 16 MiB in flight. Limited
  log and trace queries start at `PULSE_QUERY_PREFETCH` segments ahead and read
  as far ahead as they have already read, up to the same bound, so a limited
  query that has to scan its whole range is not held to the configured depth
  (see `PULSE_QUERY_PREFETCH` in [configuration](configuration.md#query-budgets)).

Line filters do not prune segments; they are evaluated natively on every row
of every segment the selector keeps. `PULSE_QUERY_MAX_SCAN_ROWS` counts the
lines a log query's stream selector and leading line filters select, not every
line stored in the segments it reads, and with
[stream-grouped log segments](configuration.md#stream-grouped-log-segments) a
service selector reads only its service's segments of settled hours. For alert rules over many uncompacted
segments, enable [log compaction](configuration.md#log-compaction) and
[ingest coalescing](configuration.md#ingest-coalescing) to reduce how many
objects a range covers.

A query over a scan budget fails whole with HTTP 422 `query_limit` (MCP:
`:query_scan_limit`) and names the budget, its value and what the query
reached, for example `max_scan_segments=1024 exceeded: candidates in the time
range total at least 2400 segments`.

### Limits and metric evaluation

Send `X-Loki-Query-Limits: {"maxQueryLength":"1m"}` to add a request-local
time-window ceiling to finite Loki reads (GET or form POST). The exact boundary
is allowed; a longer `end - start` returns HTTP 400 before storage reads. The
check uses effective default bounds too, including discovery's six-hour default.
It covers log/metric queries, discovery, index statistics/volumes, detected
labels/fields/values and patterns. Instant metrics normally have a zero-length
evaluation window; range selectors such as `[1h]` are not this policy's window.
Instant log reads require an explicit finite `start` with a positive ceiling.

Queries also accept `maxQueryInterval` and `maxEntriesLimitPerQuery` in the same
header. `maxQueryInterval` bounds each metric range selector, including selectors
inside aggregations and either side of binary expressions. `[1m]` is allowed
with a `1m` ceiling; `[60001ms]` rejects. It does not bound offsets, the outer
evaluation window or plain log reads. A parenthesized log pipeline before its
range bracket, such as `count_over_time(({job="api"} |= "error")[1m])`, works too.
`maxEntriesLimitPerQuery` bounds the requested log-entry `limit`, including the
default of 100. An excessive request returns HTTP 400 before storage rather
than returning a truncated result. Detected-field/value requests apply it to
`line_limit` instead; it does not cap metric points or stream discovery.

`requiredLabels` accepts an array of stream-selector label names, while
`minimumLabelsNumber` requires a minimum number of matchers. Both apply to each
selector independently, including every metric branch, detected-field/value
requests and patterns. Pipeline filters and aggregation labels do not satisfy
them. Required names are deduplicated; matcher counts include repeated names,
as in Loki. Any matcher operator satisfies name presence, so these policies do
not prove a selector is selective. Missing required names reject before matcher
counts. Empty required-name arrays and a zero minimum add no restriction.
These policies do not restrict selector-free scalar/vector expressions or
label/series discovery.

`maxQueryTime`, for example `"500ms"`, shortens the query worker's execution
deadline across these finite APIs, including discovery, detected fields,
patterns and both volume modes. The effective timeout is the smaller positive
client/server timeout; zero or an omitted field keeps the server deadline.
An expired worker returns HTTP 504 `query_timeout` and releases query admission.
This bounds admitted query execution, not HTTP body parsing or response encoding.
Native work or provider requests already dispatched may finish after the caller
times out; this is not a provider-side cancellation guarantee.

Use ordered, unrepeated integer duration components (`y`, `w`, `d`, `h`, `m`,
`s`, `ms`), for example `1h30m`; durations must fit signed 64-bit nanoseconds.
The entry ceiling and matcher minimum are nonnegative JSON integers fitting
signed 64 bits. Required names must be strings; the header's size bound applies
to the whole array too.
An absent header, `{}`, or a zero field adds no restriction for that field.
Policies are limited to one header of 1,024 bytes and 128 bytes per duration
string. Malformed, negative, overflowing, duplicate-key, duplicate-header and
unsupported-field policies return HTTP 400 rather than
being ignored. This is deliberately stricter than Loki's malformed-header
fallback. Live tail rejects this header because it has no finite end. Client
policies never raise server scan/admission/resource budgets or persist between
requests. This is optional client tightening, not an operator security quota.
Upgrade all query-serving applications before relying on enforcement;
older instances ignore the header. No configuration switch, native/storage or
keyed-byte change is required.

`maxQueryLookback`, `maxQueryBytesRead` and
`tsdbShardingStrategy` remain unsupported and reject explicitly.

`limit` keeps the newest lines (`direction=backward`, the default) or the oldest
lines (`direction=forward`) across all matching streams, as Loki does. Direction
is case-insensitive; malformed supplied limits or directions return HTTP 400.
Without a positive `interval`, only those lines are held while the query reads
storage, and a backward query stops reading as soon as no older segment can
contain a newer line.

Range log queries accept `interval` as nonnegative float seconds or an ordered
integer Prometheus duration. A positive interval keeps the first line and then
lines at least that far from the last emitted line, globally across streams in
the requested direction, **before** applying `limit`. This is not metric `step`
or per-stream sampling. Because stored batches are not globally ordered, this
path collects and sorts selected entries under the existing log-sample, work,
scan, deadline and worker-heap ceilings. It can therefore fail a broad request
that ordinary top-k can answer; exhaustion fails the whole query. Zero/omission
keeps the ordinary streaming top-k path.

Metric queries such as `rate`, `count_over_time`, `bytes_over_time`,
`quantile_over_time` or `sum_over_time(... | unwrap ...)` reduce each selected
line to one sample of its series while reading, so their memory follows the
number of series and samples rather than the log volume. When the pipeline only
uses line filters, `logfmt`, `regexp`, string, regex or number label filters,
`keep` of plain label names (with no parser after it) and a plain `unwrap`,
optionally followed by `| __error__=""`, it runs natively without creating
per-line Erlang terms;
other pipelines, and lines whose labels or bodies are not plain strings, use the
equivalent Elixir pipeline with the same results. Every kept line counts
against `PULSE_QUERY_MAX_LOG_SAMPLES` and every selected line as work (see
[query budgets](configuration.md#query-budgets)); log queries do not use
PromQL's `PULSE_QUERY_MAX_SAMPLES`.

LogQL `sum_over_time` and vector `sum` use compensated floating-point summation,
retaining small contributions across observations and series, including when
large positive and negative values cancel.
This is still float64 arithmetic, not exact arbitrary-precision summation;
existing selected-sample, window-work and output ceilings are unchanged.

The leading `quantile_over_time` parameter is an unsigned numeric token:
`-0.1`, `-0` and explicitly signed `+0.5` reject before storage, while exponent
signs such as `5e-1` remain valid. Values above one still return `+Inf`;
signed scalar expressions elsewhere retain their existing meanings. Rejections
use the existing parse-error envelope, not exact upstream diagnostic text.

### Stream discovery

`/loki/api/v1/labels`, `/loki/api/v1/label/<name>/values` (both with an
optional `query` selector) and `/loki/api/v1/series` (optional `match`/`match[]`
selectors) accept GET or form-encoded POST. Stream labels are the labels a
stream selector can match: the stream labels of pushed logs, the resource
attributes of OTLP logs, and `service_name` for records with a service.
Empty values count as absent. Repeated `match` and `match[]` values are unioned
and deduplicated. Omission or a lone `{}` selector (including ASCII spaces)
discovers all streams under the same budgets. Without explicit bounds,
discovery covers the last hour; `since` can change that window.

On these three discovery endpoints, repeated scalar `query`, `start`, `end`
and `since` parameters use their first value. Form-body values precede URL
values, including empty values: an empty first value uses the parameter's
default, while an invalid first value rejects even if a later value is valid.
Names are literal: `query[]`, `start[]`, `end[]`, `since[]` and nested bracket
spellings are separate, unused parameters, not arrays/maps of the scalar name.
They neither select streams nor override or repair a malformed literal parameter.
This does not change repeated selector unions, discovery request-size ceilings
or the separate Prometheus discovery duplicate-parameter rejection policy.
Upgrade query-serving applications for these discovery parsing semantics;
native/storage/keyed-byte formats and resource ceilings are unchanged.

Discovery selectors and the `query` parameter of `/loki/api/v1/index/stats`
accept only label matchers. A pipeline such as `{job="api"} |= "error"` or
`{job="api"} | logfmt` returns HTTP 400 rather than silently ignoring stages.
Use `/loki/api/v1/query_range` to filter log lines.

Discovery reads only the timestamp, service, level and stream-label columns
of the stored segments, natively, and evaluates each distinct stream once per
batch rather than once per log line. Results are complete or fail: more than
5,000 entries or 1 MiB returns HTTP 422 instead of a truncated list, and the
segment, byte and row budgets below apply. Narrow the time range or add a
selector when a broad request fails.

### Index statistics and volume

`/loki/api/v1/index/stats` estimates a query's size from storage metadata
alone, which Grafana shows before running a query. It counts whole stored
segments that overlap the range and can match an exact service selector, so it
is an upper bound; `streams` is always `0` because Pulse does not index
streams. GET and form POST validate the same range parameters as Loki:
positive uint32 `limit`, case-insensitive `forward`/`backward` direction,
positive `step` with at most 11,000 integer intervals, and nonnegative
`interval`. Empty values use the range-query defaults. These parameters are
validated even though statistics use only the selector and time bounds;
they do not sample or truncate the estimated totals. Invalid parameters
return `400` before storage reads. Existing window policies still apply.

`/loki/api/v1/index/volume` and `/loki/api/v1/index/volume_range` return log
bytes per group, largest first. Both accept GET and form POST:

- `aggregateBy=series` (the default) groups by `targetLabels` (comma-separated)
  when given, otherwise by the selector's label names. `limit` (default 100,
  maximum 5,000) bounds the instant result. This uses the same storage reads
  as an equivalent `bytes_over_time` query.
- `aggregateBy=labels` counts each selected line's bytes once for every stream
  **label name**, across all values, returning metrics such as `{"pod":""}`.
  Omitted `targetLabels` includes all names on matching streams, not only names
  in the selector. Explicit targets restrict names; each target not already
  constrained by the selector also requires a nonempty stream value. Empty
  values, structured metadata, parser-created labels and Loki's internal
  `__loki_tenant__` name are not counted. This mode accepts selectors only,
  not pipelines, and scans stored lines once instead of using chunk estimates.

Label-name volumes count actual UTF-8 line bytes within the inclusive
nanosecond `[start,end]` window, not Loki's estimated chunk KB or whole-second
storage windows. In `volume_range`, `step` accepts seconds or a duration, at
least 1 ms, defaulting to the window divided by 250 (whole seconds, at least
one second). At most 11,000 epoch-aligned buckets are allowed. Internal
boundaries belong to the next bucket, and the final `end` remains inclusive;
nonfinal sample timestamps are one millisecond before the next boundary,
and the final timestamp is `end`. `limit` applies independently per bucket,
so a matrix may contain more than `limit` names. Missing buckets are omitted,
not zero-filled; range responses always use a matrix. Ties sort by name;
series sort by their first sample's bytes, then name.

Label-name queries fail whole on scan, selected-line, work, intermediate or
result-point limits. The complete dictionary is capped at 5,000 names and
1 MiB of name bytes **before** applying `limit`; reducing `limit` does not
bypass admission. These queries read Parquet lines in bounded batches and
can cost more than Loki's index-backed volume estimates. No index or storage
format change is required.

`/loki/api/v1/status/buildinfo` reports the Loki API version Pulse follows.

### Patterns

`/loki/api/v1/patterns` returns the log patterns of the lines a log `query`
selects between `start` and `end` (default: the last hour), each with its line
count per `step` (default: the window over 250, at least one second; at most
11,000 steps), most frequent first, as Logs Drilldown expects. Variable parts
of a pattern read `<_>`, and every pattern is a valid `|>` line filter that
selects the lines it counts.

Loki mines patterns continuously at ingestion; Pulse mines them when queried,
from every selected line in the window, so a pattern request reads what the
equivalent log query reads and the same query budgets apply. Mining runs
natively over stored segments when the query is a selector with optional
`|=`, `!=`, `|~` or `!~` filters. Patterns are a heuristic summary: Pulse
groups lines with its own Drain-based miner and returns at most 500 patterns,
which need not match the patterns Loki would report for the same logs.

### Detected labels and fields

Grafana's Loki query builder and Logs Drilldown use these for suggestions.

`/loki/api/v1/detected_labels` returns the stream labels an optional `query`
selector matches, with their number of distinct values, from the same complete
discovery as `series`. Like Loki, it omits labels whose values are all numbers
or UUIDs, except `cluster`, `namespace`, `instance` and `pod`, and nonempty
value sets containing only the literal strings `0` and/or `1`. Other numeric
spellings such as `0.0`, `+0` or `-0` do not get this boolean exception.
Detected-field typing still classifies `0`/`1` as integers; only label
suggestion filtering changes. Upgrade query-serving applications; no native
or storage-format change is required.

`/loki/api/v1/detected_fields` and
`/loki/api/v1/detected_field/<name>/values` read the newest `line_limit`
lines (default 100, at most 5000) a log `query` selects between `start` and
`end` (default: `since`, one hour, before now). Fields are each line's
structured metadata (log attributes), labels the query's own parsers extract,
and the line parsed as JSON (nested objects joined with `_`, reported with their
JSON path) or otherwise as logfmt. Types are Loki's: `int`, `float`,
`boolean`, `duration`, `bytes` or `string`. `limit` (default 1000, at most
5000) caps the number of fields or values. A missing or empty `limit` falls
back to the legacy `field_limit` parameter; if both are missing/empty, the
default applies. A nonempty `limit` takes precedence, even when invalid.
The selected value must be a positive integer at most 5000; invalid values
reject before storage rather than silently using the default. Cardinality is
the exact count of distinct values in the sampled lines, where Loki estimates it.

Detected-field JSON observation also recognizes a trailing comma after an
object's final value, including nested objects, without changing stored lines.
This is local to field detection: commas inside strings stay literal, trailing
array commas and other malformed structures remain invalid, and ordinary
LogQL `| json` and JSON transport admission do not change. Invalid detector
JSON still falls back to logfmt. The additional scan/decode stays after
newest-line selection under existing query-worker bounds; it does not make
field discovery a complete malformed-JSON parser. Upgrade query-serving
applications; no native/storage-format change is required.

JSON string values observed by field detection replace decoded U+FFFD (`�`)
characters with spaces, matching ordinary LogQL JSON extraction. This includes
JSON `\ufffd` escapes, but not literal backslash text. Original stored lines,
JSON keys/paths and structured metadata remain unchanged. Upgrade query-serving
applications for this observation-only correction; storage formats and resource
ceilings do not change.

Automatic logfmt field detection keeps the first retained value for each final
field name, including sanitized-key aliases and stream-label `_extracted`
suffix collisions. Empty values are skipped by default, so an empty first pair
does not claim the name. Stored lines, metadata and ordinary LogQL parsing stay
unchanged. Upgrade query-serving applications for consistent suggestions;
storage formats and resource ceilings do not change.

Both endpoints validate `step` as seconds or an ordered integer Prometheus
duration, with a minimum of 1 ms. Omission or an empty value uses the whole-second
floor of the window divided by 250, at least one second. The integer-truncated
number of intervals must not exceed 11,000, calculated with the original duration
before any millisecond truncation. Malformed, smaller or overflowing steps return
HTTP 400 before storage; parameter text remains bounded to 128 bytes. This is
request admission, not a change to Pulse's newest-line sampling or field results.

Both time bounds are inclusive. The newest-line limit applies across all
matching segments, not separately to each segment or time bucket. Widening the
window may reveal older field values only when they fit in that sample; it does
not turn these suggestions into a complete retained-field inventory. GET and
form POST use the same bounds and sampling rules, and existing scan/query
resource limits still apply to wide windows.
Upgrade query-serving applications for empty-limit fallback and step admission;
native/storage/keyed-byte formats and existing resource ceilings are unchanged.

### Live tail

`/loki/api/v1/tail` streams logs over a WebSocket, as Loki does and as
Grafana uses for live mode in Explore. The query must be a log query. The
socket first receives the newest `limit` entries (default 100, at most 5000)
since `start` (default: one hour ago), oldest first, then newly observed matching
entries on a best-effort live stream, in Loki's `{"streams": [...], "dropped_entries": ...}`
frames. `delay_for` (0 to 5 seconds) is accepted and ignored: entries are never
held back.

A tail sees pushes to every instance, whether or not instances are connected
to each other. Pushes to the instance serving the tail arrive as soon as they
are acknowledged; pushes to other instances arrive once the serving instance
next reads the tenant's log manifest, every `PULSE_LOKI_TAIL_POLL_INTERVAL_MS`
(default 1000) while the tenant has tails open on it. Each poll is one
conditional GET of the manifest plus one GET per new log segment. Deduplication
compares exact timestamps, labels and lines, not short hashes. Each tenant's
follower retains identities for up to 120 seconds, capped at 200,000 entries and
16 MiB of identity payload (line/label bytes and eight timestamp bytes per entry);
the oldest are evicted as entries arrive. Standalone binaries are reused; retained
slices are detached so small identities cannot pin large request/column buffers.
These are cache bounds, not total process-memory limits. An entry repeated after its
identity expires or is evicted can be delivered again.

Queue admission happens before sending record batches, with at most 64 queued
batches and 16 MiB of serialized input credit per recipient. One batch up to
32 MiB can occupy an otherwise empty queue, accommodating term overhead on a
large admitted ingest request; no second batch can join it above ordinary credit.
These credits exclude currently processing work, encoded frames and referenced
request/column arenas, so they are not a bound on total retained memory. A slow
or oversized stream closes explicitly with WebSocket code **1013**; reconnect
and query history. Follower termination or restart also closes affected sockets
with 1013 instead of silently starting a new live cursor. Reconnecting reads a
new history window; overlap can repeat entries and does not prove gap-free delivery.
If local tail supervision is unavailable before upgrade, the request returns
HTTP **503** and can be retried. A lower configured backlog threshold can still report up to
100 dropped entries per frame, unfiltered.

Live tail follows segments whose newest event is at most an hour old. A poll
with more than 64 unseen original segments closes the stream with 1013 instead
of publishing a partial cursor. Local low-latency hints can be dropped under
pressure; S3 polling is the fallback, not a durable delivery queue. Compaction
settles by **event time**, not publication time, and compacted replacements are
not replayed. A late publication, polling failure or source retired between
snapshots can therefore be missed, even without a detected backlog. This is
not a complete changefeed or an exporter-delivery guarantee; query storage for
durable history and size compaction settle/poll intervals for the workload.
Entries pushed while no tail is open are not replayed. Each instance accepts
`PULSE_LOKI_TAIL_MAX_PER_TENANT` concurrent tails per tenant (default 10);
more return HTTP 429. Admission is atomic across simultaneous connections on
that instance, including connections still preparing history. Slots are released
when the connection leaves or its process terminates. This is not a deployment-wide
limit; adding instances increases aggregate tail and object-store polling pressure.

### Shared query regex semantics

PromQL, trace predicates, log queries, live tails and native log-metric scans use the same bounded
Go/RE2-subset regex policy: ASCII Perl classes/word boundaries, Unicode
codepoint `.` and strict end-of-input `$` (unless multiline mode is explicit).
Braced hexadecimal escapes can precede repetition (`\x{61}+`, `\x{61}{2}`),
including padded digits and Unicode characters. Invalid escapes and actual
nested/possessive repetitions reject, including repeated lazy suffixes:
`a??` is valid, but `a???` and `a{2}??` are not.

Counted repetitions follow Go's 1,000-copy admission limit, including nested
products: `(x{100}){10}` is valid, but `(x{100}){11}` rejects. Invalid inner
counts still reject under an outer `{0}`. Ordinary `*`, `+` and `?` do not add
a counted bound. Leading-zero and malformed count spellings such as `x{01}`,
`x{,1001}` and `x{1001` denote literal braces; the complete `x{1001}` rejects.
Existing compiled-program and query-work ceilings apply independently.

Literal quoting (`\Q...\E`) ends at the first `\E` or the pattern's end.
Following quantifiers apply to the last quoted character: `\Qab\E+` matches
`ab` and `abb`, not `abab`. Quoting inside character classes rejects.
Octal escapes consume up to three digits and denote Unicode characters,
not raw bytes: `\141` matches `a`, and `\400` matches `Ā`. A leading zero
can stand alone; other first digits require a second octal digit. `\1`
remains an unsupported backreference. Octals work inside character classes
and before quantifiers. Query-string escaping is separate: use raw LogQL
strings or double each regex backslash in a double-quoted query literal.
Whole-label and trace matching stays fully anchored, even when `\E` is omitted.
POSIX classes retain ASCII membership with Unicode simple case folding under
`(?i)`; negated classes exclude those folded characters too.
Inside character classes, repeated `&&` and `~~` are ordinary members, not set
operators: `[x&&y]` matches `x`, `&` or `y`. Negation, folding and adjacent
ranges retain Go semantics; invalid ranges still reject. Opening brackets are
literal members except in complete POSIX named classes: `[[]` matches `[`, and
`[a[]\d` matches `a5` or `[5`. Hyphens follow left-to-right scalar ranges:
`[--x]` includes `-` through `x`, while `[a--b]` rejects its descending range.
These spellings do not enable Rust class intersection, subtraction, symmetric
difference or nested-class semantics.

Negated classes operate on Unicode scalars, including the adjacent U+D7FF and
U+E000 endpoints on either side of the surrogate hole. For example,
`[^\x{d7ff}\x{e000}]` excludes both endpoints but matches U+D7FE and U+E001.
Raw UTF-8 members, hexadecimal escapes, range endpoints, case folding,
captures and repetition preserve that exclusion. This does not admit surrogate
code points or arbitrary byte strings as inputs.

Unicode property escapes accept Go's leading-caret negation: `\p{^Latin}` is
`\P{Latin}`, and `\P{^Latin}` is `\p{Latin}`. This also works inside classes,
with case folding and before quantifiers; quoted or escaped literal text stays
literal. Category and script membership follows Go 1.27.3's Unicode 17 tables,
including newly assigned characters and scripts. Category aliases such as
`Uppercase_Letter`, full script names such as `Canadian_Aboriginal`, and
`Any`, `ASCII` and `Assigned` work. ASCII case, spaces, underscores and hyphens
in names are ignored: `\p{upper case-let ter}` is `\p{Lu}`. Tabs, Unicode
whitespace, ISO script abbreviations such as `Latn`, binary properties such as
`White_Space`, and `property=value` forms reject. This matches the pinned
upstream parser profile, not every regex dialect.

Property-specific simple folds apply before negation, respecting inline flag
scopes. Properties do not change the version of case folding for literal
characters or other classes; complete Go regex/case-fold parity remains open.
Property preparation has a separate 1 MiB logical expansion ceiling: 21 bytes
per source range plus 24 bytes per property, charged before union or zero-repeat
simplification. Emitted text reserves its maximum size before each expansion.
Very repetitive property expressions can reject earlier than upstream.
Existing compiled-program, schema, work and query limits still apply.

Capture headers require nonempty raw ASCII names in `(?P<name>...)` or
`(?<name>...)`. Unicode, punctuation and escaped/quoted name bytes reject;
literal normalization never repairs an invalid header. Names can start with
digits and repeat in selectors and `label_replace`. Replacement expansion
selects the first participating capture with that name, including a matched
empty capture. Decimal references below one billion without leading zeros
always select their original numeric index, never a same-spelled alias;
leading-zero and larger numeric spellings name aliases instead.

Loki `regexp` parser stages require unique raw names, even if a duplicate is
optimized away. Numeric destinations gain an underscore prefix (`1` becomes
`_1`) before ordinary stream/metadata collision suffixing. Distinct names that
normalize to one destination keep the first declared capture, including an
empty or unmatched capture on a matching line.

Inline `i`, `m`, `s` and `U` flags accept repetitions, with disabling taking
precedence within a header (`(?i-i)` disables folding). Empty `(?)` directives
do not introduce an atom: `x(?)*` repeats `x`. Directives between an atom and
its quantifier preserve that atom's earlier flags, subsequent flag scope and
`U`/lazy greediness. Flag-separated repetition of an already quantified atom
adds another repetition: `x*(?)?` means `(?:x*)?`, not the lazy `x*?`.
Only the preceding atom is repeated, not the whole concatenation. Flags still
apply to subsequent text and to each quantifier's own greediness. Counted
products retain the 1,000-copy ceiling, even through directives; adjacent
quantifiers without a directive still reject. No synthetic capture is added.
Named `regexp` parser admission inspects the
same native program as extraction, so these supported flag and atom-binding
forms also work in parser stages. At least one real named capture is required;
quoted/class-contained fake headers do not qualify. Unmatched lines remain
in the result without newly extracted labels.
Captures erased by zero repetition or an impossible alternative still exist
in the original schema. On a match, their values are empty strings, not missing
labels; later parsers cannot overwrite that first extraction. Original numeric
indices and later live captures do not shift. A nonmatch still adds no labels.
Predicate, `regexp` parser, indexed-extraction and template-helper schemas have an
independent 1 MiB logical ceiling: 32 bytes per group plus raw capture-name
bytes. This also limits expressions whose
optimized programs are tiny; oversized schemas reject rather than expanding
unbounded capture maps. Template replacements index named aliases only after
shared schema admission; counting allocates no name metadata. Existing program,
scan, work and heap limits also apply.

Upgrade every query-serving app/native pair before relying on these forms.
The required log capability tuple is `{1,1,19}` for missing unwrap values before
prior pipeline-error checks, correlation-ID metadata,
scalar class complements, Unicode property admission and numeric/repeated capture names;
trace/metric capability tuples, storage formats and keyed bytes are unchanged.
Unsupported syntax rejects rather than switching dialects. Remaining pipeline
line/label predicates, drop/keep and named `regexp` capture extraction use the
same non-backtracking native engine as pushdown, rather than treating a PCRE
execution-limit failure as a nonmatch or empty capture set. Upgrade every
serving app/native pair before relying on this parity.

### Time parameters

Instant queries honor `time` (default: now); an explicitly supplied `end` is a
compatibility fallback when `time` is absent. Range queries default to an end of
now and a start one hour before the earlier of `end` and now. `since` changes
the default start using ordered integer Prometheus durations such as `1d2h`;
an explicit start wins, but malformed `since` still rejects. Supply explicit
bounds for older data.
`time`, `start` and `end` accept integer Unix timestamps, decimal Unix seconds
or RFC3339 strings. Calendar parsing follows Go's RFC3339Nano grammar, including
single-digit hours, dot/comma fractions and signed timezone offsets with hours
up to 24 and minutes up to 60 (inclusive). Clock hours still stop at 23;
lowercase `t`/`z`, leap seconds and malformed dates reject. Fractions retain
the first nine digits, truncating additional digits rather than rounding.
Decimal seconds follow Loki's float64 conversion and millisecond fractional
rounding, not exact decimal
nanoseconds. As in Loki, integer strings of at most ten
characters mean Unix seconds; longer integer strings mean Unix nanoseconds.
The converted value must fit signed int64 nanoseconds. Use RFC3339 to identify
very early epoch nanoseconds unambiguously. Timestamp text caps at 128 bytes.
Malformed, overflowing or reversed supplied bounds return HTTP 400 instead of
being dropped into an unbounded scan. Nonfinite and nonportable out-of-range
float conversions reject rather than inventing a timestamp.

Range `step` accepts positive float seconds or ordered integer Prometheus
durations. Its default is the whole-second floor of the window divided by 250,
at least one second. HTTP admission rejects more than 11,000 intervals;
evaluation still applies the existing stricter inclusive-point and resource
ceilings. Numeric/duration parameter text is bounded to 128 bytes. Primitive
uint32 acceptance does not bypass endpoint caps: detected fields and volume
retain their 5,000 limit, and tail retains its configured entry cap and
five-second maximum `delay_for` (accepted but not used to delay delivery).
Upgrade all query-serving applications for these HTTP semantics; native,
storage and keyed-byte formats are unchanged.

Raw MCP logs expose complete typed OTLP metadata; Loki responses remain
line-oriented projections. See [stored log content](logs.md#stored-content-and-raw-queries).

LogQL is a subset, not a complete Loki replacement. Metric queries support
suffix `by (...)` and `without (...)` grouping for unwrapped averages, extrema,
variance/deviation, quantiles and first/last observations. Quantiles interpolate
between observations after grouping across matching streams. The unwrapped
label is removed from series identity. Empty ordinary windows are missing
samples, not synthetic zeros; `absent_over_time` returns one only for an empty
window. Set operators preserve sample values and unmatched right-hand union
members. Empty-label aggregations remain vectors, and ambiguous arithmetic
matching returns an error rather than overwriting a series.

For duplicate indexed-side series in LogQL binary matching, the error message
identifies the `right hand-side`, or the `left hand-side` when `group_right`
indexes the left operand. A matched many-side collision without an explicit
group modifier reports `multiple matches for labels: many-to-one matching must
be explicit (group_left/group_right)`. These remain HTTP 400/`evaluation_failed`;
matching, filtering and grouped-output uniqueness policies are unchanged.
Upgrade query-serving applications; no native or storage change is required.

LogQL ranking parameters validate before storage reads. For `topk`, an omitted
parameter reports `parameter required`, while a fractional parameter reports
`invalid parameter`. These remain HTTP 400/`evaluation_failed`; valid ranking
results, integer admission, zero-rank policy and budgets are unchanged.
Upgrade query-serving applications; no native or storage change is required.

Supported unwrap-only range aggregations, including `stdvar_over_time` and
`stddev_over_time`, report `invalid aggregation <operation> without unwrap`
when `unwrap` is absent, before storage reads. HTTP 400/`evaluation_failed`,
parameter/grouping validation precedence and successful arithmetic are unchanged.
Upgrade query-serving applications; native artifacts and storage are unchanged.

LogQL `sort` and `sort_desc` reject nonempty `by` or `without` grouping,
including nested aggregations, before reading storage. Empty `by ()` and
`without ()` remain admitted, as do ungrouped sorts and grouping on ordinary
aggregators. Rejections use HTTP 400/`parse_error` with
`sort and sort_desc doesn't allow grouping by`. Upgrade query-serving
applications; sorting algorithms, budgets and native/storage formats are unchanged.

For `absent_over_time` without `unwrap`, a pipeline consisting only of plain
`json` parsers and line filters skips unused JSON extraction. Malformed JSON
then still proves presence instead of creating an unused parser error. The
whole pipeline must qualify: label/error filters, format stages, explicit JSON
fields and other parsers retain ordinary execution and error checks. Pre-existing
metadata errors still fail observations. Validation and selected scan/work
charges remain; this is not general parser-hint or error-suppression support.
Upgrade query-serving applications; log codec `{1,1,18}` remains sufficient.

Every `unwrap` aggregation skips missing or empty target fields, including
duration/byte conversions. They create neither observations nor empty series;
`absent_over_time` therefore returns one when all target fields in the window
are missing/empty. Present malformed values still fail evaluated windows.
An earlier pipeline error on a skipped line does not fail the aggregation:
there is no observation to carry it. Usable unwrap targets and count/bytes
observations retain their existing error checks on both native and Elixir paths.
Skipped fields consume scan and pipeline work, not retained-log-sample quota.
Upgrade every query-serving app/native pair before relying on this behavior;
the required log codec tuple is `{1,1,18}`. Old native artifacts fail startup
rather than serving the previous error behavior. No storage-format,
keyed encoder-byte change, migration or retry drain is needed.

`rate_counter({app="api"} | logfmt | unwrap requests [5m])` treats the extracted
values as a counter, compensates each decrease as a reset and extrapolates the
per-second increase to the window edges. Distant edges cap at half the average
sample spacing; back-extrapolation also stops at the counter's zero point.
It requires `unwrap`, forbids range grouping, and supports instant/range queries
and offsets. Missing or empty counter fields supply no observation; present
nonnumeric fields fail evaluated windows. One observation returns zero; no
observations return no sample. This differs from unwrapped `rate`, which sums
observations and divides by the window duration. Equal-time counter observations
follow ascending canonical record keys, not numeric-value or arrival order;
Loki equal-time ordering parity is unproven. Counter evaluation uses the bounded
Elixir pipeline, not the packed native metric fast path.

Expressions cap at 16,384 UTF-8 bytes, 256 AST nodes and 64 AST levels. A
quote-aware pre-parser guard also bounds parenthesis nesting at 64 and operator
characters at 512. Log-based metric queries share selected-sample, work and
cumulative point ceilings with the Prometheus evaluator: by default 100,000,
five million and 100,000 respectively. Repeated window visits consume work;
wide windows or many steps can fail even below the output ceiling. Object scan
budgets still apply separately to each selector, not to the deployment as a
whole. Budget failure returns no partial answer.

Label filters may follow `unwrap`; conversion runs before these filters and
grouping runs afterward. For example,
`sum_over_time({app="api"} | logfmt | unwrap latency | __error__="" [5m])`
removes failed conversions. Rejected observations still spend scan and pipeline
work but not retained-sample quota. A string/regex `__error__` filter that
explicitly accepts errors can retain failed conversions as zero-valued samples,
with `SampleExtractionErr` and `__error_details__` retained through range grouping.
Outer vector aggregation can combine these series. Reading `__error_details__`
alone does not authorize keeping errors, nor does an input `__preserve_error__`
label. A failing unwrap replaces a prior pipeline error with
`SampleExtractionErr` and its own details before post-unwrap filtering; a
successful unwrap leaves an earlier error unchanged. Error-label filters accept
string/regex operands, not numeric or unit conversions. Queries using
post-unwrap filters or explicit error preservation
use the bounded Elixir evaluator rather than the native metric fast path.

`@` modifiers, zero-duration windows, unsupported range grouping and non-filter
stages after `unwrap` still reject explicitly. Unfiltered invalid values in an
evaluated window fail the whole query, including invalid middle samples in
`first_over_time`/`last_over_time`; they never silently disappear from an average
or quantile. Invalid unwrap samples fetched only between sparse evaluation
windows do not invalidate windows they do not belong to. Unpreserved nonempty
`__error__` labels fail metric queries before grouping can discard them; the
guard applies only when a usable unwrap target supplies an observation.
Missing/empty targets skip earlier errors but still spend scan/pipeline work.
Complete parser-error generation
remains unsupported; quoted/raw string literals use Loki's scanner/decoder
profile above, and runtime numeric/duration/byte conversion details use the Go
profiles above.
Upgrade every query-serving app/native pair to log tuple `{1,1,8}` for
typed-filter errors, logfmt decoding and parser ownership; no storage-format or keyed-byte change
is introduced.
Other pipeline translation and complete Loki numerical,
error-label and client-wire compatibility remain unproven. Average/deviation
folds currently use the Prometheus numerical helpers and can differ from Loki's
own incremental reducers by a few ULPs; extrema can retain a different zero sign
on equal-valued ties. Matcher and pipeline-stage nodes
count toward the AST ceiling, so long valid pipelines can fail closed. Disabled
Grafana graph previews accept explicit same-tenant native Prometheus instant and
metric-producing LogQL instant/range bindings, with shared admission/deadline,
counters and conservative scan partitioning. Sparse native frames do not prove
Grafana gap filling or source conversion. See [graph previews](alerting.md#preview-an-imported-expression-graph).

## Limits

Raw `query_logs` and `query_metrics` result text each have a fixed 16 MiB ceiling, independent of row,
scan, deadline and heap budgets. Exhaustion returns `query_result_limit`, not
clipped bodies/metadata or a partial answer. Narrow the range or reduce `limit`.
The enclosing MCP transport envelope has additional overhead.

Each node runs a bounded number of queries at once, at most two per tenant, and
bounds each query's duration, memory, scanned objects, and result size. A query
that exceeds a budget fails with an explicit error rather than returning a
partial result; narrow the time range or the selector and retry. Samples that
conflict at the same timestamp resolve deterministically and add a warning to
the response. A stale marker wins a conflict with a finite sample at the same
timestamp; otherwise the maximum value wins, with ordinary NaN ordered last.
Out-of-order samples are sorted before evaluation. This is deterministic query
resolution, not ingest-time duplicate rejection.

Selected-sample and evaluation-work budgets cover all selectors and operations
in one expression. The result-point budget counts only the points a query
returns. Intermediate results (selector, function, subquery and operator
outputs) are bounded by the materialized-sample budget (250,000 by default),
which, like Prometheus's `query.max-samples`, counts the points held at once:
a result is released when the operation that consumes it finishes, so both
operands of a binary operation count together, but a `rate` and the `sum` over
it do not. Exhaustion returns `query_intermediate_limit`, not an output-size
error. Every outer query and inner subquery grid caps at 11,000
steps, independently of its series count. Nested subqueries share the sample,
work, materialized, deadline and heap ceilings. These can reject a supported
expression at a wide window or high cardinality; they never clip its answer.
Expressions have at most 256 nodes and 64 levels of AST depth.
All selectors of a query share one scan of their candidate segments. The
scan-row budget counts the rows the selectors match in the time range, not
the other series stored in the same segments; the segment and byte budgets
bound those reads.
