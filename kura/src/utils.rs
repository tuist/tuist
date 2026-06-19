use std::{
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use axum::extract::Request;
use futures_util::StreamExt;
use sha2::{Digest, Sha256};
use tokio::{io::AsyncWriteExt, sync::Notify};
use uuid::Uuid;

use crate::{artifact::producer::ArtifactProducer, bandwidth::BandwidthLimiter, io::IoController};

/// Byte-accounted reservation over the shared tmp-dir budget.
///
/// Bootstrap stages every non-inline artifact it pulls from a peer into the
/// shared tmp dir before appending it to a segment. Multiple peers (and the
/// sequential artifacts within a single peer) stage concurrently, so without a
/// shared accounting the combined in-flight bytes scale with the number of
/// concurrent stagers rather than the budget. This reserves a staging slot
/// sized to the artifact and waits when the budget is full, so peak staged
/// bytes stay bounded by the budget regardless of total account size.
#[derive(Debug)]
pub struct TmpBudget {
    capacity: u64,
    reserved: AtomicU64,
    available: Notify,
}

impl TmpBudget {
    pub fn new(capacity: u64) -> Arc<Self> {
        Arc::new(Self {
            capacity: capacity.max(1),
            reserved: AtomicU64::new(0),
            available: Notify::new(),
        })
    }

    /// Reserve `bytes` against the budget, waiting until the reservation fits.
    ///
    /// A request larger than the whole budget is clamped to the budget so a
    /// single oversized artifact can still make progress once the dir drains
    /// (the hard per-body byte ceiling is still enforced while streaming).
    pub async fn reserve(self: &Arc<Self>, bytes: u64) -> TmpReservation {
        let bytes = bytes.clamp(1, self.capacity);
        loop {
            let notified = self.available.notified();
            tokio::pin!(notified);
            // Register before checking capacity: notify_waiters() only wakes
            // already-registered waiters and stores no permit, so without this
            // a release racing the check below would be a lost wakeup.
            notified.as_mut().enable();
            let mut current = self.reserved.load(Ordering::Acquire);
            loop {
                if current.saturating_add(bytes) > self.capacity {
                    break;
                }
                match self.reserved.compare_exchange_weak(
                    current,
                    current + bytes,
                    Ordering::AcqRel,
                    Ordering::Acquire,
                ) {
                    Ok(_) => {
                        return TmpReservation {
                            budget: self.clone(),
                            bytes,
                        };
                    }
                    Err(observed) => current = observed,
                }
            }
            notified.await;
        }
    }

    fn release(&self, bytes: u64) {
        self.reserved.fetch_sub(bytes, Ordering::AcqRel);
        self.available.notify_waiters();
    }
}

/// RAII guard that releases its tmp-budget reservation on drop.
#[derive(Debug)]
pub struct TmpReservation {
    budget: Arc<TmpBudget>,
    bytes: u64,
}

impl Drop for TmpReservation {
    fn drop(&mut self) {
        self.budget.release(self.bytes);
    }
}

#[derive(Debug)]
pub struct TempBodyFile {
    pub path: PathBuf,
    pub size: u64,
}

#[derive(Debug, PartialEq, Eq)]
pub enum BodyReadError {
    TooLarge,
    TmpDirFull(String),
    Io(String),
}

pub async fn read_request_to_temp(
    request: Request,
    directory: &Path,
    max_bytes: u64,
    tmp_dir: &Path,
    tmp_dir_max_bytes: u64,
    io: &IoController,
    bandwidth_limiter: Option<Arc<BandwidthLimiter>>,
) -> Result<TempBodyFile, BodyReadError> {
    ensure_tmp_dir_capacity(tmp_dir, max_bytes, tmp_dir_max_bytes)
        .await
        .map_err(BodyReadError::TmpDirFull)?;

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
        let chunk = match item {
            Ok(chunk) => chunk,
            Err(error) => {
                drop(file);
                io.remove_file_if_exists(&temp_path).await;
                return Err(BodyReadError::Io(format!(
                    "failed to read request body: {error}"
                )));
            }
        };
        size += chunk.len() as u64;
        if size > max_bytes {
            drop(file);
            io.remove_file_if_exists(&temp_path).await;
            return Err(BodyReadError::TooLarge);
        }
        if let Some(limiter) = bandwidth_limiter.as_ref() {
            limiter.acquire(chunk.len()).await;
        }

        if let Err(error) = file.write_all(&chunk).await {
            drop(file);
            io.remove_file_if_exists(&temp_path).await;
            return Err(BodyReadError::Io(format!(
                "failed to write temp file: {error}"
            )));
        }
    }

    if let Err(error) = file.flush().await {
        drop(file);
        io.remove_file_if_exists(&temp_path).await;
        return Err(BodyReadError::Io(format!(
            "failed to flush temp file: {error}"
        )));
    }

    Ok(TempBodyFile {
        path: temp_path,
        size,
    })
}

