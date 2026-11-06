//! Query-local compiled capture regexes share selector RE2-subset semantics.
use crate::out::{BinSink, Counter, Sink};
use crate::query_regex::CaptureMetadata;
use rustler::{Encoder, Env, ResourceArc, Term};
use std::collections::HashMap;
use std::sync::LazyLock;

pub struct MetricRegex(regex::Regex, CaptureMetadata);
#[rustler::resource_impl]
impl rustler::Resource for MetricRegex {}

mod atoms {
    rustler::atoms! { ok, error, nil, query_work_limit, query_result_limit }
}

// Compile the shared Go schema once, indexing duplicate aliases for repeated
// template expansions without rescanning every declaration per reference.
struct TemplateRegex {
    regex: regex::Regex,
    names: HashMap<String, Vec<usize>>,
}

impl TemplateRegex {
    fn compile(pattern: &str) -> Result<Self, regex::Error> {
        let (regex, metadata) = crate::query_regex::string_with_metadata(pattern)?;
        let mut names: HashMap<String, Vec<usize>> = HashMap::new();
        for (name, index) in metadata.names {
            names.entry(name).or_default().push(index);
        }
        Ok(Self { regex, names })
    }
}

// Count without retaining captures or expanding matches into BEAM terms.
// The string engine excludes positions inside UTF-8 scalars even for ASCII
// word boundaries. find_iter suppresses empty matches adjoining nonempty ones.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_regex_count<'a>(env: Env<'a>, pattern: &str, input: &str, max_work: usize) -> Term<'a> {
    let Ok(regex) = crate::query_regex::string(pattern) else {
        return atoms::error().encode(env);
    };
    // Reserve the final no-match/EOF probe, including when nothing matched.
    if max_work == 0 {
        return (atoms::error(), atoms::query_work_limit()).encode(env);
    }
    let mut count = 0usize;
    for _ in regex.find_iter(input) {
        count += 1;
        if count >= max_work {
            return (atoms::error(), atoms::query_work_limit()).encode(env);
        }
    }
    (atoms::ok(), count).encode(env)
}

// The same bounded pass first proves output bytes, then writes straight into
// an exactly sized Erlang binary. Neither pass retains a match/capture list.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_regex_replace<'a>(
    env: Env<'a>,
    pattern: &str,
    input: &str,
    replacement: &str,
    literal: bool,
    max_work: usize,
    max_output: usize,
) -> Term<'a> {
    let Ok(regex) = TemplateRegex::compile(pattern) else {
        return atoms::error().encode(env);
    };
    let plan = TemplateReplacement {
        regex: &regex.regex,
        names: &regex.names,
        input,
        replacement,
        literal,
    };
    let mut counter = Counter::new(max_output);
    let mut work = 0;
    if let Err(reason) = plan.write(&mut counter, &mut work, max_work, max_output) {
        return (atoms::error(), reason).encode(env);
    }
    // Rendering repeats the same probes/expansions. Reserve them before any
    // output allocation, not after the caller's allowance has already run out.
    if work > max_work - work {
        return (atoms::error(), atoms::query_work_limit()).encode(env);
    }
    let mut out = BinSink::with_capacity(counter.len());
    if let Err(reason) = plan.write(&mut out, &mut work, max_work, max_output) {
        return (atoms::error(), reason).encode(env);
    }
    (atoms::ok(), out.finish(env), work).encode(env)
}

struct TemplateReplacement<'a> {
    regex: &'a regex::Regex,
    names: &'a HashMap<String, Vec<usize>>,
    input: &'a str,
    replacement: &'a str,
    literal: bool,
}

