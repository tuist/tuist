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
        /// The publishing client's git branch, carried so a replicated
        /// action-cache entry keeps its tag. Without it every entry arrived at
        /// the peer untagged, and untagged entries sit in the trunk baseline —
        /// so a feature entry re-polluted the very view the tag exists to
        /// scope. Additive: an old peer's message decodes to `None` (today's
        /// behavior), and an old peer drops the field it does not know.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        branch: Option<String>,
        /// The publishing client's trunk, carried so the receiving node can
        /// re-run the trunk-sticky rule against its own view of the key.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        trunk: Option<String>,
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
mod tests {
    use crate::artifact::producer::ArtifactProducer;

    use super::ReplicationOperation;

    /// The outbox is JSON on disk and the peer protocol is derived from it, so
    /// both directions of a one-version skew must decode: an old node's message
    /// (no branch/trunk) yields `None` — the untagged trunk-baseline entry
    /// today's fleet already produces — and an old node reading a new message
    /// ignores the fields it does not know rather than failing the drain.
    #[test]
    fn upsert_artifact_branch_is_additive_across_a_version_skew() {
        let old_format = r#"{
            "type": "upsert_artifact",
            "producer": "reapi",
            "namespace_id": "ios",
            "key": "action_cache/aa/10",
            "content_type": "application/x-protobuf",
            "artifact_id": "artifact-id",
            "inline": true,
            "version_ms": 123
        }"#;
        let decoded: ReplicationOperation =
            serde_json::from_str(old_format).expect("an old peer's message should decode");
        assert!(matches!(
            decoded,
            ReplicationOperation::UpsertArtifact {
                branch: None,
                trunk: None,
                ..
            }
        ));

        let tagged = ReplicationOperation::UpsertArtifact {
            producer: ArtifactProducer::Reapi,
            namespace_id: "ios".into(),
            key: "action_cache/aa/10".into(),
            content_type: "application/x-protobuf".into(),
            artifact_id: "artifact-id".into(),
            inline: true,
            version_ms: 123,
            branch: Some("main".into()),
            trunk: Some("main".into()),
        };
        let encoded = serde_json::to_string(&tagged).expect("message should encode");
        assert_eq!(
            serde_json::from_str::<ReplicationOperation>(&encoded).expect("round trip should hold"),
            tagged
        );
        // An untagged publish keeps the fields off the wire entirely, so what
        // an old node receives is byte-identical to what it sends today.
        let untagged = ReplicationOperation::UpsertArtifact {
            producer: ArtifactProducer::Reapi,
            namespace_id: "ios".into(),
            key: "action_cache/aa/10".into(),
            content_type: "application/x-protobuf".into(),
            artifact_id: "artifact-id".into(),
            inline: true,
            version_ms: 123,
            branch: None,
            trunk: None,
        };
        let encoded = serde_json::to_string(&untagged).expect("message should encode");
        assert!(
            !encoded.contains("branch"),
            "absent fields stay off the wire"
        );
        assert!(!encoded.contains("trunk"));
    }

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
                branch: None,
                trunk: None,
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
