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
mod tests;
