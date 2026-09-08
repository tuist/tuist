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
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::time::{Duration, Instant};

pub use bazel_remote_apis::build::bazel::remote::execution::v2::Digest;
use bazel_remote_apis::build::bazel::remote::execution::v2::{
    self as reapi, action_cache_client::ActionCacheClient, batch_update_blobs_request,
    capabilities_client::CapabilitiesClient,
    content_addressable_storage_client::ContentAddressableStorageClient,
};
use futures_util::{stream, StreamExt};
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

pub struct Node {
    pub refs: Vec<Vec<u8>>,
    pub data: Vec<u8>,
}

/// One node of a value graph as it travels: the llcas digest identifies it to
/// the local CAS, the REAPI digest identifies its frame blob remotely.
#[derive(Clone, PartialEq)]
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
const MAX_CHUNK_REQUESTS: usize = 8;
// Generous because it is a per-RPC ceiling, not the dead-link detector (h2
// keepalive reaps dead connections in ~30s regardless): the snapshot fetch
// legitimately carries tens of MB in one unary response — measured 40s for
// 48MiB over a WAN link — and a 60s cap made slower links fail it
// systematically.
const RPC_TIMEOUT: Duration = Duration::from_secs(180);
const ATTEMPTS: usize = 3;
// How many times `batch_read` re-requests the subset of blobs a `BatchReadBlobs`
// call returned with a retryable per-blob status. This is a separate budget from
// `ATTEMPTS`: that one retries the RPC itself, which succeeds here -- the
// rejection rides on each response entry, so the RPC-level retry never sees it.
const BLOB_STATUS_ATTEMPTS: usize = 3;
// After a `batch_read` exhausts its per-blob retries with blobs still declined,
// how long the same `Remote` fails fast (no retries) instead. Long enough that a
// build's thousands of reads against a deterministically-pressured node don't
// each pay the retry ladder and pile read load onto it; short enough to re-probe
// for recovery several times within one build.
const PRESSURE_BACKOFF_MS: u64 = 30_000;
// The same idea for the PUBLICATION write path, which had no equivalent: every
// publication paid `retry_call`'s full ladder on every shed, and that ladder
// sleeps 200ms. A build publishing thousands of keys against a node shedding
// writes therefore spent hundreds of milliseconds per publication asleep in a
// publisher thread -- invisible in wall clock, because publications are
// background work, and visible only as `write_duration` in the build report.
//
// Shorter than the read window because a publication's retry is not a caller
// blocking on it, it is the proxy's 10s sweep: at 5s every sweep re-probes, so
// a node that recovers is picked up on the next one rather than waited out.
const WRITE_PRESSURE_BACKOFF_MS: u64 = 5_000;

pub(crate) fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as u64)
        .unwrap_or(0)
}

/// Delay between retries: the first retry is immediate -- the dominant
/// retryable condition is kura's graceful GOAWAY rotation, where re-issuing
/// on a fresh connection succeeds right away -- while later retries back off
/// so many concurrent fetches don't hammer a node that is genuinely
/// struggling.
const RETRY_BACKOFF: Duration = Duration::from_millis(200);

/// Retries a synchronous gRPC call up to `ATTEMPTS` times on retryable statuses,
/// keeping the retry policy in one place. The caller maps success and terminal
/// errors (e.g. NotFound) at the call site.
fn retry_call<T>(mut op: impl FnMut() -> Result<T, tonic::Status>) -> Result<T, tonic::Status> {
    let mut last = None;
    for attempt in 0..ATTEMPTS {
        if attempt > 1 {
            std::thread::sleep(RETRY_BACKOFF * (attempt - 1) as u32);
        }
        match op() {
            Ok(value) => return Ok(value),
            Err(status) if retryable(&status) && attempt + 1 < ATTEMPTS => last = Some(status),
            Err(status) => return Err(status),
        }
    }
    Err(last.unwrap_or_else(|| tonic::Status::unknown("retry attempts exhausted")))
}

/// `retry_call` for a publication's write RPCs, with the ladder gated on a
/// per-`Remote` breaker.
///
/// The ladder exists for a node that is briefly unavailable. It is the wrong
/// answer for one that is deliberately shedding writes under load: the sleep
/// buys nothing (the outbox is full for as long as it is full), it costs a
/// publisher thread 200ms it could have spent on a publication that would
/// succeed, and re-issuing adds load to the node that is already saying it has
/// too much. So once a shed survives the ladder, the next publications make one
/// fail-fast attempt for `WRITE_PRESSURE_BACKOFF_MS`.
///
/// Failing fast is safe here in a way it would not be on the read path: a
/// publication's record is durable on disk and is deleted only once the
/// publication succeeds, so a refusal is retried by the next sweep rather than
/// lost. The one thing that must not happen is reporting it as published.
fn retry_write<T>(
    breaker: &AtomicU64,
    mut op: impl FnMut() -> Result<T, tonic::Status>,
) -> Result<T, tonic::Status> {
    let attempts = if now_ms() < breaker.load(Ordering::Relaxed) {
        1
    } else {
        ATTEMPTS
    };
    for attempt in 0..attempts {
        if attempt > 1 {
            std::thread::sleep(RETRY_BACKOFF * (attempt - 1) as u32);
        }
        match op() {
            Ok(value) => return Ok(value),
            Err(status) if retryable(&status) && attempt + 1 < attempts => continue,
            Err(status) => {
                // Only a shed arms the breaker. An unreachable node
                // (UNAVAILABLE) or a dropped connection is transient and
                // unrelated to load, and failing publications fast for 5s
                // because one connection blipped would turn a reconnect into a
                // window of skipped publications.
                if status.code() == tonic::Code::ResourceExhausted {
                    arm_write_pressure_backoff(breaker);
                }
                return Err(status);
            }
        }
    }
    Err(tonic::Status::unknown("retry attempts exhausted"))
}

/// Opens a fresh fail-fast window, logging the transition once. Same
/// compare-exchange discipline as `arm_pressure_backoff`: eight publisher
/// threads race the same `Remote`, and a plain load-then-store would let every
/// one of them arm and log.
fn arm_write_pressure_backoff(breaker: &AtomicU64) {
    let now = now_ms();
    let mut current = breaker.load(Ordering::Relaxed);
    loop {
        if current > now {
            return;
        }
        match breaker.compare_exchange_weak(
            current,
            now + WRITE_PRESSURE_BACKOFF_MS,
            Ordering::Relaxed,
            Ordering::Relaxed,
        ) {
            Ok(_) => break,
            Err(observed) => current = observed,
        }
    }
    crate::log_line(&format!(
        "publish: server shedding writes under load; failing publications fast \
         for {}s (their records are kept and the next sweep retries)",
        WRITE_PRESSURE_BACKOFF_MS / 1000
    ));
}

/// Async counterpart of `retry_call`, for calls issued from within a tokio task
/// where blocking is not allowed. `op` is re-invoked (returning a fresh future)
/// per attempt.
async fn retry_call_async<T, F, Fut>(mut op: F) -> Result<T, tonic::Status>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T, tonic::Status>>,
{
    retry_call_async_if(&mut op, retryable).await
}

async fn retry_call_async_if<T, F, Fut>(
    mut op: F,
    should_retry: impl Fn(&tonic::Status) -> bool,
) -> Result<T, tonic::Status>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T, tonic::Status>>,
{
    let mut last = None;
    for attempt in 0..ATTEMPTS {
        if attempt > 1 {
            tokio::time::sleep(RETRY_BACKOFF * (attempt - 1) as u32).await;
        }
        match op().await {
            Ok(value) => return Ok(value),
            Err(status) if should_retry(&status) && attempt + 1 < ATTEMPTS => last = Some(status),
            Err(status) => return Err(status),
        }
    }
    Err(last.unwrap_or_else(|| tonic::Status::unknown("retry attempts exhausted")))
}

async fn retry_write_async<T, F, Fut>(breaker: &AtomicU64, mut op: F) -> Result<T, tonic::Status>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T, tonic::Status>>,
{
    let attempts = if now_ms() < breaker.load(Ordering::Relaxed) {
        1
    } else {
        ATTEMPTS
    };
    for attempt in 0..attempts {
        if attempt > 1 {
            tokio::time::sleep(RETRY_BACKOFF * (attempt - 1) as u32).await;
        }
        match op().await {
            Ok(value) => return Ok(value),
            Err(status) if retryable(&status) && attempt + 1 < attempts => continue,
            Err(status) => {
                if status.code() == tonic::Code::ResourceExhausted {
                    arm_write_pressure_backoff(breaker);
                }
                return Err(status);
            }
        }
    }
    Err(tonic::Status::unknown("retry attempts exhausted"))
}

