# Public OTLP JSON field decisions

Independent, synthetic, **file-only** reference using public OTLP generated Go
messages **v1.9.0**, actual Google protobuf **v1.36.11** and **Go1.25.10 darwin/arm64**.
`protojson.UnmarshalOptions{DiscardUnknown: true}` decides acceptance. Public
message descriptors enumerate every field in the selected owners; expectations
are not computed by Pulse, a locally duplicated schema or another backend.

## Corpus

`cases.json` contains **704 decisions: 355 accepted, 349 rejected**, across **35
message/field contexts**:

- Each public field of those owners has single/duplicate controls, including
  message/scalar fields, repeated containers, optional histogram statistics,
  exemplars, quantiles, metadata, status and Span field16 flags.
- Representative fields additionally test escaped duplicate names and first-null,
  last-null and both-null duplicates. The public decoder rejects duplicates even
  when equal or null: null does not refund a previously seen field number.
- Unknown duplicate names and opaque unknown objects remain ignored, even if their
  internal names resemble a real schema or another export root.
- Valid numeric tokens in unknown objects include float overflow and negative
  underflow. Unknown fields must not fail because a native/BEAM float cannot
  represent their numeric value; supplied nodes still consume admission.
- Foreign signal roots test receiver-specific scope. A metrics field on a logs
  export root is unknown, not a reason to parse/reject it as a metrics request.
- Separate sibling objects reuse their field names without a false duplicate.

Cases use lowerCamelCase names and numeric enums, respecting the
[OTLP JSON deviations](https://github.com/open-telemetry/opentelemetry-proto/blob/v1.9.0/docs/specification.md#json-protobuf-encoding)
from generic ProtoJSON. Original snake_case aliases and enum-name strings are NOT
required OTLP features. Empty context-ID controls avoid differences between OTLP
hex and generic Google base64; this corpus measures field decisions, not acceptance
of complete trace records with empty IDs. Accepted cases' canonical JSON comes
from the actual public serializer. Unsupported metric types/entity references and
remaining null/request-shape semantics are not made supported by these checks.

Pulse compares native answers with an independent Elixir numeric-token/object-pair
reference. Known duplicates return native fallback and then raise; native success
is required for clean single-field/sibling inputs. Opaque unknown duplicates may
fall back without becoming known fields. Gzip HTTP tests prove no earlier valid
resource subset is appended on rejection. Separate owned S3/CAS tests replay full
rich raw-number requests with unknown fields across instances and canonical JSON
under one key, preserving exact values/metadata rather than only parser success.

`checksums.json` indexes **four producer/capture files**. Ordinary replay needs only
the native project toolchain: no Go, protoc, SDK, Collector, availability probe,
network or external backend. No other backend was built or queried. Prepared
compiler/dependency artifacts remain trusted, not cryptographic attestation; this
is not provider, capacity, deployed-client or full conformance acceptance.

## Optional reproduction

Prepare pinned tools/cache separately, then from the repository root:

```sh
producer=$(mktemp -d)
cp test/fixtures/otlp/json_fields/produce.go.txt "$producer/main.go"
cp test/fixtures/otlp/json_fields/producer.go.mod.txt "$producer/go.mod"
cp test/fixtures/otlp/json_fields/producer.go.sum.txt "$producer/go.sum"
output=$(mktemp -d)
(cd "$producer" && GOPROXY=off GOSUMDB=off GOTOOLCHAIN=local GOMAXPROCS=2 \
  go run -mod=readonly . "$output")
```

Do not silently refresh frozen captures. Retain and explain changes; public
canonical JSON spacing may vary between builds. See the
[operator wire contract](../../../../docs/otlp-wire.md) for capability 3,
whole-request rejection, unchanged limits and upgrade/rollback rules. Contributor
[backend reference notes](../../../../plans/backend-protocol-references.md) keep
GreptimeDB/OpenObserve source observations separate from protocol evidence.
