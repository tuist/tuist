# Original Loki label-parsing source tests

`label-parsing.json` freezes two complete functions from Grafana Loki revision
`5aa4b9212d64d723f63b2770452054aa23df114d`, without executing them:

| Original function in `pkg/logql/syntax/parser_test.go` | Lines | Literal rows | Original output pairs | Additional control |
| --- | --- | ---: | ---: | --- |
| [`TestParseLabels`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser_test.go#L3698-L3739) | 3698–3739 | 4 | 6 | One trailing oversized-input rejection |
| [`TestParseUnreservedWordsAsLabelNames`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser_test.go#L3782-L3794) | 3782–3794 | 4 | 0 | None |
| **Total** | | **8** | **6** | **1 rejection** |

Test-derived inputs and assertions are copyright Grafana Labs contributors,
AGPL-3.0-only; the adjacent `LICENSE` applies. No selected source rows or
trailing statements are omitted, rewritten, deduplicated or substituted.
`TestNoOpLabelToString` and `TestParseSampleExpr_String` are neighboring
formatting/optimization tests, explicitly outside this increment.

## Original oracles, not computed results

The four label rows preserve their original descriptions: `basic`,
`multiple labels, already sorted`, `multiple labels, not sorted` and
`strip empty label value`. Each `expected_labels` array contains the original
ordered name/value pairs decoded **only from that row's actual
`labels.FromStrings(...)` arguments**, not by parsing or sorting its input.
There are four such calls, with pair counts **1, 2, 2, 1**. Their complete
symbolic expressions and all twelve original argument records remain frozen.
The unsorted input still has the upstream sorted output oracle; the
empty-valued `bar` input still has only the upstream `job=foo` output oracle.
No constructor is run to obtain either result.

The complete executor retains `got, _ := ParseLabels(tc.input)` and
`require.Equal(t, tc.output, got)`. In particular, it discards the error:
there is **no separate `NoError` assertion** for these four label rows.
`accepted_count` describes the source's non-rejection/output cases, not an
additional error oracle or an observed execution result.

The four unreserved-word queries preserve exact original literal bytes and
use the original query as their `t.Run` name. Their executor calls
`ParseExpr(query)` and `require.NoError(t, err)`. These are admission oracles
for `variants` and `of` in selectors, grouping and pipeline label filters.
They specify no output label set; none is inferred from the query text.

### The trailing oversized input is included

`controls[0]` preserves the three original statements at lines 3736–3738:

```go
input := strings.Repeat("a", 1<<24)
_, err := ParseLabels(input)
require.Error(t, err)
```

The producer decodes the original string argument to byte **97** (`a`, base64
`YQ==`) and the original shift expression to **16,777,216 repetitions/bytes**.
It never calls `strings.Repeat` or allocates a 16 MiB input for JSON. The
construction, executor, parser call and assertion are separate source records,
also retained inside the complete original `TestParseLabels` function.
The original assertion requires only an error. `error_oracle` is
`presence_only`, `reject` is true and `expected_error` is null. No exact error
text, identity or position is invented from the implementation below.

## Supporting source contract

Three supporting selections preserve complete original source:

- [`ParseLabels`, lines 296–302](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser.go#L291-L302),
  with its separate original documentation record: calls `ParseMetric`,
  propagates errors, then calls `WithoutEmpty()` to normalize stream labels.
- [`ParseMetric`, lines 311–317](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser.go#L304-L317),
  with its separate original documentation record: retains empty-valued labels,
  checks the byte-length limit and delegates to the Prometheus metric parser.
- [`maxStreamLabelsSize`, line 22](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser.go#L16-L23):
  retains the **complete enclosing `const` declaration**, including its two
  sibling constants and comments, plus the specific `value_spec` and symbolic
  `value_expression` `1<<24 - 1`. Its decoded value is **16,777,215 bytes**.
  The trailing rejected input is exactly one byte above that limit.

These distinguish empty-label normalization by `ParseLabels` from retention
by `ParseMetric`; the latter is supporting implementation evidence, not an
additional selected upstream test table. This fixture makes no Pulse outcome,
adaptation, resource-label rewriting, HTTP/storage/client compatibility or
capacity claim. The separate Pulse replay and boundary qualifications follow.

## Pulse replay and boundary qualifications

All **eight literal rows and the separate oversized-input rejection** replay
with the native project toolchain. No Go/Loki process or network download is
needed. The existing runtime requires no change; there is no runtime red-to-green
claim.

`test/pulse/loki/push_test.exs` feeds every original label string, unchanged,
through the public Snappy/protobuf decoder. The four original label maps match
the record-backed discovery projection, including input-order independence and
empty-label omission. Unlike Loki's `ParseLabels`, Pulse deliberately retains
the original empty `bar` label in `Log.resource`. The component test pins this
source-preservation difference rather than rewriting the original output oracle
or changing raw labels to satisfy it.

Authenticated HTTP replay in
`test/pulse_web/controllers/loki_upstream_integration_test.exs` verifies:

- Four original label strings enter through protobuf push, then all four
  expected label maps return from `/series` through GET/form POST: **four
  writes and eight discovery reads**. Exact per-entry time windows isolate
  each row. A subsequent actual S3/Parquet record read proves `bar=""` remains
  stored even though public discovery omits it. JSON label maps preserve
  identity, not the ordered Go-label representation or serialized key order.
- All four original unreserved-name queries execute via instant/range GET/form
  POST: **16 read requests**. Two authored input streams distinguish `variants`
  and `of` in selectors, grouping and pipeline filters. Correct labels, lines
  and grouped counts are checked as authored runtime controls, not invented
  upstream value oracles; upstream asserts admission only.
- The original 16,777,216-byte repeated input, wrapped unchanged in a valid
  protobuf push, rejects with **HTTP 413 / `payload_too_large`**, with no provider
  requests or publication. The component decoder also rejects it. This happens
  at the **whole decompressed-request cap**, not Go's standalone 16,777,215-byte
  label-parser limit. It proves bounded rejection of the original input, not
  equality of parser limits or diagnostics. Malformedness is not the size-error
  oracle.

An additional one-byte malformed-label control follows the existing **204 with
one rejected entry** policy and makes no provider request; it is not falsely
reported as an HTTP parse rejection. A valid protobuf push and successful native
read prove recovery afterward. Including two authored seed writes and those
drop/recovery controls, the HTTP replay performs **34 requests total**. Direct
storage verification is separate from that HTTP count.

The original label executor's discarded error remains unasserted source data;
the replay's successful protobuf decoding is an additional public-boundary
check, not a fabricated upstream `NoError` assertion. Broader label grammar,
duplicate/escape/UTF-8 policies, exact diagnostics, standalone parser capacity,
formatting/optimization tests and deployed-client/provider-capacity acceptance
remain outside these selected tables. Source preservation and all existing
resource ceilings stay unchanged.

```sh
ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix test \
  test/pulse/loki/push_test.exs \
  test/pulse_web/controllers/loki_upstream_integration_test.exs \
  --only label_parsing_batch:true --warnings-as-errors --seed 1991
```

All four tagged tests pass (309 unrelated tests excluded). Evidence is retained
in `.amp/in/artifacts/loki-label-parsing-baseline.log` and
`loki-label-parsing-selected.log`.

The full suite (`mix test --seed 0 --max-cases 4 --warnings-as-errors`, with
the same toolchain/environment prefix) passes: **2659 passed, 1 skipped,
37 excluded**, in 235.3 seconds. Its log is
`.amp/in/artifacts/loki-label-parsing-full.log`. Compilation with warnings as
errors, scoped formatter checks, strict Credo and `git diff --check` also pass.

## JSON schema, version 1

The envelope contains `schema_version`, `revision`, `sources`,
`supporting_declarations`, `tables`, `controls` and aggregate counts:

- `row_count: 8`, `accepted_count: 8`, `rejected_count: 0` count **literal
  table rows only**.
- `label_pair_count: 6` counts pairs from original expected-output calls.
- `control_count: 1`, `rejected_control_count: 1` count the separate symbolic
  oversized-input control. Thus the fixture has **nine source cases**, not
  eight with a silently dropped rejection.
- `exact_error_count: 0` means no selected assertion supplies an exact error.

Each `tables[]` item contains `name` (original function name), `selection`
(complete original function), `table` (slice literal), `executor` (complete
range statement including its inline table), `parser_calls`, `assertion_calls`,
counts and `rows`. Flatten literal replay rows with `[.tables[].rows[]]`;
replay the separate `controls` explicitly rather than treating it as a literal.

Each row contains:

- `table` and zero-based `source_index`: stable original identity.
- `name`: original `tc.desc` for labels, original query for unreserved words.
- `query_bytes_base64`: authoritative decoded original Go-literal bytes;
  `query_expression`: verbatim source literal; `query`: decoded text;
  `query_utf8_valid`: true. No whitespace is trimmed.
- `reject: false`, `expected_error: null`: original non-rejection case, subject
  to the exact assertion distinctions above.
- `expected_labels_present`, `expected_labels_expression`, `expected_labels`:
  true plus original symbolic call and ordered `{name, value}` pairs for label
  rows; false/null/null for unreserved-word rows. Label rows additionally have
  `expected_labels_source` with original constructor expression, argument
  records and source provenance.
- `source`, `source_range`, `original_go`: complete original row provenance.

The separate control has parent `table`, `control_index: 0`, a descriptive
fixture `name` (the trailing upstream code has no `t.Run` name), `construction`,
`query_expression`, `executor`, `parser_calls`, `assertion`, `assertion_calls`,
`repeat_expression`, `repeat_bytes_base64`, `repeat_byte`,
`repeat_count_expression`, `repeat_count`, `query_byte_count`,
`materialized: false` and the error-presence fields described above. It has
no fake literal `source_index`, `query` or full `query_bytes_base64`.

Source records use one-based lines/columns and zero-based half-open byte
ranges `[start_byte, end_byte_exclusive)`. Selection `original_go` and its
SHA-256 include one original trailing newline; the AST range ends before it.
Other records preserve exact AST-node bytes without adding a newline.
The three parser-call and three assertion-call records across the tables and
control are **source call sites**, not runtime execution counts.

## Offline regeneration and checks

The standard-library-only Go AST producer follows the method of
`matcher-admission-producer.go.txt`. It reads two pinned files and refuses
changed full-file SHA-256 hashes before extracting anything. It does not build,
import or modify Loki, run constructors or execute Pulse. No dependencies,
network or Python are needed; normal fixture replay needs no Go toolchain.

```sh
scratch=$(mktemp -d .amp/in/label-parsing.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp test/fixtures/logs/loki-upstream/label-parsing-producer.go.txt "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go build -o "$scratch/producer" "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go vet "$scratch/producer.go"
"$scratch/producer" /tmp/amp-librarian/grafana__loki > "$scratch/label-parsing.json"
cmp "$scratch/label-parsing.json" test/fixtures/logs/loki-upstream/label-parsing.json
jq '[.tables[] | {name,row_count,label_pair_count}], .controls' \
  test/fixtures/logs/loki-upstream/label-parsing.json
```

Go **1.25.10** built and vetted the producer successfully; `gofmt -d` was
empty. Two producer invocations were byte-identical (`cmp` exit 0). A separate
temporary standard-library Go validator independently located tables by AST
type, enumerated all eight literal inputs and original subtest names, checked
all six output pairs directly against `labels.FromStrings`, independently
decoded the original oversized repeat geometry, and checked the three complete
supporting declarations. It verified **45 nested source records**, including
byte/line/column ranges, selection hashes and entire-source hashes. The pinned
checkout revision and clean selected source files were checked independently.
Changed-source negative controls rejected before emitting JSON. Scratch was
removed. No Loki/Pulse constructors, runtime or tests were run.

| Complete source/artifact, including final newline | SHA-256 |
| --- | --- |
| `pkg/logql/syntax/parser_test.go` | `0a8466fd5d9cab3f852f9a18a52dc54b7b1a1ab0c9c6af53ca1df21d9f38ce99` |
| `pkg/logql/syntax/parser.go` | `a38e8d4760af3969d5316e456db8abed93655a66fd81f8cfdd2fa50226142667` |
| Complete `TestParseLabels` function | `2e7f98beb5947cb225d4cc38eac6feb62b416669e135529e02e64f3e5ee4a988` |
| Complete `TestParseUnreservedWordsAsLabelNames` function | `c2c1d663ff88a6f3d91b64009633ecf206517e4467403841432667567dc031f9` |
| Complete `ParseLabels` function | `e6ca047ff65c97fd86ff7147b7bb902d5ba87c98d4faf620217b9b627bdf16be` |
| Complete `ParseMetric` function | `ad2132476a90e64caf1d2d32e7170e153a8887169b37934be7856a2247926a58` |
| Complete enclosing `const` declaration | `705dec29c2dce742221749cb0407abd97cff094c67ce06ebed23a2ef2181a981` |
| `label-parsing.json` | `cc909a965753978a91b1a48ac6303ee750d2a0c0152aa8475a71510e6d8aedf8` |
| `label-parsing-producer.go.txt` | `bc122ee82be0d4297305191a1cb0572c60b00a2b0240cd0984fd75953dd2d867` |

The JSON is **30,778 bytes**, not a materialized oversized-input fixture.
These are source-extraction checks, not observed Loki outcomes, full parser
parity, deployed compatibility or resource-capacity acceptance.
