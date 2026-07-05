//! Remote transport over the Bazel Remote Execution API (REAPI), spoken by
//! kura's gRPC service.
//!
//! Mapping (Bazel-shaped, digest-function friction avoided entirely):
//! - An llcas action key K maps to the REAPI ActionCache key
//!   `Digest { hash: sha256(K), size: len(K) }`.
//! - Each llcas node is stored as ONE CAS blob whose content is the
//!   zstd-compressed `"TCP0" | u32 ref_count | (u32 len | digest)* | data`
//!   frame, addressed by sha256 of that content (REAPI-native).
//! - The ActionResult is the closure MANIFEST: one OutputFile per node in the
//!   value graph, `path` = the node's llcas digest in hex (root first),
//!   `digest` = the blob's sha256 digest. A reader learns every blob it needs
//!   in one round trip and fetches the missing set in one batch.
//! - Publication: FindMissingBlobs -> BatchUpdateBlobs (missing only, which
//!   makes cross-process upload dedup server-side) -> UpdateActionResult
//!   LAST, so a reader can never observe an entry whose graph is incomplete.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

use bazel_remote_apis::build::bazel::remote::execution::v2::{
    self as reapi, action_cache_client::ActionCacheClient, batch_update_blobs_request,
    content_addressable_storage_client::ContentAddressableStorageClient,
};
pub use bazel_remote_apis::build::bazel::remote::execution::v2::Digest;
use sha2::{Digest as _, Sha256};
use tonic::transport::{Channel, Endpoint};

#[derive(Default)]
pub struct OpStats {
    pub count: AtomicU64,
    pub total_ms: AtomicU64,
    pub max_ms: AtomicU64,
}

impl OpStats {
    pub fn record(&self, elapsed: Duration) {
        let ms = elapsed.as_millis() as u64;
        self.count.fetch_add(1, Ordering::Relaxed);
        self.total_ms.fetch_add(ms, Ordering::Relaxed);
        self.max_ms.fetch_max(ms, Ordering::Relaxed);
    }

    pub fn summary(&self) -> String {
        let count = self.count.load(Ordering::Relaxed);
        format!(
            "n={} sum={}ms max={}ms",
            count,
            self.total_ms.load(Ordering::Relaxed),
            self.max_ms.load(Ordering::Relaxed),
        )
    }
}

pub struct RemoteConfig {
    pub grpc_url: String,
    pub instance: String,
}

impl RemoteConfig {
    pub fn from_env() -> Option<Self> {
        let grpc_url = std::env::var("TUIST_CAS_REMOTE_GRPC_URL").ok()?;
        let account = std::env::var("TUIST_CAS_ACCOUNT").unwrap_or_else(|_| "tuist".into());
        let project = std::env::var("TUIST_CAS_PROJECT").unwrap_or_else(|_| "tuist".into());
        Some(Self {
            grpc_url,
            instance: format!("{account}/{project}"),
        })
    }
}

pub struct Node {
    pub refs: Vec<Vec<u8>>,
    pub data: Vec<u8>,
}

/// One node of a value graph as it travels: the llcas digest identifies it to
/// the local CAS, the REAPI digest identifies its frame blob remotely.
pub struct ManifestEntry {
    pub llcas_digest: Vec<u8>,
    pub blob: reapi::Digest,
}

// One request must stay under kura's 64MB decoding cap, with headroom.
const MAX_BATCH_BYTES: i64 = 32 << 20;
const RPC_TIMEOUT: Duration = Duration::from_secs(60);
const ATTEMPTS: usize = 3;

fn hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

fn unhex(s: &str) -> Option<Vec<u8>> {
    if s.len() % 2 != 0 {
        return None;
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).ok())
        .collect()
}

pub fn blob_digest(content: &[u8]) -> reapi::Digest {
    reapi::Digest {
        hash: hex(&Sha256::digest(content)),
        size_bytes: content.len() as i64,
    }
}

