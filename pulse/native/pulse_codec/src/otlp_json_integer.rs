//! Schema-scoped integer lexemes. Never round a protocol integer through f64.
use crate::json_read::{self, Builder, Context, Number, Res, Stacks};
use crate::otlp_traces::{field, Kind, Schema};
use crate::term_json::TermBuilder;
use rustler::{Binary, Encoder, Env, Term};
use std::borrow::Cow;

#[derive(Clone, Copy)]
enum Scope {
    Root,
    Message(Schema),
    Integer,
    Ordinary,
}
impl Context for Scope {
    fn key(self, key: &[u8]) -> Self {
        match self {
            Self::Root => match key {
                b"resourceLogs" => Self::Message(Schema::ResourceLogs),
                b"resourceMetrics" => Self::Message(Schema::ResourceMetrics),
                b"resourceSpans" => Self::Message(Schema::ResourceSpans),
                _ => Self::Ordinary,
            },
            Self::Message(schema) => {
                // Current public message schemas use field numbers <= 16.
                let kind = (1..=16)
                    .filter_map(|n| field(schema, n))
                    .find(|(name, _, _)| name.as_bytes() == key)
                    .map(|(_, kind, _)| kind);
                match kind {
                    Some(Kind::Message(child)) => Self::Message(child),
                    Some(
                        Kind::Int
                        | Kind::Uint
                        | Kind::Signed64
                        | Kind::Fixed64
                        | Kind::Fixed32
                        | Kind::PackedFixed64
                        | Kind::Sint32
                        | Kind::PackedUint64,
                    ) => Self::Integer,
                    _ => Self::Ordinary,
                }
            }
            _ => Self::Ordinary,
        }
    }
    fn field_bit(self, key: &[u8]) -> u64 {
        match self {
            Self::Root => match key {
                b"resourceLogs" => 1,
                b"resourceMetrics" => 2,
                b"resourceSpans" => 4,
                _ => 0,
            },
            // Nonempty entity references remain unsupported, but their field
            // is recognized for JSON duplicate validation even when empty/null.
            Self::Message(Schema::Resource) if key == b"entityRefs" => 1 << 3,
            Self::Message(schema) => (1..=16)
                .find(|&n| field(schema, n).is_some_and(|(name, _, _)| name.as_bytes() == key))
                .map_or(0, |n| 1 << n),
            _ => 0,
        }
    }
    fn integer(self) -> bool {
        matches!(self, Self::Integer)
    }
}

// Input grammar has already passed the JSON lexer. Digit positions exclude
// the decimal point; trim insignificant zeros before any bounded conversion.
fn integer(raw: &[u8]) -> Option<Number> {
    let negative = raw.first() == Some(&b'-');
    let unsigned = &raw[usize::from(negative)..];
    let end = unsigned
        .iter()
        .position(|b| matches!(b, b'e' | b'E'))
        .unwrap_or(unsigned.len());
    let mantissa = &unsigned[..end];
    let fraction = mantissa
        .iter()
        .position(|&b| b == b'.')
        .map_or(0, |dot| mantissa.len() - dot - 1);
    let mut digits = 0usize;
    let mut first = None;
    let mut last = 0;
    for &byte in mantissa {
        if byte == b'.' {
            continue;
        }
        if byte != b'0' {
            first.get_or_insert(digits);
            last = digits;
        }
        digits += 1;
    }
    let Some(first) = first else {
        return Some(Number::Int(0));
    };
    let width = last - first + 1;
    if width > 20 {
        return None;
    }
    let limit = (raw.len() as i64).saturating_add(21);
    let exponent = if end == unsigned.len() {
        0
    } else {
        let text = &unsigned[end + 1..];
        let minus = text.first() == Some(&b'-');
        let offset = usize::from(matches!(text.first(), Some(b'-' | b'+')));
        let value = text[offset..].iter().fold(0i64, |n, b| {
            n.saturating_mul(10)
                .saturating_add(i64::from(b - b'0'))
                .min(limit)
        });
        if minus {
            -value
        } else {
            value
        }
    };
    let shift = exponent - fraction as i64 + (digits - last - 1) as i64;
    if shift < 0 || width as i64 + shift > 20 {
        return None;
    }
    let mut magnitude = 0u64;
    for &byte in mantissa
        .iter()
        .filter(|&&b| b != b'.')
        .skip(first)
        .take(width)
    {
        magnitude = magnitude
            .checked_mul(10)?
            .checked_add(u64::from(byte - b'0'))?;
    }
    for _ in 0..shift {
        magnitude = magnitude.checked_mul(10)?;
    }
    if negative {
        if magnitude == i64::MAX as u64 + 1 {
            Some(Number::Int(i64::MIN))
        } else {
            Some(Number::Int(-i64::try_from(magnitude).ok()?))
        }
    } else if magnitude <= i64::MAX as u64 {
        Some(Number::Int(magnitude as i64))
    } else {
        Some(Number::UInt(magnitude))
    }
}

