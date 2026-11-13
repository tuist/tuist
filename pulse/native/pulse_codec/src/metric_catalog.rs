//! Hourly metric series catalogs.
//!
//! A catalog lists the distinct series of one UTC hour, plus the label
//! dictionaries discovery answers most requests from, so label and series
//! discovery reads objects sized by series count instead of every sample.
//! Each catalog also names the sample segments whose rows it covers.
//!
//! One Parquet object has four sections, ordered by `kind`, then `name`,
//! then `value`, each in its own row groups:
//!
//! | kind | `name`       | `value`              |
//! |------|--------------|----------------------|
//! | 0    | label name   | empty                |
//! | 1    | label name   | label value          |
//! | 2    | metric name  | label name           |
//! | 3    | metric name  | canonical label set  |
//!
//! Empty-valued labels are absent from sections 0 to 2, as discovery
//! projects them. Statistics on `kind` and `name` are untruncated, so readers
//! can skip row groups of other sections and metric names. Like rollups, the
//! object starts with a string column, so metric segment readers that predate
//! catalogs reject it rather than misread it.

use crate::metric_segment_parquet as mp;
use arrow::array::{
    Array, BinaryArray, BinaryBuilder, DictionaryArray, Int64Array, Int8Array, RecordBatch,
    StringArray, StringBuilder,
};
use arrow::datatypes::{DataType, Field, Int32Type, Schema};
use bytes::Bytes;
use parquet::arrow::arrow_reader::{
    ArrowReaderMetadata, ArrowReaderOptions, ParquetRecordBatchReaderBuilder,
};
use parquet::arrow::{ArrowWriter, ProjectionMask};
use parquet::basic::{Compression, ZstdLevel};
use parquet::file::metadata::{KeyValue, RowGroupMetaData};
use parquet::file::properties::{EnabledStatistics, WriterProperties, WriterVersion};
use parquet::file::statistics::Statistics;
use rustler::{Binary, Encoder, Env, ResourceArc, Term};
use std::collections::{BTreeSet, HashSet};
use std::sync::Arc;

pub const NAMES: i8 = 0;
pub const VALUES: i8 = 1;
pub const METRIC_LABELS: i8 = 2;
pub const SERIES: i8 = 3;

const VERSION_KEY: &str = "pulse.metric.catalog";
const VERSION: &str = "1";
const COVERS_KEY: &str = "pulse.metric.catalog.covers";
const GROUP_ROWS: usize = 8192;
const MAX_SERIES: usize = 4_000_000;

#[derive(Debug)]
pub enum CatalogError {
    Invalid,
    TooLarge,
    Encode,
}

fn schema() -> Arc<Schema> {
    Arc::new(Schema::new(vec![
        Field::new("name", DataType::Utf8, false),
        Field::new("kind", DataType::Int8, false),
        Field::new("value", DataType::Binary, false),
    ]))
}

/// Validated `(name, value)` pairs of a stored canonical label set: nonempty
/// UTF-8 names in strictly ascending order and UTF-8 values.
type Pairs<'a> = Vec<(&'a [u8], &'a [u8])>;

fn pairs(canonical: &[u8]) -> Result<Pairs<'_>, CatalogError> {
    let mut pairs = Vec::new();
    mp::parse_canonical_pairs(canonical, &mut pairs).map_err(|_| CatalogError::Invalid)?;
    for (i, (name, value)) in pairs.iter().enumerate() {
        if name.is_empty()
            || std::str::from_utf8(name).is_err()
            || std::str::from_utf8(value).is_err()
            || (i > 0 && pairs[i - 1].0 >= *name)
        {
            return Err(CatalogError::Invalid);
        }
    }
    Ok(pairs)
}

fn metric_name<'a>(pairs: &[(&'a [u8], &'a [u8])]) -> &'a [u8] {
    pairs
        .iter()
        .find(|(name, _)| *name == b"__name__")
        .map_or(&b""[..], |(_, value)| *value)
}

/// The series of samples in `[start, end)` that `known` catalogs do not
/// already list, plus every series of merged catalogs.
pub struct Builder {
    start: i64,
    end: i64,
    known: HashSet<Box<[u8]>>,
    series: HashSet<Box<[u8]>>,
}

