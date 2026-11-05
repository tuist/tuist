//! Prometheus native histograms: the remote-write wire message, the compact
//! byte form stored in metric segments, and `%Pulse.Record.NativeHistogram{}`.
//!
//! Remote Write 1.0 (`prometheus.Histogram`) and 2.0
//! (`io.prometheus.write.v2.Histogram`) share field numbers:
//!
//! ```proto
//! oneof count { uint64 count_int = 1; double count_float = 2; }
//! double sum = 3;
//! sint32 schema = 4;
//! double zero_threshold = 5;
//! oneof zero_count { uint64 zero_count_int = 6; double zero_count_float = 7; }
//! repeated BucketSpan negative_spans = 8;   // { sint32 offset = 1; uint32 length = 2; }
//! repeated sint64 negative_deltas = 9;      // integer histograms: deltas
//! repeated double negative_counts = 10;     // float histograms: absolute
//! repeated BucketSpan positive_spans = 11;
//! repeated sint64 positive_deltas = 12;
//! repeated double positive_counts = 13;
//! ResetHint reset_hint = 14;
//! int64 timestamp = 15;
//! repeated double custom_values = 16;
//! ```
//!
//! Integer histograms become float ones with absolute bucket counts, which is
//! what PromQL computes with. Validation follows Prometheus: spans must cover
//! exactly the given buckets, the schema must be exponential (`-4..=8`) or
//! custom (`-53`, with strictly increasing finite bounds), and integer
//! histograms may not have negative buckets or fewer observations than their
//! buckets hold.

use crate::wire::{Reader, Value};
use rustler::{Encoder, Env, Term};

pub const CUSTOM_BUCKETS_SCHEMA: i32 = -53;

#[derive(Debug, Clone, PartialEq)]
pub struct Histogram {
    pub schema: i32,
    pub zero_threshold: f64,
    pub zero_count: f64,
    pub count: f64,
    pub sum: f64,
    pub positive_spans: Vec<(i32, u32)>,
    pub positive: Vec<f64>,
    pub negative_spans: Vec<(i32, u32)>,
    pub negative: Vec<f64>,
    /// 0 unknown, 1 yes, 2 no, 3 gauge (the wire enum).
    pub reset_hint: u8,
    pub custom_values: Vec<f64>,
}

mod atoms {
    rustler::atoms! {
        struct_key = "__struct__",
        native_histogram = "Elixir.Pulse.Record.NativeHistogram",
        schema,
        zero_threshold,
        zero_count,
        count,
        sum,
        positive_spans,
        positive_buckets,
        negative_spans,
        negative_buckets,
        counter_reset_hint,
        custom_values,
        unknown,
        yes,
        no,
        gauge,
    }
}

// -- Wire ------------------------------------------------------------------

fn zigzag(v: u64) -> i64 {
    ((v >> 1) as i64) ^ -((v & 1) as i64)
}

fn double(value: &Value) -> Option<f64> {
    match value {
        Value::Fixed64(bytes) => Some(f64::from_le_bytes(*bytes)),
        _ => None,
    }
}

fn varint_field(value: &Value) -> Option<u64> {
    match value {
        Value::Varint(v) => Some(*v),
        _ => None,
    }
}

// Repeated doubles arrive packed or as one fixed64 field per element.
fn doubles(value: &Value, out: &mut Vec<f64>) -> Option<()> {
    match value {
        Value::Bytes(bytes) if bytes.len() % 8 == 0 => {
            out.extend(
                bytes
                    .as_chunks::<8>()
                    .0
                    .iter()
                    .map(|c| f64::from_le_bytes(*c)),
            );
            Some(())
        }
        Value::Fixed64(bytes) => {
            out.push(f64::from_le_bytes(*bytes));
            Some(())
        }
        _ => None,
    }
}

// Repeated sint64 arrive packed or as one varint per element.
fn sint64s(value: &Value, out: &mut Vec<i64>) -> Option<()> {
    match value {
        Value::Bytes(bytes) => {
            let mut reader = Reader::new(bytes);
            while !reader.is_empty() {
                out.push(zigzag(reader.read_varint()?));
            }
            Some(())
        }
        Value::Varint(v) => {
            out.push(zigzag(*v));
            Some(())
        }
        _ => None,
    }
}

