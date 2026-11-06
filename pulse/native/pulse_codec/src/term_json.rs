//! Erlang terms <-> JSON.
//!
//! The encoder writes the same JSON Elixir's `JSON` module would (modulo
//! float spelling, which round-trips identically) for binaries, integers
//! within 64 bits, floats, atoms, proper lists and maps whose keys are
//! binaries, atoms or integers. Anything else it cannot guarantee to match
//! — structs (which Elixir encodes through a protocol), bignums, float,
//! tuple or colliding keys, invalid UTF-8, improper lists, pids, tuples —
//! returns `Fallback` and the caller re-encodes in Elixir. The same rules
//! reproduce `Pulse.Storage.S3`'s key sanitizing for the cases they accept,
//! because sanitizing only differs from plain encoding on inputs that fall
//! back.

use crate::json_read::{Builder, Fallback, Number, Res};
use crate::json_write::{write_f64, write_i64, write_str, write_u64};
use crate::out::Sink;
use rustler::types::map::MapIterator;
use rustler::{Binary, Encoder, Env, ListIterator, NewBinary, Term, TermType};
use std::borrow::Cow;

// Storage uses this encoder too: never write JSON deeper than our parser
// can read back. General-purpose JSON calls fall back to Elixir at this bound.
const MAX_DEPTH: usize = crate::json_read::MAX_DEPTH;

/// Strings at or below this size are copied into small heap binaries;
/// larger ones become sub-binaries of the input.
const SUBBINARY_MIN: usize = 64;

pub enum EncodeError {
    Fallback,
    /// The output passed the caller's budget (used to move large
    /// encodings off the regular schedulers).
    TooBig,
}

impl From<Fallback> for EncodeError {
    fn from(_: Fallback) -> Self {
        EncodeError::Fallback
    }
}

pub type Enc<T> = Result<T, EncodeError>;

pub struct JsonEncoder<'a> {
    nil: usize,
    true_: usize,
    false_: usize,
    struct_key: usize,
    pub budget: usize,
    _env: Env<'a>,
}

fn raw(t: Term) -> usize {
    t.as_c_arg()
}

impl<'a> JsonEncoder<'a> {
    pub fn new(env: Env<'a>, budget: usize) -> Self {
        JsonEncoder {
            nil: raw(rustler::types::atom::nil().encode(env)),
            true_: raw(true.encode(env)),
            false_: raw(false.encode(env)),
            struct_key: raw(rustler::types::atom::Atom::from_str(env, "__struct__")
                .unwrap()
                .encode(env)),
            budget,
            _env: env,
        }
    }

    pub fn is_nil_or_false(&self, t: Term) -> bool {
        let r = raw(t);
        r == self.nil || r == self.false_
    }

    pub fn value<S: Sink>(&self, out: &mut S, t: Term, depth: usize) -> Enc<()> {
        if depth > MAX_DEPTH {
            return Err(EncodeError::Fallback);
        }
        match t.get_type() {
            TermType::Binary => {
                let b: Binary = t.decode().map_err(|_| Fallback)?;
                let bytes = b.as_slice();
                simdutf8::basic::from_utf8(bytes).map_err(|_| Fallback)?;
                write_str(out, bytes);
            }
            TermType::Integer => write_int(out, t)?,
            TermType::Float => {
                let f: f64 = t.decode().map_err(|_| Fallback)?;
                write_f64(out, f);
            }
            TermType::Atom => {
                let r = raw(t);
                if r == self.nil {
                    out.extend(b"null");
                } else if r == self.true_ {
                    out.extend(b"true");
                } else if r == self.false_ {
                    out.extend(b"false");
                } else {
                    let name = t.atom_to_string().map_err(|_| Fallback)?;
                    write_str(out, name.as_bytes());
                }
            }
            TermType::List => {
                t.list_length().map_err(|_| Fallback)?;
                let items: ListIterator = t.decode().map_err(|_| Fallback)?;
                out.push(b'[');
                for (i, item) in items.enumerate() {
                    if i > 0 {
                        out.push(b',');
                    }
                    self.value(out, item, depth + 1)?;
                }
                out.push(b']');
            }
            TermType::Map => self.map(out, t, depth)?,
            _ => return Err(EncodeError::Fallback),
        }
        if out.len() > self.budget {
            return Err(EncodeError::TooBig);
        }
        Ok(())
    }

    pub fn map<S: Sink>(&self, out: &mut S, t: Term, depth: usize) -> Enc<()> {
        let entries: Vec<(Term, Term)> = MapIterator::new(t).ok_or(Fallback)?.collect();
        // Keys only need a collision check when one is not a binary: map
        // keys are unique terms, but `:a` and "a" stringify the same.
        let mut stringified: Option<Vec<Cow<[u8]>>> = None;
        for (k, _) in &entries {
            if raw(*k) == self.struct_key {
                return Err(EncodeError::Fallback);
            }
            if stringified.is_none() && k.get_type() != TermType::Binary {
                stringified = Some(Vec::with_capacity(entries.len()));
            }
        }
        if let Some(keys) = stringified.as_mut() {
            for (k, _) in &entries {
                let key = key_bytes(*k)?;
                if keys.contains(&key) {
                    return Err(EncodeError::Fallback);
                }
                keys.push(key);
            }
        }
        out.push(b'{');
        for (i, (k, v)) in entries.iter().enumerate() {
            if i > 0 {
                out.push(b',');
            }
            let key = key_bytes(*k)?;
            write_str(out, &key);
            out.push(b':');
            self.value(out, *v, depth + 1)?;
        }
        out.push(b'}');
        Ok(())
    }
}

