//! Bounded protobuf merge plans. Raw preflight precedes every allocation here.
//! Keep borrowed scalar slices and native plans until *all* logical owner budgets
//! pass. Supplied charges survive oneof replacement, even though its value does not.
use super::{
    base64, binary, field, packed_number, Error, Kind, Options, Reader, Res, Schema, Value,
};
use rustler::{Encoder, Env, Term};
use std::collections::btree_map::Entry;
use std::collections::BTreeMap;

#[derive(Default, Clone, Copy)]
struct Charge {
    bytes: usize,
    nodes: usize,
}
impl Charge {
    fn add(&mut self, other: Self) {
        self.bytes = self.bytes.saturating_add(other.bytes);
        self.nodes = self.nodes.saturating_add(other.nodes);
    }
}
struct Plan<'b> {
    schema: Schema,
    fields: BTreeMap<u64, Values<'b>>,
    supplied: Charge,
    pairs: usize,
}
enum Item<'b> {
    Scalar(Value<'b>),
    Message(Plan<'b>),
}
enum Values<'b> {
    Single(Item<'b>),
    Many(Vec<Item<'b>>),
}
fn attribute(schema: Schema) -> bool {
    matches!(
        schema,
        Schema::Pair | Schema::Any | Schema::Array | Schema::KvList
    )
}
fn oneof(schema: Schema, number: u64) -> bool {
    match schema {
        Schema::Any => (1..=7).contains(&number),
        Schema::Metric => matches!(number, 5 | 7 | 9 | 10 | 11),
        Schema::NumberPoint => matches!(number, 4 | 6),
        Schema::Exemplar => matches!(number, 3 | 6),
        _ => false,
    }
}
impl<'b> Plan<'b> {
    fn new(schema: Schema) -> Self {
        Self {
            schema,
            fields: BTreeMap::new(),
            supplied: Charge::default(),
            pairs: 0,
        }
    }
    fn merge(&mut self, bytes: &'b [u8], options: Options) -> Res<Charge> {
        let context = attribute(self.schema);
        let mut charge = Charge {
            bytes: 0,
            nodes: usize::from(context),
        };
        let mut reader = Reader { bytes, pos: 0 };
        while let Some((number, _, value)) = reader.next()? {
            let Some((_, kind, many)) = field(self.schema, number) else {
                continue;
            };
            if oneof(self.schema, number) {
                self.fields
                    .retain(|&key, _| key == number || !oneof(self.schema, key));
            }
            match (kind, value) {
                (Kind::Message(child), Value::Data(bytes)) => {
                    let mut nested_options = options;
                    if self.schema == Schema::LogRecord && number == 5 {
                        nested_options.3 = 16 * 1024 * 1024;
                        nested_options.4 = 16 * 1024 * 1024;
                    }
                    let added = if many {
                        let mut child_plan = Plan::new(child);
                        let added = child_plan.merge(bytes, nested_options)?;
                        self.push(number, Item::Message(child_plan))?;
                        added
                    } else {
                        let entry = self
                            .fields
                            .entry(number)
                            .or_insert_with(|| Values::Single(Item::Message(Plan::new(child))));
                        let Values::Single(Item::Message(child_plan)) = entry else {
                            return Err(Error::InvalidProtobuf);
                        };
                        child_plan.merge(bytes, nested_options)?
                    };
                    if child == Schema::Pair {
                        self.pairs = self.pairs.saturating_add(1);
                        if self.pairs > options.1 {
                            return Err(Error::AttributesTooLarge);
                        }
                    }
                    if context || child == Schema::Pair {
                        charge.add(added);
                    }
                }
                (Kind::PackedUint64, Value::Data(bytes)) => {
                    super::packed_varints(bytes)?;
                    let mut reader = super::Reader { bytes, pos: 0 };
                    while reader.pos < bytes.len() {
                        let n = reader.varint()?;
                        self.push(number, Item::Scalar(Value::Number(n)))?;
                    }
                    // Preserve an explicitly empty repeated field as well.
                    self.fields
                        .entry(number)
                        .or_insert_with(|| Values::Many(Vec::new()));
                }
                (Kind::PackedFixed64 | Kind::PackedDouble, Value::Data(bytes)) => {
                    for bytes in bytes.as_chunks::<8>().0 {
                        self.push(
                            number,
                            Item::Scalar(Value::Number(u64::from_le_bytes(*bytes))),
                        )?;
                    }
                    // Preserve an explicitly empty repeated field as well.
                    self.fields
                        .entry(number)
                        .or_insert_with(|| Values::Many(Vec::new()));
                }
                (_, value) => {
                    if context {
                        charge.bytes = charge.bytes.saturating_add(match &value {
                            Value::Data(bytes) if matches!(kind, Kind::Bytes) => {
                                bytes.len().div_ceil(3) * 4
                            }
                            Value::Data(bytes) => bytes.len(),
                            Value::Number(_) => 8,
                        });
                    }
                    if many {
                        self.push(number, Item::Scalar(value))?;
                    } else {
                        self.fields
                            .insert(number, Values::Single(Item::Scalar(value)));
                    }
                }
            }
            // Charge ignored/replaced branches too. A split owner cannot hide
            // aggregate bytes/nodes by overwriting its AnyValue oneof.
            let mut total = self.supplied;
            total.add(charge);
            if total.bytes > options.4 || total.nodes > options.6 {
                return Err(Error::AttributesTooLarge);
            }
        }
        self.supplied.add(charge);
        if self.supplied.bytes > options.4 || self.supplied.nodes > options.6 {
            return Err(Error::AttributesTooLarge);
        }
        Ok(charge)
    }
    fn push(&mut self, number: u64, item: Item<'b>) -> Res<()> {
        match self.fields.entry(number) {
            Entry::Vacant(entry) => {
                entry.insert(Values::Many(vec![item]));
            }
            Entry::Occupied(mut entry) => {
                let Values::Many(items) = entry.get_mut() else {
                    return Err(Error::InvalidProtobuf);
                };
                items.push(item);
            }
        }
        Ok(())
    }
    fn materialize<'a>(&self, env: Env<'a>) -> Res<Term<'a>> {
        let mut keys = Vec::with_capacity(self.fields.len());
        let mut values = Vec::with_capacity(self.fields.len());
        for (&number, items) in &self.fields {
            let (name, kind, _) = field(self.schema, number).ok_or(Error::InvalidProtobuf)?;
            keys.push(binary(env, name.as_bytes()));
            values.push(match items {
                Values::Single(item) => item.materialize(env, kind)?,
                Values::Many(items) => items
                    .iter()
                    .map(|item| item.materialize(env, kind))
                    .collect::<Res<Vec<_>>>()?
                    .encode(env),
            });
        }
        Term::map_from_term_arrays(env, &keys, &values).map_err(|_| Error::InvalidProtobuf)
    }
}
impl Item<'_> {
    fn materialize<'a>(&self, env: Env<'a>, kind: Kind) -> Res<Term<'a>> {
        Ok(match self {
            Item::Message(plan) => plan.materialize(env)?,
            Item::Scalar(Value::Data(bytes)) => match kind {
                Kind::Hex => binary(env, &super::hex(bytes)),
                Kind::Bytes => binary(env, &base64(bytes)),
                Kind::String => binary(env, bytes),
                _ => return Err(Error::InvalidProtobuf),
            },
            Item::Scalar(Value::Number(n)) => match kind {
                Kind::Int | Kind::Signed64 => (*n as i64).encode(env),
                Kind::Sint32 => {
                    let n = *n as u32;
                    (((n >> 1) as i32) ^ -((n & 1) as i32)).encode(env)
                }
                Kind::Bool => (*n != 0).encode(env),
                Kind::Double | Kind::PackedDouble => packed_number(env, Kind::PackedDouble, *n),
                _ => n.encode(env),
            },
        })
    }
}
pub(super) fn decode<'a>(
    env: Env<'a>,
    input: &[u8],
    schema: Schema,
    options: Options,
) -> Res<Term<'a>> {
    let mut plan = Plan::new(schema);
    plan.merge(input, options)?;
    plan.materialize(env)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn bytes(number: u8, value: &[u8]) -> Vec<u8> {
        assert!(value.len() < 128);
        [vec![number * 8 + 2, value.len() as u8], value.to_vec()].concat()
    }
    fn options() -> Options {
        Options(100, 128, 256, 16384, 65536, 16, 1024, 262144)
    }
    fn pair(key: &[u8], values: &[&[u8]]) -> Vec<u8> {
        let mut result = bytes(1, key);
        for value in values {
            result.extend(bytes(2, &bytes(1, value)));
        }
        bytes(1, &result)
    }
    #[test]
    fn cumulative_owner_limits_survive_fragment_boundaries() {
        let first = pair(b"a", &[b"12345"]);
        let second = pair(b"b", &[b"12345"]);
        for o in [
            Options(100, 1, 256, 16384, 65536, 16, 1024, 262144),
            Options(100, 128, 256, 16384, 7, 16, 1024, 262144),
            Options(100, 128, 256, 16384, 65536, 16, 3, 262144),
        ] {
            let mut plan = Plan::new(Schema::Resource);
            assert!(plan.merge(&first, o).is_ok());
            assert!(matches!(
                plan.merge(&second, o),
                Err(Error::AttributesTooLarge)
            ));
        }
    }
    #[test]
    fn replaced_oneofs_do_not_refund_supplied_owner_bytes() {
        let first = pair(b"a", &[b"12345678901234567890", b"12345678901234567890"]);
        let second = pair(b"b", &[b"12345678901234567890", b"12345678901234567890"]);
        let mut o = options();
        o.4 = 70;
        let mut plan = Plan::new(Schema::Resource);
        assert!(plan.merge(&first, o).is_ok());
        assert_eq!(plan.supplied.bytes, 41);
        assert!(matches!(
            plan.merge(&second, o),
            Err(Error::AttributesTooLarge)
        ));
    }
    #[test]
    fn same_oneof_message_merges_but_switching_away_and_back_does_not_resurrect_it() {
        let old = bytes(5, &bytes(1, &bytes(1, b"old")));
        let switched = bytes(1, b"string");
        let new = bytes(5, &bytes(1, &bytes(1, b"new")));
        let appended = bytes(5, &bytes(1, &bytes(1, b"last")));
        let mut plan = Plan::new(Schema::Any);
        for fragment in [&old, &switched, &new, &appended] {
            assert!(plan.merge(fragment, options()).is_ok());
        }
        assert_eq!(plan.fields.len(), 1);
        let Some(Values::Single(Item::Message(array))) = plan.fields.get(&5) else {
            panic!("array expected")
        };
        let Some(Values::Many(values)) = array.fields.get(&1) else {
            panic!("elements expected")
        };
        assert_eq!(values.len(), 2);
        assert_eq!(plan.supplied.bytes, 3 + 6 + 3 + 4);
    }
}
