//! Per-minute log rollups: for each minute bucket and each distinct stream
//! (resource labels, structured metadata, promoted service and level), the
//! number of log lines and their byte size as LogQL counts them.
//!
//! A rollup answers pipeline-free `count_over_time`, `bytes_over_time`,
//! `rate` and `bytes_rate` windows that start and end on minute boundaries
//! exactly as reading the lines would (`crate::log_metric` folds rollup rows
//! into the same bins it folds lines into). The dedicated trace and span ID
//! columns are left out of stream identity; each row counts the lines that
//! had either (`traced`), so readers grouping by those labels read lines.
//!
//! A bucket ending at `b` holds the lines with `b - 60s < ts <= b`, the
//! window shape LogQL ranges use. Rows are written in bucket order.
//!
//! Objects whose rows the evaluator could not reproduce (non-string bodies or
//! label values) are never built: building answers `:fallback` instead.

use crate::log_metric;
use crate::query_filter;
use arrow::array::{Array, Int64Array, Int64Builder, RecordBatch, StringArray, StringBuilder};
use arrow::datatypes::{DataType, Field, Schema};
use bytes::Bytes;
use parquet::arrow::arrow_reader::ParquetRecordBatchReaderBuilder;
use parquet::arrow::ArrowWriter;
use parquet::basic::{Compression, ZstdLevel};
use parquet::file::metadata::KeyValue;
use parquet::file::properties::{EnabledStatistics, WriterProperties, WriterVersion};
use parquet::schema::types::ColumnPath;
use rustler::{Binary, Encoder, Env, ListIterator, ResourceArc, Term};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

pub const BUCKET_NS: i64 = 60_000_000_000;
pub const ROLLUP_KEY: &str = "pulse.log.rollup";
pub const ROLLUP_VERSION: &str = "1";
pub const SOURCES_KEY: &str = "pulse.log.rollup.sources";
// Distinct (bucket, stream) rows one build may hold.
const MAX_ROWS: usize = 4_000_000;

mod atoms {
    rustler::atoms! { ok, error, fallback, nil, too_large }
}

/// The end of the minute bucket holding `ts`: the smallest multiple of a
/// minute that is `>= ts`.
pub fn bucket_end(ts: i64) -> i64 {
    (ts.saturating_sub(1)).div_euclid(BUCKET_NS) * BUCKET_NS + BUCKET_NS
}

#[derive(Debug)]
pub enum RollupError {
    Fallback,
    TooLarge,
}

/// The label inputs of one stream, as stored in log segments.
#[derive(Clone, PartialEq, Eq, Hash)]
pub struct Stream {
    pub resource: Arc<str>,
    pub attributes: Arc<str>,
    pub service: Option<Arc<str>>,
    pub level: Option<Arc<str>>,
}

pub struct RollupRow {
    pub bucket_end: i64,
    pub stream: u32,
    pub count: i64,
    pub bytes: i64,
    pub traced: i64,
}

/// One rollup cell: lines, their bytes, and lines carrying a trace/span ID.
#[derive(Clone, Copy, Default)]
pub struct Cell {
    pub count: i64,
    pub bytes: i64,
    pub traced: i64,
}

/// Accumulates minute buckets in `[start, end]` from log segments or other
/// rollups.
pub struct Builder {
    start: i64,
    end: i64,
    streams: Vec<Stream>,
    index: HashMap<Stream, u32>,
    cells: HashMap<(i64, u32), Cell>,
    // When set, only these bucket ends are counted.
    allowed: Option<std::collections::HashSet<i64>>,
}

impl Builder {
    pub fn new(start: i64, end: i64) -> Self {
        Builder {
            start,
            end,
            streams: Vec::new(),
            index: HashMap::new(),
            cells: HashMap::new(),
            allowed: None,
        }
    }

    fn wanted(&self, bucket: i64) -> bool {
        self.allowed
            .as_ref()
            .is_none_or(|allowed| allowed.contains(&bucket))
    }

    fn intern(&mut self, stream: Stream) -> Result<u32, RollupError> {
        if let Some(index) = self.index.get(&stream) {
            return Ok(*index);
        }
        // Rows whose labels the evaluator cannot build natively would make
        // the rollup answer differently from reading lines.
        log_metric::validate_labels(
            &stream.resource,
            &stream.attributes,
            stream.service.as_deref(),
            stream.level.as_deref(),
        )
        .map_err(|_| RollupError::Fallback)?;
        let index = self.streams.len() as u32;
        self.streams.push(stream.clone());
        self.index.insert(stream, index);
        Ok(index)
    }

