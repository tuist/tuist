// Copyright 2023 Greptime Team
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// Modified by Tuist; see pulse/FORK.md.

//！An extended "array" based on [DictionaryArray].

use datafusion::arrow::datatypes::Field;
use datatypes::arrow::array::{Array, ArrayData, ArrayRef, DictionaryArray, Int64Array};
use datatypes::arrow::datatypes::{DataType, Int64Type};
use snafu::ensure;

use crate::error::{EmptyRangeSnafu, IllegalRangeSnafu, Result};

pub type RangeTuple = (u32, u32);

/// An compound logical "array" type. Represent serval ranges (slices) of one array.
/// It's useful to use case like compute sliding window, or range selector from promql.
///
/// It's build on top of Arrow's [DictionaryArray]. [DictionaryArray] contains two
/// sub-arrays, one for dictionary key and another for dictionary value. Both of them
/// can be arbitrary types, but here the key array is fixed to u32 type.
///
/// ```text
///             │ ┌─────┬─────┬─────┬─────┐
///      Two    │ │ i64 │ i64 │ i64 │ i64 │      Keys
///    Arrays   │ └─────┴─────┴─────┴─────┘     (Fixed to i64)
///      In     │
///   Arrow's   │ ┌────────────────────────────┐
/// Dictionary  │ │                            │ Values
///    Array    │ └────────────────────────────┘(Any Type)
/// ```
///
/// Because the i64 key array is reinterpreted into two u32 for offset and length
/// in [RangeArray] to represent a "range":
///
/// ```text
/// 63            32│31             0
/// ┌───────────────┼───────────────┐
/// │  offset (u32) │  length (u32) │
/// └───────────────┼───────────────┘
/// ```
///
/// Then the [DictionaryArray] can be expanded to several ranges like this:
///
/// ```text
/// Keys
/// ┌───────┬───────┬───────┐      ┌───────┐
/// │ (0,2) │ (1,2) │ (2,2) │ ─┐   │[A,B,C]│ values.slice(0,2)
/// └───────┴───────┴───────┘  │   ├───────┤
///  Values                    ├─► │[B,C,D]│ values.slice(1,2)
/// ┌───┬───┬───┬───┬───┐      │   ├───────┤
/// │ A │ B │ C │ D │ E │     ─┘   │[C,D,E]│ values.slice(2,2)
/// └───┴───┴───┴───┴───┘          └───────┘
/// ```
pub struct RangeArray {
    array: DictionaryArray<Int64Type>,
}

impl RangeArray {
    pub const fn key_type() -> DataType {
        DataType::Int64
    }

    pub fn value_type(&self) -> DataType {
        self.array.value_type()
    }

    pub fn try_new(dict: DictionaryArray<Int64Type>) -> Result<Self> {
        ensure!(dict.keys().null_count() == 0, EmptyRangeSnafu);
        let ranges_iter = dict.keys().values().iter().copied().map(unpack);
        Self::check_ranges(dict.values().len(), ranges_iter)?;

        Ok(Self { array: dict })
    }

    pub fn from_ranges<R>(values: ArrayRef, ranges: R) -> Result<Self>
    where
        R: IntoIterator<Item = RangeTuple> + Clone,
    {
        Self::check_ranges(values.len(), ranges.clone())?;

        unsafe { Ok(Self::from_ranges_unchecked(values, ranges)) }
    }

    /// Construct [RangeArray] from given range without checking its validity.
    ///
    /// # Safety
    ///
    /// Caller should ensure the given range are valid. Otherwise use [`from_ranges`]
    /// instead.
    ///
    /// [`from_ranges`]: crate::range_array::RangeArray#method.from_ranges
    pub unsafe fn from_ranges_unchecked<R>(values: ArrayRef, ranges: R) -> Self
    where
        R: IntoIterator<Item = RangeTuple>,
    {
        let key_array = Int64Array::from_iter(
            ranges
                .into_iter()
                .map(|(offset, length)| pack(offset, length)),
        );

        // Build from ArrayData to bypass the "offset" checker. Because
        // we are not using "keys" as-is.
        // This paragraph is copied from arrow-rs dictionary_array.rs `try_new()`.
        let mut data = ArrayData::builder(DataType::Dictionary(
            Box::new(Self::key_type()),
            Box::new(values.data_type().clone()),
        ))
        .len(key_array.len())
        .add_buffer(key_array.to_data().buffers()[0].clone())
        .add_child_data(values.to_data());
        match key_array.to_data().nulls() {
            Some(buffer) if key_array.to_data().null_count() > 0 => {
                data = data
                    .nulls(Some(buffer.clone()))
                    .null_count(key_array.to_data().null_count());
            }
            _ => data = data.null_count(0),
        }
        let array_data = unsafe { data.build_unchecked() };

        Self {
            array: array_data.into(),
        }
    }

    pub fn len(&self) -> usize {
        self.array.keys().len()
    }

