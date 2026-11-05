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
    // Whether any leaf or selection reads resource or span attributes.
    attributes: bool,
    size: usize,
}
enum Instruction {
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
        let (mut leaves, mut regexes, mut stack, mut events) = (0, 0, 0, false);
        let mut attributes = false;
        let mut spansets = vec![Vec::new()];
        let (mut relations, mut select) = (Vec::new(), Vec::new());
        for (scope, key, op, wanted) in program {
            if scope == "select" {
                let valid = match key.as_str() {
                    "resource" | "span" | "event" | "none" => (1..=256).contains(&op.len()),
                    "intrinsic" => ["name", "status", "kind"].contains(&op.as_str()),
                    _ => false,
                };
                if !valid || !wanted.is_empty() || select.len() == SELECT_MAX {
                    return None;
                }
                events |= key == "event";
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
                "resource.string" | "span.string" | "none.string" | "event.string" => {
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
                "resource.int" | "span.int" | "none.int" | "event.int" | "intrinsic" => {
                    if !["=", "!=", "<", "<=", ">", ">="].contains(&op.as_str()) {
                        return None;
                    }
                    let n = wanted.parse::<i64>().ok()?;
                    if scope == "intrinsic"
                        && match key.as_str() {
                            "status" => {
                                !["=", "!="].contains(&op.as_str()) || !(0..=2).contains(&n)
                            }
                            "duration" => n < 0,
                            _ => true,
                        }
                    {
                        return None;
                    }
                    None
                }
                _ => return None,
            };
            events |= scope.starts_with("event.");
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
            attributes,
            size,
        })
    }

    /// Structural operators or `select` need the search path: per-span
    /// metrics accept neither.
    pub(crate) fn span_local(&self) -> bool {
        self.relations.is_empty() && self.select.is_empty()
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
            let mut events = Vec::new();
            for owner in Parser::new(field(meta, b"events")?)
                .raw_array()
                .map_err(|_| Error::Invalid)?
            {
                let owner = attributes(owner)?;
                units += 1 + owner.len();
                events.push(owner);
            }
            events
        } else {
            Vec::new()
        };
        // Charge all owners, attributes and instructions before filtering, in
        // both candidate and retained-context passes, including nonmatches.
        *work = work.checked_add(units).ok_or(Error::Budget)?;
        if *work > WORK_MAX {
            return Err(Error::Budget);
        }
        let owners = Owners {
            resource: &resource,
            span: &span,
            events: &events,
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
                if let Some((owner, value)) = owners.select(fields, scope, key)? {
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
    events: &'a [Owner<'b>],
}
impl Owners<'_, '_> {
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
                .find_map(|event| event.get(key))
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
                    _ => {
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
                let (matched, value) = if scope == "intrinsic" {
                    let n = if key == "status" {
                        crate::tempo_search::integer(field(
                            &object(field(fields, b"status")?)?,
                            b"code",
                        )?)?
                    } else {
                        crate::tempo_search::integer(field(fields, b"end_timestamp_ns")?)?
                            - crate::tempo_search::integer(field(fields, b"timestamp_ns")?)?
                    };
                    let value = if collect && key == "status" {
                        let status = ["unset", "ok", "error"]
                            .get(n as usize)
                            .ok_or(Error::Invalid)?;
                        Some(format!("{{\"stringValue\":\"{status}\"}}").into_bytes())
                    } else {
                        None
                    };
                    (
                        compare(n, wanted.parse().map_err(|_| Error::Invalid)?, op),
                        value,
                    )
                } else if scope.starts_with("event.") {
                    // Any event of the span with a matching original value,
                    // as Tempo's Parquet fetch selects event attributes. The
                    // first matching event's value is sampled.
                    let string_type = scope.ends_with(".string");
                    let mut found = None;
                    for event in owners.events {
                        if let Some(raw) = event.get(key.as_str()) {
                            if attribute_matches(raw, string_type, op, wanted, regex.as_ref())? {
                                found = Some(*raw);
                                break;
                            }
                        }
                    }
                    (
                        found.is_some(),
                        found.filter(|_| collect).map(<[u8]>::to_vec),
                    )
                } else if scope.starts_with("none.") {
                    let string_type = scope.ends_with(".string");
                    if let Some(attrs) = attrs.as_deref_mut() {
                        for (name, owner) in [("resource", owners.resource), ("span", owners.span)]
                        {
                            if let Some(raw) = owner.get(key.as_str()) {
                                if attribute_matches(raw, string_type, op, wanted, regex.as_ref())?
                                {
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
                        .map_or(Ok(false), |raw| {
                            attribute_matches(raw, string_type, op, wanted, regex.as_ref())
                        })?;
                    (matched, None)
                } else {
                    let owner = if scope.starts_with("resource.") {
                        owners.resource
                    } else {
                        owners.span
                    };
                    match owner.get(key.as_str()) {
                        None => (false, None),
                        Some(raw) => {
                            let matched = attribute_matches(
                                raw,
                                scope.ends_with(".string"),
                                op,
                                wanted,
                                regex.as_ref(),
                            )?;
                            (matched, (collect && matched).then(|| raw.to_vec()))
                        }
                    }
                };
                if matched {
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
    string_type: bool,
    op: &str,
    wanted: &str,
    regex: Option<&regex::Regex>,
) -> Res<bool> {
    let value = object(raw)?;
    if string_type {
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
    } else {
        match field(&value, b"intValue") {
            Ok(n) => Ok(compare(
                string(n)?.parse().map_err(|_| Error::Invalid)?,
                wanted.parse().map_err(|_| Error::Invalid)?,
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
fn compare(left: i64, right: i64, op: &str) -> bool {
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
    fn malformed_programs_cannot_bypass_the_frontend() {
        for program in [
            vec![],
            vec![leaf("boolean", "", "||", "")],
            vec![leaf("span.int", "code", "=", "9223372036854775808")],
            vec![leaf("intrinsic", "duration", ">", "-1")],
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
    fn event_leaves_match_any_event_and_select_samples_first_value() {
        let expression = Expression::compile(vec![
            leaf("event.string", "exception.type", "=", "B"),
            leaf("select", "event", "exception.message", ""),
            leaf("select", "intrinsic", "status", ""),
        ])
        .unwrap();
        let payload = br#"{"status":{"code":2},"otlp":{"resource":[],"attributes":[],"events":[[{"key":"exception.type","value":{"stringValue":"A"}},{"key":"exception.message","value":{"stringValue":"first"}}],[{"key":"exception.type","value":{"stringValue":"B"}}]]}}"#;
        let fields = object(payload).unwrap();
        let mut work = 0;
        let got = expression.evaluate(&fields, &mut work, true).unwrap();
        assert!(got.matched);
        // 2 owners + 3 instructions + two events with 2 and 1 attributes.
        assert_eq!(work, 2 + 3 + 3 + 2);
        let keys: Vec<_> = got.attributes.keys().cloned().collect();
        assert_eq!(
            keys,
            vec![
                ("exception.message".to_string(), "event".to_string()),
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
        let fields = object(br#"{"otlp":{"resource":[],"attributes":[{"key":"exception.type","value":{"stringValue":"span"}}],"events":[[{"key":"exception.type","value":{"intValue":"1"}}]]}}"#).unwrap();
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
            vec![a.clone(), leaf("select", "intrinsic", "duration", "")],
            vec![a.clone(), leaf("select", "link", "k", "")],
            [vec![a.clone()], vec![leaf("select", "span", "k", ""); 9]].concat(),
            std::iter::once(a.clone())
                .chain((0..4).flat_map(|_| [leaf("spanset", "", ">", ""), a.clone()]))
                .collect(),
        ] {
            assert!(Expression::compile(program).is_none());
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
