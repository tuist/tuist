// Pulse codec NIF: the byte-heavy encoding and decoding on Pulse's hot
// paths.
//
//   * Loki push protobuf decoding (ingest).
//   * JSON encode/decode, used as Phoenix's JSON library (request bodies,
//     responses).
//   * Log segment encode/decode for the S3 adapter and the MCP tools.
//
// Every JSON function falls back to Elixir (returns `:fallback`) on input
// it cannot guarantee to handle exactly like Elixir's `JSON` module, so
// the Rust path is an optimization, never a behavior change.
//
// Decoded strings are sub-binaries of the input where that avoids a
// copy, so a retained term can keep its whole source buffer alive.
// Callers that keep decoded data past a request should `:binary.copy/1`
// the fields they keep.

mod bounded_json;
mod erlang_bytes;
mod exemplar;
mod ingest_limits;
mod json_read;
mod json_write;
mod labels;
mod log_discovery;
mod log_metric;
mod log_rollup;
mod log_tiers;
mod loki;
mod metric_catalog;
mod metric_discovery;
mod metric_footer;
mod metric_json;
mod metric_postings;
mod metric_regex;
mod metric_segment_parquet;
mod metric_tiers;
mod metric_value;
mod native_histogram;
mod otlp_json;
mod otlp_traces;
mod out;
mod patterns;
mod query_filter;
mod query_regex;
mod remote_write;
mod segment;
mod segment_parquet;
mod stable_hash;
mod tempo_discovery;
mod tempo_duration;
mod tempo_expression;
mod tempo_float;
mod tempo_search;
mod term_json;
mod trace_export;
mod trace_metadata;
mod trace_metrics;
mod trace_query;
mod trace_search;
mod trace_segment_parquet;
mod trace_sort_key;
mod wire;

use json_read::Parser;
use memchr::memmem::Finder;
use out::BinSink;
use query_filter::{LineFilter, LineFilterOp, MatchOp, Matcher};
use term_json::{EncodeError, JsonEncoder, TermBuilder};

use rustler::{Binary, Encoder, Env, ListIterator, NewBinary, NifResult, Term};
use std::borrow::Cow;

mod counting_alloc;

// Bytes this library currently holds on the native heap (see counting_alloc.rs).
#[rustler::nif]
fn native_allocated_bytes() -> i64 {
    counting_alloc::allocated()
}

// Process-wide glibc malloc statistics: `{system, in_use, free}` bytes, where
// `system` is what malloc holds from the OS (arenas plus mmapped chunks),
// `in_use` what callers hold and `free` what malloc keeps without returning.
// Covers every malloc user in the VM (the BEAM's own sys_alloc, OpenSSL, all
// NIF crates). `nil` on other C libraries.
#[rustler::nif]
fn native_malloc_stats() -> Option<(i64, i64, i64)> {
    malloc_stats()
}

#[cfg(all(target_os = "linux", target_env = "gnu"))]
fn malloc_stats() -> Option<(i64, i64, i64)> {
    #[repr(C)]
    struct MallInfo {
        arena: std::ffi::c_int,
        ordblks: std::ffi::c_int,
        smblks: std::ffi::c_int,
        hblks: std::ffi::c_int,
        hblkhd: std::ffi::c_int,
        usmblks: std::ffi::c_int,
        fsmblks: std::ffi::c_int,
        uordblks: std::ffi::c_int,
        fordblks: std::ffi::c_int,
        keepcost: std::ffi::c_int,
    }
    extern "C" {
        // `mallinfo2` needs glibc 2.33; the int fields here wrap at 4 GiB,
        // which is read as unsigned and is beyond any supported node size.
        fn mallinfo() -> MallInfo;
    }
    let info = unsafe { mallinfo() };
    let u = |v: std::ffi::c_int| v as u32 as i64;
    Some((
        u(info.arena) + u(info.hblkhd),
        u(info.uordblks) + u(info.hblkhd),
        u(info.fordblks),
    ))
}

#[cfg(not(all(target_os = "linux", target_env = "gnu")))]
fn malloc_stats() -> Option<(i64, i64, i64)> {
    None
}

// Return free C-allocator memory to the operating system. glibc keeps freed
// chunks in per-thread arenas and only gives back the top of each heap on its
// own, so memory freed by native work (Parquet encoding, manifest JSON) in
// the middle of an arena stays resident. `malloc_trim` releases those pages.
// Returns whether anything was released; `false` on other C libraries.
#[rustler::nif(schedule = "DirtyCpu")]
fn native_malloc_trim() -> bool {
    malloc_trim()
}

#[cfg(all(target_os = "linux", target_env = "gnu"))]
fn malloc_trim() -> bool {
    extern "C" {
        fn malloc_trim(pad: usize) -> std::ffi::c_int;
    }
    unsafe { malloc_trim(0) == 1 }
}

#[cfg(not(all(target_os = "linux", target_env = "gnu")))]
fn malloc_trim() -> bool {
    false
}

mod atoms {
    rustler::atoms! {
        done,
        none,
        final_ = "final",
        before,
        after,
        rollup,
        exemplars,
        histogram,
        more,
        ok,
        error,
        nil,
        invalid_snappy,
        invalid_protobuf,
        payload_too_large,
        too_many_records,
        invalid_segment,
        too_large,
        too_many_trace_nodes,
        too_many_otlp_nodes,
        invalid_otlp,
        invalid_otlp_integer,
        logs,
        metrics,
        traces,
        trace_projection_invalid,
        attributes_too_large,
        fallback,
        too_big,
        query_sample_limit,
        query_resource_limit,
        query_result_limit,
        query_decoded_limit,
        trace_projection_tie,
        storage,
        lines,
        eq,
        neq,
        re,
        nre,
        contains,
        not_contains,
        match_re,
        not_match_re,
        struct_key = "__struct__",
        log = "Elixir.Pulse.Record.Log",
        timestamp_ns,
        start_timestamp_ms,
        observed_timestamp_ns,
        severity_number,
        severity_text,
        service,
        body,
        trace_id,
        span_id,
        attributes,
        resource,
        metric_sample = "Elixir.Pulse.Record.MetricSample",
        otlp,
        series_id,
        value,
        labels,
    }
}

/// Decode a Snappy-compressed (raw block format) Loki `PushRequest`.
///
/// The uncompressed size is read from the Snappy header and checked
/// against `max_decompressed` before any output buffer is allocated.
/// Runs on a dirty CPU scheduler: a 1 MiB batch takes a few ms, well
/// past the ~1 ms budget of a regular scheduler.
#[rustler::nif(schedule = "DirtyCpu")]
fn decode_loki_push<'a>(
    env: Env<'a>,
    compressed: Binary<'a>,
    max_decompressed: usize,
) -> NifResult<Term<'a>> {
    decode_loki_inner(env, compressed, max_decompressed, None)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn decode_loki_push_limited<'a>(
    env: Env<'a>,
    compressed: Binary<'a>,
    max_decompressed: usize,
    options: ingest_limits::Options,
) -> NifResult<Term<'a>> {
    decode_loki_inner(env, compressed, max_decompressed, Some(options.into()))
}

fn decode_loki_inner<'a>(
    env: Env<'a>,
    compressed: Binary<'a>,
    max_decompressed: usize,
    limits: Option<ingest_limits::Limits>,
) -> NifResult<Term<'a>> {
    let input = compressed.as_slice();
    let len = match snap::raw::decompress_len(input) {
        Ok(len) => len,
        Err(_) => return Ok(error(env, atoms::invalid_snappy())),
    };
    if len > max_decompressed {
        return Ok(error(env, atoms::payload_too_large()));
    }

    let mut buffer = NewBinary::new(env, len);
    match snap::raw::Decoder::new().decompress(input, buffer.as_mut_slice()) {
        Ok(written) if written == len => {}
        _ => return Ok(error(env, atoms::invalid_snappy())),
    }
    let buffer: Binary = buffer.into();

    if let Some(limits) = limits {
        if let Err(reason) = limits.loki(buffer.as_slice()) {
            return Ok(ingest_error(env, reason));
        }
    }

    match loki::decode(buffer.as_slice()) {
        Some(decoded) => to_terms(env, &buffer, &decoded),
        None => Ok(error(env, atoms::invalid_protobuf())),
    }
}

fn ingest_error(env: Env<'_>, reason: ingest_limits::Error) -> Term<'_> {
    error(
        env,
        match reason {
            ingest_limits::Error::InvalidProtobuf => atoms::invalid_protobuf(),
            ingest_limits::Error::TooManyRecords => atoms::too_many_records(),
            ingest_limits::Error::AttributesTooLarge => atoms::attributes_too_large(),
        },
    )
}

fn error<'a>(env: Env<'a>, reason: rustler::Atom) -> Term<'a> {
    (atoms::error(), reason).encode(env)
}

