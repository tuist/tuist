//! Query-time filters pushed into the Parquet decode loop.
//!
//! Every row that fails one of these predicates is rejected before any
//! Erlang term is built for it — no sub-binaries, no map allocation, no
//! JSON re-encode for `attributes` or `resource`. The Elixir side keeps
//! the same predicate set as a post-decode fallback so a `:fallback`
//! from the NIF is a hard error, not a correctness gate.
//!
//! Label matchers evaluate against the `resource` JSON column, which is
//! where the Loki push pipeline puts stream labels (`Pulse.Loki.Push`).
//! The scanner is a bespoke flat JSON object walker: it produces
//! borrowed `(key, value)` slices without allocating and without going
//! deeper than one level. Anything more complex than a top-level object
//! with string values falls through as "no match" — which is the right
//! answer for a stream-label matcher.
//!
//! Body line filters evaluate against the raw JSON-encoded `body` bytes
//! (with quotes intact for string bodies). This is close-enough to
//! Loki's semantics for the common case where bodies are plain strings.
//! `\n` and other escape sequences in the source are preserved as
//! escaped forms in the JSON representation, so a pattern containing
//! literal newlines will not match a body that JSON-encoded them.

use memchr::memmem::Finder;
use regex::bytes::Regex;
use std::borrow::Cow;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MatchOp {
    Eq,
    Neq,
    Re,
    Nre,
}

pub enum Matcher {
    Literal {
        name: Vec<u8>,
        op: MatchOp,
        value: Vec<u8>,
    },
    Regex {
        name: Vec<u8>,
        op: MatchOp,
        regex: Regex,
    },
}

impl Matcher {
    /// Name of the label this matcher looks up (borrowed slice into the
    /// matcher; borrowed lifetime tied to `&self`).
    pub fn name(&self) -> &[u8] {
        match self {
            Matcher::Literal { name, .. } | Matcher::Regex { name, .. } => name,
        }
    }

    /// Evaluate the matcher against a *found* label value. Callers
    /// distinguish "label present" from "label absent"; a Neq/Nre matcher
    /// against an absent label evaluates true, which is why callers must
    /// track presence rather than passing `""` for missing labels.
    pub fn evaluate_present(&self, value: &[u8]) -> bool {
        match self {
            Matcher::Literal {
                op: MatchOp::Eq,
                value: v,
                ..
            } => value == v.as_slice(),
            Matcher::Literal {
                op: MatchOp::Neq,
                value: v,
                ..
            } => value != v.as_slice(),
            Matcher::Regex {
                op: MatchOp::Re,
                regex,
                ..
            } => regex.is_match(value),
            Matcher::Regex {
                op: MatchOp::Nre,
                regex,
                ..
            } => !regex.is_match(value),
            // Op-value combinations that shouldn't be constructed but
            // are cheap to close over.
            Matcher::Literal {
                op: MatchOp::Re, ..
            }
            | Matcher::Literal {
                op: MatchOp::Nre, ..
            }
            | Matcher::Regex {
                op: MatchOp::Eq, ..
            }
            | Matcher::Regex {
                op: MatchOp::Neq, ..
            } => false,
        }
    }

