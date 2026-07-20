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

use crate::{
    artifact::producer::ArtifactProducer,
    bandwidth::BandwidthLimiter,
    io::{IoController, TrackedFile},
    memory::{
        FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES, FileCachePolicy, ForegroundMemoryReservation,
        MemoryController,
    },
};

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

    /// Reserve `bytes` immediately, rejecting the caller when the shared
    /// staging budget has no room. Foreground uploads use this instead of
    /// waiting while they hold a request body and memory admission.
    pub fn try_reserve(self: &Arc<Self>, bytes: u64) -> Result<TmpReservation, String> {
        let bytes = bytes.max(1);
        if bytes > self.capacity {
            return Err(format!(
                "tmp dir budget exhausted: {bytes} bytes requested, {} bytes allowed",
                self.capacity
            ));
        }

        let mut current = self.reserved.load(Ordering::Acquire);
        loop {
            let requested = current.saturating_add(bytes);
            if requested > self.capacity {
                return Err(format!(
                    "tmp dir budget exhausted: {current} bytes reserved, {bytes} bytes requested, {} bytes allowed",
                    self.capacity
                ));
            }
            match self.reserved.compare_exchange_weak(
                current,
                requested,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => {
                    return Ok(TmpReservation {
                        budget: self.clone(),
                        bytes,
                    });
                }
                Err(observed) => current = observed,
            }
        }
    }

    #[cfg(test)]
    fn reserved_bytes(&self) -> u64 {
        self.reserved.load(Ordering::Acquire)
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

pub struct TempBodyFile {
    pub path: PathBuf,
    pub size: u64,
    pub file_cache_policy: FileCachePolicy,
    _cleanup: TempFileCleanup,
    _memory_reservation: ForegroundMemoryReservation,
}

impl TempBodyFile {
    pub async fn remove_and_disarm(&mut self, io: &IoController) {
        self._cleanup.remove_and_disarm(io).await;
    }
}

impl std::fmt::Debug for TempBodyFile {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("TempBodyFile")
            .field("path", &self.path)
            .field("size", &self.size)
            .field("file_cache_policy", &self.file_cache_policy)
            .finish_non_exhaustive()
    }
}

#[derive(Debug)]
pub(crate) struct TempFileCleanup {
    path: Option<PathBuf>,
    reservation: Option<TmpReservation>,
}

impl TempFileCleanup {
    pub(crate) fn new(path: PathBuf, reservation: TmpReservation) -> Self {
        Self {
            path: Some(path),
            reservation: Some(reservation),
        }
    }

    pub(crate) fn new_unreserved(path: PathBuf) -> Self {
        Self {
            path: Some(path),
            reservation: None,
        }
    }

    pub(crate) fn set_reservation(&mut self, reservation: TmpReservation) {
        debug_assert!(self.reservation.is_none());
        self.reservation = Some(reservation);
    }

    pub(crate) fn disarm(&mut self) {
        self.path.take();
        self.reservation.take();
    }

    pub(crate) async fn remove_and_disarm(&mut self, io: &IoController) {
        let Some(path) = self.path.clone() else {
            return;
        };
        match io.remove_file_if_exists_result(&path).await {
            Ok(()) => self.disarm(),
            Err(error) => {
                tracing::warn!(
                    path = %path.display(),
                    "failed to remove temporary file before releasing its disk reservation: {error}"
                );
            }
        }
    }
}

