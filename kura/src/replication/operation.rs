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

    /// Whether delivering this message ships segment-backed artifact bytes.
    /// Bulk messages drain in a lower-priority outbox lane so metadata-sized
    /// operations (inline artifacts such as action-cache entries, namespace
    /// deletes) are not parked behind gigabytes of blob backlog.
    pub fn is_bulk(&self) -> bool {
        matches!(self, Self::UpsertArtifact { inline: false, .. })
    }
}

#[cfg(test)]
mod tests;