fn span(bytes: &[u8]) -> Option<(i32, u32)> {
    let (mut offset, mut length) = (0i32, 0u32);
    let mut reader = Reader::new(bytes);
    while let Some((number, value)) = reader.next_field()? {
        match (number, value) {
            (1, Value::Varint(v)) => offset = i32::try_from(zigzag(v)).ok()?,
            (2, Value::Varint(v)) => length = u32::try_from(v).ok()?,
            _ => {}
        }
    }
    Some((offset, length))
}

/// Decode one wire `Histogram` into the float form and its millisecond
/// timestamp. `None` when the message is malformed or fails validation.
pub fn decode_wire(bytes: &[u8]) -> Option<(Histogram, i64)> {
    let mut h = Histogram {
        schema: 0,
        zero_threshold: 0.0,
        zero_count: 0.0,
        count: 0.0,
        sum: 0.0,
        positive_spans: Vec::new(),
        positive: Vec::new(),
        negative_spans: Vec::new(),
        negative: Vec::new(),
        reset_hint: 0,
        custom_values: Vec::new(),
    };
    let mut timestamp = 0i64;
    let mut integer = None::<bool>;
    let (mut positive_deltas, mut negative_deltas) = (Vec::new(), Vec::new());
    let mut reader = Reader::new(bytes);
    while let Some((number, value)) = reader.next_field()? {
        match number {
            1 => {
                h.count = varint_field(&value)? as f64;
                integer = Some(true);
            }
            2 => {
                h.count = double(&value)?;
                integer = Some(false);
            }
            3 => h.sum = double(&value)?,
            4 => h.schema = i32::try_from(zigzag(varint_field(&value)?)).ok()?,
            5 => h.zero_threshold = double(&value)?,
            6 => h.zero_count = varint_field(&value)? as f64,
            7 => h.zero_count = double(&value)?,
            8 => match value {
                Value::Bytes(b) => h.negative_spans.push(span(b)?),
                _ => return None,
            },
            11 => match value {
                Value::Bytes(b) => h.positive_spans.push(span(b)?),
                _ => return None,
            },
            9 => sint64s(&value, &mut negative_deltas)?,
            12 => sint64s(&value, &mut positive_deltas)?,
            10 => doubles(&value, &mut h.negative)?,
            13 => doubles(&value, &mut h.positive)?,
            14 => {
                h.reset_hint = u8::try_from(varint_field(&value)?)
                    .ok()
                    .filter(|v| *v <= 3)?
            }
            15 => timestamp = varint_field(&value)? as i64,
            16 => doubles(&value, &mut h.custom_values)?,
            _ => {}
        }
    }
    let integer = integer.unwrap_or(h.positive.is_empty() && h.negative.is_empty());
    if integer {
        if !h.positive.is_empty() || !h.negative.is_empty() {
            return None;
        }
        h.positive = absolute(&positive_deltas)?;
        h.negative = absolute(&negative_deltas)?;
        let held = h.zero_count + h.positive.iter().sum::<f64>() + h.negative.iter().sum::<f64>();
        if h.positive.iter().chain(&h.negative).any(|c| *c < 0.0) || held > h.count {
            return None;
        }
    } else if !positive_deltas.is_empty() || !negative_deltas.is_empty() {
        return None;
    }
    validate(&h).then_some((h, timestamp))
}

// Integer bucket counts arrive as deltas from the previous bucket.
fn absolute(deltas: &[i64]) -> Option<Vec<f64>> {
    let mut current = 0i64;
    deltas
        .iter()
        .map(|delta| {
            current = current.checked_add(*delta)?;
            Some(current as f64)
        })
        .collect()
}

fn covered(spans: &[(i32, u32)]) -> u64 {
    spans.iter().map(|(_, length)| u64::from(*length)).sum()
}

pub fn validate(h: &Histogram) -> bool {
    let custom = h.schema == CUSTOM_BUCKETS_SCHEMA;
    let schema_ok = custom || (-4..=8).contains(&h.schema);
    let custom_ok = if custom {
        h.negative.is_empty()
            && h.negative_spans.is_empty()
            && h.custom_values.iter().all(|v| v.is_finite())
            && h.custom_values.windows(2).all(|w| w[0] < w[1])
            && h.positive_spans
                .first()
                .is_none_or(|(offset, _)| *offset >= 0)
    } else {
        h.custom_values.is_empty()
    };
    schema_ok
        && custom_ok
        && covered(&h.positive_spans) == h.positive.len() as u64
        && covered(&h.negative_spans) == h.negative.len() as u64
        && h.positive_spans
            .iter()
            .skip(1)
            .all(|(offset, _)| *offset >= 0)
        && h.negative_spans
            .iter()
            .skip(1)
            .all(|(offset, _)| *offset >= 0)
        && h.zero_threshold >= 0.0
}

