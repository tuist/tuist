//! Optional footer-only exclusion. Missing bytes are errors, never zero-filled.
use bytes::Bytes;
use parquet::arrow::arrow_reader::{ArrowReaderMetadata, ArrowReaderOptions};
use parquet::errors::{ParquetError, Result};
use parquet::file::reader::{ChunkReader, Length};
use std::io::Cursor;

use crate::metric_segment_parquet::{self, Filter};

pub const MAX_FOOTER: usize = 1024 * 1024;

pub enum Plan {
    More(usize),
    Scan { rows: u64, empty: bool },
    Unknown,
}

struct Tail {
    bytes: Bytes,
    size: u64,
}
impl Length for Tail {
    fn len(&self) -> u64 {
        self.size
    }
}
impl ChunkReader for Tail {
    type T = Cursor<Bytes>;
    fn get_read(&self, start: u64) -> Result<Self::T> {
        let length = usize::try_from(self.size.checked_sub(start).ok_or_else(missing)?)
            .map_err(|_| missing())?;
        Ok(Cursor::new(self.get_bytes(start, length)?))
    }
    fn get_bytes(&self, start: u64, length: usize) -> Result<Bytes> {
        let base = self
            .size
            .checked_sub(self.bytes.len() as u64)
            .ok_or_else(missing)?;
        let offset =
            usize::try_from(start.checked_sub(base).ok_or_else(missing)?).map_err(|_| missing())?;
        let end = offset.checked_add(length).ok_or_else(missing)?;
        if end > self.bytes.len() {
            return Err(missing());
        }
        Ok(self.bytes.slice(offset..end))
    }
}
fn missing() -> ParquetError {
    ParquetError::General("footer range unavailable".into())
}

pub fn plan(tail: Bytes, size: u64, filter: &Filter<'_>) -> Plan {
    if tail.len() < 8 || tail.len() > MAX_FOOTER || tail.len() as u64 > size || size < 12 {
        return Plan::Unknown;
    }
    if &tail[tail.len() - 4..] != b"PAR1"
        || metric_segment_parquet::compile_regexes(&filter.matchers).is_err()
    {
        return Plan::Unknown;
    }
    let length =
        u32::from_le_bytes(tail[tail.len() - 8..tail.len() - 4].try_into().unwrap()) as usize;
    let Some(required) = length.checked_add(8) else {
        return Plan::Unknown;
    };
    if required > MAX_FOOTER || required as u64 > size - 4 {
        return Plan::Unknown;
    }
    if required > tail.len() {
        return Plan::More(required);
    }
    let source = Tail { bytes: tail, size };
    let Ok(metadata) = ArrowReaderMetadata::load(&source, ArrowReaderOptions::default()) else {
        return Plan::Unknown;
    };
    // Enforce the same core schema checks before a zero-result proof as a scan.
    if metric_segment_parquet::optional_columns(metadata.schema()).is_err() {
        return Plan::Unknown;
    }
    let m = metadata.metadata();
    let Ok(rows) = u64::try_from(m.file_metadata().num_rows()) else {
        return Plan::Unknown;
    };
    let total = m.row_groups().iter().try_fold(0u64, |sum, group| {
        sum.checked_add(u64::try_from(group.num_rows()).ok()?)
    });
    if total != Some(rows) {
        return Plan::Unknown;
    }
    Plan::Scan {
        rows,
        empty: metric_segment_parquet::surviving_row_groups(m, filter).is_empty(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn negative_proofs_validate_optional_columns_before_time_pruning() {
        use arrow::array::{
            ArrayRef, BinaryArray, Float64Array, Int64Array, RecordBatch, StringArray,
        };
        use arrow::datatypes::{DataType, Field, Schema};
        use parquet::arrow::ArrowWriter;
        use std::sync::Arc;
        for optional in [
            None,
            Some("histogram"),
            Some("exemplars"),
            Some("otlp"),
            Some("start_timestamp_ms"),
        ] {
            let mut fields = vec![
                Field::new("series_id", DataType::Int64, false),
                Field::new("timestamp_ns", DataType::Int64, false),
                Field::new("value", DataType::Float64, false),
                Field::new("metric_name", DataType::Utf8, false),
                Field::new("labels_canonical", DataType::Binary, false),
                Field::new("labels_json", DataType::Utf8, false),
            ];
            let mut columns: Vec<ArrayRef> = vec![
                Arc::new(Int64Array::from(vec![1])),
                Arc::new(Int64Array::from(vec![1])),
                Arc::new(Float64Array::from(vec![1.0])),
                Arc::new(StringArray::from(vec!["m"])),
                Arc::new(BinaryArray::from(vec![b"__name__\xffm\xff".as_slice()])),
                Arc::new(StringArray::from(vec!["{}"])),
            ];
            if let Some(name) = optional {
                // Deliberately opposite to the supported optional-column type.
                if name == "otlp" {
                    fields.push(Field::new(name, DataType::Binary, true));
                    columns.push(Arc::new(BinaryArray::from(vec![b"bad".as_slice()])));
                } else {
                    fields.push(Field::new(name, DataType::Utf8, true));
                    columns.push(Arc::new(StringArray::from(vec!["bad"])));
                }
            }
            let schema = Arc::new(Schema::new(fields));
            let batch = RecordBatch::try_new(Arc::clone(&schema), columns).unwrap();
            let mut bytes = Vec::new();
            let mut writer = ArrowWriter::try_new(&mut bytes, schema, None).unwrap();
            writer.write(&batch).unwrap();
            writer.close().unwrap();
            let size = bytes.len() as u64;
            let filter = Filter {
                start: Some(10),
                end: None,
                matchers: vec![],
                max_samples: None,
                exemplars_only: false,
            };
            let result = plan(Bytes::from(bytes), size, &filter);
            if optional.is_none() {
                assert!(matches!(
                    result,
                    Plan::Scan {
                        rows: 1,
                        empty: true
                    }
                ));
            } else {
                assert!(matches!(result, Plan::Unknown));
            }
        }
    }

    #[test]
    fn unavailable_ranges_never_fabricate_bytes() {
        let source = Tail {
            bytes: Bytes::from_static(b"abcdefgh"),
            size: 100,
        };
        assert!(source.get_bytes(0, 1).is_err());
        assert!(source.get_bytes(99, 2).is_err());
        assert_eq!(source.get_bytes(94, 2).unwrap().as_ref(), b"cd");
        let filter = Filter {
            start: None,
            end: None,
            matchers: vec![],
            max_samples: None,
            exemplars_only: false,
        };
        for size in [0, 1, 7, 100] {
            assert!(matches!(plan(Bytes::new(), size, &filter), Plan::Unknown));
        }
        assert!(matches!(
            plan(Bytes::from_static(b"\xff\xff\xff\xffPAR1"), 100, &filter),
            Plan::Unknown
        ));
        assert!(matches!(
            plan(Bytes::from_static(b"\x10\0\0\0PAR1"), 100, &filter),
            Plan::More(24)
        ));
        assert!(matches!(
            plan(Bytes::from_static(b"\x10\0\0\0PAR1"), 12, &filter),
            Plan::Unknown
        ));
    }
}
