use serde::{Deserialize, Serialize};

use crate::artifact::producer::ArtifactProducer;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ReplicationOperation {
    UpsertArtifact {
        producer: ArtifactProducer,
        namespace_id: String,
        key: String,
        content_type: String,
        artifact_id: String,
        #[serde(default)]
        inline: bool,
        #[serde(default)]
        version_ms: u64,
    },
    DeleteNamespace {
        namespace_id: String,
        #[serde(default)]
        version_ms: u64,
    },
}

impl ReplicationOperation {
    pub fn name(&self) -> &'static str {
        match self {
            Self::UpsertArtifact { .. } => "upsert_artifact",
            Self::DeleteNamespace { .. } => "delete_namespace",
        }
    }
}

#[cfg(test)]
mod tests {
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
}
