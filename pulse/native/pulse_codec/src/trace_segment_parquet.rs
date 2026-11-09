//! Trace segments have typed search columns plus a lossless JSON payload for
//! nested OTLP metadata. Only matching rows are expanded into Erlang terms.
use crate::json_read::{Parser, Stacks};
use crate::term_json::{EncodeError, JsonEncoder, TermBuilder};
use crate::trace_sort_key;
use arrow::array::{Array, ArrayRef, Int64Array, RecordBatch, StringArray};
use arrow::compute::{concat_batches, lexsort_to_indices, take_record_batch, SortColumn};
use arrow::datatypes::{DataType, Field, Schema};
use parquet::arrow::{arrow_reader::ParquetRecordBatchReaderBuilder, ArrowWriter};
use parquet::basic::{Compression, Encoding, ZstdLevel};
use parquet::file::properties::{WriterProperties, WriterVersion};
use parquet::file::statistics::Statistics;
use parquet::schema::types::ColumnPath;
use rustler::{Binary, Env, ListIterator, Term};
use std::cmp::Reverse;
use std::collections::BTreeSet;
use std::collections::BinaryHeap;
use std::collections::HashMap;
use std::sync::Arc;

pub enum Error {
    Invalid,
    InvalidProjection,
    TooMany,
    PayloadTooLarge,
    QueryBytes,
    /// A projected query retained two different copies of one span (same start,
    /// trace ID and span ID) and cannot order them from digests alone.
    ProjectionTie,
}
type Res<T> = Result<T, Error>;
const MAX_PAYLOAD_BYTES: usize = 16 * 1024 * 1024;
const STRINGS: [&str; 5] = ["service", "trace_id", "span_id", "name", "payload"];
const INTS: [&str; 4] = ["timestamp_ns", "end_timestamp_ns", "kind", "status_code"];
fn binary<'a>(env: Env<'a>, value: &[u8]) -> Binary<'a> {
    let mut b = rustler::NewBinary::new(env, value.len());
    b.as_mut_slice().copy_from_slice(value);
    b.into()
}
fn get<'a>(env: Env<'a>, term: Term<'a>, key: &str) -> Res<Term<'a>> {
    term.map_get(binary(env, key.as_bytes()))
        .map_err(|_| Error::Invalid)
}
pub fn payload_size<'a>(
    env: Env<'a>,
    records: Term<'a>,
    limit: usize,
) -> Result<usize, EncodeError> {
    use crate::out::Sink;
    let limit = limit.min(MAX_PAYLOAD_BYTES);
    let mut counter = crate::out::Counter::new(limit);
    let encoder = JsonEncoder::new(env, limit);
    for record in records
        .decode::<ListIterator>()
        .map_err(|_| EncodeError::Fallback)?
    {
        encoder.value(&mut counter, record, 0)?;
    }
    if counter.len() > limit {
        return Err(EncodeError::TooBig);
    }
    Ok(counter.len())
}

struct Row {
    strings: [Option<std::string::String>; 5],
    ints: [i64; 4],
}
fn validate_projection(
    fields: &crate::json_read::RawFields<'_>,
    strings: [Option<&str>; 4],
    ints: [i64; 4],
) -> Result<(), crate::trace_search::Error> {
    use crate::trace_search::{field, object, string, Error};
    crate::tempo_search::validate_fields(
        strings[1].ok_or(Error::Invalid)?,
        ints[0],
        ints[1],
        fields,
    )?;
    if Some(string(field(fields, b"span_id")?)?.as_str()) != strings[2]
        || Some(string(field(fields, b"name")?)?.as_str()) != strings[3]
        || crate::tempo_search::integer(field(fields, b"kind")?)? != ints[2]
        || crate::tempo_search::integer(field(&object(field(fields, b"status")?)?, b"code")?)?
            != ints[3]
    {
        return Err(Error::Invalid);
    }
    let service = field(fields, b"service")?;
    if service == b"null" {
        if strings[0].is_some() {
            return Err(Error::Invalid);
        }
    } else if Some(string(service)?.as_str()) != strings[0] {
        return Err(Error::Invalid);
    }
    Ok(())
}
fn metadata_service_safe(fields: &crate::json_read::RawFields<'_>, service: Option<&str>) -> bool {
    use crate::trace_search::{field, object, typed_attributes, Res};
    (|| -> Res<bool> {
        let metadata = field(fields, b"otlp")?;
        if metadata == b"null" {
            return Ok(false);
        }
        let resource = typed_attributes(field(&object(metadata)?, b"resource")?)?;
        Ok(resource
            .get("service.name")
            .is_none_or(|original| Some(original.as_str()) == service))
    })()
    .unwrap_or(false)
}

