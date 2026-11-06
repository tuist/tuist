//! Parquet metric segment encoding and decoding.
//!
//! Six scalar/label columns plus nullable typed `otlp Utf8` JSON metadata:
//! `series_id Int64`, `timestamp_ns Int64`, `value Float64`, `metric_name Utf8`,
//! `labels_canonical Binary`, `labels_json Utf8`. Legacy six-column reads remain
//! supported. Row groups adapt to series runs; rows sorted by
//! `(series_id, timestamp_ns)` on write. That sort is what the
//! Prometheus storage model expects on the hot query path: a
//! label-matcher query picks series, then streams samples per series in
//! time order. The dictionary + zstd encoding on `metric_name` and
//! `labels_canonical` compresses tightly because a single series
//! produces thousands of consecutive identical values; delta-binary-
//! packed `timestamp_ns` compresses because samples arrive at a fixed
//! scrape cadence.
//!
//! `labels_canonical` is the exact byte sequence hashed into
//! `series_id` (see [`crate::stable_hash`]): `name<0xff>value<0xff>…`
//! across sorted labels. Keeping it in the segment lets a decoder
//! re-verify series identity without rebuilding the hash. Optional native
//! footer postings map complete label values to canonical-series ordinals
//! and row groups; unknown/over-budget indexes retain the scan path.
//!
//! The matcher-pushdown surface for v1 metrics is deliberately small:
//! a decoder-side filter accepts a list of `(name, op, value)`
//! matchers and only materialises rows for which every matcher
//! holds. `op` is one of `:eq | :neq | :re | :nre`. Regex matchers
//! compile once per decode and apply per row. Positive equality matchers
//! first intersect optional footer postings; other matchers still filter
//! surviving rows. This saves Arrow decode work, not S3 download bytes.
//!
//! No fallback to Elixir: a decode failure here is a hard error (the
//! Elixir side maps `:fallback` to `{:error, {:decode_failed, _}}`),
//! same policy as the log Parquet codec.

use crate::stable_hash;

use arrow::array::{
    Array, BinaryArray, BinaryBuilder, DictionaryArray, Float64Array, Float64Builder, Int64Array,
    Int64Builder, RecordBatch, StringArray, StringBuilder,
};
use arrow::datatypes::{DataType, Field, Int32Type, Schema, SchemaRef};
use parquet::arrow::arrow_reader::{
    ArrowReaderMetadata, ArrowReaderOptions, ParquetRecordBatchReaderBuilder,
};
use parquet::arrow::ArrowWriter;
use parquet::basic::{Compression, Encoding, ZstdLevel};
use parquet::file::metadata::RowGroupMetaData;
use parquet::file::properties::{EnabledStatistics, WriterProperties, WriterVersion};
use parquet::file::statistics::Statistics;
use parquet::schema::types::ColumnPath;
use rustler::{Binary, Encoder, Env, ListIterator, MapIterator, NewBinary, Term};
use std::sync::Arc;

mod atoms {
    rustler::atoms! {
        struct_key = "__struct__",
        metric_sample = "Elixir.Pulse.Record.MetricSample",
        series_id,
        timestamp_ns,
        start_timestamp_ms,
        value,
        labels,
        otlp,
        histogram,
        exemplars,
        nil,
        name_atom = "__name__",
        eq,
        neq,
        re,
        nre,
    }
}

pub struct Bounds {
    pub min_ts: i128,
    pub max_ts: i128,
    pub count: usize,
}

#[derive(Clone, Copy, Debug)]
pub enum MatcherOp {
    Eq,
    Neq,
    Re,
    Nre,
}

pub struct Matcher<'a> {
    pub name: &'a [u8],
    pub op: MatcherOp,
    pub value: &'a [u8],
}

pub struct Filter<'f> {
    pub start: Option<i128>,
    pub end: Option<i128>,
    pub matchers: Vec<Matcher<'f>>,
    pub max_samples: Option<usize>,
    /// Only rows carrying exemplars, for exemplar queries.
    pub exemplars_only: bool,
}

pub(crate) struct Row {
    pub(crate) series_id: i64,
    pub(crate) timestamp_ns: i64,
    pub(crate) start_timestamp_ms: Option<i64>,
    pub(crate) value: f64,
    pub(crate) labels: Arc<EncodedLabels>,
    pub(crate) otlp: Option<Vec<u8>>,
    pub(crate) histogram: Option<Vec<u8>>,
    pub(crate) exemplars: Option<Vec<u8>>,
}

pub(crate) struct EncodedLabels {
    pub(crate) series_hash: i64,
    pub(crate) metric_name: Vec<u8>,
    pub(crate) canonical: Vec<u8>,
    pub(crate) json: Vec<u8>,
}

impl EncodedLabels {
    /// Labels of a stored row from its canonical bytes, deriving the same
    /// name, JSON and hash the term encoder writes for that label map.
    pub(crate) fn from_canonical(canonical: &[u8]) -> Option<Self> {
        let mut pairs = Vec::new();
        parse_canonical_pairs(canonical, &mut pairs).ok()?;
        if pairs.windows(2).any(|w| w[0].0 >= w[1].0)
            || pairs.iter().any(|(n, v)| {
                simdutf8::basic::from_utf8(n).is_err() || simdutf8::basic::from_utf8(v).is_err()
            })
        {
            return None;
        }
        let metric_name = pairs
            .iter()
            .find(|(name, _)| *name == b"__name__")
            .map(|(_, value)| value.to_vec())
            .unwrap_or_default();
        Some(EncodedLabels {
            series_hash: stable_hash::stable_hash(pairs.iter().copied()) as i64,
            metric_name,
            canonical: canonical.to_vec(),
            json: labels_as_json(&pairs),
        })
    }
}

#[derive(Debug)]
pub enum EncodeError {
    BadInput,
    Writer,
    PayloadTooLarge,
}

#[derive(Debug)]
pub enum DecodeError {
    Reader,
    InvalidRegex,
    TooManySamples,
}