    fn add_cell(&mut self, bucket: i64, stream: u32, add: Cell) -> Result<(), RollupError> {
        if self.cells.len() >= MAX_ROWS && !self.cells.contains_key(&(bucket, stream)) {
            return Err(RollupError::TooLarge);
        }
        let cell = self.cells.entry((bucket, stream)).or_default();
        cell.count += add.count;
        cell.bytes += add.bytes;
        cell.traced += add.traced;
        Ok(())
    }

    /// Add every line of one log segment with a timestamp in range.
    pub fn add_segment(&mut self, bytes: Bytes) -> Result<usize, RollupError> {
        let builder =
            ParquetRecordBatchReaderBuilder::try_new(bytes).map_err(|_| RollupError::Fallback)?;
        let schema = builder.schema().clone();
        let names = [
            "timestamp_ns",
            "service",
            "severity_text",
            "body",
            "attributes",
            "resource",
            "trace_id",
            "span_id",
        ];
        let mut indexes = Vec::with_capacity(names.len());
        for name in names {
            indexes.push(schema.index_of(name).map_err(|_| RollupError::Fallback)?);
        }
        let projection = parquet::arrow::ProjectionMask::roots(builder.parquet_schema(), indexes);
        let reader = builder
            .with_projection(projection)
            .with_batch_size(8192)
            .build()
            .map_err(|_| RollupError::Fallback)?;
        let mut added = 0;
        for batch in reader {
            let batch = batch.map_err(|_| RollupError::Fallback)?;
            let strings = |name: &str| -> Result<&StringArray, RollupError> {
                batch
                    .column_by_name(name)
                    .and_then(|c| c.as_any().downcast_ref::<StringArray>())
                    .ok_or(RollupError::Fallback)
            };
            let times = batch
                .column_by_name("timestamp_ns")
                .and_then(|c| c.as_any().downcast_ref::<Int64Array>())
                .ok_or(RollupError::Fallback)?;
            let (service, level, body) = (
                strings("service")?,
                strings("severity_text")?,
                strings("body")?,
            );
            let (attributes, resource) = (strings("attributes")?, strings("resource")?);
            let (trace_id, span_id) = (strings("trace_id")?, strings("span_id")?);
            // Streams repeat in runs: reuse the previous row's interned index.
            let mut previous: Option<(usize, u32)> = None;
            for row in 0..batch.num_rows() {
                if times.is_null(row) {
                    continue;
                }
                let ts = times.value(row);
                if ts < self.start || ts > self.end || !self.wanted(bucket_end(ts)) {
                    continue;
                }
                let raw = (!body.is_null(row) && !body.value(row).is_empty())
                    .then(|| body.value(row).as_bytes());
                // Entry.line re-encodes non-string bodies; only strings count natively.
                if raw.is_some_and(|raw| {
                    raw.len() < 2 || raw[0] != b'"' || raw[raw.len() - 1] != b'"'
                }) {
                    return Err(RollupError::Fallback);
                }
                let size =
                    raw.map_or(0, |raw| query_filter::line_bytes_for_match(raw).len()) as i64;
                let same = previous.is_some_and(|(p, _)| {
                    same_value(resource, p, row)
                        && same_value(attributes, p, row)
                        && same_value(service, p, row)
                        && same_value(level, p, row)
                });
                let stream = match previous {
                    Some((_, index)) if same => index,
                    _ => {
                        let text = |a: &StringArray| -> Arc<str> {
                            Arc::from(if a.is_null(row) { "" } else { a.value(row) })
                        };
                        let optional =
                            |a: &StringArray| (!a.is_null(row)).then(|| Arc::from(a.value(row)));
                        self.intern(Stream {
                            resource: text(resource),
                            attributes: text(attributes),
                            service: optional(service),
                            level: optional(level),
                        })?
                    }
                };
                previous = Some((row, stream));
                let has_id = |a: &StringArray| !a.is_null(row) && !a.value(row).is_empty();
                let traced = i64::from(has_id(trace_id) || has_id(span_id));
                self.add_cell(
                    bucket_end(ts),
                    stream,
                    Cell {
                        count: 1,
                        bytes: size,
                        traced,
                    },
                )?;
                added += 1;
            }
        }
        Ok(added)
    }