#[cfg(test)]
mod proof_tests {
    use super::*;
    const PAYLOAD: &str = r#"{"timestamp_ns":1,"end_timestamp_ns":2,"trace_id":"11111111111111111111111111111111","span_id":"2222222222222222","parent_span_id":null,"flags":0,"name":"n","kind":2,"service":"api","status":{"code":0},"events":[],"links":[],"otlp":{"version":1,"resource":[{"key":"service.name","value":{"stringValue":"api"}}],"scope":[],"attributes":[],"events":[],"links":[]}}"#;
    #[test]
    fn every_physical_projection_must_agree() {
        let fields = crate::trace_metadata::validated_fields(PAYLOAD.as_bytes()).unwrap();
        let strings = [
            Some("api"),
            Some("11111111111111111111111111111111"),
            Some("2222222222222222"),
            Some("n"),
        ];
        let ints = [1, 2, 2, 0];
        assert!(validate_projection(&fields, strings, ints).is_ok());
        for index in 0..4 {
            let mut changed = strings;
            changed[index] = Some("wrong");
            assert!(validate_projection(&fields, changed, ints).is_err());
            let mut changed = ints;
            changed[index] += 1;
            assert!(validate_projection(&fields, strings, changed).is_err());
        }
        assert!(metadata_service_safe(&fields, Some("api")));
        assert!(!metadata_service_safe(&fields, Some("different")));
        let nonstring = PAYLOAD.replace(r#""stringValue":"api""#, r#""boolValue":true"#);
        let fields = crate::trace_metadata::validated_fields(nonstring.as_bytes()).unwrap();
        assert!(metadata_service_safe(&fields, Some("api")));
        let duplicate = PAYLOAD.replace(
            r#""scope":[]"#,
            r#""resource":[{"key":"service.name","value":{"stringValue":"other"}}],"scope":[]"#,
        );
        assert!(crate::trace_metadata::validated_fields(duplicate.as_bytes()).is_err());
    }
}

pub fn encode<'a>(env: Env<'a>, records: Term<'a>) -> Res<(Binary<'a>, i64, i64, usize, bool)> {
    let mut metadata_safe = true;
    let mut payload_bytes = 0;
    let mut rows = Vec::new();
    let mut min = i64::MAX;
    let mut max = i64::MIN;
    for record in records
        .decode::<ListIterator>()
        .map_err(|_| Error::Invalid)?
    {
        let mut strings: [Option<std::string::String>; 5] = Default::default();
        for (i, name) in STRINGS[..4].iter().enumerate() {
            let v = get(env, record, name)?;
            if v.decode::<rustler::Atom>().ok() == Some(rustler::types::atom::nil()) {
                if *name != "service" {
                    return Err(Error::Invalid);
                }
            } else {
                strings[i] = Some(v.decode().map_err(|_| Error::Invalid)?);
            }
        }
        let mut payload = crate::bounded_json::Buffer::new(MAX_PAYLOAD_BYTES - payload_bytes);
        JsonEncoder::new(env, MAX_PAYLOAD_BYTES - payload_bytes)
            .value(&mut payload, record, 0)
            .map_err(|e| match e {
                EncodeError::TooBig => Error::PayloadTooLarge,
                _ => Error::Invalid,
            })?;
        let payload = payload.finish();
        let fields =
            crate::trace_metadata::validated_fields(&payload).map_err(|_| Error::Invalid)?;
        let mut ints = [0; 4];
        for (i, name) in INTS[..3].iter().enumerate() {
            ints[i] = get(env, record, name)?
                .decode()
                .map_err(|_| Error::Invalid)?;
        }
        ints[3] = get(env, get(env, record, "status")?, "code")?
            .decode()
            .map_err(|_| Error::Invalid)?;
        validate_projection(
            &fields,
            std::array::from_fn(|i| strings[i].as_deref()),
            ints,
        )
        .map_err(|_| Error::InvalidProjection)?;
        if metadata_safe {
            metadata_safe = metadata_service_safe(&fields, strings[0].as_deref());
        }
        drop(fields);
        payload_bytes += payload.len();
        strings[4] = Some(std::string::String::from_utf8(payload).map_err(|_| Error::Invalid)?);
        if ints[0] < 0 || ints[1] < ints[0] {
            return Err(Error::Invalid);
        }
        min = min.min(ints[0]);
        max = max.max(ints[0]);
        rows.push(Row { strings, ints });
    }
    rows.sort_by(|a, b| {
        a.strings[0]
            .cmp(&b.strings[0])
            .then(a.ints[0].cmp(&b.ints[0]))
            .then(a.strings[1].cmp(&b.strings[1]))
            .then(a.strings[2].cmp(&b.strings[2]))
    });
    let fields: Vec<_> = INTS
        .iter()
        .map(|n| Field::new(*n, DataType::Int64, false))
        .chain(
            STRINGS
                .iter()
                .map(|n| Field::new(*n, DataType::Utf8, *n == "service")),
        )
        .collect();
    let schema = Arc::new(Schema::new(fields));
    let mut columns: Vec<ArrayRef> = Vec::new();
    for i in 0..4 {
        columns.push(Arc::new(Int64Array::from(
            rows.iter().map(|r| r.ints[i]).collect::<Vec<_>>(),
        )));
    }
    for i in 0..5 {
        columns.push(Arc::new(StringArray::from(
            rows.iter()
                .map(|r| r.strings[i].as_deref())
                .collect::<Vec<_>>(),
        )));
    }
    let batch = RecordBatch::try_new(schema.clone(), columns).map_err(|_| Error::Invalid)?;
    let mut props = WriterProperties::builder()
        .set_writer_version(WriterVersion::PARQUET_2_0)
        .set_compression(Compression::ZSTD(ZstdLevel::try_new(6).unwrap()))
        .set_max_row_group_size(8192)
        .set_statistics_truncate_length(Some(64));
    for name in ["timestamp_ns", "end_timestamp_ns"] {
        props = props
            .set_column_dictionary_enabled(ColumnPath::from(name), false)
            .set_column_encoding(ColumnPath::from(name), Encoding::DELTA_BINARY_PACKED);
    }
    for name in ["trace_id", "span_id", "payload"] {
        props = props.set_column_dictionary_enabled(ColumnPath::from(name), false);
    }
    let sink = crate::out::BinaryWriter(crate::out::BinSink::with_capacity(4096));
    let mut writer =
        ArrowWriter::try_new(sink, schema, Some(props.build())).map_err(|_| Error::Invalid)?;
    writer.write(&batch).map_err(|_| Error::Invalid)?;
    let buf = writer
        .into_inner()
        .map_err(|_| Error::Invalid)?
        .0
        .finish(env);
    if rows.is_empty() {
        min = 0;
        max = 0;
    }
    Ok((buf, min, max, rows.len(), metadata_safe))
}

/// Bounded compaction: Arrow stays native; only tiny pruning summaries cross
/// to BEAM. No per-span maps, metadata decoding/re-encoding, or final blob copy.
type Compacted<'a> = (
    Binary<'a>,
    i64,
    i64,
    usize,
    Option<Vec<String>>,
    Vec<String>,
    bool,
);

/// Validated sources concatenated in input order, with what the summaries of
/// any subset of their rows need: per-row metadata proof and event presence.
struct Loaded {
    schema: arrow::datatypes::SchemaRef,
    merged: RecordBatch,
    rows: usize,
    safe: Vec<bool>,
    events: Vec<bool>,
}

