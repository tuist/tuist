# Actual SDK/Collector bridge evidence

These are **first-party harness captures driving real upstream components**,
not an independent implementation of SDK/Collector behavior or a deployed-client
acceptance claim. Ordinary tests replay checked-in data with Elixir/Rust only.
They do not download, probe for, build or execute Go or a Collector.

Product-renaming maintenance normalized first-party producer/module identities
to Pulse in the sources, build information, oracle and protobuf captures. This
was not a new SDK/Collector run. The replacement strings have identical byte
lengths, preserving protobuf length delimiters; the updated payloads were
decoded with `protoc`. The hashes below pin these normalized fixtures rather
than the original capture bytes. Upstream component identities are unchanged.

## Producers and boundaries

- Go 1.25.10, `go.opentelemetry.io/otel` / SDK / gRPC trace exporter **1.43.0**.
  Full module pins/checksums: `../sdk-bridge.go.mod.txt`,
  `../sdk-bridge.go.sum.txt`; captured `go version -m` is `sdk-buildinfo.txt`.
- Producer source: `../produce_sdk_bridge.go.txt`. It uses two real tracer
  providers/resources, SDK batch processors, gRPC exporters and an actual
  loopback HTTP request with W3C `TraceContext` injection/extraction. IDs and
  source timestamps are deterministic; RPC/batch ordering is scheduler-dependent.
  Explicit tiny sampler/queue/batch/attribute/event/link limits are not defaults.
- **Core** Collector **0.137.0**, official release (not contrib/Alloy):
  `https://github.com/open-telemetry/opentelemetry-collector-releases/releases/tag/v0.137.0`.
  Darwin-arm64 archive `otelcol_0.137.0_darwin_arm64.tar.gz` SHA-256:
  `56a4535b97b9dcb168bbb46d77d926a2ec9de6d02a5262416d7101eb691dd76f`,
  matched against the release's published checksum manifest.
  Extracted binary SHA-256:
  `1747a6d1a058684e610d2a508e10185788cd66e1f802f547b320e81660110bae`;
  `--version`: `otelcol version 0.137.0`. This checksum match is not a signature-
  verification or vulnerability/security recommendation. Other platforms must
  verify their own artifacts; do not compare Linux binaries to this checksum.
- Passing profile: no Collector processors/re-batching or sending queue; gzip
  `otlphttp` exporter with static tenant/auth headers and bounded retries. Actual
  Pulse HTTP server, native Parquet/S3 client against an **owned HTTP S3 stub**,
  manifest-supervision restart, and MCP reads. No real provider/node restart,
  TLS, deployed SDK/Alloy, persistent queue or capacity acceptance.

The producer's gRPC unary interceptor deterministically marshals the export
**request message** before invoking gRPC. `sdk-request.protobuf` is not literal
gRPC packet bytes, HTTP/2 frames or compressed transport capture. Collector
requests are actual HTTP bodies captured at the loopback proxy after gzip
inflation. Concatenating repeated-resource export request messages preserves the
whole supplied span list; it is not trace-ID reconciliation or SDK deduplication.

## Frozen artifacts

`SDKBridgeTest` checks these SHA-256 values before replay:

| File | SHA-256 |
| --- | --- |
| `sdk-request.protobuf` | `0c41960561d3d93e066a99178266090e1cd0d06926e9c06cb1d479eaf92cfab1` |
| `collector-request.protobuf` | `6d54d47fa6e9676145696adcda14afea6b6bbf8017a98960b1d82f9aa64c4ed8` |
| `sdk-oracle.json` | `d9bfb3897bcfba2b4eece63712a38a31842f696319f2abc493d0c3bdbd4226b5` |
| `sdk-buildinfo.txt` | `19004d69934f5e5f53507e7b263eeec10b227c58c93f739c16c43d1ae95e315f` |
| `split-collector-request.protobuf` | `da01f7c8b92f26f5eff721172fb168e3a4d4c6055855b8bb09e1d6d38397e40f` |
| `partial-producer.protobuf` | `977747b0c64211e2b07187a7d5c333ead8cb542ec35e12707247e185c54ce967` |
| `partial-collector.protobuf` | `19cdc88fac71f448c59140a510ac07c8e67eeae7f002abaf213f93baab971bfe` |
| `partial-result.json` | `a85bb10c2fe3983a53c315cdb3ac52f4f45e347a3167a31b5ff9bddc3126a1fe` |

`sdk-oracle.json` snapshots the SDK `ReadOnlySpan` API with a small first-party
attribute converter. Float values are decimal/class strings to avoid losing
signed zero in the oracle's JSON; replay normalizes them and separately asserts
projection and typed scalar/array zero bits. Int64 above 2^53, flags, statuses,
resource/scope schemas, typed metadata, events, links and drops are checked.
SDK request → Collector → stored records agree for every normalized field.
Native Parquet compaction/assembly and four Tempo export formats also replay.