    /// Add the buckets of another rollup that lie in range and, when `only`
    /// is nonempty, in `only`.
    pub fn add_rollup(&mut self, bytes: Bytes, only: &[i64]) -> Result<usize, RollupError> {
        let mut added = 0;
        let (start, end) = (self.start, self.end);
        let only: std::collections::HashSet<i64> = only.iter().copied().collect();
        read(bytes, |bucket, stream, cell| {
            if bucket - BUCKET_NS + 1 < start
                || bucket > end
                || !self.wanted(bucket)
                || (!only.is_empty() && !only.contains(&bucket))
            {
                return Ok(());
            }
            let index = self.intern(stream)?;
            self.add_cell(bucket, index, cell)?;
            added += 1;
            Ok(())
        })?;
        Ok(added)
    }

    /// Encode the rollup, recording `sources` (object keys) in its metadata.
    /// Also returns the line count of every bucket.
    pub fn finish(self, sources: &[String]) -> Result<Finished, RollupError> {
        let mut rows: Vec<RollupRow> = self
            .cells
            .into_iter()
            .map(|((bucket_end, stream), c)| RollupRow {
                bucket_end,
                stream,
                count: c.count,
                bytes: c.bytes,
                traced: c.traced,
            })
            .collect();
        let streams = &self.streams;
        rows.sort_unstable_by(|a, b| {
            let (sa, sb) = (&streams[a.stream as usize], &streams[b.stream as usize]);
            (
                a.bucket_end,
                &sa.service,
                &sa.resource,
                &sa.attributes,
                &sa.level,
            )
                .cmp(&(
                    b.bucket_end,
                    &sb.service,
                    &sb.resource,
                    &sb.attributes,
                    &sb.level,
                ))
        });
        let mut totals: Vec<(i64, i64)> = Vec::new();
        for row in &rows {
            match totals.last_mut() {
                Some((bucket, count)) if *bucket == row.bucket_end => *count += row.count,
                _ => totals.push((row.bucket_end, row.count)),
            }
        }
        let payload = encode(&rows, streams, sources)?;
        Ok(Finished {
            payload,
            rows: rows.len(),
            totals,
        })
    }
}

pub struct Finished {
    pub payload: Vec<u8>,
    pub rows: usize,
    /// `(bucket_end, lines)` in bucket order.
    pub totals: Vec<(i64, i64)>,
}

fn same_value(array: &StringArray, a: usize, b: usize) -> bool {
    match (array.is_null(a), array.is_null(b)) {
        (true, true) => true,
        (false, false) => array.value(a) == array.value(b),
        _ => false,
    }
}

fn schema() -> Arc<Schema> {
    let fields = vec![
        // A leading integer column named unlike any log column makes log
        // segment readers reject rollups rather than misread them.
        Field::new("bucket_end", DataType::Int64, false),
        Field::new("resource", DataType::Utf8, false),
        Field::new("attributes", DataType::Utf8, false),
        Field::new("service", DataType::Utf8, true),
        Field::new("severity_text", DataType::Utf8, true),
        Field::new("count", DataType::Int64, false),
        Field::new("bytes", DataType::Int64, false),
        Field::new("traced", DataType::Int64, false),
    ];
    let metadata = HashMap::from([(ROLLUP_KEY.to_owned(), ROLLUP_VERSION.to_owned())]);
    Arc::new(Schema::new_with_metadata(fields, metadata))
}

