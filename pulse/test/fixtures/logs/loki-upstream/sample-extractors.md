# Pinned Loki sample-extractor source fixtures

`sample-extractors.json` freezes **every Test-prefixed function (16)** in
[`pkg/logql/log/metrics_extraction_test.go`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/log/metrics_extraction_test.go)
at revision `5aa4b9212d64d723f63b2770452054aa23df114d`. Only
`BenchmarkLineSampleExtractor_Process` is excluded. Complete functions include
their local helper functions, executors, conditional assertions, discarded
results, inert fields, comments, repeated calls and original imperative order.

This is **source extraction, not observed execution, public-query oracles or a
Pulse parity claim**. The standard-library-only Go AST producer never imports,
builds or executes Loki/Pulse, extractors, stages, parsers, label builders,
hash functions or label-result rendering. Original tests and assertions are
copyright Grafana Labs contributors, AGPL-3.0-only; adjacent `LICENSE` applies.
Public replay and compatibility accounting are deliberately separate.

## Inventory

“Assertion sites” counts original `require.*`, `assert.*` and
`assertLabelResult` calls, including calls inside local functions. These are
source sites, not passing ports or expanded runtime assertion counts.

| Function | Assertion sites | Process sites | Expanded calls |
| --- | ---: | ---: | ---: |
| `Test_labelSampleExtractor_Extract` | 6 | 2 | 34 |
| `Test_Extract_ExpectedLabels` | 3 | 1 | 1 |
| `TestLabelExtractorWithStages` | 4 | 1 | 6 |
| `TestDistinctValueSampleExtractor` | 7 | 3 | 3 |
| `TestNewDistinctValueSampleExtractorDoesNotMutateGroups` | 2 | 0 | 0 |
| `TestNewDistinctValueSampleExtractorAllowsEmptyGroups` | 8 | 2 | 2 |
| `TestNewLineSampleExtractor` | 12 | 4 | 4 |
| `TestNewLineSampleExtractorWithStructuredMetadata` | 18 | 6 | 6 |
| `TestFilteringSampleExtractor` | 2 | 2 | 18 (wrapper only) |
| `TestLineSampleExtractor_ForStream_ShouldReturnOptimizedExtractorWhenOutputHasConstantLabels` | 67 | 17 | 21 |
| `TestLineSampleExtractor_ForStream_FilteredConstantIsolatesFromSiblingStreams` | 9 | 3 | 3 |
| `TestLineSampleExtractor_ForStream_ConstantPathFallsBackOnStructuredMetadataError` | 19 | 8 | 8 |
| `TestStageHints_Merge` | 9 | 0 | 0 |
| `TestReduceStages_FoldsHintsAcrossStages` | 6 | 0 | 0 |
| `TestBinaryLabelFilter_Hints` | 11 | 0 | 0 |
| `TestStages_KeepsErroredLines` | 2 | 0 | 0 |
| **Total** | **185** | **49** | **106** |

`executions` contains **88 non-wrapper calls: 58 Process and 30 ProcessString**.
`deletion_wrapper_executions` contains **18 calls: nine of each method**.
Counting both gives **106 calls: 67 Process and 39 ProcessString**. The loop
comparing fast and builder paths retains **both calls for each of three
iterations**, not one representative call. Calls to different streams, repeated
inputs and both byte/string APIs are never deduplicated.

`literal_rows` has **55 records**, also referenced through `tests[].rows`:

- **17** extraction rows, expanded to 34 method calls.
- **Two** stage-filter outer rows and **six** nested `checkLine` rows, expanded
  to six ProcessString calls.
- **Nine** deletion-wrapper rows, expanded to 18 symbolic wrapper calls.
- **21** literal `TestStages_KeepsErroredLines` rows: **nine true / 12 false**.
  This includes the two post-filter rows and the final omitted-stages row.

Thus there are **53 leaf rows plus two outer rows**, not 55 independent
executions. Literal tables and executions are views of the same original source,
not additional cases.

## Schema version 1: primitive replay view