fn action_digest(key: &[u8]) -> reapi::Digest {
    reapi::Digest {
        hash: hex(&Sha256::digest(key)),
        size_bytes: key.len() as i64,
    }
}

fn runtime() -> &'static tokio::runtime::Runtime {
    static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("tokio runtime")
    })
}

pub struct Remote {
    config: RemoteConfig,
    channel: OnceLock<Result<Channel, String>>,
    pub get_stats: OpStats,
    pub post_stats: OpStats,
}

fn retryable(status: &tonic::Status) -> bool {
    matches!(
        status.code(),
        tonic::Code::Unavailable
            | tonic::Code::Unknown
            | tonic::Code::DeadlineExceeded
            | tonic::Code::ResourceExhausted
    )
}

impl Remote {
    pub fn new(config: RemoteConfig) -> Arc<Self> {
        Arc::new(Self {
            config,
            channel: OnceLock::new(),
            get_stats: OpStats::default(),
            post_stats: OpStats::default(),
        })
    }

    fn channel(&self) -> Result<Channel, String> {
        self.channel
            .get_or_init(|| {
                let endpoint = Endpoint::from_shared(self.config.grpc_url.clone())
                    .map_err(|e| format!("bad grpc url: {e}"))?
                    .connect_timeout(Duration::from_secs(5))
                    .timeout(RPC_TIMEOUT)
                    // h2 keepalive prevents the stale-idle-connection class
                    // that plagued the HTTP/1.1 transport.
                    .http2_keep_alive_interval(Duration::from_secs(20))
                    .keep_alive_while_idle(true)
                    .keep_alive_timeout(Duration::from_secs(10));
                runtime()
                    .block_on(endpoint.connect())
                    .map_err(|e| format!("grpc connect: {e}"))
            })
            .clone()
    }

    fn cas_client(&self) -> Result<ContentAddressableStorageClient<Channel>, String> {
        Ok(ContentAddressableStorageClient::new(self.channel()?)
            .max_decoding_message_size(256 << 20))
    }

    fn ac_client(&self) -> Result<ActionCacheClient<Channel>, String> {
        Ok(ActionCacheClient::new(self.channel()?).max_decoding_message_size(64 << 20))
    }

    /// Fetches the closure manifest for an action key. `Ok(None)` is a
    /// definitive miss; `Err` is a transport problem.
    pub fn get_action(&self, key: &[u8]) -> Result<Option<Vec<ManifestEntry>>, String> {
        let started = Instant::now();
        let result = (|| {
            let mut client = self.ac_client()?;
            let request = reapi::GetActionResultRequest {
                instance_name: self.config.instance.clone(),
                action_digest: Some(action_digest(key)),
                ..Default::default()
            };
            for attempt in 0..ATTEMPTS {
                let response =
                    runtime().block_on(client.get_action_result(request.clone()));
                match response {
                    Ok(response) => {
                        let manifest = response
                            .into_inner()
                            .output_files
                            .into_iter()
                            .filter_map(|file| {
                                Some(ManifestEntry {
                                    llcas_digest: unhex(&file.path)?,
                                    blob: file.digest?,
                                })
                            })
                            .collect();
                        return Ok(Some(manifest));
                    }
                    Err(status) if status.code() == tonic::Code::NotFound => return Ok(None),
                    Err(status) if retryable(&status) && attempt + 1 < ATTEMPTS => continue,
                    Err(status) => return Err(format!("get_action: {status}")),
                }
            }
            unreachable!()
        })();
        self.get_stats.record(started.elapsed());
        result
    }

