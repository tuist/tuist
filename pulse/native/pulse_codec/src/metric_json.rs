//! Full metric-sample JSON, including nullable typed OTLP metadata.
//! Counter preflight proves complete output size before binary allocation.
use crate::atoms;
use crate::out::{BinSink, Counter, Sink};
use crate::term_json::{Enc, EncodeError, JsonEncoder};
use rustler::{Binary, Encoder, Env, ListIterator, MapIterator, Term};

pub const MAX_PAYLOAD: usize = 16 * 1024 * 1024;

pub fn payload_size<'a>(env: Env<'a>, samples: Term<'a>, limit: usize) -> Enc<usize> {
    let mut counter = Counter::new(limit);
    write(env, &mut counter, samples, limit)?;
    Ok(counter.len())
}

pub fn encode<'a>(env: Env<'a>, samples: Term<'a>, limit: usize) -> Enc<Binary<'a>> {
    let size = payload_size(env, samples, limit)?;
    let mut out = BinSink::with_capacity(size);
    write(env, &mut out, samples, limit)?;
    Ok(out.finish(env))
}

fn write<'a, S: Sink>(env: Env<'a>, out: &mut S, samples: Term<'a>, limit: usize) -> Enc<()> {
    samples.list_length().map_err(|_| EncodeError::Fallback)?;
    let items: ListIterator = samples.decode().map_err(|_| EncodeError::Fallback)?;
    let enc = JsonEncoder::new(env, limit);
    let expected = atoms::metric_sample().encode(env);
    let nil = atoms::nil().encode(env);
    out.push(b'[');
    for (i, sample) in items.enumerate() {
        if sample
            .map_get(atoms::struct_key())
            .map_err(|_| EncodeError::Fallback)?
            .as_c_arg()
            != expected.as_c_arg()
        {
            return Err(EncodeError::Fallback);
        }
        validate_fields(sample, nil)?;
        if i > 0 {
            out.push(b',');
        }
        out.extend(b"{\"series_id\":");
        enc.value(
            out,
            sample
                .map_get(atoms::series_id())
                .map_err(|_| EncodeError::Fallback)?,
            0,
        )?;
        out.extend(b",\"timestamp_ns\":");
        enc.value(
            out,
            sample
                .map_get(atoms::timestamp_ns())
                .map_err(|_| EncodeError::Fallback)?,
            0,
        )?;
        out.extend(b",\"value\":");
        enc.value(
            out,
            sample
                .map_get(atoms::value())
                .map_err(|_| EncodeError::Fallback)?,
            0,
        )?;
        out.extend(b",\"labels\":");
        enc.value(
            out,
            sample
                .map_get(atoms::labels())
                .map_err(|_| EncodeError::Fallback)?,
            0,
        )?;
        out.extend(b",\"otlp\":");
        enc.value(out, sample.map_get(atoms::otlp()).unwrap_or(nil), 0)?;
        let start = sample.map_get(atoms::start_timestamp_ms()).unwrap_or(nil);
        if start.as_c_arg() != nil.as_c_arg() {
            start.decode::<i64>().map_err(|_| EncodeError::Fallback)?;
            out.extend(b",\"start_timestamp_ms\":");
            enc.value(out, start, 0)?;
        }
        write_exemplars(
            out,
            &enc,
            sample.map_get(atoms::exemplars()).unwrap_or(nil),
            nil,
        )?;
        out.push(b'}');
    }
    out.push(b']');
    if out.len() > limit {
        return Err(EncodeError::TooBig);
    }
    Ok(())
}

// As the Elixir reference renders `%Pulse.Record.Exemplar{}` fields, in key order.
fn write_exemplars<'a, S: Sink>(
    out: &mut S,
    enc: &JsonEncoder<'a>,
    exemplars: Term<'a>,
    nil: Term<'a>,
) -> Enc<()> {
    if exemplars.as_c_arg() == nil.as_c_arg() {
        return Ok(());
    }
    let items: ListIterator = exemplars.decode().map_err(|_| EncodeError::Fallback)?;
    out.extend(b",\"exemplars\":[");
    for (i, exemplar) in items.enumerate() {
        if i > 0 {
            out.push(b',');
        }
        for (j, (key, name)) in [
            (atoms::labels(), &b"labels"[..]),
            (atoms::timestamp_ns(), b"timestamp_ns"),
            (atoms::value(), b"value"),
        ]
        .into_iter()
        .enumerate()
        {
            out.push(if j == 0 { b'{' } else { b',' });
            out.push(b'"');
            out.extend(name);
            out.extend(b"\":");
            let field = exemplar.map_get(key).map_err(|_| EncodeError::Fallback)?;
            enc.value(out, field, 0)?;
        }
        out.push(b'}');
    }
    out.push(b']');
    Ok(())
}

fn validate_fields<'a>(sample: Term<'a>, nil: Term<'a>) -> Enc<()> {
    for key in [atoms::series_id(), atoms::timestamp_ns()] {
        let term = sample.map_get(key).map_err(|_| EncodeError::Fallback)?;
        if term.as_c_arg() != nil.as_c_arg() && term.decode::<i64>().is_err() {
            return Err(EncodeError::Fallback);
        }
    }
    // The Elixir reference renders histograms.
    if sample
        .map_get(atoms::histogram())
        .is_ok_and(|term| term.as_c_arg() != nil.as_c_arg())
    {
        return Err(EncodeError::Fallback);
    }
    let value = sample
        .map_get(atoms::value())
        .map_err(|_| EncodeError::Fallback)?;
    if value.as_c_arg() != nil.as_c_arg() && crate::metric_value::decode(value).is_err() {
        return Err(EncodeError::Fallback);
    }
    let labels = sample
        .map_get(atoms::labels())
        .map_err(|_| EncodeError::Fallback)?;
    for (key, value) in MapIterator::new(labels).ok_or(EncodeError::Fallback)? {
        key.decode::<Binary>().map_err(|_| EncodeError::Fallback)?;
        value
            .decode::<Binary>()
            .map_err(|_| EncodeError::Fallback)?;
    }
    let metadata = sample.map_get(atoms::otlp()).unwrap_or(nil);
    if metadata.as_c_arg() != nil.as_c_arg() && metadata.get_type() != rustler::TermType::Map {
        return Err(EncodeError::Fallback);
    }
    Ok(())
}
