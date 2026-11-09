//! Prometheus exemplars: the remote-write wire messages, the compact byte
//! form stored per metric row, and `%Pulse.Record.Exemplar{}`.
//!
//! ```proto
//! // Remote Write 1.0
//! message Exemplar { repeated Label labels = 1; double value = 2; int64 timestamp = 3; }
//! // Remote Write 2.0: labels are name/value pairs of symbol references
//! message Exemplar { repeated uint32 labels_refs = 1; double value = 2; int64 timestamp = 3; }
//! ```
//!
//! As in Prometheus, an exemplar's label names and values may hold at most 128
//! UTF-8 characters in total; longer or invalid label sets are dropped.

use crate::wire::{Reader, Value};
use rustler::{Encoder, Env, Term};

pub const MAX_LABEL_SET_LENGTH: usize = 128;

#[derive(Debug, Clone, PartialEq)]
pub struct Exemplar<'a> {
    pub labels: Vec<(&'a [u8], &'a [u8])>,
    pub value: f64,
    pub timestamp_ms: i64,
}

mod atoms {
    rustler::atoms! {
        struct_key = "__struct__",
        exemplar = "Elixir.Pulse.Record.Exemplar",
        labels,
        value,
        timestamp_ns,
    }
}

fn valid(labels: &[(&[u8], &[u8])]) -> bool {
    let mut chars = 0;
    for (name, value) in labels {
        let (Ok(name), Ok(value)) = (std::str::from_utf8(name), std::str::from_utf8(value)) else {
            return false;
        };
        if name.is_empty() {
            return false;
        }
        chars += name.chars().count() + value.chars().count();
    }
    chars <= MAX_LABEL_SET_LENGTH
}

fn finish<'a>(
    mut labels: Vec<(&'a [u8], &'a [u8])>,
    value: f64,
    timestamp_ms: i64,
) -> Option<Exemplar<'a>> {
    labels.sort_by(|a, b| a.0.cmp(b.0));
    let unique = labels.windows(2).all(|pair| pair[0].0 != pair[1].0);
    (unique && valid(&labels)).then_some(Exemplar {
        labels,
        value,
        timestamp_ms,
    })
}

/// A Remote Write 1.0 exemplar; `None` when malformed or invalid.
pub fn decode_v1(bytes: &[u8]) -> Option<Exemplar<'_>> {
    let mut labels = Vec::new();
    let (mut value, mut timestamp_ms) = (0.0, 0);
    let mut reader = Reader::new(bytes);
    while let Some((field, v)) = reader.next_field()? {
        match (field, v) {
            (2, Value::Fixed64(b)) => value = f64::from_le_bytes(b),
            (1, Value::Bytes(pair)) => {
                let (mut name, mut value): (&[u8], &[u8]) = (&[], &[]);
                let mut inner = Reader::new(pair);
                while let Some((field, v)) = inner.next_field()? {
                    match (field, v) {
                        (1, Value::Bytes(b)) => name = b,
                        (2, Value::Bytes(b)) => value = b,
                        _ => {}
                    }
                }
                labels.push((name, value));
            }
            (3, Value::Varint(t)) => timestamp_ms = t as i64,
            _ => {}
        }
    }
    finish(labels, value, timestamp_ms)
}

/// A Remote Write 2.0 exemplar resolved through the request's symbols.
pub fn decode_v2<'a>(bytes: &'a [u8], symbols: &[&'a [u8]]) -> Option<Exemplar<'a>> {
    let mut refs = Vec::new();
    let (mut value, mut timestamp_ms) = (0.0, 0);
    let mut reader = Reader::new(bytes);
    while let Some((field, v)) = reader.next_field()? {
        match (field, v) {
            (2, Value::Fixed64(b)) => value = f64::from_le_bytes(b),
            (1, Value::Bytes(packed)) => {
                let mut inner = Reader::new(packed);
                while !inner.is_empty() {
                    refs.push(inner.read_varint()?);
                }
            }
            (1, Value::Varint(r)) => refs.push(r),
            (3, Value::Varint(t)) => timestamp_ms = t as i64,
            _ => {}
        }
    }
    if refs.len() % 2 != 0 {
        return None;
    }
    let symbol = |r: u64| symbols.get(usize::try_from(r).ok()?).copied();
    let labels = refs
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| Some((symbol(pair[0])?, symbol(pair[1])?)))
        .collect::<Option<Vec<_>>>()?;
    finish(labels, value, timestamp_ms)
}