Top-level `executions[]` is the ordinary replay view. Each entry contains:

- `execution_id`, `source_function`, `name`, `source_index`, `sequence`, `method`.
  `name` is the original subtest name, or function name if not in a subtest.
  `source_index` is a zero-based array of outer/nested row or integer-loop
  indices; imperative calls outside loops have `[]`. `sequence` is the global
  source-expansion sequence across ordinary and wrapper calls. It consequently
  has gaps in the ordinary-only array. Do not sort by timestamp or input bytes.
- `source`: the exact original Process/ProcessString expression and provenance.
- `timestamp` and `timestamp_expression`. All input timestamps are resolved
  literal integers, including the three original `int64(i)` loop values.
- `stream_labels`, `structured_metadata`: resolved arrays of `{name, value}`.
  `line_bytes_base64`: exact input line bytes, including empty default lines.
- `extractor`: `constructor`, `conversion`, `label`, `groups`, `without`,
  `no_labels`, ordered `stages`, `post_filter`, and `original`. Inapplicable
  properties are null. Original nil grouping remains null, not an invented
  explicit empty grouping. The constructor distinguishes label, line, distinct
  and the explicitly symbolic local `builderExtractor` reference path.
- `expected_ok`, `expected_value`, `expected_labels`: nullable primitive
  channels. Known empty labels are `[]`; null is not an empty-label oracle.
  `asserted_channels` distinguishes `ok`, `value`, `labels`, `labels_nil`,
  `hash_symbolic`, `string_symbolic` and `value_hash_bits_symbolic`.
- `assertions` and `symbolic_contracts`: original assertions and nonprimitive
  relationships, never computed replacement oracles.

Among the 88 ordinary executions, **all 88 ok flags are asserted: 76 true /
12 false**. **60** have primitive value expectations and **70** have literal
label-array expectations. Another **four** explicitly assert `ExtractedSample{}`:
they retain `expected_value: 0`, `expected_labels: null`,
`expected_labels_result_is_nil: true`, and `labels_nil`. These are nil result
contracts, not fabricated empty series. The other **28 value channels** and
**14 label channels** are null because they are unasserted or symbolic; no
successful fast/reference comparison is turned into a new literal value.

The **four** asserted distinct-value hash bit patterns stay symbolic:
`xxhash.Sum64String("aa:bb")` or `xxhash.Sum64String("cc:dd")` compared against
`math.Float64bits(sample.Value)`. All five distinct-extractor calls have null
`expected_value`, including the missing-value rejection. Public cardinality is
an authored adaptation, **not** the expected sample value of these tests.

The **30** calls through `assertLabelResult` preserve literal label expectations
and symbolic StableHash/String contracts. No hashes or rendered label strings
are generated. Expected labels on builder-path reference samples remain null
where the source asserts only String equality with the fast path.

### Stages and remaining literal tables

`extractor.stages` is an ordered array. A normalized call has `constructor`,
positional `arguments`, `original` source provenance, and `receiver` for method
calls. Literal arguments are primitives or arrays; package constants remain
explicit symbolic selector objects (`kind`, `name`, `receiver`, `origin`).
For example matcher types retain `MatchEqual`/`MatchNotEqual`, not guessed
integer enum values. `mustFilter(...).ToStage()` retains its full receiver tree.
`NoopStage` remains a symbolic identifier, including as a post-filter.

`literal_rows[]` and `tests[].rows[]` expose original field names, normalized
values, `source_function`, `source_index`, the complete `source` row and the raw
`row` expression tree. Extractor-bearing rows additionally expose `extractor`
in the same shape as executions. Omitted source fields remain omitted in the
literal row view; the execution view resolves only the declared Go zero defaults
needed by its executor. `in`, `wantLbs` and `structuredMetadata` are original
literal label arrays when supplied, not results produced by the extractor.

