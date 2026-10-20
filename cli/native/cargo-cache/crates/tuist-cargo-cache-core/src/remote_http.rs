//! The remote cache protocol as spoken to an tuist_cargo_cache cache server over HTTP.
//!
//! This is one of the two backends behind [`crate::RemoteCacheClient`]. It
//! implements the full v1 protocol, including the negotiated blob-pack and
//! batched-lookup extensions that only a protocol server offers.

use crate::{
    ACTION_PROMISE_MEDIA_TYPE, ACTION_RESULT_BATCH_MEDIA_TYPE, ACTION_RESULT_MEDIA_TYPE,
    ActionPromiseCompletion, ActionPromiseJoin, ActionPromiseState, BLOB_MEDIA_TYPE,
    BLOB_PACK_BLOBS_HEADER, BLOB_PACK_BYTES_HEADER, BLOB_PACK_HEADER_BYTES, BLOB_PACK_MAGIC,
    BLOB_PACK_MEDIA_TYPE, BLOB_PACK_RECEIPT_MEDIA_TYPE, BLOB_PACK_TIMEOUT_BYTES_PER_UNIT,
    BLOB_PACK_TIMEOUT_ITEMS_PER_UNIT, BlobPackReceipt, BlobSource, BlobUpload, CacheDigest,
    Capabilities, DIGEST_LIST_MEDIA_TYPE, DigestAlgorithm, MAX_ACTION_BATCH_ITEMS,
    MAX_ACTION_RESULT_BYTES, MAX_REMOTE_BLOB_BYTES, MAX_REMOTE_JSON_BYTES,
    MAX_STAGED_BLOB_PACK_BYTES, MAX_STAGED_BLOB_PACK_ITEMS, ManifestPutOutcome, NAMESPACE_HEADER,
    PACK_STREAM_CHUNK_BYTES, PROTOCOL_HEADER, PROTOCOL_VERSION, RemoteActionManifest,
    RemoteActionResult, RemoteBlobPack, RemoteCacheConfig, TASK_ACTION_MANIFEST_MEDIA_TYPE,
    parse_strong_etag, quoted_etag, read_bounded_json, read_json_within, retry_async,
};
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use eyre::{Result, bail, eyre};
use futures_util::TryStreamExt as _;
use log::warn;
use reqwest::StatusCode;
use reqwest::header::{
    ACCEPT, AUTHORIZATION, CONTENT_ENCODING, CONTENT_LENGTH, CONTENT_TYPE, ETAG, HeaderMap,
    HeaderValue, IF_MATCH, IF_NONE_MATCH,
};
use serde::{Deserialize, Serialize};
use sha2::Digest as _;
use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};
use url::{Host, Url};

const MAX_REMOTE_ERROR_BYTES: usize = 4 * 1024;

struct DownloadedBlobPack {
    directory: tempfile::TempDir,
    blobs: Vec<(CacheDigest, PathBuf)>,
    metadata: BlobPackResponseStats,
}

#[derive(Debug, Clone, Copy, Default)]
struct BlobPackResponseMetadata {
    content_length: Option<u64>,
    blob_count: Option<u64>,
    payload_bytes: Option<u64>,
}

#[derive(Debug, Clone, Copy)]
struct BlobPackResponseStats {
    blob_count: u64,
    payload_bytes: u64,
    framed_bytes: u64,
}

impl BlobPackResponseMetadata {
    fn from_headers(headers: &HeaderMap) -> Result<Self> {
        Ok(Self {
            content_length: optional_u64_header(headers, CONTENT_LENGTH.as_str())?,
            blob_count: optional_u64_header(headers, BLOB_PACK_BLOBS_HEADER)?,
            payload_bytes: optional_u64_header(headers, BLOB_PACK_BYTES_HEADER)?,
        })
    }

    fn validate(self, decoded: BlobPackResponseStats) -> Result<BlobPackResponseStats> {
        if let Some(content_length) = self.content_length
            && content_length != decoded.framed_bytes
        {
            bail!(
                "remote cache blob pack content length metadata mismatch: expected {}, decoded {}",
                content_length,
                decoded.framed_bytes
            );
        }
        if let Some(blob_count) = self.blob_count
            && blob_count != decoded.blob_count
        {
            bail!(
                "remote cache blob pack blob count metadata mismatch: expected {}, decoded {}",
                blob_count,
                decoded.blob_count
            );
        }
        if let Some(payload_bytes) = self.payload_bytes
            && payload_bytes != decoded.payload_bytes
        {
            bail!(
                "remote cache blob pack payload byte metadata mismatch: expected {}, decoded {}",
                payload_bytes,
                decoded.payload_bytes
            );
        }
        Ok(BlobPackResponseStats {
            blob_count: self.blob_count.unwrap_or(decoded.blob_count),
            payload_bytes: self.payload_bytes.unwrap_or(decoded.payload_bytes),
            framed_bytes: self.content_length.unwrap_or(decoded.framed_bytes),
        })
    }
}

fn optional_u64_header(headers: &HeaderMap, name: &str) -> Result<Option<u64>> {
    let Some(value) = headers.get(name) else {
        return Ok(None);
    };
    let value = value
        .to_str()
        .map_err(|_| eyre!("remote cache blob pack {name} header is not valid UTF-8"))?;
    let value = value
        .parse::<u64>()
        .map_err(|_| eyre!("remote cache blob pack {name} header is not an unsigned integer"))?;
    Ok(Some(value))
}

type RemoteCacheCapabilities = Capabilities;

#[derive(Debug, Clone, Copy)]
pub(crate) struct BlobPackLimits {
    pub(crate) max_items: usize,
    pub(crate) max_bytes: u64,
}

/// Largest blob pack sent in one streaming upload.
///
/// Downloads can make progress while the response body arrives, but an upload
/// receives no response progress until the server has consumed its request.
/// Keep one pack comfortably inside the ordinary HTTP inactivity timeout even
/// when a server advertises a multi-gigabyte protocol limit. The upload queue
/// sends independent packs concurrently, so smaller packs also avoid making a
/// single timeout replay hundreds of megabytes.
const MAX_UPLOAD_BLOB_PACK_BYTES: u64 = 64 * 1024 * 1024;

/// What one capabilities exchange settled, cached for the session.
///
/// `Default` is also the answer for a server with no capabilities endpoint:
/// no blob packs and no compression, which is exactly how every request
/// behaved before either feature existed.
#[derive(Debug, Clone, Copy, Default)]
struct NegotiatedCapabilities {
    blob_packs: Option<BlobPackLimits>,
    blob_pack_uploads: Option<BlobPackLimits>,
    action_batches: Option<usize>,
    zstd_uploads: bool,
    action_promises: bool,
}

#[derive(Serialize)]
struct DigestList<'a> {
    digests: &'a [CacheDigest],
}

/// Action results a server holds, in no particular order.
///
/// Deliberately tolerant of fields it does not know, so a later protocol minor
/// can describe more about a batch without this client refusing the response.
/// The records inside stay canonical and exhaustive.
#[derive(Deserialize)]
struct ActionResultBatch {
    #[serde(default)]
    results: Vec<RemoteActionResult>,
}
/// The tuist_cargo_cache remote cache protocol spoken over HTTP.
///
/// The client validates digests, response sizes, media types, and redirects at
/// the protocol boundary. It is safe to share between asynchronous tasks.
pub(crate) struct HttpRemoteCache {
    base_url: Url,
    namespace: String,
    client: reqwest::Client,
    credential: RemoteCacheCredential,
    download_timeout: Duration,
    retries: i64,
    capabilities: tokio::sync::OnceCell<NegotiatedCapabilities>,
    blob_packs_disabled: AtomicBool,
    blob_pack_uploads_disabled: AtomicBool,
    action_batches_disabled: AtomicBool,
    action_promises_disabled: AtomicBool,
    /// Wall clock this session may lose to reads that fail before it stops
    /// asking, and the total lost so far.
    ///
    /// `download_timeout` bounds one logical download. It cannot bound what a
    /// session pays for an unhealthy server, because every object is charged
    /// that deadline again. Reads are best effort — a miss costs a local
    /// compile — so once the losses add up past the budget the session stops
    /// reading and builds instead.
    read_stall_budget: Duration,
    read_stall_nanos: AtomicU64,
    reads_abandoned: AtomicBool,
}

