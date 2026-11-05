# OTLP over gRPC

Pulse can receive OTLP logs, metrics and traces over gRPC, so OpenTelemetry
Collectors, Grafana Alloy and SDK exporters can send to it directly, without
a bridge that converts gRPC to HTTP.

The receiver is disabled by default. When enabled, it serves the standard
`Export` methods of:

- `opentelemetry.proto.collector.logs.v1.LogsService`
- `opentelemetry.proto.collector.metrics.v1.MetricsService`
- `opentelemetry.proto.collector.trace.v1.TraceService`

Requests are handled exactly like OTLP/HTTP protobuf requests to `/v1/logs`,
`/v1/metrics` and `/v1/traces`: the same supported data types, limits,
idempotency behavior, partial-success reporting and storage. Anything the
HTTP receivers reject, the gRPC receiver rejects too.

## Enable it

| Environment variable | Default | Meaning |
| --- | --- | --- |
| `PULSE_OTLP_GRPC_PORT` | unset (disabled) | Port to listen on. Setting it enables the receiver; `4317` is the conventional OTLP/gRPC port. |
| `PULSE_OTLP_GRPC_IP` | `0.0.0.0` | Address to bind. |
| `PULSE_OTLP_GRPC_MAX_MESSAGE_BYTES` | `16777216` | Largest export message after decompression. Larger messages fail permanently. |
| `PULSE_OTLP_GRPC_MAX_IN_FLIGHT` | `64` | Admitted calls receiving/ingesting on each instance. Further calls wait within their deadline (HTTP/2 backpressure). |
| `PULSE_OTLP_GRPC_TIMEOUT_MS` | `30000` | End-to-end call deadline, including admission wait, body completion and storage; expires as retryable `UNAVAILABLE`. |

With the Helm chart, set `otlpGrpc.enabled=true` (and optionally
`otlpGrpc.port`, `otlpGrpc.maxMessageBytes`, `otlpGrpc.maxInFlight`). The
chart then exposes the port on the pod and the Service, with
`appProtocol: grpc`.

The listener speaks plain-text HTTP/2 (h2c). Terminate TLS in front of Pulse
with a load balancer or ingress that supports gRPC, as you would for HTTP.
Every instance can receive exports; no instance is special.

## Tenants and authentication

gRPC metadata carries the same information as HTTP headers:

- `x-scope-orgid` names the tenant. Without it, the tenant is the username of
  Basic credentials, or `default`.
- `authorization` carries `Bearer <token>`, or `Basic <tenant>:<token>` in the
  Grafana Cloud style. Basic credentials authorize only their username's
  tenant.
- `idempotency-key` makes the export keyed, exactly as on HTTP.

Malformed non-visible-ASCII values in these three text metadata fields reject
with `INVALID_ARGUMENT`; they are never silently omitted or converted into a
default tenant/unkeyed request. Unknown metadata, including binary `-bin` fields,
is not interpreted.

Tenant and credential are checked from metadata before the listener reads or
decompresses the message, so a call without valid credentials is answered
(`UNAUTHENTICATED`, `PERMISSION_DENIED` or retryable `UNAVAILABLE`) without
reading its body. Authorization runs again when the message is ingested. This
changes the listener's native interface: upgrade the application and its
native artifacts together.

For example, an OpenTelemetry Collector exporter:

```yaml
exporters:
  otlp/pulse:
    endpoint: pulse.example.com:443
    headers:
      x-scope-orgid: acme
      authorization: "Bearer ${env:PULSE_TOKEN}"
```

A Grafana Alloy or k8s-monitoring OTLP destination with
`protocol: grpc` and Basic auth (username = tenant, password = token) works
the same way.

## Compression and limits

Requests may be uncompressed, gzip or zstd. Responses are gzip-compressed
when the client accepts it. The message limit applies to the decompressed
message, so a small compressed request cannot expand past it.

In-flight admission is acquired before tonic buffers/decompresses the unary
message. The call deadline starts before admission and includes incomplete
bodies, so a responsive connection cannot reserve a slot indefinitely without
finishing its export. Time spent waiting or receiving the body reduces the time
left for the client response; storage does not receive a fresh full timeout.
A timeout or disconnected caller does not free admission while
its BEAM handler still owns the reply. One second after the configured gRPC
timeout, a watchdog requests termination of a stuck BEAM handler; its monitored
exit releases reply/admission and reports retryable `UNAVAILABLE`. This is not
a preemption deadline for a handler executing native code. Handler heap-limit termination returns
permanent `RESOURCE_EXHAUSTED` without `RetryInfo`, rather than encouraging an
identical oversized retry. These are per-instance handler/message bounds, not
limits on all connections, HTTP/2 transport buffers, native allocations or
provider I/O that can outlive a killed task. Apply network/connection admission
at the proxy and measure aggregate pressure across replicas.

## Status codes

Outcomes follow the OTLP specification, so exporters retry only what can
succeed later:

| Situation | gRPC status | Retried by exporters |
| --- | --- | --- |
| Accepted, possibly with rejected items | `OK` with `partial_success` | No |
| Malformed or invalid request | `INVALID_ARGUMENT` | No |
| Missing or wrong credentials | `UNAUTHENTICATED` | No |
| Keyed request whose key already stores different content | `ALREADY_EXISTS` | No |
| Message or batch over a limit | `RESOURCE_EXHAUSTED` without `RetryInfo` | No |
| Instance ingest capacity exhausted | `RESOURCE_EXHAUSTED` with `RetryInfo` (1s) | Yes |
| Storage unavailable, timeout or handler failure | `UNAVAILABLE` | Yes |
| Any method other than `Export` | `UNIMPLEMENTED` | No |

Inspect `partial_success` on `OK` responses: many exporters do not retry
rejected items, exactly as with OTLP/HTTP.

A timed-out/disconnected call can still publish before its handler stops; unkeyed
delivery is at-least-once, not exactly-once. Reuse an `idempotency-key` only with
identical request content when the client supports it; never evade an exact-byte
409/`ALREADY_EXISTS` conflict by changing keys or resending a subset.

## Upgrading

The receiver ships as a separate native library in the same release. Upgrade
every instance before enabling it; an instance without the library refuses
to start the receiver rather than starting without it. Current applications
require native gRPC API **2** for the admission/lifetime contract. Upgrade every
serving app/native pair; this does not change OTLP wire or stored signal formats.
