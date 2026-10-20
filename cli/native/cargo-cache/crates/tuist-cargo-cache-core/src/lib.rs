//! Protocol and storage primitives for tuist_cargo_cache build caches.
//!
//! This crate contains the types shared by cache clients, the task-scoped
//! cache agent, and remote cache implementations. Protocol records are
//! serialized with [`canonical_json`] before hashing; changing their shape is
//! therefore a wire-format change, not merely an implementation detail.
//!
//! Most consumers start with [`CacheDigest`] and the local stores
//! [`LocalCas`] and [`LocalActionCache`]. Remote clients use
//! [`RemoteCacheClient`], while tuist_cargo_cache's compiler shim communicates with a
//! [`CacheAgent`] using [`AgentRequest`] and [`AgentResponse`].
//!
//! ```
//! use tuist_cargo_cache_core::{CacheDigest, canonical_json};
//! use serde::Serialize;
//!
//! #[derive(Serialize)]
//! struct Key<'a> {
//!     compiler: &'a str,
//!     source: CacheDigest,
//! }
//!
//! let source = CacheDigest::blake3(b"fn main() {}\n");
//! let bytes = canonical_json(&Key { compiler: "rustc", source })?;
//! let action = CacheDigest::blake3(&bytes);
//! assert_eq!(action.algorithm, "blake3");
//! # Ok::<(), eyre::Report>(())
//! ```
#![deny(missing_docs)]

use eyre::{Result, bail, eyre};
use log::warn;
use reqwest::header::HeaderValue;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};
use url::Url;

mod agent;
mod client;
mod imds;
mod local;
mod path_mapping;
mod public_cache_report;

/// Drain the invocation-local public report without changing the Cargo result.
pub fn flush_public_cache_report() {
    public_cache_report::flush();
}

/// Build-script actions are keyed after declared-input validation, not rustc invocations.
pub fn record_public_build_script(action: &CacheDigest, name: &str, status: &str) {
    public_cache_report::build_script(action, name, status);
}

mod reapi_proto;
mod reapi_retry;
mod remote_http;
mod remote_reapi;
mod remote_reapi_network;
mod remote_s3;
mod sigv4;
mod uploads;

