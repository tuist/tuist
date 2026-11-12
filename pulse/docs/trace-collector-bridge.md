# Collector bridge compatibility

Pulse accepts OTLP/HTTP and, through its opt-in [gRPC receiver](otlp-grpc.md), OTLP/gRPC.
This page covers deployments that keep a Collector or Alloy between a sender and
`POST /v1/traces`. Such a bridge is **not automatically transparent**.
Validate the exact SDK/exporter, Collector version and processing configuration
before replacing a tracing destination.

## Locally exercised profile

A controlled loopback run exercises **Go SDK 1.43.0 → OpenTelemetry Collector
core 0.137.0 → gzip OTLP/HTTP → Pulse**. It checks three spans across two services
with actual HTTP W3C trace-context propagation; remote-parent/link flags,
tracestate, schemas, scope metadata, events, dropped counters, arrays, int64 above
2^53, signed zero and non-finite doubles. Two tenants use the same trace/span IDs
with distinct resources and credentials. Stored records agree with the SDK's
export request messages after a manifest-supervision restart and are readable
through MCP. This uses a local HTTP object-store stub, **not a real provider or
node restart**. It is not deployed SDK, Alloy, TLS, capacity or cutover acceptance.

The SDK's batches are retained without Collector re-batching or queuing:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:4317
exporters:
  otlphttp/pulse:
    endpoint: https://pulse.example.com
    compression: gzip
    headers:
      Authorization: "Bearer ${env:PULSE_TOKEN}"
      X-Scope-OrgID: "${env:PULSE_TENANT}"
    sending_queue:
      enabled: false
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: []
      exporters: [otlphttp/pulse]
```

This is an illustrative private-sidecar shape, not an HA buffering recommendation.
The example leaves Collector retry defaults in effect, unlike the conformance
run's 100 ms initial / 200 ms maximum interval and five-second total retry budget.
The run also uses loopback HTTP and synthetic tokens. Production TLS, outage/retry horizons, SDK queue limits and Collector
buffering need independent validation. With queuing disabled, outages pressure
SDK queues; enabling a Collector queue changes acknowledgment/crash semantics.
External durable buffering, if needed, remains the operator's Collector concern,
not a new Pulse WAL or acknowledged-data authority.

Bind receivers privately, configure receiver authentication/TLS where needed, and
bind each trusted source to the right tenant pipeline. The local test's receivers
are not an authenticated multi-tenant front door. Static exporter headers ignore
untrusted incoming gRPC tenant metadata; resource environment/service attributes
are **not authorization**. Do not let public callers choose a privileged pipeline
or turn their incoming tenant header directly into an authenticated export.

## Losses found before Pulse

### Collector batch-split schema loss

The tested **core Collector 0.137.0** batch processor, with mixed resources and
`send_batch_size: 2` / `send_batch_max_size: 2`, can omit resource and scope schema
URLs from a split span. The SDK export request still contains both URLs; the
Collector HTTP request already lacks them. Frozen counterexample replay detects
this difference. Pulse preserves the received empty values and cannot reconstruct
the originals.

The locally passing profile removes Collector re-batching and keeps SDK batches.
Do not infer that another batch size, Collector/Alloy version or exporter queue
batching preserves schemas. Verify a fixed version/profile if you need those
features; this is not a claim that all versions are broken or that an old pinned
version is a production/security recommendation.

### Go SDK link tracestate omission

Go SDK **1.43.0's OTLP trace exporter** omits a link's tracestate even when the
SDK span snapshot contains it. Its export request message already has an empty
link tracestate before the Collector receives it. Span tracestate and link
IDs/flags/attributes remain intact in this run. Pulse cannot recover metadata
an exporter never sent. Validate another exporter/version or an upstream fix
if link tracestate is required. This is not a Pulse storage repair.

## Delivery observations, not blanket guarantees

- Controlled HTTP **429 and 503** before publication are retried by the Collector
  with unchanged decompressed request messages and eventual Pulse acknowledgment.
  This does not exercise a lost response after a successful commit; ordinary
  unkeyed retries can duplicate spans. No exactly-once delivery claim.
- Actual Pulse **401** and whole-request **413** are not retried in this profile.
  A 413 request appends nothing, but another smaller request belonging to the
  same trace can succeed: trace-wide atomic ingestion is not provided.
- A deliberately malformed **public-protobuf** probe, not ordinary SDK output,
  produces HTTP 200 with one rejected and one durable span. The Collector does
  not replay the whole batch. Its upstream gRPC response is successful with an
  empty partial-success message, **not the backend's rejection count**. Monitor
  receiver/Collector rejection diagnostics rather than trusting the sender's RPC
  status to prove every supplied span was retained.
- The SDK producer records export failures separately from `ForceFlush` results.
  A background export can fail even when a later flush reports no error. Ending
  a span or seeing a fixture process exit successfully is not a durability ack.
- Collector queues/processors may acknowledge admission before Pulse publication.
  A crash can lose such buffered data unless the external pipeline provides and
  validates its own durability. Pulse's durability boundary remains segment PUT
  plus manifest CAS for accepted records.

The SDK batch/attribute/event/link limits in this run are deliberately tiny and
explicit. They are not default-SDK coverage, safe universal batch sizes, sustained
load, crash/restart delivery, multi-instance/provider pressure or a migration
approval. Validate your actual SDKs and deployment profile next. See the
[remaining OTel/Tempo gaps](trace-otel-compatibility.md) and
[fixture provenance/reproduction](../test/fixtures/traces/collector_bridge/README.md).
