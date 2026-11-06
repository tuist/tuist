//! Native LogQL range-aggregation input: selects log rows, runs a supported
//! pipeline subset and reduces each kept row to one sample of its series,
//! without building Erlang terms for log records.
//!
//! This is a fast path for `Pulse.LogQL.MetricEval`'s streamed evaluation and
//! must reproduce it exactly. Labels are those of `Pulse.LogQL.Entry`
//! (resource, then attributes, then the promoted service/level mirrors when
//! absent), stages follow `Pulse.LogQL.Pipeline`, unwrap values follow
//! `Pulse.PromQL.FloatParser` and label-filter numbers `Integer.parse` then
//! `Float.parse`. Whenever a row needs behavior this module cannot guarantee
//! (non-string label values, non-string bodies, number spellings outside the
//! plain decimal grammar), the whole scan answers `:fallback` and the caller
//! evaluates the query in Elixir instead.
use crate::query_filter::{self, LineFilter, Matcher};
use arrow::array::{Array, Int64Array, StringArray};
use bytes::Bytes;
use memchr::memmem::Finder;
use parquet::arrow::arrow_reader::ParquetRecordBatchReaderBuilder;
use regex::bytes::Regex;
use rustler::{Binary, Encoder, Env, ListIterator, NewBinary, ResourceArc, Term};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::rc::Rc;
use std::sync::Mutex;

mod atoms {
    rustler::atoms! { ok, error, fallback, nil, contains, not_contains, match_re, not_match_re,
    logfmt, regexp, label_filter, and, or, eq, neq, re, nre, num, lt, lte, gt, gte, count, bytes,
    unwrap, by, without, pipeline_error, query_resource_limit, keep, drop_errors }
}

const COLUMNS: [&str; 8] = [
    "timestamp_ns",
    "service",
    "severity_text",
    "body",
    "attributes",
    "resource",
    "trace_id",
    "span_id",
];

#[derive(Debug)]
enum Error {
    Fallback,
    Pipeline,
    Limit,
}

type Res<T> = Result<T, Error>;

#[derive(Clone, Copy, PartialEq)]
enum CmpOp {
    Eq,
    Neq,
    Lt,
    Lte,
    Gt,
    Gte,
}

#[derive(Clone, Copy, PartialEq, PartialOrd)]
enum Number {
    Int(i64),
    Float(f64),
}

impl Number {
    fn float(self) -> f64 {
        match self {
            Number::Int(i) => i as f64,
            Number::Float(f) => f,
        }
    }
}

enum Filter {
    And(Box<Filter>, Box<Filter>),
    Or(Box<Filter>, Box<Filter>),
    Str {
        name: String,
        negate: bool,
        value: Vec<u8>,
    },
    Re {
        name: String,
        negate: bool,
        regex: Regex,
    },
    Num {
        name: String,
        op: CmpOp,
        value: Number,
    },
}

enum Stage {
    Line {
        negate: bool,
        finder: Box<Finder<'static>>,
    },
    LineRe {
        negate: bool,
        regex: Regex,
    },
    Logfmt,
    Regexp {
        regex: Regex,
        names: Vec<(String, usize)>,
    },
    Labels(Filter),
    // `keep` of plain names: every other label but the error labels leaves.
    Keep(Vec<String>),
}

enum Value {
    Count,
    Bytes,
    Unwrap(String),
}

enum Grouping {
    All,
    By(Vec<String>),
    Without(Vec<String>),
}

type SeriesKey = Vec<(String, String)>;

#[derive(Clone, Copy)]
enum Sample {
    Float(f64),
    Int(i64),
    Error,
}

struct State {
    stages: Vec<Stage>,
    value: Value,
    drop: Option<String>,
    // A post-unwrap `__error__=""` filter: observations whose labels carry an
    // error, from an earlier stage or the conversion, are dropped uncharged.
    drop_errors: bool,
    grouping: Grouping,
    series: HashMap<SeriesKey, Vec<(i64, Sample)>>,
    samples: usize,
    // Retained samples allowed: the query's remaining log sample budget.
    max_samples: u64,
    // Pattern scans train this miner on every selected line instead.
    patterns: Option<crate::patterns::Miner>,
    // Binned scans (`log_metric_binned_new`) sum counts or bytes per minute
    // bucket end instead of keeping one sample per line.
    bins: Option<HashMap<SeriesKey, HashMap<i64, i64>>>,
}

pub struct Scan(Mutex<Option<State>>);

#[rustler::resource_impl]
impl rustler::Resource for Scan {}

fn result<'a, T: Encoder>(env: Env<'a>, value: Res<T>) -> Term<'a> {
    match value {
        Ok(value) => (atoms::ok(), value).encode(env),
        Err(Error::Fallback) => atoms::fallback().encode(env),
        Err(Error::Pipeline) => (atoms::error(), atoms::pipeline_error()).encode(env),
        Err(Error::Limit) => (atoms::error(), atoms::query_resource_limit()).encode(env),
    }
}

// The reference uses UTF-8 PCRE with strict end-of-input `$`; the shared
// native subset additionally enforces Go's ASCII Perl classes/boundaries.
fn pcre_compatible(pattern: &str) -> Res<Regex> {
    crate::query_regex::bytes(pattern).map_err(|_| Error::Fallback)
}

fn text(term: Term<'_>) -> Res<String> {
    let binary: Binary = term.decode().map_err(|_| Error::Fallback)?;
    String::from_utf8(binary.as_slice().to_vec()).map_err(|_| Error::Fallback)
}

fn number(term: Term<'_>) -> Res<Number> {
    if let Ok(i) = term.decode::<i64>() {
        return Ok(Number::Int(i));
    }
    term.decode::<f64>()
        .map(Number::Float)
        .map_err(|_| Error::Fallback)
}

