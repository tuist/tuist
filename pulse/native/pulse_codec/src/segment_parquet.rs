//! Parquet log segment encoding and decoding.
//!
//! Fixed 10-column schema (Int64 / Int32 / Utf8 only), one row group per
//! segment, rows sorted by `(service, timestamp_ns)` on write so the
//! dictionary + zstd column encoding compresses tightly and the row-group
//! stats let a later query skip the whole segment. `attributes` and
//! `resource` always encode to a JSON string (empty map is `"{}"`);
//! `body` is a nullable JSON-encoded value.
//!
//! Memory contract:
//!   * Encode drops UTF-8 validation on `JsonEncoder` output — that
//!     encoder is documented to always emit valid UTF-8, and the O(n)
//!     re-scan of every JSON blob is not free.
//!   * Decode allocates one Erlang binary per string column per batch
//!     (the "arena"), and every returned string is a sub-binary of that
//!     arena. Cost: 7 fresh binaries per batch instead of 7 × row-count.
//!     A caller that retains a returned term keeps the whole column
//!     arena alive — callers past the query boundary should
//!     `:binary.copy/1` if that matters.
//!   * Row-group `timestamp_ns` min/max stats prune whole row groups
//!     before any column pages are read, so a segment outside the query
//!     range decodes to `[]` with no column-buffer allocations at all.
//!
//! Follow-ups worth doing when the query path is on the hot list:
//!   * Wrap the input Erlang binary in a `Bytes` without copying (needs
//!     ref-counted access, so either `rustler_sys` or a wrapper crate).
//!     Would remove one full-blob memcpy per read.
//!   * Arena the JSON blobs on encode too so the sort is by indices,
//!     not by owned strings.

use crate::json_read::{Fallback, Parser, Res, Stacks};
use crate::query_filter::{find_label, line_bytes_for_match, LineFilter, Matcher};
use crate::term_json::{Enc, EncodeError, InternedKeys, JsonEncoder, TermBuilder};

use arrow::array::{
    Array, Int32Array, Int32Builder, Int64Array, Int64Builder, RecordBatch, StringArray,
    StringBuilder,
};
use arrow::datatypes::{DataType, Field, Schema, SchemaRef};
use bytes::Bytes;
use parquet::arrow::arrow_reader::ParquetRecordBatchReaderBuilder;
use parquet::arrow::ArrowWriter;
use parquet::basic::{Compression, Encoding, ZstdLevel};
use parquet::column::reader::ColumnReader;
use parquet::file::metadata::RowGroupMetaData;
use parquet::file::properties::{EnabledStatistics, WriterProperties, WriterVersion};
use parquet::file::reader::FileReader;
use parquet::file::serialized_reader::SerializedFileReader;
use parquet::file::statistics::Statistics;
use parquet::schema::types::ColumnPath;
use rustler::types::atom;
use rustler::{Binary, Encoder, Env, ListIterator, NewBinary, Term};
use std::sync::Arc;

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

pub struct Bounds {
    pub min_ts: i128,
    pub max_ts: i128,
    pub count: usize,
}

pub struct Filter<'f> {
    pub start: Option<i128>,
    pub end: Option<i128>,
    pub service: Option<&'f [u8]>,
    pub matchers: Vec<Matcher>,
    pub line_filters: Vec<LineFilter>,
    pub max_records: Option<usize>,
    pub max_decoded_bytes: Option<usize>,
}

pub enum DecodeError {
    Fallback,
    TooManyRecords,
    TooManyDecodedBytes,
}

impl From<Fallback> for DecodeError {
    fn from(_: Fallback) -> Self {
        Self::Fallback
    }
}

struct Row {
    timestamp_ns: Option<i64>,
    observed_timestamp_ns: Option<i64>,
    severity_number: Option<i32>,
    severity_text: Option<Vec<u8>>,
    service: Option<Vec<u8>>,
    // JSON-encoded body value, `None` when the caller passed nil.
    body: Option<Vec<u8>>,
    trace_id: Option<Vec<u8>>,
    span_id: Option<Vec<u8>>,
    // JSON-encoded map, always populated (empty map is `"{}"`).
    attributes: Vec<u8>,
    resource: Vec<u8>,
    otlp: Option<Vec<u8>>,
}

pub const MAX_PAYLOAD: usize = 16 * 1024 * 1024;

pub fn payload_size<'a>(env: Env<'a>, records: Term<'a>, limit: usize) -> Enc<usize> {
    use crate::out::Sink;
    let mut counter = crate::out::Counter::new(limit);
    let enc = JsonEncoder::new(env, limit);
    crate::segment::encode(
        env,
        &mut counter,
        records,
        crate::segment::Mode::Storage,
        crate::segment::Framing::Array,
        &enc,
    )?;
    if counter.len() > limit {
        return Err(EncodeError::TooBig);
    }
    Ok(counter.len())
}

pub fn encode<'a>(env: Env<'a>, records: Term<'a>) -> Enc<(Binary<'a>, Bounds)> {
    // Prove total escaped JSON expansion before allocating any row buffers.
    payload_size(env, records, MAX_PAYLOAD)?;
    let len = records.list_length().map_err(|_| EncodeError::Fallback)?;
    let items: ListIterator = records.decode().map_err(|_| EncodeError::Fallback)?;
    let struct_key = atoms::struct_key().encode(env);
    let log = atoms::log().encode(env);
    let enc = JsonEncoder::new(env, usize::MAX);

    let mut rows: Vec<Row> = Vec::with_capacity(len);
    let mut bounds = Bounds {
        min_ts: i128::MAX,
        max_ts: i128::MIN,
        count: 0,
    };
    // Reused scratch buffer for JSON encoding, one allocation for the
    // whole batch instead of one per row × per string column.
    let mut scratch: Vec<u8> = Vec::with_capacity(256);

    for record in items {
        let tag = record
            .map_get(struct_key)
            .map_err(|_| EncodeError::Fallback)?;
        if tag.as_c_arg() != log.as_c_arg() {
            return Err(EncodeError::Fallback);
        }
        let row = extract_row(env, record, &enc, &mut bounds, &mut scratch)?;
        rows.push(row);
    }

    if bounds.count == 0 {
        bounds.min_ts = 0;
        bounds.max_ts = 0;
    }

    // Sort by (service, timestamp_ns) so records for the same service sit
    // next to each other on disk — dictionary + zstd on `service` and
    // delta encoding on `timestamp_ns` do most of their work here.
    rows.sort_by(|a, b| {
        a.service
            .cmp(&b.service)
            .then(a.timestamp_ns.cmp(&b.timestamp_ns))
    });

    let batch = build_batch(&rows).map_err(|_| EncodeError::Fallback)?;
    // Rough starting size: 64 B header + 32 B per row. Zstd will shrink
    // it further; growing the Vec is cheap enough that under-sizing is
    // fine, but starting large avoids the first few reallocs.
    let mut buf =
        crate::out::BinaryWriter(crate::out::BinSink::with_capacity(64 + rows.len() * 32));
    let props = writer_properties();
    let mut writer = ArrowWriter::try_new(&mut buf, batch.schema(), Some(props))
        .map_err(|_| EncodeError::Fallback)?;
    writer.write(&batch).map_err(|_| EncodeError::Fallback)?;
    writer.close().map_err(|_| EncodeError::Fallback)?;

    Ok((buf.0.finish(env), bounds))
}