pub fn encode<'a>(
    env: Env<'a>,
    samples: Term<'a>,
    indexed: bool,
) -> Result<(Binary<'a>, Bounds), EncodeError> {
    metadata_size(env, samples, crate::metric_json::MAX_PAYLOAD)?;
    let len = samples.list_length().map_err(|_| EncodeError::BadInput)?;
    let items: ListIterator = samples.decode().map_err(|_| EncodeError::BadInput)?;
    let struct_key = atoms::struct_key().encode(env);
    let expected = atoms::metric_sample().encode(env);

    let mut rows: Vec<Row> = Vec::with_capacity(len);
    let mut previous_labels: Option<(Term<'a>, Arc<EncodedLabels>)> = None;
    let mut bounds = Bounds {
        min_ts: i128::MAX,
        max_ts: i128::MIN,
        count: 0,
    };

    for sample in items {
        let tag = sample
            .map_get(struct_key)
            .map_err(|_| EncodeError::BadInput)?;
        if tag.as_c_arg() != expected.as_c_arg() {
            return Err(EncodeError::BadInput);
        }
        let row = extract_row(env, sample, &mut bounds, &mut previous_labels)?;
        rows.push(row);
    }

    if bounds.count == 0 {
        bounds.min_ts = 0;
        bounds.max_ts = 0;
    }

    // (series_id, timestamp_ns) ascending so consecutive rows in the
    // same series sit next to each other on disk. Dictionary + zstd on
    // `metric_name` and `labels_canonical` and delta-binary-packed
    // `timestamp_ns` all do most of their work from this ordering.
    rows.sort_by(|a, b| {
        a.series_id
            .cmp(&b.series_id)
            .then(a.timestamp_ns.cmp(&b.timestamp_ns))
    });

    drop(previous_labels);
    let payload = write_rows(env, rows, indexed)?;
    Ok((payload, bounds))
}

/// Write rows, in their given order, as one segment. Keyed appends retain
/// the byte-stable v2 encoder; unkeyed and compaction outputs opt into
/// additive footer postings (`indexed`) under fresh keys.
pub(crate) fn write_rows<'a>(
    env: Env<'a>,
    rows: Vec<Row>,
    indexed: bool,
) -> Result<Binary<'a>, EncodeError> {
    let len = rows.len();
    let batch = build_batch(&rows).map_err(|_| EncodeError::BadInput)?;
    let group_size = row_group_size(&rows);
    let postings = if indexed {
        crate::metric_postings::build(
            rows.iter().map(|row| row.labels.canonical.as_slice()),
            group_size,
        )
    } else {
        None
    };
    let props = writer_properties(group_size, postings);
    // Arrow owns the finished columns now. Do not retain the input row
    // metadata through compression, when writer buffers are at their peak.
    drop(rows);
    let mut buf = crate::out::BinaryWriter(crate::out::BinSink::with_capacity(64 + len * 32));
    let mut writer = ArrowWriter::try_new(&mut buf, batch.schema(), Some(props))
        .map_err(|_| EncodeError::Writer)?;
    writer.write(&batch).map_err(|_| EncodeError::Writer)?;
    writer.close().map_err(|_| EncodeError::Writer)?;
    Ok(buf.0.finish(env))
}

// Bound only the additive envelope column, not existing label/scalar rows.
// Ordinary 100,000-row compactions must not acquire an ingest/result-text cap.
pub fn metadata_size<'a>(
    env: Env<'a>,
    samples: Term<'a>,
    limit: usize,
) -> Result<usize, EncodeError> {
    use crate::out::Sink;
    samples.list_length().map_err(|_| EncodeError::BadInput)?;
    let items: ListIterator = samples.decode().map_err(|_| EncodeError::BadInput)?;
    let nil = atoms::nil().encode(env);
    let enc = crate::term_json::JsonEncoder::new(env, limit);
    let mut counter = crate::out::Counter::new(limit);
    for sample in items {
        let metadata = sample.map_get(atoms::otlp()).unwrap_or(nil);
        if metadata.as_c_arg() == nil.as_c_arg() {
            continue;
        }
        if metadata.get_type() != rustler::TermType::Map {
            return Err(EncodeError::BadInput);
        }
        enc.value(&mut counter, metadata, 0)
            .map_err(|error| match error {
                crate::term_json::EncodeError::TooBig => EncodeError::PayloadTooLarge,
                _ => EncodeError::BadInput,
            })?;
    }
    Ok(counter.len())
}

fn extract_row<'a>(
    env: Env<'a>,
    sample: Term<'a>,
    bounds: &mut Bounds,
    previous_labels: &mut Option<(Term<'a>, Arc<EncodedLabels>)>,
) -> Result<Row, EncodeError> {
    let nil = atoms::nil().encode(env);

    let labels_term = sample
        .map_get(atoms::labels().encode(env))
        .map_err(|_| EncodeError::BadInput)?;

    // Compare complete maps, never series IDs. Reuse derived bytes for a
    // consecutive run even when equivalent maps are separate Erlang terms.
    // Only one lookup entry is retained; rows share immutable metadata.
    let labels = match previous_labels.as_ref() {
        Some((previous, labels)) if *previous == labels_term => Arc::clone(labels),
        _ => {
            let labels = Arc::new(encode_labels(labels_term)?);
            *previous_labels = Some((labels_term, Arc::clone(&labels)));
            labels
        }
    };

    let series_id_term = sample
        .map_get(atoms::series_id().encode(env))
        .map_err(|_| EncodeError::BadInput)?;

    // Caller may pre-fill series_id or leave it nil; recompute on nil.
    let series_id: i64 = if series_id_term.as_c_arg() == nil.as_c_arg() {
        labels.series_hash
    } else {
        series_id_term.decode().map_err(|_| EncodeError::BadInput)?
    };

    let ts_term = sample
        .map_get(atoms::timestamp_ns().encode(env))
        .map_err(|_| EncodeError::BadInput)?;
    let timestamp_ns: i64 = if ts_term.as_c_arg() == nil.as_c_arg() {
        0
    } else {
        ts_term.decode().map_err(|_| EncodeError::BadInput)?
    };
    let start_timestamp_ms: Option<i64> = sample
        .map_get(atoms::start_timestamp_ms())
        .unwrap_or(nil)
        .decode()
        .map_err(|_| EncodeError::BadInput)?;
    if start_timestamp_ms == Some(0) {
        return Err(EncodeError::BadInput);
    }

    let exemplars_term = sample.map_get(atoms::exemplars()).unwrap_or(nil);
    let exemplars = if exemplars_term.as_c_arg() == nil.as_c_arg() {
        None
    } else {
        let list: Vec<Term> = exemplars_term.decode().map_err(|_| EncodeError::BadInput)?;
        let owned = list
            .into_iter()
            .map(crate::exemplar::from_term)
            .collect::<Option<Vec<_>>>()
            .ok_or(EncodeError::BadInput)?;
        (!owned.is_empty()).then(|| crate::exemplar::to_bytes(&owned))
    };

    // Rows without a float value keep one older readers understand: a
    // histogram sample stores the stale marker, so the series ends rather than
    // showing an invented number, and a row that only carries exemplars
    // stores a reserved NaN that queries skip.
    let histogram_term = sample.map_get(atoms::histogram()).unwrap_or(nil);
    let value_term = sample
        .map_get(atoms::value().encode(env))
        .map_err(|_| EncodeError::BadInput)?;
    let (value, histogram) = if histogram_term.as_c_arg() != nil.as_c_arg() {
        let histogram = crate::native_histogram::Histogram::from_term(histogram_term)
            .ok_or(EncodeError::BadInput)?;
        (
            f64::from_bits(crate::metric_value::STALE_BITS),
            Some(histogram.to_bytes()),
        )
    } else if value_term.as_c_arg() == nil.as_c_arg() && exemplars.is_some() {
        (
            f64::from_bits(crate::metric_value::EXEMPLAR_ONLY_BITS),
            None,
        )
    } else {
        let value = crate::metric_value::decode(value_term).map_err(|_| EncodeError::BadInput)?;
        (value, None)
    };

    let metadata = sample.map_get(atoms::otlp()).unwrap_or(nil);
    let otlp = if metadata.as_c_arg() == nil.as_c_arg() {
        None
    } else {
        if metadata.get_type() != rustler::TermType::Map {
            return Err(EncodeError::BadInput);
        }
        let mut json = Vec::new();
        crate::term_json::JsonEncoder::new(env, crate::metric_json::MAX_PAYLOAD)
            .value(&mut json, metadata, 0)
            .map_err(|_| EncodeError::BadInput)?;
        Some(json)
    };
    bounds.count += 1;
    let ts = i128::from(timestamp_ns);
    if ts < bounds.min_ts {
        bounds.min_ts = ts;
    }
    if ts > bounds.max_ts {
        bounds.max_ts = ts;
    }

    Ok(Row {
        series_id,
        timestamp_ns,
        start_timestamp_ms,
        value,
        labels,
        otlp,
        histogram,
        exemplars,
    })
}