// -- Stored bytes ------------------------------------------------------------

const VERSION: u8 = 1;

fn put_varint(out: &mut Vec<u8>, mut v: u64) {
    while v >= 0x80 {
        out.push((v as u8) | 0x80);
        v >>= 7;
    }
    out.push(v as u8);
}

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

/// One row's exemplars: a version byte, a count, then per exemplar its
/// nanosecond timestamp, value and length-prefixed label pairs.
/// An exemplar's owned label pairs, value and nanosecond timestamp.
pub type Owned = (Vec<(Vec<u8>, Vec<u8>)>, f64, i64);

pub fn to_bytes(exemplars: &[Owned]) -> Vec<u8> {
    let mut out = vec![VERSION];
    put_varint(&mut out, exemplars.len() as u64);
    for (labels, value, timestamp_ns) in exemplars {
        out.extend_from_slice(&timestamp_ns.to_le_bytes());
        out.extend_from_slice(&value.to_le_bytes());
        put_varint(&mut out, labels.len() as u64);
        for (name, value) in labels {
            put_varint(&mut out, name.len() as u64);
            out.extend_from_slice(name);
            put_varint(&mut out, value.len() as u64);
            out.extend_from_slice(value);
        }
    }
    out
}

type Stored<'a> = (Vec<(&'a [u8], &'a [u8])>, f64, i64);

pub fn from_bytes(bytes: &[u8]) -> Option<Vec<Stored<'_>>> {
    if *bytes.first()? != VERSION {
        return None;
    }
    let mut pos = 1;
    let n = usize::try_from(varint(bytes, &mut pos)?).ok()?;
    let mut out = Vec::with_capacity(n.min(bytes.len()));
    for _ in 0..n {
        let timestamp_ns = i64::from_le_bytes(bytes.get(pos..pos + 8)?.try_into().ok()?);
        let value = f64::from_le_bytes(bytes.get(pos + 8..pos + 16)?.try_into().ok()?);
        pos += 16;
        let pairs = usize::try_from(varint(bytes, &mut pos)?).ok()?;
        let mut labels = Vec::with_capacity(pairs.min(bytes.len()));
        for _ in 0..pairs {
            let mut slice = || -> Option<&[u8]> {
                let len = usize::try_from(varint(bytes, &mut pos)?).ok()?;
                let end = pos.checked_add(len).filter(|end| *end <= bytes.len())?;
                let s = &bytes[pos..end];
                pos = end;
                Some(s)
            };
            let name = slice()?;
            let value = slice()?;
            labels.push((name, value));
        }
        if !valid(&labels) || labels.windows(2).any(|pair| pair[0].0 >= pair[1].0) {
            return None;
        }
        out.push((labels, value, timestamp_ns));
    }
    (pos == bytes.len()).then_some(out)
}

// -- Terms -------------------------------------------------------------------

pub fn to_term<'a>(
    env: Env<'a>,
    labels: &[(&[u8], &[u8])],
    value: f64,
    timestamp_ns: i64,
) -> Term<'a> {
    let names: Vec<Term> = labels.iter().map(|(n, _)| bytes_term(env, n)).collect();
    let values: Vec<Term> = labels.iter().map(|(_, v)| bytes_term(env, v)).collect();
    let labels = Term::map_from_arrays(env, &names, &values).expect("unique exemplar labels");
    let keys = [
        atoms::struct_key().encode(env),
        atoms::labels().encode(env),
        atoms::value().encode(env),
        atoms::timestamp_ns().encode(env),
    ];
    let fields = [
        atoms::exemplar().encode(env),
        labels,
        crate::metric_value::encode(env, if value.is_nan() { f64::NAN } else { value }),
        timestamp_ns.encode(env),
    ];
    Term::map_from_arrays(env, &keys, &fields).expect("distinct keys")
}

fn bytes_term<'a>(env: Env<'a>, bytes: &[u8]) -> Term<'a> {
    let mut binary = rustler::NewBinary::new(env, bytes.len());
    binary.as_mut_slice().copy_from_slice(bytes);
    rustler::Binary::from(binary).encode(env)
}

