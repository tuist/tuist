//! JSON scalar writers, matching Elixir's `JSON` encoder: `"`, `\` and
//! control characters are escaped (`\n`, `\t`, ... or `\u00XX`); `/`,
//! DEL and non-ASCII are written as-is. Callers guarantee valid UTF-8.

use crate::out::Sink;

const HEX: &[u8; 16] = b"0123456789ABCDEF";

#[inline]
fn escape(c: u8) -> Option<&'static [u8]> {
    match c {
        b'"' => Some(b"\\\""),
        b'\\' => Some(b"\\\\"),
        b'\n' => Some(b"\\n"),
        b'\r' => Some(b"\\r"),
        b'\t' => Some(b"\\t"),
        0x08 => Some(b"\\b"),
        0x0c => Some(b"\\f"),
        _ => None,
    }
}

pub fn write_str<S: Sink>(out: &mut S, s: &[u8]) {
    out.push(b'"');
    let mut start = 0;
    for (i, &c) in s.iter().enumerate() {
        if c >= 0x20 && c != b'"' && c != b'\\' {
            continue;
        }
        out.extend(&s[start..i]);
        match escape(c) {
            Some(e) => out.extend(e),
            None => out.extend(&[
                b'\\',
                b'u',
                b'0',
                b'0',
                HEX[(c >> 4) as usize],
                HEX[(c & 15) as usize],
            ]),
        }
        start = i + 1;
    }
    out.extend(&s[start..]);
    out.push(b'"');
}

pub fn write_i64<S: Sink>(out: &mut S, v: i64) {
    out.extend(itoa::Buffer::new().format(v).as_bytes());
}

pub fn write_u64<S: Sink>(out: &mut S, v: u64) {
    out.extend(itoa::Buffer::new().format(v).as_bytes());
}

/// Shortest round-trip representation. It can differ textually from
/// Elixir's (`1e20` vs `1.0e20`) but always decodes to the same float,
/// which is why float map keys are left to the Elixir encoder.
pub fn write_f64<S: Sink>(out: &mut S, v: f64) {
    out.extend(ryu::Buffer::new().format_finite(v).as_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(input: &[u8]) -> String {
        let mut out = Vec::new();
        write_str(&mut out, input);
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn escapes_like_elixir() {
        assert_eq!(s(b"plain"), r#""plain""#);
        assert_eq!(s(b"a\"b\\c/d"), r#""a\"b\\c/d""#);
        assert_eq!(s(b"\n\r\t\x08\x0c"), r#""\n\r\t\b\f""#);
        assert_eq!(s(b"\x00\x01\x1f\x7f"), "\"\\u0000\\u0001\\u001F\x7f\"");
        assert_eq!(s("é\u{2028}".as_bytes()), "\"é\u{2028}\"");
    }

    #[test]
    fn string_writer_matches_bytewise_oracle() {
        fn oracle(input: &[u8]) -> Vec<u8> {
            let mut out = vec![b'"'];
            for &byte in input {
                match byte {
                    b'"' => out.extend_from_slice(b"\\\""),
                    b'\\' => out.extend_from_slice(b"\\\\"),
                    b'\n' => out.extend_from_slice(b"\\n"),
                    b'\r' => out.extend_from_slice(b"\\r"),
                    b'\t' => out.extend_from_slice(b"\\t"),
                    0x08 => out.extend_from_slice(b"\\b"),
                    0x0c => out.extend_from_slice(b"\\f"),
                    b if b < 0x20 => out.extend_from_slice(format!("\\u{b:04X}").as_bytes()),
                    b => out.push(b),
                }
            }
            out.push(b'"');
            out
        }

        let mut state = 0xdead_beef_cafe_f00du64;
        for len in [0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 127, 1024]
            .into_iter()
            .chain((0..2000).map(|i| i % 128))
        {
            let input: Vec<u8> = (0..len)
                .map(|_| {
                    state = state
                        .wrapping_mul(6364136223846793005)
                        .wrapping_add(1442695040888963407);
                    (state >> 56) as u8
                })
                .collect();
            let mut out = Vec::new();
            write_str(&mut out, &input);
            assert_eq!(out, oracle(&input));
        }
    }

    #[test]
    fn numbers() {
        let mut out = Vec::new();
        write_i64(&mut out, -42);
        out.push(b' ');
        write_u64(&mut out, u64::MAX);
        out.push(b' ');
        write_f64(&mut out, 0.25);
        out.push(b' ');
        write_f64(&mut out, 1.0);
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "-42 18446744073709551615 0.25 1.0"
        );
    }
}