fn extract_row<'a>(
    env: Env<'a>,
    record: Term<'a>,
    enc: &JsonEncoder<'a>,
    bounds: &mut Bounds,
    scratch: &mut Vec<u8>,
) -> Enc<Row> {
    let ts = extract_i64(record, atoms::timestamp_ns().encode(env), enc)?;
    let observed = extract_i64(record, atoms::observed_timestamp_ns().encode(env), enc)?;
    let sev_num = extract_i32(record, atoms::severity_number().encode(env), enc)?;
    let sev_text = extract_binary(record, atoms::severity_text().encode(env), enc)?;
    let service = extract_binary(record, atoms::service().encode(env), enc)?;

    let body_term = record
        .map_get(atoms::body().encode(env))
        .map_err(|_| EncodeError::Fallback)?;
    let body = if body_term == atom::nil().encode(env) {
        None
    } else {
        scratch.clear();
        enc.value(scratch, body_term, 1)?;
        Some(scratch.clone())
    };

    let trace_id = extract_binary(record, atoms::trace_id().encode(env), enc)?;
    let span_id = extract_binary(record, atoms::span_id().encode(env), enc)?;
    let attributes = extract_map_as_json(record, atoms::attributes().encode(env), enc, scratch)?;
    let resource = extract_map_as_json(record, atoms::resource().encode(env), enc, scratch)?;
    let otlp_term = record
        .map_get(atoms::otlp().encode(env))
        .map_err(|_| EncodeError::Fallback)?;
    let otlp = if otlp_term == atom::nil().encode(env) {
        None
    } else {
        Some(extract_map_as_json(
            record,
            atoms::otlp().encode(env),
            enc,
            scratch,
        )?)
    };

    // The caller-supplied `timestamp_ns` maps `nil` to `0`, matching the
    // NDJSON path in `Pulse.Storage.S3.caller_ts_bounds/1`.
    let ts_for_bounds: i128 = i128::from(ts.unwrap_or(0));
    bounds.min_ts = bounds.min_ts.min(ts_for_bounds);
    bounds.max_ts = bounds.max_ts.max(ts_for_bounds);
    bounds.count += 1;

    Ok(Row {
        timestamp_ns: ts,
        observed_timestamp_ns: observed,
        severity_number: sev_num,
        severity_text: sev_text,
        service,
        body,
        trace_id,
        span_id,
        attributes,
        resource,
        otlp,
    })
}

fn extract_i64<'a>(record: Term<'a>, key: Term<'a>, enc: &JsonEncoder<'a>) -> Enc<Option<i64>> {
    let value = record.map_get(key).map_err(|_| EncodeError::Fallback)?;
    if enc.is_nil_or_false(value) {
        return Ok(None);
    }
    if let Ok(i) = value.decode::<i64>() {
        return Ok(Some(i));
    }
    let u = value.decode::<u64>().map_err(|_| EncodeError::Fallback)?;
    i64::try_from(u)
        .map(Some)
        .map_err(|_| EncodeError::Fallback)
}

fn extract_i32<'a>(record: Term<'a>, key: Term<'a>, enc: &JsonEncoder<'a>) -> Enc<Option<i32>> {
    let value = record.map_get(key).map_err(|_| EncodeError::Fallback)?;
    if enc.is_nil_or_false(value) {
        return Ok(None);
    }
    value
        .decode::<i32>()
        .map(Some)
        .map_err(|_| EncodeError::Fallback)
}

fn extract_binary<'a>(
    record: Term<'a>,
    key: Term<'a>,
    enc: &JsonEncoder<'a>,
) -> Enc<Option<Vec<u8>>> {
    let value = record.map_get(key).map_err(|_| EncodeError::Fallback)?;
    if enc.is_nil_or_false(value) {
        return Ok(None);
    }
    let bin: Binary = value.decode().map_err(|_| EncodeError::Fallback)?;
    // Arrow's StringBuilder validates UTF-8 on `append_value(&str)`, so
    // reject non-UTF-8 here to surface a clean Fallback rather than an
    // Arrow error mid-batch.
    simdutf8::basic::from_utf8(bin.as_slice()).map_err(|_| EncodeError::Fallback)?;
    Ok(Some(bin.as_slice().to_vec()))
}

fn extract_map_as_json<'a>(
    record: Term<'a>,
    key: Term<'a>,
    enc: &JsonEncoder<'a>,
    scratch: &mut Vec<u8>,
) -> Enc<Vec<u8>> {
    let value = record.map_get(key).map_err(|_| EncodeError::Fallback)?;
    if enc.is_nil_or_false(value) {
        return Ok(b"{}".to_vec());
    }
    if value.get_type() != rustler::TermType::Map {
        return Err(EncodeError::Fallback);
    }
    scratch.clear();
    enc.map(scratch, value, 1)?;
    Ok(scratch.clone())
}

fn parquet_schema() -> SchemaRef {
    Arc::new(Schema::new(vec![
        Field::new("timestamp_ns", DataType::Int64, true),
        Field::new("observed_timestamp_ns", DataType::Int64, true),
        Field::new("severity_number", DataType::Int32, true),
        Field::new("severity_text", DataType::Utf8, true),
        Field::new("service", DataType::Utf8, true),
        Field::new("body", DataType::Utf8, true),
        Field::new("trace_id", DataType::Utf8, true),
        Field::new("span_id", DataType::Utf8, true),
        Field::new("attributes", DataType::Utf8, false),
        Field::new("resource", DataType::Utf8, false),
        Field::new("otlp", DataType::Utf8, true),
    ]))
}

// SAFETY on the `unsafe` calls below: each `Vec<u8>` in a Row was either
// (a) written by `JsonEncoder`, which is documented to emit only valid
// UTF-8, or (b) checked at `extract_binary` via `simdutf8::from_utf8`.
// The unchecked conversion elides an O(n) revalidation per string per
// row on the encode hot path.
fn build_batch(rows: &[Row]) -> Result<RecordBatch, arrow::error::ArrowError> {
    let mut ts = Int64Builder::with_capacity(rows.len());
    let mut observed = Int64Builder::with_capacity(rows.len());
    let mut sev_num = Int32Builder::with_capacity(rows.len());
    let mut sev_text = StringBuilder::with_capacity(rows.len(), rows.len() * 16);
    let mut service = StringBuilder::with_capacity(rows.len(), rows.len() * 16);
    let mut body = StringBuilder::with_capacity(rows.len(), rows.len() * 64);
    let mut trace_id = StringBuilder::with_capacity(rows.len(), rows.len() * 16);
    let mut span_id = StringBuilder::with_capacity(rows.len(), rows.len() * 16);
    let mut attributes = StringBuilder::with_capacity(rows.len(), rows.len() * 32);
    let mut resource = StringBuilder::with_capacity(rows.len(), rows.len() * 32);
    let mut otlp = StringBuilder::with_capacity(rows.len(), rows.len() * 64);

    for row in rows {
        ts.append_option(row.timestamp_ns);
        observed.append_option(row.observed_timestamp_ns);
        sev_num.append_option(row.severity_number);
        append_opt_bytes(&mut sev_text, row.severity_text.as_deref());
        append_opt_bytes(&mut service, row.service.as_deref());
        append_opt_bytes(&mut body, row.body.as_deref());
        append_opt_bytes(&mut trace_id, row.trace_id.as_deref());
        append_opt_bytes(&mut span_id, row.span_id.as_deref());
        append_bytes(&mut attributes, &row.attributes);
        append_bytes(&mut resource, &row.resource);
        append_opt_bytes(&mut otlp, row.otlp.as_deref());
    }

    RecordBatch::try_new(
        parquet_schema(),
        vec![
            Arc::new(ts.finish()),
            Arc::new(observed.finish()),
            Arc::new(sev_num.finish()),
            Arc::new(sev_text.finish()),
            Arc::new(service.finish()),
            Arc::new(body.finish()),
            Arc::new(trace_id.finish()),
            Arc::new(span_id.finish()),
            Arc::new(attributes.finish()),
            Arc::new(resource.finish()),
            Arc::new(otlp.finish()),
        ],
    )
}