    /// Evaluate against an *absent* label. Loki's semantics treat a
    /// missing label as the empty string, so `foo=""` matches when foo
    /// is absent and `foo!=""` does not.
    pub fn evaluate_absent(&self) -> bool {
        match self {
            Matcher::Literal {
                op: MatchOp::Eq,
                value,
                ..
            } => value.is_empty(),
            Matcher::Literal {
                op: MatchOp::Neq,
                value,
                ..
            } => !value.is_empty(),
            Matcher::Regex {
                op: MatchOp::Re,
                regex,
                ..
            } => regex.is_match(b""),
            Matcher::Regex {
                op: MatchOp::Nre,
                regex,
                ..
            } => !regex.is_match(b""),
            _ => false,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LineFilterOp {
    Contains,
    NotContains,
    MatchRe,
    NotMatchRe,
}

pub enum LineFilter {
    Substring {
        op: LineFilterOp,
        // Finder holds the pattern for `memmem` searches. Boxed so the
        // enum stays close in size to its Regex variant (clippy's
        // `large_enum_variant` lint).
        finder: Box<Finder<'static>>,
    },
    Regex {
        op: LineFilterOp,
        regex: Regex,
    },
}

impl LineFilter {
    pub fn matches(&self, body: &[u8]) -> bool {
        match self {
            LineFilter::Substring {
                op: LineFilterOp::Contains,
                finder,
            } => finder.find(body).is_some(),
            LineFilter::Substring {
                op: LineFilterOp::NotContains,
                finder,
            } => finder.find(body).is_none(),
            LineFilter::Regex {
                op: LineFilterOp::MatchRe,
                regex,
            } => regex.is_match(body),
            LineFilter::Regex {
                op: LineFilterOp::NotMatchRe,
                regex,
            } => !regex.is_match(body),
            // Op-value combinations that shouldn't be constructed.
            LineFilter::Substring {
                op: LineFilterOp::MatchRe,
                ..
            }
            | LineFilter::Substring {
                op: LineFilterOp::NotMatchRe,
                ..
            } => false,
            LineFilter::Regex {
                op: LineFilterOp::Contains,
                ..
            }
            | LineFilter::Regex {
                op: LineFilterOp::NotContains,
                ..
            } => false,
        }
    }
}

/// Turn a JSON-encoded body into the bytes an evaluator should match
/// against.
///
/// Body is stored as JSON: a string body is `"..."` (quoted, escaped),
/// a structured body is `{...}` / `[...]`. LogQL line filters mean
/// "match against the log line" — for a string body that's the
/// unescaped content, for a structured body that's whatever the
/// original JSON looked like. Peeling the quotes off a string body
/// makes `|~ "^hello"` behave the way a user expects, and it stays
/// consistent with `Pulse.LogQL.Entry.from_record/1` on the Memory
/// side which uses the raw string.
pub fn line_bytes_for_match(body: &[u8]) -> Cow<'_, [u8]> {
    if body.len() >= 2 && body[0] == b'"' && body[body.len() - 1] == b'"' {
        let inner = &body[1..body.len() - 1];
        if inner.contains(&b'\\') {
            Cow::Owned(unescape_json_string(inner))
        } else {
            Cow::Borrowed(inner)
        }
    } else {
        Cow::Borrowed(body)
    }
}

/// Look up a single top-level string label in a JSON object encoded as
/// bytes. Returns `Some(Cow::Borrowed(bytes))` for an unescaped string
/// value (zero-copy sub-slice) and `Some(Cow::Owned(vec))` for a value
/// with escapes (one small alloc). `None` means the label is either
/// absent or has a non-string value — the caller then uses
/// `evaluate_absent`, which is the same answer either way.
///
/// Handles the common case Loki push produces
/// (`{"key":"value","key2":"value2"}`); nested objects and arrays are
/// skipped correctly so subsequent keys still parse.
pub fn find_label<'a>(input: &'a [u8], key: &[u8]) -> Option<Cow<'a, [u8]>> {
    let mut found = None;
    walk_string_pairs(input, false, |name, value| {
        if decoded(name).as_ref() == key {
            found = Some(decoded(value));
            false
        } else {
            true
        }
    })?;
    found
}

/// A decoded `(key, value)` label, borrowed when it had no escapes.
pub type LabelPair<'a> = (Cow<'a, [u8]>, Cow<'a, [u8]>);

/// Every top-level string-valued `(key, value)` pair of a flat JSON object,
/// in source order, with escapes decoded. Non-string values are skipped, as
/// they are for `find_label`. `None` means the input is not an object.
pub fn string_pairs(input: &[u8]) -> Option<Vec<LabelPair<'_>>> {
    let mut pairs = Vec::new();
    walk_string_pairs(input, false, |name, value| {
        pairs.push((decoded(name), decoded(value)));
        true
    })?;
    Some(pairs)
}

/// Like `string_pairs`, but `None` when any value is not a string, so the
/// caller never has to reproduce another runtime's stringification.
pub fn strict_string_pairs(input: &[u8]) -> Option<Vec<LabelPair<'_>>> {
    let mut pairs = Vec::new();
    walk_string_pairs(input, true, |name, value| {
        pairs.push((decoded(name), decoded(value)));
        true
    })?;
    Some(pairs)
}

// Raw (still escaped) JSON string contents.
fn decoded(raw: &[u8]) -> Cow<'_, [u8]> {
    if has_escapes(raw) {
        Cow::Owned(unescape_json_string(raw))
    } else {
        Cow::Borrowed(raw)
    }
}

