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
use tonic::transport::{Channel, ClientTlsConfig, Endpoint};

use crate::token::TokenProvider;

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
    /// REAPI `instance_name`: the project segment only, NOT the `account/project`
    /// full handle. Kura derives the tenant (account) from the bearer token and
    /// builds the authz identifier as `{tenant}/{instance_name}`, so carrying the
    /// account here would double-count it (e.g. `tuist/tuist/tuist`, which no
    /// principal is granted). See `reapi_instance`.
    pub instance: String,
}

/// The REAPI `instance_name` for an `account/project` full handle: the project
/// segment only (everything after the first `/`). The account is conveyed to
/// Kura by the bearer token, so it must not also be part of `instance_name`.
pub fn reapi_instance(full_handle: &str) -> &str {
    full_handle
        .split_once('/')
        .map(|(_account, project)| project)
        .unwrap_or(full_handle)
}

impl RemoteConfig {
    pub fn from_env() -> Option<Self> {
        let grpc_url = std::env::var("TUIST_CAS_REMOTE_GRPC_URL").ok()?;
        let project = std::env::var("TUIST_CAS_PROJECT").unwrap_or_else(|_| "tuist".into());
        Some(Self {
            grpc_url,
            instance: reapi_instance(&project).to_string(),
        })
    }
}

pub struct Node {
    pub refs: Vec<Vec<u8>>,
    pub data: Vec<u8>,
}

/// One node of a value graph as it travels: the llcas digest identifies it to
/// the local CAS, the REAPI digest identifies its frame blob remotely.
#[derive(Clone)]
pub struct ManifestEntry {
    pub llcas_digest: Vec<u8>,
    pub blob: reapi::Digest,
    /// Frame bytes the server inlined into the GetActionResult response (see
    /// the `inline_output_files: ["*"]` request hint). `None` means the server
    /// did not inline this blob (older kura, or response budget exhausted) and
    /// it must be fetched via `batch_read` as before.
    pub contents: Option<Vec<u8>>,
}

// One request must stay under kura's 64MB decoding cap, with headroom.
const MAX_BATCH_BYTES: i64 = 32 << 20;
const RPC_TIMEOUT: Duration = Duration::from_secs(60);
const ATTEMPTS: usize = 3;

/// Retries a synchronous gRPC call up to `ATTEMPTS` times on retryable statuses,
/// keeping the retry policy in one place. The caller maps success and terminal
/// errors (e.g. NotFound) at the call site.
fn retry_call<T>(mut op: impl FnMut() -> Result<T, tonic::Status>) -> Result<T, tonic::Status> {
    let mut last = None;
    for attempt in 0..ATTEMPTS {
        match op() {
            Ok(value) => return Ok(value),
            Err(status) if retryable(&status) && attempt + 1 < ATTEMPTS => last = Some(status),
            Err(status) => return Err(status),
        }
    }
    Err(last.unwrap_or_else(|| tonic::Status::unknown("retry attempts exhausted")))
}

/// Async counterpart of `retry_call`, for calls issued from within a tokio task
/// where blocking is not allowed. `op` is re-invoked (returning a fresh future)
/// per attempt.
async fn retry_call_async<T, F, Fut>(mut op: F) -> Result<T, tonic::Status>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T, tonic::Status>>,
{
    let mut last = None;
    for attempt in 0..ATTEMPTS {
        match op().await {
            Ok(value) => return Ok(value),
            Err(status) if retryable(&status) && attempt + 1 < ATTEMPTS => last = Some(status),
            Err(status) => return Err(status),
        }
    }
    Err(last.unwrap_or_else(|| tonic::Status::unknown("retry attempts exhausted")))
}

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
            .worker_threads(8)
            .enable_all()
            .build()
            .expect("tokio runtime")
    })
}

pub struct Remote {
    config: RemoteConfig,
    tokens: Arc<TokenProvider>,
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
            // Kura periodically closes an h2 connection with GOAWAY(NO_ERROR)
            // (graceful rotation), which tonic surfaces as `Internal`
            // ("h2 protocol error"); an in-flight stream on the dropped
            // connection surfaces as `Cancelled` ("connection closed"). Both are
            // transient transport conditions, not the server rejecting the
            // request -- re-issuing reconnects the lazy channel. Safe to retry
            // because every CAS op is idempotent (content-addressed reads,
            // dedup'd writes). Without this a graceful GOAWAY turned a cache hit
            // into a miss + recompile: harmless at low concurrency, a real
            // hit-rate drain once many fetches overlap.
            | tonic::Code::Internal
            | tonic::Code::Cancelled
    )
}