fn column<'a, T: 'static>(batch: &'a RecordBatch, name: &str) -> Res<&'a T> {
    batch
        .column_by_name(name)
        .and_then(|a| a.as_any().downcast_ref::<T>())
        .ok_or(Error::Invalid)
}

// Any event in the plain or the typed metadata. Legacy rows without typed
// metadata count as having events: they never prove their absence.
fn has_events(fields: &crate::json_read::RawFields<'_>) -> bool {
    use crate::trace_search::{field, object};
    let empty = |raw: &[u8]| Parser::new(raw).raw_array().is_ok_and(|v| v.is_empty());
    let absent = || -> Option<bool> {
        let metadata = field(fields, b"otlp").ok()?;
        let typed = field(&object(metadata).ok()?, b"events").ok()?;
        Some(empty(field(fields, b"events").ok()?) && empty(typed))
    };
    absent() != Some(true)
}

fn load(blobs: Term<'_>, max_rows: usize) -> Res<Loaded> {
    let mut batches = Vec::new();
    let mut schema = None;
    let mut rows = 0usize;
    let mut payload_bytes = 0usize;
    let mut column_bytes = 0usize;
    let mut safe = Vec::new();
    let mut events = Vec::new();
    for term in blobs.decode::<ListIterator>().map_err(|_| Error::Invalid)? {
        let blob: Binary = term.decode().map_err(|_| Error::Invalid)?;
        let builder =
            ParquetRecordBatchReaderBuilder::try_new(crate::erlang_bytes::from_binary(blob))
                .map_err(|_| Error::Invalid)?;
        let declared = usize::try_from(builder.metadata().file_metadata().num_rows())
            .map_err(|_| Error::Invalid)?;
        if rows.checked_add(declared).is_none_or(|n| n > max_rows) {
            return Err(Error::TooMany);
        }
        if schema.as_ref().is_some_and(|s| s != builder.schema()) {
            return Err(Error::Invalid);
        }
        schema = Some(builder.schema().clone());
        for batch in builder
            .with_batch_size(1024)
            .build()
            .map_err(|_| Error::Invalid)?
        {
            let batch = batch.map_err(|_| Error::Invalid)?;
            rows += batch.num_rows();
            if rows > max_rows {
                return Err(Error::TooMany);
            }
            for name in STRINGS {
                let values: &StringArray = column(&batch, name)?;
                column_bytes += values.value_data().len();
                if name == "payload" {
                    payload_bytes += values.value_data().len();
                }
                if payload_bytes > MAX_PAYLOAD_BYTES || column_bytes > 2 * MAX_PAYLOAD_BYTES {
                    return Err(Error::PayloadTooLarge);
                }
            }
            let ts: &Int64Array = column(&batch, "timestamp_ns")?;
            let end: &Int64Array = column(&batch, "end_timestamp_ns")?;
            let service: &StringArray = column(&batch, "service")?;
            let trace: &StringArray = column(&batch, "trace_id")?;
            let payload: &StringArray = column(&batch, "payload")?;
            let span: &StringArray = column(&batch, "span_id")?;
            let name: &StringArray = column(&batch, "name")?;
            let kind: &Int64Array = column(&batch, "kind")?;
            let status: &Int64Array = column(&batch, "status_code")?;
            for i in 0..batch.num_rows() {
                if payload.is_null(i)
                    || span.is_null(i)
                    || name.is_null(i)
                    || kind.is_null(i)
                    || status.is_null(i)
                {
                    return Err(Error::Invalid);
                }
                if ts.is_null(i)
                    || end.is_null(i)
                    || trace.is_null(i)
                    || ts.value(i) < 0
                    || end.value(i) < ts.value(i)
                {
                    return Err(Error::Invalid);
                }
                let fields = crate::trace_metadata::validated_fields(payload.value(i).as_bytes())
                    .map_err(|_| Error::Invalid)?;
                let projected = [
                    if service.is_null(i) {
                        None
                    } else {
                        Some(service.value(i))
                    },
                    Some(trace.value(i)),
                    Some(span.value(i)),
                    Some(name.value(i)),
                ];
                validate_projection(
                    &fields,
                    projected,
                    [ts.value(i), end.value(i), kind.value(i), status.value(i)],
                )
                .map_err(|_| Error::InvalidProjection)?;
                let id = trace.value(i);
                if id.len() != 32
                    || id.bytes().all(|b| b == b'0')
                    || !id
                        .bytes()
                        .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
                {
                    return Err(Error::Invalid);
                }
                safe.push(metadata_service_safe(&fields, projected[0]));
                events.push(has_events(&fields));
            }
            batches.push(batch);
        }
    }
    let schema = schema.ok_or(Error::Invalid)?;
    let merged = concat_batches(&schema, &batches).map_err(|_| Error::Invalid)?;
    Ok(Loaded {
        schema,
        merged,
        rows,
        safe,
        events,
    })
}

/// Summary of some rows of a load: start bounds, complete service set
/// (≤128 values of 1..256 bytes), trace IDs, metadata proof, status codes
/// and whether any row has an event.
struct Summary {
    min: i64,
    max: i64,
    services: Option<Vec<String>>,
    ids: Vec<String>,
    safe: bool,
    statuses: Vec<i64>,
    events: bool,
    resource: OwnerSummary,
    span: OwnerSummary,
}

fn summarize(loaded: &Loaded, indices: &[u32]) -> Res<Summary> {
    let ts: &Int64Array = column(&loaded.merged, "timestamp_ns")?;
    let service: &StringArray = column(&loaded.merged, "service")?;
    let trace: &StringArray = column(&loaded.merged, "trace_id")?;
    let status: &Int64Array = column(&loaded.merged, "status_code")?;
    let payload: &StringArray = column(&loaded.merged, "payload")?;
    let (mut resource, mut span) = (Owner::new(), Owner::new());
    let (mut min, mut max) = (i64::MAX, i64::MIN);
    let mut services = Some(BTreeSet::new());
    let mut ids = BTreeSet::new();
    let mut statuses = BTreeSet::new();
    let (mut safe, mut events) = (true, false);
    for &i in indices {
        let i = i as usize;
        min = min.min(ts.value(i));
        max = max.max(ts.value(i));
        ids.insert(trace.value(i));
        statuses.insert(status.value(i));
        safe &= loaded.safe[i];
        events |= loaded.events[i];
        let fields = crate::trace_search::object(payload.value(i).as_bytes()).ok();
        let owner = |name: &[u8]| {
            fields
                .as_ref()
                .and_then(|f| crate::trace_search::field(f, name).ok())
        };
        resource.add(owner(b"resource"));
        span.add(owner(b"attributes"));
        services =
            services.filter(|_| !service.is_null(i) && (1..=256).contains(&service.value(i).len()));
        if let Some(set) = services.as_mut() {
            set.insert(service.value(i));
            if set.len() > 128 {
                services = None;
            }
        }
    }
    if indices.is_empty() {
        (min, max) = (0, 0);
    }
    Ok(Summary {
        min,
        max,
        services: services.map(|s| s.into_iter().map(str::to_owned).collect()),
        ids: ids.into_iter().map(str::to_owned).collect(),
        safe,
        statuses: statuses.into_iter().collect(),
        events,
        resource: resource.finish(),
        span: span.finish(),
    })
}

fn write<'a>(
    env: Env<'a>,
    schema: arrow::datatypes::SchemaRef,
    batch: &RecordBatch,
) -> Res<Binary<'a>> {
    let sink = crate::out::BinaryWriter(crate::out::BinSink::with_capacity(4096));
    let props = WriterProperties::builder()
        .set_writer_version(WriterVersion::PARQUET_2_0)
        .set_compression(Compression::ZSTD(ZstdLevel::try_new(6).unwrap()))
        .set_max_row_group_size(8192)
        .set_statistics_truncate_length(Some(64))
        .set_column_dictionary_enabled(ColumnPath::from("payload"), false)
        .set_column_dictionary_enabled(ColumnPath::from("trace_id"), false)
        .set_column_dictionary_enabled(ColumnPath::from("span_id"), false);
    let mut writer =
        ArrowWriter::try_new(sink, schema, Some(props.build())).map_err(|_| Error::Invalid)?;
    writer.write(batch).map_err(|_| Error::Invalid)?;
    Ok(writer
        .into_inner()
        .map_err(|_| Error::Invalid)?
        .0
        .finish(env))
}

