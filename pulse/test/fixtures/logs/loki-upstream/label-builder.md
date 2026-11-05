# Pinned Loki label-builder source fixtures

`label-builder.json` freezes **every Test-prefixed function** in Grafana Loki's
[`pkg/logql/log/labels_test.go`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/log/labels_test.go)
at revision `5aa4b9212d64d723f63b2770452054aa23df114d`, including the final
hash-collision regression after the benchmarks. This is **source extraction,
not observed execution, a builder implementation, public admission evidence or
a Pulse parity claim**. The producer uses only Go's standard library. It never
imports, builds or executes Loki, Prometheus, Pulse or their dependencies.

Original source, test inputs and oracles are copyright Grafana Labs contributors,
AGPL-3.0-only; the adjacent `LICENSE` applies. Three benchmarks are explicitly
excluded and listed by name and source range. Nothing inside the selected tests
or four required helpers is elided.

## Complete scope and counts

`tables` is a complete-function inventory, **not fifteen literal case tables**.
Most functions are imperative assertion/operation sequences. There is one named
literal input table: the hash test's five map entries plus its sixth symbolic
input. There is intentionally no monolithic executable-case count.

| Index | Function | Lines | Source assertion sites |
| ---: | --- | --- | ---: |
| 0 | `TestLabelsBuilder_Get` | 18–52 | 15 |
| 1 | `TestLabelsBuilder_BaseHas` | 54–63 | 3 |
| 2 | `TestLabelsBuilder_GroupedLabels_ByAfterDelete` | 65–79 | 2 |
| 3 | `TestLabelsBuilder_LabelsError` | 81–101 | 7 |
| 4 | `TestLabelsBuilder_LabelsErrorFromAdd` | 103–126 | 7 |
| 5 | `TestLabelsBuilder_IntoMap` | 128–184 | 4 |
| 6 | `TestLabelsBuilder_LabelsResult` | 186–257 | 12 |
| 7 | `TestLabelsBuilder_Set` | 259–352 | 20 |
| 8 | `TestLabelsBuilder_UnsortedLabels` | 354–385 | 3 |
| 9 | `TestHashSorted_MatchesStableHash` | 397–437 | 1 |
| 10 | `TestLabelsBuilder_GroupedLabelsResult` | 439–509 | 16 |
| 11 | `TestLabelsBuilder_GroupedLabelsResult_PipelineError` | 511–585 | 7 |
| 12 | `TestLabelsBuilder_SetErr` | 587–619 | 5 |
| 13 | `TestLabelsBuilder_PreserveErrorIsAnOrdinaryLabel` | 624–661 | 3 |
| 14 | `TestBaseLabelsBuilder_ForLabels_HashCollisionKeepsResultsDistinct` | 778–786 | 2 |
| | **Total** | **15 complete functions** | **107** |

The **107** test-function sites comprise **77 assert/require calls** and
**30 assertLabelResult helper invocations**. The four complete supporting
helpers are `sortLabelSlice`, `assertLabelResult`, `mergeLabels` and
`collidingLabelPair`; they contain **five more assert/require sites**: three in
assertLabelResult and two in collidingLabelPair. Thus there are **112 preserved
assertion/helper-invocation sites**, or **82 primitive assert/require sites**,
depending on the explicitly chosen scope. These are source counts, not runtime
assertion counts or passing parity evaluations.

The normalized event tree has **386 unique event identities**:
142 assignments, 99 operations, 118 assertions, 21 subtests, five loops and
one declaration. It enumerates **15 literal-member iteration identities**:

- **Nine preserve-error identities**: three source subtests, each with
  StreamLabel, StructuredMetadataLabel and ParsedLabel. Their two equality
  assertion sites expand to six assertions; the false assertion site expands
  to three. The source's three assertions are not incorrectly counted as nine
  independent table rows.
- **Six hash-input identities**: `empty`, `single`, `typical`, `empty values`,
  `non-ascii`, and `1KB+ fallback`. The first five retain original literal label
  arrays. The last retains `make([]labels.Label, 50)` and the complete loop body
  with `fmt.Sprintf("label_%02d", i)` / `strings.Repeat("v", 30)` symbolically.
  It does not generate fifty labels, calculate hashes or assert map iteration
  order. The construction loop is the fifth loop event and is not executed.

Expanding only those literal memberships yields **118 assertion events**:
107 + five additional hash identities + six additional preserve-error identities.
The 30 helper invocations remain single events with three declared channels,
not fabricated helper executions. Helpers' own assertion inventories stay separate.

## Schema version 1 and consuming ordinary expectations

