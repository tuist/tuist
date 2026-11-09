//! Bounded TraceQL span programs: same-parent boolean spansets, optionally
//! joined by structural operators and followed by `select(...)`. No
//! projection/type inference, DNF expansion or short-circuit accounting.
//! Spansets are evaluated per span; structural joins run per complete trace
//! over the spans' parent links (`structural`).
use crate::json_read::{Parser, RawFields};
use crate::trace_metadata::Envelope;
use crate::trace_search::{field, object, string, Error, Res};
use std::borrow::Cow;
use std::collections::{BTreeMap, HashMap, HashSet};

pub(crate) const WORK_MAX: usize = 20_000_000;
const SPANSETS_MAX: usize = 4;
const SELECT_MAX: usize = 8;
const PROGRAM_MAX: usize = 64;
const STRING_INTRINSICS: &[&str] = &[
    "name",
    "statusMessage",
    "rootName",
    "rootServiceName",
    "span:id",
    "span:parentID",
    "trace:id",
    "event:name",
    "link:traceID",
    "link:spanID",
    "instrumentation:name",
    "instrumentation:version",
];
const OMITTED: &[&str] = &[
    "duration",
    "trace_duration",
    "rootName",
    "rootServiceName",
    "span:id",
    "trace:id",
];
/// Complete retained context, shared by search and expression discovery.
/// The caller bounds the number of contexts and charges `retained_bytes()`
/// against its aggregate retained-byte budget. Rows must already be validated.
#[derive(Default)]
pub(crate) struct TraceContext {
    pub(crate) start: i64,
    pub(crate) end: i64,
    pub(crate) root: Option<(String, String)>,
    root_id: Option<String>,
    root_conflict: bool,
    root_service_known: bool,
    initialized: bool,
}
impl TraceContext {
    pub(crate) fn duration(&self) -> i64 {
        self.end - self.start
    }
    pub(crate) fn retained_bytes(&self) -> usize {
        96 + self.root_id.as_ref().map_or(0, String::len)
            + self.root.as_ref().map_or(0, |(s, n)| s.len() + n.len())
    }
    pub(crate) fn observe(&mut self, fields: &RawFields<'_>, work: &mut usize) -> Res<()> {
        let meta = object(field(fields, b"otlp")?)?;
        let resource = attributes(field(&meta, b"resource")?)?;
        let links = Parser::new(field(&meta, b"links")?)
            .raw_array()
            .map_err(|_| Error::Invalid)?;
        let mut units = 2 + resource.len();
        for attrs in &links {
            units += 1 + attributes(attrs)?.len();
        }
        *work = work
            .checked_add(units)
            .ok_or_else(|| Error::budget("expression_work", WORK_MAX, usize::MAX))?;
        if *work > WORK_MAX {
            return Err(Error::budget("expression_work", WORK_MAX, *work));
        }
        let start = crate::tempo_search::integer(field(fields, b"timestamp_ns")?)?;
        let end = crate::tempo_search::integer(field(fields, b"end_timestamp_ns")?)?;
        if !self.initialized {
            self.start = start;
            self.end = end;
            self.initialized = true;
        } else {
            self.start = self.start.min(start);
            self.end = self.end.max(end);
        }
        if field(fields, b"parent_span_id")? == b"null" && !has_child_link(fields, &meta)? {
            let id = string(field(fields, b"span_id")?)?;
            let service = resource
                .get("service.name")
                .and_then(|raw| object(raw).ok())
                .and_then(|v| field(&v, b"stringValue").ok().and_then(|r| string(r).ok()));
            let known = service.is_some();
            let root = (
                service.unwrap_or_default(),
                string(field(fields, b"name")?)?,
            );
            self.root_conflict |= self.root_id.as_ref().is_some_and(|v| v != &id)
                || self.root.as_ref().is_some_and(|v| v != &root);
            if self.root_id.is_none() {
                self.root_service_known = known;
                self.root_id = Some(id);
                self.root = Some(root);
            } else {
                self.root_service_known &= known;
            }
        }
        if self.retained_bytes() > 16_777_216 {
            return Err(Error::budget(
                "context_bytes",
                16_777_216,
                self.retained_bytes(),
            ));
        }
        Ok(())
    }
}
pub(crate) fn has_child_link(fields: &RawFields<'_>, meta: &RawFields<'_>) -> Res<bool> {
    let links = Parser::new(field(fields, b"links")?)
        .raw_array()
        .map_err(|_| Error::Invalid)?;
    let attrs = Parser::new(field(meta, b"links")?)
        .raw_array()
        .map_err(|_| Error::Invalid)?;
    let tid = field(fields, b"trace_id")?;
    for (link, attrs) in links.into_iter().zip(attrs) {
        if field(&object(link)?, b"trace_id")? == tid {
            if let Some(raw) = attributes(attrs)?.get("opentracing.ref_type") {
                let v = object(raw)?;
                if field(&v, b"stringValue")
                    .ok()
                    .map(string)
                    .transpose()?
                    .as_deref()
                    == Some("child_of")
                {
                    return Ok(true);
                }
            }
        }
    }
    Ok(false)
}
pub(crate) type Attributes = BTreeMap<(String, String), Vec<u8>>;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Relation {
    /// `{a} >> {b}`: b spans with an ancestor in a.
    Descendant,
    /// `{a} > {b}`: b spans whose parent is in a.
    Child,
    /// `{a} << {b}`: b spans that are an ancestor of an a span.
    Ancestor,
    /// `{a} < {b}`: b spans that are the parent of an a span.
    Parent,
    /// `{a} ~ {b}`: b spans sharing a parent with a different a span.
    Sibling,
}
pub(crate) struct Expression {
    spansets: Vec<Vec<Instruction>>,
    relations: Vec<Relation>,
    select: Vec<(String, String)>,
    events: bool,
    links: bool,
    instrumentation: bool,
    // Whether any leaf or selection reads resource or span attributes.
    attributes: bool,
    trace_duration: bool,
    search_only: bool,
    size: usize,
}
enum Instruction {
    True,
    And,
    Or,
    Leaf {
        scope: String,
        key: String,
        op: String,
        wanted: String,
        regex: Option<regex::Regex>,
    },
}
pub(crate) struct Evaluation {
    /// The last spanset: the spans a structural query returns.
    pub(crate) matched: bool,
    /// Bit `i` is set when spanset `i` matched this span.
    pub(crate) mask: u8,
    /// Sampled values of the last spanset's matching leaves plus `select`.
    pub(crate) attributes: Attributes,
}
impl Expression {
    pub(crate) fn compile(program: Vec<(String, String, String, String)>) -> Option<Self> {
        if program.is_empty() || program.len() > PROGRAM_MAX {
            return None;
        }
        let size = program.len();
        let search_only = program.iter().any(|(scope, key, _, _)| {
            scope.starts_with("link.")
                || scope.starts_with("instrumentation.")
                || (scope == "intrinsic.string" && key != "name")
                || (scope == "intrinsic" && key == "event:timeSinceStart")
        });
        let trace_duration = program.iter().any(|(scope, key, op, _)| {
            (scope == "intrinsic" && key == "trace_duration")
                || (scope == "intrinsic.string"
                    && ["rootName", "rootServiceName"].contains(&key.as_str()))
                || (scope == "select"
                    && key == "intrinsic"
                    && ["rootName", "rootServiceName", "trace_duration"].contains(&op.as_str()))
        });
        let (mut leaves, mut regexes, mut stack, mut events) = (0, 0, 0, false);
        let (mut links, mut instrumentation) = (false, false);
        let mut attributes = false;
        let mut spansets = vec![Vec::new()];
        let (mut relations, mut select) = (Vec::new(), Vec::new());
        for (scope, key, op, wanted) in program {
            if scope == "select" {
                let valid = match key.as_str() {
                    "resource" | "span" | "event" | "link" | "instrumentation" | "none" => {
                        (1..=256).contains(&op.len())
                    }
                    "intrinsic" => {
                        STRING_INTRINSICS.contains(&op.as_str())
                            || [
                                "status",
                                "kind",
                                "duration",
                                "trace_duration",
                                "event:timeSinceStart",
                            ]
                            .contains(&op.as_str())
                    }
                    _ => false,
                };
                if !valid || !wanted.is_empty() || select.len() == SELECT_MAX {
                    return None;
                }
                events |= key == "event" || (key == "intrinsic" && op.starts_with("event:"));
                links |= key == "link" || (key == "intrinsic" && op.starts_with("link:"));
                instrumentation |= key == "instrumentation"
                    || (key == "intrinsic" && op.starts_with("instrumentation:"));
                attributes |= ["resource", "span", "none"].contains(&key.as_str());
                select.push((key, op));
                continue;
            }
            if !select.is_empty() {
                return None;
            }
            if scope == "spanset" {
                let relation = match op.as_str() {
                    ">>" => Relation::Descendant,
                    ">" => Relation::Child,
                    "<<" => Relation::Ancestor,
                    "<" => Relation::Parent,
                    "~" => Relation::Sibling,
                    _ => return None,
                };
                if stack != 1 || !key.is_empty() || !wanted.is_empty() {
                    return None;
                }
                if spansets.len() == SPANSETS_MAX {
                    return None;
                }
                relations.push(relation);
                spansets.push(Vec::new());
                stack = 0;
                continue;
            }
            let out = spansets.last_mut()?;
            if scope == "constant" {
                if !key.is_empty() || op != "true" || !wanted.is_empty() {
                    return None;
                }
                leaves += 1;
                stack += 1;
                if leaves > 16 {
                    return None;
                }
                out.push(Instruction::True);
                continue;
            }
            if scope == "boolean" {
                if stack < 2 || !key.is_empty() || !wanted.is_empty() {
                    return None;
                }
                out.push(match op.as_str() {
                    "&&" => Instruction::And,
                    "||" => Instruction::Or,
                    _ => return None,
                });
                stack -= 1;
                continue;
            }
            leaves += 1;
            stack += 1;
            if leaves > 16
                || key.is_empty()
                || key.len() > 256
                || wanted.len() > 4096
                || wanted.contains("${")
            {
                return None;
            }
            let re = match scope.as_str() {
                "resource.string"
                | "span.string"
                | "none.string"
                | "event.string"
                | "link.string"
                | "instrumentation.string"
                | "intrinsic.string" => {
                    if scope == "intrinsic.string"
                        && (!STRING_INTRINSICS.contains(&key.as_str())
                            || (is_id(&key) && !["=", "!="].contains(&op.as_str())))
                    {
                        return None;
                    }
                    match op.as_str() {
                        "=" | "!=" => None,
                        "=~" | "!~" => {
                            regexes += 1;
                            if regexes > 8 || wanted.len() > 1024 {
                                return None;
                            }
                            Some(crate::query_regex::anchored(&wanted).ok()?)
                        }
                        _ => return None,
                    }
                }
                "resource.int"
                | "span.int"
                | "none.int"
                | "event.int"
                | "link.int"
                | "instrumentation.int"
                | "intrinsic" => {
                    if !["=", "!=", "<", "<=", ">", ">="].contains(&op.as_str()) {
                        return None;
                    }
                    let n = wanted.parse::<i64>().ok()?;
                    if scope == "intrinsic"
                        && match key.as_str() {
                            "status" => {
                                !["=", "!="].contains(&op.as_str()) || !(0..=2).contains(&n)
                            }
                            "kind" => !["=", "!="].contains(&op.as_str()) || !(0..=5).contains(&n),
                            "duration" | "trace_duration" | "event:timeSinceStart" => n < 0,
                            _ => true,
                        }
                    {
                        return None;
                    }
                    None
                }
                "resource.float"
                | "span.float"
                | "none.float"
                | "event.float"
                | "link.float"
                | "instrumentation.float" => {
                    if wanted.len() > 128
                        || !["=", "!=", "<", "<=", ">", ">="].contains(&op.as_str())
                        || !wanted.parse::<f64>().ok()?.is_finite()
                    {
                        return None;
                    }
                    None
                }
                "resource.bool"
                | "span.bool"
                | "none.bool"
                | "event.bool"
                | "link.bool"
                | "instrumentation.bool" => {
                    if !["=", "!="].contains(&op.as_str())
                        || !["true", "false"].contains(&wanted.as_str())
                    {
                        return None;
                    }
                    None
                }
                // `!= nil` (present, any type) and `= nil` (absent).
                "resource.any" | "span.any" | "none.any" | "instrumentation.any" => {
                    if !["=", "!="].contains(&op.as_str()) || wanted != "nil" {
                        return None;
                    }
                    None
                }
                _ => return None,
            };
            events |= scope.starts_with("event.")
                || (scope.starts_with("intrinsic") && key.starts_with("event:"));
            links |= scope.starts_with("link.")
                || (scope == "intrinsic.string" && key.starts_with("link:"));
            instrumentation |= scope.starts_with("instrumentation.")
                || (scope == "intrinsic.string" && key.starts_with("instrumentation:"));
            attributes |= ["resource.", "span.", "none."]
                .iter()
                .any(|prefix| scope.starts_with(prefix));
            out.push(Instruction::Leaf {
                scope,
                key,
                op,
                wanted,
                regex: re,
            });
        }
        (stack == 1).then_some(Self {
            spansets,
            relations,
            select,
            events,
            links,
            instrumentation,
            attributes,
            trace_duration,
            search_only,
            size,
        })
    }