For `TestStages_KeepsErroredLines`, use the direct `name`, `stages`,
`post_filters`, and literal Boolean `want` fields. Both stage arrays exist even
when omitted upstream. Nested AND/OR constructor arguments stay nested and
ordered. Local `errorFilter(matchType, value)` and `renameError()` calls remain
symbolic with original arguments; their complete declarations are preserved in
the containing test. The original post-filter append/ReduceAndLabelFilter
executor is retained, not replaced by an alternate pipeline or truth table.

Convenient queries:

```sh
jq '.executions[] | {source_function, name, source_index, sequence, method,
  stream_labels, structured_metadata, line_bytes_base64, extractor,
  expected_ok, expected_value, expected_labels, asserted_channels}' sample-extractors.json
jq '.literal_rows[] | select(.source_function == "TestStages_KeepsErroredLines") |
  {name, source_index, stages, post_filters, want}' sample-extractors.json
```

## Literal assignment snapshots, not executed builders

`assignment_snapshots` preserves the original source assignments and immutable
source-value snapshots in statement order. Normalization resolves only literal
labels.FromStrings/EmptyLabels inputs, assigned references, and the explicitly
preserved appendLabel/appendLabels helpers' literal Set assignments. It does not
execute a builder, infer grouping/collision behavior, sort labels, compute label
hashes or render Strings. In particular `foo_extracted=baz` is taken from an
**original expected-label assignment**, never generated from input collisions.
Label arrays preserve source construction/assignment order, not Loki's sorted
iteration order.

The only source-defined label aliases resolved are `logqlmodel.ErrorLabel` and
`logqlmodel.ErrorDetailsLabel`, with declarations and full-file hashes retained.
Omitted float64 fields use Go's declared zero value, omitted line strings use
the empty string, and omitted structured metadata is represented as an empty
input label array. The original type declarations and executor expressions make
these defaults auditable.

Primitive `13 * 1024 * 1024` becomes **13,631,488**, and the original
`(20 * time.Millisecond).Seconds()` expectation becomes **0.020 seconds**, with
original expression provenance and explicit primitive-resolution descriptions.
These do not run extractor conversions. The original malformed-number/duration
diagnostic strings are copied exactly from literal expected labels.

Unknown calls/expressions remain explicitly symbolic and cannot pass through
the string/label-input resolver. Nonliteral Process inputs, unknown loops or
unresolved Process-bearing branches fail closed. Full-file hash guards reject
source drift before emitting any JSON. The producer is deliberately not a Go
interpreter, a general builder simulator, or an oracle generator.

## Symbolic contracts and provenance

`tests[]` preserves all 16 complete selections, original constructor calls,
control-flow records, assertion call sites, row views and execution IDs.
Type/optimization, hint merging, errored-line preservation, grouping mutation,
base-label identity, reference-path comparisons and shared-overlay isolation
remain original symbolic contracts. The A → B → A interleaving, repeated calls,
three-iteration reference comparison, error metadata fallbacks and subsequent
normal calls keep their original execution order and distinct asserted channels.
No hash, type, cache/builder identity or hint contract is promoted to a public
numeric oracle.

The nine deletion rows and 18 method executions are in the separate
`deletion_wrapper_executions` array, marked
`symbolic_deletion_wrapper_not_public_query`. Only their wrapper `ok` flags are
asserted; values and labels remain null despite the stub's implementation.
The three original deletion-filter constructors, time boundaries, stream and
metadata matchers, line filters, complete stub methods and helper are preserved.
They are not ordinary positive/negative public line-filter tests.

There are **18 supporting declaration records**: 13 complete helper/method
declarations, two stub types, one source-import declaration and two label-alias
ValueSpecs. Helpers include mustSampleExtractor, appendLabel, newStubExtractor,
all five stub methods, appendLabels/newPipelineFilter/mustFilter from
pipeline_test.go, assertLabelResult from labels_test.go, and the additionally
referenced mustStage from parser_test.go. Local builderExtractor/errorFilter/
renameError declarations are already inside complete selected tests. Attached
declaration comments are retained separately.

