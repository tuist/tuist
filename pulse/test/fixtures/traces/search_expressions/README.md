# Same-span search expression provenance

These are synthetic, public-reference fixtures, not private saved queries or
production telemetry. Normal `mix test` replays the bytes with Pulse's Elixir/Rust
toolchain and owned loopback HTTP/S3 stubs. It never builds, probes or executes
Go, a Collector or an SDK.

## Producer and oracle

`produce.go.txt` ran as an additional test inside the actual public **Tempo
v2.9.0** `tempodb/encoding/vparquet4` package. The source archive SHA-256 is
`5b652be7d03b3329a5b986fd8678ea4a9c4849adf2966baf19d20eec01046a44`.
It uses that package's real block builder, Parquet conversion/fetch and
`traceql.NewEngine().ExecuteSearch`, not a handwritten expected-result evaluator.
Its `batch` and `value` helpers come from the already checked-in
[`produce_tempo_search.go.txt`](../produce_tempo_search.go.txt), copied into the
same package. Optional preparation has no Pulse runtime dependency.

The fixed input has **8 traces / 9 spans**. One trace has an earlier frontend
root and a later worker child. Types deliberately include a missing route/code,
integer/bool routes, a string code and a double `503.5`, int64 above 2^53,
unset/OK/error status, and durations on both sides of 500 ms. All IDs/times/data
are synthetic and deterministic.

The **24 search cases** establish:

- Fully anchored `!~` and `!=` require a present original string. Missing and
  other types do not match; `/health` and `.*health.*` differ.
- Same-span status/int64 OR, including a status-only matching branch, a false
  AND branch inside OR, and a resource condition that must not be borrowed from
  another span of the trace.
- Equal-precedence, left-associative AND/OR versus explicit parentheses.
- Original int64 equality/comparisons above 2^53, no double/string coercion.
- Span-duration equality/boundaries/decimal units, distinct from the complete
  retained trace envelope.
- Full retained root/duration/service context before ordering, matched counts
  and sampled spans. Samples contain individually matching typed attributes;
  status is an enum string, duration is not an added attribute.

`durations.json` separately records **12 actual TraceQL parser/storage-condition
results** for compounds, `us`/`µs`, sub-nanosecond fractions, long-fraction Go
rounding and int64 overflow. It caught why exact rational truncation alone is
not Go-compatible: `0.3333333333333333333333m` becomes 20,000,000,000 ns.
Parsing matches the bounded Go fractional-prefix/float64 rounding step;
subsequent comparisons use exact int64 nanoseconds.

Inspection/provider metrics are omitted, not invented. Sample attributes are
sorted by key to remove map iteration order. The corpus was deliberately
expanded from the first 20 search cases to 24 plus literal cases, not normalized
to hide a mismatch. Input bytes did not change. The recorded generation used
Go **1.25.10 darwin/arm64** with the source archive's vendored dependencies.
This is not deployed Tempo/Grafana, provider-layout, capacity or full TraceQL
acceptance.

## Checksums

| File | SHA-256 |
| --- | --- |
| `input.protobuf` | `41a46730778cf44f0934d5084000fce1a2f79aa3e6e63ce22ccdac5f0a2dac58` |
| `oracle.json` | `2e7d8723a134bd9007c86f114335ff8d21ea0853e70a1bbcf7261d4a0579eb4c` |
| `durations.json` | `4bf85da17b6a5fc161de716753b68476302bf6a3a745462118ff1b836e722262` |
| `produce.go.txt` | `c428dc2994e756fe0fa87c678b6871932c62427286601040633871c2a6ca5893` |

All four are pinned by `search_expression_test.exs`. Offline assertions compare
public results with native execution, an independent Elixir evaluator,
Memory/old-callback fallback, and authenticated HTTP ingest → owned S3 HTTP stub
→ HTTP/MCP queries. Earlier roots and different services are also replayed from
separate objects; unknown metadata/corruption/budget failures reject whole.

## Optional regeneration and public protobuf consumer

In the pinned, separately prepared public source tree, copy the helper and
producer tests into `tempodb/encoding/vparquet4` and run:

```sh
GOMAXPROCS=2 go test -mod=vendor -p 2 ./tempodb/encoding/vparquet4 \
  -run '^TestPulseSearchExpressions$' -count=1 -timeout=180s -v
```

Output goes to `/tmp/pulse-trace-expressions/`. Check source/input/output SHA
changes explicitly before refreshing fixtures. This is not an ordinary test
prerequisite. No public provider or live telemetry endpoint is involved.

The optional producer also reads `consumer-0.protobuf` through
`consumer-23.protobuf` from that directory. With
`PULSE_REQUIRE_SEARCH_EXPRESSION_CONSUMER=1`, missing files fail rather than skip.
Each must be a native Pulse search result encoded with
`Pulse.Traces.Protobuf.encode(decoded_json, :search)`. The actual public
`tempopb.SearchResponse` decoder checks all 24 against engine results, including
empty-response defaults. This consumer run was executed separately from fixture
generation; ordinary replay does not run or require it.