// -- Stored bytes ----------------------------------------------------------

const VERSION: u8 = 1;

fn varint(buf: &[u8], pos: &mut usize) -> Option<u64> {
    let mut out: u64 = 0;
    for shift in (0..64).step_by(7) {
        let byte = *buf.get(*pos)?;
        *pos += 1;
        out |= u64::from(byte & 0x7f) << shift;
        if byte & 0x80 == 0 {
            return Some(out);
        }
    }
    None
}

fn put_varint(out: &mut Vec<u8>, mut v: u64) {
    while v >= 0x80 {
        out.push((v as u8) | 0x80);
        v >>= 7;
    }
    out.push(v as u8);
}

fn put_zigzag(out: &mut Vec<u8>, v: i64) {
    put_varint(out, ((v << 1) ^ (v >> 63)) as u64);
}

fn put_floats(out: &mut Vec<u8>, values: &[f64]) {
    put_varint(out, values.len() as u64);
    for v in values {
        out.extend_from_slice(&v.to_le_bytes());
    }
}

fn put_spans(out: &mut Vec<u8>, spans: &[(i32, u32)]) {
    put_varint(out, spans.len() as u64);
    for (offset, length) in spans {
        put_zigzag(out, i64::from(*offset));
        put_varint(out, u64::from(*length));
    }
}

