//! Complete window-local trace grouping, never span top-k before grouping.
//! BEAM owns snapshot/scan/deadline admission. This disposable state retains
//! only bounded aggregates for ALL traces, including not-yet-matching traces.
use crate::json_read::{Parser, RawFields};
use crate::out::Sink;
use arrow::array::{Array, Int64Array, StringArray};
use parquet::arrow::arrow_reader::ParquetRecordBatchReaderBuilder;
use rustler::{Binary, Encoder, Env, ResourceArc, Term};
use std::collections::BTreeMap;
use std::sync::Mutex;

mod atoms {
    rustler::atoms! { ok, error, fallback, query_resource_limit, query_scan_limit, trace_metadata_unknown, trace_group_limit, trace_root_conflict, trace_root_unknown, trace_timestamp_unknown, trace_duration_limit, unsupported_trace_tag_type, trace_discovery_work_limit }
}
#[derive(Debug)]
pub(crate) enum Error {
    Invalid,
    Budget,
    Groups,
    Rows,
    Unknown,
    Root,
    RootUnknown,
    Timestamp,
    Duration,
    UnsupportedTag,
    DiscoveryWork,
}
pub(crate) type Res<T> = Result<T, Error>;
pub(crate) struct Predicate {
    pub(crate) scope: String,
    pub(crate) key: String,
    pub(crate) value: String,
    pub(crate) regex: Option<regex::Regex>,
}
#[derive(Default, Debug)]
struct Summary {
    start: i64,
    end: i64,
    stored: usize,
    matched: usize,
}
struct State {
    start: i64,
    end: i64,
    limit: usize,
    max_groups: usize,
    scanned: usize,
    predicates: Vec<Predicate>,
    traces: BTreeMap<String, Summary>,
}
pub struct Search(Mutex<Option<State>>);
#[rustler::resource_impl]
impl rustler::Resource for Search {}

