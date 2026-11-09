# Actual Rust SDK/exporter component fixtures

Synthetic telemetry only. No saved deployment queries, application builds,
production credentials or customer payloads are included. This is a first-party
workload using actual public libraries, not a Pulse SDK or an independent
upstream oracle. Ordinary replay never builds/runs/probes this producer, a
Collector or Go, and needs no external network.

Product-renaming maintenance normalized first-party producer/module identities
to Pulse in the sources, lock/tree, oracles and protobuf captures, including
base64 request observations. This was not a new SDK/exporter run. Equal-length
producer-string replacements preserve protobuf length delimiters; updated
payloads were decoded with `protoc`, and gzip observations were recompressed
with new checksums. The index below pins these normalized fixtures, not original
transport bytes. IDs, clocks, statuses, outcomes and upstream identities remain
unchanged.

## Pinned producer and provenance

- API/SDK/proto 0.31.0; OTLP exporter 0.31.1; tracing-opentelemetry 0.32.1.
- tracing 0.1.44, tracing-subscriber 0.3.23, tokio 1.52.1, tonic 0.14.5,
  prost 0.14.3, reqwest 0.12.28, serde_json 1.0.149.
- Transport dependencies include hyper 1.9.0, h2 0.4.13, http 1.4.0 and
  futures-executor 0.3.32, not the newer graph initially resolved by the fixture.
- rustc `1.97.1 (8bab26f4f 2026-07-14)`; frozen target `aarch64-apple-darwin`.
- The full [`Cargo.lock`](../rust-sdk.Cargo.lock.txt) pins all 143 dependency
  entries. All have identical names/versions in the read-only Kura lock
  inventory, including registry source and checksum identity; only the fixture
  package is additional. This does **not** establish
  the application's full feature graph, bootstrap or deployed behavior.
- [`resolved-tree.txt`](resolved-tree.txt) records `cargo tree --locked --offline
  -e normal,build --prefix none --format '{p} features=[{f}]'`. Only its first
  line's temporary project path is replaced by `(external producer)`.
- Source: [`main.rs`](../produce_rust_sdk.rs.txt),
  [`Cargo.toml`](../rust-sdk.Cargo.toml.txt), [`build.rs`](../rust-sdk.build.rs.txt).
  They are external preparation inputs, never Pulse runtime dependencies.

`checksums.json` pins 15 producer/lock/tree/capture files, with paths relative to
`test/fixtures/traces/`. The immutable index SHA-256, also asserted by offline
replay, is:

```text
f7256df86d7d6209b0df4be7acdd1f6a893a726d02cb9d356728627fede617c9
```

The live test compares staged, frozen and binary-embedded source/manifest/lock/
build bytes before exporting and records the executable's SHA-256. Each embedded
file must fit the process helper's 64 KiB output cap; stderr is merged with
stdout, so extra diagnostics or larger files fail closed. These checks do not
cryptographically attest the compiler, dependency artifacts or arbitrary
executables. Prepare a fresh external project with `--locked`; do not reuse
unverified stale builds. Live optional runs require the pinned compiler version;
the target and per-run binary checksum are evidence, not a portable binary pin.

## What each capture means

For `http`, `http-env` and `grpc`:

- `*-oracle.json` snapshots actual SDK `SpanData`, scope/resource attributes,
  parent remote state, IDs, times, flags, status, events/links/drop counters,
  exporter results, compiler/target and actual received W3C headers.
- `*-sdk.protobuf` is **re-derived** by the public
  `group_spans_by_resource_and_scope` transform over a clone of the SDK batch
  before calling the real exporter. It is not a literal HTTP/gRPC transport
  capture or independent encoding oracle. Concatenation preserves repeated
  ResourceSpans if multiple batches occur.
- `*-delivered.protobuf` contains the actual HTTP request bodies captured before
  Pulse, decompressed only when the request says gzip. Direct HTTP and the
  Collector-delivered request must decode exactly like the SDK-derived request
  and the stored records. Typed owners and signed-zero bits have additional
  nonvacuous assertions.
- `observations.json` freezes 13 actual HTTP attempts (original body bytes in
  base64, gzip indication and status), 13 producer export outcomes and observed
  stored counts. It contains no authorization header values. It is a receipt of
  the owned live exercise, not an independently measured provider oracle.

The offline suite verifies hashes, original SDK metadata, strict delivered
parity, one-segment-per-span native Parquet compaction, complete native/reference
assembly and four Tempo JSON/protobuf formats. The observation replay checks
all captured messages contain three valid spans and discloses the whole-request
rejections. Durable publication, failure behavior and authorization are exercised
by the optional live suite, not inferred merely from frozen stored counts.

## Owned live workload

The producer starts a literal loopback TCP HTTP/1.1 server, sends a real reqwest
request carrying W3C headers, and extracts those received headers to parent the
server span. The adapter span has a real **local** server parent. Joining the
worker establishes completion before force-flushing. One accept, a 4 KiB header
bound and three-second I/O/client timeouts bound the tiny service hop; the
supervised external process also has a bounded await/cleanup lifetime.