fn cmp_op(atom: rustler::Atom) -> Res<CmpOp> {
    Ok(if atom == atoms::eq() {
        CmpOp::Eq
    } else if atom == atoms::neq() {
        CmpOp::Neq
    } else if atom == atoms::lt() {
        CmpOp::Lt
    } else if atom == atoms::lte() {
        CmpOp::Lte
    } else if atom == atoms::gt() {
        CmpOp::Gt
    } else if atom == atoms::gte() {
        CmpOp::Gte
    } else {
        return Err(Error::Fallback);
    })
}

fn filter(term: Term<'_>, depth: usize) -> Res<Filter> {
    if depth > 64 {
        return Err(Error::Fallback);
    }
    let parts: Vec<Term> = rustler::types::tuple::get_tuple(term).map_err(|_| Error::Fallback)?;
    let tag: rustler::Atom = parts
        .first()
        .ok_or(Error::Fallback)?
        .decode()
        .map_err(|_| Error::Fallback)?;
    match parts.len() {
        3 if tag == atoms::and() || tag == atoms::or() => {
            let left = Box::new(filter(parts[1], depth + 1)?);
            let right = Box::new(filter(parts[2], depth + 1)?);
            Ok(if tag == atoms::and() {
                Filter::And(left, right)
            } else {
                Filter::Or(left, right)
            })
        }
        3 if tag == atoms::eq() || tag == atoms::neq() => Ok(Filter::Str {
            name: text(parts[1])?,
            negate: tag == atoms::neq(),
            value: text(parts[2])?.into_bytes(),
        }),
        3 if tag == atoms::re() || tag == atoms::nre() => Ok(Filter::Re {
            name: text(parts[1])?,
            negate: tag == atoms::nre(),
            regex: pcre_compatible(&text(parts[2])?)?,
        }),
        4 if tag == atoms::num() => Ok(Filter::Num {
            op: cmp_op(parts[1].decode().map_err(|_| Error::Fallback)?)?,
            name: text(parts[2])?,
            value: number(parts[3])?,
        }),
        _ => Err(Error::Fallback),
    }
}

fn stage(term: Term<'_>) -> Res<Stage> {
    if let Ok(atom) = term.decode::<rustler::Atom>() {
        return if atom == atoms::logfmt() {
            Ok(Stage::Logfmt)
        } else {
            Err(Error::Fallback)
        };
    }
    let parts: Vec<Term> = rustler::types::tuple::get_tuple(term).map_err(|_| Error::Fallback)?;
    if parts.len() != 2 {
        return Err(Error::Fallback);
    }
    let tag: rustler::Atom = parts[0].decode().map_err(|_| Error::Fallback)?;
    if tag == atoms::contains() || tag == atoms::not_contains() {
        let needle = text(parts[1])?.into_bytes();
        Ok(Stage::Line {
            negate: tag == atoms::not_contains(),
            finder: Box::new(Finder::new(&needle).into_owned()),
        })
    } else if tag == atoms::match_re() || tag == atoms::not_match_re() {
        Ok(Stage::LineRe {
            negate: tag == atoms::not_match_re(),
            regex: pcre_compatible(&text(parts[1])?)?,
        })
    } else if tag == atoms::regexp() {
        let (regex, metadata) = crate::query_regex::bytes_with_metadata(&text(parts[1])?)
            .map_err(|_| Error::Fallback)?;
        Ok(Stage::Regexp {
            regex,
            names: metadata.into_parser_names().ok_or(Error::Fallback)?,
        })
    } else if tag == atoms::label_filter() {
        Ok(Stage::Labels(filter(parts[1], 0)?))
    } else if tag == atoms::keep() {
        Ok(Stage::Keep(names(parts[1])?))
    } else {
        Err(Error::Fallback)
    }
}

fn names(term: Term<'_>) -> Res<Vec<String>> {
    term.decode::<ListIterator>()
        .map_err(|_| Error::Fallback)?
        .map(text)
        .collect()
}

#[rustler::nif]
fn log_metric_api_version() -> u32 {
    19
}

/// `stages` is the pipeline after pushdown; `value` is `:count`, `:bytes`,
/// `{:unwrap, label}` or `{:unwrap, label, :drop_errors}` (followed by
/// `__error__=""` filters); `drop` the unwrapped label removed from series keys or
/// nil; `grouping` nil, `{:by, names}` or `{:without, names}`; `max_samples`
/// the retained samples allowed before the scan fails with a resource limit.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_metric_scan_new<'a>(
    env: Env<'a>,
    stages: Term<'a>,
    value: Term<'a>,
    drop: Term<'a>,
    grouping: Term<'a>,
    max_samples: u64,
) -> Term<'a> {
    let build = || {
        let stages = stages
            .decode::<ListIterator>()
            .map_err(|_| Error::Fallback)?
            .map(stage)
            .collect::<Res<Vec<_>>>()?;
        let mut drop_errors = false;
        let value = if let Ok(atom) = value.decode::<rustler::Atom>() {
            if atom == atoms::count() {
                Value::Count
            } else if atom == atoms::bytes() {
                Value::Bytes
            } else {
                return Err(Error::Fallback);
            }
        } else {
            let parts: Vec<Term> =
                rustler::types::tuple::get_tuple(value).map_err(|_| Error::Fallback)?;
            let tag: rustler::Atom = parts
                .first()
                .ok_or(Error::Fallback)?
                .decode()
                .map_err(|_| Error::Fallback)?;
            match parts.len() {
                2 => {}
                3 if parts[2].decode::<rustler::Atom>().ok() == Some(atoms::drop_errors()) => {
                    drop_errors = true;
                }
                _ => return Err(Error::Fallback),
            }
            if tag != atoms::unwrap() {
                return Err(Error::Fallback);
            }
            Value::Unwrap(text(parts[1])?)
        };
        let drop = if drop.decode::<rustler::Atom>().ok() == Some(atoms::nil()) {
            None
        } else {
            Some(text(drop)?)
        };
        let grouping = if grouping.decode::<rustler::Atom>().ok() == Some(atoms::nil()) {
            Grouping::All
        } else {
            let (mode, list): (rustler::Atom, Term) =
                grouping.decode().map_err(|_| Error::Fallback)?;
            if mode == atoms::by() {
                Grouping::By(names(list)?)
            } else if mode == atoms::without() {
                Grouping::Without(names(list)?)
            } else {
                return Err(Error::Fallback);
            }
        };
        Ok(ResourceArc::new(Scan(Mutex::new(Some(State {
            stages,
            value,
            drop,
            drop_errors,
            grouping,
            series: HashMap::new(),
            samples: 0,
            max_samples,
            patterns: None,
            bins: None,
        })))))
    };
    result(env, build())
}