pub async fn ensure_tmp_dir_capacity(
    tmp_dir: &Path,
    incoming_bytes: u64,
    max_bytes: u64,
) -> Result<(), String> {
    let tmp_dir = tmp_dir.to_path_buf();
    let current_bytes = tokio::task::spawn_blocking(move || directory_size_bytes(&tmp_dir))
        .await
        .unwrap_or(0);
    let requested_bytes = current_bytes.saturating_add(incoming_bytes);
    if requested_bytes > max_bytes {
        return Err(format!(
            "tmp dir budget exhausted: {current_bytes} bytes staged, {incoming_bytes} bytes requested, {max_bytes} bytes allowed"
        ));
    }
    Ok(())
}

pub fn directory_size_bytes(path: &Path) -> u64 {
    let mut total = 0_u64;
    let mut stack = vec![path.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let entries = match std::fs::read_dir(&dir) {
            Ok(entries) => entries,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            if file_type.is_dir() {
                stack.push(entry.path());
            } else if let Ok(metadata) = entry.metadata() {
                total = total.saturating_add(metadata.len());
            }
        }
    }
    total
}

pub fn temp_file_path(directory: &Path, prefix: &str) -> PathBuf {
    directory.join(format!("{prefix}-{}", Uuid::now_v7()))
}

pub fn artifact_storage_id(
    producer: ArtifactProducer,
    tenant_id: &str,
    namespace_id: &str,
    key: &str,
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(producer.as_str().as_bytes());
    hasher.update([0]);
    hasher.update(tenant_id.as_bytes());
    hasher.update([0]);
    hasher.update(namespace_id.as_bytes());
    hasher.update([0]);
    hasher.update(key.as_bytes());
    hex::encode(hasher.finalize())
}

#[cfg(test)]
pub fn blob_path(data_dir: &Path, artifact_id: &str) -> PathBuf {
    data_dir
        .join("blobs")
        .join(&artifact_id[0..2])
        .join(&artifact_id[2..4])
        .join(artifact_id)
}

pub fn segment_path(data_dir: &Path, segment_id: &str) -> PathBuf {
    data_dir.join("segments").join(format!("{segment_id}.seg"))
}

pub fn namespace_artifact_index_key(namespace_id: &str, artifact_id: &str) -> String {
    format!("{namespace_id}\0{artifact_id}")
}

pub fn segment_artifact_index_key(segment_id: &str, artifact_id: &str) -> String {
    format!("{segment_id}\0{artifact_id}")
}