Every source record has exact `original_go`, `source`, SHA-256, one-based line/
byte-column coordinates, and zero-based half-open byte offsets. Complete
declaration selections include the original trailing newline and explicitly set
`selection_includes_trailing_newline: true`; their AST ranges end immediately
before that newline. Other records hash exactly their AST byte interval.
Raw expression trees use `kind`, `arguments_or_items`, `fields`, `receiver` and
`origin`; sample references use `execution_sequence` and `channel` (an omitted
zero sequence means sequence zero). These raw trees support auditing, not replay
of unimplemented Go APIs.

| Source file | SHA-256 |
| --- | --- |
| `pkg/logql/log/metrics_extraction_test.go` | `21317d2e294e6bbed25160a1b7cc2486dc106fda5c481b7ab7e915b06ec6b16d` |
| `pkg/logql/log/pipeline_test.go` | `d077ffbf7c67db32416395fb910dbc0440b75e08360ccace3319bfe821888bc2` |
| `pkg/logql/log/labels_test.go` | `5a3383cd2799117f8f96d1e39f5af42d92f2e07a7e205086bff4d4acaa77eff9` |
| `pkg/logqlmodel/error.go` | `21816c4294243f16157f6408d92fb0907612a3258333288ab39b3f84bf7a4db5` |
| `pkg/logql/log/parser_test.go` | `346b91ced2d38e51d8cf7fd8acb3335ea5796e9286fd901b45dd625c0b3634ff` |

## Offline regeneration and validation

Run from the Pulse root, using the pinned clone as source input. No network,
Loki dependency installation, Python or Pulse runtime is required:

```sh
scratch=$(mktemp -d .amp/in/sample-extractors.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp test/fixtures/logs/loki-upstream/sample-extractors-producer.go.txt "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go build -o "$scratch/producer" "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go vet "$scratch/producer.go"
test -z "$(gofmt -l test/fixtures/logs/loki-upstream/sample-extractors-producer.go.txt)"
"$scratch/producer" /tmp/amp-librarian/grafana__loki > "$scratch/sample-extractors.json"
cmp "$scratch/sample-extractors.json" test/fixtures/logs/loki-upstream/sample-extractors.json
jq '{test_count, execution_count, deletion_wrapper_execution_count,
     literal_row_count}' "$scratch/sample-extractors.json"
```

Validation performed with **Go 1.25.10**:

- Offline build and vet passed; gofmt reported no changes.
- Repeated regeneration was byte-identical.
- An independent AST inventory confirmed all 16 functions, 185 assertion sites,
  49 Process/ProcessString sites, literal table sizes and all 106 expanded calls.
- An independent recursive verifier checked **4,282 source records** against
  original source bytes, offsets, line/column positions and SHA-256 values.
  Execution IDs, input Base64, method counts, nil-sample controls, null distinct
  numeric values and asserted-channel totals passed.
- Six unknown-expression/hash/unknown-stage controls remained symbolic and
  rejected use as literal strings. Deliberately corrupted fixture source and
  hash records were rejected by the independent verifier.
- Deliberately changed source input failed the producer's hash guard before any
  JSON output. Disposable validation code and scratch outputs were removed.

Frozen JSON: **3,615,873 bytes**, SHA-256
`bb477e83577e81cc2b2782c5d96296f255d57a885355ac7018ed03bf88ae93de`.
Producer SHA-256:
`f862d1cb4a555b296965efc181fbb48730b643dd6c567378f2af67e360ad9e6d`.

The extraction above does not execute runtime contracts. The separately
implemented replay below must not be confused with source-extractor validation.

## Pulse public-query replay and compatibility ledger

`Pulse.Test.LokiSampleExtractorFixture` translates original constructors into
public LogQL, retaining original input bytes and only the asserted primitive
channels. It does not implement Go extractors, builders, hashes or hints.
Component replay queries test-owned Memory storage with the original labels in
record attributes. All **88 ordinary executions** agree on their asserted
presence, **60 numeric values** and **70 literal label arrays**. The four
zero-sample/nil-label expectations become absence of a public metric sample,
not assertions about an Elixir equivalent of Go's nil LabelsResult.