fn sort_columns(batch: &RecordBatch, names: &[&str]) -> Res<Vec<SortColumn>> {
    names
        .iter()
        .map(|name| {
            Ok(SortColumn {
                values: batch.column_by_name(name).ok_or(Error::Invalid)?.clone(),
                options: None,
            })
        })
        .collect()
}

pub fn compact<'a>(env: Env<'a>, blobs: Term<'a>, max_rows: usize) -> Res<Compacted<'a>> {
    let loaded = load(blobs, max_rows)?;
    let sort = sort_columns(
        &loaded.merged,
        &["service", "timestamp_ns", "trace_id", "span_id"],
    )?;
    let indices = lexsort_to_indices(&sort, None).map_err(|_| Error::Invalid)?;
    let all: Vec<u32> = (0..loaded.rows as u32).collect();
    let summary = summarize(&loaded, &all)?;
    let sorted = take_record_batch(&loaded.merged, &indices).map_err(|_| Error::Invalid)?;
    let blob = write(env, loaded.schema.clone(), &sorted)?;
    Ok((
        blob,
        summary.min,
        summary.max,
        loaded.rows,
        summary.services,
        summary.ids,
        summary.safe,
    ))
}

/// One output of `compact_split`: blob, bounds, rows, summary.
pub type SplitOutput<'a> = (
    Binary<'a>,
    i64,
    i64,
    usize,
    (Option<Vec<String>>, Vec<String>, bool),
    (Vec<i64>, bool, OwnerSummary, OwnerSummary),
);

/// Merge sources into several outputs, each holding one service's rows of one
/// class (spans with error status or events, or the others) in start order,
/// at most `max_ids` distinct trace IDs (`max_flagged_ids` for the error/event
/// class, which TraceQL metrics read) and `max_output_rows` rows. Outputs
/// keep the encoder's `(service, timestamp, trace_id, span_id)` order, so a
/// service filter, an error/event filter and trace-ID context lookups each
/// read only the outputs that can hold their rows.
pub fn compact_split<'a>(
    env: Env<'a>,
    blobs: Term<'a>,
    max_rows: usize,
    max_ids: usize,
    max_flagged_ids: usize,
    max_output_rows: usize,
) -> Res<Vec<SplitOutput<'a>>> {
    let loaded = load(blobs, max_rows)?;
    let status: &Int64Array = column(&loaded.merged, "status_code")?;
    let flagged: arrow::array::BooleanArray = (0..loaded.rows)
        .map(|i| Some(status.value(i) == 2 || loaded.events[i]))
        .collect();
    let mut sort = sort_columns(&loaded.merged, &["service"])?;
    sort.push(SortColumn {
        values: Arc::new(flagged.clone()),
        options: None,
    });
    sort.extend(sort_columns(
        &loaded.merged,
        &["timestamp_ns", "trace_id", "span_id"],
    )?);
    let order = lexsort_to_indices(&sort, None).map_err(|_| Error::Invalid)?;
    let service: &StringArray = column(&loaded.merged, "service")?;
    let trace: &StringArray = column(&loaded.merged, "trace_id")?;
    let payload: &StringArray = column(&loaded.merged, "payload")?;
    let mut groups: Vec<Vec<u32>> = Vec::new();
    let mut current: Vec<u32> = Vec::new();
    let mut ids = std::collections::HashSet::new();
    let mut bytes = 0usize;
    let key = |i: usize| {
        (
            (!service.is_null(i)).then(|| service.value(i)),
            flagged.value(i),
        )
    };
    for &i in order.values() {
        let row = i as usize;
        let id = trace.value(row);
        let cap = if flagged.value(row) {
            max_flagged_ids
        } else {
            max_ids
        };
        let split = current.last().is_some_and(|&last| {
            key(last as usize) != key(row)
                || current.len() >= max_output_rows
                || bytes >= MAX_PAYLOAD_BYTES / 2
                || (!ids.contains(id) && ids.len() >= cap)
        });
        if split {
            groups.push(std::mem::take(&mut current));
            ids.clear();
            bytes = 0;
        }
        ids.insert(id);
        bytes += payload.value(row).len();
        current.push(i);
    }
    if !current.is_empty() {
        groups.push(current);
    }
    groups
        .into_iter()
        .map(|group| {
            let summary = summarize(&loaded, &group)?;
            let indices = arrow::array::UInt32Array::from(group);
            let batch = take_record_batch(&loaded.merged, &indices).map_err(|_| Error::Invalid)?;
            let blob = write(env, loaded.schema.clone(), &batch)?;
            Ok((
                blob,
                summary.min,
                summary.max,
                batch.num_rows(),
                (summary.services, summary.ids, summary.safe),
                (
                    summary.statuses,
                    summary.events,
                    summary.resource,
                    summary.span,
                ),
            ))
        })
        .collect()
}

