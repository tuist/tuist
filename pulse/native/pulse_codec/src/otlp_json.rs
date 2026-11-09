//! OTLP-specific schema-scoped integer decoding and zero-mantissa preservation.
//! General JSON keeps Elixir's semantics; OTLP doubleValue retains IEEE sign.
//! Quoted strings are never rewritten. Malformed syntax is left to the parser.
use crate::out::{BinSink, Sink};
use rustler::{Binary, Env, Term};
#[path = "otlp_json_integer.rs"]
mod integer;

pub fn decode<'a>(env: Env<'a>, input: Binary<'a>) -> crate::json_read::Res<Term<'a>> {
    decode_scoped(env, input, None)
}

pub fn decode_scoped<'a>(
    env: Env<'a>,
    input: Binary<'a>,
    schema: Option<crate::otlp_traces::Schema>,
) -> crate::json_read::Res<Term<'a>> {
    let input = negative_zero(env, input);
    integer::decode(env, &input, schema)
}

fn zeroes(bytes: &[u8], mut visit: impl FnMut(usize)) {
    let mut quoted = false;
    let mut escaped = false;
    let mut cursor = 0;
    while cursor < bytes.len() {
        let byte = bytes[cursor];
        if quoted {
            if escaped {
                escaped = false;
            } else if byte == b'\\' {
                escaped = true;
            } else if byte == b'"' {
                quoted = false;
            }
        } else if byte == b'"' {
            quoted = true;
        } else if byte == b'-'
            && (cursor == 0
                || matches!(
                    bytes[cursor - 1],
                    b'[' | b',' | b':' | b' ' | b'\n' | b'\r' | b'\t'
                ))
            && bytes.get(cursor + 1) == Some(&b'0')
            && bytes.get(cursor + 2).is_none_or(|b| {
                matches!(
                    b,
                    b',' | b'}' | b']' | b' ' | b'\n' | b'\r' | b'\t' | b'e' | b'E'
                )
            })
        {
            visit(cursor + 2);
            cursor += 1;
        }
        cursor += 1;
    }
}
pub fn negative_zero<'a>(env: Env<'a>, input: Binary<'a>) -> Binary<'a> {
    let bytes = input.as_slice();
    let mut count = 0;
    zeroes(bytes, |_| count += 1);
    if count == 0 {
        return input;
    }
    // Each added suffix is two bytes; exact allocation avoids a growing copy.
    let mut out = BinSink::with_capacity(bytes.len() + count * 2);
    let mut start = 0;
    zeroes(bytes, |end| {
        out.extend(&bytes[start..end]);
        out.extend(b".0");
        start = end;
    });
    out.extend(&bytes[start..]);
    out.finish(env)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_unquoted_zero_mantissas_are_selected() {
        let bytes = br#"{"doubleValue":-0,"text":"escaped \" -0,","nested":[-0,-0.0,-0e2,1e-0,1E-0,1.5e-0,10,0]}"#;
        let mut positions = Vec::new();
        zeroes(bytes, |end| positions.push(end));
        assert_eq!(positions.len(), 3);
        for end in positions {
            assert_eq!(&bytes[end - 2..end], b"-0");
        }
    }
}