pub use agent::{
    AGENT_PROTOCOL_VERSION, ActionDiagnostic, AgentEvent, AgentEventObserver, AgentRemoteCache,
    AgentRequest, AgentResponse, AgentStats, CacheAgent, CompilerStats, FileDigestCache,
    FileDigestResolution, FileDigestScope, FileIdentity, FileObjectIdentity, FileSnapshot,
    NoFileDigestCache, PinnedFile, PinnedState, RecordedFileDigest, RestoreStats,
    ValidatedFileDigest, WrapperSpan, WrapperTiming, digest_file, digest_file_validated,
    is_task_identity, merge_task_action_predictions, task_manifest_actions,
};
pub use client::BlockingAgentClient;
pub use imds::{InstanceRoleCredentials, TemporaryCredentials};
pub use local::{LocalActionCache, LocalCas};
pub use path_mapping::{
    PathAliases, PathMapping, PathNormalizationError, normalize_mapped_path,
    normalize_resolved_mapped_path, normalize_resolved_mapped_path_with, resolve_path_mappings,
};
use remote_http::HttpRemoteCache;
#[cfg(feature = "fuzzing")]
#[doc(hidden)]
pub use remote_http::fuzz_decode_blob_pack;
pub(crate) use remote_http::{BlobPackLimits, blob_pack_chunk};
use remote_s3::S3RemoteCache;
pub use remote_s3::{S3ConditionalWrites, S3RemoteCacheConfig};
pub use sigv4::S3Credentials;
pub use tuist_cargo_cache_protocol::{
    ACTION_PROMISE_MEDIA_TYPE, ACTION_RESULT_BATCH_MEDIA_TYPE, ACTION_RESULT_MEDIA_TYPE,
    ActionPrediction, ActionPromiseCompletion, ActionPromiseJoin, ActionPromiseState,
    ActionResult as RemoteActionResult, BLOB_MEDIA_TYPE, BLOB_PACK_BLOBS_HEADER,
    BLOB_PACK_BYTES_HEADER, BLOB_PACK_HEADER_BYTES, BLOB_PACK_MAGIC, BLOB_PACK_MEDIA_TYPE,
    BLOB_PACK_RECEIPT_MEDIA_TYPE, CLIENT_METADATA_MEDIA_TYPE, Capabilities, CapabilityFeatures,
    CapabilityLimits, CapabilityProtocol, CcMetadata, DIGEST_LIST_MEDIA_TYPE, DIRECTORY_MEDIA_TYPE,
    Digest as CacheDigest, DigestAlgorithm, Directory as CacheDirectory,
    DirectoryNode as CacheDirectoryNode, FileNode as CacheFileNode, MAX_ACTION_PREDICTION_PAYLOAD,
    MAX_ACTION_PROMISE_CLAIM_BYTES, NAMESPACE_HEADER, PROTOCOL_HEADER, PROTOCOL_VERSION,
    RustcMetadata, SymlinkNode as CacheSymlinkNode, TASK_ACTION_MANIFEST_MEDIA_TYPE,
    TaskActionManifest,
};
/// Cap the JSON bodies a remote cache can hand back. Blob downloads are bounded
/// by the size their digest promises, but action results and manifests carry no
/// such claim, so without an explicit ceiling a hostile or broken server can
/// stream until this process runs out of memory -- for manifests, long before
/// `validate_task_manifest` ever sees the payload. The bound matches the agent's
/// own request ceiling so both ends of the protocol refuse the same magnitude.
const MAX_REMOTE_JSON_BYTES: u64 = 16 * 1024 * 1024;
/// Ceiling on the opaque part of an entity tag this client will carry back.
///
/// A tag is only ever echoed into `If-Match`, so its length is bounded to keep
/// a server from choosing how large a request header this client sends.
const MAX_ETAG_BYTES: usize = 256;
// Match the server's default maximum while retaining a client-side ceiling
// when the remote advertises or names something larger.
const MAX_REMOTE_BLOB_BYTES: u64 = 5 * 1024 * 1024 * 1024;
const MAX_STAGED_BLOB_PACK_BYTES: u64 = 256 * 1024 * 1024;
const MAX_STAGED_BLOB_PACK_ITEMS: usize = 2 * 1024;
const BLOB_PACK_TIMEOUT_BYTES_PER_UNIT: u64 = MAX_STAGED_BLOB_PACK_BYTES / 4;
const BLOB_PACK_TIMEOUT_ITEMS_PER_UNIT: usize = MAX_STAGED_BLOB_PACK_ITEMS / 4;
/// Bytes read from one pack member before the next chunk is yielded.
const PACK_STREAM_CHUNK_BYTES: usize = 64 * 1024;
/// Actions looked up in one batched request.
///
/// A prefetch wants its first results back while the rest are still being
/// answered, so a batch stays small enough to keep the download pipeline fed
/// rather than as large as a server would accept.
const MAX_ACTION_BATCH_ITEMS: usize = 256;
/// Ceiling on one batched action-result response, scaled by what was asked for.
const MAX_ACTION_RESULT_BYTES: u64 = 64 * 1024;

/// Serialize a protocol object using the JSON Canonicalization Scheme.
///
/// Action digests are computed from these bytes, so callers must not use
/// serde's struct field order as part of the wire contract.
pub fn canonical_json(value: &impl Serialize) -> Result<Vec<u8>> {
    Ok(tuist_cargo_cache_protocol::canonical_json(value)?)
}

#[derive(
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    Default,
    strum::EnumString,
    strum::Display,
    PartialEq,
    Eq,
)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
/// Operations permitted against a configured remote cache.
pub enum RemoteCacheMode {
    /// Permit reads from and writes to the remote cache.
    #[default]
    ReadWrite,
    /// Permit reads but never publish new objects.
    ReadOnly,
    /// Publish objects but never satisfy lookups from the remote cache.
    WriteOnly,
}

impl RemoteCacheMode {
    /// Whether this mode permits remote cache reads.
    pub fn reads(self) -> bool {
        matches!(self, Self::ReadWrite | Self::ReadOnly)
    }

    /// Whether this mode permits remote cache writes.
    pub fn writes(self) -> bool {
        matches!(self, Self::ReadWrite | Self::WriteOnly)
    }
}