pub fn row_count(blob: Binary<'_>) -> Res<usize> {
    let reader = ParquetRecordBatchReaderBuilder::try_new(crate::erlang_bytes::from_binary(blob))
        .map_err(|_| Error::Invalid)?;
    usize::try_from(reader.metadata().file_metadata().num_rows()).map_err(|_| Error::Invalid)
}

#[derive(Default)]
pub struct Selection {
    candidates: BinaryHeap<Reverse<Candidate>>,
    pub matches: usize,
    payload_bytes: usize,
    key_bytes: usize,
    projection: Option<Projection>,
}

/// With output fields, candidates retain only those members and a 128-bit
/// digest of their complete metadata key, so the candidate budgets count what a
/// result can contain. The digest orders nothing: complete keys only break ties
/// between rows with the same start, trace ID and span ID, and such rows with
/// different digests end the query with `ProjectionTie` so the caller reruns it
/// with complete keys. Equal digests mean identical rows.
struct Projection {
    fields: Vec<String>,
    retained: HashMap<(i64, String, String), (u128, usize)>,
}

impl Selection {
    pub fn projected(fields: Option<Vec<String>>) -> Self {
        Self {
            projection: fields.map(|fields| Projection {
                fields,
                retained: HashMap::new(),
            }),
            ..Self::default()
        }
    }

    pub fn kth(&self, limit: usize) -> Option<i64> {
        if self.candidates.len() >= limit && limit > 0 {
            self.candidates.peek().map(|c| c.0.key.0)
        } else {
            None
        }
    }
}

pub fn select<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start: Option<i128>,
    end: Option<i128>,
    filters: Term<'a>,
    max: usize,
    selection: &mut Selection,
) -> Res<usize> {
    let attributes = attribute_filters(env, filters)?;
    select_prepared(
        env,
        blob,
        start,
        end,
        filters,
        max,
        (&attributes, selection),
    )
}

