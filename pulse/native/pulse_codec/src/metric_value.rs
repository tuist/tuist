//! Preserve IEEE-754 values without constructing unsupported BEAM floats.
use rustler::{Encoder, Env, Term};

pub const STALE_BITS: u64 = 0x7ff0000000000002;
/// The float value of a row that only carries exemplars: their sample is in
/// another request. Readers that predate exemplars see an ordinary NaN.
pub const EXEMPLAR_ONLY_BITS: u64 = 0x7ff0000000000003;
mod atoms {
    rustler::atoms! { stale, nan, infinity, negative_infinity }
}

pub fn encode<'a>(env: Env<'a>, value: f64) -> Term<'a> {
    if value.to_bits() == STALE_BITS {
        atoms::stale().encode(env)
    } else if value.is_nan() {
        atoms::nan().encode(env)
    } else if value == f64::INFINITY {
        atoms::infinity().encode(env)
    } else if value == f64::NEG_INFINITY {
        atoms::negative_infinity().encode(env)
    } else {
        value.encode(env)
    }
}

pub fn decode(term: Term<'_>) -> Result<f64, ()> {
    if term == atoms::stale().encode(term.get_env()) {
        Ok(f64::from_bits(STALE_BITS))
    } else if term == atoms::nan().encode(term.get_env()) {
        Ok(f64::NAN)
    } else if term == atoms::infinity().encode(term.get_env()) {
        Ok(f64::INFINITY)
    } else if term == atoms::negative_infinity().encode(term.get_env()) {
        Ok(f64::NEG_INFINITY)
    } else {
        term.decode::<f64>()
            .or_else(|_| term.decode::<i64>().map(|i| i as f64))
            .map_err(|_| ())
    }
}
