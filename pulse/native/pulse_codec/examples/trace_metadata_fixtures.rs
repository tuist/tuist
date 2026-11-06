//! Independent Arrow fixtures, not emitted by Pulse's trace encoder.
use arrow::array::{ArrayRef, Int64Array, RecordBatch, StringArray};
use arrow::datatypes::{DataType, Field, Schema};
use parquet::arrow::ArrowWriter;
use std::sync::Arc;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let directory = std::env::args().nth(1).ok_or("output directory required")?;
    std::fs::create_dir_all(&directory)?;
    let legacy = r#"{"timestamp_ns":42,"end_timestamp_ns":43,"trace_id":"11111111111111111111111111111111","span_id":"2222222222222222","parent_span_id":null,"trace_state":"","flags":0,"name":"legacy","kind":0,"service":"fixture","status":{"code":0,"message":""},"attributes":{"blob":"AP8="},"resource":{},"scope":{},"events":[],"links":[],"dropped_attributes_count":0,"dropped_events_count":0,"dropped_links_count":0,"resource_dropped_attributes_count":0,"resource_schema_url":"","scope_schema_url":""}"#;
    for (name, metadata) in [
        ("legacy", None),
        ("invalid-type", Some("[]")),
        (
            "invalid-version",
            Some(
                r#"{"version":2,"resource":[],"scope":[],"attributes":[],"events":[],"links":[]}"#,
            ),
        ),
        (
            "invalid-value",
            Some(
                r#"{"version":1,"resource":[],"scope":[],"attributes":[{"key":"blob","value":{"bytesValue":"AR=="}}],"events":[],"links":[]}"#,
            ),
        ),
    ] {
        let payload = metadata.map_or_else(
            || legacy.to_owned(),
            |value| format!("{},\"otlp\":{value}}}", &legacy[..legacy.len() - 1]),
        );
        let fields = ["timestamp_ns", "end_timestamp_ns", "kind", "status_code"]
            .into_iter()
            .map(|name| Field::new(name, DataType::Int64, false))
            .chain(
                ["service", "trace_id", "span_id", "name", "payload"]
                    .into_iter()
                    .map(|name| Field::new(name, DataType::Utf8, name == "service")),
            )
            .collect::<Vec<_>>();
        let schema = Arc::new(Schema::new(fields));
        let mut columns: Vec<ArrayRef> = [42, 43, 0, 0]
            .into_iter()
            .map(|value| Arc::new(Int64Array::from(vec![value])) as ArrayRef)
            .collect();
        for value in [
            "fixture",
            "11111111111111111111111111111111",
            "2222222222222222",
            "legacy",
            &payload,
        ] {
            columns.push(Arc::new(StringArray::from(vec![value])));
        }
        let batch = RecordBatch::try_new(schema.clone(), columns)?;
        let file = std::fs::File::create(format!("{directory}/trace-{name}.parquet"))?;
        let mut writer = ArrowWriter::try_new(file, schema, None)?;
        writer.write(&batch)?;
        writer.close()?;
    }
    Ok(())
}
