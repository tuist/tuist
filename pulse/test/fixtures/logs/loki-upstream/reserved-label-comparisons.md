# Reserved error-label comparison admission

`reserved-label-comparisons.json` retains the complete
[`TestParseExpr_ShouldValidateLabelComparison`, `pkg/logql/syntax/parser_test.go:3796–3881`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/syntax/parser_test.go#L3796-L3881)
from Grafana Loki revision `5aa4b9212d64d723f63b2770452054aa23df114d`.
Test-derived inputs and assertions are copyright Grafana Labs contributors,
AGPL-3.0-only; the adjacent `LICENSE` applies.

The standard-library-only `reserved-label-comparisons-producer.go.txt` reads
the original Go AST, expands its actual loops and `fmt.Sprintf` calls, and
extracts its `require.Error`/`NoError` and `Contains` assertions. It refuses
source bytes differing from the pinned complete-file hash. It does not execute
Pulse or compute expectations from either parser's answers. All failing source
rows additionally assert `logqlmodel.ErrParse`; the HTTP replay checks Pulse's
`parse_error` category rather than inventing a Go error object.

There are **68 distinct original queries: 56 rejections and 12 admissions**:

- 42 number/duration/byte rejections: two reserved labels × three original
  right-hand values × seven original comparison operators.
- Four original IP rejections: two reserved labels × two operators.
- Six original compound/nested-expression rejections.
- Four original post-unwrap rejections.
- Twelve original successful string/error-label and ordinary-label comparisons,
  including successful unwrap expressions.

No original cases are excluded, deduplicated, rewritten or converted into
authored successful substitutes. These are syntax/admission oracles, not source
log/result-value oracles. The HTTP harness adds one harmless nonempty logfmt
line, authenticated tenant access, a short time window and an explicit step;
the original queries themselves remain unchanged.

The `:reserved_label_comparisons_batch` wrapper in
`test/pulse_web/controllers/loki_upstream_integration_test.exs` sends every row
through both instant/range endpoints and GET/form POST: **272 query requests**,
224 rejected and 48 admitted. Every rejected request must leave all recorded
provider requests, reads and lists unchanged. Successful requests use native
Parquet and the native S3 client against the existing owned loopback provider.
The wrapper verifies a published Parquet segment and actual Parquet reads.
This is public-interface integration evidence, not deployed-provider or client
acceptance, and does not claim complete parser/diagnostic parity.

The first valid baseline replay (seed 733) fails on the first original query,
`{app="foo"} | logfmt | __error__ > 0`: existing evaluation-time validation
returns HTTP 400 `evaluation_failed` / `:invalid_error_filter`, not the original
parse-error contract. Parser construction now rejects only these reserved-label
typed comparisons, including nested/post-unwrap predicates. Existing validation
of directly supplied ASTs remains intact. String/regex comparisons, ordinary
typed labels, pipeline error ownership, selector/duplicate policies and all
resource ceilings remain unchanged. Only the required error category and
reserved-label diagnostic fragments change; exact Loki positions/full text are
not claimed. Upgrade query-serving applications; native/storage bytes do not change.

The identical seed-733 wrapper passes after the parser change. The adjacent
parser, pipeline-correctness and query-controller suites pass 187 tests (seed
734). Earlier setup attempts corrected a hand-calculated case count and shortened
the harness window before the valid baseline; they are not behavioral proof.
The combined/full suite is left to the coordinating agent.

## Reproduction

Normal replay needs only the project's Elixir/Rust toolchain, no Go or downloads:

```sh
ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix test \
  test/pulse_web/controllers/loki_upstream_integration_test.exs \
  --only reserved_label_comparisons_batch --seed 733 --warnings-as-errors

ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix test \
  test/pulse/logql/parser_test.exs \
  test/pulse/logql/pipeline_correctness_test.exs \
  test/pulse_web/controllers/loki_query_controller_test.exs \
  --seed 734 --warnings-as-errors
```

Optional offline fixture regeneration with Go and an existing pinned checkout:

```sh
cp test/fixtures/logs/loki-upstream/reserved-label-comparisons-producer.go.txt /tmp/reserved-label-comparisons-producer.go
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go build \
  -o /tmp/reserved-label-comparisons-producer /tmp/reserved-label-comparisons-producer.go
/tmp/reserved-label-comparisons-producer \
  /tmp/amp-librarian/grafana__loki/pkg/logql/syntax/parser_test.go \
  > /tmp/reserved-label-comparisons.json
cmp /tmp/reserved-label-comparisons.json test/fixtures/logs/loki-upstream/reserved-label-comparisons.json
jq '{rows: (.rows|length), rejected: ([.rows[]|select(.reject)]|length), accepted: ([.rows[]|select(.reject|not)]|length)}' \
  test/fixtures/logs/loki-upstream/reserved-label-comparisons.json
```

Regeneration with Go 1.25.10 reproduced the checked-in fixture byte-for-byte.
Recorded red/green/adjacent test logs are in `.amp/in/artifacts/loki-reserved-label-{red,green,adjacent}.log`.

| Source/artifact, including final newline | SHA-256 |
| --- | --- |
| Complete pinned `pkg/logql/syntax/parser_test.go` | `0a8466fd5d9cab3f852f9a18a52dc54b7b1a1ab0c9c6af53ca1df21d9f38ce99` |
| Complete original function, lines 3796–3881 | `8ea521448046f7250640073322aad458a9792311992061bec98722505277c5aa` |
| Frozen JSON | `86bf7eb754b13987dc3c2abcff4e7344e1de2f1ea61ab63475456473da89fbfc` |
| Producer | `db7bfaf7eca267782df24681a67d1cb986ce58d3df00999d8469802d7335958a` |
