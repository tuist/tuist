# OpenTelemetry trace compatibility and remaining gaps

Pulse accepts OTLP/HTTP JSON and protobuf at `POST /v1/traces`, optionally gzip.
An opt-in [OTLP/gRPC receiver](otlp-grpc.md) serves the same traces over gRPC. A
Collector or Alloy that exports OTLP/HTTP downstream remains a supported
alternative, but such a bridge is not automatically transparent. See [trace configuration](traces.md#connect-an-sdk-or-collector).

## Implemented fidelity

New spans preserve typed resource, instrumentation scope, span, event and link
attributes, including nested arrays/kvlists, bytes, int64, booleans, empty values,
finite doubles and signed zero. IDs, source timing, flags, tracestate, status,
schema URLs and dropped counters are retained. Original types live in `otlp`;
legacy records without that envelope remain unknown, never reconstructed.

### Non-finite doubles

Both transports accept `doubleValue` with IEEE NaN and positive/negative infinity.
JSON spells these exactly `"NaN"`, `"Infinity"`, `"-Infinity"`; protobuf carries
IEEE doubles. Nested values and all five attribute owners retain the double tag.
Finite numeric JSON strings normalize to finite numbers. Invalid spellings,
multiple AnyValue members and out-of-range numeric input remain rejections.

BEAM cannot hold non-finite floats. Query-friendly projections use the strings
`NaN`, `Infinity`, `-Infinity`; typed metadata keeps `{"doubleValue":"NaN"}`
distinct from `{"stringValue":"NaN"}`. Exact and regex `query_traces` attribute
predicates intentionally inspect **projections**, including base64 bytes and
these spellings. They do not prove original string type. Use original-string
search selectors or inspect `otlp` when type matters.

Parquet, compaction, complete stored-trace assembly and Tempo JSON/protobuf
export preserve these classes. Protobuf export canonicalizes NaN to a quiet NaN:
**NaN sign, signaling state and payload bits are not retained.** Finite double
bits, including signed zero, keep their existing contract. A different NaN
payload can normalize to the same typed record, including at resource grouping
and duplicate reconciliation. This is class fidelity, not wire-byte replay.

Tempo tag discovery renders floats with its distinct vocabulary: `NaN.0`,
`+Inf.0`, `-Inf.0` (type `float`), not the OTLP JSON spellings. Do not send these
autocomplete strings as OTLP doubles. Stored string values remain type `string`.
Filters still accept only the documented original-string parent predicates;
this does not implement non-finite arithmetic. Retained-context search separately supports [bounded int64/status/span-duration expressions](trace-query-expressions.md); discovery filters retain their string-only grammar.

### Upgrade boundary

Pause trace ingress, drain in-flight/keyed retries, and upgrade **all trace
readers, writers, compactors and serving application/native pairs** sharing the
bucket before resuming writers. This is not a rolling mixed-artifact guarantee. Required
trace tuple: `{2,1,3,7,12}` (metadata, span search, Tempo export, retained-context
search, discovery). The envelope is still version 1; physical columns and ordinary
finite records with string service names are unchanged. Old readers/compactors
reject these new values. Startup checks cannot fence another serving pool.

Service promotion now uses only an original `stringValue` for `service.name`.
Non-string values stay in the resource attributes but produce no promoted
service. This also stops the earlier promotion of base64 byte values. Those
byte-service requests have different normalized fingerprints: drain their keyed
retries before upgrade. Old stored projections are not rewritten. If the same
byte-service span is stored once by an old writer and again by a new writer,
the differing service projections are a permanent stored-span conflict even
though the original typed resource is equal: `get_trace` reports it, and Tempo
lookup rejects the whole trace. Draining keyed retries does not reconcile existing
or unkeyed duplicates; avoid mixed writers/resends of those inputs. No automatic
repair is provided. Never rotate keys, overwrite objects or resend unkeyed to
evade conflicts. Keep compatible
rollback artifacts and coherent history; see [keyed ingestion](keyed-ingestion.md).

## Existing Erlang/Elixir clients

Two pinned local API 1.5/SDK 1.7/exporter 1.10 profiles exercise real
Phoenix/Bandit/Finch HTTP instrumentation, task propagation, direct gzip HTTP and
gRPC bridging. Ecto handler telemetry is synthetic, not database acceptance.
They expose upstream boolean-to-string conversion and event/link attribute-drop
counter loss before Pulse. Delivery callbacks are checked separately from
asynchronous flush, including OTP-specific 503 retry behavior. See
[Erlang/Elixir exporter evidence and limits](trace-elixir-clients.md). These are
not full application/deployment or all-signal SDK compatibility claims.

## Rust SDK/tracing component

A pinned API/SDK0.31.0, exporter0.31.1 and tracing-opentelemetry0.32.1 component
exercises a real loopback HTTP/W3C hop, direct HTTP (programmatic and env headers)
and gRPC→Collector0.137→gzip HTTP, owned S3-stub publication/restart and HTTP/MCP
queries. This profile retains original booleans, link tracestate and event/link
attribute-drop counters. Actual401/whole413 and pre-publication injected429/503
are observed once on each transport, produce exporter errors and store nothing;
this differs from the other pinned clients' retry behavior. Programmatic HTTP
URLs need `/v1/traces`; malformed env entries can omit headers and env credentials
override programmatic ones. No default HTTP-client policy, TLS, full application,
queue/crash or deployed Alloy acceptance is implied. See
[Rust client evidence and limits](trace-rust-clients.md).

## Gaps to validate before replacing a Tempo deployment

| Area | Remaining work or explicit limit |
| --- | --- |
| Actual SDK and bridge | A local Go SDK 1.43/core Collector 0.137 non-rebatching profile now checks real W3C HTTP propagation, gRPC→gzip HTTP, flags/typed metadata, static tenant isolation, retries and stored replay. It finds SDK link-tracestate omission and Collector batch-split schema loss before Pulse. This is not the actual deployed SDK/Alloy/TLS pipeline; validate your exact versions and queue/processor configuration. See [bridge contract](trace-collector-bridge.md). |
| Delivery and retries | The local Go/Collector profile retries injected pre-publication 429/503, rejects actual 401/413 without replay, and does not retry a public-protobuf malformed partial-success batch. In this Collector 0.137 profile, the upstream gRPC caller sees success without the backend rejection count; SDK flush may hide earlier background failures. Real overload/provider ambiguity,400/409 propagation, outage buffering, queued/crashed/restarted delivery and other SDK policies still need acceptance. A sample batch size is not universal safety proof. |
| Direct gRPC | Opt-in [OTLP/gRPC receiver](otlp-grpc.md) sharing the HTTP decoding, limits and storage path. Deployed-client acceptance is not established. |
| Additional OTLP fields/forms | Resource entity references remain unsupported. Singular messages now merge under cumulative owner budgets, and known oneofs follow protobuf selection; shared wire capability 3 is required. Exact quoted/unquoted decimal/exponent integer forms preserve source time/types and reject fractional underflow. Known duplicate JSON fields reject whole with receiver-specific unknown-field handling. Quoted trace uint32 counts and fixed32 flags now normalize exactly at every owner; enum digits must remain numeric tokens, not strings. Remaining null/presence edges and broader wire conformance remain generic protocol gaps regardless of sampled producer usage. See [shared wire contract](otlp-wire.md). |
| Large retained traces | Complete lookup fails above 5,000 stored spans or 16 MiB rather than truncating. Ingest success does not guarantee a trace fits retrieval. Sampling and exporter completeness remain external. |
| Tempo/Grafana consumers | Lookup/search/discovery have explicit bounded subsets and fixture evidence, not complete TraceQL or deployed datasource/browser parity. Shared client/server span IDs and larger traces still need a compatible, non-guessing policy. |
| Storage and capacity | Native pruning and configured retention exist, but representative cold/broad-history, high-cardinality, separate-node/provider, recovery and restore acceptance are still needed. Retain-forever flat catalogs are not bounded. |

Tail sampling, spanmetrics/servicegraph generation, collection and instrumentation
remain external pipeline responsibilities. They are requirements only if your
workload needs them; Pulse does not silently add sampling or fabricate spans.
Live rollout, shadow delivery, outage/load/restore exercises and cutover require
explicit operator authorization and a tested rollback plan.
