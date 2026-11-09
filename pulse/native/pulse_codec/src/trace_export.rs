//! Tempo v1 trace envelope conversion. Only a complete dedicated assembly is
//! accepted. Lossless typed metadata is mandatory; duplicate conflicts fail.
//! JSON is emitted directly to an Erlang binary. Protobuf uses one bounded
//! resource JSON scratch buffer and memoized message sizes (no exponential
//! recursive length passes or whole-trace intermediate buffer).
use crate::json_read::{Parser, RawFields};
use crate::otlp_traces::{field as descriptor, Kind, Schema};
use crate::out::{Counter, Sink};
use rustler::{Binary, Encoder, Env, Term};
use std::collections::BTreeMap;
const MAX: usize = 16_777_216;
#[derive(Debug)]
enum Error {
    Invalid,
    Unknown,
    Conflict,
    NotFound,
    Budget,
    Plan,
}
type Res<T> = Result<T, Error>;
mod atoms {
    rustler::atoms! { ok, error, fallback, trace_metadata_unknown, trace_span_id_conflict, not_found, query_resource_limit }
}
fn object(raw: &[u8]) -> Res<RawFields<'_>> {
    let mut p = Parser::new(raw);
    let fields = p.raw_object().map_err(|_| Error::Invalid)?;
    p.ws();
    p.end().map_err(|_| Error::Invalid)?;
    Ok(fields)
}
fn array(raw: &[u8]) -> Res<Vec<&[u8]>> {
    let mut p = Parser::new(raw);
    let values = p.raw_array().map_err(|_| Error::Invalid)?;
    p.ws();
    p.end().map_err(|_| Error::Invalid)?;
    Ok(values)
}
fn get<'a>(fields: &RawFields<'a>, name: &[u8]) -> Res<&'a [u8]> {
    let mut found = fields.iter().filter(|(k, _)| k.as_ref() == name);
    let value = found.next().map(|(_, v)| *v).ok_or(Error::Invalid)?;
    if found.next().is_some() {
        return Err(Error::Invalid);
    }
    Ok(value)
}
fn text(raw: &[u8]) -> Res<Vec<u8>> {
    let mut p = Parser::new(raw);
    let value = p.string().map_err(|_| Error::Invalid)?.into_owned();
    p.ws();
    p.end().map_err(|_| Error::Invalid)?;
    Ok(value)
}
fn uint(raw: &[u8]) -> Res<u64> {
    let bytes = if raw.first() == Some(&b'"') {
        text(raw)?
    } else {
        raw.to_vec()
    };
    std::str::from_utf8(&bytes)
        .map_err(|_| Error::Invalid)?
        .parse()
        .map_err(|_| Error::Invalid)
}
fn hex(raw: &[u8], width: usize) -> Res<Vec<u8>> {
    if raw == b"null" {
        return Ok(vec![]);
    }
    let raw = text(raw)?;
    if raw.iter().all(|b| *b == b'0')
        || raw.len() != width
        || !raw.iter().all(|b| b.is_ascii_hexdigit())
    {
        return Err(Error::Invalid);
    }
    raw.as_chunks::<2>()
        .0
        .iter()
        .map(|b| {
            u8::from_str_radix(std::str::from_utf8(b).unwrap(), 16).map_err(|_| Error::Invalid)
        })
        .collect()
}
struct Object<'a, S: Sink> {
    out: &'a mut S,
    first: bool,
}
impl<'a, S: Sink> Object<'a, S> {
    fn new(out: &'a mut S) -> Self {
        out.push(b'{');
        Self { out, first: true }
    }
    fn key(&mut self, name: &[u8]) {
        if !self.first {
            self.out.push(b',');
        }
        self.first = false;
        crate::json_write::write_str(self.out, name);
        self.out.push(b':');
    }
    fn string(&mut self, name: &[u8], raw: &[u8]) -> Res<()> {
        let v = text(raw)?;
        if !v.is_empty() {
            self.key(name);
            crate::json_write::write_str(self.out, &v);
        }
        Ok(())
    }
    fn number(&mut self, name: &[u8], raw: &[u8], quoted: bool) -> Res<()> {
        let n = uint(raw)?;
        if (!quoted && n > u64::from(u32::MAX)) || (quoted && n > i64::MAX as u64) {
            return Err(Error::Invalid);
        }
        if n != 0 {
            self.key(name);
            if quoted {
                self.out.push(b'"');
            }
            self.out.extend(n.to_string().as_bytes());
            if quoted {
                self.out.push(b'"');
            }
        }
        Ok(())
    }
    fn attrs(&mut self, raw: &[u8]) -> Res<()> {
        if !array(raw)?.is_empty() {
            self.key(b"attributes");
            self.out.extend(raw);
        }
        Ok(())
    }
    fn id(&mut self, name: &[u8], raw: &[u8], width: usize) -> Res<()> {
        let bytes = hex(raw, width)?;
        if !bytes.is_empty() {
            self.key(name);
            crate::json_write::write_str(self.out, &crate::otlp_traces::base64(&bytes));
        }
        Ok(())
    }
    fn finish(self) {
        self.out.push(b'}');
    }
}
fn owner(out: &mut impl Sink, raw: &RawFields<'_>, typed: &[u8], scope: bool) -> Res<()> {
    let mut o = Object::new(out);
    if scope {
        o.string(b"name", get(raw, b"name")?)?;
        o.string(b"version", get(raw, b"version")?)?;
    }
    o.attrs(typed)?;
    o.number(
        b"droppedAttributesCount",
        get(
            raw,
            if scope {
                b"dropped_attributes_count"
            } else {
                b"resource_dropped_attributes_count"
            },
        )?,
        false,
    )?;
    o.finish();
    Ok(())
}
fn span(out: &mut impl Sink, fields: &RawFields<'_>, typed: &RawFields<'_>) -> Res<()> {
    if uint(get(fields, b"end_timestamp_ns")?)? < uint(get(fields, b"timestamp_ns")?)?
        || get(fields, b"trace_id")? == b"null"
        || get(fields, b"span_id")? == b"null"
    {
        return Err(Error::Invalid);
    }
    let mut o = Object::new(out);
    o.id(b"traceId", get(fields, b"trace_id")?, 32)?;
    o.id(b"spanId", get(fields, b"span_id")?, 16)?;
    o.id(b"parentSpanId", get(fields, b"parent_span_id")?, 16)?;
    o.string(b"traceState", get(fields, b"trace_state")?)?;
    o.string(b"name", get(fields, b"name")?)?;
    let kind = uint(get(fields, b"kind")?)?;
    if kind > 5 {
        return Err(Error::Invalid);
    }
    if kind > 0 {
        o.key(b"kind");
        crate::json_write::write_str(
            o.out,
            [
                b"SPAN_KIND_UNSPECIFIED".as_slice(),
                b"SPAN_KIND_INTERNAL",
                b"SPAN_KIND_SERVER",
                b"SPAN_KIND_CLIENT",
                b"SPAN_KIND_PRODUCER",
                b"SPAN_KIND_CONSUMER",
            ][kind as usize],
        );
    }
    o.number(b"startTimeUnixNano", get(fields, b"timestamp_ns")?, true)?;
    o.number(b"endTimeUnixNano", get(fields, b"end_timestamp_ns")?, true)?;
    o.attrs(get(typed, b"attributes")?)?;
    for (dst, src) in [
        (
            b"droppedAttributesCount".as_slice(),
            b"dropped_attributes_count".as_slice(),
        ),
        (b"droppedEventsCount", b"dropped_events_count"),
        (b"droppedLinksCount", b"dropped_links_count"),
        (b"flags", b"flags"),
    ] {
        o.number(dst, get(fields, src)?, false)?;
    }
    for name in [b"events".as_slice(), b"links"] {
        let rows = array(get(fields, name)?)?;
        let attrs = array(get(typed, name)?)?;
        if rows.len() != attrs.len() {
            return Err(Error::Invalid);
        }
        if !rows.is_empty() {
            o.key(name);
            o.out.push(b'[');
            for (index, (row, attr)) in rows.iter().zip(attrs).enumerate() {
                if index > 0 {
                    o.out.push(b',');
                }
                let fields = object(row)?;
                let mut child = Object::new(o.out);
                if name == b"events" {
                    child.number(b"timeUnixNano", get(&fields, b"timestamp_ns")?, true)?;
                    child.string(b"name", get(&fields, b"name")?)?;
                } else {
                    child.id(b"traceId", get(&fields, b"trace_id")?, 32)?;
                    child.id(b"spanId", get(&fields, b"span_id")?, 16)?;
                    child.string(b"traceState", get(&fields, b"trace_state")?)?;
                    child.number(b"flags", get(&fields, b"flags")?, false)?;
                }
                child.attrs(attr)?;
                child.number(
                    b"droppedAttributesCount",
                    get(&fields, b"dropped_attributes_count")?,
                    false,
                )?;
                child.finish();
            }
            o.out.push(b']');
        }
    }
    let status = object(get(fields, b"status")?)?;
    let code = uint(get(&status, b"code")?)?;
    if code > 2 {
        return Err(Error::Invalid);
    }
    {
        // Tempo stored traces materialize Status even for UNSET. Grafana's
        // TraceToFrame dereferences the message; preserve empty-message presence.
        o.key(b"status");
        let mut status_out = Object::new(o.out);
        status_out.string(b"message", get(&status, b"message")?)?;
        if code > 0 {
            status_out.key(b"code");
            crate::json_write::write_str(
                status_out.out,
                if code == 1 {
                    b"STATUS_CODE_OK"
                } else {
                    b"STATUS_CODE_ERROR"
                },
            );
        }
        status_out.finish();
    }
    o.finish();
    Ok(())
}
fn resource(out: &mut impl Sink, rows: &[&[u8]]) -> Res<()> {
    let payload = rows.first().ok_or(Error::Invalid)?;
    crate::trace_metadata::validate(payload).map_err(|_| Error::Invalid)?;
    let fields = object(payload)?;
    let metadata = get(&fields, b"otlp").map_err(|_| Error::Unknown)?;
    if metadata == b"null" {
        return Err(Error::Unknown);
    }
    let typed = object(metadata)?;
    let scope = object(get(&fields, b"scope")?)?;
    let mut root = Object::new(out);
    root.key(b"resource");
    owner(root.out, &fields, get(&typed, b"resource")?, false)?;
    root.key(b"scopeSpans");
    root.out.push(b'[');
    let mut scopes = Object::new(root.out);
    scopes.key(b"scope");
    owner(scopes.out, &scope, get(&typed, b"scope")?, true)?;
    scopes.key(b"spans");
    scopes.out.push(b'[');
    for (index, payload) in rows.iter().enumerate() {
        if index > 0 {
            scopes.out.push(b',');
        }
        let fields = object(payload)?;
        let typed = object(get(&fields, b"otlp")?)?;
        span(scopes.out, &fields, &typed)?;
    }
    scopes.out.push(b']');
    scopes.string(b"schemaUrl", get(&fields, b"scope_schema_url")?)?;
    scopes.finish();
    root.out.push(b']');
    root.string(b"schemaUrl", get(&fields, b"resource_schema_url")?)?;
    root.finish();
    Ok(())
}
fn select(input: &[u8]) -> Res<Vec<&[u8]>> {
    if input.len() > MAX {
        return Err(Error::Budget);
    }
    let fields = object(input)?;
    let coverage = text(get(&fields, b"coverage")?)?;
    if !matches!(
        coverage.as_slice(),
        b"all_stored_spans" | b"all_stored_spans_at_or_above_floor"
    ) {
        return Err(Error::Invalid);
    }
    let id = text(get(&fields, b"trace_id")?)?;
    let spans = array(get(&fields, b"spans")?)?;
    if spans.len() > 5000 {
        return Err(Error::Budget);
    }
    let mut seen = BTreeMap::new();
    let mut selected = vec![];
    let mut bytes = 0;
    for raw in spans {
        crate::trace_metadata::validate(raw).map_err(|_| Error::Invalid)?;
        let fields = object(raw)?;
        if text(get(&fields, b"trace_id")?)? != id {
            return Err(Error::Invalid);
        }
        if get(&fields, b"otlp").is_err() || get(&fields, b"otlp")? == b"null" {
            return Err(Error::Unknown);
        }
        let sid = text(get(&fields, b"span_id")?)?;
        let key = crate::trace_sort_key::span_key(raw, false).map_err(|_| Error::Invalid)?;
        if let Some(old) = seen.get(&sid) {
            if old != &key {
                return Err(Error::Conflict);
            }
        } else {
            bytes += key.len();
            if bytes > MAX {
                return Err(Error::Budget);
            }
            seen.insert(sid, key);
            selected.push(raw);
        }
    }
    if selected.is_empty() {
        return Err(Error::NotFound);
    }
    Ok(selected)
}
fn base64(raw: &[u8]) -> Res<Vec<u8>> {
    let raw = text(raw)?;
    if raw.len() % 4 != 0 {
        return Err(Error::Invalid);
    }
    let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = Vec::with_capacity(raw.len() / 4 * 3);
    for chunk in raw.as_chunks::<4>().0 {
        let mut n = 0u32;
        let mut padding = 0;
        for b in chunk {
            n <<= 6;
            if *b == b'=' {
                padding += 1;
            } else {
                if padding > 0 {
                    return Err(Error::Invalid);
                }
                n |= alphabet.iter().position(|c| c == b).ok_or(Error::Invalid)? as u32;
            }
        }
        if padding > 2 {
            return Err(Error::Invalid);
        }
        out.push((n >> 16) as u8);
        if padding < 2 {
            out.push((n >> 8) as u8);
        }
        if padding == 0 {
            out.push(n as u8);
        }
    }
    if crate::otlp_traces::base64(&out) != raw {
        return Err(Error::Invalid);
    }
    Ok(out)
}
fn varint(out: &mut impl Sink, mut n: u64) {
    while n >= 128 {
        out.push(n as u8 | 128);
        n >>= 7;
    }
    out.push(n as u8);
}
type Sizes = BTreeMap<(usize, usize, usize), usize>;
fn message(
    out: &mut impl Sink,
    raw: &[u8],
    schema: Schema,
    sizes: &mut Sizes,
    depth: usize,
) -> Res<()> {
    if depth > 128 || sizes.len() > 262_144 {
        // A native planning bound is not a semantic/result byte budget. The
        // admitted reference may answer under its own heap/deadline guards.
        return Err(Error::Plan);
    }
    let fields = object(raw)?;
    for n in 1..=16 {
        let Some((name, kind, many)) = descriptor(schema, n) else {
            continue;
        };
        let Ok(raw) = get(&fields, name.as_bytes()) else {
            continue;
        };
        if many {
            for value in array(raw)? {
                wire(out, n, kind, value, schema == Schema::Any, sizes, depth)?;
            }
        } else {
            wire(out, n, kind, raw, schema == Schema::Any, sizes, depth)?;
        }
    }
    Ok(())
}
fn wire(
    out: &mut impl Sink,
    n: u64,
    kind: Kind,
    raw: &[u8],
    oneof: bool,
    sizes: &mut Sizes,
    depth: usize,
) -> Res<()> {
    match kind {
        // Metric-only wire kinds do not belong to the trace export schema.
        Kind::PackedFixed64 | Kind::PackedDouble | Kind::PackedUint64 | Kind::Sint32 => {
            return Err(Error::Invalid)
        }
        Kind::Message(Schema::Span) => {
            // Scope groups may contain 5,000 spans. Do not accumulate every
            // attribute message plan across the group: reuse a bounded local
            // plan for exactly one span's measure/write pair, then discard it.
            let mut local = Sizes::new();
            let mut counter = Counter::new(MAX);
            message(&mut counter, raw, Schema::Span, &mut local, depth + 1)?;
            varint(out, n * 8 + 2);
            varint(out, counter.len() as u64);
            message(out, raw, Schema::Span, &mut local, depth + 1)?;
        }
        Kind::Message(schema) => {
            let cache = (schema as usize, raw.as_ptr() as usize, raw.len());
            let length = if let Some(size) = sizes.get(&cache) {
                *size
            } else {
                let mut counter = Counter::new(MAX);
                message(&mut counter, raw, schema, sizes, depth + 1)?;
                if counter.len() > MAX {
                    return Err(Error::Budget);
                }
                sizes.insert(cache, counter.len());
                counter.len()
            };
            varint(out, n * 8 + 2);
            varint(out, length as u64);
            message(out, raw, schema, sizes, depth + 1)?;
        }
        Kind::String | Kind::Hex | Kind::Bytes => {
            let bytes = if matches!(kind, Kind::String) {
                text(raw)?
            } else {
                base64(raw)?
            };
            if !bytes.is_empty() || oneof {
                varint(out, n * 8 + 2);
                varint(out, bytes.len() as u64);
                out.extend(&bytes);
            }
        }
        Kind::Double => {
            let number = crate::trace_metadata::double(raw).map_err(|_| Error::Invalid)?;
            let bits = number.to_bits();
            if bits != 0 || oneof {
                varint(out, n * 8 + 1);
                out.extend(&bits.to_le_bytes());
            }
        }
        Kind::Fixed64 | Kind::Fixed32 | Kind::Signed64 | Kind::Uint | Kind::Int | Kind::Bool => {
            let value = if matches!(kind, Kind::Int | Kind::Signed64) {
                std::str::from_utf8(&text(raw)?)
                    .map_err(|_| Error::Invalid)?
                    .parse::<i64>()
                    .map_err(|_| Error::Invalid)? as u64
            } else if matches!(kind, Kind::Bool) {
                match raw {
                    b"true" => 1,
                    b"false" => 0,
                    _ => return Err(Error::Invalid),
                }
            } else if raw.first() == Some(&b'"') && matches!(kind, Kind::Uint) {
                match text(raw)?.as_slice() {
                    b"SPAN_KIND_INTERNAL" => 1,
                    b"SPAN_KIND_SERVER" => 2,
                    b"SPAN_KIND_CLIENT" => 3,
                    b"SPAN_KIND_PRODUCER" => 4,
                    b"SPAN_KIND_CONSUMER" => 5,
                    b"STATUS_CODE_OK" => 1,
                    b"STATUS_CODE_ERROR" => 2,
                    _ => return Err(Error::Invalid),
                }
            } else {
                uint(raw)?
            };
            if value != 0 || oneof {
                match kind {
                    Kind::Fixed64 | Kind::Signed64 => {
                        varint(out, n * 8 + 1);
                        out.extend(&value.to_le_bytes());
                    }
                    Kind::Fixed32 => {
                        varint(out, n * 8 + 5);
                        out.extend(
                            &u32::try_from(value)
                                .map_err(|_| Error::Invalid)?
                                .to_le_bytes(),
                        );
                    }
                    _ => {
                        varint(out, n * 8);
                        varint(out, value);
                    }
                }
            }
        }
    }
    if out.len() > MAX {
        return Err(Error::Budget);
    }
    Ok(())
}
fn groups<'a>(spans: &[&'a [u8]]) -> Res<Vec<Vec<&'a [u8]>>> {
    let mut indexes = BTreeMap::new();
    let mut groups: Vec<Vec<&[u8]>> = Vec::new();
    let mut bytes = 0;
    for payload in spans {
        let fields = object(payload)?;
        let typed = object(get(&fields, b"otlp")?)?;
        let scope = object(get(&fields, b"scope")?)?;
        let mut key = Vec::new();
        for raw in [
            get(&typed, b"resource")?,
            get(&fields, b"resource_dropped_attributes_count")?,
            get(&fields, b"resource_schema_url")?,
            get(&scope, b"name")?,
            get(&scope, b"version")?,
            get(&scope, b"dropped_attributes_count")?,
            get(&typed, b"scope")?,
            get(&fields, b"scope_schema_url")?,
        ] {
            key.extend_from_slice(&crate::trace_sort_key::key(raw).map_err(|_| Error::Invalid)?);
        }
        let index = if let Some(index) = indexes.get(&key) {
            *index
        } else {
            bytes += key.len();
            if bytes > MAX {
                return Err(Error::Budget);
            }
            let index = groups.len();
            indexes.insert(key, index);
            groups.push(Vec::new());
            index
        };
        groups[index].push(payload);
    }
    Ok(groups)
}
fn render(out: &mut impl Sink, groups: &[Vec<&[u8]>], protobuf: bool, v2: bool) -> Res<()> {
    if protobuf && v2 {
        let mut trace = Counter::new(MAX);
        render(&mut trace, groups, true, false)?;
        varint(out, 10);
        varint(out, trace.len() as u64);
        return render(out, groups, true, false);
    }
    if !protobuf {
        out.extend(if v2 {
            b"{\"trace\":{\"resourceSpans\":["
        } else {
            b"{\"batches\":["
        });
    }
    for (index, rows) in groups.iter().enumerate() {
        if protobuf {
            let mut scratch = Vec::new();
            resource(&mut scratch, rows)?;
            if scratch.len() > MAX {
                return Err(Error::Budget);
            }
            let mut sizes = Sizes::new();
            let mut counter = Counter::new(MAX);
            message(&mut counter, &scratch, Schema::ResourceSpans, &mut sizes, 0)?;
            varint(out, 10);
            varint(out, counter.len() as u64);
            message(out, &scratch, Schema::ResourceSpans, &mut sizes, 0)?;
        } else {
            if index > 0 {
                out.push(b',');
            }
            resource(out, rows)?;
        }
        if out.len() > MAX {
            return Err(Error::Budget);
        }
    }
    if !protobuf {
        out.extend(if v2 { b"]}}" } else { b"]}" });
    }
    if out.len() > MAX {
        return Err(Error::Budget);
    }
    Ok(())
}
#[rustler::nif]
fn tempo_trace_api_version() -> u32 {
    3
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_trace_export<'a>(env: Env<'a>, assembly: Binary<'a>, format: &str) -> Term<'a> {
    let export = || {
        let (protobuf, v2) = match format {
            "json" => (false, false),
            "protobuf" => (true, false),
            "json_v2" => (false, true),
            "protobuf_v2" => (true, true),
            _ => return Err(Error::Invalid),
        };
        let spans = select(assembly.as_slice())?;
        let groups = groups(&spans)?;
        let mut counter = Counter::new(MAX);
        render(&mut counter, &groups, protobuf, v2)?;
        let mut out = crate::out::BinSink::with_capacity(counter.len());
        render(&mut out, &groups, protobuf, v2)?;
        Ok(out.finish(env))
    };
    match export() {
        Ok(body) => (atoms::ok(), body).encode(env),
        Err(Error::Unknown) => (atoms::error(), atoms::trace_metadata_unknown()).encode(env),
        Err(Error::Conflict) => (atoms::error(), atoms::trace_span_id_conflict()).encode(env),
        Err(Error::NotFound) => (atoms::error(), atoms::not_found()).encode(env),
        Err(Error::Budget) => (atoms::error(), atoms::query_resource_limit()).encode(env),
        Err(Error::Invalid | Error::Plan) => atoms::fallback().encode(env),
    }
}