pub(crate) fn hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

/// kura marks a refusal the caller can act on, rather than one that is
/// transient, with this metadata. gRPC has no payment-required code, so the
/// status itself is an ordinary permission denial and the reason travels beside
/// it.
const REFUSAL_REASON_KEY: &str = "tuist-refusal-reason";
const REFUSAL_REASON_PAYMENT_REQUIRED: &str = "payment_required";

static PAYMENT_REQUIRED_REPORTED: std::sync::Once = std::sync::Once::new();

fn is_payment_required(status: &tonic::Status) -> bool {
    status
        .metadata()
        .get(REFUSAL_REASON_KEY)
        .and_then(|reason| reason.to_str().ok())
        == Some(REFUSAL_REASON_PAYMENT_REQUIRED)
}

/// Reported once for the life of the process, which is one build: the lookup it
/// answers runs per compilation, so saying this per lookup would bury it. The
/// caller still treats the refusal as a miss, so the build finishes uncached
/// rather than failing.
fn note_payment_required(status: &tonic::Status) {
    if !is_payment_required(status) {
        return;
    }

    PAYMENT_REQUIRED_REPORTED.call_once(|| {
        let message = status.message().to_owned();
        crate::log_line(&format!("cache refused: {message}"));
        eprintln!("warning: {message} Builds continue without the remote cache.");
    });
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

/// Reserved action key kura answers with the instance-wide action-cache
/// snapshot. Must byte-match the server constant; the version suffix bumps on
/// any encoding change so a mixed deployment degrades to a plain not-found
/// (v2 added the write-time watermark header and delta responses).
pub const SNAPSHOT_ACTION_KEY: &[u8] = b"tuist-actioncache-snapshot/v2";
/// `inline_output_files` hint carrying our watermark: the server then returns
/// only entries written after it (a delta), so a long-lived proxy refreshes
/// without refetching the world.
const SNAPSHOT_AFTER_HINT: &str = "tuist-snapshot-after:";

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
    chunking: std::sync::Mutex<Option<(Instant, bool)>>,
    chunking_disabled_until_ms: AtomicU64,
    uploaded_blob_bytes: AtomicU64,
    downloaded_blob_bytes: AtomicU64,
    reused_chunk_bytes: AtomicU64,
    chunk_cache: OnceLock<crate::chunk_cache::ChunkCache>,
    shared_blob_reads: SharedBlobReads,
    pub get_stats: OpStats,
    pub post_stats: OpStats,
    // Epoch-ms until which `batch_read` skips its per-blob retries because the
    // node was just seen persistently declining reads under memory pressure.
    // Retrying a deterministically-pressured node only triples its read load
    // and deepens the pressure (the same reasoning `retryable` applies to
    // server-sent Internal), so once tripped we fail fast until it may have
    // recovered. 0 means healthy.
    pressure_backoff_until_ms: AtomicU64,
    // The publication write path's own breaker. Separate from the read one
    // because the two are shed independently: kura sheds WRITES when its
    // outbox is at its cap while reads keep being served, and arming the read
    // breaker on that would fail-fast cache hits that were never in trouble.
    write_pressure_backoff_until_ms: AtomicU64,
    // Publications this `Remote` refused to attempt because it was inside that
    // window. Without it a build report cannot tell a `write_duration` that is
    // flat because publishing is healthy from one that is flat because almost
    // nothing was published.
    shed_writes: AtomicU64,
}

fn retryable(status: &tonic::Status) -> bool {
    match status.code() {
        tonic::Code::Unavailable
        | tonic::Code::Unknown
        | tonic::Code::DeadlineExceeded
        | tonic::Code::ResourceExhausted => true,
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
        //
        // The codes alone are broader than that condition, though: kura maps
        // genuine storage faults to trailer-borne `Internal`, and the
        // client's own `Endpoint::timeout` surfaces as `Cancelled`
        // ("Timeout expired"). Retrying those triples the load on a server
        // that is deterministically failing and turns one 60s timeout into
        // three, so gate on the status actually coming from the local
        // transport.
        tonic::Code::Internal | tonic::Code::Cancelled => transport_caused(status),
        _ => false,
    }
}

/// Whether a per-blob status on a `BatchReadBlobs` response entry means "the
/// blob exists but the server briefly declined to serve it" rather than "the
/// blob is gone". RESOURCE_EXHAUSTED is kura shedding load under memory
/// pressure -- it zeroes its per-request REAPI materialization budget and
/// rejects every read until pressure eases -- and UNAVAILABLE is a transient
/// serving hiccup. Both are worth re-requesting: the byte is there, and
/// dropping it as absent hands the compiler a missing object it fails the build
/// on even though a retry moments later succeeds. NOT_FOUND is deliberately
/// excluded -- a genuinely evicted blob must fall through to the caller's
/// skip-and-recompile path, not spin on retries that can never find it.
fn retryable_blob_status(code: i32) -> bool {
    code == tonic::Code::ResourceExhausted as i32 || code == tonic::Code::Unavailable as i32
}

/// One blob's outcome from a `BatchReadBlobs` pass: the digest the server
/// echoed (`None` if it omitted it), the per-blob gRPC status code, and the
/// bytes (empty unless the code is 0).
type BlobOutcome = (Option<reapi::Digest>, i32, Vec<u8>);

type SharedBlobResult = Result<Arc<Vec<BlobOutcome>>, String>;
type BlobReadKey = (String, i64);
const MAX_SHARED_BLOB_READS: usize = 128;

fn blob_read_key(digest: &reapi::Digest) -> BlobReadKey {
    (digest.hash.clone(), digest.size_bytes)
}

fn chunk_eligible(digest: &reapi::Digest) -> bool {
    (2 * 1024 * 1024..=2 * 1024 * 1024 * 1024).contains(&digest.size_bytes)
}

#[derive(Default)]
struct BlobRead {
    result: Mutex<Option<SharedBlobResult>>,
    ready: Condvar,
}

/// Share active large-node transfers across demand and background workers.
/// Completed bytes live only as long as their current readers, not in a second
/// unbounded output cache. Small blobs keep the existing batched fast path.
#[derive(Default)]
struct SharedBlobReads {
    active: Mutex<std::collections::HashMap<BlobReadKey, Arc<BlobRead>>>,
}

struct BlobReadOwner<'a> {
    reads: &'a SharedBlobReads,
    key: BlobReadKey,
    flight: Arc<BlobRead>,
}

impl BlobReadOwner<'_> {
    fn finish(self, result: SharedBlobResult) -> SharedBlobResult {
        *self.flight.result.lock().unwrap() = Some(result.clone());
        result
    }
}

impl Drop for BlobReadOwner<'_> {
    fn drop(&mut self) {
        // Worker panics must release waiters too. Never hold either lock while
        // fetching, and remove the entry so a later caller can retry a failure.
        self.flight
            .result
            .lock()
            .unwrap()
            .get_or_insert_with(|| Err("shared blob read interrupted".into()));
        self.reads.active.lock().unwrap().remove(&self.key);
        self.flight.ready.notify_all();
    }
}

impl SharedBlobReads {
    fn fetch_batch(
        &self,
        digests: &[reapi::Digest],
        fetch: impl FnOnce(&[reapi::Digest]) -> Result<Vec<BlobOutcome>, String>,
    ) -> Result<Vec<BlobOutcome>, String> {
        let mut owned = Vec::new();
        let mut owners = Vec::new();
        let mut followers = Vec::new();
        let mut seen = std::collections::HashSet::new();
        {
            let mut active = self.active.lock().unwrap();
            for digest in digests {
                let key = blob_read_key(digest);
                if !seen.insert(key.clone()) {
                    continue;
                }
                if !chunk_eligible(digest) {
                    owned.push(digest.clone());
                } else if let Some(flight) = active.get(&key) {
                    followers.push(flight.clone());
                } else {
                    if active.len() < MAX_SHARED_BLOB_READS {
                        let flight = Arc::new(BlobRead::default());
                        active.insert(key.clone(), flight.clone());
                        owners.push(BlobReadOwner {
                            reads: self,
                            key,
                            flight,
                        });
                    }
                    owned.push(digest.clone());
                }
            }
        }
        // Complete everything this batch owns before waiting on other batches.
        // Overlapping requests in opposite orders must not wait on one another
        // while still holding unfinished ownership of their remaining digests.
        let result = if owned.is_empty() {
            Ok(Vec::new())
        } else {
            fetch(&owned)
        };
        let mut outcomes = Vec::new();
        match result {
            Ok(fetched) => {
                let mut by_digest =
                    std::collections::HashMap::<BlobReadKey, Vec<BlobOutcome>>::new();
                for outcome in fetched {
                    if let Some(digest) = &outcome.0 {
                        by_digest
                            .entry(blob_read_key(digest))
                            .or_default()
                            .push(outcome);
                    } else {
                        outcomes.push(outcome);
                    }
                }
                for owner in owners {
                    let fetched = by_digest.remove(&owner.key).unwrap_or_default();
                    let shared = owner.finish(Ok(Arc::new(fetched)))?;
                    outcomes.extend(Arc::unwrap_or_clone(shared));
                }
                outcomes.extend(by_digest.into_values().flatten());
            }
            Err(message) => {
                for owner in owners {
                    let _ = owner.finish(Err(message.clone()));
                }
                return Err(message);
            }
        }
        for flight in followers {
            let shared = {
                let mut result = flight.result.lock().unwrap();
                while result.is_none() {
                    result = flight.ready.wait(result).unwrap();
                }
                result.as_ref().unwrap().clone()?
            };
            drop(flight);
            outcomes.extend(Arc::unwrap_or_clone(shared));
        }
        Ok(outcomes)
    }