// Visit each top-level string-valued pair as raw escaped slices until the
// visitor returns false. `None` for a malformed or non-object input.
fn walk_string_pairs<'a>(
    input: &'a [u8],
    strict: bool,
    mut visit: impl FnMut(&'a [u8], &'a [u8]) -> bool,
) -> Option<()> {
    let mut i = 0;
    let n = input.len();

    while i < n && (input[i] as char).is_whitespace() {
        i += 1;
    }
    if i >= n || input[i] != b'{' {
        return None;
    }
    i += 1;

    loop {
        // Skip whitespace and commas.
        while i < n && matches!(input[i], b' ' | b'\t' | b'\n' | b'\r' | b',') {
            i += 1;
        }
        if i >= n {
            return None;
        }
        if input[i] == b'}' {
            return Some(());
        }
        if input[i] != b'"' {
            return None;
        }
        i += 1;
        let key_start = i;
        i = string_end(input, i)?;
        let key = &input[key_start..i];
        i += 1;
        // Skip whitespace, expect ':'.
        while i < n && matches!(input[i], b' ' | b'\t' | b'\n' | b'\r') {
            i += 1;
        }
        if i >= n || input[i] != b':' {
            return None;
        }
        i += 1;
        while i < n && matches!(input[i], b' ' | b'\t' | b'\n' | b'\r') {
            i += 1;
        }
        if i >= n {
            return None;
        }

        if input[i] == b'"' {
            i += 1;
            let val_start = i;
            i = string_end(input, i)?;
            let value = &input[val_start..i];
            i += 1;
            if !visit(key, value) {
                return Some(());
            }
        } else if strict {
            return None;
        } else {
            // Non-string value: only string labels are visited, so walking
            // its extent to reach the next key is enough.
            i = skip_value(input, i)?;
        }
    }
}

// Position of the closing quote of a string whose contents start at `i`.
fn string_end(input: &[u8], mut i: usize) -> Option<usize> {
    let n = input.len();
    while i < n && input[i] != b'"' {
        if input[i] == b'\\' && i + 1 < n {
            i += 2;
        } else {
            i += 1;
        }
    }
    (i < n).then_some(i)
}

fn has_escapes(bytes: &[u8]) -> bool {
    bytes.contains(&b'\\')
}

fn unescape_json_string(bytes: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\' && i + 1 < bytes.len() {
            match bytes[i + 1] {
                b'n' => {
                    out.push(b'\n');
                    i += 2;
                }
                b't' => {
                    out.push(b'\t');
                    i += 2;
                }
                b'r' => {
                    out.push(b'\r');
                    i += 2;
                }
                b'b' => {
                    out.push(0x08);
                    i += 2;
                }
                b'f' => {
                    out.push(0x0C);
                    i += 2;
                }
                b'"' => {
                    out.push(b'"');
                    i += 2;
                }
                b'\\' => {
                    out.push(b'\\');
                    i += 2;
                }
                b'/' => {
                    out.push(b'/');
                    i += 2;
                }
                b'u' if i + 6 <= bytes.len() => match decode_unicode_escape(&bytes[i + 2..i + 6]) {
                    Some(cp) => {
                        push_utf8(&mut out, cp);
                        i += 6;
                    }
                    None => {
                        // Malformed \uXXXX — keep the raw sequence rather
                        // than silently dropping bytes.
                        out.extend_from_slice(&bytes[i..i + 6]);
                        i += 6;
                    }
                },
                other => {
                    out.push(b'\\');
                    out.push(other);
                    i += 2;
                }
            }
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    out
}

fn decode_unicode_escape(hex: &[u8]) -> Option<u32> {
    let mut cp: u32 = 0;
    for &b in hex {
        let d = match b {
            b'0'..=b'9' => (b - b'0') as u32,
            b'a'..=b'f' => (b - b'a' + 10) as u32,
            b'A'..=b'F' => (b - b'A' + 10) as u32,
            _ => return None,
        };
        cp = (cp << 4) | d;
    }
    Some(cp)
}

fn push_utf8(out: &mut Vec<u8>, cp: u32) {
    match cp {
        0..=0x7F => out.push(cp as u8),
        0x80..=0x7FF => {
            out.push(0xC0 | ((cp >> 6) as u8));
            out.push(0x80 | ((cp & 0x3F) as u8));
        }
        0x800..=0xFFFF => {
            out.push(0xE0 | ((cp >> 12) as u8));
            out.push(0x80 | (((cp >> 6) & 0x3F) as u8));
            out.push(0x80 | ((cp & 0x3F) as u8));
        }
        _ => {
            // Astral code points require surrogate-pair decoding; we don't
            // handle that here (label values rarely go past the BMP).
            // Emit the replacement character so the value is well-formed
            // UTF-8 even if the specific codepoint is lost.
            out.extend_from_slice("\u{FFFD}".as_bytes());
        }
    }
}