fn append_opt_bytes(builder: &mut StringBuilder, bytes: Option<&[u8]>) {
    match bytes {
        Some(b) => append_bytes(builder, b),
        None => builder.append_null(),
    }
}

fn append_bytes(builder: &mut StringBuilder, bytes: &[u8]) {
    // SAFETY: see the `build_batch` header comment.
    let s = unsafe { std::str::from_utf8_unchecked(bytes) };
    builder.append_value(s);
}

fn writer_properties() -> WriterProperties {
    WriterProperties::builder()
        .set_writer_version(WriterVersion::PARQUET_2_0)
        .set_compression(Compression::ZSTD(ZstdLevel::try_new(6).unwrap()))
        // Delta packing on timestamps requires dictionary encoding off
        // for those columns; the Parquet spec disallows both at once.
        .set_column_encoding(
            ColumnPath::from("timestamp_ns"),
            Encoding::DELTA_BINARY_PACKED,
        )
        .set_column_dictionary_enabled(ColumnPath::from("timestamp_ns"), false)
        .set_column_encoding(
            ColumnPath::from("observed_timestamp_ns"),
            Encoding::DELTA_BINARY_PACKED,
        )
        .set_column_dictionary_enabled(ColumnPath::from("observed_timestamp_ns"), false)
        .set_column_dictionary_enabled(ColumnPath::from("severity_number"), true)
        .set_column_dictionary_enabled(ColumnPath::from("severity_text"), true)
        .set_column_dictionary_enabled(ColumnPath::from("service"), true)
        // Trace/span identifiers are usually unique. A dictionary adds an
        // index stream without removing payload bytes; pack their lengths
        // instead and let zstd compress the contiguous identifier bytes.
        .set_column_dictionary_enabled(ColumnPath::from("trace_id"), false)
        .set_column_encoding(
            ColumnPath::from("trace_id"),
            Encoding::DELTA_LENGTH_BYTE_ARRAY,
        )
        .set_column_dictionary_enabled(ColumnPath::from("span_id"), false)
        .set_column_encoding(
            ColumnPath::from("span_id"),
            Encoding::DELTA_LENGTH_BYTE_ARRAY,
        )
        // Queries prune at row-group granularity; per-page statistics and
        // column indexes add bytes to every small object without being read.
        .set_statistics_enabled(EnabledStatistics::Chunk)
        // Whole row groups are decoded; row-number page seeks are not used.
        .set_offset_index_disabled(true)
        // Footer statistics are uncompressed. Bound long JSON/string extrema
        // without truncating column data; parquet-rs widens truncated bounds
        // and marks them inexact. Integer timestamp bounds remain exact.
        .set_statistics_truncate_length(Some(64))
        .set_column_index_truncate_length(Some(64))
        .build()
}

// -- decode --------------------------------------------------------------

pub fn decode<'a>(
    env: Env<'a>,
    blob: &Binary<'a>,
    filter: &Filter,
) -> Result<(Vec<Term<'a>>, usize), DecodeError> {
    // Borrow the Erlang binary for the reader's `'static` lifetime instead of
    // copying the whole segment, as the metric and discovery readers do.
    let bytes = crate::erlang_bytes::from_binary(*blob);
    let builder = ParquetRecordBatchReaderBuilder::try_new(bytes.clone()).map_err(|_| Fallback)?;
    let metadata = builder.metadata().clone();

    let ts_col = metadata
        .file_metadata()
        .schema_descr()
        .columns()
        .iter()
        .position(|c| c.name() == "timestamp_ns");

    let time_filter = filter.start.is_some() || filter.end.is_some();
    let surviving: Vec<usize> = (0..metadata.num_row_groups())
        .filter(|&i| {
            if !time_filter {
                return true;
            }
            let rg = metadata.row_group(i);
            row_group_matches_time(rg, ts_col, filter)
        })
        .collect();

    if surviving.is_empty() {
        return Ok((Vec::new(), 0));
    }

    // Writer-owned page sizes cannot exceed their row group's uncompressed
    // size. Reject oversized groups before Arrow allocates/decompresses them.
    // This is not the expanded-string charge: dictionary repetition can make
    // Arrow much larger, so actual buffers are independently checked below.
    if let Some(max) = filter.max_decoded_bytes {
        for &index in &surviving {
            let size = usize::try_from(metadata.row_group(index).total_byte_size())
                .map_err(|_| Fallback)?;
            if size > max {
                return Err(DecodeError::TooManyDecodedBytes);
            }
        }
    }

    let builder = if let Some(max) = filter.max_decoded_bytes {
        // Ordinary logs can share these segments and exceed the Sentry wire
        // cap after JSON escaping. Count actual repeated string lengths with
        // the low-level reader before Arrow expands dictionaries into Utf8.
        let schema = builder.schema();
        let expected = parquet_schema();
        let fields = schema.fields();
        let valid = fields == expected.fields()
            || (fields.len() == 10 && fields.iter().eq(expected.fields().iter().take(10)));
        if !valid {
            return Err(Fallback.into());
        }
        let batch_size = preflight_expansion(bytes, &surviving, max)?;
        builder.with_batch_size(batch_size)
    } else {
        builder
    };

    let reader = builder
        .with_row_groups(surviving)
        .build()
        .map_err(|_| Fallback)?;

    // Footer row counts are untrusted. Grow only as rows are decoded,
    // rather than allowing a corrupt footer to request a huge allocation.
    let mut out = Vec::new();
    let mut decoded_bytes = 0usize;
    for batch in reader {
        let batch = batch.map_err(|_| Fallback)?;
        if let Some(max) = filter.max_decoded_bytes {
            for column in batch.columns() {
                decoded_bytes = decoded_bytes
                    .checked_add(column.get_buffer_memory_size())
                    .ok_or(DecodeError::TooManyDecodedBytes)?;
            }
            // Charge all decoded buffers, not only matching rows. Check before
            // materialize copies any string column into an Erlang arena.
            if decoded_bytes > max {
                return Err(DecodeError::TooManyDecodedBytes);
            }
        }
        materialize(env, &batch, filter, &mut out)?;
    }
    Ok((out, decoded_bytes))
}

