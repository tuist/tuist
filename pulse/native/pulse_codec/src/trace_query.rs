//! Per-query native state. BEAM owns admission, S3 I/O and deadlines; Rust owns
//! global top-k and final JSON. No selected span is materialized on the VM heap.
use crate::trace_segment_parquet::{self, Error, Selection};
use rustler::env::SavedTerm;
use rustler::{Binary, Encoder, Env, OwnedEnv, ResourceArc, Term};
use std::sync::Mutex;

struct State {
    env: OwnedEnv,
    filters: SavedTerm,
    attributes: trace_segment_parquet::AttributeFilters,
    start: Option<i128>,
    retained_snapshot: bool,
    end: Option<i128>,
    max: usize,
    limit: usize,
    fields: Option<Vec<String>>,
    selection: Option<Selection>,
}
pub struct Query(Mutex<State>);
#[rustler::resource_impl]
impl rustler::Resource for Query {}

fn result<'a, T: Encoder>(env: Env<'a>, value: Result<T, Error>) -> Term<'a> {
    match value {
        Ok(value) => (crate::atoms::ok(), value).encode(env),
        Err(Error::TooMany) => {
            (crate::atoms::error(), crate::atoms::query_sample_limit()).encode(env)
        }
        Err(Error::QueryBytes) => {
            (crate::atoms::error(), crate::atoms::query_resource_limit()).encode(env)
        }
        Err(Error::ProjectionTie) => {
            (crate::atoms::error(), crate::atoms::trace_projection_tie()).encode(env)
        }
        Err(_) => crate::atoms::fallback().encode(env),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn trace_query_new<'a>(
    env: Env<'a>,
    start: Term<'a>,
    end: Term<'a>,
    filters: Term<'a>,
    fields: Term<'a>,
    max: usize,
) -> Term<'a> {
    new_query(env, start, end, filters, fields, (max, false))
}

// Only this constructor may apply a retention floor to an assembled trace.
// Its fixed predicate and overflow sentinel cannot describe a filtered search.
#[rustler::nif(schedule = "DirtyCpu")]
fn trace_query_new_trace<'a>(
    env: Env<'a>,
    trace_id: String,
    floor: Term<'a>,
    max: usize,
) -> Term<'a> {
    let valid_floor = crate::optional_int(floor)
        .is_ok_and(|v| v.is_none_or(|f| (0..=i128::from(i64::MAX)).contains(&f)));
    if !valid_floor {
        return crate::atoms::fallback().encode(env);
    }
    let filters = Term::map_from_pairs(
        env,
        &[
            ("trace_id".encode(env), trace_id.encode(env)),
            ("limit".encode(env), 5001usize.encode(env)),
        ],
    )
    .unwrap();
    let nil = crate::atoms::nil().encode(env);
    new_query(env, floor, nil, filters, nil, (max, true))
}