    /// Structural operators or `select` need the search path: per-span
    /// metrics accept neither.
    pub(crate) fn span_local(&self) -> bool {
        self.relations.is_empty()
            && self.select.is_empty()
            && !self.trace_duration
            && !self.search_only
    }

    pub(crate) fn trace_duration(&self) -> bool {
        self.trace_duration
    }

    pub(crate) fn needs_context(&self) -> bool {
        self.trace_duration
    }

    pub(crate) fn relations(&self) -> &[Relation] {
        &self.relations
    }

    pub(crate) fn evaluate(
        &self,
        fields: &RawFields<'_>,
        work: &mut usize,
        collect: bool,
    ) -> Res<Evaluation> {
        self.evaluate_with(fields, None, work, collect)
    }

    /// `evaluate/3` given the typed envelope's members when the caller
    /// already has them from validation.
    pub(crate) fn evaluate_with(
        &self,
        fields: &RawFields<'_>,
        envelope: Option<&Envelope<'_>>,
        work: &mut usize,
        collect: bool,
    ) -> Res<Evaluation> {
        self.evaluate_context(fields, envelope, work, collect, None)
    }

    pub(crate) fn evaluate_trace(
        &self,
        fields: &RawFields<'_>,
        work: &mut usize,
        collect: bool,
        context: Option<&TraceContext>,
    ) -> Res<Evaluation> {
        self.evaluate_impl(fields, None, work, collect, context, true)
    }

