# Pinned Loki pipeline ownership source fixtures

`pipeline-ownership.json` freezes six complete tests from Grafana Loki revision
`5aa4b9212d64d723f63b2770452054aa23df114d`. This is **source extraction, not
observed execution or a Pulse parity claim**. The producer uses only Go's standard
library and never imports, builds or executes Loki/Pulse, pipeline constructors,
parsers, formatters, hashing, or label-result rendering.

Test inputs, assertions and original source are copyright Grafana Labs
contributors, AGPL-3.0-only; the adjacent `LICENSE` applies. No unsupported case,
inert field, assertion, constructor or helper is silently discarded.

## Complete scope and counts

All selections are in
[`pkg/logql/log/pipeline_test.go`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/log/pipeline_test.go).
Each table's `selection` contains the complete function, including setup,
executors, all assertions and reset controls, plus its exact source range and
SHA-256. Complete selections include the original trailing newline; AST byte
ranges end immediately before it.

| Function | Lines | Rows | Process | ProcessString | Assertion call sites |
| --- | --- | ---: | ---: | ---: | ---: |
| `TestNoopPipeline` | 13–59 | 5 calls | 3 | 2 | 26 |
| `TestPipeline` | 61–104 | 4 calls | 2 | 2 | 19 |
| `TestPipelineWithStructuredMetadata` | 106–180 | 8 calls | 4 | 4 | 35 |
| `TestFilteringPipeline` | 192–231 | 9 table rows | 9 | 9 | 3 |
| `TestDropLabelsPipeline` | 299–400 | 2 outer rows / 4 lines | 4 | 0 | 5 |
| `TestKeepLabelsPipeline` | 402–524 | 3 outer rows / 9 lines | 9 | 0 | 7 |
| **Total** | | **31 rows** | **31** | **17** | **95** |

The flat `executions` array contains **30 distinct source executions**: the first
three functions' **17** calls plus **13** drop/keep input lines. Its method counts
are **22 Process / 8 ProcessString**. The other **18** source executions belong
to nine symbolic deletion-wrapper rows and are deliberately **not** ordinary
query executions in that array. Counting both scopes gives **48**, not 30 or 31.
Assertion call-site counts describe the original source, not expanded runtime
assertion counts, replay successes or public HTTP requests.

The 30 flat executions retain:

- **17** literal match booleans: **11 true / 6 false**. Drop/keep discard the
  original match return value; their **13** `expected_match` values are null,
  not invented successes.
- **26** asserted line-byte expectations: 17 imperative and nine keep executions.
  Three Process rejection expectations are `[]byte(nil)`; their
  `expected_line_is_nil: true` distinguishes nil from empty bytes. The three
  corresponding ProcessString rejection expectations are literal empty strings.
- **24** known label/category expectations; six rejected imperative executions
  expect a nil LabelsResult and have null label/category arrays instead of
  invented empty results.
- **24** symbolic hash assertions and **20** symbolic String assertions. There
  are no computed hash values or rendered label-result string oracles.
- All **four** drop `wantLine` literals, retained as **unasserted source data**.

## Literal state resolution, not computed pipeline oracles

The first three functions are imperative tests, not literal tables. Each original
Process/ProcessString assignment gets its own row and execution identity, in
source order. Noop's final duplicate-metadata case has **only Process**; no extra
ProcessString counterpart is manufactured. Identical byte/string test inputs
are not deduplicated.

The producer resolves only original `labels.FromStrings`/`labels.EmptyLabels`
assignments, references to those assigned values, the preserved `appendLabels`
helper's explicit Set assignments, and the source's
`labels.NewBuilder(...).Set(name, value).Labels()` construction. Source assignment
snapshots and original constructor expressions remain alongside the resolved
name/value arrays. Arrays preserve source construction/assignment order, **not
an assertion about Loki's sorted iteration or String rendering**.

Expected renamed collision labels such as `foo_extracted=baz` come from the
original **expected label literals**, never from running a collision algorithm.
`expected_categories` separates `stream`, `structured_metadata` and `parsed`
using the three original NewLabelsResult arguments, or the drop/keep executor's
explicit category assertions. It does not infer ownership from the final labels.
All original NewLabelsResult, append, String and StableHash expressions are
preserved symbolically. Cache Reset, cache sizes, builder clearing and downstream
reset contracts likewise remain symbolic; no cache implementation is simulated.

Only four literal source aliases are resolved: `errJSON`, `errLogfmt`,
`logqlmodel.ErrorLabel`, and `logqlmodel.ErrorDetailsLabel`. Their original
declarations, values, source ranges and hashes are retained. Both drop diagnostic
strings remain exactly as written upstream, including JSON's
`Value looks like object, but can't find closing '}' symbol` and logfmt's
`logfmt syntax error at pos 2 : unexpected '"'`.

Unknown expressions, runtime calls in literal fields, unknown stage/matcher
constructors and nonliteral booleans/integers reject extraction. Hash/String
calls cannot pass through the label-literal resolver. Full-file SHA-256 checks
reject source drift before emitting any JSON.