impl Builder {
    pub fn new(start: i64, end: i64) -> Self {
        Builder {
            start,
            end,
            known: HashSet::new(),
            series: HashSet::new(),
        }
    }

    fn insert(&mut self, canonical: &[u8], known: bool) -> Result<(), CatalogError> {
        if self.known.contains(canonical) || self.series.contains(canonical) {
            return Ok(());
        }
        if self.known.len() + self.series.len() >= MAX_SERIES {
            return Err(CatalogError::TooLarge);
        }
        pairs(canonical)?;
        let target = if known {
            &mut self.known
        } else {
            &mut self.series
        };
        target.insert(canonical.into());
        Ok(())
    }

    /// Read a catalog's series: as `known` ones a delta leaves out, or as
    /// series of a merged catalog. Returns the rows read.
    pub fn add_catalog(&mut self, bytes: Bytes, known: bool) -> Result<usize, CatalogError> {
        let catalog = Catalog::open(bytes)?;
        let (groups, rows) = catalog.groups(SERIES, None);
        catalog.read(groups, SERIES, |_, canonical| self.insert(canonical, known))?;
        Ok(rows)
    }

    /// Add the series of one metric segment's rows inside the hour.
    pub fn add_segment(&mut self, bytes: Bytes) -> Result<usize, CatalogError> {
        let builder = ParquetRecordBatchReaderBuilder::try_new(bytes.clone())
            .map_err(|_| CatalogError::Invalid)?;
        let schema = builder.schema();
        let ts = schema
            .index_of("timestamp_ns")
            .map_err(|_| CatalogError::Invalid)?;
        let labels = schema
            .index_of("labels_canonical")
            .map_err(|_| CatalogError::Invalid)?;
        if schema.field(ts).data_type() != &DataType::Int64
            || schema.field(labels).data_type() != &DataType::Binary
        {
            return Err(CatalogError::Invalid);
        }
        // Repeated samples share dictionary keys, so each batch looks up a
        // series' bytes once.
        let mut fields = schema.fields().to_vec();
        fields[labels] = Arc::new(fields[labels].as_ref().clone().with_data_type(
            DataType::Dictionary(Box::new(DataType::Int32), Box::new(DataType::Binary)),
        ));
        let read_schema = Arc::new(Schema::new_with_metadata(fields, schema.metadata().clone()));
        let metadata = ArrowReaderMetadata::try_new(
            Arc::clone(builder.metadata()),
            ArrowReaderOptions::new().with_schema(read_schema),
        )
        .map_err(|_| CatalogError::Invalid)?;
        let builder = ParquetRecordBatchReaderBuilder::new_with_metadata(bytes, metadata);
        let projection = ProjectionMask::roots(builder.parquet_schema(), [ts, labels]);
        let (ts, labels) = if ts < labels { (0, 1) } else { (1, 0) };
        let reader = builder
            .with_projection(projection)
            .with_batch_size(1024)
            .build()
            .map_err(|_| CatalogError::Invalid)?;
        let mut rows = 0;
        for batch in reader {
            let batch = batch.map_err(|_| CatalogError::Invalid)?;
            rows += batch.num_rows();
            let times = batch
                .column(ts)
                .as_any()
                .downcast_ref::<Int64Array>()
                .ok_or(CatalogError::Invalid)?;
            let keys = batch
                .column(labels)
                .as_any()
                .downcast_ref::<DictionaryArray<Int32Type>>()
                .ok_or(CatalogError::Invalid)?;
            let values = keys
                .values()
                .as_any()
                .downcast_ref::<BinaryArray>()
                .ok_or(CatalogError::Invalid)?;
            let mut seen = HashSet::new();
            for row in 0..batch.num_rows() {
                if times.is_null(row) || keys.is_null(row) {
                    return Err(CatalogError::Invalid);
                }
                let time = times.value(row);
                if time < self.start || time >= self.end {
                    continue;
                }
                let key = keys.key(row).ok_or(CatalogError::Invalid)?;
                if seen.insert(key) {
                    self.insert(values.value(key), false)?;
                }
            }
        }
        Ok(rows)
    }

    pub fn series(&self) -> usize {
        self.series.len()
    }

