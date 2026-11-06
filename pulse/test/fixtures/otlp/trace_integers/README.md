# Public quoted trace integer reference

File-only inputs decoded by **opentelemetry-proto v1.9.0**, actual
**google.golang.org/protobuf v1.36.11**, and **Go1.25.10 darwin/arm64**.
No Pulse implementation, SDK or Collector computes the expectations.

## Captures

- `cases.json`: 451 actual public quoted-field decisions: 41 literals for each
  of 11 fields across Resource, InstrumentationScope, Span, Event, Link and
  Status. Includes uint32/fixed32 limits, signed zero, exact decimals/exponents,
  fractions, overflow, underflow, noncanonical strings and whitespace. Accepted
  integer values come from public protobuf reflection, not float conversion.
- Enum fields are tested separately: public ProtoJSON **rejects quoted numeric
  strings**, while it accepts recognized enum names. OTLP requires integer enum
  tokens and therefore rejects both quoted digits and names. Named-enum verdicts
  are retained as explicit deviations, not silently relabeled public failures.
- `traces-google-input.json`: complete authored request with every dropped-count
  and flags owner quoted. Kind and status code remain numeric tokens.
- `traces-input.json`: the same input with only known base64 context IDs changed
  to OTLP hex through exact text replacement.
- `traces-google.json`, `traces-canonical.json`: public numeric-enum ProtoJSON
  output, respectively before/after hex-ID adaptation and object-order normalization.
- `traces.protobuf`: actual public binary encoding of the decoded request.
- `checksums.json`: SHA-256 index of nine producer/capture files and version pins.

Ordinary tests replay without Go, network or external tools. They compare Rust
and independent Elixir JSON paths, decoded records, native Parquet and exact-byte
keyed gzip HTTP publication across owned local S3 runtime instances. This is
component evidence, not SDK/Collector, deployed-client, real-provider or capacity
acceptance. Existing wire capability 3 suffices; every ingress application must
be upgraded before producers rely on quoted trace counts/flags.

## Optional reproduction

Prepare the pinned Go toolchain and dependency cache separately. From the repo:

```sh
producer=$(mktemp -d)
cp test/fixtures/otlp/trace_integers/produce.go.txt "$producer/main.go"
cp test/fixtures/otlp/trace_integers/producer.go.mod.txt "$producer/go.mod"
cp test/fixtures/otlp/trace_integers/producer.go.sum.txt "$producer/go.sum"
output=$(mktemp -d)
(cd "$producer" && GOPROXY=off GOSUMDB=off GOTOOLCHAIN=local GOMAXPROCS=2 \
  go run -mod=readonly . "$output")
```

Keep independent captures separate from derived expectations. Do not overwrite
frozen fixtures without explaining differences; public ProtoJSON whitespace can
vary across builds. Toolchain/cache preparation is trusted, not attestation.
See [operator wire semantics](../../../../docs/otlp-wire.md).