impl Drop for TempFileCleanup {
    fn drop(&mut self) {
        let Some(path) = self.path.take() else {
            return;
        };
        // Keep the disk reservation alive until the unlink has actually run.
        // Releasing it when the task is merely queued would let a cancellation
        // storm admit replacement files before their predecessors leave disk.
        let reservation = self.reservation.take();
        let remove = move || {
            let removed = match std::fs::remove_file(&path) {
                Ok(()) => true,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => true,
                Err(error) => {
                    tracing::warn!(
                        path = %path.display(),
                        "failed to clean up temporary file on drop; retaining its disk reservation until restart: {error}"
                    );
                    false
                }
            };
            if removed {
                drop(reservation);
            } else {
                // Failing closed keeps the configured disk ceiling truthful.
                // Startup clears the staging directory and rebuilds the
                // in-memory ledger, so a stuck reservation is recoverable.
                std::mem::forget(reservation);
            }
        };
        match tokio::runtime::Handle::try_current() {
            Ok(runtime) => {
                runtime.spawn_blocking(remove);
            }
            Err(_) => {
                remove();
            }
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum BodyReadError {
    TooLarge,
    TmpDirFull(String),
    MemoryPressure,
    Io(String),
}

pub struct RequestBodyStaging<'a> {
    pub tmp_budget: &'a Arc<TmpBudget>,
    pub io: &'a IoController,
    pub memory: &'a MemoryController,
    pub bandwidth_limiter: Option<&'a BandwidthLimiter>,
}

pub async fn read_request_to_temp(
    request: Request,
    directory: &Path,
    max_bytes: u64,
    staging: RequestBodyStaging<'_>,
) -> Result<TempBodyFile, BodyReadError> {
    let declared_or_max_bytes = match request
        .headers()
        .get(axum::http::header::CONTENT_LENGTH)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<u64>().ok())
    {
        Some(declared_bytes) if declared_bytes > max_bytes => {
            return Err(BodyReadError::TooLarge);
        }
        Some(declared_bytes) => declared_bytes,
        None => max_bytes,
    };
    let memory_reservation = staging
        .memory
        .reserve_foreground_staging(declared_or_max_bytes)
        .await
        .map_err(|_| BodyReadError::MemoryPressure)?;
    let disk_reservation = staging
        .tmp_budget
        .try_reserve(declared_or_max_bytes)
        .map_err(BodyReadError::TmpDirFull)?;
    let file_cache_policy = memory_reservation.file_cache_policy();

    let temp_path = temp_file_path(directory, "upload");
    if let Some(parent) = temp_path.parent() {
        staging
            .io
            .create_dir_all(parent)
            .await
            .map_err(BodyReadError::Io)?;
    }
    let cleanup = TempFileCleanup::new(temp_path.clone(), disk_reservation);

    let mut file = staging
        .io
        .create_file(&temp_path)
        .await
        .map_err(BodyReadError::Io)?;
    let mut stream = request.into_body().into_data_stream();
    let mut size = 0_u64;
    let mut advised_through = 0_u64;

    while let Some(item) = stream.next().await {
        let chunk = match item {
            Ok(chunk) => chunk,
            Err(error) => {
                drop(file);
                staging.io.remove_file_if_exists(&temp_path).await;
                return Err(BodyReadError::Io(format!(
                    "failed to read request body: {error}"
                )));
            }
        };
        size += chunk.len() as u64;
        if size > max_bytes {
            drop(file);
            staging.io.remove_file_if_exists(&temp_path).await;
            return Err(BodyReadError::TooLarge);
        }
        if let Some(limiter) = staging.bandwidth_limiter {
            limiter.acquire(chunk.len()).await;
        }

        if let Err(error) = file.write_all(&chunk).await {
            drop(file);
            staging.io.remove_file_if_exists(&temp_path).await;
            return Err(BodyReadError::Io(format!(
                "failed to write temp file: {error}"
            )));
        }
        if file_cache_policy.should_drop(
            staging.memory.pressure(),
            staging.memory.transient_reserved_bytes(),
        ) && size.saturating_sub(advised_through) >= FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES
        {
            file = match drop_staging_cache_range(
                file,
                &temp_path,
                advised_through,
                size - advised_through,
                staging.io,
            )
            .await
            {
                Ok(file) => file,
                Err(error) => {
                    staging.io.remove_file_if_exists(&temp_path).await;
                    return Err(BodyReadError::Io(error));
                }
            };
            advised_through = size;
        }
    }

    if let Err(error) = file.flush().await {
        drop(file);
        staging.io.remove_file_if_exists(&temp_path).await;
        return Err(BodyReadError::Io(format!(
            "failed to flush temp file: {error}"
        )));
    }

    Ok(TempBodyFile {
        path: temp_path,
        size,
        file_cache_policy,
        _cleanup: cleanup,
        _memory_reservation: memory_reservation,
    })
}

pub(crate) async fn drop_staging_cache_range(
    file: TrackedFile,
    path: &Path,
    offset: u64,
    length: u64,
    io: &IoController,
) -> Result<TrackedFile, String> {
    let file = io
        .sync_drop_cache_and_reopen_append(file, path, offset, length)
        .await?;
    io.metrics().record_memory_action("staging_file_cache_drop");
    Ok(file)
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

/// Row key in the action-cache index CF. The version is stored bitwise-NOT
/// big-endian so a forward prefix scan yields entries newest-first and can
/// stop at the snapshot's entry cap without sorting. The action hash keeps
/// same-millisecond rows distinct; the row value is the artifact id.
pub fn action_cache_index_key(namespace_id: &str, version_ms: u64, action_hash: &str) -> Vec<u8> {
    let mut key = Vec::with_capacity(namespace_id.len() + 1 + 8 + action_hash.len());
    key.extend_from_slice(namespace_id.as_bytes());
    key.push(0);
    key.extend_from_slice(&(!version_ms).to_be_bytes());
    key.extend_from_slice(action_hash.as_bytes());
    key
}

pub fn action_cache_index_prefix(namespace_id: &str) -> Vec<u8> {
    let mut prefix = Vec::with_capacity(namespace_id.len() + 1);
    prefix.extend_from_slice(namespace_id.as_bytes());
    prefix.push(0);
    prefix
}

/// The action hash of a REAPI action-cache manifest key
/// (`action_cache/{hash}`), `None` for every other artifact.
pub fn action_cache_manifest_hash(key: &str) -> Option<&str> {
    key.strip_prefix("action_cache/")?.split('/').next()
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
        let metrics = Metrics::new("eu-west".into(), "acme".into());
        let io = IoController::new(
            metrics.clone(),
            8,
            Duration::from_secs(1),
            vec![directory.path().to_path_buf()],
        )
        .expect("failed to create io controller");
        let memory = MemoryController::new(metrics, 64 * 1024 * 1024, 128 * 1024 * 1024);
        let tmp_budget = TmpBudget::new(10);
        let request = Request::builder()
            .body(Body::from("hello"))
            .expect("failed to build request");

        let mut temp = read_request_to_temp(
            request,
            directory.path(),
            10,
            RequestBodyStaging {
                tmp_budget: &tmp_budget,
                io: &io,
                memory: &memory,
                bandwidth_limiter: None,
            },
        )
        .await
        .expect("failed to read request to temp");

        assert_eq!(temp.size, 5);
        assert_eq!(
            std::fs::read_to_string(&temp.path).expect("failed to read temp file"),
            "hello"
        );
        assert_eq!(tmp_budget.reserved_bytes(), 10);
        temp.remove_and_disarm(&io).await;
        assert!(!temp.path.exists());
        assert_eq!(tmp_budget.reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn read_request_to_temp_rejects_large_payloads() {
        let directory = tempdir().expect("failed to create temp dir");
        let metrics = Metrics::new("eu-west".into(), "acme".into());
        let io = IoController::new(
            metrics.clone(),
            8,
            Duration::from_secs(1),
            vec![directory.path().to_path_buf()],
        )
        .expect("failed to create io controller");
        let memory = MemoryController::new(metrics, 64 * 1024 * 1024, 128 * 1024 * 1024);
        let tmp_budget = TmpBudget::new(10);
        let request = Request::builder()
            .body(Body::from("hello"))
            .expect("failed to build request");

        let error = read_request_to_temp(
            request,
            directory.path(),
            4,
            RequestBodyStaging {
                tmp_budget: &tmp_budget,
                io: &io,
                memory: &memory,
                bandwidth_limiter: None,
            },
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
    async fn read_request_to_temp_cleans_up_when_cancelled() {
        let directory = tempdir().expect("failed to create temp dir");
        let metrics = Metrics::new("eu-west".into(), "acme".into());
        let io = IoController::new(
            metrics.clone(),
            8,
            Duration::from_secs(1),
            vec![directory.path().to_path_buf()],
        )
        .expect("failed to create io controller");
        let memory = MemoryController::new(metrics, 64 * 1024 * 1024, 128 * 1024 * 1024);
        let tmp_budget = TmpBudget::new(10);
        let body = futures_util::stream::once(async {
            Ok::<_, std::convert::Infallible>(bytes::Bytes::from_static(b"hello"))
        })
        .chain(futures_util::stream::pending());
        let request = Request::builder()
            .body(Body::from_stream(body))
            .expect("failed to build request");

        let result = tokio::time::timeout(
            Duration::from_millis(50),
            read_request_to_temp(
                request,
                directory.path(),
                10,
                RequestBodyStaging {
                    tmp_budget: &tmp_budget,
                    io: &io,
                    memory: &memory,
                    bandwidth_limiter: None,
                },
            ),
        )
        .await;

        assert!(result.is_err(), "the pending body should be cancelled");
        for _ in 0..100 {
            if std::fs::read_dir(directory.path())
                .expect("failed to list temp dir")
                .next()
                .is_none()
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
        assert!(
            std::fs::read_dir(directory.path())
                .expect("failed to list temp dir")
                .next()
                .is_none(),
            "cancellation must not leave a staged file"
        );
        assert_eq!(
            tmp_budget.reserved_bytes(),
            0,
            "disk admission must release after cancellation cleanup"
        );
    }

    #[tokio::test]
    async fn read_request_to_temp_rejects_when_tmp_budget_is_exhausted() {
        let directory = tempdir().expect("failed to create temp dir");
        let metrics = Metrics::new("eu-west".into(), "acme".into());
        let io = IoController::new(
            metrics.clone(),
            8,
            Duration::from_secs(1),
            vec![directory.path().to_path_buf()],
        )
        .expect("failed to create io controller");
        let memory = MemoryController::new(metrics, 64 * 1024 * 1024, 128 * 1024 * 1024);
        let tmp_budget = TmpBudget::new(9);
        let _held = tmp_budget
            .try_reserve(5)
            .expect("failed to seed tmp reservation");
        let request = Request::builder()
            .body(Body::from("world"))
            .expect("failed to build request");

        let error = read_request_to_temp(
            request,
            directory.path(),
            5,
            RequestBodyStaging {
                tmp_budget: &tmp_budget,
                io: &io,
                memory: &memory,
                bandwidth_limiter: None,
            },
        )
        .await
        .expect_err("expected body reader to reject exhausted tmp budget");

        assert!(matches!(error, BodyReadError::TmpDirFull(_)));
        assert_eq!(tmp_budget.reserved_bytes(), 5);
    }

    #[test]
    fn tmp_budget_rejects_concurrent_reservations_over_capacity() {
        let budget = TmpBudget::new(100);
        let first = budget.try_reserve(60).expect("first reservation");

        assert!(budget.try_reserve(41).is_err());
        let second = budget.try_reserve(40).expect("remaining capacity");
        assert_eq!(budget.reserved_bytes(), 100);

        drop(first);
        drop(second);
        assert_eq!(budget.reserved_bytes(), 0);
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