    /// Encode the added series and their label sections, naming `covers`.
    pub fn encode<W: std::io::Write + Send>(
        &self,
        out: W,
        covers: &str,
    ) -> Result<(), CatalogError> {
        let mut names = BTreeSet::new();
        let mut values = BTreeSet::new();
        let mut metric_labels = BTreeSet::new();
        let mut series = Vec::with_capacity(self.series.len());
        for canonical in &self.series {
            let pairs = pairs(canonical)?;
            let metric = metric_name(&pairs);
            for (name, value) in &pairs {
                if !value.is_empty() {
                    names.insert(*name);
                    values.insert((*name, *value));
                    metric_labels.insert((metric, *name));
                }
            }
            series.push((metric, &canonical[..]));
        }
        series.sort_unstable();
        let props = WriterProperties::builder()
            .set_writer_version(WriterVersion::PARQUET_2_0)
            .set_compression(Compression::ZSTD(ZstdLevel::try_new(3).unwrap()))
            .set_statistics_enabled(EnabledStatistics::Chunk)
            .set_statistics_truncate_length(None)
            .set_offset_index_disabled(true)
            .set_max_row_group_size(GROUP_ROWS)
            .set_key_value_metadata(Some(vec![
                KeyValue::new(VERSION_KEY.to_owned(), VERSION.to_owned()),
                KeyValue::new(COVERS_KEY.to_owned(), covers.to_owned()),
            ]))
            .build();
        let mut writer =
            ArrowWriter::try_new(out, schema(), Some(props)).map_err(|_| CatalogError::Encode)?;
        let names: Vec<(&[u8], &[u8])> = names.into_iter().map(|n| (n, &b""[..])).collect();
        let values: Vec<(&[u8], &[u8])> = values.into_iter().collect();
        let metric_labels: Vec<(&[u8], &[u8])> = metric_labels.into_iter().collect();
        for (kind, rows) in [
            (NAMES, &names),
            (VALUES, &values),
            (METRIC_LABELS, &metric_labels),
            (SERIES, &series),
        ] {
            for chunk in rows.chunks(GROUP_ROWS) {
                writer
                    .write(&section_batch(kind, chunk)?)
                    .map_err(|_| CatalogError::Encode)?;
            }
            // Row groups never mix sections.
            writer.flush().map_err(|_| CatalogError::Encode)?;
        }
        writer.close().map_err(|_| CatalogError::Encode)?;
        Ok(())
    }
}

fn section_batch(kind: i8, rows: &[(&[u8], &[u8])]) -> Result<RecordBatch, CatalogError> {
    let mut names = StringBuilder::new();
    let mut values = BinaryBuilder::new();
    for (name, value) in rows {
        names.append_value(std::str::from_utf8(name).map_err(|_| CatalogError::Invalid)?);
        values.append_value(value);
    }
    RecordBatch::try_new(
        schema(),
        vec![
            Arc::new(names.finish()),
            Arc::new(Int8Array::from(vec![kind; rows.len()])),
            Arc::new(values.finish()),
        ],
    )
    .map_err(|_| CatalogError::Encode)
}

/// A parsed catalog object.
pub struct Catalog {
    bytes: Bytes,
    metadata: ArrowReaderMetadata,
    covers: String,
}

impl Catalog {
    pub fn open(bytes: Bytes) -> Result<Self, CatalogError> {
        let metadata = ArrowReaderMetadata::load(&bytes, ArrowReaderOptions::default())
            .map_err(|_| CatalogError::Invalid)?;
        let value = |key: &str| {
            metadata
                .metadata()
                .file_metadata()
                .key_value_metadata()
                .and_then(|kv| kv.iter().find(|entry| entry.key == key))
                .and_then(|entry| entry.value.clone())
        };
        // File key-values also appear as schema metadata; compare columns.
        if value(VERSION_KEY).as_deref() != Some(VERSION)
            || metadata.schema().fields() != schema().fields()
        {
            return Err(CatalogError::Invalid);
        }
        let covers = value(COVERS_KEY).unwrap_or_default();
        Ok(Catalog {
            bytes,
            metadata,
            covers,
        })
    }

    /// Newline-separated keys of the segments this catalog covers.
    pub fn covers(&self) -> &str {
        &self.covers
    }

