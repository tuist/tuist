# Public trace uint32/fixed32 reference

Frozen file-only evidence from **opentelemetry-proto v1.9.0**, actual
**google.golang.org/protobuf v1.36.11** and **Go 1.25.10 (darwin/arm64)**.
No Pulse decoder, encoder, SDK, Collector or exporter computes expectations.

- `cases.json`: 306 actual `protojson.Unmarshal` decisions, covering 34 quoted
  literals in each of the nine trace uint32/fixed32 fields. Owners are Resource,
  InstrumentationScope, Span, Span.Event and Span.Link. Includes uint32 max,
  exact decimal/exponent forms, signed zero, fractional underflow, huge exponents,
  overflow, invalid numeric spellings and nonnumeric strings. Accepted values
  come from the public canonical serializer; uint32 values are exact in JSON.
- `google-input.json`: authored quoted-field request with generic ProtoJSON
  base64 context IDs, supplied directly to the public decoder.
- `google-canonical.json` and `request.protobuf`: actual public canonical JSON
  and deterministic protobuf serialization of that decoded request.
- `input.json` and `canonical.json`: the respective JSON files with only context
  IDs translated from generic base64 to OTLP hex, plus ordinary formatting/key
  ordering. Quoted literals and exact uint32 numeric values are preserved.
- `produce.go.txt`, `producer.go.mod.txt`, `producer.go.sum.txt`: optional producer
  and pinned dependencies. `checksums.json` covers all nine producer/capture files.

Normal ExUnit replay requires only Elixir/Rust, without Go, subprocesses or
network. Tests prove native/reference wire parity without early string rewriting,
semantic normalization, native Parquet fidelity and gzip keyed cross-instance
publication against an owned local S3 stub. Invalid owner/record behavior and
keyed valid-neighbor rejection remain unchanged. No deployment, actual-provider,
capacity, SDK/default-policy or full ProtoJSON conformance is established.
Quoted enum values are intentionally outside this increment.

## Optional reproduction

Prepare the pinned Go toolchain/module cache separately. From the repository root:

```sh
producer=$(mktemp -d)
output=$(mktemp -d)
cp test/fixtures/otlp/trace_uint32/produce.go.txt "$producer/main.go"
cp test/fixtures/otlp/trace_uint32/producer.go.mod.txt "$producer/go.mod"
cp test/fixtures/otlp/trace_uint32/producer.go.sum.txt "$producer/go.sum"
cp test/fixtures/otlp/trace_uint32/*.txt "$output/"
(cd "$producer" && GOPROXY=off GOSUMDB=off GOTOOLCHAIN=local GOWORK=off GOMAXPROCS=2 \
  go run -mod=readonly . "$output")
```

Never silently overwrite captures. Preserve differences and explain intentional
updates; generic Google ProtoJSON whitespace can vary across builds. The raw
`google-canonical.json` capture is intentionally not reserialized: retaining the
actual public output is more useful than byte-stable regeneration. The derived
`canonical.json` is already independently formatted with sorted keys. Prepared
compiler/module artifacts are trusted, not cryptographic attestation.

See [wire semantics and upgrade rules](../../../../docs/otlp-wire.md).