    #[cfg(test)]
    fn fetch(
        &self,
        digest: &reapi::Digest,
        fetch: impl FnOnce() -> Result<Vec<BlobOutcome>, String>,
    ) -> SharedBlobResult {
        self.fetch_batch(std::slice::from_ref(digest), |_| fetch())
            .map(Arc::new)
    }
}

/// The retry-and-backoff policy over one or more `BatchReadBlobs` passes,
/// factored out of `batch_read` so it is exercised without a live server:
/// `fetch` performs one pass. Served blobs (status 0) accumulate; retryable
/// declines (see `retryable_blob_status`) are re-requested with backoff up to
/// `BLOB_STATUS_ATTEMPTS`. Action-result materialization may also retry a
/// `NOT_FOUND`, because it can observe metadata before its blob is readable.
/// A pressure decline that survives every attempt arms
/// `pressure_backoff_until_ms` so subsequent reads make a single fail-fast pass
/// rather than pile the retry ladder onto a struggling node, and logs the
/// transition once (`backing_off` already means it was armed).
fn batch_read_retrying(
    pressure_backoff_until_ms: &AtomicU64,
    blobs: &[reapi::Digest],
    retry_not_found: bool,
    mut fetch: impl FnMut(&[reapi::Digest]) -> Result<Vec<BlobOutcome>, String>,
) -> Result<std::collections::HashMap<String, Vec<u8>>, String> {
    let backing_off = now_ms() < pressure_backoff_until_ms.load(Ordering::Relaxed);
    let attempts = if backing_off { 1 } else { BLOB_STATUS_ATTEMPTS };
    let mut contents = std::collections::HashMap::new();
    let mut pending: Vec<reapi::Digest> = blobs.to_vec();
    let mut saw_pressure_decline = false;
    for round in 1..=attempts {
        let outcomes = fetch(&pending)?;
        let mut retry: Vec<reapi::Digest> = Vec::new();
        for (digest, code, data) in outcomes {
            if code == 0 {
                if let Some(digest) = digest {
                    contents.insert(digest.hash, data);
                }
            } else if retryable_blob_status(code)
                || (retry_not_found && code == tonic::Code::NotFound as i32)
            {
                if let Some(digest) = digest {
                    retry.push(digest);
                }
                saw_pressure_decline |= retryable_blob_status(code);
            }
            // Any other status (NOT_FOUND, ...) is a genuine miss: leave it out
            // of the map so the caller's skip-and-recompile path takes over.
        }
        if retry.is_empty() {
            break;
        }
        if round == attempts {
            // Only the memory-pressure signature -- the node declined the
            // *entire* set -- arms the node-wide breaker. A budget-zeroed
            // Critical kura rejects every read; a RESOURCE_EXHAUSTED on one
            // blob that overran a per-request materialization limit leaves the
            // rest served, and arming on that would fail-fast unrelated,
            // genuinely transient declines on the same Remote for 30s.
            // `contents.is_empty()` is that signature and needs no fragile
            // parse of the per-blob status message.
            if contents.is_empty() && saw_pressure_decline {
                arm_pressure_backoff(pressure_backoff_until_ms, retry.len(), round);
            }
            break;
        }
        std::thread::sleep(RETRY_BACKOFF * round as u32);
        pending = retry;
    }
    Ok(contents)
}

/// Moves `deadline` from healthy/expired to a fresh backoff window, logging the
/// transition. The compare-exchange makes exactly one caller win: the
/// prematerializer's worker pool and the compiler threads' demand fetches race
/// the same `Remote`, so a plain load-then-store would let every racer arm and
/// log at once. A caller that finds the window already armed returns without
/// re-logging or extending it, so "back off / log once" holds under concurrency.
fn arm_pressure_backoff(deadline: &AtomicU64, declined: usize, attempts: usize) {
    let now = now_ms();
    let mut current = deadline.load(Ordering::Relaxed);
    loop {
        if current > now {
            return;
        }
        match deadline.compare_exchange_weak(
            current,
            now + PRESSURE_BACKOFF_MS,
            Ordering::Relaxed,
            Ordering::Relaxed,
        ) {
            Ok(_) => break,
            Err(observed) => current = observed,
        }
    }
    crate::log_line(&format!(
        "batch_read: server declining reads under memory pressure \
         ({declined} blob(s) unmaterialized after {attempts} attempt(s)); \
         backing off retries for {}s",
        PRESSURE_BACKOFF_MS / 1000
    ));
}

/// Whether a status was synthesized by the local h2/hyper transport rather
/// than sent by the server. tonic attaches the transport error chain as the
/// status source for local failures (GOAWAY, dropped connection, broken
/// stream); a status parsed from response trailers -- i.e. one the server
/// actually returned -- carries no source. The client's own deadline
/// (`TimeoutExpired`) is also source-borne but is deliberately not matched:
/// a hung server should cost one timeout, not `ATTEMPTS`.
fn transport_caused(status: &tonic::Status) -> bool {
    let mut source = std::error::Error::source(status);
    while let Some(error) = source {
        if error.downcast_ref::<h2::Error>().is_some()
            || error.downcast_ref::<hyper::Error>().is_some()
        {
            return true;
        }
        source = error.source();
    }
    false
}

type AuthValue = tonic::metadata::MetadataValue<tonic::metadata::Ascii>;

/// Wraps a message in a `tonic::Request`, attaching the bearer when present.
fn authed_request<T>(message: T, auth: Option<&AuthValue>) -> tonic::Request<T> {
    let mut request = tonic::Request::new(message);
    if let Some(value) = auth {
        request
            .metadata_mut()
            .insert("authorization", value.clone());
    }
    request
}

impl Remote {
    pub fn new(config: RemoteConfig, tokens: Arc<TokenProvider>) -> Arc<Self> {
        Arc::new(Self {
            config,
            tokens,
            channel: OnceLock::new(),
            chunking: std::sync::Mutex::new(None),
            chunking_disabled_until_ms: AtomicU64::new(0),
            uploaded_blob_bytes: AtomicU64::new(0),
            downloaded_blob_bytes: AtomicU64::new(0),
            reused_chunk_bytes: AtomicU64::new(0),
            chunk_cache: OnceLock::new(),
            shared_blob_reads: SharedBlobReads::default(),
            get_stats: OpStats::default(),
            post_stats: OpStats::default(),
            pressure_backoff_until_ms: AtomicU64::new(0),
            write_pressure_backoff_until_ms: AtomicU64::new(0),
            shed_writes: AtomicU64::new(0),
        })
    }

    /// Whether this `Remote` is inside a window in which the server was last
    /// seen shedding publication writes.
    ///
    /// The publication path asks BEFORE it does any work, not just before each
    /// write RPC: a shedding node fails the write at the end either way, so
    /// probing the action cache, walking the value closure and asking which
    /// blobs are missing are three round trips and a pile of local reads spent
    /// to arrive at a refusal that is already known.
    pub fn shedding_writes(&self) -> bool {
        now_ms() < self.write_pressure_backoff_until_ms.load(Ordering::Relaxed)
    }

    /// Counts a publication skipped because `shedding_writes` was true.
    pub fn record_shed_write(&self) {
        self.shed_writes.fetch_add(1, Ordering::Relaxed);
    }

    pub fn shed_writes(&self) -> u64 {
        self.shed_writes.load(Ordering::Relaxed)
    }

    /// Blob payload bytes handed to the transport, including retry attempts.
    pub fn uploaded_blob_bytes(&self) -> u64 {
        self.uploaded_blob_bytes.load(Ordering::Relaxed)
    }