pub(crate) fn result<'a, T: Encoder>(env: Env<'a>, result: Res<T>) -> Term<'a> {
    match result {
        Ok(value) => (atoms::ok(), value).encode(env),
        Err(Error::Budget) => (atoms::error(), atoms::query_resource_limit()).encode(env),
        Err(Error::DiscoveryWork) => {
            (atoms::error(), atoms::trace_discovery_work_limit()).encode(env)
        }
        Err(Error::Groups) => (atoms::error(), atoms::trace_group_limit()).encode(env),
        Err(Error::Rows) => (atoms::error(), atoms::query_scan_limit()).encode(env),
        Err(Error::Unknown) => (atoms::error(), atoms::trace_metadata_unknown()).encode(env),
        Err(Error::Timestamp) => (atoms::error(), atoms::trace_timestamp_unknown()).encode(env),
        Err(Error::UnsupportedTag) => {
            (atoms::error(), atoms::unsupported_trace_tag_type()).encode(env)
        }
        Err(Error::Duration) => (atoms::error(), atoms::trace_duration_limit()).encode(env),
        Err(Error::Root) => (atoms::error(), atoms::trace_root_conflict()).encode(env),
        Err(Error::RootUnknown) => (atoms::error(), atoms::trace_root_unknown()).encode(env),
        Err(Error::Invalid) => atoms::fallback().encode(env),
    }
}
#[rustler::nif]
fn trace_search_api_version() -> u32 {
    1
}
#[rustler::nif(schedule = "DirtyCpu")]
fn trace_search_new<'a>(
    env: Env<'a>,
    start: i64,
    end: i64,
    predicates: Vec<(String, String, String, String)>,
    limit: usize,
    max_groups: usize,
) -> Term<'a> {
    let build = || {
        if start < 0
            || end < 0
            || !(1..=1000).contains(&limit)
            || !(1..=65_536).contains(&max_groups)
            || !(1..=16).contains(&predicates.len())
        {
            return Err(Error::Invalid);
        }
        let mut regexes = 0;
        let predicates = predicates
            .into_iter()
            .map(|(scope, key, op, value)| {
                if !matches!(scope.as_str(), "resource" | "span")
                    || key.is_empty()
                    || key.len() > 256
                    || value.len() > 4096
                    || value.contains("${")
                {
                    return Err(Error::Invalid);
                }
                let regex = match op.as_str() {
                    "=" => None,
                    "=~" if value.len() <= 1024 => {
                        regexes += 1;
                        if regexes > 8 {
                            return Err(Error::Invalid);
                        }
                        Some(crate::query_regex::anchored(&value).map_err(|_| Error::Invalid)?)
                    }
                    _ => return Err(Error::Invalid),
                };
                Ok(Predicate {
                    scope,
                    key,
                    value,
                    regex,
                })
            })
            .collect::<Res<Vec<_>>>()?;
        Ok(ResourceArc::new(Search(Mutex::new(Some(State {
            start,
            end,
            limit,
            max_groups,
            scanned: 0,
            predicates,
            traces: BTreeMap::new(),
        })))))
    };
    result(env, build())
}
#[rustler::nif(schedule = "DirtyCpu")]
fn trace_search_add<'a>(env: Env<'a>, search: ResourceArc<Search>, blob: Binary<'a>) -> Term<'a> {
    let add = || {
        let mut lock = search.0.try_lock().map_err(|_| Error::Budget)?;
        let state = lock.as_mut().ok_or(Error::Invalid)?;
        let added = state.scan(blob);
        if added.is_err() {
            *lock = None;
        }
        added
    };
    result(env, add())
}
#[rustler::nif(schedule = "DirtyCpu")]
fn trace_search_finish<'a>(env: Env<'a>, search: ResourceArc<Search>) -> Term<'a> {
    let finish = || {
        let state = search
            .0
            .try_lock()
            .map_err(|_| Error::Budget)?
            .take()
            .ok_or(Error::Invalid)?;
        let mut out = crate::out::BinSink::with_capacity(4096);
        state.write(&mut out);
        Ok(out.finish(env))
    };
    result(env, finish())
}
pub(crate) fn object(raw: &[u8]) -> Res<RawFields<'_>> {
    let mut parser = Parser::new(raw);
    let fields = parser.raw_object().map_err(|_| Error::Invalid)?;
    parser.ws();
    parser.end().map_err(|_| Error::Invalid)?;
    Ok(fields)
}
pub(crate) fn field<'a>(fields: &RawFields<'a>, name: &[u8]) -> Res<&'a [u8]> {
    let mut values = fields.iter().filter(|(key, _)| key.as_ref() == name);
    let value = values
        .next()
        .map(|(_, value)| *value)
        .ok_or(Error::Invalid)?;
    if values.next().is_some() {
        return Err(Error::Invalid);
    }
    Ok(value)
}
pub(crate) fn string(raw: &[u8]) -> Res<String> {
    let mut parser = Parser::new(raw);
    let value = parser.string().map_err(|_| Error::Invalid)?;
    parser.ws();
    parser.end().map_err(|_| Error::Invalid)?;
    String::from_utf8(value.into_owned()).map_err(|_| Error::Invalid)
}
pub(crate) fn typed_attributes(raw: &[u8]) -> Res<BTreeMap<String, String>> {
    let mut parser = Parser::new(raw);
    let mut values = BTreeMap::new();
    for pair in parser.raw_array().map_err(|_| Error::Invalid)? {
        let pair = object(pair)?;
        let key = string(field(&pair, b"key")?)?;
        let value = object(field(&pair, b"value")?)?;
        if let Ok(raw) = field(&value, b"stringValue") {
            values.insert(key, string(raw)?);
        }
    }
    Ok(values)
}
impl State {
    fn observe(&mut self, id: &str, start: i64, end: i64, payload: &[u8]) -> Res<()> {
        if payload.len() > 16_777_216 {
            return Err(Error::Budget);
        }
        if id.len() != 32
            || !id
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
            || id.bytes().all(|b| b == b'0')
            || start < 0
            || end < start
        {
            return Err(Error::Invalid);
        }
        crate::trace_metadata::validate(payload).map_err(|_| Error::Invalid)?;
        let fields = object(payload)?;
        if string(field(&fields, b"trace_id")?)? != id {
            return Err(Error::Invalid);
        }
        for (name, expected) in [
            (b"timestamp_ns".as_slice(), start),
            (b"end_timestamp_ns", end),
        ] {
            let raw = field(&fields, name)?;
            let actual: i64 = std::str::from_utf8(raw)
                .map_err(|_| Error::Invalid)?
                .parse()
                .map_err(|_| Error::Invalid)?;
            if actual != expected {
                return Err(Error::Invalid);
            }
        }
        let metadata = match field(&fields, b"otlp") {
            Ok(raw) if raw != b"null" => object(raw)?,
            _ => return Err(Error::Unknown),
        };
        // Only original string values enter the predicate dictionaries. Bytes
        // with identical projected base64 text never become strings here.
        let resource = typed_attributes(field(&metadata, b"resource")?)?;
        let span = typed_attributes(field(&metadata, b"attributes")?)?;
        let matched = self.predicates.iter().all(|p| {
            let attrs = if p.scope == "resource" {
                &resource
            } else {
                &span
            };
            attrs
                .get(&p.key)
                .is_some_and(|v| p.regex.as_ref().map_or(v == &p.value, |r| r.is_match(v)))
        });
        if !self.traces.contains_key(id) && self.traces.len() == self.max_groups {
            return Err(Error::Groups);
        }
        let summary = self.traces.entry(id.to_owned()).or_insert(Summary {
            start,
            end,
            ..Default::default()
        });
        summary.start = summary.start.min(start);
        summary.end = summary.end.max(end);
        summary.stored = summary.stored.checked_add(1).ok_or(Error::Budget)?;
        summary.matched = summary
            .matched
            .checked_add(usize::from(matched))
            .ok_or(Error::Budget)?;
        Ok(())
    }
    fn scan(&mut self, blob: Binary<'_>) -> Res<usize> {
        let reader =
            ParquetRecordBatchReaderBuilder::try_new(crate::erlang_bytes::from_binary(blob))
                .map_err(|_| Error::Invalid)?
                .with_batch_size(1024)
                .build()
                .map_err(|_| Error::Invalid)?;
        let mut rows = 0;
        for batch in reader {
            let batch = batch.map_err(|_| Error::Invalid)?;
            let ints = ["timestamp_ns", "end_timestamp_ns"].map(|name| {
                batch
                    .column_by_name(name)
                    .and_then(|c| c.as_any().downcast_ref::<Int64Array>())
                    .ok_or(Error::Invalid)
            });
            let [start, end] = ints;
            let (start, end) = (start?, end?);
            let strings = ["trace_id", "payload"].map(|name| {
                batch
                    .column_by_name(name)
                    .and_then(|c| c.as_any().downcast_ref::<StringArray>())
                    .ok_or(Error::Invalid)
            });
            let [ids, payloads] = strings;
            let (ids, payloads) = (ids?, payloads?);
            for i in 0..batch.num_rows() {
                if start.is_null(i) || end.is_null(i) || ids.is_null(i) || payloads.is_null(i) {
                    return Err(Error::Invalid);
                }
                rows += 1;
                self.scanned = self.scanned.checked_add(1).ok_or(Error::Budget)?;
                if self.scanned > 1_000_000 {
                    return Err(Error::Rows);
                }
                let ts = start.value(i);
                if ts >= self.start && ts <= self.end {
                    self.observe(ids.value(i), ts, end.value(i), payloads.value(i).as_bytes())?;
                }
            }
        }
        Ok(rows)
    }
    fn write(self, out: &mut impl Sink) {
        let mut rows: Vec<_> = self.traces.iter().filter(|(_, s)| s.matched > 0).collect();
        rows.sort_by(|(id_a, a), (id_b, b)| b.start.cmp(&a.start).then_with(|| id_a.cmp(id_b)));
        out.extend(format!("{{\"coverage\":\"window_stored_spans\",\"effective_start_ts_ns\":{},\"end_ts_ns\":{},\"matched_trace_count\":{},\"traces\":[", self.start, self.end, rows.len()).as_bytes());
        for (index, (id, s)) in rows.into_iter().take(self.limit).enumerate() {
            if index > 0 {
                out.push(b',');
            }
            // Fixed hex IDs and integer aggregates bound output well below
            // 1 MiB at the fixed 1,000-trace maximum. No payload expansion.
            out.extend(format!("{{\"trace_id\":\"{id}\",\"start_timestamp_ns\":{},\"end_timestamp_ns\":{},\"duration_ns\":{},\"stored_span_count\":{},\"matching_span_count\":{}}}", s.start, s.end, s.end - s.start, s.stored, s.matched).as_bytes());
        }
        out.extend(b"]}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn state(max_groups: usize) -> State {
        State {
            start: 0,
            end: 1000,
            limit: 1,
            max_groups,
            scanned: 0,
            predicates: vec![Predicate {
                scope: "resource".into(),
                key: "env".into(),
                value: "prod".into(),
                regex: None,
            }],
            traces: BTreeMap::new(),
        }
    }
    fn payload(id: &str, start: i64, end: i64, value: &str) -> Vec<u8> {
        format!(r#"{{"trace_id":"{id}","timestamp_ns":{start},"end_timestamp_ns":{end},"events":[],"links":[],"otlp":{{"version":1,"resource":[{{"key":"env","value":{value}}}],"scope":[],"attributes":[],"events":[],"links":[]}}}}"#).into_bytes()
    }
    #[test]
    fn groups_every_span_before_limit_and_uses_nonmatching_context() {
        let mut s = state(10);
        let a = "00000000000000000000000000000001";
        let b = "00000000000000000000000000000002";
        s.observe(
            a,
            900,
            950,
            &payload(a, 900, 950, r#"{"stringValue":"prod"}"#),
        )
        .unwrap();
        s.observe(
            b,
            500,
            700,
            &payload(b, 500, 700, r#"{"stringValue":"prod"}"#),
        )
        .unwrap();
        s.observe(
            a,
            100,
            200,
            &payload(a, 100, 200, r#"{"stringValue":"other"}"#),
        )
        .unwrap();
        let mut out = Vec::new();
        s.write(&mut out);
        let out = String::from_utf8(out).unwrap();
        assert!(out.contains(b));
        assert!(!out.contains(a));
        assert!(out.contains("\"matched_trace_count\":2"));
    }
    #[test]
    fn types_and_unknown_metadata_never_guess_from_projection() {
        let mut s = state(2);
        let id = "00000000000000000000000000000001";
        s.observe(id, 1, 2, &payload(id, 1, 2, r#"{"bytesValue":"cHJvZA=="}"#))
            .unwrap();
        assert_eq!(s.traces[id].matched, 0);
        let legacy = format!(r#"{{"trace_id":"{id}","timestamp_ns":1,"end_timestamp_ns":2}}"#);
        assert!(matches!(
            s.observe(id, 1, 2, legacy.as_bytes()),
            Err(Error::Unknown)
        ));
    }
    #[test]
    fn groups_budget_counts_unmatched_traces_too() {
        let mut s = state(1);
        let a = "00000000000000000000000000000001";
        let b = "00000000000000000000000000000002";
        s.observe(a, 1, 2, &payload(a, 1, 2, r#"{"stringValue":"other"}"#))
            .unwrap();
        assert!(matches!(
            s.observe(b, 1, 2, &payload(b, 1, 2, r#"{"stringValue":"prod"}"#)),
            Err(Error::Groups)
        ));
    }
}
