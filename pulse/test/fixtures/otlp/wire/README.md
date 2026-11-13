# Public protobuf merging and numeric strings

File-only synthetic reference using **opentelemetry-proto v1.9.0** generated Go
messages and **google.golang.org/protobuf v1.36.11**, executed with **Go 1.25.10
(darwin/arm64)**. This is not SDK traffic, a live backend or a Pulse encoder oracle.

`produce.go.txt` constructs noncanonical-but-valid protobuf occurrences with the
public `protowire` package, then runs actual `proto.Unmarshal` into each public
Export request type. It captures:

- `logs|metrics|traces.protobuf`: supplied fragments, never Pulse-encoded.
- `*-canonical.protobuf`: actual `proto.Marshal` of the public decoder's merged
  result, not a concatenation or locally implemented merge expectation.
- `*-google.json`: actual numeric-enum Google ProtoJSON output. Its byte IDs use
  generic base64, not OTLP's required hex.
- `logs|metrics|traces.json`: explicitly adapted JSON, changing only context IDs
  to hex. Go's ordinary JSON round-trip also normalizes object order/spacing;
  signed-zero float bits and quoted 64-bit numbers remain intact.
- `numeric-strings.json`: 60 actual `protojson.Unmarshal` decisions and canonical
  signed/unsigned integer strings, from `common.AnyValue.int_value` and
  `metrics.HistogramDataPoint.count`. No float parser computes expectations.

All three requests split resource and scope messages, append ordered attributes,
overwrite a nonzero resource dropped count with an explicit zero, and retain a
negative-zero scope attribute. Logs merge nested kvlists and switch a body oneof
away from an array and back, then append a second array fragment; the discarded
values must not reappear. Traces merge status message and code. Metrics switch
Gauge -> Sum -> Gauge, then merge a second Gauge; only source values 7 and 8
survive. Scalar points and their embedded exemplars independently select asInt
after asDouble. Their values are authored, while all merge/selection expectations
come from the actual public decoder.

The reference decoder's merge semantics do not prove OTLP semantic validity or
resource limits. Pulse separately tests invalid duplicate keys, cumulative owner
counts/bytes/nodes, overwritten-branch charges, source record/node admission,
no-subset HTTP failures, native Parquet fidelity and S3 keyed replay across two
owned runtime instances. Neither canonicalizing a rejected request nor changing
its retry key is an operational workaround for admission.

`checksums.json` indexes 16 producer/capture files. Ordinary tests replay them
without Go, protoc, SDKs, Collectors, subprocesses or network access. Compiler and
prepared module artifacts are trusted inputs, not cryptographic attestation.

## Optional reproduction

Prepare the pinned Go toolchain and public module cache separately. From the repo
root, create an isolated directory containing only this producer and its pins:

```sh
producer=$(mktemp -d)
cp test/fixtures/otlp/wire/produce.go.txt "$producer/main.go"
cp test/fixtures/otlp/wire/producer.go.mod.txt "$producer/go.mod"
cp test/fixtures/otlp/wire/producer.go.sum.txt "$producer/go.sum"
output=$(mktemp -d)
(cd "$producer" && GOPROXY=off GOSUMDB=off GOTOOLCHAIN=local GOMAXPROCS=2 \
  go run -mod=readonly . "$output")
```

Do not overwrite frozen evidence automatically. Compare semantic output and
bytes, retain differences and explain any deliberate update. Google ProtoJSON
spacing may vary across builds; hashes identify the captured bytes rather than
asserting a canonical JSON encoder. See [operator wire semantics](../../../../docs/otlp-wire.md)
for the accepted scope and remaining gaps.