// ByteArray values borrow dictionary/page bytes instead of concatenating every
// occurrence into an Arrow value buffer. Read one value at a time so even a
// large ordinary log cannot turn the preflight itself into an expanded batch.
// Keep the normal post-decode buffer charge: lengths do not account for every
// Arrow offset, validity bit or allocation capacity.
fn preflight_expansion(bytes: Bytes, groups: &[usize], max: usize) -> Result<usize, DecodeError> {
    // Both legacy and rich schemas fit 20 scalar bytes, up to 32 offset
    // bytes and validity bits per row. Reserve extra alignment/capacity.
    const ROW_BYTES: usize = 64;
    const BATCH_PADDING: usize = 2048;

    let reader = SerializedFileReader::new(bytes).map_err(|_| Fallback)?;
    let mut expanded = 0usize;
    let mut largest_row = 0usize;
    for &index in groups {
        let group = reader.get_row_group(index).map_err(|_| Fallback)?;
        let rows = usize::try_from(group.metadata().num_rows()).map_err(|_| Fallback)?;
        // Bound row/offset bookkeeping as well as string data. Never allocate
        // from an unchecked footer row count.
        charge_expansion(
            &mut expanded,
            rows.checked_mul(ROW_BYTES).ok_or(Fallback)?,
            max,
        )?;
        let mut row_bound = ROW_BYTES;
        for column in 0..group.num_columns() {
            let descriptor = group.metadata().column(column).column_descr();
            if descriptor.max_rep_level() != 0 || descriptor.max_def_level() > 1 {
                return Err(Fallback.into());
            }
            if let ColumnReader::ByteArrayColumnReader(mut column_reader) =
                group.get_column_reader(column).map_err(|_| Fallback)?
            {
                let mut values = Vec::with_capacity(1);
                let mut definitions = Vec::with_capacity(1);
                let mut count = 0usize;
                let mut longest = 0usize;
                loop {
                    values.clear();
                    definitions.clear();
                    let (read, _, _) = column_reader
                        .read_records(1, Some(&mut definitions), None, &mut values)
                        .map_err(|_| Fallback)?;
                    if read == 0 {
                        break;
                    }
                    count = count.checked_add(read).ok_or(Fallback)?;
                    if count > rows {
                        return Err(Fallback.into());
                    }
                    for value in &values {
                        charge_expansion(&mut expanded, value.len(), max)?;
                        longest = longest.max(value.len());
                    }
                }
                if count != rows {
                    return Err(Fallback.into());
                }
                row_bound = row_bound.checked_add(longest).ok_or(Fallback)?;
            }
        }
        largest_row = largest_row.max(row_bound);
    }
    // Allow for geometrically grown value buffers and fixed per-column
    // allocation padding. A single row grows from empty rather than doubling.
    let single_row = largest_row.checked_add(BATCH_PADDING).ok_or(Fallback)?;
    if single_row > max {
        return Err(DecodeError::TooManyDecodedBytes);
    }
    let per_row = largest_row
        .checked_mul(2)
        .and_then(|n| n.checked_add(BATCH_PADDING))
        .ok_or(Fallback)?;
    // Power-of-two batches avoid charging unused geometric buffer capacity
    // for repeated dictionary values (e.g. 20 equal strings reserve 32).
    let rows = (max / per_row).clamp(1, 64);
    Ok(1usize << rows.ilog2())
}

fn charge_expansion(total: &mut usize, bytes: usize, max: usize) -> Result<(), DecodeError> {
    *total = total
        .checked_add(bytes)
        .ok_or(DecodeError::TooManyDecodedBytes)?;
    if *total > max {
        Err(DecodeError::TooManyDecodedBytes)
    } else {
        Ok(())
    }
}

// True when the row group's `timestamp_ns` column stats overlap the
// filter range, so the group might contain matching records. Missing or
// non-integer stats mean we don't know — err on the side of scanning.
fn row_group_matches_time(rg: &RowGroupMetaData, ts_col: Option<usize>, filter: &Filter) -> bool {
    let Some(col) = ts_col else {
        return true;
    };
    let Some(stats) = rg.column(col).statistics() else {
        return true;
    };
    let Statistics::Int64(s) = stats else {
        return true;
    };
    let min = s.min_opt().map(|v| i128::from(*v));
    let max = s.max_opt().map(|v| i128::from(*v));
    if let (Some(start), Some(max)) = (filter.start, max) {
        if max < start {
            return false;
        }
    }
    if let (Some(end), Some(min)) = (filter.end, min) {
        if min > end {
            return false;
        }
    }
    true
}

// Per-column arena: one Erlang binary holding every string in the
// column, plus the Arrow offset slice. Sub-binaries slice into the arena
// without another copy — for a batch of N rows we go from N alloc/copy
// per column to one. `'a` is the NIF env's lifetime (the arena binary);
// `'b` is the batch's lifetime (the Arrow references). The two are
// deliberately independent — sub-binaries returned from `sub_binary`
// carry only `'a`, so the batch can be dropped at the end of each
// materialise loop iteration while the returned terms outlive it.
pub(crate) struct StringArena<'a, 'b> {
    arena: Option<Binary<'a>>,
    offsets: &'b [i32],
    array: &'b StringArray,
}

impl<'a, 'b> StringArena<'a, 'b> {
    pub(crate) fn from(env: Env<'a>, col: &'b StringArray) -> Self {
        let bytes = col.value_data();
        let arena = if bytes.is_empty() {
            None
        } else {
            let mut nb = NewBinary::new(env, bytes.len());
            nb.as_mut_slice().copy_from_slice(bytes);
            Some(Binary::from(nb))
        };
        StringArena {
            arena,
            offsets: col.value_offsets(),
            array: col,
        }
    }

    fn is_null(&self, i: usize) -> bool {
        self.array.is_null(i)
    }

    fn is_empty(&self, i: usize) -> bool {
        self.offsets[i + 1] == self.offsets[i]
    }

    fn sub_binary(&self, i: usize) -> Res<Binary<'a>> {
        let start = self.offsets[i] as usize;
        let end = self.offsets[i + 1] as usize;
        match &self.arena {
            Some(a) => a.make_subbinary(start, end - start).map_err(|_| Fallback),
            None => Err(Fallback),
        }
    }

    fn value_bytes(&self, i: usize) -> &'b [u8] {
        self.array.value(i).as_bytes()
    }
}

