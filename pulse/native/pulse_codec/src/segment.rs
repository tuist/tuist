//! Log segment encoding and decoding: `%Pulse.Record.Log{}` lists to and
//! from the JSON the S3 adapter stores and the MCP tools return.
//!
//! Encoding reproduces `Pulse.Storage.S3`'s normalize-then-encode (nil or
//! false attributes/resource become `{}`, keys stringified) in `Storage`
//! mode, or the plain field encoding the MCP tool uses in `Plain` mode,
//! and returns the caller timestamp bounds in the same pass. A resource
//! map shared by consecutive records is encoded once and copied.
//!
//! Decoding reproduces the adapter's `decode/1` plus its time and service
//! filters, and only builds terms for records that pass them.

use crate::json_read::{Builder, Fallback, Number, Parser, Res, Stacks};
use crate::out::Sink;
use crate::term_json::{Enc, EncodeError, JsonEncoder, TermBuilder};
use rustler::{Binary, Encoder, Env, ListIterator, Term};
use std::borrow::Cow;

mod atoms {
    rustler::atoms! {
        struct_key = "__struct__",
        log = "Elixir.Pulse.Record.Log",
        timestamp_ns,
        observed_timestamp_ns,
        severity_number,
        severity_text,
        service,
        body,
        trace_id,
        span_id,
        attributes,
        resource,
        otlp,
    }
}

// Field order of the written object and of the struct we build.
const FIELDS: [&str; 11] = [
    "attributes",
    "body",
    "observed_timestamp_ns",
    "resource",
    "service",
    "severity_number",
    "severity_text",
    "span_id",
    "timestamp_ns",
    "trace_id",
    "otlp",
];

#[derive(Clone, Copy, PartialEq)]
pub enum Mode {
    /// What `Pulse.Storage.S3` writes: attributes/resource sanitized.
    Storage,
    /// What `Pulse.MCP.Tools` returns: fields as they are.
    Plain,
}

#[derive(Clone, Copy, PartialEq)]
pub enum Framing {
    Lines,
    Array,
}

pub struct Bounds {
    pub min_ts: i128,
    pub max_ts: i128,
    pub count: usize,
}

fn field_atoms<'a>(env: Env<'a>) -> [Term<'a>; 11] {
    [
        atoms::attributes(),
        atoms::body(),
        atoms::observed_timestamp_ns(),
        atoms::resource(),
        atoms::service(),
        atoms::severity_number(),
        atoms::severity_text(),
        atoms::span_id(),
        atoms::timestamp_ns(),
        atoms::trace_id(),
        atoms::otlp(),
    ]
    .map(|a| a.encode(env))
}

