//! Decoding of Loki's push protobuf (`PushRequest` → `Stream` → `Entry`)
//! into borrowed records.
//!
//! Wire-level corruption anywhere fails the whole request (`None`), the
//! same contract a generated protobuf decoder gives. Semantic problems
//! are per record or per stream and are counted in `rejected`:
//!
//!   * missing, negative, or out-of-range timestamp → record rejected
//!   * line or structured metadata that is not valid UTF-8 → record rejected
//!   * unparseable labels, or a label value that decodes to invalid
//!     UTF-8 → every entry in that stream rejected
//!
//! Duplicate label names and duplicate metadata names resolve last-wins.

use crate::labels;
use crate::wire::{Reader, Value};

pub struct Record<'a> {
    pub timestamp_ns: u64,
    pub line: &'a [u8],
    pub trace_id: Option<&'a [u8]>,
    pub span_id: Option<&'a [u8]>,
    pub attributes: Vec<(&'a [u8], &'a [u8])>,
}

pub struct Stream<'a> {
    pub labels: labels::Labels<'a>,
    pub records: Vec<Record<'a>>,
}

impl Stream<'_> {
    fn label(&self, name: &str) -> Option<usize> {
        self.labels.iter().position(|(k, _)| *k == name)
    }

    /// Index of the label lifted to `Log.service`.
    pub fn service(&self) -> Option<usize> {
        self.label("service_name").or_else(|| self.label("service"))
    }

    /// Index of the label lifted to `Log.severity_text`.
    pub fn level(&self) -> Option<usize> {
        self.label("level").or_else(|| self.label("detected_level"))
    }
}

pub struct Decoded<'a> {
    pub streams: Vec<Stream<'a>>,
    pub rejected: u64,
}

pub fn decode(buf: &[u8]) -> Option<Decoded<'_>> {
    let mut out = Decoded {
        streams: Vec::new(),
        rejected: 0,
    };
    let mut r = Reader::new(buf);
    while let Some((field, value)) = r.next_field()? {
        if let (1, Value::Bytes(stream)) = (field, value) {
            decode_stream(stream, &mut out)?;
        }
    }
    Some(out)
}

fn decode_stream<'a>(buf: &'a [u8], out: &mut Decoded<'a>) -> Option<()> {
    let mut labels_raw: &[u8] = b"";
    let mut entries = Vec::new();
    let mut r = Reader::new(buf);
    while let Some((field, value)) = r.next_field()? {
        match (field, value) {
            (1, Value::Bytes(l)) => labels_raw = l,
            (2, Value::Bytes(e)) => entries.push(e),
            _ => {}
        }
    }

    // Walk every entry even when the stream will be rejected: wire
    // corruption must still fail the request, whatever the labels say.
    let mut records = Vec::with_capacity(entries.len());
    let mut rejected = 0;
    for e in entries.iter() {
        match decode_entry(e)? {
            Some(record) => records.push(record),
            None => rejected += 1,
        }
    }

    match parse_labels(labels_raw) {
        Some(labels) => {
            out.rejected += rejected;
            out.streams.push(Stream { labels, records });
        }
        None => out.rejected += entries.len() as u64,
    }
    Some(())
}

fn parse_labels(raw: &[u8]) -> Option<labels::Labels<'_>> {
    let parsed = labels::parse(raw)?;
    if !parsed
        .iter()
        .all(|(_, v)| simdutf8::basic::from_utf8(v).is_ok())
    {
        return None;
    }
    Some(last_wins(parsed, |(k, _)| k.as_bytes()))
}

