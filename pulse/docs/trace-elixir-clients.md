# Erlang and Elixir trace exporters

Pulse's OTLP/HTTP trace receiver has been exercised locally with the real
Erlang OpenTelemetry SDK **1.7.0**, API **1.5.0** and OTLP exporter **1.10.0**.
This is compatibility testing of existing clients, not a Pulse SDK or a new
runtime dependency.

Two isolated producer profiles cover `grpcbox` **0.18.0** and **0.17.1**,
Phoenix instrumentation **2.0.1**, Bandit instrumentation **0.3.0**, process
propagator **0.3.0**, git-pinned Ecto instrumentation, and both git-pinned Finch
instrumentation **0.3.0** and Hex **0.2.0**. The exact optional producer sources,
dependency locks, checksums and reproduction instructions are in the
[fixture README](../test/fixtures/traces/elixir_sdk/README.md).

## What was exercised

Each profile exports the same synthetic five-span workload through both:

- Direct **OTLP/HTTP protobuf with gzip** to Pulse.
- **OTLP/gRPC to core Collector 0.137.0**, then gzip OTLP/HTTP to Pulse. The
  Collector has no processors, sending queue or exporter retry in this profile.

A real loopback HTTP request runs through Req/Finch, Bandit and a Phoenix router.
The instrumentation libraries create their own spans and route attributes.
W3C headers cross that HTTP connection, and the process-propagator library
carries the server context into a real task. Ecto's actual instrumentation
handler receives synthetic query telemetry: **no database or Ecto query execution
is exercised**. The task is not an Oban application or lifecycle test.

SDK record snapshots are compared with an export-request message re-encoded
using the exporter's own trace conversion and generated protobuf encoder. That snapshot is **not a literal gRPC wire
capture or an independent upstream oracle**. Actual HTTP request bodies captured
before Pulse agree with the decoded SDK messages. Tests also cover typed data,
int64 above 2^53, signed-zero bits, events, links, schemas, flags, status and
parent relationships.

An owned local S3 HTTP stub exercises native Parquet and conditional manifest
publication. After restarting manifest supervision, authenticated MCP trace
lookup and both basic and same-span string-filtered Tempo metadata searches
recover the stored data. Cross-tenant MCP reads fail. This is **not a real object
provider, whole-node restart, deployed application bootstrap or capacity test**.

## Upstream losses are not repaired

The pinned exporter changes some data before Pulse receives it:

| SDK record | Exported OTLP in this profile |
| --- | --- |
| Boolean attribute, including boolean array elements | Original `stringValue` spelling `"true"` or `"false"`, not `boolValue` |
| Event attribute-drop counter of 1 | Counter omitted, decoded as 0 |
| Link attribute-drop counter of 1 | Counter explicitly 0 |
| Original link context flags/remote identity | Not represented in the SDK link record; exporter emits flags 256, declaring remote=false |

The boolean conversion comes from exporter `1.10.0` checking Erlang atoms before
booleans; booleans are atoms. Event and link counter behavior is in its trace
conversion. Frozen SDK snapshots retain the original values, while replay tests
assert these precise differences and strict agreement after export. Pulse never
turns received strings back into booleans or invents missing counters/flags.
Link tracestate is retained in this Elixir profile, unlike the separately
[documented Go SDK profile](trace-collector-bridge.md).

BEAM cannot represent NaN or infinity as floats, so this SDK producer does **not**
validate non-finite double emission. Literal `"NaN"` strings are not substitutes.
The receiver's non-finite contract is tested separately.

## Delivery results are transport-specific

Controlled direct-HTTP cases on the recorded Elixir/OTP toolchain show:

- Actual **401** and whole-batch **413** produce exporter callback `:error` and
  store no spans. The five-span batch is never acknowledged as a subset.
- Injected pre-publication **429 + Retry-After** produces callback `:error`
  without replay in this profile.
- Injected pre-publication **503 + Retry-After** is retried by OTP `httpc` with
  the same compressed body, then succeeds and stores five spans.
- The SDK's asynchronous `force_flush` returns `:ok` in **all** those cases.
  Tests wait for and assert the actual exporter callback separately.

Do not generalize that retry policy to another OTP release, transport, queued
Collector or SDK. No post-publication lost acknowledgment, durable SDK queue,
crash recovery, exactly-once delivery or TLS/mTLS acceptance is established.
A successful flush alone is not proof of backend publication.

## Query compatibility remains a subset

String equality/positive-regex AND selectors, explicit most-recent metadata
search and exact-ID lookup work in the local workload. Retained-context metadata
search also supports [bounded negated regex, status/int64 OR and span-duration
comparisons](trace-query-expressions.md). These run against locally ingested SDK
data and independent public Tempo fixtures; unsupported syntax still rejects the
whole request. Discovery and window-local search retain their narrower grammar.
Grafana-side SQL/frame expressions,
service maps, profiles, streaming search and trace/log/metric correlations are
separate client or pipeline requirements, not proven by this trace test.

This does not validate Elixir OTLP metric/log exporters, an entire application's
instrumentation graph, application-specific HTTP-server forks, production Alloy
processing, separate-node/provider behavior or production cutover. See the full
[trace compatibility requirements](trace-otel-compatibility.md).
