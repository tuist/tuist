//! Parser for the Prometheus-style `{name="value",...}` label string that
//! Loki carries in `Stream.labels`.
//!
//! Values are Go-quoted (`strconv.Quote`), so every Go escape form may
//! appear. An unknown or truncated escape is an error rather than a
//! silent byte drop: labels are the stream's identity. Values with no
//! escapes borrow from the input so the NIF can emit them as sub-binaries.

use std::borrow::Cow;

pub type Labels<'a> = Vec<(&'a str, Cow<'a, [u8]>)>;

pub fn parse(s: &[u8]) -> Option<Labels<'_>> {
    parse_inner(s, usize::MAX, &mut false)
}

/// Distinguish a pair-budget failure from malformed label syntax. Checking
/// before parsing the next pair also bounds the parser's output allocation.
pub fn parse_limited(s: &[u8], max_pairs: usize) -> Result<Option<Labels<'_>>, ()> {
    let mut too_many = false;
    let labels = parse_inner(s, max_pairs, &mut too_many);
    if too_many {
        Err(())
    } else {
        Ok(labels)
    }
}

fn parse_inner<'a>(s: &'a [u8], max_pairs: usize, too_many: &mut bool) -> Option<Labels<'a>> {
    let mut p = Parser { s, i: 0 };
    let mut out = Vec::new();
    p.expect(b'{')?;
    p.ws();
    if p.peek() == Some(b'}') {
        p.i += 1;
        return p.at_end().then_some(out);
    }
    loop {
        if out.len() >= max_pairs {
            *too_many = true;
            return None;
        }
        let name = p.name()?;
        p.ws();
        p.expect(b'=')?;
        p.ws();
        let value = p.quoted()?;
        out.push((name, value));
        p.ws();
        match p.peek()? {
            b',' => {
                p.i += 1;
                p.ws();
                // PromQL's grammar allows a trailing comma: `{a="1",}`.
                if p.peek() == Some(b'}') {
                    p.i += 1;
                    return p.at_end().then_some(out);
                }
            }
            b'}' => {
                p.i += 1;
                return p.at_end().then_some(out);
            }
            _ => return None,
        }
    }
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
}

impl<'a> Parser<'a> {
    fn peek(&self) -> Option<u8> {
        self.s.get(self.i).copied()
    }

    fn at_end(&self) -> bool {
        self.i == self.s.len()
    }

    fn expect(&mut self, c: u8) -> Option<()> {
        (self.peek()? == c).then(|| self.i += 1)
    }

    fn ws(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\t')) {
            self.i += 1;
        }
    }

    fn name(&mut self) -> Option<&'a str> {
        let start = self.i;
        if !matches!(self.peek()?, b'a'..=b'z' | b'A'..=b'Z' | b'_') {
            return None;
        }
        while matches!(
            self.peek(),
            Some(b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'_')
        ) {
            self.i += 1;
        }
        std::str::from_utf8(&self.s[start..self.i]).ok()
    }

    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        let out = self.s.get(self.i..self.i.checked_add(n)?)?;
        self.i += n;
        Some(out)
    }

    fn quoted(&mut self) -> Option<Cow<'a, [u8]>> {
        self.expect(b'"')?;
        let start = self.i;
        let mut owned: Option<Vec<u8>> = None;
        loop {
            let c = self.peek()?;
            if c == b'"' {
                let value = match owned {
                    Some(o) => Cow::Owned(o),
                    None => Cow::Borrowed(&self.s[start..self.i]),
                };
                self.i += 1;
                return Some(value);
            }
            if c != b'\\' {
                if let Some(o) = owned.as_mut() {
                    o.push(c);
                }
                self.i += 1;
                continue;
            }
            let o = owned.get_or_insert_with(|| self.s[start..self.i].to_vec());
            self.i += 1;
            let e = self.peek()?;
            self.i += 1;
            match e {
                b'a' => o.push(0x07),
                b'b' => o.push(0x08),
                b'f' => o.push(0x0c),
                b'n' => o.push(b'\n'),
                b'r' => o.push(b'\r'),
                b't' => o.push(b'\t'),
                b'v' => o.push(0x0b),
                b'\\' | b'"' | b'\'' => o.push(e),
                b'x' => {
                    let v = hex(self.s.get(self.i..self.i + 2)?)?;
                    self.i += 2;
                    o.push(v as u8);
                }
                b'u' | b'U' => {
                    let n = if e == b'u' { 4 } else { 8 };
                    let cp = hex(self.s.get(self.i..self.i + n)?)?;
                    self.i += n;
                    let ch = char::from_u32(cp)?;
                    o.extend_from_slice(ch.encode_utf8(&mut [0; 4]).as_bytes());
                }
                b'0'..=b'7' => {
                    let rest = self.take(2)?;
                    let digits = [e, rest[0], rest[1]];
                    if !digits.iter().all(|d| (b'0'..=b'7').contains(d)) {
                        return None;
                    }
                    let v = digits
                        .iter()
                        .fold(0u32, |acc, d| acc * 8 + u32::from(d - b'0'));
                    o.push(u8::try_from(v).ok()?);
                }
                _ => return None,
            }
        }
    }
}