struct IntegerBuilder<'a, 'b> {
    base: TermBuilder<'a, 'b>,
    env: Env<'a>,
}
impl<'a, 'b> Builder<'a> for IntegerBuilder<'a, 'b> {
    type Value = Term<'a>;
    fn null(&mut self) -> Res<Self::Value> {
        self.base.null()
    }
    fn boolean(&mut self, value: bool) -> Res<Self::Value> {
        self.base.boolean(value)
    }
    fn number(&mut self, value: Number) -> Res<Self::Value> {
        self.base.number(value)
    }
    fn string(&mut self, value: Cow<'a, [u8]>) -> Res<Self::Value> {
        self.base.string(value)
    }
    fn key(&mut self, value: Cow<'a, [u8]>) -> Res<Self::Value> {
        self.base.key(value)
    }
    fn array(&mut self, items: &[Self::Value]) -> Res<Self::Value> {
        self.base.array(items)
    }
    fn object(&mut self, keys: &[Self::Value], values: &[Self::Value]) -> Res<Self::Value> {
        self.base.object(keys, values)
    }
    fn integer_literal(&mut self, raw: &'a [u8]) -> Res<Self::Value> {
        match integer(raw) {
            Some(value) => self.base.number(value),
            // JSON cannot forge this atom. Invalid protocol numbers keep their
            // scalar node/eight-byte admission cost and reject semantically.
            None => Ok(crate::atoms::invalid_otlp_integer().encode(self.env)),
        }
    }
}
pub(super) fn decode<'a>(
    env: Env<'a>,
    input: &Binary<'a>,
    schema: Option<Schema>,
) -> Res<Term<'a>> {
    let mut builder = IntegerBuilder {
        base: TermBuilder::new(env, input),
        env,
    };
    json_read::Parser::new(input.as_slice()).document_in(
        &mut builder,
        &mut Stacks::new(),
        schema.map_or(Scope::Root, Scope::Message),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_union_range_and_underflow() {
        for (raw, expected) in [
            ("9007199254740993.0", Number::Int(9007199254740993)),
            ("-9.223372036854775808e18", Number::Int(i64::MIN)),
            ("184467440737095516150e-1", Number::UInt(u64::MAX)),
            ("-0.0e-99999", Number::Int(0)),
            ("1e3", Number::Int(1000)),
        ] {
            assert_eq!(integer(raw.as_bytes()), Some(expected));
        }
        for raw in [
            "1e1000000",
            "1e-1000000",
            "0.0000000000001e-1000",
            "18446744073709551616",
            "-9223372036854775809",
            "1.0000000000000000001",
        ] {
            assert_eq!(integer(raw.as_bytes()), None);
        }
    }
    #[test]
    fn known_field_bits_are_disjoint_and_include_span_field_sixteen() {
        for schema in [
            Schema::Export,
            Schema::ExportLogs,
            Schema::ExportMetrics,
            Schema::ResourceLogs,
            Schema::ResourceMetrics,
            Schema::ResourceSpans,
            Schema::ScopeLogs,
            Schema::ScopeMetrics,
            Schema::ScopeSpans,
            Schema::Resource,
            Schema::Scope,
            Schema::Metric,
            Schema::Gauge,
            Schema::Sum,
            Schema::Histogram,
            Schema::ExponentialHistogram,
            Schema::Summary,
            Schema::NumberPoint,
            Schema::HistogramPoint,
            Schema::SummaryPoint,
            Schema::QuantileValue,
            Schema::Exemplar,
            Schema::LogRecord,
            Schema::Span,
            Schema::Status,
            Schema::Event,
            Schema::Link,
            Schema::Pair,
            Schema::Any,
            Schema::Array,
            Schema::KvList,
        ] {
            let scope = Scope::Message(schema);
            let mut seen = 0;
            for number in 1..=16 {
                if let Some((name, _, _)) = field(schema, number) {
                    let bit = scope.field_bit(name.as_bytes());
                    assert_eq!(bit, 1 << number);
                    assert_eq!(seen & bit, 0);
                    seen |= bit;
                }
            }
        }
        assert_eq!(
            Scope::Message(Schema::Resource).field_bit(b"entityRefs"),
            1 << 3
        );
    }
    #[test]
    fn foreign_signal_roots_and_unknown_objects_are_opaque() {
        let logs = Scope::Message(Schema::ExportLogs);
        assert_ne!(logs.field_bit(b"resourceLogs"), 0);
        assert_eq!(logs.field_bit(b"resourceMetrics"), 0);
        assert_eq!(logs.key(b"resourceMetrics").field_bit(b"scopeMetrics"), 0);
        assert_eq!(logs.key(b"future").field_bit(b"resourceLogs"), 0);
    }
    #[test]
    fn context_is_schema_scoped_and_arrays_inherit_their_element_role() {
        assert!(!Scope::Root.key(b"intValue").integer());
        assert!(Scope::Root
            .key(b"resourceLogs")
            .key(b"scopeLogs")
            .key(b"logRecords")
            .key(b"body")
            .key(b"intValue")
            .integer());
        assert!(!Scope::Root
            .key(b"unknown")
            .key(b"resourceLogs")
            .key(b"scopeLogs")
            .key(b"logRecords")
            .key(b"body")
            .key(b"intValue")
            .integer());
        assert!(!Scope::Message(Schema::HistogramPoint)
            .key(b"explicitBounds")
            .integer());
        assert!(Scope::Message(Schema::HistogramPoint)
            .key(b"bucketCounts")
            .integer());
    }
}
