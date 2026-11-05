# Original Loki HTTP error-writer table

`http-errors.json` freezes the **complete 25-row `Test_writeError` table** in
[`pkg/util/server/error_test.go:41–96`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/util/server/error_test.go#L41-L96)
at Grafana Loki revision `5aa4b9212d64d723f63b2770452054aa23df114d`.
Test-derived inputs and assertions are copyright Grafana Labs contributors,
AGPL-3.0-only; the adjacent `LICENSE` applies. The vendored dskit string
declaration retains its Apache-2.0/Weaveworks provenance in the pinned
[`vendor/github.com/grafana/dskit/user/id.go`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/vendor/github.com/grafana/dskit/user/id.go).

There are **25 source rows, not 50 rows**. Upstream executes each row twice:

1. **Direct**, lines 75–82: `WriteError(tt.err, rec)`.
2. **Roundtrip**, lines 84–94: `WrapError(tt.err)`, `UnwrapError(status)`, then
   `WriteError(unwrappedErr, rec)`; the original subtest name appends `-roundtrip`.

That is **50 upstream subtest executions**, with a status equality, successful
body read and body equality assertion in each execution (150 assertion calls).
This describes the source test structure, not 50 newly executed Loki tests or
50 Pulse HTTP requests. No requested row is omitted, deduplicated, rewritten,
or replaced with an authored substitute.

The optional producer imports only the Go standard library. It parses source
ASTs and extracts original inputs/wants; it does not execute Loki error
classification, serialization, parsers, or Pulse. Ordinary fixture decoding
needs no Go toolchain, network, Python, or upstream dependencies.

## Complete selection

Rows remain in source order. Status totals are **9 × 400, 3 × 499, 8 × 500,
5 × 504**; the two execution paths double those counts without adding rows.
Exact bodies, including spaces and punctuation, are in JSON rather than
rephrased here.

| Original name | Source line | Original status |
| --- | ---: | ---: |
| `cancelled` | 49 | 499 |
| `cancelled multi` | 50 | 499 |
| `rpc cancelled` | 51 | 500 |
| `rpc cancelled multi` | 52 | 500 |
| `mixed context and rpc cancelled` | 53 | 500 |
| `mixed context, rpc cancelled and another` | 54 | 500 |
| `cancelled storage` | 55 | 499 |
| `orgid` | 56 | 400 |
| `deadline` | 57 | 504 |
| `deadline multi` | 58 | 504 |
| `rpc deadline` | 59 | 504 |
| `rpc deadline multi` | 60 | 504 |
| `mixed context and rpc deadline` | 61 | 504 |
| `mixed context, rpc deadline and another` | 62 | 500 |
| `parse error` | 63 | 400 |
| `parse error wrapped in grpc status` | 64 | 400 |
| `interval limit` | 65 | 400 |
| `httpgrpc` | 66 | 400 |
| `internal` | 67 | 500 |
| `query error` | 68 | 400 |
| `wrapped query error` | 69 | 400 |
| `multi mixed` | 70 | 500 |
| `multi httpgrpc client errors` | 71 | 400 |
| `multi httpgrpc server errors` | 72 | 500 |
| `multi httpgrpc client error among untyped errors` | 73 | 400 |

## Scope and nonportable contracts

These are **Go error-writer unit-test oracles**, not malformed HTTP request
inputs, LogQL parser tests, or end-to-end endpoint assertions. The fixture
contains no invented Pulse expectations, adaptation decisions, replay ledger,
or claim of Pulse acceptance. Replay/adaptation ownership is separate.

- Every roundtrip execution exercises Loki's internal gRPC/protobuf status
  boundary. It is not a second public HTTP operation and must not be relabeled
  as Pulse HTTP roundtrip coverage.
- Thirteen direct rows also construct gRPC-specific errors: all eight rows
  containing `rpc` in their names at lines 51–54 and 59–62, the typed wrapper
  at line 64, and the four `httpgrpc` rows at lines 66 and 71–73. Their
  `codes.Canceled`/`DeadlineExceeded`/`Unknown`, `Code(400)`/`Code(500)`, status
  wrappers and exact `rpc error: code = ... desc = ...` spellings are Go/Loki
  contracts, not evidence that Pulse exposes the same internal error types.
- `grpcStatusWrappedErr` deliberately both unwraps to a typed parse error and
  exposes a non-HTTP gRPC status. Its complete type and three methods are
  retained in `supporting_declarations`, not replaced with an ordinary parse
  error. The distinction is essential to the original precedence assertion.
- The other twelve direct rows still use Go identities and wrappers:
  `context.Canceled`, `context.DeadlineExceeded`, `util.MultiError`,
  `promql.ErrStorage`, tenant/query sentinels and `%w` wrapping. Their error
  identity, wrapping and aggregate precedence cannot be established just by
  making an endpoint return a similar string. In particular, homogeneous
  cancellation/deadline aggregates differ from mixed aggregates; RPC
  cancellation is not treated as direct context cancellation.
- Status **499** is Loki's explicit nonstandard client-closed-request
  constant, not an inference from HTTP standard status names. A recorder can
  assert a body for a canceled context; a real disconnected client may never
  receive one. The empty `ParseError{}` body's final space is intentional.
  All 25 original body wants lack a trailing newline; do not append one or
  trim their whitespace during replay.
- The selected test asserts status, body-read success and exact body bytes.
  It does **not** assert response headers, JSON envelopes, authorization,
  request validation order, deadlines firing, retries, storage behavior,
  deployed clients, provider/capacity limits or a successful response path.
  Headers seen in the implementation are not promoted into new source wants.

## JSON schema, version 1

The envelope contains `schema_version`, `revision`, `row_count` and
`upstream_execution_count`, plus:

- `sources`: all five complete source paths and SHA-256 hashes. Regeneration
  refuses changed bytes, including changes outside selected declarations.
- `selections`: the complete original `Test_writeError` text with one trailing
  newline, source range, SHA-256, table name and both counts.
- `supporting_declarations`: original gRPC wrapper type/method source and ranges.
- `resolved_constants`: six actual original declarations, their symbolic names,
  resolved values, original text, source ranges and complete source-file hashes.
  Five resolve strings; `StatusClientClosedRequest` resolves integer 499.
- `standard_library_status_constants`: the three public `net/http` constants
  named in the table, resolved by the producer's standard library, not inferred
  from error text. They are 400, 500 and 504.
- `execution_paths`: the complete original direct/roundtrip `t.Run` blocks,
  name expressions and each of their three original assertion calls/ranges.
- `rows`: original source order, `table`, unchanged `name`, source range,
  `original_go`, symbolic `input.error_expression`, `expected_expressions`,
  resolved `expected: {status, body}`, and two `executions`. Each execution
  retains its original name, mode and the shared original status/body want.

Inputs remain symbolic Go expressions because recreating error identities,
gRPC statuses or `errors.Is` behavior in the producer would manufacture an
alternative implementation. Body wants come only from the original table's
string literals, string concatenation and the following pinned declarations:

| Symbol | Source and declaration line |
| --- | --- |
| `ErrClientCanceled` | `pkg/util/server/error.go:142` |
| `ErrDeadlineExceeded` | `pkg/util/server/error.go:143` |
| `StatusClientClosedRequest` | `pkg/util/server/error.go:139` |
| `logqlmodel.ErrIntervalLimit` | `pkg/logqlmodel/error.go:16` |
| `storage_errors.ErrQueryMustContainMetricName` | `pkg/storage/errors/errors.go:3` |
| `user.ErrNoOrgID` | `vendor/github.com/grafana/dskit/user/id.go:22` |

For the three string-carrying error declarations, extraction unwraps only
their original `errors.New("...")` / `QueryError("...")` literal and the
original `.Error()` expression. It does not derive wants from error inputs or
observed writer output. Unknown declarations, symbols, calls, operators or
value types fail rather than becoming empty/default expectations. Names are
not Go testing's display-name space substitutions.

## Optional offline regeneration and checks

Run from the Pulse repository root, with `/.amp/in/` already in the local Git
exclude file. The existing pinned checkout may be sparse: a missing source
file is read using `git show <pinned-revision>:<path>` from that local checkout.
Existing files always use their actual bytes and must match the pinned hash;
the producer never fetches Git objects or substitutes a different revision.

```sh
mkdir -p .amp/in
scratch=$(mktemp -d .amp/in/http-errors.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp test/fixtures/logs/loki-upstream/http-errors-producer.go.txt "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go build \
  -o "$scratch/producer" "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go vet "$scratch/producer.go"
"$scratch/producer" /tmp/amp-librarian/grafana__loki > "$scratch/http-errors.json"
cmp "$scratch/http-errors.json" test/fixtures/logs/loki-upstream/http-errors.json
jq '{rows:(.rows|length), executions:([.rows[].executions[]]|length)}' \
  test/fixtures/logs/loki-upstream/http-errors.json
```

Go **1.25.10** built and vetted the producer successfully. Independent
invocations regenerated byte-identical JSON (`cmp` exit 0). Independent
`jq` checks confirmed 25 unique row names, 50 unique execution names, matching
direct/roundtrip expectations and all six assertion-call records. The embedded
selected function was independently compared byte-for-byte with source lines
41–96, including its final newline. Temporary standard-library Go tests
confirmed unknown identifiers/selectors/calls/operators and changed source
hashes reject; those scratch tests were removed after validation.
No Loki/Pulse test execution or HTTP compatibility claim is made here.

## Pulse adaptation ledger and HTTP checks

The following ledger accounts for every direct row without turning frozen
oracles into passing compatibility claims. **None of the 25 exact-body rows is
claimed as a byte-for-byte Pulse replay.** Pulse deliberately returns JSON with
sanitized operational errors rather than Loki's plaintext writer bodies.
Four rows have equivalent categories/statuses exercised through public HTTP;
21 retain an explicit incompatible or unimplemented contract. All 25 internal
gRPC roundtrips are unimplemented, not a second set of passing HTTP tests.

| Original direct row(s) | Pulse ownership or explicit gap |
| --- | --- |
| `parse error` | Adapted: malformed LogQL through instant/range GET/form POST returns source status 400 and JSON `parse_error`; the empty Go `ParseError{}` body is not reproduced. |
| `interval limit` | Adapted: `maxQueryInterval=1s` with a 2s range selector rejects before storage through both endpoints/methods, with source status 400 and the unchanged source message prefix. |
| `deadline` | Adapted: an adapter-reported `query_timeout` returns source status 504 and fixed JSON on all 15 finite-read shapes/both methods. Existing `query_deadline_batch` tests separately prove actual worker deadlines and blocked native S3 GET recovery. |
| `internal` | Adapted: a blocked query worker is terminated with a non-kill failure; every finite-read shape/both methods returns source status 500 and fixed JSON, not the original `foo` body. |
| `orgid` | Incompatible: authorized omitted tenant uses Pulse's default tenant. No missing-org-ID 400 is invented. Existing tenant/authentication tests own that behavior. |
| `query error`, `wrapped query error` | Incompatible: Pulse permits selectors without a metric-name matcher. These Go storage-query sentinels and wrapping do not exist in its storage contract. |
| `cancelled`, `cancelled multi`, `cancelled storage` | Gap: no explicit query-context cancellation/499 response contract, Go storage wrapper or homogeneous cancellation aggregate. Disconnecting a real client is not evidence it received a 499 body. |
| `rpc cancelled`, `rpc cancelled multi`, `mixed context and rpc cancelled`, `mixed context, rpc cancelled and another` | Gap: no Loki internal gRPC error identities or mixed cancellation precedence. |
| `deadline multi`, `rpc deadline`, `rpc deadline multi`, `mixed context and rpc deadline`, `mixed context, rpc deadline and another` | Gap: native timeout checks do not establish homogeneous or mixed Go/RPC aggregate precedence. |
| `parse error wrapped in grpc status` | Gap: no typed parse error that also exposes a gRPC status; ordinary parse admission is not a substitute. |
| `httpgrpc`, `multi mixed`, `multi httpgrpc client errors`, `multi httpgrpc server errors`, `multi httpgrpc client error among untyped errors` | Gap: no Go HTTP/gRPC status wrappers or multi-error prioritization. Provider failures remain sanitized 503, not arbitrary forwarded status/body pairs. |

`loki_upstream_integration_test.exs`, tag `http_errors_batch`, owns four tests
with **98 error HTTP attempts**: eight parse/interval attempts and 30 each for
timeouts, worker failures and provider errors. The four source statuses are read
from the frozen JSON, never generated from Pulse. Inputs are explicitly authored
public equivalents of Go error objects, not original source HTTP requests.
The 15 shapes include raw/metric queries, discovery, index stats/volumes,
detected fields/values/labels and patterns. Both GET and form POST are exercised.
Faults are injected through a test-owned adapter; this is public HTTP/error
boundary coverage, not a real provider outage or execution of Loki's Go tests.

The additional authored provider-error control found raw private terms in
discovery responses before the fix. All finite reads now return the same fixed
503 JSON without exposing the provider term. The test restores S3, ingests one
line and verifies a successful native Parquet read against an owned loopback
store (one additional recovery read). Client rejections prove no provider access.
No resource ceilings, native/storage formats or keyed bytes changed.

The separate upstream `TestClassifyFailure`,
`TestWrappedLimitErrorStatusPreserved` and prefix-template tests are not part of
`Test_writeError`; their complete source inventory and qualified public checks
now live in [the classifier/limit continuation](error-classification.md).
Internal classification/wrapping remains unimplemented. Neither selection
establishes general exact diagnostics, deployed-client acceptance or provider/capacity behavior.

```sh
ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix test \
  test/pulse_web/controllers/loki_upstream_integration_test.exs \
  --only http_errors_batch:true --only query_deadline_batch:true \
  --warnings-as-errors --seed 744
```

| Complete source/artifact, including final newline | SHA-256 |
| --- | --- |
| `pkg/util/server/error_test.go` | `d250f31887b80c5ded25a7ea04630192ee3701b1ca53ec4265cf8ffb20c7caca` |
| `pkg/util/server/error.go` | `5ada39308f1f1a5f7c43918d92e13e854a50d3dbe35c08348a39db29ffd7f85e` |
| `pkg/logqlmodel/error.go` | `21816c4294243f16157f6408d92fb0907612a3258333288ab39b3f84bf7a4db5` |
| `pkg/storage/errors/errors.go` | `c413c44b1dbc8f3842ae897193351088027c96674eec90d94137b591c9e5b1a0` |
| `vendor/github.com/grafana/dskit/user/id.go` | `ed142d00dabb6581aead5a42ddf06024c775a1f3f5f6436db5940243d3284464` |
| Selected `Test_writeError` function | `ddfa9f9b6a7a0c055bb46d4e272325acb36946a4cb3db48c3052d8e66857837e` |
| `http-errors.json` | `17fc5ca560c3ab679fc7057a67209daef1b255c4f6b919981da91e8cabca7a1d` |
| `http-errors-producer.go.txt` | `cb97e2efd48268ed5a350fe3537de2867c67f548fb2cf9f552e289539a6eccfb` |