/// A scan without pipeline stages that sums `value` (`:count` or `:bytes`)
/// per series and minute bucket end (`crate::log_rollup::bucket_end`), fed by
/// log segments (`log_metric_scan_add`) and rollups (`log_metric_scan_rollup`).
/// `max_samples` bounds the buckets kept.
#[rustler::nif]
fn log_metric_binned_new<'a>(
    env: Env<'a>,
    value: Term<'a>,
    grouping: Term<'a>,
    max_samples: u64,
) -> Term<'a> {
    let build = || {
        let value = match value.decode::<rustler::Atom>() {
            Ok(atom) if atom == atoms::count() => Value::Count,
            Ok(atom) if atom == atoms::bytes() => Value::Bytes,
            _ => return Err(Error::Fallback),
        };
        let grouping = decode_grouping(grouping)?;
        Ok(ResourceArc::new(Scan(Mutex::new(Some(State {
            stages: Vec::new(),
            value,
            drop: None,
            drop_errors: false,
            grouping,
            series: HashMap::new(),
            samples: 0,
            max_samples,
            patterns: None,
            bins: Some(HashMap::new()),
        })))))
    };
    result(env, build())
}

fn decode_grouping(grouping: Term<'_>) -> Res<Grouping> {
    if grouping.decode::<rustler::Atom>().ok() == Some(atoms::nil()) {
        return Ok(Grouping::All);
    }
    let (mode, list): (rustler::Atom, Term) = grouping.decode().map_err(|_| Error::Fallback)?;
    if mode == atoms::by() {
        Ok(Grouping::By(names(list)?))
    } else if mode == atoms::without() {
        Ok(Grouping::Without(names(list)?))
    } else {
        Err(Error::Fallback)
    }
}

/// Fold the rows of one log rollup whose bucket ends are in `buckets` into a
/// binned scan: `{:ok, rows}`. Answers `:fallback` when a row counts lines
/// with trace or span IDs and the grouping may keep those labels.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_metric_scan_rollup<'a>(
    env: Env<'a>,
    scan: ResourceArc<Scan>,
    blob: Binary<'a>,
    buckets: Vec<i64>,
    service: Term<'a>,
    matchers: Term<'a>,
) -> Term<'a> {
    let add = || {
        let service = match service.decode::<Binary>() {
            Ok(service) => Some(service.as_slice().to_vec()),
            Err(_) if service.decode::<rustler::Atom>().ok() == Some(atoms::nil()) => None,
            Err(_) => return Err(Error::Fallback),
        };
        let matchers = crate::decode_matchers(matchers).map_err(|_| Error::Fallback)?;
        let buckets: HashSet<i64> = buckets.into_iter().collect();
        let mut guard = scan.0.lock().map_err(|_| Error::Fallback)?;
        let state = guard.as_mut().ok_or(Error::Fallback)?;
        let selection = Selection {
            start: i64::MIN,
            end: i64::MAX,
            service,
            matchers,
            line_filters: Vec::new(),
        };
        let outcome =
            state.add_rollup(crate::erlang_bytes::from_binary(blob), &buckets, &selection);
        if outcome.is_err() {
            guard.take();
        }
        outcome
    };
    result(env, add())
}

/// Fold one segment: `{:ok, {rows_selected, rows_kept}}`: rows the storage
/// filters select, then rows the pipeline keeps. Selection arguments are
/// those of `decode_log_segment_parquet_v2`.
#[allow(clippy::too_many_arguments)]
#[rustler::nif(schedule = "DirtyCpu")]
fn log_metric_scan_add<'a>(
    env: Env<'a>,
    scan: ResourceArc<Scan>,
    blob: Binary<'a>,
    start: i64,
    end: i64,
    service: Term<'a>,
    matchers: Term<'a>,
    line_filters: Term<'a>,
) -> Term<'a> {
    let add = || {
        let service = match service.decode::<Binary>() {
            Ok(service) => Some(service.as_slice().to_vec()),
            Err(_) if service.decode::<rustler::Atom>().ok() == Some(atoms::nil()) => None,
            Err(_) => return Err(Error::Fallback),
        };
        let matchers = crate::decode_matchers(matchers).map_err(|_| Error::Fallback)?;
        let line_filters = crate::decode_line_filters(line_filters).map_err(|_| Error::Fallback)?;
        let mut guard = scan.0.lock().map_err(|_| Error::Fallback)?;
        let state = guard.as_mut().ok_or(Error::Fallback)?;
        let selection = Selection {
            start,
            end,
            service,
            matchers,
            line_filters,
        };
        let outcome = state.scan(crate::erlang_bytes::from_binary(blob), &selection);
        if outcome.is_err() {
            guard.take();
        }
        outcome
    };
    result(env, add())
}