    pub(crate) fn evaluate_context(
        &self,
        fields: &RawFields<'_>,
        envelope: Option<&Envelope<'_>>,
        work: &mut usize,
        collect: bool,
        context: Option<&TraceContext>,
    ) -> Res<Evaluation> {
        self.evaluate_impl(fields, envelope, work, collect, context, false)
    }

    fn evaluate_impl(
        &self,
        fields: &RawFields<'_>,
        envelope: Option<&Envelope<'_>>,
        work: &mut usize,
        collect: bool,
        context: Option<&TraceContext>,
        parquet_ids: bool,
    ) -> Res<Evaluation> {
        let parsed;
        let meta = match envelope {
            Some(envelope) => &envelope.members,
            None => {
                parsed = object(field(fields, b"otlp")?)?;
                &parsed
            }
        };
        // A validated envelope already counted its attributes; programs that
        // read none of them need not build the maps.
        let (resource, span, owned) = match envelope {
            Some(envelope) if !self.attributes => (
                Owner::new(),
                Owner::new(),
                envelope.resource + envelope.span,
            ),
            _ => {
                let resource = attributes(field(meta, b"resource")?)?;
                let span = attributes(field(meta, b"attributes")?)?;
                let owned = resource.len() + span.len();
                (resource, span, owned)
            }
        };
        let mut units = 2 + owned + self.size;
        let events = if self.events {
            repeated(fields, meta, b"events", &mut units)?
        } else {
            Vec::new()
        };
        let links = if self.links {
            repeated(fields, meta, b"links", &mut units)?
        } else {
            Vec::new()
        };
        let instrumentation = if self.instrumentation {
            let a = attributes(field(meta, b"scope")?)?;
            units += 1 + a.len();
            a
        } else {
            Owner::new()
        };
        // Repeated-owner pushdown and bounded select may revisit predicates.
        // Charge the conservative bound before performing any of that work.
        units += (events.len() + links.len()) * self.size * (2 * self.size + SELECT_MAX);
        // Charge all owners, attributes and instructions before filtering, in
        // both candidate and retained-context passes, including nonmatches.
        *work = work
            .checked_add(units)
            .ok_or_else(|| Error::budget("expression_work", WORK_MAX, usize::MAX))?;
        if *work > WORK_MAX {
            return Err(Error::budget("expression_work", WORK_MAX, *work));
        }
        let owners = Owners {
            resource: &resource,
            span: &span,
            events: &events,
            links: &links,
            instrumentation: &instrumentation,
            context,
            parquet_ids,
        };
        let mut attrs = BTreeMap::new();
        let mut mask = 0u8;
        let last = self.spansets.len() - 1;
        for (i, program) in self.spansets.iter().enumerate() {
            let sink = (collect && i == last).then_some(&mut attrs);
            if run(program, fields, &owners, sink)? {
                mask |= 1 << i;
            }
        }
        if collect {
            for (scope, key) in &self.select {
                if let Some((owner, value)) = owners.select_program(
                    fields,
                    scope,
                    key,
                    self.spansets.last().ok_or(Error::Invalid)?,
                )? {
                    attrs
                        .entry((key.clone(), owner.to_owned()))
                        .or_insert(value);
                }
            }
        }
        Ok(Evaluation {
            matched: mask & (1 << last) != 0,
            mask,
            attributes: attrs,
        })
    }
}
struct Owners<'a, 'b> {
    resource: &'a Owner<'b>,
    span: &'a Owner<'b>,
    events: &'a [Repeated<'b>],
    links: &'a [Repeated<'b>],
    instrumentation: &'a Owner<'b>,
    context: Option<&'a TraceContext>,
    parquet_ids: bool,
}
struct Repeated<'a> {
    attrs: Owner<'a>,
    meta: RawFields<'a>,
}
struct RepeatedValue {
    actual: Option<Vec<u8>>,
    sampled: Option<Vec<u8>>,
}
fn repeated<'a>(
    fields: &RawFields<'a>,
    meta: &RawFields<'a>,
    key: &[u8],
    units: &mut usize,
) -> Res<Vec<Repeated<'a>>> {
    let values = Parser::new(field(fields, key)?)
        .raw_array()
        .map_err(|_| Error::Invalid)?;
    let attrs = Parser::new(field(meta, key)?)
        .raw_array()
        .map_err(|_| Error::Invalid)?;
    values
        .into_iter()
        .zip(attrs)
        .map(|(value, attrs)| {
            let attrs = attributes(attrs)?;
            *units += 1 + attrs.len();
            Ok(Repeated {
                attrs,
                meta: object(value)?,
            })
        })
        .collect()
}
impl Owners<'_, '_> {
    fn select_program(
        &self,
        fields: &RawFields<'_>,
        scope: &str,
        key: &str,
        program: &[Instruction],
    ) -> Res<Option<(&'static str, Vec<u8>)>> {
        let repeated_scope = if scope == "intrinsic" {
            key.split(':').next().unwrap_or("")
        } else {
            scope
        };
        if ["event", "link"].contains(&repeated_scope) {
            let all = if repeated_scope == "event" {
                self.events
            } else {
                self.links
            };
            let mut found = None;
            for owner in all {
                if owner_admitted(program, repeated_scope, owner, fields)? {
                    found = Some(owner);
                }
            }
            if scope == "intrinsic" {
                let empty = Repeated {
                    attrs: Owner::new(),
                    meta: Vec::new(),
                };
                let value = repeated_value(
                    if key == "event:timeSinceStart" {
                        "intrinsic"
                    } else {
                        "intrinsic.string"
                    },
                    key,
                    found.unwrap_or(&empty),
                    fields,
                )?;
                return Ok(value.sampled.map(|v| ("intrinsic", v)));
            }
            // Last present selected value, not simply the last owner.
            let mut value = None;
            for owner in all {
                if owner_admitted(program, repeated_scope, owner, fields)? {
                    if let Some(raw) = owner.attrs.get(key) {
                        value = Some(raw.to_vec());
                    }
                }
            }
            return Ok(value.map(|v| (if scope == "event" { "event" } else { "link" }, v)));
        }
        if scope == "instrumentation" {
            return Ok(self
                .instrumentation
                .get(key)
                .map(|v| ("instrumentation", v.to_vec())));
        }
        if scope == "intrinsic" && OMITTED.contains(&key) {
            return Ok(None);
        }
        self.select(fields, scope, key)
    }
    fn select(
        &self,
        fields: &RawFields<'_>,
        scope: &str,
        key: &str,
    ) -> Res<Option<(&'static str, Vec<u8>)>> {
        let found = match scope {
            "resource" => self.resource.get(key).map(|raw| ("resource", raw.to_vec())),
            "span" => self.span.get(key).map(|raw| ("span", raw.to_vec())),
            "none" => match self.span.get(key) {
                Some(raw) => Some(("span", raw.to_vec())),
                None => self.resource.get(key).map(|raw| ("resource", raw.to_vec())),
            },
            "event" => self
                .events
                .iter()
                .find_map(|event| event.attrs.get(key))
                .map(|raw| ("event", raw.to_vec())),
            _ => {
                let value = match key {
                    "name" => string(field(fields, b"name")?)?,
                    "status" => {
                        let code = crate::tempo_search::integer(field(
                            &object(field(fields, b"status")?)?,
                            b"code",
                        )?)?;
                        ["unset", "ok", "error"]
                            .get(code as usize)
                            .ok_or(Error::Invalid)?
                            .to_string()
                    }
                    "kind" => {
                        let kind = crate::tempo_search::integer(field(fields, b"kind")?)?;
                        [
                            "unspecified",
                            "internal",
                            "server",
                            "client",
                            "producer",
                            "consumer",
                        ]
                        .get(kind as usize)
                        .ok_or(Error::Invalid)?
                        .to_string()
                    }
                    _ => scalar_intrinsic(fields, key, self.context)?.ok_or(Error::Invalid)?,
                };
                let mut out = b"{\"stringValue\":".to_vec();
                crate::json_write::write_str(&mut out, value.as_bytes());
                out.push(b'}');
                Some(("intrinsic", out))
            }
        };
        Ok(found)
    }
}
fn run(
    program: &[Instruction],
    fields: &RawFields<'_>,
    owners: &Owners<'_, '_>,
    mut attrs: Option<&mut Attributes>,
) -> Res<bool> {
    let collect = attrs.is_some();
    let mut stack = Vec::with_capacity(16);
    for instruction in program {
        match instruction {
            Instruction::True => stack.push(true),
            Instruction::And | Instruction::Or => {
                let rhs = stack.pop().ok_or(Error::Invalid)?;
                let lhs = stack.pop().ok_or(Error::Invalid)?;
                stack.push(if matches!(instruction, Instruction::And) {
                    lhs && rhs
                } else {
                    lhs || rhs
                });
            }
            Instruction::Leaf {
                scope,
                key,
                op,
                wanted,
                regex,
            } => {
                let (matched, value) = if scope == "intrinsic" && key == "trace_duration" {
                    // Unknown during candidate discovery: true is conservative
                    // for every AND/OR program, including negative comparisons.
                    let wanted = wanted.parse::<i64>().map_err(|_| Error::Invalid)?;
                    (
                        owners
                            .context
                            .is_none_or(|ctx| compare(ctx.duration(), wanted, op)),
                        None,
                    )
                } else if repeated_scope(instruction).is_some() {
                    let scope_name = repeated_scope(instruction).ok_or(Error::Invalid)?;
                    let repeated = if scope_name == "event" {
                        owners.events
                    } else {
                        owners.links
                    };
                    let mut first = None;
                    let mut found = None;
                    for owner in repeated {
                        if !owner_admitted(program, scope_name, owner, fields)? {
                            continue;
                        }
                        let mut fetched = false;
                        for other in program {
                            if let Instruction::Leaf {
                                scope: other_scope,
                                key: other_key,
                                ..
                            } = other
                            {
                                if other_key == key
                                    && repeated_scope(other) == Some(scope_name)
                                    && scope.starts_with("intrinsic")
                                        == other_scope.starts_with("intrinsic")
                                    && repeated_matches(other, owner, fields)?
                                {
                                    fetched = true;
                                    break;
                                }
                            }
                        }
                        if fetched {
                            let value = repeated_value(scope, key, owner, fields)?;
                            if first.is_none() {
                                first = value.actual;
                            }
                            found = value.sampled;
                        }
                    }
                    let matched = first.as_ref().map_or(Ok(false), |raw| {
                        attribute_matches(raw, value_type(scope, key), op, wanted, regex.as_ref())
                    })?;
                    (matched, found.filter(|_| collect))
                } else if scope == "intrinsic.string" {
                    let name = scalar_intrinsic(fields, key, owners.context)?;
                    if name.is_none() {
                        stack.push(true);
                        continue;
                    }
                    let name = name.ok_or(Error::Invalid)?;
                    let normalized = if key == "trace:id" {
                        wanted.trim_start_matches('0')
                    } else {
                        wanted.as_str()
                    };
                    let positive = regex
                        .as_ref()
                        .map_or(name == normalized, |r| r.is_match(&name));
                    let mut matched = if op == "!=" || op == "!~" {
                        !positive
                    } else {
                        positive
                    };
                    if is_id(key) {
                        matched = id_matches(
                            key,
                            &name,
                            wanted,
                            op,
                            owners.parquet_ids && conjunction(program),
                        );
                    }
                    let value = if collect && matched && !OMITTED.contains(&key.as_str()) {
                        owners
                            .select(fields, "intrinsic", key)?
                            .map(|(_, value)| value)
                    } else {
                        None
                    };
                    (matched, value)
                } else if scope == "intrinsic" {
                    let n = if key == "status" {
                        crate::tempo_search::integer(field(
                            &object(field(fields, b"status")?)?,
                            b"code",
                        )?)?
                    } else if key == "kind" {
                        crate::tempo_search::integer(field(fields, b"kind")?)?
                    } else {
                        crate::tempo_search::integer(field(fields, b"end_timestamp_ns")?)?
                            - crate::tempo_search::integer(field(fields, b"timestamp_ns")?)?
                    };
                    let value = if collect && key != "duration" {
                        owners
                            .select(fields, "intrinsic", key)?
                            .map(|(_, value)| value)
                    } else {
                        None
                    };
                    (
                        compare(n, wanted.parse().map_err(|_| Error::Invalid)?, op),
                        value,
                    )
                } else if scope.starts_with("none.") {
                    let value_type = scope.rsplit('.').next().ok_or(Error::Invalid)?;
                    if let Some(attrs) = attrs.as_deref_mut() {
                        for (name, owner) in [("resource", owners.resource), ("span", owners.span)]
                        {
                            if let Some(raw) = owner.get(key.as_str()) {
                                if attribute_matches(raw, value_type, op, wanted, regex.as_ref())? {
                                    attrs.insert((key.clone(), name.to_owned()), raw.to_vec());
                                }
                            }
                        }
                    }
                    // An original span value wins even if its type/value
                    // does not match. Samples above retain both owners.
                    let matched = owners
                        .span
                        .get(key.as_str())
                        .or_else(|| owners.resource.get(key.as_str()))
                        .map_or(Ok(value_type == "any" && op == "="), |raw| {
                            attribute_matches(raw, value_type, op, wanted, regex.as_ref())
                        })?;
                    (matched, None)
                } else {
                    let owner = if scope.starts_with("resource.") {
                        owners.resource
                    } else if scope.starts_with("instrumentation.") {
                        owners.instrumentation
                    } else {
                        owners.span
                    };
                    match owner.get(key.as_str()) {
                        None => (scope.ends_with(".any") && op == "=", None),
                        Some(raw) => {
                            let matched = attribute_matches(
                                raw,
                                scope.rsplit('.').next().ok_or(Error::Invalid)?,
                                op,
                                wanted,
                                regex.as_ref(),
                            )?;
                            (matched, (collect && matched).then(|| raw.to_vec()))
                        }
                    }
                };
                if matched || repeated_scope(instruction).is_some() {
                    if let (Some(value), Some(attrs)) = (value, attrs.as_deref_mut()) {
                        let owner = scope.split('.').next().unwrap_or(scope);
                        attrs.insert((key.clone(), owner.to_owned()), value);
                    }
                }
                stack.push(matched);
            }
        }
    }
    stack.pop().ok_or(Error::Invalid)
}