fn to_terms<'a>(env: Env<'a>, buffer: &Binary<'a>, decoded: &loki::Decoded) -> NifResult<Term<'a>> {
    let nil = atoms::nil().encode(env);
    let keys = [
        atoms::struct_key(),
        atoms::timestamp_ns(),
        atoms::observed_timestamp_ns(),
        atoms::severity_number(),
        atoms::severity_text(),
        atoms::service(),
        atoms::body(),
        atoms::trace_id(),
        atoms::span_id(),
        atoms::attributes(),
        atoms::resource(),
        // Every `%Pulse.Record.Log{}` field: the segment encoder rejects a
        // record map missing one. Loki pushes carry no OTLP envelope.
        atoms::otlp(),
    ]
    .map(|atom| atom.encode(env));
    let struct_name = atoms::log().encode(env);

    let total = decoded.streams.iter().map(|s| s.records.len()).sum();
    let mut records = Vec::with_capacity(total);

    for stream in &decoded.streams {
        let mut names = Vec::with_capacity(stream.labels.len());
        let mut values = Vec::with_capacity(stream.labels.len());
        for (name, value) in &stream.labels {
            names.push(slice(env, buffer, name.as_bytes())?);
            values.push(match value {
                Cow::Borrowed(b) => slice(env, buffer, b)?,
                Cow::Owned(o) => copy(env, o),
            });
        }
        // One resource map per stream, shared by every record in it.
        let resource = Term::map_from_arrays(env, &names, &values)?;
        let service = stream.service().map_or(nil, |i| values[i]);
        let level = stream.level().map_or(nil, |i| values[i]);

        for record in &stream.records {
            let mut attr_keys = Vec::with_capacity(record.attributes.len());
            let mut attr_values = Vec::with_capacity(record.attributes.len());
            for (k, v) in &record.attributes {
                attr_keys.push(slice(env, buffer, k)?);
                attr_values.push(slice(env, buffer, v)?);
            }
            let fields = [
                struct_name,
                record.timestamp_ns.encode(env),
                nil,
                nil,
                level,
                service,
                slice(env, buffer, record.line)?,
                optional(env, buffer, record.trace_id)?,
                optional(env, buffer, record.span_id)?,
                Term::map_from_arrays(env, &attr_keys, &attr_values)?,
                resource,
                nil,
            ];
            records.push(Term::map_from_arrays(env, &keys, &fields)?);
        }
    }

    Ok((atoms::ok(), records, decoded.rejected).encode(env))
}

/// A sub-binary of `buffer` when `part` lies inside it; otherwise (empty
/// proto3 defaults point at static memory) a fresh binary.
fn slice<'a>(env: Env<'a>, buffer: &Binary<'a>, part: &[u8]) -> NifResult<Term<'a>> {
    let base = buffer.as_slice();
    let start = (part.as_ptr() as usize).wrapping_sub(base.as_ptr() as usize);
    if !part.is_empty() && start <= base.len() && part.len() <= base.len() - start {
        Ok(buffer.make_subbinary(start, part.len())?.encode(env))
    } else {
        Ok(copy(env, part))
    }
}

fn optional<'a>(env: Env<'a>, buffer: &Binary<'a>, part: Option<&[u8]>) -> NifResult<Term<'a>> {
    match part {
        Some(p) => slice(env, buffer, p),
        None => Ok(atoms::nil().encode(env)),
    }
}

fn copy<'a>(env: Env<'a>, bytes: &[u8]) -> Term<'a> {
    let mut out = NewBinary::new(env, bytes.len());
    out.as_mut_slice().copy_from_slice(bytes);
    Binary::from(out).encode(env)
}

// -- JSON ---------------------------------------------------------------

fn json_decode_impl<'a>(env: Env<'a>, input: Binary<'a>) -> Term<'a> {
    let mut builder = TermBuilder::new(env, &input);
    match Parser::new(input.as_slice()).document(&mut builder) {
        Ok(term) => (atoms::ok(), term).encode(env),
        Err(_) => atoms::fallback().encode(env),
    }
}

/// For inputs small enough to parse well inside a scheduler timeslice.
#[rustler::nif]
fn json_decode<'a>(env: Env<'a>, input: Binary<'a>) -> Term<'a> {
    json_decode_impl(env, input)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn json_decode_dirty<'a>(env: Env<'a>, input: Binary<'a>) -> Term<'a> {
    json_decode_impl(env, input)
}

fn json_encode_impl<'a>(env: Env<'a>, term: Term<'a>, budget: usize, capacity: usize) -> Term<'a> {
    let encoder = JsonEncoder::new(env, budget);
    let mut out = BinSink::with_capacity(capacity);
    match encoder.value(&mut out, term, 0) {
        Ok(()) => (atoms::ok(), out.finish(env)).encode(env),
        Err(EncodeError::TooBig) => atoms::too_big().encode(env),
        Err(EncodeError::Fallback) => atoms::fallback().encode(env),
    }
}

/// Encodes on the calling scheduler and gives up with `:too_big` once the
/// output passes `budget` bytes, so the caller can retry on a dirty
/// scheduler. Keeps small responses off the dirty pool.
#[rustler::nif]
fn json_encode<'a>(env: Env<'a>, term: Term<'a>, budget: usize) -> Term<'a> {
    json_encode_impl(env, term, budget, 256)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn json_encode_dirty<'a>(env: Env<'a>, term: Term<'a>) -> Term<'a> {
    json_encode_impl(env, term, usize::MAX, 64 * 1024)
}

// -- Log segments --------------------------------------------------------

fn integer<'a>(env: Env<'a>, v: i128) -> Term<'a> {
    match i64::try_from(v) {
        Ok(i) => i.encode(env),
        Err(_) => (v as u64).encode(env),
    }
}

/// Encode `[%Pulse.Record.Log{}]` as stored segment lines (`:storage`,
/// `:lines`) or as the MCP tool's JSON array (`:plain`, `:array`).
/// Returns `{:ok, binary, min_ts, max_ts, count}` or `:fallback`.
#[rustler::nif(schedule = "DirtyCpu")]
fn encode_log_segment<'a>(
    env: Env<'a>,
    records: Term<'a>,
    mode: rustler::Atom,
    framing: rustler::Atom,
) -> Term<'a> {
    let mode = if mode == atoms::storage() {
        segment::Mode::Storage
    } else {
        segment::Mode::Plain
    };
    let framing = if framing == atoms::lines() {
        segment::Framing::Lines
    } else {
        segment::Framing::Array
    };
    let estimate = records.list_length().unwrap_or(0).saturating_mul(512);
    let encoder = JsonEncoder::new(env, usize::MAX);
    let mut out = BinSink::with_capacity(estimate);
    match segment::encode(env, &mut out, records, mode, framing, &encoder) {
        Ok(b) => (
            atoms::ok(),
            out.finish(env),
            integer(env, b.min_ts),
            integer(env, b.max_ts),
            b.count,
        )
            .encode(env),
        Err(_) => atoms::fallback().encode(env),
    }
}

/// Public raw log responses prove their full JSON size before allocating the
/// result binary. Counter and writer use the exact same reference encoder.
#[rustler::nif(schedule = "DirtyCpu")]
fn encode_log_segment_bounded<'a>(env: Env<'a>, records: Term<'a>, limit: usize) -> Term<'a> {
    use out::Sink;
    let encoder = JsonEncoder::new(env, limit);
    let mut counter = out::Counter::new(limit);
    let mode = segment::Mode::Plain;
    let framing = segment::Framing::Array;
    match segment::encode(env, &mut counter, records, mode, framing, &encoder) {
        Ok(_) if counter.len() <= limit => (),
        Ok(_) | Err(EncodeError::TooBig) => return error(env, atoms::query_result_limit()),
        Err(_) => return atoms::fallback().encode(env),
    }
    let mut out = BinSink::with_capacity(counter.len());
    match segment::encode(env, &mut out, records, mode, framing, &encoder) {
        Ok(_) => (atoms::ok(), out.finish(env)).encode(env),
        Err(EncodeError::TooBig) => error(env, atoms::query_result_limit()),
        Err(_) => atoms::fallback().encode(env),
    }
}

fn optional_int(t: Term) -> Result<Option<i128>, ()> {
    if t.decode::<rustler::Atom>().ok() == Some(atoms::nil()) {
        Ok(None)
    } else if let Ok(i) = t.decode::<i64>() {
        Ok(Some(i128::from(i)))
    } else {
        t.decode::<u64>()
            .map(|u| Some(i128::from(u)))
            .map_err(|_| ())
    }
}