fn materialize<'a>(
    env: Env<'a>,
    batch: &RecordBatch,
    filter: &Filter,
    out: &mut Vec<Term<'a>>,
) -> Result<(), DecodeError> {
    let ts_col: &Int64Array = downcast_int64(batch, "timestamp_ns")?;
    let observed_col: &Int64Array = downcast_int64(batch, "observed_timestamp_ns")?;
    let sev_num_col: &Int32Array = downcast_int32(batch, "severity_number")?;
    let sev_text_col: &StringArray = downcast_string(batch, "severity_text")?;
    let service_col: &StringArray = downcast_string(batch, "service")?;
    let body_col: &StringArray = downcast_string(batch, "body")?;
    let trace_id_col: &StringArray = downcast_string(batch, "trace_id")?;
    let span_id_col: &StringArray = downcast_string(batch, "span_id")?;
    let attributes_col: &StringArray = downcast_string(batch, "attributes")?;
    let resource_col: &StringArray = downcast_string(batch, "resource")?;

    let sev_text = StringArena::from(env, sev_text_col);
    let service = StringArena::from(env, service_col);
    let body = StringArena::from(env, body_col);
    let trace_id = StringArena::from(env, trace_id_col);
    let span_id = StringArena::from(env, span_id_col);
    let attributes = StringArena::from(env, attributes_col);
    let resource = StringArena::from(env, resource_col);
    // Absence is the legacy ten-column schema. A present column with the
    // wrong Arrow type is corruption, not permission to discard metadata.
    let otlp = if batch.column_by_name("otlp").is_some() {
        Some(StringArena::from(env, downcast_string(batch, "otlp")?))
    } else {
        None
    };

    let nil = atom::nil().encode(env);
    let empty_map = rustler::types::map::map_new(env);
    let struct_key = atoms::struct_key().encode(env);
    let log = atoms::log().encode(env);
    let keys = field_atoms(env);

    let mut all_keys: Vec<Term<'a>> = Vec::with_capacity(12);
    all_keys.push(struct_key);
    all_keys.extend_from_slice(&keys);

    let time_filter = filter.start.is_some() || filter.end.is_some();
    let has_matchers = !filter.matchers.is_empty();
    let has_line_filters = !filter.line_filters.is_empty();
    let mut stacks: Stacks<Term<'a>> = Stacks::new();
    // Keep the existing bounded JSON key interner for the whole batch, not
    // just one row. Column arenas keep borrowed key bytes alive in this env.
    let mut interned_keys: InternedKeys<'a> = Vec::new();
    // Resource metadata is commonly repeated for a run of records. Share
    // the immutable decoded map only after comparing the complete JSON
    // bytes; a single entry bounds memory for high-cardinality resources.
    let mut previous_resource: Option<(&[u8], Term<'a>)> = None;
    // Share the fixed flat-map key tuple and unchanged field terms across
    // records. Keep only one previous record; never conflate differing rows.
    let mut previous_record: Option<(Term<'a>, [Term<'a>; 12])> = None;
    let mut previous_row: Option<usize> = None;

    for i in 0..batch.num_rows() {
        // Apply per-row filters before building any Erlang terms so the
        // rejected rows cost nothing beyond an Arrow lookup.
        if time_filter {
            let keep = if ts_col.is_null(i) {
                false
            } else {
                let ts = i128::from(ts_col.value(i));
                filter.start.is_none_or(|s| ts >= s) && filter.end.is_none_or(|e| ts <= e)
            };
            if !keep {
                continue;
            }
        }
        if let Some(wanted) = filter.service {
            let matches = !service.is_null(i) && service.value_bytes(i) == wanted;
            if !matches {
                continue;
            }
        }
        if has_matchers && !matchers_pass(&filter.matchers, &resource, &service, &sev_text, i) {
            continue;
        }
        if has_line_filters && !line_filters_pass(&filter.line_filters, &body, i) {
            continue;
        }

        // Count duplicates too, before sharing a previously materialized term.
        if filter.max_records.is_some_and(|max| out.len() >= max) {
            return Err(DecodeError::TooManyRecords);
        }

        // Share duplicates only after byte-exact Arrow comparison, including
        // JSON columns. BEAM equality alone loses signed-zero distinctions.
        if let (Some(previous), Some((term, _))) = (previous_row, previous_record) {
            if identical_row(batch, previous, i) {
                out.push(term);
                continue;
            }
        }
        let ts_term = int_term(env, ts_col, i, nil);
        let observed_term = int_term(env, observed_col, i, nil);
        let sev_num_term = int32_term(env, sev_num_col, i, nil);
        let sev_text_term = sub_term(env, &sev_text, i, nil)?;
        let service_term = sub_term(env, &service, i, nil)?;
        let body_term = json_term(env, &body, i, nil, &mut stacks, &mut interned_keys)?;
        let trace_id_term = sub_term(env, &trace_id, i, nil)?;
        let span_id_term = sub_term(env, &span_id, i, nil)?;
        let attributes_term = map_json_term(
            env,
            &attributes,
            i,
            empty_map,
            &mut stacks,
            &mut interned_keys,
        )?;
        let resource_term = if resource.is_null(i) || resource.is_empty(i) {
            empty_map
        } else {
            let bytes = resource.value_bytes(i);
            match previous_resource {
                Some((previous, term)) if previous == bytes => term,
                _ => {
                    let term = map_json_term(
                        env,
                        &resource,
                        i,
                        empty_map,
                        &mut stacks,
                        &mut interned_keys,
                    )?;
                    previous_resource = Some((bytes, term));
                    term
                }
            }
        };

        let otlp_term = match &otlp {
            Some(arena) => json_term(env, arena, i, nil, &mut stacks, &mut interned_keys)?,
            None => nil,
        };
        if otlp_term != nil && otlp_term.get_type() != rustler::TermType::Map {
            return Err(Fallback.into());
        }
        // Field order matches `field_atoms/1`.
        let values = [
            log,
            attributes_term,
            body_term,
            observed_term,
            resource_term,
            service_term,
            sev_num_term,
            sev_text_term,
            span_id_term,
            ts_term,
            trace_id_term,
            otlp_term,
        ];
        let term = match previous_record {
            Some((mut term, previous_values)) => {
                for (index, ((key, value), previous)) in all_keys
                    .iter()
                    .zip(values.iter())
                    .zip(previous_values.iter())
                    .enumerate()
                {
                    // Pointer-identical terms can be shared. Do not use BEAM
                    // numeric equality for distinct JSON terms: it conflates
                    // +0.0 and -0.0 inside bodies, attributes and metadata.
                    let json_field = matches!(index, 1 | 2 | 4 | 11);
                    if value.as_c_arg() != previous.as_c_arg() && (json_field || value != previous)
                    {
                        term = term.map_update(*key, *value).map_err(|_| Fallback)?;
                    }
                }
                term
            }
            None => Term::map_from_arrays(env, &all_keys, &values).map_err(|_| Fallback)?,
        };
        previous_record = Some((term, values));
        previous_row = Some(i);
        out.push(term);
    }
    Ok(())
}

fn identical_row(batch: &RecordBatch, left: usize, right: usize) -> bool {
    batch.columns().iter().all(|column| {
        if column.is_null(left) || column.is_null(right) {
            return column.is_null(left) == column.is_null(right);
        }
        match column.data_type() {
            DataType::Int64 => column
                .as_any()
                .downcast_ref::<Int64Array>()
                .is_some_and(|a| a.value(left) == a.value(right)),
            DataType::Int32 => column
                .as_any()
                .downcast_ref::<Int32Array>()
                .is_some_and(|a| a.value(left) == a.value(right)),
            DataType::Utf8 => column
                .as_any()
                .downcast_ref::<StringArray>()
                .is_some_and(|a| a.value(left).as_bytes() == a.value(right).as_bytes()),
            _ => false,
        }
    })
}

