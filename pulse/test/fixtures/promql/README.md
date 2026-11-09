# Independent Prometheus numerical corpus

`conformance.json` defines controlled 30-second input series and expression/time cases, including resets, missing samples, stale markers, NaN/infinities, compensated sums, large values, label matching, classic histograms and Tuist's region enrichment pattern. It covers the new used functions and epoch-aligned nested/offset subqueries. It is synthetic, not production telemetry.

`verified-results.json` contains Pulse's results independently checked by **Prometheus promtool 3.5.0**, linked to the exact source fixture SHA-256. The default test suite checks both the Memory reference path and native Parquet path against these verified results. It does not invoke/download promtool during tests.

Recheck and regenerate explicitly:

```sh
MIX_ENV=test PULSE_CONFORMANCE_RESULTS=test/fixtures/promql/verified-results.json \
  mix run scripts/promql_conformance.exs /path/to/promtool
```

The command is local/offline. It uses a privately owned runtime with memory storage and no production credentials or telemetry. It creates a temporary promtool rule-test file, deletes it on completion and writes verified results **only after** promtool succeeds. Set `PULSE_CONFORMANCE_ARTIFACT=/tmp/failure.yaml` to retain a failed comparison for diagnosis. Use the pinned 3.5.0 oracle when regenerating this snapshot.

Promtool's `fuzzy_compare` accepts adjacent IEEE encodings (one ULP), not label differences. YAML NaN bit patterns differ from computed NaNs, so NaN-containing vectors are tested both by an independent `!= bool` mask and by equality-filtered non-NaN values. Top-k inputs avoid ties because tied ranking is not a deterministic Prometheus label-selection contract. Exact large-epoch timestamp comparisons have separate regression coverage.

The corpus includes 166 basic-math cases for `ceil`, `sqrt`, `exp`, `ln`,
`log2`, and `log10`: negative/zero domains, signed zeros (also observed through
reciprocals), NaN/infinities, the smallest subnormal, the normal/subnormal
boundary, adjacent exponential overflow inputs, underflow, stale markers,
lookback expiry and multiple label sets. The pinned implementation is
[Prometheus v3.5.0](https://github.com/prometheus/prometheus/blob/v3.5.0/promql/functions.go)
(release revision `8be3a9560fbdd18a94dedec4b747c35178177202`).
The complete snapshot has 946 cases, independently checked with promtool 3.5.0
(Go 1.24.5, darwin/arm64). This is a verified Pulse snapshot, not a raw capture
of Prometheus API responses. Offline math replay permits at most one ULP for
finite platform-libm differences; labels, timestamps, signed zero and nonfinite
classes stay exact. Both memory and native Parquet paths replay instant answers
and every math range step. This is component conformance, not deployed-client,
provider or capacity acceptance.

Regeneration additionally checks **780 exact boolean classification cases**
without fuzzy comparison: NaN, either zero, positive/negative infinity and the
sign of every zero result. This prevents fuzzy comparison from accepting
zero versus the smallest subnormal or infinity versus maximum finite. Eight
boundary predicates cover adjacent-to-one logarithms and exponential
underflow/overflow. `log2` and `exp` follow the pinned Go arm64 arithmetic,
including its early exponential underflow; this is not universal Go/libm
bit parity. Go-derived arithmetic retains its BSD/Sun notices alongside
Pulse's MIT license; the notices ship in `priv/third_party/go-math-LICENSE`.

[The Mimir fixtures](mimir/README.md) add 30 verbatim upstream query-engine
integration evaluations, replayed through both HTTP query APIs and memory/S3
storage. Their original expectations, pinned source ranges, licenses and
diagnostic adaptations are documented there. They are independent of this
Pulse-generated, promtool-verified snapshot.

`alert_inventory_contract_test.exs` additionally checks all 104 distinct Prometheus source expressions in the complete 115-rule inventory. Empty-input execution is a grammar/dispatch check, **not** numerical conformance of all 104 expressions or alerting parity. A paused rule's `$__rate_interval` is represented as `5m` for syntax only; importing/enabling it still needs an explicit approved window.
