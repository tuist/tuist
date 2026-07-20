
use crate::artifact::producer::ArtifactProducer;

use super::ReplicationOperation;

#[test]
fn replication_operation_names_match_routes() {
    assert_eq!(
        ReplicationOperation::UpsertArtifact {
            producer: ArtifactProducer::Xcode,
            namespace_id: "ios".into(),
            key: "artifact".into(),
            content_type: "application/octet-stream".into(),
            artifact_id: "artifact-id".into(),
            inline: false,
            version_ms: 123,
        }
        .name(),
        "upsert_artifact"
    );
    assert_eq!(
        ReplicationOperation::DeleteNamespace {
            namespace_id: "ios".into(),
            version_ms: 456,
        }
        .name(),
        "delete_namespace"
    );
}