| Original source contract | Component calls | HTTP calls | Remaining boundary |
| --- | ---: | ---: | --- |
| Label extraction table | 34 | 34 | Constructor error emission needs explicit public error selection. |
| Expected JSON labels | 1 | 1 | No parser-hint/early-exit claim. |
| Label extraction with filter stages | 6 | 6 | Source skip/default channels retained. |
| Distinct value extraction | 3 | 3 | Float-encoded xxhash values remain symbolic. |
| Distinct constructor group mutation | 0 | 0 | Slice mutation is a Go API contract. |
| Distinct empty/omitted groups | 2 | 2 | Two more float-encoded hashes remain symbolic. |
| Line extraction | 4 | 4 | No byte/string API identity claim. |
| Line extraction with metadata | 6 | 6 | Original suffixed collision label expectations retained. |
| Deletion wrapper | 0 | 0 | All 18 original wrapper calls stay unsupported/symbolic. |
| Optimized/reference line paths | 21 | 21 | Original correlation-ID cases restored; Go types/cache/reference equivalence remain symbolic. |
| Sibling-stream isolation | 3 | 3 | Additional whole-sequence HTTP control; no shared Go overlay claim. |
| Error-metadata fallback | 8 | 8 | Explicit error selection plus fail-whole companions, not Go optimized-type parity. |
| Stage hint merge | 0 | 0 | Complete symbolic boolean contract. |
| Reduced-stage hints | 0 | 0 | Complete symbolic boolean contract. |
| Binary label-filter hints | 0 | 0 | Complete symbolic boolean contract. |
| KeepsErroredLines table | 0 | 0 | All 21 original booleans retained; not claimed as an executed hint implementation. |
| **Ordinary execution total** | **88** | **88** | Source completeness is not complete extractor compatibility. |

The four builder-reference calls retain their asserted `ok` observations under
the equivalent count/group query. Their unasserted literal values/labels stay
unasserted; reference String equality and implementation type are not promoted
to public expectations. Distinct queries additionally return cardinality one
for each retained input: this is an authored public control, **not** the source's
four symbolic `Float64bits` hash oracles.

### Public-query adaptations

- Label extraction uses `avg_over_time` on one original input, preserving its
  value and supporting the original by/without/no-label grouping. The extracted
  field is removed by normal unwrap semantics, not by altering expected labels.
- Count/byte extractors use `count_over_time`/`bytes_over_time` and, when needed,
  an outer `sum` grouping. Input windows are isolated by 120-second spacing;
  original line bytes, stream labels and structured metadata are unchanged.
- Unlike the raw constructor, public metric evaluation rejects unselected
  errors. The six original failed-conversion calls and four accepted incoming
  error-metadata calls therefore add explicit `__error__!=""` selection. Line
  grouping explicitly retains the two error fields. All ten companion queries
  without that selection must fail whole with HTTP 400 `evaluation_failed` and
  no data; error permission is never inferred from caller metadata.
- Original Process and ProcessString calls remain distinct replay identities,
  not claims that Pulse implements those separate Go methods. Null expectation
  channels remain unasserted; HTTP timestamps, one-point shapes and status codes
  are authored transport controls.

Two HTTP wrappers replay **88 ordinary calls through 352 reads**, covering
instant/range GET and form POST. The ten unpreserved-error companions add
**40 rejection reads**. A third wrapper replays the original A → B → A sibling
inputs on a one-second grid, plus an authored wider-window count control:
**six reads**. Overall: **398 authenticated reads and three seed pushes**, using
native Parquet and the Rust S3 client against an owned loopback provider.

### Correlation-ID gap and query-side repair

Original execution sequences **85, 91 and 92** in the optimized-extractor test
depend on structured metadata `trace_id`. Sequence 85 expects it among the
ungrouped output labels; 91/92 filter matching/nonmatching values. Pulse's Loki
push decoder deliberately moves `trace_id` into the dedicated record field and
removes it from attributes. Before this repair, LogQL did not project that field
back into metadata labels. Direct-record replay alone was consequently **not**
evidence of public ingestion compatibility.