fn encode_labels<'a>(labels_term: Term<'a>) -> Result<EncodedLabels, EncodeError> {
    // Erlang binaries stay alive for this NIF call. A map guarantees unique
    // keys; only byte ordering is needed, with no owned per-label hash map.
    let iter = MapIterator::new(labels_term).ok_or(EncodeError::BadInput)?;
    let mut pairs: Vec<(&[u8], &[u8])> = Vec::new();
    for (k, v) in iter {
        let kb: Binary<'a> = k.decode().map_err(|_| EncodeError::BadInput)?;
        let vb: Binary<'a> = v.decode().map_err(|_| EncodeError::BadInput)?;
        // Canonical fields use 0xff as a separator, which cannot occur
        // in valid UTF-8. Reject invalid labels before writing a segment
        // that would be unreadable or decode into fabricated labels.
        simdutf8::basic::from_utf8(kb.as_slice()).map_err(|_| EncodeError::BadInput)?;
        simdutf8::basic::from_utf8(vb.as_slice()).map_err(|_| EncodeError::BadInput)?;
        pairs.push((kb.as_slice(), vb.as_slice()));
    }
    pairs.sort_by(|a, b| a.0.cmp(b.0));
    let metric_name = pairs
        .iter()
        .find(|(name, _)| *name == b"__name__")
        .map(|(_, value)| value.to_vec())
        .unwrap_or_default();
    Ok(EncodedLabels {
        series_hash: stable_hash::stable_hash(pairs.iter().copied()) as i64,
        metric_name,
        canonical: canonical_bytes(&pairs),
        json: labels_as_json(&pairs),
    })
}

fn canonical_bytes(pairs: &[(&[u8], &[u8])]) -> Vec<u8> {
    let mut out = Vec::with_capacity(pairs.iter().map(|(n, v)| n.len() + v.len() + 2).sum());
    for (n, v) in pairs {
        out.extend_from_slice(n);
        out.push(stable_hash::SEP);
        out.extend_from_slice(v);
        out.push(stable_hash::SEP);
    }
    out
}

pub(crate) fn labels_as_json(pairs: &[(&[u8], &[u8])]) -> Vec<u8> {
    // Minimal JSON encoder for `{"name":"value",…}` — label names and
    // values can contain anything, but Prometheus's own convention
    // restricts them to UTF-8 and names to `[A-Za-z_][A-Za-z0-9_]*`, so
    // we only need to escape `"` and `\` plus the mandatory control
    // characters. If a value is not valid UTF-8 (which Prometheus
    // forbids but a malicious client could send), we lossily replace
    // with `�` — the segment stays readable rather than failing
    // the whole batch.
    let mut out = Vec::with_capacity(pairs.iter().map(|(n, v)| n.len() + v.len() + 6).sum());
    out.push(b'{');
    for (i, (n, v)) in pairs.iter().enumerate() {
        if i > 0 {
            out.push(b',');
        }
        encode_json_string(&mut out, n);
        out.push(b':');
        encode_json_string(&mut out, v);
    }
    out.push(b'}');
    out
}

pub(crate) fn encode_json_string(out: &mut Vec<u8>, s: &[u8]) {
    out.push(b'"');
    for &b in s {
        match b {
            b'"' => out.extend_from_slice(b"\\\""),
            b'\\' => out.extend_from_slice(b"\\\\"),
            0x08 => out.extend_from_slice(b"\\b"),
            0x09 => out.extend_from_slice(b"\\t"),
            0x0a => out.extend_from_slice(b"\\n"),
            0x0c => out.extend_from_slice(b"\\f"),
            0x0d => out.extend_from_slice(b"\\r"),
            b if b < 0x20 => {
                out.extend_from_slice(b"\\u00");
                let hi = b >> 4;
                let lo = b & 0xf;
                out.push(hex_nibble(hi));
                out.push(hex_nibble(lo));
            }
            b => out.push(b),
        }
    }
    out.push(b'"');
}

fn hex_nibble(n: u8) -> u8 {
    match n {
        0..=9 => b'0' + n,
        _ => b'a' + (n - 10),
    }
}

// `histogram`, `exemplars` and `start_timestamp_ms` exist only in segments with rows that carry
// them, so segments of plain samples keep their exact earlier bytes (keyed
// retries compare bytes) and readers that predate them keep working.
fn schema(histograms: bool, exemplars: bool, starts: bool) -> SchemaRef {
    let mut fields = base_fields();
    if histograms {
        fields.push(Field::new("histogram", DataType::Binary, true));
    }
    if exemplars {
        fields.push(Field::new("exemplars", DataType::Binary, true));
    }
    if starts {
        fields.push(Field::new("start_timestamp_ms", DataType::Int64, true));
    }
    Arc::new(Schema::new(fields))
}