/// Connection, authentication, and retry settings for [`RemoteCacheClient`].
pub struct RemoteCacheConfig {
    /// Base URL of the remote cache service.
    pub base_url: Url,
    /// Server-side namespace used to isolate cache objects.
    pub namespace: String,
    /// Static bearer token, if configured directly.
    pub token: Option<String>,
    /// File containing a bearer token that may be refreshed externally.
    pub token_file: Option<PathBuf>,
    /// Audience used when obtaining an OIDC token from the CI environment.
    pub oidc_audience: Option<String>,
    /// Maximum time allowed to establish a connection.
    pub connect_timeout: Duration,
    /// Maximum time without response progress for ordinary requests.
    pub read_timeout: Duration,
    /// Deadline for one blob download, spanning every retry attempt and the
    /// backoff between them rather than bounding a single attempt.
    ///
    /// A single stalled attempt is already bounded by `connect_timeout` and
    /// `read_timeout`, so this budget exists to cap the total wall-clock one
    /// logical download may spend: exhausting it fails the download even when
    /// retries remain. Size it for the largest artifact worth waiting on, not
    /// for one attempt at it.
    pub download_timeout: Duration,
    /// Number of attempts after the initial request for retryable failures.
    pub retries: i64,
}

/// Backing data for a blob upload.
pub enum BlobSource {
    /// Bytes held in memory.
    Bytes(Vec<u8>),
    /// A temporary file whose lifetime is owned by the upload.
    File(tempfile::NamedTempFile),
    /// A persistent file at the given path.
    Path(PathBuf),
}

/// A digest paired with the data to upload under that digest.
pub struct BlobUpload {
    /// Expected digest and length of the source data.
    pub digest: CacheDigest,
    /// Data source read by [`RemoteCacheClient::put_blob`].
    pub source: BlobSource,
}

/// Task action-manifest bytes returned with their concurrency token.
pub struct RemoteActionManifest {
    /// Raw canonical manifest JSON.
    pub bytes: Vec<u8>,
    /// Entity tag used for conditional manifest replacement.
    pub etag: String,
}

/// A verified set of remote CAS objects downloaded through blob-pack streams.
pub struct RemoteBlobPack {
    _directory: tempfile::TempDir,
    /// Verified blobs paired with paths in this pack's temporary directory.
    pub blobs: Vec<(CacheDigest, PathBuf)>,
    /// Number of HTTP pack requests needed to retrieve the requested set.
    pub requests: u64,
    /// Unique digests requested from the remote service.
    pub requested: Vec<CacheDigest>,
    /// Number of verified blob frames received.
    pub blob_count: u64,
    /// Total unframed blob payload bytes received.
    pub payload_bytes: u64,
    /// Total bytes received including framing.
    pub framed_bytes: u64,
}

/// What a server did with the blobs in an uploaded pack.
#[derive(Debug, Clone, Copy, Deserialize)]
pub struct BlobPackReceipt {
    /// Blobs this request added to the remote cache.
    #[serde(default)]
    pub created: u64,
    /// Blobs the remote cache already held.
    #[serde(default)]
    pub existing: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Result of a conditional task-manifest write.
pub enum ManifestPutOutcome {
    /// The manifest was stored.
    Stored,
    /// The supplied entity-tag precondition did not match.
    PreconditionFailed,
}

/// A client for a remote tuist_cargo_cache cache.
///
/// The client validates digests, response sizes, media types, and redirects at
/// the protocol boundary. It is safe to share between asynchronous tasks.
///
/// Which service is on the other end is not part of this type's contract. A
/// cache server speaks the full protocol; an object store answers the same
/// lookups without the extensions built on top of it, and reports that by
/// declining them rather than by failing.
pub struct RemoteCacheClient {
    backend: Backend,
}

/// The service a [`RemoteCacheClient`] talks to.
///
/// Backends are a closed set, so they dispatch through an enum rather than a
/// trait: an `async fn` in a trait is not object-safe, and boxing every call to
/// work around that would buy nothing here.
enum Backend {
    Reapi(Box<remote_reapi::ReapiRemoteCache>),
    Http(HttpRemoteCache),
    S3(S3RemoteCache),
}

impl RemoteCacheClient {
    /// Construct a client and validate its URL and authentication settings.
    pub fn new(config: RemoteCacheConfig) -> Result<Self> {
        Ok(Self {
            backend: Backend::Reapi(Box::new(remote_reapi::ReapiRemoteCache::new(config)?)),
        })
    }

