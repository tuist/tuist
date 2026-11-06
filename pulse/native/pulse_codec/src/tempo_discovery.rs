//! Bounded retained discovery, parent filters and whole-source time envelopes.
//! No span-time approximation, legacy guessing or dictionary truncation.
use crate::json_read::{Parser, RawFields};
use crate::out::{Counter, Sink};
use crate::trace_search::{field, object, result, string, typed_attributes, Error, Predicate, Res};
use arrow::array::{Array, Int64Array, StringArray};
use parquet::arrow::arrow_reader::ParquetRecordBatchReaderBuilder;
use parquet::arrow::ProjectionMask;
use rustler::{Binary, Env, ResourceArc, Term};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Mutex;
const MAX: usize = 1_048_576;
const WORK_MAX: usize = 2_000_000;

// Root dictionaries require positive root evidence. Unlike expression/search
// link ancestry, any original child_of marker disqualifies a parentless span,
// including a linked parent belonging to another trace.
pub(crate) fn root_child_link(metadata: &RawFields<'_>) -> Res<bool> {
    let mut child_link = false;
    for owner in Parser::new(field(metadata, b"links")?)
        .raw_array()
        .map_err(|_| Error::Invalid)?
    {
        child_link |= typed_attributes(owner)?
            .get("opentracing.ref_type")
            .is_some_and(|value| value == "child_of");
    }
    Ok(child_link)
}

