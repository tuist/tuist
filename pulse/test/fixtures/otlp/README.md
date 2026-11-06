# Independent OTLP wire fixtures

## Shared merging and integer numbers

[`wire/`](wire/README.md) freezes actual public Google protobuf merging and
canonical encoding for logs, metrics and traces, plus 60 signed/unsigned quoted
numeric cases. It covers split resource/scope/status/AnyValue messages, oneof
switches, scalar/exemplar selection and signed zero. Ordinary replay needs no
Go/protoc/SDK tools or network.

[`numbers/`](numbers/README.md) adds exact unquoted integer tokens: 156 actual
public ProtoJSON decisions, 11 float-bit cases and complete raw-number/canonical-
JSON/protobuf requests for all signals. Authored raw numeric lexemes never pass
through a float-based JSON round-trip before capture. Ordinary replay is offline.

[`exponential_boundaries/`](exponential_boundaries/README.md) adds 1,160 actual
public protobuf source points with independent mathematical and public Prometheus
bucket geometry captures. Ordinary replay covers bounded classic projection,
source preservation, native storage and owned cross-instance gzip keyed replay;
it is not native-histogram or deployed-client parity.

[`json_fields/`](json_fields/README.md) adds 704 actual public duplicate/unknown
field decisions across 35 owner contexts, including all fields enumerated by
public descriptors, null/escaped duplicates, opaque numeric tokens and receiver
scope. It follows OTLP's numeric-enum/lowerCamelCase rules, not generic aliases.

## Trace exporter

`erlang-exporter-traces.protobuf` is a synthetic `ExportTraceServiceRequest`
encoded by the generated `opentelemetry_exporter_trace_service_pb` module from
`opentelemetry_exporter` 1.8 (gpb 4.21.1), not by Pulse's test encoder.

It contains a server span from `opentelemetry_phoenix`, an empty root parent,
flags `257`, nanosecond timestamps, an error status, request/account attributes,
a false boolean attribute and an exception event, with a `tuist-server`
resource. All values are synthetic. The fixture pins compatibility with an
independent encoder without adding an OTel SDK dependency to Pulse's tests.

## Logs compiler fixture

`protoc-logs.textproto` is synthetic input for the official
`opentelemetry-proto` **v1.9.0** descriptors, compiled with **libprotoc 34.1** to
`protoc-logs.protobuf`. `protoc-logs.json` is independently decoded by Google's
Python protobuf **6.33.6**, not Pulse's encoder/decoder. ProtoJSON base64 IDs are
converted to OTLP-required hex; no other protocol values are rewritten. The
fixture covers typed bytes/string values, int64 extrema, signed zero/non-finite
doubles, resource/scope/schema metadata, flags, dropped counts and event names.
It is a compiler fixture, **not captured SDK traffic or live acceptance**.

To reproduce the wire fixture, obtain those official `.proto` files under
`$PROTO_ROOT` and run from the repository root. The independent JSON expectation
is checked in; tests replay both artifacts with Elixir/Rust and require neither
Python nor an installed SDK. Do not regenerate an independent expectation using
the decoder under test:

```sh
protoc -I "$PROTO_ROOT" \
  --encode=opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest \
  opentelemetry/proto/collector/logs/v1/logs_service.proto \
  < test/fixtures/otlp/protoc-logs.textproto \
  > test/fixtures/otlp/protoc-logs.protobuf
```

Pinned source SHA-256, paths relative to `$PROTO_ROOT`:

| File | SHA-256 |
| --- | --- |
| `opentelemetry/proto/common/v1/common.proto` | `354d818af9cb0ed67f7447b9cf8408f1ac8911cedea0db73c5309484ec2bcc04` |
| `opentelemetry/proto/resource/v1/resource.proto` | `e0a7cdc0ffcfeffaa2606e8611839735ebffaa2d6acdf33e9356f2c48ae692d3` |
| `opentelemetry/proto/logs/v1/logs.proto` | `37abe88f091239abf77b80be380166a526fa7dbcc0d4061f16802636c71714cb` |
| `opentelemetry/proto/collector/logs/v1/logs_service.proto` | `0252687fc8f59d139ced709d383e83678e9bd4957bdbe76077242f1c32363fa5` |

Fixture SHA-256:

- Text: `908313ec259ad184145bddc5787facd9453bd1e7ec0bec6777839324db084b5c`
- Wire: `6e75ce297e3c64d5926a45dc37e67f3cdc923dce123eb79f57a46f42783e0163`
- JSON: `54af19a270ed546dab3c7dcb9a93283a2019eecc4dc84065be5fb4c058c49bf4`

## Distribution compiler and float-label fixtures

[`distributions/`](distributions/README.md) adds public OTLP v1.9.0
histogram/summary messages encoded by protoc 34.1 and Google protobuf 1.36.11
through Go 1.25.10, plus actual Go fixed-decimal label spellings. Seven source
points project to 24 float samples, preserving uint64-max counts, optional fields,
signed zero and ignored staleness values. Generic ProtoJSON and correctly
hex-adapted OTLP JSON remain separate captures. Ordinary Elixir/Rust replay needs
neither Go/protoc nor external tools or network; the frozen manifest pins the
producer, locks and reference sources. These are protocol fixtures, not SDK
exporter or application-bootstrap evidence.