fn base_fields() -> Vec<Field> {
    vec![
        Field::new("series_id", DataType::Int64, false),
        Field::new("timestamp_ns", DataType::Int64, false),
        Field::new("value", DataType::Float64, false),
        Field::new("metric_name", DataType::Utf8, false),
        // `labels_canonical` is `Binary`, not `Utf8`, specifically so
        // the 0xff byte we use as the field separator — identical to
        // Prometheus's `labels.StableHash` separator in
        // `prometheus/prometheus/model/labels/labels_common.go` — can
        // appear verbatim. Writing it to a Utf8 column would force an
        // `invalid utf-8 → U+FFFD` lossy replacement on encode and
        // break the exact-bytes contract that lets decode return
        // sub-binaries of the arena without a second parse.
        Field::new("labels_canonical", DataType::Binary, false),
        Field::new("labels_json", DataType::Utf8, false),
        Field::new("otlp", DataType::Utf8, true),
    ]
}

fn build_batch(rows: &[Row]) -> Result<RecordBatch, arrow::error::ArrowError> {
    let mut series_id = Int64Builder::with_capacity(rows.len());
    let mut ts = Int64Builder::with_capacity(rows.len());
    let mut value = Float64Builder::with_capacity(rows.len());
    // The encoded label bytes already exist; reserve their total column
    // size once rather than repeatedly reallocating and copying buffers.
    let name_bytes = rows.iter().map(|row| row.labels.metric_name.len()).sum();
    let canonical_bytes = rows.iter().map(|row| row.labels.canonical.len()).sum();
    let json_bytes = rows.iter().map(|row| row.labels.json.len()).sum();
    let mut metric_name = StringBuilder::with_capacity(rows.len(), name_bytes);
    let mut labels_canonical = BinaryBuilder::with_capacity(rows.len(), canonical_bytes);
    let mut labels_json = StringBuilder::with_capacity(rows.len(), json_bytes);
    let mut otlp = StringBuilder::with_capacity(
        rows.len(),
        rows.iter()
            .filter_map(|r| r.otlp.as_ref())
            .map(Vec::len)
            .sum(),
    );

    for row in rows {
        series_id.append_value(row.series_id);
        ts.append_value(row.timestamp_ns);
        value.append_value(row.value);
        // `metric_name` and `labels_json` are UTF-8 by construction
        // (Prometheus restricts metric names, and our JSON encoder
        // escapes any sub-0x20 bytes), so the StringBuilder path is
        // the common case. `labels_canonical` is raw bytes.
        append_string(&mut metric_name, &row.labels.metric_name);
        labels_canonical.append_value(&row.labels.canonical);
        append_string(&mut labels_json, &row.labels.json);
        match &row.otlp {
            Some(json) => append_string(&mut otlp, json),
            None => otlp.append_null(),
        };
    }

    let mut columns: Vec<arrow::array::ArrayRef> = vec![
        Arc::new(series_id.finish()),
        Arc::new(ts.finish()),
        Arc::new(value.finish()),
        Arc::new(metric_name.finish()),
        Arc::new(labels_canonical.finish()),
        Arc::new(labels_json.finish()),
        Arc::new(otlp.finish()),
    ];
    let histograms = rows.iter().any(|row| row.histogram.is_some());
    let exemplars = rows.iter().any(|row| row.exemplars.is_some());
    if histograms {
        columns.push(Arc::new(optional_binary(
            rows.iter().map(|r| r.histogram.as_deref()),
        )));
    }
    if exemplars {
        columns.push(Arc::new(optional_binary(
            rows.iter().map(|r| r.exemplars.as_deref()),
        )));
    }
    let starts = rows.iter().any(|r| r.start_timestamp_ms.is_some());
    if starts {
        columns.push(Arc::new(Int64Array::from_iter(
            rows.iter().map(|r| r.start_timestamp_ms),
        )));
    }
    RecordBatch::try_new(schema(histograms, exemplars, starts), columns)
}

fn optional_binary<'r>(values: impl Iterator<Item = Option<&'r [u8]>> + Clone) -> BinaryArray {
    let bytes = values.clone().flatten().map(<[u8]>::len).sum();
    let mut builder = BinaryBuilder::with_capacity(values.clone().count(), bytes);
    for value in values {
        match value {
            Some(bytes) => builder.append_value(bytes),
            None => builder.append_null(),
        }
    }
    builder.finish()
}

fn append_string(b: &mut StringBuilder, bytes: &[u8]) {
    match std::str::from_utf8(bytes) {
        Ok(s) => b.append_value(s),
        Err(_) => {
            // Lossy: convert each malformed byte to U+FFFD so the
            // segment still writes. The alternative — failing encode —
            // would drop the whole batch for one bad label and lose
            // acknowledged data.
            b.append_value(String::from_utf8_lossy(bytes));
        }
    }
}

// A long sorted series can fill whole groups with a narrow time interval,
// making 8192-row timestamp statistics useful. Short series runs mix many
// time intervals in every group; larger groups avoid repeated dictionaries
// and footer overhead there. Hash collisions can only choose smaller groups,
// never change sample identity or filtering.
fn row_group_size(rows: &[Row]) -> usize {
    if rows.len() <= 8192 {
        return 8192;
    }
    let mut previous = None;
    let mut run = 0;
    for row in rows {
        if previous == Some(row.series_id) {
            run += 1;
        } else {
            previous = Some(row.series_id);
            run = 1;
        }
        if run >= 8192 {
            return 8192;
        }
    }
    65_536
}

fn writer_properties(max_rows: usize, postings: Option<String>) -> WriterProperties {
    let metadata = postings.map(|value| {
        vec![parquet::format::KeyValue {
            key: crate::metric_postings::KEY.to_owned(),
            value: Some(value),
        }]
    });
    let mut builder = WriterProperties::builder()
        .set_key_value_metadata(metadata)
        .set_writer_version(WriterVersion::PARQUET_2_0)
        .set_compression(Compression::ZSTD(ZstdLevel::try_new(6).unwrap()))
        .set_statistics_enabled(EnabledStatistics::Chunk)
        // The current decoder reads whole selected row groups, not row-number
        // page seeks, so offset indexes only increase object metadata.
        .set_offset_index_disabled(true)
        // Bound uncompressed label extrema in the footer, not the stored
        // labels. Truncated string bounds remain conservative for readers.
        .set_statistics_truncate_length(Some(64))
        // Bound all groups well below parquet-rs's million-row default;
        // preserve narrow groups when long series runs enable time pruning.
        .set_max_row_group_size(max_rows);

    // Delta-binary-packed on the sort key: back-to-back samples for the
    // same series differ by a scrape interval, which packs down to a few
    // bits per row.
    builder = builder.set_column_encoding(
        ColumnPath::from("timestamp_ns"),
        Encoding::DELTA_BINARY_PACKED,
    );
    // Dictionary on `metric_name` and `labels_canonical`: thousands of
    // rows share a handful of distinct values each.
    builder = builder.set_column_dictionary_enabled(ColumnPath::from("metric_name"), true);
    builder = builder.set_column_dictionary_enabled(ColumnPath::from("labels_canonical"), true);

    builder.build()
}