/// Decode a stored segment into `[%Pulse.Record.Log{}]`, keeping only
/// records inside `[start_ts, end_ts]` (either may be nil) and with the
/// given service (nil for any). Returns `{:ok, records}` or `:fallback`.
#[rustler::nif(schedule = "DirtyCpu")]
fn decode_log_segment<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start_ts: Term<'a>,
    end_ts: Term<'a>,
    service: Term<'a>,
) -> Term<'a> {
    let (Ok(start), Ok(end)) = (optional_int(start_ts), optional_int(end_ts)) else {
        return atoms::fallback().encode(env);
    };
    let service_bin: Option<Binary> = service.decode().ok();
    if service_bin.is_none() && service.decode::<rustler::Atom>().ok() != Some(atoms::nil()) {
        return atoms::fallback().encode(env);
    }
    let filter = segment::Filter {
        start,
        end,
        service: service_bin.as_ref().map(|b| b.as_slice()),
    };
    match segment::decode(env, &blob, &filter) {
        Ok(records) => (atoms::ok(), records).encode(env),
        Err(_) => atoms::fallback().encode(env),
    }
}

/// Encode `[%Pulse.Record.Log{}]` as an Apache Parquet segment for the
/// S3 storage adapter. Returns `{:ok, binary, min_ts, max_ts, count}` on
/// success or `:fallback` on any Rust-side failure — the Elixir side
/// treats `:fallback` here as a hard error rather than falling back to
/// pure Elixir, since there is no Elixir Parquet encoder.
#[rustler::nif(schedule = "DirtyCpu")]
fn encode_log_segment_parquet_v2<'a>(env: Env<'a>, records: Term<'a>) -> Term<'a> {
    match segment_parquet::encode(env, records) {
        Ok((buf, b)) => (
            atoms::ok(),
            buf,
            integer(env, b.min_ts),
            integer(env, b.max_ts),
            b.count,
        )
            .encode(env),
        Err(EncodeError::TooBig) => error(env, atoms::payload_too_large()),
        Err(_) => atoms::fallback().encode(env),
    }
}

/// Decode a Parquet segment into `[%Pulse.Record.Log{}]`, applying
/// four categories of pushdown filter before any Erlang term is built:
///
///   * `start_ts` / `end_ts` — row-group `timestamp_ns` stats prune
///     whole row groups; per-row check then rejects the rest.
///   * `service` (a binary or `nil`) — kept on its own arg because
///     `service` is a dictionary-encoded column and matching against it
///     is faster than an equivalent matcher against `resource`.
///   * `matchers` — a list of `{name, op, value}` tuples evaluated
///     against the row's `resource` JSON. `op` is one of `:eq | :neq |
///     :re | :nre`. Regex ops compile the pattern once here.
///   * `line_filters` — a list of `{op, value}` tuples evaluated against
///     the row's raw `body` bytes. `op` is one of `:contains |
///     :not_contains | :match_re | :not_match_re`.
///
/// Any element the NIF cannot decode returns `:fallback`; the Elixir
/// side treats that as a hard error and does not silently drop the
/// pushdown — a Parquet segment lacks the Elixir reference
/// implementation the JSON codecs have.
#[rustler::nif(schedule = "DirtyCpu")]
fn decode_log_segment_parquet_v2<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start_ts: Term<'a>,
    end_ts: Term<'a>,
    service: Term<'a>,
    matchers: Term<'a>,
    line_filters: Term<'a>,
) -> Term<'a> {
    decode_logs(
        env,
        blob,
        (start_ts, end_ts, service, matchers, line_filters),
        None,
        None,
    )
}

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
fn decode_log_segment_parquet_bounded<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start_ts: Term<'a>,
    end_ts: Term<'a>,
    service: Term<'a>,
    matchers: Term<'a>,
    line_filters: Term<'a>,
    max_records: usize,
) -> Term<'a> {
    decode_logs(
        env,
        blob,
        (start_ts, end_ts, service, matchers, line_filters),
        Some(max_records),
        None,
    )
}

#[rustler::nif(schedule = "DirtyCpu")]
#[allow(clippy::too_many_arguments)]
fn decode_log_segment_parquet_limited<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start_ts: Term<'a>,
    end_ts: Term<'a>,
    service: Term<'a>,
    matchers: Term<'a>,
    line_filters: Term<'a>,
    max_records: Option<usize>,
    max_decoded_bytes: usize,
) -> Term<'a> {
    decode_logs(
        env,
        blob,
        (start_ts, end_ts, service, matchers, line_filters),
        max_records,
        Some(max_decoded_bytes),
    )
}