impl TemplateReplacement<'_> {
    fn write(
        &self,
        out: &mut impl Sink,
        work: &mut usize,
        max_work: usize,
        max_output: usize,
    ) -> Result<(), rustler::Atom> {
        let mut matches = self.regex.captures_iter(self.input);
        let mut previous = 0;
        loop {
            spend_regex_work(work, max_work, 1)?;
            let Some(captures) = matches.next() else {
                break;
            };
            let matched = captures.get(0).unwrap();
            append_replacement(
                out,
                &self.input.as_bytes()[previous..matched.start()],
                max_output,
            )?;
            if self.literal {
                append_replacement(out, self.replacement.as_bytes(), max_output)?;
            } else {
                self.expand(out, &captures, work, max_work, max_output)?;
            }
            previous = matched.end();
        }
        append_replacement(out, &self.input.as_bytes()[previous..], max_output)
    }

    fn expand(
        &self,
        out: &mut impl Sink,
        captures: &regex::Captures<'_>,
        work: &mut usize,
        max_work: usize,
        max_output: usize,
    ) -> Result<(), rustler::Atom> {
        // Go expands the maximal Letter/Nd/_ name, not Rust's ASCII-only
        // replacement grammar. Malformed references retain their literal $.
        static NAME: LazyLock<regex::Regex> =
            LazyLock::new(|| regex::Regex::new(r"\A[\p{L}\p{Nd}_]+").unwrap());
        let mut rest = self.replacement;
        while let Some((before, after)) = rest.split_once('$') {
            spend_regex_work(work, max_work, 1)?;
            append_replacement(out, before.as_bytes(), max_output)?;
            rest = after;
            if let Some(tail) = rest.strip_prefix('$') {
                append_replacement(out, b"$", max_output)?;
                rest = tail;
                continue;
            }
            let name_input = rest.strip_prefix('{').unwrap_or(rest);
            let name = NAME.find(name_input);
            if let Some(name) = name
                .filter(|name| !rest.starts_with('{') || name_input[name.end()..].starts_with('}'))
            {
                let name = name.as_str();
                // Unknown names emit no bytes, so the output cap cannot bound
                // repeated parsing. The dollar charge covers the first byte.
                spend_regex_work(work, max_work, name.len() - 1)?;
                let numeric = capture_number(name);
                let value = match numeric {
                    Some(index) if index < captures.len() => captures.get(index),
                    Some(_) => None,
                    None => {
                        let mut value = None;
                        if let Some(indices) = self.names.get(name) {
                            for (attempt, &index) in indices.iter().enumerate() {
                                // The name charge covers its first candidate.
                                // Further duplicates can emit no bytes and must
                                // still consume shared query work.
                                if attempt > 0 {
                                    spend_regex_work(work, max_work, 1)?;
                                }
                                value = captures.get(index);
                                if value.is_some() {
                                    break;
                                }
                            }
                        }
                        value
                    }
                };
                if let Some(value) = value {
                    append_replacement(out, value.as_str().as_bytes(), max_output)?;
                }
                rest = &name_input[name.len() + usize::from(rest.starts_with('{'))..];
            } else {
                append_replacement(out, b"$", max_output)?;
            }
        }
        append_replacement(out, rest.as_bytes(), max_output)
    }
}

fn spend_regex_work(work: &mut usize, max_work: usize, amount: usize) -> Result<(), rustler::Atom> {
    if amount > max_work - *work {
        return Err(atoms::query_work_limit());
    }
    *work += amount;
    Ok(())
}

fn append_replacement(
    out: &mut impl Sink,
    bytes: &[u8],
    max_output: usize,
) -> Result<(), rustler::Atom> {
    if bytes.len() > max_output - out.len() {
        return Err(atoms::query_result_limit());
    }
    out.extend(bytes);
    Ok(())
}

// Live tails compile once, then filter whole batches with the exact byte-regex
// engine used by Parquet log queries. Input and output records stay BEAM terms;
// only borrowed line/label slices cross into the matcher.
pub struct LogRegex(regex::bytes::Regex, Option<Vec<(String, usize)>>);
#[rustler::resource_impl]
impl rustler::Resource for LogRegex {}

#[rustler::nif(schedule = "DirtyCpu")]
fn compile_log_regex<'a>(env: Env<'a>, pattern: &str) -> Term<'a> {
    match crate::query_regex::bytes_with_metadata(pattern) {
        Ok((regex, metadata)) => (
            atoms::ok(),
            ResourceArc::new(LogRegex(regex, metadata.into_parser_names())),
        )
            .encode(env),
        Err(_) => atoms::error().encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn filter_log_regex<'a>(
    env: Env<'a>,
    regex: ResourceArc<LogRegex>,
    rows: rustler::ListIterator<'a>,
    negate: bool,
) -> rustler::NifResult<Term<'a>> {
    let mut kept = Vec::new();
    for row in rows {
        let (record, value): (Term<'a>, rustler::Binary<'a>) = row.decode()?;
        if regex.0.is_match(value.as_slice()) != negate {
            kept.push(record);
        }
    }
    Ok(kept.encode(env))
}

