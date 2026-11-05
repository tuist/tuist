//! Validate the versioned typed-attribute envelope without BEAM terms.
//! Absent/null metadata is explicitly legacy, never reconstructed from strings.
use crate::json_read::{Fallback, Parser, RawFields, Res, MAX_DEPTH};
use std::borrow::Cow;

#[cfg(test)]
fn object(raw: &[u8]) -> Res<RawFields<'_>> {
    let mut parser = Parser::new(raw);
    let value = parser.raw_object()?;
    parser.ws();
    parser.end()?;
    Ok(value)
}
fn array(raw: &[u8]) -> Res<Vec<&[u8]>> {
    let mut parser = Parser::new(raw);
    let value = parser.raw_array()?;
    parser.ws();
    parser.end()?;
    Ok(value)
}
fn string(raw: &[u8]) -> Res<Cow<'_, [u8]>> {
    let mut parser = Parser::new(raw);
    let value = parser.string()?;
    parser.ws();
    parser.end()?;
    Ok(value)
}
fn field<'a>(fields: &RawFields<'a>, name: &[u8]) -> Res<&'a [u8]> {
    fields
        .iter()
        .find(|(key, _)| key.as_ref() == name)
        .map(|(_, value)| *value)
        .ok_or(Fallback)
}

pub fn validate(payload: &[u8]) -> Res<()> {
    validated_fields(payload).map(|_| ())
}
/// The payload's top-level fields once its typed envelope is valid, in one
/// pass: the envelope is validated while it is parsed, as strictly as
/// re-parsing each level would (same syntax and nesting limits), because this
/// is the per-row cost of every native trace scan.
pub(crate) fn validated_fields(payload: &[u8]) -> Res<RawFields<'_>> {
    validated_parts(payload).map(|(fields, _)| fields)
}
/// `validated_fields/1` plus the typed envelope's members when it is not
/// null, so callers that read them need not parse the envelope again.
pub(crate) type Parts<'a> = (RawFields<'a>, Option<Envelope<'a>>);
/// A validated typed envelope: its six members and how many resource and
/// span attributes it holds (distinct keys).
pub(crate) struct Envelope<'a> {
    pub(crate) members: RawFields<'a>,
    pub(crate) resource: usize,
    pub(crate) span: usize,
}
pub(crate) fn validated_parts(payload: &[u8]) -> Res<Parts<'_>> {
    parts(Parser::new(payload), payload)
}
/// `validated_parts/1` for text already known to be UTF-8.
pub(crate) fn validated_parts_utf8(payload: &str) -> Res<Parts<'_>> {
    parts(Parser::new_utf8(payload), payload.as_bytes())
}
fn parts<'a>(mut p: Parser<'a>, payload: &'a [u8]) -> Res<Parts<'a>> {
    p.ws();
    p.expect(b'{')?;
    let mut fields = Vec::new();
    let mut typed = None;
    if p.object_open()? {
        loop {
            let key = p.string()?;
            p.colon()?;
            let start = p.position();
            if key.as_ref() != b"otlp" {
                p.skip_value()?;
            } else if typed.is_some() {
                return Err(Fallback);
            } else if p.peek()? == b'n' {
                p.skip_value()?;
                typed = Some(None);
            } else {
                typed = Some(Some(envelope(&mut p, payload)?));
            }
            fields.push((key, &payload[start..p.position()]));
            if !p.object_next()? {
                break;
            }
        }
    }
    p.ws();
    p.end()?;
    let Some(Some((events, links, envelope))) = typed else {
        return Ok((fields, None));
    };
    if events != array(field(&fields, b"events")?)?.len()
        || links != array(field(&fields, b"links")?)?.len()
    {
        return Err(Fallback);
    }
    Ok((fields, Some(envelope)))
}
// Container nesting below the payload object, counted as the parser does.
fn open(p: &mut Parser<'_>, level: usize, c: u8) -> Res<()> {
    if level > MAX_DEPTH {
        return Err(Fallback);
    }
    p.ws();
    p.expect(c)
}
/// Exactly the six envelope members, version 1; returns the event and link
/// owner counts and the members.
fn envelope<'a>(p: &mut Parser<'a>, payload: &'a [u8]) -> Res<(usize, usize, Envelope<'a>)> {
    open(p, 1, b'{')?;
    let (mut seen, mut counts) = (0u8, (0, 0));
    let mut members = Vec::with_capacity(6);
    let (mut resource, mut span) = (0, 0);
    if p.object_open()? {
        loop {
            let key = p.string()?;
            p.colon()?;
            let start = p.position();
            let bit = match key.as_ref() {
                b"version" => 1,
                b"resource" => 2,
                b"scope" => 4,
                b"attributes" => 8,
                b"events" => 16,
                b"links" => 32,
                _ => return Err(Fallback),
            };
            if seen & bit != 0 {
                return Err(Fallback);
            }
            seen |= bit;
            match bit {
                1 if p.skip_value()? != b"1" => return Err(Fallback),
                1 => {}
                16 => counts.0 = owners(p)?,
                32 => counts.1 = owners(p)?,
                2 => resource = attributes(p, 0, 2)?,
                8 => span = attributes(p, 0, 2)?,
                _ => {
                    attributes(p, 0, 2)?;
                }
            }
            members.push((key, &payload[start..p.position()]));
            if !p.object_next()? {
                break;
            }
        }
    }
    if seen != 63 {
        return Err(Fallback);
    }
    let envelope = Envelope {
        members,
        resource,
        span,
    };
    Ok((counts.0, counts.1, envelope))
}
fn owners(p: &mut Parser<'_>) -> Res<usize> {
    open(p, 2, b'[')?;
    let mut count = 0;
    if p.array_rest()? {
        loop {
            attributes(p, 0, 3)?;
            count += 1;
            if !p.array_next()? {
                break;
            }
        }
    }
    Ok(count)
}
/// An array of `{"key": nonempty string, "value": AnyValue}` pairs with
/// distinct keys; returns how many.
fn attributes<'a>(p: &mut Parser<'a>, depth: usize, level: usize) -> Res<usize> {
    open(p, level, b'[')?;
    let mut keys: Vec<Cow<'a, [u8]>> = Vec::new();
    if p.array_rest()? {
        loop {
            open(p, level + 1, b'{')?;
            if !p.object_open()? {
                return Err(Fallback);
            }
            let (mut key, mut value) = (None, false);
            loop {
                let name = p.string()?;
                p.colon()?;
                match name.as_ref() {
                    b"key" if key.is_none() => {
                        let k = p.string()?;
                        if k.is_empty() {
                            return Err(Fallback);
                        }
                        key = Some(k);
                    }
                    b"value" if !value => {
                        any_value(p, depth, level + 2)?;
                        value = true;
                    }
                    _ => return Err(Fallback),
                }
                if !p.object_next()? {
                    break;
                }
            }
            if !value {
                return Err(Fallback);
            }
            keys.push(key.ok_or(Fallback)?);
            if !p.array_next()? {
                break;
            }
        }
    }
    keys.sort_unstable();
    if keys.windows(2).any(|w| w[0] == w[1]) {
        return Err(Fallback);
    }
    Ok(keys.len())
}
/// `{}` or exactly one canonical typed member.
fn any_value(p: &mut Parser<'_>, depth: usize, level: usize) -> Res<()> {
    if depth > 128 {
        return Err(Fallback);
    }
    open(p, level, b'{')?;
    if !p.object_open()? {
        return Ok(());
    }
    let key = p.string()?;
    p.colon()?;
    match key.as_ref() {
        b"stringValue" => {
            p.string()?;
        }
        b"boolValue" => {
            if !matches!(p.skip_value()?, b"true" | b"false") {
                return Err(Fallback);
            }
        }
        b"intValue" => integer(&p.string()?)?,
        b"doubleValue" => {
            double(p.skip_value()?)?;
        }
        b"bytesValue" => {
            if !base64(&p.string()?) {
                return Err(Fallback);
            }
        }
        b"arrayValue" => values(p, level + 1, |p| {
            open(p, level + 2, b'[')?;
            if p.array_rest()? {
                loop {
                    any_value(p, depth + 1, level + 3)?;
                    if !p.array_next()? {
                        break;
                    }
                }
            }
            Ok(())
        })?,
        b"kvlistValue" => values(p, level + 1, |p| {
            attributes(p, depth + 1, level + 2).map(|_| ())
        })?,
        _ => return Err(Fallback),
    }
    if p.object_next()? {
        return Err(Fallback);
    }
    Ok(())
}
/// `{"values": ...}` with nothing else.
fn values<'a>(
    p: &mut Parser<'a>,
    level: usize,
    inner: impl FnOnce(&mut Parser<'a>) -> Res<()>,
) -> Res<()> {
    open(p, level, b'{')?;
    if !p.object_open()? || p.string()?.as_ref() != b"values" {
        return Err(Fallback);
    }
    p.colon()?;
    inner(p)?;
    if p.object_next()? {
        return Err(Fallback);
    }
    Ok(())
}
/// Canonical int64 spelling: an optional minus, no leading zeros, no `-0`.
fn integer(value: &[u8]) -> Res<()> {
    let value = std::str::from_utf8(value).map_err(|_| Fallback)?;
    let number: i64 = value.parse().map_err(|_| Fallback)?;
    let digits = value.strip_prefix('-').unwrap_or(value);
    if value.starts_with('+')
        || (digits.len() > 1 && digits.starts_with('0'))
        || (number == 0 && value != "0")
    {
        return Err(Fallback);
    }
    Ok(())
}
// OTLP's three quoted non-finite spellings retain type without BEAM floats.
// Finite stored doubles remain JSON numbers; do not accept arbitrary strings.
pub(crate) fn double(raw: &[u8]) -> Res<f64> {
    if raw.first() == Some(&b'"') {
        return match string(raw)?.as_ref() {
            b"NaN" => Ok(f64::NAN),
            b"Infinity" => Ok(f64::INFINITY),
            b"-Infinity" => Ok(f64::NEG_INFINITY),
            _ => Err(Fallback),
        };
    }
    let key = crate::trace_sort_key::key(raw)?;
    if !matches!(key.first(), Some(3 | 4)) {
        return Err(Fallback);
    }
    let value: f64 = std::str::from_utf8(raw)
        .map_err(|_| Fallback)?
        .parse()
        .map_err(|_| Fallback)?;
    if value.is_finite() {
        Ok(value)
    } else {
        Err(Fallback)
    }
}