fn hex(b: &[u8]) -> Option<u32> {
    if !b.iter().all(u8::is_ascii_hexdigit) {
        return None;
    }
    u32::from_str_radix(std::str::from_utf8(b).ok()?, 16).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map(s: &str) -> Option<Vec<(String, Vec<u8>)>> {
        parse(s.as_bytes()).map(|l| {
            l.into_iter()
                .map(|(k, v)| (k.to_string(), v.into_owned()))
                .collect()
        })
    }

    fn one(s: &str) -> Option<Vec<u8>> {
        map(s).map(|mut v| v.remove(0).1)
    }

    #[test]
    fn empty_set() {
        assert_eq!(map("{}"), Some(vec![]));
        assert_eq!(map("{ }"), Some(vec![]));
    }

    #[test]
    fn pairs_and_whitespace() {
        assert_eq!(
            map(r#"{  service = "api" ,	level="info"  }"#),
            Some(vec![
                ("service".into(), b"api".to_vec()),
                ("level".into(), b"info".to_vec())
            ])
        );
    }

    #[test]
    fn plain_values_borrow_from_input() {
        let input = br#"{a="plain"}"#;
        let parsed = parse(input).unwrap();
        assert!(matches!(parsed[0].1, Cow::Borrowed(_)));
    }

    #[test]
    fn common_and_control_escapes() {
        assert_eq!(
            one(r#"{k="a\"b\\c\nd\te\rf"}"#),
            Some(b"a\"b\\c\nd\te\rf".to_vec())
        );
        assert_eq!(
            one(r#"{k="\a\b\f\v\'"}"#),
            Some(vec![0x07, 0x08, 0x0c, 0x0b, b'\''])
        );
    }

    #[test]
    fn hex_unicode_and_octal_escapes() {
        assert_eq!(one(r#"{k="\x00\x7f\xff"}"#), Some(vec![0x00, 0x7f, 0xff]));
        // `~` stands in for a backslash so the escape survives tooling
        // that eagerly rewrites four-digit unicode escapes.
        let input = r#"{k="caf~u00e9 ~u4e2d"}"#.replace('~', "\\");
        assert_eq!(one(&input), Some("caf\u{e9} \u{4e2d}".as_bytes().to_vec()));
        assert_eq!(one(r#"{k="\U0001F600"}"#), Some("😀".as_bytes().to_vec()));
        assert_eq!(one(r#"{k="\000\177\377"}"#), Some(vec![0x00, 0x7f, 0xff]));
    }

    #[test]
    fn rejects_malformed_escapes() {
        for bad in [
            r#"{k="\x0"}"#,
            r#"{k="\xzz"}"#,
            r#"{k="\u00"}"#,
            r#"{k="\U0001"}"#,
            r#"{k="\ud800"}"#,
            r#"{k="\q"}"#,
            r#"{k="\400"}"#,
            r#"{k="\09"}"#,
            r#"{k="\"#,
        ] {
            assert_eq!(map(bad), None, "{bad}");
        }
    }

    #[test]
    fn rejects_malformed_structure() {
        for bad in [
            r#"service="api""#,
            r#"{service="api""#,
            r#"{service="api"#,
            r#"{="api"}"#,
            r#"{1a="api"}"#,
            r#"{service=api}"#,
            r#"{service="api"} extra"#,
            r#"{a="1",,}"#,
            "",
        ] {
            assert_eq!(map(bad), None, "{bad}");
        }
    }

    #[test]
    fn accepts_trailing_comma() {
        assert_eq!(map(r#"{a="1",}"#), Some(vec![("a".into(), b"1".to_vec())]));
    }
}
