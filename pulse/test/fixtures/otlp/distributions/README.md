# Independent OTLP distribution messages

Synthetic public-protocol fixtures, unrelated to any application inventory.
There is no Pulse encoder, exporter or SDK in the producer. Ordinary tests read
these files with Elixir/Rust only, without probing/downloading external tools.

## Evidence and pins

- OTLP schemas/generated Go bindings: **v1.9.0**.
- Metrics data model reference: **OpenTelemetry specification v1.50.0**.
- Compiler: **libprotoc 34.1**; Go: **go1.25.10 darwin/arm64**;
  Google protobuf library **v1.36.11**.
- `input.textproto` is the authored source; actual public `protoc --encode`
  produces `input.protobuf`. It contains seven source points, projecting to 24
  float samples: explicit buckets, summary quantiles, uint64-max counts, absent
  optional sum, present negative-zero sum/min, NaN max, empty staleness and a
  no-recorded-value point whose ignored count/sum/buckets are inconsistent.
- `generic-protojson.json` is actual Google ProtoJSON output with numeric enums.
  It is **not** directly valid OTLP JSON for exemplar context IDs: generic
  ProtoJSON encodes bytes as base64, whereas OTLP requires hex trace/span IDs.
- `input.json` applies that documented ID adaptation to the Google output.
  No values, attributes, counts, buckets or optional fields are repaired.
  Enum numbers are selected through `UseEnumNumbers`, another OTLP JSON rule.
- `float-labels.json` contains **2,055 finite IEEE boundary/randomized cases**
  from actual Go `strconv.FormatFloat(value, 'f', -1, 64)`, including signed zero
  and subnormals. The 2,048 generated bit patterns plus explicit boundaries omit
  one non-finite random value. This is an independent label-spelling oracle,
  not a metric-semantic oracle.
- Prometheus **v3.5.0** `prometheusremotewrite/helper.go` is a pinned **source**
  reference for bound/quantile label spelling, optional histogram sum, universal
  `+Inf` and stale-component behavior. The full translator was not executed by
  this producer. OTLP shape/value constraints are checked independently; Pulse
  rejects malformed ordinary bucket shapes/totals that this translator tolerates.
- `checksums.json` pins eight input/output/producer/lock files, tool identities
  and six public reference source hashes. Its SHA-256 is
  `d44328c9424809b01115d78763c3876300659188e233cb11698627dc167ebe98`.
  Hashes freeze this capture, not an attestation of compilers or byte-stability
  promises from Google's JSON formatting implementation.

Tests distinguish source protobuf, adapted OTLP JSON, generic ProtoJSON and
hand-asserted projections. They replay exact source metadata through native
Parquet, repeated encode/decode and actual HTTP/MCP/PromQL, shared S3-stub
publication across two runtime instances, manifest-supervision restart and
compaction. Latest stale markers must suppress earlier ordinary values. Source
identity conflicts and independent node/row/metadata budgets fail closed.

## Optional reproduction

Use a fresh temporary producer directory, not Pulse's module or dependency graph.
Download the four schemas under
`https://raw.githubusercontent.com/open-telemetry/opentelemetry-proto/v1.9.0/opentelemetry/proto/`:

- `common/v1/common.proto`
- `resource/v1/resource.proto`
- `metrics/v1/metrics.proto`
- `collector/metrics/v1/metrics_service.proto`

Keep their `opentelemetry/proto/...` directory structure beneath `$PROTO_ROOT`.
Verify their hashes against `checksums.json`, then, from the repository root:

```sh
protoc --proto_path="$PROTO_ROOT" \
  --encode=opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceRequest \
  opentelemetry/proto/collector/metrics/v1/metrics_service.proto \
  < test/fixtures/otlp/distributions/input.textproto > /tmp/distributions.protobuf

# $PRODUCER is a fresh directory owned by this preparation.
cp test/fixtures/otlp/distributions/produce.go.txt "$PRODUCER/main.go"
cp test/fixtures/otlp/distributions/producer.go.mod.txt "$PRODUCER/go.mod"
cp test/fixtures/otlp/distributions/producer.go.sum.txt "$PRODUCER/go.sum"
cd "$PRODUCER"
go mod download
go run -mod=readonly . /tmp/distributions.protobuf /tmp/distributions.json /tmp/float-labels.json
# Generic Google output is /tmp/distributions.json.google.
```

Dependencies are preparation, not telemetry export. The producer reads/writes
local files only. Do not silently refresh the frozen corpus after a failed
assertion: preserve the old inputs and explain producer/profile changes.