impl HttpRemoteCache {
    pub(crate) fn new(config: RemoteCacheConfig) -> Result<Self> {
        let authenticated = config
            .token
            .as_deref()
            .is_some_and(|token| !token.trim().is_empty())
            || config.token_file.is_some()
            || config
                .oidc_audience
                .as_deref()
                .is_some_and(|audience| !audience.trim().is_empty());
        validate_remote_url(&config.base_url, authenticated)?;
        let client = reqwest::Client::builder()
            .connect_timeout(config.connect_timeout)
            .read_timeout(config.read_timeout)
            .redirect(reqwest::redirect::Policy::none())
            .build()?;
        let credential = remote_credential(&config, client.clone())?;
        Ok(Self {
            base_url: normalized_base_url(config.base_url),
            namespace: config.namespace,
            client,
            credential,
            download_timeout: config.download_timeout,
            retries: config.retries,
            capabilities: tokio::sync::OnceCell::new(),
            blob_packs_disabled: AtomicBool::new(false),
            blob_pack_uploads_disabled: AtomicBool::new(false),
            action_batches_disabled: AtomicBool::new(false),
            action_promises_disabled: AtomicBool::new(false),
            read_stall_budget: Duration::ZERO,
            read_stall_nanos: AtomicU64::new(0),
            reads_abandoned: AtomicBool::new(false),
        })
    }

    /// Set the budget from [`RemoteCacheClient::with_read_stall_budget`].
    pub(crate) fn set_read_stall_budget(&mut self, budget: Duration) {
        self.read_stall_budget = budget;
    }

    /// Whether this session has given up on reading from the remote.
    fn reads_abandoned(&self) -> bool {
        self.reads_abandoned.load(Ordering::Relaxed)
    }

    /// Charge a failed read against the session's stall budget.
    ///
    /// Only failures are charged: a slow read that returns an object paid for
    /// itself, while a slow read that returns nothing is pure loss. Crossing
    /// the budget abandons reads for the rest of the session and says so once.
    fn charge_read_stall(&self, elapsed: Duration) {
        // A zero budget means the operator asked to keep reading no matter how
        // long the remote takes to fail.
        if self.read_stall_budget.is_zero() {
            return;
        }
        let nanos = u64::try_from(elapsed.as_nanos()).unwrap_or(u64::MAX);
        let total = self
            .read_stall_nanos
            .fetch_add(nanos, Ordering::Relaxed)
            .saturating_add(nanos);
        if Duration::from_nanos(total) < self.read_stall_budget {
            return;
        }
        if !self.reads_abandoned.swap(true, Ordering::Relaxed) {
            warn!(
                "remote cache reads gave up after losing {:?} to failed reads, over the {:?} budget; building locally for the rest of this session",
                Duration::from_nanos(total),
                self.read_stall_budget
            );
        }
    }

    pub(crate) async fn check_connection(&self) -> Result<()> {
        self.fetch_capabilities(false).await?;
        Ok(())
    }

    fn action_result_endpoint(&self, action: &CacheDigest) -> Result<Url> {
        action.validate()?;
        if action.algorithm != "blake3" {
            bail!("remote cache action keys must use blake3");
        }
        Ok(self.base_url.join(&format!(
            "v{PROTOCOL_VERSION}/action-results/{}/{}/{}",
            action.algorithm, action.hash, action.size
        ))?)
    }

    fn blob_endpoint(&self, digest: &CacheDigest) -> Result<Url> {
        digest.validate()?;
        Ok(self.base_url.join(&format!(
            "v{PROTOCOL_VERSION}/blobs/{}/{}/{}",
            digest.algorithm, digest.hash, digest.size
        ))?)
    }

    fn action_manifest_endpoint(&self, key: &CacheDigest) -> Result<Url> {
        key.validate()?;
        if key.algorithm != "blake3" {
            bail!("remote action manifest keys must use blake3");
        }
        Ok(self.base_url.join(&format!(
            "v{PROTOCOL_VERSION}/action-manifests/{}/{}/{}",
            key.algorithm, key.hash, key.size
        ))?)
    }

    fn capabilities_endpoint(&self) -> Result<Url> {
        Ok(self
            .base_url
            .join(&format!("v{PROTOCOL_VERSION}/capabilities"))?)
    }

    fn blob_pack_endpoint(&self) -> Result<Url> {
        Ok(self
            .base_url
            .join(&format!("v{PROTOCOL_VERSION}/blobs:pack"))?)
    }

    fn blob_pack_upload_endpoint(&self) -> Result<Url> {
        Ok(self
            .base_url
            .join(&format!("v{PROTOCOL_VERSION}/blobs:pack-upload"))?)
    }

    fn action_result_batch_endpoint(&self) -> Result<Url> {
        Ok(self
            .base_url
            .join(&format!("v{PROTOCOL_VERSION}/action-results:batch"))?)
    }

    fn action_promise_endpoint(&self, invocation: &CacheDigest) -> Result<Url> {
        invocation.validate()?;
        if invocation.algorithm != "blake3" {
            bail!("remote cache invocation keys must use blake3");
        }
        Ok(self.base_url.join(&format!(
            "v{PROTOCOL_VERSION}/action-promises/{}/{}/{}",
            invocation.algorithm, invocation.hash, invocation.size
        ))?)
    }

    async fn request(
        &self,
        method: reqwest::Method,
        url: Url,
        media_type: &'static str,
    ) -> Result<reqwest::RequestBuilder> {
        let request = self
            .client
            .request(method, url)
            .header(PROTOCOL_HEADER, u16::from(PROTOCOL_VERSION))
            .header(NAMESPACE_HEADER, &self.namespace)
            .header(ACCEPT, media_type);
        if let Some(authorization) = self.credential.authorization().await? {
            Ok(request.header(AUTHORIZATION, authorization))
        } else {
            Ok(request)
        }
    }

    pub(crate) async fn blob_pack_limits(&self) -> Result<Option<BlobPackLimits>> {
        Ok(self.negotiated_capabilities().await?.blob_packs)
    }

    async fn negotiated_capabilities(&self) -> Result<NegotiatedCapabilities> {
        self.capabilities
            .get_or_try_init(|| self.fetch_capabilities(true))
            .await
            .copied()
    }