const INTRINSICS: &[&str] = &[
    "duration",
    "event:name",
    "event:timeSinceStart",
    "instrumentation:name",
    "instrumentation:version",
    "kind",
    "link:spanID",
    "link:traceID",
    "name",
    "rootName",
    "rootServiceName",
    "span:duration",
    "span:id",
    "span:kind",
    "span:name",
    "span:parentID",
    "span:status",
    "span:statusMessage",
    "status",
    "statusMessage",
    "trace:duration",
    "trace:id",
    "trace:rootName",
    "trace:rootService",
    "traceDuration",
];
const DYNAMIC: &[&str] = &[
    "name",
    "span:name",
    "statusMessage",
    "span:statusMessage",
    "instrumentation:name",
    "instrumentation:version",
    "event:name",
    "event:timeSinceStart",
    "trace:id",
    "span:id",
    "span:parentID",
    "link:traceID",
    "link:spanID",
];
fn scopes(scope: &str, names: bool) -> Res<&'static [&'static str]> {
    match scope {
        "none" if names => Ok(&["resource", "span", "instrumentation", "event", "link"]),
        "none" => Ok(&["resource", "span", "instrumentation"]),
        "intrinsic" => Ok(&[]),
        "resource" => Ok(&["resource"]),
        "span" => Ok(&["span"]),
        "instrumentation" => Ok(&["instrumentation"]),
        "event" => Ok(&["event"]),
        "link" => Ok(&["link"]),
        _ => Err(Error::Invalid),
    }
}
fn new_state(floor: i64, scope: String, key: String, predicates: Vec<Predicate>) -> Res<State> {
    if floor < 0
        || scopes(&scope, key.is_empty()).is_err()
        || key.len() > 256
        || (scope == "none" && matches!(key.as_str(), "root.name" | "root.service.name"))
        || (scope == "intrinsic" && !DYNAMIC.contains(&key.as_str()))
    {
        return Err(Error::Invalid);
    }
    let mut state = State {
        floor,
        names: key.is_empty(),
        scope,
        key,
        rows: 0,
        bytes: 0,
        work: 0,
        values: BTreeSet::new(),
        predicates,
        window: None,
        expression: None,
        expression_match: None,
    };
    if state.scope == "none" && state.names {
        for name in INTRINSICS {
            state.keep("intrinsic".into(), (*name).into())?;
        }
    }
    Ok(state)
}
fn scope_field(scope: &str) -> Res<&'static [u8]> {
    match scope {
        "resource" => Ok(b"resource"),
        "span" => Ok(b"attributes"),
        "instrumentation" => Ok(b"scope"),
        "event" => Ok(b"events"),
        "link" => Ok(b"links"),
        _ => Err(Error::Invalid),
    }
}
struct State {
    floor: i64,
    scope: String,
    key: String,
    names: bool,
    rows: usize,
    bytes: usize,
    work: usize,
    values: BTreeSet<(String, String)>,
    predicates: Vec<Predicate>,
    window: Option<(i64, i64)>,
    expression: Option<ExpressionDiscovery>,
    expression_match: Option<bool>,
}
struct ExpressionDiscovery {
    program: crate::tempo_expression::Expression,
    filtered: bool,
    blobs: Vec<(bytes::Bytes, bool, usize)>,
    input_bytes: usize,
    work: usize,
    contexts: BTreeMap<String, crate::tempo_expression::TraceContext>,
    context_bytes: usize,
    needs_context: bool,
    needs_roots: bool,
    root_errors: BTreeSet<String>,
    unknown_root_services: BTreeSet<String>,
    root_flags: BTreeMap<(String, String), bool>,
    root_ids: BTreeMap<String, String>,
    projection_work: BTreeMap<String, usize>,
}
fn promoted_name(scope: &str, key: &str, value: &[u8]) -> Res<bool> {
    let kind = match (scope, key) {
        (
            "resource",
            "cluster" | "namespace" | "pod" | "container" | "k8s.cluster.name"
            | "k8s.namespace.name" | "k8s.pod.name" | "k8s.container.name",
        )
        | ("span", "http.method" | "http.url") => b"stringValue".as_slice(),
        ("span", "http.status_code") => b"intValue".as_slice(),
        _ => return Ok(false),
    };
    Ok(field(&object(value)?, kind).is_ok())
}
fn optional_string(fields: &RawFields<'_>, key: &[u8]) -> Res<String> {
    let raw = field(fields, key).unwrap_or(b"null");
    if raw == b"null" {
        Ok(String::new())
    } else {
        string(raw)
    }
}
// Shared source-envelope proof; the caller charges returned rows cumulatively.
pub(crate) fn source_window_selection(
    bytes: bytes::Bytes,
    floor: i64,
    window: (i64, i64),
) -> Res<(bool, usize)> {
    let mut state = new_state(floor, "intrinsic".into(), "name".into(), vec![])?;
    state.window = Some(window);
    state.window_selection(bytes)
}
pub struct Discovery(Mutex<Option<State>>);
#[rustler::resource_impl]
impl rustler::Resource for Discovery {}
#[rustler::nif]
fn tempo_discovery_api_version() -> u32 {
    13
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_expression_discovery_new<'a>(
    env: Env<'a>,
    floor: i64,
    scope: String,
    key: String,
    input: Vec<(String, String, String, String)>,
    start: i64,
    end: i64,
) -> Term<'a> {
    result(
        env,
        (|| {
            if input
                .iter()
                .any(|(scope, _, _, _)| matches!(scope.as_str(), "spanset" | "select"))
                || start < 0
                || end < start
                || (start == 0 && end != 0)
            {
                return Err(Error::Invalid);
            }
            let filtered = !matches!(input.as_slice(), [(scope, key, op, value)] if scope == "constant" && key.is_empty() && op == "true" && value.is_empty());
            let root_filter = input.iter().any(|(scope, key, _, _)| {
                scope == "intrinsic.string"
                    && matches!(key.as_str(), "rootName" | "rootServiceName")
            });
            let needs_roots = root_filter
                || (scope == "intrinsic"
                    && matches!(
                        key.as_str(),
                        "rootName" | "trace:rootName" | "rootServiceName" | "trace:rootService"
                    ));
            let program =
                crate::tempo_expression::Expression::compile(input).ok_or(Error::Invalid)?;
            let needs_context = needs_roots
                || program.needs_context()
                || (scope == "intrinsic" && key == "trace:duration");
            // Trace-wide/static targets are only admitted by this new callback,
            // never by an older adapter that could silently drop the program.
            let target = key.clone();
            let mut state = new_state(
                floor,
                scope.clone(),
                if scope == "intrinsic" {
                    "name".into()
                } else {
                    key
                },
                Vec::new(),
            )?;
            if scope == "intrinsic" && !INTRINSICS.contains(&target.as_str()) && !target.is_empty()
            {
                return Err(Error::Invalid);
            }
            state.key = target;
            state.names = state.key.is_empty();
            state.window = (start > 0).then_some((start, end));
            state.expression = Some(ExpressionDiscovery {
                program,
                filtered,
                blobs: Vec::new(),
                input_bytes: 0,
                work: 0,
                contexts: BTreeMap::new(),
                context_bytes: 0,
                needs_context,
                needs_roots,
                root_errors: BTreeSet::new(),
                unknown_root_services: BTreeSet::new(),
                root_flags: BTreeMap::new(),
                root_ids: BTreeMap::new(),
                projection_work: BTreeMap::new(),
            });
            Ok(ResourceArc::new(Discovery(Mutex::new(Some(state)))))
        })(),
    )
}
#[rustler::nif]
fn tempo_discovery_new<'a>(env: Env<'a>, floor: i64, scope: String, key: String) -> Term<'a> {
    result(
        env,
        (|| {
            let state = new_state(floor, scope, key, Vec::new())?;
            Ok(ResourceArc::new(Discovery(Mutex::new(Some(state)))))
        })(),
    )
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_filtered_discovery_new<'a>(
    env: Env<'a>,
    floor: i64,
    scope: String,
    key: String,
    input: Vec<(String, String, String, String)>,
) -> Term<'a> {
    result(
        env,
        (|| {
            let predicates = crate::tempo_search::predicates(input)?;
            // Tempo's same-target equality shortcut returns unproven query literals.
            // This endpoint promises stored values, so refuse instead of inventing one.
            if predicates
                .iter()
                .any(|p| (p.scope == scope || scope == "none") && p.key == key && p.regex.is_none())
            {
                return Err(Error::Invalid);
            }
            let state = new_state(floor, scope, key, predicates)?;
            Ok(ResourceArc::new(Discovery(Mutex::new(Some(state)))))
        })(),
    )
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_windowed_discovery_new<'a>(
    env: Env<'a>,
    floor: i64,
    scope: String,
    key: String,
    input: Vec<(String, String, String, String)>,
    start: i64,
    end: i64,
) -> Term<'a> {
    result(
        env,
        (|| {
            if start <= 0 || end < start {
                return Err(Error::Invalid);
            }
            let predicates = if input.is_empty() {
                Vec::new()
            } else {
                crate::tempo_search::predicates(input)?
            };
            if !key.is_empty()
                && predicates.iter().any(|p| {
                    (p.scope == scope || scope == "none") && p.key == key && p.regex.is_none()
                })
            {
                return Err(Error::Invalid);
            }
            let mut state = new_state(floor, scope, key, predicates)?;
            state.window = Some((start, end));
            Ok(ResourceArc::new(Discovery(Mutex::new(Some(state)))))
        })(),
    )
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_discovery_add<'a>(
    env: Env<'a>,
    handle: ResourceArc<Discovery>,
    blob: Binary<'a>,
) -> Term<'a> {
    let mut guard = match handle.0.lock() {
        Ok(guard) => guard,
        Err(_) => return result(env, Err::<usize, _>(Error::Invalid)),
    };
    let scanned = guard
        .as_mut()
        .ok_or(Error::Invalid)
        .and_then(|s| s.scan(blob));
    if scanned.is_err() {
        *guard = None;
    }
    result(env, scanned)
}
#[rustler::nif(schedule = "DirtyCpu")]
fn tempo_discovery_finish<'a>(env: Env<'a>, handle: ResourceArc<Discovery>) -> Term<'a> {
    result(
        env,
        (|| {
            let mut state = handle
                .0
                .lock()
                .map_err(|_| Error::Invalid)?
                .take()
                .ok_or(Error::Invalid)?;
            state.finish_expression()?;
            let mut count = Counter::new(MAX);
            state.write(&mut count);
            if count.len() > MAX {
                return Err(Error::Budget);
            }
            let mut out = crate::out::BinSink::with_capacity(count.len());
            state.write(&mut out);
            Ok(out.finish(env))
        })(),
    )
}
impl State {
    fn capture_expression(&mut self, bytes: bytes::Bytes) -> Res<usize> {
        let expression = self.expression.as_ref().ok_or(Error::Invalid)?;
        if expression.blobs.len() >= 1024
            || expression
                .input_bytes
                .checked_add(bytes.len())
                .ok_or(Error::Budget)?
                > 33_554_432
        {
            return Err(Error::Budget);
        }
        let (selected, expected) = match self.window {
            Some(window) => {
                let (selected, rows) = source_window_selection(bytes.clone(), self.floor, window)?;
                (selected, Some(rows))
            }
            None => (true, None),
        };
        let trace_projection = self.scope == "intrinsic"
            && matches!(
                self.key.as_str(),
                "rootName"
                    | "trace:rootName"
                    | "rootServiceName"
                    | "trace:rootService"
                    | "trace:duration"
            );
        let duration_projection = self.key == "trace:duration";
        let expression = self.expression.as_mut().ok_or(Error::Invalid)?;
        let rows = visit_expression_rows(bytes.clone(), self.floor, |id, fields| {
            if !expression.needs_context {
                return Ok(());
            }
            if trace_projection {
                let meta = object(field(fields, b"otlp")?)?;
                let mut units = 2;
                for key in [b"resource".as_slice(), b"attributes".as_slice()] {
                    units += Parser::new(field(&meta, key)?)
                        .raw_array()
                        .map_err(|_| Error::Invalid)?
                        .len();
                }
                if !duration_projection {
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
                if !expression.projection_work.contains_key(id) {
                    expression.context_bytes += id.len() + 40;
                }
                let work = expression.projection_work.entry(id.to_owned()).or_default();
                *work = work.checked_add(units).ok_or(Error::DiscoveryWork)?;
            }
            let new = !expression.contexts.contains_key(id);
            if !expression.contexts.contains_key(id) {
                if expression.contexts.len() >= 65_536 {
                    return Err(Error::Groups);
                }
                expression.context_bytes += id.len() + 96;
            }
            let context = expression.contexts.entry(id.to_owned()).or_default();
            let previous = context.retained_bytes();
            if expression.needs_roots {
                let meta = object(field(fields, b"otlp")?)?;
                let disqualified =
                    field(fields, b"parent_span_id")? == b"null" && root_child_link(&meta)?;
                let root = field(fields, b"parent_span_id")? == b"null" && !disqualified;
                let flag = (id.to_owned(), string(field(fields, b"span_id")?)?);
                if root {
                    let service = typed_attributes(field(&meta, b"resource")?)?
                        .get("service.name")
                        .cloned()
                        .unwrap_or_default();
                    let pair = (service, string(field(fields, b"name")?)?);
                    if expression
                        .root_ids
                        .get(id)
                        .is_some_and(|previous| previous != &flag.1)
                        || context
                            .root
                            .as_ref()
                            .is_some_and(|previous| previous != &pair)
                    {
                        expression.root_errors.insert(id.to_owned());
                    }
                    if !expression.root_ids.contains_key(id) {
                        expression.context_bytes += id.len() + flag.1.len() + 32;
                        expression.root_ids.insert(id.to_owned(), flag.1.clone());
                    }
                }
                match expression.root_flags.insert(flag.clone(), root) {
                    None => expression.context_bytes += flag.0.len() + flag.1.len() + 64,
                    Some(previous) if previous != root => {
                        expression.root_errors.insert(id.to_owned());
                    }
                    _ => {}
                }
                if root
                    && !typed_attributes(field(&meta, b"resource")?)?.contains_key("service.name")
                {
                    expression.unknown_root_services.insert(id.to_owned());
                }
                let start = crate::tempo_search::integer(field(fields, b"timestamp_ns")?)?;
                let end = crate::tempo_search::integer(field(fields, b"end_timestamp_ns")?)?;
                let start = if new { start } else { context.start.min(start) };
                let end = if new { end } else { context.end.max(end) };
                // Keep the shared observer's complete work accounting without
                // admitting its weaker same-trace root evidence. Disqualified
                // rows still contribute to the complete trace duration.
                let observed = if disqualified {
                    crate::tempo_expression::TraceContext::default()
                        .observe(fields, &mut expression.work)
                } else {
                    context.observe(fields, &mut expression.work)
                };
                match observed {
                    Err(Error::Root) => {
                        expression.root_errors.insert(id.to_owned());
                    }
                    result => result?,
                }
                context.start = start;
                context.end = end;
            } else {
                let start = crate::tempo_search::integer(field(fields, b"timestamp_ns")?)?;
                let end = crate::tempo_search::integer(field(fields, b"end_timestamp_ns")?)?;
                context.start = if new { start } else { context.start.min(start) };
                context.end = if new { end } else { context.end.max(end) };
                expression.work += 1;
                if expression.work > crate::tempo_expression::WORK_MAX {
                    return Err(Error::Budget);
                }
            }
            expression.context_bytes += context.retained_bytes().saturating_sub(previous);
            if expression.context_bytes > 16_777_216 {
                return Err(Error::Budget);
            }
            Ok(())
        })?;
        self.rows = self.rows.checked_add(rows).ok_or(Error::Rows)?;
        if self.rows > 1_000_000 {
            return Err(Error::Rows);
        }
        if expected.is_some_and(|expected| expected != rows) {
            return Err(Error::Invalid);
        }
        expression.input_bytes += bytes.len();
        expression.blobs.push((bytes, selected, rows));
        Ok(rows)
    }

    fn finish_expression(&mut self) -> Res<()> {
        let Some(mut expression) = self.expression.take() else {
            return Ok(());
        };
        let trace_target = self.scope == "intrinsic"
            && matches!(
                self.key.as_str(),
                "rootName"
                    | "trace:rootName"
                    | "rootServiceName"
                    | "trace:rootService"
                    | "trace:duration"
            );
        let static_target = self.scope == "intrinsic"
            && matches!(
                self.key.as_str(),
                "" | "status"
                    | "span:status"
                    | "kind"
                    | "span:kind"
                    | "duration"
                    | "span:duration"
                    | "traceDuration"
            );
        let mut ids = BTreeSet::new();
        for (blob, selected, expected) in std::mem::take(&mut expression.blobs) {
            // Even unselected sources were validated and charged during capture;
            // context is complete before the first projected parent is tested.
            if !selected {
                continue;
            }
            let rows = visit_expression_rows(blob, self.floor, |id, fields| {
                let context = expression.contexts.get(id);
                let matched = expression
                    .program
                    .evaluate_context(fields, None, &mut expression.work, false, context)?
                    .matched;
                if trace_target {
                    if matched {
                        ids.insert(id.to_owned());
                    }
                } else if !static_target {
                    self.expression_match = Some(matched);
                    let meta = object(field(fields, b"otlp")?)?;
                    self.observe_fields(fields, &meta)?;
                }
                Ok(())
            })?;
            if rows != expected {
                return Err(Error::Invalid);
            }
        }
        if trace_target {
            for id in ids {
                self.charge(*expression.projection_work.get(&id).ok_or(Error::Invalid)?)?;
                let context = expression.contexts.get(&id).ok_or(Error::Invalid)?;
                let (typ, value) = if self.key == "trace:duration" {
                    if expression.filtered {
                        (
                            "duration",
                            crate::tempo_duration::format(context.duration() as u64),
                        )
                    } else {
                        ("int", context.duration().to_string())
                    }
                } else {
                    if expression.root_errors.contains(&id) {
                        return Err(Error::Root);
                    }
                    if matches!(self.key.as_str(), "rootServiceName" | "trace:rootService")
                        && expression.unknown_root_services.contains(&id)
                    {
                        return Err(Error::RootUnknown);
                    }
                    let root = context.root.as_ref().ok_or(Error::RootUnknown)?;
                    (
                        "string",
                        if matches!(self.key.as_str(), "rootName" | "trace:rootName") {
                            root.1.clone()
                        } else {
                            root.0.clone()
                        },
                    )
                };
                self.keep(typ.into(), value)?;
            }
        } else if static_target {
            let values: &[&str] = match self.key.as_str() {
                "" => INTRINSICS,
                "status" | "span:status" => &["error", "ok", "unset"],
                "kind" | "span:kind" => &[
                    "client",
                    "consumer",
                    "internal",
                    "producer",
                    "server",
                    "unspecified",
                ],
                _ => &[],
            };
            for value in values {
                self.keep(
                    if self.names { "intrinsic" } else { "keyword" }.into(),
                    (*value).into(),
                )?;
            }
        }
        Ok(())
    }

    fn observe(&mut self, id: &str, start: i64, end: i64, payload: &[u8]) -> Res<()> {
        let fields = crate::tempo_search::validate_row(id, start, end, payload)?;
        let metadata = field(&fields, b"otlp").map_err(|_| Error::Unknown)?;
        if metadata == b"null" {
            return Err(Error::Unknown);
        }
        let metadata = object(metadata)?;
        self.observe_fields(&fields, &metadata)
    }
    fn observe_fields(&mut self, fields: &RawFields<'_>, metadata: &RawFields<'_>) -> Res<()> {
        if self.scope == "intrinsic" {
            return self.observe_intrinsic(fields, metadata);
        }
        let mut owners = Vec::new();
        for scope in scopes(&self.scope, self.names)? {
            let raw = field(metadata, scope_field(scope)?)?;
            if matches!(*scope, "event" | "link") {
                for owner in Parser::new(raw).raw_array().map_err(|_| Error::Invalid)? {
                    owners.push((*scope, owner));
                }
            } else {
                owners.push((*scope, raw));
            }
        }
        // Parent rows alone do not bound nested events/links. Charge owners and
        // every target-owner attribute before filtering, including nonmatches.
        for (_, owner) in &owners {
            let pairs = Parser::new(owner).raw_array().map_err(|_| Error::Invalid)?;
            self.charge(1 + pairs.len())?;
        }
        let matched = self.matches_metadata(metadata)?;
        // Tempo's filtered names include promoted-column hints from all visible
        // context, not just matching owners. ServiceName is a required column,
        // even when no original service.name attribute exists. Never use this
        // shortcut for values or unfiltered original-key discovery.
        for (scope, owner) in owners {
            if self.names
                && (self.scope == "none"
                    || !self.predicates.is_empty()
                    || self.expression_match.is_some())
                && scope == "resource"
            {
                self.keep(scope.into(), "service.name".into())?;
            }
            if !matched && (!self.names || !matches!(scope, "resource" | "span")) {
                continue;
            }
            self.observe_owner(scope, owner, matched)?;
        }
        Ok(())
    }
    fn observe_owner(&mut self, scope: &str, owner: &[u8], matched: bool) -> Res<()> {
        let mut parser = Parser::new(owner);
        for raw in parser.raw_array().map_err(|_| Error::Invalid)? {
            let pair = object(raw)?;
            let key = string(field(&pair, b"key")?)?;
            if self.names {
                if matched
                    || ((!self.predicates.is_empty() || self.expression_match.is_some())
                        && promoted_name(scope, &key, field(&pair, b"value")?)?)
                {
                    self.keep(scope.into(), key)?;
                }
                continue;
            }
            if !matched || key != self.key {
                continue;
            }
            let value = object(field(&pair, b"value")?)?;
            let (kind, value) = if let Ok(raw) = field(&value, b"stringValue") {
                ("string", string(raw)?)
            } else if let Ok(raw) = field(&value, b"intValue") {
                ("int", string(raw)?)
            } else if let Ok(raw) = field(&value, b"doubleValue") {
                let number = crate::trace_metadata::double(raw).map_err(|_| Error::Invalid)?;
                (
                    "float",
                    crate::tempo_float::format(number).ok_or(Error::Invalid)?,
                )
            } else if let Ok(raw) = field(&value, b"boolValue") {
                match raw {
                    b"true" => ("bool", "true".into()),
                    b"false" => ("bool", "false".into()),
                    _ => return Err(Error::Invalid),
                }
            } else {
                return Err(Error::UnsupportedTag);
            };
            self.keep(kind.into(), value)?;
        }
        Ok(())
    }
    fn matches_metadata(&self, meta: &RawFields<'_>) -> Res<bool> {
        if let Some(matched) = self.expression_match {
            return Ok(matched);
        }
        if self.predicates.is_empty() {
            return Ok(true);
        }
        let resource = typed_attributes(field(meta, b"resource")?)?;
        let attrs = typed_attributes(field(meta, b"attributes")?)?;
        Ok(crate::tempo_search::matches(
            &self.predicates,
            &resource,
            &attrs,
        ))
    }
    fn charge(&mut self, units: usize) -> Res<()> {
        self.work = self.work.checked_add(units).ok_or(Error::DiscoveryWork)?;
        if self.work > WORK_MAX {
            return Err(Error::DiscoveryWork);
        }
        Ok(())
    }
    fn observe_intrinsic(&mut self, fields: &RawFields<'_>, meta: &RawFields<'_>) -> Res<()> {
        if self.key.starts_with("link:") {
            self.charge(1)?;
            for owner in Parser::new(field(meta, b"links")?)
                .raw_array()
                .map_err(|_| Error::Invalid)?
            {
                self.charge(
                    1 + Parser::new(owner)
                        .raw_array()
                        .map_err(|_| Error::Invalid)?
                        .len(),
                )?;
            }
            if self.matches_metadata(meta)? {
                let key = if self.key == "link:traceID" {
                    b"trace_id".as_slice()
                } else {
                    b"span_id".as_slice()
                };
                for link in Parser::new(field(fields, b"links")?)
                    .raw_array()
                    .map_err(|_| Error::Invalid)?
                {
                    self.keep("string".into(), string(field(&object(link)?, key)?)?)?;
                }
            }
            return Ok(());
        }
        if matches!(self.key.as_str(), "trace:id" | "span:id" | "span:parentID") {
            self.charge(
                1 + Parser::new(field(meta, b"attributes")?)
                    .raw_array()
                    .map_err(|_| Error::Invalid)?
                    .len(),
            )?;
            if self.matches_metadata(meta)? {
                let key = match self.key.as_str() {
                    "trace:id" => b"trace_id".as_slice(),
                    "span:id" => b"span_id".as_slice(),
                    _ => b"parent_span_id".as_slice(),
                };
                let raw = field(fields, key)?;
                let value = if raw == b"null" {
                    "0000000000000000".into()
                } else {
                    string(raw)?
                };
                self.keep("string".into(), value)?;
            }
            return Ok(());
        }
        if matches!(self.key.as_str(), "event:name" | "event:timeSinceStart") {
            let owners = Parser::new(field(meta, b"events")?)
                .raw_array()
                .map_err(|_| Error::Invalid)?;
            let events = Parser::new(field(fields, b"events")?)
                .raw_array()
                .map_err(|_| Error::Invalid)?;
            if owners.len() != events.len() {
                return Err(Error::Invalid);
            }
            self.charge(1)?;
            for owner in owners {
                self.charge(
                    1 + Parser::new(owner)
                        .raw_array()
                        .map_err(|_| Error::Invalid)?
                        .len(),
                )?;
            }
            let matched = self.matches_metadata(meta)?;
            for event in events {
                if self.key == "event:timeSinceStart" {
                    let fields_event = object(event)?;
                    let raw = field(&fields_event, b"timestamp_ns")?;
                    let time = crate::tempo_search::integer(raw)?;
                    if time < 0 {
                        return Err(Error::Invalid);
                    }
                    // Both actual source times are nonnegative int64, so their
                    // difference cannot overflow. Validate even on nonmatches.
                    let start = crate::tempo_search::integer(field(fields, b"timestamp_ns")?)?;
                    if matched {
                        self.keep("int".into(), (time - start).to_string())?;
                    }
                } else if matched {
                    self.keep("string".into(), optional_string(&object(event)?, b"name")?)?;
                }
            }
        } else {
            let instrumentation = self.key.starts_with("instrumentation:");
            let attrs = field(
                meta,
                if instrumentation {
                    b"scope"
                } else {
                    b"attributes"
                },
            )?;
            self.charge(
                1 + Parser::new(attrs)
                    .raw_array()
                    .map_err(|_| Error::Invalid)?
                    .len(),
            )?;
            if !self.matches_metadata(meta)? {
                return Ok(());
            }
            let value = if instrumentation {
                let scope = object(field(fields, b"scope")?)?;
                optional_string(
                    &scope,
                    if self.key.ends_with("version") {
                        b"version"
                    } else {
                        b"name"
                    },
                )?
            } else if self.key.ends_with("statusMessage") {
                let raw = field(fields, b"status")?;
                if raw == b"null" {
                    String::new()
                } else {
                    optional_string(&object(raw)?, b"message")?
                }
            } else {
                string(field(fields, b"name")?)?
            };
            self.keep("string".into(), value)?;
        }
        Ok(())
    }
    fn keep(&mut self, kind: String, value: String) -> Res<()> {
        let pair = (kind, value);
        if self.values.contains(&pair) {
            return Ok(());
        }
        if self.values.len() >= 5000 {
            return Err(Error::Budget);
        }
        self.bytes = self
            .bytes
            .checked_add(pair.0.len() + pair.1.len() + 32)
            .ok_or(Error::Budget)?;
        if self.bytes > MAX {
            return Err(Error::Budget);
        }
        self.values.insert(pair);
        Ok(())
    }
    fn window_selection(&mut self, bytes: bytes::Bytes) -> Res<(bool, usize)> {
        let (start, end) = self.window.ok_or(Error::Invalid)?;
        let builder =
            ParquetRecordBatchReaderBuilder::try_new(bytes).map_err(|_| Error::Invalid)?;
        for name in ["trace_id", "payload"] {
            if builder
                .schema()
                .field_with_name(name)
                .map_err(|_| Error::Invalid)?
                .data_type()
                != &arrow::datatypes::DataType::Utf8
            {
                return Err(Error::Invalid);
            }
        }
        let indexes = [
            builder
                .schema()
                .index_of("timestamp_ns")
                .map_err(|_| Error::Invalid)?,
            builder
                .schema()
                .index_of("end_timestamp_ns")
                .map_err(|_| Error::Invalid)?,
        ];
        let mask = ProjectionMask::roots(builder.parquet_schema(), indexes);
        let reader = builder
            .with_projection(mask)
            .with_batch_size(1024)
            .build()
            .map_err(|_| Error::Invalid)?;
        let (mut low, mut high, mut rows) = (i64::MAX, i64::MIN, 0);
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
            for i in 0..batch.num_rows() {
                if starts.is_null(i)
                    || ends.is_null(i)
                    || starts.value(i) < 0
                    || ends.value(i) < starts.value(i)
                {
                    return Err(Error::Invalid);
                }
                rows += 1;
                self.rows += 1;
                if self.rows > 1_000_000 {
                    return Err(Error::Rows);
                }
                if starts.value(i) >= self.floor {
                    low = low.min(starts.value(i));
                    high = high.max(ends.value(i));
                }
            }
        }
        Ok((
            end >= self.floor && low <= end && high >= start.max(self.floor),
            rows,
        ))
    }
    fn scan(&mut self, blob: Binary<'_>) -> Res<usize> {
        let bytes = crate::erlang_bytes::from_binary(blob);
        if self.expression.is_some() {
            return self.capture_expression(bytes);
        }
        let expected = if self.window.is_some() {
            let (selected, rows) = self.window_selection(bytes.clone())?;
            if !selected {
                return Ok(rows);
            }
            Some(rows)
        } else {
            None
        };
        let reader = ParquetRecordBatchReaderBuilder::try_new(bytes)
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
                if expected.is_none() {
                    self.rows += 1;
                    if self.rows > 1_000_000 {
                        return Err(Error::Rows);
                    }
                }
                if starts.value(i) >= self.floor {
                    self.observe(
                        ids.value(i),
                        starts.value(i),
                        ends.value(i),
                        payloads.value(i).as_bytes(),
                    )?;
                }
            }
        }
        if expected.is_some_and(|expected| expected != rows) {
            return Err(Error::Invalid);
        }
        Ok(rows)
    }
    fn write(&self, out: &mut impl Sink) {
        if self.names {
            out.extend(b"{\"scopes\":[");
            let mut previous: Option<&str> = None;
            for (scope, key) in &self.values {
                if previous != Some(scope.as_str()) {
                    if previous.is_some() {
                        out.extend(b"]},");
                    }
                    out.extend(b"{\"name\":");
                    crate::json_write::write_str(out, scope.as_bytes());
                    out.extend(b",\"tags\":[");
                    previous = Some(scope);
                } else {
                    out.push(b',');
                }
                crate::json_write::write_str(out, key.as_bytes());
            }
            if previous.is_some() {
                out.extend(b"]}");
            }
            out.extend(b"]}");
            return;
        }
        out.extend(b"{\"tagValues\":[");
        for (i, (kind, value)) in self.values.iter().enumerate() {
            if i > 0 {
                out.push(b',');
            }
            if !self.names {
                out.extend(b"{\"type\":");
                crate::json_write::write_str(out, kind.as_bytes());
                if !value.is_empty() {
                    out.extend(b",\"value\":");
                }
            }
            if self.names || !value.is_empty() {
                crate::json_write::write_str(out, value.as_bytes());
            }
            if !self.names {
                out.push(b'}');
            }
        }
        if self.names {
            out.extend(b"]}]}");
        } else {
            out.extend(b"]}");
        }
    }
}