fn new_query<'a>(
    env: Env<'a>,
    start: Term<'a>,
    end: Term<'a>,
    filters: Term<'a>,
    fields: Term<'a>,
    policy: (usize, bool),
) -> Term<'a> {
    let (max, retained_snapshot) = policy;
    let build = || -> Result<ResourceArc<Query>, Error> {
        let start = crate::optional_int(start).map_err(|_| Error::Invalid)?;
        let end = crate::optional_int(end).map_err(|_| Error::Invalid)?;
        let limit: usize = filters
            .map_get("limit".encode(env))
            .map_err(|_| Error::Invalid)?
            .decode()
            .map_err(|_| Error::Invalid)?;
        if limit == 0 || limit > 5001 {
            return Err(Error::Invalid);
        }
        let fields: Option<Vec<String>> = fields.decode().map_err(|_| Error::Invalid)?;
        if fields
            .as_ref()
            .is_some_and(|fs| fs.len() > 32 || fs.iter().any(|f| f.len() > 64))
        {
            return Err(Error::Invalid);
        }
        let attributes = trace_segment_parquet::attribute_filters(env, filters)?;
        // Callers rerun with complete keys after a `trace_projection_tie`.
        let full_keys = filters
            .map_get("full_sort_keys".encode(env))
            .is_ok_and(|value| matches!(value.decode::<bool>(), Ok(true)));
        let projection = if full_keys { None } else { fields.clone() };
        let owned = OwnedEnv::new();
        let saved = owned.save(filters);
        Ok(ResourceArc::new(Query(Mutex::new(State {
            env: owned,
            filters: saved,
            attributes,
            start,
            retained_snapshot,
            end,
            max,
            limit,
            fields,
            selection: Some(Selection::projected(projection)),
        }))))
    };
    result(env, build())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn trace_query_add<'a>(env: Env<'a>, query: ResourceArc<Query>, blob: Binary<'a>) -> Term<'a> {
    let add = || -> Result<(usize, Option<i64>, usize), Error> {
        let mut state = query.0.try_lock().map_err(|_| Error::QueryBytes)?;
        let filters = state.env.run(|e| state.filters.load(e).in_env(env));
        let start = state
            .selection
            .as_ref()
            .ok_or(Error::Invalid)?
            .kth(state.limit)
            .map(i128::from)
            .map(|floor| state.start.map_or(floor, |s| s.max(floor)))
            .or(state.start);
        let end = state.end;
        let max = state.max;
        // Reuse compiled programs and bounded lazy-DFA caches for this query.
        let State {
            attributes,
            selection,
            ..
        } = &mut *state;
        let scan = trace_segment_parquet::select_prepared(
            env,
            blob,
            start,
            end,
            filters,
            max,
            (attributes, selection.as_mut().ok_or(Error::Invalid)?),
        );
        match scan {
            Ok(rows) => {
                let selection = state.selection.as_ref().unwrap();
                Ok((selection.matches, selection.kth(state.limit), rows))
            }
            Err(error) => {
                state.selection = None;
                Err(error)
            }
        }
    };
    result(env, add())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn trace_query_finish<'a>(env: Env<'a>, query: ResourceArc<Query>, max_results: usize) -> Term<'a> {
    let finish = || -> Result<Binary<'a>, Error> {
        let mut state = query.0.try_lock().map_err(|_| Error::QueryBytes)?;
        let selection = state.selection.take().ok_or(Error::Invalid)?;
        if selection.matches > max_results {
            return Err(Error::TooMany);
        }
        selection.json(env, state.fields.as_deref())
    };
    result(env, finish())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn trace_query_finish_trace<'a>(
    env: Env<'a>,
    query: ResourceArc<Query>,
    max_results: usize,
    trace_id: String,
) -> Term<'a> {
    let finish = || -> Result<Binary<'a>, Error> {
        let mut state = query.0.try_lock().map_err(|_| Error::QueryBytes)?;
        let selection = state.selection.take().ok_or(Error::Invalid)?;
        // A top-k or attribute-filtered state cannot establish all-stored-span
        // coverage, even when its retained candidates happen to share an ID.
        let exact = state.env.run(|e| {
            let filters = state.filters.load(e);
            let pairs: Result<rustler::types::map::MapIterator, _> = filters.decode();
            let id: Option<String> = filters
                .map_get("trace_id".encode(e))
                .ok()
                .and_then(|v| v.decode().ok());
            pairs.is_ok_and(|pairs| pairs.count() == 2) && id.as_deref() == Some(trace_id.as_str())
        });
        if state.limit != 5001
            || state.fields.is_some()
            || (state.start.is_some() && !state.retained_snapshot)
            || state.end.is_some()
            || max_results > 5000
            || !exact
        {
            return Err(Error::Invalid);
        }
        if selection.matches > max_results {
            return Err(Error::TooMany);
        }
        selection.assembly(env, &trace_id, state.start)
    };
    result(env, finish())
}