    /// Row groups that can hold `kind` rows named one of `names`, and their
    /// row count. Groups without exact statistics are always kept.
    pub fn groups(&self, kind: i8, names: Option<&[Vec<u8>]>) -> (Vec<usize>, usize) {
        let mut groups = Vec::new();
        let mut rows = 0usize;
        for (i, group) in self.metadata.metadata().row_groups().iter().enumerate() {
            if may_hold(group, kind, names) {
                groups.push(i);
                rows += usize::try_from(group.num_rows()).unwrap_or(usize::MAX);
            }
        }
        (groups, rows)
    }

    /// Visit the `(name, value)` of every `kind` row in `groups`.
    pub fn read<E: From<CatalogError>>(
        &self,
        groups: Vec<usize>,
        kind: i8,
        mut visit: impl FnMut(&[u8], &[u8]) -> Result<(), E>,
    ) -> Result<(), E> {
        if groups.is_empty() {
            return Ok(());
        }
        let builder = ParquetRecordBatchReaderBuilder::new_with_metadata(
            self.bytes.clone(),
            self.metadata.clone(),
        );
        let reader = builder
            .with_row_groups(groups)
            .with_batch_size(GROUP_ROWS)
            .build()
            .map_err(|_| CatalogError::Invalid)?;
        for batch in reader {
            let batch = batch.map_err(|_| CatalogError::Invalid)?;
            let names = column::<StringArray>(&batch, 0)?;
            let kinds = column::<Int8Array>(&batch, 1)?;
            let values = column::<BinaryArray>(&batch, 2)?;
            for row in 0..batch.num_rows() {
                if names.is_null(row) || kinds.is_null(row) || values.is_null(row) {
                    return Err(CatalogError::Invalid.into());
                }
                if kinds.value(row) == kind {
                    visit(names.value(row).as_bytes(), values.value(row))?;
                }
            }
        }
        Ok(())
    }
}

fn column<T: 'static>(batch: &RecordBatch, index: usize) -> Result<&T, CatalogError> {
    batch
        .column(index)
        .as_any()
        .downcast_ref::<T>()
        .ok_or(CatalogError::Invalid)
}

fn may_hold(group: &RowGroupMetaData, kind: i8, names: Option<&[Vec<u8>]>) -> bool {
    if let Some(Statistics::Int32(s)) = group.column(1).statistics() {
        if let (Some(min), Some(max)) = (s.min_opt(), s.max_opt()) {
            if s.min_is_exact()
                && s.max_is_exact()
                && (i32::from(kind) < *min || i32::from(kind) > *max)
            {
                return false;
            }
        }
    }
    let Some(names) = names else {
        return true;
    };
    match group.column(0).statistics() {
        Some(Statistics::ByteArray(s)) if s.min_is_exact() && s.max_is_exact() => {
            match (s.min_opt(), s.max_opt()) {
                (Some(min), Some(max)) => names
                    .iter()
                    .any(|name| min.data() <= name.as_slice() && name.as_slice() <= max.data()),
                _ => true,
            }
        }
        _ => true,
    }
}

// ---- NIFs -----------------------------------------------------------------

mod atoms {
    rustler::atoms! { ok, error, fallback, known, merge, segment, invalid_segment, too_large }
}

#[rustler::nif]
fn metric_catalog_api_version() -> u32 {
    1
}

pub struct CatalogBuilder(std::sync::Mutex<Option<Builder>>);

#[rustler::resource_impl]
impl rustler::Resource for CatalogBuilder {}

fn catalog_error<'a>(env: Env<'a>, reason: CatalogError) -> Term<'a> {
    match reason {
        CatalogError::Invalid => (atoms::error(), atoms::invalid_segment()).encode(env),
        CatalogError::TooLarge => (atoms::error(), atoms::too_large()).encode(env),
        CatalogError::Encode => atoms::fallback().encode(env),
    }
}

/// A builder for the catalog of `[start, end)`.
#[rustler::nif]
fn metric_catalog_new(env: Env, start: i64, end: i64) -> Term {
    if start >= end {
        return atoms::fallback().encode(env);
    }
    let builder = CatalogBuilder(std::sync::Mutex::new(Some(Builder::new(start, end))));
    (atoms::ok(), ResourceArc::new(builder)).encode(env)
}