## Drop/keep asserted channels

The drop executor discards the output line and match flag. It asserts only final
labels, empty Stream/StructuredMetadata categories, Parsed labels and StableHash.
Thus each drop input has `want_line_asserted: false`, retained
`want_line_bytes_base64`, and **null** `expected_line_bytes_base64`. Its inert
`wantLine` is not promoted to an oracle. It has no String assertion.

Keep asserts line bytes, final labels, the same categories, StableHash and String,
but still discards matches. All nine keep lines have `want_line_asserted: true`.
The empty `NewKeepLabels([]NamedLabelMatcher{})` stage is explicitly marked
`constructor_noop: true` and `public_grammar_form: null`. It is an original
constructor case, **not a fabricated empty `| keep` LogQL query**.

Normalized `stages` preserve order and all admitted literal inputs: equality
matcher names/values, line-format templates, logfmt strict/keep-empty flags,
JSON capture-path flags and drop/keep named matchers. Every stage also contains
its original constructor call and source range. The fixture contains no authored
LogQL query strings or replacement implementations.

## Filtering/deletion wrapper is a separate symbolic contract

The nine filtering rows preserve original timestamps, line bytes, stream labels,
structured metadata, literal `ok` expectations, both method calls and reset
assertions. Their `contract` is
`symbolic_deletion_wrapper_not_public_query`. `expected_match` describes the
**NewFilteringPipeline wrapper result**, not an ordinary positive/negative LogQL
line filter. Six row booleans are true and three are false, each asserted once
for each method.

All three `newPipelineFilter` constructor inputs are retained, including time
boundaries **2–4**, **3–5**, **3–5**, stream-label matcher inputs, metadata-label
stage inputs and literal `"e"` line-filter inputs. The full helper preserves its
stream matcher construction, structured-metadata filter stages,
`mustFilter(NewFilter(filter, LineMatchEqual)).ToStage()` append and returned
PipelineFilter constructor. No alternate filter, negated LogQL query or deletion
implementation is substituted. The full stub support explains why its downstream
data is not an unchanged-input line oracle: Process returns `nil, nil, true`,
ProcessString returns `"", nil, true`, and Reset sets `resetCalled`.

There are **17 supporting declaration records**: four aliases; appendLabels,
newPipelineFilter, newStubPipeline, six stub methods and mustFilter; the two stub
types; and newMustLineFormatter from `fmt_test.go`. Attached declaration comments
are retained separately when present. Production hash, String, Reset and deletion
implementations are not embedded or executed.

## Schema version 1

- Top-level `sources` contains full-file hashes; `supporting_declarations`
  contains original helper/type/alias source. `tables` contains the six full
  selections, `assertion_calls`, symbolic reset controls, `rows` and counts.
- `tables[].rows[]` has `table`, zero-based `source_index`, `name` and complete
  source provenance. For the first three functions each row is one method call;
  filtering has nine source rows; drop/keep have five outer rows with `inputs`.
- `executions` is a convenient flattened copy of the 17 imperative rows and 13
  drop/keep inputs, **not additional cases**. `execution_id` includes table,
  source index, input index and method. `input_index` is zero for imperative
  rows, and zero-based within each drop/keep row.
- Each execution has `method`, `timestamp`, `stages`, `pipeline_constructor`,
  `input_line_bytes_base64`, `stream_labels`, `structured_metadata`, nullable
  expected channels, and original assertions. Label arrays contain objects with
  `name` and `value`; empty known labels are `[]`, unknown/nil results are null.
- `asserted_channels` distinguishes actual line/label/match assertions from
  symbolic hash/String assertions. `expected_labels_result_is_nil` and
  `expected_line_is_nil` preserve imperative nil expectations. Drop/keep use
  `want_line_asserted` to distinguish inert source values from line oracles.
- Original source records use `original_go`, `source` and `source_range`:
  one-based line/column positions and zero-based half-open byte intervals.
  Complete selection hashes include their original trailing newline. Alias
  ValueSpec hashes cover exactly the node bytes without a newline or enclosing
  declaration keyword.

## Offline regeneration and validation

Go is needed only to regenerate, not to consume the checked-in JSON. No Loki
dependencies, network or Python are required. From the repository root:

```sh
scratch=$(mktemp -d .amp/in/pipeline-ownership.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp test/fixtures/logs/loki-upstream/pipeline-ownership-producer.go.txt "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go build -o "$scratch/producer" "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go vet "$scratch/producer.go"
"$scratch/producer" /tmp/amp-librarian/grafana__loki > "$scratch/pipeline-ownership.json"
cmp "$scratch/pipeline-ownership.json" test/fixtures/logs/loki-upstream/pipeline-ownership.json
jq '{row_count, execution_count, source_execution_count, method_counts,
     execution_method_counts, assertion_call_site_count}' "$scratch/pipeline-ownership.json"
```

