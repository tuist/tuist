use std::{
    path::{Path, PathBuf},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use axum::extract::Request;
use futures_util::StreamExt;
use sha2::{Digest, Sha256};
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

use crate::{artifact::kind::ArtifactKind, io::IoController};

#[derive(Debug)]
pub struct TempBodyFile {
    pub path: PathBuf,
    pub size: u64,
}

#[derive(Debug, PartialEq, Eq)]
pub enum BodyReadError {
    TooLarge,
    Io(String),
}

pub async fn read_request_to_temp(
    request: Request,
    directory: &Path,
    max_bytes: u64,
    io: &IoController,
) -> Result<TempBodyFile, BodyReadError> {
    let temp_path = temp_file_path(directory, "upload");
    if let Some(parent) = temp_path.parent() {
        io.create_dir_all(parent).await.map_err(BodyReadError::Io)?;
    }

    let mut file = io
        .create_file(&temp_path)
        .await
        .map_err(BodyReadError::Io)?;
    let mut stream = request.into_body().into_data_stream();
    let mut size = 0_u64;

    while let Some(item) = stream.next().await {
        let chunk = item
            .map_err(|error| BodyReadError::Io(format!("failed to read request body: {error}")))?;
        size += chunk.len() as u64;
        if size > max_bytes {
            io.remove_file_if_exists(&temp_path).await;
            return Err(BodyReadError::TooLarge);
        }

        file.write_all(&chunk)
            .await
            .map_err(|error| BodyReadError::Io(format!("failed to write temp file: {error}")))?;
    }

    file.flush()
        .await
        .map_err(|error| BodyReadError::Io(format!("failed to flush temp file: {error}")))?;

    Ok(TempBodyFile {
        path: temp_path,
        size,
    })
}

pub fn temp_file_path(directory: &Path, prefix: &str) -> PathBuf {
    directory.join(format!("{prefix}-{}", Uuid::now_v7()))
}

pub fn artifact_storage_id(
    kind: ArtifactKind,
    tenant_id: &str,
    namespace_id: &str,
    key: &str,
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(kind.as_str().as_bytes());
    hasher.update([0]);
    hasher.update(tenant_id.as_bytes());
    hasher.update([0]);
    hasher.update(namespace_id.as_bytes());
    hasher.update([0]);
    hasher.update(key.as_bytes());
    hex::encode(hasher.finalize())
}

pub fn blob_path(data_dir: &Path, kind: ArtifactKind, artifact_id: &str) -> PathBuf {
    data_dir
        .join("blobs")
        .join(kind.as_str())
        .join(&artifact_id[0..2])
        .join(&artifact_id[2..4])
        .join(artifact_id)
}

pub fn segment_path(data_dir: &Path, kind: ArtifactKind, segment_id: &str) -> PathBuf {
    data_dir
        .join("segments")
        .join(kind.as_str())
        .join(format!("{segment_id}.seg"))
}

pub fn namespace_artifact_index_key(namespace_id: &str, artifact_id: &str) -> String {
    format!("{namespace_id}\0{artifact_id}")
}

pub fn segment_artifact_index_key(
    kind: ArtifactKind,
    segment_id: &str,
    artifact_id: &str,
) -> String {
    format!("{}\0{segment_id}\0{artifact_id}", kind.as_str())
}

pub fn segment_artifact_index_prefix(kind: ArtifactKind, segment_id: &str) -> String {
    format!("{}\0{segment_id}\0", kind.as_str())
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0))
        .as_millis() as u64
}

pub fn module_key(category: &str, hash: &str, name: &str) -> String {
    format!("{category}/{hash}/{name}")
}

pub fn url_encode(value: &str) -> String {
    value
        .bytes()
        .flat_map(|byte| match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                vec![byte as char]
            }
            other => format!("%{:02X}", other).chars().collect(),
        })
        .collect()
}

pub fn replication_target_label(value: &str) -> String {
    value
        .trim_start_matches("http://")
        .trim_start_matches("https://")
        .split('/')
        .next()
        .unwrap_or(value)
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::metrics::Metrics;
    use axum::body::Body;
    use tempfile::tempdir;

    #[test]
    fn artifact_ids_are_stable() {
        let a = artifact_storage_id(ArtifactKind::Xcode, "tenant", "ios", "abc");
        let b = artifact_storage_id(ArtifactKind::Xcode, "tenant", "ios", "abc");
        let c = artifact_storage_id(ArtifactKind::Gradle, "tenant", "ios", "abc");

        assert_eq!(a, b);
        assert_ne!(a, c);
    }

    #[test]
    fn module_keys_include_category_hash_and_name() {
        assert_eq!(
            module_key("builds", "hash-1", "Module.framework"),
            "builds/hash-1/Module.framework"
        );
    }

    #[test]
    fn url_encoding_is_query_safe() {
        assert_eq!(
            url_encode("builds/hash 1/Module.framework"),
            "builds%2Fhash%201%2FModule.framework"
        );
    }

    #[test]
    fn replication_labels_strip_scheme_and_path() {
        assert_eq!(
            replication_target_label("https://kura.example.com/_internal/status"),
            "kura.example.com"
        );
    }

    #[test]
    fn blob_paths_are_partitioned_by_hash_prefix() {
        let path = blob_path(
            Path::new("/data"),
            ArtifactKind::Module,
            "abcdef1234567890abcdef1234567890",
        );

        assert_eq!(
            path,
            PathBuf::from("/data/blobs/module/ab/cd/abcdef1234567890abcdef1234567890")
        );
    }

    #[test]
    fn segment_paths_are_partitioned_by_kind() {
        let path = segment_path(Path::new("/data"), ArtifactKind::Gradle, "01962a2d-8f1f");

        assert_eq!(
            path,
            PathBuf::from("/data/segments/gradle/01962a2d-8f1f.seg")
        );
    }

    #[test]
    fn segment_artifact_index_keys_include_kind_segment_and_artifact() {
        assert_eq!(
            segment_artifact_index_key(ArtifactKind::Module, "segment-1", "artifact-1"),
            "module\0segment-1\0artifact-1"
        );
        assert_eq!(
            segment_artifact_index_prefix(ArtifactKind::Module, "segment-1"),
            "module\0segment-1\0"
        );
    }

    #[tokio::test]
    async fn read_request_to_temp_persists_request_body() {
        let directory = tempdir().expect("failed to create temp dir");
        let io = IoController::new(
            Metrics::new("eu-west".into(), "acme".into()),
            8,
            Duration::from_secs(1),
        );
        let request = Request::builder()
            .body(Body::from("hello"))
            .expect("failed to build request");

        let temp = read_request_to_temp(request, directory.path(), 10, &io)
            .await
            .expect("failed to read request to temp");

        assert_eq!(temp.size, 5);
        assert_eq!(
            std::fs::read_to_string(temp.path).expect("failed to read temp file"),
            "hello"
        );
    }

    #[tokio::test]
    async fn read_request_to_temp_rejects_large_payloads() {
        let directory = tempdir().expect("failed to create temp dir");
        let io = IoController::new(
            Metrics::new("eu-west".into(), "acme".into()),
            8,
            Duration::from_secs(1),
        );
        let request = Request::builder()
            .body(Body::from("hello"))
            .expect("failed to build request");

        let error = read_request_to_temp(request, directory.path(), 4, &io)
            .await
            .expect_err("expected body reader to reject oversized request");

        assert_eq!(error, BodyReadError::TooLarge);
        assert!(
            std::fs::read_dir(directory.path())
                .expect("failed to list temp dir")
                .next()
                .is_none()
        );
    }
}