fn decode_logs<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    (start_ts, end_ts, service, matchers, line_filters): (
        Term<'a>,
        Term<'a>,
        Term<'a>,
        Term<'a>,
        Term<'a>,
    ),
    max_records: Option<usize>,
    max_decoded_bytes: Option<usize>,
) -> Term<'a> {
    let (Ok(start), Ok(end)) = (optional_int(start_ts), optional_int(end_ts)) else {
        return atoms::fallback().encode(env);
    };
    let service_bin: Option<Binary> = service.decode().ok();
    if service_bin.is_none() && service.decode::<rustler::Atom>().ok() != Some(atoms::nil()) {
        return atoms::fallback().encode(env);
    }
    let matchers_vec = match decode_matchers(matchers) {
        Ok(v) => v,
        Err(_) => return atoms::fallback().encode(env),
    };
    let line_filters_vec = match decode_line_filters(line_filters) {
        Ok(v) => v,
        Err(_) => return atoms::fallback().encode(env),
    };
    let filter = segment_parquet::Filter {
        start,
        end,
        service: service_bin.as_ref().map(|b| b.as_slice()),
        matchers: matchers_vec,
        line_filters: line_filters_vec,
        max_records,
        max_decoded_bytes,
    };
    match segment_parquet::decode(env, &blob, &filter) {
        Ok((records, bytes)) if max_decoded_bytes.is_some() => {
            (atoms::ok(), records, bytes).encode(env)
        }
        Ok((records, _)) => (atoms::ok(), records).encode(env),
        Err(segment_parquet::DecodeError::TooManyRecords) => {
            (atoms::error(), atoms::query_sample_limit()).encode(env)
        }
        Err(segment_parquet::DecodeError::TooManyDecodedBytes) => {
            (atoms::error(), atoms::query_decoded_limit()).encode(env)
        }
        Err(_) => atoms::fallback().encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn otlp_json_decode<'a>(env: Env<'a>, body: Binary<'a>) -> Term<'a> {
    match otlp_json::decode(env, body) {
        Ok(value) => (atoms::ok(), value).encode(env),
        Err(_) => atoms::fallback().encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn otlp_json_decode_scoped<'a>(env: Env<'a>, body: Binary<'a>, signal: rustler::Atom) -> Term<'a> {
    let schema = if signal == atoms::logs() {
        otlp_traces::Schema::ExportLogs
    } else if signal == atoms::metrics() {
        otlp_traces::Schema::ExportMetrics
    } else if signal == atoms::traces() {
        otlp_traces::Schema::Export
    } else {
        return atoms::fallback().encode(env);
    };
    match otlp_json::decode_scoped(env, body, Some(schema)) {
        Ok(value) => (atoms::ok(), value).encode(env),
        Err(_) => atoms::fallback().encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn otlp_json_negative_zero<'a>(env: Env<'a>, body: Binary<'a>) -> Binary<'a> {
    otlp_json::negative_zero(env, body)
}

#[rustler::nif]
fn log_metadata_api_version() -> u32 {
    1
}

#[rustler::nif]
fn trace_metadata_api_version() -> u32 {
    2
}

#[rustler::nif(schedule = "DirtyCpu")]
fn trace_payload_size<'a>(env: Env<'a>, records: Term<'a>, limit: usize) -> Term<'a> {
    match trace_segment_parquet::payload_size(env, records, limit) {
        Ok(size) => (atoms::ok(), size).encode(env),
        Err(EncodeError::TooBig) => error(env, atoms::payload_too_large()),
        Err(_) => error(env, atoms::invalid_otlp()),
    }
}

#[rustler::nif]
fn metric_metadata_api_version() -> u32 {
    2
}

#[rustler::nif]
fn otlp_wire_api_version() -> u32 {
    3
}

#[rustler::nif]
fn otlp_metrics_api_version() -> u32 {
    2
}

#[rustler::nif(schedule = "DirtyCpu")]
fn log_payload_size<'a>(env: Env<'a>, records: Term<'a>, limit: usize) -> Term<'a> {
    match segment_parquet::payload_size(env, records, limit) {
        Ok(size) => (atoms::ok(), size).encode(env),
        Err(EncodeError::TooBig) => error(env, atoms::payload_too_large()),
        Err(_) => error(env, atoms::invalid_otlp()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn metric_metadata_size<'a>(env: Env<'a>, samples: Term<'a>, limit: usize) -> Term<'a> {
    match metric_segment_parquet::metadata_size(env, samples, limit) {
        Ok(size) => (atoms::ok(), size).encode(env),
        Err(metric_segment_parquet::EncodeError::PayloadTooLarge) => {
            error(env, atoms::payload_too_large())
        }
        Err(_) => error(env, atoms::invalid_otlp()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn decode_otlp_metrics<'a>(
    env: Env<'a>,
    body: Binary<'a>,
    limits: otlp_traces::Options,
) -> Term<'a> {
    match otlp_traces::decode_metrics(env, body.as_slice(), limits) {
        Ok(payload) => (atoms::ok(), payload).encode(env),
        Err(reason) => error(
            env,
            match reason {
                otlp_traces::Error::InvalidProtobuf => atoms::invalid_protobuf(),
                otlp_traces::Error::TooManyRecords => atoms::too_many_records(),
                otlp_traces::Error::AttributesTooLarge => atoms::attributes_too_large(),
                otlp_traces::Error::TooManyNodes => atoms::too_many_otlp_nodes(),
            },
        ),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn decode_otlp_logs<'a>(env: Env<'a>, body: Binary<'a>, limits: otlp_traces::Options) -> Term<'a> {
    match otlp_traces::decode_logs(env, body.as_slice(), limits) {
        Ok(payload) => (atoms::ok(), payload).encode(env),
        Err(error) => {
            let reason = match error {
                otlp_traces::Error::InvalidProtobuf => atoms::invalid_protobuf(),
                otlp_traces::Error::TooManyRecords => atoms::too_many_records(),
                otlp_traces::Error::AttributesTooLarge => atoms::attributes_too_large(),
                otlp_traces::Error::TooManyNodes => atoms::too_many_otlp_nodes(),
            };
            (atoms::error(), reason).encode(env)
        }
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn decode_otlp_traces<'a>(
    env: Env<'a>,
    body: Binary<'a>,
    limits: otlp_traces::Options,
) -> Term<'a> {
    match otlp_traces::decode(env, body.as_slice(), limits) {
        Ok(payload) => (atoms::ok(), payload).encode(env),
        Err(error) => {
            let reason = match error {
                otlp_traces::Error::InvalidProtobuf => atoms::invalid_protobuf(),
                otlp_traces::Error::TooManyRecords => atoms::too_many_records(),
                otlp_traces::Error::AttributesTooLarge => atoms::attributes_too_large(),
                otlp_traces::Error::TooManyNodes => atoms::too_many_trace_nodes(),
            };
            (atoms::error(), reason).encode(env)
        }
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn encode_trace_segment_parquet<'a>(env: Env<'a>, records: Term<'a>) -> Term<'a> {
    encode_trace_segment_impl(env, records, false)
}
#[rustler::nif(schedule = "DirtyCpu")]
fn encode_trace_segment_parquet_v2<'a>(env: Env<'a>, records: Term<'a>) -> Term<'a> {
    encode_trace_segment_impl(env, records, true)
}
fn encode_trace_segment_impl<'a>(env: Env<'a>, records: Term<'a>, proof: bool) -> Term<'a> {
    match trace_segment_parquet::encode(env, records) {
        Ok((blob, min, max, count, safe)) => {
            if proof {
                (atoms::ok(), blob, min, max, count, safe).encode(env)
            } else {
                (atoms::ok(), blob, min, max, count).encode(env)
            }
        }
        Err(trace_segment_parquet::Error::PayloadTooLarge) => {
            error(env, atoms::payload_too_large())
        }
        Err(trace_segment_parquet::Error::InvalidProjection) if proof => {
            error(env, atoms::trace_projection_invalid())
        }
        Err(_) => atoms::fallback().encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn compact_trace_segments<'a>(env: Env<'a>, blobs: Term<'a>, max_rows: usize) -> Term<'a> {
    compact_trace_segments_impl(env, blobs, max_rows, false)
}
#[rustler::nif(schedule = "DirtyCpu")]
fn compact_trace_segments_v2<'a>(env: Env<'a>, blobs: Term<'a>, max_rows: usize) -> Term<'a> {
    compact_trace_segments_impl(env, blobs, max_rows, true)
}
fn compact_trace_segments_impl<'a>(
    env: Env<'a>,
    blobs: Term<'a>,
    max_rows: usize,
    proof: bool,
) -> Term<'a> {
    if max_rows == 0
        || max_rows > 100_000
        || blobs.list_length().is_err()
        || blobs.list_length().unwrap() > 32
    {
        return atoms::fallback().encode(env);
    }
    match trace_segment_parquet::compact(env, blobs, max_rows) {
        Ok((blob, min, max, count, services, ids, safe)) => {
            if proof {
                (atoms::ok(), blob, min, max, count, (services, ids, safe)).encode(env)
            } else {
                (atoms::ok(), blob, min, max, count, services, ids).encode(env)
            }
        }
        Err(trace_segment_parquet::Error::PayloadTooLarge) => {
            error(env, atoms::payload_too_large())
        }
        Err(trace_segment_parquet::Error::InvalidProjection) if proof => {
            error(env, atoms::trace_projection_invalid())
        }
        Err(trace_segment_parquet::Error::TooMany) => error(env, atoms::query_sample_limit()),
        Err(_) => atoms::fallback().encode(env),
    }
}

/// Merge up to 1024 trace segments into outputs partitioned by service, by
/// error/event class and by at most `max_ids` (`max_flagged_ids`) trace IDs:
/// `{:ok, [{blob, min_ts, max_ts, count, {services, ids, proof}, {statuses, events?}}]}`.
#[rustler::nif(schedule = "DirtyCpu")]
fn compact_trace_segments_split<'a>(
    env: Env<'a>,
    blobs: Term<'a>,
    max_rows: usize,
    max_ids: usize,
    max_flagged_ids: usize,
    max_output_rows: usize,
) -> Term<'a> {
    if max_rows == 0
        || max_rows > 100_000
        || max_ids == 0
        || max_flagged_ids == 0
        || max_output_rows == 0
        || blobs.list_length().map_or(true, |n| n > 1024)
    {
        return atoms::fallback().encode(env);
    }
    match trace_segment_parquet::compact_split(
        env,
        blobs,
        max_rows,
        max_ids,
        max_flagged_ids,
        max_output_rows,
    ) {
        Ok(outputs) => (atoms::ok(), outputs).encode(env),
        Err(trace_segment_parquet::Error::PayloadTooLarge) => {
            error(env, atoms::payload_too_large())
        }
        Err(trace_segment_parquet::Error::InvalidProjection) => {
            error(env, atoms::trace_projection_invalid())
        }
        Err(trace_segment_parquet::Error::TooMany) => error(env, atoms::query_sample_limit()),
        Err(_) => atoms::fallback().encode(env),
    }
}

/// Streaming counterpart of `decode_log_segment_parquet_v2`: the same
/// filters, decoded a bounded chunk at a time by `log_segment_reader_next`.
pub struct LogSegmentReader(std::sync::Mutex<Option<segment_parquet::Reader>>);

#[rustler::resource_impl]
impl rustler::Resource for LogSegmentReader {}

#[rustler::nif(schedule = "DirtyCpu")]
fn log_segment_reader_new<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start_ts: Term<'a>,
    end_ts: Term<'a>,
    service: Term<'a>,
    matchers: Term<'a>,
    line_filters: Term<'a>,
) -> Term<'a> {
    let (Ok(start), Ok(end)) = (optional_int(start_ts), optional_int(end_ts)) else {
        return atoms::fallback().encode(env);
    };
    let service_bin: Option<Binary> = service.decode().ok();
    if service_bin.is_none() && service.decode::<rustler::Atom>().ok() != Some(atoms::nil()) {
        return atoms::fallback().encode(env);
    }
    let (Ok(matchers), Ok(line_filters)) =
        (decode_matchers(matchers), decode_line_filters(line_filters))
    else {
        return atoms::fallback().encode(env);
    };
    let filter = segment_parquet::Filter {
        start,
        end,
        service: service_bin.as_ref().map(|b| b.as_slice()),
        matchers,
        line_filters,
        max_records: None,
        max_decoded_bytes: None,
    };
    match segment_parquet::Reader::new(&blob, filter) {
        Ok(reader) => (
            atoms::ok(),
            rustler::ResourceArc::new(LogSegmentReader(std::sync::Mutex::new(reader))),
        )
            .encode(env),
        Err(_) => atoms::fallback().encode(env),
    }
}

/// `{:ok, records}` with at least `min_records` records unless the segment
/// ends first, `:done` once exhausted, `:fallback` on a corrupt segment.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_segment_reader_next<'a>(
    env: Env<'a>,
    reader: rustler::ResourceArc<LogSegmentReader>,
    min_records: usize,
) -> Term<'a> {
    let Ok(mut guard) = reader.0.lock() else {
        return atoms::fallback().encode(env);
    };
    let Some(state) = guard.as_mut() else {
        return atoms::done().encode(env);
    };
    match state.next(env, min_records.max(1)) {
        Ok(Some(records)) => (atoms::ok(), records).encode(env),
        Ok(None) => {
            guard.take();
            atoms::done().encode(env)
        }
        Err(_) => {
            guard.take();
            atoms::fallback().encode(env)
        }
    }
}

/// Merge up to 32 log Parquet segments natively into one replacement:
/// `{:ok, blob, min_ts, max_ts, count, services | nil, included}`, where
/// `included` lists the indices of the sources whose decoded strings fit the
/// merge's bound together (see `segment_parquet::compact`). Mirrors
/// `compact_trace_segments_v2`; records never become Erlang terms.
#[rustler::nif(schedule = "DirtyCpu")]
fn compact_log_segments<'a>(env: Env<'a>, blobs: Term<'a>, max_rows: usize) -> Term<'a> {
    if max_rows == 0 || max_rows > 100_000 || blobs.list_length().map_or(true, |n| n > 32) {
        return atoms::fallback().encode(env);
    }
    match segment_parquet::compact(env, blobs, max_rows) {
        Ok((blob, b, services, included)) => (
            atoms::ok(),
            blob,
            integer(env, b.min_ts),
            integer(env, b.max_ts),
            b.count,
            services,
            included,
        )
            .encode(env),
        Err(segment_parquet::CompactError::PayloadTooLarge) => {
            error(env, atoms::payload_too_large())
        }
        Err(segment_parquet::CompactError::TooMany) => error(env, atoms::query_sample_limit()),
        Err(segment_parquet::CompactError::Invalid) => atoms::fallback().encode(env),
    }
}

/// Row count of a log segment, verified against its row groups.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_segment_parquet_row_count<'a>(env: Env<'a>, blob: Binary<'a>) -> Term<'a> {
    match trace_segment_parquet::row_count(blob) {
        Ok(count) => (atoms::ok(), count).encode(env),
        Err(_) => atoms::fallback().encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn trace_segment_parquet_row_count<'a>(env: Env<'a>, blob: Binary<'a>) -> Term<'a> {
    match trace_segment_parquet::row_count(blob) {
        Ok(count) => (atoms::ok(), count).encode(env),
        Err(_) => atoms::fallback().encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn decode_trace_segment_parquet<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start: Term<'a>,
    end: Term<'a>,
    filters: Term<'a>,
    max: usize,
) -> Term<'a> {
    let (Ok(start), Ok(end)) = (optional_int(start), optional_int(end)) else {
        return atoms::fallback().encode(env);
    };
    match trace_segment_parquet::decode(env, blob, start, end, filters, max) {
        Ok(records) => (atoms::ok(), records).encode(env),
        Err(trace_segment_parquet::Error::TooMany) => {
            (atoms::error(), atoms::query_sample_limit()).encode(env)
        }
        Err(trace_segment_parquet::Error::QueryBytes) => error(env, atoms::query_resource_limit()),
        Err(_) => atoms::fallback().encode(env),
    }
}

/// Encode `[%Pulse.Record.MetricSample{}]` as an Apache Parquet segment
/// for the metrics S3 storage path. Returns
/// `{:ok, binary, min_ts, max_ts, count}` on success or `:fallback`.
#[rustler::nif(schedule = "DirtyCpu")]
fn encode_metric_segment_parquet_v2<'a>(env: Env<'a>, samples: Term<'a>) -> Term<'a> {
    encode_metrics(env, samples, false)
}

#[rustler::nif]
fn metric_postings_api_version() -> u32 {
    1
}

#[rustler::nif(schedule = "DirtyCpu")]
fn encode_metric_segment_parquet_indexed_v1<'a>(env: Env<'a>, samples: Term<'a>) -> Term<'a> {
    encode_metrics(env, samples, true)
}

fn encode_metrics<'a>(env: Env<'a>, samples: Term<'a>, indexed: bool) -> Term<'a> {
    match metric_segment_parquet::encode(env, samples, indexed) {
        Ok((buf, b)) => (
            atoms::ok(),
            buf,
            integer(env, b.min_ts),
            integer(env, b.max_ts),
            b.count,
        )
            .encode(env),
        Err(metric_segment_parquet::EncodeError::PayloadTooLarge) => {
            error(env, atoms::payload_too_large())
        }
        Err(_) => atoms::fallback().encode(env),
    }
}

/// Decode a metric Parquet segment into
/// `[%Pulse.Record.MetricSample{}]`, keeping only samples inside
/// `[start_ts, end_ts]` and matching every supplied label matcher.
/// Matchers are a list of `{name :: binary, op :: :eq | :neq | :re | :nre, value :: binary}`.
#[rustler::nif(schedule = "DirtyCpu")]
fn decode_metric_segment_parquet_v2<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start_ts: Term<'a>,
    end_ts: Term<'a>,
    matchers: Term<'a>,
) -> Term<'a> {
    decode_metrics(
        env,
        blob,
        start_ts,
        end_ts,
        matchers,
        None,
        None,
        MetricDecode::Records,
    )
}

/// Like `decode_metric_segment_parquet_v2`, keeping only samples that carry
/// exemplars, for exemplar queries.
#[rustler::nif(schedule = "DirtyCpu")]
fn decode_metric_exemplars_parquet<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start_ts: Term<'a>,
    end_ts: Term<'a>,
    matchers: Term<'a>,
) -> Term<'a> {
    decode_metrics(
        env,
        blob,
        start_ts,
        end_ts,
        matchers,
        None,
        None,
        MetricDecode::Exemplars,
    )
}

#[rustler::nif(schedule = "DirtyCpu")]
fn decode_metric_segment_parquet_bounded_v2<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start_ts: Term<'a>,
    end_ts: Term<'a>,
    matchers: Term<'a>,
    max_samples: usize,
) -> Term<'a> {
    decode_metrics(
        env,
        blob,
        start_ts,
        end_ts,
        matchers,
        Some(max_samples),
        None,
        MetricDecode::Records,
    )
}

pub struct MetricSegmentReader(std::sync::Mutex<Option<metric_segment_parquet::Reader>>);

#[rustler::resource_impl]
impl rustler::Resource for MetricSegmentReader {}

#[rustler::nif]
fn metric_reader_api_version() -> u32 {
    1
}

#[rustler::nif(schedule = "DirtyCpu")]
fn metric_segment_reader_new<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start: Term<'a>,
    end: Term<'a>,
    matchers: Term<'a>,
) -> Term<'a> {
    decode_metrics(
        env,
        blob,
        start,
        end,
        matchers,
        None,
        None,
        MetricDecode::Reader,
    )
}

