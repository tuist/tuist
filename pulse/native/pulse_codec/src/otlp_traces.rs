//! OTLP trace protobuf -> JSON-shaped terms. Validate without allocations before
//! expanding repeated fields onto the Erlang heap. No generated-code dependency.
use rustler::{Binary, Encoder, Env, Term};
#[path = "otlp_merge.rs"]
mod merge;

#[derive(Clone, Copy, PartialEq)]
pub(crate) enum Schema {
    Export,
    ExportLogs,
    ExportMetrics,
    ResourceMetrics,
    ScopeMetrics,
    Metric,
    Gauge,
    Sum,
    Histogram,
    ExponentialHistogram,
    Summary,
    NumberPoint,
    HistogramPoint,
    ExponentialPoint,
    Buckets,
    SummaryPoint,
    QuantileValue,
    Exemplar,
    ResourceLogs,
    ScopeLogs,
    LogRecord,
    ResourceSpans,
    Resource,
    ScopeSpans,
    Scope,
    Span,
    Status,
    Event,
    Link,
    Pair,
    Any,
    Array,
    KvList,
}
#[derive(Clone, Copy)]
pub(crate) enum Kind {
    Message(Schema),
    String,
    Hex,
    Bytes,
    Uint,
    Int,
    Bool,
    Double,
    Fixed64,
    Fixed32,
    Signed64,
    // Zigzag varint (`sint32`), truncated to 32 bits as protobuf decoders do.
    Sint32,
    PackedFixed64,
    // Repeated varint `uint64`, packed or not.
    PackedUint64,
    PackedDouble,
}
use Kind::*;
use Schema::*;

