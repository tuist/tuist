//! Strict JSON parser over a borrowed slice.
//!
//! It accepts exactly the documents Elixir's `JSON.decode/1` accepts and
//! produces the same values, except in cases where the two could differ;
//! for those it gives up with `Fallback` so the caller re-decodes in
//! Elixir. Those cases are: any syntax error, integers outside the 64-bit
//! range, floats that overflow, lone surrogates, duplicate object keys
//! (Elixir keeps the first), and nesting deeper than `MAX_DEPTH`.
//!
//! Schema-aware callers explicitly opt into integral-lexeme callbacks via
//! `document_in`; ordinary document/value APIs retain their existing semantics.
//!
//! Strings without escapes are handed to the builder as slices of the
//! input so they can become sub-binaries instead of copies.

use std::borrow::Cow;

pub const MAX_DEPTH: usize = 256;

/// An object's keys with the raw, unparsed slice of each value.
pub type RawFields<'a> = Vec<(Cow<'a, [u8]>, &'a [u8])>;

#[derive(Debug, PartialEq, Eq)]
pub struct Fallback;

pub type Res<T> = Result<T, Fallback>;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Number {
    Int(i64),
    UInt(u64),
    Float(f64),
}

/// Optional schema context. Ordinary JSON never requests integer lexemes.
pub trait Context: Copy {
    fn key(self, key: &[u8]) -> Self;
    // Zero means unknown. Schema-aware callers assign distinct known-field bits.
    fn field_bit(self, _key: &[u8]) -> u64 {
        0
    }
    fn integer(self) -> bool {
        false
    }
}
#[derive(Clone, Copy)]
struct Ordinary;
impl Context for Ordinary {
    fn key(self, _: &[u8]) -> Self {
        self
    }
}

pub trait Builder<'a> {
    type Value;
    fn null(&mut self) -> Res<Self::Value>;
    fn boolean(&mut self, v: bool) -> Res<Self::Value>;
    fn number(&mut self, n: Number) -> Res<Self::Value>;
    fn integer_literal(&mut self, _raw: &'a [u8]) -> Res<Self::Value> {
        Err(Fallback)
    }
    fn string(&mut self, s: Cow<'a, [u8]>) -> Res<Self::Value>;
    /// An object key; builders can intern these since keys repeat.
    fn key(&mut self, s: Cow<'a, [u8]>) -> Res<Self::Value> {
        self.string(s)
    }
    fn array(&mut self, items: &[Self::Value]) -> Res<Self::Value>;
    /// Must return `Fallback` on duplicate keys.
    fn object(&mut self, keys: &[Self::Value], values: &[Self::Value]) -> Res<Self::Value>;
}

/// Scratch space shared by every container in a document: children are
/// pushed here and the container is built from a slice, so parsing does
/// not allocate a vector per object or array.
pub struct Stacks<V> {
    keys: Vec<V>,
    values: Vec<V>,
}

impl<V> Stacks<V> {
    pub fn new() -> Self {
        Stacks {
            keys: Vec::new(),
            values: Vec::new(),
        }
    }
}

impl<V> Default for Stacks<V> {
    fn default() -> Self {
        Self::new()
    }
}

pub struct Parser<'a> {
    buf: &'a [u8],
    pos: usize,
    depth: usize,
    // The whole buffer is valid UTF-8, and so is every string chunk, since
    // chunks end at ASCII quotes and backslashes.
    utf8: bool,
}

impl<'a> Parser<'a> {
    pub fn new(buf: &'a [u8]) -> Self {
        Parser {
            buf,
            pos: 0,
            depth: 0,
            utf8: false,
        }
    }

    /// A parser over text already known to be UTF-8, such as an Arrow
    /// string column value: strings then skip UTF-8 validation.
    pub fn new_utf8(buf: &'a str) -> Self {
        Parser {
            utf8: true,
            ..Parser::new(buf.as_bytes())
        }
    }

