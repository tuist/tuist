# OTLP wire compatibility

The `/v1/logs`, `/v1/metrics` and `/v1/traces` receivers accept OTLP/HTTP
JSON or protobuf, optionally gzip-compressed. This page covers shared wire
behavior; the [protocol matrix](protocol-coverage.md) and individual
[logs](logs.md), [metrics](metrics.md) and [traces](traces.md) contracts still
determine which signal types and semantics are supported. The opt-in
[OTLP/gRPC receiver](otlp-grpc.md) decodes gRPC messages with this same wire support.

## OTLP JSON field rules

JSON parsing is bound to the receiving signal. Known fields in the implemented
message schemas may appear **only once in each object**. Duplicate scalars,
messages, repeated-field containers and oneof members reject the entire request
with HTTP `400`, even when the values agree or one/both are `null`. Escaping a
field name (for example `int\u0056alue`) does not make it a different field.
There is no first-key/last-key selection and no accepted subset from an earlier
valid resource group. Reusing a field in separate objects is normal and allowed.

Genuinely unknown message fields remain ignored, including duplicate unknown
names and their opaque nested objects. A field belonging to a different signal's
export root is unknown on this receiver, not a reason to reject the request or
interpret its contents as another signal. Syntactically valid numeric tokens in
unknown fields are opaque even if their values overflow a BEAM float; they still
consume scalar node/eight-byte admission, not a discarded tree or cheaper string.
Known duplicates still reject if an
unrelated unknown field forced the native decoder to fall back. Ordinary JSON
outside the OTLP receivers retains its previous first-key behavior.