    async fn fetch_capabilities(&self, allow_missing: bool) -> Result<NegotiatedCapabilities> {
        let url = self.capabilities_endpoint()?;
        let response = self
            .request(reqwest::Method::GET, url, "application/json")
            .await?
            .send()
            .await?;
        if allow_missing
            && matches!(
                response.status(),
                StatusCode::NOT_FOUND
                    | StatusCode::METHOD_NOT_ALLOWED
                    | StatusCode::NOT_IMPLEMENTED
            )
        {
            return Ok(NegotiatedCapabilities::default());
        }
        let bytes =
            read_bounded_json(error_for_status_with_body(response).await?, "capabilities").await?;
        let capabilities: RemoteCacheCapabilities = serde_json::from_slice(&bytes)?;
        if capabilities.protocol.major != PROTOCOL_VERSION {
            bail!(
                "remote cache capability protocol {} is incompatible with client protocol {PROTOCOL_VERSION}",
                capabilities.protocol.major
            );
        }
        // Compression is negotiated, never assumed: a body sent with a
        // coding the server did not offer would be stored corrupt or
        // rejected, so absence of the advertisement means identity.
        let zstd_uploads = capabilities
            .compressors
            .iter()
            .any(|compressor| compressor == "zstd");
        let pack_limits = |feature: bool| -> Result<Option<BlobPackLimits>> {
            if !feature {
                return Ok(None);
            }
            let max_items = usize::try_from(capabilities.limits.max_batch_items)
                .ok()
                .filter(|limit| *limit > 0)
                .ok_or_else(|| {
                    eyre!("remote cache blob packs require a positive max_batch_items limit")
                })?;
            if capabilities.limits.max_pack_bytes == 0 {
                bail!("remote cache blob packs require a positive max_pack_bytes limit");
            }
            Ok(Some(BlobPackLimits {
                max_items: max_items.min(MAX_STAGED_BLOB_PACK_ITEMS),
                max_bytes: capabilities
                    .limits
                    .max_pack_bytes
                    .min(MAX_STAGED_BLOB_PACK_BYTES),
            }))
        };
        let blob_packs = pack_limits(capabilities.features.blob_packs)?;
        let blob_pack_uploads =
            pack_limits(capabilities.features.blob_pack_uploads)?.map(|limits| BlobPackLimits {
                max_bytes: limits.max_bytes.min(MAX_UPLOAD_BLOB_PACK_BYTES),
                ..limits
            });
        let action_batches = if capabilities.features.action_batch {
            let max_items = usize::try_from(capabilities.limits.max_batch_items)
                .ok()
                .filter(|limit| *limit > 0)
                .ok_or_else(|| {
                    eyre!("remote cache action batches require a positive max_batch_items limit")
                })?;
            Some(max_items.min(MAX_ACTION_BATCH_ITEMS))
        } else {
            None
        };
        Ok(NegotiatedCapabilities {
            blob_packs,
            blob_pack_uploads,
            action_batches,
            zstd_uploads,
            action_promises: capabilities.features.action_promises,
        })
    }

    pub(crate) async fn join_action_promise(
        &self,
        invocation: &CacheDigest,
        adapter: &str,
    ) -> Result<Option<ActionPromiseState>> {
        if self.action_promises_disabled.load(Ordering::Relaxed)
            || !self.negotiated_capabilities().await?.action_promises
        {
            return Ok(None);
        }
        let url = self.action_promise_endpoint(invocation)?;
        let join = ActionPromiseJoin {
            adapter: adapter.to_string(),
        };
        join.validate()?;
        let body = serde_json::to_vec(&join)?;
        let response = self
            .request(reqwest::Method::POST, url, ACTION_PROMISE_MEDIA_TYPE)
            .await?
            .header(CONTENT_TYPE, ACTION_PROMISE_MEDIA_TYPE)
            .body(body)
            .send()
            .await?;
        if matches!(
            response.status(),
            StatusCode::NOT_FOUND | StatusCode::METHOD_NOT_ALLOWED | StatusCode::NOT_IMPLEMENTED
        ) {
            self.action_promises_disabled.store(true, Ordering::Relaxed);
            return Ok(None);
        }
        let bytes = read_bounded_json(
            error_for_status_with_body(response).await?,
            "action promise",
        )
        .await?;
        let state: ActionPromiseState = serde_json::from_slice(&bytes)?;
        state.validate()?;
        if let ActionPromiseState::Complete { prediction } = &state {
            prediction.validate()?;
            if &prediction.invocation != invocation || prediction.adapter != adapter {
                bail!("remote cache action promise returned an incompatible prediction");
            }
        }
        Ok(Some(state))
    }

    pub(crate) async fn complete_action_promise(
        &self,
        invocation: &CacheDigest,
        completion: &ActionPromiseCompletion,
    ) -> Result<bool> {
        if self.action_promises_disabled.load(Ordering::Relaxed)
            || !self.negotiated_capabilities().await?.action_promises
        {
            return Ok(false);
        }
        completion.validate()?;
        if &completion.prediction.invocation != invocation {
            bail!("remote cache action promise completion names another invocation");
        }
        let url = self.action_promise_endpoint(invocation)?;
        let body = serde_json::to_vec(completion)?;
        let response = self
            .request(reqwest::Method::PUT, url, ACTION_PROMISE_MEDIA_TYPE)
            .await?
            .header(CONTENT_TYPE, ACTION_PROMISE_MEDIA_TYPE)
            .body(body)
            .send()
            .await?;
        if matches!(
            response.status(),
            StatusCode::NOT_FOUND | StatusCode::METHOD_NOT_ALLOWED | StatusCode::NOT_IMPLEMENTED
        ) {
            self.action_promises_disabled.store(true, Ordering::Relaxed);
            return Ok(false);
        }
        error_for_status_with_body(response).await?;
        Ok(true)
    }

    pub(crate) async fn get_blob_pack(
        &self,
        digests: &[CacheDigest],
        staging_dir: &Path,
    ) -> Result<Option<RemoteBlobPack>> {
        self.get_blob_pack_with_limit(digests, staging_dir, MAX_STAGED_BLOB_PACK_BYTES)
            .await
    }

    pub(crate) async fn get_blob_pack_with_limit(
        &self,
        digests: &[CacheDigest],
        staging_dir: &Path,
        max_bytes: u64,
    ) -> Result<Option<RemoteBlobPack>> {
        if digests.is_empty()
            || self.blob_packs_disabled.load(Ordering::Relaxed)
            || self.reads_abandoned()
        {
            return Ok(None);
        }
        let Some(mut limits) = self.blob_pack_limits().await? else {
            return Ok(None);
        };
        limits.max_bytes = limits.max_bytes.min(max_bytes);
        if limits.max_bytes == 0 {
            bail!("remote cache download budget is exhausted");
        }
        fs::create_dir_all(staging_dir)?;
        let chunk = blob_pack_chunk(digests, limits)?;
        if chunk.is_empty() {
            return Ok(Some(RemoteBlobPack {
                _directory: tempfile::tempdir_in(staging_dir)?,
                blobs: Vec::new(),
                requests: 0,
                requested: Vec::new(),
                blob_count: 0,
                payload_bytes: 0,
                framed_bytes: BLOB_PACK_MAGIC.len() as u64,
            }));
        }
        match self.download_blob_pack_chunk(&chunk, staging_dir).await? {
            Some(pack) => Ok(Some(RemoteBlobPack {
                _directory: pack.directory,
                blobs: pack.blobs,
                requests: 1,
                requested: chunk,
                blob_count: pack.metadata.blob_count,
                payload_bytes: pack.metadata.payload_bytes,
                framed_bytes: pack.metadata.framed_bytes,
            })),
            None => {
                self.blob_packs_disabled.store(true, Ordering::Relaxed);
                Ok(None)
            }
        }
    }

