# Selected Grafana Mimir service integration scenarios

Revision: **`dd039cdd4ba466adb5d28280bf1b8a374a98432e`**.

The executable fixtures are embedded in
[`mimir_service_conformance_test.exs`](../../../../pulse_web/controllers/mimir_service_conformance_test.exs).
They are ports of the public request/response portions of actual Mimir service
integration tests, not invented cases labelled upstream. This is **52 selected
scenario replays** (51 ExUnit tests: the scalar/range frontend pair shares one),
plus 23 separately named Pulse regression/control tests and five shared-regex
control wrappers: **79 ExUnit tests**, not the complete Mimir integration suite.
The existing math corpus in the parent directory is separate and remains unchanged.

## Sources and exact selection

All links below are pinned to the revision above.

| Upstream entry point and source | Selected scenarios | Replays |
| --- | --- | ---: |
| [`TestDistributor` → `testDistributorWithCachingUnmarshalData`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/distributor_test.go#L41-L425) | `simple counter`, `simple gauge`, `simple histogram`, `simple summary`, each with RW1 and RW2 | 8 |
| [Same distributor table, native histograms](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/distributor_test.go#L420-L605) | `simple native histogram` with RW1 and RW2; `simple nhcb histogram` with RW2 (upstream has no RW1 input) | 3 |
| [Same distributor table, exemplars](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/distributor_test.go#L803-L847) | `series with exemplars`, with RW1 and RW2 | 2 |
| [Same distributor table, label normalization](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/distributor_test.go#L607-L665) | `drop empty labels` and `wrong labels order`, each with RW1 and RW2 | 4 |
| [Same distributor table, invalid symbols](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/distributor_test.go#L1008-L1040) | `invalid rw2 symbols`, RW2-only upstream | 1 |
| [`TestDistributor_NameValidation` → `testDistributorNameValidation`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/distributor_test.go#L1353-L1615) | All three rows (`legacy metric name`, `utf8 metric name`, `utf8 label name`), each with RW1 and RW2, selecting **UTF8Validation only** | 6 |
| [`TestIngesterQuerying`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/ingester_test.go#L23-L582) | All seven table entries: `float series`; `integer histogram series`; `float histogram series`; `series switching from float to integer histogram to float histogram`; `series including float and native histograms at same timestamp`; `float series where sample timestamps don't align with query step`; `query that returns no results` | 7 |
| [`TestQueryFrontendWithExplicitLookbackDelta` → `queryLookbackDeltaTest`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/query_frontend_test.go#L1067-L1203) | Default 5m lookback at sample+3m / sample+6m; explicit 10m / 1m at sample+6m. Each checks instant and range queries with the upstream ±100m / 100m step geometry. | 4 |
| [`testQueryFrontend`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/query_frontend_test.go#L359-L454) | User-0's `scalar(series_1)` and `series_1[5m]` instant requests, preserving complete type, timestamp and value assertions | 2 |
| [`TestQueryFrontendErrorMessageParity` → `testQueryFrontendErrorMessageParityScenario`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/query_frontend_test.go#L566-L905) | Eight portable invalid range requests: maximum resolution; negative step; unknown function; range vector instead of instant vector; start after end; malformed step; malformed start; range query with range vector. Five parameter rows and the top-level range-result row assert complete original envelopes; two expression rows retain adapted diagnostics (details below). | 8 |
| [Same frontend table, `execution error`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/query_frontend_test.go#L865-L872) | All 50 source metric series, original grouped binary expression, -1m..now / 1m range, exact HTTP 422 and complete execution-error envelope including the original diagnostic | 1 |
| [`TestQuerierWithBlocksStorageRunningInSingleBinaryMode`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/querier_test.go#L311-L517) → [`testMetadataQueriesWithBlocksStorage`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/querier_test.go#L573-L790) | All four helper time windows: inside head; inside ingester/outside head; partially inside ingester; entirely outside ingester. Every series lookup, metric-name values selector (including OR), and label-name expectation in that helper is retained: 29 discovery requests. | 4 |
| [`TestHashCollisionHandling`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/querier_test.go#L983-L1068) | One RW1 push containing both `fingerprint_collision` series under `user-0`, then the complete instant vector at the shared sample timestamp | 1 |
| [`TestFormatQueryAPIEndpoint`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/api_endpoints_test.go#L89-L112) | Exact GET expression `count(up)by(foo)`, HTTP 200 and expected `data="count by (foo) (up)"`; no storage request | 1 |

### Preserved inputs and assertions

- Distributor cases keep the exact metric names, labels, float values,
  metadata family/type/help/unit, RW2 symbol order and references, query strings,
  one-hour evaluation range and 5m step. They assert exact query matrices and
  metadata responses. RW2 written counts remain exactly 1/1/4/3 samples,
  zero native histograms and zero exemplars for the first four cases. The
  added native cases preserve schema -1 and -53, integer bucket deltas
  `[150, -100]`, the custom bound 0.1, count 200/sum 1000 and exact bucket
  boundary rules. The exemplar case preserves `test=test`, value 123 and its
  source timestamp. Written counts are checked (also as additional controls
  where upstream did not specify a count); RW1 must not return RW2 counts.
  Label scenarios retain the exact unsorted label order, `empty=""`, duplicate
  empty string in the RW2 symbol table, label references, sample 100 and exact
  query output identities. The invalid-symbol case retains the nonempty first
  symbol, references `[0, 1]`, counter metadata/help/unit, HTTP 400 and all three
  zero written-count expectations. Upstream specifies no error-body text for
  that case; the port does not invent a matching Mimir error string.
- Ingester cases keep `foobar`, `timestamp(foobar)`, `not_foobar`, all six
  100/110/120/130/140/150 samples, 10m spacing, the -2s unaligned timestamps,
  a one-hour evaluation range and the empty-result expectations. Source
  timestamps from `timestamp()` are checked, not evaluation timestamps.
  Histogram cases use generator indices 1..6, both delta-integer and absolute
  floating count encodings, schema 1, zero threshold 0.001, symmetric sparse
  positive/negative spans `[{0, 2}, {1, 2}]` and all nine exact output buckets.
  Mixed-type lifetime transitions and the scalar-wins same-time collision
  expectation are retained. This revision has only one unaligned table case
  (scalar samples), already included; no invented histogram cases are counted.
- Discovery keeps `series_1`/`series_2`/`series_3`, the same-name extra labels,
  relative timestamps (0/2/4 block periods), every selector and every expected
  identity/dictionary. Bounds stay inclusive, including a stored sample exactly
  at the last window's end. These are sample-backed results, not instant-vector
  discovery limited by a five-minute lookback.
- `TestHashCollisionHandling` keeps `A="K6sjsNNczPl"` then
  `A="cswpLMIZpwt"`, `__name__="fingerprint_collision"`, the wire label order
  (`A` before `__name__`), values 0 and 1 at the same timestamp, tenant `user-0`
  on both requests, the exact query and the complete ordered two-series vector.
  No sorting, count-only assertion or Pulse-generated result oracle replaces
  upstream's full-vector equality.
- The scalar/range frontend cases retain tenant `user-0`, `series_1`, both
  exact queries and complete scalar/matrix responses. The source random float
  is frozen to 0.5 and the source clock to the harness timestamp. They replay
  one portable input, not Mimir's multi-user/concurrent deployment permutations,
  histogram users or ring/frontend synchronization. The scalar case is a
  pre-existing-behavior control; the raw range result closes a reproduced gap.
- Expected successful responses come from the upstream tables and assertion
  rules, never from querying Pulse to regenerate an oracle. Sorting the
  histogram's two bucket series ignores response ordering only; every
  identity/value is exact.
  Invalid range requests retain upstream HTTP 400, `status=error` and
  `errorType=bad_data`; their diagnostic text explicitly uses Pulse's existing
  message, not an upstream error-message parity oracle.

### Histogram oracle provenance

[`pkg/util/test/histogram.go`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/pkg/util/test/histogram.go#L20-L104)
delegates `GenerateTestHistogram` and `GenerateTestFloatHistogram` to vendored
[`tsdbutil/histogram.go`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/vendor/github.com/prometheus/prometheus/tsdb/tsdbutil/histogram.go#L39-L128).
`GenerateTestSampleHistogram` supplies explicit decoded bounds and boundary
rules, so no Go fixture generation or Pulse-derived oracle was needed. The
Elixir test transcribes those input formulas and that expected geometry,
including the shortest-roundtrip spellings of `18.4 * float64(i+1)` sums.

## Explicit adaptations and omissions

1. Upstream wall-clock origins are replaced with Unix second `1700000000`.
   Upstream `generateFloatSeries` aliases the vendored
   [`e2e.GenerateSeries`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/vendor/github.com/grafana/e2e/util.go#L132-L179),
   which chooses `rand.Float64()`. Its random value is frozen to 0.5 wherever
   used. Its unasserted `trace_id=1234` exemplar is omitted. The fixed clock is
   a reproducibility adaptation, not a Pulse-derived expected value.
2. Mimir's `/prometheus/api/v1/*` and remote-write push paths become Pulse's
   `/api/v1/*` and `/api/v1/write`. Successful pushes assert Pulse's documented
   **204**, not Mimir's **200/202**. Read status and successful envelopes remain
   exact; invalid range-query diagnostic text is adapted as documented below.
3. Discovery freezes the block period to 60s (the helper accepts this as a
   parameter). `series_2` uses the upstream generated native histogram again,
   not a scalar substitute. Its generator's random integer is frozen to 1,
   retaining exact source-generated geometry. The unasserted `trace_id=1234`
   exemplar from
   [`generateHistogramSeriesWrapper`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/e2ehistograms/e2ehistograms.go#L55-L108)
   is omitted. This proves these sample-backed discovery results with native
   histogram input, not TSDB-tier boundary parity.
4. Docker, Consul, Kafka, MinIO provisioning, quorum/ring readiness, TSDB head
   compaction/shipping, store-gateway synchronization, cache counters,
   ingester gRPC status assertions, query-engine and caching-unmarshal flag
   permutations are not translated into pretend equivalents. Pulse has none
   of those service boundaries. Each test owns a loopback S3 protocol stub,
   real native object-store HTTP client, manifest processes, native Parquet
   writes and metric reads. Assertions check actual `PAR1` objects. Public
   requests enter the real Phoenix endpoint with `Phoenix.ConnTest`, not a
   network Grafana/Prometheus client.
5. Discovery requests also run as form POSTs with the same expected response;
   these 29 additional transport controls are not counted as upstream scenarios.
   Tenant-isolated metadata reads and durable metadata-object assertions are
   likewise additional controls.
6. The extra Pulse lookback control covers decimal/exponent seconds, nested
   `timestamp()`, subqueries, offset, a left-open boundary, unchanged explicit range
   windows, form POST, request isolation and malformed/overflow rejection.
   A separate evaluator batch regression checks per-source isolation and invalid
   internal options. These are **not** upstream cases. Pulse deliberately
   requires a positive override; zero/negative values reject rather than using
   upstream Prometheus's nonpositive-default fallback.
7. Two additional Pulse collision controls (RW1/RW2) put histograms before
   scalar samples in separate same-label entries. They check scalar precedence,
   exemplar preservation, written counts and exact keyed retries through S3.
   Deliberately corrupting the test-owned object at the same deterministic key
   must return 409 without replacing any object or manifest. These are not
   upstream cases. A different normalized caller body derives a different key,
   as documented, rather than reserving an exclusive idempotency token.
8. Sixteen additional Pulse label controls are separate from upstream scenarios:
   normalized same-label merging/keyed retries in RW1/RW2, and seven partial-write
   invalid-label variants in each version. Variants cover differing and identical
   duplicate values, duplicates with one/both values empty, duplicate metric-name
   labels, and an empty label name with nonempty/empty value. Each invalid series
   carries two points before a valid sibling is ingested; both points must count
   as rejected. RW1 retains its documented 204/rejected header and RW2 its
   400/rejected/written-count response. Public query/discovery and actual S3 rows
   must contain only valid surviving identities. These controls do not assert
   full Mimir name-validation/tenant-policy parity.
9. `TestHashCollisionHandling` uses the same fixed wall clock as the harness:
   source and evaluation time are `1700000000` seconds (`1700000000000` ms on
   the RW1 wire). Upstream's `Push` is RW1, so no invented RW2 variant or extra
   control test is added. The existing request helpers preserve `user-0` without
   changing the other scenarios' `user-1` default. Upstream fingerprints and
   fast fingerprints collide for these labels; Pulse uses a different
   StableHash/xxhash64 identity and these two identities **do not collide**.
   This is a faithful public request/result replay, not proof of Pulse hash
   collision handling. It does not emulate Mimir's distributor/ingester/querier
   deployment or ring synchronization.
10. The eight invalid range requests retain exact expressions, malformed
    literals, relative bounds and numeric-second steps from the raw client.
    They use the harness's fixed clock and existing `user-1` tenant, rather
    than upstream's `fake` / `query-sharding` tenants and wall clock. The 50
    seeded metric series are omitted for these eight pre-storage rejections,
    but retained for the separate execution-error replay below. Tenant policy,
    sharding, remote-execution and client permutations are omitted.
    Five request-parameter rows and the top-level range-result row now retain
    upstream diagnostic text exactly; the other two expression rows retain
    Pulse's generic message. This is **not
    complete upstream error-message parity**. Omitted-resolution subqueries
    and instant top-level range results are now supported. Range-query requests
    still reject range expressions, including the last selected row, even with
    equal bounds. A separate Pulse control checks GET/form POST and verifies
    that invalid result types cause no provider requests.

## Gaps reproduced and fixed

Before the runtime change, **17/19** selected scenarios passed. The two explicit
lookback scenarios failed at their first instant query with **HTTP 400**:
`{"status":"error","errorType":"bad_data","error":"Invalid or unsupported query parameters."}`.
No failure was skipped or converted into a success expectation.

The query endpoints now admit bounded positive `lookback_delta` and pass it to
the evaluator. Plain selectors, `timestamp()` and nested selectors use the
request's value; explicit range vectors retain their own windows. Batch sources
reset their own default and keep the same aggregate admission/budgets. That
lookback change has no storage format, native ABI, keyed-byte or global
configuration changes.

The follow-up added four ingester cases and restored discovery's native input.
Before the collision fix, **23/24 tests passed** (22/23 upstream scenarios plus
the existing Pulse control). Integer geometry, floating geometry, mixed-type
transitions and restored discovery passed unchanged. The same-time collision
case failed: Pulse returned histogram index 3 at step 2, losing scalar 120,
where upstream expects the scalar and no histogram at that timestamp.
No assertion was weakened or skipped. Request-local remote-write normalization
now omits native histograms shadowed by same-label/same-time floats, after
native validation/admission and before immutable append. It does not change
global query conflict resolution, add cross-request state, or bypass keyed
verification. Only colliding requests change normalized caller hashes/segment
bytes; drain affected retries and replace all receivers as described in
[`docs/querying.md`](../../../../../docs/querying.md#native-histograms).
The five histogram/exemplar distributor replays were coverage-only gaps and
needed no runtime changes. That phase passed 31 tests: 28 upstream replays and
three Pulse controls.

The label/symbol follow-up added five upstream replays and sixteen Pulse
controls. Before its runtime changes, **45/52 tests passed** (30/33 upstream
replays and 15/19 Pulse controls). Both wrong-label-order cases already passed.
Both empty-label cases returned `empty: ""` in query results, rather than
omitting it; normalized same-label entries failed to merge and retained an
otherwise shadowed histogram. The invalid RW2 symbol table was acknowledged
204 instead of rejected 400. RW1 empty-name labels before their point fields
reported one rejected record instead of both supplied points.

Native remote-write normalization now validates UTF-8, empty names and duplicate
names before dropping empty-valued labels, and does so before hashing or BEAM
materialization. Invalid RW1 names are checked after all points have been read
so rejection counts are complete. A nonempty reserved first RW2 symbol rejects
before samples or metadata can escape; the controller reports zero RW2 written
counts on this `invalid_protobuf` path. Invalid-series partial-write status
distinctions, raw admission bounds and exact keyed publication remain unchanged.
There is no stored-format/native tuple change. Empty-valued labels change caller
hashes, series hashes and encoded bytes, so drain affected retries and replace
all ingress application/native pairs before resuming them; historical rows are
not rewritten. See the Prometheus section of
[`docs/querying.md`](../../../../../docs/querying.md#prometheus-api).

That selection passed **52 tests: 33 upstream replays and 19 Pulse
controls**, with no skips. Two additional native unit tests check canonical
label identities and an unused but invalid first symbol; existing native invalid
label tests also cover complete rejection counts and validation before removal.

### UTF-8 name-validation increment

The six new replays select only Mimir's `model.UTF8Validation` branch. Pulse's
remote-write decoder already validates nonempty UTF-8 label names and UTF-8
values; no legacy-versus-UTF-8 configuration knob is introduced. Mimir's
`model.LegacyValidation` branch, including its two UTF-8 rejection rows per
wire version, is deliberately **not ported**. The row named `legacy metric name`
is an ASCII input under UTF-8 validation, not evidence of a legacy policy mode.

All three rows preserve exact labels, RW2 symbols/references, sample 100,
query strings and expected identities. The one-hour query and 5m step end at
the **sample timestamp**, unlike earlier distributor rows which sample at the
start. Here `queryEnd = 1700003600` and `queryStart = 1700000000` replace the
wall clock. The UTF-8 counter's family `utf_metric😀C`, help `some helpC` and
unit `someunitC` are retained in both encodings; the other rows send no metadata.
Metadata readback and written-count checks are additional Pulse assertions,
not new upstream cases. Success remains Pulse HTTP 204 instead of Mimir 200.

Before the parser change, the expanded service file passed **56/60 tests**:
**37/39 upstream replays** and **19/21 Pulse controls**. Both UTF-8 metric rows
successfully ingested but their exact `{"utf_metric😀C"}` range query failed
HTTP 400 with `bad_data` / `Invalid or unsupported query parameters.` Both new
selector controls failed at their first query with the same response. The
ASCII-name and UTF-8-label rows already passed unchanged. The accompanying
parser suite passed **13/15 tests**; shorthand parsing and the newly exercised
64-quoted-matcher acceptance failed. Combined baseline: **69/75 passed**, six
failures, with no skipped or weakened assertions.

The owning parser boundary now decodes quoted UTF-8 matcher names and bare
quoted metric names inside braces into the existing matcher AST. It retains
ASCII unquoted identifiers, existing string escaping, native regex validation,
64-matcher/1024-byte-regex/16KiB-query bounds, and nonempty-selector checks.
Empty quoted names and multiple bare metric names reject, including an outer
name plus an inner bare name. Two separately named Pulse public controls cover
RW1/RW2 round trips with escaped/non-ASCII names, all four matching operators,
metric position/whitespace/trailing comma, nonmatches and malformed-query 400s.
Focused parser tests also cover all three quote styles, comments, range
functions, byte/Unicode escapes, invalid UTF-8, matcher budgets and mutated input.

That service selection passed **60 tests: 39 upstream replays and
21 Pulse controls**. Together with the **15 parser tests**, the targeted run
passes **75/75**, with no skips. This is an independently written Elixir parser
change: no upstream AGPL runtime implementation was copied. Ingest, Parquet,
hashes, keyed bytes and native ABI are unchanged; this increment requires no
data migration or keyed-retry draining. Upgrade every query-serving instance
before relying on the new selector syntax behind non-sticky routing. Quoted
UTF-8 grouping/matching-modifier label lists and `label_replace` destination
validation remain outside this selector-only increment.

Validation also ran the complete `test/pulse/promql` directory plus the Mimir
service, Prometheus query/discovery/math and all three remote-write controller
files: **225 passed, one existing optional promtool test skipped** because
`PULSE_PROMTOOL` was unset. `mix compile --warnings-as-errors`, scoped
`mix format --check-formatted` and `git diff --check` passed. The targeted
service/parser replay used `ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mix test`
with both test file paths and `--warnings-as-errors`.

### Fingerprint-collision public replay increment

The additional single upstream scenario passed on the existing runtime:
**1 passed, 60 excluded** for the location-selected baseline, then **61 passed**
for the full service file (**40 upstream replays and 21 Pulse controls**), with
no failures or skips. No runtime changes were needed or made for this increment.
Both runs used `ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix test`
with `--warnings-as-errors`; the baseline selected
`test/pulse_web/controllers/mimir_service_conformance_test.exs:630`, and the
full run used that file without a location suffix. Scoped
`mix format --check-formatted` and `git diff --check` also passed.

The port follows the pinned client's
[`NewClient` / `Push` / `PushRW1`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/e2emimir/client.go#L105-L199),
[`Query`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/e2emimir/client.go#L321-L329),
[`prompbLabelsToMetric`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/util.go#L175-L183)
and
[`TimeToMilliseconds`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/vendor/github.com/grafana/e2e/util.go#L114-L130)
helpers. SHA-256 provenance from the checkout at the pinned revision:

```text
42c795bf77896661476901f67d7b29735fb91a88c1ad2694956d3eae92b1edd7  integration/querier_test.go (whole file)
efa9b6515031cc168538045601d1f694e11044eaaad56b0533e6338bf2ee898f  integration/querier_test.go (sed -n '983,1068p', including final newline)
1a699a91a65da204ee8cff7f88da64fc91c6b8e13b29f28c7c2c1b28efa0d537  integration/e2emimir/client.go (whole file)
```

A separate native RW1 decoder diagnostic confirmed distinct signed `series_id`
values `5441807118388983113` and `-497404242484687497` for the two label sets.
These are diagnostic Pulse identities, not the upstream expected-result oracle
or an additional scenario. The test continues to use the owned HTTP S3 fake,
native object-store client and native Parquet writes/reads, and checks a real
`PAR1` artifact. It does not establish a collision in Pulse or deployed-client
compatibility.

### Invalid range-query read-only coverage increment

The selected rows are the seven contiguous
[`maximum resolution error` through `wrong timestamp in start`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/query_frontend_test.go#L770-L838)
entries and the later
[`range query with range vector`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/query_frontend_test.go#L874-L880)
entry. Each sends one GET to `/api/v1/query_range`. With fixed
`N = 1700000000` Unix seconds, the exact inputs are:

| Upstream row | Query | Start | End | Step literal |
| --- | --- | --- | --- | --- |
| maximum resolution error | `unknown` | N - 86400 | N | `1` |
| negative step | `unknown` | N - 3600 | N | `-60` |
| unknown function | `unknown(up)` | N - 3600 | N | `60` |
| range vector instead of instant vector | `sum by(grpc_method)(grpc_server_handled_total{job="cortex-dedicated-06/etcd"}[1m])` | N - 3600 | N | `60` |
| start after end | `unknown` | N | N - 3600 | `60` |
| wrong duration specified in step | `unknown` | N - 3600 | N | `123notafloat` |
| wrong timestamp in start | `unknown` | `depths-of-time` | N | `30` |
| range query with range vector | `(sum(rate(up[1m])))[5m:]` | N - 3600 | N | `60` |

The client's
[`QueryRangeRaw`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/e2emimir/client.go#L343-L358)
URL-escapes the expression and formats `step.Seconds()` as a decimal string,
so the negative step remains `-60`, not a synthetic `-1m` duration.
[`FormatTime`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/e2emimir/client.go#L1454-L1457)
formats Unix seconds plus fractional nanoseconds; the fixed second-aligned
origin therefore produces integer-second bounds. The two malformed-parameter
rows bypass `QueryRangeRaw` but still use that time helper. The actual
[`DoGetBody` / `doRequest`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/e2emimir/client.go#L1391-L1452)
path sends GET with `X-Scope-OrgID` and reads the full body. The harness retains
that method/header behavior via its existing connection helper, with the
documented path and tenant adaptations.

All eight retain upstream **HTTP 400**, `status=error`, `errorType=bad_data`.
The five parameter rows and top-level range-result row now assert Mimir's complete
original envelopes, including their diagnostic strings, as detailed below. The two
expression rows (`unknown function`, `range vector instead of instant vector`)
still assert this complete adapted Pulse
envelope, including no extra keys, rather than a partial-map match:

```json
{"status":"error","errorType":"bad_data","error":"Invalid or unsupported query parameters."}
```

Initially `(sum(rate(up[1m])))[5m:]` rejected because omitted resolutions were
unsupported. The grammar and result-type batches now support them inside range
functions and as top-level instant results. The selected range request still
rejects, now with `{:error, :range_result_for_range_query}` and the default
upstream diagnostic below. Other expression-diagnostic parity remains a gap.
No selected row unexpectedly succeeded or returned a different HTTP status.

Each test uses the existing async, owned loopback S3 provider/native
object-store/manifest/Parquet context without application or OS environment
mutation. Its provider request list is empty before and after the invalid GET:
no LIST, HEAD, GET, PUT or DELETE is issued. These cases intentionally do not
seed data or create Parquet objects; existing valid scenarios continue to
exercise native Parquet writes/reads. The initial coverage-only increment needed
no runtime changes. The parameter-diagnostic follow-up below adds runtime
validation and separately named controller controls, preserving the existing
UTF-8 and fingerprint additions.

SHA-256 provenance from the clean Mimir checkout at the pinned revision:

```text
e3efbd42ededf70a5b4ec1af7c1bc0ac2929b85401bbae0888ad39c225076b52  integration/query_frontend_test.go (whole file)
63a947320eee539ea4f5abd8e48994a22ea252ee501d14c50115bf293d38534a  integration/query_frontend_test.go (sed -n '566,905p', including final newline)
b27b20794647e5bb2780130acbddb0e105c293e496b9cba03d5ec4ac47fe63ca  integration/query_frontend_test.go (sed -n '770,838p;874,881p', including final newlines)
1a699a91a65da204ee8cff7f88da64fc91c6b8e13b29f28c7c2c1b28efa0d537  integration/e2emimir/client.go (whole file)
```

The pre-increment baseline (seed `255007`) ran **61 tests: 59 passed, two
failed**, with no skips. Existing `TestDistributor / simple summary / v2` and
`TestDistributor_NameValidation / utf8 / utf8 metric name / v2` failed their
write assertion with **503 instead of 204**. The captured failures did not
include response bodies, so their storage failure cause is unverified; no
expectation or runtime behavior was changed to hide them. The expanded full
file rerun with the same seed passed **69/69: 48 upstream replays and 21 Pulse
controls**, including both previously failing writes and all eight new
invalid queries. This is a coverage-only increment on the existing runtime,
not a claimed runtime fix for those baseline write failures.

The location-selected run at `mimir_service_conformance_test.exs:645` also
passed **8/8, 61 excluded**, with no skips, exercising the complete envelope
and zero-provider-request assertions for every added row. Final scoped
formatter and whitespace checks passed. Commands actually run (each prefixed
with `ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec --`):

```sh
# Pre-increment baseline: 59/61 passed, two existing write-status failures.
mix test test/pulse_web/controllers/mimir_service_conformance_test.exs --warnings-as-errors
# Expanded full file, same seed: 69/69 passed.
mix test test/pulse_web/controllers/mimir_service_conformance_test.exs --warnings-as-errors --seed 255007
# Selected invalid requests: 8 passed, 61 excluded.
mix test test/pulse_web/controllers/mimir_service_conformance_test.exs:645 --warnings-as-errors --seed 255007
mix format --check-formatted test/pulse_web/controllers/mimir_service_conformance_test.exs
git diff --check -- test/pulse_web/controllers/mimir_service_conformance_test.exs test/fixtures/promql/mimir/services/README.md
```

### Five exact request-parameter diagnostics

The existing five rows now preserve the full original `expJSON` objects from
`TestQueryFrontendErrorMessageParity`, not merely HTTP status or selected keys:

| Row | Exact `error` value (the other fields remain `status=error`, `errorType=bad_data`) |
| --- | --- |
| maximum resolution error | `exceeded maximum resolution of 11,000 points per timeseries. Try decreasing the query resolution (?step=XX)` |
| negative step | `invalid parameter "step": zero or negative query resolution step widths are not accepted. Try a positive integer` |
| start after end | `invalid parameter "end": end timestamp must not be before start time` |
| wrong duration specified in step | `invalid parameter "step": cannot parse "123notafloat" to a valid duration` |
| wrong timestamp in start | `invalid parameter "start": cannot parse "depths-of-time" to a valid timestamp` |

No selected inputs, expressions, relative bounds, methods, tenants, fixed clocks
or storage assertions changed. All eight rows still prove zero provider requests.
The two remaining expression diagnostics are explicitly adapted, not exact;
the top-level range-result follow-up below supersedes its earlier generic error.

The independently written range-request validation attributes timestamp failures
to their field, rejects reversed bounds before parsing step, distinguishes numeric
nonpositive steps from malformed durations and reports the existing point limit.
Authorization still runs first. Exact decimal/exponent seconds, RFC3339 timestamps,
nanosecond rounding, admitted duration grammar and evaluator/query budgets remain
unchanged. In particular, Pulse's existing ceiling is **11,000 inclusive evaluation
points**: 10,999 intervals succeed; 11,000 intervals reject. The pinned upstream
helper checks `> 11000` intervals and can admit an extra endpoint; this boundary
is deliberately **not** adopted. Numeric overflow/nonfinite and signed-unit
duration diagnostics are not claimed to match upstream. Instant-query, timeout,
lookback and expression diagnostics retain their existing adaptation.

Reflected values use the existing Go-compatible quoting, capped at 128 input bytes
before quoting with an explicit `...(truncated)` marker for longer values.
Non-string terms are described without inspecting nested contents. These are
bounded diagnostic adaptations, not a new timestamp/duration grammar. No upstream
runtime implementation was copied; storage, keyed bytes and native ABI are
unchanged. Upgrade query-serving applications for consistent diagnostics.

Three separately named tests in `prometheus_query_controller_test.exs` cover GET
and real URL-encoded form POST, field/ordering precedence, zero/negative/sub-ns
steps, equal bounds, exact point-limit boundaries, successful numeric/unit and
RFC3339 inputs, missing/empty/nested/oversized/overflow/nonfinite values, escaped
quotes/backslashes/control bytes/Unicode, unchanged generic errors and denial
before diagnostics. These are local controls, not additional upstream scenarios.

Source helper review used pinned
[`invalidParamError`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/vendor/github.com/prometheus/prometheus/web/api/v1/api.go#L595-L599),
[`queryRange` validation](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/vendor/github.com/prometheus/prometheus/web/api/v1/api.go#L1079-L1105),
[`parseTime` / `parseDuration`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/vendor/github.com/prometheus/prometheus/web/api/v1/api.go#L2912-L2948)
and the raw-client/time helpers linked above. SHA-256 hashes (each `sed`
selection includes its final newline):

```text
e3efbd42ededf70a5b4ec1af7c1bc0ac2929b85401bbae0888ad39c225076b52  integration/query_frontend_test.go (whole file)
c687b25759978e72d2fe13dab683f86734648808f18b52605b2102227637785d  integration/query_frontend_test.go (sed -n '770,785p;802,838p')
ae172cc1cc506fa8ceb7f62b5bf0d79a871407ec616451bdaec646e982013f16  vendor/github.com/prometheus/prometheus/web/api/v1/api.go (whole file)
21386994b95271af81f3f972d4436ce6cf8fffe29a9f88b43c2adfbf6883bcbf  vendor/github.com/prometheus/prometheus/web/api/v1/api.go (sed -n '595,599p;1079,1105p;2912,2948p')
1a699a91a65da204ee8cff7f88da64fc91c6b8e13b29f28c7c2c1b28efa0d537  integration/e2emimir/client.go (whole file)
189d2b5a7fada5ae508e55122af28a3fb09a06bbf18d361e2fe60a1b5651d308  integration/e2emimir/client.go (sed -n '343,358p;1454,1457p')
```

Before runtime changes, the strengthened selection plus controller suite failed
**6/20** tests at seed **1201**: all five upstream parameter rows and the local
diagnostic control returned the old generic text. Fourteen tests passed, 71 were
excluded, and no failures were hidden. The identical selection then passed
**20/20**, 71 excluded. The complete service/controller run passed **91/91** with
no skips. Red/green logs are retained under `.amp/in/artifacts/` as
`mimir-parameter-diagnostics-{red-selected,green-selected,green-full}.log`.
The first attempted location selection landed before the generated upstream
tests and only exercised the controller suite; its separate red log is retained
as `mimir-parameter-diagnostics-red.log`, not counted as the five-row baseline.
Commands used `ERL_FLAGS='+S 4:4' mise exec --`:

```sh
mix test test/pulse_web/controllers/mimir_service_conformance_test.exs:1127 test/pulse_web/controllers/prometheus_query_controller_test.exs --warnings-as-errors --seed 1201
mix test test/pulse_web/controllers/mimir_service_conformance_test.exs test/pulse_web/controllers/prometheus_query_controller_test.exs --warnings-as-errors --seed 1201
```

After the additional malformed/missing/unchanged-error controls, the complete
`test/pulse/promql` directory plus both controller files passed **229 tests**;
the existing optional promtool conformance test was skipped because
`PULSE_PROMTOOL` was unset. This run used seed 1201 and is retained in
`mimir-parameter-diagnostics-green-regression.log`. Compile-with-warnings-as-errors,
scoped formatting and scoped `git diff --check` passed; their output is retained
in `mimir-parameter-diagnostics-checks.log`.

```sh
# Same ERL_FLAGS / mise exec prefix as above.
mix test test/pulse/promql test/pulse_web/controllers/mimir_service_conformance_test.exs test/pulse_web/controllers/prometheus_query_controller_test.exs --warnings-as-errors --seed 1201
mix compile --warnings-as-errors
mix format --check-formatted lib/pulse_web/controllers/prometheus_query_controller.ex test/pulse_web/controllers/prometheus_query_controller_test.exs test/pulse_web/controllers/mimir_service_conformance_test.exs
git diff --check -- lib/pulse_web/controllers/prometheus_query_controller.ex test/pulse_web/controllers/prometheus_query_controller_test.exs test/pulse_web/controllers/mimir_service_conformance_test.exs test/fixtures/promql/mimir/services/README.md
```

### Query-formatting increment

The added service port preserves `TestFormatQueryAPIEndpoint`'s expression,
GET method, HTTP 200 and exact formatted string. Only the existing route,
tenant and owned ConnTest harness adaptations apply. There is no input data or
wall clock to freeze. The source only decodes `data`; the shared Pulse helper
additionally checks the success envelope and the test verifies zero provider
requests. This is not a Parquet read/write test or a live Mimir execution.

Before runtime changes, the isolated upstream case failed at seed 111:
`count(up)by(foo)` was returned unchanged, not `count by (foo) (up)`.
The new independently written Elixir formatter prints Pulse's validated AST,
preserving evaluation order and selector order. It handles all currently
supported node types without adding query syntax, storage or native state.
Input and formatted output must both fit the existing 16 KiB query ceiling.
Comments/redundant parentheses are removed; output remains single-line and
does not claim upstream multiline, matcher-sorting or redundant-syntax parity.
All query-serving apps must upgrade for consistent formatting; no native ABI,
stored format, keyed bytes, migration or retry drain changes are involved.

Three additional Pulse tests and the extended existing formatter check in
`compat_controller_test.exs` cover GET/form POST, exact expected strings,
idempotence, all 450 two-operator/parenthesization combinations, subqueries,
offsets, vector matching, UTF-8/control-character quoting, special metric names,
signed zero, finite float extremes/subnormals and fail-whole input/output-size
checks. They compare successfully reparsed trees, not two parse errors. The
authentication control rejects an unauthorized malformed query before parsing.
These are local controls, not additional upstream ports. The complete Mimir
service plus compatibility-controller replay passed **84 tests**, seed 113.

Pinned source SHA-256 hashes:

```text
7f7e61388811ca343fdd2c6d8ec859eb1b74b41bba1170c4a2a63f98dce53c77  integration/api_endpoints_test.go
ceff996c20433ee86378330cfa02d27b8ec58ab213158af7b6027137257cadde  selected lines 89–112, including final newline
```

### Grouped vector execution-error increment

The complete portable public scenario selects the `execution error` row at
[`query_frontend_test.go:865–872`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/query_frontend_test.go#L865-L872),
with its full [50-series seed loop at lines 672–687](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/query_frontend_test.go#L672-L687).
The exact expression is:

```promql
sum by (group_1) (metric{unique=~"0|1|2|3"}) * on(group_1) group_right(unique) (sum by (group_1,unique) (metric{unique=~"0|1|2|3"}))
```

All 50 distinct RW1 pushes retain `metric`, `unique=i` and `group_1=i%2`,
including the 46 series excluded by the query. Each push traverses HTTP ingest,
native encoding and actual Parquet/S3 publication. The query retains GET,
`start=N-60`, `end=N`, `step=60`, HTTP **422** and this complete original envelope,
without adapting the diagnostic:

```json
{"error":"multiple matches for labels: grouping labels must ensure unique matches","errorType":"execution","status":"error"}
```

The generator alias is
[`integration/util.go:28–32`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/integration/util.go#L28-L32);
[`e2e.GenerateSeries:132–179`](https://github.com/grafana/mimir/blob/dd039cdd4ba466adb5d28280bf1b8a374a98432e/vendor/github.com/grafana/e2e/util.go#L132-L179)
adds the metric name before the supplied labels, generates one random float
and an unasserted exemplar, and uses `TimeToMilliseconds` (lines 114–130).
As in the earlier ports, the float is frozen to **0.5**, the clock to
**1700000000**, and the unasserted `trace_id=1234` exemplar is omitted. The seed
retains separate pushes instead of merging them into one synthetic write. The
upstream `fake` and sharded tenants collapse to the harness's `user-1` tenant;
the three frontend/sharded-frontend/querier clients and both remote-execution
modes collapse to one public Pulse endpoint. Push success is 204 rather than
200. No tenant policies, max-sample quota, blocked queries, remote read or
deployment/sharding machinery are simulated. Adjacent unported table rows
depend on those deliberately excluded features, not another portable scenario.

Before the runtime fix, both added tests failed (seed **901**, **0/2 passed,
77 excluded**). The selected upstream request already returned HTTP 422 and
`execution`, but its diagnostic was the generic
`Vector matching produced ambiguous or duplicate series.` The separately named
Pulse control reached the same diagnostic mismatch after its successful-group
assertions. Earlier test-authoring runs exposed a sigil delimiter typo and
incorrect expected ordering in the new local control; both were corrected
before this red baseline, without changing runtime or upstream expectations.

The independently written runtime change distinguishes same-matching-group,
same-final-label collisions from an ambiguous one-side index and from generic
duplicate result identities. Checks occur after pair filtering and restart at
every evaluation step. The controller exposes the original upstream message
only for the new specific reason; unrelated duplicate/ambiguous errors retain
their existing diagnostics. No upstream runtime code was copied. This changes
error classification/text, not successful samples, storage/keyed bytes, native
ABI or resource ceilings. Upgrade all query-serving applications for consistent
errors behind non-sticky routing; no data migration or retry drain is needed.

The local control covers both group directions, omitted versus explicit include
labels, one retained sample per group, two valid evaluation steps, the empty
step before ingestion, the exact left-open five-minute lookback boundary,
filtered-out and unmatched pairs, false-valued `bool` collisions, and generic
error ownership. Collision queries replay instant/range GET and form POST,
including a range whose earlier step is empty: execution fails whole, never
publishes partial results. These are local controls, not more upstream ports.

Validation, with `ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec --`:

```sh
# After fix: 2 passed, 77 excluded, seed 901.
mix test test/pulse_web/controllers/mimir_service_conformance_test.exs:994 test/pulse_web/controllers/mimir_service_conformance_test.exs:1017 --warnings-as-errors --seed 901
# Complete service file: 79 passed, no skips.
mix test test/pulse_web/controllers/mimir_service_conformance_test.exs --warnings-as-errors --seed 901
# Expanded regression run: 538 passed; one existing optional promtool test skipped.
mix test test/pulse_web/controllers/mimir_service_conformance_test.exs test/pulse/promql test/pulse_web/controllers/prometheus_query_controller_test.exs test/pulse_web/controllers/prometheus_math_conformance_test.exs --warnings-as-errors --seed 902
mix compile --warnings-as-errors
mix credo --strict lib/pulse/promql/operations.ex lib/pulse_web/controllers/prometheus_query_controller.ex test/pulse_web/controllers/mimir_service_conformance_test.exs
mix format --check-formatted lib/pulse/promql/operations.ex lib/pulse_web/controllers/prometheus_query_controller.ex test/pulse_web/controllers/mimir_service_conformance_test.exs
```

Scoped strict Credo checked all three files with no issues. The optional
promtool check requires an externally configured executable; the default service
replay remains offline with no Go, Docker or network dependency. SHA-256 hashes
of the pinned inputs (range selections include their final newlines):

```text
e3efbd42ededf70a5b4ec1af7c1bc0ac2929b85401bbae0888ad39c225076b52  integration/query_frontend_test.go (whole file)
a424e9c5315231d4cd6d338572a470f14161cc0004e88ae788817ccf9222e12b  integration/query_frontend_test.go (sed -n '672,687p;865,872p')
04c2be3bbbd201741eae3097001129e67c9999acccd85b7e8232bc06bd38e41d  integration/util.go (whole file)
6acb197a8f9bb97af58e632fa1543bcd30ea7a36634dae3f79e9d050b0503b53  integration/util.go (sed -n '28,32p')
6f3d2dfd92e26d7eb8f620da253ea7b0fa7d9627729968b0ed160a6c66f77ecc  vendor/github.com/grafana/e2e/util.go (whole file)
085a6cade8a5da80c74d361757d5132dc4312cac4f01cc8cb674b823d827ef72  vendor/github.com/grafana/e2e/util.go (sed -n '114,179p')
e9f0db4655abd580e7efea236d4843774990c62d13fc5e035a0160cfef618e65  vendor/github.com/grafana/e2e/util.go (sed -n '132,179p')
```

The service source retains the existing AGPL-3.0-only/Cortex Apache-2.0
attributions. The vendored Grafana e2e generator is Apache-2.0, as recorded in
its pinned `vendor/github.com/grafana/e2e/LICENSE`; the existing
`LICENSE-Prometheus` contains that license text.

Remaining service-suite gaps include exemplar age/disabled policies and histogram
downscaling under tenant overrides, broader label/name-validation and partial-write
permutations, HA/relabel/tenant configuration, UTF-8 grammar outside selectors, OTLP translation,
remote-read, tenant federation, cardinality analysis, exact upstream printer layout,
streaming transport and Mimir-specific sharding/caching/limits/failure topology.
Passing this selection is not full PromQL, full Mimir service or deployed-client
compatibility evidence.

## Top-level range-vector diagnostic continuation

The original `range query with range vector` row at
`integration/query_frontend_test.go:874–882` retains its query
`(sum(rate(up[1m])))[5m:]`, one-hour range, one-minute step and complete HTTP400
error envelope. It now asserts the default engine's exact message:

```json
{"error":"invalid parameter \"query\": query expression produces a range vector, but expression for range queries must produce an instant vector or scalar","errorType":"bad_data","status":"error"}
```

The same source also specifies an MQE variant without the `invalid parameter`
prefix. This port selects the default variant, not both contradictory messages.
Whole-source SHA-256 remains
`e3efbd42ededf70a5b4ec1af7c1bc0ac2929b85401bbae0888ad39c225076b52`.
No input or original expectation is rewritten, and no new upstream scenario is
counted. The existing local result-type control additionally covers named and
label-only ranges, parentheses, anchors, explicit/default-resolution subqueries,
GET/form POST and equal/multiple evaluation bounds, with zero provider requests.
String results keep their existing generic rejection; scalar/vector queries
and instant matrices remain accepted. Authorization still precedes diagnostics.
This is a query-serving application fix with unchanged storage/keyed bytes,
native ABI and resource ceilings. Unknown-function and aggregation-type parser
diagnostics remain explicitly unported.

## Shared hexadecimal regex controls

The separately tagged `:regex_hex_batch` is a local control, not an extra Mimir
integration port. It sends eight distinct label values through remote write and
queries native Parquet/S3 with 18 anchored patterns, positive/negative matchers
and GET/form POST. Expected selections come from independently executed Go
answers in [`regex/go-controls.json`](../../../regex/go-controls.json), not Pulse.
The original unanchored Go syntax-table pattern stays in the matcher corpus:
its substring oracle is not a whole-label HTTP expectation.

Both this Mimir wrapper and the analogous Loki wrapper reject valid braced-hex
repetition before the shared guard fix (seed643). Malformed escapes and real
nested/possessive repetitions remain invalid. Six additional Go-checked
malformed lazy-repetition controls must return HTTP400 through GET/form POST.
Before that second fix, `a???` returned HTTP200 and selected the `a` row
(seed646), while valid optional/counted lazy forms remain in the matching
oracles. Native ABI, storage/keyed bytes and resource limits do not change;
all query-serving native artifacts need the
fix. This batch does not establish full Go regex, Tempo or deployed-client parity.

The local `:regex_admission_batch` additionally replays all 53 shared Go
admission patterns over eight remote-written label values through positive/
negative selectors and GET/form POST against native Parquet/S3. Independent
whole-label expectations distinguish 999/1,000/1,001 counts from literal braces.
Invalid patterns must return HTTP400 without storage requests. The separate
[`regex/admission-controls.json`](../../../regex/admission-controls.json)
retains eight original Go parser patterns plus local controls; it is not an
additional Mimir integration export or full regex conformance claim.

The same batch also replays 32 local literal-class cases from
[`regex/class-controls.json`](../../../regex/class-controls.json): `&&`/`~~`
remain ordinary members with negation, folding, POSIX classes and ranges.
All three protocol wrappers reject valid classes before implementation
(seed 669); the affected 370-test suites pass seed 670. Existing scan/work
ceilings and storage/keyed bytes are unchanged; this is not full class grammar.

The wrapper also replays 72 local bracket/range admission cases from
[`regex/range-controls.json`](../../../regex/range-controls.json), retaining
independent whole-label Go answers and no-storage assertions for invalid
patterns. Literal brackets and left-to-right scalar hyphen ranges never become
Rust nested classes or set subtraction. All three protocol wrappers rejected
valid `[[]` before this fix (seed 673). These are local controls, not additional
Mimir integration exports; the three older fixtures and existing limits are unchanged.

The wrapper also replays 44 raw-header and 58 inline-flag cases from
[`regex/name-controls.json`](../../../regex/name-controls.json) and
[`regex/flag-controls.json`](../../../regex/flag-controls.json). Invalid raw
names/headers reject before storage; empty/repeated flags preserve matching
and scope. All three wrappers failed the respective baselines (seeds 680/682).
The shared matcher additionally checks Go's complete anchored capture maps,
including `U`/lazy greediness. These independent Go controls are not additional
Mimir integration exports; see the [regex provenance](../../../regex/README.md).

## Offline replay

```sh
ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix test \
  test/pulse_web/controllers/mimir_service_conformance_test.exs \
  --warnings-as-errors
```

No Go, Docker, live Mimir or externally configured object store is required.
Tests are `async: true`; all runtime configuration and processes are owned by the
test, with no application/OS environment mutation.

## Attribution and licenses

The adapted service test retains **AGPL-3.0-only** attribution to Grafana Mimir.
Its `querier_test.go`, `query_frontend_test.go` and `api_endpoints_test.go` sources also preserve
**Apache-2.0** Cortex provenance, copyright **The Cortex Authors**. The vendored
histogram generator is **Apache-2.0**, copyright **The Prometheus Authors**.
The test header retains these attributions. The parent directory's [`LICENSE`](../LICENSE)
is Mimir's AGPL license; [`LICENSE-Prometheus`](../LICENSE-Prometheus) provides the
Apache-2.0 license text. These adapted tests are not relicensed under Pulse's MIT
license. Runtime changes are independently written Elixir/Rust, with **no upstream
AGPL implementation code** copied into runtime.
