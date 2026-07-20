
use crate::artifact::{producer::ArtifactProducer, storage_kind::StorageKind};

use super::{ArtifactManifest, PersistedManifestRecord};

#[test]
fn exposes_normalized_storage_metadata() {
    let manifest = ArtifactManifest {
        artifact_id: "artifact".into(),
        producer: ArtifactProducer::Xcode,
        namespace_id: "ios".into(),
        key: "action-key".into(),
        content_type: "application/json".into(),
        inline: true,
        blob_path: None,
        segment_id: None,
        segment_offset: None,
        size: 128,
        version_ms: 100,
        created_at_ms: 90,
    };

    let metadata = manifest.metadata("acme");
    assert_eq!(metadata.tenant_id, "acme");
    assert_eq!(metadata.namespace_id, "ios");
    assert_eq!(metadata.producer, ArtifactProducer::Xcode);
    assert_eq!(metadata.logical_key, "action-key");
    assert_eq!(metadata.storage_kind, StorageKind::RocksdbInline);
    assert_eq!(metadata.content_type, "application/json");
    assert_eq!(metadata.size_bytes, 128);
    assert_eq!(metadata.version_ms, 100);
    assert_eq!(metadata.created_at_ms, 90);
}

#[test]
fn persisted_record_round_trips_without_storing_kind() {
    let manifest = ArtifactManifest {
        artifact_id: "artifact".into(),
        producer: ArtifactProducer::Gradle,
        namespace_id: "android".into(),
        key: "artifact".into(),
        content_type: "application/octet-stream".into(),
        inline: false,
        blob_path: Some("/tmp/blob".into()),
        segment_id: None,
        segment_offset: None,
        size: 64,
        version_ms: 200,
        created_at_ms: 150,
    };

    let restored = PersistedManifestRecord::from_manifest(&manifest)
        .into_manifest(&manifest.artifact_id)
        .expect("persisted record should restore manifest");

    assert_eq!(restored, manifest);
}