/// `[{labels, samples}]` where `samples` packs `<<ts::64, tag::8, value::64>>`
/// in descending order (tag 0 float bits, 1 unwrap error, 2 integer).
#[rustler::nif(schedule = "DirtyCpu")]
fn log_metric_scan_finish<'a>(env: Env<'a>, scan: ResourceArc<Scan>) -> Term<'a> {
    let finish = || {
        let state = scan
            .0
            .lock()
            .map_err(|_| Error::Fallback)?
            .take()
            .ok_or(Error::Fallback)?;
        let series = match state.bins {
            // One `(bucket_end, Int(sum))` sample per bucket.
            Some(bins) => bins
                .into_iter()
                .map(|(labels, bins)| {
                    (
                        labels,
                        bins.into_iter().map(|(b, v)| (b, Sample::Int(v))).collect(),
                    )
                })
                .collect(),
            None => state.series,
        };
        let mut out = Vec::with_capacity(series.len());
        for (labels, mut samples) in series {
            samples.sort_by(|a, b| descending(*a, *b));
            let mut packed = NewBinary::new(env, samples.len() * 17);
            for (i, (ts, sample)) in samples.iter().enumerate() {
                let slot = &mut packed.as_mut_slice()[i * 17..(i + 1) * 17];
                slot[..8].copy_from_slice(&ts.to_be_bytes());
                let (tag, bits) = match sample {
                    Sample::Float(f) => (0u8, f.to_bits()),
                    Sample::Error => (1, 0),
                    Sample::Int(n) => (2, *n as u64),
                };
                slot[8] = tag;
                slot[9..].copy_from_slice(&bits.to_be_bytes());
            }
            let keys: Vec<Term> = labels.iter().map(|(k, _)| k.encode(env)).collect();
            let values: Vec<Term> = labels.iter().map(|(_, v)| v.encode(env)).collect();
            let map = Term::map_from_arrays(env, &keys, &values).map_err(|_| Error::Fallback)?;
            out.push((map, Binary::from(packed)));
        }
        Ok(out)
    };
    result(env, finish())
}

#[rustler::nif]
fn log_metric_scan_abort(scan: ResourceArc<Scan>) -> rustler::Atom {
    if let Ok(mut guard) = scan.0.lock() {
        guard.take();
    }
    atoms::ok()
}

/// A scan that mines log patterns (`crate::patterns`) from every selected
/// line instead of running a pipeline. `log_metric_scan_add` feeds it from
/// stored segments, `log_pattern_observe` from lines already in the BEAM.
#[rustler::nif]
fn log_pattern_scan_new(start: i64, step: i64) -> ResourceArc<Scan> {
    ResourceArc::new(Scan(Mutex::new(Some(State {
        stages: Vec::new(),
        value: Value::Count,
        drop: None,
        drop_errors: false,
        grouping: Grouping::All,
        series: HashMap::new(),
        samples: 0,
        max_samples: u64::MAX,
        patterns: Some(crate::patterns::Miner::new(start, step)),
        bins: None,
    }))))
}

/// Train on `[{timestamp_ns, line}]`.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_pattern_observe<'a>(env: Env<'a>, scan: ResourceArc<Scan>, lines: Term<'a>) -> Term<'a> {
    let observe = || {
        let mut guard = scan.0.lock().map_err(|_| Error::Fallback)?;
        let miner = guard
            .as_mut()
            .and_then(|state| state.patterns.as_mut())
            .ok_or(Error::Fallback)?;
        for item in lines
            .decode::<ListIterator>()
            .map_err(|_| Error::Fallback)?
        {
            let (ts, line): (i64, Binary) = item.decode().map_err(|_| Error::Fallback)?;
            miner.train(ts, line.as_slice());
        }
        Ok(atoms::ok())
    };
    match observe() {
        Ok(ok) => ok.encode(env),
        Err(error) => result::<rustler::Atom>(env, Err(error)),
    }
}

/// `{:ok, [{pattern, [{bucket_start_ns, count}]}]}`, largest total first.
#[rustler::nif(schedule = "DirtyCpu")]
fn log_pattern_finish<'a>(env: Env<'a>, scan: ResourceArc<Scan>) -> Term<'a> {
    let finish = || {
        let miner = scan
            .0
            .lock()
            .map_err(|_| Error::Fallback)?
            .take()
            .and_then(|state| state.patterns)
            .ok_or(Error::Fallback)?;
        Ok(miner
            .finish()
            .into_iter()
            .map(|(pattern, counts)| {
                let mut binary = NewBinary::new(env, pattern.len());
                binary.as_mut_slice().copy_from_slice(&pattern);
                (Binary::from(binary), counts)
            })
            .collect::<Vec<_>>())
    };
    result(env, finish())
}

// Erlang term order, descending: time, then `:error` (an atom) above every
// number, then numeric value. Series values are homogeneous in kind.
fn descending(a: (i64, Sample), b: (i64, Sample)) -> std::cmp::Ordering {
    use std::cmp::Ordering;
    b.0.cmp(&a.0).then_with(|| match (a.1, b.1) {
        (Sample::Error, Sample::Error) => Ordering::Equal,
        (Sample::Error, _) => Ordering::Less,
        (_, Sample::Error) => Ordering::Greater,
        (Sample::Int(x), Sample::Int(y)) => y.cmp(&x),
        (x, y) => sample_float(y)
            .partial_cmp(&sample_float(x))
            .unwrap_or(Ordering::Equal),
    })
}

fn sample_float(s: Sample) -> f64 {
    match s {
        Sample::Float(f) => f,
        Sample::Int(i) => i as f64,
        Sample::Error => f64::NAN,
    }
}

struct Selection {
    start: i64,
    end: i64,
    service: Option<Vec<u8>>,
    matchers: Vec<Matcher>,
    line_filters: Vec<LineFilter>,
}

type Labels = BTreeMap<String, String>;

struct EntryLabels {
    labels: Labels,
    stream_keys: HashSet<String>,
    metadata_keys: HashSet<String>,
}
// All inputs to a row's labels, including its per-entry correlation metadata.
type StreamKey<'b> = (
    &'b str,
    &'b str,
    Option<&'b str>,
    Option<&'b str>,
    Option<&'b str>,
    Option<&'b str>,
);

