//! Loki stream-label discovery over log Parquet segments. One disposable
//! state unions every source, retaining discovered labels only, never log
//! bodies, attributes or input blobs.
//!
//! Stream labels are the string values of the `resource` JSON column (where
//! Loki push keeps stream labels and OTLP keeps resource attributes) plus the
//! promoted `service` column as `service_name`. Selection uses exactly the
//! log decoder's predicates: inclusive time bounds, exact promoted service
//! and the stream matchers, including the promoted `service`/`level`
//! mirrors. Empty values are absent, as in Loki.
//!
//! Only the four columns involved are decoded, as dictionaries: a run of rows
//! from one stream shares dictionary keys, so its resource JSON is walked and
//! matched once per 1024-row batch rather than once per row.
use crate::out::Sink;
use crate::query_filter::{self, Matcher};
use arrow::array::{Array, DictionaryArray, Int64Array, StringArray};
use arrow::datatypes::{DataType, Int32Type, Schema};
use bytes::Bytes;
use parquet::arrow::arrow_reader::{
    ArrowReaderMetadata, ArrowReaderOptions, ParquetRecordBatchReaderBuilder,
};
use rustler::{Binary, Encoder, Env, ResourceArc, Term};
use std::borrow::Cow;
use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex};

mod atoms {
    rustler::atoms! { ok, error, fallback, nil, query_scan_limit, query_work_limit,
    query_resource_limit, invalid_stored_sample }
}

const ENTRIES: usize = 5000;
const BYTES: usize = 1_048_576;
const SOURCES: usize = 1024;
const INPUT: usize = 128 * 1_048_576;
const ROWS: usize = 10_000_000;
const WORK: usize = 50_000_000;
const PROBES: usize = 64 * 1_048_576;
const COLUMNS: [&str; 4] = ["timestamp_ns", "service", "severity_text", "resource"];

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