impl Histogram {
    /// The stored form: a version byte, then schema, scalars, reset hint,
    /// spans and buckets of each sign, and custom bounds.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(64 + 8 * (self.positive.len() + self.negative.len()));
        out.push(VERSION);
        put_zigzag(&mut out, i64::from(self.schema));
        for v in [self.zero_threshold, self.zero_count, self.count, self.sum] {
            out.extend_from_slice(&v.to_le_bytes());
        }
        out.push(self.reset_hint);
        put_spans(&mut out, &self.positive_spans);
        put_floats(&mut out, &self.positive);
        put_spans(&mut out, &self.negative_spans);
        put_floats(&mut out, &self.negative);
        put_floats(&mut out, &self.custom_values);
        out
    }

    pub fn from_bytes(bytes: &[u8]) -> Option<Histogram> {
        let mut pos = 0;
        if *bytes.first()? != VERSION {
            return None;
        }
        pos += 1;
        let float = |pos: &mut usize| -> Option<f64> {
            let v = f64::from_le_bytes(bytes.get(*pos..*pos + 8)?.try_into().ok()?);
            *pos += 8;
            Some(v)
        };
        let floats = |pos: &mut usize| -> Option<Vec<f64>> {
            let n = usize::try_from(varint(bytes, pos)?).ok()?;
            if n > bytes.len() {
                return None;
            }
            (0..n).map(|_| float(pos)).collect()
        };
        let spans = |pos: &mut usize| -> Option<Vec<(i32, u32)>> {
            let n = usize::try_from(varint(bytes, pos)?).ok()?;
            if n > bytes.len() {
                return None;
            }
            (0..n)
                .map(|_| {
                    let offset = i32::try_from(zigzag(varint(bytes, pos)?)).ok()?;
                    let length = u32::try_from(varint(bytes, pos)?).ok()?;
                    Some((offset, length))
                })
                .collect()
        };
        let schema = i32::try_from(zigzag(varint(bytes, &mut pos)?)).ok()?;
        let (zero_threshold, zero_count, count, sum) = (
            float(&mut pos)?,
            float(&mut pos)?,
            float(&mut pos)?,
            float(&mut pos)?,
        );
        let reset_hint = *bytes.get(pos)?;
        pos += 1;
        let h = Histogram {
            schema,
            zero_threshold,
            zero_count,
            count,
            sum,
            positive_spans: spans(&mut pos)?,
            positive: floats(&mut pos)?,
            negative_spans: spans(&mut pos)?,
            negative: floats(&mut pos)?,
            reset_hint,
            custom_values: floats(&mut pos)?,
        };
        (pos == bytes.len() && reset_hint <= 3 && validate(&h)).then_some(h)
    }

    // -- Terms -------------------------------------------------------------

    pub fn to_term<'a>(&self, env: Env<'a>) -> Term<'a> {
        let number = |v: f64| crate::metric_value::encode(env, canonical(v));
        let floats = |values: &[f64]| values.iter().map(|v| number(*v)).collect::<Vec<_>>();
        let hint = match self.reset_hint {
            1 => atoms::yes(),
            2 => atoms::no(),
            3 => atoms::gauge(),
            _ => atoms::unknown(),
        };
        let keys = [
            atoms::struct_key().encode(env),
            atoms::schema().encode(env),
            atoms::zero_threshold().encode(env),
            atoms::zero_count().encode(env),
            atoms::count().encode(env),
            atoms::sum().encode(env),
            atoms::positive_spans().encode(env),
            atoms::positive_buckets().encode(env),
            atoms::negative_spans().encode(env),
            atoms::negative_buckets().encode(env),
            atoms::counter_reset_hint().encode(env),
            atoms::custom_values().encode(env),
        ];
        let values = [
            atoms::native_histogram().encode(env),
            self.schema.encode(env),
            number(self.zero_threshold),
            number(self.zero_count),
            number(self.count),
            // Prometheus reserves the Sum StaleNaN as the series terminator.
            crate::metric_value::encode(env, self.sum),
            self.positive_spans.encode(env),
            floats(&self.positive).encode(env),
            self.negative_spans.encode(env),
            floats(&self.negative).encode(env),
            hint.encode(env),
            floats(&self.custom_values).encode(env),
        ];
        Term::map_from_arrays(env, &keys, &values).expect("distinct keys")
    }

    pub fn from_term(term: Term<'_>) -> Option<Histogram> {
        let env = term.get_env();
        if term.map_get(atoms::struct_key().encode(env)).ok()?
            != atoms::native_histogram().encode(env)
        {
            return None;
        }
        let get = |key: rustler::Atom| term.map_get(key.encode(env)).ok();
        let number =
            |key: rustler::Atom| crate::metric_value::decode(get(key)?).ok().map(canonical);
        let floats = |key: rustler::Atom| -> Option<Vec<f64>> {
            get(key)?
                .decode::<Vec<Term>>()
                .ok()?
                .into_iter()
                .map(|v| crate::metric_value::decode(v).ok().map(canonical))
                .collect()
        };
        let spans = |key: rustler::Atom| get(key)?.decode::<Vec<(i32, u32)>>().ok();
        let hint = get(atoms::counter_reset_hint())?;
        let reset_hint = [atoms::unknown(), atoms::yes(), atoms::no(), atoms::gauge()]
            .iter()
            .position(|a| hint == a.encode(env))? as u8;
        let h = Histogram {
            schema: get(atoms::schema())?.decode().ok()?,
            zero_threshold: number(atoms::zero_threshold())?,
            zero_count: number(atoms::zero_count())?,
            count: number(atoms::count())?,
            sum: crate::metric_value::decode(get(atoms::sum())?).ok()?,
            positive_spans: spans(atoms::positive_spans())?,
            positive: floats(atoms::positive_buckets())?,
            negative_spans: spans(atoms::negative_spans())?,
            negative: floats(atoms::negative_buckets())?,
            reset_hint,
            custom_values: floats(atoms::custom_values())?,
        };
        validate(&h).then_some(h)
    }
}