impl State {
    fn scan(&mut self, bytes: Bytes, selection: &Selection) -> Res<(usize, usize)> {
        let builder =
            ParquetRecordBatchReaderBuilder::try_new(bytes).map_err(|_| Error::Fallback)?;
        let schema = builder.schema().clone();
        let mut indexes = Vec::with_capacity(COLUMNS.len());
        for name in COLUMNS {
            indexes.push(schema.index_of(name).map_err(|_| Error::Fallback)?);
        }
        let projection = parquet::arrow::ProjectionMask::roots(builder.parquet_schema(), indexes);
        let reader = builder
            .with_projection(projection)
            .with_batch_size(4096)
            .build()
            .map_err(|_| Error::Fallback)?;
        let (mut chosen, mut kept) = (0, 0);
        for batch in reader {
            let batch = batch.map_err(|_| Error::Fallback)?;
            let column = |name| batch.column_by_name(name).ok_or(Error::Fallback);
            let strings = |name| -> Res<&StringArray> {
                column(name)?
                    .as_any()
                    .downcast_ref::<StringArray>()
                    .ok_or(Error::Fallback)
            };
            let times = column("timestamp_ns")?
                .as_any()
                .downcast_ref::<Int64Array>()
                .ok_or(Error::Fallback)?;
            let (service, level, body) = (
                strings("service")?,
                strings("severity_text")?,
                strings("body")?,
            );
            let (attributes, resource) = (strings("attributes")?, strings("resource")?);
            let (trace_id, span_id) = (strings("trace_id")?, strings("span_id")?);
            // Stream labels repeat for runs of rows: build each set once.
            let mut bases: HashMap<StreamKey, Rc<EntryLabels>> = HashMap::new();
            for row in 0..batch.num_rows() {
                if times.is_null(row) {
                    continue;
                }
                let ts = times.value(row);
                if ts < selection.start || ts > selection.end {
                    continue;
                }
                let svc = (!service.is_null(row)).then(|| service.value(row));
                let lvl = (!level.is_null(row)).then(|| level.value(row));
                let res = if resource.is_null(row) {
                    ""
                } else {
                    resource.value(row)
                };
                if !selected(selection, res.as_bytes(), svc, lvl) {
                    continue;
                }
                let raw_body = (!body.is_null(row) && !body.value(row).is_empty())
                    .then(|| body.value(row).as_bytes());
                let matched = match raw_body {
                    Some(raw) => query_filter::line_bytes_for_match(raw),
                    None => std::borrow::Cow::Borrowed(&b""[..]),
                };
                if !selection.line_filters.iter().all(|f| f.matches(&matched)) {
                    continue;
                }
                chosen += 1;
                if let Some(miner) = self.patterns.as_mut() {
                    miner.train(ts, &matched);
                    kept += 1;
                    continue;
                }
                // Entry.line re-encodes non-string bodies; only strings match.
                if raw_body.is_some_and(|raw| {
                    raw.len() < 2 || raw[0] != b'"' || raw[raw.len() - 1] != b'"'
                }) {
                    return Err(Error::Fallback);
                }
                let attrs = if attributes.is_null(row) {
                    ""
                } else {
                    attributes.value(row)
                };
                let trace = (!trace_id.is_null(row)).then(|| trace_id.value(row));
                let span = (!span_id.is_null(row)).then(|| span_id.value(row));
                let key = (res, attrs, svc, lvl, trace, span);
                let base = match bases.get(&key) {
                    Some(base) => Rc::clone(base),
                    None => {
                        let base = Rc::new(entry_labels(res, attrs, svc, lvl, trace, span)?);
                        bases.insert(key, Rc::clone(&base));
                        base
                    }
                };
                if let Some(labels) = self.pipeline(&matched, &base)? {
                    kept += usize::from(self.observe(ts, &matched, &labels)?);
                }
            }
        }
        Ok((chosen, kept))
    }