#[rustler::nif(schedule = "DirtyCpu")]
fn metric_segment_reader_next<'a>(
    env: Env<'a>,
    reader: rustler::ResourceArc<MetricSegmentReader>,
    max_samples: usize,
) -> Term<'a> {
    let Ok(mut guard) = reader.0.lock() else {
        return atoms::fallback().encode(env);
    };
    let Some(state) = guard.as_mut() else {
        return atoms::done().encode(env);
    };
    match state.next(env, max_samples) {
        Ok(Some(records)) => (atoms::ok(), records).encode(env),
        Ok(None) => {
            guard.take();
            atoms::done().encode(env)
        }
        Err(reason) => {
            guard.take();
            match reason {
                metric_segment_parquet::DecodeError::TooManySamples => {
                    error(env, atoms::query_sample_limit())
                }
                _ => atoms::fallback().encode(env),
            }
        }
    }
}

enum MetricDecode {
    Records,
    Exemplars,
    Reader,
}

#[allow(clippy::too_many_arguments)]
fn decode_metrics<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start_ts: Term<'a>,
    end_ts: Term<'a>,
    matchers: Term<'a>,
    max_samples: Option<usize>,
    footer_size: Option<u64>,
    mode: MetricDecode,
) -> Term<'a> {
    let (Ok(start), Ok(end)) = (optional_int(start_ts), optional_int(end_ts)) else {
        return atoms::fallback().encode(env);
    };
    let Ok(matcher_iter) = matchers.decode::<ListIterator>() else {
        return atoms::fallback().encode(env);
    };
    // Borrow the raw bytes from the matcher value binaries through the
    // owning `Binary` list we keep alive via `_owners`.
    let mut owners: Vec<(Binary, Binary, metric_segment_parquet::MatcherOp)> = Vec::new();
    for term in matcher_iter {
        let Ok((name, op_atom, value)): Result<(Binary, rustler::Atom, Binary), _> = term.decode()
        else {
            return atoms::fallback().encode(env);
        };
        let op = if op_atom == atoms::eq() {
            metric_segment_parquet::MatcherOp::Eq
        } else if op_atom == atoms::neq() {
            metric_segment_parquet::MatcherOp::Neq
        } else if op_atom == atoms::re() {
            metric_segment_parquet::MatcherOp::Re
        } else if op_atom == atoms::nre() {
            metric_segment_parquet::MatcherOp::Nre
        } else {
            return atoms::fallback().encode(env);
        };
        owners.push((name, value, op));
    }
    let matcher_views: Vec<metric_segment_parquet::Matcher> = owners
        .iter()
        .map(|(n, v, op)| metric_segment_parquet::Matcher {
            name: n.as_slice(),
            value: v.as_slice(),
            op: *op,
        })
        .collect();
    let filter = metric_segment_parquet::Filter {
        start,
        end,
        matchers: matcher_views,
        max_samples,
        exemplars_only: matches!(mode, MetricDecode::Exemplars),
    };
    if let Some(size) = footer_size {
        return match metric_footer::plan(erlang_bytes::from_binary(blob), size, &filter) {
            metric_footer::Plan::Scan { rows, empty } => (atoms::ok(), rows, empty).encode(env),
            metric_footer::Plan::More(bytes) => (atoms::ok(), atoms::more(), bytes).encode(env),
            metric_footer::Plan::Unknown => atoms::fallback().encode(env),
        };
    }
    if matches!(mode, MetricDecode::Reader) {
        return match metric_segment_parquet::Reader::new(&blob, &filter) {
            Ok(reader) => (
                atoms::ok(),
                rustler::ResourceArc::new(MetricSegmentReader(std::sync::Mutex::new(Some(reader)))),
            )
                .encode(env),
            Err(_) => atoms::fallback().encode(env),
        };
    }
    match metric_segment_parquet::decode(env, &blob, &filter) {
        Ok(records) => (atoms::ok(), records).encode(env),
        Err(metric_segment_parquet::DecodeError::TooManySamples) => {
            (atoms::error(), atoms::query_sample_limit()).encode(env)
        }
        Err(_) => atoms::fallback().encode(env),
    }
}