    /// Legacy transport retained only to run copied model regression fixtures.
    /// The shipped Tuist runtime always constructs the REAPI client with `new`.
    #[doc(hidden)]
    pub fn new_http_for_model_tests(config: RemoteCacheConfig) -> Result<Self> {
        Ok(Self {
            backend: Backend::Http(HttpRemoteCache::new(config)?),
        })
    }

    /// Bound the wall clock this session may lose to reads that fail.
    ///
    /// `download_timeout` bounds one logical download; this bounds their sum.
    /// Without it an unhealthy server charges every object that deadline again,
    /// so a build can spend longer failing to read the cache than it would have
    /// spent compiling. Reads are best effort, so exhausting this budget stops
    /// them for the rest of the session rather than failing the build.
    ///
    /// `Duration::ZERO` keeps reading however long the remote takes to fail.
    /// Has no effect on an S3 backend, which has no such deadline to repeat.
    pub fn with_read_stall_budget(mut self, budget: Duration) -> Self {
        match &mut self.backend {
            Backend::Http(client) => client.set_read_stall_budget(budget),
            Backend::Reapi(client) => client.set_read_stall_budget(budget),
            Backend::S3(_) => {}
        }
        self
    }

    /// Construct a client backed directly by an S3-compatible object store.
    ///
    /// The store answers the same lookups a cache server does, without the
    /// extensions built on top of the protocol. See [`S3RemoteCacheConfig`].
    pub fn new_s3(config: S3RemoteCacheConfig) -> Result<Self> {
        Ok(Self {
            backend: Backend::S3(S3RemoteCache::new(config)?),
        })
    }

    /// Construct an S3 client whose credentials come from an EC2 instance role
    /// and are renewed before they expire.
    ///
    /// `config.credentials` and `expires_at` are the credentials the role
    /// returned when `provider` was first asked, and the instant they lapse.
    /// From then on the client fetches a new set from `provider` shortly
    /// before that, so a session that outlives its credentials keeps working.
    pub fn new_s3_with_instance_role(
        config: S3RemoteCacheConfig,
        provider: InstanceRoleCredentials,
        expires_at: std::time::SystemTime,
    ) -> Result<Self> {
        Ok(Self {
            backend: Backend::S3(
                S3RemoteCache::new(config)?.with_instance_role(provider, expires_at),
            ),
        })
    }

    /// Connect to the service, authenticate, and negotiate protocol capabilities.
    ///
    /// This performs no cache reads or writes. It is intended for diagnostics
    /// that need to distinguish a valid client configuration from a reachable,
    /// compatible remote cache.
    pub async fn check_connection(&self) -> Result<()> {
        match &self.backend {
            Backend::Reapi(client) => client.check_connection().await,
            Backend::Http(client) => client.check_connection().await,
            Backend::S3(store) => store.check_connection().await,
        }
    }

    /// Download verified CAS objects using the server's negotiated blob-pack extension.
    ///
    /// `None` means the service does not support blob packs. Objects omitted by a
    /// supported server are absent from `blobs`, so callers can retry them through
    /// the ordinary single-blob endpoint.
    pub async fn get_blob_pack(
        &self,
        digests: &[CacheDigest],
        staging_dir: &Path,
    ) -> Result<Option<RemoteBlobPack>> {
        match &self.backend {
            Backend::Reapi(_) => Ok(None),
            Backend::Http(client) => client.get_blob_pack(digests, staging_dir).await,
            Backend::S3(store) => store.get_blob_pack(digests, staging_dir).await,
        }
    }

    pub(crate) async fn get_blob_pack_with_limit(
        &self,
        digests: &[CacheDigest],
        staging_dir: &Path,
        max_bytes: u64,
    ) -> Result<Option<RemoteBlobPack>> {
        match &self.backend {
            Backend::Reapi(_) => Ok(None),
            Backend::Http(client) => {
                client
                    .get_blob_pack_with_limit(digests, staging_dir, max_bytes)
                    .await
            }
            Backend::S3(store) => {
                store
                    .get_blob_pack_with_limit(digests, staging_dir, max_bytes)
                    .await
            }
        }
    }