// Evaluate every matcher against the row's `resource` JSON, plus the
// promoted-field mirror for `service`/`service_name`/`level`/
// `detected_level` (so an OTLP record that never populated `resource`
// but has typed struct fields still matches). All matchers must pass
// — stream selectors are conjunctive.
//
// The lookup is inlined here rather than extracted to a helper because
// the two arenas (`service`, `severity_text`) have distinct lifetime
// parameters that Rust's variance rules don't unify through a Cow
// return without extra copies.
fn matchers_pass(
    matchers: &[Matcher],
    resource: &StringArena,
    service: &StringArena,
    severity_text: &StringArena,
    i: usize,
) -> bool {
    for m in matchers {
        let name = m.name();
        let kept = match name {
            b"service" | b"service_name" => promoted_or_resource(name, service, resource, i, m),
            b"level" | b"detected_level" => {
                promoted_or_resource(name, severity_text, resource, i, m)
            }
            _ => match resource_lookup(resource, name, i) {
                Some(v) => m.evaluate_present(&v),
                None => m.evaluate_absent(),
            },
        };

        if !kept {
            return false;
        }
    }
    true
}

// Prefer the promoted typed column when present; fall back to a
// resource-JSON scan when it's null/empty.
fn promoted_or_resource(
    name: &[u8],
    promoted: &StringArena,
    resource: &StringArena,
    i: usize,
    matcher: &Matcher,
) -> bool {
    if !promoted.is_null(i) && !promoted.is_empty(i) {
        return matcher.evaluate_present(promoted.value_bytes(i));
    }
    match resource_lookup(resource, name, i) {
        Some(v) => matcher.evaluate_present(&v),
        None => matcher.evaluate_absent(),
    }
}

fn resource_lookup<'b>(
    resource: &StringArena<'_, 'b>,
    name: &[u8],
    i: usize,
) -> Option<std::borrow::Cow<'b, [u8]>> {
    if resource.is_null(i) || resource.is_empty(i) {
        return None;
    }
    find_label(resource.value_bytes(i), name)
}

// Every line filter must match. Conjunction, same as label matchers.
// Body is stored as JSON-encoded — for a string body that is the source
// text surrounded by `"`. We peel the quotes and unescape before
// matching so `|~ "^hello"` behaves the way a user reading the log
// line would expect, and so the Rust and Memory adapters produce
// identical result sets for identical LogQL.
fn line_filters_pass(line_filters: &[LineFilter], body: &StringArena, i: usize) -> bool {
    if body.is_null(i) || body.is_empty(i) {
        return line_filters.iter().all(|f| f.matches(b""));
    }
    let raw = body.value_bytes(i);
    let matched = line_bytes_for_match(raw);
    line_filters.iter().all(|f| f.matches(&matched))
}

// Same column order + atom order as `segment.rs` uses so the returned
// maps are indistinguishable from the NDJSON path's output.
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

fn downcast_int64<'b>(batch: &'b RecordBatch, name: &str) -> Res<&'b Int64Array> {
    batch
        .column_by_name(name)
        .and_then(|c| c.as_any().downcast_ref::<Int64Array>())
        .ok_or(Fallback)
}

fn downcast_int32<'b>(batch: &'b RecordBatch, name: &str) -> Res<&'b Int32Array> {
    batch
        .column_by_name(name)
        .and_then(|c| c.as_any().downcast_ref::<Int32Array>())
        .ok_or(Fallback)
}

fn downcast_string<'b>(batch: &'b RecordBatch, name: &str) -> Res<&'b StringArray> {
    batch
        .column_by_name(name)
        .and_then(|c| c.as_any().downcast_ref::<StringArray>())
        .ok_or(Fallback)
}

fn int_term<'a>(env: Env<'a>, col: &Int64Array, i: usize, nil: Term<'a>) -> Term<'a> {
    if col.is_null(i) {
        nil
    } else {
        col.value(i).encode(env)
    }
}

fn int32_term<'a>(env: Env<'a>, col: &Int32Array, i: usize, nil: Term<'a>) -> Term<'a> {
    if col.is_null(i) {
        nil
    } else {
        col.value(i).encode(env)
    }
}

fn sub_term<'a>(
    env: Env<'a>,
    arena: &StringArena<'a, '_>,
    i: usize,
    nil: Term<'a>,
) -> Res<Term<'a>> {
    if arena.is_null(i) {
        return Ok(nil);
    }
    if arena.is_empty(i) {
        // Sub-binary of an empty range would need an arena; just hand
        // back a fresh empty binary. No allocation savings to protect.
        let empty = NewBinary::new(env, 0);
        return Ok(Binary::from(empty).encode(env));
    }
    Ok(arena.sub_binary(i)?.encode(env))
}

pub(crate) fn json_term<'a>(
    env: Env<'a>,
    arena: &StringArena<'a, '_>,
    i: usize,
    nil: Term<'a>,
    stacks: &mut Stacks<Term<'a>>,
    interned_keys: &mut InternedKeys<'a>,
) -> Res<Term<'a>> {
    if arena.is_null(i) {
        return Ok(nil);
    }
    if arena.is_empty(i) {
        return Ok(nil);
    }
    parse_json_sub(env, arena, i, stacks, interned_keys)
}

fn map_json_term<'a>(
    env: Env<'a>,
    arena: &StringArena<'a, '_>,
    i: usize,
    empty_map: Term<'a>,
    stacks: &mut Stacks<Term<'a>>,
    interned_keys: &mut InternedKeys<'a>,
) -> Res<Term<'a>> {
    if arena.is_null(i) || arena.is_empty(i) {
        return Ok(empty_map);
    }
    // Common fast path: `"{}"` (2 bytes) — skip the JSON parser entirely.
    let start = arena.offsets[i] as usize;
    let end = arena.offsets[i + 1] as usize;
    if end - start == 2 {
        let bytes = arena.value_bytes(i);
        if bytes == b"{}" {
            return Ok(empty_map);
        }
    }
    parse_json_sub(env, arena, i, stacks, interned_keys)
}