    pub fn enable_chunk_cache(&self, directory: std::path::PathBuf, full_handle: &str) {
        let _ = self.chunk_cache.set(crate::chunk_cache::ChunkCache::new(
            directory,
            format!("{}\0{full_handle}", self.config.grpc_url),
        ));
    }

    pub fn downloaded_blob_bytes(&self) -> u64 {
        self.downloaded_blob_bytes.load(Ordering::Relaxed)
    }
    pub fn reused_chunk_bytes(&self) -> u64 {
        self.reused_chunk_bytes.load(Ordering::Relaxed)
    }

    pub fn uses_chunked_compression(&self, size: usize) -> bool {
        size >= 2 * 1024 * 1024 && self.supports_chunking()
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

    /// An authed request carrying a git ref (the branch a publish is attributed
    /// to, or the trunk to scope a view by) as metadata.
    ///
    /// Sent twice, and both are load-bearing. Git allows any UTF-8 in a ref name,
    /// but an ASCII metadata value takes visible ASCII only, so `feature/café`
    /// fails to convert and used to be dropped in silence: the publish went out
    /// untagged, or the view came back unscoped, and nothing said why. The `-bin`
    /// header carries the bytes whatever they are.
    ///
    /// The ASCII header stays because a node that predates the binary one reads
    /// only that, and dropping it would untag every ASCII ref on the way through
    /// a rolling deploy. So: ASCII when it fits, bytes always, and a reader takes
    /// the binary one first.
    fn authed_with<T>(
        &self,
        message: T,
        header: &'static str,
        binary_header: &'static str,
        value: Option<&str>,
    ) -> tonic::Request<T> {
        let mut request = self.authed(message);
        if let Some(value) = value.filter(|value| !value.is_empty()) {
            if let Ok(ascii) = tonic::metadata::MetadataValue::try_from(value) {
                request.metadata_mut().insert(header, ascii);
            }
            request.metadata_mut().insert_bin(
                binary_header,
                tonic::metadata::MetadataValue::from_bytes(value.as_bytes()),
            );
        }
        request
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
        // Kura's wildcard inlining packs blob contents greedily up to its
        // response budget, whose ceiling is exactly 64MB
        // (MAX_REAPI_RESPONSE_BUDGET_BYTES); the budget counts content bytes,
        // not the few bytes per file of protobuf framing added by embedding
        // them, so a cap equal to the budget can reject a maximally-packed
        // response and turn the largest cached graphs into permanent misses.
        // 96MB keeps deliberate headroom above the server ceiling.
        Ok(ActionCacheClient::new(self.channel()?).max_decoding_message_size(96 << 20))
    }

    /// Fetches the closure manifest for an action key. `Ok(None)` is a
    /// definitive miss; `Err` is a transport problem.
    ///
    /// Asks the server to inline every output blob it can afford, which is a
    /// deliberate latency-for-bytes trade: the request goes out before the
    /// local store is consulted, so on a warm store the response carries (and
    /// the server bills as egress) frame bytes for blobs the caller already
    /// holds and will discard. Cold-store resolves -- the dominant remote-hit
    /// case -- waste nothing and save a full WAN round-trip per resolve.
    pub fn get_action(&self, key: &[u8]) -> Result<Option<Vec<ManifestEntry>>, String> {
        self.get_action_with_inline(key, true)
    }

    /// Existence probe for the publish path: the same lookup without the
    /// wildcard inline hint. Publish callers only compare the manifest's
    /// first entry, so asking the server to materialize and ship every output
    /// blob (16-way concurrent reads, claims on the shared materialization
    /// pool, billed egress up to the response budget) would pay all of that
    /// for bytes that are immediately dropped.
    pub fn probe_action(&self, key: &[u8]) -> Result<Option<Vec<ManifestEntry>>, String> {
        self.get_action_with_inline(key, false)
    }

    fn get_action_with_inline(
        &self,
        key: &[u8],
        inline_outputs: bool,
    ) -> Result<Option<Vec<ManifestEntry>>, String> {
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
                inline_output_files: if inline_outputs {
                    if self.chunk_cache.get().is_some() {
                        vec!["*".into(), "tuist-inline-max-bytes:2097151".into()]
                    } else {
                        vec!["*".into()]
                    }
                } else {
                    Vec::new()
                },
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
                                contents: (!file.contents.is_empty()).then_some(file.contents),
                                blob: file.digest?,
                            })
                        })
                        .collect();
                    Ok(Some(manifest))
                }
                Err(status) if status.code() == tonic::Code::NotFound => Ok(None),
                Err(status) => {
                    note_payment_required(&status);
                    Err(format!("get_action: {status}"))
                }
            }
        })();
        self.get_stats.record(started.elapsed());
        result
    }

    /// Fetches the instance's action-cache snapshot: kura answers the reserved
    /// snapshot key with the namespace's complete key→value map inlined into a
    /// single output file (see `SNAPSHOT_ACTION_KEY`). `Ok(None)` means the
    /// server has no snapshot support (an ordinary not-found), and the caller
    /// stays on the per-key path.
    /// `after` asks for a delta: only entries written after that watermark.
    pub fn get_snapshot(
        &self,
        after: Option<u64>,
        trunk: Option<&str>,
    ) -> Result<Option<Vec<u8>>, String> {
        let mut client = self.ac_client()?;
        let mut inline_output_files = vec!["*".to_string()];
        if let Some(after) = after {
            inline_output_files.push(format!("{SNAPSHOT_AFTER_HINT}{after}"));
        }
        let request = reapi::GetActionResultRequest {
            instance_name: self.config.instance.clone(),
            action_digest: Some(action_digest(SNAPSHOT_ACTION_KEY)),
            inline_output_files,
            ..Default::default()
        };
        let response = retry_call(|| {
            runtime().block_on(client.get_action_result(self.authed_with(
                request.clone(),
                "x-tuist-trunk-branch",
                "x-tuist-trunk-branch-bin",
                trunk,
            )))
        });
        match response {
            Ok(response) => Ok(response
                .into_inner()
                .output_files
                .into_iter()
                .next()
                .map(|file| file.contents)
                .filter(|contents| !contents.is_empty())),
            Err(status) if status.code() == tonic::Code::NotFound => Ok(None),
            Err(status) => {
                note_payment_required(&status);
                Err(format!("get_snapshot: {status}"))
            }
        }
    }

    /// Reads blobs, returning the bytes keyed by content hash for every blob
    /// the server served. Blobs the server reports absent (NOT_FOUND) are
    /// simply missing from the map -- the caller treats that as an incomplete
    /// graph and recompiles. Blobs the server briefly declined under load
    /// (RESOURCE_EXHAUSTED/UNAVAILABLE) are re-requested with backoff before
    /// giving up, because the byte is there and reporting it absent fails the
    /// build on a missing object; a persistent decline is logged so a build
    /// that then fails has a cause in the proxy log.
    pub fn batch_read(
        &self,
        blobs: &[reapi::Digest],
    ) -> Result<std::collections::HashMap<String, Vec<u8>>, String> {
        let started = Instant::now();
        let result =
            batch_read_retrying(&self.pressure_backoff_until_ms, blobs, false, |pending| {
                self.batch_read_with_chunks(pending)
            });
        self.get_stats.record(started.elapsed());
        result
    }

    /// Reads blobs immediately following an action-cache hit. A Kura node can
    /// briefly report a blob absent while the action result that references it
    /// is already visible, so this path gives NOT_FOUND the same bounded retry
    /// budget as a transient serving decline.
    pub fn batch_read_after_action_result(
        &self,
        blobs: &[reapi::Digest],
    ) -> Result<std::collections::HashMap<String, Vec<u8>>, String> {
        let started = Instant::now();
        let result = batch_read_retrying(&self.pressure_backoff_until_ms, blobs, true, |pending| {
            self.batch_read_with_chunks(pending)
        });
        self.get_stats.record(started.elapsed());
        result
    }

    fn batch_read_with_chunks(&self, blobs: &[reapi::Digest]) -> Result<Vec<BlobOutcome>, String> {
        if self.chunk_cache.get().is_none()
            || !blobs.iter().any(chunk_eligible)
            || !self.supports_chunking()
        {
            return self.batch_read_once(blobs);
        }
        let mut outcomes = Vec::new();
        // Release verified results before starting the next working batch, so
        // a demand reader never waits for unrelated outputs later in the graph.
        for batch in chunk_digests(blobs) {
            outcomes.extend(
                self.shared_blob_reads
                    .fetch_batch(batch, |owned| self.batch_read_with_chunks_once(owned))?,
            );
        }
        Ok(outcomes)
    }

    fn batch_read_with_chunks_once(
        &self,
        blobs: &[reapi::Digest],
    ) -> Result<Vec<BlobOutcome>, String> {
        let Some(cache) = self.chunk_cache.get() else {
            return self.batch_read_once(blobs);
        };
        if !blobs.iter().any(chunk_eligible) || !self.supports_chunking() {
            return self.batch_read_once(blobs);
        }
        let (large, mut whole): (Vec<_>, Vec<_>) = blobs.iter().cloned().partition(chunk_eligible);
        let client = self
            .cas_client()?
            .max_decoding_message_size(2 * 1024 * 1024);
        let auth = self.authorization();
        let splits = runtime().block_on(async {
            stream::iter(large)
                .map(|blob| {
                    let client = client.clone();
                    let auth = auth.clone();
                    async move {
                        let request = reapi::SplitBlobRequest {
                            instance_name: self.config.instance.clone(),
                            blob_digest: Some(blob.clone()),
                            ..Default::default()
                        };
                        let result = retry_call_async_if(
                            || {
                                let mut client = client.clone();
                                let request = authed_request(request.clone(), auth.as_ref());
                                async move { client.split_blob(request).await }
                            },
                            |status| {
                                // Pressure belongs to the original blob's retry budget,
                                // not a nested per-recipe ladder.
                                retryable(status) && !retryable_blob_status(status.code() as i32)
                            },
                        )
                        .await;
                        (blob, result)
                    }
                })
                .buffer_unordered(MAX_CHUNK_REQUESTS)
                .collect::<Vec<_>>()
                .await
        });
        let mut recipes = Vec::new();
        let mut outcomes = Vec::new();
        for (blob, result) in splits {
            let recipe = match result {
                Ok(response) => response.into_inner(),
                Err(status) if status.code() == tonic::Code::Unimplemented => {
                    self.chunking_disabled_until_ms
                        .store(now_ms() + 300_000, Ordering::Relaxed);
                    whole.push(blob);
                    continue;
                }
                Err(status)
                    if matches!(
                        status.code(),
                        tonic::Code::NotFound | tonic::Code::FailedPrecondition
                    ) =>
                {
                    whole.push(blob);
                    continue;
                }
                Err(status) if retryable_blob_status(status.code() as i32) => {
                    outcomes.push((Some(blob), status.code() as i32, Vec::new()));
                    continue;
                }
                Err(status) => {
                    // A per-blob split failure is a per-blob outcome: other
                    // independent outputs in the same batch can still be
                    // restored, so surface this one and keep going instead of
                    // aborting every sibling.
                    let code = status.code() as i32;
                    outcomes.push((
                        Some(blob),
                        if (0..=16).contains(&code) {
                            code
                        } else {
                            tonic::Code::Internal as i32
                        },
                        Vec::new(),
                    ));
                    continue;
                }
            };
            let chunks = recipe.chunk_digests;
            if recipe.chunking_function != reapi::chunking_function::Value::FastCdc2020 as i32
                || chunks.is_empty()
                || chunks.len() > 16_384
                || chunks.iter().any(|c| {
                    c.size_bytes <= 0
                        || c.size_bytes > 2 * 1024 * 1024
                        || c.hash.len() != 64
                        || !c
                            .hash
                            .bytes()
                            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
                })
                || chunks.iter().map(|c| c.size_bytes).sum::<i64>() != blob.size_bytes
            {
                whole.push(blob);
                continue;
            }
            recipes.push((blob, chunks));
        }

        let mut available = std::collections::HashMap::<BlobReadKey, (i32, Vec<u8>)>::new();
        let mut missing = whole.clone();
        let mut expected: std::collections::HashSet<_> = whole.iter().map(blob_read_key).collect();
        let whole_keys = expected.clone();
        for (_, chunks) in &recipes {
            for chunk in chunks {
                let key = blob_read_key(chunk);
                if available.contains_key(&key) || expected.contains(&key) {
                    continue;
                }
                if let Some(bytes) = cache.get(chunk) {
                    self.reused_chunk_bytes
                        .fetch_add(bytes.len() as u64, Ordering::Relaxed);
                    available.insert(key, (0, bytes));
                } else {
                    expected.insert(key);
                    missing.push(chunk.clone());
                }
            }
        }
        // Small outputs and missing chunks from every recipe share the same
        // size-bounded batch read. Deduplicate chunks shared by several outputs.
        for (digest, code, bytes) in self.batch_read_once(&missing)? {
            let digest = digest.ok_or("chunk response omitted a digest")?;
            let key = blob_read_key(&digest);
            if !expected.remove(&key) {
                return Err("chunk response repeated or returned an unrequested digest".into());
            }
            if code == tonic::Code::PermissionDenied as i32
                || code == tonic::Code::Unauthenticated as i32
                || !(0..=16).contains(&code)
            {
                return Err(format!("chunk read rejected with status {code}"));
            }
            if code == 0 {
                if blob_digest(&bytes) != digest {
                    if whole_keys.contains(&key) {
                        return Err("whole-blob fallback failed its integrity check".into());
                    }
                    continue;
                }
                if !whole_keys.contains(&key) {
                    cache.put(&digest, &bytes);
                }
            }
            available.insert(key, (code, bytes));
        }
        if !expected.is_empty() {
            return Err("chunk response omitted requested digests".into());
        }
        let mut fallback = Vec::new();
        for (blob, chunks) in recipes {
            let mut rejected = None;
            for chunk in &chunks {
                if let Some((code, _)) = available.get(&blob_read_key(chunk)) {
                    if *code != 0
                        && *code != tonic::Code::NotFound as i32
                        && rejected.is_none_or(retryable_blob_status)
                    {
                        rejected = Some(*code);
                    }
                }
            }
            if let Some(code) = rejected {
                outcomes.push((Some(blob), code, Vec::new()));
                continue;
            }
            let mut assembled = Vec::new();
            for chunk in chunks {
                let Some((0, bytes)) = available.get(&blob_read_key(&chunk)) else {
                    break;
                };
                assembled.extend_from_slice(bytes);
            }
            if blob_digest(&assembled) == blob {
                outcomes.push((Some(blob), 0, assembled));
            } else {
                fallback.push(blob);
            }
        }
        for blob in whole {
            if let Some((code, bytes)) = available.remove(&blob_read_key(&blob)) {
                outcomes.push((Some(blob), code, bytes));
            }
        }
        for outcome in self.batch_read_once(&fallback)? {
            if outcome.1 == 0
                && outcome
                    .0
                    .as_ref()
                    .is_none_or(|digest| blob_digest(&outcome.2) != *digest)
            {
                return Err("whole-blob fallback failed its integrity check".into());
            }
            outcomes.push(outcome);
        }
        Ok(outcomes)
    }

    /// One `BatchReadBlobs` pass: fetches `blobs` in size-bounded chunks
    /// concurrently over the multiplexed channel (bulk resolves can carry
    /// gigabytes, and a sequential chunk loop turns them into round-trip
    /// ladders). Each returned tuple is `(echoed digest, per-blob status code,
    /// bytes)`: the RPC itself is retried inside, but a per-blob status rides
    /// out for `batch_read_retrying` to interpret and selectively re-request.
    fn batch_read_once(&self, blobs: &[reapi::Digest]) -> Result<Vec<BlobOutcome>, String> {
        if blobs.is_empty() {
            return Ok(Vec::new());
        }
        let client = self.cas_client()?;
        let instance = self.config.instance.clone();
        let auth = self.authorization();
        let chunks = chunk_digests(blobs);
        let responses = runtime().block_on(async {
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
        Ok(responses
            .into_iter()
            .map(|response| {
                self.downloaded_blob_bytes
                    .fetch_add(response.data.len() as u64, Ordering::Relaxed);
                // The loop owns each response; move the bytes out rather than
                // deep-copying every fetched blob (batches run to 32MB while
                // the requesting compiler blocks on the resolve).
                let code = response
                    .status
                    .as_ref()
                    .map(|status| status.code)
                    .unwrap_or(-1);
                (response.digest, code, response.data)
            })
            .collect())
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
        if !items
            .iter()
            .any(|(_, bytes)| bytes.len() >= 2 * 1024 * 1024)
            || !self.supports_chunking()
        {
            return self.batch_update_whole(items, false);
        }
        let mut batch = Vec::new();
        let mut size = 0;
        for item in items {
            if !batch.is_empty() && size + item.1.len() > MAX_BATCH_BYTES as usize {
                self.batch_update_with_chunks(std::mem::take(&mut batch))?;
                size = 0;
            }
            size += item.1.len();
            batch.push(item);
        }
        self.batch_update_with_chunks(batch)
    }

    fn batch_update_with_chunks(&self, items: Vec<(reapi::Digest, Vec<u8>)>) -> Result<(), String> {
        if items.is_empty() {
            return Ok(());
        }
        if !self.supports_chunking() {
            return self.batch_update_whole(items, false);
        }
        let mut whole = Vec::new();
        let mut recipes = Vec::new();
        let mut chunks = std::collections::HashMap::new();
        for (digest, data) in &items {
            if data.len() < 2 * 1024 * 1024 {
                whole.push((digest.clone(), data.clone()));
                continue;
            }
            if blob_digest(data) != *digest {
                return Err("chunked upload digest does not match its bytes".into());
            }
            let selected: Vec<_> = fastcdc::v2020::FastCDC::with_level(
                data,
                128 * 1024,
                512 * 1024,
                2 * 1024 * 1024,
                fastcdc::v2020::Normalization::Level2,
            )
            .map(|chunk| {
                let bytes = &data[chunk.offset..chunk.offset + chunk.length];
                (blob_digest(bytes), bytes)
            })
            .collect();
            if selected.len() < 2 || selected.len() > 16_384 {
                whole.push((digest.clone(), data.clone()));
                continue;
            }
            let mut recipe = Vec::new();
            for (chunk, bytes) in selected {
                recipe.push(chunk.clone());
                chunks
                    .entry(blob_read_key(&chunk))
                    .or_insert((chunk, bytes));
            }
            recipes.push((digest.clone(), recipe));
        }
        if recipes.is_empty() {
            return self.batch_update_whole(items, false);
        }
        if let Some(cache) = self.chunk_cache.get() {
            for (digest, bytes) in chunks.values() {
                cache.put(digest, bytes);
            }
        }
        // The closure probe tests whole outputs, not their chunks. Pool this
        // second, finer-grained presence query across the missing outputs.
        let missing =
            self.find_missing(chunks.values().map(|(digest, _)| digest.clone()).collect())?;
        let mut seen = std::collections::HashSet::new();
        for digest in missing {
            let key = blob_read_key(&digest);
            let (_, bytes) = chunks
                .get(&key)
                .ok_or("chunk presence response contained an unrequested digest")?;
            if seen.insert(key) {
                whole.push((digest, bytes.to_vec()));
            }
        }
        self.batch_update_whole(whole, true)?;
        let client = self.cas_client()?;
        let auth = self.authorization();
        let splices = runtime().block_on(async {
            stream::iter(recipes)
                .map(|(digest, chunk_digests)| {
                    let client = client.clone();
                    let auth = auth.clone();
                    async move {
                        let request = reapi::SpliceBlobRequest {
                            instance_name: self.config.instance.clone(),
                            blob_digest: Some(digest.clone()),
                            chunk_digests,
                            chunking_function: reapi::chunking_function::Value::FastCdc2020 as i32,
                            ..Default::default()
                        };
                        let result =
                            retry_write_async(&self.write_pressure_backoff_until_ms, || {
                                let mut client = client.clone();
                                let request = authed_request(request.clone(), auth.as_ref());
                                async move { client.splice_blob(request).await }
                            })
                            .await;
                        (digest, result)
                    }
                })
                .buffer_unordered(MAX_CHUNK_REQUESTS)
                .collect::<Vec<_>>()
                .await
        });
        let mut fallback = std::collections::HashSet::new();
        for (digest, result) in splices {
            match result {
                Ok(response) if response.get_ref().blob_digest.as_ref() == Some(&digest) => {}
                Ok(_) => return Err("splice response did not confirm the uploaded digest".into()),
                Err(status) if status.code() == tonic::Code::Unimplemented => {
                    self.chunking_disabled_until_ms
                        .store(now_ms() + 300_000, Ordering::Relaxed);
                    fallback.insert(blob_read_key(&digest));
                }
                Err(status)
                    if matches!(
                        status.code(),
                        tonic::Code::NotFound | tonic::Code::FailedPrecondition
                    ) =>
                {
                    fallback.insert(blob_read_key(&digest));
                }
                Err(status) => return Err(format!("splice_blob: {status}")),
            }
        }
        self.batch_update_whole(
            items
                .into_iter()
                .filter(|(digest, _)| fallback.contains(&blob_read_key(digest)))
                .collect(),
            false,
        )
    }

    // Only enable the algorithm/parameters this implementation understands. A
    // failed handshake is an optional optimization failure, so old endpoints
    // continue to use the original transport. Each Remote is endpoint-scoped.
    fn supports_chunking(&self) -> bool {
        if now_ms() < self.chunking_disabled_until_ms.load(Ordering::Relaxed) {
            return false;
        }
        let mut cached = self.chunking.lock().unwrap();
        if let Some((checked, supported)) = *cached {
            if checked.elapsed() < Duration::from_secs(300) {
                return supported;
            }
        }
        let supported = (|| {
            let Ok(channel) = self.channel() else {
                return false;
            };
            let mut client = CapabilitiesClient::new(channel);
            let mut request = self.authed(reapi::GetCapabilitiesRequest {
                instance_name: self.config.instance.clone(),
            });
            request.set_timeout(Duration::from_secs(5));
            let Ok(Ok(response)) = runtime().block_on(async {
                tokio::time::timeout(Duration::from_secs(5), client.get_capabilities(request)).await
            }) else {
                return false;
            };
            let Some(capabilities) = response.into_inner().cache_capabilities else {
                return false;
            };
            capabilities.splice_blob_support
                && capabilities.split_blob_support
                && capabilities.fast_cdc_2020_params.is_some_and(|params| {
                    params.avg_chunk_size_bytes == 512 * 1024 && params.seed == 0
                })
        })();
        *cached = Some((Instant::now(), supported));
        supported
    }

    fn batch_update_whole(
        &self,
        items: Vec<(reapi::Digest, Vec<u8>)>,
        validate_responses: bool,
    ) -> Result<(), String> {
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
                let mut expected: std::collections::HashSet<_> = request
                    .requests
                    .iter()
                    .filter_map(|entry| entry.digest.as_ref())
                    .map(|digest| (digest.hash.clone(), digest.size_bytes))
                    .collect();
                let response = retry_write(&self.write_pressure_backoff_until_ms, || {
                    self.uploaded_blob_bytes
                        .fetch_add(size as u64, Ordering::Relaxed);
                    runtime().block_on(client.batch_update_blobs(self.authed(request.clone())))
                })
                .map_err(|status| format!("batch_update: {status}"))?;
                for entry in response.into_inner().responses {
                    if validate_responses {
                        let digest = entry
                            .digest
                            .ok_or("batch_update response omitted a digest")?;
                        if !expected.remove(&(digest.hash, digest.size_bytes)) {
                            return Err(
                                "batch_update response repeated or returned an unrequested digest"
                                    .into(),
                            );
                        }
                        if entry.status.is_none() {
                            return Err("batch_update response omitted a status".into());
                        }
                    }
                    if let Some(status) = entry.status {
                        if status.code != 0 {
                            // A shed can arrive either way, and only the RPC-level
                            // one goes through `retry_write`: kura refuses the whole
                            // call when its outbox is already at its cap, but a call
                            // that exhausts capacity mid-request comes back OK with
                            // the refusal on the individual blob. Both mean the same
                            // thing about the node, so both must arm the breaker.
                            // Without this the per-blob shape left every later
                            // publication paying a probe, a closure walk and a
                            // missing-blob query to reach a refusal already known,
                            // which is most of what the breaker exists to stop.
                            if status.code == tonic::Code::ResourceExhausted as i32 {
                                arm_write_pressure_backoff(&self.write_pressure_backoff_until_ms);
                            }
                            return Err(format!("batch_update blob rejected: {}", status.message));
                        }
                    }
                }
                if validate_responses && !expected.is_empty() {
                    return Err("batch_update response omitted requested blobs".into());
                }
            }
            Ok(())
        })();
        self.post_stats.record(started.elapsed());
        result
    }

    /// Publishes the entry. Called only after every blob in the manifest is
    /// known to be on the server.
    pub fn update_action(
        &self,
        key: &[u8],
        manifest: &[ManifestEntry],
        branch: Option<&str>,
        trunk: Option<&str>,
    ) -> Result<(), String> {
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
            retry_write(&self.write_pressure_backoff_until_ms, || {
                // The trunk rides the write too: kura keeps trunk-baseline
                // keys sticky against feature-branch republishes.
                let mut request = self.authed_with(
                    request.clone(),
                    "x-tuist-branch",
                    "x-tuist-branch-bin",
                    branch,
                );
                if let Some(trunk) = trunk.filter(|trunk| !trunk.is_empty()) {
                    if let Ok(value) = tonic::metadata::MetadataValue::try_from(trunk) {
                        request.metadata_mut().insert("x-tuist-trunk-branch", value);
                    }
                    request.metadata_mut().insert_bin(
                        "x-tuist-trunk-branch-bin",
                        tonic::metadata::MetadataValue::from_bytes(trunk.as_bytes()),
                    );
                }
                runtime().block_on(client.update_action_result(request))
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

/// Small compressed outputs cannot reuse transfer chunks. Keep their original
/// encoding, and return the actual choice for the publication's digest memo.
pub fn compress_frame_for_transfer(frame: &[u8], chunking: bool) -> (Vec<u8>, bool) {
    if chunking && frame.len() >= 2 * 1024 * 1024 {
        let chunked = compress_frame_in_chunks(frame);
        if chunked.len() >= 2 * 1024 * 1024 {
            return (chunked, true);
        }
    }
    (compress_frame(frame), false)
}

/// Independent compression histories preserve content-defined boundaries after
/// edits. The concatenated frames decode to the original bytes with the existing
/// decoder, including in clients released before chunked transfers existed.
pub fn compress_frame_in_chunks(frame: &[u8]) -> Vec<u8> {
    let mut result = Vec::new();
    for chunk in fastcdc::v2020::FastCDC::with_level(
        frame,
        128 * 1024,
        512 * 1024,
        2 * 1024 * 1024,
        fastcdc::v2020::Normalization::Level2,
    ) {
        let Ok(compressed) =
            zstd::stream::encode_all(&frame[chunk.offset..chunk.offset + chunk.length], 1)
        else {
            return Vec::new();
        };
        result.extend(compressed);
    }
    result
}

pub fn decompress_frame(blob: &[u8]) -> Option<Vec<u8>> {
    zstd::stream::decode_all(blob).ok()
}

#[cfg(test)]
mod tests {

    fn shared_test_digest(bytes: &[u8]) -> super::Digest {
        super::Digest {
            size_bytes: 3 * 1024 * 1024,
            ..super::blob_digest(bytes)
        }
    }

    fn wait_for_blob_read_follower(reads: &super::SharedBlobReads, digest: &super::Digest) {
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        loop {
            // The map and the batch's unwind guard own two references.
            let joined = reads
                .active
                .lock()
                .unwrap()
                .get(&(digest.hash.clone(), digest.size_bytes))
                .is_some_and(|flight| std::sync::Arc::strong_count(flight) > 2);
            if joined {
                return;
            }
            assert!(std::time::Instant::now() < deadline, "reader did not join");
            std::thread::yield_now();
        }
    }

    #[test]
    fn shared_blob_read_errors_and_panics_release_waiters_and_allow_retry() {
        for panic in [false, true] {
            let reads = super::SharedBlobReads::default();
            let digest = shared_test_digest(b"shared");
            let (started_tx, started_rx) = std::sync::mpsc::channel();
            let (release_tx, release_rx) = std::sync::mpsc::channel();
            std::thread::scope(|scope| {
                let reads = &reads;
                let digest = &digest;
                let leader = scope.spawn(move || {
                    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        reads.fetch(digest, || {
                            started_tx.send(()).unwrap();
                            release_rx
                                .recv_timeout(std::time::Duration::from_secs(5))
                                .unwrap();
                            assert!(!panic, "simulated worker panic");
                            Err("simulated read error".into())
                        })
                    }))
                });
                started_rx
                    .recv_timeout(std::time::Duration::from_secs(5))
                    .unwrap();
                let follower =
                    scope.spawn(move || reads.fetch(digest, || panic!("duplicate transfer")));
                wait_for_blob_read_follower(reads, digest);
                release_tx.send(()).unwrap();
                assert!(follower.join().unwrap().is_err());
                let result = leader.join().unwrap();
                if panic {
                    assert!(result.is_err());
                } else {
                    assert!(result.unwrap().is_err());
                }
            });
            assert!(reads.active.lock().unwrap().is_empty());
            assert!(reads.fetch(&digest, || Ok(Vec::new())).is_ok());
        }
    }

    #[test]
    fn shared_blob_reads_do_not_serialize_other_digests_or_retain_results() {
        let reads = super::SharedBlobReads::default();
        let digest = shared_test_digest(b"first");
        let result = reads
            .fetch(&digest, || {
                // Even the same hash with a different size must not join this read.
                let other = super::Digest {
                    size_bytes: digest.size_bytes + 1,
                    ..digest.clone()
                };
                assert!(reads.fetch(&other, || Ok(Vec::new())).is_ok());
                Ok(vec![(Some(digest.clone()), 0, b"first".to_vec())])
            })
            .unwrap();
        assert!(reads.active.lock().unwrap().is_empty());
        assert_eq!(std::sync::Arc::strong_count(&result), 1);
        let retained = std::sync::Arc::downgrade(&result);
        drop(result);
        assert!(retained.upgrade().is_none());
    }

    #[test]
    fn shared_blob_reads_bypass_coalescing_at_the_bookkeeping_limit() {
        let reads = super::SharedBlobReads::default();
        for index in 0..super::MAX_SHARED_BLOB_READS {
            reads
                .active
                .lock()
                .unwrap()
                .insert((index.to_string(), 1), std::sync::Arc::default());
        }
        assert!(reads
            .fetch(&shared_test_digest(b"overflow"), || Ok(Vec::new()))
            .is_ok());
        assert_eq!(
            reads.active.lock().unwrap().len(),
            super::MAX_SHARED_BLOB_READS
        );
    }

    #[test]
    fn overlapping_batches_finish_owned_reads_before_waiting_on_shared_reads() {
        let reads = super::SharedBlobReads::default();
        let first = shared_test_digest(b"first");
        let shared = shared_test_digest(b"shared");
        let last = shared_test_digest(b"last");
        let (started_tx, started_rx) = std::sync::mpsc::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let (second_tx, second_rx) = std::sync::mpsc::channel();
        std::thread::scope(|scope| {
            let reads = &reads;
            let first = &first;
            let shared = &shared;
            let last = &last;
            let one = scope.spawn(move || {
                reads
                    .fetch_batch(&[first.clone(), shared.clone()], |owned| {
                        assert_eq!(owned, &[first.clone(), shared.clone()]);
                        started_tx.send(()).unwrap();
                        release_rx
                            .recv_timeout(std::time::Duration::from_secs(5))
                            .unwrap();
                        Ok(owned
                            .iter()
                            .map(|digest| (Some(digest.clone()), 0, vec![1]))
                            .collect())
                    })
                    .unwrap()
            });
            started_rx
                .recv_timeout(std::time::Duration::from_secs(5))
                .unwrap();
            let two = scope.spawn(move || {
                reads
                    .fetch_batch(&[last.clone(), shared.clone()], |owned| {
                        assert_eq!(owned, std::slice::from_ref(last));
                        second_tx.send(()).unwrap();
                        Ok(vec![(Some(last.clone()), 0, vec![2])])
                    })
                    .unwrap()
            });
            second_rx
                .recv_timeout(std::time::Duration::from_secs(5))
                .unwrap();
            wait_for_blob_read_follower(&reads, &shared);
            release_tx.send(()).unwrap();
            assert_eq!(one.join().unwrap().len(), 2);
            let result = two.join().unwrap();
            assert_eq!(result.len(), 2);
            assert!(result
                .iter()
                .any(|outcome| outcome.0 == Some(shared.clone()) && outcome.2 == [1]));
        });
        assert!(reads.active.lock().unwrap().is_empty());
    }

    #[test]
    fn recognises_a_refusal_the_caller_can_act_on() {
        let mut status = tonic::Status::permission_denied("upgrade to Tuist Pro");
        status.metadata_mut().insert(
            super::REFUSAL_REASON_KEY,
            tonic::metadata::MetadataValue::from_static(super::REFUSAL_REASON_PAYMENT_REQUIRED),
        );

        assert!(super::is_payment_required(&status));
    }

    // A node that is merely unreachable, or a credential that genuinely lacks
    // access, must not be reported as a billing problem.
    #[test]
    fn does_not_mistake_an_ordinary_refusal_for_an_exhausted_plan() {
        assert!(!super::is_payment_required(
            &tonic::Status::permission_denied("nope")
        ));
        assert!(!super::is_payment_required(&tonic::Status::unavailable(
            "node down"
        )));
    }
    use std::sync::atomic::{AtomicU64, Ordering};

    use super::{reapi_instance, retryable, retryable_blob_status};

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

    #[test]
    fn server_sent_internal_and_cancelled_are_terminal() {
        // A status constructed directly models one parsed from response
        // trailers: no error source, so it was the server speaking, not the
        // local transport. Kura maps genuine storage faults to Internal --
        // retrying those only amplifies load on a failing node.
        assert!(!retryable(&tonic::Status::internal("failed to load blob")));
        assert!(!retryable(&tonic::Status::cancelled("Timeout expired")));
    }

    #[test]
    fn transport_borne_internal_and_cancelled_are_retryable() {
        // tonic attaches the h2/hyper error chain as the status source when
        // the failure is local (GOAWAY rotation, dropped connection).
        let goaway: h2::Error = h2::Reason::NO_ERROR.into();
        let status = tonic::Status::from_error(Box::new(goaway));
        assert_eq!(status.code(), tonic::Code::Internal);
        assert!(retryable(&status));

        let cancel: h2::Error = h2::Reason::CANCEL.into();
        let status = tonic::Status::from_error(Box::new(cancel));
        assert_eq!(status.code(), tonic::Code::Cancelled);
        assert!(retryable(&status));
    }

    #[test]
    fn plain_transport_codes_stay_retryable() {
        assert!(retryable(&tonic::Status::unavailable("draining")));
        assert!(retryable(&tonic::Status::deadline_exceeded("slow")));
        assert!(!retryable(&tonic::Status::not_found("miss")));
        assert!(!retryable(&tonic::Status::out_of_range(
            "message length too large"
        )));
    }

    #[test]
    fn per_blob_backpressure_is_retryable_but_absence_is_not() {
        // RESOURCE_EXHAUSTED (8) is kura declining a blob it holds under memory
        // pressure, and UNAVAILABLE (14) is a transient serving hiccup: both
        // mean re-request. NOT_FOUND (5) is a genuine eviction that must fall
        // through to skip-and-recompile, and OK (0) is served, not retried.
        assert!(retryable_blob_status(tonic::Code::ResourceExhausted as i32));
        assert!(retryable_blob_status(tonic::Code::Unavailable as i32));
        assert!(!retryable_blob_status(tonic::Code::NotFound as i32));
        assert!(!retryable_blob_status(0));
    }

    fn exhausted(pending: &[super::Digest]) -> Result<Vec<super::BlobOutcome>, String> {
        Ok(pending
            .iter()
            .map(|digest| {
                (
                    Some(digest.clone()),
                    tonic::Code::ResourceExhausted as i32,
                    Vec::new(),
                )
            })
            .collect())
    }

    #[test]
    fn transient_backpressure_is_retried_then_served() {
        // The exact production shape, minus the sustained pressure: the first
        // pass declines the blob with RESOURCE_EXHAUSTED, the retry serves it.
        // Before this fix that first decline was dropped as a miss and the
        // build failed on the (present) object.
        let breaker = AtomicU64::new(0);
        let digest = super::Digest {
            hash: "aa".into(),
            size_bytes: 3,
        };
        let mut round = 0;
        let served =
            super::batch_read_retrying(&breaker, std::slice::from_ref(&digest), false, |pending| {
                round += 1;
                if round == 1 {
                    exhausted(pending)
                } else {
                    Ok(vec![(Some(pending[0].clone()), 0, vec![1, 2, 3])])
                }
            })
            .unwrap();
        assert_eq!(
            served.get("aa"),
            Some(&vec![1, 2, 3]),
            "the retry delivered the byte"
        );
        assert_eq!(round, 2, "it took exactly one retry");
        assert_eq!(
            breaker.load(Ordering::Relaxed),
            0,
            "a recovery does not arm the backoff"
        );
    }

    #[test]
    fn persistent_backpressure_arms_the_backoff_then_fails_fast() {
        let breaker = AtomicU64::new(0);
        let digest = super::Digest {
            hash: "bb".into(),
            size_bytes: 1,
        };

        let mut first_calls = 0;
        let served =
            super::batch_read_retrying(&breaker, std::slice::from_ref(&digest), false, |pending| {
                first_calls += 1;
                exhausted(pending)
            })
            .unwrap();
        assert!(served.is_empty(), "a declined blob is never served");
        assert_eq!(
            first_calls,
            super::BLOB_STATUS_ATTEMPTS,
            "the first read exhausts its retries"
        );
        assert!(
            breaker.load(Ordering::Relaxed) > 0,
            "a sustained decline arms the backoff"
        );

        let mut second_calls = 0;
        let _ =
            super::batch_read_retrying(&breaker, std::slice::from_ref(&digest), false, |pending| {
                second_calls += 1;
                exhausted(pending)
            })
            .unwrap();
        assert_eq!(
            second_calls, 1,
            "within the backoff window the next read makes one fail-fast pass"
        );
    }

    #[test]
    fn not_found_is_skipped_without_retry_or_backoff() {
        let breaker = AtomicU64::new(0);
        let digest = super::Digest {
            hash: "cc".into(),
            size_bytes: 1,
        };
        let mut calls = 0;
        let served =
            super::batch_read_retrying(&breaker, std::slice::from_ref(&digest), false, |pending| {
                calls += 1;
                Ok(vec![(
                    Some(pending[0].clone()),
                    tonic::Code::NotFound as i32,
                    Vec::new(),
                )])
            })
            .unwrap();
        assert!(served.is_empty(), "an evicted blob is not served");
        assert_eq!(calls, 1, "a genuine miss is not retried");
        assert_eq!(
            breaker.load(Ordering::Relaxed),
            0,
            "a miss does not arm the backoff"
        );
    }

    #[test]
    fn action_result_materialization_retries_a_transient_not_found_without_backoff() {
        let breaker = AtomicU64::new(0);
        let digest = super::Digest {
            hash: "dd".into(),
            size_bytes: 1,
        };
        let mut calls = 0;

        let served =
            super::batch_read_retrying(&breaker, std::slice::from_ref(&digest), true, |pending| {
                calls += 1;
                if calls == 1 {
                    Ok(vec![(
                        Some(pending[0].clone()),
                        tonic::Code::NotFound as i32,
                        Vec::new(),
                    )])
                } else {
                    Ok(vec![(Some(pending[0].clone()), 0, vec![1])])
                }
            })
            .unwrap();

        assert_eq!(served.get("dd"), Some(&vec![1]));
        assert_eq!(calls, 2);
        assert_eq!(breaker.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn a_partial_decline_does_not_arm_the_node_wide_backoff() {
        // One blob declined with RESOURCE_EXHAUSTED because it overran a
        // per-request materialization limit -- not node-wide memory pressure --
        // leaves the rest of the batch served. Arming the breaker off that would
        // fail-fast unrelated transient declines on the same Remote for 30s, so
        // only a decline of the *whole* set (nothing served) counts as pressure.
        let breaker = AtomicU64::new(0);
        let pending = [
            super::Digest {
                hash: "aa".into(),
                size_bytes: 3,
            },
            super::Digest {
                hash: "bb".into(),
                size_bytes: 1,
            },
        ];
        let mut calls = 0;
        let served = super::batch_read_retrying(&breaker, &pending, false, |pending| {
            calls += 1;
            Ok(pending
                .iter()
                .map(|digest| {
                    if digest.hash == "aa" {
                        (Some(digest.clone()), 0, vec![1, 2, 3])
                    } else {
                        (
                            Some(digest.clone()),
                            tonic::Code::ResourceExhausted as i32,
                            Vec::new(),
                        )
                    }
                })
                .collect())
        })
        .unwrap();
        assert_eq!(
            served.get("aa"),
            Some(&vec![1, 2, 3]),
            "the served blob is delivered"
        );
        assert!(
            !served.contains_key("bb"),
            "the declined blob falls through to recompile"
        );
        assert_eq!(
            calls,
            super::BLOB_STATUS_ATTEMPTS,
            "the declined subset is still retried"
        );
        assert_eq!(
            breaker.load(Ordering::Relaxed),
            0,
            "a partial decline does not arm the node-wide backoff"
        );
    }

    #[test]
    fn arming_is_idempotent_within_the_window() {
        // Concurrent materializer workers all reach the arm site at once; the
        // compare-exchange lets exactly one set the deadline, so the window is
        // not re-extended (nor the transition re-logged) once per racer.
        let breaker = AtomicU64::new(0);
        super::arm_pressure_backoff(&breaker, 1, super::BLOB_STATUS_ATTEMPTS);
        let first = breaker.load(Ordering::Relaxed);
        assert!(first > 0, "the first arm opens the window");
        super::arm_pressure_backoff(&breaker, 1, super::BLOB_STATUS_ATTEMPTS);
        assert_eq!(
            breaker.load(Ordering::Relaxed),
            first,
            "a second arm within the window does not extend it"
        );
    }
}