#[rustler::nif]
fn metric_footer_api_version() -> u32 {
    1
}

#[rustler::nif(schedule = "DirtyCpu")]
fn metric_segment_footer_plan<'a>(
    env: Env<'a>,
    tail: Binary<'a>,
    size: u64,
    start: Term<'a>,
    end: Term<'a>,
    matchers: Term<'a>,
) -> Term<'a> {
    decode_metrics(
        env,
        tail,
        start,
        end,
        matchers,
        None,
        Some(size),
        MetricDecode::Records,
    )
}

#[rustler::nif(schedule = "DirtyCpu")]
fn validate_metric_regex(pattern: &str) -> rustler::Atom {
    if metric_segment_parquet::compile_metric_regex(pattern).is_ok() {
        atoms::ok()
    } else {
        atoms::error()
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn validate_log_regex(pattern: &str) -> rustler::Atom {
    if query_regex::bytes(pattern).is_ok() {
        atoms::ok()
    } else {
        atoms::error()
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn match_metric_regex(pattern: &str, value: &str) -> NifResult<bool> {
    let regex = metric_segment_parquet::compile_metric_regex(pattern)
        .map_err(|_| rustler::Error::BadArg)?;
    Ok(regex.is_match(value))
}

/// Decode a Snappy-compressed Prometheus remote_write v1
/// `WriteRequest`. Returns `{:ok, series, rejected}` where each entry
/// of `series` is `{labels_map, [{ts_ms, value}, …], series_id}`.
///
/// `labels_map` is `%{binary => binary}`, `ts_ms` is milliseconds (the
/// Prometheus unit, not nanoseconds — the Elixir caller rescales),
/// `series_id` is the Prometheus-compatible `labels.StableHash`
/// digest (see `src/stable_hash.rs`).
#[rustler::nif(schedule = "DirtyCpu")]
fn decode_remote_write<'a>(
    env: Env<'a>,
    compressed: Binary<'a>,
    max_decompressed: usize,
) -> NifResult<Term<'a>> {
    decode_remote_write_inner(env, compressed, max_decompressed, None, false)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn decode_remote_write_limited<'a>(
    env: Env<'a>,
    compressed: Binary<'a>,
    max_decompressed: usize,
    options: ingest_limits::Options,
) -> NifResult<Term<'a>> {
    decode_remote_write_inner(
        env,
        compressed,
        max_decompressed,
        Some(options.into()),
        false,
    )
}

/// Like `decode_remote_write_limited`, for a Remote Write 2.0
/// `io.prometheus.write.v2.Request` (`remote_write::decode_v2`), with the same
/// result shape.
#[rustler::nif(schedule = "DirtyCpu")]
fn decode_remote_write_v2_limited<'a>(
    env: Env<'a>,
    compressed: Binary<'a>,
    max_decompressed: usize,
    options: ingest_limits::Options,
) -> NifResult<Term<'a>> {
    decode_remote_write_inner(
        env,
        compressed,
        max_decompressed,
        Some(options.into()),
        true,
    )
}

fn decode_remote_write_inner<'a>(
    env: Env<'a>,
    compressed: Binary<'a>,
    max_decompressed: usize,
    limits: Option<ingest_limits::Limits>,
    v2: bool,
) -> NifResult<Term<'a>> {
    let input = compressed.as_slice();
    let len = match snap::raw::decompress_len(input) {
        Ok(len) => len,
        Err(_) => return Ok(error(env, atoms::invalid_snappy())),
    };
    if len > max_decompressed {
        return Ok(error(env, atoms::payload_too_large()));
    }

    let mut buffer = NewBinary::new(env, len);
    match snap::raw::Decoder::new().decompress(input, buffer.as_mut_slice()) {
        Ok(written) if written == len => {}
        _ => return Ok(error(env, atoms::invalid_snappy())),
    }
    let buffer: Binary = buffer.into();

    if let Some(limits) = limits {
        let preflight = if v2 {
            limits.remote_write_v2(buffer.as_slice())
        } else {
            limits.remote_write(buffer.as_slice())
        };
        if let Err(reason) = preflight {
            return Ok(ingest_error(env, reason));
        }
    }

    let decoded = if v2 {
        remote_write::decode_v2(buffer.as_slice())
    } else {
        remote_write::decode(buffer.as_slice())
    };
    let decoded = match decoded {
        Some(d) => d,
        None => return Ok(error(env, atoms::invalid_protobuf())),
    };

    let mut series_terms: Vec<Term<'a>> = Vec::with_capacity(decoded.series.len());
    for series in &decoded.series {
        let mut names: Vec<Term<'a>> = Vec::with_capacity(series.labels.len());
        let mut values: Vec<Term<'a>> = Vec::with_capacity(series.labels.len());
        for (name, value) in &series.labels {
            names.push(slice(env, &buffer, name)?);
            values.push(slice(env, &buffer, value)?);
        }
        let labels_map = Term::map_from_arrays(env, &names, &values)?;
        let samples: Vec<Term<'a>> = series
            .samples
            .iter()
            .map(|s| {
                let ts = s.timestamp_ms.encode(env);
                let value = metric_value::encode(env, s.value);
                if v2 {
                    (ts, value, s.start_timestamp_ms).encode(env)
                } else {
                    (ts, value).encode(env)
                }
            })
            .collect();
        let sorted_pairs: Vec<(&[u8], &[u8])> =
            series.labels.iter().map(|(n, v)| (*n, *v)).collect();
        let series_id = stable_hash::stable_hash(sorted_pairs) as i64;
        let histograms: Vec<Term<'a>> = series
            .histograms
            .iter()
            .map(|(h, ts, start)| {
                if v2 {
                    (ts.encode(env), h.to_term(env), start).encode(env)
                } else {
                    (ts.encode(env), h.to_term(env)).encode(env)
                }
            })
            .collect();
        // Exemplar timestamps leave in nanoseconds, like stored ones.
        let exemplars: Vec<Term<'a>> = series
            .exemplars
            .iter()
            .map(|e| {
                exemplar::to_term(
                    env,
                    &e.labels,
                    e.value,
                    e.timestamp_ms.saturating_mul(1_000_000),
                )
            })
            .collect();
        series_terms.push((labels_map, samples, series_id, histograms, exemplars).encode(env));
    }

    let mut metadata_terms: Vec<Term<'a>> = Vec::with_capacity(decoded.metadata.len());
    for entry in &decoded.metadata {
        metadata_terms.push(
            (
                slice(env, &buffer, entry.name)?,
                entry.kind,
                slice(env, &buffer, entry.help)?,
                slice(env, &buffer, entry.unit)?,
            )
                .encode(env),
        );
    }

    Ok((atoms::ok(), series_terms, decoded.rejected, metadata_terms).encode(env))
}