// Remaining LogQL stages use the same non-backtracking engine as pushdown.
// Named values borrow the input binary; retained query/tail results detach at
// their existing lifetime boundary rather than copying every parsed line.
#[rustler::nif(schedule = "DirtyCpu")]
fn match_log_regex(regex: ResourceArc<LogRegex>, input: rustler::Binary<'_>) -> bool {
    regex.0.is_match(input.as_slice())
}

// Admission inspects the same native program as extraction, without compiling
// a second dialect or materializing the names/capture values as BEAM terms.
#[rustler::nif(name = "log_regex_named_capture?", schedule = "DirtyCpu")]
fn log_regex_named_capture(regex: ResourceArc<LogRegex>) -> bool {
    regex.1.as_ref().is_some_and(|names| !names.is_empty())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn log_regex_named_captures<'a>(
    env: Env<'a>,
    regex: ResourceArc<LogRegex>,
    input: rustler::Binary<'a>,
) -> rustler::NifResult<Term<'a>> {
    let names = regex.1.as_ref().ok_or(rustler::Error::BadArg)?;
    let Some(captures) = regex.0.captures(input.as_slice()) else {
        return Ok(atoms::nil().encode(env));
    };
    let mut keys = Vec::with_capacity(names.len());
    let mut values = Vec::with_capacity(names.len());
    for (name, index) in names {
        let (start, len) = captures
            .get(*index)
            .map_or((0, 0), |capture| (capture.start(), capture.len()));
        keys.push(name.as_str());
        values.push(input.make_subbinary(start, len)?);
    }
    Term::map_from_arrays(env, &keys, &values)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn compile_metric_capture_regex<'a>(env: Env<'a>, pattern: &str) -> Term<'a> {
    match crate::query_regex::anchored_with_metadata(pattern) {
        Ok((regex, mut metadata)) => {
            // Group aliases once; each match visits each declaration at most
            // once, independent of alias ordering or the number of duplicates.
            metadata.names.sort_unstable();
            (atoms::ok(), ResourceArc::new(MetricRegex(regex, metadata))).encode(env)
        }
        Err(_) => atoms::error().encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn metric_regex_captures<'a>(
    env: Env<'a>,
    regex: ResourceArc<MetricRegex>,
    input: &str,
) -> Term<'a> {
    let Some(captures) = regex.0.captures(input) else {
        return atoms::nil().encode(env);
    };
    let size = regex.1.count + 1 + regex.1.names.len();
    let mut keys = Vec::with_capacity(size);
    let mut values = Vec::with_capacity(size);
    for index in 0..=regex.1.count {
        let value = captures.get(index).map_or("", |capture| capture.as_str());
        keys.push(index.to_string().encode(env));
        values.push(value.encode(env));
    }
    for aliases in regex.1.names.chunk_by(|left, right| left.0 == right.0) {
        let name = &aliases[0].0;
        // Numeric references cannot be shadowed by capture names, including
        // references beyond the last index. Leading zeros/large numbers name
        // aliases instead, following Go's ExpandString rather than SubexpIndex.
        if capture_number(name).is_some() {
            continue;
        }
        let index = aliases
            .iter()
            .find(|(_, index)| captures.get(*index).is_some())
            .unwrap_or(&aliases[0])
            .1;
        keys.push(name.encode(env));
        // Named and numeric aliases share one detached BEAM value, without
        // an intermediate Rust string or a second binary copy for the name.
        values.push(values[index]);
    }
    Term::map_from_arrays(env, &keys, &values).unwrap()
}

fn capture_number(name: &str) -> Option<usize> {
    name.parse::<usize>()
        .ok()
        .filter(|&n| n < 1_000_000_000 && (name.len() == 1 || !name.starts_with('0')))
}