    /// Reads blobs in size-bounded batches. Returns content per digest hash.
    pub fn batch_read(
        &self,
        blobs: &[reapi::Digest],
    ) -> Result<std::collections::HashMap<String, Vec<u8>>, String> {
        let started = Instant::now();
        let result = (|| {
            let mut client = self.cas_client()?;
            let mut contents = std::collections::HashMap::new();
            for chunk in chunk_digests(blobs) {
                let request = reapi::BatchReadBlobsRequest {
                    instance_name: self.config.instance.clone(),
                    digests: chunk.to_vec(),
                    ..Default::default()
                };
                let mut last_error = String::new();
                let mut done = false;
                for attempt in 0..ATTEMPTS {
                    match runtime().block_on(client.batch_read_blobs(request.clone())) {
                        Ok(response) => {
                            for entry in response.into_inner().responses {
                                let ok = entry
                                    .status
                                    .as_ref()
                                    .map(|s| s.code == 0)
                                    .unwrap_or(false);
                                if ok {
                                    if let Some(digest) = entry.digest {
                                        contents.insert(digest.hash, entry.data.to_vec());
                                    }
                                }
                            }
                            done = true;
                            break;
                        }
                        Err(status) if retryable(&status) && attempt + 1 < ATTEMPTS => {
                            last_error = status.to_string();
                        }
                        Err(status) => return Err(format!("batch_read: {status}")),
                    }
                }
                if !done {
                    return Err(format!("batch_read: {last_error}"));
                }
            }
            Ok(contents)
        })();
        self.get_stats.record(started.elapsed());
        result
    }

    /// Returns the subset of digests the server does not have.
    pub fn find_missing(&self, blobs: Vec<reapi::Digest>) -> Result<Vec<reapi::Digest>, String> {
        let started = Instant::now();
        let result = (|| {
            let mut client = self.cas_client()?;
            let request = reapi::FindMissingBlobsRequest {
                instance_name: self.config.instance.clone(),
                blob_digests: blobs,
                ..Default::default()
            };
            let mut last_error = String::new();
            for attempt in 0..ATTEMPTS {
                match runtime().block_on(client.find_missing_blobs(request.clone())) {
                    Ok(response) => return Ok(response.into_inner().missing_blob_digests),
                    Err(status) if retryable(&status) && attempt + 1 < ATTEMPTS => {
                        last_error = status.to_string();
                    }
                    Err(status) => return Err(format!("find_missing: {status}")),
                }
            }
            Err(format!("find_missing: {last_error}"))
        })();
        self.get_stats.record(started.elapsed());
        result
    }

    /// Uploads blobs in size-bounded batches.
    pub fn batch_update(&self, items: Vec<(reapi::Digest, Vec<u8>)>) -> Result<(), String> {
        let started = Instant::now();
        let result = (|| {
            let mut client = self.cas_client()?;
            let mut pending: Vec<batch_update_blobs_request::Request> = items
                .into_iter()
                .map(|(digest, data)| batch_update_blobs_request::Request {
                    digest: Some(digest),
                    data: data.into(),
                    ..Default::default()
                })
                .collect();
            while !pending.is_empty() {
                let mut size = 0i64;
                let mut take = 0usize;
                for request in &pending {
                    let blob_size = request.digest.as_ref().map(|d| d.size_bytes).unwrap_or(0);
                    if take > 0 && size + blob_size > MAX_BATCH_BYTES {
                        break;
                    }
                    size += blob_size;
                    take += 1;
                }
                let chunk: Vec<_> = pending.drain(..take).collect();
                let request = reapi::BatchUpdateBlobsRequest {
                    instance_name: self.config.instance.clone(),
                    requests: chunk,
                    ..Default::default()
                };
                let mut last_error = String::new();
                let mut done = false;
                for attempt in 0..ATTEMPTS {
                    match runtime().block_on(client.batch_update_blobs(request.clone())) {
                        Ok(response) => {
                            for entry in response.into_inner().responses {
                                if let Some(status) = entry.status {
                                    if status.code != 0 {
                                        return Err(format!(
                                            "batch_update blob rejected: {}",
                                            status.message
                                        ));
                                    }
                                }
                            }
                            done = true;
                            break;
                        }
                        Err(status) if retryable(&status) && attempt + 1 < ATTEMPTS => {
                            last_error = status.to_string();
                        }
                        Err(status) => return Err(format!("batch_update: {status}")),
                    }
                }
                if !done {
                    return Err(format!("batch_update: {last_error}"));
                }
            }
            Ok(())
        })();
        self.post_stats.record(started.elapsed());
        result
    }