/// Add a source: `:known` (a catalog whose series a delta leaves out),
/// `:merge` (a catalog merged into this one) or `:segment` (metric samples).
/// `{:ok, rows}`; a failed add discards the builder.
#[rustler::nif(schedule = "DirtyCpu")]
fn metric_catalog_add<'a>(
    env: Env<'a>,
    builder: ResourceArc<CatalogBuilder>,
    blob: Binary<'a>,
    source: rustler::Atom,
) -> Term<'a> {
    let Ok(mut guard) = builder.0.lock() else {
        return atoms::fallback().encode(env);
    };
    let Some(state) = guard.as_mut() else {
        return atoms::fallback().encode(env);
    };
    let bytes = crate::erlang_bytes::from_binary(blob);
    let result = if source == atoms::known() {
        state.add_catalog(bytes, true)
    } else if source == atoms::merge() {
        state.add_catalog(bytes, false)
    } else if source == atoms::segment() {
        state.add_segment(bytes)
    } else {
        Err(CatalogError::Encode)
    };
    match result {
        Ok(rows) => (atoms::ok(), rows).encode(env),
        Err(reason) => {
            guard.take();
            catalog_error(env, reason)
        }
    }
}

/// `{:ok, {payload, series}}`: the encoded catalog covering the
/// newline-separated segment keys `covers`.
#[rustler::nif(schedule = "DirtyCpu")]
fn metric_catalog_finish<'a>(
    env: Env<'a>,
    builder: ResourceArc<CatalogBuilder>,
    covers: Binary<'a>,
) -> Term<'a> {
    let Some(state) = builder.0.lock().ok().and_then(|mut guard| guard.take()) else {
        return atoms::fallback().encode(env);
    };
    let Ok(covers) = std::str::from_utf8(covers.as_slice()) else {
        return atoms::fallback().encode(env);
    };
    let mut out = crate::out::BinaryWriter(crate::out::BinSink::with_capacity(
        4096 + state.series() * 64,
    ));
    match state.encode(&mut out, covers) {
        Ok(()) => (atoms::ok(), (out.0.finish(env), state.series())).encode(env),
        Err(reason) => catalog_error(env, reason),
    }
}