OTLP JSON is **not generic ProtoJSON**: senders must use lowerCamelCase field
names and integer enum values. Original snake_case protobuf field names and
named enum strings are not valid OTLP spellings. They are not compatibility
features that Pulse should add merely because generic ProtoJSON supports them.
See the pinned [OTLP encoding contract](https://github.com/open-telemetry/opentelemetry-proto/blob/v1.9.0/docs/specification.md#json-protobuf-encoding).

## Protobuf messages and oneofs

Singular message occurrences merge recursively, repeated fields append in wire
order, and singular scalar fields use their last supplied value, including an
explicit zero or empty string. For example, two Resource occurrences can supply
different attributes, and separate Status occurrences can supply its message
and code without either being lost.

Known protobuf oneofs select their last member. Repeating the same message
member merges its contents. Switching to a different member clears the previous
member; switching back does not resurrect old contents. This applies to AnyValue,
Metric data, scalar data-point values and exemplar values. JSON objects with
multiple populated oneof members remain invalid: object-map order is not a
protobuf wire-order contract.

Merging does **not** bypass admission:

- The native decoder validates wire types, UTF-8, depth, request nodes and source
  record counts before building a native merge plan or allocating decoded BEAM
  maps/lists. Known overwritten fields and discarded Metric data points still
  consume those source limits. Unknown wire occurrences consume request nodes;
  their opaque payloads also remain subject to the request body-size ceiling.
- Before expanding the merged plan onto the BEAM heap, cumulative attribute
  counts, bytes and nodes are checked for each logical owner across fragments.
  Replaced AnyValue contents do not refund supplied attribute bytes or nodes.
  Attribute-node accounting can therefore exceed the size of the final tree.
- Existing source-point, expanded-sample, full metadata, normalized segment and
  result ceilings are unchanged. Merging cannot make a wide distribution fit.
- Duplicate attribute keys remain invalid for logs and metrics, and inside
  trace kvlist values. Trace owner attribute lists keep the last occurrence of a
  repeated key instead (see [traces](traces.md#acknowledgments-and-limits)).
  Resource entity references and
  unsupported signal types are not made supported by message merging.

The merge plan adds transient native memory proportional to supplied known
fields/elements under the request-node ceiling. These limits are not a total
native/process memory allowance or node-wide admission. A BEAM deadline/heap
failure does not interrupt already-running dirty native work; measure concurrent
pressure before treating the bounds as capacity.

A merged request can fail `413` where the public encoder's canonicalized request
fits: canonicalization may remove source points or metadata that the original
request actually supplied. Safety failures append nothing, including when a
valid earlier resource group was already present in the request. Do not silently
canonicalize and resend a failed keyed request as a way around admission.

## Exact integer numbers

Known integral OTLP fields accept **unquoted** decimal/exponent JSON numbers
when they denote an exact, in-range integer, including times, int64 values,
uint64 counts/bucket arrays and numeric 32-bit fields. Integer fields using the
shared string decoder also accept exact quoted forms, including trace uint32
counts and fixed32 flags at resource, scope, span, event and link owners.
Trace counts/flags must be in `0..4294967295`. Trace enums remain numeric JSON
tokens (`kind` in `0..5`, status `code` in `0..2`): quoted digits such as
`"2"` and named enum strings are rejected. Examples:

| JSON spelling | Normalized integer |
| --- | --- |
| `9007199254740993.0` or `"9007199254740993.0"` | `9007199254740993` |
| `1.700000000123456789e18` | `1700000000123456789` |
| `184467440737095516150e-1` | `18446744073709551615`, for an unsigned count |
| `10e-1` | `1` |
| `1e-1` or `1e-1000` | Rejected: fractional, never rounded/underflowed to zero |

Raw number tokens are decoded in their message schema, not by matching a field
name anywhere in application data. Escaped JSON keys work too. Floating fields
and unknown objects retain their normal numeric handling; doubles preserve
negative zero including `-0e0` and `-0E+99`. Malformed JSON is not repaired.

No float rounding or exponent-sized integer/power is used for integral fields.
Signed/unsigned caller bounds still apply, source times remain exact nanoseconds,
and typed int64/count metadata stores canonical decimal integers. An invalid
fractional timestamp cannot become an unknown-time/receive-time fallback. Keyed
requests containing rejected points fail whole rather than publishing a subset.

Unquoted numbers remain **one scalar node and eight admission bytes**, including
invalid/out-of-range numeric values. They are not reclassified as cheaper short
strings. Existing body, attribute, record, node, metadata and result limits are
unchanged. Use the OTLP decoder for raw OTLP bodies; a caller that first rounds
numbers with a general JSON decoder cannot recover their original precision.

**Input tightening:** noncanonical quoted integer spellings such as `"01"`,
`"+1"`, `".0"`, `"1."` or surrounding whitespace now reject, matching the pinned
public ProtoJSON reference. Some were previously accepted as extensions. Correct
producers rather than rewriting retry keys or sending a keyed rejected subset.
Previously stored canonical values remain readable.

Trace counts and flags normalize to the same stored integers as numeric JSON
and protobuf. Admission examines the original supplied terms before normalization;
node, record, attribute and body ceilings are unchanged. Count/flag strings and
numeric scalars each consume one request node. Their byte lengths are bounded by
the request body limit, not the separate attribute-value byte limit. Invalid
resource/scope counts reject the request; invalid span/event/link counts or flags
reject the containing span. Keyed requests with any rejected span fail whole,
never publishing a valid subset.

This is **not full OTLP JSON conformance**. Remaining null/presence behavior
and Resource entity references remain separate
gaps. Numeric token parsing does not expand the accepted semantic enum vocabulary
or add an unsupported metric type. Repeated-field null elements and unsupported
message shapes are not made valid by duplicate detection.
OTLP context IDs use hex, not generic Google ProtoJSON's base64 byte spelling.

## Upgrade and rollback

Upgrade every serving ingress application/native pair before relying on these
forms. Matching artifacts must expose shared **OTLP wire capability 3**; startup
checks it separately from log metadata capability 1, metrics
`{2,2,1,1,1,1}` (including remote-write start retention and streaming reads) and traces `{2,1,3,7,12}`. A local check cannot fence an older running
pool. Old applications may reject merged requests or the newly accepted numeric
spellings, interpret an underflowed fractional timestamp as unknown/zero time,
or silently choose the first duplicate JSON field. Duplicate rejection is input
tightening: fix the producer instead of rewriting keys or sending a failed
keyed subset. Rolling back ingress can reopen the previous first-key behavior.

Quoted trace counts/flags require the updated ingress application on every
serving instance before producers use them. Existing capability-3 native artifacts
already preserve these strings; this acceptance change does not bump the native
ABI. Older ingress applications reject the containing span (or the whole request
for resource/scope counts). Unkeyed requests can therefore report partial success
in a mixed pool; keyed requests fail whole. Rollback narrows input acceptance but
can still read the canonical integers already stored.

There is no Parquet schema, metadata-envelope or scalar keyed-byte format change
in this wire increment. Earlier rich-metadata reader/writer/compactor upgrade
requirements still apply. An application rollback also rolls back accepted wire
forms; keep compatible ingress or change producers before relying on rollback.

## Evidence and limits

Frozen fixtures use OTLP public schemas **v1.9.0** and the actual Google protobuf
**v1.36.11** decoder, canonical protobuf encoder and ProtoJSON serializer. They
cover all three signals, split resource/scope metadata, status merging, nested
AnyValue merges, oneof switches, scalar/exemplar selection, exact integers and
signed zero. The [wire fixtures](../test/fixtures/otlp/wire/README.md) retain 60
signed/unsigned string cases. Separate [numeric fixtures](../test/fixtures/otlp/numbers/README.md)
add 156 actual public numeric-token decisions, 11 float-bit cases and complete
raw-number/canonical-JSON/protobuf requests for all three signals. Native decoding
is also compared to an independent Elixir token-preserving reference, including
randomized exact integers and fallback cases. Separate [field fixtures](../test/fixtures/otlp/json_fields/README.md)
add 704 actual public duplicate/unknown-field decisions across 35 message/field
contexts, enumerating all fields of those owners with public descriptors. Receiver
scope, unknown-root handling, gzip rejection and cross-instance S3 replay are also
exercised. Dedicated [quoted trace integer fixtures](../test/fixtures/otlp/trace_integers/README.md)
add 451 actual public decisions across all 11 trace uint32/fixed32/enum fields,
plus complete quoted JSON/canonical JSON/protobuf keyed replay. Generic ProtoJSON
accepts named enums, unlike OTLP; quoted numeric enum strings reject in both.
The separate [trace uint32 fixtures](../test/fixtures/otlp/trace_uint32/README.md)
add 306 public quoted-integer decisions across all nine trace count/flag fields,
plus canonical JSON/protobuf, native Parquet and cross-instance gzip keyed replay.
Unsupported signal/message semantics remain unsupported.

Ordinary replay uses only the native project toolchain. Optional Go reproduction
is file-only preparation, not a runtime dependency or network exporter. Public
wire evidence, native Parquet round-trips and owned local object-store HTTP tests
do not establish full protocol, SDK/default-policy, actual-provider, capacity,
crash-recovery or deployment acceptance.