    async fn download_blob_pack_chunk(
        &self,
        digests: &[CacheDigest],
        staging_dir: &Path,
    ) -> Result<Option<DownloadedBlobPack>> {
        let url = self.blob_pack_endpoint()?;
        let body = serde_json::to_vec(&DigestList { digests })?;
        let download_timeout = blob_pack_download_timeout(self.download_timeout, digests);
        let download = retry_async("POST", &url, self.retries, || async {
            let response = self
                .request(reqwest::Method::POST, url.clone(), BLOB_PACK_MEDIA_TYPE)
                .await?
                .header(CONTENT_TYPE, DIGEST_LIST_MEDIA_TYPE)
                .body(body.clone())
                .send()
                .await?;
            if matches!(
                response.status(),
                StatusCode::NOT_FOUND
                    | StatusCode::METHOD_NOT_ALLOWED
                    | StatusCode::NOT_IMPLEMENTED
            ) {
                return Ok(None);
            }
            let response = error_for_status_with_body(response).await?;
            let media_type = response
                .headers()
                .get(CONTENT_TYPE)
                .and_then(|value| value.to_str().ok())
                .and_then(|value| value.split(';').next())
                .map(str::trim);
            if media_type != Some(BLOB_PACK_MEDIA_TYPE) {
                bail!("remote cache blob pack has an invalid content type");
            }
            Ok(Some(
                decode_blob_pack(response, digests, staging_dir).await?,
            ))
        });
        // Deliberately outside `retry_async`: `download_timeout` is a deadline
        // for the whole download, not a per-attempt bound. A stalled attempt is
        // already caught by the client's connect and read timeouts.
        let started_at = Instant::now();
        let result = tokio::time::timeout(download_timeout, download)
            .await
            .map_err(|_| {
                eyre!(
                    "remote cache blob pack download for {url} exceeded its {download_timeout:?} budget across all attempts"
                )
            })
            .and_then(|result| result);
        if result.is_err() {
            self.charge_read_stall(started_at.elapsed());
        }
        result
    }

    pub(crate) async fn get_action_result(
        &self,
        action: &CacheDigest,
    ) -> Result<Option<RemoteActionResult>> {
        let url = self.action_result_endpoint(action)?;
        let result = retry_async("GET", &url, self.retries, || async {
            let response = self
                .request(reqwest::Method::GET, url.clone(), ACTION_RESULT_MEDIA_TYPE)
                .await?
                .send()
                .await?;
            if response.status() == StatusCode::NOT_FOUND {
                return Ok(None);
            }
            let bytes =
                read_bounded_json(error_for_status_with_body(response).await?, "action result")
                    .await?;
            Ok(Some(serde_json::from_slice::<RemoteActionResult>(&bytes)?))
        })
        .await?;
        if let Some(result) = &result
            && (result.version != 1 || result.action != *action)
        {
            bail!("remote action result does not match requested action");
        }
        Ok(result)
    }

    pub(crate) async fn action_batch_limit(&self) -> Result<Option<usize>> {
        if self.action_batches_disabled.load(Ordering::Relaxed) {
            return Ok(None);
        }
        Ok(self.negotiated_capabilities().await?.action_batches)
    }

    pub(crate) async fn get_action_results(
        &self,
        actions: &[CacheDigest],
    ) -> Result<Option<Vec<RemoteActionResult>>> {
        if actions.is_empty() {
            return Ok(Some(Vec::new()));
        }
        if self.action_batches_disabled.load(Ordering::Relaxed) {
            return Ok(None);
        }
        let Some(limit) = self.negotiated_capabilities().await?.action_batches else {
            return Ok(None);
        };
        if actions.len() > limit {
            bail!(
                "remote cache action batch of {} exceeds the negotiated limit of {limit}",
                actions.len()
            );
        }
        let mut requested = BTreeSet::new();
        for action in actions {
            action.validate()?;
            if action.algorithm != "blake3" {
                bail!("remote cache action keys must use blake3");
            }
            requested.insert(action.clone());
        }
        let url = self.action_result_batch_endpoint()?;
        let body = serde_json::to_vec(&DigestList { digests: actions })?;
        let bound = MAX_ACTION_RESULT_BYTES.saturating_mul(actions.len() as u64);
        let batch = retry_async("POST", &url, self.retries, || async {
            let response = self
                .request(
                    reqwest::Method::POST,
                    url.clone(),
                    ACTION_RESULT_BATCH_MEDIA_TYPE,
                )
                .await?
                .header(CONTENT_TYPE, DIGEST_LIST_MEDIA_TYPE)
                .body(body.clone())
                .send()
                .await?;
            if matches!(
                response.status(),
                StatusCode::NOT_FOUND
                    | StatusCode::METHOD_NOT_ALLOWED
                    | StatusCode::NOT_IMPLEMENTED
            ) {
                // Advertised but not served. Asking again every wave would cost
                // a round trip each time to learn the same thing.
                self.action_batches_disabled.store(true, Ordering::Relaxed);
                return Ok(None);
            }
            let bytes = read_json_within(
                error_for_status_with_body(response).await?,
                "action result batch",
                bound,
            )
            .await?;
            Ok(Some(serde_json::from_slice::<ActionResultBatch>(&bytes)?))
        })
        .await?;
        let Some(batch) = batch else {
            return Ok(None);
        };
        // A result for an action that was not asked for would key cached outputs
        // under a digest this client never derived, so it is refused rather than
        // ignored.
        let mut seen = BTreeSet::new();
        for result in &batch.results {
            if result.version != 1 || !requested.contains(&result.action) {
                bail!("remote action result batch contains an unrequested action");
            }
            if !seen.insert(result.action.clone()) {
                bail!("remote action result batch repeats an action");
            }
        }
        Ok(Some(batch.results))
    }

    pub(crate) async fn put_action_result(&self, result: &RemoteActionResult) -> Result<()> {
        let url = self.action_result_endpoint(&result.action)?;
        let body = serde_json::to_vec(result)?;
        retry_async("PUT", &url, self.retries, || async {
            let response = self
                .request(reqwest::Method::PUT, url.clone(), ACTION_RESULT_MEDIA_TYPE)
                .await?
                .header(CONTENT_TYPE, ACTION_RESULT_MEDIA_TYPE)
                .header(IF_NONE_MATCH, "*")
                .body(body.clone())
                .send()
                .await?;
            if !matches!(
                response.status(),
                StatusCode::PRECONDITION_FAILED | StatusCode::CONFLICT
            ) {
                error_for_status_with_body(response).await?;
            }
            Ok(())
        })
        .await
    }

    pub(crate) async fn get_action_manifest(
        &self,
        key: &CacheDigest,
    ) -> Result<Option<RemoteActionManifest>> {
        let url = self.action_manifest_endpoint(key)?;
        retry_async("GET", &url, self.retries, || async {
            let response = self
                .request(
                    reqwest::Method::GET,
                    url.clone(),
                    TASK_ACTION_MANIFEST_MEDIA_TYPE,
                )
                .await?
                .send()
                .await?;
            if response.status() == StatusCode::NOT_FOUND {
                return Ok(None);
            }
            let response = error_for_status_with_body(response).await?;
            let etag = parse_strong_etag(response.headers().get(ETAG))?;
            let bytes = read_bounded_json(response, "action manifest").await?;
            Ok(Some(RemoteActionManifest { bytes, etag }))
        })
        .await
    }

    pub(crate) async fn put_action_manifest(
        &self,
        key: &CacheDigest,
        bytes: &[u8],
        expected_etag: Option<&str>,
    ) -> Result<ManifestPutOutcome> {
        let url = self.action_manifest_endpoint(key)?;
        let body = bytes.to_vec();
        let expected_etag = expected_etag.map(quoted_etag).transpose()?;
        retry_async("PUT", &url, self.retries, || async {
            let mut request = self
                .request(
                    reqwest::Method::PUT,
                    url.clone(),
                    TASK_ACTION_MANIFEST_MEDIA_TYPE,
                )
                .await?
                .header(CONTENT_TYPE, TASK_ACTION_MANIFEST_MEDIA_TYPE)
                .body(body.clone());
            request = if let Some(etag) = &expected_etag {
                request.header(IF_MATCH, etag)
            } else {
                request.header(IF_NONE_MATCH, "*")
            };
            let response = request.send().await?;
            if response.status() == StatusCode::PRECONDITION_FAILED {
                return Ok(ManifestPutOutcome::PreconditionFailed);
            }
            error_for_status_with_body(response).await?;
            Ok(ManifestPutOutcome::Stored)
        })
        .await
    }