pub(crate) fn field(s: Schema, n: u64) -> Option<(&'static str, Kind, bool)> {
    Some(match (s, n) {
        (ExportMetrics, 1) => ("resourceMetrics", Message(ResourceMetrics), true),
        (ResourceMetrics, 1) => ("resource", Message(Resource), false),
        (ResourceMetrics, 2) => ("scopeMetrics", Message(ScopeMetrics), true),
        (ResourceMetrics, 3) | (ScopeMetrics, 3) => ("schemaUrl", String, false),
        (ScopeMetrics, 1) => ("scope", Message(Scope), false),
        (ScopeMetrics, 2) => ("metrics", Message(Metric), true),
        (Metric, 1) => ("name", String, false),
        (Metric, 2) => ("description", String, false),
        (Metric, 3) => ("unit", String, false),
        (Metric, 5) => ("gauge", Message(Gauge), false),
        (Metric, 7) => ("sum", Message(Sum), false),
        (Metric, 9) => ("histogram", Message(Histogram), false),
        (Metric, 10) => ("exponentialHistogram", Message(ExponentialHistogram), false),
        (Metric, 11) => ("summary", Message(Summary), false),
        (Metric, 12) => ("metadata", Message(Pair), true),
        (Gauge, 1) | (Sum, 1) => ("dataPoints", Message(NumberPoint), true),
        (Histogram, 1) => ("dataPoints", Message(HistogramPoint), true),
        (ExponentialHistogram, 1) => ("dataPoints", Message(ExponentialPoint), true),
        (Summary, 1) => ("dataPoints", Message(SummaryPoint), true),
        (HistogramPoint, 9) | (ExponentialPoint, 1) | (SummaryPoint, 7) => {
            ("attributes", Message(Pair), true)
        }
        (HistogramPoint, 8) | (ExponentialPoint, 11) => ("exemplars", Message(Exemplar), true),
        (Sum, 2) | (Histogram, 2) | (ExponentialHistogram, 2) => {
            ("aggregationTemporality", Uint, false)
        }
        (Sum, 3) => ("isMonotonic", Bool, false),
        (HistogramPoint, 2) | (SummaryPoint, 2) => ("startTimeUnixNano", Fixed64, false),
        (HistogramPoint, 3) | (SummaryPoint, 3) => ("timeUnixNano", Fixed64, false),
        (HistogramPoint, 4) | (SummaryPoint, 4) => ("count", Fixed64, false),
        (HistogramPoint, 5) | (SummaryPoint, 5) => ("sum", Double, false),
        (HistogramPoint, 6) => ("bucketCounts", PackedFixed64, true),
        (HistogramPoint, 7) => ("explicitBounds", PackedDouble, true),
        (HistogramPoint, 10) | (SummaryPoint, 8) | (ExponentialPoint, 10) => ("flags", Uint, false),
        (ExponentialPoint, 2) => ("startTimeUnixNano", Fixed64, false),
        (ExponentialPoint, 3) => ("timeUnixNano", Fixed64, false),
        (ExponentialPoint, 4) => ("count", Fixed64, false),
        (ExponentialPoint, 5) => ("sum", Double, false),
        (ExponentialPoint, 6) => ("scale", Sint32, false),
        (ExponentialPoint, 7) => ("zeroCount", Fixed64, false),
        (ExponentialPoint, 8) => ("positive", Message(Buckets), false),
        (ExponentialPoint, 9) => ("negative", Message(Buckets), false),
        (ExponentialPoint, 12) => ("min", Double, false),
        (ExponentialPoint, 13) => ("max", Double, false),
        (ExponentialPoint, 14) => ("zeroThreshold", Double, false),
        (Buckets, 1) => ("offset", Sint32, false),
        (Buckets, 2) => ("bucketCounts", PackedUint64, true),
        (HistogramPoint, 11) => ("min", Double, false),
        (HistogramPoint, 12) => ("max", Double, false),
        (SummaryPoint, 6) => ("quantileValues", Message(QuantileValue), true),
        (QuantileValue, 1) => ("quantile", Double, false),
        (QuantileValue, 2) => ("value", Double, false),
        (NumberPoint, 2) => ("startTimeUnixNano", Fixed64, false),
        (NumberPoint, 3) | (Exemplar, 2) => ("timeUnixNano", Fixed64, false),
        (NumberPoint, 4) | (Exemplar, 3) => ("asDouble", Double, false),
        (NumberPoint, 6) | (Exemplar, 6) => ("asInt", Signed64, false),
        (NumberPoint, 7) => ("attributes", Message(Pair), true),
        (NumberPoint, 5) => ("exemplars", Message(Exemplar), true),
        (NumberPoint, 8) => ("flags", Uint, false),
        (Exemplar, 7) => ("filteredAttributes", Message(Pair), true),
        (Exemplar, 4) => ("spanId", Hex, false),
        (Exemplar, 5) => ("traceId", Hex, false),
        (ExportLogs, 1) => ("resourceLogs", Message(ResourceLogs), true),
        (ResourceLogs, 1) => ("resource", Message(Resource), false),
        (ResourceLogs, 2) => ("scopeLogs", Message(ScopeLogs), true),
        (ResourceLogs, 3) | (ScopeLogs, 3) => ("schemaUrl", String, false),
        (ScopeLogs, 1) => ("scope", Message(Scope), false),
        (ScopeLogs, 2) => ("logRecords", Message(LogRecord), true),
        (LogRecord, 1) => ("timeUnixNano", Fixed64, false),
        (LogRecord, 2) => ("severityNumber", Uint, false),
        (LogRecord, 3) => ("severityText", String, false),
        (LogRecord, 5) => ("body", Message(Any), false),
        (LogRecord, 6) => ("attributes", Message(Pair), true),
        (LogRecord, 7) => ("droppedAttributesCount", Uint, false),
        (LogRecord, 8) => ("flags", Fixed32, false),
        (LogRecord, 9) => ("traceId", Hex, false),
        (LogRecord, 10) => ("spanId", Hex, false),
        (LogRecord, 11) => ("observedTimeUnixNano", Fixed64, false),
        (LogRecord, 12) => ("eventName", String, false),
        (Export, 1) => ("resourceSpans", Message(ResourceSpans), true),
        (ResourceSpans, 1) => ("resource", Message(Resource), false),
        (ResourceSpans, 2) => ("scopeSpans", Message(ScopeSpans), true),
        (ResourceSpans, 3) | (ScopeSpans, 3) => ("schemaUrl", String, false),
        (Resource, 1) | (Scope, 3) | (Span, 9) | (Event, 3) | (Link, 4) => {
            ("attributes", Message(Pair), true)
        }
        (Resource, 2) | (Scope, 4) | (Span, 10) | (Event, 4) | (Link, 5) => {
            ("droppedAttributesCount", Uint, false)
        }
        (ScopeSpans, 1) => ("scope", Message(Scope), false),
        (ScopeSpans, 2) => ("spans", Message(Span), true),
        (Scope, 1) | (Span, 5) | (Event, 2) => ("name", String, false),
        (Scope, 2) => ("version", String, false),
        (Span, 1) | (Link, 1) => ("traceId", Hex, false),
        (Span, 2) | (Link, 2) => ("spanId", Hex, false),
        (Span, 3) | (Link, 3) => ("traceState", String, false),
        (Span, 4) => ("parentSpanId", Hex, false),
        (Span, 6) => ("kind", Uint, false),
        (Span, 7) => ("startTimeUnixNano", Fixed64, false),
        (Span, 8) => ("endTimeUnixNano", Fixed64, false),
        (Span, 11) => ("events", Message(Event), true),
        (Span, 12) => ("droppedEventsCount", Uint, false),
        (Span, 13) => ("links", Message(Link), true),
        (Span, 14) => ("droppedLinksCount", Uint, false),
        (Span, 15) => ("status", Message(Status), false),
        (Span, 16) | (Link, 6) => ("flags", Fixed32, false),
        (Status, 2) => ("message", String, false),
        (Status, 3) => ("code", Uint, false),
        (Event, 1) => ("timeUnixNano", Fixed64, false),
        (Pair, 1) => ("key", String, false),
        (Pair, 2) => ("value", Message(Any), false),
        (Any, 1) => ("stringValue", String, false),
        (Any, 2) => ("boolValue", Bool, false),
        (Any, 3) => ("intValue", Int, false),
        (Any, 4) => ("doubleValue", Double, false),
        (Any, 5) => ("arrayValue", Message(Array), false),
        (Any, 6) => ("kvlistValue", Message(KvList), false),
        (Any, 7) => ("bytesValue", Bytes, false),
        (Array, 1) => ("values", Message(Any), true),
        (KvList, 1) => ("values", Message(Pair), true),
        _ => return None,
    })
}