- Top-level `sources` contains full-file SHA-256 guards. `tables` contains all
  fifteen complete functions, `source_function_index` (zero-based source order),
  `assertion_calls`, `assertion_call_site_count` and ordered `events`.
- Every original assertion has `source_function` and zero-based
  `source_assertion_index`, shared by its inventory record and expanded events.
  Event `identity` adds the original subtest/iteration path and source line.
  Literal map-member indices are declaration order, never Go map execution order.
- Events distinguish `assignment`, `operation`, `assertion`, `subtest`, `loop`
  and `declaration`. `events` nests subtests; `iterations[].events` nests literal
  memberships. No reset boundary or cached repeated assertion is deduplicated.
- Assertions preserve all arguments, including messages, plus `expected`,
  `actual`, and `expected_resolved`. The latter follows **source-assignment
  references only**, never an operation's result. A reference's `resolution` is
  explicitly `source_assignment_snapshot_not_runtime_evaluation`.
- `kind: labels` has `labels: [{name, value}, ...]`; `kind: string_map` has
  a literal `value` object plus original key/value items. `strings`, `string`,
  `integer`, `boolean`, `category` and `nil` retain corresponding literal data.
  Every normalized string expression also has `bytes_base64`. Empty known
  labels/maps are `[]`/`{}`; nil is a distinct expression kind.
- Literal label normalization admits `labels.FromStrings`, `labels.EmptyLabels`,
  literal `[]labels.Label`/elided hash-table arrays, source string slices and
  their literal `append` construction. It preserves construction order, not
  Loki's sorted iteration/rendering. Only the source-defined ErrorLabel and
  ErrorDetailsLabel string aliases are resolved. Category names remain symbolic
  names, not reimplemented numeric enum semantics.
- `mergeLabels` stays `symbolic_call` with `label_components`. Its three
  immutable expected component lists are available through their references;
  the producer does **not** run a merge/deduplication algorithm or invent a flat
  expected list. Original expected String/StableHash calls remain symbolic too.
- GetWithCategory multi-assignments retain `symbolic_tuple_binding` indices
  and the source call, so Get's literal value/category/boolean assertions remain
  traceable to the immediately preceding read and operation history.
- Operation calls retain normalized argument expressions. Set, Add, Del, SetErr
  and SetErrorDetails have named `parameters`; grouping constructors expose
  `groups`, `parser_key_hints`, `without` and `no_labels`. Reset remains a
  symbolic call. Local `newBuilder` / `buildErrored` function bodies are preserved
  verbatim, not executed or inlined. `buildErrored` calls additionally expose
  their literal-membership category/group/without arguments.
- `supporting_helpers` contains the complete four helper functions and their
  assertion inventories. `collidingLabelPair.literal_label_bindings` exposes
  the **actual two original label sets**: shared `cluster=prod`,
  `namespace=team`, and `pod=39ae2fcfd732c147` versus
  `pod=f35246e8ca75a99b`. Their String-inequality/hash-equality assertions remain
  symbolic; no collision hash was calculated or substituted.
- Fourteen `supporting_declarations` preserve production category definitions,
  constructor/ForLabels/Reset/GetWithCategory/BaseHas/Set/Add/Del/SetErr/
  SetErrorDetails definitions and two error-label constants for provenance,
  never execution. All source records retain `original_go`, `source` and
  `source_range`: one-based line/column positions and zero-based half-open byte
  offsets. Complete function hashes/text include the original trailing newline;
  their AST ranges end just before it. Constant/declaration records without
  function selection cover exactly their AST bytes.

The 118 expanded assertions' resolved expectation kinds are **57 label lists,
four maps, four categories, eleven strings, 23 booleans and nineteen symbolic
calls**. These numbers identify available source data, not executable public
coverage. For example, hash collision and reference-flag assertions also have
literal true/false expectations but remain internal symbolic contracts.

## Public-query boundary and deliberate limitations

Raw `LabelsBuilder.Set(category, ...)` uses Parsed > Structured Metadata > Stream
preference, not collision suffixing. `Add` has separate base-label collision and
error-label behavior. **Do not replay raw Set as public metadata admission.**
Direct `b.add[...]` assignments in UnsortedLabels likewise remain internal
constructor inputs. There is no public query API for mutating stream labels with
SetStream. A consumer may adapt selected successful grouping expectations through
`label_format` only with an explicit category/ownership caveat, not a claim that
the raw API or category-preference semantics are publicly implemented.