    /// A whole document: one value, optional surrounding whitespace.
    pub fn document<B: Builder<'a>>(&mut self, b: &mut B) -> Res<B::Value> {
        self.document_with(b, &mut Stacks::new())
    }

    /// Like `document/1`, reusing the caller's scratch stacks.
    pub fn document_with<B: Builder<'a>>(
        &mut self,
        b: &mut B,
        st: &mut Stacks<B::Value>,
    ) -> Res<B::Value> {
        self.document_in(b, st, Ordinary)
    }

    pub fn document_in<B: Builder<'a>, C: Context>(
        &mut self,
        b: &mut B,
        st: &mut Stacks<B::Value>,
        context: C,
    ) -> Res<B::Value> {
        self.ws();
        let v = self.value_in(b, st, context)?;
        self.ws();
        self.end()?;
        Ok(v)
    }

    pub fn end(&self) -> Res<()> {
        if self.pos == self.buf.len() {
            Ok(())
        } else {
            Err(Fallback)
        }
    }

    #[inline]
    pub fn ws(&mut self) {
        while let Some(b' ' | b'\t' | b'\n' | b'\r') = self.buf.get(self.pos) {
            self.pos += 1;
        }
    }

    pub(crate) fn position(&self) -> usize {
        self.pos
    }

    #[inline]
    pub(crate) fn peek(&self) -> Res<u8> {
        self.buf.get(self.pos).copied().ok_or(Fallback)
    }

    pub(crate) fn expect(&mut self, c: u8) -> Res<()> {
        if self.peek()? == c {
            self.pos += 1;
            Ok(())
        } else {
            Err(Fallback)
        }
    }

    fn literal(&mut self, word: &[u8]) -> Res<()> {
        if self.buf[self.pos..].starts_with(word) {
            self.pos += word.len();
            Ok(())
        } else {
            Err(Fallback)
        }
    }

    pub fn value<B: Builder<'a>>(&mut self, b: &mut B, st: &mut Stacks<B::Value>) -> Res<B::Value> {
        self.value_in(b, st, Ordinary)
    }

    fn value_in<B: Builder<'a>, C: Context>(
        &mut self,
        b: &mut B,
        st: &mut Stacks<B::Value>,
        context: C,
    ) -> Res<B::Value> {
        match self.peek()? {
            b'{' => {
                self.enter()?;
                self.pos += 1;
                let (k0, v0) = (st.keys.len(), st.values.len());
                let mut seen = 0u64;
                if self.object_open()? {
                    loop {
                        let key = self.string()?;
                        let bit = context.field_bit(&key);
                        if seen & bit != 0 {
                            return Err(Fallback);
                        }
                        seen |= bit;
                        let child = context.key(&key);
                        let key = b.key(key)?;
                        st.keys.push(key);
                        self.colon()?;
                        let value = self.value_in(b, st, child)?;
                        st.values.push(value);
                        if !self.object_next()? {
                            break;
                        }
                    }
                }
                self.depth -= 1;
                let object = b.object(&st.keys[k0..], &st.values[v0..]);
                st.keys.truncate(k0);
                st.values.truncate(v0);
                object
            }
            b'[' => {
                self.enter()?;
                self.pos += 1;
                let v0 = st.values.len();
                self.ws();
                if self.peek()? == b']' {
                    self.pos += 1;
                } else {
                    loop {
                        self.ws();
                        let item = self.value_in(b, st, context)?;
                        st.values.push(item);
                        self.ws();
                        match self.peek()? {
                            b',' => self.pos += 1,
                            b']' => {
                                self.pos += 1;
                                break;
                            }
                            _ => return Err(Fallback),
                        }
                    }
                }
                self.depth -= 1;
                let array = b.array(&st.values[v0..]);
                st.values.truncate(v0);
                array
            }
            b'"' => {
                let s = self.string()?;
                b.string(s)
            }
            b't' => {
                self.literal(b"true")?;
                b.boolean(true)
            }
            b'f' => {
                self.literal(b"false")?;
                b.boolean(false)
            }
            b'n' => {
                self.literal(b"null")?;
                b.null()
            }
            b'-' | b'0'..=b'9' => {
                if context.integer() {
                    let raw = self.number_literal()?;
                    b.integer_literal(raw)
                } else {
                    let n = self.number()?;
                    b.number(n)
                }
            }
            _ => Err(Fallback),
        }
    }

    fn enter(&mut self) -> Res<()> {
        self.depth += 1;
        if self.depth > MAX_DEPTH {
            Err(Fallback)
        } else {
            Ok(())
        }
    }

    // After `{`: skips whitespace; true when a first key follows, false on
    // an immediate `}`. Leaves `pos` on the key's opening quote.
    pub(crate) fn object_open(&mut self) -> Res<bool> {
        self.ws();
        match self.peek()? {
            b'}' => {
                self.pos += 1;
                Ok(false)
            }
            b'"' => Ok(true),
            _ => Err(Fallback),
        }
    }

    pub(crate) fn colon(&mut self) -> Res<()> {
        self.ws();
        self.expect(b':')?;
        self.ws();
        Ok(())
    }

    // After a value: true when another key follows (positioned on its
    // quote), false after the closing `}`.
    pub(crate) fn object_next(&mut self) -> Res<bool> {
        self.ws();
        match self.peek()? {
            b',' => {
                self.pos += 1;
                self.ws();
                if self.peek()? == b'"' {
                    Ok(true)
                } else {
                    Err(Fallback)
                }
            }
            b'}' => {
                self.pos += 1;
                Ok(false)
            }
            _ => Err(Fallback),
        }
    }

    // After an array's `[`: true when a first element follows (positioned on
    // it), false after an immediate `]`.
    pub(crate) fn array_rest(&mut self) -> Res<bool> {
        self.ws();
        if self.peek()? == b']' {
            self.pos += 1;
            return Ok(false);
        }
        Ok(true)
    }

    // After an element: true when another follows (positioned on it), false
    // after the closing `]`.
    pub(crate) fn array_next(&mut self) -> Res<bool> {
        self.ws();
        match self.peek()? {
            b',' => {
                self.pos += 1;
                self.ws();
                Ok(true)
            }
            b']' => {
                self.pos += 1;
                Ok(false)
            }
            _ => Err(Fallback),
        }
    }

    /// Top-level object whose values are returned unparsed, as slices of
    /// the input. Used by the segment decoder to look at a few fields
    /// before deciding whether to build the rest.
    pub fn raw_object(&mut self) -> Res<RawFields<'a>> {
        self.ws();
        self.expect(b'{')?;
        let mut fields = Vec::new();
        if self.object_open()? {
            loop {
                let key = self.string()?;
                self.colon()?;
                fields.push((key, self.skip_value()?));
                if !self.object_next()? {
                    break;
                }
            }
        }
        Ok(fields)
    }

    /// Top-level array values as validated slices, without materializing trees.
    pub fn raw_array(&mut self) -> Res<Vec<&'a [u8]>> {
        self.ws();
        self.expect(b'[')?;
        self.ws();
        let mut values = Vec::new();
        if self.peek()? == b']' {
            self.pos += 1;
            return Ok(values);
        }
        loop {
            values.push(self.skip_value()?);
            self.ws();
            match self.peek()? {
                b']' => {
                    self.pos += 1;
                    return Ok(values);
                }
                b',' => {
                    self.pos += 1;
                    self.ws();
                }
                _ => return Err(Fallback),
            }
        }
    }

    /// Validate a value and return its raw slice.
    pub fn skip_value(&mut self) -> Res<&'a [u8]> {
        let start = self.pos;
        self.value(&mut Skip, &mut Stacks::new())?;
        Ok(&self.buf[start..self.pos])
    }

    pub fn string(&mut self) -> Res<Cow<'a, [u8]>> {
        self.expect(b'"')?;
        let start = self.pos;
        let rest = &self.buf[start..];
        let end = memchr::memchr2(b'"', b'\\', rest).ok_or(Fallback)?;
        let chunk = &rest[..end];
        check_chunk(chunk, self.utf8)?;
        if rest[end] == b'"' {
            self.pos = start + end + 1;
            return Ok(Cow::Borrowed(chunk));
        }
        let mut owned = chunk.to_vec();
        self.pos = start + end;
        loop {
            // At a backslash.
            self.pos += 1;
            match self.peek()? {
                b'"' => owned.push(b'"'),
                b'\\' => owned.push(b'\\'),
                b'/' => owned.push(b'/'),
                b'b' => owned.push(0x08),
                b'f' => owned.push(0x0c),
                b'n' => owned.push(b'\n'),
                b'r' => owned.push(b'\r'),
                b't' => owned.push(b'\t'),
                b'u' => {
                    self.pos += 1;
                    let ch = self.unicode_escape()?;
                    owned.extend_from_slice(ch.encode_utf8(&mut [0; 4]).as_bytes());
                    self.pos -= 1;
                }
                _ => return Err(Fallback),
            }
            self.pos += 1;
            let rest = &self.buf[self.pos..];
            let end = memchr::memchr2(b'"', b'\\', rest).ok_or(Fallback)?;
            let chunk = &rest[..end];
            check_chunk(chunk, self.utf8)?;
            owned.extend_from_slice(chunk);
            self.pos += end;
            if rest[end] == b'"' {
                self.pos += 1;
                return Ok(Cow::Owned(owned));
            }
        }
    }

    // After `\u`; leaves `pos` just past the last hex digit consumed.
    fn unicode_escape(&mut self) -> Res<char> {
        let hi = self.hex4()?;
        if (0xDC00..=0xDFFF).contains(&hi) {
            return Err(Fallback);
        }
        if !(0xD800..=0xDBFF).contains(&hi) {
            return char::from_u32(hi).ok_or(Fallback);
        }
        if !self.buf[self.pos..].starts_with(b"\\u") {
            return Err(Fallback);
        }
        self.pos += 2;
        let lo = self.hex4()?;
        if !(0xDC00..=0xDFFF).contains(&lo) {
            return Err(Fallback);
        }
        char::from_u32(0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)).ok_or(Fallback)
    }

    fn hex4(&mut self) -> Res<u32> {
        let digits = self.buf.get(self.pos..self.pos + 4).ok_or(Fallback)?;
        let mut v = 0u32;
        for &d in digits {
            v = v * 16 + (d as char).to_digit(16).ok_or(Fallback)?;
        }
        self.pos += 4;
        Ok(v)
    }

    fn digits(&mut self) -> usize {
        let start = self.pos;
        while let Some(b'0'..=b'9') = self.buf.get(self.pos) {
            self.pos += 1;
        }
        self.pos - start
    }

    // Lexical validation only: integral OTLP fields must not first round through f64.
    fn number_literal(&mut self) -> Res<&'a [u8]> {
        let start = self.pos;
        if self.peek()? == b'-' {
            self.pos += 1;
        }
        match self.peek()? {
            b'0' => self.pos += 1,
            b'1'..=b'9' => {
                self.digits();
            }
            _ => return Err(Fallback),
        }
        if self.buf.get(self.pos) == Some(&b'.') {
            self.pos += 1;
            if self.digits() == 0 {
                return Err(Fallback);
            }
        }
        if let Some(b'e' | b'E') = self.buf.get(self.pos) {
            self.pos += 1;
            if let Some(b'+' | b'-') = self.buf.get(self.pos) {
                self.pos += 1;
            }
            if self.digits() == 0 {
                return Err(Fallback);
            }
        }
        Ok(&self.buf[start..self.pos])
    }

    fn number(&mut self) -> Res<Number> {
        let start = self.pos;
        let negative = self.buf[self.pos] == b'-';
        if negative {
            self.pos += 1;
        }
        match self.peek()? {
            b'0' => self.pos += 1,
            b'1'..=b'9' => {
                self.digits();
            }
            _ => return Err(Fallback),
        }
        let int_end = self.pos;
        let mut float = false;
        if self.buf.get(self.pos) == Some(&b'.') {
            self.pos += 1;
            if self.digits() == 0 {
                return Err(Fallback);
            }
            float = true;
        }
        if let Some(b'e' | b'E') = self.buf.get(self.pos) {
            self.pos += 1;
            if let Some(b'+' | b'-') = self.buf.get(self.pos) {
                self.pos += 1;
            }
            if self.digits() == 0 {
                return Err(Fallback);
            }
            float = true;
        }
        if float {
            // Safe: the slice is ASCII digits, sign, '.', 'e'.
            let text = std::str::from_utf8(&self.buf[start..self.pos]).map_err(|_| Fallback)?;
            let f: f64 = text.parse().map_err(|_| Fallback)?;
            // Overflow is an error in Elixir; underflow to zero is left to
            // Elixir too rather than assuming both round the same way.
            if !f.is_finite() || (f == 0.0 && has_nonzero_digit(text)) {
                return Err(Fallback);
            }
            return Ok(Number::Float(f));
        }
        let digits = &self.buf[if negative { start + 1 } else { start }..int_end];
        let mut magnitude: u64 = 0;
        for &d in digits {
            magnitude = magnitude
                .checked_mul(10)
                .and_then(|m| m.checked_add(u64::from(d - b'0')))
                .ok_or(Fallback)?;
        }
        if negative {
            if magnitude <= i64::MAX as u64 {
                Ok(Number::Int(-(magnitude as i64)))
            } else if magnitude == i64::MAX as u64 + 1 {
                Ok(Number::Int(i64::MIN))
            } else {
                Err(Fallback)
            }
        } else if magnitude <= i64::MAX as u64 {
            Ok(Number::Int(magnitude as i64))
        } else {
            Ok(Number::UInt(magnitude))
        }
    }
}