    pub fn is_empty(&self) -> bool {
        self.array.keys().is_empty()
    }

    pub fn get(&self, index: usize) -> Option<ArrayRef> {
        if index >= self.len() {
            return None;
        }

        let compound_key = self.array.keys().value(index);
        let (offset, length) = unpack(compound_key);
        let array = self.array.values().slice(offset as usize, length as usize);

        Some(array)
    }

    pub fn get_offset_length(&self, index: usize) -> Option<(usize, usize)> {
        if index >= self.len() {
            return None;
        }

        let compound_key = self.array.keys().value(index);
        let (offset, length) = unpack(compound_key);

        Some((offset as usize, length as usize))
    }

    /// Return the underlying Arrow's [DictionaryArray]. Notes the dictionary array might be
    /// invalid from Arrow's definition. Be care if try to access this dictionary through
    /// Arrow's API.
    pub fn into_dict(self) -> DictionaryArray<Int64Type> {
        self.array
    }

    fn check_ranges<R>(value_len: usize, ranges: R) -> Result<()>
    where
        R: IntoIterator<Item = RangeTuple>,
    {
        for (offset, length) in ranges.into_iter() {
            ensure!(
                offset as usize + length as usize <= value_len,
                IllegalRangeSnafu {
                    offset,
                    length,
                    len: value_len
                }
            );
        }
        Ok(())
    }

    /// Change the field's datatype to the type after processed by [RangeArray].
    /// Like `Utf8` will become `Dictionary<Int64, Utf8>`.
    pub fn convert_field(field: &Field) -> Field {
        let value_type = Box::new(field.data_type().clone());
        Field::new(
            field.name(),
            Self::convert_data_type(*value_type),
            field.is_nullable(),
        )
    }

    /// Build datatype of wrapped [RangeArray] on given value type.
    pub fn convert_data_type(value_type: DataType) -> DataType {
        DataType::Dictionary(Box::new(Self::key_type()), Box::new(value_type))
    }

    pub fn values(&self) -> &ArrayRef {
        self.array.values()
    }

    pub fn ranges(&self) -> impl Iterator<Item = Option<RangeTuple>> + '_ {
        self.array
            .keys()
            .into_iter()
            .map(|compound| compound.map(unpack))
    }
}

impl std::fmt::Debug for RangeArray {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let ranges = self
            .array
            .keys()
            .iter()
            .map(|compound_key| {
                compound_key.map(|key| {
                    let (offset, length) = unpack(key);
                    offset..(offset + length)
                })
            })
            .collect::<Vec<_>>();
        f.debug_struct("RangeArray")
            .field("base array", self.array.values())
            .field("ranges", &ranges)
            .finish()
    }
}

// util functions

fn pack(offset: u32, length: u32) -> i64 {
    bytemuck::cast::<[u32; 2], i64>([offset, length])
}

pub(crate) fn unpack(compound: i64) -> (u32, u32) {
    let [offset, length] = bytemuck::cast::<i64, [u32; 2]>(compound);
    (offset, length)
}

#[cfg(test)]
mod test {
    use std::fmt::Write;
    use std::sync::Arc;

    use datatypes::arrow::array::UInt64Array;

    use super::*;
    use crate::error::Error;

    fn dict_with_keys(keys: Int64Array) -> DictionaryArray<Int64Type> {
        let values = UInt64Array::from(vec![11, 23, 47, 83]);
        let data = ArrayData::builder(RangeArray::convert_data_type(DataType::UInt64))
            .len(keys.len())
            .add_buffer(keys.to_data().buffers()[0].clone())
            .nulls(keys.nulls().cloned())
            .add_child_data(values.to_data());
        // Packed range keys are not Arrow dictionary offsets. Bypass Arrow's
        // offset validation, as from_ranges_unchecked does, so try_new can
        // validate the ranges and nulls in these deliberately malformed inputs.
        DictionaryArray::from(unsafe { data.build_unchecked() })
    }

    fn expand_format(range_array: &RangeArray) -> String {
        let mut result = String::new();
        for i in 0..range_array.len() {
            writeln!(result, "{:?}", range_array.get(i)).unwrap();
        }
        result
    }

    #[test]
    fn construct_from_ranges() {
        let values_array = Arc::new(UInt64Array::from_iter([1, 2, 3, 4, 5, 6, 7, 8, 9]));
        let ranges = [(0, 2), (0, 5), (1, 1), (3, 3), (8, 1), (9, 0)];

        let range_array = RangeArray::from_ranges(values_array, ranges).unwrap();
        assert_eq!(range_array.len(), 6);

        let expected = String::from(
            "Some(PrimitiveArray<UInt64>\
            \n[\
            \n  1,\
            \n  2,\
            \n])\
            \nSome(PrimitiveArray<UInt64>\
            \n[\
            \n  1,\
            \n  2,\
            \n  3,\
            \n  4,\
            \n  5,\
            \n])\
            \nSome(PrimitiveArray<UInt64>\
            \n[\
            \n  2,\
            \n])\
            \
            \nSome(PrimitiveArray<UInt64>\
            \n[\
            \n  4,\
            \n  5,\
            \n  6,\
            \n])\
            \nSome(PrimitiveArray<UInt64>\
            \n[\
            \n  9,\
            \n])\
            \nSome(PrimitiveArray<UInt64>\
            \n[\
            \n])\
            \n",
        );

        let formatted = expand_format(&range_array);
        assert_eq!(formatted, expected);
    }

