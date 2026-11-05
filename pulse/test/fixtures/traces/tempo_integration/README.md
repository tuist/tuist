# Tempo public HTTP integration cases

Pinned source: [grafana/tempo at 1a7373ee774b2ee5a40957c2310179b0ef7ff843](https://github.com/grafana/tempo/tree/1a7373ee774b2ee5a40957c2310179b0ef7ff843).
`cases.json` transcribes data and expectations from
[`integration/api/search/search_tags_test.go`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/integration/api/search/search_tags_test.go).
This is a selected public API port, **not the complete Tempo integration suite**.

| Upstream test | Imported cases |
| --- | --- |
| `TestTagEndpoints` | All seven two-span input batches; v1 tag-name list and bare `service.name` values; six v2 name-content rows and six v2 value-table rows. Name rows cover unfiltered, resource-filtered span/resource scopes, no matches and service equality; exact selections are below. Value rows cover no filtering, first/second resource attribute, too restrictive, both batches/name values and only resource attributes. |
| `TestTagValuesWithSpecialCharacters` | All 19 enabled attribute/value pairs, in resource and span scopes; explicit encoded and unescaped slash requests |
| `TestSearchTagValuesV2_badRequest` | HTTP rejection of `app.user.id`; Pulse's diagnostic rather than Tempo's parser wording |
| [`TestSearchTraceQL`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/integration/api/search/search_test.go) and [`SearchTraceQLAndAssertTrace{WithRange}`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/integration/util/harness_api_reads.go) | Find the ingested trace with `{ .<original-key> = "<value>" }`, both without bounds and with explicit bounds. Random trace/attribute selection becomes the first batch's fixed `firstRes` and `firstSpan`; this preserves the found-trace assertion/query shape, not the random producer's full input. |
| [`TestTraceByIDandTraceQL`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/integration/api/tracebyid/trace_by_id_test.go#L15-L64), exact-ID selection | All ten actual `NewTraceInfos` traces, including every delayed batch, resource, scope, span, parent, typed attribute, event and status; complete v1/v2 trace equality before/after manifest restart. The original search assertion **does not pass**: multi-root inputs hit Pulse's deliberate whole-response rejection, recorded separately below. |
| [`TestTraceByIDV2Filtering`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/integration/api/tracebyid/trace_by_id_filtering_test.go) | All 31 depth-table combinations, the exact six-span parent graph, two integer predicates, span-ID sets and COMPLETE/PARTIAL expectations; malformed query and active/ignored depth assertions. The oversized-URI response is an explicit adaptation below. |
| [`TestQueryRangeExemplars`, metric and HTTP-validation subtests](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/integration/api/metrics/query_range_test.go#L306-L536) | All three aligned/unaligned/default-step interval rows (3/4/122 samples), all five instant/range aggregate comparisons, the instant-average comparison, all six topk/bottomk rows, both empty-result counts, and HTTP rejection of `0`, `0s` and `35ms` steps. The small-step row retains its original diagnostic substring. Exemplar production/requests and transport permutations are excluded. |
| [`TestQueryRangeTypeHandling` and `TestQueryRangeMaxSeriesDisabled`, metric-cardinality selections](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/integration/api/metrics/query_range_test.go#L636-L725) | Two spans with `foo` string `123` versus integer `123`, and the timed one-span producer, queried with `{} \| rate() by (span:id)`, five-minute bounds and `5s` step. COMPLETE and exact producer-cardinality assertions are retained. Exemplar requests, streaming and the unlimited-series configuration are not selected. |
| [`TestDefaultQueryRangeStep`, public engine table](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/traceql/engine_metrics_test.go#L35-L65) | All fifteen original window/expected-step pairs, retaining start zero and end equal to the window. Assert the expected spacing through HTTP/native-Parquet range samples rather than a private helper; the one-span producer is a separately identified Pulse adaptation. This is an engine-table port, not an additional upstream service-integration test. |

The separate malformed-name, exact-percent, nested `/values`, missing-key, route
suffix, authentication, search-window rejection and full-response public-engine
checks are Pulse regressions, not additional upstream integration cases.

## Replay and adaptations

```sh
mix test test/pulse_web/controllers/tempo_upstream_integration_test.exs
```

The async ExUnit tests send real authenticated OTLP/HTTP JSON/protobuf requests to an
owned Bandit listener, persist native Parquet through Pulse's S3 adapter against
an owned loopback object store, restart manifest supervision, and query JSON and
protobuf responses. Default tests need no Go, Docker, remote services or network
downloads. All data and expectations are checked in. Additional sections below
describe the public engine step rows, arithmetic tables and separately labelled
Pulse controls.

The upstream harness converts Jaeger batches to OTLP/gRPC and queries both live
and flushed backend data. This port expresses the same resource/span attributes
as OTLP/HTTP JSON, fixes random IDs to distinct deterministic values, and uses
relative source times with the same one-microsecond durations. Pulse publishes
Parquet before acknowledgement, so both unbounded and paired ±2-hour windows run
after publication with fresh manifest state, not against a WAL. Source names,
values, span counts and selected filter expressions are unchanged; expected
dictionaries are sorted because upstream sorts before comparison. JSON empty
lists and protobuf default omission are compared through their protocol shapes.
Protobuf expectations use Pulse's existing encoder; this tests content
negotiation/transport consistency, not independent wire conformance (covered by
the separate public protobuf fixtures).

### V2 name content tables and versioned static vocabulary

The six original `TestTagEndpoints` name rows come from the pinned
`integration/api/search/search_tags_test.go`:

- `130–146`: no filtering.
- `191–203`: first batch, resource attribute, span scope.
- `204–216`: first batch, resource attribute, resource scope.
- `217–229`: second batch, resource attribute, span scope.
- `230–243`: too restrictive query, retaining the original service-name hint.
- `278–294`: both batches, name and resource attribute.

All seven original two-span batches (`40–53`) are ingested for every row. The
upstream helper (`362–374`) augments scope-none results with the intrinsic
vocabulary and sorts scopes/names; the port retains that behavior, unbounded
and ±2-hour windows, and complete scope/name equality. JSON/protobuf transport
checks are Pulse coverage. Upstream additionally asserts
`metrics.inspectedBytes > 300` (`591–601`, `678–687`) and gRPC results: those are **not ported**. These
are original HTTP **content-table selections**, not passing complete helper,
deployment, storage-provider or gRPC scenarios.

`intrinsic-names-producer.go.txt` executes the actual pinned
`pkg/search/util.go:GetVirtualIntrinsicValues` (`57–93`), resolving names through
`pkg/traceql/enum_attributes.go` (`174–213`). It produced all 25 names in
`intrinsic-names.json`, independently of Pulse. Run it with Go 1.27.3 from the
verified Tempo module root using `go run -mod=vendor /path/to/copied-producer.go`.
Normal Elixir replay needs neither Go nor the checkout.

Source and fixture SHA-256:

- `search_tags_test.go`: `1dd8f881778c08ede478d2d369aaeed323ae6658175b12d7539985f22ef45e8f`.
- `pkg/search/util.go`: `b88386fb59665c1200e440a37b8613ed8249416b47e33845a9a1705cbcc16bf9`.
- `pkg/traceql/enum_attributes.go`: `7150265d29922a9209821369a9df1d9450eadfcfc66476eae82cf13125c84062`.
- `cases.json`: `144bada60b7d5688753730bac3f36a64dbcc0ef3197607a601992d017d3ffd60`.
- `intrinsic-names.json`: `a614ea99ad33f66a0c1c61fa1591c5f14470b7745730d4c30f1476bcfe24f70e`.
- `intrinsic-names-producer.go.txt`: `0a544e83e268187aad25fd012cfab3dc153640b6435ee0db3a3d7f051950054b`.

Before the fix, the initial three-row selection passed only its explicit-span
case: unfiltered and service-filtered scope-none results lacked five names
(`tempo-name-vocabulary-before.log`, seed51). Adding the capacity regression
also failed: the old reservation yielded 4,995 rather than 5,000 pairs
(`tempo-name-vocabulary-budget-before.log`, seed52). Elixir/native vocabularies
now add `link:spanID`, `link:traceID`, `span:id`, `span:parentID` and `trace:id`.
The final six upstream rows plus two local controls pass seed52
(`tempo-name-vocabulary-final-focused.log`).

The local controls cover authenticated HTTP/MCP static discovery without any
provider request, denied requests, unchanged unsupported ID-value discovery,
and exactly 5,000 versus 5,001 pairs through native/reference paths, filtered
and unfiltered, including v1 before flattening. All 25 names reserve capacity
before stored names; the limit is not raised to accommodate the vocabulary.
Existing v2.9 oracle files and hashes remain unchanged: only their vocabulary
portion is explicitly overlaid with this newer independent list, leaving stored
name expectations and all seven value shortcuts intact. This is not evidence
that ID-value discovery or intrinsic filters are implemented.

Final validation: the full Elixir suite passes **2507 tests**, one optional
skipped and 37 optional excluded (seed0, four concurrent cases); the combined
three-service plus Tempo end-to-end/default-name/intrinsic suites pass **409
tests** (seed41). The first full run exposed two additional old-vocabulary
end-to-end assertions; their vocabulary alone now uses the same independent
newer list. All **133 native codec tests**, compile with warnings as errors,
strict Credo, scoped Elixir/Rust formatting and whitespace checks pass. Logs:
`tempo-name-vocabulary-full-suite-final.log`,
`tempo-name-vocabulary-combined-final.log`, `tempo-name-vocabulary-native.log`
and `tempo-name-vocabulary-credo-final.log` under `.amp/in/artifacts/`.

### Special-character test deadlines

The original Go test uses separate `t.Run` cases for each key, scope and
WAL/backend phase. The Elixir port retains all 19 enabled pairs together in each
fixture but separates resource/span scopes and retained/explicit windows into
four independently owned tests. Each ingests all 19 batches and restarts
manifest supervision before querying. JSON and protobuf assertions, the full
expected responses and the separate encoded/raw-slash test are unchanged.
There are still 152 retrievals, now 38 per test instead of 152 sharing one
60-second deadline. This adds three fixture setups; it is not a query-speed
improvement or a production timeout change.

Run this subset with `mix test test/pulse_web/controllers/tempo_upstream_integration_test.exs --only special_characters`.
An instrumented replay of the formerly failing seed617 passed all four tests
in 1.8–5.3 seconds each with `timeout=60000` and `trace=false`. That confirms
the ordinary deadline was retained, not relaxed by tracing/slow-test options.
It does not prove the cause of every historical timeout or provider capacity.

## Failures reproduced and fixed

- Bare v1 `service.name` returned 400. V1 now accepts bare original keys as
  unscoped targets; existing canonical scoped/intrinsic extensions retain
  precedence. This is not every legacy-v1 alias/collision behavior.
- Quoted attribute identifiers, such as `span."attr space"`, returned empty
  dictionaries instead of the original value. The HTTP boundary now decodes
  JSON-compatible double-quoted identifiers before applying the existing key
  and query budgets. Invalid quotes/escapes reject, not an empty success.
- An unescaped slash in a key returned 404 even though an encoded slash worked.
  The router now captures the full target path, removing only the terminal
  `/values`. URL decoding remains exactly once, preserving literal `%20` keys.

The first executable baseline was 2 passing / 4 failing tests before runtime
changes. The search continuation initially had 6 passing / 2 failing HTTP tests:
both the unscoped lookup and omitted time bounds returned 400. A separate public
unscoped-engine replay failed at the parser with `unsupported_trace_selector`.
Unscoped predicates now preserve span-key precedence, not resource/span OR;
HTTP omitted bounds and paired zeros scan all bounded retained context. Pulse
has no ingester-only tier, unlike upstream default request routing. Partial or
mixed-zero bounds deliberately still reject. The search grammar extension
requires search capability **5**, current tuple `{2,1,3,5,12}`, on every serving
app/native artifact. Segment format, keyed bytes and feature gates are unchanged.

## Independent unscoped search oracle

`produce_search.go.txt` executed inside the actual public **Tempo v2.9.0**
`tempodb/encoding/vparquet4` package, using its real Parquet block builder,
fetcher and `traceql.NewEngine().ExecuteSearch`. Source archive SHA-256:
`5b652be7d03b3329a5b986fd8678ea4a9c4849adf2966baf19d20eec01046a44`.
Its `batch`/`value` helpers come from the existing
[`produce_tempo_search.go.txt`](../produce_tempo_search.go.txt).

The separate synthetic six-trace/six-span input exercises resource-only,
span-only, differing same-key strings, a wrong-typed overriding span value,
identical same-key strings and missing attributes. Eight expressions run with
both explicit and paired-zero bounds, producing **16 full responses**. They
establish equality, regex, negative predicates, original int64, AND/OR, span
precedence and independent sampling of both requested owners. These are public
engine controls, not transplanted upstream integration-table rows. Provider
metrics are omitted; sample attributes are sorted by key, without dropping
same-key duplicates. These scenarios do not establish every physical-layout,
dedicated-column or complex-value behavior.

`search_expression_test.exs` pins all checksums and compares the full responses
with native execution, the independent Elixir evaluator, bounded old-adapter
fallback and positive-window MCP queries. The HTTP suite separately ingests the
frozen protobuf through the real endpoint/S3 path, restarts manifest supervision
and checks all 16 responses. Ordinary replay requires no Go or downloads.

| File | SHA-256 |
| --- | --- |
| `search-input.protobuf` | `dec8004d8460e2f487c50af8093acb71e2eebfcbad84a93b921ebe269d184ea0` |
| `search-oracle.json` | `3b655f0433d4a93634098e89286a9c5c6db55e8ae8a6bda10e1ceb7d5d98c602` |
| `produce_search.go.txt` | `59e93879c6ff66167bef4470d36164da0c1bc17335a84af83d0dbf39ee6b79d3` |

Optional regeneration: copy the helper and producer into the pinned public
package, then run with Go 1.25.10 and vendored dependencies:

```sh
PULSE_ORACLE_DIR=/tmp/pulse-unscoped-oracle GOMAXPROCS=2 \
  go test -mod=vendor -p 2 ./tempodb/encoding/vparquet4 \
  -run '^TestPulseUnscoped$' -count=1 -timeout=180s -v
```

This actual public-engine producer run was executed; the latest upstream
multi-service/Docker integration suite was inspected, not executed.

## V2 exact-ID filtering continuation

`filter-cases.json` transcribes all 31 rows from the pinned trace-by-ID table.
Input span IDs/parents, status-code attributes and expected retained ID sets are
unchanged; source times are relative, as in the other HTTP fixtures. Two added
upstream-derived wrappers cover the table and invalid/ignored depth parameters.
The baseline had **9/11 passing tests**: filtering returned unsupported-parameter
400, and the oversized-filter assertion returned 414 instead of upstream's 400.
No upstream Go cluster suite was executed to generate these expectations.

Filtering now runs after the existing complete validated/deduplicated assembly,
under the same query admission, scan, heap, deadline and result bounds. It uses
the bounded same-span expression evaluator, not general TraceQL. Independently
bounded ancestor and descendant walks start only at matches. No-match results
are empty PARTIAL traces; a whole-trace selection is COMPLETE. JSON/protobuf
checks cover all 31 rows; field numbers 3/4 and PARTIAL enum value 1 are also
checked independently of Pulse's encoder against `pkg/tempopb/tempo.proto`.
Filtered conversion expands bounded rows on BEAM; native unfiltered export is
unchanged. There is no additional GET, storage/keyed-byte or native-ABI change.

The oversized 150 KiB query deliberately expects **HTTP 414** at the default
HTTP URI ceiling, not upstream's 400. A separate parser check rejects that same
input. This is rejection parity, **not exact status-code parity**; the HTTP
ceiling was not relaxed. The two upstream recent/backend repetitions become one
durable S3 path, not simulated live-store coverage.

Additional Pulse filtering controls cover typed strings/regex/int64,
duration/status and boolean groups; no matches/blank filters; unchanged full
reads; V1/auth rejection; expression/depth/scan ceilings; cycle termination,
missing parents, maximum int64 depth and independently seeded graph walks; and
nonmatching legacy/conflicting spans failing the whole lookup. Two HTTP/native-S3
regressions additionally prove that malformed stored link IDs or event timestamps
fail with 500 before either a nonempty or empty selection, in JSON and protobuf.
Both failed with 200 before the fix. Export tests cover malformed owner/core/
event/link fields, exact ID widths/nonzero IDs, valid numeric boundaries and the
5,000-span limit. Validation-only checks cover every stored span before filtering;
only selected spans allocate export maps and encoded timestamps/IDs, without a
discarded conversion pass or second full-trace binary. Protobuf spans become
encoded binaries individually, avoiding retention of every span's whole nested
iodata tree without separately copying each small attribute/event. A bounded
5,000-rich-span check compares the public filtered export with exact native
protobuf under the default 16-million-word query heap.
These controls are not counted as upstream cases.

| File | SHA-256 |
| --- | --- |
| Upstream `integration/api/tracebyid/trace_by_id_filtering_test.go` | `5e3a1700e9bc3d580316651ed5ccc95b52e3f59ba6bfcf07ea6df874e86c0b56` |
| `filter-cases.json` | `f7dc3635a0b5b9e676fe02b21e9543eb728c519c24c9c3acf0e25fe72507a550` |

## Metric table continuation

The fifteen metric-only subtests preserve the upstream queries, range lengths,
steps, reductions, interval counts and ranking cardinalities. They passed on the
unchanged runtime (seed 67), alongside the existing seventeen wrappers and a
separately identified ranking control: **33 passed**. This is additional regression
coverage, not evidence of a newly fixed metric implementation bug.

The source's timed producer becomes exactly twenty half-second ticks, with its
three one-span batches per tick. Names, attribute keys, fixed values and
one-microsecond durations are unchanged; UUIDs and trace/span IDs become distinct
deterministic strings. The query clock is fixed to a recent minute boundary,
with source starts from clock minus 13 seconds to minus 3.5 seconds. This keeps
the complete input inside the source's aligned windows without sleeps, timers or
wall-clock-dependent empty results. Unaligned ends use exactly half a second
past that boundary. Input reaches the real OTLP/HTTP and durable Parquet/S3 path,
then manifest supervision restarts before querying. There is no simulated
ingester/backend double read or gRPC-streaming coverage.

The upstream helper normally also sends an unasserted exemplar-count request
parameter; the metric-only selection omits it. **This is not a port of exemplar
behavior**, `compare()`, arithmetic between metric expressions, or every subtest
in `TestQueryRangeExemplars`. Metric JSON content is checked over HTTP, not
protobuf or the source helper's second gRPC transport. In addition to the
upstream aggregate consistency assertions, independent expectations use the exact
sixty input spans and their durations, so mutually incorrect range/instant
responses cannot agree their way through the tests.

Two separately named Pulse controls exercise unequal series counts 1/3/5 through
both ranking directions, both attribute scopes and both metric endpoints; and
unequal counts/durations across three intervals. The latter checks exact
timestamps and span-weighted instant averages rather than an average of interval
averages. These are not additional upstream cases. No runtime, native ABI,
storage format, keyed bytes, budgets or upgrade requirements change for this
Tempo coverage increment.

| Upstream source | SHA-256 |
| --- | --- |
| `integration/api/metrics/query_range_test.go` | `7749294d4d682939a602e656cac41728f2b9c63344e913999d5c7d58170078f2` |
| `integration/util/harness_api_writes.go` | `53ea99c9dad9c6e2645e4004aeb587fe6d8bf6235ae7aab3bbb191e5124d66d3` |

## Span-ID metric grouping continuation

The two new source selections failed before runtime edits: the full HTTP replay
had **34/37 passing wrappers** (seed 71), with both upstream-derived requests
and the new Pulse control returning HTTP 400 for `by (span:id)`. No source
assertion was weakened. The numeric/string `foo` values, default helper's `x=y`,
`xx=""`, service/name, one-microsecond duration, five-minute query geometry,
five-second step and source cardinality assertions are preserved. Random IDs
become distinct fixed IDs. The five-second/half-second producer freezes to ten
ticks with starts from query time minus 7.5 to minus 3 seconds. This preserves
the one-span-per-tick helper and counts actual input, without sleeps or races
between upstream's final timer/ticker events. Both cases use persisted S3 after
manifest-supervision restart, not separate recent/backend phases.

The selection is explicitly **metric-cardinality only**: the unasserted
`exemplars=100` parameter and gRPC-streaming repetition are omitted. Pulse does
not reproduce the `max_series=0` override or unlimited-series semantics; its
10,000-series hard ceiling remains. A separate public query test checks exactly
10,000 distinct IDs succeeding and 10,001 failing whole with `trace_group_limit`,
while an ungrouped count still sees all 10,001. A local-fixture iteration first
caught out-of-window and uppercase core-ID mistakes in that boundary test; only
the fixture changed, not validation or limits.

Grouping now reads the already validated core span ID without attribute-owner
expansion and emits the canonical `span:id` label with a 16-character lowercase
hex string. The pinned public implementation confirms the protocol spelling in
[`enum_attributes.go`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/traceql/enum_attributes.go#L210-L211),
string typing in
[`block_traceql.go`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/tempodb/encoding/vparquet4/block_traceql.go#L3199),
and fixed-width formatting in
[`SpanIDToHexString`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/util/traceid.go#L54-L65).
No upstream runtime code is copied. The parser admits this intrinsic only for
grouping, and native compilation independently rejects it as a numeric value.

Additional controls distinguish intrinsic IDs from ordinary `span.id` and
`resource.id`, preserve typed string/int64 `foo` groupings, combine reused span
IDs across distinct traces, retain leading zeros and high unsigned bits, and
normalize uppercase ingress to lowercase output. Both instant and range metric
endpoints run these checks. Bare `id`, `trace:id` and numeric ID aggregations
still reject. Legacy core-only grouping remains supported without inventing
unknown original attributes. These controls are not additional upstream ports.

Trace metrics capability **2** is independently required at startup alongside
the unchanged trace tuple `{2,1,3,5,12}`. Upgrade all serving app/native pairs
before depending on the syntax. No encoder, storage format, keyed bytes,
migration or retry-drain requirement changes. Five grouping keys, series/point/
byte ceilings and shared query/scan budgets remain unchanged. These offline
ports do not establish full typed metrics, deployed clients or capacity parity.

Final cross-protocol replay passed **149 tests** (seed 76), including all 37
Tempo HTTP wrappers and the trace metrics unit/HTTP suites. Whole-repository
`mix precommit` passed **1807 tests**, with one existing optional promtool skip
and 37 optional exclusions (seed 75). Codec release tests passed all 133 cases;
strict Credo, release Clippy, formatters and whitespace checks passed. Direct
native validation also rejected numeric ID operations and six grouping keys.

| Additional inspected source | SHA-256 |
| --- | --- |
| `pkg/traceql/enum_attributes.go` | `7150265d29922a9209821369a9df1d9450eadfcfc66476eae82cf13125c84062` |
| `pkg/util/traceid.go` | `1158046cd8942d42e052c10c7562c40a593ff660623ad705e56f17cc1bf19787` |
| `tempodb/encoding/vparquet4/block_traceql.go` | `87d66734e1e26a66fa467f461d217cff84bf92ab31af19f21ec1013e0d5729a4` |

## Empty selections and interval validation continuation

Five more rows from the pinned `TestQueryRangeExemplars` are ported: both
empty-result count queries (`{status=error}` and the absent `span.randomattr`),
and HTTP steps `0`, `0s` and `35ms`. The same frozen sixty-span fixture remains
non-error and lacks that attribute. Bounds retain the helper's five minutes
before / one minute after the anchor, with its `5s` step for empty selections.
Both empty cases preserve the at-least-one-series and zero-exemplar assertions.
The unsupported exemplar-count request and gRPC transport remain excluded;
zero exemplars here do not prove exemplar production or selection support.

Both empty-result assertions failed before the native fix (seed 78), returning
`series: []`; the initial baseline used the receiver-default step, later made
explicit as the upstream helper's `5s`. A public-query control also failed because
it expected exact zero samples. Ungrouped count/rate finalization now returns its
zero identity only after a successful scan. It does not invent labels for grouped
queries or numeric/histogram/quantile observations. Separate public-query
controls check every aligned timestamp/value for nonmatching selectors, empty
tenants and out-of-window spans, plus instant zeros and unchanged empty
grouped/numeric results. Legacy/corrupt inputs and exhausted budgets still fail,
not zeros.

The three HTTP validation rows initially passed **2/3** (seed 80): `35ms` over
six minutes wrongly returned HTTP 200. Admission now checks the original range's
integer interval quotient against the pinned default **10,000**, before boundary
alignment. The native aligned-window ceiling remains 11,000, not an operator
override. A public-query boundary control accepts exactly 10,000 requested
intervals and a sub-step remainder (10,001/10,002 aligned output samples), rejects
10,001 requested intervals, and leaves instant requests at one interval.
At this initial stage, the small-step port asserted only HTTP 400, adapting
away upstream's diagnostic assertion. The diagnostic continuation below removes
that adaptation. Zero-step source cases only assert rejection. No source safety
ceiling is raised.

Runtime changes are independently written, not copied upstream implementations.
Upgrade all serving app/native pairs for consistent query semantics; no storage,
keyed bytes, native ABI or migration changes are introduced by this increment.
The earlier span-ID capability remains **2**. Pinned runtime inspection confirms
the ungrouped placeholder series and pre-alignment interval validation:

| Additional inspected source | SHA-256 |
| --- | --- |
| [`pkg/traceql/engine_metrics.go`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/traceql/engine_metrics.go#L768-L774) (`UngroupedAggregator.Series` at lines 994–1005) | `cd05466f788a7a0705578fd79aa47d38a1408ca9609cdbd9b9e6fa8493058e01` |
| [`modules/frontend/metrics_query_validation.go`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/modules/frontend/metrics_query_validation.go#L16-L34) | `dde4a210f65c885d59844b089a04e61cbb43e89eca0955acda6aaaca303966ad` |
| [`modules/frontend/config.go`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/modules/frontend/config.go#L152) | `5fa9a3e016101b5f3ed6e79a26f9eb91a3373f19131a194b9f1ffb4fd9b0a10c` |

The final three-service plus trace metrics unit/HTTP replay passed **157 tests**
(seed 83), including all **42 Tempo wrappers**. `mix precommit` passed **1815**
with one existing optional promtool skip and 37 optional exclusions (seed 82).
Codec release tests passed all **133** cases; strict Credo, release Clippy,
formatters and whitespace checks passed. These remain offline HTTP/native-S3
regressions, not a run of upstream Tempo or deployed-client acceptance.

## Small metric-step diagnostic continuation

The pinned `integration/api/metrics/query_range_test.go:323–332` small-step row
now preserves its original `ErrorContains` oracle:
`step of 35ms is too small, minimum step for given range is 36ms`. The original
six-minute bounds, `35ms` step and count query remain unchanged. The strengthened
HTTP replay failed before runtime edits (seed 732, two zero-step rows passed):
Pulse returned `invalid or unsupported trace lookup parameters` instead.

Requested-range overflow now carries the requested step and integer-divided
minimum to the HTTP boundary, which uses the existing Go duration formatter.
The pinned validator uses floor division by 10,000, not a ceiling or aligned
range. The requested 10,000 and native aligned 11,000 interval ceilings are
unchanged. Other invalid parameters keep their existing diagnostic; instant
queries still ignore supplied steps. Upgrade query-serving applications for
consistent diagnostics; no native ABI, storage/keyed-byte or migration change.

Separately named Pulse controls cover nanosecond/microsecond/fractional-second/
minute rendering, decimal-seconds step normalization, the floor-division edge,
exactly 10,000 requested intervals with a sub-step remainder, and rejection of
10,001 intervals. Nanosecond HTTP bounds express the sub-millisecond remainder
without changing the existing decimal timestamp parser. Rejected authenticated,
zero/malformed and unauthorized requests produce no object-store requests.
Public evaluator controls retain instant behavior and aligned int64 overflow
rejection. These are local controls, not additional upstream integration rows.

Run the five focused HTTP wrappers with:

```sh
mix test test/pulse_web/controllers/tempo_upstream_integration_test.exs --only metric_step_validation
mix test test/pulse/traces/metrics_test.exs
```

Final focused validation passed all five HTTP wrappers and all eighteen public
metrics evaluator tests (seed 735, two concurrent cases). The combined complete
Tempo replay/evaluator run passed 96/97 (seed 734); the existing unrelated
`Go repetition classes and raw headers agree in retained trace predicates`
wrapper exceeded its unchanged 60-second deadline. The focused HTTP command
selects only the five step-validation wrappers; the combined failure remains
unresolved. Compile with warnings as errors, scoped formatting and whitespace
checks passed.

The complete source hashes remain those recorded above:
`query_range_test.go` SHA-256
`7749294d4d682939a602e656cac41728f2b9c63344e913999d5c7d58170078f2`,
and `metrics_query_validation.go` SHA-256
`dde4a210f65c885d59844b089a04e61cbb43e89eca0955acda6aaaca303966ad`.
The checkout revision and hashes were verified again; no Tempo runtime code was
copied and the upstream multi-service suite was not executed. This is offline
authenticated HTTP/native-Parquet/S3 replay, not deployed-client/provider proof.

## Default metric-step continuation

All fifteen `TestDefaultQueryRangeStep` rows preserve the public source's
start-zero/window-end geometry and expected duration exactly: 59 seconds through
30 days. Expected steps are transcribed into milliseconds for the public JSON
timestamps, not computed by Pulse. Each case ingests one rich span at one second
using the existing fixture helper, restarts manifest supervision and queries
`{} | count_over_time()` without `step`. It checks the first sample timestamp,
every adjacent sample spacing and total count one. The original unit test has
no producer; this persisted span and HTTP transport are explicit adaptations,
not copied upstream input or an execution of Tempo itself.

The unchanged-runtime baseline failed **7/15 upstream rows** (seed 105): 59s,
6h, 24h minus 1s, 24h, 2d, 7d and 14d. The minimum-step Pulse control also
failed; the explicit-step control already passed. The independently written
default policy now rounds the window/240 baseline at 50 ms below one minute,
or at the largest applicable hour/5m/1m/15s/5s/1s granularity otherwise, with a
one-second minimum in that second branch. No Tempo runtime code is copied.

Two local controls cover a one-nanosecond window, the 50 ms floor, subminute
rounding, both sides of the minute boundary and a shifted nanosecond epoch;
explicit `700ms` spacing, instant ignored-step/count behavior, and unchanged
HTTP rejection above 10,000 requested intervals. These are not additional
upstream rows. The complete Tempo service plus metrics unit/HTTP suites passed
**74 tests**, seed 106, including all **59 HTTP wrappers**.

The broader Loki HTTP/WebSocket/module/LogQL, Mimir service and Tempo replay
passed **510 tests**, seed 107; the separate batch suite passed **9**, seed 108.
All seventeen additions passed eleven consecutive runs (**187 executions**,
fixed seed 109). Compile with warnings as errors, strict Credo across 437 source
files, scoped formatting and whitespace checks passed. No native source changed;
native unit tests were not separately rerun for this application-only policy.

Upgrade every query-serving application for consistent omitted-step results.
Trace metrics capability **2**, storage formats, keyed bytes and all existing
query/result bounds remain unchanged; no native ABI change, migration or retry
drain is introduced. These offline checks do not establish metrics exemplars,
expression arithmetic, streaming, deployed clients or provider/capacity parity.

| Additional pinned source | SHA-256 |
| --- | --- |
| `pkg/traceql/engine_metrics_test.go` | `6568615e285b21b5094c218444d1a93aa8996d2fda82b5eb65d44f9e1637fe49` |
| Selected lines 35–65 (`TestDefaultQueryRangeStep`) | `b4c1bf93cbfc446f35d2a87c9f4e227524adb9bd7227fd226533f3490b1c19bf` |
| Inspected `pkg/traceql/engine_metrics.go` (policy at lines 37–81) | `cd05466f788a7a0705578fd79aa47d38a1408ca9609cdbd9b9e6fa8493058e01` |

## Metric arithmetic and scalar-filter continuation

`metrics-math.json` freezes the complete selected test tables at the same
revision. `Pulse.Traces.MetricExpressionConformanceTest` replays all rows;
`PulseWeb.TempoUpstreamIntegrationTest` additionally sends all 87 scalar queries
through authenticated HTTP and native Parquet against isolated loopback S3.
Ordinary ExUnit replay needs neither Go nor a downloaded source tree.

| Source | Selection | Replay |
| --- | --- | --- |
| `pkg/traceql/engine_metrics_test.go:1044–1707`, `TestScalarMath` | All 87 cases, original 11 spans and exact nanosecond durations; all 522 dense expected values | Memory/native and HTTP/Parquet; NaN slots omitted at response serialization; float/int constant division, precedence, operand order, filters and infinity retained |
| `tempodb/tempodb_metrics_test.go:1289–2644`, every `math_` row | All 23 cases, 100 original single-span traces, complete L1/L2/L3 expectations | Native batch/final evaluator, asserting L3 samples and labels; not a literal HTTP port |
| `pkg/traceql/parse_test.go:1966–2179`, `TestMetricsMathExpression{Errors}` | All 18 positive and 6 negative rows | Public metrics parser acceptance/rejection; stored expected Go ASTs are provenance, not asserted Elixir AST shapes |

The storage tests retain start **1 ns**, end **50 s**, step **15 s** and spans
51–100. The final bucket timestamp of **60 s** does not change the scan end.
Two identical input sets simulate the original engine's two additive L1
observations, preserving doubled counts/rates and unchanged maxima before
arithmetic. HTTP aligns the end to 60 s and would admit additional spans, so
these 23 storage oracles intentionally bypass HTTP window alignment. L1/L2
arrays are preserved for provenance; replay asserts the original final L3.
Random IDs become deterministic while the original fixed trace-30 ID remains.
Incidental producer fields unused by these queries are omitted.

The AGPL-licensed `metrics-math-producer.go.txt` reproduces the complete JSON
using only Go's standard library. It executes the original scalar **test-table
transform closures**, and evaluates original storage expected-value expressions
with data-only stand-ins. This is not execution of Tempo's engine. Independent
source-AST checks verified all scalar values (including signed zero/nonfinite
classes), 376 storage samples across all phases, 163 selected-range hashes and
the three complete source-file hashes. Both generated files retain attribution;
no Tempo runtime implementation is copied.

| Artifact or complete source | SHA-256 |
| --- | --- |
| `metrics-math.json` | `eab201ee0dacf639ef7649d548d43ff16fa40c7b5c75bfee60fa85363dc72980` |
| `metrics-math-producer.go.txt` | `caeb6d16c5f8d9ba4c4d0c58125de868452fbecce9ade732ba117e51692df6bc` |
| `pkg/traceql/engine_metrics_test.go` | `6568615e285b21b5094c218444d1a93aa8996d2fda82b5eb65d44f9e1637fe49` |
| `tempodb/tempodb_metrics_test.go` | `e4315a0ebb5d7ef3fc03097718c8bca7a8a826a4436964b85e4ca77397bf8f1f` |
| `pkg/traceql/parse_test.go` | `3eef0b3f465ed516623b34568ddd11023739d27612df74c2e26b75916f8dd1af` |

Pulse controls cover instant span-weighted arithmetic, two branches sharing
exactly one GET per Parquet object, fail-whole HTTP scan quotas, shared native
series ceilings (5000 groups across two leaves succeed, 5001 fail), typed label
identity/order/missing groups and invalid-query rejection before storage.
Integer literal/folding overflow deliberately rejects rather than using Go's
machine-int wraparound. JSON infinities use Pulse's established string encoding,
not a claim about Tempo's HTTP nonfinite encoding. Native trace metrics
capability **3** is required; trace storage/search tuples and keyed bytes do not
change. Exemplars, full TraceQL, streaming, provider capacity and deployed-client
acceptance remain separate gaps.

## Shared regex literal controls

The local `:regex_literals_batch` wrapper replays eight quote/octal patterns
over eight OTLP-ingested one-span traces through native Parquet/S3, after
restarting local manifest authority. Independent whole-label answers come from
[`regex/go-controls.json`](../../regex/go-controls.json), not Pulse or inferred
Tempo results. Both resource/span retained search and JSON/protobuf filtered
discovery run through HTTP; authenticated HTTP MCP exercises window-local
`search_traces` and both resource/span raw `query_traces` regex filters.
Unfinished literal quotes remain fully anchored. Shared fixture provenance
preserves the complete Go parser-table patterns and independently executed
matching answers. These local controls use the Tempo integration harness, but
are not additional upstream integration rows or full client/provider/capacity
acceptance. Existing trace tuples, storage/keyed bytes and resource ceilings
are unchanged; upgrade every query-serving app/native pair for these forms.

The local `:regex_admission_batch` replays all 53 shared Go admission patterns
over eight OTLP-ingested traces through resource/span retained search and
native Parquet/S3. Independent whole-label expectations distinguish counted
repetition bounds from literal braces; invalid patterns reject before storage.
[`regex/README.md`](../../regex/README.md) preserves the eight original Go
parser-table patterns, local controls, source hashes and matching provenance.
These are not additional Tempo integration rows or a full regex parity claim.

The same wrapper also replays 32 local literal-class cases from
[`regex/class-controls.json`](../../regex/class-controls.json), preserving
`&&`/`~~` members with negation, folding, POSIX classes and adjacent ranges.
All three protocol wrappers reject valid classes before implementation
(seed 669); the affected 370-test suites pass seed 670. Trace tuples and all
resource ceilings stay unchanged; complete class grammar remains open.

The same wrapper also replays 72 local literal-bracket/hyphen-range cases from
[`regex/range-controls.json`](../../regex/range-controls.json). Independent Go
answers preserve scalar ranges, literal `[`/POSIX-token boundaries and
whole-value anchoring, with no storage requests for invalid ranges, escapes,
groups, flags or counts. All three HTTP wrappers rejected valid `[[]` before
this fix (seed 673). These are local controls, not extra upstream integration
rows or full regex/client/capacity acceptance; trace tuples and limits are unchanged.

The same wrapper replays 44 raw-header and 58 inline-flag cases from
[`regex/name-controls.json`](../../regex/name-controls.json) and
[`regex/flag-controls.json`](../../regex/flag-controls.json), for both resource
and span predicates. Invalid headers reject before storage; empty/repeated
flags preserve whole-value matching and scope. The shared matcher also checks
actual Go anchored capture maps and `U`/lazy greediness. All three wrappers
failed the respective baselines (seeds 680/682). These are independent Go
controls, not extra Tempo integration exports; see the [regex provenance](../../regex/README.md).

## Ten-trace exact-ID continuation and explicit search incompatibility

`trace-by-id-producer.go.txt` was executed against the **actual pinned Tempo
checkout and its vendored Jaeger translator**, using Go 1.27.3. It invokes
`NewTraceInfos(time.Unix(1793404800, 0), 10, "")`, `EmitAllBatches` and
`ConstructTraceFromEpoch` without copying or simplifying their implementation.
The collector uses the same `ThriftToTraces` conversion as the upstream harness
exporter. It checks the separately executed write and reconstruction paths with
protobuf equality before emitting the fixture. Two regeneration runs produced
byte-identical output. No Pulse code runs in this producer.

`trace-by-id.json` freezes the complete OTLP protobuf inputs (base64) and
independent expected JSON traces: **10 traces, 89 resource/scope batches, 266
spans, 802 events and 3045 integer AnyValues**, alongside the original random
strings/blobs, status codes and parent chains. All **89 parentless spans** remain
intact. The fixed clock controls random seeds only; the original producer's
nanosecond seed increments, microsecond source precision, random batch counts
and delayed writes remain. There are no synthetic parent links or one-span
substitutions. Empty/default messages and every typed owner are retained.

The exact-ID wrapper compares complete v1 and v2 JSON traces, sorting collection
order as upstream `AssertEqualTrace` does without removing duplicates or sorting
AnyValue arrays. The v1 `batches` wrapper is mapped to `resourceSpans`; field
content is unchanged. All ten traces are stored together through authenticated
OTLP/HTTP protobuf and native Parquet/S3. Each endpoint is checked before and
after manifest-supervision restart (**40 exact-ID content comparisons**).
Another **40 protobuf HTTP responses** are compared with the existing independent
Elixir encoder over the already independently checked JSON. The upstream client
uses protobuf for exact-ID reads; this cross-format check is not independent
wire-decoder or byte-layout conformance.

The original range-search helper picks one random non-integer original
attribute. The producer freezes two eligible original strings per trace,
`vulture-process-0` and `vulture-0`, covering both resource/span branches. Queries
retain `{ .<key> = "<value>"}` and the original ±one-hour bounds. **The upstream
found-trace assertion failed on unchanged Pulse**, seed 701: exact-ID passed,
but the first search returned `409 trace_root_conflict` instead of 200. All ten
inputs contain multiple independent roots with differing names. This is not
corruption and is not a passing upstream search port.

Pulse already deliberately rejects conflicting matched root summaries rather
than choosing or hiding a root: see `docs/traces.md` (retained-context search),
`TempoSearch.selected/2`, native `tempo_search.rs::selected` and the existing
native/reference ambiguity regression in `tempo_search_test.exs`. Changing
that policy simply to pass this source scenario would undo a documented design
decision. No runtime change is made. A **separately named Pulse incompatibility
regression**, not an upstream success case, checks all **40** searches returning
the explicit whole-response rejection across both phases. Original data,
queries and source expectations remain documented; search compatibility is
blocked on an explicit root-summary policy decision, not silently claimed.

The restart phases test fresh local manifest authority over already published
objects, not upstream recent-data/backend routing. This is one loopback S3
configuration, not the original S3/Azure/GCS permutations. Jaeger ingestion,
gRPC streaming, collector/deployed clients, WAL/Kafka orchestration and provider
capacity remain untested. No native capability, storage/keyed bytes, budget,
upgrade procedure or runtime behavior changes in this continuation.

Run the new selection with:

```sh
mix test test/pulse_web/controllers/tempo_upstream_integration_test.exs --only trace_by_id_upstream
```

Optional regeneration (from the pinned checkout, not required for replay):

```sh
cp /path/to/trace-by-id-producer.go.txt /tmp/trace-by-id-producer.go
GOMAXPROCS=4 go run -mod=vendor /tmp/trace-by-id-producer.go > /tmp/trace-by-id.json
```

| Complete source or generated artifact | SHA-256 |
| --- | --- |
| `integration/api/tracebyid/trace_by_id_test.go` (selected lines 15–64) | `4c95c1216c538dfd56fcf9e8d1a8bbfe552d72f1e20e2e2cd07278101e4e043b` |
| `integration/util/harness_api_reads.go` (selected helpers 76–87, 136–159) | `41ac12605ba3b3b5d8ab0150e02213979cca2b09a42378e87dd7a05ea6eecd6d` |
| `integration/util/harness_api_writes.go` (85–96, 206–212) | `53ea99c9dad9c6e2645e4004aeb587fe6d8bf6235ae7aab3bbb191e5124d66d3` |
| `pkg/util/trace_info.go` | `d6a575ff8e3af47d9de976902ab8841d57197f255e17415e01dabfa8fafd14af` |
| `pkg/model/trace/sort.go` | `472e499fe2013e94b4be2fe1b28d8f3367653b1db18b81d095dc82ac4d8807cc` |
| `pkg/httpclient/client.go` (transport 120–144, query methods 270–292, 346–354) | `88ae684df15357ac2ac3cf678a25f40c267c7a8483694dcf2a862f8b0106bdd4` |
| `vendor/github.com/open-telemetry/opentelemetry-collector-contrib/pkg/translator/jaeger/jaegerthrift_to_traces.go` | `0c6cf9b49e452848bee0f652c13083ab9ade950d032360b4698aa525dde4e5b5` |
| `trace-by-id.json` | `e4c37ec95b0bd97bbd00e01876b14422c55ee669799a1e3a791c05cad93cef43` |
| `trace-by-id-producer.go.txt` | `2413583749bdbd525a92976647d6a283151ed2d138fa7a5c365c5d3ad506c5ea` |

## Homogeneous-string bottom-k tie continuation

The complete active `TestTiesInBottomK / all values tied` subtest at
[`pkg/traceql/engine_metrics_test.go:3700–3714`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/traceql/engine_metrics_test.go#L3700-L3714)
supplies three string-labelled series `x`, `y`, `z`, each with values
`[5, 5, 5]`, and selects `k=2` over all three intervals. Its unchanged oracle
keeps `y` and `z` with every value intact and excludes `x`. The original helper
uses label name `label`. The pinned runtime's reversed lexical key comparison
and bottom-k replacement agree with that explicit test, despite an adjacent
helper comment saying "earlier": see
[`series_heap.go:13–56`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/traceql/series_heap.go#L13-L56)
and
[`engine_metrics.go:2507–2558`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/traceql/engine_metrics.go#L2507-L2558).
The complete engine-test source hash remains the one recorded above.

The public adaptation ingests nine one-span OTLP/HTTP batches, with the original
three strings in `span.label` and integer `span.v=5` at three successive source
seconds. `{} | max_over_time(span.v) by (span.label) | bottomk(2)` constructs the
original arrays through authenticated HTTP and native Parquet/S3, after manifest
supervision restarts. Relative recent timestamps replace the engine table's
position-only arrays; no input span producer exists in that original subtest.
The HTTP assertion compares the complete response, including both labels and
every sample timestamp/value, so a cardinality-only result cannot pass.

Two bottom-k wrappers exercise ordinary finalization and the existing arithmetic
leaf path through `(query) + 0`. Two separately named Pulse top-k controls keep
`x` and `y` over the identical inputs and paths. The arithmetic wrapping and
top-k controls are not additional original bottom-k cases. Before the runtime
change, both bottom-k wrappers failed with `x,y` instead of `y,z`; both top-k
controls passed (seed 741, `tempo-bottomk-ties-red.log` under
`.amp/in/artifacts/`). The independently written native comparator now reverses
the tie direction for bottom-k only; top-k's direction and unequal-value ordering
are unchanged. This verifies homogeneous string-group ties, not full mixed-type
or multi-label comparator parity, signed-zero ordering or general ranking parity.

Trace metrics capability **4** is required by both the native artifact and the
application loader, preventing a new application from accepting capability-3
artifacts with the old tie direction. Upgrade every query-serving app/native
pair together. Trace tuple `{2,1,3,5,12}`, storage formats, keyed bytes, scan/work/
series/point/output ceilings and request admission are unchanged. No migration,
retry drain, new API or cluster state is introduced. This is local public
HTTP/native-Parquet/S3 proof, not execution of Tempo's Go test or deployed-client,
cloud-provider or capacity acceptance.

```sh
ERL_FLAGS='+S 2:2 +SDcpu 1' mix test test/pulse_web/controllers/tempo_upstream_integration_test.exs \
  --only metric_ranking_ties --max-cases 1 --seed 741
```

Final focused validation passed all four new HTTP wrappers (seed 741), the five
unchanged step-diagnostic wrappers (seed 742), twenty trace-metrics unit/HTTP
tests (seed 743), and all seven existing public ranking wrappers/controls
(seed 744). Every Elixir run used two schedulers and one concurrent case, with
warnings as errors on the green runs. All six native trace-metrics tests pass
in release mode with one test thread, and codec-only release Clippy passes for
library/test targets with warnings denied. Scoped Elixir/Rust formatting and
whitespace checks pass. Logs are `tempo-bottomk-ties-{green,step-controls,
metric-controls,ranking-controls,native-tests,clippy}.log` under
`.amp/in/artifacts/`. No full Elixir suite, unrelated native-crate tests or
upstream Go suite was run for this change.

## Single scalar prefilter before ranking

Three complete active `TestMetricsSecondStage` rows at
[`pkg/traceql/parse_test.go:1866–1894`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/traceql/parse_test.go#L1866-L1894)
retain their original query strings:

```text
{ } | rate() > 10 | topk(5)
{ } | rate() by(name) >= 5.5 | bottomk(3)
{ } | count_over_time() != 0 | topk(10)
```

The unchanged upstream oracle is **parser acceptance, ordered filter/ranking
AST and formatted string**, not a numerical engine result or span producer.
The original test loop asserts these at lines 1907–1915. Pulse checks acceptance
and its own ordered native-leaf representation, not Go AST/string equality.
The complete source-file SHA-256 remains
`3eef0b3f465ed516623b34568ddd11023739d27612df74c2e26b75916f8dd1af`,
already recorded in the arithmetic provenance above. Runtime source confirms
sequential stage execution at
[`ast_metrics.go:640–673`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/traceql/ast_metrics.go#L640-L673).
No upstream runtime implementation is copied.

The authenticated HTTP adaptation uses an **authored numeric producer**: three
OTLP batches named `low`, `middle`, `high` contain 1, 6, 11 spans respectively,
all at the first second of a three-second range. Thus ungrouped rate/count has
18 in that interval; grouped prefilter `>= 5.5` retains `middle=6, high=11`.
Every original query runs standalone and as `(query) + 0`, with complete
label/timestamp/value expectations. Relative recent timestamps, OTLP/HTTP,
native Parquet/S3 and manifest-supervision restart are local adaptations.
These six wrappers do not claim six original numerical engine oracles.

Separate Pulse controls prove order-sensitive `>= 5.5 | bottomk(1)` returns
`middle=6` while `| bottomk(1) >= 5.5` returns nothing, on ordinary and arithmetic
paths. Two distinct prefiltered leaves share exactly one GET per source object;
instant rate divides by the original window; scan errors fail whole. Unsupported
stages, zero/negative k, nonfinite thresholds, vector comparisons, chained
prefilters and ranking a whole arithmetic expression reject before any provider
request. Unit controls compare all six comparisons/top-k/bottom-k against the
existing BEAM scalar filter plus independent per-interval selection, and retain
the shared series ceiling even when every sample is filtered away. Native
controls cover NaN omission, infinity/signed-zero values, invalid schemas and
prefilter work charging across leaves against the existing shared work counter.

The change admits one finite scalar comparison on one unranked pipeline before
one native ranking stage. Arbitrary second-stage chains and whole-expression
ranking remain unsupported. Existing native ranking/tie semantics are reused;
no BEAM ranking implementation, selector pushdown or filter reordering is added.
Every prefilter slot, including NaN/failing slots, spends shared native work
before selection. Existing scan/series/point/output limits remain authoritative.

Trace metrics capability **5** supersedes capability 4 and is required by both
the application loader and native artifact. Upgrade query-serving app/native
pairs together. Trace tuple `{2,1,3,5,12}`, storage formats and keyed bytes are
unchanged; no migration or retry drain is introduced. This is local HTTP/native
Parquet/S3 evidence, not execution of Tempo's Go tests, full second-stage grammar
or deployed-client/provider-capacity acceptance.

Before the implementation, the focused HTTP run (seed 751) had seven failures:
all six original-query wrappers and the order-sensitive control returned HTTP
400, `invalid or unsupported trace lookup parameters`. The rejection-before-
provider control passed. The first post-change run passed the six wrappers but
caught an authored assertion matching integer `12` against arithmetic JSON
`12.0`; the final assertion compares the complete expected response with `12.0`.
The final run at the same seed passes all eight tests. It includes exactly 15
Parquet GETs across five requests over three objects, including the two-distinct-
leaf expression; each object is fetched once per request.

Focused validation also passes all 24 metric evaluator/conformance tests (seed
752), 12 existing HTTP tie/step/arithmetic controls (seed 753), all eight native
trace-metric tests in release mode with one test thread, codec-only release
Clippy for library/test targets with warnings denied, test-environment
compilation with warnings as errors, scoped formatting and whitespace checks.
Every Elixir run uses `ERL_FLAGS='+S 2:2 +SDcpu 1'`; tests run serially against
compiled artifacts with `--no-compile --no-deps-check`. No broad suite or
upstream Go suite was run. Evidence is under `.amp/in/artifacts/` as
`tempo-prefilter-ranking-{red,first-green-attempt,green,evaluator,http-controls,
native-tests,clippy,compile}.log`.

```sh
ERL_FLAGS='+S 2:2 +SDcpu 1' mix test --no-compile --no-deps-check \
  test/pulse_web/controllers/tempo_upstream_integration_test.exs \
  --only metric_prefilter_ranking --warnings-as-errors --max-cases 1 --seed 751
```

## RFC3339Nano metric bounds: original parser oracle and authored HTTP consumer

The active [`Test_parseTimestamp` table](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L1210-L1239)
contains the complete selected row `RFC3339nano format`:

```text
value:   2009-11-10T23:00:00.000000001Z
default: now
want:    time.Date(2009, 11, 10, 23, 0, 0, 1, time.UTC)
wantErr: false
```

The unchanged exact oracle is **1257894000000000001 Unix nanoseconds**.
This is one original **parser-only** row, not an upstream numerical metric
evaluation or the complete timestamp table. Its default is unused because the
input is explicit. The pinned [`parseTimestamp`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http.go#L643-L667)
uses `time.Parse(time.RFC3339Nano, value)`; both metric request parsers retain
`UnixNano()` bounds. Source SHA-256:

- `pkg/api/http_test.go`: `6dd0951e0e691bdef2260ce2cb973d90d3a55297cbd2faf1e17acdb5e3880540`
- `pkg/api/http.go`: `328380983c1476278b89e1ee94e6609b00dcac1ee7dbe13111ab449310d83c8c`

The numerical consumer is explicitly **Pulse-authored**: one OTLP/HTTP span
named `authored-timestamp-probe`, starting at that exact timestamp and ending
one nanosecond later, with deterministic trace/span IDs and string attributes.
Authenticated `GET /api/metrics/query` and `/api/metrics/query_range` evaluate
`{} | count_over_time()` with a `1ns` step and a start two nanoseconds before
the oracle. Their complete responses must equal the integer-nanosecond-bound
control, whose count is independently asserted to be one. A whole-second or
zero-fraction end excludes the span; an end one nanosecond later includes it.
Offset-equivalent `+01:00` and `-05:00` inputs retain the exact original value.

Separate authored controls compare both bound sides around `.123456789`,
including one-nanosecond neighbors and a timezone offset, against exact integer
responses. They preserve range alignment's extra leading interval and existing
millisecond response timestamps rather than imposing instant-window semantics
on range samples. Additional controls cover epoch-zero starts with a positive
1ns end, six-digit and longer-than-nine-digit fractions, integral seconds,
integer nanoseconds and the existing decimal-seconds millisecond truncation.
Ten malformed-bound requests plus two invalid-window requests per endpoint
reject before any object-store request (missing timezone, invalid date, text,
negative numeric input, empty input, negative start and equal bounds).

Before the runtime change, seed 791 had **four failures and two passes**:
both original-row HTTP consumers returned zero instead of one, and both
fractional-bound controls failed; rejection controls already passed. The final
eight-test run at the same seed passes, including the two subsequently added
epoch-zero controls. It makes **98 metric GETs** (74 successful, 24 rejected)
and six OTLP POSTs, using owned Runtime/authentication, a real loopback HTTP
listener, native Parquet publication, restarted manifest supervision and an
owned S3-compatible store. Focused controller/evaluator/conformance checks
pass 26 tests (seed 792); existing step/tie/prefilter HTTP controls pass 17
tests (seed 793). Logs are `.amp/in/artifacts/tempo-rfc3339nano-{red,green,
final-green,metrics,http-controls}.log`.

The runtime change only restores the validated calendar fraction's discarded
sub-microsecond digits after existing DateTime timezone conversion. Existing
numeric semantics, accepted calendar grammar, 64-byte input ceiling, positive
window policies, scan/work/output budgets, storage and native interfaces remain
unchanged. Loki's nanosecond-aware parser has different grammar/bounds policies;
Prometheus discovery's precision helper is private and similarly policy-specific,
so neither is substituted for Tempo validation. No native change or capability
bump is required; metrics capability **5** remains sufficient. No Go test suite,
external cloud provider, capacity or deployed-client acceptance was run.

```sh
ERL_FLAGS='+S 2:2 +SDcpu 1' mix test --no-compile --no-deps-check \
  test/pulse_web/controllers/tempo_upstream_integration_test.exs \
  --only metric_timestamp_precision --warnings-as-errors --max-cases 1 --seed 791
```

## Negative metric steps: complete original rejection table

The active [`TestParseQueryRangeNegativeStep`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L1276-L1287)
is replayed in full, with all four original requests unchanged:

```text
q={} | rate()
start=1700000000
end=1700003600
step=-1h / -30m / -1.5 / -0.001
```

The original oracle is an error containing **`step must be positive`** for
every row. It is a parser-only rejection table, not a numerical metric oracle.
The public HTTP wrappers retain that substring and additionally assert HTTP400
and the complete diagnostic produced by the pinned [`step` helper](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http.go#L669-L695):
`cannot parse "<original step>": step must be positive`. Those complete-body
assertions are source-derived additions, not extra assertions in the Go test.
The source-file hashes are the same `pkg/api/http{,_test}.go` hashes recorded in
the preceding timestamp section.

No input spans are needed by the four rejection rows. A separately authored
positive/instant control loads one deterministic span at
`1700001800000000000` ns through authenticated OTLP/HTTP, publishes native
Parquet through the owned S3-compatible store and restarts manifest supervision.
A `1h` range query actually reads the object and sums to `1/3600`; the instant
query also returns `1/3600`. All four negative step strings, plus zero and
malformed steps, remain ignored on instant queries. Repeating the four negative
range requests with that visible object, and without authorization, proves
HTTP400/401 rejection without any additional object-store requests. All four
original wrappers independently assert no provider requests too.

Fifteen separate authored malformed/zero/`since` controls keep the generic
HTTP400 body, including repeated signs, unsupported negative day units,
overflow, negative zero and negative `since`. A positive `35ms` step over360s
keeps the existing minimum-step diagnostic. The old authored `-1s` generic-body
assertion is updated to the new negative-step diagnostic, retaining its HTTP400
and no-provider checks. These are diagnostic changes only: no negative or zero
range step becomes executable, and no timestamp, query grammar or safety policy
is broadened.

The pre-change seed811 run had **five failures and one pass**: every original
row and the authored negative-range control returned the generic lookup body;
malformed/zero/`since`/minimum-step controls passed. The first runtime attempt
still failed the two unit-bearing source rows and the authored control because
the existing Go-duration parser is unsigned. The final implementation reuses
that same parser after one minus sign, without duplicating its unit grammar.
Decimal seconds still use the existing numeric parser; `since` keeps its generic
positive-only policy. The final focused run passes **all six tests**, covering
36 metric GETs (eight HTTP200, 24 HTTP400 and four HTTP401) and one OTLP POST.

Adjacent timestamp/step/tie/prefilter HTTP validation passes **31 tests** at
seed812, including the six new tests. Focused metric controller/evaluator/
conformance validation passes **26 tests** at seed813. Every run uses
`ERL_FLAGS='+S 2:2 +SDcpu 1'`, `--max-cases 1` and `--warnings-as-errors`.
Logs are `.amp/in/artifacts/tempo-negative-step-{red,green,final-green,
http-controls,evaluator}.log`; `green` is the unsuccessful first runtime attempt.

To avoid rebuilding native artifacts or changing shared compiled modules, the
green checks use `mix run --no-compile --no-deps-check`, compile only the current
controller **in-process**, fail on any captured compiler diagnostics, then invoke
the test task. This does not persist an updated controller BEAM file. After a
normal application compilation, the focused replay command is:

```sh
ERL_FLAGS='+S 2:2 +SDcpu 1' mix test --no-compile --no-deps-check \
  test/pulse_web/controllers/tempo_upstream_integration_test.exs \
  --only metric_negative_step --warnings-as-errors --max-cases 1 --seed 811
```

No native source/interface, capability, storage/keyed bytes, or resource ceilings
change; metrics capability **5** remains sufficient. No native build, broad test
suite, upstream Go execution, external-provider, capacity or deployed-client
acceptance was performed.

## Invalid metric bounds: complete original parameter-diagnostic table

All four active wrappers from [`TestParseQueryRequestInvalidBounds`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L1241-L1274)
are replayed: two original request rows, each through instant and range HTTP.

| Query | Start | End | Unchanged original error substring |
| --- | --- | --- | --- |
| `{} \| rate()` | `abc` | `1700000000` | `could not parse 'start' parameter` |
| `{} \| rate()` | `1700000000` | `bca` | `could not parse 'end' parameter` |

These are parser-only error oracles, not numerical evaluations. The original
test requires errors containing those substrings, not complete Go error-text
equality. The public wrappers retain the requests/substrings unchanged and add
HTTP400 and no-object-store-request assertions. Tempo's [`determineBounds`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http.go#L533-L561)
adds the parameter names. Pulse returns the required prefix alone; underlying
Go timestamp-parser diagnostics are not claimed. The source hashes are the
same `pkg/api/http{,_test}.go` hashes recorded in the timestamp section above.

Separate authored controls ingest one deterministic span at
`1700001800000000000` ns per endpoint, publish native Parquet through owned
authenticated HTTP/S3 and restart manifest supervision. Valid range and instant
queries actually read that object and return `1/3600`. With that visible input,
malformed start/end requests, both-invalid requests and unauthorized requests
make no further provider requests. Both-invalid timestamps report `end`.
Additional authored controls retain Pulse's existing **end, since, start**
validation order: invalid end precedes invalid since, while invalid since
precedes invalid start. This is preservation of Pulse's existing policy, not
a claim of upstream multi-error-precedence parity.

Admitted-but-invalid windows are kept separate: equal/reversed bounds, a
successfully parsed pre-epoch start and an integer end exceeding int64 still
return the generic window-policy HTTP400 body. Existing timestamp grammar
controls now assert named parsing errors, while their separate negative/equal
window controls explicitly retain generic errors. Search and tag-discovery
malformed-bound requests independently retain their generic responses.

At seed831 the red run had **six failures and one pass**: all four original
wrappers and both authored metric controls saw the old generic lookup body;
the discovery control passed. After adding context only around metric timestamp
parsing, **all seven tests pass**. They issue 36 GETs (two HTTP200, 24 HTTP400,
ten HTTP401) and two OTLP POSTs. All rejected requests leave the owned store's
complete request history unchanged, not only its Parquet GET count.

Adjacent invalid-bound/negative-step/timestamp/minimum-step/tie/prefilter HTTP
validation passes **38 tests** at seed832, including the seven new tests.
Focused metric controller/evaluator/conformance validation passes **26 tests**
at seed833. Logs are `.amp/in/artifacts/tempo-invalid-bounds-{red,green,
http-controls,evaluator}.log`. Runs use `ERL_FLAGS='+S 2:2 +SDcpu 1'`, serial
`--max-cases 1` and `--warnings-as-errors`. Green checks reload only the current
controller in-process under `mix run --no-compile --no-deps-check`, reject any
captured compiler diagnostics, and then invoke the scoped test task; final normal
application compilation is separate. After normal compilation, replay with:

```sh
ERL_FLAGS='+S 2:2 +SDcpu 1' mix test --no-compile --no-deps-check \
  test/pulse_web/controllers/tempo_upstream_integration_test.exs \
  --only metric_invalid_bounds --warnings-as-errors --max-cases 1 --seed 831
```

The existing metric-only timestamp parser now returns parameter context directly,
without a separate wrapper. Admission grammar, numeric semantics, nanosecond
precision, defaults, validation order, discovery and window-policy errors are unchanged.
No native/interface/capability, storage/keyed-byte or resource-ceiling change;
metrics capability **5** remains sufficient. No native build, broad suite,
upstream Go execution, external-provider/capacity or deployed-client acceptance
was performed.

## Malformed metric since: selected original helper error row

The active [`Test_determineBounds`, `invalid since` row](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L1400-L1413)
at the same pin supplies `now = 2022-12-18T00:00:00Z`,
`startString = "2022-12-17T00:00:00Z"`,
`endString = "2022-12-18T00:00:00Z"` and `sinceString = "HI!"`.
Its unchanged oracle is an error containing **`could not parse 'since' parameter:`**,
including the colon. The row's zero-time result placeholders are not compared
after the expected error. This is one complete selected helper row, **not the
whole bounds table**, and a parser-only oracle, not an upstream metric result.
Source SHA-256 values remain the `pkg/api/http{,_test}.go` hashes above.
The original [`determineBounds` parser](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http.go#L533-L541)
wraps malformed duration errors with this context.

Both `/api/metrics/query` and `/api/metrics/query_range` retain the original
start/end/since strings and substring oracle. The explicit bounds make the
original injected clock irrelevant to these HTTP consumers. The query
`{} | count_over_time()`, `step=1h`, HTTP400 and no-provider assertions are
**authored HTTP adaptations**, not further original helper expectations.
Pulse returns the required prefix alone; exact Go duration diagnostics are
not claimed. Existing duration parsers and their precedence are unchanged.
Only a failed parse gains the `since` context; successfully parsed zero and
negative values still fail Pulse's strictly-positive safety policy with the
generic lookup error. Omission still uses the existing default.

Separately authored controls ingest one deterministic **one-nanosecond** span
at `1671278400000000000` ns through authenticated OTLP/HTTP, owned native
Parquet/S3 and restarted manifest supervision. Omitted since, `1h` and `1d`
each return count `1` through both endpoints, with a real Parquet read proved.
Malformed, unauthorized and multi-error requests leave the owned provider's
complete request history unchanged. Authored precedence remains **end, since,
start, range step**: invalid end wins over malformed since; malformed since
wins over invalid start or negative step. This is Pulse policy preservation,
not upstream multi-error-precedence parity. Six malformed forms and six
successfully parsed nonpositive forms per endpoint keep parse and policy errors
distinct. Earlier authored generic-body `since=bad/garbage` assertions now
expect parsing context; their zero/negative policy controls are unchanged.

At seed1933 the red run failed **all six new tests** with the generic lookup
body. The runtime change makes **all six pass**, issuing 48 metric GETs
(six HTTP200, 34 HTTP400, eight HTTP401) plus two OTLP POSTs. The original helper
row accounts for two of those GETs, not all 48 upstream cases. Adjacent Tempo
diagnostic/precision/ranking controls and three shared finite-read deadline,
admission-release and native-S3 recovery tests pass **47 tests** at seed1934.
Focused metric controller/evaluator/conformance tests pass **26 tests** at
seed1935. Logs: `.amp/in/artifacts/tempo-invalid-since-{red,green,
http-deadlines,evaluator}.log`.

All runs use `ERL_FLAGS='+S 2:2 +SDcpu 1'`, serial `--max-cases 1` and
`--warnings-as-errors`. Green runs compile only the controller in-process,
reject captured compiler diagnostics, and invoke tests with
`--no-compile --no-deps-check`; normal application compilation remains a
separate check. After normal compilation, replay with:

```sh
ERL_FLAGS='+S 2:2 +SDcpu 1' mix test --no-compile --no-deps-check \
  test/pulse_web/controllers/tempo_upstream_integration_test.exs \
  --only metric_invalid_since --warnings-as-errors --max-cases 1 --seed 1933
```

No native build, capability bump, storage/keyed-byte, parser-grammar or resource
ceiling change; metrics capability **5** remains sufficient. No full upstream
table, upstream Go execution, external-provider/capacity, deployed-client or
broad-suite acceptance is established by these focused checks.

## Mixed quoted discovery identifiers: five original parser rows

Five active [`TestParseIdentifier` rows](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/traceql/parse_test.go#L1476-L1503)
retain their complete original inputs and exact decoded attribute mappings:

| Input | Expected attribute |
| --- | --- |
| `."bar z".foo` | unscoped `bar z.foo` |
| `."bar z".foo."bar"` | unscoped `bar z.foo.bar` |
| `.foo."bar baz"` | unscoped `foo.bar baz` |
| `.foo."bar baz".bar` | unscoped `foo.bar baz.bar` |
| `span."bar z".foo` | span-scoped `bar z.foo` |

These are five **parser-only rows**, not the whole identifier table or original
HTTP result oracles. The pinned [v2 HTTP request parser](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/search_tags.go#L332-L355)
uses `ParseIdentifier`. Its [attribute lexer](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/traceql/lexer.go#L259-L310)
concatenates ordinary and quoted portions and decodes **only escaped quote and
backslash**, not JSON newline/Unicode escapes. Source SHA-256:

- `pkg/traceql/parse_test.go`: `3eef0b3f465ed516623b34568ddd11023739d27612df74c2e26b75916f8dd1af`
- `pkg/traceql/lexer.go`: `d595e64b993fc5a3de589643c191aa6277a16a5edd98db1f2a72ac9870e4efd3`
- `pkg/api/search_tags.go`: `f0b412a6eada7f8e2020b83ca3f8855d4332e995d9eeb210ed8a2eb0f772e03e`

The string producer and all HTTP expectations are **authored**:
one deterministic OTLP span carries the four decoded keys with string values
`one` through `four`. Authenticated v1/v2 discovery must retrieve those values,
equally through mixed and fully quoted spellings, JSON/protobuf responses,
unbounded/explicit source windows, and absent/matching existing resource-string
filters. Native Parquet publication and fresh manifest supervision precede reads.
Filters use existing unquoted names; target normalization does not add quoted
predicate grammar or change same-target, metadata-integrity or window policies.

Separate authored controls cover escaped quote/backslash, quoted literal dots,
decoded **256-byte** Unicode keys versus 257-byte rejection, encoded input over
2048 bytes, missing closing quotes/trailing escapes, unsupported escapes,
unquoted whitespace, suffixes/adjacent quotes, empty keys and stage text.
Whole-key JSON controls retain Unicode escapes, escaped newline/NUL and
surrogate-pair decoding, plus escaped 256-byte keys and 257-byte rejection.
Mixed portions reject JSON newline/Unicode escapes even when the first portion
is quoted. These are authored preservation controls, not upstream lexer rows.
Unauthorized original targets return HTTP401. All rejected requests leave the
owned S3 store's complete request history unchanged, including after valid
Parquet reads. The four new tests issue **272 discovery GETs** (224 HTTP200,
38 HTTP400, ten HTTP401), plus four OTLP POSTs. Only five selected source rows
are upstream cases; transport, filter, producer, boundary and error controls
are not additional upstream oracles.

Mixed normalization is deliberately narrower than the entire pinned lexer:
ordinary and quoted portions must be dot-separated. Existing suffix/adjacent-
quote and literal unescaped ASCII-control rejections remain, although the
upstream lexer permits more concatenation and quoted literal controls.
**Whole quoted keys preserve Pulse's documented JSON-compatible contract**,
including `\n`/`\uXXXX` and every decoded key allowed by existing validation.
A one-argument normalization entry first tries the existing whole-string JSON
decoder; non-whole inputs use the mixed parser's verified quote/backslash
profile. Both paths feed the same decoded-key validation. Existing scope/
legacy-v1 handling and one-time URL decoding remain. The 2048-byte normalization
input bound keeps temporary chunks finite; the existing decoded 256-byte UTF-8
key limit and all storage/query budgets stay.

The red run at seed1941 failed all four new tests: fully quoted controls read
the object, while mixed forms returned the generic HTTP400 body. After the
controller-only change all four passed. Final source/control plus existing
special-character checks pass **eight tests** at seed1942; three adjacent
slash/malformed-name/scope checks pass at seed1943; scoped ordinary, filtered
and windowed discovery checks pass **18 tests** at seed1944. Strict scoped
Credo, formatting and whitespace checks pass. Logs are
`.amp/in/artifacts/tempo-segmented-identifiers-{red,green,controls,legacy,
discovery,credo,format}.log`.

The follow-up preservation regression at seed1951 exposed the initial whole-
key narrowing: two source-mapping tests passed, while both v1/v2 authored
Unicode-escape controls failed with HTTP400. Restoring whole-key JSON decoding
makes the expanded source/control plus special-character checks pass **eight
tests** at seed1951. The five original source rows/mappings are unchanged.
The three adjacent slash/malformed-name/scope checks also pass at seed1952;
scoped strict Credo, formatting and whitespace checks remain clean.
Follow-up logs are `.amp/in/artifacts/tempo-segmented-whole-json-{red,green,
legacy,credo,format}.log`.

Tests use `ERL_FLAGS='+S 2:2 +SDcpu 1'`, `--max-cases 1` and
`--warnings-as-errors`. Green checks compile only the owned controller in a
disposable VM, reject captured compiler diagnostics and run tests with
`--no-compile --no-deps-check`. Normal persisted application compilation remains
separate. After that compilation, replay with:

```sh
ERL_FLAGS='+S 2:2 +SDcpu 1' mix test --no-compile --no-deps-check \
  test/pulse_web/controllers/tempo_upstream_integration_test.exs \
  --only segmented_identifiers --max-cases 1 --warnings-as-errors --seed 1941
```

No native/capability, storage/keyed-byte or resource-ceiling change; upgrade
serving applications for the HTTP normalization behavior. No broad suites,
native builds, upstream Go execution or external-provider/deployed-client
acceptance is claimed. Search/metric/filter identifier grammars are unchanged.

## Search-limit rejection diagnostics

Four complete active rows from pinned
[`TestQuerierParseSearchRequest`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L83-L97)
retain their original request URLs and exact helper error messages. The overflow
row is at [lines195–199](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L195-L199).
The original [table loop](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L263-L275)
constructs the HTTP request and asserts `ParseSearchRequest` error equality;
it is not an upstream numerical engine test.

| Original URL | Unchanged helper message |
| --- | --- |
| `/api/search?limit=0` | `invalid limit: must be a positive number` |
| `/api/search?limit=-5` | `invalid limit: strconv.ParseUint: parsing "-5": invalid syntax` |
| `/api/search?limit=five` | `invalid limit: strconv.ParseUint: parsing "five": invalid syntax` |
| `/api/search?limit=4294967298` | `invalid limit: strconv.ParseUint: parsing "4294967298": value out of range` |

The production parser is
[`pkg/api/http.go:287–295`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http.go#L287-L295).
Complete source SHA-256:

- `pkg/api/http_test.go`: `6dd0951e0e691bdef2260ce2cb973d90d3a55297cbd2faf1e17acdb5e3880540`.
- `pkg/api/http.go`: `328380983c1476278b89e1ee94e6609b00dcac1ee7dbe13111ab449310d83c8c`.

Authenticated HTTP400 and unauthorized HTTP401 assertions, newline-free body
equality, the one-span/1ns producer and successful supported-selector results
are authored adaptations. Each original rejection follows an authenticated
`{ resource.service.name = "my-service" }` search of published native Parquet
through owned S3 after manifest restart. Rejections leave the store's complete
provider-request history unchanged. The separate authored test checks omitted
limit, 1/10/100/1000, existing plus/leading-zero acceptance, empty/fractional/
scientific/malformed values, Go quote/newline escaping, ten-byte context bounds,
over-cap values, authentication and unknown-parameter/window/limit/spss error
precedence. The five tests issue **33 search GETs** (11 HTTP200, 17 HTTP400,
five HTTP401), plus five OTLP POSTs.

Only rejection diagnostics change. The existing numeric parser, default100,
cap1000, ten-byte input bound, spss and auth/window precedence stay unchanged.
Bounded syntax/range context is tagged only after the existing parser rejects;
the existing Go-compatible quoting helper renders it. Values exceeding the
operator cap but not uint32, larger inputs and non-scalar inputs retain generic
policy errors. No additional Go numeric acceptance, discovery/metrics grammar,
native/capability, storage/keyed-byte or resource-ceiling change is made.

At seed1961, the public red run failed all five new tests with the previous
generic body, including all four original rows after successful Parquet reads.
Source-loading only the owned controller in a disposable VM makes all five
pass with compiler diagnostics rejected and `--warnings-as-errors`. Logs:
`.amp/in/artifacts/tempo-search-limit-{red,green}.log`.
The adjacent malformed-since, timestamp-bound, negative-step and mixed/whole-
quoted identifier selections pass **23 tests** at seed1962. Three existing
retained-search/window/quoted-name controls pass at seed1963. Strict scoped
Credo checks both owned source files without issues; formatting and whitespace
checks pass. Their logs are `.amp/in/artifacts/tempo-search-limit-{adjacent,
search-controls,credo-scoped,format}.log`. All tests run serially with
`ERL_FLAGS='+S 2:2 +SDcpu 1'`, `--max-cases 1` and `--warnings-as-errors`.
Normal persisted application compilation is a separate handoff. Replay after
that compilation:

```sh
ERL_FLAGS='+S 2:2 +SDcpu 1' mix test --no-compile --no-deps-check \
  test/pulse_web/controllers/tempo_upstream_integration_test.exs \
  --only search_limit_diagnostics --max-cases 1 --warnings-as-errors --seed 1961
```

No upstream Go/engine execution, broad suite, native build, external provider or
deployed-client acceptance is claimed.

## Single empty Accept header

The complete selected active row from pinned
[`TestMarshalingFormatFromAcceptHeader`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L24-L43)
is unchanged: `name="empty accept header"`, `acceptHeader=""`,
`expected=MarshallingFormatJSON`. Its assertion supplies
`http.Header{HeaderAccept: []string{""}}`, not an absent header.
The production helper explicitly returns JSON for the empty value at
[`pkg/api/http.go:146–151`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http.go#L146-L151).
Both exact-lookup frontend handlers call it at
[`traceid_handlers.go:40–44`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/modules/frontend/traceid_handlers.go#L40-L44)
and [154–158](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/modules/frontend/traceid_handlers.go#L154-L158).

Complete source SHA-256:

- `pkg/api/http_test.go`: `6dd0951e0e691bdef2260ce2cb973d90d3a55297cbd2faf1e17acdb5e3880540`.
- `pkg/api/http.go`: `328380983c1476278b89e1ee94e6609b00dcac1ee7dbe13111ab449310d83c8c`.
- `modules/frontend/traceid_handlers.go`: `d1f786689f6928a7b4e9609a83361acca149672abb3c3ec1552b588afb853b05`.

The original oracle selects a format, not a stored-trace body or HTTP status.
The v1/v2 exact-ID URLs, deterministic IDs, one-span/1ns producer, HTTP200,
JSON MIME and full body equality with the no-Accept baseline are authored
consumer adaptations. They reuse the owned actual HTTP listener so that
`Accept: ""` remains an explicitly present header. Each test ingests through
authenticated OTLP/HTTP, publishes native Parquet through owned loopback S3,
restarts manifest supervision and proves a successful read before the original
empty-header request.

Separate authored v1/v2 controls preserve JSON/no-header equivalence, wildcard,
existing JSON quality/list/multiple-header behavior and exact protobuf success
with a nonempty binary body. This is not an independent protobuf wire oracle.
Unsupported HTML/invalid/LLM media, protobuf quality/list variants, two empty
headers and empty-plus-protobuf headers still return406. Empty-header requests
without credentials return401; unsupported lookup modes still return400.
All these rejected requests leave complete provider-request history unchanged
after successful reads. Four tests issue **36 lookup GETs** (18 HTTP200,
14 HTTP406, two HTTP401, two HTTP400), plus four OTLP POSTs.

Only the single empty-header value gains the existing JSON fallback. Other
media negotiation, auth/parameter precedence, limits, storage/native formats
and capabilities are unchanged. The rest of the upstream helper table is not
newly claimed: invalid-media fallback and LLM negotiation remain deliberately
unsupported, and general protobuf quality/list negotiation is not added.

At seed1971, both original-row public consumers failed red with HTTP406 after
successful Parquet reads; both authored policy-control tests already passed.
The one-line controller change makes all four tests pass. Adjacent search-limit
and mixed/whole-quoted identifier checks pass nine tests at seed1972; three
existing filtered-lookup checks pass at seed1973, including all31 original
depth combinations and JSON/protobuf controls. Strict scoped Credo (two files),
formatting and whitespace checks pass. Logs:
`.amp/in/artifacts/tempo-empty-accept-{red,green,adjacent,lookup,credo,format}.log`.

Tests use `ERL_FLAGS='+S 2:2 +SDcpu 1'`, `--max-cases 1` and
`--warnings-as-errors`. Green checks source-load only the owned controller in
a disposable VM and reject captured compiler diagnostics. Main application
compilation is a separate handoff. After persisted compilation, replay with:

```sh
ERL_FLAGS='+S 2:2 +SDcpu 1' mix test --no-compile --no-deps-check \
  test/pulse_web/controllers/tempo_upstream_integration_test.exs \
  --only empty_accept --max-cases 1 --warnings-as-errors --seed 1971
```

No upstream Go/engine execution, broad suite, normal project/native build,
external-provider or deployed-client acceptance is claimed.

## Spans-per-spanset rejection diagnostics

Three complete active `TestQuerierParseSearchRequest` rows retain their original
URLs and exact helper error messages: the
[overflow row](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L200-L204)
and [negative/nonnumeric rows](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L233-L242).
The [original loop](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L263-L275)
constructs requests and checks helper error equality. The production parser is
[`pkg/api/http.go:298–304`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http.go#L298-L304).

| Original URL | Unchanged helper message |
| --- | --- |
| `/api/search?spss=-2` | `invalid spss: strconv.ParseUint: parsing "-2": invalid syntax` |
| `/api/search?spss=four` | `invalid spss: strconv.ParseUint: parsing "four": invalid syntax` |
| `/api/search?spss=4294967296` | `invalid spss: strconv.ParseUint: parsing "4294967296": value out of range` |

Complete source SHA-256:

- `pkg/api/http_test.go`: `6dd0951e0e691bdef2260ce2cb973d90d3a55297cbd2faf1e17acdb5e3880540`.
- `pkg/api/http.go`: `328380983c1476278b89e1ee94e6609b00dcac1ee7dbe13111ab449310d83c8c`.

The one-root/three-child producer, `filter-test` service, supported selector,
matched4 and sampled3/1/2/4 results are authored numerical HTTP adaptations,
not upstream engine oracles. Each original error follows a successful
authenticated public search of native Parquet through owned loopback S3 after
manifest restart. HTTP400/401 status and exact newline-free response bodies,
authentication and unchanged provider-request histories are HTTP consumer
adaptations. The original rejection URLs do not gain a selector.

The separate authored test covers omitted spss, 1/2/100, existing plus and
ten-byte leading-zero acceptance; empty/fractional/scientific/malformed values,
Go quote/newline rendering, ten-byte syntax/range diagnostics and eleven-byte
generic rejection. Parsed zero and over-cap values remain generic policy
failures, including the uint32 maximum. Unknown-parameter/window/limit/auth
precedence stays intact. The four tests issue **33 search GETs** (nine HTTP200,
20 HTTP400, four HTTP401), plus four OTLP POSTs; all24 rejection/auth requests
leave the complete provider-request history unchanged.

Only bounded parse-error diagnostics change. The existing numeric grammar,
ten-byte admission bound, default3/cap100, default100/cap1000 for limit,
whole-failure policies and auth/window/limit ordering are unchanged. The
existing bounded limit error classifier and Go-compatible quote renderer are
shared with spss; no extra Go numeric acceptance is added. Upstream's separate
zero-spss acceptance row is deliberately not imported. No native/capability,
storage/keyed-byte, discovery/metrics or resource-ceiling change is made.

Public red at seed1981 failed all four new tests with the previous generic
body, including all three original rows after successful Parquet reads. Green
source-loads only the owned controller in a disposable VM, rejects captured
compiler diagnostics and passes nine tests (four new plus five existing limit
tests). After scoped formatting, the new/limit/empty-Accept/mixed-identifier
selection passes17 tests at seed1982; three existing retained-search/window/
quoted-key controls pass at seed1983. Strict scoped Credo checks two source
files without issues; formatting and whitespace checks pass. Logs:
`.amp/in/artifacts/tempo-spss-{red,green,adjacent,search-controls,credo,format}.log`.
Tests run serially with `ERL_FLAGS='+S 2:2 +SDcpu 1'`, `--max-cases 1` and
`--warnings-as-errors`. Normal persisted application compilation remains a
separate handoff. After that compilation, replay with:

```sh
ERL_FLAGS='+S 2:2 +SDcpu 1' mix test --no-compile --no-deps-check \
  test/pulse_web/controllers/tempo_upstream_integration_test.exs \
  --only search_spss_diagnostics --only search_limit_diagnostics \
  --max-cases 1 --warnings-as-errors --seed 1981
```

No upstream Go/helper/engine execution, broad suite, normal project/native
build, external-provider, capacity or deployed-client acceptance is claimed.

## Search start/end rejection diagnostics

Three complete active rows from pinned
[`TestQuerierParseSearchRequest`](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L180-L194)
retain their original URLs and exact helper error messages. The
[table loop](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http_test.go#L263-L275)
constructs each request and asserts helper error equality. The
[production parser](https://github.com/grafana/tempo/blob/1a7373ee774b2ee5a40957c2310179b0ef7ff843/pkg/api/http.go#L199-L212)
parses start before end and attaches the parameter name to parsing failures.

| Original URL | Unchanged helper message |
| --- | --- |
| `/api/search?start=-1&end=20` | `invalid start: strconv.ParseUint: parsing "-1": invalid syntax` |
| `/api/search?start=4294967296&end=4294967297` | `invalid start: strconv.ParseUint: parsing "4294967296": value out of range` |
| `/api/search?start=10&end=-1` | `invalid end: strconv.ParseUint: parsing "-1": invalid syntax` |

Complete source SHA-256:

- `pkg/api/http_test.go`: `6dd0951e0e691bdef2260ce2cb973d90d3a55297cbd2faf1e17acdb5e3880540`.
- `pkg/api/http.go`: `328380983c1476278b89e1ee94e6609b00dcac1ee7dbe13111ab449310d83c8c`.

HTTP400/401 status and exact newline-free response bodies are consumer
adaptations, not an upstream HTTP-server or engine oracle. The one-root/1ns
producer, `my-service` selector, one retained trace and matched1 result are
authored numerical adaptations. Each original rejection follows an
authenticated successful public search after native Parquet publication and
manifest restart on owned loopback S3; the test explicitly observes a new
`.parquet` read. The original rejection URLs do not gain a selector.

A separate authored test preserves identical retained results with omitted,
paired-zero and positive enclosing bounds, uint32 maximum end and ten-byte
leading-zero start. Its rejection controls cover partial bounds (including a
malformed partial bound), mixed-zero/reversed windows, plus-prefixed numeric
bounds, eleven-byte inputs, empty/fractional/malformed bounds, ten-byte syntax/
overflow errors, invalid-both start precedence and unknown/window/limit/spss/
auth ordering. All four new tests issue **32 search GETs** (eight HTTP200,
20 HTTP400, four HTTP401), plus four OTLP POSTs. All24 rejection/auth requests
leave complete provider-request history unchanged.

Only bounded parse failures gain start/end context through the existing
parameter-aware classifier and Go quote renderer. The shared bounded search
parser retains existing `seconds/1` numeric acceptance and ten-byte input
admission. Partial bounds, digit-only policy (including plus-prefix rejection),
mixed-zero/reversed-window policies, limits, defaults and ordering are
unchanged. Both seconds values still parse before the existing digit/window
policy checks; start parsing still precedes end parsing. Two older authored
limit/spss precedence assertions now expect the correctly contextualized
malformed-start error instead of a generic body. Discovery, exact lookup and
metrics parsing are untouched. No native/capability, storage/keyed-byte or
resource-ceiling change is made.

At seed1991, public red failed all four new tests with the prior generic body,
including all three original rows after explicit successful Parquet reads.
Green source-loads only the owned controller in a disposable VM, rejects
captured compiler diagnostics and passes13 tests: four new, five limit and
four spss. After scoped formatting, three adjacent retained-search/window/
quoted-key tests pass at seed1992. Strict scoped Credo checks two source files
without issues; formatting and whitespace checks pass. Logs:
`.amp/in/artifacts/tempo-search-bounds-{red,green,adjacent,credo,format}.log`.
All tests run serially with `ERL_FLAGS='+S 2:2 +SDcpu 1'`, `--max-cases 1` and
`--warnings-as-errors`. Normal persisted compilation is a separate handoff;
after that compilation, replay with:

```sh
ERL_FLAGS='+S 2:2 +SDcpu 1' mix test --no-compile --no-deps-check \
  test/pulse_web/controllers/tempo_upstream_integration_test.exs \
  --only search_bound_diagnostics --only search_limit_diagnostics \
  --only search_spss_diagnostics --max-cases 1 --warnings-as-errors --seed 1991
```

No upstream Go/helper/engine execution, broad suite, normal project/native
build, external-provider, capacity or deployed-client acceptance is claimed.

## Explicit remaining gaps

Not imported: intrinsic-name filters, partial/invalid-query fallback, unscoped
filter fallback, OR discovery, and exact dedicated-column name-hint omission
from the rest of `TestTagEndpoints`. Pulse continues to reject unsupported
filters rather than ignore them. The upstream disabled double-slash case stays
excluded. Backtick identifiers and every Go string-escape spelling are not
established by these double-quoted fixtures.

Also not ported here: gRPC streaming queries, broader trace-by-ID filters/diffs, partial
search time bounds, structural/spanset queries, metrics
exemplars and `compare()`, tenant federation, overrides, receiver
variants, fault/restart/limit matrices, metrics generation, and Tempo-specific
Kafka/WAL/livestore/block orchestration and cloud-provider tests. Existing Pulse
trace/export/search/metric tests remain separate evidence, not transplanted
upstream acceptance. Loopback S3 is not provider/capacity/deployed-client proof.

## License

The copied tables and derived ExUnit test retain Tempo's **AGPL-3.0-only**
license; `LICENSE` is copied verbatim from that source revision. They are not
relicensed under Pulse's MIT license. No Tempo runtime implementation is copied.