    // Returns the entry's labels after every stage, or None when dropped.
    fn pipeline<'l>(
        &self,
        line: &[u8],
        base: &'l EntryLabels,
    ) -> Res<Option<std::borrow::Cow<'l, Labels>>> {
        let mut labels = std::borrow::Cow::Borrowed(&base.labels);
        let mut extracted = HashSet::new();
        for stage in &self.stages {
            match stage {
                Stage::Line { negate, finder } => {
                    if finder.find(line).is_some() == *negate {
                        return Ok(None);
                    }
                }
                Stage::LineRe { negate, regex } => {
                    if regex.is_match(line) == *negate {
                        return Ok(None);
                    }
                }
                Stage::Logfmt => {
                    let pairs = logfmt(line)?;
                    let owned = labels.to_mut();
                    for (k, v) in pairs {
                        let target = parsed_name(base, &extracted, k);
                        if extracted.insert(target.clone()) {
                            owned.insert(target, v);
                        }
                    }
                }
                Stage::Regexp { regex, names } => {
                    if let Some(captures) = regex.captures(line) {
                        let owned = labels.to_mut();
                        for (name, index) in names {
                            let target = parsed_name(base, &extracted, name.clone());
                            if extracted.insert(target.clone()) {
                                let value = captures.get(*index).map_or(&b""[..], |m| m.as_bytes());
                                let value = String::from_utf8(value.to_vec())
                                    .map_err(|_| Error::Fallback)?;
                                owned.insert(target, value);
                            }
                        }
                    }
                }
                Stage::Labels(filter) => {
                    if !evaluate(filter, &labels)? {
                        return Ok(None);
                    }
                }
                Stage::Keep(names) => labels.to_mut().retain(|k, _| {
                    k == "__error__" || k == "__error_details__" || names.iter().any(|n| n == k)
                }),
            }
        }
        Ok(Some(labels))
    }

    fn observe(&mut self, ts: i64, line: &[u8], labels: &Labels) -> Res<bool> {
        // Without an unwrap target there is no observation whose labels can
        // carry an earlier pipeline error. Selected rows still spend work.
        let unwrapped = if let Value::Unwrap(name) = &self.value {
            let Some(value) = labels.get(name).filter(|v| !v.is_empty()) else {
                return Ok(false);
            };
            Some(value)
        } else {
            None
        };
        if labels.get("__error__").is_some_and(|e| !e.is_empty()) {
            return if self.drop_errors {
                Ok(false)
            } else {
                Err(Error::Pipeline)
            };
        }
        if self.bins.is_some() {
            let amount = match &self.value {
                Value::Bytes => i64::try_from(line.len()).map_err(|_| Error::Fallback)?,
                _ => 1,
            };
            let key = self.key(labels);
            self.add_bin(key, crate::log_rollup::bucket_end(ts), amount)?;
            return Ok(true);
        }
        let sample = match &self.value {
            Value::Count => Sample::Float(1.0),
            Value::Bytes => Sample::Int(i64::try_from(line.len()).map_err(|_| Error::Fallback)?),
            Value::Unwrap(_) => unwrap_value(unwrapped)?,
        };
        if self.drop_errors && matches!(sample, Sample::Error) {
            return Ok(false);
        }
        let key = self.key(labels);
        self.samples += 1;
        if self.samples as u64 > self.max_samples {
            return Err(Error::Limit);
        }
        self.series.entry(key).or_default().push((ts, sample));
        Ok(true)
    }

    fn key(&self, labels: &Labels) -> SeriesKey {
        labels
            .iter()
            .filter(|(k, _)| self.drop.as_deref() != Some(k.as_str()))
            .filter(|(k, _)| match &self.grouping {
                Grouping::All => true,
                Grouping::By(names) => names.iter().any(|n| n == *k),
                Grouping::Without(names) => !names.iter().any(|n| n == *k),
            })
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect()
    }

    // Each distinct (series, bucket) counts once against the sample budget.
    fn add_bin(&mut self, key: SeriesKey, bucket: i64, amount: i64) -> Res<()> {
        let bins = self.bins.as_mut().ok_or(Error::Fallback)?;
        let series = bins.entry(key).or_default();
        match series.get_mut(&bucket) {
            Some(value) => *value += amount,
            None => {
                self.samples += 1;
                if self.samples as u64 > self.max_samples {
                    return Err(Error::Limit);
                }
                series.insert(bucket, amount);
            }
        }
        Ok(())
    }

    // Whether series keys can never hold the dedicated trace/span ID labels.
    fn drops_ids(&self) -> bool {
        matches!(&self.grouping, Grouping::By(names)
            if !names.iter().any(|n| matches!(n.as_str(), "trace_id" | "span_id" | "trace_id_extracted" | "span_id_extracted")))
    }

    fn add_rollup(
        &mut self,
        bytes: Bytes,
        buckets: &HashSet<i64>,
        selection: &Selection,
    ) -> Res<usize> {
        if self.bins.is_none() {
            return Err(Error::Fallback);
        }
        let drops_ids = self.drops_ids();
        let mut rows = 0;
        // Rows are in bucket order, so streams repeat across buckets: build
        // each stream's series key once.
        let mut keys: HashMap<crate::log_rollup::Stream, Option<SeriesKey>> = HashMap::new();
        let mut failure: Option<Error> = None;
        crate::log_rollup::read(bytes, |bucket, stream, cell| {
            if !buckets.contains(&bucket) {
                return Ok(());
            }
            rows += 1;
            if cell.traced > 0 && !drops_ids {
                return Err(crate::log_rollup::RollupError::Fallback);
            }
            let key = match keys.get(&stream) {
                Some(key) => key.clone(),
                None => {
                    let key = self.rollup_key(&stream, selection).map_err(|error| {
                        failure = Some(error);
                        crate::log_rollup::RollupError::Fallback
                    })?;
                    keys.insert(stream, key.clone());
                    key
                }
            };
            if let Some(key) = key {
                let amount = match self.value {
                    Value::Bytes => cell.bytes,
                    _ => cell.count,
                };
                self.add_bin(key, bucket, amount).map_err(|e| match e {
                    Error::Limit => crate::log_rollup::RollupError::TooLarge,
                    _ => crate::log_rollup::RollupError::Fallback,
                })?;
            }
            Ok(())
        })
        .map_err(|e| match (e, failure.take()) {
            (_, Some(error)) => error,
            (crate::log_rollup::RollupError::TooLarge, None) => Error::Limit,
            (crate::log_rollup::RollupError::Fallback, None) => Error::Fallback,
        })?;
        Ok(rows)
    }

    // The series key of a selected rollup stream, None when unselected.
    fn rollup_key(
        &self,
        stream: &crate::log_rollup::Stream,
        selection: &Selection,
    ) -> Res<Option<SeriesKey>> {
        let (service, level) = (stream.service.as_deref(), stream.level.as_deref());
        if !selected(selection, stream.resource.as_bytes(), service, level) {
            return Ok(None);
        }
        let base = entry_labels(
            &stream.resource,
            &stream.attributes,
            service,
            level,
            None,
            None,
        )?;
        if base.labels.get("__error__").is_some_and(|e| !e.is_empty()) {
            return Err(Error::Pipeline);
        }
        Ok(Some(self.key(&base.labels)))
    }
}

// A parsed write can replace a suffixed metadata owner. Later stages then see
// that name as parsed, while stream owners remain protected in this pipeline.
fn parsed_name(base: &EntryLabels, extracted: &HashSet<String>, mut name: String) -> String {
    if base.stream_keys.contains(&name)
        || (base.metadata_keys.contains(&name) && !extracted.contains(&name))
    {
        name.push_str("_extracted");
    }
    name
}

// The log decoder's stream selection, with promoted service/level mirrors.
fn present(value: Option<&str>) -> Option<&[u8]> {
    value.filter(|v| !v.is_empty()).map(str::as_bytes)
}

