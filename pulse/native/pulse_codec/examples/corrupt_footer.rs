//! Regenerate the log decoder's corrupt-footer regression fixture:
//! cargo run --release --manifest-path native/pulse_codec/Cargo.toml \
//!   --example corrupt_footer -- test/fixtures/logs/corrupt_footer.parquet

use arrow::array::{Int64Array, RecordBatch};
use arrow::datatypes::{DataType, Field, Schema};
use bytes::Bytes;
use parquet::arrow::arrow_reader::ParquetRecordBatchReaderBuilder;
use parquet::arrow::ArrowWriter;
use parquet::file::metadata::ParquetMetaDataWriter;
use std::sync::Arc;

fn main() {
    let path = std::env::args().nth(1).expect("output fixture path");
    // Deliberately incomplete log schema. A decoder should reject it, not
    // allocate space for the fake row count before validating any columns.
    let schema = Arc::new(Schema::new(vec![Field::new(
        "timestamp_ns",
        DataType::Int64,
        false,
    )]));
    let batch = RecordBatch::try_new(schema.clone(), vec![Arc::new(Int64Array::from(vec![1]))])
        .expect("valid batch");
    let mut blob = Vec::new();
    let mut writer = ArrowWriter::try_new(&mut blob, schema, None).expect("writer");
    writer.write(&batch).expect("write batch");
    writer.close().expect("close writer");

    let reader = ParquetRecordBatchReaderBuilder::try_new(Bytes::copy_from_slice(&blob))
        .expect("read metadata");
    let metadata = reader.metadata();
    let row_group = metadata
        .row_group(0)
        .clone()
        .into_builder()
        .set_num_rows(1 << 36)
        .build()
        .expect("row group");
    let corrupt = metadata
        .as_ref()
        .clone()
        .into_builder()
        .set_row_groups(vec![row_group])
        .build();
    let footer_len =
        u32::from_le_bytes(blob[blob.len() - 8..blob.len() - 4].try_into().unwrap()) as usize;
    blob.truncate(blob.len() - 8 - footer_len);
    ParquetMetaDataWriter::new(&mut blob, &corrupt)
        .finish()
        .expect("rewrite footer");
    let reader = ParquetRecordBatchReaderBuilder::try_new(Bytes::copy_from_slice(&blob))
        .expect("corrupt count remains readable metadata");
    assert_eq!(reader.metadata().row_group(0).num_rows(), 1 << 36);
    std::fs::write(path, blob).expect("write fixture");
}