The workload has one client root, one server and one tracing-adapter span. Its
service response is deliberately 503, separate from exporter failure injection.
It uses ParentBased/TraceIdRatioBased(1.0), a real SDK BatchSpanProcessor,
deterministic IDs and actual source clocks. An explicit flush profile has queue
and maximum batch size 64 and scheduled delay 86,400 seconds, beyond the owned
child's 30-second await. Shared constants configure the processor and report the
observed profile, rather than maintaining a second copy of those values. This avoids a slow-host race with the default five-second
export timer while keeping all three spans in one request; it is not Kura's
default batching/queue acceptance. Event/link attribute limits of one against two
inputs each yield exactly one dropped attribute, verified before and after
storage. The default tracing layer adds source/thread and busy/idle attributes;
`code.file.path` must remain relative (`src/main.rs`), not leak a home directory.
These fields, thread scheduling, ports and wall clocks make regeneration
non-byte-reproducible. Never silently refresh goldens or normalize discrepancies.

Direct `http` uses programmatic headers; `http-env` uses only
`OTEL_EXPORTER_OTLP_TRACES_HEADERS`. A narrowly allowed child-only setting adds
that variable after inherited OTEL/GRPC/proxy settings are scrubbed. The HTTP
endpoint must include `/v1/traces`; a programmatic URL is used verbatim by this
exporter. The client explicitly disables proxies/redirects and uses a three-second
timeout, blocking reqwest without TLS/HTTP2, unlike the application's default
HTTP client. Rich schemas/scope version are additional component coverage, not
Kura's exact span shape. The bridge is core Collector 0.137, gRPC to gzip HTTP,
without processors/re-batching/queue/retry and with static downstream tenant
headers. Untrusted incoming gRPC tenant metadata must leave that tenant empty.

All three destinations share IDs but have isolated resource/tenant data. Native
S3-stub/Parquet/CAS publication, manifest-supervision restart, exact MCP assembly,
HTTP/MCP search and cross-tenant denial are checked. This is not whole-node or
provider recovery. Static credentials do not authenticate a public Collector
receiver or create a dynamic tenant gateway.

Actual 401/whole 413 and injected pre-publication 503/429 each occur once via
both direct HTTP and gRPC bridging, store zero, and cause an observed exporter
error. The bridge maps them to Unauthenticated/Unknown/Unavailable/
ResourceExhausted respectively. A malformed env-header entry omits authorization
and yields 401; an env token overrides a good programmatic token and also yields
401. No blanket retry policy is inferred. A successful `force_flush` after an
earlier scheduled failure would not establish delivery: exporter results and
stored counts are decisive. Shutdown succeeds in these controlled cases.

This profile preserves booleans, link tracestate and event/link drop counters;
no known pre-Pulse loss is normalized away. NaN payload/sign/signaling are still
outside Pulse's class-fidelity contract. No full Kura build/bootstrap, deployed
Alloy/TLS, framework auto-instrumentation, sampling/queue pressure, partial
success, ambiguous post-publication outcome, durable crash queue, capacity,
provider/node fault/restore or production cutover is accepted.

## Explicit external preparation and reproduction

From the Pulse repository root, prepare a fresh project with the pinned Rust
compiler. Public dependency downloads are preparation, not telemetry export:

```sh
producer=$(mktemp -d "${TMPDIR:-/tmp}/pulse-rust-sdk.XXXXXX")
mkdir -p "$producer/src"
cp test/fixtures/traces/produce_rust_sdk.rs.txt "$producer/src/main.rs"
cp test/fixtures/traces/rust-sdk.Cargo.toml.txt "$producer/Cargo.toml"
cp test/fixtures/traces/rust-sdk.Cargo.lock.txt "$producer/Cargo.lock"
cp test/fixtures/traces/rust-sdk.build.rs.txt "$producer/build.rs"
(cd "$producer" && cargo fetch --locked && cargo build --locked --offline)

PULSE_TEST_RUST_SDK_DIR="$producer" \
PULSE_TEST_RUST_SDK="$producer/target/debug/pulse-rust-sdk-fixture" \
PULSE_TEST_OTELCOL=/absolute/path/to/pinned/otelcol \
ERL_FLAGS='+S 4:4' mix test \
  test/pulse_web/controllers/rust_sdk_live_test.exs \
  --include rust_sdk --max-cases 4
```

Prepare and checksum the actual Collector executable as described in
[the bridge fixture](../collector_bridge/README.md); no Go SDK producer is needed
for this suite. Use direct executables, not daemonizing wrappers. The helper
signals the owned direct Unix PID, not a subprocess tree. Environment scrubbing
is not an OS sandbox. Collector port handoff races fail readiness, never attach
to another process. Missing paths fail explicit opt-in; default tests and
`PULSE_INTEGRATION=1` still exclude `:rust_sdk`.

The ordinary offline command is simply:

```sh
ERL_FLAGS='+S 4:4' mix test test/pulse/otlp/rust_sdk_test.exs --max-cases 4
```

Live output under `tmp/PulseWeb.RustSDKLiveTest/` includes source snapshots,
received messages, request observations, binary hash, Collector/producer logs
and MCP responses. Earlier local captures were preserved before deliberate regeneration for the
explicit batch configuration, shared configuration constants and changed
source/tracing lines. The initial 15-file index was
`3f15d7d7c099f11116f50fc68ef0b3c1a0bcd9a40db8270610a82b13b4b8c3ed`; the intermediate
explicit-batch index was `7264619035798afddc0cdf8617269e0b0d972bb241c1e41cc7268457aeb354d3`.
Neither is the current replay pin. No fidelity, status, request-count, metadata
or budget assertion was weakened. Captured error-message ports are owned,
capture-local loopback addresses, not deployed destinations.