Validation performed with Go 1.25.10: offline build/vet, byte-identical regeneration,
independent AST inventory of all six functions and 95 assertions, verification of
all **1,292 nested source records** against original byte slices/positions/hashes,
input/output Base64 checks, execution-ID uniqueness, asserted-channel/nil checks,
six unknown-expression/hash/String rejection controls, and deliberate source-drift
rejection before output. Disposable validation code is not part of fixture replay.
No Loki/Pulse pipeline was executed to create or validate these source fixtures.

| File | SHA-256 |
| --- | --- |
| `pkg/logql/log/pipeline_test.go` | `d077ffbf7c67db32416395fb910dbc0440b75e08360ccace3319bfe821888bc2` |
| `pkg/logql/log/error.go` | `d836fe896703aaa92d53baa61e6532c605344261460af3bab3994d531fa14458` |
| `pkg/logqlmodel/error.go` | `21816c4294243f16157f6408d92fb0907612a3258333288ab39b3f84bf7a4db5` |
| `pkg/logql/log/fmt_test.go` | `58955c60c2ff68f91a5f0777208e49180d194c290c3bbb36f3145911f1f22ff6` |
| `pipeline-ownership.json` (775,434 bytes) | `d632fae95472a800b1b01933f6276807df3e792e42ac2689fef6b979eaabb125` |
| `pipeline-ownership-producer.go.txt` | `b17709916d635ae59e34223145e0ce18f8179e1ccc3a02c51b27f83ae2d9a6d6` |

Public replay, implementation gaps and compatibility evidence belong to separate
tests and their ledger. Preserving a symbolic deletion-wrapper, cache, hash,
String or constructor contract here does not claim a public implementation.

## Pulse replay and compatibility ledger

The `pipeline_ownership_batch` component and authenticated HTTP tests consume all
30 ordinary executions without deriving expectations from Pulse. Both ordinary
and categorized output preserve the original line, label and ownership oracles,
including structured-metadata collisions, strict logfmt/JSON errors and drop/keep
results. The original JSON and logfmt diagnostic strings agree exactly in these
selected rows; this is not a claim about complete malformed-input diagnostics.

The shared test mapping translates original stage constructors into public
LogQL, not source query literals. Empty selectors are permitted under Pulse's
existing bounded-query policy. Each source execution runs through both instant
and range endpoints, GET and form POST, with and without categorized output:
**240 read requests**, plus **one push** storing all 30 records in native Parquet
against an owned loopback S3 provider. Distinct past timestamps isolate exact
single-entry windows; original labels, metadata and line bytes are unchanged.
Component replay retains the original timestamps and reuses compiled pipelines.

The following contracts remain explicitly separate:

- All nine deletion-filter wrapper rows / 18 method executions are retained
  symbolically, **not passing ports**. Pulse has no corresponding deletion wrapper
  or Loki delete-request route. Ordinary line-filter negation is not substituted.
- Go StableHash, LabelsResult.String, builder/cache-reset identities and separate
  Process/ProcessString APIs are not implemented or claimed. Both original method
  identities replay through Pulse's binary entry path. Rejected Go nil byte lines
  and empty string lines both map to Pulse's `:drop`, not a fabricated return tuple.
- The empty keep constructor is an identity in upstream. No public empty-keep
  syntax exists; replay omits that identity stage. Pulse rejects `{} | keep`,
  while a manually constructed empty `AST.Keep` removes labels. Neither that
  internal constructor nor its equivalence is counted as passing parity.
- Drop's four output lines and drop/keep's match flags are unasserted upstream.
  HTTP line preservation/retention is an additional authored transport control,
  not promotion of the inert source `wantLine` fields into upstream oracles.

Normal replay requires only the native Elixir/Rust toolchain, not Go or Loki.
No production code, resource ceiling, native tuple, storage or keyed bytes change.

Validation for this increment:

- Focused `pipeline_ownership_batch` replay: **2 passed**, 336 excluded, seed 2011;
  60 component applications and 240 HTTP reads preserve all 30 execution identities.
- Offline producer build/vet and regeneration `cmp` pass; frozen JSON SHA-256
  remains `d632fae95472a800b1b01933f6276807df3e792e42ac2689fef6b979eaabb125`.
- Strict compilation, scoped formatter/whitespace checks and strict Credo pass
  (462 source files, no issues).
- Full suite, seed 0 / four cases: **2,664 passed, one failed, one skipped,
  37 excluded**, 649.9 seconds. The sole failure is the existing
  `test/pulse/query_regex_test.exs:36` Unicode-property test's 60-second timeout.
  The unchanged isolated rerun passes in 28.3 seconds. No regex code/assertions
  or timeouts were changed; the intermittent failure remains unresolved.

Evidence is retained in `.amp/in/artifacts/loki-pipeline-ownership-{focused,full,regex-rerun,credo,compile}.log`.
These local results do not imply provider, deployed-client or capacity acceptance,
and no commit or push was performed.