#[derive(Debug, PartialEq)]
pub enum Error {
    InvalidProtobuf,
    TooManyRecords,
    AttributesTooLarge,
    TooManyNodes,
}
type Res<T> = Result<T, Error>;
#[derive(Clone, Copy, rustler::NifTuple)]
pub struct Options(
    pub usize,
    pub usize,
    pub usize,
    pub usize,
    pub usize,
    pub usize,
    pub usize,
    pub usize,
);

struct Reader<'a> {
    bytes: &'a [u8],
    pos: usize,
}
enum Value<'a> {
    Number(u64),
    Data(&'a [u8]),
}
impl<'a> Reader<'a> {
    fn take(&mut self, len: usize) -> Res<&'a [u8]> {
        let end = self.pos.checked_add(len).ok_or(Error::InvalidProtobuf)?;
        let b = self
            .bytes
            .get(self.pos..end)
            .ok_or(Error::InvalidProtobuf)?;
        self.pos = end;
        Ok(b)
    }
    fn varint(&mut self) -> Res<u64> {
        let mut v = 0;
        for shift in (0..64).step_by(7) {
            let b = self.take(1)?[0];
            if shift == 63 && b > 1 {
                return Err(Error::InvalidProtobuf);
            }
            v |= u64::from(b & 127) << shift;
            if b < 128 {
                return Ok(v);
            }
        }
        Err(Error::InvalidProtobuf)
    }
    fn next(&mut self) -> Res<Option<(u64, u8, Value<'a>)>> {
        if self.pos == self.bytes.len() {
            return Ok(None);
        }
        let key = self.varint()?;
        if key >> 3 == 0 || key >> 3 > 0x1fff_ffff {
            return Err(Error::InvalidProtobuf);
        }
        let wire = (key & 7) as u8;
        let value = match wire {
            0 => Value::Number(self.varint()?),
            1 => Value::Number(u64::from_le_bytes(self.take(8)?.try_into().unwrap())),
            2 => {
                let len = usize::try_from(self.varint()?).map_err(|_| Error::InvalidProtobuf)?;
                Value::Data(self.take(len)?)
            }
            5 => Value::Number(u32::from_le_bytes(self.take(4)?.try_into().unwrap()) as u64),
            _ => return Err(Error::InvalidProtobuf),
        };
        Ok(Some((key >> 3, wire, value)))
    }
}
// Number of varints in a packed field; malformed or truncated input is invalid.
pub(crate) fn packed_varints(bytes: &[u8]) -> Res<usize> {
    let mut count = 0;
    let mut length = 0;
    for &byte in bytes {
        length += 1;
        if length > 10 {
            return Err(Error::InvalidProtobuf);
        }
        if byte & 0x80 == 0 {
            count += 1;
            length = 0;
        }
    }
    if length == 0 {
        Ok(count)
    } else {
        Err(Error::InvalidProtobuf)
    }
}
fn wire_type(kind: Kind) -> u8 {
    match kind {
        Message(_) | String | Hex | Bytes => 2,
        Fixed64 | Signed64 | Double | PackedFixed64 | PackedDouble => 1,
        Fixed32 => 5,
        _ => 0,
    }
}
// Bound total intermediate terms, not only each of 10,000 attribute sets.
struct Budget {
    options: Options,
    nodes: usize,
    spans: usize,
    groups: usize,
    events: usize,
    links: usize,
}
fn increment(v: &mut usize, max: usize, error: Error) -> Res<()> {
    *v += 1;
    if *v > max {
        Err(error)
    } else {
        Ok(())
    }
}
fn preflight(
    input: &[u8],
    schema: Schema,
    budget: &mut Budget,
    depth: usize,
    attr: &mut (usize, usize),
) -> Res<()> {
    if depth > budget.options.5.min(64) {
        return Err(Error::AttributesTooLarge);
    }
    increment(&mut budget.nodes, budget.options.7, Error::TooManyNodes)?;
    let mut reader = Reader {
        bytes: input,
        pos: 0,
    };
    let mut pairs = 0;
    let mut repeated_fields = 0u32;
    let attribute_context = matches!(schema, Pair | Any | Array | KvList);
    if attribute_context {
        increment(&mut attr.1, budget.options.6, Error::AttributesTooLarge)?;
    }
    while let Some((number, wire, value)) = reader.next()? {
        // Resource.entity_refs is a known, currently unsupported feature.
        // Never acknowledge protobuf metadata that the JSON path rejects.
        if schema == Resource && number == 3 {
            return Err(Error::InvalidProtobuf);
        }
        let Some((_, kind, repeated)) = field(schema, number) else {
            // Unknown fields are skipped semantically, not free scan work.
            // Opaque bytes remain independently body-size bounded.
            increment(&mut budget.nodes, budget.options.7, Error::TooManyNodes)?;
            continue;
        };
        // Raw limits include every fragment and losing oneof branch. The
        // native merge plan then checks cumulative logical owner budgets.
        let packed = matches!(kind, PackedFixed64 | PackedDouble | PackedUint64);
        if wire != wire_type(kind) && !(packed && wire == 2) {
            return Err(Error::InvalidProtobuf);
        }
        // One map per message, one list per repeated field, and one node per
        // scalar. Count supplied fields before oneof/last-wins collapse.
        if repeated && repeated_fields & (1 << number) == 0 {
            repeated_fields |= 1 << number;
            increment(&mut budget.nodes, budget.options.7, Error::TooManyNodes)?;
        }
        if packed && wire == 2 {
            let Value::Data(bytes) = value else {
                return Err(Error::InvalidProtobuf);
            };
            let values = if matches!(kind, PackedUint64) {
                packed_varints(bytes)?
            } else if bytes.len() % 8 == 0 {
                bytes.len() / 8
            } else {
                return Err(Error::InvalidProtobuf);
            };
            // Charge every packed occurrence as well as each expanded value.
            increment(&mut budget.nodes, budget.options.7, Error::TooManyNodes)?;
            budget.nodes = budget.nodes.saturating_add(values);
            if budget.nodes > budget.options.7 {
                return Err(Error::TooManyNodes);
            }
            continue;
        }
        if !matches!(kind, Message(_)) {
            increment(&mut budget.nodes, budget.options.7, Error::TooManyNodes)?;
        }
        match (kind, value) {
            (Message(child), Value::Data(b)) => {
                match child {
                    ResourceSpans | ScopeSpans | ResourceLogs | ScopeLogs | ResourceMetrics
                    | ScopeMetrics | Metric => increment(
                        &mut budget.groups,
                        budget.options.0
                            * if matches!(child, ResourceMetrics | ScopeMetrics | Metric) {
                                3
                            } else {
                                2
                            },
                        Error::TooManyRecords,
                    )?,
                    Span | LogRecord | NumberPoint | HistogramPoint | ExponentialPoint
                    | SummaryPoint => {
                        increment(&mut budget.spans, budget.options.0, Error::TooManyRecords)?
                    }
                    Event | Exemplar => {
                        increment(&mut budget.events, budget.options.0, Error::TooManyRecords)?
                    }
                    Link => increment(&mut budget.links, budget.options.0, Error::TooManyRecords)?,
                    Pair => increment(&mut pairs, budget.options.1, Error::AttributesTooLarge)?,
                    _ => (),
                }
                // Each top-level attribute set gets its own aggregate and node budget.
                if !attribute_context && child != Pair {
                    let saved = budget.options;
                    // Ordinary log bodies use the expanded-body byte ceiling,
                    // not the much smaller per-attribute string ceiling.
                    if schema == LogRecord && number == 5 {
                        budget.options.3 = 16 * 1024 * 1024;
                        budget.options.4 = 16 * 1024 * 1024;
                    }
                    let result = preflight(b, child, budget, 0, &mut (0, 0));
                    budget.options = saved;
                    result?;
                } else {
                    let next_depth = if matches!(schema, Pair | Array) {
                        depth + 1
                    } else {
                        depth
                    };
                    preflight(b, child, budget, next_depth, attr)?;
                }
            }
            (String | Hex | Bytes, Value::Data(b)) => {
                if matches!(kind, String) && std::str::from_utf8(b).is_err() {
                    return Err(Error::InvalidProtobuf);
                }
                if schema == Metric && matches!(kind, String) && b.len() > budget.options.3 {
                    return Err(Error::AttributesTooLarge);
                }
                if attribute_context {
                    let max = if schema == Pair && number == 1 {
                        budget.options.2
                    } else {
                        budget.options.3
                    };
                    // bytesValue materializes as base64, so budget its expanded length.
                    let size = if matches!(kind, Bytes) {
                        b.len().div_ceil(3) * 4
                    } else {
                        b.len()
                    };
                    if size > max {
                        return Err(Error::AttributesTooLarge);
                    }
                    attr.0 = attr.0.saturating_add(size);
                }
            }
            (Double, Value::Number(_)) => {
                if attribute_context {
                    attr.0 = attr.0.saturating_add(8);
                }
            }
            (_, Value::Number(_)) if attribute_context => {
                attr.0 = attr.0.saturating_add(8);
            }
            _ => (),
        }
        if attr.0 > budget.options.4 {
            return Err(Error::AttributesTooLarge);
        }
    }
    Ok(())
}