// -- LogQL pushdown helpers for `decode_log_segment_parquet` ---------------
//
// These share the `MatchOp` / `LineFilterOp` enums with `query_filter`
// so the log Parquet decoder can push label matchers and line filters
// down to Rust. The metric decoder uses its own `MatcherOp` because its
// row shape and column set are different — a near-duplicate that is a
// documented follow-up when the two filter shapes converge.

pub(crate) fn decode_matchers(term: Term<'_>) -> Result<Vec<Matcher>, ()> {
    let list: Vec<Term> = term.decode().map_err(|_| ())?;
    let mut out = Vec::with_capacity(list.len());
    for item in list {
        let (name, op_atom, value): (Binary, rustler::Atom, Binary) =
            item.decode().map_err(|_| ())?;
        let op = decode_match_op(op_atom)?;
        let name_vec = name.as_slice().to_vec();
        let value_vec = value.as_slice().to_vec();
        match op {
            MatchOp::Re | MatchOp::Nre => {
                let pat = std::str::from_utf8(&value_vec).map_err(|_| ())?;
                let re = query_regex::bytes(pat).map_err(|_| ())?;
                out.push(Matcher::Regex {
                    name: name_vec,
                    op,
                    regex: re,
                });
            }
            MatchOp::Eq | MatchOp::Neq => out.push(Matcher::Literal {
                name: name_vec,
                op,
                value: value_vec,
            }),
        }
    }
    Ok(out)
}

fn decode_match_op(atom: rustler::Atom) -> Result<MatchOp, ()> {
    if atom == atoms::eq() {
        Ok(MatchOp::Eq)
    } else if atom == atoms::neq() {
        Ok(MatchOp::Neq)
    } else if atom == atoms::re() {
        Ok(MatchOp::Re)
    } else if atom == atoms::nre() {
        Ok(MatchOp::Nre)
    } else {
        Err(())
    }
}

pub(crate) fn decode_line_filters(term: Term<'_>) -> Result<Vec<LineFilter>, ()> {
    let list: Vec<Term> = term.decode().map_err(|_| ())?;
    let mut out = Vec::with_capacity(list.len());
    for item in list {
        let (op_atom, value): (rustler::Atom, Binary) = item.decode().map_err(|_| ())?;
        let op = decode_line_filter_op(op_atom)?;
        match op {
            LineFilterOp::Contains | LineFilterOp::NotContains => {
                let owned = value.as_slice().to_vec();
                out.push(LineFilter::Substring {
                    op,
                    finder: Box::new(Finder::new(&owned).into_owned()),
                });
            }
            LineFilterOp::MatchRe | LineFilterOp::NotMatchRe => {
                let pat = std::str::from_utf8(value.as_slice()).map_err(|_| ())?;
                let re = query_regex::bytes(pat).map_err(|_| ())?;
                out.push(LineFilter::Regex { op, regex: re });
            }
        }
    }
    Ok(out)
}

fn decode_line_filter_op(atom: rustler::Atom) -> Result<LineFilterOp, ()> {
    if atom == atoms::contains() {
        Ok(LineFilterOp::Contains)
    } else if atom == atoms::not_contains() {
        Ok(LineFilterOp::NotContains)
    } else if atom == atoms::match_re() {
        Ok(LineFilterOp::MatchRe)
    } else if atom == atoms::not_match_re() {
        Ok(LineFilterOp::NotMatchRe)
    } else {
        Err(())
    }
}

/// JSON-encode `[%Pulse.Record.MetricSample{}]` for the MCP
/// `query_metrics` response. Returns `{:ok, binary}` on success or
/// `:fallback` on any input the Rust encoder cannot guarantee to encode
/// with the same JSON values. The Elixir caller uses `JSON.encode!` then.
#[rustler::nif(schedule = "DirtyCpu")]
fn encode_metric_samples<'a>(env: Env<'a>, samples: Term<'a>) -> Term<'a> {
    match metric_json::encode(env, samples, metric_json::MAX_PAYLOAD) {
        Ok(buf) => (atoms::ok(), buf).encode(env),
        Err(crate::term_json::EncodeError::TooBig) => error(env, atoms::query_result_limit()),
        Err(_) => atoms::fallback().encode(env),
    }
}

// ---- stream-grouped log segments -------------------------------------------

#[rustler::nif]
fn log_tier_api_version() -> u32 {
    1
}

/// Rows of many log segments regrouped by service or stream (`log_tiers::Grouper`).
pub struct LogGrouper(std::sync::Mutex<Option<log_tiers::Grouper>>);

#[rustler::resource_impl]
impl rustler::Resource for LogGrouper {}

#[rustler::nif]
fn log_group_new<'a>(
    env: Env<'a>,
    target_rows: usize,
    target_bytes: usize,
    pack_bytes: usize,
    max_held: usize,
) -> Term<'a> {
    if target_rows == 0 || target_rows > 100_000 || target_bytes == 0 || pack_bytes == 0 {
        return atoms::fallback().encode(env);
    }
    let grouper = log_tiers::Grouper::new(
        target_rows,
        target_bytes.min(segment_parquet::MAX_COMPACT_STRING_BYTES),
        pack_bytes,
        max_held,
    );
    (
        atoms::ok(),
        rustler::ResourceArc::new(LogGrouper(std::sync::Mutex::new(Some(grouper)))),
    )
        .encode(env)
}

/// `{:ok, rows}` once one log segment's rows are held by group.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_group_add<'a>(
    env: Env<'a>,
    grouper: rustler::ResourceArc<LogGrouper>,
    blob: Binary<'a>,
) -> Term<'a> {
    let Ok(mut guard) = grouper.0.lock() else {
        return atoms::fallback().encode(env);
    };
    let Some(state) = guard.as_mut() else {
        return atoms::fallback().encode(env);
    };
    match state.add(erlang_bytes::from_binary(blob)) {
        Ok(rows) => (atoms::ok(), rows).encode(env),
        Err(_) => {
            // A partly added source can never be published.
            guard.take();
            error(env, atoms::invalid_segment())
        }
    }
}

/// The next output: `{:ok, {payload, min_ts, max_ts, rows, services | nil,
/// [{service | nil, resource}] | nil, [{minute, count}] | nil}}`, `:none`
/// while no output is due (only without `finish`), or `:done`.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_group_next<'a>(
    env: Env<'a>,
    grouper: rustler::ResourceArc<LogGrouper>,
    finish: bool,
) -> Term<'a> {
    let Ok(mut guard) = grouper.0.lock() else {
        return atoms::fallback().encode(env);
    };
    let Some(state) = guard.as_mut() else {
        return atoms::fallback().encode(env);
    };
    match state.next(env, finish) {
        Ok(Some(output)) => {
            let nil = rustler::types::atom::nil().to_term(env);
            let services = output.services.map_or(nil, |s| s.encode(env));
            let streams = output.streams.map_or(nil, |streams| {
                streams
                    .iter()
                    .map(|(service, resource)| {
                        let service = service.as_ref().map_or(nil, |s| s.encode(env));
                        (service, resource).encode(env)
                    })
                    .collect::<Vec<Term>>()
                    .encode(env)
            });
            let minutes = output.minutes.map_or(nil, |m| m.encode(env));
            let output = (
                output.payload,
                output.min_ts,
                output.max_ts,
                output.rows,
                services,
                streams,
                minutes,
            );
            (atoms::ok(), output).encode(env)
        }
        Ok(None) if finish => {
            guard.take();
            atoms::done().encode(env)
        }
        Ok(None) => atoms::none().encode(env),
        Err(_) => {
            guard.take();
            atoms::fallback().encode(env)
        }
    }
}

// ---- metric hour finalization and rollups ---------------------------------

#[rustler::nif]
fn metric_tier_api_version() -> u32 {
    2
}

/// Rows of the segments overlapping one hour, accumulated natively one
/// segment at a time by `metric_finalize_add` and encoded by
/// `metric_finalize_finish`. Records never become Erlang terms.
pub struct MetricFinalizer(std::sync::Mutex<Option<metric_tiers::Builder>>);

#[rustler::resource_impl]
impl rustler::Resource for MetricFinalizer {}