type AuthValue = tonic::metadata::MetadataValue<tonic::metadata::Ascii>;

/// Wraps a message in a `tonic::Request`, attaching the bearer when present.
fn authed_request<T>(message: T, auth: Option<&AuthValue>) -> tonic::Request<T> {
    let mut request = tonic::Request::new(message);
    if let Some(value) = auth {
        request.metadata_mut().insert("authorization", value.clone());
    }
    request
}

impl Remote {
    pub fn new(config: RemoteConfig, tokens: Arc<TokenProvider>) -> Arc<Self> {
        Arc::new(Self {
            config,
            tokens,
            channel: OnceLock::new(),
            get_stats: OpStats::default(),
            post_stats: OpStats::default(),
        })
    }

    /// The `authorization: Bearer <token>` header, or `None` when the endpoint
    /// is unauthenticated. Cloned onto every request so the spawned batch-read
    /// tasks stay self-contained.
    fn authorization(&self) -> Option<AuthValue> {
        let token = self.tokens.current()?;
        AuthValue::try_from(format!("Bearer {token}")).ok()
    }

    fn authed<T>(&self, message: T) -> tonic::Request<T> {
        authed_request(message, self.authorization().as_ref())
    }

    fn channel(&self) -> Result<Channel, String> {
        self.channel
            .get_or_init(|| {
                // connect_lazy wires the hyper connection pool and the h2
                // keepalive timers to the *current* Tokio runtime. This runs from
                // a proxy handler thread (outside the runtime), so without
                // entering the runtime here the first RPC panics with "there is
                // no reactor running" on a detached connection task; the panic is
                // swallowed at the FFI boundary and every resolve silently
                // degrades to a local miss (0% remote cache).
                let _runtime_guard = runtime().enter();
                let mut endpoint = Endpoint::from_shared(self.config.grpc_url.clone())
                    .map_err(|e| format!("bad grpc url: {e}"))?
                    .connect_timeout(Duration::from_secs(5))
                    .timeout(RPC_TIMEOUT)
                    // h2 keepalive prevents the stale-idle-connection class
                    // that plagued the HTTP/1.1 transport.
                    .http2_keep_alive_interval(Duration::from_secs(20))
                    .keep_alive_while_idle(true)
                    .keep_alive_timeout(Duration::from_secs(10))
                    // Bulk-transfer windows: with default ~64KB stream
                    // windows, a 500KB batch response costs ~8 window-update
                    // round trips, which dominates on links with real RTT
                    // (measured ~31ms per 30-blob resolve over the VM bridge
                    // vs ~1ms server-side).
                    .initial_stream_window_size(Some(16 * 1024 * 1024))
                    .initial_connection_window_size(Some(64 * 1024 * 1024));
                // Public kura endpoints are https (TLS with the system trust
                // store); private-network endpoints stay plaintext h2c.
                if self.config.grpc_url.starts_with("https://") {
                    endpoint = endpoint
                        .tls_config(ClientTlsConfig::new().with_native_roots())
                        .map_err(|e| format!("tls config: {e}"))?;
                }
                // connect_lazy establishes (and transparently re-establishes)
                // the connection per request, so a Kura restart or transient
                // unreachability during the proxy's first call no longer gets
                // cached as a permanent Err that poisons every later RPC. The
                // only errors cached here are deterministic endpoint/TLS config
                // errors, which will never succeed on retry anyway.
                Ok(endpoint.connect_lazy())
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
                // Kura extension: `"*"` asks the server to inline every output
                // file's frame bytes into this response (best-effort, within
                // its response budget), collapsing the action lookup + blob
                // fetch into one round-trip. A server without the extension
                // matches no literal `"*"` path and inlines nothing, in which
                // case the caller batch-reads as before.
                inline_output_files: vec!["*".into()],
                ..Default::default()
            };
            let response = retry_call(|| {
                runtime().block_on(client.get_action_result(self.authed(request.clone())))
            });
            match response {
                Ok(response) => {
                    let manifest = response
                        .into_inner()
                        .output_files
                        .into_iter()
                        .filter_map(|file| {
                            Some(ManifestEntry {
                                llcas_digest: unhex(&file.path)?,
                                contents: (!file.contents.is_empty())
                                    .then_some(file.contents),
                                blob: file.digest?,
                            })
                        })
                        .collect();
                    Ok(Some(manifest))
                }
                Err(status) if status.code() == tonic::Code::NotFound => Ok(None),
                Err(status) => Err(format!("get_action: {status}")),
            }
        })();
        self.get_stats.record(started.elapsed());
        result
    }

    /// Reads blobs in size-bounded batches. Chunks are fetched concurrently
    /// over the multiplexed channel: bulk resolves can carry gigabytes, and
    /// a sequential chunk loop turns them into round-trip ladders.
    pub fn batch_read(
        &self,
        blobs: &[reapi::Digest],
    ) -> Result<std::collections::HashMap<String, Vec<u8>>, String> {
        let started = Instant::now();
        let result = (|| {
            let client = self.cas_client()?;
            let instance = self.config.instance.clone();
            let auth = self.authorization();
            let chunks = chunk_digests(blobs);
            let outcomes = runtime().block_on(async {
                let mut join_set = tokio::task::JoinSet::new();
                for chunk in &chunks {
                    let client = client.clone();
                    let auth = auth.clone();
                    let request = reapi::BatchReadBlobsRequest {
                        instance_name: instance.clone(),
                        digests: chunk.to_vec(),
                        ..Default::default()
                    };
                    join_set.spawn(async move {
                        retry_call_async(|| {
                            let mut client = client.clone();
                            let request = request.clone();
                            let auth = auth.clone();
                            async move {
                                client
                                    .batch_read_blobs(authed_request(request, auth.as_ref()))
                                    .await
                            }
                        })
                        .await
                        .map(|response| response.into_inner().responses)
                        .map_err(|status| format!("batch_read: {status}"))
                    });
                }
                let mut all = Vec::new();
                while let Some(joined) = join_set.join_next().await {
                    match joined {
                        Ok(Ok(responses)) => all.extend(responses),
                        Ok(Err(message)) => return Err(message),
                        Err(join_error) => return Err(format!("batch_read join: {join_error}")),
                    }
                }
                Ok(all)
            })?;
            let mut contents = std::collections::HashMap::new();
            for entry in outcomes {
                let ok = entry.status.as_ref().map(|s| s.code == 0).unwrap_or(false);
                if ok {
                    if let Some(digest) = entry.digest {
                        // The loop owns `entry`; move its data out rather than
                        // deep-copying every fetched blob (batches run to 32MB
                        // while the requesting compiler blocks on the resolve).
                        contents.insert(digest.hash, entry.data);
                    }
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
            let response = retry_call(|| {
                runtime().block_on(client.find_missing_blobs(self.authed(request.clone())))
            })
            .map_err(|status| format!("find_missing: {status}"))?;
            Ok(response.into_inner().missing_blob_digests)
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
                let response = retry_call(|| {
                    runtime().block_on(client.batch_update_blobs(self.authed(request.clone())))
                })
                .map_err(|status| format!("batch_update: {status}"))?;
                for entry in response.into_inner().responses {
                    if let Some(status) = entry.status {
                        if status.code != 0 {
                            return Err(format!("batch_update blob rejected: {}", status.message));
                        }
                    }
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
            retry_call(|| {
                runtime().block_on(client.update_action_result(self.authed(request.clone())))
            })
            .map_err(|status| format!("update_action: {status}"))?;
            Ok(())
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

#[cfg(test)]
mod tests {
    use super::reapi_instance;

    #[test]
    fn reapi_instance_strips_the_account_from_a_full_handle() {
        // Kura prepends the token's tenant to instance_name, so instance_name is
        // the project only; the full handle would become account/account/project.
        assert_eq!(reapi_instance("tuist/tuist"), "tuist");
        assert_eq!(reapi_instance("acme/ios-app"), "ios-app");
    }

    #[test]
    fn reapi_instance_passes_through_a_bare_project() {
        assert_eq!(reapi_instance("tuist"), "tuist");
        assert_eq!(reapi_instance(""), "");
    }
}
