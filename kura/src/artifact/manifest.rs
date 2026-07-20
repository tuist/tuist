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
mod tests;