fn parse_json_sub<'a>(
    env: Env<'a>,
    arena: &StringArena<'a, '_>,
    i: usize,
    stacks: &mut Stacks<Term<'a>>,
    interned_keys: &mut InternedKeys<'a>,
) -> Res<Term<'a>> {
    let bin = arena.sub_binary(i)?;
    let mut builder = TermBuilder::with_keys(env, &bin, std::mem::take(interned_keys));
    let result = Parser::new(bin.as_slice()).document_with(&mut builder, stacks);
    *interned_keys = builder.into_keys();
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn string_segment(strings: Vec<Option<&str>>, groups: usize) -> Bytes {
        let schema = Arc::new(Schema::new(vec![Field::new("body", DataType::Utf8, true)]));
        let batch =
            RecordBatch::try_new(schema.clone(), vec![Arc::new(StringArray::from(strings))])
                .unwrap();
        let mut buf = Vec::new();
        let mut writer = ArrowWriter::try_new(&mut buf, schema, Some(writer_properties())).unwrap();
        for _ in 0..groups {
            writer.write(&batch).unwrap();
            writer.flush().unwrap();
        }
        writer.close().unwrap();
        Bytes::from(buf)
    }

    #[test]
    fn preflight_rejects_repeated_dictionary_payloads_before_arrow_expansion() {
        let body = "\\u0000".repeat(500_000);
        let bytes = string_segment(vec![Some(body.as_str()); 32], 1);
        assert!(bytes.len() < 10_000);
        let reader = SerializedFileReader::new(bytes.clone()).unwrap();
        assert!(reader.metadata().row_group(0).total_byte_size() < 33_554_432);
        // This exercises only the low-level preflight, not an Arrow reader:
        // rejection cannot depend on allocating the 96 MB expanded batch.
        assert!(matches!(
            preflight_expansion(bytes, &[0], 33_554_432),
            Err(DecodeError::TooManyDecodedBytes)
        ));
    }

    #[test]
    fn preflight_sizes_batches_from_actual_values_and_counts_null_rows() {
        let body = "x".repeat(3_000_000);
        let bytes = string_segment(vec![None, Some(body.as_str()), None], 1);
        let batch = preflight_expansion(bytes, &[0], 8_388_608)
            .unwrap_or_else(|_| panic!("valid preflight"));
        assert_eq!(batch, 1);
        let bytes = string_segment(vec![None, Some("small"), None], 1);
        assert_eq!(
            preflight_expansion(bytes, &[0], 8_388_608)
                .unwrap_or_else(|_| panic!("valid preflight")),
            64
        );
    }

    #[test]
    fn preflight_accumulates_expansion_across_row_groups() {
        let bytes = string_segment(vec![Some("x"); 32], 2);
        assert!(preflight_expansion(bytes.clone(), &[0], 4096).is_ok());
        assert!(matches!(
            preflight_expansion(bytes, &[0, 1], 4096),
            Err(DecodeError::TooManyDecodedBytes)
        ));
    }

    #[test]
    fn long_utf8_statistics_are_conservative_and_timestamp_bounds_stay_exact() {
        let lo = format!("a{}", "界🌍".repeat(200));
        let hi = format!("z{}", "界🌍".repeat(200));
        let schema = Arc::new(Schema::new(vec![
            Field::new("body", DataType::Utf8, false),
            Field::new("timestamp_ns", DataType::Int64, false),
        ]));
        let batch = RecordBatch::try_new(
            schema.clone(),
            vec![
                Arc::new(StringArray::from(vec![lo.as_str(), hi.as_str()])),
                Arc::new(Int64Array::from(vec![10, 20])),
            ],
        )
        .unwrap();
        let mut buf = Vec::new();
        let mut writer = ArrowWriter::try_new(&mut buf, schema, Some(writer_properties())).unwrap();
        writer.write(&batch).unwrap();
        writer.close().unwrap();
        let builder = ParquetRecordBatchReaderBuilder::try_new(Bytes::from(buf)).unwrap();
        let group = builder.metadata().row_group(0);
        for column in group.columns() {
            assert!(column.offset_index_offset().is_none());
            assert!(column.offset_index_length().is_none());
        }
        let strings = group.column(0).statistics().unwrap();
        assert!(strings.min_bytes_opt().unwrap().len() <= 64);
        assert!(strings.max_bytes_opt().unwrap().len() <= 64);
        assert!(strings.min_bytes_opt().unwrap() <= lo.as_bytes());
        assert!(strings.max_bytes_opt().unwrap() >= hi.as_bytes());
        assert!(!strings.min_is_exact());
        assert!(!strings.max_is_exact());
        match group.column(1).statistics().unwrap() {
            Statistics::Int64(stats) => {
                assert_eq!(stats.min_opt(), Some(&10));
                assert_eq!(stats.max_opt(), Some(&20));
            }
            _ => panic!("timestamp stats must be Int64"),
        }
        let decoded = builder.build().unwrap().next().unwrap().unwrap();
        let strings = decoded
            .column(0)
            .as_any()
            .downcast_ref::<StringArray>()
            .unwrap();
        assert_eq!(strings.value(0), lo);
        assert_eq!(strings.value(1), hi);
    }
}

// -- compaction ----------------------------------------------------------

/// Why a log compaction cannot produce a replacement segment.
#[derive(Debug, PartialEq, Eq)]
pub enum CompactError {
    Invalid,
    TooMany,
    PayloadTooLarge,
}

/// A merged log segment: payload, encoder-compatible bounds, row count, the
/// complete nonempty service set (`None` when unknown) and the indices of the
/// sources it holds, ascending.
pub type Compacted<'a> = (Binary<'a>, Bounds, Option<Vec<String>>, Vec<usize>);

/// Decoded string bytes one merge may hold: twice an ingest segment's payload.
pub const MAX_COMPACT_STRING_BYTES: usize = 2 * MAX_PAYLOAD;

/// Merge log segments natively, never building Erlang terms for records.
///
/// Every source must have the encoder's schema; legacy ten-column segments
/// gain a null `otlp` column, which decodes exactly as the legacy layout.
/// Rows are re-sorted by `(service, timestamp_ns)` with nulls first, the
/// encoder's order, and written with the encoder's writer properties. The
/// service summary follows `Segment.summarize_logs/2`: complete when every
/// row has a nonempty service of at most 256 bytes and there are at most
/// 128 distinct services, unknown otherwise.
///
/// Sources are taken in order while their decoded strings fit
/// `MAX_COMPACT_STRING_BYTES` together; a source that would exceed it is
/// left out whole (never truncated), and later, smaller ones may still fit.
/// Only one source beyond the bound is ever decoded at a time. The merge
/// fails with `PayloadTooLarge` only when no source with rows fits.
pub fn compact<'a>(
    env: Env<'a>,
    blobs: Term<'a>,
    max_rows: usize,
) -> Result<Compacted<'a>, CompactError> {
    use std::collections::BTreeSet;

    let mut batches = Vec::new();
    let mut included = Vec::new();
    let mut declared_rows = 0usize;
    let mut rows = 0usize;
    let mut held_bytes = 0usize;
    let mut bounds = Bounds {
        min_ts: i128::MAX,
        max_ts: i128::MIN,
        count: 0,
    };
    let mut services = Some(BTreeSet::new());

    for (index, term) in blobs
        .decode::<ListIterator>()
        .map_err(|_| CompactError::Invalid)?
        .enumerate()
    {
        let blob: Binary = term.decode().map_err(|_| CompactError::Invalid)?;
        let (declared, source_batches) =
            segment_batches(crate::erlang_bytes::from_binary(blob), 8192)?;
        declared_rows = declared_rows
            .checked_add(declared)
            .ok_or(CompactError::TooMany)?;
        if declared_rows > max_rows {
            return Err(CompactError::TooMany);
        }
        let mut source = Vec::new();
        let mut source_rows = 0usize;
        let mut source_bytes = 0usize;
        let mut fits = true;
        for batch in source_batches {
            let batch = batch?;
            source_rows += batch.num_rows();
            if rows + source_rows > max_rows {
                return Err(CompactError::TooMany);
            }
            source_bytes += string_bytes(&batch);
            if held_bytes + source_bytes > MAX_COMPACT_STRING_BYTES {
                fits = false;
                break;
            }
            source.push(batch);
        }
        if !fits {
            continue;
        }
        for batch in &source {
            let ts = downcast_int64(batch, "timestamp_ns").map_err(|_| CompactError::Invalid)?;
            let service = downcast_string(batch, "service").map_err(|_| CompactError::Invalid)?;
            for i in 0..batch.num_rows() {
                let value = if ts.is_null(i) {
                    0
                } else {
                    i128::from(ts.value(i))
                };
                bounds.min_ts = bounds.min_ts.min(value);
                bounds.max_ts = bounds.max_ts.max(value);
                bounds.count += 1;
                services = services.and_then(|mut set| {
                    let name = (!service.is_null(i)).then(|| service.value(i));
                    match name {
                        Some(name) if !name.is_empty() && name.len() <= 256 => {
                            set.insert(name.to_owned());
                            (set.len() <= 128).then_some(set)
                        }
                        _ => None,
                    }
                });
            }
        }
        rows += source_rows;
        held_bytes += source_bytes;
        batches.extend(source);
        included.push(index);
    }

    if included.is_empty() && declared_rows > 0 {
        return Err(CompactError::PayloadTooLarge);
    }

    if bounds.count == 0 {
        bounds.min_ts = 0;
        bounds.max_ts = 0;
    }
    let payload = encode_sorted(env, batches, rows)?;
    let services = services.map(|set| set.into_iter().collect());
    Ok((payload, bounds, services, included))
}