fn encode(
    rows: &[RollupRow],
    streams: &[Stream],
    sources: &[String],
) -> Result<Vec<u8>, RollupError> {
    let n = rows.len();
    let mut bucket = Int64Builder::with_capacity(n);
    let mut resource = StringBuilder::with_capacity(n, n * 32);
    let mut attributes = StringBuilder::with_capacity(n, n * 16);
    let mut service = StringBuilder::with_capacity(n, n * 8);
    let mut level = StringBuilder::with_capacity(n, n * 4);
    let mut count = Int64Builder::with_capacity(n);
    let mut bytes = Int64Builder::with_capacity(n);
    let mut traced = Int64Builder::with_capacity(n);
    for row in rows {
        let stream = &streams[row.stream as usize];
        bucket.append_value(row.bucket_end);
        resource.append_value(&stream.resource);
        attributes.append_value(&stream.attributes);
        service.append_option(stream.service.as_deref());
        level.append_option(stream.level.as_deref());
        count.append_value(row.count);
        bytes.append_value(row.bytes);
        traced.append_value(row.traced);
    }
    let columns: Vec<Arc<dyn Array>> = vec![
        Arc::new(bucket.finish()),
        Arc::new(resource.finish()),
        Arc::new(attributes.finish()),
        Arc::new(service.finish()),
        Arc::new(level.finish()),
        Arc::new(count.finish()),
        Arc::new(bytes.finish()),
        Arc::new(traced.finish()),
    ];
    let batch = RecordBatch::try_new(schema(), columns).map_err(|_| RollupError::Fallback)?;
    let mut builder = WriterProperties::builder()
        .set_writer_version(WriterVersion::PARQUET_2_0)
        .set_compression(Compression::ZSTD(
            ZstdLevel::try_new(6).map_err(|_| RollupError::Fallback)?,
        ))
        .set_statistics_enabled(EnabledStatistics::Chunk)
        .set_offset_index_disabled(true)
        .set_max_row_group_size(65_536);
    for column in ["resource", "attributes", "service", "severity_text"] {
        builder = builder.set_column_dictionary_enabled(ColumnPath::from(column), true);
    }
    if !sources.is_empty() {
        builder = builder.set_key_value_metadata(Some(vec![KeyValue::new(
            SOURCES_KEY.to_owned(),
            sources.join("\n"),
        )]));
    }
    let mut out = Vec::with_capacity(256 + n * 8);
    let mut writer = ArrowWriter::try_new(&mut out, batch.schema(), Some(builder.build()))
        .map_err(|_| RollupError::Fallback)?;
    writer.write(&batch).map_err(|_| RollupError::Fallback)?;
    writer.close().map_err(|_| RollupError::Fallback)?;
    Ok(out)
}

fn reader(bytes: Bytes) -> Result<ParquetRecordBatchReaderBuilder<Bytes>, RollupError> {
    let builder =
        ParquetRecordBatchReaderBuilder::try_new(bytes).map_err(|_| RollupError::Fallback)?;
    let schema = builder.schema();
    let expected = self::schema();
    // Read historical rollups without rewriting them. Both aliases at once
    // are ambiguous, even when their values happen to agree.
    let version = match (
        schema.metadata().get(ROLLUP_KEY),
        schema.metadata().get("pulso.log.rollup"),
    ) {
        (Some(version), None) | (None, Some(version)) => Some(version.as_str()),
        _ => None,
    };
    if version != Some(ROLLUP_VERSION)
        || schema.fields().len() != expected.fields().len()
        || schema
            .fields()
            .iter()
            .zip(expected.fields().iter())
            .any(|(a, b)| a.name() != b.name() || a.data_type() != b.data_type())
    {
        return Err(RollupError::Fallback);
    }
    Ok(builder)
}

/// The source keys recorded in a rollup, empty when none were.
pub fn sources(bytes: Bytes) -> Result<Vec<String>, RollupError> {
    let builder = reader(bytes)?;
    let metadata = builder.metadata().file_metadata().key_value_metadata();
    let mut entries = metadata
        .into_iter()
        .flatten()
        .filter(|kv| kv.key == SOURCES_KEY || kv.key == "pulso.log.rollup.sources");
    let value = entries.next().map(|kv| kv.value.as_ref());
    if entries.next().is_some() || matches!(value, Some(None)) {
        return Err(RollupError::Fallback);
    }
    Ok(value
        .flatten()
        .map(|value| {
            value
                .split('\n')
                .filter(|k| !k.is_empty())
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default())
}

/// Visit every rollup row: `(bucket_end, stream, cell)`.
pub fn read(
    bytes: Bytes,
    mut visit: impl FnMut(i64, Stream, Cell) -> Result<(), RollupError>,
) -> Result<(), RollupError> {
    let reader = reader(bytes)?
        .with_batch_size(8192)
        .build()
        .map_err(|_| RollupError::Fallback)?;
    for batch in reader {
        let batch = batch.map_err(|_| RollupError::Fallback)?;
        let ints = |i: usize| {
            batch
                .column(i)
                .as_any()
                .downcast_ref::<Int64Array>()
                .ok_or(RollupError::Fallback)
        };
        let strings = |i: usize| {
            batch
                .column(i)
                .as_any()
                .downcast_ref::<StringArray>()
                .ok_or(RollupError::Fallback)
        };
        let (bucket, count, size, traced) = (ints(0)?, ints(5)?, ints(6)?, ints(7)?);
        let (resource, attributes, service, level) =
            (strings(1)?, strings(2)?, strings(3)?, strings(4)?);
        let mut previous: Option<(usize, Stream)> = None;
        for row in 0..batch.num_rows() {
            let stream = match &previous {
                Some((p, stream))
                    if same_value(resource, *p, row)
                        && same_value(attributes, *p, row)
                        && same_value(service, *p, row)
                        && same_value(level, *p, row) =>
                {
                    stream.clone()
                }
                _ => Stream {
                    resource: Arc::from(resource.value(row)),
                    attributes: Arc::from(attributes.value(row)),
                    service: (!service.is_null(row)).then(|| Arc::from(service.value(row))),
                    level: (!level.is_null(row)).then(|| Arc::from(level.value(row))),
                },
            };
            let cell = Cell {
                count: count.value(row),
                bytes: size.value(row),
                traced: traced.value(row),
            };
            if cell.count < 1
                || cell.bytes < 0
                || cell.traced < 0
                || cell.traced > cell.count
                || bucket.value(row).rem_euclid(BUCKET_NS) != 0
            {
                return Err(RollupError::Fallback);
            }
            visit(bucket.value(row), stream.clone(), cell)?;
            previous = Some((row, stream));
        }
    }
    Ok(())
}

// ---- NIFs ------------------------------------------------------------------

pub struct LogRollup(Mutex<Option<Builder>>);

#[rustler::resource_impl]
impl rustler::Resource for LogRollup {}

fn error<'a>(env: Env<'a>, reason: RollupError) -> Term<'a> {
    match reason {
        RollupError::TooLarge => (atoms::error(), atoms::too_large()).encode(env),
        RollupError::Fallback => atoms::fallback().encode(env),
    }
}

