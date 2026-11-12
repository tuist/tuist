//! Deterministic, type-preserving metadata ordering shared with
//! Pulse.Record.SpanKey. Built from JSON without allocating any Erlang terms.
use crate::json_read::{Builder, Fallback, Number, Parser, Res};
use std::borrow::Cow;

pub fn key(json: &[u8]) -> Res<Vec<u8>> {
    Parser::new(json).document(&mut KeyBuilder)
}
/// Span keys omit explicit null metadata, matching the legacy reference map.
/// Projected comparison also omits rich metadata but never guesses its types.
pub fn span_key(json: &[u8], projected: bool) -> Res<Vec<u8>> {
    let fields = Parser::new(json).raw_object()?;
    let mut entries = fields
        .into_iter()
        .filter(|(key, value)| key.as_ref() != b"otlp" || (!projected && *value != b"null"))
        .collect::<Vec<_>>();
    entries.sort_by(|a, b| a.0.as_ref().cmp(b.0.as_ref()));
    if entries.windows(2).any(|pair| pair[0].0 == pair[1].0) {
        return Err(Fallback);
    }
    let mut out = vec![7];
    out.extend((entries.len() as u32).to_be_bytes());
    for (name, value) in entries {
        out.extend(sized(5, &name));
        out.extend(key(value)?);
    }
    Ok(out)
}

struct KeyBuilder;
fn sized(tag: u8, bytes: &[u8]) -> Vec<u8> {
    let mut out = vec![tag];
    out.extend((bytes.len() as u32).to_be_bytes());
    out.extend(bytes);
    out
}
fn integer(negative: bool, n: u64) -> Vec<u8> {
    let bytes = n.to_be_bytes();
    let start = bytes.iter().position(|v| *v != 0).unwrap_or(7);
    let mut out = vec![3, u8::from(negative)];
    out.extend(((8 - start) as u32).to_be_bytes());
    out.extend(&bytes[start..]);
    out
}
impl<'a> Builder<'a> for KeyBuilder {
    type Value = Vec<u8>;
    fn null(&mut self) -> Res<Vec<u8>> {
        Ok(vec![0])
    }
    fn boolean(&mut self, v: bool) -> Res<Vec<u8>> {
        Ok(vec![if v { 2 } else { 1 }])
    }
    fn number(&mut self, n: Number) -> Res<Vec<u8>> {
        Ok(match n {
            Number::Int(v) => integer(v < 0, v.unsigned_abs()),
            Number::UInt(v) => integer(false, v),
            Number::Float(v) => {
                let mut out = vec![4];
                out.extend(v.to_bits().to_be_bytes());
                out
            }
        })
    }
    fn string(&mut self, s: Cow<'a, [u8]>) -> Res<Vec<u8>> {
        Ok(sized(5, &s))
    }
    fn array(&mut self, items: &[Vec<u8>]) -> Res<Vec<u8>> {
        let mut out = vec![6];
        out.extend((items.len() as u32).to_be_bytes());
        for item in items {
            out.extend(item);
        }
        Ok(out)
    }
    fn object(&mut self, keys: &[Vec<u8>], values: &[Vec<u8>]) -> Res<Vec<u8>> {
        let mut entries: Vec<_> = keys.iter().zip(values).collect();
        entries.sort_by(|a, b| a.0[5..].cmp(&b.0[5..]));
        if entries.windows(2).any(|p| p[0].0 == p[1].0) {
            return Err(Fallback);
        }
        let mut out = vec![7];
        out.extend((entries.len() as u32).to_be_bytes());
        for (k, v) in entries {
            out.extend(k);
            out.extend(v);
        }
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn legacy_null_metadata_normalization_is_root_only() {
        assert_eq!(
            span_key(br#"{"a":1}"#, false),
            span_key(br#"{"a":1,"otlp":null}"#, false)
        );
        assert_ne!(
            span_key(br#"{"a":{"otlp":null}}"#, false),
            span_key(br#"{"a":{}}"#, false)
        );
        assert_eq!(
            span_key(br#"{"a":1,"otlp":{"version":1}}"#, true),
            key(br#"{"a":1}"#)
        );
    }

    #[test]
    fn types_and_key_order_are_preserved() {
        assert_eq!(
            key(br#"{"a":1,"b":[true,null]}"#),
            key(br#"{"b":[true,null],"a":1}"#)
        );
        assert_ne!(key(b"1"), key(b"1.0"));
        assert_ne!(key(b"\"1\""), key(b"1"));
        assert_ne!(key(b"-0.0"), key(b"0.0"));
        assert_ne!(key(b"-1"), key(b"18446744073709551615"));
    }
}