fn digit(byte: u8) -> Option<u8> {
    match byte {
        b'A'..=b'Z' => Some(byte - b'A'),
        b'a'..=b'z' => Some(byte - b'a' + 26),
        b'0'..=b'9' => Some(byte - b'0' + 52),
        b'+' => Some(62),
        b'/' => Some(63),
        _ => None,
    }
}
fn base64(value: &[u8]) -> bool {
    if !value.len().is_multiple_of(4) {
        return false;
    }
    let padding = value.iter().rev().take_while(|&&byte| byte == b'=').count();
    if padding > 2 {
        return false;
    }
    let digits = &value[..value.len() - padding];
    if !digits.iter().all(|&byte| digit(byte).is_some()) {
        return false;
    }
    match padding {
        1 => digits
            .last()
            .and_then(|&byte| digit(byte))
            .is_some_and(|value| value & 3 == 0),
        2 => digits
            .last()
            .and_then(|&byte| digit(byte))
            .is_some_and(|value| value & 15 == 0),
        _ => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn legacy_and_closed_typed_envelopes() {
        assert!(validate(br#"{"attributes":{"bytes":"AQ=="}}"#).is_ok());
        let valid = br#"{"events":[],"links":[],"otlp":{"version":1,"resource":[],"scope":[],"attributes":[{"key":"b","value":{"bytesValue":"AQ=="}},{"key":"s","value":{"stringValue":"AQ=="}}],"events":[],"links":[]}}"#;
        assert!(validate(valid).is_ok());
        for metadata in ["null", "[]", "1", r#"{"version":2}"#] {
            let value = format!(r#"{{"otlp":{metadata}}}"#);
            assert_eq!(validate(value.as_bytes()).is_ok(), metadata == "null");
        }
    }
    #[test]
    fn canonical_values_only() {
        for value in [
            r#"{"bytesValue":"AR=="}"#,
            r#"{"intValue":"9223372036854775808"}"#,
            r#"{"intValue":"01"}"#,
            r#"{"doubleValue":"nan"}"#,
            r#"{"doubleValue":"+Inf"}"#,
            r#"{"doubleValue":"1.0"}"#,
            r#"{"boolValue":0}"#,
            r#"{"stringValue":"s","bytesValue":"AQ=="}"#,
        ] {
            assert!(whole(value.as_bytes(), |p| any_value(p, 0, 1)).is_err());
        }
        assert!(
            whole(br#"{"intValue":"-9223372036854775808"}"#, |p| any_value(
                p, 0, 1
            ))
            .is_ok()
        );
        assert!(whole(br#"{"doubleValue":-0.0}"#, |p| any_value(p, 0, 1)).is_ok());
        for spelling in ["NaN", "Infinity", "-Infinity"] {
            assert!(whole(
                format!(r#"{{"doubleValue":"{spelling}"}}"#).as_bytes(),
                |p| any_value(p, 0, 1)
            )
            .is_ok());
        }
        assert!(double(br#""NaN""#).unwrap().is_nan());
        assert_eq!(double(br#""Infinity""#).unwrap(), f64::INFINITY);
        assert_eq!(double(br#""-Infinity""#).unwrap(), f64::NEG_INFINITY);
        assert_eq!(double(b"-0.0").unwrap().to_bits(), (-0.0f64).to_bits());
        assert!(
            whole(br#"[{"key":"a","value":{}},{"key":"a","value":{}}]"#, |p| {
                attributes(p, 0, 1).map(|_| ())
            })
            .is_err()
        );
    }
    fn whole<'a>(raw: &'a [u8], f: impl FnOnce(&mut Parser<'a>) -> Res<()>) -> Res<()> {
        let mut p = Parser::new(raw);
        f(&mut p)?;
        p.ws();
        p.end()
    }

    /// The validator as it was before the streaming pass, re-parsing each
    /// level: the oracle for `streaming_validation_matches_reparsing`.
    mod reference {
        use super::super::{array, base64, double, field, object, string};
        use crate::json_read::{Fallback, RawFields, Res};
        use std::collections::BTreeSet;
        pub(crate) fn validated_fields(payload: &[u8]) -> Res<RawFields<'_>> {
            let fields = object(payload)?;
            if fields
                .iter()
                .filter(|(key, _)| key.as_ref() == b"otlp")
                .count()
                > 1
            {
                return Err(Fallback);
            }
            let Some((_, metadata)) = fields.iter().find(|(key, _)| key.as_ref() == b"otlp") else {
                return Ok(fields);
            };
            if *metadata == b"null" {
                return Ok(fields);
            }
            let metadata = object(metadata)?;
            if metadata.len() != 6 || field(&metadata, b"version")? != b"1" {
                return Err(Fallback);
            }
            for name in [b"resource".as_slice(), b"scope", b"attributes"] {
                attributes(field(&metadata, name)?, 0)?;
            }
            for name in [b"events".as_slice(), b"links"] {
                let owners = array(field(&metadata, name)?)?;
                if owners.len() != array(field(&fields, name)?)?.len() {
                    return Err(Fallback);
                }
                for owner in owners {
                    attributes(owner, 0)?;
                }
            }
            Ok(fields)
        }
        fn attributes(raw: &[u8], depth: usize) -> Res<()> {
            let mut keys = BTreeSet::new();
            for pair in array(raw)? {
                let pair = object(pair)?;
                if pair.len() != 2 {
                    return Err(Fallback);
                }
                let key = string(field(&pair, b"key")?)?;
                if key.is_empty() || !keys.insert(key.into_owned()) {
                    return Err(Fallback);
                }
                any_value(field(&pair, b"value")?, depth)?;
            }
            Ok(())
        }
        fn any_value(raw: &[u8], depth: usize) -> Res<()> {
            if depth > 128 {
                return Err(Fallback);
            }
            let fields = object(raw)?;
            if fields.is_empty() {
                return Ok(());
            }
            if fields.len() != 1 {
                return Err(Fallback);
            }
            let (key, value) = &fields[0];
            match key.as_ref() {
                b"stringValue" => {
                    string(value)?;
                }
                b"boolValue" if *value == b"true" || *value == b"false" => {}
                b"intValue" => {
                    let value = string(value)?;
                    let value = std::str::from_utf8(&value).map_err(|_| Fallback)?;
                    let number: i64 = value.parse().map_err(|_| Fallback)?;
                    if number.to_string() != value {
                        return Err(Fallback);
                    }
                }
                b"doubleValue" => {
                    double(value)?;
                }
                b"bytesValue" => {
                    if !base64(&string(value)?) {
                        return Err(Fallback);
                    }
                }
                b"arrayValue" => {
                    let owner = object(value)?;
                    if owner.len() != 1 {
                        return Err(Fallback);
                    }
                    for value in array(field(&owner, b"values")?)? {
                        any_value(value, depth + 1)?;
                    }
                }
                b"kvlistValue" => {
                    let owner = object(value)?;
                    if owner.len() != 1 {
                        return Err(Fallback);
                    }
                    attributes(field(&owner, b"values")?, depth + 1)?;
                }
                _ => return Err(Fallback),
            }
            Ok(())
        }
    }

    // Deterministic generator of near-valid payloads: every member may be
    // dropped, duplicated, renamed or given the wrong type, so both
    // validators see accepting and rejecting inputs at every level.
    struct Gen(u64);
    impl Gen {
        fn next(&mut self) -> u64 {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            self.0
        }
        fn one(&mut self, n: u64) -> bool {
            self.next().is_multiple_of(n)
        }
        fn pick<'s>(&mut self, items: &[&'s str]) -> &'s str {
            items[(self.next() % items.len() as u64) as usize]
        }
        fn members(&mut self, members: Vec<(String, String)>) -> String {
            let mut out: Vec<String> = Vec::new();
            for (key, value) in members {
                if self.one(30) {
                    continue;
                }
                let key = if self.one(40) {
                    self.pick(&["x", "", "Key", "values"]).to_owned()
                } else {
                    key
                };
                out.push(format!("\"{key}\":{value}"));
                if self.one(40) {
                    out.push(format!("\"{key}\":{value}"));
                }
            }
            if self.one(15) && out.len() > 1 {
                let n = out.len();
                out.swap(0, n - 1);
            }
            format!("{{{}}}", out.join(if self.one(10) { " , " } else { "," }))
        }
        fn any(&mut self, depth: usize) -> String {
            let typed = match self.next() % 12 {
                0 => return "{}".to_owned(),
                1 => return self.pick(&["[]", "null", "\"s\"", "1"]).to_owned(),
                2 => (
                    "stringValue",
                    self.pick(&["\"a\"", "\"\\u00e9\"", "1", "null"]).to_owned(),
                ),
                3 => (
                    "boolValue",
                    self.pick(&["true", "false", "0", "\"true\""]).to_owned(),
                ),
                4 => (
                    "intValue",
                    self.pick(&[
                        "\"1\"",
                        "\"-12\"",
                        "\"0\"",
                        "\"-0\"",
                        "\"+1\"",
                        "\"01\"",
                        "\"9223372036854775808\"",
                        "1",
                    ])
                    .to_owned(),
                ),
                5 => (
                    "doubleValue",
                    self.pick(&["1.5", "-0.0", "\"NaN\"", "\"nan\"", "1e400", "\"1\""])
                        .to_owned(),
                ),
                6 => (
                    "bytesValue",
                    self.pick(&["\"AQ==\"", "\"AR==\"", "\"\"", "\"A\"", "1"])
                        .to_owned(),
                ),
                7 | 8 if depth < 4 => {
                    let items: Vec<String> =
                        (0..self.next() % 3).map(|_| self.any(depth + 1)).collect();
                    (
                        "arrayValue",
                        self.members(vec![("values".into(), format!("[{}]", items.join(",")))]),
                    )
                }
                9 | 10 if depth < 4 => {
                    let inner = self.attributes(depth + 1);
                    ("kvlistValue", self.members(vec![("values".into(), inner)]))
                }
                _ => (self.pick(&["stringValue", "fooValue"]), "\"v\"".to_owned()),
            };
            let mut members = vec![(typed.0.to_owned(), typed.1)];
            if self.one(25) {
                members.push(("boolValue".into(), "true".into()));
            }
            self.members(members)
        }
        fn attributes(&mut self, depth: usize) -> String {
            if self.one(40) {
                return self.pick(&["{}", "null", "[1]"]).to_owned();
            }
            let pairs: Vec<String> = (0..self.next() % 4)
                .map(|_| {
                    let key = self
                        .pick(&["\"a\"", "\"b\"", "\"c\"", "\"\"", "\"\\u0061\"", "1"])
                        .to_owned();
                    let value = self.any(depth);
                    self.members(vec![("key".into(), key), ("value".into(), value)])
                })
                .collect();
            format!("[ {} ]", pairs.join(","))
        }
        fn payload(&mut self) -> String {
            let (events, links) = (self.next() % 3, self.next() % 2);
            let list = |n: u64, s: &mut Self| -> String {
                let n = if s.one(20) { n + 1 } else { n };
                let owners: Vec<String> = (0..n).map(|_| s.attributes(0)).collect();
                format!("[{}]", owners.join(","))
            };
            let typed = match self.next() % 8 {
                0 => "null".to_owned(),
                1 => self.pick(&["[]", "1", "{}"]).to_owned(),
                _ => {
                    let members = vec![
                        (
                            "version".to_owned(),
                            self.pick(&["1", "1", "1", "2", "1.0", "\"1\""]).to_owned(),
                        ),
                        ("resource".to_owned(), self.attributes(0)),
                        ("scope".to_owned(), self.attributes(0)),
                        ("attributes".to_owned(), self.attributes(0)),
                        ("events".to_owned(), list(events, self)),
                        ("links".to_owned(), list(links, self)),
                    ];
                    self.members(members)
                }
            };
            let plain = |n: u64| format!("[{}]", vec!["{}"; n as usize].join(","));
            self.members(vec![
                ("name".into(), "\"n\"".into()),
                ("events".into(), plain(events)),
                ("links".into(), plain(links)),
                ("otlp".into(), typed),
            ])
        }
    }

    #[test]
    fn streaming_validation_matches_reparsing() {
        let mut generator = Gen(0x9e37_79b9_7f4a_7c15);
        let (mut accepted, mut rejected) = (0, 0);
        for _ in 0..200_000 {
            let payload = generator.payload();
            let expected = reference::validated_fields(payload.as_bytes()).is_ok();
            assert_eq!(validate(payload.as_bytes()).is_ok(), expected, "{payload}");
            if expected {
                accepted += 1;
            } else {
                rejected += 1;
            }
        }
        assert!(
            accepted > 10_000 && rejected > 10_000,
            "{accepted} {rejected}"
        );
    }

    #[test]
    fn streaming_validation_keeps_the_nesting_limit() {
        // Values nested through arrayValue and kvlistValue around the
        // parser's 256-container limit and the 128-value depth limit.
        let mut outcomes = std::collections::BTreeSet::new();
        for n in 60..140 {
            for kv in [false, true] {
                let mut value = r#"{"stringValue":"x"}"#.to_owned();
                for _ in 0..n {
                    value = if kv {
                        format!(r#"{{"kvlistValue":{{"values":[{{"key":"k","value":{value}}}]}}}}"#)
                    } else {
                        format!(r#"{{"arrayValue":{{"values":[{value}]}}}}"#)
                    };
                }
                let payload = format!(
                    r#"{{"events":[],"links":[],"otlp":{{"version":1,"resource":[{{"key":"a","value":{value}}}],"scope":[],"attributes":[],"events":[],"links":[]}}}}"#
                );
                let expected = reference::validated_fields(payload.as_bytes()).is_ok();
                assert_eq!(validate(payload.as_bytes()).is_ok(), expected, "{n} {kv}");
                outcomes.insert((kv, expected));
            }
        }
        assert_eq!(outcomes.len(), 4);
    }
}
