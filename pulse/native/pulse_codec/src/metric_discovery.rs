//! Sample-backed metadata discovery. One disposable state unions all selectors
//! and sources, retaining labels only, never values/OTLP records or input blobs.
use crate::metric_segment_parquet::{self as metrics, MatcherOp};
use crate::out::Sink;
use arrow::array::{Array, BinaryArray, DictionaryArray, Int64Array};
use arrow::datatypes::{DataType, Int32Type, Schema};
use bytes::Bytes;
use parquet::arrow::arrow_reader::{
    ArrowReaderMetadata, ArrowReaderOptions, ParquetRecordBatchReaderBuilder,
};
use rustler::{Binary, Encoder, Env, ListIterator, ResourceArc, Term};
use std::collections::{BTreeMap, HashSet};
use std::sync::{Arc, Mutex};

mod atoms {
    rustler::atoms! { ok, error, fallback, eq, neq, re, nre, query_scan_limit,
    query_work_limit, query_resource_limit, invalid_stored_sample }
}
const ENTRIES: usize = 5000;
const BYTES: usize = 1_048_576;
const ROWS: usize = 1_000_000;
const WORK: usize = 5_000_000;
const PROBES: usize = 16 * 1_048_576;
#[derive(Debug)]
enum Error {
    Invalid,
    Rows,
    Work,
    Budget,
    Stored,
}
type Res<T> = Result<T, Error>;
#[derive(Clone, Copy)]
enum Mode {
    Names,
    Values,
    Series,
}
struct Matcher {
    name: String,
    value: String,
    op: MatcherOp,
    regex: Option<regex::Regex>,
}
impl Matcher {
    fn matches(&self, value: &str) -> bool {
        match self.op {
            MatcherOp::Eq => value == self.value,
            MatcherOp::Neq => value != self.value,
            MatcherOp::Re => self.regex.as_ref().is_some_and(|r| r.is_match(value)),
            MatcherOp::Nre => self.regex.as_ref().is_some_and(|r| !r.is_match(value)),
        }
    }
}
struct State {
    mode: Mode,
    key: String,
    start: i64,
    end: i64,
    selectors: Vec<Vec<Matcher>>,
    matcher_count: usize,
    rows: usize,
    sources: usize,
    input: usize,
    work: usize,
    probes: usize,
    bytes: usize,
    encoded: usize,
    entries: BTreeMap<Vec<u8>, Vec<u8>>,
}
pub struct Discovery(Mutex<Option<State>>);
#[rustler::resource_impl]
impl rustler::Resource for Discovery {}
fn result<'a, T: Encoder>(env: Env<'a>, value: Res<T>) -> Term<'a> {
    match value {
        Ok(value) => (atoms::ok(), value).encode(env),
        Err(Error::Invalid) => atoms::fallback().encode(env),
        Err(reason) => (
            atoms::error(),
            match reason {
                Error::Rows => atoms::query_scan_limit(),
                Error::Work => atoms::query_work_limit(),
                Error::Stored => atoms::invalid_stored_sample(),
                _ => atoms::query_resource_limit(),
            },
        )
            .encode(env),
    }
}
#[rustler::nif]
fn metric_discovery_api_version() -> u32 {
    1
}
#[rustler::nif(schedule = "DirtyCpu")]
fn metric_discovery_new<'a>(
    env: Env<'a>,
    mode: &str,
    key: &str,
    start: i64,
    end: i64,
    selectors: Term<'a>,
) -> Term<'a> {
    let build = || {
        let mode = match mode {
            "names" => Mode::Names,
            "values" => Mode::Values,
            "series" => Mode::Series,
            _ => return Err(Error::Invalid),
        };
        if start > end
            || key.len() > 256
            || (matches!(mode, Mode::Values) == key.is_empty())
            || (!matches!(mode, Mode::Values) && !key.is_empty())
        {
            return Err(Error::Invalid);
        }
        let mut parsed = Vec::new();
        let (mut count, mut regex_count, mut bytes) = (0, 0, 0);
        for selector in selectors
            .decode::<ListIterator>()
            .map_err(|_| Error::Invalid)?
        {
            if parsed.len() == 16 {
                return Err(Error::Invalid);
            }
            let mut matchers = Vec::new();
            for term in selector
                .decode::<ListIterator>()
                .map_err(|_| Error::Invalid)?
            {
                count += 1;
                if count > 64 {
                    return Err(Error::Invalid);
                }
                let (name, op, value): (Binary, rustler::Atom, Binary) =
                    term.decode().map_err(|_| Error::Invalid)?;
                bytes += name.len() + value.len();
                if name.is_empty() || name.len() > 256 || bytes > 16_384 {
                    return Err(Error::Invalid);
                }
                let name = std::str::from_utf8(name.as_slice())
                    .map_err(|_| Error::Invalid)?
                    .to_owned();
                let value = std::str::from_utf8(value.as_slice())
                    .map_err(|_| Error::Invalid)?
                    .to_owned();
                let op = if op == atoms::eq() {
                    MatcherOp::Eq
                } else if op == atoms::neq() {
                    MatcherOp::Neq
                } else if op == atoms::re() {
                    MatcherOp::Re
                } else if op == atoms::nre() {
                    MatcherOp::Nre
                } else {
                    return Err(Error::Invalid);
                };
                let regex = if matches!(op, MatcherOp::Re | MatcherOp::Nre) {
                    regex_count += 1;
                    if regex_count > 8 || value.len() > 1024 {
                        return Err(Error::Invalid);
                    }
                    Some(crate::query_regex::anchored(&value).map_err(|_| Error::Invalid)?)
                } else {
                    None
                };
                matchers.push(Matcher {
                    name,
                    value,
                    op,
                    regex,
                });
            }
            if !matchers.iter().any(|m| !m.matches("")) {
                return Err(Error::Invalid);
            }
            parsed.push(matchers);
        }
        if matches!(mode, Mode::Series) && parsed.is_empty() {
            return Err(Error::Invalid);
        }
        Ok(ResourceArc::new(Discovery(Mutex::new(Some(State {
            mode,
            key: key.to_owned(),
            start,
            end,
            selectors: parsed,
            matcher_count: count,
            sources: 0,
            input: 0,
            rows: 0,
            work: 0,
            probes: 0,
            bytes: 0,
            encoded: 2,
            entries: BTreeMap::new(),
        })))))
    };
    result(env, build())
}
fn row_count(builder: &ParquetRecordBatchReaderBuilder<Bytes>) -> Res<usize> {
    let metadata = builder.metadata();
    let rows = usize::try_from(metadata.file_metadata().num_rows()).map_err(|_| Error::Stored)?;
    let groups = metadata.row_groups().iter().try_fold(0usize, |sum, g| {
        let n = usize::try_from(g.num_rows()).map_err(|_| Error::Stored)?;
        sum.checked_add(n).ok_or(Error::Stored)
    })?;
    if groups != rows {
        return Err(Error::Stored);
    }
    Ok(rows)
}
#[rustler::nif(schedule = "DirtyCpu")]
fn metric_segment_parquet_row_count<'a>(env: Env<'a>, blob: Binary<'a>) -> Term<'a> {
    result(
        env,
        ParquetRecordBatchReaderBuilder::try_new(crate::erlang_bytes::from_binary(blob))
            .map_err(|_| Error::Stored)
            .and_then(|b| row_count(&b)),
    )
}
#[rustler::nif(schedule = "DirtyCpu")]
fn metric_discovery_add<'a>(
    env: Env<'a>,
    resource: ResourceArc<Discovery>,
    blob: Binary<'a>,
) -> Term<'a> {
    let add = || {
        let mut guard = resource.0.lock().map_err(|_| Error::Invalid)?;
        let mut state = guard.take().ok_or(Error::Invalid)?;
        if blob.len() > 128 * 1_048_576 {
            return Err(Error::Budget);
        }
        let rows = state.scan(crate::erlang_bytes::from_binary(blob))?;
        *guard = Some(state);
        Ok(rows)
    };
    result(env, add())
}
#[rustler::nif(schedule = "DirtyCpu")]
fn metric_discovery_finish<'a>(env: Env<'a>, resource: ResourceArc<Discovery>) -> Term<'a> {
    let finish = || {
        let state = resource
            .0
            .lock()
            .map_err(|_| Error::Invalid)?
            .take()
            .ok_or(Error::Invalid)?;
        let mut out = crate::out::BinSink::with_capacity(state.encoded);
        out.push(b'[');
        for (i, entry) in state.entries.values().enumerate() {
            if i > 0 {
                out.push(b',');
            }
            out.extend(entry);
        }
        out.push(b']');
        Ok(out.finish(env))
    };
    result(env, finish())
}
#[rustler::nif(schedule = "DirtyCpu")]
fn metric_discovery_abort(resource: ResourceArc<Discovery>) -> rustler::Atom {
    if let Ok(mut guard) = resource.0.lock() {
        guard.take();
    }
    atoms::ok()
}
impl State {
    fn insert(&mut self, key: &[u8], encoded: Vec<u8>) -> Res<()> {
        if self.entries.contains_key(key) {
            return Ok(());
        }
        self.bytes += key.len();
        self.encoded += encoded.len() + usize::from(!self.entries.is_empty());
        if self.entries.len() == ENTRIES || self.bytes > BYTES || self.encoded > BYTES - 32 {
            return Err(Error::Budget);
        }
        self.entries.insert(key.to_vec(), encoded);
        Ok(())
    }
    fn observe(&mut self, canonical: &[u8]) -> Res<()> {
        self.probes += canonical.len();
        if canonical.len() > 65_536 || self.probes > PROBES {
            return Err(Error::Budget);
        }
        let mut pairs = Vec::new();
        metrics::parse_canonical_pairs(canonical, &mut pairs).map_err(|_| Error::Stored)?;
        if pairs.len() > 1024 {
            return Err(Error::Budget);
        }
        for (i, (name, value)) in pairs.iter().enumerate() {
            if name.is_empty()
                || std::str::from_utf8(name).is_err()
                || std::str::from_utf8(value).is_err()
                || (i > 0 && pairs[i - 1].0 >= *name)
            {
                return Err(Error::Stored);
            }
        }
        self.work += 1 + pairs.len() + self.matcher_count;
        if self.work > WORK {
            return Err(Error::Work);
        }
        if !self.selectors.is_empty()
            && !self.selectors.iter().any(|selector| {
                selector.iter().all(|m| {
                    let value = pairs
                        .binary_search_by(|p| p.0.cmp(m.name.as_bytes()))
                        .ok()
                        .map(|i| pairs[i].1)
                        .unwrap_or(b"");
                    m.matches(std::str::from_utf8(value).expect("validated labels"))
                })
            })
        {
            return Ok(());
        }
        // Prometheus treats empty-valued labels as absent. This is a metadata
        // projection only; raw records/OTLP envelopes are never rewritten.
        pairs.retain(|(_, value)| !value.is_empty());
        match self.mode {
            Mode::Series => self.insert(&series_key(&pairs), metrics::labels_as_json(&pairs)),
            Mode::Names => {
                for (name, _) in pairs {
                    self.insert(name, quoted(name))?;
                }
                Ok(())
            }
            Mode::Values => {
                if let Some((_, value)) = pairs.iter().find(|p| p.0 == self.key.as_bytes()) {
                    self.insert(value, quoted(value))?;
                }
                Ok(())
            }
        }
    }
    fn scan(&mut self, bytes: Bytes) -> Res<usize> {
        self.sources += 1;
        self.input += bytes.len();
        if self.sources > 1024 || self.input > 128 * 1_048_576 {
            return Err(Error::Rows);
        }
        let builder =
            ParquetRecordBatchReaderBuilder::try_new(bytes.clone()).map_err(|_| Error::Stored)?;
        let rows = row_count(&builder)?;
        self.rows += rows;
        if self.rows > ROWS {
            return Err(Error::Rows);
        }
        let schema = builder.schema();
        let ts = schema.index_of("timestamp_ns").map_err(|_| Error::Stored)?;
        let labels = schema
            .index_of("labels_canonical")
            .map_err(|_| Error::Stored)?;
        if schema.field(ts).data_type() != &DataType::Int64
            || schema.field(labels).data_type() != &DataType::Binary
        {
            return Err(Error::Stored);
        }
        if ["timestamp_ns", "labels_canonical"]
            .iter()
            .any(|name| schema.fields().iter().filter(|f| f.name() == name).count() != 1)
        {
            return Err(Error::Stored);
        }
        // Repeated samples share dictionary keys, never full byte comparisons.
        // The seen-key set is bounded to one 1024-row batch.
        let mut fields = schema.fields().to_vec();
        fields[labels] = Arc::new(fields[labels].as_ref().clone().with_data_type(
            DataType::Dictionary(Box::new(DataType::Int32), Box::new(DataType::Binary)),
        ));
        let read_schema = Arc::new(Schema::new_with_metadata(fields, schema.metadata().clone()));
        let metadata = ArrowReaderMetadata::try_new(
            Arc::clone(builder.metadata()),
            ArrowReaderOptions::new().with_schema(read_schema),
        )
        .map_err(|_| Error::Stored)?;
        let builder = ParquetRecordBatchReaderBuilder::new_with_metadata(bytes, metadata);
        let projection =
            parquet::arrow::ProjectionMask::roots(builder.parquet_schema(), [ts, labels]);
        let (ts, labels) = if ts < labels { (0, 1) } else { (1, 0) };
        let reader = builder
            .with_projection(projection)
            .with_batch_size(1024)
            .build()
            .map_err(|_| Error::Stored)?;
        let mut decoded = 0;
        for batch in reader {
            let batch = batch.map_err(|_| Error::Stored)?;
            let times = batch
                .column(ts)
                .as_any()
                .downcast_ref::<Int64Array>()
                .ok_or(Error::Stored)?;
            let labels = batch
                .column(labels)
                .as_any()
                .downcast_ref::<DictionaryArray<Int32Type>>()
                .ok_or(Error::Stored)?;
            let values = labels
                .values()
                .as_any()
                .downcast_ref::<BinaryArray>()
                .ok_or(Error::Stored)?;
            let mut seen = HashSet::with_capacity(batch.num_rows());
            decoded += batch.num_rows();
            for row in 0..batch.num_rows() {
                self.work += 1;
                if self.work > WORK {
                    return Err(Error::Work);
                }
                if times.is_null(row) {
                    return Err(Error::Stored);
                }
                if times.value(row) < self.start || times.value(row) > self.end {
                    continue;
                }
                if labels.is_null(row) {
                    return Err(Error::Stored);
                }
                let key = labels.key(row).ok_or(Error::Stored)?;
                if values.is_null(key) {
                    return Err(Error::Stored);
                }
                if seen.insert(key) {
                    self.observe(values.value(key))?;
                }
            }
        }
        if decoded != rows {
            return Err(Error::Stored);
        }
        Ok(rows)
    }
}
// Order-preserving tuple encoding: NUL escapes sort after terminators, so
// shorter names/values and equal-prefix label sets sort first, like Go.
fn series_key(pairs: &[(&[u8], &[u8])]) -> Vec<u8> {
    let mut key = Vec::new();
    for (name, value) in pairs {
        for part in [name, value] {
            for byte in *part {
                key.push(*byte);
                if *byte == 0 {
                    key.push(1);
                }
            }
            key.extend_from_slice(&[0, 0]);
        }
    }
    key
}
fn quoted(bytes: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    metrics::encode_json_string(&mut out, bytes);
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use arrow::datatypes::{Field, Schema};
    use arrow::record_batch::RecordBatch;
    use parquet::arrow::ArrowWriter;
    use std::sync::Arc;

    fn state(mode: Mode) -> State {
        State {
            mode,
            key: "host".into(),
            start: i64::MIN,
            end: i64::MAX,
            selectors: Vec::new(),
            matcher_count: 0,
            sources: 0,
            input: 0,
            rows: 0,
            work: 0,
            probes: 0,
            bytes: 0,
            encoded: 2,
            entries: BTreeMap::new(),
        }
    }
    fn canonical(pairs: &[(&str, &str)]) -> Vec<u8> {
        pairs
            .iter()
            .flat_map(|(k, v)| [k.as_bytes(), &[255], v.as_bytes(), &[255]].concat())
            .collect()
    }
    fn blob() -> Bytes {
        let schema = Arc::new(Schema::new(vec![
            Field::new("timestamp_ns", DataType::Int64, false),
            Field::new("labels_canonical", DataType::Binary, false),
        ]));
        let labels = canonical(&[("__name__", "requests"), ("host", "a")]);
        let batch = RecordBatch::try_new(
            Arc::clone(&schema),
            vec![
                Arc::new(Int64Array::from(vec![-1, 0, 1, 2, 3])),
                Arc::new(BinaryArray::from(vec![labels.as_slice(); 5])),
            ],
        )
        .unwrap();
        let mut writer = ArrowWriter::try_new(Vec::new(), schema, None).unwrap();
        writer.write(&batch).unwrap();
        Bytes::from(writer.into_inner().unwrap())
    }
    #[test]
    fn projection_counts_all_source_rows_but_selects_exact_sample_time() {
        let mut s = state(Mode::Series);
        s.start = 1;
        s.end = 1;
        assert_eq!(s.scan(blob()).unwrap(), 5);
        assert_eq!(s.rows, 5);
        assert_eq!(s.work, 8);
        assert_eq!(s.entries.len(), 1);
        assert_eq!(
            s.entries.values().next().unwrap(),
            br#"{"__name__":"requests","host":"a"}"#
        );
        s.rows = ROWS;
        assert!(matches!(s.scan(blob()), Err(Error::Rows)));
    }
    #[test]
    fn complete_dictionaries_deduplicate_and_reject_the_5001st() {
        let mut s = state(Mode::Values);
        for i in 0..ENTRIES {
            s.observe(&canonical(&[("host", &i.to_string())])).unwrap();
        }
        assert_eq!(s.entries.len(), ENTRIES);
        s.observe(&canonical(&[("host", "0")])).unwrap();
        assert!(matches!(
            s.observe(&canonical(&[("host", "extra")])),
            Err(Error::Budget)
        ));
        let mut s = state(Mode::Values);
        s.observe(&canonical(&[("missing", "")])).unwrap();
        assert!(s.entries.is_empty());
        s.observe(&canonical(&[("host", "")])).unwrap();
        assert!(s.entries.is_empty());
    }
    #[test]
    fn missing_labels_regex_union_and_corruption_before_predicates() {
        let mut s = state(Mode::Names);
        s.selectors = vec![
            vec![Matcher {
                name: "host".into(),
                value: "".into(),
                op: MatcherOp::Eq,
                regex: None,
            }],
            vec![Matcher {
                name: "host".into(),
                value: "a".into(),
                op: MatcherOp::Re,
                regex: Some(metrics::compile_metric_regex("(?s:\\A(?:a)\\z)").unwrap()),
            }],
        ];
        s.matcher_count = 2;
        s.observe(&canonical(&[("other", "b")])).unwrap();
        s.observe(&canonical(&[("host", "a")])).unwrap();
        s.observe(&canonical(&[("excluded", "b"), ("host", "aa")]))
            .unwrap();
        assert_eq!(
            s.entries.keys().cloned().collect::<Vec<_>>(),
            vec![b"host".to_vec(), b"other".to_vec()]
        );
        for bad in [
            &b"x\xffa\xffx\xffb\xff"[..],
            &b"z\xffa\xffa\xffb\xff"[..],
            &b"a\xff\xfe\xff"[..],
            &b"a\xff"[..],
        ] {
            assert!(matches!(s.observe(bad), Err(Error::Stored)));
        }
    }
    #[test]
    fn dictionary_scans_do_not_probe_repeated_sample_bytes() {
        let canonical = canonical(&[("host", &"x".repeat(240))]);
        let schema = Arc::new(Schema::new(vec![
            Field::new("timestamp_ns", DataType::Int64, false),
            Field::new("labels_canonical", DataType::Binary, false),
        ]));
        let batch = RecordBatch::try_new(
            Arc::clone(&schema),
            vec![
                Arc::new(Int64Array::from(vec![1; 100_000])),
                Arc::new(BinaryArray::from(vec![canonical.as_slice(); 100_000])),
            ],
        )
        .unwrap();
        let mut writer = ArrowWriter::try_new(Vec::new(), schema, None).unwrap();
        writer.write(&batch).unwrap();
        let mut s = state(Mode::Values);
        assert_eq!(
            s.scan(Bytes::from(writer.into_inner().unwrap())).unwrap(),
            100_000
        );
        assert_eq!(s.entries.len(), 1);
        assert!(s.probes <= canonical.len() * 100);
        assert!(s.work < 101_000);
        let mut s = state(Mode::Names);
        s.sources = 1024;
        assert!(matches!(s.scan(blob()), Err(Error::Rows)));
        let mut s = state(Mode::Names);
        s.input = 128 * 1_048_576;
        assert!(matches!(s.scan(blob()), Err(Error::Rows)));
    }
    #[test]
    fn series_order_is_pairwise_and_empty_labels_are_projection_only() {
        let mut tuples = Vec::new();
        for name in ["a", "aa", "á"] {
            for value in ["1", "10", "1\0", "1\0x", "2", "µ"] {
                tuples.push(vec![(name.as_bytes(), value.as_bytes())]);
            }
        }
        let mut encoded = tuples.clone();
        tuples.sort();
        encoded.sort_by_key(|pairs| series_key(pairs));
        assert_eq!(encoded, tuples);
        let mut s = state(Mode::Series);
        s.observe(&canonical(&[("a", "1"), ("host", "")])).unwrap();
        s.observe(&canonical(&[("a", "1")])).unwrap();
        assert_eq!(s.entries.len(), 1);
        assert_eq!(s.entries.values().next().unwrap(), br#"{"a":"1"}"#);
    }
    #[test]
    fn work_probe_and_encoded_output_budgets_are_independent() {
        let row = canonical(&[("host", "a")]);
        let mut s = state(Mode::Values);
        s.work = WORK - 2;
        s.observe(&row).unwrap();
        assert!(matches!(s.observe(&row), Err(Error::Work)));
        let mut s = state(Mode::Values);
        s.probes = PROBES - row.len();
        s.observe(&row).unwrap();
        assert!(matches!(s.observe(&row), Err(Error::Budget)));
        let mut s = state(Mode::Values);
        s.encoded = BYTES - 32 - 3;
        s.observe(&row).unwrap();
        assert!(matches!(
            s.observe(&canonical(&[("host", "b")])),
            Err(Error::Budget)
        ));
        let mut raw = state(Mode::Values);
        raw.bytes = BYTES - 1;
        raw.observe(&row).unwrap();
        assert!(matches!(
            raw.observe(&canonical(&[("host", "b")])),
            Err(Error::Budget)
        ));
        let mut s = state(Mode::Series);
        s.observe(&canonical(&[("host", "\n\"µ")])).unwrap();
        assert_eq!(
            s.entries.values().next().unwrap(),
            "{\"host\":\"\\n\\\"µ\"}".as_bytes()
        );
    }
}