## Metrics compiler fixture

`protoc-metrics.textproto` uses the same official v1.9.0 common/resource
sources and libprotoc 34.1 as logs. Google's protobuf 6.33.6 independently
produces JSON; only exemplar context IDs change from ProtoJSON base64 to
OTLP-required hex. Integer enums remain integers. The corpus pins gauge and
cumulative-sum fields, signed int64 extrema, signed zero, non-finite/stale
values, typed resource/scope/descriptor metadata, and a sampled exemplar.
This is compiler evidence, **not SDK capture or live Collector acceptance**.

```sh
protoc -I "$PROTO_ROOT" \
  --encode=opentelemetry.proto.collector.metrics.v1.ExportMetricsServiceRequest \
  opentelemetry/proto/collector/metrics/v1/metrics_service.proto \
  < test/fixtures/otlp/protoc-metrics.textproto \
  > test/fixtures/otlp/protoc-metrics.protobuf
```

Additional pinned source SHA-256:

| File | SHA-256 |
| --- | --- |
| `opentelemetry/proto/metrics/v1/metrics.proto` | `d0a53dda45ad100edbf25675f5b339ce8bf689bdc51816f8cf19b0d51464e1a4` |
| `opentelemetry/proto/collector/metrics/v1/metrics_service.proto` | `2bb3c6adee5f7609c8a32c5e4b1ec57057320015e298e9cf136699a42abc24d7` |

- Text: `dffae285f8a6a5659e94fa19b9b5813e011483463715e05c51854bb25fee666e`
- Wire: `426803e5240485e65defe7c4ae8d1aadcc375352914787e35518bc930bb53440`
- JSON: `9ca7318eeea3ef0c2c3d715cddd485d09d35396e0f869bc0f5db61d7d217789f`

## Synthetic SDK wire fixture

`python-sdk-metrics.protobuf` is synthetic OTLP/HTTP output captured from the
OpenTelemetry Python SDK and HTTP exporter **1.40.0**, using protobuf **6.33.6**.
The producer sent gzip protobuf to an isolated loopback capture endpoint. It
contains a cumulative scalar counter with an exemplar recorded under an explicit
sampled span context, and an observable signed-zero gauge. All resource values
and IDs are synthetic. SDK-generated timestamps are captured unchanged, so this
fixture's checksum is pinned rather than deterministically regenerated.

SHA-256: `36144b5834ad48a26b10dfe4b16c3787f75733b070f0d8c7f0c3e94dc5954c78`.

**No Python or SDK installation is needed to run these tests.** Elixir replays the
checked-in bytes through native decoding and gzip HTTP/S3/MCP tests. This proves
compatibility with the captured SDK payload, not live Tuist/Collector delivery,
cross-node operation, production load or migration readiness. Repository tooling
does not include or invoke the external producer.

Mutation tests use a small Pulse test encoder separately from these pinned
baselines. Legacy/corrupt Parquet reader fixtures are described in
[`../logs/README.md`](../logs/README.md).

## Typed trace compiler fixture

`protoc-trace-values.textproto` was encoded with **libprotoc 34.1** and official
OpenTelemetry protobuf **v1.9.0** sources. It covers byte/string pairs at every
attribute owner, exact signed-int64 bounds, int/double identity, negative zero,
empty AnyValues and nested arrays/kvlists. IDs are literal protobuf bytes;
`0123456789abcdef` becomes hex `30313233343536373839616263646566`.

Additional official source SHA-256 pins:

- `trace/v1/trace.proto`: `c3fb1385c90b8bc08a2a462e28b5d0c422c7b524a839f75f75e3cd9f64f36956`
- `collector/trace/v1/trace_service.proto`: `03c8cc4e3e101087d884392d6eda32152ad5cd696e6344f50deaa59804a75c7a`

Paths are under `opentelemetry/proto/` in the official
`https://github.com/open-telemetry/opentelemetry-proto/tree/v1.9.0` tag, using the
same common/resource source pins as the log/metric fixtures above. Optional regeneration:

```sh
protoc -I "$PROTO_ROOT" \
  --encode=opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest \
  opentelemetry/proto/collector/trace/v1/trace_service.proto \
  < test/fixtures/otlp/protoc-trace-values.textproto \
  > test/fixtures/otlp/protoc-trace-values.protobuf
```

Fixture SHA-256:

- textproto: `f34f29049a7d8dbfd13a510c755fe649ab667243cf50f4f4915c323a6224a85d`
- protobuf: `345cbbcb764b0e9959735462671d4ed65265b726ed7d75bb98461d637db95234`

Normal tests replay the checked-in bytes with the native toolchain only; they do
not require or probe for protoc or an external SDK. This is independent compiler
wire evidence, not captured SDK traffic, live delivery or Tempo compatibility.
Independent legacy/corrupt Arrow trace fixtures are described in
[`../traces/README.md`](../traces/README.md).