    /// How many blobs, and how many payload bytes, one downloaded pack may carry.
    pub(crate) async fn blob_pack_limits(&self) -> Result<Option<BlobPackLimits>> {
        match &self.backend {
            Backend::Reapi(_) => Ok(None),
            Backend::Http(client) => client.blob_pack_limits().await,
            Backend::S3(_) => Ok(None),
        }
    }

    /// Fetch and validate an action-result record, returning `None` on a miss.
    pub async fn get_action_result(
        &self,
        action: &CacheDigest,
    ) -> Result<Option<RemoteActionResult>> {
        match &self.backend {
            Backend::Reapi(client) => client.get_action_result(action).await,
            Backend::Http(client) => client.get_action_result(action).await,
            Backend::S3(store) => store.get_action_result(action).await,
        }
    }

    /// How many actions one batched lookup may ask about.
    ///
    /// `None` means the service does not answer batched lookups.
    pub(crate) async fn action_batch_limit(&self) -> Result<Option<usize>> {
        match &self.backend {
            Backend::Reapi(_) => Ok(None),
            Backend::Http(client) => client.action_batch_limit().await,
            Backend::S3(store) => store.action_batch_limit().await,
        }
    }

    /// Look up several action results in one request.
    ///
    /// `None` means the service does not answer batched lookups, leaving the
    /// caller to ask for each action individually. The response carries only the
    /// results the service holds, in no particular order, so each record is bound
    /// to its request by the action digest it names rather than by position.
    pub async fn get_action_results(
        &self,
        actions: &[CacheDigest],
    ) -> Result<Option<Vec<RemoteActionResult>>> {
        match &self.backend {
            Backend::Reapi(_) => Ok(None),
            Backend::Http(client) => client.get_action_results(actions).await,
            Backend::S3(store) => store.get_action_results(actions).await,
        }
    }

    /// Canonically serialize and store an action-result record.
    pub async fn put_action_result(&self, result: &RemoteActionResult) -> Result<()> {
        match &self.backend {
            Backend::Reapi(client) => client.put_action_result(result).await,
            Backend::Http(client) => client.put_action_result(result).await,
            Backend::S3(store) => store.put_action_result(result).await,
        }
    }

    /// Atomically join or claim a server-wide compilation promise.
    ///
    /// `None` means this backend does not support ephemeral coordination.
    pub async fn join_action_promise(
        &self,
        invocation: &CacheDigest,
        adapter: &str,
    ) -> Result<Option<ActionPromiseState>> {
        match &self.backend {
            Backend::Reapi(_) => Ok(None),
            Backend::Http(client) => client.join_action_promise(invocation, adapter).await,
            Backend::S3(_) => Ok(None),
        }
    }

    /// Complete a claimed promise after its action result has been published.
    ///
    /// `false` means this backend does not support ephemeral coordination.
    pub async fn complete_action_promise(
        &self,
        invocation: &CacheDigest,
        completion: &ActionPromiseCompletion,
    ) -> Result<bool> {
        match &self.backend {
            Backend::Reapi(_) => Ok(false),
            Backend::Http(client) => client.complete_action_promise(invocation, completion).await,
            Backend::S3(_) => Ok(false),
        }
    }

    /// Fetch a task action manifest and the entity tag needed to update it.
    pub async fn get_action_manifest(
        &self,
        key: &CacheDigest,
    ) -> Result<Option<RemoteActionManifest>> {
        match &self.backend {
            Backend::Reapi(client) => client.get_action_manifest(key).await,
            Backend::Http(client) => client.get_action_manifest(key).await,
            Backend::S3(store) => store.get_action_manifest(key).await,
        }
    }

    /// Store a task action manifest, optionally requiring an entity-tag match.
    pub async fn put_action_manifest(
        &self,
        key: &CacheDigest,
        bytes: &[u8],
        expected_etag: Option<&str>,
    ) -> Result<ManifestPutOutcome> {
        match &self.backend {
            Backend::Reapi(client) => client.put_action_manifest(key, bytes, expected_etag).await,
            Backend::Http(client) => client.put_action_manifest(key, bytes, expected_etag).await,
            Backend::S3(store) => store.put_action_manifest(key, bytes, expected_etag).await,
        }
    }