struct State {
    mode: Mode,
    key: Vec<u8>,
    start: i64,
    end: i64,
    service: Option<Vec<u8>>,
    matchers: Vec<Matcher>,
    sources: usize,
    input: usize,
    rows: usize,
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
fn log_discovery_api_version() -> u32 {
    1
}

#[rustler::nif(schedule = "DirtyCpu")]
fn log_discovery_new<'a>(
    env: Env<'a>,
    mode: &str,
    key: Binary<'a>,
    start: i64,
    end: i64,
    service: Term<'a>,
    matchers: Term<'a>,
) -> Term<'a> {
    let build = || {
        let mode = match mode {
            "names" => Mode::Names,
            "values" => Mode::Values,
            "series" => Mode::Series,
            _ => return Err(Error::Invalid),
        };
        if start > end || key.len() > 256 || matches!(mode, Mode::Values) == key.is_empty() {
            return Err(Error::Invalid);
        }
        let service = match service.decode::<Binary>() {
            Ok(service) if !service.is_empty() && service.len() <= 256 => {
                Some(service.as_slice().to_vec())
            }
            Ok(_) => return Err(Error::Invalid),
            Err(_) if service.decode::<rustler::Atom>().ok() == Some(atoms::nil()) => None,
            Err(_) => return Err(Error::Invalid),
        };
        let matchers = crate::decode_matchers(matchers).map_err(|_| Error::Invalid)?;
        if matchers.len() > 64 {
            return Err(Error::Invalid);
        }
        Ok(ResourceArc::new(Discovery(Mutex::new(Some(State {
            mode,
            key: key.as_slice().to_vec(),
            start,
            end,
            service,
            matchers,
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

#[rustler::nif(schedule = "DirtyCpu")]
fn log_discovery_add<'a>(
    env: Env<'a>,
    resource: ResourceArc<Discovery>,
    blob: Binary<'a>,
) -> Term<'a> {
    let add = || {
        let mut guard = resource.0.lock().map_err(|_| Error::Invalid)?;
        let mut state = guard.take().ok_or(Error::Invalid)?;
        let rows = state.scan(crate::erlang_bytes::from_binary(blob))?;
        *guard = Some(state);
        Ok(rows)
    };
    result(env, add())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn log_discovery_finish<'a>(env: Env<'a>, resource: ResourceArc<Discovery>) -> Term<'a> {
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
fn log_discovery_abort(resource: ResourceArc<Discovery>) -> rustler::Atom {
    if let Ok(mut guard) = resource.0.lock() {
        guard.take();
    }
    atoms::ok()
}

// The dictionary values of one string column in a batch, with a row's key.
struct Column<'b> {
    keys: &'b DictionaryArray<Int32Type>,
    values: &'b StringArray,
}

impl<'b> Column<'b> {
    fn from(array: &'b dyn Array) -> Res<Self> {
        let keys = array
            .as_any()
            .downcast_ref::<DictionaryArray<Int32Type>>()
            .ok_or(Error::Stored)?;
        let values = keys
            .values()
            .as_any()
            .downcast_ref::<StringArray>()
            .ok_or(Error::Stored)?;
        Ok(Column { keys, values })
    }

    // -1 is null; nonnegative is the dictionary key.
    fn key(&self, row: usize) -> i32 {
        if self.keys.is_null(row) {
            -1
        } else {
            self.keys.keys().value(row)
        }
    }

    // Null and empty strings both mean "no value", as in the log decoder.
    fn bytes(&self, key: i32) -> Option<&'b [u8]> {
        let key = usize::try_from(key).ok()?;
        (key < self.values.len() && !self.values.is_null(key))
            .then(|| self.values.value(key).as_bytes())
            .filter(|bytes| !bytes.is_empty())
    }
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

    // Mirrors `segment_parquet::matchers_pass`: promoted service/level win
    // when present, otherwise the resource JSON is consulted.
    fn selected(
        &self,
        resource: Option<&[u8]>,
        service: Option<&[u8]>,
        level: Option<&[u8]>,
    ) -> bool {
        if let Some(wanted) = &self.service {
            if service != Some(wanted.as_slice()) {
                return false;
            }
        }
        self.matchers.iter().all(|m| {
            let promoted = match m.name() {
                b"service" | b"service_name" => service,
                b"level" | b"detected_level" => level,
                _ => None,
            };
            if let Some(value) = promoted {
                return m.evaluate_present(value);
            }
            match resource.and_then(|r| query_filter::find_label(r, m.name())) {
                Some(value) => m.evaluate_present(&value),
                None => m.evaluate_absent(),
            }
        })
    }

    fn observe(&mut self, resource: Option<&[u8]>, service: Option<&[u8]>) -> Res<()> {
        let mut labels: BTreeMap<Cow<'_, [u8]>, Cow<'_, [u8]>> = BTreeMap::new();
        if let Some(resource) = resource {
            self.probes += resource.len();
            if resource.len() > 65_536 || self.probes > PROBES {
                return Err(Error::Budget);
            }
            // Later duplicates win, as when the JSON decodes into a map.
            for (name, value) in query_filter::string_pairs(resource).unwrap_or_default() {
                if !name.is_empty() && !value.is_empty() {
                    labels.insert(name, value);
                }
            }
        }
        if let Some(service) = service {
            labels
                .entry(Cow::Borrowed(b"service_name"))
                .or_insert(Cow::Borrowed(service));
        }
        if labels.len() > 1024 {
            return Err(Error::Budget);
        }
        self.work += 1 + labels.len();
        if self.work > WORK {
            return Err(Error::Work);
        }
        if labels
            .iter()
            .any(|(n, v)| std::str::from_utf8(n).is_err() || std::str::from_utf8(v).is_err())
        {
            return Err(Error::Stored);
        }
        match self.mode {
            Mode::Series => {
                let mut key = Vec::new();
                let mut json = vec![b'{'];
                for (i, (name, value)) in labels.iter().enumerate() {
                    key.extend_from_slice(name);
                    key.push(0xff);
                    key.extend_from_slice(value);
                    key.push(0xff);
                    if i > 0 {
                        json.push(b',');
                    }
                    json.extend_from_slice(&quoted(name));
                    json.push(b':');
                    json.extend_from_slice(&quoted(value));
                }
                json.push(b'}');
                self.insert(&key, json)
            }
            Mode::Names => {
                for name in labels.keys() {
                    self.insert(name, quoted(name))?;
                }
                Ok(())
            }
            Mode::Values => {
                if let Some(value) = labels.get(self.key.as_slice()) {
                    let value = value.to_vec();
                    self.insert(&value, quoted(&value))?;
                }
                Ok(())
            }
        }
    }

    fn scan(&mut self, bytes: Bytes) -> Res<usize> {
        self.sources += 1;
        self.input += bytes.len();
        if self.sources > SOURCES || self.input > INPUT {
            return Err(Error::Rows);
        }
        let builder =
            ParquetRecordBatchReaderBuilder::try_new(bytes.clone()).map_err(|_| Error::Stored)?;
        let rows = usize::try_from(builder.metadata().file_metadata().num_rows())
            .map_err(|_| Error::Stored)?;
        self.rows += rows;
        if self.rows > ROWS {
            return Err(Error::Rows);
        }
        let schema = builder.schema();
        let mut indexes = [0usize; 4];
        for (slot, name) in indexes.iter_mut().zip(COLUMNS) {
            if schema.fields().iter().filter(|f| f.name() == name).count() != 1 {
                return Err(Error::Stored);
            }
            *slot = schema.index_of(name).map_err(|_| Error::Stored)?;
        }
        if schema.field(indexes[0]).data_type() != &DataType::Int64
            || indexes[1..]
                .iter()
                .any(|&i| schema.field(i).data_type() != &DataType::Utf8)
        {
            return Err(Error::Stored);
        }
        // Read the string columns as dictionaries so repeated stream labels
        // share keys instead of being compared byte by byte.
        let mut fields = schema.fields().to_vec();
        for &i in &indexes[1..] {
            fields[i] = Arc::new(
                fields[i]
                    .as_ref()
                    .clone()
                    .with_data_type(DataType::Dictionary(
                        Box::new(DataType::Int32),
                        Box::new(DataType::Utf8),
                    )),
            );
        }
        let read_schema = Arc::new(Schema::new_with_metadata(fields, schema.metadata().clone()));
        let metadata = ArrowReaderMetadata::try_new(
            Arc::clone(builder.metadata()),
            ArrowReaderOptions::new().with_schema(read_schema),
        )
        .map_err(|_| Error::Stored)?;
        let builder = ParquetRecordBatchReaderBuilder::new_with_metadata(bytes, metadata);
        let projection = parquet::arrow::ProjectionMask::roots(builder.parquet_schema(), indexes);
        // Projected columns keep file order; locate each by name.
        let reader = builder
            .with_projection(projection)
            .with_batch_size(1024)
            .build()
            .map_err(|_| Error::Stored)?;
        for batch in reader {
            let batch = batch.map_err(|_| Error::Stored)?;
            let column = |name| batch.column_by_name(name).ok_or(Error::Stored);
            let times = column("timestamp_ns")?
                .as_any()
                .downcast_ref::<Int64Array>()
                .ok_or(Error::Stored)?;
            let service = Column::from(column("service")?.as_ref())?;
            let level = Column::from(column("severity_text")?.as_ref())?;
            let resource = Column::from(column("resource")?.as_ref())?;
            // One verdict per distinct stream identity in this batch.
            let mut seen: HashMap<(i32, i32, i32), ()> = HashMap::new();
            for row in 0..batch.num_rows() {
                self.work += 1;
                if self.work > WORK {
                    return Err(Error::Work);
                }
                if times.is_null(row)
                    || times.value(row) < self.start
                    || times.value(row) > self.end
                {
                    continue;
                }
                let identity = (resource.key(row), service.key(row), level.key(row));
                if seen.insert(identity, ()).is_some() {
                    continue;
                }
                let (r, s, l) = (
                    resource.bytes(identity.0),
                    service.bytes(identity.1),
                    level.bytes(identity.2),
                );
                self.work += self.matchers.len();
                if self.selected(r, s, l) {
                    self.observe(r, s)?;
                }
            }
        }
        Ok(rows)
    }
}

fn quoted(value: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(value.len() + 2);
    crate::json_write::write_str(&mut out, value);
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::query_filter::MatchOp;
    use arrow::array::{Int64Array, StringArray};
    use arrow::datatypes::{Field, Schema};
    use arrow::record_batch::RecordBatch;
    use parquet::arrow::ArrowWriter;

    type Row<'a> = (i64, Option<&'a str>, Option<&'a str>, &'a str);

    fn segment(rows: &[Row<'_>]) -> Bytes {
        let schema = Arc::new(Schema::new(vec![
            Field::new("timestamp_ns", DataType::Int64, true),
            Field::new("severity_text", DataType::Utf8, true),
            Field::new("service", DataType::Utf8, true),
            Field::new("body", DataType::Utf8, true),
            Field::new("resource", DataType::Utf8, false),
        ]));
        let batch = RecordBatch::try_new(
            Arc::clone(&schema),
            vec![
                Arc::new(Int64Array::from_iter_values(rows.iter().map(|r| r.0))),
                Arc::new(StringArray::from_iter(rows.iter().map(|r| r.2))),
                Arc::new(StringArray::from_iter(rows.iter().map(|r| r.1))),
                Arc::new(StringArray::from_iter_values(
                    rows.iter().map(|_| "\"line\""),
                )),
                Arc::new(StringArray::from_iter_values(rows.iter().map(|r| r.3))),
            ],
        )
        .unwrap();
        let mut out = Vec::new();
        let mut writer = ArrowWriter::try_new(&mut out, schema, None).unwrap();
        writer.write(&batch).unwrap();
        writer.close().unwrap();
        Bytes::from(out)
    }

    fn state(mode: Mode, key: &str, matchers: Vec<Matcher>) -> State {
        State {
            mode,
            key: key.as_bytes().to_vec(),
            start: 0,
            end: 100,
            service: None,
            matchers,
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

    fn literal(name: &str, op: MatchOp, value: &str) -> Matcher {
        Matcher::Literal {
            name: name.as_bytes().to_vec(),
            op,
            value: value.as_bytes().to_vec(),
        }
    }

    fn output(state: &State) -> Vec<String> {
        state
            .entries
            .values()
            .map(|v| String::from_utf8(v.clone()).unwrap())
            .collect()
    }

    const ROWS: &[Row<'static>] = &[
        (
            10,
            Some("api"),
            Some("info"),
            r#"{"namespace":"prod","pod":"api-1"}"#,
        ),
        (
            11,
            Some("api"),
            Some("error"),
            r#"{"namespace":"prod","pod":"api-1"}"#,
        ),
        (
            12,
            None,
            None,
            r#"{"namespace":"staging","pod":"web-1","empty":"","n":3}"#,
        ),
        (500, Some("late"), None, r#"{"namespace":"future"}"#),
    ];

    #[test]
    fn names_union_resource_labels_and_promoted_service() {
        let mut s = state(Mode::Names, "", vec![]);
        s.scan(segment(ROWS)).unwrap();
        assert_eq!(
            output(&s),
            [r#""namespace""#, r#""pod""#, r#""service_name""#]
        );
    }

    #[test]
    fn values_respect_time_bounds_and_drop_empty_values() {
        let mut s = state(Mode::Values, "namespace", vec![]);
        s.scan(segment(ROWS)).unwrap();
        assert_eq!(output(&s), [r#""prod""#, r#""staging""#]);
        let mut s = state(Mode::Values, "empty", vec![]);
        s.scan(segment(ROWS)).unwrap();
        assert!(output(&s).is_empty());
    }

    #[test]
    fn series_deduplicate_streams_and_apply_matchers() {
        let mut s = state(
            Mode::Series,
            "",
            vec![literal("namespace", MatchOp::Eq, "prod")],
        );
        s.scan(segment(ROWS)).unwrap();
        assert_eq!(
            output(&s),
            [r#"{"namespace":"prod","pod":"api-1","service_name":"api"}"#]
        );
    }

    #[test]
    fn promoted_service_and_level_mirror_the_log_decoder() {
        let mut s = state(
            Mode::Values,
            "pod",
            vec![literal("level", MatchOp::Eq, "error")],
        );
        s.scan(segment(ROWS)).unwrap();
        assert_eq!(output(&s), [r#""api-1""#]);

        let mut s = state(Mode::Values, "namespace", vec![]);
        s.service = Some(b"api".to_vec());
        s.scan(segment(ROWS)).unwrap();
        assert_eq!(output(&s), [r#""prod""#]);
    }

    #[test]
    fn absent_labels_match_empty_and_regex_matchers() {
        let regex = Matcher::Regex {
            name: b"pod".to_vec(),
            op: MatchOp::Re,
            regex: regex::bytes::Regex::new(r"(?s:\A(?:web-.*)\z)").unwrap(),
        };
        let mut s = state(Mode::Values, "namespace", vec![regex]);
        s.scan(segment(ROWS)).unwrap();
        assert_eq!(output(&s), [r#""staging""#]);

        let mut s = state(
            Mode::Values,
            "namespace",
            vec![literal("service_name", MatchOp::Eq, "")],
        );
        s.scan(segment(ROWS)).unwrap();
        assert_eq!(output(&s), [r#""staging""#]);
    }

    #[test]
    fn entry_budget_fails_whole_instead_of_truncating() {
        let resources: Vec<String> = (0..=ENTRIES)
            .map(|i| format!(r#"{{"pod":"p{i}"}}"#))
            .collect();
        let rows: Vec<Row<'_>> = resources
            .iter()
            .map(|r| (1, None, None, r.as_str()))
            .collect();
        let mut s = state(Mode::Values, "pod", vec![]);
        assert!(matches!(s.scan(segment(&rows)), Err(Error::Budget)));
    }

    #[test]
    fn corrupt_schema_is_a_stored_error() {
        let schema = Arc::new(Schema::new(vec![Field::new(
            "timestamp_ns",
            DataType::Int64,
            true,
        )]));
        let batch = RecordBatch::try_new(
            Arc::clone(&schema),
            vec![Arc::new(Int64Array::from_iter_values([1]))],
        )
        .unwrap();
        let mut out = Vec::new();
        let mut writer = ArrowWriter::try_new(&mut out, schema, None).unwrap();
        writer.write(&batch).unwrap();
        writer.close().unwrap();
        let mut s = state(Mode::Names, "", vec![]);
        assert!(matches!(s.scan(Bytes::from(out)), Err(Error::Stored)));
    }
}