// Walks past one JSON value, returning the position after it, or None if
// malformed. Handles nested objects and arrays by depth counting.
fn skip_value(input: &[u8], start: usize) -> Option<usize> {
    let n = input.len();
    if start >= n {
        return None;
    }
    match input[start] {
        b'{' | b'[' => {
            let opener = input[start];
            let closer = if opener == b'{' { b'}' } else { b']' };
            let mut depth = 1;
            let mut i = start + 1;
            while i < n && depth > 0 {
                match input[i] {
                    b'"' => {
                        i += 1;
                        while i < n && input[i] != b'"' {
                            if input[i] == b'\\' && i + 1 < n {
                                i += 2;
                            } else {
                                i += 1;
                            }
                        }
                        if i >= n {
                            return None;
                        }
                        i += 1;
                    }
                    b if b == opener => {
                        depth += 1;
                        i += 1;
                    }
                    b if b == closer => {
                        depth -= 1;
                        i += 1;
                    }
                    _ => i += 1,
                }
            }
            if depth == 0 {
                Some(i)
            } else {
                None
            }
        }
        b't' | b'f' | b'n' => {
            let mut i = start;
            while i < n && input[i].is_ascii_alphabetic() {
                i += 1;
            }
            Some(i)
        }
        b'-' | b'0'..=b'9' => {
            let mut i = start;
            while i < n
                && (input[i].is_ascii_digit()
                    || matches!(input[i], b'.' | b'e' | b'E' | b'+' | b'-'))
            {
                i += 1;
            }
            Some(i)
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn as_slice(v: Option<Cow<'_, [u8]>>) -> Option<Vec<u8>> {
        v.map(|c| c.into_owned())
    }

    #[test]
    fn find_label_simple() {
        assert_eq!(
            as_slice(find_label(b"{\"env\":\"prod\",\"svc\":\"api\"}", b"env")),
            Some(b"prod".to_vec())
        );
        assert_eq!(
            as_slice(find_label(b"{\"env\":\"prod\",\"svc\":\"api\"}", b"svc")),
            Some(b"api".to_vec())
        );
    }

    #[test]
    fn find_label_missing() {
        assert_eq!(as_slice(find_label(b"{\"env\":\"prod\"}", b"svc")), None);
    }

    #[test]
    fn find_label_empty_object() {
        assert_eq!(as_slice(find_label(b"{}", b"foo")), None);
    }

    #[test]
    fn find_label_skips_non_string_values() {
        assert_eq!(
            as_slice(find_label(b"{\"n\":42,\"env\":\"prod\"}", b"env")),
            Some(b"prod".to_vec())
        );
        assert_eq!(
            as_slice(find_label(b"{\"o\":{\"a\":1},\"env\":\"prod\"}", b"env")),
            Some(b"prod".to_vec())
        );
    }

    #[test]
    fn find_label_with_whitespace() {
        assert_eq!(
            as_slice(find_label(b"{ \"env\" : \"prod\" }", b"env")),
            Some(b"prod".to_vec())
        );
    }

    #[test]
    fn find_label_with_escaped_value_returns_decoded() {
        // Escaped quote inside the value: {"env":"prod\"beta"}
        assert_eq!(
            as_slice(find_label(b"{\"env\":\"prod\\\"beta\"}", b"env")),
            Some(b"prod\"beta".to_vec())
        );
    }

    #[test]
    fn find_label_with_escaped_newline_in_value() {
        assert_eq!(
            as_slice(find_label(b"{\"msg\":\"line\\nbreak\"}", b"msg")),
            Some(b"line\nbreak".to_vec())
        );
    }

    #[test]
    fn find_label_with_unicode_escape() {
        // é = é
        assert_eq!(
            as_slice(find_label(b"{\"name\":\"caf\\u00e9\"}", b"name")),
            Some("café".as_bytes().to_vec())
        );
    }

    #[test]
    fn matcher_literal_eq() {
        let m = Matcher::Literal {
            name: b"env".to_vec(),
            op: MatchOp::Eq,
            value: b"prod".to_vec(),
        };
        assert!(m.evaluate_present(b"prod"));
        assert!(!m.evaluate_present(b"dev"));
        assert!(!m.evaluate_absent());
    }

    #[test]
    fn matcher_literal_neq_on_absent() {
        // `foo != "bar"` matches when foo is absent (treated as empty)
        let m = Matcher::Literal {
            name: b"foo".to_vec(),
            op: MatchOp::Neq,
            value: b"bar".to_vec(),
        };
        assert!(m.evaluate_absent());
    }

    #[test]
    fn matcher_regex_re() {
        let m = Matcher::Regex {
            name: b"env".to_vec(),
            op: MatchOp::Re,
            regex: Regex::new("prod|stg").unwrap(),
        };
        assert!(m.evaluate_present(b"prod"));
        assert!(m.evaluate_present(b"stg"));
        assert!(!m.evaluate_present(b"dev"));
    }

    #[test]
    fn line_filter_substring() {
        let f = LineFilter::Substring {
            op: LineFilterOp::Contains,
            finder: Box::new(Finder::new("timeout").into_owned()),
        };
        assert!(f.matches(b"connection timeout at server"));
        assert!(!f.matches(b"connection ok"));
    }

    #[test]
    fn line_filter_regex() {
        let f = LineFilter::Regex {
            op: LineFilterOp::MatchRe,
            regex: Regex::new(r"\d{3}").unwrap(),
        };
        assert!(f.matches(b"code 500"));
        assert!(!f.matches(b"no code"));
    }
}