pub fn encode<'a, S: Sink>(
    env: Env<'a>,
    out: &mut S,
    records: Term<'a>,
    mode: Mode,
    framing: Framing,
    enc: &JsonEncoder<'a>,
) -> Enc<Bounds> {
    records.list_length().map_err(|_| Fallback)?;
    let items: ListIterator = records.decode().map_err(|_| Fallback)?;
    let keys = field_atoms(env);
    let struct_key = atoms::struct_key().encode(env);
    let log = atoms::log().encode(env);
    let mut bounds = Bounds {
        min_ts: i128::MAX,
        max_ts: i128::MIN,
        count: 0,
    };
    // (resource term, start, end) of the last resource written.
    let mut last_resource: Option<(usize, usize, usize)> = None;

    if framing == Framing::Array {
        out.push(b'[');
    }
    for record in items {
        let tag = record.map_get(struct_key).map_err(|_| Fallback)?;
        if tag.as_c_arg() != log.as_c_arg() {
            return Err(EncodeError::Fallback);
        }
        if framing == Framing::Array && bounds.count > 0 {
            out.push(b',');
        }
        out.push(b'{');
        for (i, (name, key)) in FIELDS.iter().zip(keys.iter()).enumerate() {
            if i > 0 {
                out.push(b',');
            }
            out.push(b'"');
            out.extend(name.as_bytes());
            out.extend(b"\":");
            let value = record.map_get(*key).map_err(|_| Fallback)?;
            match *name {
                "attributes" | "resource" if mode == Mode::Storage => {
                    let cacheable = *name == "resource";
                    let id = value.as_c_arg();
                    if let (true, Some((last, start, end))) = (cacheable, last_resource) {
                        if last == id {
                            out.repeat(start, end);
                            continue;
                        }
                    }
                    let start = out.len();
                    if enc.is_nil_or_false(value) {
                        out.extend(b"{}");
                    } else if value.get_type() == rustler::TermType::Map {
                        enc.map(out, value, 1)?;
                    } else {
                        return Err(EncodeError::Fallback);
                    }
                    if cacheable {
                        last_resource = Some((id, start, out.len()));
                    }
                }
                "timestamp_ns" => {
                    let ts: i128 = if enc.is_nil_or_false(value) {
                        0
                    } else if let Ok(i) = value.decode::<i64>() {
                        i128::from(i)
                    } else {
                        i128::from(value.decode::<u64>().map_err(|_| Fallback)?)
                    };
                    bounds.min_ts = bounds.min_ts.min(ts);
                    bounds.max_ts = bounds.max_ts.max(ts);
                    enc.value(out, value, 1)?;
                }
                _ => enc.value(out, value, 1)?,
            }
        }
        out.push(b'}');
        if framing == Framing::Lines {
            out.push(b'\n');
        }
        bounds.count += 1;
        if out.len() > enc.budget {
            return Err(EncodeError::TooBig);
        }
    }
    if framing == Framing::Array {
        out.push(b']');
    }
    if bounds.count == 0 {
        bounds.min_ts = 0;
        bounds.max_ts = 0;
    }
    Ok(bounds)
}

pub struct Filter<'f> {
    pub start: Option<i128>,
    pub end: Option<i128>,
    pub service: Option<&'f [u8]>,
}

enum Ts {
    Int(i128),
    Other,
}

struct ClassifyTs;

impl<'a> Builder<'a> for ClassifyTs {
    type Value = Ts;
    fn null(&mut self) -> Res<Ts> {
        Ok(Ts::Other)
    }
    fn boolean(&mut self, _: bool) -> Res<Ts> {
        Ok(Ts::Other)
    }
    fn number(&mut self, n: Number) -> Res<Ts> {
        Ok(match n {
            Number::Int(i) => Ts::Int(i128::from(i)),
            Number::UInt(u) => Ts::Int(i128::from(u)),
            Number::Float(_) => Ts::Other,
        })
    }
    fn string(&mut self, _: Cow<'a, [u8]>) -> Res<Ts> {
        Ok(Ts::Other)
    }
    fn array(&mut self, _: &[Ts]) -> Res<Ts> {
        Ok(Ts::Other)
    }
    fn object(&mut self, _: &[Ts], _: &[Ts]) -> Res<Ts> {
        Ok(Ts::Other)
    }
}

pub fn decode<'a>(env: Env<'a>, blob: &Binary<'a>, filter: &Filter) -> Res<Vec<Term<'a>>> {
    let keys = field_atoms(env);
    let struct_key = atoms::struct_key().encode(env);
    let log = atoms::log().encode(env);
    let nil = rustler::types::atom::nil().encode(env);
    let empty_map = rustler::types::map::map_new(env);
    let time_filter = filter.start.is_some() || filter.end.is_some();
    let mut out = Vec::new();
    let mut builder = TermBuilder::new(env, blob);
    let mut stacks = Stacks::new();

    let mut all_keys = Vec::with_capacity(12);
    all_keys.push(struct_key);
    all_keys.extend_from_slice(&keys);
    let filtered = time_filter || filter.service.is_some();

    for line in blob.as_slice().split(|b| *b == b'\n') {
        if line.is_empty() {
            continue;
        }
        let slots = if filtered {
            match filtered_line(line, filter, time_filter, &mut builder, &mut stacks)? {
                Some(slots) => slots,
                None => continue,
            }
        } else {
            direct_line(line, &mut builder, &mut stacks)?
        };

        let mut values = Vec::with_capacity(12);
        values.push(log);
        for (i, name) in FIELDS.iter().enumerate() {
            let term = slots[i].unwrap_or(nil);
            let term =
                if (*name == "attributes" || *name == "resource") && is_nil_or_false(term, nil) {
                    empty_map
                } else {
                    term
                };
            values.push(term);
        }
        out.push(Term::map_from_arrays(env, &all_keys, &values).map_err(|_| Fallback)?);
    }
    Ok(out)
}