// Per-batch arena for a Binary column: one Erlang `NewBinary` holds
// the entire column's underlying bytes, and `sub_binary` returns
// zero-copy slices into it. For a batch of N rows we go from N
// allocations per column to one — same contract as
// `segment_parquet::StringArena`.
struct BinaryArena<'a> {
    arena: Option<Binary<'a>>,
    offsets: Vec<i32>,
}

impl<'a> BinaryArena<'a> {
    fn from(env: Env<'a>, col: &BinaryArray) -> Self {
        let bytes = col.value_data();
        let arena = if bytes.is_empty() {
            None
        } else {
            let mut nb = NewBinary::new(env, bytes.len());
            nb.as_mut_slice().copy_from_slice(bytes);
            Some(Binary::from(nb))
        };
        BinaryArena {
            arena,
            offsets: col.value_offsets().to_vec(),
        }
    }

    fn row_bounds(&self, row: usize) -> (usize, usize) {
        (self.offsets[row] as usize, self.offsets[row + 1] as usize)
    }

    fn sub_binary(&self, start: usize, len: usize) -> Result<Binary<'a>, DecodeError> {
        match &self.arena {
            Some(a) => a
                .make_subbinary(start, len)
                .map_err(|_| DecodeError::Reader),
            None => Err(DecodeError::Reader),
        }
    }

    fn arena_bytes(&self) -> Option<&[u8]> {
        self.arena.as_ref().map(|a| a.as_slice())
    }
}

// Shared by full decoding and footer-only negative proofs. Never let pruning
// turn an invalid projected schema into a successful empty result.
pub(super) fn optional_columns(schema: &Schema) -> Result<[Option<usize>; 4], DecodeError> {
    let fields = schema.fields();
    for (i, kind) in [
        (0, DataType::Int64),
        (1, DataType::Int64),
        (2, DataType::Float64),
        (4, DataType::Binary),
    ] {
        if fields.get(i).is_none_or(|field| field.data_type() != &kind) {
            return Err(DecodeError::Reader);
        }
    }
    let mut columns = [None; 4];
    for (slot, (name, kind)) in [
        ("otlp", DataType::Utf8),
        ("histogram", DataType::Binary),
        ("exemplars", DataType::Binary),
        ("start_timestamp_ms", DataType::Int64),
    ]
    .into_iter()
    .enumerate()
    {
        for (i, field) in fields
            .iter()
            .enumerate()
            .filter(|(_, field)| field.name() == name)
        {
            if columns[slot].is_some() || field.data_type() != &kind {
                return Err(DecodeError::Reader);
            }
            columns[slot] = Some(i);
        }
    }
    Ok(columns)
}