// Only Sum may carry Prometheus' staleness marker. Other NaNs are ordinary.
fn canonical(v: f64) -> f64 {
    if v.is_nan() {
        f64::NAN
    } else {
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn put_key(out: &mut Vec<u8>, field: u64, wire: u64) {
        put_varint(out, (field << 3) | wire);
    }

    fn put_bytes(out: &mut Vec<u8>, field: u64, bytes: &[u8]) {
        put_key(out, field, 2);
        put_varint(out, bytes.len() as u64);
        out.extend_from_slice(bytes);
    }

    fn put_double(out: &mut Vec<u8>, field: u64, v: f64) {
        put_key(out, field, 1);
        out.extend_from_slice(&v.to_le_bytes());
    }

    fn wire_span(offset: i64, length: u64) -> Vec<u8> {
        let mut out = Vec::new();
        put_key(&mut out, 1, 0);
        put_zigzag(&mut out, offset);
        put_key(&mut out, 2, 0);
        put_varint(&mut out, length);
        out
    }

    // Prometheus' integer histogram example: count 12, buckets 1, 2, 1, 1 at
    // indexes 0..2 and 4, sent as deltas 1, 1, -1, 0.
    fn integer_wire(count: u64) -> Vec<u8> {
        let mut out = Vec::new();
        put_key(&mut out, 1, 0);
        put_varint(&mut out, count);
        put_double(&mut out, 3, 18.4);
        put_key(&mut out, 4, 0);
        put_zigzag(&mut out, 1);
        put_double(&mut out, 5, 0.001);
        put_key(&mut out, 6, 0);
        put_varint(&mut out, 2);
        put_bytes(&mut out, 11, &wire_span(0, 3));
        put_bytes(&mut out, 11, &wire_span(1, 1));
        let mut deltas = Vec::new();
        for d in [1i64, 1, -1, 0] {
            put_zigzag(&mut deltas, d);
        }
        put_bytes(&mut out, 12, &deltas);
        put_key(&mut out, 14, 0);
        put_varint(&mut out, 2);
        put_key(&mut out, 15, 0);
        put_varint(&mut out, 1_700_000_000_000);
        out
    }

    #[test]
    fn integer_histograms_become_absolute_float_buckets() {
        let (h, ts) = decode_wire(&integer_wire(12)).unwrap();
        assert_eq!(ts, 1_700_000_000_000);
        assert_eq!(h.schema, 1);
        assert_eq!((h.count, h.sum, h.zero_count), (12.0, 18.4, 2.0));
        assert_eq!(h.positive_spans, vec![(0, 3), (1, 1)]);
        assert_eq!(h.positive, vec![1.0, 2.0, 1.0, 1.0]);
        assert_eq!(h.reset_hint, 2);
        assert_eq!(Histogram::from_bytes(&h.to_bytes()), Some(h));
    }

    #[test]
    fn float_histograms_keep_absolute_counts_packed_or_not() {
        let mut out = Vec::new();
        put_double(&mut out, 2, 3.5);
        put_key(&mut out, 4, 0);
        put_zigzag(&mut out, CUSTOM_BUCKETS_SCHEMA as i64);
        put_bytes(&mut out, 11, &wire_span(0, 2));
        put_double(&mut out, 13, 1.5);
        put_double(&mut out, 13, 2.0);
        let packed: Vec<u8> = [0.5f64, 1.0].iter().flat_map(|v| v.to_le_bytes()).collect();
        put_bytes(&mut out, 16, &packed);
        let (h, _) = decode_wire(&out).unwrap();
        assert_eq!(h.positive, vec![1.5, 2.0]);
        assert_eq!(h.custom_values, vec![0.5, 1.0]);
        assert_eq!(Histogram::from_bytes(&h.to_bytes()), Some(h));
    }

    #[test]
    fn stale_sum_payload_survives_wire_and_repeated_storage_round_trips() {
        let stale = f64::from_bits(crate::metric_value::STALE_BITS);
        let mut wire = Vec::new();
        put_double(&mut wire, 3, stale);
        let (mut h, _) = decode_wire(&wire).unwrap();
        for _ in 0..3 {
            assert_eq!(h.sum.to_bits(), crate::metric_value::STALE_BITS);
            h = Histogram::from_bytes(&h.to_bytes()).unwrap();
        }
    }

    #[test]
    fn invalid_histograms_are_rejected() {
        // Fewer observations than the buckets hold.
        assert!(decode_wire(&integer_wire(4)).is_none());
        let mut bad_schema = integer_wire(12);
        bad_schema.extend([0x20, 0x13]); // schema = -10 (zigzag 19)
        assert!(decode_wire(&bad_schema).is_none());
        // Spans covering more buckets than were sent.
        let mut short = Vec::new();
        put_double(&mut short, 2, 1.0);
        put_bytes(&mut short, 11, &wire_span(0, 2));
        put_double(&mut short, 13, 1.0);
        assert!(decode_wire(&short).is_none());
        // Truncated stored bytes.
        let (h, _) = decode_wire(&integer_wire(12)).unwrap();
        let bytes = h.to_bytes();
        assert!(Histogram::from_bytes(&bytes[..bytes.len() - 1]).is_none());
    }
}