    pub(crate) async fn get_blob(
        &self,
        digest: &CacheDigest,
        media_type: &'static str,
    ) -> Result<Vec<u8>> {
        digest.validate()?;
        if digest.size > MAX_REMOTE_JSON_BYTES {
            bail!(
                "remote cache in-memory blob declared {} bytes, over the {} byte limit",
                digest.size,
                MAX_REMOTE_JSON_BYTES
            );
        }
        let url = self.blob_endpoint(digest)?;
        retry_async("GET", &url, self.retries, || async {
            let response = self
                .request(reqwest::Method::GET, url.clone(), media_type)
                .await?
                .send()
                .await?;
            let mut response = error_for_status_with_body(response).await?;
            // Stop reading as soon as the response outgrows the digest it claims
            // to satisfy. A server that streams more than it promised must not be
            // able to exhaust this process before verification rejects it.
            let mut bytes = Vec::new();
            while let Some(chunk) = response.chunk().await? {
                if bytes.len() as u64 + chunk.len() as u64 > digest.size {
                    bail!("remote cache blob exceeded the size of its digest");
                }
                bytes.extend_from_slice(&chunk);
            }
            if !digest.matches_bytes(&bytes)? {
                bail!("remote cache blob failed digest verification");
            }
            Ok(bytes)
        })
        .await
    }

    pub(crate) async fn get_blob_file(
        &self,
        digest: &CacheDigest,
        staging_dir: &Path,
    ) -> Result<tempfile::NamedTempFile> {
        digest.validate()?;
        if self.reads_abandoned() {
            bail!("remote cache reads were abandoned for this session");
        }
        if digest.size > MAX_REMOTE_BLOB_BYTES {
            bail!(
                "remote cache blob declared {} bytes, over the {} byte limit",
                digest.size,
                MAX_REMOTE_BLOB_BYTES
            );
        }
        let url = self.blob_endpoint(digest)?;
        let download = retry_async("GET", &url, self.retries, || async {
            let response = self
                .request(reqwest::Method::GET, url.clone(), BLOB_MEDIA_TYPE)
                .await?
                .send()
                .await?;
            let mut response = error_for_status_with_body(response).await?;
            fs::create_dir_all(staging_dir)?;
            let temporary = tempfile::NamedTempFile::new_in(staging_dir)?;
            let mut output = tokio::fs::File::from_std(temporary.reopen()?);
            // Bound the download by the digest's own size so an oversized
            // response cannot fill the disk before verification rejects it.
            let mut written = 0u64;
            while let Some(chunk) = response.chunk().await? {
                written += chunk.len() as u64;
                if written > digest.size {
                    bail!("remote cache blob exceeded the size of its digest");
                }
                output.write_all(&chunk).await?;
            }
            output.flush().await?;
            drop(output);
            if !digest.matches_file(temporary.path())? {
                bail!("remote cache blob failed digest verification");
            }
            Ok(temporary)
        });
        let download_timeout = self.download_timeout;
        // Deliberately outside `retry_async`: `download_timeout` is a deadline
        // for the whole download, not a per-attempt bound. A stalled attempt is
        // already caught by the client's connect and read timeouts.
        let started_at = Instant::now();
        let result = tokio::time::timeout(download_timeout, download)
            .await
            .map_err(|_| {
                eyre!(
                    "remote cache blob download for {url} exceeded its {download_timeout:?} budget across all attempts"
                )
            })
            .and_then(|result| result);
        if result.is_err() {
            self.charge_read_stall(started_at.elapsed());
        }
        result
    }

    pub(crate) async fn blob_pack_upload_limits(&self) -> Result<Option<BlobPackLimits>> {
        if self.blob_pack_uploads_disabled.load(Ordering::Relaxed) {
            return Ok(None);
        }
        Ok(self.negotiated_capabilities().await?.blob_pack_uploads)
    }

    pub(crate) async fn put_blob_pack(
        &self,
        uploads: &[BlobUpload],
    ) -> Result<Option<BlobPackReceipt>> {
        if uploads.is_empty() {
            return Ok(Some(BlobPackReceipt {
                created: 0,
                existing: 0,
            }));
        }
        let Some(limits) = self.blob_pack_upload_limits().await? else {
            return Ok(None);
        };
        if uploads.len() > limits.max_items {
            bail!(
                "remote cache blob pack of {} blobs exceeds the negotiated limit of {}",
                uploads.len(),
                limits.max_items
            );
        }
        let mut payload_bytes = 0u64;
        for upload in uploads {
            upload.digest.validate()?;
            payload_bytes = payload_bytes
                .checked_add(upload.digest.size)
                .ok_or_else(|| eyre!("remote cache blob pack payload overflowed"))?;
        }
        if payload_bytes > limits.max_bytes {
            bail!(
                "remote cache blob pack of {payload_bytes} bytes exceeds the negotiated limit of {}",
                limits.max_bytes
            );
        }
        let framed_bytes = BLOB_PACK_MAGIC.len() as u64
            + payload_bytes
            + BLOB_PACK_HEADER_BYTES * uploads.len() as u64;
        let compress = self
            .negotiated_capabilities()
            .await
            .map(|capabilities| capabilities.zstd_uploads)
            .unwrap_or(false);
        let url = self.blob_pack_upload_endpoint()?;
        retry_async("POST", &url, self.retries, || async {
            let request = self
                .request(
                    reqwest::Method::POST,
                    url.clone(),
                    BLOB_PACK_RECEIPT_MEDIA_TYPE,
                )
                .await?
                .header(CONTENT_TYPE, BLOB_PACK_MEDIA_TYPE)
                .header(BLOB_PACK_BLOBS_HEADER, uploads.len())
                .header(BLOB_PACK_BYTES_HEADER, payload_bytes);
            // Each attempt reads the sources again, so the pack is rebuilt here
            // rather than buffered once and held in memory.
            let stream = blob_pack_stream(blob_pack_members(uploads)?);
            let request = if compress {
                let encoder = async_compression::tokio::bufread::ZstdEncoder::new(
                    tokio::io::BufReader::new(tokio_util::io::StreamReader::new(stream)),
                );
                request
                    .header(CONTENT_ENCODING, "zstd")
                    .body(reqwest::Body::wrap_stream(
                        tokio_util::io::ReaderStream::new(encoder),
                    ))
            } else {
                request
                    .header(CONTENT_LENGTH, framed_bytes)
                    .body(reqwest::Body::wrap_stream(stream))
            };
            let response = request.send().await?;
            if matches!(
                response.status(),
                StatusCode::NOT_FOUND
                    | StatusCode::METHOD_NOT_ALLOWED
                    | StatusCode::NOT_IMPLEMENTED
            ) {
                self.blob_pack_uploads_disabled
                    .store(true, Ordering::Relaxed);
                return Ok(None);
            }
            let bytes = read_bounded_json(
                error_for_status_with_body(response).await?,
                "blob pack receipt",
            )
            .await?;
            Ok(Some(serde_json::from_slice::<BlobPackReceipt>(&bytes)?))
        })
        .await
    }