fn write_int<S: Sink>(out: &mut S, t: Term) -> Res<()> {
    if let Ok(i) = t.decode::<i64>() {
        write_i64(out, i);
    } else {
        write_u64(out, t.decode::<u64>().map_err(|_| Fallback)?);
    }
    Ok(())
}

fn key_bytes<'t>(k: Term<'t>) -> Res<Cow<'t, [u8]>> {
    match k.get_type() {
        TermType::Binary => {
            let b: Binary<'t> = k.decode().map_err(|_| Fallback)?;
            simdutf8::basic::from_utf8(b.as_slice()).map_err(|_| Fallback)?;
            Ok(Cow::Borrowed(b.as_slice()))
        }
        TermType::Atom => Ok(Cow::Owned(
            k.atom_to_string().map_err(|_| Fallback)?.into_bytes(),
        )),
        TermType::Integer => {
            let mut buf = Vec::new();
            write_int(&mut buf, k)?;
            Ok(Cow::Owned(buf))
        }
        _ => Err(Fallback),
    }
}

/// Builds Erlang terms from parsed JSON. Values Elixir's `JSON` would
/// produce: maps with binary keys, lists, binaries, integers, floats,
/// `true`/`false`/`nil`.
pub type InternedKeys<'a> = Vec<(&'a [u8], Term<'a>)>;

pub struct TermBuilder<'a, 'b> {
    env: Env<'a>,
    input: &'b Binary<'a>,
    /// Object keys seen so far, so a key repeated across objects (OTLP's
    /// "key"/"value", a segment's attribute names, a manifest's field
    /// names) is one shared binary instead of one per occurrence.
    keys: InternedKeys<'a>,
}

const INTERN_MAX_KEY: usize = 32;
const INTERN_MAX_KEYS: usize = 128;

impl<'a, 'b> TermBuilder<'a, 'b> {
    pub fn new(env: Env<'a>, input: &'b Binary<'a>) -> Self {
        TermBuilder {
            env,
            input,
            keys: Vec::new(),
        }
    }

    /// Reuse the bounded interning cache across documents backed by binaries
    /// in this same NIF environment. Borrowed key bytes must remain alive for
    /// the entire environment (as with Parquet column arenas).
    pub fn with_keys(env: Env<'a>, input: &'b Binary<'a>, keys: InternedKeys<'a>) -> Self {
        TermBuilder { env, input, keys }
    }

    pub fn into_keys(self) -> InternedKeys<'a> {
        self.keys
    }

    pub fn bytes(&self, s: &[u8]) -> Res<Term<'a>> {
        let base = self.input.as_slice();
        let start = (s.as_ptr() as usize).wrapping_sub(base.as_ptr() as usize);
        let inside = start <= base.len() && s.len() <= base.len() - start;
        if s.len() > SUBBINARY_MIN && inside {
            return self
                .input
                .make_subbinary(start, s.len())
                .map(|b| b.encode(self.env))
                .map_err(|_| Fallback);
        }
        let mut nb = NewBinary::new(self.env, s.len());
        nb.as_mut_slice().copy_from_slice(s);
        Ok(Binary::from(nb).encode(self.env))
    }
}

impl<'a, 'b> Builder<'a> for TermBuilder<'a, 'b> {
    type Value = Term<'a>;
    fn null(&mut self) -> Res<Term<'a>> {
        Ok(rustler::types::atom::nil().encode(self.env))
    }
    fn boolean(&mut self, v: bool) -> Res<Term<'a>> {
        Ok(v.encode(self.env))
    }
    fn number(&mut self, n: Number) -> Res<Term<'a>> {
        Ok(match n {
            Number::Int(i) => i.encode(self.env),
            Number::UInt(u) => u.encode(self.env),
            Number::Float(f) => f.encode(self.env),
        })
    }
    fn string(&mut self, s: Cow<'a, [u8]>) -> Res<Term<'a>> {
        self.bytes(&s)
    }
    fn key(&mut self, s: Cow<'a, [u8]>) -> Res<Term<'a>> {
        let Cow::Borrowed(bytes) = s else {
            return self.bytes(&s);
        };
        if bytes.len() > INTERN_MAX_KEY {
            return self.bytes(bytes);
        }
        if let Some((_, term)) = self.keys.iter().find(|(k, _)| *k == bytes) {
            return Ok(*term);
        }
        let term = self.bytes(bytes)?;
        if self.keys.len() < INTERN_MAX_KEYS {
            self.keys.push((bytes, term));
        }
        Ok(term)
    }
    fn array(&mut self, items: &[Term<'a>]) -> Res<Term<'a>> {
        Ok(items.encode(self.env))
    }
    fn object(&mut self, keys: &[Term<'a>], values: &[Term<'a>]) -> Res<Term<'a>> {
        // Fails on duplicate keys; Elixir keeps the first, so fall back.
        Term::map_from_arrays(self.env, keys, values).map_err(|_| Fallback)
    }
}