Hash/HashSorted/StableHash, String rendering, reference flags, result-cache
identity, reset implementation, raw constructors, hints and direct pipeline-error
injection remain symbolic. Source literal final/category/map/Get expectations
are reusable independently; no symbolic result is promoted into a literal
oracle. In particular, an actual map reference can resolve to its original
empty-map **assignment snapshot** even after IntoMap: that is not an assertion
that the runtime output map is empty. Consume the original assertion's expected
literal map, not a computed actual value.

No public LogQL strings, HTTP requests, synthetic runtime errors, recomputed
builder outputs or passing-compatibility ledger entries are generated here.
Component/public replay, any adaptations and compatibility claims belong to
separate tests and documentation. Normal checked-in JSON replay is Go-, network-
and Python-free.

## Offline regeneration and validation

From the Pulse repository root, with an existing pinned source checkout:

```sh
scratch=$(mktemp -d .amp/in/label-builder.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp test/fixtures/logs/loki-upstream/label-builder-producer.go.txt "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go build -o "$scratch/producer" "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go vet "$scratch/producer.go"
test -z "$(gofmt -l test/fixtures/logs/loki-upstream/label-builder-producer.go.txt)"
"$scratch/producer" /tmp/amp-librarian/grafana__loki > "$scratch/label-builder.json"
cmp "$scratch/label-builder.json" test/fixtures/logs/loki-upstream/label-builder.json
jq '{function_count, literal_table_count, assertion_call_site_count,
     hash_input_count, preserve_error_expanded_identity_count,
     expanded_event_counts}' "$scratch/label-builder.json"
```

Validation performed with Go 1.25.10: offline build/vet, clean gofmt,
byte-identical regeneration; independent source AST inventory of every test and
helper assertion; verification of **4,745 nested source records**, **33 embedded
hashes**, **1,764 literal string/Base64 records**, **537 label normalizations**
and **28 map normalizations** (including repeated references); coverage of all
107 source sites by the 118 expanded assertions; and 386 unique event identities.
Ten disposable negative controls rejected unknown calls, unbound identifiers,
selectors, composite/binary expressions, odd/nonliteral label constructors and
attempts to use hash/String computations as label literals. Independent newline
drift controls on **each of the three guarded source files** rejected extraction
before writing JSON. Symbolic function bodies/geometry remain exact source, not
normalized or interpreted expressions. Disposable validation files were removed;
no Loki/Pulse runtime or HTTP tests were run for this source-only change.

| File | SHA-256 |
| --- | --- |
| `pkg/logql/log/labels_test.go` | `5a3383cd2799117f8f96d1e39f5af42d92f2e07a7e205086bff4d4acaa77eff9` |
| `pkg/logql/log/labels.go` | `2f37f986442f5535402d0bd1503135fb358027e006842eba5e5690c64880e0f8` |
| `pkg/logqlmodel/error.go` | `21816c4294243f16157f6408d92fb0907612a3258333288ab39b3f84bf7a4db5` |
| `label-builder.json` (3,265,019 bytes) | `a2d2f0d184b45e218ca7fdcd6b7142ba7d141ce96d7acda386d5ddc6f618e30a` |
| `label-builder-producer.go.txt` | `88d22421369e0fe638872da79987842eafea0fb910d8aea9aa483606b061bc74` |

## Public replay and adaptation ledger

Source completeness and public compatibility are separate. The shared test
mapping consumes original literal expectations; it is not a builder interpreter
and never generates expected values from Pulse. Operation constructors have no
upstream query-string oracle. Their public translations and synthetic line,
time and one-sample metric controls are authored transport adaptations.

| Complete source function | Public replay / remaining boundary |
| --- | --- |
| Get | All 13 value/category/presence assertions replay through four pipeline snapshots; the two metadata-reference flags remain symbolic. |
| BaseHas | Three presence assertions replay before/after deletion; no separate Go base-builder API is claimed. |
| GroupedLabels_ByAfterDelete | Both original flat label maps replay, including delete followed by parsed re-addition. |
| LabelsError | Raw `SetErr("err", nil)` injection, rendering, hashes and builder immutability remain symbolic. |
| LabelsErrorFromAdd | Original flat labels and all three category maps replay from public structured-metadata ingestion; hashes/String and builder immutability are not public ports. |
| IntoMap | All four original maps replay, including repeated snapshots around the source reset. Go map copying, object/cache identity and reset APIs are not claimed. |
| LabelsResult | Raw category mutations, repeated cached-result checks, error injection, String and hash contracts remain symbolic. |
| Set | All 20 assertions remain source contracts, not ingestion semantics. Raw Set category preference and unsuffixed writes are not public metadata Add. |
| UnsortedLabels | Direct mutation of internal category arrays, sorting and array iteration remain symbolic. |
| HashSorted_MatchesStableHash | All six inputs are retained; no numeric hash or HashSorted implementation is invented. The 50-label geometry stays symbolic. |
| GroupedLabelsResult | All 11 non-error flat grouping snapshots replay; its one arbitrary error injection and four metadata-reference flags remain symbolic. |
| GroupedLabelsResult_PipelineError | All seven direct error/detail-injection results remain symbolic. Actual metric error policies are checked separately, not relabeled as these exact constructor oracles. |
| SetErr | All five direct setter/accessor assertions remain symbolic; exact replacement/clearing of arbitrary injected errors is not claimed. |
| PreserveErrorIsAnOrdinaryLabel | All nine category/group identities retain their original string/absence oracles under real conversion errors. |
| ForLabels_HashCollisionKeepsResultsDistinct | Both original label sets stay distinct through raw and metric HTTP reads. This does not prove a Go cache API or a numeric collision in Pulse's query-key machinery. |