    pub(crate) async fn put_blob(&self, upload: &BlobUpload) -> Result<()> {
        let url = self.blob_endpoint(&upload.digest)?;
        // A failed negotiation downgrades to identity rather than failing the
        // upload: compression is an economy, not a requirement.
        let compress = self
            .negotiated_capabilities()
            .await
            .map(|capabilities| capabilities.zstd_uploads)
            .unwrap_or(false);
        retry_async("PUT", &url, self.retries, || async {
            let request = self
                .request(reqwest::Method::PUT, url.clone(), BLOB_MEDIA_TYPE)
                .await?
                .header(CONTENT_TYPE, BLOB_MEDIA_TYPE)
                .header(IF_NONE_MATCH, "*");
            let request = if compress {
                // Compressed and therefore chunked: the length of the encoded
                // stream is not known up front, and the digest already tells
                // the server the decompressed size it must enforce.
                let reader: Box<dyn tokio::io::AsyncRead + Send + Sync + Unpin> = match &upload
                    .source
                {
                    BlobSource::Bytes(bytes) => Box::new(std::io::Cursor::new(bytes.clone())),
                    BlobSource::File(file) => Box::new(tokio::fs::File::open(file.path()).await?),
                    BlobSource::Path(path) => Box::new(tokio::fs::File::open(path).await?),
                };
                let encoder = async_compression::tokio::bufread::ZstdEncoder::new(
                    tokio::io::BufReader::new(reader),
                );
                request
                    .header(CONTENT_ENCODING, "zstd")
                    .body(reqwest::Body::wrap_stream(
                        tokio_util::io::ReaderStream::new(encoder),
                    ))
            } else {
                let (length, body) = match &upload.source {
                    BlobSource::Bytes(bytes) => {
                        (bytes.len() as u64, reqwest::Body::from(bytes.clone()))
                    }
                    BlobSource::File(file) => {
                        let file = tokio::fs::File::open(file.path()).await?;
                        let length = file.metadata().await?.len();
                        let stream = tokio_util::io::ReaderStream::new(file);
                        (length, reqwest::Body::wrap_stream(stream))
                    }
                    BlobSource::Path(path) => {
                        let file = tokio::fs::File::open(path).await?;
                        let length = file.metadata().await?.len();
                        let stream = tokio_util::io::ReaderStream::new(file);
                        (length, reqwest::Body::wrap_stream(stream))
                    }
                };
                request.header(CONTENT_LENGTH, length).body(body)
            };
            let response = request.send().await?;
            if response.status() != StatusCode::PRECONDITION_FAILED {
                error_for_status_with_body(response).await?;
            }
            Ok(())
        })
        .await
    }
}

/// Preserve a failed request's status for retry classification while adding a
/// bounded, log-safe version of the server's explanation to the error.
async fn error_for_status_with_body(mut response: reqwest::Response) -> Result<reqwest::Response> {
    let Err(status_error) = response.error_for_status_ref() else {
        return Ok(response);
    };
    let mut body = Vec::new();
    let mut truncated = false;
    loop {
        // This body is only diagnostic. If reading it fails, keep the HTTP
        // status as the authoritative error and any detail already received.
        let chunk = match response.chunk().await {
            Ok(Some(chunk)) => chunk,
            Ok(None) | Err(_) => break,
        };
        let remaining = MAX_REMOTE_ERROR_BYTES.saturating_sub(body.len());
        if chunk.len() > remaining {
            body.extend_from_slice(&chunk[..remaining]);
            truncated = true;
            break;
        }
        body.extend_from_slice(&chunk);
    }
    let body = String::from_utf8_lossy(&body);
    let detail = body
        .chars()
        .map(|character| {
            if character.is_control() {
                ' '
            } else {
                character
            }
        })
        .collect::<String>();
    let detail = detail.trim();
    if detail.is_empty() {
        return Err(status_error.into());
    }
    let suffix = if truncated { " (truncated)" } else { "" };
    let message = format!("{status_error}: remote cache server response: {detail}{suffix}");
    Err(eyre::Report::new(status_error).wrap_err(message))
}

pub(crate) fn blob_pack_chunk<'a>(
    digests: impl IntoIterator<Item = &'a CacheDigest>,
    limits: BlobPackLimits,
) -> Result<Vec<CacheDigest>> {
    let mut seen = BTreeSet::new();
    let mut chunk = Vec::new();
    let mut chunk_bytes = 0_u64;
    for digest in digests {
        digest.validate()?;
        if !seen.insert(digest) || digest.size > limits.max_bytes {
            continue;
        }
        if chunk.len() == limits.max_items
            || chunk_bytes.saturating_add(digest.size) > limits.max_bytes
        {
            break;
        }
        chunk_bytes = chunk_bytes.saturating_add(digest.size);
        chunk.push(digest.clone());
    }
    Ok(chunk)
}

/// Scale the configured download deadline by the work a pack declares.
///
/// The deadline covers the whole download, retries included, so one request
/// carrying many megabytes or thousands of objects needs a proportionally
/// larger budget than the single blob the configured value is written for.
fn blob_pack_download_timeout(base: Duration, digests: &[CacheDigest]) -> Duration {
    let bytes = digests
        .iter()
        .fold(0_u64, |total, digest| total.saturating_add(digest.size));
    let byte_units = bytes.div_ceil(BLOB_PACK_TIMEOUT_BYTES_PER_UNIT);
    let item_units = digests.len().div_ceil(BLOB_PACK_TIMEOUT_ITEMS_PER_UNIT);
    let item_units = u64::try_from(item_units).unwrap_or(u64::MAX);
    let multiplier = byte_units.max(item_units).max(1);
    base.saturating_mul(u32::try_from(multiplier).unwrap_or(u32::MAX))
}
/// One member of a pack, described rather than opened.
///
/// A pack can hold thousands of objects. Opening them all before the first byte
/// is sent would spend a file descriptor on each for the length of the request,
/// so a member is opened only when the stream reaches it and closed when it is
/// past.
struct PackMemberSource {
    header: Vec<u8>,
    payload_bytes: u64,
    source: PackPayloadSource,
}

enum PackPayloadSource {
    Bytes(Vec<u8>),
    Path(PathBuf),
}

enum PackStreamState {
    Magic,
    Header(usize),
    Payload(usize, u64, Box<dyn AsyncRead + Send + Sync + Unpin>),
    Done,
}

/// Frame blobs into one `TUISTPK1` stream, read on demand rather than buffered.
///
/// The frames mirror what [`decode_blob_pack_reader`] accepts, so both
/// directions of the extension agree on the format by construction.
fn blob_pack_stream(
    members: Vec<PackMemberSource>,
) -> impl futures_util::Stream<Item = std::io::Result<bytes::Bytes>> + Send + 'static {
    futures_util::stream::unfold(
        (PackStreamState::Magic, members),
        |(state, members)| async move {
            let mut state = state;
            loop {
                match state {
                    PackStreamState::Magic => {
                        return Some((
                            Ok(bytes::Bytes::from_static(BLOB_PACK_MAGIC)),
                            (PackStreamState::Header(0), members),
                        ));
                    }
                    PackStreamState::Header(index) => {
                        let Some(member) = members.get(index) else {
                            state = PackStreamState::Done;
                            continue;
                        };
                        let payload: Box<dyn AsyncRead + Send + Sync + Unpin> = match &member.source
                        {
                            PackPayloadSource::Bytes(bytes) => {
                                Box::new(std::io::Cursor::new(bytes.clone()))
                            }
                            PackPayloadSource::Path(path) => {
                                match tokio::fs::File::open(path).await {
                                    Ok(file) => Box::new(file),
                                    Err(error) => {
                                        return Some((
                                            Err(error),
                                            (PackStreamState::Done, members),
                                        ));
                                    }
                                }
                            }
                        };
                        return Some((
                            Ok(bytes::Bytes::from(member.header.clone())),
                            (
                                PackStreamState::Payload(index, member.payload_bytes, payload),
                                members,
                            ),
                        ));
                    }
                    PackStreamState::Payload(index, remaining, mut payload) => {
                        if remaining == 0 {
                            // The declared frame length, rather than EOF, is the
                            // boundary between adjacent members.
                            state = PackStreamState::Header(index + 1);
                            continue;
                        }
                        let chunk_bytes =
                            usize::try_from(remaining.min(PACK_STREAM_CHUNK_BYTES as u64)).unwrap();
                        let mut chunk = vec![0; chunk_bytes];
                        match payload.read(&mut chunk).await {
                            Ok(0) => {
                                let error = std::io::Error::new(
                                    std::io::ErrorKind::UnexpectedEof,
                                    format!(
                                        "blob pack member {index} ended with {remaining} bytes remaining"
                                    ),
                                );
                                return Some((Err(error), (PackStreamState::Done, members)));
                            }
                            Ok(read) => {
                                chunk.truncate(read);
                                return Some((
                                    Ok(bytes::Bytes::from(chunk)),
                                    (
                                        PackStreamState::Payload(
                                            index,
                                            remaining - read as u64,
                                            payload,
                                        ),
                                        members,
                                    ),
                                ));
                            }
                            Err(error) => {
                                return Some((Err(error), (PackStreamState::Done, members)));
                            }
                        }
                    }
                    PackStreamState::Done => return None,
                }
            }
        },
    )
}

