# Backend protocol implementation references

These projects are useful implementation references, not Pulse's specification,
architecture template or acceptance oracle. Public protocol versions determine
scope; independent public producers/consumers establish semantics. No reference
server was built, queried or used to export telemetry in this review, and no code
was copied or dependency imported.

## GreptimeDB

- Product: <https://greptime.com/>
- Source snapshot: [`cca95b2637a797a9a0b8e6824718500d0fe692e7`](https://github.com/GreptimeTeam/greptimedb/tree/cca95b2637a797a9a0b8e6824718500d0fe692e7).
- Read: [OTLP metric translator](https://github.com/GreptimeTeam/greptimedb/blob/cca95b2637a797a9a0b8e6824718500d0fe692e7/src/servers/src/otlp/metrics/translator.rs).

The translator makes escaping and unit/type suffixes explicit strategy choices,
with unit and per-unit mappings and monotonic-sum handling. That is a useful
reference for Pulse's real remaining naming gap: version the policy and preserve
original descriptor/owner identity instead of treating every name rewrite as a
protocol-neutral sanitizer. Source inspection does not prove equivalent naming,
queries, storage behavior or capacity. The translator was not executed as an oracle.

## OpenObserve

- Source snapshot: [`210d1b5e9f9baa6380336606681eca52f74884a7`](https://github.com/openobserve/openobserve/tree/210d1b5e9f9baa6380336606681eca52f74884a7).
- Read: [OTLP metrics JSON compatibility](https://github.com/openobserve/openobserve/blob/210d1b5e9f9baa6380336606681eca52f74884a7/src/core/src/metrics/otlp_json_compat.rs).

Its documented generated-serde/flattened-oneof gaps illustrate why a JSON parser
pass is not enough: int64 strings, omitted defaults, exemplar oneofs and float
spellings can otherwise produce absent metric data or zeros. Pulse must test full
source envelopes and actual publication, not only successful deserialization.
Its compatibility treatment is not automatically OTLP's normative contract. This
is a source observation, not an independently reproduced defect/result in that
backend. Source was read only, not reused in Pulse.

## Normative distinction: OTLP JSON versus generic ProtoJSON

The pinned [OTLP v1.9.0 encoding specification](https://github.com/open-telemetry/opentelemetry-proto/blob/v1.9.0/docs/specification.md#json-protobuf-encoding)
requires integer enums and lowerCamelCase names, unlike generic ProtoJSON's named
enums/original protobuf-name aliases. It also requires ignoring unknown message
fields. Do not list named enums or snake_case aliases as missing mandatory OTLP
features or add them by blindly following another receiver's compatibility layer.
Any future lenient extension needs an explicit policy and separate evidence.

The actual Google protobuf v1.36.11 decoder with `DiscardUnknown: true` supplies
independent duplicate/unknown-field decisions in
[`test/fixtures/otlp/json_fields`](../test/fixtures/otlp/json_fields/README.md).
Authored cases use OTLP field names and numeric enums; generic aliases are not
silently promoted to OTLP acceptance requirements. This increment tightens duplicate
recognized fields, including null/escaped keys, while retaining receiver-specific
unknown-field handling. It does not close unsupported metric types, every null
case or general ProtoJSON conformance.

## Follow-up priorities

1. Broader exponential-histogram acceptance beyond the existing bounded classic
   projection. Boundary hardening now covers rounded/subnormal/overflow geometry,
   zero regions and conversion ceilings against public producer/iterator captures;
   native OTLP histogram rows, mixed-grid aggregation and deployed-client acceptance
   remain separate. No dropped negative buckets or metadata invention.
2. Explicit versioned metric naming/unit/resource policy. Prevent incompatible
   descriptors/typed owners from aliasing, retain canonical originals and document
   mixed-pool/retry compatibility. No mutable cross-request instrument registry.
3. Delta interval observations and query-time cumulative conversion, including
   reset/overlap/out-of-order/retry/multi-writer semantics. No node-local durable
   accumulator, sticky routing or alternate database authority.
4. Remaining scalar/null and full receiver/request conformance, broader query/
   exemplar/client coverage and separately authorized operational acceptance.

S3/CAS remains Pulse's only shared durable authority. These references do not
justify adopting a reference project's WAL, catalog/database, singleton topology,
UI, SQL surface or operational assumptions.