There are two deliberately retained losses:

1. SDK 1.43 snapshots have link tracestate `vendor=opaque`, but its export request
   message already omits that field. The Collector/Pulse preserve what was sent;
   no tracestate is fabricated. Upstream source inspected: `opentelemetry-go`,
   tag `exporters/otlp/otlptrace/v1.43.0`,
   `exporters/otlp/otlptrace/internal/tracetransform/span.go`, function `links`:
   the constructed protobuf link omits `TraceState`.
2. `split-collector-request.protobuf` comes from the same SDK request bytes, with
   Collector 0.137 batch processing instead: `send_batch_size: 2`,
   `send_batch_max_size: 2`, `timeout: 100ms`. Mixed frontend/worker resources
   split so the database span loses both resource and scope schema URLs. The
   other normalized fields and IDs agree. Replay asserts the precise loss and
   that storage doesn't invent the missing values. A different batch order may
   choose another split span; no universal byte-reproduction claim.

The partial case deliberately constructs one valid and one all-zero-trace-ID
span using **public OTLP protobuf types**, not an ordinary SDK. Collector forwards
both, Pulse stores the valid span and reports `rejectedSpans=1`. The live test
observes one HTTP 200 attempt, no whole-batch retry, and a successful upstream
gRPC response with empty `partial_success:{}` rather than the backend count.
Fixture replay alone does not establish network retry behavior.

The live harness additionally injects **pre-publication** HTTP 429/503, observes
unchanged decompressed retry messages, and checks actual Pulse 401/413 permanence.
Two static pipelines have the same trace/span IDs but different tenant resources
and credentials; unauthorized MCP access fails. This does not authenticate the
Collector's incoming gRPC clients or demonstrate a public multi-tenant gateway.
SDK process exit means capture completed, not delivery succeeded: export and
flush errors are recorded/asserted separately. A background failure may not be
returned by a later flush.

## Optional local reproduction

Use directly built binaries on Unix. Do not pass `go run` or a wrapper that forks
without `exec`: subprocess cleanup signals only the owned direct OS pid. Port
handoff has a reservation race (reserve ephemeral ports, release, Collector binds);
a conflict fails readiness rather than attaching to an unrelated server. Rerun
with fresh ports on that failure. Logs are bounded to 64 KiB and evidence requests
to 64 (exhaustion fails, never truncates). Child environments clear known OTel,
gRPC, proxy and Go runtime settings and fix GOMAXPROCS=2, without changing the
parent/test environment. This is not an OS sandbox. Captured credentials are
synthetic; request logs redact authorization and no secret-bearing config/log is
frozen here.

```sh
# Run from the Pulse root; Go/dependency downloads are optional producer tooling.
work=$(mktemp -d)
cp test/fixtures/traces/produce_sdk_bridge.go.txt "$work/main.go"
cp test/fixtures/traces/sdk-bridge.go.mod.txt "$work/go.mod"
cp test/fixtures/traces/sdk-bridge.go.sum.txt "$work/go.sum"
(cd "$work" && GOTOOLCHAIN=local go build -mod=readonly -o "$work/trace-sdk" .)

# Supply a separately downloaded/verified core Collector 0.137.0 binary.
PULSE_TEST_OTELCOL=/absolute/path/to/otelcol \
PULSE_TEST_TRACE_SDK="$work/trace-sdk" ERL_FLAGS='+S 4:4' \
  mix test test/pulse_web/controllers/collector_bridge_live_test.exs \
    --include collector_bridge --max-cases 4 --trace
```

A missing binary path is an explicit failure after opt-in, not a skip. The tag is
excluded by default **even when `PULSE_INTEGRATION=1`**; normal CI's S3 integration
job must not require these tools. Generated SDK oracles/request messages,
Collector requests/delivery logs and config stay in the test-owned tmp directory;
the successful test prints its path. Reproduction never refreshes golden files.
Inspect semantic differences before deliberately updating captures/checksums.

Source SHA-256:

- Producer `4bd4ed2b4bc4699e798093aa8e15d3eb58b5eecd407458c01f621059185d086e`.
- Module `1b8d0366e4a8585265b03b342e26ec796d6fa7a0559b50ee3821ee27ab544fe3`.
- Checksums `3c0e4cc1e2fe9edf04b373eaa2fc0928559602c05f5c29ab0134be7a54b86001`.

No upstream implementation is vendored. The workload still needs actual
Rust/Elixir SDKs, deployment/Alloy/TLS, queues/crashes/ambiguous acknowledgments,
representative batches/volume, provider/native pressure, recovery and authorized
shadow/cutover acceptance. See [operator contract](../../../../docs/trace-collector-bridge.md).
