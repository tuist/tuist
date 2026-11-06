# Rust trace exporters

Pulse accepts OTLP/HTTP and, when its opt-in [gRPC receiver](otlp-grpc.md) is
enabled, OTLP/gRPC. A pinned local Rust component
profile exercises OpenTelemetry API/SDK 0.31.0, OTLP exporter 0.31.1 and
tracing-opentelemetry 0.32.1 through both direct HTTP and a core Collector 0.137
bridge. This is evidence for those library paths, not a whole application,
deployed Alloy, TLS, durable exporter queue or capacity acceptance.

## Endpoints and authentication

For the 0.31.1 HTTP exporter, a programmatic `with_endpoint` URL is used **as
provided**. Include the full receiver path, for example
`https://pulse.example.com/v1/traces`. The signal-specific
`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` also uses a full URL; only the generic
`OTEL_EXPORTER_OTLP_ENDPOINT` setting appends the signal path. Programmatic
endpoints override environment endpoints in this exporter. Do not assume these
settings are interchangeable.

When your application selects gRPC from its configured URL, point it at Pulse's
[OTLP/gRPC receiver](otlp-grpc.md) or at a trusted Collector/Alloy gRPC receiver
that exports OTLP/HTTP to Pulse. The pinned profile below exercised only the
Collector path. An application choosing gRPC for an empty or `/` URL path must be given a
full `/v1/traces` path to select direct HTTP. A port or `https` scheme alone does
not establish the transport.

The exporter accepts standard environment headers:

```sh
OTEL_EXPORTER_OTLP_TRACES_HEADERS="authorization=Bearer%20<TOKEN>,x-scope-orgid=production"
```

Values are URL-decoded. In this pinned exporter, environment headers override
programmatically supplied headers with the same name. Malformed entries can be
silently omitted rather than causing startup failure. Verify actual delivery
and authorization errors, not just successful exporter construction.

Static Collector downstream headers select a fixed authorized Pulse tenant.
Incoming gRPC metadata does not establish tenant authorization and must not be
allowed to override those headers. A trusted loopback receiver with static
credentials is not an authenticated public multi-tenant gateway. See
[Collector bridge configuration and limits](trace-collector-bridge.md).

## What was exercised locally

The synthetic component runs a real reqwest-to-TCP HTTP/1.1 service hop with W3C
traceparent/tracestate. It emits a client root, a remotely parented server and a
locally parented `tracing` adapter span. Three isolated destinations share the
same IDs: direct HTTP with programmatic headers, direct HTTP using only
environment headers, and gRPC bridged to gzip HTTP. They publish through an
owned S3 HTTP stub, native Parquet and manifest CAS. Manifest-supervision restart,
MCP complete lookup and HTTP/MCP retained-context search verify stored metadata
and tenant boundaries. This is not a provider or whole-node restart.

Original SDK `SpanData` snapshots are compared with the requests actually
received before Pulse. Int64 above 2^53, booleans, signed-zero bits, nonfinite
double classes, schema/scope metadata, tracestate, flags, status, events and
links survive in this profile. Explicit event/link attribute limits each drop
one attribute; the exporter preserves both counters. It also preserves link
tracestate and boolean types, unlike the independently documented Go and
Erlang/Elixir profile losses. This does not guarantee other versions or
processors are lossless.

Actual HTTP 401 and whole-request 413, and injected **pre-publication** 429/503,
produce exporter errors and store nothing. The same failures through this
non-queuing/non-retrying Collector reach the Rust caller as gRPC
Unauthenticated, Unknown, ResourceExhausted and Unavailable respectively. Each
attempt occurs once in this profile, including responses with Retry-After.
Malformed environment-header entries omit authentication and fail with 401;
an environment token also overrides a valid programmatic token and fails with
401. No error case is treated as a successfully delivered batch.

`force_flush` is not the sole delivery signal: a failed scheduled export can
precede a successful flush in ordinary configurations, although this controlled
profile deliberately avoids scheduled export. The harness separately observes export results and
durable stored counts. These controlled failures do not prove post-publication
recovery, exactly-once delivery, retry policies in other clients, disk queues,
crash recovery, partial-success handling, or real overload behavior.

## Deliberate profile differences and remaining work

- This is a component workload, not application bootstrap or automatic HTTP
  framework instrumentation. Rich resource/schema/scope fields exercise more
  metadata than applications that omit them. Sampling admits all three spans.
  The explicit flush profile has a 64-span queue/batch and a 24-hour scheduled
  delay, far beyond the owned child's 30-second await, so a slow host cannot
  race the default five-second timer within the admitted exercise. Default
  application batching, unsampled traffic and queue saturation are not accepted.
- The fixture supplies a blocking reqwest client with no proxy, no redirects and
  a three-second timeout. It has no TLS or HTTP/2 feature. This is not the
  exporter's default HTTP-client policy or a deployed application's feature
  graph, even when the dependency versions match.
- The bridge has no processors, re-batching, sending queue or exporter retries.
  Validate the exact deployed Alloy/Collector version and processing pipeline;
  earlier bridge tests found schema loss under mixed-resource batch splitting.
- Default tracing-layer source/thread/busy/idle fields and wall-clock times vary.
  Frozen captures are immutable evidence, not byte-reproducible telemetry.
- Source/lock/embedded-input checks and a recorded executable checksum detect
  accidental profile mismatch. They are not compiler/dependency attestation or
  an OS sandbox. Optional executables are trusted inputs.
- Full application/service topology, TLS, deployed exporter behavior, provider
  faults, multi-instance pressure, recovery/restore, large traces and production
  cutover remain separate acceptance requirements.

The [fixture provenance and reproduction instructions](../test/fixtures/traces/rust_sdk/README.md)
include the complete lock, resolved feature tree, source and capture hashes.
Ordinary replay uses only the normal Pulse toolchain. The optional `rust_sdk`
live suite is excluded from ordinary and S3 integration CI and fails, rather
than skips, when explicitly included without prepared tools.