fn binary<'a>(env: Env<'a>, bytes: &[u8]) -> Term<'a> {
    let mut b = rustler::NewBinary::new(env, bytes.len());
    b.as_mut_slice().copy_from_slice(bytes);
    Binary::from(b).encode(env)
}
fn hex(bytes: &[u8]) -> Vec<u8> {
    let alphabet = b"0123456789abcdef";
    bytes
        .iter()
        .flat_map(|b| [alphabet[(b >> 4) as usize], alphabet[(b & 15) as usize]])
        .collect()
}
pub(crate) fn base64(bytes: &[u8]) -> Vec<u8> {
    let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = Vec::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let a = chunk[0];
        let b = *chunk.get(1).unwrap_or(&0);
        let c = *chunk.get(2).unwrap_or(&0);
        out.extend([
            alphabet[(a >> 2) as usize],
            alphabet[(((a & 3) << 4) | (b >> 4)) as usize],
            if chunk.len() > 1 {
                alphabet[(((b & 15) << 2) | (c >> 6)) as usize]
            } else {
                b'='
            },
            if chunk.len() > 2 {
                alphabet[(c & 63) as usize]
            } else {
                b'='
            },
        ]);
    }
    out
}
fn packed_number(env: Env<'_>, kind: Kind, n: u64) -> Term<'_> {
    if matches!(kind, PackedFixed64) {
        return n.encode(env);
    }
    let f = f64::from_bits(n);
    // BEAM preserves finite bits; nonfinite values retain the OTLP double class.
    if f.is_nan() {
        binary(env, b"NaN")
    } else if f == f64::INFINITY {
        binary(env, b"Infinity")
    } else if f == f64::NEG_INFINITY {
        binary(env, b"-Infinity")
    } else {
        f.encode(env)
    }
}

pub fn decode<'a>(env: Env<'a>, input: &[u8], options: Options) -> Res<Term<'a>> {
    decode_signal(env, input, options, Export)
}

