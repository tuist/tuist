# Original Loki matcher-admission tables

`matcher-admission.json` freezes exactly three complete source functions from
Grafana Loki revision `5aa4b9212d64d723f63b2770452054aa23df114d`:

| Original function in `pkg/logql/syntax/parser_test.go` | Lines | Rows | Accept | Reject |
| --- | --- | ---: | ---: | ---: |
| [`TestParseMatchers`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser_test.go#L3364-L3413) | 3364–3413 | 4 | 2 | 2 |
| [`TestParseSampleExpr_equalityMatcher`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser_test.go#L3581-L3659) | 3581–3659 | 19 | 9 | 10 |
| [`TestParseLogSelectorExpr_equalityMatcher`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser_test.go#L3661-L3696) | 3661–3696 | 7 | 4 | 3 |
| **Total** | | **30** | **15** | **15** |

Test-derived inputs and assertions are copyright Grafana Labs contributors,
AGPL-3.0-only; the adjacent `LICENSE` applies. No source rows are omitted,
deduplicated, rewritten or replaced. Neighboring `ParseLabels`, formatting,
benchmark and other parser tests are separate contracts and are not these tables.

## Source oracles and boundaries

The first function's positional rows specify input, expected matchers and
`wantErr`. Its complete executor retains the original
`ParseMatchers(tt.input, true)` call, the error-presence comparison
`(err != nil) != tt.wantErr`, the early return on disagreement, and the
`require.Nil`/`AssertMatchers` branches. The original **`true` validation
argument is preserved**, never changed to false to obtain an admission.

Only its two successful rows specify expected matcher tuples: **five literal
`mustNewMatcher` calls** in source order. Their original symbolic expressions,
individual arguments and normalized `name`/`op`/`value` are retained. Lexical
operator normalization is `labels.MatchEqual` → `=`, `labels.MatchNotEqual` →
`!=`, `labels.MatchRegexp` → `=~`, `labels.MatchNotRegexp` → `!~`; each tuple also
retains `operator_symbol`. No numeric Go enum values are assumed. Neither
`mustNewMatcher` nor `labels.NewMatcher` nor any regex compiler is executed.
The original `mustNewMatcher`, `AssertMatchers` and `RemoveFastRegexMatchers`
functions are frozen as supporting declarations, including the assertion's
removal of compiled regex implementation details before comparison.

The two equality-matcher functions have keyed `in`/`err` rows. Omitted `err`
means accept; a present non-nil error expression means reject. The original
executors call `ParseSampleExpr(tc.in)` and `ParseLogSelector(tc.in, true)`,
respectively, then `require.Equal(t, tc.err, err)`. They **do not specify
matcher-result tuples**; none are invented by parsing their queries. There
are five assertion-call source records across the three executors, not five
executed tests or a fixed runtime assertion count across conditional branches.

There are **13 exact original error-constructor tuples**. Twelve reference
[`errAtleastOneEqualityMatcherRequired`, `parser.go:19`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser.go#L19):
sample-table indices `1,4,6,7,8,10,15,16,17` and log-selector indices `1,4,6`.
The original declaration and decoded constant value are preserved with source
range and full-file hash provenance. Sample index `18` instead retains the
literal diagnostic `syntax error: unexpected RATE, expecting IDENTIFIER or )`
at line `1`, column `16`. Constant-based errors retain original `0,0` positions.

`expected_error.diagnostic` is exactly the original constructor's
`{message, line, column}`, **not** an executed `Error()` rendering. The pinned
`ParseError` type, `NewParseError` constructor and `Error` method from
[`pkg/logqlmodel/error.go`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logqlmodel/error.go)
remain complete supporting declarations. Unknown error/helper expression
forms keep their original source and `resolved: false`, never guessed values.
All 13 original error calls and all five original matcher calls resolve here.

The **other two rejections are boolean-only** `TestParseMatchers` rows.
The upstream table supplies no exact diagnostic for them; their
`expected_error` remains null. Do not infer diagnostic text from a later run.
These are source admission/matcher/error oracles, not HTTP, storage, result,
resource-capacity, deployed-client or Pulse compatibility claims. No Pulse
outcomes or adaptations are encoded in the JSON. Replay and any policy ledger
are recorded separately below.

## Pulse replay and policy ledger

The component replay in `test/pulse/logql/parser_test.exs` checks all 30 rows.
The four matcher-only rows require a log selector with no pipeline, preserving
all five original matcher name/operator/value expectations in source order.
General `Parser.parse/1` may accept the pipeline in matcher-table index `3`;
that is not a matcher-only admission. Its rejection is verified at the public
series-discovery boundary, not by pretending the whole query is invalid LogQL.
Sample/log expression rows use parsing followed by static pre-storage validation,
as in the complete syntax-table replay.

**18 original admission outcomes agree: 15 accepts and three rejections.**
The remaining **12 original rejections** are explicit existing policy
differences, not skipped or passing upstream cases:

| Source table | Zero-based indices | Original rejection | Pulse policy |
| --- | --- | --- | --- |
| `TestParseSampleExpr_equalityMatcher` | `1,4,6,7,8,10,15,16,17` | At least one selector leaf has no matcher excluding empty label values, including nested binary leaves and empty distinct-count selectors. | These valid expressions remain admitted under server scan/work/output ceilings. |
| `TestParseLogSelectorExpr_equalityMatcher` | `1,4,6` | Negative-only or empty-compatible selector. | These valid selectors remain admitted under the same server ceilings. |

The component test pins every exception's original error expression to
`logqlmodel.NewParseError(errAtleastOneEqualityMatcherRequired, 0, 0)` and checks
Pulse admission separately. Neither the original validation arguments nor JSON
expectations are rewritten. There is no new opt-out flag or relaxed server
budget, and no production change.

Authenticated HTTP replay in
`test/pulse_web/controllers/loki_upstream_integration_test.exs` executes all
30 rows via GET and form POST. Matcher-only rows use `/series` with `match[]`
(eight attempts); sample/log rows use both `/query` and `/query_range`
(104 attempts). All **112 table attempts** run against empty owned S3 storage
to isolate admission from data-dependent evaluation. All **eight rejected
attempts** retain HTTP 400 and verify no provider requests/reads/lists occur.
Success statuses are not upstream value oracles or full execution proof.

A separate authored seven-stream native Parquet/owned-loopback-S3 control uses
the two original accepted matcher inputs, verifying exact selected streams
through GET/form POST. Full-value regex matching is distinguished from substring
matching with prefix/suffix near-misses; negative regexes retain a longer
nonmatching value. Original negative-only sample/log inputs additionally prove
that the deliberate policy actually executes: two present non-`bar` labels and
one missing `foo` label survive, while `foo="bar"` streams do not. Metric counts
and complete log labels/lines are checked through GET/POST, with both query
modes for logs. These **ten authored read attempts** are separate from the 112
source-table attempts. They do not manufacture source result expectations.

Exact Go error identity/text/positions, compiled regex representation, neighboring
`ParseLabels`/formatting tests, deployed clients and provider/capacity acceptance
remain outside this increment. Existing instant-log-query compatibility
differences are unchanged.

Replay without Go or a running Loki:

```sh
ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix test \
  test/pulse/logql/parser_test.exs \
  test/pulse_web/controllers/loki_upstream_integration_test.exs \
  --only matcher_admission_batch:true --warnings-as-errors --seed 1982
```

All three tagged tests pass (385 unrelated tests excluded). The unchanged
runtime baseline already admits the same 12 policy exceptions; there is no
runtime red-to-green claim. Evidence is retained in
`.amp/in/artifacts/loki-matcher-baseline.log` and `loki-matcher-selected-green.log`.
The full `mix test --seed 0 --max-cases 4 --warnings-as-errors` replay passed
**2655 tests**, with one skip and 37 opt-in exclusions; its log is
`.amp/in/artifacts/loki-matcher-full.log`.

## JSON schema, version 1

The envelope has `schema_version`, `revision`, `sources`, `resolved_constants`,
`supporting_declarations`, `tables`, and aggregate `row_count`, `accepted_count`,
`rejected_count`, `matcher_tuple_count`, `exact_error_count` and
`boolean_only_rejection_count`.

Each `tables[]` item has `name` (source function name), counts, `selection`
(the complete original function), `table` (the original anonymous slice
literal), `executor` (the complete original range statement), `parser_calls`,
`assertion_calls` and `rows`. With inline-table executors, the executor includes
the table too. Flatten replay rows without changing their identities using
`[.tables[].rows[]]`.

Each row contains:

- `table`: original source function name; `source_index`: zero-based within
  that table. The pair is the stable identity, not the query text.
- `query_bytes_base64`: authoritative decoded original Go-literal bytes;
  `query_expression`: verbatim original literal; `query`: decoded UTF-8;
  `query_utf8_valid`: true for all 30 current inputs. Nothing is trimmed.
- `reject`: original `wantErr` or original non-nil `err` presence, never an
  observed parser result. `want_err_expression` preserves the positional
  boolean where supplied and is null in the keyed tables.
- `expected_matchers_present`, `expected_matchers_expression`,
  `expected_matchers`: a true presence flag and literal expression for every
  positional matcher want, including `"nil"`. A non-nil original list yields
  ordered records containing `name`, `op`, `value`, `operator_symbol`,
  `resolved`, `constructor_expression`, ordered original `arguments`, and
  source metadata. The two explicit nil wants produce null lists; the keyed
  tables supply no wants and have false presence flags and null expressions.
- `expected_error_present`, `expected_error_expression`, `expected_error`:
  absent fields are false/null/null; an original error call retains its raw
  expression, constructor/argument source records, `resolved` and, when
  resolvable, `diagnostic: {message, line, column}`. No explicit nil error field
  occurs in these tables; the schema preserves its expression if encountered.
- `source`, `source_range`, `original_go`: full row provenance and text.

Source records throughout the fixture retain `source`, `source_range` and
`original_go`. All ranges use one-based lines/columns, zero-based byte offsets
and a half-open `[start_byte, end_byte_exclusive)` interval. Selection text and
its SHA-256 include one trailing original newline; the AST range itself ends
before that newline. Other records preserve the exact node bytes without an
added newline. Complete functions preserve all whitespace, executors,
conditions, assertions and comments, even where normalized fields are absent.
`sources` hashes cover entire original files, not only selected snippets, and
the producer refuses any changed bytes in those five files.

## Offline regeneration and verification

The producer follows the standard-library-only Go AST method of
`syntax-admission-producer.go.txt`. It reads pinned files without building or
modifying Loki. No dependencies, network, Python, Loki constructors or Pulse
runtime are needed. Normal fixture consumers need no Go toolchain.

```sh
mkdir -p .amp/in
scratch=$(mktemp -d .amp/in/matcher-admission.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp test/fixtures/logs/loki-upstream/matcher-admission-producer.go.txt "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go build -o "$scratch/producer" "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go vet "$scratch/producer.go"
"$scratch/producer" /tmp/amp-librarian/grafana__loki > "$scratch/matcher-admission.json"
cmp "$scratch/matcher-admission.json" test/fixtures/logs/loki-upstream/matcher-admission.json
jq '[.tables[] | {name,row_count,accepted_count,rejected_count}]' \
  test/fixtures/logs/loki-upstream/matcher-admission.json
```

Go **1.25.10** built and vetted the producer successfully; `gofmt -d` was empty.
Two invocations generated byte-identical JSON (`cmp` exit 0). A separate
temporary standard-library Go check independently located anonymous source
tables by AST type rather than producer statement positions, enumerated all
30 original rows and checked literal query bytes, indices, original admission,
all five matcher tuples and all 13 diagnostic tuples. It also verified **126
nested source records**, including all byte/line/column ranges, complete
selections, supporting declarations, arguments, assertions and selection
hashes against the original source bytes. Scratch files were removed after
validation. No Loki/Pulse runtime, constructors or HTTP tests were run for
this extraction.

| Complete source/artifact, including final newline | SHA-256 |
| --- | --- |
| `pkg/logql/syntax/parser_test.go` | `0a8466fd5d9cab3f852f9a18a52dc54b7b1a1ab0c9c6af53ca1df21d9f38ce99` |
| `pkg/logql/syntax/parser.go` | `a38e8d4760af3969d5316e456db8abed93655a66fd81f8cfdd2fa50226142667` |
| `pkg/logqlmodel/error.go` | `21816c4294243f16157f6408d92fb0907612a3258333288ab39b3f84bf7a4db5` |
| `pkg/logql/syntax/test_utils.go` | `9fcfb55c03fe98c52c19b00f3dc058c7d92c16dcf2138a39fc851a62cc6d67df` |
| `pkg/logql/syntax/ast.go` | `87eb6811c68654e2b2f7d629d799d215dc79fb549e0f9d71a805a46bd51e1e69` |
| Complete `TestParseMatchers` function | `587442f4625c0d42e0e6772ceadee5a9abb300e9c09ef56b86deaeffaa0ee1d7` |
| Complete `TestParseSampleExpr_equalityMatcher` function | `5d647a773115ac726857ceebf220e11e0ecb0d086fe3181e3da7a94a13d68f93` |
| Complete `TestParseLogSelectorExpr_equalityMatcher` function | `656686469d6490c0096e4712f93509aed356980d18122d11f9a6843ada9c39c2` |
| `matcher-admission.json` | `91b78febdb59e04609c73c12a0ec320af3749075bcd3eaf37c49f3a281f3d5dd` |
| `matcher-admission-producer.go.txt` | `bd91f8fb1e409db296b1218dc0e4a643a912bf87331864abd235339d45b48da5` |
