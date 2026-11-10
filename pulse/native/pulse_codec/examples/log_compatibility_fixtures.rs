//! Generate checked-in log reader compatibility fixtures without the NIF.
//! cargo run --example log_compatibility_fixtures -- test/fixtures/logs
use arrow::array::{ArrayRef, Int32Array, Int64Array, RecordBatch, StringArray};
use arrow::datatypes::{DataType, Field, Schema};
use parquet::arrow::ArrowWriter;
use parquet::basic::{Compression, ZstdLevel};
use parquet::file::properties::{EnabledStatistics, WriterProperties};
use std::{fs::File, path::Path, sync::Arc};

fn main() {
    let directory = std::env::args().nth(1).expect("output directory");
    let fields = vec![
        Field::new("timestamp_ns", DataType::Int64, true),
        Field::new("observed_timestamp_ns", DataType::Int64, true),
        Field::new("severity_number", DataType::Int32, true),
        Field::new("severity_text", DataType::Utf8, true),
        Field::new("service", DataType::Utf8, true),
        Field::new("body", DataType::Utf8, true),
        Field::new("trace_id", DataType::Utf8, true),
        Field::new("span_id", DataType::Utf8, true),
        Field::new("attributes", DataType::Utf8, false),
        Field::new("resource", DataType::Utf8, false),
    ];
    let columns: Vec<ArrayRef> = vec![
        Arc::new(Int64Array::from(vec![1_700_000_000_123_456_789])),
        Arc::new(Int64Array::from(vec![1_700_000_000_123_456_790])),
        Arc::new(Int32Array::from(vec![9])),
        Arc::new(StringArray::from(vec!["INFO"])),
        Arc::new(StringArray::from(vec!["legacy-api"])),
        Arc::new(StringArray::from(vec![r#""legacy log""#])),
        Arc::new(StringArray::from(vec![None::<&str>])),
        Arc::new(StringArray::from(vec![None::<&str>])),
        Arc::new(StringArray::from(vec![r#"{"request":"old"}"#])),
        Arc::new(StringArray::from(vec![r#"{"service.name":"legacy-api"}"#])),
    ];
    write(
        Path::new(&directory).join("legacy_log.parquet"),
        fields.clone(),
        columns.clone(),
    );
    write_amplified(
        Path::new(&directory).join("legacy_expanded_log.parquet"),
        fields.clone(),
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
// Historical ten-column data can expand beyond today's normalized write cap.
// Keep it tiny on disk while retaining 96 MB of repeated JSON body bytes.
fn write_amplified(path: std::path::PathBuf, fields: Vec<Field>) {
    let rows = 32;
    let body = format!("\"{}\"", "\\u0000".repeat(500_000));
    let columns: Vec<ArrayRef> = vec![
        Arc::new(Int64Array::from(vec![1; rows])),
        Arc::new(Int64Array::from(vec![None::<i64>; rows])),
        Arc::new(Int32Array::from(vec![None::<i32>; rows])),
        Arc::new(StringArray::from(vec![None::<&str>; rows])),
        Arc::new(StringArray::from(vec!["api"; rows])),
        Arc::new(StringArray::from(vec![body.as_str(); rows])),
        Arc::new(StringArray::from(vec![None::<&str>; rows])),
        Arc::new(StringArray::from(vec![None::<&str>; rows])),
        Arc::new(StringArray::from(vec!["{}"; rows])),
        Arc::new(StringArray::from(vec!["{}"; rows])),
    ];
    let batch = RecordBatch::try_new(Arc::new(Schema::new(fields)), columns).unwrap();
    let props = WriterProperties::builder()
        .set_dictionary_enabled(true)
        .set_dictionary_page_size_limit(4_194_304)
        .set_compression(Compression::ZSTD(ZstdLevel::try_new(3).unwrap()))
        .set_statistics_enabled(EnabledStatistics::None)
        .build();
    let mut writer =
        ArrowWriter::try_new(File::create(path).unwrap(), batch.schema(), Some(props)).unwrap();
    writer.write(&batch).unwrap();
    writer.close().unwrap();
}

fn write(path: std::path::PathBuf, fields: Vec<Field>, columns: Vec<ArrayRef>) {
    let batch = RecordBatch::try_new(Arc::new(Schema::new(fields)), columns).unwrap();
    let mut writer =
        ArrowWriter::try_new(File::create(path).unwrap(), batch.schema(), None).unwrap();
    writer.write(&batch).unwrap();
    writer.close().unwrap();
}