pub fn decode<'a>(
    env: Env<'a>,
    blob: &Binary<'a>,
    filter: &Filter<'_>,
) -> Result<Term<'a>, DecodeError> {
    let regex_cache = compile_regexes(&filter.matchers)?;
    let bytes = crate::erlang_bytes::from_binary(*blob);

    // Preserve the label dictionary instead of expanding identical bytes
    // for every sample. Plain/fallback pages remain supported: parquet-rs
    // builds an Arrow dictionary for them. Keep all other inferred fields
    // and metadata unchanged, including legacy fixture schemas.
    let metadata = ArrowReaderMetadata::load(&bytes, ArrowReaderOptions::default())
        .map_err(|_| DecodeError::Reader)?;
    let [otlp_column, histogram_column, exemplars_column, start_column] =
        optional_columns(metadata.schema())?;
    let mut fields = metadata.schema().fields().to_vec();
    let labels_field = fields.get(4).ok_or(DecodeError::Reader)?;
    if labels_field.data_type() != &DataType::Binary {
        return Err(DecodeError::Reader);
    }
    fields[4] = Arc::new(
        labels_field
            .as_ref()
            .clone()
            .with_data_type(DataType::Dictionary(
                Box::new(DataType::Int32),
                Box::new(DataType::Binary),
            )),
    );
    let read_schema = Arc::new(Schema::new_with_metadata(
        fields,
        metadata.schema().metadata().clone(),
    ));
    let read_metadata = ArrowReaderMetadata::try_new(
        Arc::clone(metadata.metadata()),
        ArrowReaderOptions::new().with_schema(read_schema),
    )
    .map_err(|_| DecodeError::Reader)?;
    let builder = ParquetRecordBatchReaderBuilder::new_with_metadata(bytes, read_metadata);

    // Column projection: only the four columns the decoder actually
    // reads. `metric_name` and `labels_json` stay in the file but are
    // never materialised, decompressed, or allocated into Arrow
    // buffers. After the mask is applied the returned batch has
    // these four columns in projection order:
    //
    //     0 → series_id
    //     1 → timestamp_ns
    //     2 → value
    //     3 → labels_canonical
    //
    // `metric_name` sits between `value` and `labels_canonical` in the
    // on-disk schema (position 3), so dropping it renumbers the two
    // columns after it; the indices below reflect the post-projection
    // order and must stay in sync with the mask.
    // Optional columns follow, in on-disk order, from projected index 4.
    let mut projected = vec![0usize, 1, 2, 4];
    let mut place = |column: Option<usize>| {
        column.map(|column| {
            projected.push(column);
            projected.len() - 1
        })
    };
    let otlp_index = place(otlp_column);
    let histogram_index = place(histogram_column);
    let exemplars_index = place(exemplars_column);
    let start_index = place(start_column);
    let projection = parquet::arrow::ProjectionMask::leaves(builder.parquet_schema(), projected);

    // Row-group pruning: when a time filter is set, consult each row
    // group's `timestamp_ns` min/max chunk stats and only read the
    // groups that could contain surviving rows. The segment writer
    // caps groups at 8192 rows for long series runs and 65536 otherwise,
    // so a tight filter can skip irrelevant groups without opening any
    // column pages.
    let metadata = builder.metadata().clone();
    let surviving = surviving_row_groups(&metadata, filter);

    if surviving.is_empty() {
        return Ok(Vec::<Term<'a>>::new().encode(env));
    }

    let reader = builder
        .with_projection(projection)
        .with_row_groups(surviving)
        .build()
        .map_err(|_| DecodeError::Reader)?;

    let mut records: Vec<Term<'a>> = Vec::new();

    let keys = [
        atoms::struct_key().encode(env),
        atoms::series_id().encode(env),
        atoms::timestamp_ns().encode(env),
        atoms::value().encode(env),
        atoms::labels().encode(env),
        atoms::otlp().encode(env),
        atoms::histogram().encode(env),
        atoms::exemplars().encode(env),
        atoms::start_timestamp_ms().encode(env),
    ];
    let struct_name = atoms::metric_sample().encode(env);
    // Arrow reconstructs array wrappers across batches, but dictionary
    // value/offset buffers remain shared. Retain the previous array owner
    // so buffer identities cannot be recycled while comparing them.
    let mut previous_arena: Option<(arrow::array::ArrayRef, BinaryArena<'a>)> = None;

    for batch_result in reader {
        let batch = batch_result.map_err(|_| DecodeError::Reader)?;
        let series_id_arr = col::<Int64Array>(&batch, 0)?;
        let ts_arr = col::<Int64Array>(&batch, 1)?;
        let value_arr = col::<Float64Array>(&batch, 2)?;
        let otlp_arr = otlp_index
            .map(|i| col::<StringArray>(&batch, i))
            .transpose()?;
        let histogram_arr = histogram_index
            .map(|i| col::<BinaryArray>(&batch, i))
            .transpose()?;
        let exemplars_arr = exemplars_index
            .map(|i| col::<BinaryArray>(&batch, i))
            .transpose()?;
        let start_arr = start_index
            .map(|i| col::<Int64Array>(&batch, i))
            .transpose()?;
        let otlp_arena =
            otlp_arr.map(|array| crate::segment_parquet::StringArena::from(env, array));
        let mut stacks = crate::json_read::Stacks::new();
        let mut interned_keys = Vec::new();
        // Post-projection column 3 is `labels_canonical` (`metric_name`
        // and `labels_json` were masked out). `labels_canonical` carries
        // the raw `name<0xff>value<0xff>...` bytes we hashed into
        // `series_id`, so every label slice is returned as a sub-binary
        // of the arena without a per-row JSON parse.
        let labels_dict = col::<DictionaryArray<Int32Type>>(&batch, 3)?;
        let labels_arr = labels_dict
            .values()
            .as_any()
            .downcast_ref::<BinaryArray>()
            .ok_or(DecodeError::Reader)?;
        let same_dictionary = previous_arena.as_ref().is_some_and(|(values, _)| {
            values
                .as_any()
                .downcast_ref::<BinaryArray>()
                .is_some_and(|previous| {
                    previous.value_data().as_ptr() == labels_arr.value_data().as_ptr()
                        && previous.value_data().len() == labels_arr.value_data().len()
                        && previous.value_offsets().as_ptr() == labels_arr.value_offsets().as_ptr()
                        && previous.value_offsets().len() == labels_arr.value_offsets().len()
                })
        });
        if !same_dictionary {
            previous_arena = Some((
                Arc::clone(labels_dict.values()),
                BinaryArena::from(env, labels_arr),
            ));
        }
        let labels_arena = &previous_arena.as_ref().ok_or(DecodeError::Reader)?.1;
        // The whole-column byte view — the per-row canonical slices we
        // scan during the row loop point into this slice.
        let labels_bytes: &[u8] = labels_arena.arena_bytes().unwrap_or(&[]);
        let base = labels_bytes.as_ptr() as usize;

        // Scratch buffers reused across rows within the batch to avoid
        // per-row Vec allocs. Scope is per-batch so the slice lifetimes
        // in `label_pairs` do not escape `labels_bytes`'s borrow.
        // Prometheus series rarely exceed a dozen labels, so 16 is a
        // comfortable upper bound to avoid reallocation.
        let mut name_terms: Vec<Term<'a>> = Vec::with_capacity(16);
        let mut value_terms: Vec<Term<'a>> = Vec::with_capacity(16);
        let mut label_pairs: Vec<(&[u8], &[u8])> = Vec::with_capacity(16);
        // Cache just the previous canonical label set, not the series hash:
        // hashes may collide and callers may supply their own series IDs.
        // Runs of samples from one series share both matcher work and the
        // immutable Erlang labels map. The cache is bounded to one entry.
        let mut previous_labels: Option<&[u8]> = None;
        let mut previous_matches = false;
        let mut previous_term: Option<Term<'a>> = None;
        // Updating a fixed-key flat map shares its key tuple, unlike
        // constructing one from arrays for every row. Compare exact terms
        // so unchanged fields (and duplicate samples) require no update.
        let mut previous_record: Option<(Term<'a>, [Term<'a>; 9])> = None;
        let mut previous_raw = None;

        for row in 0..batch.num_rows() {
            let ts = ts_arr.value(row) as i128;
            if let Some(start) = filter.start {
                if ts < start {
                    continue;
                }
            }
            if let Some(end) = filter.end {
                if ts > end {
                    continue;
                }
            }
            if filter.exemplars_only && present(exemplars_arr, row).is_none() {
                continue;
            }

            let label_index = labels_dict.key(row).ok_or(DecodeError::Reader)?;
            let (row_start, row_end) = labels_arena.row_bounds(label_index);

            let row_bytes = &labels_bytes[row_start..row_end];
            if previous_labels != Some(row_bytes) {
                label_pairs.clear();
                parse_canonical_pairs(row_bytes, &mut label_pairs)
                    .map_err(|_| DecodeError::Reader)?;
                previous_labels = Some(row_bytes);
                previous_matches = labels_match(&label_pairs, &filter.matchers, &regex_cache);
                previous_term = None;
            }

            if !previous_matches {
                continue;
            }

            if filter.max_samples.is_some_and(|max| records.len() >= max) {
                return Err(DecodeError::TooManySamples);
            }
            let series_id = series_id_arr.value(row);
            let value = value_arr.value(row);

            // Rebuild label terms as sub-binaries of the arena. The
            // slice pointer arithmetic recovers each slice's absolute
            // offset inside the arena so the sub-binary points at the
            // right bytes — no second copy.
            let labels_term = match previous_term {
                Some(term) => term,
                None => {
                    name_terms.clear();
                    value_terms.clear();
                    for (name, value) in &label_pairs {
                        let name_off = (name.as_ptr() as usize) - base;
                        let value_off = (value.as_ptr() as usize) - base;
                        name_terms.push(labels_arena.sub_binary(name_off, name.len())?.encode(env));
                        value_terms
                            .push(labels_arena.sub_binary(value_off, value.len())?.encode(env));
                    }
                    let term = Term::map_from_arrays(env, &name_terms, &value_terms)
                        .map_err(|_| DecodeError::Reader)?;
                    previous_term = Some(term);
                    term
                }
            };

            let nil = atoms::nil().encode(env);
            let metadata = match &otlp_arena {
                Some(arena) => crate::segment_parquet::json_term(
                    env,
                    arena,
                    row,
                    nil,
                    &mut stacks,
                    &mut interned_keys,
                )
                .map_err(|_| DecodeError::Reader)?,
                None => nil,
            };
            if otlp_arr.is_some_and(|array| !array.is_null(row))
                && metadata.get_type() != rustler::TermType::Map
            {
                return Err(DecodeError::Reader);
            }
            let histogram_bytes = present(histogram_arr, row);
            let exemplar_bytes = present(exemplars_arr, row);
            let start = start_arr
                .filter(|array| !array.is_null(row))
                .map(|array| array.value(row));
            if start == Some(0) {
                return Err(DecodeError::Reader);
            }
            let raw = (
                series_id,
                ts_arr.value(row),
                value.to_bits(),
                row_bytes,
                otlp_arr.and_then(|array| {
                    if array.is_null(row) {
                        None
                    } else {
                        Some(array.value(row))
                    }
                }),
                histogram_bytes,
                exemplar_bytes,
                start,
            );
            // A histogram row's float value is the stale marker kept for
            // older readers; its sample value is the histogram. A row that only
            // carries exemplars has no value.
            let exemplar_only = exemplar_bytes.is_some()
                && value.to_bits() == crate::metric_value::EXEMPLAR_ONLY_BITS;
            let (value_term, histogram_term) = match histogram_bytes {
                Some(bytes) => (
                    nil,
                    crate::native_histogram::Histogram::from_bytes(bytes)
                        .ok_or(DecodeError::Reader)?
                        .to_term(env),
                ),
                None if exemplar_only => (nil, nil),
                None => (crate::metric_value::encode(env, value), nil),
            };
            let exemplars_term = match exemplar_bytes {
                Some(bytes) => crate::exemplar::from_bytes(bytes)
                    .ok_or(DecodeError::Reader)?
                    .iter()
                    .map(|(labels, value, ts)| crate::exemplar::to_term(env, labels, *value, *ts))
                    .collect::<Vec<_>>()
                    .encode(env),
                None => nil,
            };
            let fields = [
                struct_name,
                series_id.encode(env),
                ts_arr.value(row).encode(env),
                value_term,
                labels_term,
                metadata,
                histogram_term,
                exemplars_term,
                start.encode(env),
            ];
            let record = match previous_record {
                Some((record, _)) if previous_raw == Some(raw) => record,
                Some((mut record, previous_fields)) => {
                    for ((key, field), previous) in
                        keys.iter().zip(fields.iter()).zip(previous_fields.iter())
                    {
                        if field.as_c_arg() != previous.as_c_arg() {
                            record = record
                                .map_update(*key, *field)
                                .map_err(|_| DecodeError::Reader)?;
                        }
                    }
                    record
                }
                None => {
                    Term::map_from_arrays(env, &keys, &fields).map_err(|_| DecodeError::Reader)?
                }
            };
            previous_record = Some((record, fields));
            previous_raw = Some(raw);
            records.push(record);
        }
    }

    Ok(records.encode(env))
}