fn scalar_intrinsic(
    fields: &RawFields<'_>,
    key: &str,
    context: Option<&TraceContext>,
) -> Res<Option<String>> {
    Ok(Some(match key {
        "name" => string(field(fields, b"name")?)?,
        "statusMessage" => string(field(&object(field(fields, b"status")?)?, b"message")?)?,
        "span:id" => string(field(fields, b"span_id")?)?,
        "span:parentID" => match field(fields, b"parent_span_id")? {
            b"null" => "0000000000000000".into(),
            raw => string(raw)?,
        },
        "trace:id" => string(field(fields, b"trace_id")?)?
            .trim_start_matches('0')
            .to_owned(),
        "instrumentation:name" | "instrumentation:version" => {
            let scope = object(field(fields, b"scope")?)?;
            field(
                &scope,
                if key.ends_with("name") {
                    b"name"
                } else {
                    b"version"
                },
            )
            .ok()
            .map(string)
            .transpose()?
            .unwrap_or_default()
        }
        "rootName" | "rootServiceName" => match context {
            None => return Ok(None),
            Some(ctx) => {
                if ctx.root_conflict {
                    return Err(Error::Root);
                }
                if key == "rootServiceName" && ctx.root.is_some() && !ctx.root_service_known {
                    return Err(Error::RootUnknown);
                }
                ctx.root
                    .as_ref()
                    .map(|(service, name)| {
                        if key == "rootName" {
                            name.clone()
                        } else {
                            service.clone()
                        }
                    })
                    .unwrap_or_default()
            }
        },
        _ => return Err(Error::Invalid),
    }))
}
fn string_value(s: &str) -> Vec<u8> {
    let mut out = b"{\"stringValue\":".to_vec();
    crate::json_write::write_str(&mut out, s.as_bytes());
    out.push(b'}');
    out
}
fn repeated_scope(instruction: &Instruction) -> Option<&'static str> {
    if let Instruction::Leaf { scope, key, .. } = instruction {
        if scope.starts_with("event.")
            || (scope.starts_with("intrinsic") && key.starts_with("event:"))
        {
            return Some("event");
        }
        if scope.starts_with("link.") || (scope == "intrinsic.string" && key.starts_with("link:")) {
            return Some("link");
        }
    }
    None
}
fn conjunction(program: &[Instruction]) -> bool {
    !program.iter().any(|i| matches!(i, Instruction::Or))
}
fn owner_admitted(
    program: &[Instruction],
    scope_name: &str,
    owner: &Repeated<'_>,
    fields: &RawFields<'_>,
) -> Res<bool> {
    let all = conjunction(program);
    let mut any = false;
    let mut count = 0;
    for leaf in program {
        if repeated_scope(leaf) != Some(scope_name) {
            continue;
        }
        if let Instruction::Leaf {
            scope,
            key,
            op,
            wanted,
            regex,
        } = leaf
        {
            count += 1;
            let value = repeated_value(scope, key, owner, fields)?;
            let matched = value.actual.as_ref().map_or(Ok(false), |raw| {
                attribute_matches(raw, value_type(scope, key), op, wanted, regex.as_ref())
            })?;
            if all && !matched {
                return Ok(false);
            }
            any |= matched;
        }
    }
    Ok(count == 0 || all || any)
}
fn value_type<'a>(scope: &'a str, key: &str) -> &'a str {
    if key == "event:timeSinceStart" && scope == "intrinsic" {
        "int"
    } else if scope == "intrinsic.string" {
        "string"
    } else {
        scope.rsplit('.').next().unwrap_or("")
    }
}
fn repeated_matches(leaf: &Instruction, owner: &Repeated<'_>, fields: &RawFields<'_>) -> Res<bool> {
    if let Instruction::Leaf {
        scope,
        key,
        op,
        wanted,
        regex,
    } = leaf
    {
        let value = repeated_value(scope, key, owner, fields)?;
        value.actual.as_ref().map_or(Ok(false), |raw| {
            attribute_matches(raw, value_type(scope, key), op, wanted, regex.as_ref())
        })
    } else {
        Ok(false)
    }
}
fn repeated_value(
    scope: &str,
    key: &str,
    owner: &Repeated<'_>,
    fields: &RawFields<'_>,
) -> Res<RepeatedValue> {
    if scope == "intrinsic" {
        let ns = field(&owner.meta, b"timestamp_ns")
            .ok()
            .map(crate::tempo_search::integer)
            .transpose()?
            .map_or(0, |n| {
                n - crate::tempo_search::integer(field(fields, b"timestamp_ns").unwrap_or(b"0"))
                    .unwrap_or(0)
            });
        let sample = if ns < 0 {
            format!("-{}", crate::tempo_duration::format(ns.unsigned_abs()))
        } else {
            crate::tempo_duration::format(ns as u64)
        };
        return Ok(RepeatedValue {
            actual: Some(format!("{{\"intValue\":\"{ns}\"}}").into_bytes()),
            sampled: Some(string_value(&sample)),
        });
    }
    if scope == "intrinsic.string" {
        let value = match key {
            "event:name" => field(&owner.meta, b"name")
                .ok()
                .map(string)
                .transpose()?
                .unwrap_or_default(),
            "link:traceID" => field(&owner.meta, b"trace_id")
                .ok()
                .map(string)
                .transpose()?
                .unwrap_or_default()
                .trim_start_matches('0')
                .to_owned(),
            "link:spanID" => field(&owner.meta, b"span_id")
                .ok()
                .map(string)
                .transpose()?
                .unwrap_or_else(|| "0000000000000000".into()),
            _ => return Err(Error::Invalid),
        };
        let raw = string_value(&value);
        return Ok(RepeatedValue {
            actual: Some(raw.clone()),
            sampled: Some(raw),
        });
    }
    let value = owner.attrs.get(key).map(|v| v.to_vec());
    Ok(RepeatedValue {
        actual: value.clone(),
        sampled: value,
    })
}
fn is_id(key: &str) -> bool {
    [
        "span:id",
        "span:parentID",
        "trace:id",
        "link:traceID",
        "link:spanID",
    ]
    .contains(&key)
}
fn id_matches(key: &str, actual: &str, wanted: &str, op: &str, pushdown: bool) -> bool {
    let normalized = if key == "trace:id" {
        wanted.trim_start_matches('0')
    } else {
        wanted
    };
    let equal = actual == normalized;
    let engine = if op == "!=" { !equal } else { equal };
    if !pushdown || !["span:id", "span:parentID"].contains(&key) {
        return engine;
    }
    // The pinned Parquet predicate decodes span IDs without padding after
    // trimming leading zeroes. Preserve its byte-width filter as well as the
    // public engine's case-sensitive string comparison; do not invent coercion.
    let wanted = wanted.trim_start_matches('0');
    if !wanted.bytes().all(|c| c.is_ascii_hexdigit()) || wanted.len() > 16 {
        return engine;
    }
    let expected = if wanted.len() % 2 == 1 {
        format!("0{wanted}")
    } else {
        wanted.to_owned()
    };
    let stored = if key == "span:parentID" && actual == "0000000000000000" {
        ""
    } else {
        actual
    };
    let equal = stored == expected.to_ascii_lowercase();
    engine && if op == "!=" { !equal } else { equal }
}
/// One stored span of a trace: span ID, parent span ID and spanset mask.
pub(crate) type Link = (u64, Option<u64>, u8);
/// Which spans of one trace a structural chain returns. Relations follow
/// parent span IDs, so duplicate rows of one span share its relatives, a
/// missing parent ends a chain, and cycles terminate. Linear in the spans.
pub(crate) fn structural(relations: &[Relation], spans: &[Link]) -> Vec<bool> {
    let mut children: HashMap<u64, Vec<u64>> = HashMap::new();
    let mut parents: HashMap<u64, Vec<u64>> = HashMap::new();
    for (id, parent, _) in spans {
        if let Some(parent) = parent {
            children.entry(*parent).or_default().push(*id);
            parents.entry(*id).or_default().push(*parent);
        }
    }
    let mut current: Vec<bool> = spans.iter().map(|(_, _, mask)| mask & 1 != 0).collect();
    for (i, relation) in relations.iter().enumerate() {
        let bit = 1u8 << (i + 1);
        let ids: HashSet<u64> = spans
            .iter()
            .zip(&current)
            .filter(|(_, c)| **c)
            .map(|((id, _, _), _)| *id)
            .collect();
        let candidate = |s: &Link| s.2 & bit != 0;
        current = match relation {
            Relation::Child => spans
                .iter()
                .map(|s| candidate(s) && s.1.is_some_and(|p| ids.contains(&p)))
                .collect(),
            Relation::Parent => {
                let wanted: HashSet<u64> = spans
                    .iter()
                    .zip(&current)
                    .filter_map(|(s, c)| s.1.filter(|_| *c))
                    .collect();
                spans
                    .iter()
                    .map(|s| candidate(s) && wanted.contains(&s.0))
                    .collect()
            }
            Relation::Descendant => {
                let down = closure(ids.iter().copied(), &children);
                spans
                    .iter()
                    .map(|s| candidate(s) && s.1.is_some_and(|p| down.contains(&p)))
                    .collect()
            }
            Relation::Ancestor => {
                let seeds = spans
                    .iter()
                    .zip(&current)
                    .filter_map(|(s, c)| s.1.filter(|_| *c));
                let up = closure(seeds, &parents);
                spans
                    .iter()
                    .map(|s| candidate(s) && up.contains(&s.0))
                    .collect()
            }
            Relation::Sibling => {
                let mut by_parent: HashMap<u64, HashSet<u64>> = HashMap::new();
                for (s, c) in spans.iter().zip(&current) {
                    if let (true, Some(parent)) = (*c, s.1) {
                        by_parent.entry(parent).or_default().insert(s.0);
                    }
                }
                spans
                    .iter()
                    .map(|s| {
                        candidate(s)
                            && s.1.is_some_and(|p| {
                                by_parent
                                    .get(&p)
                                    .is_some_and(|ids| ids.iter().any(|id| *id != s.0))
                            })
                    })
                    .collect()
            }
        };
    }
    current
}
// Seeds plus everything reachable from them through `edges`.
fn closure(seeds: impl Iterator<Item = u64>, edges: &HashMap<u64, Vec<u64>>) -> HashSet<u64> {
    let mut seen = HashSet::new();
    let mut queue: Vec<u64> = Vec::new();
    for seed in seeds {
        if seen.insert(seed) {
            queue.push(seed);
        }
    }
    while let Some(id) = queue.pop() {
        for next in edges.get(&id).into_iter().flatten() {
            if seen.insert(*next) {
                queue.push(*next);
            }
        }
    }
    seen
}
fn attribute_matches(
    raw: &[u8],
    value_type: &str,
    op: &str,
    wanted: &str,
    regex: Option<&regex::Regex>,
) -> Res<bool> {
    let value = object(raw)?;
    if value_type == "any" {
        Ok(op == "!=")
    } else if value_type == "string" {
        match field(&value, b"stringValue") {
            Ok(text) => {
                let text = string(text)?;
                let positive = regex.map_or(text == wanted, |r| r.is_match(&text));
                Ok(if op == "!=" || op == "!~" {
                    !positive
                } else {
                    positive
                })
            }
            Err(_) => Ok(false),
        }
    } else if value_type == "float" {
        match field(&value, b"doubleValue") {
            Ok(n) => Ok(compare(
                crate::trace_metadata::double(n).map_err(|_| Error::Invalid)?,
                wanted.parse::<f64>().map_err(|_| Error::Invalid)?,
                op,
            )),
            Err(_) => Ok(false),
        }
    } else if value_type == "bool" {
        match field(&value, b"boolValue") {
            Ok(n) => Ok(compare(n == b"true", wanted == "true", op)),
            Err(_) => Ok(false),
        }
    } else {
        match field(&value, b"intValue") {
            Ok(n) => Ok(compare(
                string(n)?.parse::<i64>().map_err(|_| Error::Invalid)?,
                wanted.parse::<i64>().map_err(|_| Error::Invalid)?,
                op,
            )),
            Err(_) => Ok(false),
        }
    }
}
/// Typed attributes by key; keys borrow the payload unless escaped, since
/// every scanned row builds these maps.
pub(crate) type Owner<'a> = BTreeMap<Cow<'a, str>, &'a [u8]>;
pub(crate) fn attributes(raw: &[u8]) -> Res<Owner<'_>> {
    let mut parser = Parser::new(raw);
    let mut out = BTreeMap::new();
    for pair in parser.raw_array().map_err(|_| Error::Invalid)? {
        let pair = object(pair)?;
        let key = borrowed_string(field(&pair, b"key")?)?;
        if out.insert(key, field(&pair, b"value")?).is_some() {
            return Err(Error::Invalid);
        }
    }
    Ok(out)
}
// `string/1` without copying unescaped text.
fn borrowed_string(raw: &[u8]) -> Res<Cow<'_, str>> {
    let mut parser = Parser::new(raw);
    let value = parser.string().map_err(|_| Error::Invalid)?;
    parser.ws();
    parser.end().map_err(|_| Error::Invalid)?;
    match value {
        Cow::Borrowed(bytes) => std::str::from_utf8(bytes)
            .map(Cow::Borrowed)
            .map_err(|_| Error::Invalid),
        Cow::Owned(bytes) => String::from_utf8(bytes)
            .map(Cow::Owned)
            .map_err(|_| Error::Invalid),
    }
}
fn compare<T: PartialEq + PartialOrd>(left: T, right: T, op: &str) -> bool {
    match op {
        "=" => left == right,
        "!=" => left != right,
        "<" => left < right,
        "<=" => left <= right,
        ">" => left > right,
        ">=" => left >= right,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn leaf(scope: &str, key: &str, op: &str, value: &str) -> (String, String, String, String) {
        (scope.into(), key.into(), op.into(), value.into())
    }

    #[test]
    fn context_charges_all_original_link_attributes_and_defers_root_ambiguity() {
        let a=br#"{"trace_id":"00000000000000000000000000000001","span_id":"0000000000000001","parent_span_id":null,"timestamp_ns":100,"end_timestamp_ns":101,"name":"root","links":[{"trace_id":"00000000000000000000000000000002"}],"otlp":{"resource":[],"attributes":[],"links":[[{"key":"opentracing.ref_type","value":{"stringValue":"child_of"}},{"key":"other","value":{"boolValue":true}}]]}}"#;
        let fields = object(a).unwrap();
        let mut context = TraceContext::default();
        let mut work = 0;
        context.observe(&fields, &mut work).unwrap();
        assert_eq!(work, 5); // two owners, link owner, both original link attrs
        assert_eq!(context.root.as_ref().unwrap().1, "root"); // foreign child_of link is not a parent
        assert!(matches!(
            TraceContext::default().observe(&fields, &mut (WORK_MAX - 4)),
            Err(Error::Budget)
        ));
        let b = String::from_utf8(a.to_vec())
            .unwrap()
            .replace(
                "\"span_id\":\"0000000000000001\"",
                "\"span_id\":\"0000000000000002\"",
            )
            .replace("\"end_timestamp_ns\":101", "\"end_timestamp_ns\":200");
        context
            .observe(&object(b.as_bytes()).unwrap(), &mut work)
            .unwrap();
        assert!(context.root_conflict);
        let duration =
            Expression::compile(vec![leaf("intrinsic", "trace_duration", ">", "50")]).unwrap();
        assert!(
            duration
                .evaluate_context(&fields, None, &mut work, false, Some(&context))
                .unwrap()
                .matched
        );
        let root =
            Expression::compile(vec![leaf("intrinsic.string", "rootName", "=", "root")]).unwrap();
        assert!(matches!(
            root.evaluate_context(&fields, None, &mut work, false, Some(&context)),
            Err(Error::Root)
        ));
    }

    #[test]
    fn malformed_programs_cannot_bypass_the_frontend() {
        for program in [
            vec![],
            vec![leaf("boolean", "", "||", "")],
            vec![leaf("span.int", "code", "=", "9223372036854775808")],
            vec![leaf("intrinsic", "duration", ">", "-1")],
            vec![leaf("intrinsic", "trace_duration", ">", "-1")],
            vec![leaf("intrinsic", "status", "=", "3")],
            vec![leaf("intrinsic", "status", ">", "1")],
            vec![leaf("span.string", "route", "!~", "(?=x)")],
            vec![leaf("span.string", "route", "!~", "${route}")],
            vec![leaf("span.int", "code", "=", "1"); 32],
        ] {
            assert!(Expression::compile(program).is_none());
        }
    }
    #[test]
    fn trace_duration_is_conservative_only_until_complete_context_and_never_span_local() {
        let fields = object(br#"{"otlp":{"resource":[],"attributes":[]}}"#).unwrap();
        for (op, expected) in [
            ("=", false),
            ("!=", true),
            ("<", false),
            ("<=", false),
            (">", true),
            (">=", true),
        ] {
            let expression =
                Expression::compile(vec![leaf("intrinsic", "trace_duration", op, "1000000000")])
                    .unwrap();
            assert!(expression.trace_duration());
            assert!(!expression.span_local());
            let mut work = 0;
            assert!(
                expression
                    .evaluate(&fields, &mut work, false)
                    .unwrap()
                    .matched
            );
            let context = TraceContext {
                start: 0,
                end: 7200002000000,
                ..Default::default()
            };
            let final_value = expression
                .evaluate_trace(&fields, &mut work, true, Some(&context))
                .unwrap();
            assert_eq!(final_value.matched, expected);
            assert!(final_value.attributes.is_empty());
            assert_eq!(work, 6);
            assert!(matches!(
                expression.evaluate_trace(&fields, &mut (WORK_MAX - 2), true, Some(&context)),
                Err(Error::Budget)
            ));
        }
    }
    #[test]
    fn negative_regex_requires_original_string_and_work_is_charged_before_truth() {
        let expression =
            Expression::compile(vec![leaf("span.string", "route", "!~", "/health")]).unwrap();
        for (value, expected) in [
            (r#"{"stringValue":"/health"}"#, false),
            (r#"{"stringValue":"/work"}"#, true),
            (r#"{"intValue":"503"}"#, false),
            (r#"{"boolValue":true}"#, false),
        ] {
            let payload = format!(
                r#"{{"otlp":{{"resource":[],"attributes":[{{"key":"route","value":{value}}}]}}}}"#
            );
            let fields = object(payload.as_bytes()).unwrap();
            let mut work = 0;
            assert_eq!(
                expression
                    .evaluate(&fields, &mut work, true)
                    .unwrap()
                    .matched,
                expected
            );
            assert_eq!(work, 4);
            work = WORK_MAX - 3;
            assert!(matches!(
                expression.evaluate(&fields, &mut work, false),
                Err(Error::Budget)
            ));
        }
        let fields = object(br#"{"otlp":{"resource":[],"attributes":[]}}"#).unwrap();
        assert!(!expression.evaluate(&fields, &mut 0, false).unwrap().matched);
    }
    #[test]
    fn int64_comparison_is_exact_and_nonmatching_or_attributes_are_not_invented() {
        let expression = Expression::compile(vec![
            leaf("intrinsic", "status", "=", "2"),
            leaf("span.int", "code", "=", "9007199254740993"),
            leaf("boolean", "", "||", ""),
        ])
        .unwrap();
        let fields = object(br#"{"status":{"code":0},"otlp":{"resource":[],"attributes":[{"key":"code","value":{"intValue":"9007199254740993"}}]}}"#).unwrap();
        let candidate = expression.evaluate(&fields, &mut 0, false).unwrap();
        assert!(candidate.matched);
        assert!(candidate.attributes.is_empty());
        let got = expression.evaluate(&fields, &mut 0, true).unwrap();
        assert!(got.matched);
        assert_eq!(got.attributes.len(), 1);
        assert!(got.attributes.contains_key(&("code".into(), "span".into())));
    }
    #[test]
    fn event_pushdown_keeps_matching_owner_and_charges_selection_revisits() {
        let expression = Expression::compile(vec![
            leaf("event.string", "exception.type", "=", "B"),
            leaf("select", "event", "exception.message", ""),
            leaf("select", "intrinsic", "status", ""),
        ])
        .unwrap();
        let payload = br#"{"status":{"code":2},"events":[{},{}],"otlp":{"resource":[],"attributes":[],"events":[[{"key":"exception.type","value":{"stringValue":"A"}},{"key":"exception.message","value":{"stringValue":"first"}}],[{"key":"exception.type","value":{"stringValue":"B"}}]]}}"#;
        let fields = object(payload).unwrap();
        let mut work = 0;
        let got = expression.evaluate(&fields, &mut work, true).unwrap();
        assert!(got.matched);
        // Owners, instructions, original attrs, plus conservative owner revisits.
        assert_eq!(work, 2 + 3 + 3 + 2 + 2 * 3 * (2 * 3 + 8));
        let keys: Vec<_> = got.attributes.keys().cloned().collect();
        assert_eq!(
            keys,
            vec![
                ("exception.type".to_string(), "event".to_string()),
                ("status".to_string(), "intrinsic".to_string()),
            ]
        );
        assert_eq!(
            got.attributes[&("exception.type".to_string(), "event".to_string())],
            br#"{"stringValue":"B"}"#.to_vec()
        );
        let absent =
            Expression::compile(vec![leaf("event.string", "exception.type", "!=", "")]).unwrap();
        let fields = object(br#"{"events":[{}],"otlp":{"resource":[],"attributes":[{"key":"exception.type","value":{"stringValue":"span"}}],"events":[[{"key":"exception.type","value":{"intValue":"1"}}]]}}"#).unwrap();
        assert!(!absent.evaluate(&fields, &mut 0, false).unwrap().matched);
    }
    #[test]
    fn spansets_and_selects_are_ordered_and_bounded() {
        let a = leaf("span.string", "a", "=", "x");
        for program in [
            vec![a.clone(), leaf("spanset", "", ">>", "")],
            vec![leaf("spanset", "", ">>", ""), a.clone()],
            vec![a.clone(), leaf("spanset", "", "&>>", ""), a.clone()],
            vec![a.clone(), leaf("select", "event", "k", ""), a.clone()],
            [vec![a.clone()], vec![leaf("select", "span", "k", ""); 9]].concat(),
            std::iter::once(a.clone())
                .chain((0..4).flat_map(|_| [leaf("spanset", "", ">", ""), a.clone()]))
                .collect(),
        ] {
            assert!(Expression::compile(program).is_none());
        }
        for select in [
            leaf("select", "intrinsic", "duration", ""),
            leaf("select", "link", "k", ""),
        ] {
            let expression = Expression::compile(vec![a.clone(), select]).unwrap();
            assert!(!expression.span_local());
        }
        let chain = std::iter::once(a.clone())
            .chain((0..3).flat_map(|_| [leaf("spanset", "", "~", ""), a.clone()]))
            .collect();
        let chain = Expression::compile(chain).unwrap();
        assert_eq!(chain.relations().len(), 3);
        assert!(!chain.span_local());
    }
    #[test]
    fn structural_relations_follow_parent_links() {
        // 1 -> 2 -> 3 -> 4, 2 -> 5; 6 is an orphan whose parent 9 is missing.
        let spans: Vec<Link> = vec![
            (1, None, 0b01),
            (2, Some(1), 0b00),
            (3, Some(2), 0b10),
            (4, Some(3), 0b11),
            (5, Some(2), 0b10),
            (6, Some(9), 0b10),
        ];
        let run = |r| structural(&[r], &spans);
        assert_eq!(
            run(Relation::Descendant),
            [false, false, true, true, true, false]
        );
        assert_eq!(run(Relation::Child), [false; 6]);
        // {span 1 or 4} << {lhs bit 1}: ancestors of 4 are 3, 2, 1.
        assert_eq!(
            run(Relation::Ancestor),
            [false, false, true, false, false, false]
        );
        assert_eq!(
            run(Relation::Parent),
            [false, false, true, false, false, false]
        );
        let siblings: Vec<Link> = vec![
            (1, None, 0b00),
            (2, Some(1), 0b11),
            (3, Some(1), 0b10),
            (4, None, 0b11),
            (5, None, 0b11),
        ];
        // A span is not its own sibling; parentless spans have no siblings.
        assert_eq!(
            structural(&[Relation::Sibling], &siblings),
            [false, false, true, false, false]
        );
        // Cycles terminate.
        let cycle: Vec<Link> = vec![(1, Some(2), 0b01), (2, Some(1), 0b10)];
        assert_eq!(structural(&[Relation::Descendant], &cycle), [false, true]);
        assert_eq!(
            structural(
                &[Relation::Descendant, Relation::Child],
                &[
                    (1, None, 0b001),
                    (2, Some(1), 0b010),
                    (3, Some(2), 0b100),
                    (4, Some(1), 0b100)
                ]
            ),
            [false, false, true, false]
        );
    }

    #[test]
    fn validated_envelopes_evaluate_like_reparsing() {
        let payload = |status: u8, events: &str, typed: &str| {
            format!(
                r#"{{"trace_id":"11111111111111111111111111111111","status":{{"code":{status}}},"name":"n","kind":2,"events":[{events}],"links":[],"otlp":{{"version":1,"resource":[{{"key":"service.name","value":{{"stringValue":"api"}}}},{{"key":"n","value":{{"intValue":"3"}}}}],"scope":[],"attributes":[{{"key":"http.route","value":{{"stringValue":"/a"}}}}],"events":[{typed}],"links":[]}}}}"#
            )
        };
        let exception = r#"[{"key":"exception.type","value":{"stringValue":"E"}},{"key":"exception.message","value":{"stringValue":"m"}}]"#;
        let payloads = [
            payload(2, "", ""),
            payload(0, "{}", exception),
            payload(2, "{},{}", &format!("{exception},[]")),
        ];
        let programs = [
            vec![leaf("intrinsic", "status", "=", "2")],
            vec![leaf("event.string", "exception.type", "=", "E")],
            vec![leaf("event.string", "exception.type", "!=", "")],
            vec![
                leaf("resource.string", "service.name", "=~", "a.*"),
                leaf("span.int", "n", ">", "1"),
                leaf("boolean", "", "||", ""),
            ],
            vec![leaf("none.string", "http.route", "=", "/a")],
            vec![
                leaf("intrinsic", "status", "=", "2"),
                leaf("select", "resource", "service.name", ""),
            ],
        ];
        for program in programs {
            let expression = Expression::compile(program).unwrap();
            for payload in &payloads {
                let (fields, envelope) =
                    crate::trace_metadata::validated_parts(payload.as_bytes()).unwrap();
                let (mut reparsed, mut reused) = (0, 0);
                for collect in [false, true] {
                    let a = expression
                        .evaluate(&fields, &mut reparsed, collect)
                        .unwrap();
                    let b = expression
                        .evaluate_with(&fields, envelope.as_ref(), &mut reused, collect)
                        .unwrap();
                    assert_eq!(
                        (a.matched, a.mask, a.attributes),
                        (b.matched, b.mask, b.attributes)
                    );
                }
                assert_eq!(reparsed, reused, "{payload}");
            }
        }
    }
}
