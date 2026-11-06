# Original Loki error classification and prefix constraints

`error-classification.json` freezes three **complete** tests from
[`pkg/util/server/error_classify_test.go`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/util/server/error_classify_test.go)
at revision `5aa4b9212d64d723f63b2770452054aa23df114d`:

| Complete original function | Lines | Source rows | Original executions |
| --- | --- | ---: | --- |
| `TestClassifyFailure` | 24–118 | 22 | 22 named subtests |
| `TestWrappedLimitErrorStatusPreserved` | 122–160 | 3 | 3 named subtests |
| `TestPrefixBeforeFormat` | 165–197 | 0 | 1 test body, not a table/subtest loop |

Test-derived inputs and assertions are copyright Grafana Labs contributors,
AGPL-3.0-only; the adjacent `LICENSE` applies. The complete `wrapLimit`
supporting function at lines 20–22 is also retained, including both `%w`
operands and its embedded `httpgrpc.Errorf`. No row or assertion is omitted,
deduplicated or replaced with a Pulse-authored substitute.

There are **25 table rows / 25 named subtest executions**, plus the separate
prefix test body, within **3 top-level tests**. These are source-structure
counts, not newly executed Loki tests, HTTP requests or passing Pulse cases.
On a successful original run, classification executes 44 `require` calls,
wrapped limits 9 and prefixes 10: **63 `require` assertion executions**.
The prefix uniqueness guard runs twice and its failure-only `t.Fatalf`
runs zero times on success. Guards, constraints, rows and executions are
intentionally counted separately.

## Complete classification table