pub(super) fn surviving_row_groups(
    metadata: &parquet::file::metadata::ParquetMetaData,
    filter: &Filter<'_>,
) -> Vec<usize> {
    let ts_col = metadata
        .file_metadata()
        .schema_descr()
        .columns()
        .iter()
        .position(|column| column.name() == "timestamp_ns");
    let time_filter = filter.start.is_some() || filter.end.is_some();
    let postings = crate::metric_postings::candidate_groups(metadata, &filter.matchers);
    (0..metadata.num_row_groups())
        .filter(|&i| {
            postings.as_ref().is_none_or(|groups| groups[i])
                && (!time_filter || row_group_matches_time(metadata.row_group(i), ts_col, filter))
        })
        .collect()
}

// Split a row's canonical bytes (`name<0xff>value<0xff>...`) into
// borrowed `(name, value)` pairs. Returns `Err(())` on a stray trailing
// byte or a missing separator — a well-formed segment never produces
// either.
pub(crate) fn parse_canonical_pairs<'r>(
    bytes: &'r [u8],
    out: &mut Vec<(&'r [u8], &'r [u8])>,
) -> Result<(), ()> {
    let mut i = 0;
    while i < bytes.len() {
        let name_start = i;
        let name_end = memchr::memchr(crate::stable_hash::SEP, &bytes[i..]).ok_or(())? + i;
        let value_start = name_end + 1;
        if value_start > bytes.len() {
            return Err(());
        }
        let value_end =
            memchr::memchr(crate::stable_hash::SEP, &bytes[value_start..]).ok_or(())? + value_start;
        out.push((&bytes[name_start..name_end], &bytes[value_start..value_end]));
        i = value_end + 1;
    }
    Ok(())
}

fn present(array: Option<&BinaryArray>, row: usize) -> Option<&[u8]> {
    array.and_then(|a| (!a.is_null(row)).then(|| a.value(row)))
}

fn col<T: 'static>(batch: &RecordBatch, idx: usize) -> Result<&T, DecodeError> {
    batch
        .column(idx)
        .as_any()
        .downcast_ref::<T>()
        .ok_or(DecodeError::Reader)
}

