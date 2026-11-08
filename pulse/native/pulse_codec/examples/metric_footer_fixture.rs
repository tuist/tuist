//! Optional first-party large-footer fixture producer. No external service/toolchain.
use arrow::array::{ArrayRef, BinaryArray, Float64Array, Int64Array, StringArray};
use arrow::datatypes::{DataType, Field, Schema};
use arrow::record_batch::RecordBatch;
use parquet::arrow::ArrowWriter;
use parquet::file::properties::WriterProperties;
use parquet::format::KeyValue;
use std::sync::Arc;

fn main() {
    let output = std::env::args().nth(1).expect("output path");
    let schema = Arc::new(Schema::new(vec![
        Field::new("series_id", DataType::Int64, false),
        Field::new("timestamp_ns", DataType::Int64, false),
        Field::new("value", DataType::Float64, false),
        Field::new("metric_name", DataType::Utf8, false),
        Field::new("labels_canonical", DataType::Binary, false),
        Field::new("labels_json", DataType::Utf8, false),
    ]));
    let canonical = b"__name__\xffm\xffhost\xffa\xff";
    let columns: Vec<ArrayRef> = vec![
        Arc::new(Int64Array::from(vec![7, 7])),
        Arc::new(Int64Array::from(vec![1, 2])),
        Arc::new(Float64Array::from(vec![1.0, 2.0])),
        Arc::new(StringArray::from(vec!["m", "m"])),
        Arc::new(BinaryArray::from(vec![
            canonical.as_slice(),
            canonical.as_slice(),
        ])),
        Arc::new(StringArray::from(vec![r#"{"__name__":"m","host":"a"}"#; 2])),
    ];
    let props = WriterProperties::builder()
        .set_max_row_group_size(1)
        .set_key_value_metadata(Some(vec![KeyValue::new(
            "padding".into(),
            "p".repeat(70_000),
        )]))
        .build();
    let mut bytes = Vec::new();
    let mut writer = ArrowWriter::try_new(&mut bytes, schema.clone(), Some(props)).unwrap();
    writer
        .write(&RecordBatch::try_new(schema, columns).unwrap())
        .unwrap();
    writer.close().unwrap();
    std::fs::write(output, bytes).unwrap();
}
