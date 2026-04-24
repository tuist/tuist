use serde::{Deserialize, Serialize};

use crate::artifact::{
    metadata::ArtifactMetadata, producer::ArtifactProducer, storage_kind::StorageKind,
};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct ArtifactManifest {
    pub artifact_id: String,
    pub producer: ArtifactProducer,
    pub namespace_id: String,
    pub key: String,
    pub content_type: String,
    #[serde(default)]
    pub inline: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub blob_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub segment_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub segment_offset: Option<u64>,
    pub size: u64,
    pub version_ms: u64,
    pub created_at_ms: u64,
}

impl ArtifactManifest {
    pub fn is_segment_backed(&self) -> bool {
        self.segment_id.is_some()
    }

    pub fn logical_key(&self) -> &str {
        &self.key
    }

    pub fn storage_kind(&self) -> StorageKind {
        if self.inline {
            StorageKind::RocksdbInline
        } else if self.segment_id.is_some() {
            StorageKind::Segment
        } else if self.blob_path.is_some() {
            StorageKind::FilesystemBlob
        } else {
            StorageKind::RocksdbInline
        }
    }

    pub fn metadata(&self, tenant_id: &str) -> ArtifactMetadata {
        ArtifactMetadata {
            tenant_id: tenant_id.to_owned(),
            namespace_id: self.namespace_id.clone(),
            producer: self.producer,
            logical_key: self.logical_key().to_owned(),
            storage_kind: self.storage_kind(),
            content_type: self.content_type.clone(),
            size_bytes: self.size,
            version_ms: self.version_ms,
            created_at_ms: self.created_at_ms,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct PersistedManifestRecord {
    pub producer: ArtifactProducer,
    pub namespace_id: String,
    pub key: String,
    pub content_type: String,
    #[serde(default)]
    pub inline: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub blob_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub segment_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub segment_offset: Option<u64>,
    pub size: u64,
    pub version_ms: u64,
    pub created_at_ms: u64,
}

impl PersistedManifestRecord {
    pub fn from_manifest(manifest: &ArtifactManifest) -> Self {
        Self {
            producer: manifest.producer,
            namespace_id: manifest.namespace_id.clone(),
            key: manifest.key.clone(),
            content_type: manifest.content_type.clone(),
            inline: manifest.inline,
            blob_path: manifest.blob_path.clone(),
            segment_id: manifest.segment_id.clone(),
            segment_offset: manifest.segment_offset,
            size: manifest.size,
            version_ms: manifest.version_ms,
            created_at_ms: manifest.created_at_ms,
        }
    }

    pub fn into_manifest(self, artifact_id: &str) -> Result<ArtifactManifest, String> {
        Ok(ArtifactManifest {
            artifact_id: artifact_id.to_owned(),
            producer: self.producer,
            namespace_id: self.namespace_id,
            key: self.key,
            content_type: self.content_type,
            inline: self.inline,
            blob_path: self.blob_path,
            segment_id: self.segment_id,
            segment_offset: self.segment_offset,
            size: self.size,
            version_ms: self.version_ms,
            created_at_ms: self.created_at_ms,
        })
    }
}

#[cfg(test)]
mod tests {
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
}