pub fn decode_logs<'a>(env: Env<'a>, input: &[u8], options: Options) -> Res<Term<'a>> {
    decode_signal(env, input, options, ExportLogs)
}

pub fn decode_metrics<'a>(env: Env<'a>, input: &[u8], options: Options) -> Res<Term<'a>> {
    decode_signal(env, input, options, ExportMetrics)
}

fn decode_signal<'a>(
    env: Env<'a>,
    input: &[u8],
    options: Options,
    schema: Schema,
) -> Res<Term<'a>> {
    preflight(
        input,
        schema,
        &mut Budget {
            options,
            nodes: 0,
            spans: 0,
            groups: 0,
            events: 0,
            links: 0,
        },
        0,
        &mut (0, 0),
    )?;
    merge::decode(env, input, schema, options)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn independent_metrics_wire_preflight_counts_points_and_checks_sfixed64() {
        let fixture = include_bytes!("../../../test/fixtures/otlp/protoc-metrics.protobuf");
        let check = |input: &[u8], schema, max_records, max_nodes| {
            preflight(
                input,
                schema,
                &mut Budget {
                    options: Options(max_records, 128, 256, 16384, 65536, 16, 1024, max_nodes),
                    nodes: 0,
                    spans: 0,
                    groups: 0,
                    events: 0,
                    links: 0,
                },
                0,
                &mut (0, 0),
            )
        };
        assert_eq!(check(fixture, ExportMetrics, 7, 262144), Ok(()));
        assert_eq!(
            check(fixture, ExportMetrics, 6, 262144),
            Err(Error::TooManyRecords)
        );
        assert_eq!(
            check(fixture, ExportMetrics, 7, 10),
            Err(Error::TooManyNodes)
        );
        assert_eq!(
            check(&[0x30, 1], NumberPoint, 7, 262144),
            Err(Error::InvalidProtobuf)
        );
        assert_eq!(
            check(&[0x31, 0, 0, 0, 0, 0, 0, 0, 128], NumberPoint, 7, 262144),
            Ok(())
        );
    }

    #[test]
    fn packed_metric_arrays_are_preflighted_before_expansion() {
        let check = |bytes: &[u8], nodes| {
            preflight(
                bytes,
                HistogramPoint,
                &mut Budget {
                    options: Options(10, 128, 256, 16384, 65536, 16, 1024, nodes),
                    nodes: 0,
                    spans: 0,
                    groups: 0,
                    events: 0,
                    links: 0,
                },
                0,
                &mut (0, 0),
            )
        };
        let mut packed = vec![0x32, 16];
        packed.extend(u64::MAX.to_le_bytes());
        packed.extend(0u64.to_le_bytes());
        assert_eq!(check(&packed, 5), Ok(()));
        assert_eq!(check(&packed, 4), Err(Error::TooManyNodes));
        assert_eq!(check(&[0x32, 1, 0], 100), Err(Error::InvalidProtobuf));
        assert_eq!(check(&[0x30, 1], 100), Err(Error::InvalidProtobuf));
        assert_eq!(
            check(&[0x32, 0, 0x32, 0, 0x32, 0], 4),
            Err(Error::TooManyNodes)
        );
        let fixture = include_bytes!("../../../test/fixtures/otlp/distributions/input.protobuf");
        let mut budget = Budget {
            options: Options(7, 128, 256, 16384, 65536, 16, 1024, 262144),
            nodes: 0,
            spans: 0,
            groups: 0,
            events: 0,
            links: 0,
        };
        assert_eq!(
            preflight(fixture, ExportMetrics, &mut budget, 0, &mut (0, 0)),
            Ok(())
        );
        assert_eq!(budget.spans, 7);
    }

    #[test]
    fn rejects_bad_wire_and_bounds_without_allocating() {
        let o = Options(1, 2, 256, 16384, 65536, 16, 1024, 262144);
        let check = |b: &[u8]| {
            preflight(
                b,
                Export,
                &mut Budget {
                    options: o,
                    nodes: 0,
                    spans: 0,
                    groups: 0,
                    events: 0,
                    links: 0,
                },
                0,
                &mut (0, 0),
            )
        };
        assert_eq!(check(&[0]), Err(Error::InvalidProtobuf));
        assert_eq!(check(&[10, 255]), Err(Error::InvalidProtobuf));
        assert_eq!(
            check(&[10, 4, 18, 2, 18, 0, 10, 4, 18, 2, 18, 0]),
            Err(Error::TooManyRecords)
        );
        assert_eq!(hex(&[1, 255]), b"01ff");
        assert_eq!(base64(b"hello"), b"aGVsbG8=");
    }
}