Raw `Set(StreamLabel, ...)` mutations become `label_format` only for flat grouping
observations, whose source does not assert categories. The public write is parsed;
it is **not** advertised as implementing the raw Stream Set API. Metadata Set
inputs used by these successful grouping snapshots do not collide with base
names. Each source reset gets an independent input/window; repeated original
snapshot assertions remain separate, not deduplicated.

The preserve-error replay uses `avg_over_time` (which supports grouping) over
one failed unwrap conversion and explicit `__error__!=""` selection. It preserves
the original pod/preserve-label values and three categories, replacing direct
`SetErr` injection with an actual `SampleExtractionErr`. Its diagnostic text is
not an original oracle. All nine companion queries without error-selection syntax
must fail whole despite the supplied label; the authored zero sample, HTTP 400
and generic failure envelope are Pulse controls, not Go builder expectations.

Four authenticated HTTP wrappers perform **232 reads and four seed pushes**
against native Parquet/owned loopback S3:

- 96 ordinary/categorized log reads cover four Get snapshots, two BaseHas
  snapshots, four IntoMap maps, the Add error-label input and one suffixed-name
  control. Each runs on instant/range GET/form POST.
- 52 metric reads cover all 13 non-error grouping maps on both endpoints/methods.
- 72 metric attempts cover nine preserve-error identities and their fail-whole
  companion queries on both endpoints/methods.
- Twelve reads preserve the original colliding pair as two raw streams and two
  metric identities. Their source hash equality stays symbolic; no hash value
  is computed to manufacture an oracle.

Component tests additionally replay the literal log observations in both modes,
all 13 grouping maps and nine preservation/error-rejection pairs. An inventory
check accounts for all 107 original source assertion identities and 118 expanded
events; it is completeness accounting, not 118 passing public contracts.

### Categorized incoming error-label fix

The unchanged runtime failed the original Add input through authenticated HTTP:
values `test error`/`test details` appeared under `structuredMetadata`, while
the source expects the parsed category. Initial category construction treated
every received metadata key alike. Exact unsuffixed `__error__` and
`__error_details__` now use parsed output ownership; ordinary `_extracted` names
remain metadata. The same original public scenario passes after the fix.
Flat values, protected names, parser collision policies, error-selection admission,
budgets, native tuples, storage and keyed bytes do not change. Upgrade query-serving
applications consistently; no writer upgrade, retry drain or migration is needed.

Evidence: `.amp/in/artifacts/loki-label-builder-red.log` and
`loki-label-builder-focused.log`. These are local owned-provider results, not
deployed-client, separate-node or capacity acceptance. No commit or push is implied.

### Validation results

- Focused `label_builder_batch` replay: **six passed**, 338 excluded, with
  warnings treated as errors (seed 2023).
- Scoped formatter checks, compilation with warnings as errors and strict Credo
  passed; Credo inspected 463 source files without issues.
- Independent offline producer build/vet and regeneration matched the frozen
  JSON byte-for-byte.
- Full suite, seed 0 and four concurrent cases: **2,669 passed, two timed out**,
  one skipped and 37 excluded. The timeouts were the existing retained-trace
  Unicode-property test and log repetition/class/raw-header test, each at its
  unchanged 60-second limit. This is not a passing full-suite result.
- Both timed-out tests passed unchanged in a serial, location-selected rerun
  with the same seed and original timeout: **two passed**, 368 excluded, in
  63.5 seconds total. This establishes intermittent failures, not their cause.

Full-suite and rerun evidence: `.amp/in/artifacts/loki-label-builder-full.log`
and `loki-label-builder-timeout-rerun.log`. No unrelated timeout, regex or test
admission behavior was changed to obtain a passing result.