The unmodified expected-label HTTP replay failed at sequence 85. An independent
push/query probe confirmed that `trace_id="t1"` survives in the dedicated field
while attributes are empty and the corresponding LogQL filter finds no sample.
Sequence 92 can coincidentally drop a missing label too; that is not proof that
metadata values are read correctly. All three original expectations now run in
the public replay without exclusions or renamed inputs.

The shared Elixir entry projection and native metric scan now fill absent
metadata names from dedicated nonempty `trace_id` and `span_id` fields. Explicit
attributes win, including empty values. Existing stream collision suffixing,
occupied-suffix protection and parser ownership apply unchanged. IDs remain
metadata, never stream-selector or discovery labels. Both IDs participate in
the native per-batch label cache key; same-stream rows with independently varying
IDs must retain independent labels. Query-serving app/native pairs require log
tuple `{1,1,17}`; storage/keyed bytes, ingestion and resource ceilings do not change.

Separate owned-provider controls cover unflagged/categorized raw output through
both endpoints and GET/form POST, native metric grouping and filters, parser
collisions, missing/empty IDs and exclusion from stream selectors: **20 reads
and one push**, in addition to the source replay counts above. A literal-result
native/reference control also covers explicit attribute precedence, occupied
stream suffixes and independent trace/span changes within one native batch.

### Original source-table increment validation

- Initial adjacent baseline: **169 passed**, seed 2101.
- Complete component replay: **one passed**, 51 excluded, seed 2104.
- Unadapted HTTP replay: **two passed / one failed**, seed 2105, exposing the
  original correlation-label expectation above rather than a runtime repair.
- Accounted public/component batch: **four passed**, 344 excluded, seed 2106.
- Final replay after quality-check adjustments: **four passed**, 344 excluded,
  seed 2108, in 11.3 seconds.
- Broader parser, metric evaluator, pipeline, query-controller and Loki-push
  regression run: **233 passed**, seed 2107.
- Compilation with warnings as errors, scoped formatter checks and strict Credo
  over 464 source files passed. The main agent independently rebuilt/vetted the
  producer and regenerated byte-identical JSON offline.

Evidence is under `.amp/in/artifacts/loki-sample-extractors-{baseline,component,
http-original,focused,final,adjacent,quality,correlation-probe}.log`. These results are
local owned-provider replay, not deployed clients, independent-node topology,
capacity acceptance, complete hint/deletion/hash parity or a green full-suite
claim. No full-suite rerun was performed for this test-only increment; the prior
full run's two intermittent regex timeouts remain documented in the label-builder
ledger. No commit or push is implied.

### Correlation-ID repair validation

- Before the production change, seed 735: **two passed / three failed**.
  Original execution 85, raw HTTP labels and the literal reference projection
  exposed the missing IDs without changing source inputs or expected labels.
- The same focused run after the repair: **five passed**, 299 excluded,
  including all 88 ordinary HTTP observations and both correlation-ID controls.
- Broader LogQL/Loki, native/reference randomized parity, query-controller,
  Loki/OTLP ingest and log end-to-end checks: **448 passed**, seed 736.
- Native codec release suite: **133 passed**. Compilation with warnings as
  errors, scoped Elixir/Rust formatting and strict Credo over 464 files passed.
- Initial strict all-target Clippy was blocked by three pre-existing
  `nonminimal_bool` diagnostics in `query_regex.rs:471` and
  `trace_segment_parquet.rs:543–548`. The subsequent authorized cleanup replaced
  their negated predicates with equivalent `is_none_or` expressions, without
  suppressing warnings. Strict all-target Clippy, Rust formatting and all
  **133 debug-profile Rust tests** now pass; evidence is in
  `.amp/in/artifacts/clippy-warning-fix{,-tests}.log`.

Evidence: `.amp/in/artifacts/correlation-metadata-{red,green,adjacent,rust-tests,
quality,clippy}.log`. This is local public-query and native/reference validation,
not a complete full-suite, deployed-client, capacity or full Go-extractor claim.
Changes are local and uncommitted; no push or deployment was performed.
