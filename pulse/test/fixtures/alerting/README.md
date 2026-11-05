# Expression math reference fixture

`expression-math.json` contains **968 synthetic cases**. ExUnit replays them with
Elixir/Rust only: no Go, Python, Grafana server, SDK, container or network is
required by automated tests or normal builds.

The independent producer was a temporary standalone Go harness using the
**Grafana v12.3.0** `mathexp/parse` package, the unchanged `unaryOp` and `binaryOp`
function excerpts from `mathexp/exp.go`, and a small custom label-union/nullable
number driver. The driver models equal/subset labels, singleton fallback, empty
set early return and dropped-item counts. It does **not** execute the complete
Grafana server, datasource conversion, graph commands, lifecycle, templates,
notifications or scheduling. The source commit of the inventoried deployed
Grafana 13.3 build was unavailable through the public source endpoint; this
fixture is **not deployed-version or migration acceptance**.

Cases cover all fourteen binary operators on the cross product of null, NaN,
infinities, finite values and both zero signs, unary operators, precedence,
octal/decimal syntax, label union/empty/duplicate dimensions, and integer-input
float64 rounding near 2^53, 2^59 and signed int64 extrema. Source integers are
converted by Go `float64(int64)` in the independent producer, not by Pulse.
Expected finite values are shortest round-trip decimal strings; `-0` is retained.

## Provenance and integrity

Sources are under
`https://github.com/grafana/grafana/tree/v12.3.0/pkg/expr/`:

| Source | SHA-256 |
| --- | --- |
| `mathexp/parse/parse.go` | `19361016f53fa39f7aaf7349e1dc2f0a3009840268b79cadb2d46314b6ceb6c7` |
| `mathexp/parse/lex.go` | `426729ffc1ba36dcfa8d7821ac32236eac6c19b4a0de2b5ab7956f949f882a34` |
| `mathexp/parse/node.go` | `ea553e7e0534a5f7f2f4b44af194bafd44cd3fd66fe55b5e0b6c709ae99e4627` |
| `mathexp/exp.go` | `9fbc7f3368fa92344161b77c72269a51b01112f0925e6c4706bcfed665562efa` |
| `mathexp/reduce.go` (review reference) | `1437e79528f2cde5181dc8c442d92f2572985e9689f5b7a3f2d7eea9d588440a` |
| `threshold.go` (review reference) | `4bb6fddb726e94974fe29e8122dc939bff70e25e3139d1db6dcc567cb4673997` |

Temporary complete Go driver/excerpt source SHA-256:
`ec33c2a0f1f11b4427f82cd0815767170edd5cd740e928619c39b308747e4749`.
It is an external fixture producer, not repository runtime or tooling authority.
That temporary driver is not shipped; its hash records provenance, not a promise
of reproducible reconstruction from this repository. Regeneration requires
rebuilding and reviewing an equivalent harness from the pinned upstream sources
and the protocol below. Upstream executable source is not vendored into this MIT
project.

Fixture SHA-256:
`a88723939b7e6d0feafe6348113ab933c42e24d443f09df04340c5486fef55b3`.

## Optional independent regeneration

The Elixir case generator accepts an independently supplied reference executable:

```sh
mix run --no-start scripts/grafana_expression_conformance.exs \
  /path/to/independent-expression-reference \
  test/fixtures/alerting/expression-math.json
```

The executable takes one input JSON path and writes the resulting case array to
stdout. Each input has `name`, `expression`, and `inputs` keyed by ref. Each set
has `kind: scalar|numbers` and `frames` with `labels` and a decimal-string/null
`value`; an optional decimal `int64` overrides the value before float64 conversion.
Outputs add `expected` with the same set shape (finite/nonfinite numeric strings)
and an integer `drops` count. The checked-in generator creates inputs only and
never invokes Pulse's expression evaluator to manufacture expected answers.

## Loki quantile reference

`loki-quantiles.json` contains 63 synthetic interpolation cases from public
**Loki v3.6.6**, not the deployed Loki backend. A temporary standalone Go producer
used the `Quantile` function excerpt from `pkg/logql/range_vector.go`. Its only
algorithm adaptations replace the Prometheus sample vector with `[]float64`,
`.F` accesses with direct indexing, and its sorter with Go `sort.Float64Slice`
(NaNs first). Inputs cover empty/singleton/unsorted samples, out-of-range
quantiles, NaN/infinities, signed zero and large finite values. It does not run
Loki ingestion, parsers, label extraction, grouping, query evaluation or HTTP.
Tests replay pinned JSON without an external runtime.

Finite arithmetic is compared with relative tolerance `1e-14` and a one-smallest-
subnormal floor because Go on ARM may fuse the weighted multiply/add while BEAM
rounds each operation.
Zeros and nonfinite values are checked as exact terms, including the zero sign.
This is algorithm evidence, not bit-exact cross-architecture or alert-boundary
parity. Grouping and public query regressions use separate synthetic local tests.

| Source/artifact | SHA-256 |
| --- | --- |
| v3.6.6 `pkg/logql/range_vector.go` | `1b73200708f63571f0c375b5da83f124d0e2edd2f6a2aac6f09962691a9ffed7` |
| v3.6.6 `pkg/logql/syntax/ast.go` (validation review) | `ccfa07dcd28949f889ac85efe459c276d4d25e6eb22ebf4bbeadbfbc9a196c40` |
| Temporary complete producer | `0afa1cee8ff7c10fd64537fa1ab21ea7854a96e64fab29a072ff351482a528df` |
| `loki-quantiles.json` | `f56aebc9d9bb0db7219c61f62dc39004a8b6d70f92de16eaf8bff65da195cde5` |

The producer is not vendored into this MIT repository. Its JSON protocol accepts
an array of `{q: decimal_string, values: [decimal_string]}` and adds
`expected: decimal_string`; Go `NaN`, `+Inf`, `-Inf` and `-0` spellings are retained.
Independent regeneration requires a separately reviewed producer from the pinned
upstream source. Never derive expected answers from Pulse's evaluator.

Review the independent producer and source pins before replacing the fixture.
Update this checksum only after conformance passes and any changed semantics have
been explained. Do not regenerate the oracle with the implementation under test.