    #[test]
    fn illegal_range() {
        for (offset, length) in [(0, 5), (3, 2), (5, 0), (u32::MAX, 1), (1, u32::MAX)] {
            let dict = dict_with_keys(Int64Array::from(vec![
                pack(0, 2),
                pack(offset, length),
                pack(1, 1),
            ]));
            let from_ranges = RangeArray::from_ranges(dict.values().clone(), [(offset, length)]);
            let from_dict = RangeArray::try_new(dict.slice(1, 1));
            for result in [from_ranges, from_dict] {
                match result.unwrap_err() {
                    Error::IllegalRange {
                        offset: actual_offset,
                        length: actual_length,
                        len,
                        ..
                    } => assert_eq!((actual_offset, actual_length, len), (offset, length, 4)),
                    error => {
                        panic!("Expected IllegalRange for ({offset}, {length}), got {error:?}")
                    }
                }
            }
        }
    }

    #[test]
    fn dict_array_round_trip() {
        let values_array = Arc::new(UInt64Array::from_iter([1, 2, 3, 4, 5, 6, 7, 8, 9]));
        let ranges = [(0, 4), (1, 4), (2, 4), (3, 4), (4, 4), (5, 4)];
        let expected = String::from(
            "Some(PrimitiveArray<UInt64>\
            \n[\
            \n  1,\
            \n  2,\
            \n  3,\
            \n  4,\
            \n])\
            \nSome(PrimitiveArray<UInt64>\
            \n[\
            \n  2,\
            \n  3,\
            \n  4,\
            \n  5,\
            \n])\
            \nSome(PrimitiveArray<UInt64>\
            \n[\
            \n  3,\
            \n  4,\
            \n  5,\
            \n  6,\
            \n])\
            \nSome(PrimitiveArray<UInt64>\
            \n[\
            \n  4,\
            \n  5,\
            \n  6,\
            \n  7,\
            \n])\
            \nSome(PrimitiveArray<UInt64>\
            \n[\
            \n  5,\
            \n  6,\
            \n  7,\
            \n  8,\
            \n])\
            \nSome(PrimitiveArray<UInt64>\
            \n[\
            \n  6,\
            \n  7,\
            \n  8,\
            \n  9,\
            \n])\
            \n",
        );

        let range_array = RangeArray::from_ranges(values_array, ranges).unwrap();
        assert_eq!(range_array.len(), 6);
        let formatted = expand_format(&range_array);
        assert_eq!(formatted, expected);

        // this dict array is invalid from Arrow's definition
        let dict_array = range_array.into_dict();
        let rounded_range_array = RangeArray::try_new(dict_array).unwrap();
        let formatted = expand_format(&rounded_range_array);
        assert_eq!(formatted, expected);
    }

    #[test]
    fn dict_array_sliced_keys() {
        let dict = dict_with_keys(Int64Array::from(vec![
            Some(pack(5, 0)),
            None,
            Some(pack(1, 2)),
            Some(pack(3, 1)),
            Some(pack(4, 0)),
            Some(pack(3, 2)),
            None,
        ]));
        // Invalid and null keys outside the logical slice must not be checked.
        let range_array = RangeArray::try_new(dict.slice(2, 3)).unwrap();
        assert_eq!(range_array.len(), 3);
        for (index, expected) in [vec![23, 47], vec![83], vec![]].into_iter().enumerate() {
            let values = range_array.get(index).unwrap();
            assert_eq!(
                values.as_any().downcast_ref::<UInt64Array>().unwrap(),
                &UInt64Array::from(expected)
            );
        }
        assert!(range_array.get(3).is_none());
    }

    #[test]
    fn dict_array_null_keys() {
        let dict = dict_with_keys(Int64Array::from(vec![
            Some(pack(1, 2)),
            None,
            Some(pack(0, 1)),
        ]));
        for dict in [dict.clone(), dict.slice(1, 1)] {
            assert!(matches!(
                RangeArray::try_new(dict),
                Err(Error::EmptyRange { .. })
            ));
        }
    }

    #[test]
    fn empty_range_array() {
        let values_array = Arc::new(UInt64Array::from_iter([1, 2, 3, 4, 5, 6, 7, 8, 9]));
        let ranges = [];
        let range_array = RangeArray::from_ranges(values_array, ranges).unwrap();
        assert!(range_array.is_empty());
    }
}