fn has_nonzero_digit(text: &str) -> bool {
    let mantissa = text.split(['e', 'E']).next().unwrap_or("");
    mantissa.bytes().any(|c| (b'1'..=b'9').contains(&c))
}

/// Raw string content between escapes: no control characters, valid UTF-8.
/// A multi-byte sequence never contains `\` or `"`, so validating chunk by
/// chunk is equivalent to validating the whole string.
#[inline]
fn check_chunk(chunk: &[u8], utf8: bool) -> Res<()> {
    if chunk.iter().any(|&c| c < 0x20) || (!utf8 && simdutf8::basic::from_utf8(chunk).is_err()) {
        Err(Fallback)
    } else {
        Ok(())
    }
}

/// Builder that validates without constructing anything.
struct Skip;

impl<'a> Builder<'a> for Skip {
    type Value = ();
    fn null(&mut self) -> Res<()> {
        Ok(())
    }
    fn boolean(&mut self, _: bool) -> Res<()> {
        Ok(())
    }
    fn number(&mut self, _: Number) -> Res<()> {
        Ok(())
    }
    fn string(&mut self, _: Cow<'a, [u8]>) -> Res<()> {
        Ok(())
    }
    fn array(&mut self, _: &[()]) -> Res<()> {
        Ok(())
    }
    // Duplicate keys inside skipped values are only detected once the
    // value is built for real, which falls back then.
    fn object(&mut self, _: &[()], _: &[()]) -> Res<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, PartialEq, Clone)]
    enum V {
        Null,
        Bool(bool),
        Num(Number),
        Str(Vec<u8>, bool),
        Arr(Vec<V>),
        Obj(Vec<(V, V)>),
    }

    struct T;

    impl<'a> Builder<'a> for T {
        type Value = V;
        fn null(&mut self) -> Res<V> {
            Ok(V::Null)
        }
        fn boolean(&mut self, v: bool) -> Res<V> {
            Ok(V::Bool(v))
        }
        fn number(&mut self, n: Number) -> Res<V> {
            Ok(V::Num(n))
        }
        fn string(&mut self, s: Cow<'a, [u8]>) -> Res<V> {
            let borrowed = matches!(s, Cow::Borrowed(_));
            Ok(V::Str(s.into_owned(), borrowed))
        }
        fn array(&mut self, items: &[V]) -> Res<V> {
            Ok(V::Arr(items.to_vec()))
        }
        fn object(&mut self, keys: &[V], values: &[V]) -> Res<V> {
            for (i, k) in keys.iter().enumerate() {
                if keys[..i].contains(k) {
                    return Err(Fallback);
                }
            }
            Ok(V::Obj(
                keys.iter().cloned().zip(values.iter().cloned()).collect(),
            ))
        }
    }

    fn parse(s: &str) -> Res<V> {
        Parser::new(s.as_bytes()).document(&mut T)
    }

    fn str_v(s: &str, borrowed: bool) -> V {
        V::Str(s.as_bytes().to_vec(), borrowed)
    }

    // `~` stands in for a backslash so escapes survive tooling that
    // rewrites four-digit unicode escapes.
    fn esc(s: &str) -> String {
        s.replace('~', "\\")
    }

    #[test]
    fn scalars_and_whitespace() {
        assert_eq!(parse(" null "), Ok(V::Null));
        assert_eq!(parse("\ttrue\r\n"), Ok(V::Bool(true)));
        assert_eq!(parse("false"), Ok(V::Bool(false)));
        assert_eq!(parse("0"), Ok(V::Num(Number::Int(0))));
        assert_eq!(parse("-0"), Ok(V::Num(Number::Int(0))));
        assert_eq!(parse("-0.0"), Ok(V::Num(Number::Float(-0.0))));
        assert_eq!(parse("1E2"), Ok(V::Num(Number::Float(100.0))));
        assert_eq!(parse("2.5e-3"), Ok(V::Num(Number::Float(0.0025))));
        assert_eq!(
            parse("9223372036854775807"),
            Ok(V::Num(Number::Int(i64::MAX)))
        );
        assert_eq!(
            parse("-9223372036854775808"),
            Ok(V::Num(Number::Int(i64::MIN)))
        );
        assert_eq!(
            parse("18446744073709551615"),
            Ok(V::Num(Number::UInt(u64::MAX)))
        );
    }

    #[test]
    fn falls_back_where_elixir_differs_or_errors() {
        for bad in [
            "18446744073709551616",
            "-9223372036854775809",
            "1e400",
            "1e-400",
            "01",
            "-",
            "1.",
            ".5",
            "1e",
            "+1",
            "tru",
            "nul",
            "[1,]",
            "{\"a\":1,}",
            "{\"a\" 1}",
            "{1:2}",
            "[1 2]",
            "1 2",
            "",
            "\"unterminated",
            "{\"a\":1,\"a\":2}",
        ] {
            assert_eq!(parse(bad), Err(Fallback), "{bad:?}");
        }
        let deep = "[".repeat(MAX_DEPTH + 1) + &"]".repeat(MAX_DEPTH + 1);
        assert_eq!(parse(&deep), Err(Fallback));
        let ok_deep = "[".repeat(MAX_DEPTH) + &"]".repeat(MAX_DEPTH);
        assert!(parse(&ok_deep).is_ok());
    }

    #[test]
    fn strings() {
        assert_eq!(parse(r#""plain é""#), Ok(str_v("plain é", true)));
        assert_eq!(parse(r#""""#), Ok(str_v("", true)));
        assert_eq!(
            parse(r#""a\"b\\c\/d\n\t\r\b\f""#),
            Ok(str_v("a\"b\\c/d\n\t\r\u{8}\u{c}", false))
        );
        assert_eq!(
            parse(&esc(r#""~u00e9~u0000""#)),
            Ok(str_v("\u{e9}\u{0}", false))
        );
        assert_eq!(
            parse(&esc(r#""~ud83d~ude00""#)),
            Ok(str_v("\u{1F600}", false))
        );
        for bad in [
            esc(r#""~ud800""#),
            esc(r#""~udc00""#),
            esc(r#""~ud800~u0041""#),
            esc(r#""~u12""#),
            esc(r#""~x41""#),
            "\"a\u{1}b\"".to_string(),
        ] {
            assert_eq!(parse(&bad), Err(Fallback), "{bad:?}");
        }
        assert_eq!(Parser::new(b"\"\xff\"").document(&mut T), Err(Fallback));
    }

    #[test]
    fn containers() {
        assert_eq!(
            parse(r#" { "a" : [1, 2.5, {"b": null}], "c": {} } "#),
            Ok(V::Obj(vec![
                (
                    str_v("a", true),
                    V::Arr(vec![
                        V::Num(Number::Int(1)),
                        V::Num(Number::Float(2.5)),
                        V::Obj(vec![(str_v("b", true), V::Null)])
                    ])
                ),
                (str_v("c", true), V::Obj(vec![])),
            ]))
        );
        assert_eq!(parse("[]"), Ok(V::Arr(vec![])));
    }

    #[test]
    fn raw_object_returns_value_slices() {
        let input = br#"{"ts": 12, "body": "x", "attrs": {"k": [1, "v"]}}"#;
        let fields = Parser::new(input).raw_object().unwrap();
        let rendered: Vec<(String, String)> = fields
            .iter()
            .map(|(k, v)| {
                (
                    String::from_utf8(k.to_vec()).unwrap(),
                    String::from_utf8(v.to_vec()).unwrap(),
                )
            })
            .collect();
        assert_eq!(
            rendered,
            vec![
                ("ts".into(), "12".into()),
                ("body".into(), "\"x\"".into()),
                ("attrs".into(), r#"{"k": [1, "v"]}"#.into()),
            ]
        );
    }

    // Deterministic mutation fuzzing: the parser must never panic.
    #[test]
    fn survives_mutated_inputs() {
        let seeds: Vec<Vec<u8>> = vec![
            esc(r#"{"a":[1,-2.5e3,true,null,"x~ud83d~ude00~n"],"b":{"c":"d"}}"#).into_bytes(),
            br#"[0,{"k":[[],{}]},"\\\"",18446744073709551615]"#.to_vec(),
        ];
        let mut state: u64 = 0x2545_f491_4f6c_dd1d;
        let mut rand = move || {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state
        };
        for _ in 0..200_000 {
            let mut buf = seeds[(rand() % 2) as usize].clone();
            for _ in 0..(1 + rand() % 4) {
                let at = (rand() as usize) % buf.len().max(1);
                match rand() % 3 {
                    0 if !buf.is_empty() => buf[at] = rand() as u8,
                    1 => buf.truncate(at),
                    _ => buf.insert(at.min(buf.len()), rand() as u8),
                }
            }
            let _ = Parser::new(&buf).document(&mut T);
            let _ = Parser::new(&buf).raw_object();
        }
    }
}