/// A rollup of the buckets in `[start, end]`, or with a nonempty `buckets`
/// list of bucket ends only those.
#[rustler::nif]
fn log_rollup_new(start: i64, end: i64, buckets: Vec<i64>) -> ResourceArc<LogRollup> {
    let mut builder = Builder::new(start, end);
    if !buckets.is_empty() {
        builder.allowed = Some(buckets.into_iter().collect());
    }
    ResourceArc::new(LogRollup(Mutex::new(Some(builder))))
}

/// Add a log segment (`segment` true) or the `buckets` of a rollup (all
/// when empty): `{:ok, rows}`.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_rollup_add<'a>(
    env: Env<'a>,
    rollup: ResourceArc<LogRollup>,
    blob: Binary<'a>,
    segment: bool,
    buckets: Vec<i64>,
) -> Term<'a> {
    let Ok(mut guard) = rollup.0.lock() else {
        return atoms::fallback().encode(env);
    };
    let Some(builder) = guard.as_mut() else {
        return atoms::fallback().encode(env);
    };
    let bytes = crate::erlang_bytes::from_binary(blob);
    let result = if segment {
        builder.add_segment(bytes)
    } else {
        builder.add_rollup(bytes, &buckets)
    };
    match result {
        Ok(rows) => (atoms::ok(), rows).encode(env),
        Err(reason) => {
            guard.take();
            error(env, reason)
        }
    }
}

/// `{:ok, payload, rows, [{bucket_end, lines}]}`, recording `sources` (a
/// list of object keys) in the rollup's metadata.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_rollup_finish<'a>(
    env: Env<'a>,
    rollup: ResourceArc<LogRollup>,
    sources: Term<'a>,
) -> Term<'a> {
    let Some(builder) = rollup.0.lock().ok().and_then(|mut guard| guard.take()) else {
        return atoms::fallback().encode(env);
    };
    let Ok(sources) = sources.decode::<ListIterator>().and_then(|list| {
        list.map(|t| t.decode::<String>())
            .collect::<Result<Vec<_>, _>>()
    }) else {
        return atoms::fallback().encode(env);
    };
    match builder.finish(&sources) {
        Ok(finished) => {
            let mut binary = rustler::NewBinary::new(env, finished.payload.len());
            binary.as_mut_slice().copy_from_slice(&finished.payload);
            (
                atoms::ok(),
                Binary::from(binary),
                finished.rows,
                finished.totals,
            )
                .encode(env)
        }
        Err(reason) => error(env, reason),
    }
}