/// `{:ok, covers}`: the newline-separated keys a catalog covers.
#[rustler::nif(schedule = "DirtyCpu")]
fn metric_catalog_covers<'a>(env: Env<'a>, blob: Binary<'a>) -> Term<'a> {
    match Catalog::open(crate::erlang_bytes::from_binary(blob)) {
        Ok(catalog) => (atoms::ok(), catalog.covers()).encode(env),
        Err(reason) => catalog_error(env, reason),
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use arrow::datatypes::{Field, Schema};
    use parquet::arrow::ArrowWriter;

    pub fn canonical(pairs: &[(&str, &str)]) -> Vec<u8> {
        pairs
            .iter()
            .flat_map(|(k, v)| [k.as_bytes(), &[255], v.as_bytes(), &[255]].concat())
            .collect()
    }

    pub fn segment(rows: &[(i64, Vec<u8>)]) -> Bytes {
        let schema = Arc::new(Schema::new(vec![
            Field::new("timestamp_ns", DataType::Int64, false),
            Field::new("labels_canonical", DataType::Binary, false),
        ]));
        let batch = RecordBatch::try_new(
            Arc::clone(&schema),
            vec![
                Arc::new(Int64Array::from_iter_values(rows.iter().map(|r| r.0))),
                Arc::new(BinaryArray::from_iter_values(rows.iter().map(|r| &r.1))),
            ],
        )
        .unwrap();
        let mut writer = ArrowWriter::try_new(Vec::new(), schema, None).unwrap();
        writer.write(&batch).unwrap();
        Bytes::from(writer.into_inner().unwrap())
    }

    pub fn encoded(builder: &Builder, covers: &str) -> Bytes {
        let mut out = Vec::new();
        builder.encode(&mut out, covers).unwrap();
        Bytes::from(out)
    }

    fn section(catalog: &Catalog, kind: i8) -> Vec<(String, Vec<u8>)> {
        let (groups, _) = catalog.groups(kind, None);
        let mut rows = Vec::new();
        catalog
            .read(groups, kind, |n, v| {
                rows.push((String::from_utf8(n.to_vec()).unwrap(), v.to_vec()));
                Ok::<(), CatalogError>(())
            })
            .unwrap();
        rows
    }

    #[test]
    fn sections_list_hour_series_once_without_empty_labels() {
        let a = canonical(&[("__name__", "up"), ("job", "api"), ("zone", "")]);
        let b = canonical(&[("__name__", "requests"), ("job", "web")]);
        let late = canonical(&[("__name__", "late"), ("job", "x")]);
        let mut builder = Builder::new(100, 200);
        let rows = builder
            .add_segment(segment(&[
                (100, a.clone()),
                (150, a.clone()),
                (199, b.clone()),
                (200, late.clone()),
                (99, late),
            ]))
            .unwrap();
        assert_eq!((rows, builder.series()), (5, 2));
        let catalog = Catalog::open(encoded(&builder, "k1\nk2")).unwrap();
        assert_eq!(catalog.covers(), "k1\nk2");
        let names = |rows: Vec<(String, Vec<u8>)>| {
            rows.into_iter()
                .map(|(n, v)| format!("{n}={}", String::from_utf8(v).unwrap()))
                .collect::<Vec<_>>()
        };
        assert_eq!(names(section(&catalog, NAMES)), ["__name__=", "job="]);
        assert_eq!(
            names(section(&catalog, VALUES)),
            ["__name__=requests", "__name__=up", "job=api", "job=web"]
        );
        assert_eq!(
            names(section(&catalog, METRIC_LABELS)),
            ["requests=__name__", "requests=job", "up=__name__", "up=job"]
        );
        assert_eq!(
            section(&catalog, SERIES),
            [("requests".into(), b.clone()), ("up".into(), a.clone())]
        );
    }

    #[test]
    fn deltas_leave_out_known_series_and_merges_union_them() {
        let a = canonical(&[("__name__", "up")]);
        let b = canonical(&[("__name__", "down")]);
        let mut first = Builder::new(0, 10);
        first.add_segment(segment(&[(1, a.clone())])).unwrap();
        let base = encoded(&first, "");
        let mut delta = Builder::new(0, 10);
        assert_eq!(delta.add_catalog(base.clone(), true).unwrap(), 1);
        delta
            .add_segment(segment(&[(2, a.clone()), (3, b.clone())]))
            .unwrap();
        assert_eq!(delta.series(), 1);
        let delta = encoded(&delta, "");
        let mut merged = Builder::new(0, 10);
        merged.add_catalog(base, false).unwrap();
        merged.add_catalog(delta, false).unwrap();
        assert_eq!(merged.series(), 2);
    }

    #[test]
    fn statistics_skip_other_sections_and_metric_names() {
        let mut builder = Builder::new(0, 10);
        let rows: Vec<_> = (0..20_000)
            .map(|i| {
                (
                    1,
                    canonical(&[
                        ("__name__", &format!("m{:05}", i / 100)),
                        ("i", &i.to_string()),
                    ]),
                )
            })
            .collect();
        builder.add_segment(segment(&rows)).unwrap();
        let catalog = Catalog::open(encoded(&builder, "")).unwrap();
        let (groups, names) = catalog.groups(NAMES, None);
        assert_eq!((groups.len(), names), (1, 2));
        let (groups, rows) = catalog.groups(SERIES, Some(&[b"m00150".to_vec()]));
        assert_eq!((groups.len(), rows), (1, GROUP_ROWS));
        let (_, all) = catalog.groups(SERIES, None);
        assert_eq!(all, 20_000);
    }

    #[test]
    fn metric_segments_and_damaged_series_are_rejected() {
        assert!(matches!(
            Catalog::open(segment(&[(1, canonical(&[("a", "b")]))])),
            Err(CatalogError::Invalid)
        ));
        let mut builder = Builder::new(0, 10);
        assert!(matches!(
            builder.add_segment(segment(&[(1, b"z\xffa\xffa\xffb\xff".to_vec())])),
            Err(CatalogError::Invalid)
        ));
    }
}