    /// Download a small blob into memory and verify its digest.
    pub async fn get_blob(
        &self,
        digest: &CacheDigest,
        media_type: &'static str,
    ) -> Result<Vec<u8>> {
        match &self.backend {
            Backend::Reapi(client) => client.get_blob(digest, media_type).await,
            Backend::Http(client) => client.get_blob(digest, media_type).await,
            Backend::S3(store) => store.get_blob(digest, media_type).await,
        }
    }

    /// Download a blob to a temporary file and verify its digest.
    pub async fn get_blob_file(
        &self,
        digest: &CacheDigest,
        staging_dir: &Path,
    ) -> Result<tempfile::NamedTempFile> {
        match &self.backend {
            Backend::Reapi(client) => client.get_blob_file(digest, staging_dir).await,
            Backend::Http(client) => client.get_blob_file(digest, staging_dir).await,
            Backend::S3(store) => store.get_blob_file(digest, staging_dir).await,
        }
    }

    /// How many blobs, and how many payload bytes, one uploaded pack may carry.
    ///
    /// `None` means the service does not accept packed uploads.
    pub(crate) async fn blob_pack_upload_limits(&self) -> Result<Option<BlobPackLimits>> {
        match &self.backend {
            Backend::Reapi(_) => Ok(None),
            Backend::Http(client) => client.blob_pack_upload_limits().await,
            Backend::S3(store) => store.blob_pack_upload_limits().await,
        }
    }

    /// Upload several content-addressed blobs in one framed request.
    ///
    /// `None` means the service does not accept packed uploads, leaving the
    /// caller to send each blob on its own. A rejected pack is reported as an
    /// error and publishes nothing the caller may rely on: a server verifies
    /// each frame as it arrives, so an accepted prefix may exist, but every blob
    /// is content-addressed and storing one twice is not an error.
    pub async fn put_blob_pack(&self, uploads: &[BlobUpload]) -> Result<Option<BlobPackReceipt>> {
        match &self.backend {
            Backend::Reapi(_) => Ok(None),
            Backend::Http(client) => client.put_blob_pack(uploads).await,
            Backend::S3(store) => store.put_blob_pack(uploads).await,
        }
    }

