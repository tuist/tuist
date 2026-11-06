# OpenTelemetry logs

`POST /v1/logs` accepts OTLP/HTTP JSON and protobuf, optionally gzip-compressed.
Use `Content-Type: application/json` or `application/x-protobuf`, the tenant's
`Authorization: Bearer <token>` and `X-Scope-OrgID`. Success and partial-success
responses use the request encoding and exact MIME type, without a charset.
An empty successful protobuf response is valid.

Logs can also be exported over gRPC to the opt-in [OTLP/gRPC receiver](otlp-grpc.md),
which handles them exactly like this HTTP receiver; a Collector bridge is not
required. OTLP gauges, cumulative sums, cumulative explicit histograms and summaries use [`/v1/metrics`](metrics.md); delta and exponential histogram semantics remain unsupported.

## Collector example

This example forwards only logs. Keep collector listeners and Pulse private or
configure TLS and authentication at your ingress boundary. Provision the
collector's `PULSE_TOKEN` separately from Pulse's hashed tenant credentials.

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 256
  batch:
    timeout: 1s
    send_batch_size: 128
    send_batch_max_size: 128
exporters:
  otlphttp/pulse:
    endpoint: http://pulse.observability.svc:4000
    compression: gzip
    headers:
      Authorization: "Bearer ${env:PULSE_TOKEN}"
      X-Scope-OrgID: production
service:
  pipelines:
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlphttp/pulse]
```

Batch settings are starting points, not capacity guarantees. Rich resource/scope
metadata is repeated in storage for every record. Reduce batches when their
normalized payload exceeds the [ingest limits](ingest-limits.md), even if their
compressed request is small. Compare actual exporter deliveries with an
existing authoritative destination before a backend switch.

## Stored content and raw queries

The raw `query_logs` MCP tool returns timestamps, severity, service, body,
trace/span IDs, attributes and resource attributes, plus an `otlp` envelope.
Loki and legacy records have `otlp: null`; upgrading cannot recover metadata
that an older receiver never stored. Older observed-only records with a null
event-time column are not automatically re-indexed by this upgrade; validate
repair/re-ingestion before enforcing retention or relying on time-ranged reads
for such existing objects.

The primary body/attribute/resource fields are query-friendly projections.
The `otlp` envelope retains canonical typed AnyValues for the body and attributes,
complete resource/scope attributes, scope name/version, both schema URLs,
flags, dropped-attribute counts and event name. Integer AnyValues retain exact
signed 64-bit values as decimal strings in that envelope. Byte values use
canonical padded base64 with their byte tag, distinct from identical string
values. Finite doubles retain their type and signed zero; non-finite doubles
use `NaN`, `Infinity`, and `-Infinity` spellings. Empty values, arrays and key-value
lists remain distinguishable. Original attribute order is retained.

Resource attribute names are preserved verbatim, not renamed to deployment-
or product-specific conventions. LogQL/Loki responses remain their existing
line-oriented projections; use raw MCP logs for the typed envelope. Raw log
JSON has a 16 MiB result-text ceiling independent of the row/scan/heap budgets.
Exhaustion returns an error, never a clipped metadata tree. Narrow the time
range or limit; the enclosing MCP transport envelope has additional overhead.

### Time and correlation

A nonzero event time is the query/retention timestamp. Otherwise the observed
time is used. Both original OTLP times remain in the envelope as decimal strings;
`0` means unknown, including an omitted source field.

When both times are unknown, an **unkeyed** request uses receive time and records
it as `otlp.receivedTimeUnixNano`. Keep node clocks synchronized. A **keyed**
request with an unknown effective timestamp fails in full with HTTP 400
(`missing_keyed_timestamp`): receive-time assignment would change retry identity.
Supply event or observed times before using `Idempotency-Key`.

Valid trace/span IDs normalize to lowercase hex. Zero or invalid string IDs mean
no associated trace/span in the primary projection, rather than discarding an
otherwise valid log. The envelope preserves that supplied string for diagnosis.
Non-string IDs are malformed records. JSON IDs are hex, not ProtoJSON base64.

## Rejections and durability

For unkeyed requests, malformed record values produce OTLP partial success with
`rejectedLogRecords`; the JSON count is a decimal string. A keyed request with
any semantic rejection fails in full with 400 and publishes nothing. Accepted
keyed retries use the same complete normalized content, including typed metadata.
Unkeyed lost-response retries can duplicate records. Keyed uploads are create-only;
existing byte differences fail permanently with HTTP409 `keyed_content_mismatch`
(OTLP code6), without retry guidance or overwriting the object. See
[keyed ingestion](keyed-ingestion.md) for exact-byte recovery, all-writer upgrades,
provider costs and compaction/retention behavior.

Invalid resource/scope metadata rejects the whole request with 400. Empty or
duplicate attribute keys, invalid AnyValue oneofs/types, out-of-range times,
severity or dropped counts are not silently rewritten. Unknown protocol fields
are ignored, but JSON trees and protobuf field occurrences still consume
request-node preflight. Resource entity references remain unsupported: nonempty
`entityRefs` reject the whole request. Singular protobuf messages merge under
cumulative owner budgets, and malformed UTF-8 rejects in full. Exact quoted
and unquoted decimal/exponent integers preserve source time and typed values
without float rounding or fractional underflow. Known duplicate JSON fields reject the whole request, including escaped/null
names; unknown fields remain ignored in the logs schema. Require shared OTLP
wire capability 3; see [wire semantics and upgrade
rules](otlp-wire.md).

Safety-budget violations return 413 and append nothing, even when only one
record is oversized. Logs have a 262,144 request-node default
(`PULSE_INGEST_MAX_OTLP_NODES`), effective logical depth at most 32, and a fixed
16 MiB normalized-record ceiling including repeated metadata and escaped
strings. Quoted numeric-double spellings have an independent 1,024-byte cap
before float conversion; oversized spellings also reject the whole request
with 413, not partial success. The pre-parser process heap guard is 16 million words including shared
binaries; exhaustion can close the connection without an OTLP response. These
are per-request safeguards, not node-wide admission.

Retention-expired/future batches fail with 400; capacity, metadata/migration
and storage failures are retryable 503, and owner overload is 429. No success
precedes durable segment PUT and manifest CAS. Never use object-store lifecycle
rules to delete referenced objects; see [retention](retention.md).

## Upgrade and rollback

Upgrade **all readers and writers before** enabling these receivers against a
shared bucket. New log objects have an additive nullable typed-metadata column;
new readers accept legacy ten-column files. Old readers cannot expose the full
metadata. Do not roll back to an older reader after rich OTLP writes without a
separately validated compatible-reader or migration procedure.

Finish pending keyed OTLP retries before the upgrade: old receivers fingerprinted
only their reduced projections, so cross-version keyed deduplication is not
promised. Loki/legacy records without an OTLP envelope keep their fingerprints.
Use the non-overlapping upgrade procedure and coherent bucket backups described
in [deployment](deployment.md). Application startup rejects stale codec artifacts
that cannot preserve the new metadata. Rebuild with `PULSE_NIF_FORCE_BUILD=1`
or install the native artifacts matching the release.

Independent protobuf-compiler fixtures and native S3 protocol tests are not
production SDK, Collector capacity, provider fault/recovery or migration
acceptance. Validate your real collector pipeline and queries before cutover.