fn selected(
    selection: &Selection,
    resource: &[u8],
    service: Option<&str>,
    level: Option<&str>,
) -> bool {
    if let Some(wanted) = &selection.service {
        if service.map(str::as_bytes) != Some(wanted.as_slice()) {
            return false;
        }
    }
    selection.matchers.iter().all(|m| {
        let promoted = match m.name() {
            b"service" | b"service_name" => present(service),
            b"level" | b"detected_level" => present(level),
            _ => None,
        };
        if let Some(value) = promoted {
            return m.evaluate_present(value);
        }
        if resource.is_empty() {
            return m.evaluate_absent();
        }
        match query_filter::find_label(resource, m.name()) {
            Some(value) => m.evaluate_present(&value),
            None => m.evaluate_absent(),
        }
    })
}

/// Whether a stream's labels can be built natively, as `log_rollup` requires
/// of every stream it counts.
pub(crate) fn validate_labels(
    resource: &str,
    attributes: &str,
    service: Option<&str>,
    level: Option<&str>,
) -> Result<(), ()> {
    entry_labels(resource, attributes, service, level, None, None)
        .map(|_| ())
        .map_err(|_| ())
}

// Stream labels precede sorted metadata. Collisions get one suffix; an already
// occupied suffixed name is preserved. Non-string values use the BEAM path.
fn entry_labels(
    resource: &str,
    attributes: &str,
    service: Option<&str>,
    level: Option<&str>,
    trace_id: Option<&str>,
    span_id: Option<&str>,
) -> Res<EntryLabels> {
    let mut labels = Labels::new();
    let mut stream_keys = HashSet::new();
    if !resource.is_empty() {
        for (k, v) in
            query_filter::strict_string_pairs(resource.as_bytes()).ok_or(Error::Fallback)?
        {
            let k = String::from_utf8(k.into_owned()).map_err(|_| Error::Fallback)?;
            let v = String::from_utf8(v.into_owned()).map_err(|_| Error::Fallback)?;
            stream_keys.insert(k.clone());
            labels.insert(k, v);
        }
    }
    for (name, value) in [
        ("service", service),
        ("service_name", service),
        ("level", level),
        ("detected_level", level),
    ] {
        if let Some(value) = value {
            stream_keys.insert(name.to_owned());
            labels
                .entry(name.to_owned())
                .or_insert_with(|| value.to_owned());
        }
    }
    let mut metadata = Labels::new();
    if !attributes.is_empty() {
        for (k, v) in
            query_filter::strict_string_pairs(attributes.as_bytes()).ok_or(Error::Fallback)?
        {
            let k = String::from_utf8(k.into_owned()).map_err(|_| Error::Fallback)?;
            let v = String::from_utf8(v.into_owned()).map_err(|_| Error::Fallback)?;
            metadata.insert(k, v);
        }
    }
    for (name, value) in [("trace_id", trace_id), ("span_id", span_id)] {
        if let Some(value) = value.filter(|value| !value.is_empty()) {
            metadata
                .entry(name.to_owned())
                .or_insert_with(|| value.to_owned());
        }
    }
    let mut metadata_keys = HashSet::new();
    for (mut name, value) in metadata {
        if stream_keys.contains(&name) {
            name.push_str("_extracted");
            if labels.contains_key(&name) {
                continue;
            }
        }
        metadata_keys.insert(name.clone());
        labels.insert(name, value);
    }
    Ok(EntryLabels {
        labels,
        stream_keys,
        metadata_keys,
    })
}

// The unflagged Elixir logfmt stage: recover after malformed tokens, omit
// empty values and retain the first normalized key. Unicode decoding stays
// in the reference pipeline, including surrogate/replacement-rune policies.
fn logfmt(line: &[u8]) -> Res<Vec<(String, String)>> {
    if !line.is_ascii() {
        return Err(Error::Fallback);
    }
    let mut pairs = Vec::new();
    let mut seen = HashSet::new();
    let n = line.len();
    let mut i = 0;
    while i < n {
        while i < n && line[i] <= b' ' {
            i += 1;
        }
        if i >= n {
            break;
        }
        let key_start = i;
        while i < n && line[i] > b' ' && !matches!(line[i], b'=' | b'"') {
            i += 1;
        }
        if i == key_start || (i < n && line[i] == b'"') {
            logfmt_skip_token(line, &mut i);
            continue;
        }
        let key = &line[key_start..i];
        if i == n || line[i] != b'=' {
            continue;
        }
        i += 1;
        if i == n || line[i] <= b' ' {
            continue;
        }
        let value = if line[i] == b'"' {
            logfmt_quoted(line, &mut i)?
        } else {
            let start = i;
            while i < n && line[i] > b' ' && !matches!(line[i], b'=' | b'"') {
                i += 1;
            }
            if i < n && matches!(line[i], b'=' | b'"') {
                logfmt_skip_token(line, &mut i);
                None
            } else {
                Some(line[start..i].to_vec())
            }
        };
        let Some(value) = value.filter(|v| !v.is_empty()) else {
            continue;
        };
        let mut normalized = String::with_capacity(key.len() + 1);
        if key[0].is_ascii_digit() {
            normalized.push('_');
        }
        for &c in key {
            normalized.push(if c.is_ascii_alphanumeric() || c == b'_' {
                char::from(c)
            } else {
                '_'
            });
        }
        if seen.insert(normalized.clone()) {
            pairs.push((
                normalized,
                String::from_utf8(value).map_err(|_| Error::Fallback)?,
            ));
        }
    }
    Ok(pairs)
}

fn logfmt_skip_token(line: &[u8], i: &mut usize) {
    while *i < line.len() && line[*i] > b' ' {
        *i += 1;
    }
}

fn logfmt_quoted(line: &[u8], i: &mut usize) -> Res<Option<Vec<u8>>> {
    *i += 1;
    let start = *i;
    while *i < line.len() && line[*i] != b'"' {
        *i += if line[*i] == b'\\' { 2 } else { 1 };
    }
    if *i >= line.len() {
        *i = line.len();
        return Ok(None);
    }
    let body = &line[start..*i];
    *i += 1;
    let mut value = Vec::with_capacity(body.len());
    let mut cursor = 0;
    while cursor < body.len() {
        if body[cursor] == b'\\' {
            cursor += 1;
            let decoded = match body[cursor] {
                b'"' | b'\\' | b'/' | b'\'' => body[cursor],
                b'b' => 8,
                b'f' => 12,
                b'n' => 10,
                b'r' => 13,
                b't' => 9,
                b'u' => return Err(Error::Fallback),
                _ => return Ok(None),
            };
            value.push(decoded);
        } else {
            value.push(body[cursor]);
        }
        cursor += 1;
    }
    Ok(Some(value))
}

