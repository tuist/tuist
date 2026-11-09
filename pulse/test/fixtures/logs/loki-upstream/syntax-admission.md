# Original Loki syntax-admission table

`syntax-admission.json` freezes the **complete `ParseTestCases` declaration**
in [`pkg/logql/syntax/parser_test.go:21–3352`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser_test.go#L21-L3352)
and its complete [`TestParse` executor, lines 3354–3362](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser_test.go#L3354-L3362),
at Grafana Loki revision `5aa4b9212d64d723f63b2770452054aa23df114d`.
Test-derived inputs and assertions are copyright Grafana Labs contributors,
AGPL-3.0-only; the adjacent `LICENSE` applies.

There are **206 original rows: 159 admissions and 47 rejections**. Admission
comes only from the original row's `err` field being absent or explicitly
`nil`; a present, non-nil error expression means rejection. Neither expected
AST shape nor observed parser output determines this classification.

There are 205 unique query byte strings. Source indices **50 and 55** contain
the same query, `{foo="bar"} |= "baz" |= ip("123.123.123.123")`, and both remain
as separate rows. No original row is excluded, deduplicated, rewritten or
replaced with an authored substitute. The source executor invokes
`require.Equal(t, tc.err, err)` and `AssertExpressions(t, tc.exp, ast)` for
every row: 412 assertion calls structurally, not a claim of 412 executed tests.
Both original assertion calls and their source ranges are recorded separately.

The optional producer imports only the Go standard library. It parses original
source ASTs and decodes original Go string literals with `strconv.Unquote`.
It does **not** execute `ParseExpr`, Loki constructors, expected-AST helper
functions or Pulse. All expected AST expressions, including constructors,
symbols and nested fields, remain verbatim symbolic Go source. A constructor
that performs validation is not evaluated to infer a replacement expectation.

## Byte-preserving queries

Every row has authoritative `query_bytes_base64`, decoded from its original
Go literal, plus `query_expression` retaining that literal verbatim. For valid
UTF-8, `query` is the same decoded string and `query_utf8_valid` is true.
Multiline whitespace and escapes are not trimmed or normalized.

**Source index 120 intentionally contains invalid UTF-8**:
`"{app=~\"\xa0\xa1\"}"`. Its query bytes are hex
`7b 61 70 70 3d 7e 22 a0 a1 22 7d`, Base64 `e2FwcD1+IqChIn0=`.
Because JSON strings cannot represent those bytes faithfully, this one row has
`query: null` and `query_utf8_valid: false`; consumers must decode
`query_bytes_base64`, not invent replacement characters or omit the row.
This is the original rejection with diagnostic `invalid UTF-8 encoding`,
line 1, column 7, not an authored invalid-query control.

## Original errors, not manufactured diagnostics

Every rejection uses the original `logqlmodel.NewParseError` call. All 47
have resolvable original message/line/column arguments: 46 messages are string
literals, and one names `errAtleastOneEqualityMatcherRequired`. That constant's
original declaration and decoded value are extracted from pinned
[`pkg/logql/syntax/parser.go:19`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser.go#L19).
The producer recognizes only this actual original grammar: that constructor,
three arguments, a string literal or the pinned constant, and integer-literal
line/column values. Unknown constructors, expressions, symbols or computed
positions retain raw source with `resolved: false`, never guessed text.

`diagnostic.message` is the constructor's original message argument, **not**
the formatted result of Go's `Error()` method. `diagnostic.line` and `column`
retain original values, including zeros; no query positions are recomputed.
The original `ParseError` type, `NewParseError` constructor and `Error` method
from pinned [`pkg/logqlmodel/error.go`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logqlmodel/error.go)
are retained as supporting declarations. No full-message formatting is executed.

These are source syntax/AST/error unit-test oracles, not result-value, HTTP,
storage, capacity or deployed-client claims. The JSON fixture contains no Pulse
expectations; the separate replay and adaptation ledger follow below.

## Pulse admission replay and explicit differences

`test/pulse/logql/parser_test.exs` replays every original query byte string
through parsing followed by static pre-storage validation. Loki's `ParseExpr`
combines grammar and constructor validation; Pulse separates those stages.
The replay compares admission, not Go AST identity or exact diagnostic text/
positions. All original AST expressions and diagnostics remain in the fixture.

**204 of 206 rows agree with the original admission outcome**: 158 accept and
46 reject. Two existing policies deliberately differ; neither is a skipped or
passing upstream oracle:

| Zero-based source index | Original oracle | Pulse policy |
| --- | --- | --- |
| 0 | Accept a count query whose raw-string line-filter regex ends in a single backslash (exact bytes in JSON). | Grammar accepts; eager regex validation rejects the trailing backslash before storage. Loki's expected AST does not compile the line-filter pattern. |
| 42 | Reject `approx_count_distinct(mac, {}[1d]) by (version)` because the selector has no nonempty-compatible equality/regex matcher. | Empty selectors remain allowed under the existing server scan/work/output ceilings. |

The first row's exact query bytes and original Go literal are authoritative in
JSON; its invalid regex is the five letters `error` followed by one backslash.
The component test explicitly pins its regex-validation error and the unchanged
empty-selector admission. No production behavior or resource ceiling changes.

`test/pulse_web/controllers/loki_upstream_integration_test.exs` additionally
executes all 206 rows through authenticated GET and form POST on both instant
and range endpoints: **824 HTTP attempts**. Empty owned S3 storage isolates
admission from data-dependent execution errors. Every one of the 188 rejected
attempts verifies no provider requests/reads/lists occur. This includes all four
transport variants of the original invalid UTF-8 row. The duplicate source rows
are both executed, not collapsed. Accepted statuses are not upstream value
oracles or full pipeline execution proof.

A separate authored nonempty control ingests two matching lines and a differently
labelled noise line, then checks count `2` over native Parquet/owned loopback S3
via GET and POST. These two requests are not included in the 824 table attempts.
Exact error bodies/categories/positions, Go AST equivalence, arbitrary nonempty
pipeline semantics and complete parser/helper tables outside `ParseTestCases`
remain open. In particular static validation may report an evaluation error
category rather than Loki's parse-error category while still rejecting before
storage.

Replay with the native toolchain, without Go or a running Loki:

```sh
ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix test \
  test/pulse/logql/parser_test.exs \
  test/pulse_web/controllers/loki_upstream_integration_test.exs \
  --only syntax_admission_batch:true --warnings-as-errors --seed 1972
```

Both tagged wrappers passed (383 unrelated tests excluded). The full suite with
`mix test --seed 0 --max-cases 4 --warnings-as-errors` passed **2652 tests**, with
one skip and 37 opt-in exclusions. Evidence is retained in
`.amp/in/artifacts/loki-syntax-selected-green.log` and `loki-syntax-full.log`.
The initial baseline already agreed on the same 204 outcomes; there is no
runtime red-to-green claim. Initial new-test failures were harness assertions
(regex error tuple shape and count-helper expected-point shape), both corrected
without production changes or altering source oracles.

## JSON schema, version 1

The envelope contains:

- `schema_version`, `revision`, `row_count`, `accepted_count`, `rejected_count`,
  `unique_query_count`, `duplicate_query_row_count`, `invalid_utf8_query_count`.
- `sources`: three original source paths and complete-file SHA-256 hashes.
  Regeneration refuses changed bytes anywhere in those files.
- `selections`: complete original declaration and executor, `name`, `source`,
  `source_range`, `original_go` and `sha256`. Selection text includes exactly
  one trailing newline. Both selections have independent pinned hash guards.
- `assertion_calls`: the two complete original calls, source paths/ranges.
- `resolved_constants`: the one original named message declaration, source
  range, symbolic `name` and decoded string `value`.
- `supporting_declarations`: original parse-error type, constructor and method,
  each with source, range, original text and selection hash.
- `rows`: all 206 entries in original source order. Each has zero-based
  `source_index`, `source`, `source_range`, complete row `original_go`,
  `query_expression`, `query_bytes_base64`, `query_utf8_valid`, `query`, `reject`,
  `expected_ast_present`, `expected_error_present`, `expected_ast_expression`
  and `expected_error_expression`.

Absent AST/error fields have JSON-null expression values and false presence
flags. Explicit Go `nil` is retained as the string `"nil"` with a true presence
flag. This distinguishes omission from an explicit nil want without executing
the expected AST. When an error field is present, `expected_error` additionally
retains `original_go`, source/range and `resolved`. Calls also retain
`constructor_expression` and ordered `arguments` (each original expression
with its source/range). A
resolvable call adds `diagnostic: {message, line, column}`. No diagnostic object
is synthesized for an unresolved expression.

All source ranges use one-based lines/columns and zero-based byte offsets;
the end position is immediately after the last byte of the AST node, using
the half-open interval `[start_byte, end_byte_exclusive)`. Ranges exclude a
trailing newline, while
selection `original_go` and hashes include the added original newline. Row
snippets preserve comments inside the row; the complete declaration also
retains all comments and whitespace between rows.

## Optional offline regeneration and checks

Normal fixture decoding needs no Go, upstream dependencies, network or Python.
Regeneration needs an existing checkout containing the three pinned source
files. It does not fetch, modify or build Loki.

```sh
mkdir -p .amp/in
scratch=$(mktemp -d .amp/in/syntax-admission.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp test/fixtures/logs/loki-upstream/syntax-admission-producer.go.txt "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go build \
  -o "$scratch/producer" "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go vet "$scratch/producer.go"
"$scratch/producer" /tmp/amp-librarian/grafana__loki > "$scratch/syntax-admission.json"
cmp "$scratch/syntax-admission.json" test/fixtures/logs/loki-upstream/syntax-admission.json
jq '{row_count, accepted_count, rejected_count, unique_query_count,
     duplicate_query_row_count, invalid_utf8_query_count}' \
  test/fixtures/logs/loki-upstream/syntax-admission.json
```

Go **1.25.10** built and vetted the producer successfully. A second invocation
regenerated byte-identical JSON (`cmp` exit 0). Temporary standard-library Go
checks independently reparsed all 206 source rows and compared decoded query
bytes, symbolic AST/error expressions, indices, row source snippets and both
complete selections. Unknown error grammar retained raw source without guessed
diagnostics; a changed-source hash control rejected. Independent `jq` checks
confirmed the 159/47 split, consecutive indices, all 47 resolved original
errors and both assertion records. These scratch checks were removed after
validation; logs remain at `.amp/in/artifacts/loki-syntax-admission-validation.log`.
No Loki/Pulse runtime or HTTP tests were run for this fixture-only extraction.

| Complete source/artifact, including final newline | SHA-256 |
| --- | --- |
| `pkg/logql/syntax/parser_test.go` | `0a8466fd5d9cab3f852f9a18a52dc54b7b1a1ab0c9c6af53ca1df21d9f38ce99` |
| `pkg/logql/syntax/parser.go` | `a38e8d4760af3969d5316e456db8abed93655a66fd81f8cfdd2fa50226142667` |
| `pkg/logqlmodel/error.go` | `21816c4294243f16157f6408d92fb0907612a3258333288ab39b3f84bf7a4db5` |
| Complete `ParseTestCases` declaration | `476eab68004f9a52beaf52e0820ec099d497bd781ca230e5cd06d114b39f2757` |
| Complete `TestParse` executor | `91dd9d3f5f254bb2b9f7491227084b615413739413081ba3a59c69162ac63dfb` |
| `syntax-admission.json` | `0c323cd2e4f8d7111bd0f6517fbe9b53f32e214b78e7578c3cde870d589fb2e8` |
| `syntax-admission-producer.go.txt` | `c3fa3c7696ba47b56514944d1f43ba7218a1780361433f951a17054c845b7cf4` |