/// True when the row group's `timestamp_ns` column stats overlap the
/// filter range, so the group might contain matching records. Missing
/// stats, or non-integer stats (shouldn't happen for an Int64 column
/// written by our own writer), mean we don't know — err on the side
/// of scanning. Mirrors `segment_parquet::row_group_matches_time`.
fn row_group_matches_time(
    rg: &RowGroupMetaData,
    ts_col: Option<usize>,
    filter: &Filter<'_>,
) -> bool {
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

pub fn compile_metric_regex(pattern: &str) -> Result<regex::Regex, regex::Error> {
    crate::query_regex::string(pattern)
}

pub(super) fn compile_regexes(
    matchers: &[Matcher<'_>],
) -> Result<Vec<Option<regex::Regex>>, DecodeError> {
    matchers
        .iter()
        .map(|m| match m.op {
            MatcherOp::Re | MatcherOp::Nre => {
                let pattern =
                    std::str::from_utf8(m.value).map_err(|_| DecodeError::InvalidRegex)?;
                compile_metric_regex(pattern)
                    .map(Some)
                    .map_err(|_| DecodeError::InvalidRegex)
            }
            _ => Ok(None),
        })
        .collect()
}

#[cfg(test)]
pub(super) fn matches_canonical_for_test(bytes: &[u8], matchers: &[Matcher<'_>]) -> bool {
    let mut labels = Vec::new();
    parse_canonical_pairs(bytes, &mut labels).unwrap();
    let regex_cache = compile_regexes(matchers).unwrap();
    labels_match(&labels, matchers, &regex_cache)
}

pub(crate) fn labels_match(
    labels: &[(&[u8], &[u8])],
    matchers: &[Matcher<'_>],
    regex_cache: &[Option<regex::Regex>],
) -> bool {
    for (m, re) in matchers.iter().zip(regex_cache.iter()) {
        let got: Option<&[u8]> = labels.iter().find(|(k, _)| *k == m.name).map(|(_, v)| *v);

        let ok = match m.op {
            MatcherOp::Eq => got.map(|v| v == m.value).unwrap_or(m.value.is_empty()),
            MatcherOp::Neq => got.map(|v| v != m.value).unwrap_or(!m.value.is_empty()),
            MatcherOp::Re | MatcherOp::Nre => {
                let Some(re) = re else {
                    return false;
                };
                let actual = std::str::from_utf8(got.unwrap_or(b""));
                let matched = actual.map(|value| re.is_match(value)).unwrap_or(false);
                if matches!(m.op, MatcherOp::Re) {
                    matched
                } else {
                    !matched
                }
            }
        };

        if !ok {
            return false;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use bytes::Bytes;

    fn row(series_id: i64, timestamp_ns: i64) -> Row {
        Row {
            series_id,
            timestamp_ns,
            start_timestamp_ms: None,
            value: 1.0,
            otlp: None,
            histogram: None,
            exemplars: None,
            labels: Arc::new(EncodedLabels {
                series_hash: stable_hash::stable_hash([(b"host".as_slice(), b"node".as_slice())])
                    as i64,
                metric_name: b"work".to_vec(),
                canonical: b"host\xffnode\xff".to_vec(),
                json: b"{\"host\":\"node\"}".to_vec(),
            }),
        }
    }

    fn parquet_rows(rows: &[Row], postings: Option<String>, duplicate: bool) -> Bytes {
        let batch = build_batch(rows).unwrap();
        let duplicate_value = postings.clone();
        let props = writer_properties(8192, postings);
        let mut buf = Vec::new();
        let mut writer = ArrowWriter::try_new(&mut buf, batch.schema(), Some(props)).unwrap();
        if duplicate {
            writer.append_key_value_metadata(parquet::format::KeyValue {
                key: crate::metric_postings::KEY.to_owned(),
                value: duplicate_value,
            });
        }
        writer.write(&batch).unwrap();
        writer.close().unwrap();
        Bytes::from(buf)
    }

    #[test]
    fn native_postings_select_groups_before_arrow_and_combine_with_time_statistics() {
        // Deliberately identical hashes across different canonical identities.
        let rows: Vec<_> = (0..24_576)
            .map(|i| {
                let mut row = row(1, i);
                if (8192..16384).contains(&i) {
                    row.labels = Arc::new(EncodedLabels {
                        series_hash: 1,
                        metric_name: vec![],
                        canonical: b"env\xffdev\xffhost\xffother\xff".to_vec(),
                        json: b"{}".to_vec(),
                    });
                } else {
                    row.labels = Arc::new(EncodedLabels {
                        series_hash: 1,
                        metric_name: vec![],
                        canonical: b"env\xffprod\xffhost\xffnode\xff".to_vec(),
                        json: b"{}".to_vec(),
                    });
                }
                row
            })
            .collect();
        let postings = crate::metric_postings::build(
            rows.iter().map(|row| row.labels.canonical.as_slice()),
            8192,
        )
        .unwrap();
        let bytes = parquet_rows(&rows, Some(postings.clone()), false);
        let builder = ParquetRecordBatchReaderBuilder::try_new(bytes.clone()).unwrap();
        let mut filter = Filter {
            start: None,
            end: None,
            matchers: vec![Matcher {
                name: b"host",
                op: MatcherOp::Eq,
                value: b"node",
            }],
            max_samples: None,
            exemplars_only: false,
        };
        assert_eq!(
            surviving_row_groups(builder.metadata(), &filter),
            vec![0, 2]
        );
        let selected = surviving_row_groups(builder.metadata(), &filter);
        let decoded_rows: usize = builder
            .with_row_groups(selected)
            .build()
            .unwrap()
            .map(|batch| batch.unwrap().num_rows())
            .sum();
        assert_eq!(decoded_rows, 16_384); // not 24,576 Arrow rows followed by filtering
        filter.start = Some(8192);
        filter.end = Some(16383);
        let builder = ParquetRecordBatchReaderBuilder::try_new(bytes).unwrap();
        assert!(surviving_row_groups(builder.metadata(), &filter).is_empty());
        filter.start = None;
        filter.end = None;
        filter.matchers.push(Matcher {
            name: b"env",
            op: MatcherOp::Eq,
            value: b"dev",
        });
        assert!(surviving_row_groups(builder.metadata(), &filter).is_empty());

        // A complete index is optional. Missing, malformed, duplicate and
        // geometrically inconsistent metadata never prove exclusion.
        let wrong_geometry = crate::metric_postings::build(
            rows.iter().map(|row| row.labels.canonical.as_slice()),
            8193,
        )
        .unwrap();
        for (postings, duplicate) in [
            (None, false),
            (Some("bad".to_owned()), false),
            (Some(postings.clone()), true),
            (Some(wrong_geometry), false),
        ] {
            let bytes = parquet_rows(&rows, postings, duplicate);
            let builder = ParquetRecordBatchReaderBuilder::try_new(bytes).unwrap();
            assert_eq!(
                surviving_row_groups(builder.metadata(), &filter),
                vec![0, 1, 2]
            );
        }
    }

    #[test]
    fn grouping_retains_time_pruning_for_long_series_and_batches_small_inputs() {
        let small: Vec<_> = (0..100).map(|i| row(i, i)).collect();
        assert_eq!(row_group_size(&small), 8192);
        let short_runs: Vec<_> = (0..20_000).map(|i| row(i / 10, i)).collect();
        assert_eq!(row_group_size(&short_runs), 65_536);
        let long_run: Vec<_> = (0..20_000).map(|i| row(1, i)).collect();
        assert_eq!(row_group_size(&long_run), 8192);

        for rows in [short_runs, long_run] {
            let batch = build_batch(&rows).unwrap();
            let mut buf = Vec::new();
            let props = writer_properties(row_group_size(&rows), None);
            let mut writer = ArrowWriter::try_new(&mut buf, batch.schema(), Some(props)).unwrap();
            writer.write(&batch).unwrap();
            writer.close().unwrap();
            let builder = ParquetRecordBatchReaderBuilder::try_new(Bytes::from(buf)).unwrap();
            assert_eq!(builder.metadata().file_metadata().num_rows(), 20_000);
            let expected = if rows[0].series_id == rows.last().unwrap().series_id {
                3
            } else {
                1
            };
            assert_eq!(builder.metadata().num_row_groups(), expected);
        }
    }
}
