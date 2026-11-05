# Public OTLP JSON numeric-token reference

File-only synthetic inputs decoded by **opentelemetry-proto v1.9.0** generated Go
messages and actual **google.golang.org/protobuf v1.36.11**, using **Go1.25.10
(darwin/arm64)**. No Pulse parser/encoder, OTel SDK, Collector or telemetry exporter
computes the expectations.

## Captures

- `cases.json`: 156 actual `protojson.Unmarshal` decisions over raw number tokens
  in int64, uint64, uint32 and enum fields. Accepted values come directly from
  public protobuf reflection as decimal integer strings, never float64. Cases
  include exact values above 2^53, signed/unsigned limits, fractional values that
  would round to a whole float, extreme exponents, underflow and malformed JSON.
  Unknown enum *numeric parsing* is distinct from Pulse's supported semantic enum
  vocabulary; the corpus does not claim every parsed enum can be ingested.
- `floating-zeros.json`: 11 actual public double bit patterns, including integer-
  mantissa negative-zero exponents, negative underflow and positive controls.
- `logs|metrics|traces-google-input.json`: authored JSON with unquoted numeric
  tokens, decoded directly by the public implementation.
- `*-input.json`: OTLP JSON, changing only the known base64 context-ID properties
  to hex by exact text replacement. **No JSON decode/re-encode of these inputs**:
  that would round their integer lexemes before Pulse sees them.
- `*-google.json`: actual numeric-enum public ProtoJSON serialization after decode.
- `*-canonical.json`: public canonical values with hex context IDs; ordinary Go
  JSON also normalizes object order/spacing. This is safe for the expectations
  because public serialization has already converted 64-bit integers to strings.
- `logs|metrics|traces.protobuf`: actual public binary encoding of the decoded
  message, not Pulse's encoder or a local numeric conversion.

Full requests contain exact nanosecond times, int64 values above 2^53, int64 min,
uint64 max in histogram count/buckets, numeric 32-bit metadata, exemplars,
summary quantiles and signed-zero doubles. Pulse's ordinary tests compare raw JSON,
canonical JSON and protobuf records/metadata, including Float64 bits, native
Parquet and cross-instance keyed S3 publication using an owned local HTTP stub.
A separate Elixir token/schema reference and randomized exact integers check
that the Rust fast path actually answers identically.

`checksums.json` indexes 20 producer/capture files. Frozen replay needs only the
native project toolchain: no Go/protoc/SDK/Collector, subprocess or network.
Compiler and prepared dependency artifacts are trusted, not cryptographic
attestation. This is wire/component evidence, not full ProtoJSON, client/default-
policy, provider, capacity, recovery or deployment acceptance.

## Optional reproduction

Prepare the pinned Go toolchain/module cache separately, then from the repo root:

```sh
producer=$(mktemp -d)
cp test/fixtures/otlp/numbers/produce.go.txt "$producer/main.go"
cp test/fixtures/otlp/numbers/producer.go.mod.txt "$producer/go.mod"
cp test/fixtures/otlp/numbers/producer.go.sum.txt "$producer/go.sum"
output=$(mktemp -d)
(cd "$producer" && GOPROXY=off GOSUMDB=off GOTOOLCHAIN=local GOMAXPROCS=2 \
  go run -mod=readonly . "$output")
```

Never silently overwrite the frozen corpus. Retain differences and explain any
intentional update; generic Google ProtoJSON spacing can vary across builds.
See [shared operator wire semantics](../../../../docs/otlp-wire.md) for ingress
capability 3, precise numeric/budget behavior and remaining gaps.