type Slots<'a> = [Option<Term<'a>>; 11];

fn field_index(key: &[u8]) -> Option<usize> {
    FIELDS.iter().position(|f| f.as_bytes() == key)
}

/// No filters: build the known fields in one pass over the line.
fn direct_line<'a>(
    line: &'a [u8],
    builder: &mut TermBuilder<'a, '_>,
    stacks: &mut Stacks<Term<'a>>,
) -> Res<Slots<'a>> {
    let mut slots: Slots = [None; 11];
    let mut seen: Vec<Cow<'a, [u8]>> = Vec::with_capacity(12);
    let mut p = Parser::new(line);
    p.ws();
    p.expect(b'{')?;
    if p.object_open()? {
        loop {
            let key = p.string()?;
            // Elixir keeps the first of duplicate keys; leave that to Elixir.
            if seen.contains(&key) {
                return Err(Fallback);
            }
            p.colon()?;
            match field_index(&key) {
                Some(i) => slots[i] = Some(p.value(builder, stacks)?),
                None => {
                    p.skip_value()?;
                }
            }
            seen.push(key);
            if !p.object_next()? {
                break;
            }
        }
    }
    p.ws();
    p.end()?;
    // Map.fetch!/2 in Elixir raises when the key is missing.
    if !seen.iter().any(|k| k.as_ref() == b"timestamp_ns") {
        return Err(Fallback);
    }
    Ok(slots)
}

/// With filters: look at the raw timestamp and service first and only
/// build the record when it passes.
fn filtered_line<'a>(
    line: &'a [u8],
    filter: &Filter,
    time_filter: bool,
    builder: &mut TermBuilder<'a, '_>,
    stacks: &mut Stacks<Term<'a>>,
) -> Res<Option<Slots<'a>>> {
    let mut p = Parser::new(line);
    let fields = p.raw_object()?;
    p.ws();
    p.end()?;
    for (i, (k, _)) in fields.iter().enumerate() {
        if fields[..i].iter().any(|(other, _)| other == k) {
            return Err(Fallback);
        }
    }
    let get = |name: &str| {
        fields
            .iter()
            .find(|(k, _)| k.as_ref() == name.as_bytes())
            .map(|(_, v)| *v)
    };

    let ts_raw = get("timestamp_ns").ok_or(Fallback)?;
    if time_filter {
        let keep = match Parser::new(ts_raw).document(&mut ClassifyTs)? {
            Ts::Int(ts) => {
                filter.start.is_none_or(|s| ts >= s) && filter.end.is_none_or(|e| ts <= e)
            }
            Ts::Other => false,
        };
        if !keep {
            return Ok(None);
        }
    }
    if let Some(wanted) = filter.service {
        let matches = match get("service") {
            Some(raw) if raw.first() == Some(&b'"') => {
                Parser::new(raw).string()?.as_ref() == wanted
            }
            _ => false,
        };
        if !matches {
            return Ok(None);
        }
    }

    let mut slots: Slots = [None; 11];
    for (key, raw) in &fields {
        if let Some(i) = field_index(key) {
            slots[i] = Some(Parser::new(raw).document_with(builder, stacks)?);
        }
    }
    Ok(Some(slots))
}

fn is_nil_or_false(t: Term, nil: Term) -> bool {
    t.as_c_arg() == nil.as_c_arg() || matches!(t.decode::<bool>(), Ok(false))
}