/// Owned label pairs, value and nanosecond timestamp of an exemplar term.
pub fn from_term(term: Term<'_>) -> Option<Owned> {
    let env = term.get_env();
    if term.map_get(atoms::struct_key().encode(env)).ok()? != atoms::exemplar().encode(env) {
        return None;
    }
    let labels_term = term.map_get(atoms::labels().encode(env)).ok()?;
    let mut labels = Vec::new();
    for (k, v) in rustler::MapIterator::new(labels_term)? {
        let name: rustler::Binary = k.decode().ok()?;
        let value: rustler::Binary = v.decode().ok()?;
        labels.push((name.as_slice().to_vec(), value.as_slice().to_vec()));
    }
    labels.sort();
    let borrowed: Vec<(&[u8], &[u8])> = labels
        .iter()
        .map(|(n, v)| (n.as_slice(), v.as_slice()))
        .collect();
    if !valid(&borrowed) {
        return None;
    }
    let value = crate::metric_value::decode(term.map_get(atoms::value().encode(env)).ok()?).ok()?;
    let timestamp_ns = term
        .map_get(atoms::timestamp_ns().encode(env))
        .ok()?
        .decode()
        .ok()?;
    Some((labels, value, timestamp_ns))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bytes_field(field: u8, bytes: &[u8]) -> Vec<u8> {
        let mut out = vec![(field << 3) | 2];
        put_varint(&mut out, bytes.len() as u64);
        out.extend_from_slice(bytes);
        out
    }

    fn v1(labels: &[(&[u8], &[u8])], value: f64, ts: u8) -> Vec<u8> {
        let mut out = Vec::new();
        for (n, v) in labels {
            out.extend(bytes_field(
                1,
                &[bytes_field(1, n), bytes_field(2, v)].concat(),
            ));
        }
        out.push(0x11);
        out.extend(value.to_le_bytes());
        out.extend([0x18, ts]);
        out
    }

    #[test]
    fn decodes_both_wire_forms_and_round_trips_stored_bytes() {
        let wire = v1(&[(b"trace_id", b"abc"), (b"span_id", b"1")], 2.5, 7);
        let e = decode_v1(&wire).unwrap();
        assert_eq!(
            e.labels,
            vec![
                (&b"span_id"[..], &b"1"[..]),
                (&b"trace_id"[..], &b"abc"[..])
            ]
        );
        assert_eq!((e.value, e.timestamp_ms), (2.5, 7));

        let symbols: Vec<&[u8]> = vec![b"", b"trace_id", b"abc"];
        let mut v2 = bytes_field(1, &[1, 2]);
        v2.push(0x11);
        v2.extend(1.5f64.to_le_bytes());
        v2.extend([0x18, 9]);
        let e = decode_v2(&v2, &symbols).unwrap();
        assert_eq!((e.labels.len(), e.value, e.timestamp_ms), (1, 1.5, 9));
        let unresolvable = bytes_field(1, &[1, 9]);
        assert!(decode_v2(&unresolvable, &symbols).is_none());

        let owned = vec![(
            vec![(b"trace_id".to_vec(), b"abc".to_vec())],
            2.5,
            7_000_000,
        )];
        let stored = to_bytes(&owned);
        let decoded = from_bytes(&stored).unwrap();
        assert_eq!(decoded[0].0, vec![(&b"trace_id"[..], &b"abc"[..])]);
        assert_eq!((decoded[0].1, decoded[0].2), (2.5, 7_000_000));
        assert!(from_bytes(&stored[..stored.len() - 1]).is_none());
    }

    #[test]
    fn stored_labels_must_remain_valid_unique_and_canonical() {
        for labels in [
            vec![
                (b"a".to_vec(), b"x".to_vec()),
                (b"a".to_vec(), b"y".to_vec()),
            ],
            vec![
                (b"b".to_vec(), b"x".to_vec()),
                (b"a".to_vec(), b"y".to_vec()),
            ],
            vec![(vec![0xff], b"x".to_vec())],
            vec![(b"a".to_vec(), vec![b'x'; 129])],
        ] {
            let bytes = to_bytes(&[(labels, 1.0, 1)]);
            assert!(from_bytes(&bytes).is_none());
        }
    }

    #[test]
    fn drops_label_sets_over_128_characters_or_with_duplicates() {
        let long = "é".repeat(121);
        let wire = v1(&[(b"trace_id", long.as_bytes())], 1.0, 1);
        assert!(decode_v1(&wire).is_none());
        let fits = "é".repeat(120);
        let wire = v1(&[(b"trace_id", fits.as_bytes())], 1.0, 1);
        assert!(decode_v1(&wire).is_some());
        let wire = v1(&[(b"a", b"1"), (b"a", b"2")], 1.0, 1);
        assert!(decode_v1(&wire).is_none());
    }
}