/// Outer `None`: wire corruption. `Some(None)`: a well-formed entry that
/// is rejected on its own.
fn decode_entry(buf: &[u8]) -> Option<Option<Record<'_>>> {
    // `None` covers both "absent" and "out of range"; either rejects.
    let mut timestamp = None;
    let mut line: &[u8] = b"";
    let mut metadata = Vec::new();
    let mut r = Reader::new(buf);
    while let Some((field, value)) = r.next_field()? {
        match (field, value) {
            (1, Value::Bytes(t)) => timestamp = decode_timestamp(t)?,
            (2, Value::Bytes(l)) => line = l,
            (3, Value::Bytes(p)) => metadata.push(decode_pair(p)?),
            _ => {}
        }
    }

    let valid_utf8 = simdutf8::basic::from_utf8(line).is_ok()
        && metadata.iter().all(|(k, v)| {
            simdutf8::basic::from_utf8(k).is_ok() && simdutf8::basic::from_utf8(v).is_ok()
        });
    let timestamp_ns = match (timestamp, valid_utf8) {
        (Some(ts), true) => ts,
        _ => return Some(None),
    };

    let mut trace_id = None;
    let mut span_id = None;
    let mut attributes = Vec::with_capacity(metadata.len());
    for (k, v) in last_wins(metadata, |(k, _)| k) {
        match k {
            b"trace_id" => trace_id = Some(v).filter(|v| !v.is_empty()),
            b"span_id" => span_id = Some(v).filter(|v| !v.is_empty()),
            _ => attributes.push((k, v)),
        }
    }

    Some(Some(Record {
        timestamp_ns,
        line,
        trace_id,
        span_id,
        attributes,
    }))
}

/// `google.protobuf.Timestamp` (int64 seconds, int32 nanos). Outer `None`
/// is wire corruption; inner `None` is an out-of-range instant. Negative
/// values arrive as sign-extended varints and fall out of range naturally.
fn decode_timestamp(buf: &[u8]) -> Option<Option<u64>> {
    let (mut seconds, mut nanos) = (0u64, 0u64);
    let mut r = Reader::new(buf);
    while let Some((field, value)) = r.next_field()? {
        match (field, value) {
            (1, Value::Varint(v)) => seconds = v,
            (2, Value::Varint(v)) => nanos = v,
            _ => {}
        }
    }
    if nanos >= 1_000_000_000 {
        return Some(None);
    }
    Some(
        seconds
            .checked_mul(1_000_000_000)
            .and_then(|s| s.checked_add(nanos)),
    )
}

fn decode_pair(buf: &[u8]) -> Option<(&[u8], &[u8])> {
    let (mut name, mut value): (&[u8], &[u8]) = (b"", b"");
    let mut r = Reader::new(buf);
    while let Some((field, v)) = r.next_field()? {
        match (field, v) {
            (1, Value::Bytes(b)) => name = b,
            (2, Value::Bytes(b)) => value = b,
            _ => {}
        }
    }
    Some((name, value))
}