#[rustler::nif]
fn metric_finalize_new<'a>(
    env: Env<'a>,
    start: i64,
    end: i64,
    max_rows: usize,
    expected_rows: usize,
    partition: Term<'a>,
) -> Term<'a> {
    // nil, or `{index, count}`: keep only rows whose metric name hashes there.
    let partition = if partition == rustler::types::atom::nil().to_term(env) {
        None
    } else {
        match partition.decode::<(u32, u32)>() {
            Ok((index, count)) if count > 0 && index < count => Some((index, count)),
            _ => return atoms::fallback().encode(env),
        }
    };
    if start >= end || max_rows == 0 {
        return atoms::fallback().encode(env);
    }
    let builder = metric_tiers::Builder::new(start, end, max_rows, expected_rows, partition);
    (
        atoms::ok(),
        rustler::ResourceArc::new(MetricFinalizer(std::sync::Mutex::new(Some(builder)))),
    )
        .encode(env)
}

fn tier_error<'a>(env: Env<'a>, reason: metric_tiers::TierError) -> Term<'a> {
    match reason {
        metric_tiers::TierError::TooLarge => error(env, atoms::too_large()),
        metric_tiers::TierError::Invalid => error(env, atoms::invalid_segment()),
        metric_tiers::TierError::Encode => atoms::fallback().encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn metric_finalize_add<'a>(
    env: Env<'a>,
    finalizer: rustler::ResourceArc<MetricFinalizer>,
    blob: Binary<'a>,
) -> Term<'a> {
    let Ok(mut guard) = finalizer.0.lock() else {
        return atoms::fallback().encode(env);
    };
    let Some(builder) = guard.as_mut() else {
        return atoms::fallback().encode(env);
    };
    match builder.add(erlang_bytes::from_binary(blob)) {
        Ok(rows) => (atoms::ok(), rows).encode(env),
        Err(reason) => {
            // A failed add leaves a partial hour: it can never be finished.
            guard.take();
            tier_error(env, reason)
        }
    }
}

/// Order the accumulated rows and plan the outputs; `:ok`. Each output is
/// then encoded by one `metric_finalize_next` call.
#[rustler::nif(schedule = "DirtyCpu")]
fn metric_finalize_finish<'a>(
    env: Env<'a>,
    finalizer: rustler::ResourceArc<MetricFinalizer>,
    target_rows: usize,
    rollup_target_rows: usize,
    max_names: usize,
) -> Term<'a> {
    let Ok(mut guard) = finalizer.0.lock() else {
        return atoms::fallback().encode(env);
    };
    let Some(builder) = guard.as_mut() else {
        return atoms::fallback().encode(env);
    };
    builder.prepare(target_rows, rollup_target_rows, max_names.clamp(1, 128));
    atoms::ok().encode(env)
}

/// `{:ok, kind, {payload, min_ts, max_ts, rows, [labels]}}` for the next
/// planned output, with kind `:final`, `:before`, `:after` or `:rollup` and
/// one label map per series, or `:done`.
#[rustler::nif(schedule = "DirtyCpu")]
fn metric_finalize_next<'a>(
    env: Env<'a>,
    finalizer: rustler::ResourceArc<MetricFinalizer>,
) -> Term<'a> {
    let Ok(mut guard) = finalizer.0.lock() else {
        return atoms::fallback().encode(env);
    };
    let Some(builder) = guard.as_mut() else {
        return atoms::fallback().encode(env);
    };
    match builder.next(env) {
        Ok(Some((kind, output))) => {
            let mut cache = Vec::new();
            let output = tier_output(env, output, builder.series(), &mut cache);
            let kind = match kind {
                metric_tiers::Kind::Final => atoms::final_(),
                metric_tiers::Kind::Before => atoms::before(),
                metric_tiers::Kind::After => atoms::after(),
                metric_tiers::Kind::Rollup => atoms::rollup(),
            };
            (atoms::ok(), kind, output).encode(env)
        }
        Ok(None) => {
            guard.take();
            atoms::done().encode(env)
        }
        Err(reason) => {
            guard.take();
            tier_error(env, reason)
        }
    }
}

fn tier_output<'a>(
    env: Env<'a>,
    output: metric_tiers::Output<'a>,
    series: &metric_tiers::Series,
    cache: &mut Vec<Option<Term<'a>>>,
) -> Term<'a> {
    let labels: Vec<Term> = output
        .series
        .iter()
        .map(|index| series_labels(env, series, *index, cache))
        .collect();
    (
        output.payload,
        output.min_ts,
        output.max_ts,
        output.rows,
        labels,
    )
        .encode(env)
}

// One label map per series, built once per call from its canonical bytes.
fn series_labels<'a>(
    env: Env<'a>,
    series: &metric_tiers::Series,
    index: u32,
    cache: &mut Vec<Option<Term<'a>>>,
) -> Term<'a> {
    let index = index as usize;
    if cache.len() <= index {
        cache.resize(index + 1, None);
    }
    if let Some(term) = cache[index] {
        return term;
    }
    let mut pairs = Vec::new();
    let _ =
        metric_segment_parquet::parse_canonical_pairs(series.canonical(index as u32), &mut pairs);
    let binary = |bytes: &[u8]| {
        let mut b = NewBinary::new(env, bytes.len());
        b.as_mut_slice().copy_from_slice(bytes);
        Binary::from(b).encode(env)
    };
    let names: Vec<Term> = pairs.iter().map(|(n, _)| binary(n)).collect();
    let values: Vec<Term> = pairs.iter().map(|(_, v)| binary(v)).collect();
    let term =
        Term::map_from_arrays(env, &names, &values).unwrap_or_else(|_| atoms::nil().encode(env));
    cache[index] = Some(term);
    term
}

fn metric_matchers<'a>(
    matchers: Term<'a>,
) -> Option<Vec<(Binary<'a>, Binary<'a>, metric_segment_parquet::MatcherOp)>> {
    let mut owners = Vec::new();
    for term in matchers.decode::<ListIterator>().ok()? {
        let (name, op, value): (Binary, rustler::Atom, Binary) = term.decode().ok()?;
        let op = if op == atoms::eq() {
            metric_segment_parquet::MatcherOp::Eq
        } else if op == atoms::neq() {
            metric_segment_parquet::MatcherOp::Neq
        } else if op == atoms::re() {
            metric_segment_parquet::MatcherOp::Re
        } else if op == atoms::nre() {
            metric_segment_parquet::MatcherOp::Nre
        } else {
            return None;
        };
        owners.push((name, value, op));
    }
    Some(owners)
}

/// Rollup rows with buckets in `[start, end]` whose labels match:
/// `{:ok, [{labels, bucket, count, first_ts, first, last_ts, last, min, max,
/// changes, resets, reset_values, flags}]}`. Values use the sample encoding
/// of metric segments (`:nan`, `:infinity`, `:negative_infinity`).
#[rustler::nif(schedule = "DirtyCpu")]
fn decode_metric_rollups<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start_ts: Term<'a>,
    end_ts: Term<'a>,
    matchers: Term<'a>,
) -> Term<'a> {
    let (Ok(start), Ok(end), Some(owners)) = (
        optional_int(start_ts),
        optional_int(end_ts),
        metric_matchers(matchers),
    ) else {
        return atoms::fallback().encode(env);
    };
    let views: Vec<metric_segment_parquet::Matcher> = owners
        .iter()
        .map(|(n, v, op)| metric_segment_parquet::Matcher {
            name: n.as_slice(),
            value: v.as_slice(),
            op: *op,
        })
        .collect();
    match metric_tiers::decode_rollups(erlang_bytes::from_binary(blob), start, end, &views) {
        Ok((series, rows)) => {
            let mut cache = Vec::new();
            let value = |v: f64| metric_value::encode(env, v);
            let terms: Vec<Term> = rows
                .iter()
                .map(|a| {
                    let resets: Vec<Term> = a.reset_values.iter().map(|v| value(*v)).collect();
                    let fields = [
                        series_labels(env, &series, a.series, &mut cache),
                        a.bucket.encode(env),
                        a.count.encode(env),
                        a.first_ts.encode(env),
                        value(a.first),
                        a.last_ts.encode(env),
                        value(a.last),
                        value(a.min),
                        value(a.max),
                        a.changes.encode(env),
                        a.resets.encode(env),
                        resets.encode(env),
                        a.flags.encode(env),
                    ];
                    rustler::types::tuple::make_tuple(env, &fields)
                })
                .collect();
            (atoms::ok(), terms).encode(env)
        }
        Err(_) => atoms::fallback().encode(env),
    }
}

rustler::init!("Elixir.Pulse.Codec.NIF");
