# Pinned Loki formatter and AST round-trip source fixtures

`formatter-roundtrip.json` preserves the complete selected source tests at
Grafana Loki revision `5aa4b9212d64d723f63b2770452054aa23df114d`. It is source
extraction, **not observed execution**, and makes **no Pulse formatting parity
claim**. Pulse has no Loki formatter implementation. Replay and compatibility
policy belong to separate tests and their ledger, not to these source oracles.

Test inputs, assertions and source functions are copyright Grafana Labs
contributors, AGPL-3.0-only; the adjacent `LICENSE` applies. No selected row is
trimmed, rewritten, deduplicated or dropped because its contract is unsupported.

## Complete scope and counts

All links below refer to the same pinned revision. Each `selection` includes the
complete original function, including executor, assertions, comments, setup,
cleanup, transformations and skips, with a SHA-256 of its exact original bytes
including the trailing newline.

| File | Complete function | Lines | Rows | Operation |
| --- | --- | --- | ---: | --- |
| [syntax/parser_test.go](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser_test.go#L3741-L3776) | `TestNoOpLabelToString` | 3741–3750 | 1 | string |
| same | `TestParseSampleExpr_String` | 3752–3776 | 3 | string |
| [syntax/prettier_test.go](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/prettier_test.go#L10-L620) | `TestFormat` | 10–108 | 10 | prettify |
| same | `TestFormat_VectorAggregation` | 110–147 | 2 | prettify |
| same | `TestFormat_LabelAggregation` | 149–215 | 6 | prettify |
| same | `TestLabelAggregationExpr_String` | 217–252 | 4 | string |
| same | `TestFormat_CountDistinctSketch` | 254–322 | 6 | prettify, transformed AST |
| same | `TestCountDistinctSketchExpr_String` | 324–361 | 4 | string, transformed AST |
| same | `TestFormat_LabelReplace` | 363–415 | 2 | prettify |
| same | `TestFormat_BinOp` | 417–620 | 8 | prettify |
| [syntax/ast_test.go](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/ast_test.go) | `Test_logSelectorExpr_String` | 19–75 | 29 | string |
| same | `Test_SampleExpr_String` | 77–202 | 50 | roundtrip |
| same | `Test_SampleExpr_String_Fail` | 204–217 | 4 | string, explicit parse rejection |
| same | `TestStringer` | 693–859 | 38 | string |
| same | `Test_parserExpr_String` | 966–989 | 5 | symbolic parser-fragment constructors |
| same | `TestGroupingString` | 1494–1530 | 6 | grouping constructors |
| [format_query_handler_test.go](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/loki/format_query_handler_test.go#L14-L55) | `Test_formatQueryHandlerResponse` | 14–55 | 2 | http-format |
| [syntax/serialize_test.go](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/serialize_test.go#L11-L121) | `TestJSONSerializationRoundTrip` | 11–82 | 15 | symbolic internal AST JSON |
| same | `TestJSONSerializationCountDistinctSketch` | 84–97 | 1 | symbolic internal AST JSON, transformed AST |
| same | `TestJSONSerializationParseTestCases` | 99–121 | 0 new rows | symbolic shared-table reference |
| **Total** | **20 complete functions** | | **196 rows** | |

All **eight functions / 42 rows** in `prettier_test.go` are included. The producer
checks its complete function inventory, not just a selection of convenient rows.
The original formatter width is retained: 20 for the fixed-width tests, and
the original 20/100 `maxChars` values for the two variable-width tables.
Original global assignment/restoration details remain in the full functions;
the fixture does not introduce a different configuration contract.

Aggregate counts:

- **196** rows: **180** formatter/string/round-trip/HTTP cases and **16** additional
  symbolic serialization cases. The shared `ParseTestCases` contributes **zero
  duplicated rows**, not zero upstream coverage.
- **185** literal query inputs, including the 16 symbolic serialization inputs.
  The remaining **11** rows are five parser-fragment and six grouping
  constructors, with no fabricated query string.
- **94** literal string expectations, including ten transformed sketch outputs
  and eleven constructor-fragment outputs. **73** are literal output expectations
  on the same directly parsed input expression. These are source oracles, not
  measured Pulse successes.
- **4** explicit parse-error assertions, all substring checks, not exact error
  equality. No other `reject` booleans are invented.
- Operations: `string: 83`, `prettify: 34`, `roundtrip: 50`, `http-format: 2`,
  `grouping: 6`, `symbolic: 21`.
- **62** assertion/control source call sites. These are not runtime assertion
  counts or replay request counts.

Map rows in `TestJSONSerializationRoundTrip` retain **source declaration order**.
Their `source_index` is not Go's nondeterministic map iteration order.

## Literal inputs and outputs, never computed oracles

The standard-library-only Go producer parses the original files with `go/ast`.
It unquotes only original string literals and concatenates only trees of literal
strings under `+`, needed for the original backtick-containing parser case.
It never imports/builds Loki, parses LogQL, runs AST constructors, formats an
expression, serializes an AST, or derives expected text from implementation
behavior. Unsupported input-expression shapes panic instead of manufacturing a
query or an expected result. All five full-file hashes are checked before JSON
output, so an edited checkout fails closed.

Original `require.Equal(t, query, expr.String())` and
`expr.String() != tt.selector` references are preserved as `expected_reference`,
not replaced with new literal oracle records. Their `expected_bytes_base64` is
null. The 50 sample string round trips assert expression equivalence after
parse/string/parse, **not equality with the original whitespace**. Their expected
literal bytes are also null. Original `AssertExpressions` calls are preserved
symbolically; their helper is not executed by extraction.

The four sample failures retain `require.ErrorContains` and its original literal
substring `parse error : invalid parameter (must be greater than 0)`. They do not
claim an exact error string, position or HTTP envelope. The no-op label case
also retains the original assertion that the optimized pipeline has zero stages.

### Direct queries versus constructed/transformed ASTs

Every row has explicit `query_is_direct_input` and
`expected_is_same_expression` booleans:

- `query_is_direct_input: true` means the original literal query is passed to a
  parser or the HTTP query parameter. It does **not** mean successful parsing,
  supported Pulse syntax, or an available literal output expectation.
- `expected_is_same_expression: true` means the output/equivalence contract is
  about that directly parsed expression, rather than a transformed internal AST.
  It is still necessary to check `operation`, actual expected bytes and the
  original assertions. A true flag does not turn an equivalence/reference check
  into a literal text oracle.
- The ten sketch formatting rows parse their original `in`, then call
  `NewCountDistinctSketchFromLabelAggregation` **before** formatting. They keep
  `query_is_direct_input: true`, `expected_is_same_expression: false`, a
  `transformation` description, every literal expected output and the complete
  original constructor call. **Do not parse their `__count_distinct_sketch__`
  output as the expected user-facing spelling of the original query.**
- The serialization sketch case likewise has the second flag false.
- The five `LineParserExpr` rows and six `Grouping` rows have null query bytes,
  both flags false, and symbolic constructor provenance. Their literal output
  fragments are **not whole LogQL query inputs**.
- The four explicit parse failures and invalid HTTP-format response have the
  second flag false: there is no successful parsed-expression output oracle.

### HTTP format response contract

Both original HTTP cases are preserved. The success row retains literal
`Status: "success"` and `Data: "{foo=\"bar\"}"`. The invalid row retains
`Status: "invalid-query"` and the exact original `Err` string:
`parse error at line 1, col 6: literal not terminated`.

`expected_response` records only explicitly supplied struct fields, each with
its original literal value and provenance. Omitted Go zero-value fields are not
invented as new source literals. The success `Data` is also exposed as
`expected_bytes_base64`; the invalid row has null expected bytes. Neither row
has an invented `reject` boolean. The upstream test decodes a Go
`FormatQueryResponse` and compares it with `tc.expected`; **it has no explicit
HTTP status-code assertion and no exact JSON body-byte oracle**.

## Internal JSON serialization is not a wire API

All three complete functions in `serialize_test.go` are retained symbolically:

1. The 15 named rows parse their literal queries, `EncodeJSON` the **internal
   Loki AST**, `DecodeJSON`, then compare `expr.Pretty(0)` with
   `actual.Pretty(0)`. They contain no literal serialized JSON or formatted output
   oracle; none is computed here.
2. The sketch row constructs the internal sketch AST from the parsed label
   aggregation, round trips it with `EncodeJSON`/`DecodeJSON`, and compares
   `sketch.String()` with `actual.String()`. Both sides are symbolic calls.
3. The complete shared-table executor references `ParseTestCases` from
   `parser_test.go`, selects `tc.err == nil`, and explicitly skips inputs
   containing `KiB` because of the upstream byte-conversion round-trip bug.
   It encodes/decodes the AST and calls `AssertExpressions(t, tc.exp, actual)`.
   The complete source includes the skip message and all assertions.

The last function's `shared_table_reference` points to the existing complete
`syntax-admission.json` / `ParseTestCases` selection rather than copying its 206
rows or runtime AST constructors. Its source range/hash describe the original
AST `ValueSpec` (`ParseTestCases = ...`, excluding the enclosing `var` keyword
and trailing newline); this hash is intentionally distinct from the existing
fixture's full declaration selection hash. The existing syntax fixture is not
modified or duplicated.

These tests specify Loki-internal serialization and AST equivalence only. They
do **not** specify Pulse query results, Pulse wire JSON, a public Loki JSON AST
endpoint, HTTP `format_query` response bytes, or portable runtime constructors.
Consumers must keep `operation: symbolic` and these contracts out of public
wire-format parity counts, while preserving their complete source provenance.

## Schema version 1

Top-level keys include `schema_version`, `revision`, `sources`, `tables`,
`row_count`, `literal_query_count`, `literal_expected_count`,
`explicit_reject_count`, `operation_counts` and the fixture-level qualification.

Flatten **only concrete source rows** with `[.tables[].rows[]]`. Each table has
its original function `name`, `operation`, complete `selection`, original
`assertion_calls`, `row_count` and `rows`. Literal-table functions also include
the exact `table_source`. The shared serialization executor intentionally has
an empty `rows` array plus `shared_table_reference` and its explicit contract.

Every row has:

- `table` and zero-based `source_index`, preserving original row identity;
- `operation` from `string`, `prettify`, `roundtrip`, `http-format`, `grouping`,
  or `symbolic`, plus the two direct/same-expression booleans described above;
- authoritative `query_bytes_base64` and `expected_bytes_base64`, **null when
  there is no corresponding literal**; original `query_expression` and
  `expected_expression`, also nullable;
- complete `original_go`, `source`, `source_range` and a `provenance` record;
- original subtest `name` when a literal name is supplied, otherwise an empty
  string for generic table rows; original derived names remain in the executor;
- supplementary `fields`, `contract`, `transformation`, `expected_reference`,
  `expected_response`, width, error or constructor/assertion records as applicable.

Only the four explicit `require.ErrorContains` cases contain `reject: true` and
`error_oracle: substring`, with `expected_error_contains` decoded directly from
the source assertion and `error_provenance`. Absence of `reject` is not a
fabricated successful-admission assertion. There is no `reject: false` default.

Ranges use one-based lines/columns and zero-based half-open byte intervals.
AST ranges end before the trailing newline; complete function selection text
and hashes include that one verified original newline. Other source records
contain exactly their node bytes without a synthesized newline. Source hashes
cover entire files including final newlines. Selection hashes are carried in
JSON, not reconstructed by executing source expressions.

## Offline regeneration and validation

No Loki dependencies, network or Python are required. Normal fixture replay
does not require Go. To regenerate using a pinned local checkout:

```sh
scratch=$(mktemp -d .amp/in/formatter-roundtrip.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp test/fixtures/logs/loki-upstream/formatter-roundtrip-producer.go.txt "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go build -o "$scratch/producer" "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go vet "$scratch/producer.go"
"$scratch/producer" /tmp/amp-librarian/grafana__loki > "$scratch/formatter-roundtrip.json"
cmp "$scratch/formatter-roundtrip.json" test/fixtures/logs/loki-upstream/formatter-roundtrip.json
jq '{row_count,literal_query_count,literal_expected_count,explicit_reject_count,operation_counts}' \
  test/fixtures/logs/loki-upstream/formatter-roundtrip.json
```

Checks performed with Go **1.25.10**:

- Standard-library-only producer **build and vet passed**; `gofmt` clean.
- Two generator invocations produced **byte-identical** JSON (`cmp` passed).
- An independent temporary standard-library Go validator reparsed the original
  source, checked the full 20-function selections, enumerated original AST table
  elements and independently checked all **196** row counts/identities and
  **62** assertion/control call sites. It decoded the **185** query and **94**
  expected literal expressions with `go/types` constant evaluation, separately
  from the producer's literal decoder, and checked their source membership.
- It verified **845 nested source records**, including byte/line/column ranges,
  five full-file hashes, complete function hashes and the shared selection hash,
  plus the query/same-expression and explicit-reject flags.
- Five changed-source negative controls, one per input file, each failed on the
  corresponding hash guard **before emitting any JSON**.
- The pinned checkout HEAD and clean selected source files were independently
  checked. Owned validation scratch was removed.

No Loki/Pulse runtime was executed during extraction. Those checks establish
source fidelity, not formatter implementation or compatibility. The separate
Pulse replay and its limits follow the artifact hashes below.

| Source/artifact | SHA-256 |
| --- | --- |
| `pkg/logql/syntax/parser_test.go` | `0a8466fd5d9cab3f852f9a18a52dc54b7b1a1ab0c9c6af53ca1df21d9f38ce99` |
| `pkg/logql/syntax/prettier_test.go` | `f4ebfe9075503a491febd1ca60e10a983f17d8580080f1c7f4ea76ba285a8527` |
| `pkg/logql/syntax/ast_test.go` | `b058fddd8f947e159e62e694394819eb358557e040c8c27f4f69d47a16be95a6` |
| `pkg/logql/syntax/serialize_test.go` | `2a0ce1e2b8232ed4098e44c7f489f09b793f5338ae9a55a070abdf13943b8ba8` |
| `pkg/loki/format_query_handler_test.go` | `dfb90519ca32e932462434e033754d7b77451239035c385b2d5a48499fbe5595` |
| `formatter-roundtrip.json` (633,507 bytes) | `d57492fa16163622398393d601c3c8659ff60790ee648bb71798e4793e0c4440` |
| `formatter-roundtrip-producer.go.txt` | `59f5d3f87fba1364c220e634fa7de77cf203936163fb4210a41a09798160f740` |

## Pulse replay and explicit gaps

There is **no LogQL formatter, prettifier, or Loki AST JSON codec in Pulse**.
The existing `/api/v1/format_query` uses the PromQL formatter: its acceptance
of the simple `{foo="bar"}` success input does not establish LogQL support;
`{foo="bar"} | logfmt` rejects. No `/loki/api/v1/format_query` route exists.
Route/formatter inspection is recorded in
`.amp/in/artifacts/loki-formatter-route-probe.log`. The two original format
responses, exact string output, 20/100-column layout, 50 parse/string/parse
equivalence assertions, optimized zero-stage internals and all Loki AST JSON
round trips remain **unimplemented or unproved contracts**, not passing ports.
No production formatter or synthetic string-preserving substitute is added.

`test/pulse/logql/parser_test.exs` separately checks all **185 literal query
inputs** through parsing and pre-storage validation, then all **73 applicable
literal expected spellings**. The eleven constructed parser/grouping fragments
are not fabricated whole queries; transformed sketch outputs are not parsed as
user-facing syntax. Internal serialization inputs receive admission checks only,
never a fabricated public JSON oracle. The shared 206-row syntax table remains
owned by its existing replay, without being counted again here.

These checks preserve eight explicit boundaries rather than changing or
discarding source assertions:

| Complete source function / zero-based row | Source contract | Pulse boundary |
| --- | --- | --- |
| `Test_SampleExpr_String` / 49 | Parse/string/parse a logfmt stage with `code="response.code"`. | Outer grammar accepts; executable field-expression validation rejects the unquoted dotted source. The actual pinned field parser rejects it too; grammar-only success is not pipeline-construction proof. |
| `TestStringer` / 15, 36 | Parse and stringify regex operators on `ip(...)`. | Outer grammar accepts; pre-storage validation rejects `invalid_ip_operation`. Stringification does not establish executable operator support. Both literal expected spellings reject too. |
| `TestJSONSerializationRoundTrip` / 12 | Internal AST round trip containing `source = ip("")`. | Outer grammar accepts; pre-storage validation rejects the empty IP pattern before execution. |
| `Test_SampleExpr_String_Fail` / all four rows | Reject ordinary zero-rank `topk`/`bottomk` with a specific error substring. | Existing ordinary nonpositive-rank policy accepts and returns empty results; this is a compatibility difference, not a passing rejection port. Original error oracles remain unchanged. |

The malformed HTTP-format input rejects query parsing, but its exact formatter
response is not replayed. No diagnostic/body/position or Go sentinel identity
parity is claimed. The initial runtime already had these boundaries; there is
no production red-to-green fix. Initial harness failures exposed the validation
boundaries and an incorrect helper arity, corrected without changing source
oracles or production behavior.

Authenticated HTTP replay in
`test/pulse_web/controllers/loki_upstream_integration_test.exs` adds:

- **1,032 admission requests**: all 185 inputs and 73 same-expression literal
  output spellings, each through instant/range GET/form POST. All **28 rejected
  attempts** prove no provider requests/reads/lists. Empty-store success is
  admission evidence, not a value or formatting oracle.
- **304 nonempty stringer-pair reads**: both sides of all 38 literal equivalence
  pairs across the same four transports. Thirty-six pairs return identical
  actual values, covering scalar folding, precedence, negative-alternative
  expansion and string/IP/pattern alternatives. Two invalid-IP-operator pairs
  reject on both sides in **16 attempts**, all without provider access. Authored
  inputs distinguish alternative branches, matching/near-miss lines and IP
  families; original literal equivalences supply the relational oracles.
- **16 zero-rank reads** on a nonempty ranked source explicitly verify the
  existing empty-result difference for all four original rejection cases.
- **18 escaped-regex/no-op reads** check exact lines/labels and independently
  computed one-entry/one-day rate results for the original three parser-string
  cases and no-op-label query. Raw backticks, doubled backslashes, embedded
  quotes and a missing label matching `.*` exercise actual native storage.
  These are authored value controls, not upstream value assertions or optimized
  internal stage-count proof.

Including **five authored seed writes**, the three HTTP wrappers perform
**1,375 requests**. Successful nonempty controls assert actual Parquet storage
and reads against test-owned loopback S3; this is not external-provider,
deployed-client or capacity acceptance. Shared budgets, source preservation,
storage/native formats and all production behavior remain unchanged.

```sh
ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix test \
  test/pulse/logql/parser_test.exs \
  test/pulse_web/controllers/loki_upstream_integration_test.exs \
  --only formatter_roundtrip_batch:true --warnings-as-errors --seed 2001
```

All four tagged tests pass (391 unrelated tests excluded), without requiring Go,
network downloads or a running Loki. Evidence is retained in
`.amp/in/artifacts/loki-formatter-admission-baseline.log`,
`loki-formatter-focused-baseline.log` and `loki-formatter-focused.log`.

The full suite (`mix test --seed 0 --max-cases 4 --warnings-as-errors`, with the
same toolchain/environment prefix) passes: **2663 passed, 1 skipped, 37 excluded**,
in 362.5 seconds. Evidence is retained in
`.amp/in/artifacts/loki-formatter-full.log`. Compilation with warnings as errors,
scoped formatter checks, strict Credo and `git diff --check` also pass.
