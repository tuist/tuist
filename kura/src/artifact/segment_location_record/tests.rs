
use super::SegmentLocationRecord;
use crate::artifact::{manifest::ArtifactManifest, producer::ArtifactProducer};

#[test]
fn round_trips_segment_backed_manifest() {
    let manifest = ArtifactManifest {
        artifact_id: "artifact".into(),
        producer: ArtifactProducer::Gradle,
        namespace_id: "android".into(),
        key: "cache-key".into(),
        content_type: "application/octet-stream".into(),
        inline: false,
        blob_path: None,
        segment_id: Some("segment-1".into()),
        segment_offset: Some(42),
        size: 512,
        version_ms: 5678,
        created_at_ms: 1234,
    };

    let record = SegmentLocationRecord::from_manifest(&manifest)
        .expect("segment-backed manifest should encode");
    let decoded = SegmentLocationRecord::decode(&record.encode(), &manifest.artifact_id)
        .expect("record should decode")
        .expect("record should be present");

    assert_eq!(decoded, manifest);
}

#[test]
fn ignores_non_record_payloads() {
    assert!(
        SegmentLocationRecord::decode(br#"{"artifact_id":"not-a-record"}"#, "artifact")
            .expect("non-record payload should not error")
            .is_none()
    );
}

#[test]
fn rejects_record_with_unsupported_dimensions() {
    let mut bytes = Vec::new();
    bytes.push(2);
    bytes.push(99);
    bytes.extend_from_slice(&42_u64.to_le_bytes());
    bytes.extend_from_slice(&512_u64.to_le_bytes());
    bytes.extend_from_slice(&1234_u64.to_le_bytes());
    bytes.extend_from_slice(&1234_u64.to_le_bytes());
    for value in [
        "android",
        "cache-key",
        "application/octet-stream",
        "segment-1",
    ] {
        bytes.extend_from_slice(&(value.len() as u32).to_le_bytes());
        bytes.extend_from_slice(value.as_bytes());
    }

    let error = SegmentLocationRecord::decode(&bytes, "artifact")
        .expect_err("unsupported producer should fail decoding");
    assert!(
        error.contains("invalid artifact producer code"),
        "unexpected error: {error}"
    );
}