/// Keep the first position of each key and the last value, matching an
/// Elixir `Map.put` fold. The lists are tiny (a handful of labels), so a
/// quadratic scan beats hashing.
fn last_wins<T>(items: Vec<T>, key: impl Fn(&T) -> &[u8]) -> Vec<T> {
    let mut out: Vec<T> = Vec::with_capacity(items.len());
    for item in items {
        match out.iter().position(|seen| key(seen) == key(&item)) {
            Some(i) => out[i] = item,
            None => out.push(item),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wire::encode;

    struct E<'a> {
        seconds: Option<u64>,
        nanos: u64,
        line: Option<&'a [u8]>,
        meta: Vec<(&'a [u8], &'a [u8])>,
    }

    fn entry(e: &E) -> Vec<u8> {
        let mut out = Vec::new();
        if let Some(s) = e.seconds {
            let mut ts = Vec::new();
            encode::uint(&mut ts, 1, s);
            encode::uint(&mut ts, 2, e.nanos);
            encode::bytes(&mut out, 1, &ts);
        }
        if let Some(l) = e.line {
            encode::bytes(&mut out, 2, l);
        }
        for (k, v) in &e.meta {
            let mut p = Vec::new();
            encode::bytes(&mut p, 1, k);
            encode::bytes(&mut p, 2, v);
            encode::bytes(&mut out, 3, &p);
        }
        out
    }

    fn request(streams: &[(&[u8], Vec<Vec<u8>>)]) -> Vec<u8> {
        let mut out = Vec::new();
        for (labels, entries) in streams {
            let mut s = Vec::new();
            encode::bytes(&mut s, 1, labels);
            for e in entries {
                encode::bytes(&mut s, 2, e);
            }
            encode::bytes(&mut out, 1, &s);
        }
        out
    }

    fn ok(line: &[u8]) -> Vec<u8> {
        entry(&E {
            seconds: Some(1),
            nanos: 5,
            line: Some(line),
            meta: vec![],
        })
    }

    #[test]
    fn decodes_labels_timestamp_and_metadata() {
        let e = entry(&E {
            seconds: Some(1_700_000_000),
            nanos: 42,
            line: Some(b"hello"),
            meta: vec![(b"trace_id", b"abc"), (b"user", b"u1"), (b"span_id", b"")],
        });
        let buf = request(&[(br#"{service_name="api", level="info"}"#, vec![e])]);
        let d = decode(&buf).unwrap();
        assert_eq!(d.rejected, 0);
        let s = &d.streams[0];
        assert_eq!(s.labels[s.service().unwrap()].1.as_ref(), b"api");
        assert_eq!(s.labels[s.level().unwrap()].1.as_ref(), b"info");
        let r = &s.records[0];
        assert_eq!(r.timestamp_ns, 1_700_000_000_000_000_042);
        assert_eq!(r.line, b"hello");
        assert_eq!(r.trace_id, Some(&b"abc"[..]));
        assert_eq!(r.span_id, None);
        assert_eq!(r.attributes, vec![(&b"user"[..], &b"u1"[..])]);
    }

    #[test]
    fn falls_back_to_service_and_detected_level() {
        let buf = request(&[(
            br#"{service="legacy", detected_level="warn"}"#,
            vec![ok(b"x")],
        )]);
        let d = decode(&buf).unwrap();
        let s = &d.streams[0];
        assert_eq!(s.labels[s.service().unwrap()].1.as_ref(), b"legacy");
        assert_eq!(s.labels[s.level().unwrap()].1.as_ref(), b"warn");
    }

    #[test]
    fn missing_line_defaults_to_empty() {
        let e = entry(&E {
            seconds: Some(1),
            nanos: 0,
            line: None,
            meta: vec![],
        });
        let buf = request(&[(b"{}", vec![e])]);
        let d = decode(&buf).unwrap();
        assert_eq!(d.streams[0].records[0].line, b"");
    }

    #[test]
    fn rejects_records_individually() {
        let missing_ts = entry(&E {
            seconds: None,
            nanos: 0,
            line: Some(b"no ts"),
            meta: vec![],
        });
        let bad_nanos = entry(&E {
            seconds: Some(1),
            nanos: 1_000_000_000,
            line: Some(b"x"),
            meta: vec![],
        });
        let negative = entry(&E {
            seconds: Some(u64::MAX),
            nanos: 0,
            line: Some(b"x"),
            meta: vec![],
        });
        let bad_line = entry(&E {
            seconds: Some(1),
            nanos: 0,
            line: Some(&[0xff, 0xfe]),
            meta: vec![],
        });
        let bad_meta = entry(&E {
            seconds: Some(1),
            nanos: 0,
            line: Some(b"x"),
            meta: vec![(b"k", &[0xc3])],
        });
        let buf = request(&[(
            b"{a=\"1\"}",
            vec![
                ok(b"good"),
                missing_ts,
                bad_nanos,
                negative,
                bad_line,
                bad_meta,
            ],
        )]);
        let d = decode(&buf).unwrap();
        assert_eq!(d.rejected, 5);
        assert_eq!(d.streams[0].records.len(), 1);
        assert_eq!(d.streams[0].records[0].line, b"good");
    }

    #[test]
    fn rejects_whole_stream_on_bad_labels() {
        let buf = request(&[
            (b"not labels", vec![ok(b"a"), ok(b"b")]),
            (br#"{k="\xff"}"#, vec![ok(b"c")]),
            (b"{}", vec![ok(b"d")]),
        ]);
        let d = decode(&buf).unwrap();
        assert_eq!(d.rejected, 3);
        assert_eq!(d.streams.len(), 1);
        assert_eq!(d.streams[0].records[0].line, b"d");
    }

    #[test]
    fn duplicates_resolve_last_wins() {
        let e = entry(&E {
            seconds: Some(1),
            nanos: 0,
            line: Some(b"x"),
            meta: vec![
                (b"user", b"first"),
                (b"trace_id", b"t1"),
                (b"user", b"second"),
                (b"trace_id", b"t2"),
            ],
        });
        let buf = request(&[(br#"{a="1", b="2", a="3"}"#, vec![e])]);
        let d = decode(&buf).unwrap();
        let labels: Vec<_> = d.streams[0]
            .labels
            .iter()
            .map(|(k, v)| (*k, v.as_ref()))
            .collect();
        assert_eq!(labels, vec![("a", &b"3"[..]), ("b", &b"2"[..])]);
        let r = &d.streams[0].records[0];
        assert_eq!(r.attributes, vec![(&b"user"[..], &b"second"[..])]);
        assert_eq!(r.trace_id, Some(&b"t2"[..]));
    }

    #[test]
    fn wire_corruption_fails_the_request() {
        let mut buf = request(&[(b"{}", vec![ok(b"hello world")])]);
        buf.truncate(buf.len() - 3);
        assert!(decode(&buf).is_none());
        // Corruption inside a stream whose labels are invalid still fails.
        let mut bad_entry = ok(b"x");
        bad_entry.push(0x0b);
        assert!(decode(&request(&[(b"nope", vec![bad_entry])])).is_none());
    }

    #[test]
    fn empty_request_and_empty_stream() {
        assert_eq!(decode(b"").unwrap().streams.len(), 0);
        let buf = request(&[(b"{}", vec![])]);
        let d = decode(&buf).unwrap();
        assert_eq!((d.streams.len(), d.rejected), (1, 0));
    }

    // Deterministic mutation fuzzing: random byte flips, truncations and
    // insertions over valid requests. The decoder must never panic, loop,
    // or read out of bounds; any result (Some or None) is acceptable.
    #[test]
    fn survives_mutated_inputs() {
        let escaped = r#"{k="~u00e9~x41~101"}"#.replace('~', "\\");
        let seed_inputs = [
            request(&[(
                br#"{service_name="api", level="info"}"#,
                vec![ok(b"hello"), ok(b"world")],
            )]),
            request(&[
                (
                    escaped.as_bytes(),
                    vec![entry(&E {
                        seconds: Some(9),
                        nanos: 9,
                        line: Some(b"m"),
                        meta: vec![(b"trace_id", b"abc")],
                    })],
                ),
                (b"{}", vec![ok(b"")]),
            ]),
        ];
        let mut state: u64 = 0x9e37_79b9_7f4a_7c15;
        let mut rand = move || {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state
        };
        for _ in 0..200_000 {
            let mut buf = seed_inputs[(rand() % 2) as usize].clone();
            for _ in 0..(1 + rand() % 4) {
                let len = buf.len().max(1);
                let at = (rand() as usize) % len;
                match rand() % 4 {
                    0 if !buf.is_empty() => buf[at] = rand() as u8,
                    1 => buf.truncate(at),
                    2 => buf.insert(at.min(buf.len()), rand() as u8),
                    _ if !buf.is_empty() => buf[at] ^= 1 << (rand() % 8),
                    _ => {}
                }
            }
            let _ = decode(&buf);
        }
    }
}
