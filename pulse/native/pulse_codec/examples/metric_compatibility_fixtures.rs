//! Independent six-column legacy and malformed metadata reader fixtures.
use arrow::array::{ArrayRef, BinaryArray, Float64Array, Int64Array, RecordBatch, StringArray};
use arrow::datatypes::{DataType, Field, Schema};
use parquet::arrow::ArrowWriter;
use std::{fs::File, path::Path, sync::Arc};

fn main() {
    let directory = std::env::args().nth(1).expect("output directory");
    let fields = vec![
        Field::new("series_id", DataType::Int64, false),
        Field::new("timestamp_ns", DataType::Int64, false),
        Field::new("value", DataType::Float64, false),
        Field::new("metric_name", DataType::Utf8, false),
        Field::new("labels_canonical", DataType::Binary, false),
        Field::new("labels_json", DataType::Utf8, false),
    ];
    // An intentionally supplied series ID: labels, not hashes, are identity.
    let columns: Vec<ArrayRef> = vec![
        Arc::new(Int64Array::from(vec![42])),
        Arc::new(Int64Array::from(vec![1_700_000_000_123_456_789])),
        Arc::new(Float64Array::from(vec![-0.0])),
        Arc::new(StringArray::from(vec!["legacy_metric"])),
        Arc::new(BinaryArray::from(vec![
            b"__name__\xfflegacy_metric\xff".as_slice()
        ])),
        Arc::new(StringArray::from(vec![r#"{"__name__":"legacy_metric"}"#])),
    ];
    write(
        Path::new(&directory).join("legacy_metric.parquet"),
        fields.clone(),
        columns.clone(),
    );
    let mut invalid_fields = fields.clone();
    invalid_fields.push(Field::new("otlp", DataType::Int64, true));
    let mut invalid_columns = columns.clone();
    invalid_columns.push(Arc::new(Int64Array::from(vec![1])));
    write(
        Path::new(&directory).join("invalid_otlp_type.parquet"),
        invalid_fields,
        invalid_columns,
    );
    let mut invalid_fields = fields;
    invalid_fields.push(Field::new("otlp", DataType::Utf8, true));
    let mut invalid_columns = columns;
    invalid_columns.push(Arc::new(StringArray::from(vec!["[]"])));
    write(
        Path::new(&directory).join("invalid_otlp_value.parquet"),
        invalid_fields,
        invalid_columns,
    );
}

fn write(path: std::path::PathBuf, fields: Vec<Field>, columns: Vec<ArrayRef>) {
    let batch = RecordBatch::try_new(Arc::new(Schema::new(fields)), columns).unwrap();
    let mut writer =
        ArrowWriter::try_new(File::create(path).unwrap(), batch.schema(), None).unwrap();
    writer.write(&batch).unwrap();
    writer.close().unwrap();
}
