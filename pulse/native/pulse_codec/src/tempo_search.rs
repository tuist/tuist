//! Tempo-compatible single-spanset search over a complete retained snapshot.
//! No time pruning or span top-k precedes aggregation. The caller may discover
//! candidates in a proven or newest-first subset of sources first, then recover
//! all ID-selected context.
//! All input objects, groups, retained strings/samples and rendered bytes are
//! independently bounded. Legacy uncertainty is checked AFTER trace overlap.
use crate::json_read::Parser;
use crate::out::{Counter, Sink};
use crate::trace_search::{field, object, result, string, typed_attributes, Error, Predicate, Res};
use arrow::array::{Array, Int64Array, StringArray};
use parquet::arrow::arrow_reader::ParquetRecordBatchReaderBuilder;
use rustler::{Binary, Env, ResourceArc, Term};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Mutex;
const MAX: usize = 16_777_216;
const INPUT_MAX: usize = 33_554_432;
#[derive(Default)]
struct Summary {
    start: i64,
    end: i64,
    unknown: bool,
    root_conflict: bool,
    root: Option<(String, String)>,
    matched: usize,
    services: BTreeMap<String, (usize, usize)>,
    samples: Vec<Sample>,
    root_id: Option<String>,
    root_service_known: bool,
    root_flags: BTreeMap<String, bool>,
    // Structural queries resolve matches once the trace's context is complete.
    links: Vec<Link>,
}
struct Link {
    id: u64,
    parent: Option<u64>,
    mask: u8,
    start: i64,
    sample: Option<Vec<u8>>,
}
struct RootQuery {
    service: bool,
    duration: bool,
    window: Option<(i64, i64)>,
    work: usize,
}
struct Sample {
    start: i64,
    id: String,
    json: Vec<u8>,
}
#[derive(Default)]
struct State {
    roots: Option<RootQuery>,
    floor: i64,
    start: i64,
    end: i64,
    limit: usize,
    spss: usize,
    scanned: usize,
    replayed: usize,
    context_phase: bool,
    plan_hashes: Option<Vec<u64>>,
    plan_probes: usize,
    unplanned: bool,
    retained: usize,
    predicates: Vec<Predicate>,
    expression: Option<crate::tempo_expression::Expression>,
    expression_work: usize,
    candidates: BTreeSet<String>,
    blobs: Vec<(bytes::Bytes, bool, usize)>,
    input_bytes: usize,
    input_segments: usize,
    traces: BTreeMap<String, Summary>,
}
pub struct Search(Mutex<Option<State>>);
#[rustler::resource_impl]
impl rustler::Resource for Search {}
pub(crate) fn predicates(input: Vec<(String, String, String, String)>) -> Res<Vec<Predicate>> {
    if !(1..=16).contains(&input.len()) {
        return Err(Error::Invalid);
    }
    let mut regexes = 0;
    input
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
        .collect()
}
#[rustler::nif]
fn tempo_search_api_version() -> u32 {
    7
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_search_new<'a>(
    env: Env<'a>,
    floor: i64,
    start: i64,
    end: i64,
    input: Vec<(String, String, String, String)>,
    limit: usize,
    spss: usize,
) -> Term<'a> {
    result(
        env,
        (|| new_search(floor, start, end, limit, spss, predicates(input)?, None))(),
    )
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_expression_search_new<'a>(
    env: Env<'a>,
    floor: i64,
    start: i64,
    end: i64,
    program: Vec<(String, String, String, String)>,
    limit: usize,
    spss: usize,
) -> Term<'a> {
    result(
        env,
        (|| {
            let expression =
                crate::tempo_expression::Expression::compile(program).ok_or(Error::Invalid)?;
            new_search(floor, start, end, limit, spss, Vec::new(), Some(expression))
        })(),
    )
}
fn new_search(
    floor: i64,
    start: i64,
    end: i64,
    limit: usize,
    spss: usize,
    predicates: Vec<Predicate>,
    expression: Option<crate::tempo_expression::Expression>,
) -> Res<ResourceArc<Search>> {
    if floor < 0
        || start < 0
        || end < start
        || !(1..=1000).contains(&limit)
        || !(1..=100).contains(&spss)
    {
        return Err(Error::Invalid);
    }
    Ok(ResourceArc::new(Search(Mutex::new(Some(State {
        floor,
        start,
        end,
        limit,
        spss,
        predicates,
        expression,
        ..Default::default()
    })))))
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_root_discovery_new<'a>(
    env: Env<'a>,
    floor: i64,
    key: String,
    input: Vec<(String, String, String, String)>,
    start: i64,
    end: i64,
) -> Term<'a> {
    context_discovery_new(env, floor, key, input, (start, end), false)
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_trace_duration_discovery_new<'a>(
    env: Env<'a>,
    floor: i64,
    input: Vec<(String, String, String, String)>,
    start: i64,
    end: i64,
) -> Term<'a> {
    context_discovery_new(
        env,
        floor,
        "trace:duration".into(),
        input,
        (start, end),
        true,
    )
}
fn context_discovery_new<'a>(
    env: Env<'a>,
    floor: i64,
    key: String,
    input: Vec<(String, String, String, String)>,
    window: (i64, i64),
    duration: bool,
) -> Term<'a> {
    let (start, end) = window;
    result(
        env,
        (|| {
            let service = match (key.as_str(), duration) {
                ("rootName" | "trace:rootName", false) => false,
                ("rootServiceName" | "trace:rootService", false) => true,
                ("trace:duration", true) => false,
                _ => return Err(Error::Invalid),
            };
            if floor < 0 || start < 0 || end < start || (start == 0 && end != 0) {
                return Err(Error::Invalid);
            }
            let window = if start == 0 { None } else { Some((start, end)) };
            let predicates = if input.is_empty() {
                Vec::new()
            } else {
                predicates(input)?
            };
            Ok(ResourceArc::new(Search(Mutex::new(Some(State {
                floor,
                predicates,
                roots: Some(RootQuery {
                    service,
                    duration,
                    window,
                    work: 0,
                }),
                ..Default::default()
            })))))
        })(),
    )
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_root_discovery_finish<'a>(env: Env<'a>, search: ResourceArc<Search>) -> Term<'a> {
    context_discovery_finish(env, search, false)
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_trace_duration_discovery_finish<'a>(
    env: Env<'a>,
    search: ResourceArc<Search>,
) -> Term<'a> {
    context_discovery_finish(env, search, true)
}
fn context_discovery_finish<'a>(
    env: Env<'a>,
    search: ResourceArc<Search>,
    duration: bool,
) -> Term<'a> {
    result(
        env,
        (|| {
            let mut state = search
                .0
                .try_lock()
                .map_err(|_| Error::Budget)?
                .take()
                .ok_or(Error::Invalid)?;
            if state.roots.as_ref().ok_or(Error::Invalid)?.duration != duration {
                return Err(Error::Invalid);
            }
            state.assemble_candidates()?;
            state.root_dictionary(env)
        })(),
    )
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_search_add<'a>(env: Env<'a>, search: ResourceArc<Search>, blob: Binary<'a>) -> Term<'a> {
    result(
        env,
        (|| {
            let mut lock = search.0.try_lock().map_err(|_| Error::Budget)?;
            let state = lock.as_mut().ok_or(Error::Invalid)?;
            let answer = state.capture(blob, false);
            if answer.is_err() {
                *lock = None;
            }
            answer
        })(),
    )
}
// Context from a source the plan did not prune but has not discovered yet: an
// older candidate beyond a newest-first window. Its rows of sealed candidates
// join their traces; other potentially matching rows belong to traces the
// caller proves start before the window's kth trace, so they are not errors.
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_search_add_unplanned<'a>(
    env: Env<'a>,
    search: ResourceArc<Search>,
    blob: Binary<'a>,
) -> Term<'a> {
    result(
        env,
        (|| {
            let mut lock = search.0.try_lock().map_err(|_| Error::Budget)?;
            let state = lock.as_mut().ok_or(Error::Invalid)?;
            let answer = if state.context_phase && state.roots.is_none() {
                state.capture(blob, true)
            } else {
                Err(Error::Invalid)
            };
            if answer.is_err() {
                *lock = None;
            }
            answer
        })(),
    )
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_search_plan_seal<'a>(env: Env<'a>, search: ResourceArc<Search>) -> Term<'a> {
    result(
        env,
        (|| {
            let mut lock = search.0.try_lock().map_err(|_| Error::Budget)?;
            let state = lock.as_mut().ok_or(Error::Invalid)?;
            let answer = (|| {
                if state.context_phase {
                    return Err(Error::Invalid);
                }
                state.assemble_candidates()?;
                state.context_phase = true;
                let mut output = rustler::NewBinary::new(env, state.candidates.len() * 32);
                for (slot, id) in output
                    .as_mut_slice()
                    .as_chunks_mut::<32>()
                    .0
                    .iter_mut()
                    .zip(&state.candidates)
                {
                    slot.copy_from_slice(id.as_bytes());
                }
                Ok::<Binary<'a>, Error>(output.into())
            })();
            if answer.is_err() {
                *lock = None;
            }
            answer
        })(),
    )
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_search_plan_hashes<'a>(
    env: Env<'a>,
    search: ResourceArc<Search>,
    hashes: Binary<'a>,
) -> Term<'a> {
    result(
        env,
        (|| {
            let mut lock = search.0.try_lock().map_err(|_| Error::Budget)?;
            let state = lock.as_mut().ok_or(Error::Invalid)?;
            if !state.context_phase
                || state.plan_hashes.is_some()
                || hashes.len() != state.candidates.len() * 8
            {
                *lock = None;
                return Err(Error::Invalid);
            }
            let mut prefixes: Vec<_> = hashes
                .as_slice()
                .as_chunks::<8>()
                .0
                .iter()
                .map(|b| u64::from_be_bytes(*b))
                .collect();
            prefixes.sort_unstable();
            prefixes.dedup();
            state.plan_hashes = Some(prefixes);
            Ok(true)
        })(),
    )
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_search_plan_may_match<'a>(
    env: Env<'a>,
    search: ResourceArc<Search>,
    hashes: Option<Binary<'a>>,
    bits: Option<Binary<'a>>,
) -> Term<'a> {
    result(
        env,
        (|| {
            let mut lock = search.0.try_lock().map_err(|_| Error::Budget)?;
            let state = lock.as_mut().ok_or(Error::Invalid)?;
            if !state.context_phase {
                *lock = None;
                return Err(Error::Invalid);
            }
            Ok(state.context_may_match(hashes.map(|b| b.as_slice()), bits.map(|b| b.as_slice())))
        })(),
    )
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_search_abort(search: ResourceArc<Search>) -> rustler::Atom {
    match search.0.try_lock() {
        Ok(mut lock) => {
            *lock = None;
            crate::atoms::ok()
        }
        Err(_) => crate::atoms::fallback(),
    }
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_search_finish<'a>(env: Env<'a>, search: ResourceArc<Search>) -> Term<'a> {
    result(env, finish(env, search).map(|(body, _kth)| body))
}
// Also the start of the `limit`th selected trace, when `limit` were selected:
// a newest-first caller may stop once every unread candidate ends before it.
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_search_finish_window<'a>(env: Env<'a>, search: ResourceArc<Search>) -> Term<'a> {
    result(env, finish(env, search))
}
fn finish<'a>(env: Env<'a>, search: ResourceArc<Search>) -> Res<(Binary<'a>, Option<i64>)> {
    let mut state = search
        .0
        .try_lock()
        .map_err(|_| Error::Budget)?
        .take()
        .ok_or(Error::Invalid)?;
    if state.roots.is_some() {
        return Err(Error::Invalid);
    }
    state.assemble_candidates()?;
    state.resolve_links()?;
    let rows = state.selected()?;
    let kth = (rows.len() == state.limit)
        .then(|| rows.last().map(|(_, s)| s.start))
        .flatten();
    let mut count = Counter::new(MAX);
    state.write(&mut count, &rows);
    if count.len() > MAX {
        return Err(Error::Budget);
    }
    let mut out = crate::out::BinSink::with_capacity(count.len());
    state.write(&mut out, &rows);
    Ok((out.finish(env), kth))
}
pub(crate) fn matches(
    predicates: &[Predicate],
    resource: &BTreeMap<String, String>,
    span: &BTreeMap<String, String>,
) -> bool {
    predicates.iter().all(|p| {
        let attrs = if p.scope == "resource" {
            resource
        } else {
            span
        };
        attrs
            .get(&p.key)
            .is_some_and(|v| p.regex.as_ref().map_or(v == &p.value, |r| r.is_match(v)))
    })
}
pub(crate) fn integer(raw: &[u8]) -> Res<i64> {
    std::str::from_utf8(raw)
        .map_err(|_| Error::Invalid)?
        .parse()
        .map_err(|_| Error::Invalid)
}
fn valid_id(id: &str, width: usize) -> bool {
    id.len() == width
        && id
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        && id.bytes().any(|b| b != b'0')
}
fn has_child_link(metadata: &crate::json_read::RawFields<'_>) -> Res<bool> {
    let mut p = Parser::new(field(metadata, b"links")?);
    for attrs in p.raw_array().map_err(|_| Error::Invalid)? {
        if typed_attributes(attrs)?
            .get("opentracing.ref_type")
            .is_some_and(|v| v == "child_of")
        {
            return Ok(true);
        }
    }
    Ok(false)
}
fn sample(
    out: &mut impl Sink,
    start: i64,
    end: i64,
    id: &str,
    attrs: &crate::tempo_expression::Attributes,
) {
    out.extend(b"{\"spanID\":");
    crate::json_write::write_str(out, id.as_bytes());
    out.extend(format!(",\"startTimeUnixNano\":\"{start}\"").as_bytes());
    if end > start {
        out.extend(format!(",\"durationNanos\":\"{}\"", end - start).as_bytes());
    }
    if !attrs.is_empty() {
        out.extend(b",\"attributes\":[");
        for (i, ((key, _scope), value)) in attrs.iter().enumerate() {
            if i > 0 {
                out.push(b',');
            }
            out.extend(b"{\"key\":");
            crate::json_write::write_str(out, key.as_bytes());
            out.extend(b",\"value\":");
            out.extend(value);
            out.push(b'}');
        }
        out.push(b']');
    }
    out.push(b'}');
}
pub(crate) fn validate_row<'a>(
    id: &str,
    start: i64,
    end: i64,
    payload: &'a [u8],
) -> Res<crate::json_read::RawFields<'a>> {
    if payload.len() > MAX {
        return Err(Error::Budget);
    }
    let fields = crate::trace_metadata::validated_fields(payload).map_err(|_| Error::Invalid)?;
    validate_fields(id, start, end, &fields)?;
    Ok(fields)
}
/// `validate_row/4` for an Arrow string value, plus the typed envelope's
/// members.
pub(crate) fn validate_row_parts<'a>(
    id: &str,
    start: i64,
    end: i64,
    payload: &'a str,
) -> Res<crate::trace_metadata::Parts<'a>> {
    if payload.len() > MAX {
        return Err(Error::Budget);
    }
    let parts = crate::trace_metadata::validated_parts_utf8(payload).map_err(|_| Error::Invalid)?;
    validate_fields(id, start, end, &parts.0)?;
    Ok(parts)
}
// The caller must already have validated the typed envelope.
pub(crate) fn validate_fields(
    id: &str,
    start: i64,
    end: i64,
    fields: &crate::json_read::RawFields<'_>,
) -> Res<()> {
    if !valid_id(id, 32) || start < 0 || end < start {
        return Err(Error::Invalid);
    }
    if string(field(fields, b"trace_id")?)? != id
        || integer(field(fields, b"timestamp_ns")?)? != start
        || integer(field(fields, b"end_timestamp_ns")?)? != end
    {
        return Err(Error::Invalid);
    }
    // Whole-context metadata must not silently consume corrupt nonmatching
    // headers as valid counts or a fabricated missing root.
    if !valid_id(&string(field(fields, b"span_id")?)?, 16) {
        return Err(Error::Invalid);
    }
    let parent = field(fields, b"parent_span_id")?;
    if parent != b"null" && !valid_id(&string(parent)?, 16) {
        return Err(Error::Invalid);
    }
    string(field(fields, b"name")?)?;
    if !(0..=5).contains(&integer(field(fields, b"kind")?)?)
        || !(0..=i64::from(u32::MAX)).contains(&integer(field(fields, b"flags")?)?)
    {
        return Err(Error::Invalid);
    }
    let status = object(field(fields, b"status")?)?;
    if !(0..=2).contains(&integer(field(&status, b"code")?)?) {
        return Err(Error::Invalid);
    }
    Ok(())
}
impl State {
    fn observe(
        &mut self,
        id: &str,
        start: i64,
        end: i64,
        fields: &crate::json_read::RawFields<'_>,
    ) -> Res<()> {
        if !self.traces.contains_key(id) {
            if self.traces.len() == 65_536 {
                return Err(Error::Groups);
            }
            if self.roots.as_ref().is_some_and(|q| q.duration) {
                self.retained += id.len() + 48;
                if self.retained > MAX {
                    return Err(Error::Budget);
                }
            }
        }
        let summary = self.traces.entry(id.to_owned()).or_insert_with(|| Summary {
            start,
            end,
            ..Default::default()
        });
        summary.start = summary.start.min(start);
        summary.end = summary.end.max(end);
        let metadata = match field(fields, b"otlp") {
            Ok(raw) if raw != b"null" => object(raw)?,
            _ => {
                summary.unknown = true;
                return Ok(());
            }
        };
        if self.roots.as_ref().is_some_and(|q| q.duration) {
            // Duration needs complete bounds, not roots, services or samples.
            // The new-trace insertion above charges its summary exactly once.
            return Ok(());
        }
        let resource = typed_attributes(field(&metadata, b"resource")?)?;
        let span = typed_attributes(field(&metadata, b"attributes")?)?;
        let service = resource.get("service.name").cloned().unwrap_or_default();
        if self.roots.is_none() {
            if !summary.services.contains_key(&service) {
                self.retained += service.len() + 32;
            }
            let stats = summary.services.entry(service.clone()).or_default();
            stats.0 += 1;
            let status = object(field(fields, b"status")?)?;
            if integer(field(&status, b"code")?)? == 2 {
                stats.1 += 1;
            }
        }
        let root_candidate =
            field(fields, b"parent_span_id")? == b"null" && !has_child_link(&metadata)?;
        if self.roots.is_some() {
            let sid = string(field(fields, b"span_id")?)?;
            match summary.root_flags.insert(sid.clone(), root_candidate) {
                Some(previous) if previous != root_candidate => summary.root_conflict = true,
                None => self.retained += sid.len() + 64,
                _ => {}
            }
            if root_candidate {
                if summary
                    .root_id
                    .as_ref()
                    .is_some_and(|previous| previous != &sid)
                {
                    summary.root_conflict = true;
                } else if summary.root_id.is_none() {
                    self.retained += sid.len() + 32;
                    summary.root_id = Some(sid);
                }
            }
        }
        if root_candidate {
            let known = resource.contains_key("service.name");
            let root = (service, string(field(fields, b"name")?)?);
            match &summary.root {
                Some(previous) => {
                    if previous != &root {
                        summary.root_conflict = true;
                    }
                    summary.root_service_known &= known;
                }
                None => {
                    self.retained += root.0.len() + root.1.len() + 32;
                    summary.root = Some(root);
                    summary.root_service_known = known;
                }
            }
        }
        if self
            .expression
            .as_ref()
            .is_some_and(|e| !e.relations().is_empty())
        {
            return self.observe_link(id, start, end, fields);
        }
        let collect = if self.expression.is_some() {
            let sid = string(field(fields, b"span_id")?)?;
            summary.samples.len() < self.spss
                || summary
                    .samples
                    .last()
                    .is_some_and(|s| (start, sid.as_str()) < (s.start, s.id.as_str()))
        } else {
            false
        };
        let evaluation = self
            .expression
            .as_ref()
            .map(|e| e.evaluate(fields, &mut self.expression_work, collect))
            .transpose()?;
        let matched = evaluation.as_ref().map_or_else(
            || matches(&self.predicates, &resource, &span),
            |e| e.matched,
        );
        if matched {
            summary.matched += 1;
            let sid = string(field(fields, b"span_id")?)?;
            if !valid_id(&sid, 16) {
                return Err(Error::Invalid);
            }
            // Sampling is deterministic and object/partition-order independent.
            // Tempo's arbitrary first SPSS rows are not a completeness boundary.
            let position = summary
                .samples
                .partition_point(|s| (s.start, s.id.as_str()) <= (start, sid.as_str()));
            if position < self.spss {
                let mut attrs = evaluation.map_or_else(BTreeMap::new, |e| e.attributes);
                for p in &self.predicates {
                    let dictionary = if p.scope == "resource" {
                        &resource
                    } else {
                        &span
                    };
                    let mut value = b"{\"stringValue\":".to_vec();
                    crate::json_write::write_str(&mut value, dictionary[&p.key].as_bytes());
                    value.push(b'}');
                    attrs.insert((p.key.clone(), p.scope.clone()), value);
                }
                let mut count = Counter::new(MAX);
                sample(&mut count, start, end, &sid, &attrs);
                if count.len() > MAX {
                    return Err(Error::Budget);
                }
                let mut json = Vec::with_capacity(count.len());
                sample(&mut json, start, end, &sid, &attrs);
                self.retained += json.len() + sid.len() + 32;
                summary.samples.insert(
                    position,
                    Sample {
                        start,
                        id: sid,
                        json,
                    },
                );
                if summary.samples.len() > self.spss {
                    let discarded = summary.samples.pop().unwrap();
                    self.retained -= discarded.json.len() + discarded.id.len() + 32;
                }
            }
        }
        if self.retained > MAX {
            return Err(Error::Budget);
        }
        Ok(())
    }
    // Every retained span of a candidate trace with its spanset mask; samples
    // only for spans of the last spanset, which a structural query returns.
    fn observe_link(
        &mut self,
        id: &str,
        start: i64,
        end: i64,
        fields: &crate::json_read::RawFields<'_>,
    ) -> Res<()> {
        let expression = self.expression.as_ref().ok_or(Error::Invalid)?;
        let evaluation = expression.evaluate(fields, &mut self.expression_work, true)?;
        let sid = string(field(fields, b"span_id")?)?;
        let span = u64::from_str_radix(&sid, 16).map_err(|_| Error::Invalid)?;
        let parent = match field(fields, b"parent_span_id")? {
            b"null" => None,
            raw => Some(u64::from_str_radix(&string(raw)?, 16).map_err(|_| Error::Invalid)?),
        };
        let sample = if evaluation.matched {
            let mut json = Vec::new();
            sample(&mut json, start, end, &sid, &evaluation.attributes);
            if json.len() > MAX {
                return Err(Error::Budget);
            }
            Some(json)
        } else {
            None
        };
        self.retained += 48 + sample.as_ref().map_or(0, Vec::len);
        if self.retained > MAX {
            return Err(Error::Budget);
        }
        self.traces
            .get_mut(id)
            .ok_or(Error::Invalid)?
            .links
            .push(Link {
                id: span,
                parent,
                mask: evaluation.mask,
                start,
                sample,
            });
        Ok(())
    }
    // Structural matches need every retained span of a trace: resolve them
    // once all context is observed, before overlap, ordering and limits.
    fn resolve_links(&mut self) -> Res<()> {
        let Some(expression) = &self.expression else {
            return Ok(());
        };
        let relations = expression.relations();
        if relations.is_empty() {
            return Ok(());
        }
        for summary in self.traces.values_mut() {
            let links = std::mem::take(&mut summary.links);
            if links.is_empty() {
                continue;
            }
            self.expression_work = links
                .len()
                .checked_mul(relations.len())
                .and_then(|units| self.expression_work.checked_add(units))
                .ok_or(Error::Budget)?;
            if self.expression_work > crate::tempo_expression::WORK_MAX {
                return Err(Error::Budget);
            }
            let spans: Vec<_> = links.iter().map(|l| (l.id, l.parent, l.mask)).collect();
            let kept = crate::tempo_expression::structural(relations, &spans);
            let mut samples = Vec::new();
            for (link, kept) in links.into_iter().zip(kept) {
                if kept {
                    summary.matched += 1;
                    samples.push(Sample {
                        start: link.start,
                        id: format!("{:016x}", link.id),
                        json: link.sample.ok_or(Error::Invalid)?,
                    });
                }
            }
            samples.sort_by(|a, b| (a.start, &a.id).cmp(&(b.start, &b.id)));
            samples.truncate(self.spss);
            summary.samples = samples;
        }
        Ok(())
    }
    fn capture(&mut self, blob: Binary<'_>, unplanned: bool) -> Res<usize> {
        self.input_bytes = self
            .input_bytes
            .checked_add(blob.len())
            .ok_or(Error::Budget)?;
        if self.input_bytes > INPUT_MAX || self.input_segments >= 1024 {
            return Err(Error::Budget);
        }
        self.input_segments += 1;
        let blob = crate::erlang_bytes::from_binary(blob);
        if self.context_phase {
            self.unplanned = unplanned;
            let rows = self.scan(blob, false, true);
            self.unplanned = false;
            return rows;
        }
        let window = self.roots.as_ref().and_then(|q| q.window);
        let header = window
            .map(|window| {
                crate::tempo_discovery::source_window_selection(blob.clone(), self.floor, window)
            })
            .transpose()?;
        let selected = header.is_none_or(|(selected, _)| selected);
        let rows = if selected {
            let rows = self.scan(blob.clone(), true, true)?;
            if header.is_some_and(|(_, expected)| expected != rows) {
                return Err(Error::Invalid);
            }
            rows
        } else {
            let rows = header.ok_or(Error::Invalid)?.1;
            self.scanned += rows;
            if self.scanned > 1_000_000 {
                return Err(Error::Rows);
            }
            rows
        };
        self.blobs.push((blob, selected, rows));
        Ok(rows)
    }
    fn context_may_match(&mut self, hashes: Option<&[u8]>, bits: Option<&[u8]>) -> bool {
        let Some(candidates) = &self.plan_hashes else {
            return true;
        };
        if candidates.is_empty() {
            return false;
        }
        // Exhausting optional index planning reads all remaining sources;
        // it never truncates candidates/context or invents a negative match.
        if self.plan_probes >= 2_000_000 {
            return true;
        }
        if let Some(hashes) =
            hashes.filter(|h| !h.is_empty() && h.len() <= 8192 && h.len().is_multiple_of(8))
        {
            for bytes in hashes.as_chunks::<8>().0 {
                if self.plan_probes >= 2_000_000 {
                    return true;
                }
                self.plan_probes += 1;
                if candidates
                    .binary_search(&u64::from_be_bytes(*bytes))
                    .is_ok()
                {
                    return true;
                }
            }
            return false;
        }
        if let Some(bits) = bits.filter(|b| b.len() == 2048 && b.iter().any(|v| *v != 0)) {
            for hash in candidates {
                if self.plan_probes >= 2_000_000 {
                    return true;
                }
                self.plan_probes += 1;
                let (a, b) = (hash >> 32, (hash & 0xffff_ffff) | 1);
                if (0..4).all(|i| {
                    let pos = ((a + i * b) % 16384) as usize;
                    bits[2047 - pos / 8] & (1 << (pos % 8)) != 0
                }) {
                    return true;
                }
            }
            return false;
        }
        true
    }
    fn potential(&mut self, fields: &crate::json_read::RawFields<'_>) -> Res<bool> {
        match field(fields, b"otlp") {
            Ok(raw) if raw != b"null" => {
                if let Some(expression) = &self.expression {
                    return Ok(expression
                        .evaluate(fields, &mut self.expression_work, false)?
                        .matched);
                }
                let meta = object(raw)?;
                let resource = typed_attributes(field(&meta, b"resource")?)?;
                let attrs = typed_attributes(field(&meta, b"attributes")?)?;
                Ok(matches(&self.predicates, &resource, &attrs))
            }
            _ => Ok(true), // Legacy uncertainty never proves irrelevance.
        }
    }
    fn candidate(&mut self, id: &str, start: i64, end: i64, payload: &[u8]) -> Res<()> {
        let fields = validate_row(id, start, end, payload)?;
        if self.roots.is_some() {
            self.charge_root(&fields)?;
        }
        if self.potential(&fields)? && !self.candidates.contains(id) {
            if self.candidates.len() >= 65_536 {
                return Err(Error::Groups);
            }
            self.candidates.insert(id.to_owned());
        }
        Ok(())
    }
    fn assemble_candidates(&mut self) -> Res<()> {
        if self.candidates.is_empty() {
            self.blobs.clear();
            return Ok(());
        }
        // Replay the exact immutable owned bytes already admitted. No second
        // object GET, snapshot change, copying or per-span BEAM expansion.
        for (blob, selected, expected) in std::mem::take(&mut self.blobs) {
            if self.scan(blob, false, selected)? != expected {
                return Err(Error::Invalid);
            }
        }
        Ok(())
    }
    fn scan(&mut self, blob: bytes::Bytes, discover: bool, source_selected: bool) -> Res<usize> {
        let reader = ParquetRecordBatchReaderBuilder::try_new(blob)
            .map_err(|_| Error::Invalid)?
            .with_batch_size(1024)
            .build()
            .map_err(|_| Error::Invalid)?;
        let mut rows = 0;
        for batch in reader {
            let batch = batch.map_err(|_| Error::Invalid)?;
            let starts = batch
                .column_by_name("timestamp_ns")
                .and_then(|c| c.as_any().downcast_ref::<Int64Array>())
                .ok_or(Error::Invalid)?;
            let ends = batch
                .column_by_name("end_timestamp_ns")
                .and_then(|c| c.as_any().downcast_ref::<Int64Array>())
                .ok_or(Error::Invalid)?;
            let ids = batch
                .column_by_name("trace_id")
                .and_then(|c| c.as_any().downcast_ref::<StringArray>())
                .ok_or(Error::Invalid)?;
            let payloads = batch
                .column_by_name("payload")
                .and_then(|c| c.as_any().downcast_ref::<StringArray>())
                .ok_or(Error::Invalid)?;
            for i in 0..batch.num_rows() {
                if starts.is_null(i) || ends.is_null(i) || ids.is_null(i) || payloads.is_null(i) {
                    return Err(Error::Invalid);
                }
                rows += 1;
                if discover {
                    self.scanned += 1;
                } else {
                    self.replayed += 1;
                }
                // Provider accounting charges each source once; native work
                // independently caps discovery and complete-context passes.
                if self.scanned > 1_000_000 || self.replayed > 1_000_000 {
                    return Err(Error::Rows);
                }
                if starts.value(i) >= self.floor {
                    if discover {
                        self.candidate(
                            ids.value(i),
                            starts.value(i),
                            ends.value(i),
                            payloads.value(i).as_bytes(),
                        )?;
                    } else {
                        let selected = self.candidates.contains(ids.value(i));
                        if self.context_phase || selected {
                            // Parse and validate once per replay row, including
                            // noncandidate context whose publication proof must
                            // not hide a new potentially matching trace ID.
                            let fields = validate_row(
                                ids.value(i),
                                starts.value(i),
                                ends.value(i),
                                payloads.value(i).as_bytes(),
                            )?;
                            if self.context_phase
                                && !selected
                                && !self.unplanned
                                && self.potential(&fields)?
                            {
                                return Err(Error::Invalid);
                            }
                            if selected {
                                if self.roots.is_some() && !source_selected {
                                    self.charge_root(&fields)?;
                                }
                                self.observe(
                                    ids.value(i),
                                    starts.value(i),
                                    ends.value(i),
                                    &fields,
                                )?;
                            }
                        }
                    }
                }
            }
        }
        Ok(rows)
    }
    fn charge_root(&mut self, fields: &crate::json_read::RawFields<'_>) -> Res<()> {
        let raw = fields
            .iter()
            .find_map(|(key, raw)| (key.as_ref() == b"otlp").then_some(*raw))
            .ok_or(Error::Unknown)?;
        if raw == b"null" {
            return Err(Error::Unknown);
        }
        let meta = object(raw)?;
        let mut units = 2;
        for key in [b"resource".as_slice(), b"attributes".as_slice()] {
            units += Parser::new(field(&meta, key)?)
                .raw_array()
                .map_err(|_| Error::Invalid)?
                .len();
        }
        if !self.roots.as_ref().ok_or(Error::Invalid)?.duration {
            for owner in Parser::new(field(&meta, b"links")?)
                .raw_array()
                .map_err(|_| Error::Invalid)?
            {
                units += 1 + Parser::new(owner)
                    .raw_array()
                    .map_err(|_| Error::Invalid)?
                    .len();
            }
        }
        let query = self.roots.as_mut().ok_or(Error::Invalid)?;
        query.work = query.work.checked_add(units).ok_or(Error::DiscoveryWork)?;
        if query.work > 2_000_000 {
            return Err(Error::DiscoveryWork);
        }
        Ok(())
    }
    fn root_dictionary<'a>(&self, env: Env<'a>) -> Res<Binary<'a>> {
        let query = self.roots.as_ref().ok_or(Error::Invalid)?;
        if self.traces.values().any(|s| s.unknown) {
            return Err(Error::Unknown);
        }
        if !query.duration && self.traces.values().any(|s| s.root_conflict) {
            return Err(Error::Root);
        }
        if !query.duration
            && self
                .traces
                .values()
                .any(|s| s.root.is_none() || (query.service && !s.root_service_known))
        {
            return Err(Error::RootUnknown);
        }
        let mut values = BTreeSet::new();
        let mut bytes = 0usize;
        for s in self.traces.values() {
            let value = if query.duration {
                let ns = (s.end - s.start) as u64;
                if self.predicates.is_empty() {
                    ns.to_string()
                } else {
                    crate::tempo_duration::format(ns)
                }
            } else {
                let root = s.root.as_ref().ok_or(Error::RootUnknown)?;
                if query.service {
                    root.0.clone()
                } else {
                    root.1.clone()
                }
            };
            let len = value.len();
            if values.insert(value) {
                bytes += len + 38;
                if values.len() > 5000 || bytes > 1_048_576 {
                    return Err(Error::Budget);
                }
            }
        }
        let mut count = Counter::new(1_048_576);
        let typ = if query.duration {
            if self.predicates.is_empty() {
                "int"
            } else {
                "duration"
            }
        } else {
            "string"
        };
        write_root_values(&mut count, &values, typ);
        if count.len() > 1_048_576 {
            return Err(Error::Budget);
        }
        let mut out = crate::out::BinSink::with_capacity(count.len());
        write_root_values(&mut out, &values, typ);
        Ok(out.finish(env))
    }
    fn selected(&self) -> Res<Vec<(&String, &Summary)>> {
        let overlapping: Vec<_> = self
            .traces
            .iter()
            .filter(|(_, s)| {
                self.start == 0 || self.end == 0 || (s.start <= self.end && s.end >= self.start)
            })
            .collect();
        // Fixed error precedence is independent of trace IDs and arrival order.
        if overlapping.iter().any(|(_, s)| s.unknown) {
            return Err(Error::Unknown);
        }
        let mut rows: Vec<_> = overlapping
            .into_iter()
            .filter(|(_, s)| s.matched > 0)
            .collect();
        if rows.iter().any(|(_, s)| s.start == 0) {
            return Err(Error::Timestamp);
        }
        if rows.iter().any(|(_, s)| s.root_conflict) {
            return Err(Error::Root);
        }
        if rows
            .iter()
            .any(|(_, s)| (s.end - s.start) / 1_000_000 > i64::from(u32::MAX))
        {
            return Err(Error::Duration);
        }
        rows.sort_by(|(ia, a), (ib, b)| b.start.cmp(&a.start).then_with(|| ia.cmp(ib)));
        rows.truncate(self.limit);
        Ok(rows)
    }
    fn write(&self, out: &mut impl Sink, rows: &[(&String, &Summary)]) {
        if rows.is_empty() {
            out.extend(b"{\"traces\":[]}");
            return;
        }
        out.extend(b"{\"traces\":[");
        for (i, (id, s)) in rows.iter().enumerate() {
            if i > 0 {
                out.push(b',');
            }
            out.extend(b"{\"traceID\":");
            crate::json_write::write_str(out, id.trim_start_matches('0').as_bytes());
            if let Some((service, name)) = &s.root {
                if !service.is_empty() {
                    out.extend(b",\"rootServiceName\":");
                    crate::json_write::write_str(out, service.as_bytes());
                }
                if !name.is_empty() {
                    out.extend(b",\"rootTraceName\":");
                    crate::json_write::write_str(out, name.as_bytes());
                }
            }
            out.extend(format!(",\"startTimeUnixNano\":\"{}\"", s.start).as_bytes());
            let millis = (s.end - s.start) / 1_000_000;
            if millis > 0 {
                out.extend(format!(",\"durationMs\":{millis}").as_bytes());
            }
            out.extend(b",\"spanSet\":");
            write_spanset(out, s);
            out.extend(b",\"spanSets\":[");
            write_spanset(out, s);
            out.extend(b"],\"serviceStats\":{");
            for (i, (service, (spans, errors))) in s.services.iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                crate::json_write::write_str(out, service.as_bytes());
                out.extend(format!(":{{\"spanCount\":{spans}").as_bytes());
                if *errors > 0 {
                    out.extend(format!(",\"errorCount\":{errors}").as_bytes());
                }
                out.push(b'}');
            }
            out.extend(b"}}");
        }
        out.extend(b"]}");
    }
}
fn write_root_values(out: &mut impl Sink, values: &BTreeSet<String>, typ: &str) {
    out.extend(b"{\"tagValues\":[");
    for (i, value) in values.iter().enumerate() {
        if i > 0 {
            out.push(b',');
        }
        out.extend(b"{\"type\":");
        crate::json_write::write_str(out, typ.as_bytes());
        if !value.is_empty() {
            out.extend(b",\"value\":");
            crate::json_write::write_str(out, value.as_bytes());
        }
        out.push(b'}');
    }
    out.extend(b"]}");
}
fn write_spanset(out: &mut impl Sink, s: &Summary) {
    out.extend(b"{\"spans\":[");
    for (i, sample) in s.samples.iter().enumerate() {
        if i > 0 {
            out.push(b',');
        }
        out.extend(&sample.json);
    }
    out.extend(format!("],\"matched\":{}}}", s.matched).as_bytes());
}
#[cfg(test)]
mod root_tests {
    use super::*;
    #[test]
    fn root_evidence_requires_known_metadata_and_charges_all_requested_owners() {
        let mut state = State {
            roots: Some(RootQuery {
                service: true,
                duration: false,
                window: None,
                work: 1_999_994,
            }),
            ..Default::default()
        };
        for payload in [b"{}".as_slice(), b"{\"otlp\":null}".as_slice()] {
            assert!(matches!(
                state.charge_root(&object(payload).unwrap()),
                Err(Error::Unknown)
            ));
        }
        let fields = object(br#"{"otlp":{"resource":[{"key":"k","value":{"stringValue":"v"}}],"attributes":[{"key":"k","value":{"stringValue":"v"}}],"links":[[{"key":"k","value":{"stringValue":"v"}}]]}}"#).unwrap();
        state.charge_root(&fields).unwrap();
        assert_eq!(state.roots.as_ref().unwrap().work, 2_000_000);
        assert!(matches!(
            state.charge_root(&fields),
            Err(Error::DiscoveryWork)
        ));
    }
}