// Decode directly over the captured Erlang-owned bytes. No retained payload
// copies or BEAM span expansion; every source's physical rows count once.
fn visit_expression_rows(
    bytes: bytes::Bytes,
    floor: i64,
    mut observe: impl FnMut(&str, &RawFields<'_>) -> Res<()>,
) -> Res<usize> {
    let builder = ParquetRecordBatchReaderBuilder::try_new(bytes).map_err(|_| Error::Invalid)?;
    let expected = usize::try_from(builder.metadata().file_metadata().num_rows())
        .map_err(|_| Error::Invalid)?;
    if expected > 1_000_000 {
        return Err(Error::Rows);
    }
    let reader = builder
        .with_batch_size(1024)
        .build()
        .map_err(|_| Error::Invalid)?;
    let mut rows = 0usize;
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
            rows += 1;
            if rows > expected
                || starts.is_null(i)
                || ends.is_null(i)
                || ids.is_null(i)
                || payloads.is_null(i)
                || starts.value(i) < 0
                || ends.value(i) < starts.value(i)
            {
                return Err(Error::Invalid);
            }
            if starts.value(i) >= floor {
                let fields = crate::tempo_search::validate_row(
                    ids.value(i),
                    starts.value(i),
                    ends.value(i),
                    payloads.value(i).as_bytes(),
                )?;
                if field(&fields, b"otlp")? == b"null" {
                    return Err(Error::Unknown);
                }
                observe(ids.value(i), &fields)?;
            }
        }
    }
    if rows != expected {
        return Err(Error::Invalid);
    }
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::*;
    use arrow::{
        datatypes::{DataType, Field, Schema},
        record_batch::RecordBatch,
    };
    use parquet::arrow::ArrowWriter;
    use std::sync::Arc;

    fn header(start: Option<i64>, end: Option<i64>, payload: Option<bool>) -> bytes::Bytes {
        let mut fields = vec![
            Field::new("timestamp_ns", DataType::Int64, true),
            Field::new("end_timestamp_ns", DataType::Int64, true),
            Field::new("trace_id", DataType::Utf8, false),
        ];
        let mut columns: Vec<Arc<dyn Array>> = vec![
            Arc::new(Int64Array::from(vec![start])),
            Arc::new(Int64Array::from(vec![end])),
            Arc::new(StringArray::from(vec!["not-decoded-outside-window"])),
        ];
        if let Some(wrong_type) = payload {
            fields.push(Field::new(
                "payload",
                if wrong_type {
                    DataType::Int64
                } else {
                    DataType::Utf8
                },
                false,
            ));
            columns.push(if wrong_type {
                Arc::new(Int64Array::from(vec![1]))
            } else {
                Arc::new(StringArray::from(vec!["excluded-payload-is-not-scrubbed"]))
            });
        }
        let schema = Arc::new(Schema::new(fields));
        let batch = RecordBatch::try_new(schema.clone(), columns).unwrap();
        let mut blob = Vec::new();
        let mut writer = ArrowWriter::try_new(&mut blob, schema, None).unwrap();
        writer.write(&batch).unwrap();
        writer.close().unwrap();
        bytes::Bytes::from(blob)
    }

    #[test]
    fn event_offsets_are_integer_nanoseconds_and_validate_nonmatches() {
        let fields =
            object(br#"{"timestamp_ns":9223372036854775807,"events":[{"timestamp_ns":0},{"timestamp_ns":0}]}"#)
                .unwrap();
        let meta = object(br#"{"events":[[],[]]}"#).unwrap();
        let mut state =
            new_state(0, "intrinsic".into(), "event:timeSinceStart".into(), vec![]).unwrap();
        state.observe_intrinsic(&fields, &meta).unwrap();
        assert_eq!(state.work, 3);
        assert_eq!(
            state.values,
            BTreeSet::from([("int".into(), "-9223372036854775807".into())])
        );
        let predicates = crate::tempo_search::predicates(vec![(
            "resource".into(),
            "service.name".into(),
            "=".into(),
            "absent".into(),
        )])
        .unwrap();
        let mut state = new_state(
            0,
            "intrinsic".into(),
            "event:timeSinceStart".into(),
            predicates,
        )
        .unwrap();
        let meta = object(br#"{"events":[[]],"resource":[]}"#).unwrap();
        let fields = object(br#"{"timestamp_ns":1,"events":[{"timestamp_ns":-1}]}"#).unwrap();
        assert!(matches!(
            state.observe_intrinsic(&fields, &meta),
            Err(Error::Invalid)
        ));
        assert_eq!(state.work, 2);
    }

    #[test]
    fn unselected_sources_require_valid_timestamp_headers_and_trace_schema() {
        for (start, end, payload) in [
            (None, Some(11), Some(false)),
            (Some(-1), Some(11), Some(false)),
            (Some(10), Some(9), Some(false)),
            (Some(10), Some(11), None),
            (Some(10), Some(11), Some(true)),
        ] {
            let mut state = new_state(0, "intrinsic".into(), "name".into(), vec![]).unwrap();
            state.window = Some((100, 200));
            assert!(matches!(
                state.window_selection(header(start, end, payload)),
                Err(Error::Invalid)
            ));
        }
        let mut state = new_state(0, "intrinsic".into(), "name".into(), vec![]).unwrap();
        state.window = Some((100, 200));
        assert_eq!(
            state
                .window_selection(header(Some(10), Some(11), Some(false)))
                .unwrap(),
            (false, 1)
        );
    }
}