pub fn segment_artifact_index_prefix(segment_id: &str) -> String {
    format!("{segment_id}\0")
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

pub fn action_cache_key(raw_key: &str) -> String {
    format!("action_cache/{raw_key}")
}

pub fn blob_key(raw_key: &str) -> String {
    format!("blob/{raw_key}")
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
        let a = artifact_storage_id(ArtifactProducer::Xcode, "tenant", "ios", "abc");
        let b = artifact_storage_id(ArtifactProducer::Xcode, "tenant", "ios", "abc");
        let c = artifact_storage_id(ArtifactProducer::Gradle, "tenant", "ios", "abc");

        assert_eq!(a, b);
        assert_ne!(a, c);
    }

    #[test]
    fn artifact_ids_include_producer() {
        let mut hasher = Sha256::new();
        hasher.update(b"xcode");
        hasher.update([0]);
        hasher.update(b"tenant");
        hasher.update([0]);
        hasher.update(b"ios");
        hasher.update([0]);
        hasher.update(b"abc");

        assert_eq!(
            artifact_storage_id(ArtifactProducer::Xcode, "tenant", "ios", "abc"),
            hex::encode(hasher.finalize())
        );
    }

    #[test]
    fn module_keys_include_category_hash_and_name() {
        assert_eq!(
            module_key("builds", "hash-1", "Module.framework"),
            "builds/hash-1/Module.framework"
        );
    }

    #[test]
    fn route_keys_are_scoped() {
        assert_eq!(action_cache_key("cas-1"), "action_cache/cas-1");
        assert_eq!(blob_key("artifact-1"), "blob/artifact-1");
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
        let path = blob_path(Path::new("/data"), "abcdef1234567890abcdef1234567890");

        assert_eq!(
            path,
            PathBuf::from("/data/blobs/ab/cd/abcdef1234567890abcdef1234567890")
        );
    }

    #[test]
    fn segment_paths_are_shared() {
        let path = segment_path(Path::new("/data"), "01962a2d-8f1f");

        assert_eq!(path, PathBuf::from("/data/segments/01962a2d-8f1f.seg"));
    }

    #[test]
    fn segment_artifact_index_keys_include_segment_and_artifact() {
        assert_eq!(
            segment_artifact_index_key("segment-1", "artifact-1"),
            "segment-1\0artifact-1"
        );
        assert_eq!(segment_artifact_index_prefix("segment-1"), "segment-1\0");
    }

    #[tokio::test]
    async fn read_request_to_temp_persists_request_body() {
        let directory = tempdir().expect("failed to create temp dir");
        let io = IoController::new(
            Metrics::new("eu-west".into(), "acme".into()),
            8,
            Duration::from_secs(1),
            vec![directory.path().to_path_buf()],
        )
        .expect("failed to create io controller");
        let request = Request::builder()
            .body(Body::from("hello"))
            .expect("failed to build request");

        let temp = read_request_to_temp(
            request,
            directory.path(),
            10,
            directory.path(),
            10,
            &io,
            None,
        )
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
            vec![directory.path().to_path_buf()],
        )
        .expect("failed to create io controller");
        let request = Request::builder()
            .body(Body::from("hello"))
            .expect("failed to build request");

        let error = read_request_to_temp(
            request,
            directory.path(),
            4,
            directory.path(),
            10,
            &io,
            None,
        )
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

    #[tokio::test]
    async fn read_request_to_temp_rejects_when_tmp_budget_is_exhausted() {
        let directory = tempdir().expect("failed to create temp dir");
        std::fs::write(directory.path().join("staged"), b"hello").expect("failed to seed tmp dir");
        let io = IoController::new(
            Metrics::new("eu-west".into(), "acme".into()),
            8,
            Duration::from_secs(1),
            vec![directory.path().to_path_buf()],
        )
        .expect("failed to create io controller");
        let request = Request::builder()
            .body(Body::from("world"))
            .expect("failed to build request");

        let error =
            read_request_to_temp(request, directory.path(), 5, directory.path(), 9, &io, None)
                .await
                .expect_err("expected body reader to reject exhausted tmp budget");

        assert!(matches!(error, BodyReadError::TmpDirFull(_)));
        assert_eq!(
            std::fs::read_to_string(directory.path().join("staged"))
                .expect("failed to read seeded file"),
            "hello"
        );
    }

    #[tokio::test]
    async fn tmp_budget_caps_concurrent_reservations() {
        let budget = TmpBudget::new(100);
        let first = budget.reserve(60).await;
        let second = budget.reserve(40).await;
        assert_eq!(budget.reserved.load(Ordering::Acquire), 100);

        // A third reservation cannot fit until one of the held ones drops.
        let pending = tokio::spawn({
            let budget = budget.clone();
            async move { budget.reserve(40).await }
        });
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert!(!pending.is_finished(), "reservation should wait for budget");

        drop(first);
        let third = pending.await.expect("pending reservation should resolve");
        assert!(budget.reserved.load(Ordering::Acquire) <= 100);
        drop(second);
        drop(third);
        assert_eq!(budget.reserved.load(Ordering::Acquire), 0);
    }

    #[tokio::test]
    async fn tmp_budget_serializes_total_far_exceeding_capacity() {
        // Stage a total volume far larger than the budget through a tiny budget;
        // every reservation must eventually succeed (peak never exceeds budget),
        // proving bootstrap convergence is independent of total account size.
        let budget = TmpBudget::new(100);
        let mut total = 0_u64;
        for _ in 0..50 {
            let reservation = budget.reserve(80).await;
            assert!(budget.reserved.load(Ordering::Acquire) <= 100);
            total += 80;
            drop(reservation);
        }
        assert_eq!(total, 4000);
        assert_eq!(budget.reserved.load(Ordering::Acquire), 0);
    }

    #[tokio::test]
    async fn tmp_budget_clamps_oversized_request_to_capacity() {
        let budget = TmpBudget::new(100);
        let reservation = budget.reserve(10_000).await;
        assert_eq!(budget.reserved.load(Ordering::Acquire), 100);
        drop(reservation);
        assert_eq!(budget.reserved.load(Ordering::Acquire), 0);
    }
}