pub(crate) fn select_prepared<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start: Option<i128>,
    end: Option<i128>,
    filters: Term<'a>,
    max: usize,
    state: (&AttributeFilters, &mut Selection),
) -> Res<usize> {
    let (attributes, selection) = state;
    let builder = ParquetRecordBatchReaderBuilder::try_new(crate::erlang_bytes::from_binary(blob))
        .map_err(|_| Error::Invalid)?;
    let metadata = builder.metadata();
    let row_count =
        usize::try_from(metadata.file_metadata().num_rows()).map_err(|_| Error::Invalid)?;
    let ts_index = metadata
        .file_metadata()
        .schema_descr()
        .columns()
        .iter()
        .position(|c| c.name() == "timestamp_ns")
        .ok_or(Error::Invalid)?;
    let groups = (0..metadata.num_row_groups())
        .filter(
            |i| match metadata.row_group(*i).column(ts_index).statistics() {
                Some(Statistics::Int64(s)) => {
                    start
                        .zip(s.max_opt())
                        .is_none_or(|(v, m)| v <= i128::from(*m))
                        && end
                            .zip(s.min_opt())
                            .is_none_or(|(v, m)| v >= i128::from(*m))
                }
                _ => true,
            },
        )
        .collect();
    let reader = builder
        .with_row_groups(groups)
        .build()
        .map_err(|_| Error::Invalid)?;
    let limit = get(env, filters, "limit")
        .ok()
        .map(|v| v.decode::<usize>().map_err(|_| Error::Invalid))
        .transpose()?;
    if limit == Some(0) {
        return Ok(row_count);
    }
    let root_only = get(env, filters, "root_only")
        .ok()
        .map(|v| v.decode::<bool>().map_err(|_| Error::Invalid))
        .transpose()?
        .unwrap_or(false);
    let parent = get(env, filters, "parent_span_id")
        .ok()
        .map(|v| {
            let mut json = Vec::new();
            JsonEncoder::new(env, 1024)
                .value(&mut json, v, 0)
                .map_err(|_| Error::Invalid)?;
            trace_sort_key::key(&json).map_err(|_| Error::Invalid)
        })
        .transpose()?;
    let min_duration = get(env, filters, "min_duration_ns")
        .ok()
        .map(|v| v.decode::<i64>().map_err(|_| Error::Invalid))
        .transpose()?;
    let max_duration = get(env, filters, "max_duration_ns")
        .ok()
        .map(|v| v.decode::<i64>().map_err(|_| Error::Invalid))
        .transpose()?;
    let wanted_strings: Vec<_> = STRINGS[..4]
        .iter()
        .map(|n| get(env, filters, n).ok())
        .collect();
    let wanted_ints: Vec<_> = INTS.iter().map(|n| get(env, filters, n).ok()).collect();
    let Selection {
        candidates,
        matches,
        payload_bytes,
        key_bytes,
        projection,
    } = selection;
    for batch in reader {
        let batch = batch.map_err(|_| Error::Invalid)?;
        let ints: Vec<_> = INTS
            .iter()
            .map(|n| {
                batch
                    .column_by_name(n)
                    .and_then(|a| a.as_any().downcast_ref::<Int64Array>())
                    .ok_or(Error::Invalid)
            })
            .collect::<Res<_>>()?;
        let strings: Vec<_> = STRINGS
            .iter()
            .map(|n| {
                batch
                    .column_by_name(n)
                    .and_then(|a| a.as_any().downcast_ref::<StringArray>())
                    .ok_or(Error::Invalid)
            })
            .collect::<Res<_>>()?;
        for i in 0..batch.num_rows() {
            if ints.iter().any(|c| c.is_null(i)) || strings[4].is_null(i) {
                return Err(Error::Invalid);
            }
            let ts = i128::from(ints[0].value(i));
            if start.is_some_and(|s| ts < s) || end.is_some_and(|e| ts > e) {
                continue;
            }
            let duration = ints[1]
                .value(i)
                .checked_sub(ints[0].value(i))
                .ok_or(Error::Invalid)?;
            if min_duration.is_some_and(|v| duration < v)
                || max_duration.is_some_and(|v| duration > v)
            {
                continue;
            }
            let mut kept = true;
            for (j, wanted) in wanted_strings.iter().enumerate() {
                if let Some(wanted) = wanted {
                    let b: Binary = wanted.decode().map_err(|_| Error::Invalid)?;
                    if strings[j].is_null(i) || strings[j].value(i).as_bytes() != b.as_slice() {
                        kept = false;
                        break;
                    }
                }
            }
            for (j, wanted) in wanted_ints.iter().enumerate() {
                if let Some(wanted) = wanted {
                    if ints[j].value(i) != wanted.decode::<i64>().map_err(|_| Error::Invalid)? {
                        kept = false;
                        break;
                    }
                }
            }
            if !kept {
                continue;
            }
            let payload = strings[4].value(i);
            crate::trace_metadata::validate(payload.as_bytes()).map_err(|_| Error::Invalid)?;
            if !matches_attributes(payload.as_bytes(), attributes, root_only, parent.as_deref())? {
                continue;
            }
            *matches += 1;
            if *matches > max {
                return Err(Error::TooMany);
            }
            if strings[1].is_null(i) || strings[2].is_null(i) {
                return Err(Error::Invalid);
            }
            let prefix = (ints[0].value(i), strings[1].value(i), strings[2].value(i));
            // Skip older rows before parsing their complete metadata key.
            if limit.is_some_and(|k| candidates.len() == k)
                && candidates
                    .peek()
                    .is_some_and(|c| prefix < (c.0.key.0, c.0.key.1.as_str(), c.0.key.2.as_str()))
            {
                continue;
            }
            let full =
                trace_sort_key::span_key(payload.as_bytes(), false).map_err(|_| Error::Invalid)?;
            let digest = projection
                .as_ref()
                .map(|_| xxhash_rust::xxh3::xxh3_128(&full));
            let key = (
                prefix.0,
                prefix.1.to_owned(),
                prefix.2.to_owned(),
                match digest {
                    Some(digest) => digest.to_be_bytes().to_vec(),
                    None => full,
                },
            );
            if let (Some(projection), Some(digest)) = (projection.as_ref(), digest) {
                let id = (key.0, key.1.clone(), key.2.clone());
                if projection
                    .retained
                    .get(&id)
                    .is_some_and(|(retained, _)| *retained != digest)
                {
                    return Err(Error::ProjectionTie);
                }
            }
            if limit.is_some_and(|k| candidates.len() == k) {
                if candidates.peek().is_some_and(|c| key <= c.0.key) {
                    continue;
                }
                let removed = candidates.pop().unwrap().0;
                *payload_bytes -= removed.payload.len();
                *key_bytes -= removed.key.3.len();
                if let Some(projection) = projection.as_mut() {
                    let id = (removed.key.0, removed.key.1, removed.key.2);
                    if let Some(entry) = projection.retained.get_mut(&id) {
                        entry.1 -= 1;
                        if entry.1 == 0 {
                            projection.retained.remove(&id);
                        }
                    }
                }
            }
            let payload = match projection.as_mut() {
                Some(projection) => {
                    let id = (key.0, key.1.clone(), key.2.clone());
                    projection
                        .retained
                        .entry(id)
                        .or_insert((digest.unwrap(), 0))
                        .1 += 1;
                    project(payload, &projection.fields)?
                }
                None => payload.to_owned(),
            };
            *payload_bytes += payload.len();
            *key_bytes += key.3.len();
            if *payload_bytes > MAX_PAYLOAD_BYTES || *key_bytes > MAX_PAYLOAD_BYTES {
                return Err(Error::QueryBytes);
            }
            candidates.push(Reverse(Candidate {
                key,
                payload,
                duration,
            }));
        }
    }
    Ok(row_count)
}

pub fn decode<'a>(
    env: Env<'a>,
    blob: Binary<'a>,
    start: Option<i128>,
    end: Option<i128>,
    filters: Term<'a>,
    max: usize,
) -> Res<Vec<Term<'a>>> {
    let mut selection = Selection::default();
    select(env, blob, start, end, filters, max, &mut selection)?;
    // Reference/compatibility record path. Public S3 queries finish as JSON in
    // Rust instead, without allocating per-span Erlang maps or payload binaries.
    let mut out = Vec::with_capacity(selection.candidates.len());
    let mut stacks = Stacks::new();
    for Reverse(candidate) in selection.candidates.into_sorted_vec() {
        let b = binary(env, candidate.payload.as_bytes());
        let mut terms = TermBuilder::new(env, &b);
        out.push(
            Parser::new(b.as_slice())
                .document_with(&mut terms, &mut stacks)
                .map_err(|_| Error::Invalid)?,
        );
    }
    Ok(out)
}