fn blob_pack_members(uploads: &[BlobUpload]) -> Result<Vec<PackMemberSource>> {
    uploads
        .iter()
        .map(|upload| {
            Ok(PackMemberSource {
                header: blob_pack_frame_header(&upload.digest)?,
                payload_bytes: upload.digest.size,
                source: match &upload.source {
                    BlobSource::Bytes(bytes) => PackPayloadSource::Bytes(bytes.clone()),
                    BlobSource::File(file) => PackPayloadSource::Path(file.path().to_path_buf()),
                    BlobSource::Path(path) => PackPayloadSource::Path(path.clone()),
                },
            })
        })
        .collect()
}

fn blob_pack_frame_header(digest: &CacheDigest) -> Result<Vec<u8>> {
    let algorithm = match digest.algorithm_kind()? {
        DigestAlgorithm::Blake3 => 1u8,
        DigestAlgorithm::Sha256 => 2u8,
    };
    let hash = hex::decode(&digest.hash)?;
    if hash.len() != 32 {
        bail!("remote cache blob pack digests must be 32 bytes");
    }
    let mut header = Vec::with_capacity(BLOB_PACK_HEADER_BYTES as usize);
    header.push(algorithm);
    header.extend_from_slice(&hash);
    header.extend_from_slice(&digest.size.to_be_bytes());
    Ok(header)
}

async fn decode_blob_pack(
    response: reqwest::Response,
    requested: &[CacheDigest],
    staging_dir: &Path,
) -> Result<DownloadedBlobPack> {
    let metadata = BlobPackResponseMetadata::from_headers(response.headers())?;
    let stream = response.bytes_stream().map_err(std::io::Error::other);
    let reader = tokio_util::io::StreamReader::new(stream);
    decode_blob_pack_reader(reader, metadata, requested, staging_dir).await
}

async fn decode_blob_pack_reader<R>(
    mut reader: R,
    metadata: BlobPackResponseMetadata,
    requested: &[CacheDigest],
    staging_dir: &Path,
) -> Result<DownloadedBlobPack>
where
    R: AsyncRead + Unpin,
{
    let requested = requested.iter().cloned().collect::<BTreeSet<_>>();
    let mut magic = [0_u8; BLOB_PACK_MAGIC.len()];
    reader.read_exact(&mut magic).await?;
    if &magic != BLOB_PACK_MAGIC {
        bail!("remote cache blob pack has invalid magic");
    }

    let directory = tempfile::tempdir_in(staging_dir)?;
    let mut seen = BTreeSet::new();
    let mut blobs = Vec::new();
    let mut payload_bytes = 0_u64;
    let mut framed_bytes = BLOB_PACK_MAGIC.len() as u64;
    loop {
        let mut algorithm = [0_u8; 1];
        if reader.read(&mut algorithm).await? == 0 {
            break;
        }
        let (algorithm, mut hasher) = match algorithm[0] {
            1 => (
                "blake3",
                BlobPackHasher::Blake3(Box::new(blake3::Hasher::new())),
            ),
            2 => ("sha256", BlobPackHasher::Sha256(sha2::Sha256::new())),
            _ => bail!("remote cache blob pack has an invalid digest algorithm"),
        };
        let mut hash = [0_u8; 32];
        reader.read_exact(&mut hash).await?;
        let mut size = [0_u8; 8];
        reader.read_exact(&mut size).await?;
        let digest = CacheDigest {
            algorithm: algorithm.into(),
            hash: hex::encode(hash),
            size: u64::from_be_bytes(size),
        };
        if !requested.contains(&digest) {
            bail!("remote cache blob pack returned an unrequested digest");
        }
        if !seen.insert(digest.clone()) {
            bail!("remote cache blob pack returned a duplicate digest");
        }
        framed_bytes = framed_bytes
            .checked_add(BLOB_PACK_HEADER_BYTES)
            .and_then(|bytes| bytes.checked_add(digest.size))
            .ok_or_else(|| eyre!("remote cache blob pack is too large"))?;
        payload_bytes = payload_bytes
            .checked_add(digest.size)
            .ok_or_else(|| eyre!("remote cache blob pack payload is too large"))?;

        let path = directory.path().join(blobs.len().to_string());
        let mut output = tokio::fs::File::create(&path).await?;
        let mut remaining = digest.size;
        let mut buffer = [0_u8; 64 * 1024];
        while remaining > 0 {
            let limit = usize::try_from(remaining.min(buffer.len() as u64)).unwrap();
            let count = reader.read(&mut buffer[..limit]).await?;
            if count == 0 {
                bail!("remote cache blob pack ended before a blob was complete");
            }
            output.write_all(&buffer[..count]).await?;
            hasher.update(&buffer[..count]);
            remaining -= count as u64;
        }
        output.flush().await?;
        drop(output);
        if !hasher.matches(&digest.hash) {
            bail!("remote cache blob pack failed digest verification");
        }
        blobs.push((digest, path));
    }
    let blob_count = blobs.len().try_into().unwrap_or(u64::MAX);
    let metadata = metadata.validate(BlobPackResponseStats {
        blob_count,
        payload_bytes,
        framed_bytes,
    })?;
    Ok(DownloadedBlobPack {
        directory,
        blobs,
        metadata,
    })
}

/// Exercise the production blob-pack decoder without constructing an HTTP
/// response. This narrow entry point exists for the workspace's fuzz target.
#[cfg(feature = "fuzzing")]
#[doc(hidden)]
pub async fn fuzz_decode_blob_pack(
    bytes: &[u8],
    requested: &[CacheDigest],
    staging_dir: &Path,
) -> Result<()> {
    decode_blob_pack_reader(
        bytes,
        BlobPackResponseMetadata::default(),
        requested,
        staging_dir,
    )
    .await
    .map(drop)
}

enum BlobPackHasher {
    Blake3(Box<blake3::Hasher>),
    Sha256(sha2::Sha256),
}

impl BlobPackHasher {
    fn update(&mut self, bytes: &[u8]) {
        match self {
            Self::Blake3(hasher) => {
                hasher.update(bytes);
            }
            Self::Sha256(hasher) => {
                hasher.update(bytes);
            }
        }
    }

    fn matches(self, expected: &str) -> bool {
        match self {
            Self::Blake3(hasher) => hasher.finalize().to_hex().as_str() == expected,
            Self::Sha256(hasher) => hex::encode(hasher.finalize()) == expected,
        }
    }
}
#[derive(Clone)]
enum RemoteCacheCredential {
    None,
    Static(HeaderValue),
    File(PathBuf),
    GithubActions(Arc<GithubActionsOidcCredential>),
}

struct GithubActionsOidcCredential {
    audience: String,
    request_url: Url,
    request_token: HeaderValue,
    client: reqwest::Client,
    retries: i64,
    cached: tokio::sync::Mutex<Option<CachedOidcToken>>,
}