    /// Verify and upload a content-addressed blob.
    pub async fn put_blob(&self, upload: &BlobUpload) -> Result<()> {
        match &self.backend {
            Backend::Reapi(client) => client.put_blob(upload).await,
            Backend::Http(client) => client.put_blob(upload).await,
            Backend::S3(store) => store.put_blob(upload).await,
        }
    }
}

/// Buffer a JSON response body, refusing to grow past [`MAX_REMOTE_JSON_BYTES`].
///
/// A declared `Content-Length` is rejected up front so an oversized body costs
/// nothing to refuse; the streaming check then covers servers that understate or
/// omit it.
async fn read_bounded_json(response: reqwest::Response, what: &str) -> Result<Vec<u8>> {
    read_json_within(response, what, MAX_REMOTE_JSON_BYTES).await
}

async fn read_json_within(response: reqwest::Response, what: &str, limit: u64) -> Result<Vec<u8>> {
    if let Some(length) = response.content_length()
        && length > limit
    {
        bail!("remote cache {what} declared {length} bytes, over the {limit} byte limit");
    }
    let mut response = response;
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await? {
        if bytes.len() as u64 + chunk.len() as u64 > limit {
            bail!("remote cache {what} exceeded the {limit} byte limit");
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}
/// Read the entity tag that a later conditional update has to send back.
///
/// The tag is carried through opaquely, and nothing may infer content from it.
/// RFC 9110 section 8.8.3.3 requires an intermediary that re-encodes a response
/// to vary the strong tag along with it, and proxies do: Caddy appends the
/// content coding, so a manifest served through compression arrives tagged
/// `"<hash>-zstd"`. What the body actually is gets established by the caller
/// comparing it against canonical JSON, not by the shape of this header.
fn parse_strong_etag(value: Option<&HeaderValue>) -> Result<String> {
    let value = value
        .and_then(|value| value.to_str().ok())
        .ok_or_else(|| eyre!("remote action manifest response is missing an ETag"))?;
    if value.starts_with("W/") {
        // If-Match rejects a weak validator, so an update could not tell that it
        // was overwriting a manifest someone else had published.
        bail!("remote action manifest response has a weak ETag");
    }
    let etag = value
        .strip_prefix('"')
        .and_then(|value| value.strip_suffix('"'))
        .filter(|value| is_entity_tag(value))
        .ok_or_else(|| eyre!("remote action manifest response has an invalid ETag"))?;
    Ok(etag.to_owned())
}

fn quoted_etag(etag: &str) -> Result<HeaderValue> {
    if !is_entity_tag(etag) {
        bail!("invalid remote action manifest ETag");
    }
    Ok(HeaderValue::from_str(&format!("\"{etag}\""))?)
}

/// Whether this is the opaque body of a strong entity tag (RFC 9110 `etagc`).
///
/// `HeaderValue::to_str` has already ruled out anything but visible ASCII, so
/// the double quote that would end the tag early is all that is left to reject.
fn is_entity_tag(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= MAX_ETAG_BYTES
        && value.bytes().all(|byte| matches!(byte, 0x21 | 0x23..=0x7e))
}
fn retry_delays(retries: i64) -> impl Iterator<Item = Duration> {
    [200u64, 1_000, 4_000, 15_000]
        .into_iter()
        .chain(std::iter::repeat(15_000))
        .map(Duration::from_millis)
        .map(|duration| {
            let factor = 0.5 + rand::random::<f64>() * 0.5;
            Duration::from_secs_f64(duration.as_secs_f64() * factor)
        })
        .take(retries.max(0) as usize)
}

/// hyper-util exposes DNS failures in the error chain as a `dns error` source,
/// but reqwest intentionally erases the concrete connector type. Match that
/// stable connector error label rather than platform-specific resolver text.
fn is_dns_error(error: &(dyn std::error::Error + 'static)) -> bool {
    let mut current = Some(error);
    while let Some(source) = current {
        if source.to_string() == "dns error" {
            return true;
        }
        current = source.source();
    }
    false
}

/// A failure a backend has identified as worth retrying.
///
/// [`is_transient`] recognizes the statuses that are transient for any HTTP
/// service. A backend that knows one of its own -- S3 answers `409` while a
/// concurrent conditional write to the same key is in flight, and asks that it
/// be retried -- attaches this instead of teaching that function about it.
#[derive(Debug)]
pub(crate) struct TransientRequest(pub(crate) &'static str);

impl std::fmt::Display for TransientRequest {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(self.0)
    }
}

impl std::error::Error for TransientRequest {}

fn is_transient(error: &eyre::Report) -> bool {
    // An unavailable hostname is a deterministic configuration error. reqwest
    // categorizes it as a connect error, but retrying only delays the diagnosis.
    if is_dns_error(error.as_ref()) {
        return false;
    }
    error.chain().any(|source| {
        if source.downcast_ref::<TransientRequest>().is_some() {
            return true;
        }
        let Some(error) = source.downcast_ref::<reqwest::Error>() else {
            return false;
        };
        if error.is_timeout() || error.is_connect() || error.is_body() {
            return true;
        }
        error.status().is_some_and(|status| {
            let status = status.as_u16();
            status == 408 || status == 429 || (500..600).contains(&status)
        })
    })
}

async fn retry_async<F, Fut, T>(verb: &str, url: &Url, retries: i64, mut operation: F) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
{
    let mut delays = retry_delays(retries);
    let mut attempt = 1;
    loop {
        let started_at = Instant::now();
        match operation().await {
            Ok(value) => return Ok(value),
            Err(error) if is_transient(&error) => {
                let Some(delay) = delays.next() else {
                    return Err(error);
                };
                warn!(
                    "HTTP {verb} {url} attempt {attempt} failed after {:?} (transient): {error}; retrying in {delay:?}",
                    started_at.elapsed()
                );
                tokio::time::sleep(delay).await;
                attempt += 1;
            }
            Err(error) => return Err(error),
        }
    }
}