/// `{:ok, [key]}`: the source keys a rollup records.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_rollup_sources<'a>(env: Env<'a>, blob: Binary<'a>) -> Term<'a> {
    match sources(crate::erlang_bytes::from_binary(blob)) {
        Ok(keys) => (atoms::ok(), keys).encode(env),
        Err(reason) => error(env, reason),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn historical_rollups_reject_ambiguous_versions_and_sources() {
        let original = Bytes::from_static(include_bytes!(
            "../../../test/fixtures/metrics/legacy_1_38/log_rollup.parquet"
        ));
        assert_eq!(
            sources(original.clone()).unwrap(),
            vec!["source-a", "source-b"]
        );
        let batch = reader(original)
            .unwrap()
            .build()
            .unwrap()
            .next()
            .unwrap()
            .unwrap();
        for (metadata, keys, valid) in [
            (vec![(ROLLUP_KEY, "1")], vec![(SOURCES_KEY, "new")], true),
            (
                vec![("pulso.log.rollup", "1")],
                vec![("pulso.log.rollup.sources", "old")],
                true,
            ),
            (
                vec![(ROLLUP_KEY, "1"), ("pulso.log.rollup", "1")],
                vec![],
                false,
            ),
            (vec![("pulso.log.rollup", "2")], vec![], false),
            (
                vec![(ROLLUP_KEY, "1")],
                vec![(SOURCES_KEY, "a"), ("pulso.log.rollup.sources", "b")],
                false,
            ),
            (
                vec![(ROLLUP_KEY, "1")],
                vec![(SOURCES_KEY, "a"), (SOURCES_KEY, "a")],
                false,
            ),
        ] {
            let schema = Arc::new(
                batch.schema().as_ref().clone().with_metadata(
                    metadata
                        .into_iter()
                        .map(|(k, v)| (k.into(), v.into()))
                        .collect(),
                ),
            );
            let batch = RecordBatch::try_new(schema.clone(), batch.columns().to_vec()).unwrap();
            let properties = WriterProperties::builder()
                .set_key_value_metadata(Some(
                    keys.into_iter()
                        .map(|(k, v)| KeyValue::new(k.into(), v.to_owned()))
                        .collect(),
                ))
                .build();
            let mut payload = Vec::new();
            let mut writer = ArrowWriter::try_new(&mut payload, schema, Some(properties)).unwrap();
            writer.write(&batch).unwrap();
            writer.close().unwrap();
            assert_eq!(sources(Bytes::from(payload)).is_ok(), valid);
        }
        assert_eq!(
            schema().metadata().get(ROLLUP_KEY).map(String::as_str),
            Some("1")
        );
        assert!(!schema().metadata().contains_key("pulso.log.rollup"));
    }

    #[test]
    fn buckets_end_on_minutes_and_hold_the_window_shape() {
        assert_eq!(bucket_end(1), BUCKET_NS);
        assert_eq!(bucket_end(BUCKET_NS), BUCKET_NS);
        assert_eq!(bucket_end(BUCKET_NS + 1), 2 * BUCKET_NS);
        assert_eq!(bucket_end(0), 0);
        assert_eq!(bucket_end(-BUCKET_NS + 1), 0);
    }

    #[test]
    fn rollups_round_trip_with_sources() {
        let mut builder = Builder::new(0, 10 * BUCKET_NS);
        let stream = Stream {
            resource: Arc::from(r#"{"namespace":"tuist"}"#),
            attributes: Arc::from(r#"{"detected_level":"info"}"#),
            service: Some(Arc::from("api")),
            level: None,
        };
        let index = builder.intern(stream.clone()).unwrap();
        let cell = |count, bytes, traced| Cell {
            count,
            bytes,
            traced,
        };
        builder.add_cell(BUCKET_NS, index, cell(3, 30, 1)).unwrap();
        builder
            .add_cell(2 * BUCKET_NS, index, cell(1, 7, 0))
            .unwrap();
        builder.add_cell(BUCKET_NS, index, cell(2, 1, 0)).unwrap();
        let finished = builder.finish(&["a".into(), "b".into()]).unwrap();
        assert_eq!(finished.rows, 2);
        assert_eq!(finished.totals, vec![(BUCKET_NS, 5), (2 * BUCKET_NS, 1)]);
        let bytes = Bytes::from(finished.payload);
        assert_eq!(
            sources(bytes.clone()).unwrap(),
            vec!["a".to_owned(), "b".to_owned()]
        );
        let mut seen = Vec::new();
        read(bytes, |b, s, c| {
            assert!(s == stream);
            seen.push((b, c.count, c.bytes, c.traced));
            Ok(())
        })
        .unwrap();
        assert_eq!(seen, vec![(BUCKET_NS, 5, 31, 1), (2 * BUCKET_NS, 1, 7, 0)]);
    }
}