/// The record batches of a stored log segment in the encoder's schema, with
/// its declared row count. Legacy ten-column segments gain a null `otlp`
/// column, which decodes exactly as the legacy layout.
pub(crate) fn segment_batches(
    bytes: Bytes,
    batch_rows: usize,
) -> Result<
    (
        usize,
        impl Iterator<Item = Result<RecordBatch, CompactError>>,
    ),
    CompactError,
> {
    let schema = parquet_schema();
    let builder =
        ParquetRecordBatchReaderBuilder::try_new(bytes).map_err(|_| CompactError::Invalid)?;
    let declared = usize::try_from(builder.metadata().file_metadata().num_rows())
        .map_err(|_| CompactError::Invalid)?;
    let legacy = builder.schema().fields().len() + 1 == schema.fields().len()
        && builder
            .schema()
            .fields()
            .iter()
            .zip(schema.fields())
            .all(|(a, b)| a == b);
    if !legacy && builder.schema().fields() != schema.fields() {
        return Err(CompactError::Invalid);
    }
    let reader = builder
        .with_batch_size(batch_rows)
        .build()
        .map_err(|_| CompactError::Invalid)?;
    Ok((
        declared,
        reader.map(move |batch| {
            let batch = batch.map_err(|_| CompactError::Invalid)?;
            let mut columns = batch.columns().to_vec();
            if legacy {
                columns.push(arrow::array::new_null_array(
                    &DataType::Utf8,
                    batch.num_rows(),
                ));
            }
            RecordBatch::try_new(Arc::clone(&schema), columns).map_err(|_| CompactError::Invalid)
        }),
    ))
}

/// Decoded string bytes a batch holds.
pub(crate) fn string_bytes(batch: &RecordBatch) -> usize {
    batch
        .columns()
        .iter()
        .filter_map(|column| column.as_any().downcast_ref::<StringArray>())
        .map(|strings| strings.value_data().len())
        .sum()
}

/// One log segment holding `batches` (`rows` rows in all), re-sorted by
/// `(service, timestamp_ns)` with nulls first, the encoder's order, and
/// written with the encoder's writer properties.
pub(crate) fn encode_sorted<'a>(
    env: Env<'a>,
    batches: Vec<RecordBatch>,
    rows: usize,
) -> Result<Binary<'a>, CompactError> {
    use arrow::compute::{concat_batches, lexsort_to_indices, take_record_batch, SortColumn};

    let schema = parquet_schema();
    let merged = concat_batches(&schema, &batches).map_err(|_| CompactError::Invalid)?;
    drop(batches);
    let sort: Vec<SortColumn> = ["service", "timestamp_ns"]
        .iter()
        .map(|name| SortColumn {
            values: merged
                .column_by_name(name)
                .expect("log schema column")
                .clone(),
            options: None,
        })
        .collect();
    let indices = lexsort_to_indices(&sort, None).map_err(|_| CompactError::Invalid)?;
    let sorted = take_record_batch(&merged, &indices).map_err(|_| CompactError::Invalid)?;
    drop(merged);

    let mut buf = crate::out::BinaryWriter(crate::out::BinSink::with_capacity(64 + rows * 32));
    let mut writer = ArrowWriter::try_new(&mut buf, Arc::clone(&schema), Some(writer_properties()))
        .map_err(|_| CompactError::Invalid)?;
    writer.write(&sorted).map_err(|_| CompactError::Invalid)?;
    writer.close().map_err(|_| CompactError::Invalid)?;
    Ok(buf.0.finish(env))
}

// -- streaming decode ------------------------------------------------------

/// A log segment decoded a bounded chunk of records at a time, so callers
/// that fold records never hold a whole (possibly compacted, 100k-row)
/// segment as Erlang terms. Filters and row-group pruning are `decode`'s.
pub struct Reader {
    reader: parquet::arrow::arrow_reader::ParquetRecordBatchReader,
    start: Option<i128>,
    end: Option<i128>,
    service: Option<Vec<u8>>,
    matchers: Vec<Matcher>,
    line_filters: Vec<LineFilter>,
}

impl Reader {
    pub fn new(blob: &Binary<'_>, filter: Filter<'_>) -> Res<Option<Self>> {
        // Keep the segment borrowed from the BEAM across the chunk loop.
        let bytes = crate::erlang_bytes::from_binary(*blob);
        let builder = ParquetRecordBatchReaderBuilder::try_new(bytes).map_err(|_| Fallback)?;
        let metadata = builder.metadata().clone();
        let ts_col = metadata
            .file_metadata()
            .schema_descr()
            .columns()
            .iter()
            .position(|c| c.name() == "timestamp_ns");
        let time_filter = filter.start.is_some() || filter.end.is_some();
        let surviving: Vec<usize> = (0..metadata.num_row_groups())
            .filter(|&i| {
                !time_filter || row_group_matches_time(metadata.row_group(i), ts_col, &filter)
            })
            .collect();
        if surviving.is_empty() {
            return Ok(None);
        }
        let reader = builder
            .with_row_groups(surviving)
            .with_batch_size(STREAM_BATCH_ROWS)
            .build()
            .map_err(|_| Fallback)?;
        Ok(Some(Reader {
            reader,
            start: filter.start,
            end: filter.end,
            service: filter.service.map(<[u8]>::to_vec),
            matchers: filter.matchers,
            line_filters: filter.line_filters,
        }))
    }

    /// Decode batches until at least `min_records` records survive the
    /// filters or the segment ends. `None` once nothing remains.
    pub fn next<'a>(&mut self, env: Env<'a>, min_records: usize) -> Res<Option<Vec<Term<'a>>>> {
        let filter = Filter {
            start: self.start,
            end: self.end,
            service: self.service.as_deref(),
            matchers: std::mem::take(&mut self.matchers),
            line_filters: std::mem::take(&mut self.line_filters),
            max_records: None,
            max_decoded_bytes: None,
        };
        let mut out = Vec::new();
        let mut exhausted = true;
        let result = (|| {
            for batch in self.reader.by_ref() {
                let batch = batch.map_err(|_| Fallback)?;
                materialize(env, &batch, &filter, &mut out).map_err(|_| Fallback)?;
                if out.len() >= min_records {
                    exhausted = false;
                    break;
                }
            }
            Ok(())
        })();
        self.matchers = filter.matchers;
        self.line_filters = filter.line_filters;
        result?;
        Ok(if out.is_empty() && exhausted {
            None
        } else {
            Some(out)
        })
    }
}

const STREAM_BATCH_ROWS: usize = 4096;