Categories below resolve the original named constants from pinned
[`pkg/util/server/error.go:28–37`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/util/server/error.go#L28-L37).
Reasons are the original table literals; neither comes from executing the
classifier or inspecting Pulse results.

| Unchanged row name | Category | Reason |
| --- | --- | --- |
| `nil` | empty string | empty string |
| `canceled` | canceled | client_canceled |
| `deadline` | timeout | query_timeout |
| `max_query_bytes_read` | limit | max_query_bytes_read |
| `querier_too_large` | limit | querier_too_large |
| `interval_limit` | limit | interval_limit |
| `series_limit` | limit | series_limit |
| `blocked` | blocked | blocked_by_policy |
| `parse` | syntax | parse |
| `pipeline` | syntax | pipeline |
| `no_org_id` | user_error | no_org_id |
| `max_entries` | limit | max_entries |
| `max_query_length` | limit | max_query_length |
| `max_entries_400_message_only` | limit | max_entries |
| `max_query_length_400_message_only` | limit | max_query_length |
| `gateway_timeout` | timeout | query_timeout |
| `too_many_requests_generic` | throttled | too_many_requests |
| `max_query_parallelism_message_only` | throttled | too_many_requests |
| `max_query_parallelism` | throttled | max_query_parallelism |
| `unrelated_bad_request` | user_error | bad_request |
| `internal` | internal | downstream_error |
| `unknown_plain` | internal | downstream_error |

Classification rows assert **only category and reason**. Input HTTP constants
do not create extra status/body expectations. Error expressions remain exact
symbolic Go source, including sentinels, context identities, wrappers,
constructors and message-only counterparts. In particular the two parallelism
rows deliberately have different reasons; generic 429 messages are not
promoted into a sentinel-specific reason.

## Wrapped-limit status/body oracles

The three original rows, in order, are `max_query_bytes_read`,
`max_query_length`, `max_entries`. All explicitly want `http.StatusBadRequest`
(400), and each wants its unchanged input message as `clientErr.Error()`.
They also assert `require.ErrorIs(t, wrapped, tc.sentinel)`. JSON retains that
symbolic identity assertion, not an invented JSON representation of a Go error.

The byte-limit body is the original literal. The other two bodies resolve only
the original `fmt.Sprintf` expressions against
[`pkg/util/validation/validate.go:5–11`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/util/validation/validate.go#L5-L11):

- `the query would read too many bytes (query: 5GB, limit: 1GB)`
- `the query time range exceeds the limit (query length: 800h, limit: 721h)`
- `max entries limit per query exceeded, limit > max_entries_limit_per_query (10000 > 5000)`

These wants are not obtained by constructing errors or running
`ClientHTTPStatusAndError`. No newline is appended or body whitespace trimmed.

## Complete prefix inputs and relational constraints

This test has a map, **not a table with literal expected prefixes**. Both actual
entries are enumerated in JSON, in source declaration order solely for stable
serialization; Go map traversal order remains unspecified:

| Map key | Original value expression | Complete resolved template |
| --- | --- | --- |
| `max_entries` | `validation.ErrMaxEntriesLimit` | `max entries limit per query exceeded, limit > max_entries_limit_per_query (%d > %d)` |
| `max_query_length` | `validation.ErrQueryTooLong` | `the query time range exceeds the limit (query length: %s, limit: %s)` |

For each template the original test computes `prefix := prefixBeforeFormat(tmpl)`
and requires it to be nonempty and not contain `%`. It checks a shared `seen`
map for duplicate prefixes, fails on a collision, then records the current name.
The fixture **does not evaluate `prefixBeforeFormat` or freeze invented literal
prefix outputs**.

The original input operation is
`strings.ReplaceAll(strings.ReplaceAll(tmpl, "%s", "x"), "%d", "1")`.
It produces these two fully enumerated **input messages**, not expected outputs:

- `max entries limit per query exceeded, limit > max_entries_limit_per_query (1 > 1)`
- `the query time range exceeds the limit (query length: x, limit: x)`

Each message must match its own template and must not match the other template.
Both ordered cross-pairs are enumerated. The `otherName == name` branch skips
self-comparison. The complete original loop, operations, diagnostic arguments,
`seen` mutation and every assertion call/range are retained in JSON, including
the failure-only `t.Fatalf` call. Short assertion shapes in constraint records
are indexes into those original assertions, not replacements for their text.

The separate **verb-first control** has template `%s exceeded the limit` and
message `any message at all`. It requires `prefixBeforeFormat` to be empty and
`matchesTemplate` to be false, preserving the original assertions themselves.

The **11 logical constraints** are: 2 nonempty, 2 no-percent, 1 pairwise
distinctness, 2 self-match, 2 ordered non-self-match, 2 verb-first controls.
They are not 11 source rows or 11 `require` executions: distinctness is a guard
with a conditional fatal call, leaving 10 successful `require` executions.

## Provenance and schema

The standard-library-only Go producer parses pinned source ASTs. It never
imports Loki/Pulse, constructs their errors, or executes classification,
status mapping, prefix extraction or template matching. Only literal/constant
resolution, the original two validation-message formats and the original
ReplaceAll input construction run during extraction.

Schema version 1 contains:

- `sources`: complete paths and SHA-256 guards for all three source files.
- `selections`: complete original test functions with final newline, ranges,
  SHA-256 hashes and separate row/execution counts.
- `supporting_declarations`: complete original `wrapLimit`, range and hash.
- `resolved_constants`: eight used category declarations and two validation
  templates, each with exact original text/range and complete source hash.
- `standard_library_status_constants`: 400, 429, 500 and 504, resolved from the
  producer's public `net/http` constants, not inferred from error messages.
- `rows`: both complete tables in original order, table-qualified names,
  exact row text/ranges, symbolic inputs, original expected expressions and
  resolved category/reason or status/body/identity wants as appropriate.
- `execution_paths`: both complete `t.Run` blocks and original assertion calls.
- `prefix_constraints`: complete map/control inputs, generated input messages,
  original body/assertion sites, all relational constraints and separate counts.

Unknown expectation identifiers, selectors, calls, operators and value types
reject rather than becoming empty/default wants. Full-file hash guards reject
even changes outside the selected declarations. Existing source bytes must
match; missing sparse-checkout files use local
`git show <pinned-revision>:<path>`, never network fetches or alternate revisions.
Ordinary JSON replay needs no Go, upstream dependencies, network or Python.

These are **Go unit-test oracles**, not malformed HTTP requests or public client
tests. They establish no Pulse acceptance, exact endpoint body contract,
adaptation ledger, storage behavior, provider/capacity limits or deployed-client
parity. The separate adaptation/replay owner must account for Go identities,
wrapping and internal HTTP/gRPC status semantics rather than treating similar
strings as proof. No Pulse expectation is added here.

## Optional offline regeneration

From the Pulse repository root, with `/.amp/in/` already locally excluded:

```sh
scratch=$(mktemp -d .amp/in/error-classification.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp test/fixtures/logs/loki-upstream/error-classification-producer.go.txt "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go build -o "$scratch/producer" "$scratch/producer.go"
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go vet "$scratch/producer.go"
"$scratch/producer" /tmp/amp-librarian/grafana__loki > "$scratch/generated.json"
cmp "$scratch/generated.json" test/fixtures/logs/loki-upstream/error-classification.json
```

Go 1.25.10 built/vetted successfully. Independent regeneration compares
byte-identically. Temporary standard-library Go tests verified all three
complete functions against original source lines/hashes, both actual row
counts and table-qualified uniqueness. Eight unknown-expression/type controls
and a changed-source-hash control rejected as intended. Those temporary tests
were removed; validation logs remain in `.amp/in/artifacts/`.
No Loki classifier or Pulse tests were executed for this extraction.

## Pulse adaptation ledger

**No classifier row is claimed as passing category/reason parity.** Pulse's
operational counters expose bounded success/error/exception outcomes, not Loki's
failure categories/reasons. Adding an unused classifier or interpreting provider
text as trusted client-error identity would not establish compatibility.
Every original row remains frozen above, with the following explicit ownership:

| Classifier row(s) | Public analogue or gap; all category/reason pairs remain unimplemented |
| --- | --- |
| `nil` | Successful nonempty queries are exercised, but emit no empty category/reason pair. |
| `canceled` | Query-context cancellation/499 remains absent. |
| `deadline` | Existing HTTP/deadline tests own native 504, not Loki's classifier. |
| `max_query_bytes_read`, `querier_too_large` | Loki query-byte/querier-size policies are absent; Pulse's scan budgets are not equivalent and retain their own status. |
| `interval_limit`, `series_limit` | Request-local interval admission and native result ceilings exist; no Loki sentinel/classification identity is claimed. |
| `blocked` | No Loki blocked-query policy. |
| `parse`, `pipeline` | Parser/pipeline HTTP tests exist, not classification reason labels. |
| `no_org_id` | Authorized omission uses the default tenant rather than a missing-org-ID error. |
| `max_entries`, `max_query_length` | The HTTP equivalents below test the same original quantities, not wrapped sentinel classification. |
| `max_entries_400_message_only`, `max_query_length_400_message_only` | No internal HTTP/gRPC message-only classifier fallback. Untrusted provider text deliberately remains storage failure. |
| `gateway_timeout` | Native timeout 504 does not prove forwarding/classification of an internal HTTP/gRPC status. |
| `too_many_requests_generic`, `max_query_parallelism_message_only`, `max_query_parallelism` | Native admission uses 429; it has no Loki generic-versus-sentinel reason distinction or parallelism wrapper. |
| `unrelated_bad_request` | No HTTP/gRPC classifier or prefix-based user-error classification. |
| `internal`, `unknown_plain` | Native worker failures use sanitized 500 and storage failures 503; there is no category/reason pair or forwarding of ring diagnostics. |

| Wrapped-limit row | Pulse replay qualification |
| --- | --- |
| `max_query_bytes_read` | Unsupported policy and Go sentinel. Its body is used only as an adversarial provider-string control, never a passing 400 replay. No 5GB scan is performed. |
| `max_query_length` | Adapted public rejection: 800-hour window against 721-hour policy returns original status 400. Pulse's diagnostic retains the exact quantities in nanoseconds rather than the original `800h`/`721h` spelling; the original body remains unchanged in the JSON fixture. Go `ErrorIs`/wrapping is not implemented or asserted. |
| `max_entries` | Adapted public rejection: requested limit 10000 against 5000 returns the original 400 and exact source message inside Pulse's JSON envelope. Go `ErrorIs`/wrapping is not implemented or asserted. |

All **11 prefix constraints** remain unimplemented internal contracts. Pulse
does not classify errors by matching these templates, so a replica prefix helper
and tautological tests would add no public behavior. Original constraints, map
inputs, cross-pairs and verb-first controls are preserved without claiming they
execute against Pulse.

### Executed public checks

`loki_upstream_integration_test.exs`, tag `error_classification_batch`, owns
three tests with **36 authored HTTP attempts**, not 36 source rows:

- Entry limit: four original-quantity rejections, four exact-boundary successes
  at requested limit 5000, and four rejections at 5001. Existing middleware test
  coverage is extended rather than duplicated; original six-hour input/query
  and exact error message remain.
- Query length: four original-quantity rejections (800h versus 721h), four
  exact-721h successes and four one-nanosecond-over rejections. Both endpoints
  and GET/form POST are exercised; accepted cases return the ingested line from
  native Parquet against an owned loopback S3 provider.
- Provider strings: all three original wrapped-limit bodies returned as storage
  errors still yield fixed sanitized 503 JSON on log-query/discovery GET/form
  POST (12 attempts), never client 400 or leaked provider text. This is an
  authored boundary control, not execution of Loki's message-only fallback.

All 16 policy rejections prove no provider operations, even with nonempty
storage. Exact boundary acceptance distinguishes `>` from an erroneous `>=`;
the one-unit-over controls reject ignored or rounded limits. The existing runtime
passed without changes: no runtime fix or red-to-green claim is made.
No resource ceilings, native/storage formats or keyed bytes changed.

```sh
ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix test \
  test/pulse_web/controllers/loki_upstream_integration_test.exs \
  --only error_classification_batch:true --only http_errors_batch:true \
  --only query_policy_batch:true --warnings-as-errors --seed 745
```

| Complete source/selection/artifact including final newline | SHA-256 |
| --- | --- |
| `pkg/util/server/error_classify_test.go` | `3629f2a42093f4b92d6ee4169095b3b8cd562175f9c17cad8aa3b748fd98cc3e` |
| `pkg/util/server/error.go` | `5ada39308f1f1a5f7c43918d92e13e854a50d3dbe35c08348a39db29ffd7f85e` |
| `pkg/util/validation/validate.go` | `f25baad77b4c96f00585209c90d8dec7be92ac5150fce7dfe4b861c302ba3672` |
| `TestClassifyFailure` | `4a6ebacdb4da3a38e15fccb5776814600e2876879b412f7e74d54e971f2e15c0` |
| `TestWrappedLimitErrorStatusPreserved` | `1f0a53061263c771e8851c69a5b102169d904e974c4b6a85dfbdb3d93242d091` |
| `TestPrefixBeforeFormat` | `45a34eb8d3e63886fe730fa1253a2ae864bd595071245fec6f1699bf595e017a` |
| `wrapLimit` | `c1c14280a39a3a9f41ba29a6ba9cddc19619404c3e5d7f7e45d21589f4cf004a` |
| `error-classification.json` | `3b36c4579bbeb718d1e8aa70e92cd1db08a6d123c4f7d1dd46a07e20294390a9` |
| `error-classification-producer.go.txt` | `2af1f77ad7194474b23675f55c6a0814eb76afd1918a572a46448f9e1f92557c` |