fn evaluate(filter: &Filter, labels: &Labels) -> Res<bool> {
    Ok(match filter {
        Filter::And(l, r) => {
            let left = evaluate(l, labels)?;
            let right = evaluate(r, labels)?;
            left && right
        }
        Filter::Or(l, r) => evaluate(l, labels)? || evaluate(r, labels)?,
        Filter::Str {
            name,
            negate,
            value,
        } => (labels.get(name).map_or(&b""[..], |v| v.as_bytes()) == value.as_slice()) != *negate,
        Filter::Re {
            name,
            negate,
            regex,
        } => regex.is_match(labels.get(name).map_or(&b""[..], |v| v.as_bytes())) != *negate,
        Filter::Num { name, op, value } => match labels.get(name) {
            None => false,
            Some(text) => compare(*op, label_number(text)?, *value)?,
        },
    })
}

// Ordinary decimal values use float comparisons, as Go ParseFloat does.
// Every other spelling or conversion failure needs the Elixir pipeline,
// including its error labels, first-error preservation and boolean state.
fn label_number(text: &str) -> Res<Number> {
    let bytes = text.as_bytes();
    let digits = |s: &[u8]| !s.is_empty() && s.iter().all(u8::is_ascii_digit);
    let unsigned = bytes
        .strip_prefix(b"-")
        .or_else(|| bytes.strip_prefix(b"+"))
        .unwrap_or(bytes);
    if digits(unsigned) {
        return text
            .parse::<i64>()
            .map(Number::Int)
            .map_err(|_| Error::Fallback);
    }
    let (mantissa, exponent) = match unsigned.iter().position(|b| matches!(b, b'e' | b'E')) {
        Some(i) => (&unsigned[..i], Some(&unsigned[i + 1..])),
        None => (unsigned, None),
    };
    let (whole, fraction) = match mantissa.iter().position(|&b| b == b'.') {
        Some(i) => (&mantissa[..i], Some(&mantissa[i + 1..])),
        None => (mantissa, None),
    };
    let exponent_ok = exponent.is_none_or(|e| {
        digits(
            e.strip_prefix(b"-")
                .or_else(|| e.strip_prefix(b"+"))
                .unwrap_or(e),
        )
    });
    if !digits(whole) || !fraction.is_none_or(digits) || !exponent_ok {
        return Err(Error::Fallback);
    }
    let value: f64 = text.parse().map_err(|_| Error::Fallback)?;
    if value.is_finite() {
        Ok(Number::Float(value))
    } else {
        Err(Error::Fallback)
    }
}

// Both operands are float64, including integers beyond exact float precision.
fn compare(op: CmpOp, actual: Number, expected: Number) -> Res<bool> {
    let ordering = actual
        .float()
        .partial_cmp(&expected.float())
        .ok_or(Error::Fallback)?;
    use std::cmp::Ordering::*;
    Ok(match op {
        CmpOp::Eq => ordering == Equal,
        CmpOp::Neq => ordering != Equal,
        CmpOp::Lt => ordering == Less,
        CmpOp::Lte => ordering != Greater,
        CmpOp::Gt => ordering == Greater,
        CmpOp::Gte => ordering != Less,
    })
}

// `FloatParser.parse/1` for unwrap: plain decimals parse here; a missing
// label or text without digits (other than NaN/Inf spellings) is an
// extraction error; every other spelling falls back.
fn unwrap_value(value: Option<&String>) -> Res<Sample> {
    let Some(text) = value else {
        return Ok(Sample::Error);
    };
    let bytes = text.as_bytes();
    let unsigned = bytes
        .strip_prefix(b"-")
        .or_else(|| bytes.strip_prefix(b"+"))
        .unwrap_or(bytes);
    let (mantissa, exponent) = match unsigned.iter().position(|b| matches!(b, b'e' | b'E')) {
        Some(i) => (&unsigned[..i], Some(&unsigned[i + 1..])),
        None => (unsigned, None),
    };
    let digits = |s: &[u8]| !s.is_empty() && s.iter().all(u8::is_ascii_digit);
    let (whole, fraction) = match mantissa.iter().position(|&b| b == b'.') {
        Some(i) => (&mantissa[..i], Some(&mantissa[i + 1..])),
        None => (mantissa, None),
    };
    let mantissa_ok = match fraction {
        None => digits(whole),
        Some(f) => {
            (digits(whole) && (f.is_empty() || digits(f))) || (whole.is_empty() && digits(f))
        }
    };
    let exponent_ok = exponent.is_none_or(|e| {
        digits(
            e.strip_prefix(b"-")
                .or_else(|| e.strip_prefix(b"+"))
                .unwrap_or(e),
        )
    });
    if mantissa_ok && exponent_ok {
        let normalized = text.replace(".e", ".0e").replace(".E", ".0E");
        let normalized = if normalized.ends_with('.') {
            format!("{normalized}0")
        } else {
            normalized
        };
        let value: f64 = normalized.parse().map_err(|_| Error::Fallback)?;
        return if value.is_finite() {
            Ok(Sample::Float(value))
        } else {
            Err(Error::Fallback)
        };
    }
    let lower = text.to_ascii_lowercase();
    let special = [
        "nan",
        "inf",
        "+inf",
        "-inf",
        "infinity",
        "+infinity",
        "-infinity",
    ]
    .contains(&lower.as_str());
    if !special && !bytes.iter().any(u8::is_ascii_digit) {
        Ok(Sample::Error)
    } else {
        Err(Error::Fallback)
    }
}