    /// Publishes the entry. Called only after every blob in the manifest is
    /// known to be on the server.
    pub fn update_action(&self, key: &[u8], manifest: &[ManifestEntry]) -> Result<(), String> {
        let started = Instant::now();
        let result = (|| {
            let mut client = self.ac_client()?;
            let action_result = reapi::ActionResult {
                output_files: manifest
                    .iter()
                    .map(|entry| reapi::OutputFile {
                        path: hex(&entry.llcas_digest),
                        digest: Some(entry.blob.clone()),
                        ..Default::default()
                    })
                    .collect(),
                ..Default::default()
            };
            let request = reapi::UpdateActionResultRequest {
                instance_name: self.config.instance.clone(),
                action_digest: Some(action_digest(key)),
                action_result: Some(action_result),
                ..Default::default()
            };
            let mut last_error = String::new();
            for attempt in 0..ATTEMPTS {
                match runtime().block_on(client.update_action_result(request.clone())) {
                    Ok(_) => return Ok(()),
                    Err(status) if retryable(&status) && attempt + 1 < ATTEMPTS => {
                        last_error = status.to_string();
                    }
                    Err(status) => return Err(format!("update_action: {status}")),
                }
            }
            Err(format!("update_action: {last_error}"))
        })();
        self.post_stats.record(started.elapsed());
        result
    }
}

/// Splits digests into read batches that respect the size cap; oversized
/// blobs go in single-item batches (kura accepts up to its 64MB cap).
fn chunk_digests(blobs: &[reapi::Digest]) -> Vec<&[reapi::Digest]> {
    let mut chunks = Vec::new();
    let mut start = 0usize;
    let mut size = 0i64;
    for (index, digest) in blobs.iter().enumerate() {
        if index > start && size + digest.size_bytes > MAX_BATCH_BYTES {
            chunks.push(&blobs[start..index]);
            start = index;
            size = 0;
        }
        size += digest.size_bytes;
    }
    if start < blobs.len() {
        chunks.push(&blobs[start..]);
    }
    chunks
}

pub fn encode_frame(refs: &[Vec<u8>], data: &[u8]) -> Vec<u8> {
    let mut out =
        Vec::with_capacity(16 + data.len() + refs.iter().map(|r| r.len() + 4).sum::<usize>());
    out.extend_from_slice(b"TCP0");
    out.extend_from_slice(&(refs.len() as u32).to_le_bytes());
    for reference in refs {
        out.extend_from_slice(&(reference.len() as u32).to_le_bytes());
        out.extend_from_slice(reference);
    }
    out.extend_from_slice(data);
    out
}

pub fn decode_frame(frame: &[u8]) -> Option<Node> {
    if frame.len() < 8 || &frame[0..4] != b"TCP0" {
        return None;
    }
    let mut offset = 4;
    let ref_count = u32::from_le_bytes(frame[offset..offset + 4].try_into().ok()?) as usize;
    offset += 4;
    let mut refs = Vec::with_capacity(ref_count);
    for _ in 0..ref_count {
        if frame.len() < offset + 4 {
            return None;
        }
        let len = u32::from_le_bytes(frame[offset..offset + 4].try_into().ok()?) as usize;
        offset += 4;
        if frame.len() < offset + len {
            return None;
        }
        refs.push(frame[offset..offset + len].to_vec());
        offset += len;
    }
    Some(Node {
        refs,
        data: frame[offset..].to_vec(),
    })
}

pub fn compress_frame(frame: &[u8]) -> Vec<u8> {
    zstd::stream::encode_all(frame, 1).unwrap_or_default()
}

pub fn decompress_frame(blob: &[u8]) -> Option<Vec<u8>> {
    zstd::stream::decode_all(blob).ok()
}