#[derive(Eq, PartialEq, Ord, PartialOrd)]
struct Candidate {
    key: (i64, String, String, Vec<u8>),
    payload: String,
    duration: i64,
}
impl Selection {
    pub fn json<'a>(self, env: Env<'a>, fields: Option<&[String]>) -> Res<Binary<'a>> {
        let mut out = crate::out::BinSink::with_capacity(4096);
        let candidates = self.candidates.into_sorted_vec();
        write_candidates(&mut out, &candidates, fields)?;
        Ok(out.finish(env))
    }

    pub fn assembly<'a>(
        self,
        env: Env<'a>,
        trace_id: &str,
        floor: Option<i128>,
    ) -> Res<Binary<'a>> {
        use crate::out::Sink;
        use std::collections::{BTreeMap, BTreeSet};
        let candidates = self.candidates.into_sorted_vec();
        let mut ids: BTreeMap<&str, (Vec<u8>, Option<&Vec<u8>>)> = BTreeMap::new();
        let mut roots = BTreeSet::new();
        let mut parents = BTreeSet::new();
        let mut duplicates = BTreeSet::new();
        let mut conflicts = BTreeSet::new();
        let mut unknown = BTreeSet::new();
        let mut projected_bytes = 0usize;
        for Reverse(candidate) in &candidates {
            if candidate.key.1 != trace_id {
                return Err(Error::Invalid);
            }
            let id = candidate.key.2.as_str();
            let fields = Parser::new(candidate.payload.as_bytes())
                .raw_object()
                .map_err(|_| Error::Invalid)?;
            let typed = fields
                .iter()
                .any(|(key, value)| key.as_ref() == b"otlp" && *value != b"null");
            if !typed {
                unknown.insert(id);
            }
            let projected = trace_sort_key::span_key(candidate.payload.as_bytes(), true)
                .map_err(|_| Error::Invalid)?;
            if let Some((previous, previous_typed)) = ids.get_mut(id) {
                duplicates.insert(id);
                if *previous != projected
                    || (typed && previous_typed.is_some_and(|key| key != &candidate.key.3))
                {
                    conflicts.insert(id);
                }
                if typed {
                    *previous_typed = Some(&candidate.key.3);
                }
            } else {
                projected_bytes += projected.len();
                if projected_bytes > MAX_PAYLOAD_BYTES {
                    return Err(Error::QueryBytes);
                }
                ids.insert(
                    id,
                    (projected, if typed { Some(&candidate.key.3) } else { None }),
                );
            }
            let raw = fields
                .iter()
                .find(|(key, _)| key.as_ref() == b"parent_span_id")
                .ok_or(Error::Invalid)?
                .1;
            if raw == b"null" {
                roots.insert(id);
            } else if raw.len() == 18
                && raw[0] == b'"'
                && raw[17] == b'"'
                && raw[1..17].iter().all(|b| b.is_ascii_hexdigit())
            {
                parents.insert(std::str::from_utf8(&raw[1..17]).map_err(|_| Error::Invalid)?);
            } else {
                return Err(Error::Invalid);
            }
        }
        let missing: BTreeSet<_> = parents
            .into_iter()
            .filter(|id| !ids.contains_key(id))
            .collect();
        let mut out = crate::out::BinSink::with_capacity(4096);
        out.extend(b"{\"trace_id\":");
        crate::json_write::write_str(&mut out, trace_id.as_bytes());
        out.extend(b",\"coverage\":");
        let coverage = if floor.is_some() {
            "all_stored_spans_at_or_above_floor"
        } else {
            "all_stored_spans"
        };
        crate::json_write::write_str(&mut out, coverage.as_bytes());
        out.extend(b",\"retention_floor_ns\":");
        match floor {
            Some(f) => out.extend(f.to_string().as_bytes()),
            None => out.extend(b"null"),
        }
        out.extend(b",\"span_count\":");
        out.extend(candidates.len().to_string().as_bytes());
        for (name, values) in [
            ("root_span_ids", roots),
            ("missing_parent_span_ids", missing),
            ("duplicate_span_ids", duplicates),
            ("conflicting_span_ids", conflicts),
            ("metadata_unknown_span_ids", unknown),
        ] {
            out.push(b',');
            crate::json_write::write_str(&mut out, name.as_bytes());
            out.extend(b":[");
            for (i, value) in values.into_iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                crate::json_write::write_str(&mut out, value.as_bytes());
            }
            out.push(b']');
        }
        out.extend(b",\"spans\":");
        write_candidates(&mut out, &candidates, None)?;
        out.push(b'}');
        if out.len() > MAX_PAYLOAD_BYTES {
            return Err(Error::QueryBytes);
        }
        Ok(out.finish(env))
    }
}

/// The members of `payload` named in `fields`, raw and in their original order.
/// `write_candidates` applies its own filters to them, so the output bytes equal
/// those written from the whole payload.
fn project(payload: &str, fields: &[String]) -> Res<String> {
    let values = Parser::new(payload.as_bytes())
        .raw_object()
        .map_err(|_| Error::Invalid)?;
    let mut out = Vec::with_capacity(64);
    out.push(b'{');
    for (key, value) in values {
        if !fields.iter().any(|f| f.as_bytes() == key.as_ref()) {
            continue;
        }
        if out.len() > 1 {
            out.push(b',');
        }
        crate::json_write::write_str(&mut out, key.as_ref());
        out.push(b':');
        out.extend_from_slice(value);
    }
    out.push(b'}');
    String::from_utf8(out).map_err(|_| Error::Invalid)
}

