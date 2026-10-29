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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
    /// The region whose node first accepted this write, stamped at that
    /// write and carried through replication. Additive: a record written by
    /// an older binary has none, and a peer that forwards none leaves it
    /// unknown — which region sync lists from everywhere (design §4.1).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin_region: Option<String>,
    /// Lowercase hex SHA-256 of the artifact's bytes, as DECLARED by the
    /// uploading client and verified at ingest. Never computed by the server
    /// from bytes it already holds, which would certify damage. Carried through
    /// replication unchanged and served as `tuist-checksum-sha256`, so a
    /// downloader can check every hop after the upload. Additive like
    /// `origin_region`: absent on rows from older binaries and undeclared uploads.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_sha256: Option<String>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin_region: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_sha256: Option<String>,
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
            branch: manifest.branch.clone(),
            origin_region: manifest.origin_region.clone(),
            content_sha256: manifest.content_sha256.clone(),
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
            branch: self.branch,
            origin_region: self.origin_region,
            content_sha256: self.content_sha256,
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
            branch: None,
            origin_region: None,
            content_sha256: None,
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
            branch: None,
            origin_region: None,
            content_sha256: Some("ab".repeat(32)),
        };

        let restored = PersistedManifestRecord::from_manifest(&manifest)
            .into_manifest(&manifest.artifact_id)
            .expect("persisted record should restore manifest");

        assert_eq!(restored, manifest);
    }

    // Both rollback directions: a row written before the digest existed reads
    // back without one, and a row carrying one omits nothing an older reader
    // needs (serde ignores the unknown field there).
    #[test]
    fn persisted_record_reads_rows_without_a_content_digest() {
        let row = br#"{"producer":"gradle","namespace_id":"android","key":"artifact","content_type":"application/octet-stream","blob_path":"/tmp/blob","size":64,"version_ms":200,"created_at_ms":150}"#;
        let record: PersistedManifestRecord =
            serde_json::from_slice(row).expect("pre-digest row should decode");
        assert_eq!(record.content_sha256, None);

        let manifest = record
            .into_manifest("artifact")
            .expect("record should restore");
        let encoded = serde_json::to_string(&PersistedManifestRecord::from_manifest(&manifest))
            .expect("record should encode");
        assert!(!encoded.contains("content_sha256"));
    }
}