struct CachedOidcToken {
    authorization: HeaderValue,
    expires_at: u64,
}

#[derive(Deserialize)]
struct GithubActionsOidcResponse {
    value: String,
}

#[derive(Deserialize)]
struct JwtExpiry {
    exp: u64,
}

fn remote_credential(
    config: &RemoteCacheConfig,
    client: reqwest::Client,
) -> Result<RemoteCacheCredential> {
    if let Some(authorization) = authorization_header(config.token.as_deref())? {
        return Ok(RemoteCacheCredential::Static(authorization));
    }
    if let Some(path) = &config.token_file {
        return Ok(RemoteCacheCredential::File(path.clone()));
    }
    let Some(audience) = config
        .oidc_audience
        .as_deref()
        .map(str::trim)
        .filter(|audience| !audience.is_empty())
    else {
        return Ok(RemoteCacheCredential::None);
    };
    Ok(RemoteCacheCredential::GithubActions(Arc::new(
        GithubActionsOidcCredential::from_env(audience, client, config.retries)?,
    )))
}

fn authorization_header(token: Option<&str>) -> Result<Option<HeaderValue>> {
    let Some(token) = token.map(str::trim).filter(|token| !token.is_empty()) else {
        return Ok(None);
    };
    let mut value = HeaderValue::from_str(&format!("Bearer {token}"))?;
    value.set_sensitive(true);
    Ok(Some(value))
}

impl RemoteCacheCredential {
    async fn authorization(&self) -> Result<Option<HeaderValue>> {
        match self {
            Self::None => Ok(None),
            Self::Static(value) => Ok(Some(value.clone())),
            Self::File(path) => {
                let token = tokio::fs::read_to_string(path).await.map_err(|err| {
                    eyre!(
                        "failed to read remote cache token file {}: {err}",
                        path.display()
                    )
                })?;
                authorization_header(Some(&token))?
                    .ok_or_else(|| eyre!("remote cache token file {} is empty", path.display()))
                    .map(Some)
            }
            Self::GithubActions(credential) => credential.authorization().await.map(Some),
        }
    }
}

impl GithubActionsOidcCredential {
    fn from_env(audience: &str, client: reqwest::Client, retries: i64) -> Result<Self> {
        let request_url = std::env::var("ACTIONS_ID_TOKEN_REQUEST_URL").map_err(|_| {
            eyre!(
                "remote cache OIDC audience requires GitHub Actions OIDC; \
                 grant `id-token: write` or set TUIST_CARGO_CACHE_REMOTE_TOKEN"
            )
        })?;
        let request_token = std::env::var("ACTIONS_ID_TOKEN_REQUEST_TOKEN").map_err(|_| {
            eyre!(
                "remote cache OIDC audience requires GitHub Actions OIDC; \
                 ACTIONS_ID_TOKEN_REQUEST_TOKEN is missing"
            )
        })?;
        let request_url: Url = request_url
            .parse()
            .map_err(|err| eyre!("invalid GitHub Actions OIDC request URL: {err}"))?;
        Self::new(audience, request_url, &request_token, client, retries)
    }

    fn new(
        audience: &str,
        mut request_url: Url,
        request_token: &str,
        client: reqwest::Client,
        retries: i64,
    ) -> Result<Self> {
        validate_oidc_request_url(&request_url)?;
        let query = request_url
            .query_pairs()
            .filter(|(key, _)| key != "audience")
            .map(|(key, value)| (key.into_owned(), value.into_owned()))
            .collect::<Vec<_>>();
        request_url.set_query(None);
        request_url
            .query_pairs_mut()
            .extend_pairs(query)
            .append_pair("audience", audience);
        let request_token = authorization_header(Some(request_token))?
            .ok_or_else(|| eyre!("GitHub Actions OIDC request token is empty"))?;
        Ok(Self {
            audience: audience.to_string(),
            request_url,
            request_token,
            client,
            retries,
            cached: tokio::sync::Mutex::new(None),
        })
    }

    async fn authorization(&self) -> Result<HeaderValue> {
        const REFRESH_LEEWAY_SECONDS: u64 = 60;
        let mut cached = self.cached.lock().await;
        let now = unix_timestamp()?;
        if let Some(token) = cached.as_ref()
            && token.expires_at > now.saturating_add(REFRESH_LEEWAY_SECONDS)
        {
            return Ok(token.authorization.clone());
        }
        let response: GithubActionsOidcResponse =
            retry_async("GET", &self.request_url, self.retries, || async {
                Ok(self
                    .client
                    .get(self.request_url.clone())
                    .header(AUTHORIZATION, self.request_token.clone())
                    .send()
                    .await?
                    .error_for_status()?
                    .json()
                    .await?)
            })
            .await
            .map_err(|err| {
                eyre!(
                    "failed to acquire GitHub Actions OIDC token for audience {:?}: {err}",
                    self.audience
                )
            })?;
        let expires_at = jwt_expiry(&response.value)?;
        if expires_at <= now.saturating_add(REFRESH_LEEWAY_SECONDS) {
            bail!("GitHub Actions OIDC token expires too soon");
        }
        let authorization = authorization_header(Some(&response.value))?
            .ok_or_else(|| eyre!("GitHub Actions returned an empty OIDC token"))?;
        *cached = Some(CachedOidcToken {
            authorization: authorization.clone(),
            expires_at,
        });
        Ok(authorization)
    }
}

fn jwt_expiry(token: &str) -> Result<u64> {
    let payload = token
        .split('.')
        .nth(1)
        .ok_or_else(|| eyre!("GitHub Actions returned a malformed OIDC token"))?;
    let payload = URL_SAFE_NO_PAD
        .decode(payload)
        .map_err(|_| eyre!("GitHub Actions returned a malformed OIDC token"))?;
    let claims: JwtExpiry = serde_json::from_slice(&payload)
        .map_err(|_| eyre!("GitHub Actions OIDC token is missing a valid expiry"))?;
    Ok(claims.exp)
}

fn unix_timestamp() -> Result<u64> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|err| eyre!("system clock is before the Unix epoch: {err}"))?
        .as_secs())
}

fn validate_oidc_request_url(url: &Url) -> Result<()> {
    if url.scheme() == "https"
        || url.scheme() == "http"
            && url.host().is_some_and(|host| match host {
                Host::Domain(host) => host.eq_ignore_ascii_case("localhost"),
                Host::Ipv4(address) => address.is_loopback(),
                Host::Ipv6(address) => address.is_loopback(),
            })
    {
        Ok(())
    } else {
        bail!("GitHub Actions OIDC request URL must use HTTPS")
    }
}
fn validate_remote_url(base_url: &Url, authenticated: bool) -> Result<()> {
    if base_url.scheme() == "https" {
        return Ok(());
    }
    if base_url.scheme() != "http" {
        bail!("remote cache URL must use HTTPS");
    }
    let is_loopback = base_url.host().is_some_and(|host| match host {
        Host::Domain(host) => host.eq_ignore_ascii_case("localhost"),
        Host::Ipv4(address) => address.is_loopback(),
        Host::Ipv6(address) => address.is_loopback(),
    });
    if !is_loopback && authenticated {
        bail!("remote cache URL must use HTTPS except for loopback development servers");
    }
    if !is_loopback {
        warn!(
            "using an unauthenticated remote build cache over plain HTTP; cache traffic can be read \
             or modified in transit"
        );
    }
    Ok(())
}

fn normalized_base_url(mut url: Url) -> Url {
    if !url.path().ends_with('/') {
        url.set_path(&format!("{}/", url.path()));
    }
    url
}

#[cfg(test)]
#[path = "core_tests.rs"]
mod tests;