fn write_candidates(
    out: &mut crate::out::BinSink,
    candidates: &[Reverse<Candidate>],
    fields: Option<&[String]>,
) -> Res<()> {
    use crate::out::Sink;
    out.push(b'[');
    for (index, Reverse(candidate)) in candidates.iter().enumerate() {
        if index > 0 {
            out.push(b',');
        }
        let values = Parser::new(candidate.payload.as_bytes())
            .raw_object()
            .map_err(|_| Error::Invalid)?;
        out.push(b'{');
        let mut comma = false;
        for (key, value) in values {
            if key.as_ref() == b"duration_ns"
                || (key.as_ref() == b"otlp" && value == b"null")
                || fields.is_some_and(|fs| !fs.iter().any(|f| f.as_bytes() == key.as_ref()))
            {
                continue;
            }
            if comma {
                out.push(b',');
            }
            crate::json_write::write_str(out, key.as_ref());
            out.push(b':');
            out.extend(value);
            comma = true;
        }
        if fields.is_none_or(|fs| fs.iter().any(|f| f == "duration_ns")) {
            if comma {
                out.push(b',');
            }
            out.extend(b"\"duration_ns\":");
            out.extend(candidate.duration.to_string().as_bytes());
        }
        out.push(b'}');
        if out.len() > MAX_PAYLOAD_BYTES {
            return Err(Error::QueryBytes);
        }
    }
    out.push(b']');
    Ok(())
}
type ExactAttributeFilters = Vec<(&'static str, Vec<(Vec<u8>, Vec<u8>)>)>;
pub(crate) struct AttributeFilters {
    exact: ExactAttributeFilters,
    regex: Vec<(&'static str, Vec<(String, regex::Regex)>)>,
}
pub(crate) fn attribute_filters<'a>(env: Env<'a>, filters: Term<'a>) -> Res<AttributeFilters> {
    let mut out = Vec::new();
    for field in ["attributes", "resource"] {
        if let Ok(wanted) = get(env, filters, field) {
            let pairs: rustler::types::map::MapIterator =
                wanted.decode().map_err(|_| Error::Invalid)?;
            let mut values = Vec::new();
            for (k, v) in pairs {
                let k: Binary = k.decode().map_err(|_| Error::Invalid)?;
                let mut json = Vec::new();
                JsonEncoder::new(env, MAX_PAYLOAD_BYTES)
                    .value(&mut json, v, 0)
                    .map_err(|_| Error::Invalid)?;
                values.push((
                    k.as_slice().to_vec(),
                    trace_sort_key::key(&json).map_err(|_| Error::Invalid)?,
                ));
            }
            if !values.is_empty() {
                out.push((field, values));
            }
        }
    }
    let mut regex_filters = Vec::new();
    let mut count = 0;
    for (field, option) in [
        ("attributes", "attributes_regex"),
        ("resource", "resource_regex"),
    ] {
        if let Ok(wanted) = get(env, filters, option) {
            let pairs: rustler::types::map::MapIterator =
                wanted.decode().map_err(|_| Error::Invalid)?;
            let mut values = Vec::new();
            for (key, pattern) in pairs {
                let key: String = key.decode().map_err(|_| Error::Invalid)?;
                let pattern: String = pattern.decode().map_err(|_| Error::Invalid)?;
                count += 1;
                if count > 8 || key.is_empty() || key.len() > 256 || pattern.len() > 1024 {
                    return Err(Error::Invalid);
                }
                // Share Prometheus/Tempo's full-string, dot-all RE2 subset.
                let compiled =
                    crate::query_regex::anchored(&pattern).map_err(|_| Error::Invalid)?;
                values.push((key, compiled));
            }
            regex_filters.push((field, values));
        }
    }
    Ok(AttributeFilters {
        exact: out,
        regex: regex_filters,
    })
}
fn matches_attributes(
    payload: &[u8],
    filters: &AttributeFilters,
    root_only: bool,
    parent: Option<&[u8]>,
) -> Res<bool> {
    if filters.exact.is_empty() && filters.regex.is_empty() && !root_only && parent.is_none() {
        return Ok(true);
    }
    let fields = Parser::new(payload)
        .raw_object()
        .map_err(|_| Error::Invalid)?;
    if root_only || parent.is_some() {
        let (_, raw) = fields
            .iter()
            .find(|(k, _)| k.as_ref() == b"parent_span_id")
            .ok_or(Error::Invalid)?;
        let actual = trace_sort_key::key(raw).map_err(|_| Error::Invalid)?;
        if (root_only && actual != [0]) || parent.is_some_and(|v| actual != v) {
            return Ok(false);
        }
    }
    for (field, wanted) in &filters.exact {
        let Some((_, actual)) = fields.iter().find(|(k, _)| k.as_ref() == field.as_bytes()) else {
            return Err(Error::Invalid);
        };
        let values = Parser::new(actual)
            .raw_object()
            .map_err(|_| Error::Invalid)?;
        for (k, v) in wanted {
            let Some((_, raw)) = values
                .iter()
                .find(|(name, _)| name.as_ref() == k.as_slice())
            else {
                return Ok(false);
            };
            if trace_sort_key::key(raw).map_err(|_| Error::Invalid)? != *v {
                return Ok(false);
            }
        }
    }
    for (field, wanted) in &filters.regex {
        let Some((_, actual)) = fields.iter().find(|(k, _)| k.as_ref() == field.as_bytes()) else {
            return Err(Error::Invalid);
        };
        let values = Parser::new(actual)
            .raw_object()
            .map_err(|_| Error::Invalid)?;
        for (key, regex) in wanted {
            let Some((_, raw)) = values
                .iter()
                .find(|(name, _)| name.as_ref() == key.as_bytes())
            else {
                return Ok(false);
            };
            let Ok(value) = Parser::new(raw).string() else {
                return Ok(false);
            };
            let value = std::str::from_utf8(value.as_ref()).map_err(|_| Error::Invalid)?;
            if !regex.is_match(value) {
                return Ok(false);
            }
        }
    }
    Ok(true)
}

/// Per output, the string values of each resource ("r") and span ("s")
/// attribute key, as `TraceAttributeSummary.build/1` collects them from the
/// records' projected maps: at most 64 keys, 8 values of at most 96 bytes per
/// key (more become unknown, `None`), and whether no unlisted key holds a
/// string value. A row whose map is missing leaves the owner unknown.
#[derive(Default)]
struct Owner {
    keys: std::collections::BTreeMap<String, Option<BTreeSet<String>>>,
    complete: bool,
    unknown: bool,
}

pub type OwnerSummary = (bool, Vec<(String, Option<Vec<String>>)>);

impl Owner {
    fn new() -> Self {
        Owner {
            complete: true,
            ..Default::default()
        }
    }

    fn add(&mut self, raw: Option<&[u8]>) {
        if self.unknown {
            return;
        }
        let Some(fields) = raw.and_then(|raw| crate::trace_search::object(raw).ok()) else {
            self.unknown = true;
            return;
        };
        for (key, value) in fields.iter() {
            // Only string projections are tracked; other types never match.
            let Ok(value) = crate::trace_search::string(value) else {
                continue;
            };
            let Ok(key) = std::str::from_utf8(key.as_ref()) else {
                self.complete = false;
                continue;
            };
            let count = self.keys.len();
            match self.keys.get_mut(key) {
                Some(None) => {}
                Some(slot @ Some(_)) => {
                    let values = slot.as_mut().expect("present");
                    values.insert(value.clone());
                    if value.len() > 96 || values.len() > 8 {
                        *slot = None;
                    }
                }
                None if (1..=256).contains(&key.len()) && count < 64 => {
                    let values = (value.len() <= 96).then(|| BTreeSet::from([value]));
                    self.keys.insert(key.to_owned(), values);
                }
                None => self.complete = false,
            }
        }
    }

    fn finish(self) -> OwnerSummary {
        if self.unknown {
            return (false, Vec::new());
        }
        let keys = self
            .keys
            .into_iter()
            .map(|(key, values)| (key, values.map(|v| v.into_iter().collect())))
            .collect();
        (self.complete, keys)
    }
}
