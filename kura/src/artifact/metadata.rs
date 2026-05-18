use super::{producer::ArtifactProducer, storage_kind::StorageKind};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ArtifactMetadata {
    pub tenant_id: String,
    pub namespace_id: String,
    pub producer: ArtifactProducer,
    pub logical_key: String,
    pub storage_kind: StorageKind,
    pub content_type: String,
    pub size_bytes: u64,
    pub version_ms: u64,
    pub created_at_ms: u64,
}
