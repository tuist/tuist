use crate::uploads::{ConnectionUploads, UploadQueue, UploadSink};
use crate::{
    ActionPrediction, ActionPromiseCompletion, ActionPromiseState, CacheDigest, CacheDirectory,
    LocalActionCache, LocalCas, MAX_STAGED_BLOB_PACK_BYTES, ManifestPutOutcome, RemoteActionResult,
    RemoteCacheClient, RemoteCacheMode, RustcMetadata, TaskActionManifest, blob_pack_chunk,
    canonical_json,
};
use eyre::{Context, Result, bail};
use futures_util::{FutureExt, StreamExt, future::BoxFuture, stream};
use log::{debug, warn};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, Weak};
use std::time::{Duration, Instant, SystemTime};

/// Fleet claims are leases rather than correctness locks. This only bounds how
/// long one shim waits through repeated pending responses before degrading to
/// an ordinary compilation; the server independently expires abandoned claims.
const ACTION_PROMISE_WAIT: Duration = Duration::from_secs(60 * 60);
use tokio::io::{AsyncBufRead, AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader};

mod file_digest;
mod manifest;
mod prefetch;
mod stats;
mod wire;

#[cfg(test)]
pub(crate) use prefetch::select_prefetch_actions;

pub use file_digest::{
    FileDigestCache, FileDigestResolution, FileDigestScope, FileIdentity, FileObjectIdentity,
    FileSnapshot, NoFileDigestCache, RecordedFileDigest, ValidatedFileDigest, digest_file,
    digest_file_validated,
};
pub use manifest::{
    is_task_identity, task_manifest_actions,
    update_task_predictions_in_order as merge_task_action_predictions,
};
use manifest::{
    merge_task_manifests, task_manifest_dir, update_task_predictions, validate_task_identity,
    validate_task_manifest,
};
pub use stats::{AgentStats, CompilerStats};
use wire::MAX_REQUEST_BYTES;
pub use wire::{
    AGENT_PROTOCOL_VERSION, ActionDiagnostic, AgentEvent, AgentEventObserver, AgentRequest,
    AgentResponse, PinnedFile, PinnedState, RestoreStats, WrapperSpan, WrapperTiming,
};

const MAX_EXECUTABLE_IDENTITIES: usize = 64;
const MAX_EXECUTABLE_IDENTITY_SIZE: usize = 64 * 1024;
const MAX_EXECUTABLE_IDENTITY_BYTES: usize = 256 * 1024;
const TASK_ACTION_MANIFEST_VERSION: u8 = 1;
const MAX_TASK_ACTION_PREDICTIONS: usize = 16 * 1024;
const TASK_ACTION_LRU_REFRESH_MARGIN: usize = MAX_TASK_ACTION_PREDICTIONS / 16;
/// Longest shim diagnostic the agent accepts, in bytes.
const MAX_DIAGNOSTIC_BYTES: usize = 4 * 1024;
/// Most distinct shim diagnostics one session surfaces before going quiet.
///
/// A failure mode that repeats across a build tends to repeat with the same
/// message, which deduplication already collapses; the cap only guards
/// against a message that embeds something unique per compilation.
const MAX_DIAGNOSTICS: usize = 128;
const ACTION_DIAGNOSTIC_PREFIX: &str = "@tuist_cargo_cache-action-diagnostic\t";

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum DiagnosticLevel {
    Warning,
    Error,
}

impl DiagnosticLevel {
    fn label(self) -> &'static str {
        match self {
            Self::Warning => "warning",
            Self::Error => "error",
        }
    }
}

/// Most file identities one digest lookup or record may carry.
const MAX_FILE_DIGEST_BATCH: usize = 16 * 1024;
/// Most recorded file digests one session retains across every scope.
///
/// Roughly two orders of magnitude above the largest workspace measured; the
/// cap exists so a pathological build bounds the agent instead of growing it.
const MAX_FILE_DIGEST_ENTRIES: usize = 1024 * 1024;
/// Distinct cold file reads allowed at once. Identical reads coalesce before
/// this limit, while the limit prevents a wide cold build from flooding NFS.
const MAX_CONCURRENT_FILE_DIGESTS: usize = 8;
const MAX_REMOTE_TRANSFERS: usize = 64;
const MAX_PREFETCH_TRANSFERS: usize = 48;
/// Most blob packs downloaded at once.
///
/// Packs are individually bounded to keep their staging footprint predictable.
/// Allowing a few independent streams prevents one large Azure object stream
/// from serializing an entire workspace restore.
const MAX_CONCURRENT_BLOB_PACKS: usize = 8;
/// Most predicted actions whose complete output closures are downloaded
/// speculatively for one task.
///
/// Manifests deliberately retain predictions across compatible builds, so a
/// large workspace can describe far more actions than the next invocation
/// will request. Keep the most expensive recorded actions warm and let
/// foreground lookups fetch only unusually large tails on demand. The remote
/// download-byte budget remains the primary bound on speculative transfer. A
/// 1,024-action ceiling covers the measured large-workspace manifests while
/// retaining a guard against pathological manifests and stale prediction sets.
const MAX_PREFETCH_ACTIONS: usize = 1024;
// Resolve speculative actions progressively so the most valuable predictions
// become usable first and cancellation at the end of a build abandons a small
// tail instead of one workspace-sized transfer wave. Action-result lookup is
// still batched independently; this only bounds each output-closure download.
const MAX_PREFETCH_ACTION_WAVE: usize = 32;
/// Batched action lookups issued at once.
///
/// One request already asks about hundreds of actions. Serial batches keep a
/// fleet of concurrent CI jobs from multiplying metadata pressure while blob
/// transfers from earlier answers are also underway.
const MAX_PREFETCH_BATCH_LOOKUPS: usize = 1;
const PREFETCH_ACTION_BATCH_DELAY: Duration = Duration::from_millis(5);
const MAX_PREFETCH_DIRECTORY_OBJECTS: usize = 100_000;
const MAX_PREFETCH_OBJECTS_PER_WAVE: usize = 100_000;
const DEFAULT_MAX_REMOTE_DOWNLOAD_BYTES: u64 = 5 * 1024 * 1024 * 1024;

/// Names the identities a task may inherit predictions from, consulted only
/// once nothing has been recorded under its own.
pub type TaskFallbacks = Arc<dyn Fn() -> Vec<String> + Send + Sync>;
type FileDigestFlightKey = (FileDigestScope, FileIdentity);
type FileDigestFlights = BTreeMap<FileDigestFlightKey, Weak<FileDigestFlight>>;

struct FileDigestFlight {
    lock: tokio::sync::Mutex<()>,
    resolution: Mutex<Option<FileDigestResolution>>,
}

/// How many of the store's most recently written manifests a task with
/// fallbacks tries after the named identities yield nothing.
///
/// A runner that restored a cache bundle holds the manifests of the builds
/// that produced it and no version-control history to name them by, so what
/// was written last is the best remaining guess at the lockfile before this
/// one. Each candidate costs one parse, and a manifest from an unrelated
/// workspace only fails to match. One is skipped when it fills more than half
/// the prediction limit: an inherited manifest is kept under the new identity,
/// and a foreign one that large would leave this workspace's own recordings
/// no room.
const NEWEST_MANIFEST_CANDIDATES: usize = 8;

/// Remote action-cache access owned by one task session.
pub struct AgentRemoteCache {
    /// Remote protocol client used by the agent.
    pub client: RemoteCacheClient,
    /// Permitted remote read/write operations.
    pub mode: RemoteCacheMode,
    /// Directory used for verified downloads before CAS ingestion.
    pub staging_dir: PathBuf,
}

#[derive(Default)]
struct AtomicAgentStats {
    wrapper_phases_ns: Mutex<BTreeMap<String, u64>>,
    lookups: AtomicU64,
    unconsulted: AtomicU64,
    incremental_compilations: AtomicU64,
    hits: AtomicU64,
    stores: AtomicU64,
    stored_bytes: AtomicU64,
    verifications: AtomicU64,
    divergences: AtomicU64,
    downloaded_bytes: AtomicU64,
    uploaded_bytes: AtomicU64,
    background_uploads: AtomicU64,
    background_upload_failures: AtomicU64,
    remote_blob_pack_uploads: AtomicU64,
    remote_blob_pack_upload_blobs: AtomicU64,
    upload_drain_duration_ns: AtomicU64,
    prefetched_actions: AtomicU64,
    predictions_loaded: AtomicU64,
    remote_failures: AtomicU64,
    remote_manifest_lookups: AtomicU64,
    remote_manifest_lookup_duration_ns: AtomicU64,
    remote_action_lookups: AtomicU64,
    remote_action_lookup_duration_ns: AtomicU64,
    remote_blob_requests: AtomicU64,
    remote_blob_pack_requests: AtomicU64,
    remote_blob_pack_blobs: AtomicU64,
    remote_blob_transfer_duration_ns: AtomicU64,
    local_cas_write_duration_ns: AtomicU64,
    prefetch_runs: AtomicU64,
    prefetch_duration_ns: AtomicU64,
    materialization_duration_ns: AtomicU64,
    bypasses: Mutex<BTreeMap<String, u64>>,
    avoided_compiler_duration_ns: AtomicU64,
    compiler: Mutex<BTreeMap<String, CompilerStats>>,
    unit_outcomes: Mutex<BTreeMap<String, BTreeSet<String>>>,
    slow_compilations: Mutex<BTreeMap<String, u64>>,
    restored_output_files: AtomicU64,
    restored_output_bytes: AtomicU64,
    reflinked_output_files: AtomicU64,
    reflinked_output_bytes: AtomicU64,
    hardlinked_output_files: AtomicU64,
    hardlinked_output_bytes: AtomicU64,
    copied_output_files: AtomicU64,
    copied_output_bytes: AtomicU64,
    reused_output_files: AtomicU64,
    reused_output_bytes: AtomicU64,
}

struct AtomicDurationTimer<'a> {
    started: Instant,
    target: &'a AtomicU64,
}

impl<'a> AtomicDurationTimer<'a> {
    fn start(target: &'a AtomicU64) -> Self {
        Self {
            started: Instant::now(),
            target,
        }
    }
}

impl Drop for AtomicDurationTimer<'_> {
    fn drop(&mut self) {
        atomic_saturating_add(self.target, duration_ns(self.started));
    }
}

fn duration_ns(started: Instant) -> u64 {
    started.elapsed().as_nanos().try_into().unwrap_or(u64::MAX)
}

fn validate_crate_name(crate_name: Option<&str>) -> Result<()> {
    if let Some(crate_name) = crate_name
        && (crate_name.len() > 256 || crate_name.contains(['\0', '\n', '\r']))
    {
        bail!("invalid compiler crate name");
    }
    Ok(())
}

#[derive(serde::Deserialize)]
struct ActionDiagnosticEnvelope {
    outcome: String,
    crate_name: Option<String>,
    diagnostic: ActionDiagnostic,
}

/// Split a reported outcome into what the lookup did and whether the result was
/// withheld.
///
/// Every consumer normalizes through this. The diagnostic envelope and the
/// invocation it belongs to are matched by outcome, so a name normalized in one
/// place and not the other leaves the ledger row without its key details.
pub(crate) fn lookup_outcome(outcome: &str) -> (&str, bool) {
    match outcome {
        "incremental-miss" => ("miss", true),
        "incremental-unconsulted" => ("unconsulted", true),
        other => (other, false),
    }
}

fn parse_action_diagnostic(
    message: &str,
) -> Option<Result<(String, Option<String>, ActionDiagnostic)>> {
    let payload = message.strip_prefix(ACTION_DIAGNOSTIC_PREFIX)?;
    Some((|| {
        let envelope: ActionDiagnosticEnvelope = serde_json::from_str(payload)?;
        // Unconsulted belongs here with hit and miss: it is the outcome a cold
        // store gives every compilation it publishes, so refusing it threw away
        // the only record of the key another checkout would later look up.
        let (outcome, _) = lookup_outcome(&envelope.outcome);
        if !matches!(outcome, "hit" | "miss" | "unconsulted") {
            bail!("invalid action diagnostic outcome");
        }
        validate_crate_name(envelope.crate_name.as_deref())?;
        Ok((
            outcome.to_string(),
            envelope.crate_name,
            envelope.diagnostic,
        ))
    })())
}

fn atomic_saturating_add(target: &AtomicU64, value: u64) {
    // `fetch_update` is deprecated from Rust 1.99, and its replacement
    // `try_update` is newer than the MSRV, so spell out the same loop.
    let mut current = target.load(Ordering::Relaxed);
    while let Err(actual) = target.compare_exchange_weak(
        current,
        current.saturating_add(value),
        Ordering::Relaxed,
        Ordering::Relaxed,
    ) {
        current = actual;
    }
}

fn queue_prefetch_digest(
    verified: &BTreeMap<CacheDigest, PathBuf>,
    pending: &mut BTreeMap<CacheDigest, ()>,
    digest: CacheDigest,
) {
    if verified.contains_key(&digest) || pending.contains_key(&digest) {
        return;
    }
    pending.insert(digest, ());
}

fn queue_prefetch_directory(
    seen: &BTreeMap<CacheDigest, ()>,
    pending: &mut BTreeMap<CacheDigest, ()>,
    digest: CacheDigest,
    limit: usize,
) -> bool {
    if seen.contains_key(&digest) || pending.contains_key(&digest) {
        return true;
    }
    if seen.len().saturating_add(pending.len()) >= limit {
        return false;
    }
    pending.insert(digest, ());
    true
}

/// See [`CacheAgent::with_task_loader`].
pub type TaskLoader = dyn for<'a> Fn(&'a CacheAgent, &'a str) -> BoxFuture<'a, ()> + Send + Sync;

/// Shared state for an agent hosted by the process that owns a build session.
///
/// Transport listeners deliberately live in the embedder so the session
/// lifecycle owns them. This type only contains ecosystem-independent CAS and
/// protocol logic.
#[derive(Clone)]
pub struct CacheAgent {
    cas: LocalCas,
    actions: LocalActionCache,
    verified_blobs: Arc<Mutex<BTreeMap<CacheDigest, VerifiedBlob>>>,
    version: Arc<str>,
    write_locks: Arc<Mutex<BTreeMap<CacheDigest, Weak<tokio::sync::Mutex<()>>>>>,
    action_locks: Arc<Mutex<BTreeMap<CacheDigest, Weak<tokio::sync::Mutex<()>>>>>,
    stats: Arc<AtomicAgentStats>,
    observer: Option<Arc<dyn AgentEventObserver>>,
    observer_emission: Arc<Mutex<()>>,
    /// Loads a task the first time a request names it, so a connection that
    /// only reports a bypass never waits for a manifest it will not read.
    task_loader: Option<Arc<TaskLoader>>,
    executable_identities: Arc<Mutex<BTreeMap<ExecutableIdentityKey, Vec<u8>>>>,
    /// Where identities pinned to their executables outlive the session.
    identity_dir: Arc<PathBuf>,
    manifest_dir: Arc<PathBuf>,
    task_actions: Arc<Mutex<BTreeMap<String, TaskActionState>>>,
    /// Where a task may inherit predictions from, by task identity.
    task_fallbacks: Arc<Mutex<BTreeMap<String, TaskFallbacks>>>,
    next_task_run: Arc<AtomicU64>,
    manifest_write_lock: Arc<Mutex<()>>,
    remote: Option<Arc<RemoteCacheClient>>,
    remote_mode: RemoteCacheMode,
    remote_staging_dir: Arc<PathBuf>,
    remote_download_limit: u64,
    remote_download_bytes: Arc<AtomicU64>,
    pending_remote_actions: Arc<Mutex<BTreeMap<CacheDigest, RemoteActionResult>>>,
    remote_transfers: Arc<tokio::sync::Semaphore>,
    prefetch_transfers: Arc<tokio::sync::Semaphore>,
    prefetch_tasks: Arc<Mutex<Vec<tokio::task::JoinHandle<()>>>>,
    /// Distinct shim diagnostics already surfaced, so a diagnostic that fires
    /// once per compilation is printed once per session. The severity is part
    /// of each key: a fatal reason must still be surfaced after the same text
    /// appeared as a warning.
    diagnostics: Arc<Mutex<BTreeSet<(DiagnosticLevel, String)>>>,
    /// Digests of files shims hashed or wrote this session, keyed by scope and
    /// path, each entry standing while its recorded identity matches the disk.
    file_digests: Arc<Mutex<BTreeMap<(FileDigestScope, PathBuf), RecordedFileDigest>>>,
    /// Per-identity flights that make concurrent cold lookups share one read.
    file_digest_locks: Arc<Mutex<FileDigestFlights>>,
    file_digest_permits: Arc<tokio::sync::Semaphore>,
    #[cfg(test)]
    file_digest_reads: Arc<AtomicU64>,
    /// Deferred remote publication, present only when the session may write.
    uploads: Option<UploadQueue>,
}

/// What every file-digest record must satisfy before the ledger will answer
/// with it, whether a shim sent it or an earlier session left it behind.
fn validate_file_digest_record(entry: &RecordedFileDigest) -> Result<()> {
    if !entry.file.path.is_absolute() {
        bail!("file-digest records need absolute paths");
    }
    entry.digest.validate()?;
    if entry.file.len != entry.digest.size {
        bail!("file-digest record length does not match its digest");
    }
    Ok(())
}

/// Records background upload activity against a session's statistics.
struct AgentUploadSink {
    stats: Arc<AtomicAgentStats>,
}

impl UploadSink for AgentUploadSink {
    fn record_blob_uploaded(&self, bytes: u64) {
        self.stats
            .background_uploads
            .fetch_add(1, Ordering::Relaxed);
        self.stats
            .uploaded_bytes
            .fetch_add(bytes, Ordering::Relaxed);
    }

    fn record_action_uploaded(&self) {
        self.stats
            .background_uploads
            .fetch_add(1, Ordering::Relaxed);
    }

    fn record_blob_pack_uploaded(&self, blobs: u64) {
        self.stats
            .remote_blob_pack_uploads
            .fetch_add(1, Ordering::Relaxed);
        self.stats
            .remote_blob_pack_upload_blobs
            .fetch_add(blobs, Ordering::Relaxed);
    }

    fn record_upload_failure(&self) {
        self.stats
            .background_upload_failures
            .fetch_add(1, Ordering::Relaxed);
        self.stats.remote_failures.fetch_add(1, Ordering::Relaxed);
    }
}

/// A CAS blob whose contents this session hashed, and the file identity that
/// says the hash still describes what is on disk.
///
/// Length alone would miss an overwrite that keeps the size; the modification
/// time is what makes a rewrite visible without reading the bytes again.
#[derive(Debug, Clone)]
struct VerifiedBlob {
    path: PathBuf,
    len: u64,
    modified: SystemTime,
    /// The file object on Unix, so a blob replaced by another file of the
    /// same length and modification time is noticed.
    object: Option<(u64, u64)>,
}

impl VerifiedBlob {
    /// Describe a file that was just verified, or nothing when the filesystem
    /// will not report a modification time to compare against later.
    fn describe(path: &Path) -> Option<Self> {
        let metadata = std::fs::metadata(path).ok()?;
        Some(Self {
            path: path.to_path_buf(),
            len: metadata.len(),
            modified: metadata.modified().ok()?,
            object: file_object(&metadata),
        })
    }

    /// Whether the file still has the identity it had when it was verified.
    fn is_unchanged(&self) -> bool {
        let Ok(metadata) = std::fs::metadata(&self.path) else {
            return false;
        };
        metadata.len() == self.len
            && metadata.modified().is_ok_and(|now| now == self.modified)
            && file_object(&metadata) == self.object
    }
}

/// The device and inode of a file, where the platform reports them.
#[cfg(unix)]
fn file_object(metadata: &std::fs::Metadata) -> Option<(u64, u64)> {
    use std::os::unix::fs::MetadataExt as _;
    Some((metadata.dev(), metadata.ino()))
}

#[cfg(not(unix))]
fn file_object(_metadata: &std::fs::Metadata) -> Option<(u64, u64)> {
    None
}

#[derive(Debug, Clone, Default)]
struct TaskActionState {
    manifest: String,
    baseline_loaded: bool,
    predictions: BTreeMap<CacheDigest, ActionPrediction>,
    pending_predictions: BTreeMap<CacheDigest, ActionPrediction>,
    /// The pending predictions that differ from what the manifest already
    /// held when this run loaded it, each with what it held: nothing, or
    /// the baseline's own prediction. A hit re-records its prediction
    /// byte-for-byte so the receipt can name it, and that is no reason to
    /// rewrite the manifest; nor is a prediction that moved and then moved
    /// back, which is why the baseline value is kept rather than a flag.
    changed_predictions: BTreeMap<CacheDigest, Option<ActionPrediction>>,
    /// Values observed in the remote manifest when this run began. `None`
    /// means provenance is unknown because the lookup failed or the baseline
    /// was inherited locally; it must not make every inherited value look
    /// unpublished.
    remote_predictions: Option<BTreeMap<CacheDigest, ActionPrediction>>,
    /// The ordered remote snapshot associated with `remote_etag`. A
    /// read-write publisher merges this back immediately before its PUT so a
    /// bounded begin-time view cannot retract remote-only history.
    remote_manifest: Option<TaskActionManifest>,
    /// The task identity has a useful local baseline but no known remote copy.
    /// Even an otherwise hit-only run must publish an inherited or missing
    /// remote manifest once.
    remote_publication_needed: bool,
    prefetched_adapters: BTreeSet<String>,
    remote_etag: Option<String>,
}

/// Match an invocation and, on an adapter's first match, select its prefetch wave.
fn activate_prediction_adapter(
    state: &mut TaskActionState,
    invocation: &CacheDigest,
) -> (Option<ActionPrediction>, Option<Vec<ActionPrediction>>) {
    let prediction = state.predictions.get(invocation).cloned();
    let prefetch = prediction.as_ref().and_then(|prediction| {
        if !state.prefetched_adapters.insert(prediction.adapter.clone()) {
            return None;
        }
        Some(
            state
                .predictions
                .values()
                .filter(|candidate| candidate.adapter == prediction.adapter)
                .cloned()
                .collect(),
        )
    });
    (prediction, prefetch)
}

/// Protect this run's complete working set and then as many of the newest
/// concurrent changes as the bounded manifest can carry.
fn required_local_predictions(
    predictions: &[ActionPrediction],
    updates: &BTreeMap<CacheDigest, ActionPrediction>,
    concurrent_updates: &BTreeMap<CacheDigest, ActionPrediction>,
) -> BTreeSet<CacheDigest> {
    let mut required: BTreeSet<_> = updates.keys().cloned().collect();
    for prediction in predictions.iter().rev() {
        if required.len() == MAX_TASK_ACTION_PREDICTIONS {
            break;
        }
        if concurrent_updates.contains_key(&prediction.invocation) {
            required.insert(prediction.invocation.clone());
        }
    }
    required
}

/// Find disk values written after this run began, using the saved pre-recording
/// value for invocations this run also changed.
fn concurrent_task_predictions(
    predictions: &[ActionPrediction],
    state: &TaskActionState,
) -> BTreeMap<CacheDigest, ActionPrediction> {
    predictions
        .iter()
        .filter(|prediction| {
            let baseline = match state.changed_predictions.get(&prediction.invocation) {
                Some(baseline) => baseline.as_ref(),
                None => state.predictions.get(&prediction.invocation),
            };
            baseline != Some(*prediction)
        })
        .map(|prediction| (prediction.invocation.clone(), prediction.clone()))
        .collect()
}

/// Turn hit re-recordings into LRU refreshes of the value current at commit
/// time. A run that actually introduced or changed a prediction remains
/// authoritative; a hit on its unchanged baseline must not clobber a newer
/// concurrent value for the same invocation.
fn effective_task_updates(
    predictions: &[ActionPrediction],
    state: &TaskActionState,
) -> BTreeMap<CacheDigest, ActionPrediction> {
    let current: BTreeMap<_, _> = predictions
        .iter()
        .map(|prediction| (prediction.invocation.clone(), prediction))
        .collect();
    state
        .pending_predictions
        .iter()
        .map(|(invocation, update)| {
            let unchanged_hit = !state.changed_predictions.contains_key(invocation);
            let effective = if unchanged_hit {
                current.get(invocation).copied().unwrap_or(update).clone()
            } else {
                update.clone()
            };
            (invocation.clone(), effective)
        })
        .collect()
}

fn should_refresh_task_prediction_order(prediction_count: usize, has_recorded: bool) -> bool {
    has_recorded && prediction_count >= MAX_TASK_ACTION_PREDICTIONS - TASK_ACTION_LRU_REFRESH_MARGIN
}

/// Choose the last remotely observed value for every prediction this run
/// replaces. A local-only value is not proof that its action was published.
fn replaced_task_predictions(
    remote: &BTreeMap<CacheDigest, ActionPrediction>,
    candidates: &BTreeSet<CacheDigest>,
) -> Vec<ActionPrediction> {
    candidates
        .iter()
        .filter_map(|invocation| remote.get(invocation).cloned())
        .collect()
}

/// Decide which local values may outrank a remote manifest during publication.
///
/// Values changed by this run and concurrent local writers are authoritative
/// once their actions are publishable. An unchanged hit is only an LRU hint:
/// it must not replace a newer value learned remotely after this run began.
fn remote_publication_precedence(
    state: &TaskActionState,
    completed: &[ActionPrediction],
    concurrent_updates: &BTreeMap<CacheDigest, ActionPrediction>,
    proven_uploads: &BTreeSet<CacheDigest>,
    published: &BTreeMap<CacheDigest, &ActionPrediction>,
    withheld: &BTreeSet<CacheDigest>,
) -> (BTreeSet<CacheDigest>, BTreeSet<CacheDigest>) {
    let publication_base_invocations: BTreeSet<_> = state
        .remote_manifest
        .iter()
        .flat_map(|manifest| manifest.predictions.iter())
        .map(|prediction| prediction.invocation.clone())
        .collect();
    let unchanged_hits: BTreeSet<_> = completed
        .iter()
        .filter(|prediction| {
            !state
                .changed_predictions
                .contains_key(&prediction.invocation)
        })
        .map(|prediction| prediction.invocation.clone())
        .collect();
    let required = completed
        .iter()
        .filter(|prediction| !unchanged_hits.contains(&prediction.invocation))
        .chain(concurrent_updates.values().filter(|prediction| {
            state.remote_predictions.is_some() || proven_uploads.contains(&prediction.action)
        }))
        .filter(|prediction| {
            !withheld.contains(&prediction.invocation)
                && published.get(&prediction.invocation).copied() == Some(*prediction)
        })
        .map(|prediction| prediction.invocation.clone())
        .collect();
    let fallbacks = withheld
        .iter()
        .filter(|invocation| published.contains_key(*invocation))
        .cloned()
        .chain(
            unchanged_hits
                .into_iter()
                .filter(|invocation| published.contains_key(invocation)),
        )
        .chain(
            concurrent_updates
                .iter()
                .filter(|(invocation, prediction)| {
                    state.remote_predictions.is_none()
                        && !proven_uploads.contains(&prediction.action)
                        && published.contains_key(*invocation)
                })
                .map(|(invocation, _)| invocation.clone()),
        )
        .chain(
            published
                .keys()
                .filter(|invocation| {
                    state.remote_predictions.is_none()
                        && state.remote_manifest.is_some()
                        && !publication_base_invocations.contains(*invocation)
                })
                .cloned(),
        )
        .collect();
    (required, fallbacks)
}

/// Combine baseline provenance with this queue's observed upload outcomes.
/// A held action is proven only when it is absent from the failed set.
fn unpublished_task_actions(
    mut unproven: BTreeSet<CacheDigest>,
    held: &BTreeSet<CacheDigest>,
    failed: BTreeSet<CacheDigest>,
) -> BTreeSet<CacheDigest> {
    unproven.retain(|action| !held.contains(action));
    unproven.extend(failed);
    unproven
}

/// Find final values the task's remote baseline does not prove were published.
fn unproven_task_predictions<'a>(
    predictions: impl IntoIterator<Item = &'a ActionPrediction>,
    remote: &BTreeMap<CacheDigest, ActionPrediction>,
) -> BTreeMap<CacheDigest, CacheDigest> {
    predictions
        .into_iter()
        .filter(|prediction| remote.get(&prediction.invocation) != Some(*prediction))
        .map(|prediction| (prediction.invocation.clone(), prediction.action.clone()))
        .collect()
}

/// Remove new or replacement predictions whose actions did not publish,
/// restoring only the last value observed in the remote manifest.
fn withhold_unpublished_updates(
    manifest: &mut TaskActionManifest,
    candidates: &BTreeSet<CacheDigest>,
    replaced: &[ActionPrediction],
    unpublished: &BTreeSet<CacheDigest>,
) -> BTreeSet<CacheDigest> {
    let withheld: BTreeSet<_> = manifest
        .predictions
        .iter()
        .filter(|prediction| {
            candidates.contains(&prediction.invocation) && unpublished.contains(&prediction.action)
        })
        .map(|prediction| prediction.invocation.clone())
        .collect();
    manifest
        .predictions
        .retain(|prediction| !withheld.contains(&prediction.invocation));
    let mut retained: BTreeSet<_> = manifest
        .predictions
        .iter()
        .map(|prediction| prediction.invocation.clone())
        .collect();
    for previous in replaced.iter().rev() {
        if withheld.contains(&previous.invocation) && retained.insert(previous.invocation.clone()) {
            // This invocation was used by the current run. Keep its last
            // published value at the newest end of the durable LRU even though
            // the replacement could not be advertised.
            manifest.predictions.push(previous.clone());
        }
    }
    withheld
}

struct PrefetchedAction {
    adapter: String,
    result: RemoteActionResult,
}

struct RemoteDownloadReservation {
    counter: Arc<AtomicU64>,
    reserved: u64,
    committed: bool,
}

impl RemoteDownloadReservation {
    fn bytes(&self) -> u64 {
        self.reserved
    }

    fn commit(mut self, bytes: u64) {
        debug_assert!(bytes <= self.reserved);
        self.counter
            .fetch_sub(self.reserved.saturating_sub(bytes), Ordering::AcqRel);
        self.committed = true;
    }
}

impl Drop for RemoteDownloadReservation {
    fn drop(&mut self) {
        if !self.committed {
            self.counter.fetch_sub(self.reserved, Ordering::AcqRel);
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct ExecutableIdentityKey {
    executable: PathBuf,
    environment: BTreeMap<String, Option<String>>,
}

// 2: pins carry the state the shim saw, and cover the search directories.
const PERSISTED_EXECUTABLE_IDENTITY_VERSION: u8 = 2;

/// An executable identity kept across sessions.
///
/// It stands while every pinned file is as the probing shim saw it. The
/// probe reads those files and nothing else, so an unchanged set of them
/// would print the same answer again.
#[derive(Debug, Serialize, Deserialize)]
struct PersistedExecutableIdentity {
    version: u8,
    executable: PathBuf,
    environment: BTreeMap<String, Option<String>>,
    pins: Vec<PinnedFile>,
    stdout: String,
}

impl CacheAgent {
    /// Create an agent backed by the cache rooted at `cache_dir`.
    pub fn new(cache_dir: impl Into<PathBuf>, version: impl Into<Arc<str>>) -> Self {
        Self::build(cache_dir.into(), version.into(), None, 0)
    }

    /// Create an agent with local-first access to a remote action cache.
    pub fn new_remote(
        cache_dir: impl Into<PathBuf>,
        version: impl Into<Arc<str>>,
        remote: AgentRemoteCache,
    ) -> Self {
        Self::build(
            cache_dir.into(),
            version.into(),
            Some(remote),
            DEFAULT_MAX_REMOTE_DOWNLOAD_BYTES,
        )
    }

    /// Create a remote agent with a cumulative download budget for the session.
    pub fn new_remote_with_download_limit(
        cache_dir: impl Into<PathBuf>,
        version: impl Into<Arc<str>>,
        remote: AgentRemoteCache,
        max_remote_download_bytes: u64,
    ) -> Self {
        Self::build(
            cache_dir.into(),
            version.into(),
            Some(remote),
            max_remote_download_bytes,
        )
    }

    fn build(
        cache_dir: PathBuf,
        version: Arc<str>,
        remote: Option<AgentRemoteCache>,
        remote_download_limit: u64,
    ) -> Self {
        let remote_mode = remote
            .as_ref()
            .map_or(RemoteCacheMode::ReadOnly, |remote| remote.mode);
        let remote_staging_dir = remote.as_ref().map_or_else(
            || cache_dir.join("remote"),
            |remote| remote.staging_dir.clone(),
        );
        let remote = remote.map(|remote| Arc::new(remote.client));
        let stats = Arc::new(AtomicAgentStats::default());
        let remote_transfers = Arc::new(tokio::sync::Semaphore::new(MAX_REMOTE_TRANSFERS));
        // A session that cannot publish never queues an upload, so it does not
        // need somewhere to queue one.
        let uploads = remote
            .clone()
            .filter(|_| remote_mode.writes())
            .map(|client| {
                UploadQueue::new(
                    client,
                    Arc::new(AgentUploadSink {
                        stats: stats.clone(),
                    }),
                    remote_transfers.clone(),
                )
            });
        Self {
            cas: LocalCas::new(cache_dir.clone()),
            actions: LocalActionCache::new(cache_dir.clone()),
            verified_blobs: Arc::new(Mutex::new(BTreeMap::new())),
            version,
            write_locks: Arc::new(Mutex::new(BTreeMap::new())),
            action_locks: Arc::new(Mutex::new(BTreeMap::new())),
            stats,
            observer: None,
            observer_emission: Arc::new(Mutex::new(())),
            task_loader: None,
            executable_identities: Arc::new(Mutex::new(BTreeMap::new())),
            identity_dir: Arc::new(cache_dir.join("executable-identities").join("v1")),
            manifest_dir: Arc::new(task_manifest_dir(&cache_dir)),
            task_actions: Arc::new(Mutex::new(BTreeMap::new())),
            task_fallbacks: Arc::new(Mutex::new(BTreeMap::new())),
            next_task_run: Arc::new(AtomicU64::new(0)),
            manifest_write_lock: Arc::new(Mutex::new(())),
            remote,
            remote_mode,
            remote_staging_dir: Arc::new(remote_staging_dir),
            remote_download_limit,
            remote_download_bytes: Arc::new(AtomicU64::new(0)),
            pending_remote_actions: Arc::new(Mutex::new(BTreeMap::new())),
            remote_transfers,
            prefetch_transfers: Arc::new(tokio::sync::Semaphore::new(MAX_PREFETCH_TRANSFERS)),
            prefetch_tasks: Arc::new(Mutex::new(Vec::new())),
            diagnostics: Arc::new(Mutex::new(BTreeSet::new())),
            file_digests: Arc::new(Mutex::new(BTreeMap::new())),
            file_digest_locks: Arc::new(Mutex::new(BTreeMap::new())),
            file_digest_permits: Arc::new(tokio::sync::Semaphore::new(MAX_CONCURRENT_FILE_DIGESTS)),
            #[cfg(test)]
            file_digest_reads: Arc::new(AtomicU64::new(0)),
            uploads,
        }
    }

    /// Report each accounted cache decision to `observer` as it happens.
    #[must_use]
    pub fn with_observer(mut self, observer: Arc<dyn AgentEventObserver>) -> Self {
        self.observer = Some(observer);
        self
    }

    /// Load tasks on demand.
    ///
    /// The loader is called with the agent and the task's identity before the
    /// first request that names a task this agent has not begun, and is
    /// expected to begin it; a second call for the same task must be a no-op.
    /// Requests that name no task never wait on it.
    pub fn with_task_loader(mut self, loader: Arc<TaskLoader>) -> Self {
        self.task_loader = Some(loader);
        self
    }

    /// Make sure `task` has been begun before a request reads or records
    /// under it.
    async fn ensure_task_loaded(&self, task: &str) {
        let Some(loader) = &self.task_loader else {
            return;
        };
        if self.task_actions.lock().unwrap().contains_key(task) {
            return;
        }
        loader(self, task).await;
    }

    fn emit(&self, event: impl FnOnce() -> AgentEvent) {
        if let Some(observer) = &self.observer {
            let _emission = self.observer_emission.lock().unwrap();
            observer.event(event());
        }
    }

    fn emit_action(&self, diagnostic: Option<AgentEvent>, action: AgentEvent) {
        if let Some(observer) = &self.observer {
            let _emission = self.observer_emission.lock().unwrap();
            if let Some(diagnostic) = diagnostic {
                observer.event(diagnostic);
            }
            observer.event(action);
        }
    }

    fn reserve_remote_download(&self, bytes: u64) -> Result<RemoteDownloadReservation> {
        let mut current = self.remote_download_bytes.load(Ordering::Acquire);
        loop {
            let next = current
                .checked_add(bytes)
                .ok_or_else(|| eyre::eyre!("remote cache download budget overflowed"))?;
            if next > self.remote_download_limit {
                bail!(
                    "remote cache download budget exceeded: {} bytes requested with {} of {} bytes already used",
                    bytes,
                    current,
                    self.remote_download_limit
                );
            }
            match self.remote_download_bytes.compare_exchange_weak(
                current,
                next,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => {
                    return Ok(RemoteDownloadReservation {
                        counter: self.remote_download_bytes.clone(),
                        reserved: bytes,
                        committed: false,
                    });
                }
                Err(observed) => current = observed,
            }
        }
    }

    fn reserve_remote_download_up_to(&self, requested: u64) -> Result<RemoteDownloadReservation> {
        let mut current = self.remote_download_bytes.load(Ordering::Acquire);
        loop {
            let reserved = requested.min(self.remote_download_limit.saturating_sub(current));
            let next = current + reserved;
            match self.remote_download_bytes.compare_exchange_weak(
                current,
                next,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => {
                    return Ok(RemoteDownloadReservation {
                        counter: self.remote_download_bytes.clone(),
                        reserved,
                        committed: false,
                    });
                }
                Err(observed) => current = observed,
            }
        }
    }

    /// Load the last committed action manifest for a task into this session.
    pub async fn begin_task(&self, task: &str) -> Result<String> {
        self.begin_task_with_remote_errors(task, false, None, true)
            .await
    }

    /// Load a task but defer each adapter's speculative downloads until its
    /// first prediction matches the current build.
    pub async fn begin_task_on_prediction(&self, task: &str) -> Result<String> {
        self.begin_task_with_remote_errors(task, false, None, false)
            .await
    }

    /// Load a task using its identity as the run key.
    ///
    /// A task-scoped process has only one run for an identity, so it can defer
    /// this work until its first client connects while putting the identity in
    /// the client's environment ahead of time.
    pub async fn begin_session_task(&self, task: &str) -> Result<()> {
        self.begin_task_with_remote_errors(task, false, Some(task.to_string()), false)
            .await?;
        Ok(())
    }

    /// Name where a task's predictions may come from when nothing has been
    /// recorded under its own identity.
    ///
    /// The identities are produced on demand rather than taken up front,
    /// because finding them can cost a few version-control commands and most
    /// builds never need them. The first manifest found, locally and then on
    /// the remote, is adopted under the task's own identity, so the commands
    /// that follow, tests and lints included, start from it too, and a trusted
    /// build publishes it there. When none of the named identities has one,
    /// the store's newest manifests are tried.
    pub fn register_task_fallbacks(
        &self,
        task: &str,
        fallbacks: impl Fn() -> Vec<String> + Send + Sync + 'static,
    ) -> Result<()> {
        validate_task_identity(task)?;
        self.task_fallbacks
            .lock()
            .unwrap()
            .insert(task.to_string(), Arc::new(fallbacks));
        Ok(())
    }

    /// Load a task and finish its prefetch, surfacing remote lookup failures.
    pub async fn prefetch_task(&self, task: &str) -> Result<String> {
        let run = self
            .begin_task_with_remote_errors(task, true, None, true)
            .await?;
        self.wait_for_prefetches().await;
        Ok(run)
    }

    async fn begin_task_with_remote_errors(
        &self,
        task: &str,
        strict: bool,
        run: Option<String>,
        eager_prefetch: bool,
    ) -> Result<String> {
        validate_task_identity(task)?;
        // The local manifest is already enough to start useful work. Do not
        // leave those predictions idle while a high-latency remote answers the
        // manifest lookup; the authoritative snapshot is loaded again below
        // before it is merged, so another process can still update it while
        // this request is in flight.
        let early_manifest = {
            let _write_guard = self.manifest_write_lock.lock().unwrap();
            let _file_guard = self.lock_task_manifest(task)?;
            self.load_task_manifest(task)?
        };
        let early_actions: BTreeSet<_> = early_manifest
            .iter()
            .flat_map(|manifest| manifest.predictions.iter())
            .map(|prediction| prediction.action.clone())
            .collect();
        if eager_prefetch {
            self.spawn_prefetch_predictions(
                early_manifest
                    .as_ref()
                    .map(|manifest| manifest.predictions.clone())
                    .unwrap_or_default(),
            );
        }
        let (remote_manifest, mut remote_etag, mut remote_predictions, remote_missing) =
            if self.remote.is_some() && self.remote_mode.reads() {
                match self.get_remote_task_manifest(task).await {
                    Ok(Some((manifest, etag))) => {
                        let predictions = manifest
                            .predictions
                            .iter()
                            .map(|prediction| (prediction.invocation.clone(), prediction.clone()))
                            .collect();
                        (Some(manifest), Some(etag), Some(predictions), false)
                    }
                    Ok(None) => (None, None, Some(BTreeMap::new()), true),
                    Err(error) => {
                        if strict {
                            return Err(error).wrap_err_with(|| {
                                format!("remote task action manifest lookup failed for {task}")
                            });
                        }
                        self.note_remote_failure();
                        warn!("remote task action manifest lookup failed for {task}: {error}");
                        (None, None, None, false)
                    }
                }
            } else {
                (None, None, None, false)
            };
        let remote_publication_base = remote_manifest.clone();
        // Without a remote there is nothing to reconcile: the manifest just
        // read is the whole truth, and writing it back byte for byte would
        // serialize every prediction for nothing.
        let manifest = if self.remote.is_some() && self.remote_mode.reads() {
            let _write_guard = self.manifest_write_lock.lock().unwrap();
            let _file_guard = self.lock_task_manifest(task)?;
            let local_manifest = self.load_task_manifest(task)?;
            let local_baseline = local_manifest.clone();
            let manifest = match (remote_manifest, local_manifest) {
                (Some(remote), Some(local)) => {
                    let required = local
                        .predictions
                        .iter()
                        .map(|prediction| prediction.invocation.clone())
                        .collect();
                    match merge_task_manifests(
                        task,
                        remote,
                        local.clone(),
                        &required,
                        &BTreeSet::new(),
                    ) {
                        Ok(manifest) => Some(manifest),
                        Err(error) => {
                            warn!("remote task action manifest merge failed for {task}: {error}");
                            remote_etag = None;
                            Some(local)
                        }
                    }
                }
                (Some(remote), None) => Some(remote),
                (None, local) => local,
            };
            if manifest != local_baseline
                && let Some(manifest) = &manifest
            {
                self.persist_task_manifest(manifest)?;
            }
            manifest
        } else {
            early_manifest
        };
        let (manifest, remote_etag, inherited) = match manifest {
            Some(manifest) => (Some(manifest), remote_etag, false),
            // Inherited from another identity, so the remote's copy of that
            // one is no precondition for publishing under this one.
            None => {
                let (manifest, inherited_provenance, inherited) =
                    self.inherit_task_manifest(task, strict).await?;
                if inherited {
                    remote_predictions = inherited_provenance;
                }
                (manifest, None, inherited)
            }
        };
        let mut state = if let Some(manifest) = manifest {
            let write_only_baseline = self.remote_mode.writes()
                && !self.remote_mode.reads()
                && !manifest.predictions.is_empty();
            TaskActionState {
                manifest: task.to_string(),
                baseline_loaded: true,
                predictions: manifest
                    .predictions
                    .into_iter()
                    .map(|prediction| (prediction.invocation.clone(), prediction))
                    .collect(),
                pending_predictions: BTreeMap::new(),
                changed_predictions: BTreeMap::new(),
                remote_predictions,
                remote_manifest: remote_publication_base,
                remote_publication_needed: self.remote.is_some()
                    && self.remote_mode.writes()
                    && (remote_missing || inherited || write_only_baseline),
                prefetched_adapters: BTreeSet::new(),
                remote_etag,
            }
        } else {
            TaskActionState {
                manifest: task.to_string(),
                baseline_loaded: true,
                remote_predictions,
                remote_manifest: remote_publication_base,
                remote_etag,
                ..TaskActionState::default()
            }
        };
        let run = run.unwrap_or_else(|| {
            let sequence = self.next_task_run.fetch_add(1, Ordering::Relaxed);
            CacheDigest::blake3(format!("{task}\0{}\0{sequence}", std::process::id()).as_bytes())
                .hash
        });
        // The largest baseline rather than a sum: beginning the same task again
        // in one session reloads the same manifest, and counting it twice would
        // overstate what there was to match.
        self.stats.predictions_loaded.fetch_max(
            state.predictions.len().try_into().unwrap_or(u64::MAX),
            Ordering::Relaxed,
        );
        if eager_prefetch {
            state.prefetched_adapters.extend(
                state
                    .predictions
                    .values()
                    .map(|prediction| prediction.adapter.clone()),
            );
        }
        // The early local wave already owns these actions. Only launch a
        // second wave for predictions learned from the remote or from a local
        // writer that committed while its lookup was in flight.
        let predictions = state
            .predictions
            .values()
            .filter(|prediction| !early_actions.contains(&prediction.action))
            .cloned()
            .collect();
        self.task_actions.lock().unwrap().insert(run.clone(), state);
        if eager_prefetch {
            self.spawn_prefetch_predictions(predictions);
        }
        Ok(run)
    }

    /// Adopt the manifest of a fallback identity for a task that has none.
    ///
    /// The named identities are tried in the order given, each in the local
    /// store and then on the remote, and then the store's newest manifests,
    /// locally only. The first one found is persisted under `task` so the
    /// next command sees a complete baseline rather than only what this one
    /// recorded, and a later session finds it without asking again.
    async fn inherit_task_manifest(
        &self,
        task: &str,
        strict: bool,
    ) -> Result<(
        Option<TaskActionManifest>,
        Option<BTreeMap<CacheDigest, ActionPrediction>>,
        bool,
    )> {
        let fallbacks = self.task_fallbacks.lock().unwrap().get(task).cloned();
        let Some(fallbacks) = fallbacks else {
            return Ok((None, None, false));
        };
        let named = tokio::task::spawn_blocking(move || fallbacks()).await?;
        let mut tried = BTreeSet::from([task.to_string()]);
        let candidates = named.into_iter().map(|identity| (identity, true)).chain(
            self.newest_task_identities()
                .into_iter()
                .map(|identity| (identity, false)),
        );
        for (identity, named) in candidates {
            if !tried.insert(identity.clone()) || validate_task_identity(&identity).is_err() {
                continue;
            }
            let mut found = self.load_task_manifest(&identity)?;
            let mut provenance = None;
            if self.remote_mode.reads() && (found.is_some() || named) {
                match self.get_remote_task_manifest(&identity).await {
                    Ok(Some((remote, _))) => {
                        provenance = Some(
                            remote
                                .predictions
                                .iter()
                                .map(|prediction| {
                                    (prediction.invocation.clone(), prediction.clone())
                                })
                                .collect(),
                        );
                        if found.is_none() {
                            found = Some(remote);
                        }
                    }
                    Ok(None) => provenance = Some(BTreeMap::new()),
                    Err(error) => {
                        // A local fallback is already useful without remote
                        // provenance. Keep that baseline with unknown
                        // provenance rather than making strict prefetch fail
                        // because its optional proof lookup was unavailable.
                        if strict && found.is_none() {
                            return Err(error).wrap_err_with(|| {
                                format!("remote task action manifest lookup failed for {identity}")
                            });
                        }
                        self.note_remote_failure();
                        warn!("remote task action manifest lookup failed for {identity}: {error}");
                    }
                }
            }
            let Some(mut manifest) = found else {
                continue;
            };
            if manifest.predictions.is_empty()
                || (!named && manifest.predictions.len() > MAX_TASK_ACTION_PREDICTIONS / 2)
            {
                continue;
            }
            debug!(
                "no predictions were recorded for {task}; inheriting {} from {identity}",
                manifest.predictions.len()
            );
            manifest.task = task.to_string();
            validate_task_manifest(&manifest, task)?;
            let _write_guard = self.manifest_write_lock.lock().unwrap();
            let _file_guard = self.lock_task_manifest(task)?;
            // Another process may have recorded this identity while the
            // fallbacks were being found. What it wrote describes this
            // lockfile and wins over an inheritance.
            if let Some(recorded) = self.load_task_manifest(task)? {
                return Ok((Some(recorded), None, false));
            }
            self.persist_task_manifest(&manifest)?;
            return Ok((Some(manifest), provenance, true));
        }
        Ok((None, None, false))
    }

    /// The identities of the store's most recently written manifests.
    fn newest_task_identities(&self) -> Vec<String> {
        let Ok(entries) = fs::read_dir(self.manifest_dir.as_path()) else {
            return Vec::new();
        };
        let mut manifests: Vec<(std::time::SystemTime, String)> = entries
            .filter_map(|entry| {
                let entry = entry.ok()?;
                let name = entry.file_name();
                let identity = name.to_str()?.strip_suffix(".json")?.to_string();
                validate_task_identity(&identity).ok()?;
                let modified = entry.metadata().ok()?.modified().ok()?;
                Some((modified, identity))
            })
            .collect();
        manifests.sort_by(|left, right| right.cmp(left));
        manifests
            .into_iter()
            .take(NEWEST_MANIFEST_CANDIDATES)
            .map(|(_, identity)| identity)
            .collect()
    }

    /// Cancel speculative downloads before the owning session exits.
    pub async fn cancel_prefetches(&self) {
        let tasks = std::mem::take(&mut *self.prefetch_tasks.lock().unwrap());
        for task in &tasks {
            task.abort();
        }
        for task in tasks {
            if let Err(error) = task.await
                && !error.is_cancelled()
            {
                warn!("remote action prefetch task failed: {error}");
            }
        }
    }

    /// Publish everything a build queued, before the session stops.
    ///
    /// Store requests return once an object is durable locally, so at this point
    /// the remote cache may still be behind the local one. Uploads run on the
    /// session's runtime and are abandoned if it goes away, so a session that
    /// wants them published has to wait here.
    pub async fn wait_for_uploads(&self) {
        let Some(uploads) = &self.uploads else {
            return;
        };
        let _timer = AtomicDurationTimer::start(&self.stats.upload_drain_duration_ns);
        uploads.drain().await;
    }

    async fn wait_for_prefetches(&self) {
        let tasks = std::mem::take(&mut *self.prefetch_tasks.lock().unwrap());
        for task in tasks {
            if let Err(error) = task.await {
                warn!("remote action prefetch task failed: {error}");
            }
        }
    }

    /// Atomically publish the completed actions collected by a task run.
    pub async fn commit_task(&self, run: &str) -> Result<()> {
        self.commit_task_actions(run).await.map(|_| ())
    }

    /// Publish a task run and return exactly the predictions completed by it.
    ///
    /// The persisted task manifest also carries predictions inherited from
    /// earlier runs. Callers that need a receipt for this one run must not
    /// mistake that cumulative manifest for the work the run completed.
    pub async fn commit_task_actions(&self, run: &str) -> Result<Vec<ActionPrediction>> {
        validate_task_identity(run)?;
        let mut state = {
            let mut runs = self.task_actions.lock().unwrap();
            let state = runs
                .get(run)
                .ok_or_else(|| eyre::eyre!("task action manifest baseline was not loaded"))?;
            if !state.baseline_loaded {
                bail!("task action manifest baseline was not loaded");
            }
            // A hit-only run leaves a comfortably bounded manifest as it found
            // it. Refresh durable LRU order only near the cap, where it can
            // affect the next pruning decision, or when this task identity
            // still needs its first remote publication.
            debug!(
                "committing {} changed of {} recorded predictions for {}",
                state.changed_predictions.len(),
                state.pending_predictions.len(),
                state.manifest
            );
            let refresh_hit_order = should_refresh_task_prediction_order(
                state.predictions.len(),
                !state.pending_predictions.is_empty(),
            );
            if state.changed_predictions.is_empty()
                && !refresh_hit_order
                && !state.remote_publication_needed
            {
                let completed = state.pending_predictions.values().cloned().collect();
                runs.remove(run);
                return Ok(completed);
            }
            state.clone()
        };
        let task = state.manifest.clone();
        validate_task_identity(&task)?;
        let write_only = self.remote_mode.writes() && !self.remote_mode.reads();
        // Write-only mode does not use remote predictions for cache hits, but
        // it still needs the current manifest as a publication precondition
        // and provenance baseline. The conditional update path may read the
        // same metadata after a conflict, so doing it up front does not weaken
        // the mode's promise not to satisfy build lookups from the remote.
        let write_only_remote = if write_only {
            match self.get_remote_task_manifest(&task).await {
                Ok(Some((manifest, etag))) => {
                    let remote_predictions: BTreeMap<_, _> = manifest
                        .predictions
                        .iter()
                        .map(|prediction| (prediction.invocation.clone(), prediction.clone()))
                        .collect();
                    let has_missing_fallback = state
                        .predictions
                        .keys()
                        .any(|invocation| !remote_predictions.contains_key(invocation));
                    state.remote_predictions = if has_missing_fallback {
                        None
                    } else {
                        Some(remote_predictions)
                    };
                    state.remote_etag = Some(etag);
                    state.remote_manifest = Some(manifest.clone());
                    // Same-valued or conflicting remote entries already cover
                    // this unknown-provenance baseline. Missing invocations do
                    // not: publish those as fallbacks without letting a stale
                    // local value overwrite a value the remote already knows.
                    state.remote_publication_needed = has_missing_fallback;
                    Some(manifest)
                }
                Ok(None) => {
                    state.remote_predictions = if state.predictions.is_empty() {
                        Some(BTreeMap::new())
                    } else {
                        None
                    };
                    state.remote_publication_needed = !state.predictions.is_empty();
                    None
                }
                Err(error) => {
                    state.remote_predictions = None;
                    state.remote_publication_needed = false;
                    self.note_remote_failure();
                    warn!("remote task action manifest lookup failed for {task}: {error}");
                    None
                }
            }
        } else {
            None
        };
        let completed = state
            .pending_predictions
            .values()
            .cloned()
            .collect::<Vec<_>>();
        if write_only
            && state.changed_predictions.is_empty()
            && !should_refresh_task_prediction_order(
                state.predictions.len(),
                !state.pending_predictions.is_empty(),
            )
            && !state.remote_publication_needed
        {
            self.task_actions.lock().unwrap().remove(run);
            return Ok(completed);
        }
        let (manifest, concurrent_updates) = {
            let _write_guard = self.manifest_write_lock.lock().unwrap();
            let _file_guard = self.lock_task_manifest(&task)?;
            let current_manifest = self.load_task_manifest(&task)?;
            let predictions = current_manifest
                .as_ref()
                .map(|manifest| manifest.predictions.clone())
                .unwrap_or_default();
            let concurrent_updates = concurrent_task_predictions(&predictions, &state);
            let effective_updates = effective_task_updates(&predictions, &state);
            let required =
                required_local_predictions(&predictions, &effective_updates, &concurrent_updates);
            let predictions = update_task_predictions(predictions, &effective_updates, &required)?;
            let manifest = TaskActionManifest {
                version: TASK_ACTION_MANIFEST_VERSION,
                task: task.clone(),
                predictions,
            };
            validate_task_manifest(&manifest, &task)?;
            if current_manifest.as_ref() != Some(&manifest) {
                self.persist_task_manifest(&manifest)?;
            }
            (manifest, concurrent_updates)
        };
        self.task_actions.lock().unwrap().remove(run);
        if self.remote_mode.writes() {
            // A manifest advertises the actions it predicts, so it must not
            // reach the remote cache before the results a reader would then go
            // looking for -- nor name a result that never got there at all.
            let mut manifest = manifest;
            let (held, failed) = if let Some(uploads) = &self.uploads {
                let actions: Vec<CacheDigest> = manifest
                    .predictions
                    .iter()
                    .map(|prediction| prediction.action.clone())
                    .collect();
                uploads.wait_for_action_outcomes(&actions).await
            } else {
                (BTreeSet::new(), BTreeSet::new())
            };
            let proven_uploads = held.difference(&failed).cloned().collect();
            let (withhold_candidates, replaced, unpublished) =
                if let Some(remote_predictions) = &state.remote_predictions {
                    let unproven_predictions =
                        unproven_task_predictions(&manifest.predictions, remote_predictions);
                    let unproven = unproven_predictions.values().cloned().collect();
                    let candidates = unproven_predictions.keys().cloned().collect();
                    let replaced = replaced_task_predictions(remote_predictions, &candidates);
                    // A successful upload by this queue proves an otherwise
                    // local-only value is now safe to advertise.
                    let unpublished = unpublished_task_actions(unproven, &held, failed);
                    (candidates, replaced, unpublished)
                } else {
                    // Unknown provenance must not turn an inherited baseline
                    // into thousands of false negatives. Still withhold values
                    // this run actually changed unless its own upload proves
                    // them publishable.
                    let candidates: BTreeSet<_> = state
                        .changed_predictions
                        .keys()
                        .filter(|invocation| {
                            manifest
                                .predictions
                                .iter()
                                .any(|prediction| &prediction.invocation == *invocation)
                        })
                        .cloned()
                        .collect();
                    let unproven = manifest
                        .predictions
                        .iter()
                        .filter(|prediction| candidates.contains(&prediction.invocation))
                        .map(|prediction| prediction.action.clone())
                        .collect();
                    let unpublished = unpublished_task_actions(unproven, &held, failed);
                    (candidates, Vec::new(), unpublished)
                };
            let prediction_count = manifest.predictions.len();
            let withheld = withhold_unpublished_updates(
                &mut manifest,
                &withhold_candidates,
                &replaced,
                &unpublished,
            );
            if !withheld.is_empty() {
                // The local manifest keeps them: this checkout can still use
                // what it built, and a later session can publish it.
                warn!(
                    "{} of {} predicted actions were not published, so the remote task action manifest omits them",
                    withheld.len(),
                    prediction_count
                );
            }
            let published: BTreeMap<_, _> = manifest
                .predictions
                .iter()
                .map(|prediction| (prediction.invocation.clone(), prediction))
                .collect();
            let (required, fallbacks) = remote_publication_precedence(
                &state,
                &completed,
                &concurrent_updates,
                &proven_uploads,
                &published,
                &withheld,
            );
            let publication_base = write_only_remote.or(state.remote_manifest);
            if let Some(remote) = publication_base {
                manifest = merge_task_manifests(&task, remote, manifest, &required, &fallbacks)?;
            }
            match self
                .put_remote_task_manifest(&task, manifest, state.remote_etag, &required, &fallbacks)
                .await
            {
                Ok(remote_manifest) => {
                    let _write_guard = self.manifest_write_lock.lock().unwrap();
                    let reconciliation = (|| {
                        let _file_guard = self.lock_task_manifest(&task)?;
                        let manifest = match self.load_task_manifest(&task)? {
                            Some(local) => {
                                let required = local
                                    .predictions
                                    .iter()
                                    .map(|prediction| prediction.invocation.clone())
                                    .collect();
                                match merge_task_manifests(
                                    &task,
                                    remote_manifest,
                                    local.clone(),
                                    &required,
                                    &BTreeSet::new(),
                                ) {
                                    Ok(manifest) => manifest,
                                    Err(error) => {
                                        warn!(
                                            "remote task action manifest merge failed for {task}: {error}"
                                        );
                                        local
                                    }
                                }
                            }
                            None => remote_manifest,
                        };
                        self.persist_task_manifest(&manifest)
                    })();
                    if let Err(error) = reconciliation {
                        warn!(
                            "remote task action manifest reconciliation failed for {task}: {error}"
                        );
                    }
                }
                Err(error) => {
                    self.note_remote_failure();
                    warn!("remote task action manifest upload failed for {task}: {error}");
                }
            }
        }
        Ok(completed)
    }

    fn task_manifest_path(&self, task: &str) -> PathBuf {
        self.manifest_dir.join(format!("{task}.json"))
    }

    fn task_manifest_lock_path(&self, task: &str) -> PathBuf {
        self.manifest_dir.join("locks").join(format!("{task}.lock"))
    }

    fn lock_task_manifest(&self, task: &str) -> Result<fslock::LockFile> {
        let path = self.task_manifest_lock_path(task);
        fs::create_dir_all(path.parent().expect("task manifest lock has a parent"))?;
        let mut lock = fslock::LockFile::open(&path)?;
        lock.lock()?;
        Ok(lock)
    }

    fn load_task_manifest(&self, task: &str) -> Result<Option<TaskActionManifest>> {
        match fs::read(self.task_manifest_path(task)) {
            Ok(contents) => Ok(Some(self.parse_task_manifest(task, &contents, false)?)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(error.into()),
        }
    }

    fn parse_task_manifest(
        &self,
        task: &str,
        contents: &[u8],
        require_canonical: bool,
    ) -> Result<TaskActionManifest> {
        let manifest: TaskActionManifest = serde_json::from_slice(contents)?;
        validate_task_manifest(&manifest, task)?;
        if require_canonical && canonical_json(&manifest)? != contents {
            bail!("task action manifest is not canonical JSON");
        }
        Ok(manifest)
    }

    fn task_manifest_selector(task: &str) -> Result<(Vec<u8>, CacheDigest)> {
        TaskActionManifest::selector(task)
    }

    fn persist_task_manifest(&self, manifest: &TaskActionManifest) -> Result<()> {
        let bytes = canonical_json(manifest)?;
        fs::create_dir_all(self.manifest_dir.as_path())?;
        let mut temporary = tempfile::NamedTempFile::new_in(self.manifest_dir.as_path())?;
        std::io::Write::write_all(temporary.as_file_mut(), &bytes)?;
        temporary.as_file_mut().sync_all()?;
        temporary
            .persist(self.task_manifest_path(&manifest.task))
            .map_err(|error| error.error)?;
        Ok(())
    }

    async fn get_remote_task_manifest(
        &self,
        task: &str,
    ) -> Result<Option<(TaskActionManifest, String)>> {
        let Some(remote) = &self.remote else {
            return Ok(None);
        };
        let (_, selector) = Self::task_manifest_selector(task)?;
        let _permit = self.remote_transfers.acquire().await?;
        self.stats
            .remote_manifest_lookups
            .fetch_add(1, Ordering::Relaxed);
        let _timer = AtomicDurationTimer::start(&self.stats.remote_manifest_lookup_duration_ns);
        let Some(remote_manifest) = remote.get_action_manifest(&selector).await? else {
            return Ok(None);
        };
        let manifest = self.parse_task_manifest(task, &remote_manifest.bytes, true)?;
        Ok(Some((manifest, remote_manifest.etag)))
    }

    async fn put_remote_task_manifest(
        &self,
        task: &str,
        mut manifest: TaskActionManifest,
        mut expected_etag: Option<String>,
        required: &BTreeSet<CacheDigest>,
        fallbacks: &BTreeSet<CacheDigest>,
    ) -> Result<TaskActionManifest> {
        let Some(remote) = &self.remote else {
            return Ok(manifest);
        };
        let (_, selector) = Self::task_manifest_selector(task)?;
        for _ in 0..4 {
            let bytes = canonical_json(&manifest)?;
            let outcome = {
                let _permit = self.remote_transfers.acquire().await?;
                remote
                    .put_action_manifest(&selector, &bytes, expected_etag.as_deref())
                    .await?
            };
            match outcome {
                ManifestPutOutcome::Stored => return Ok(manifest),
                ManifestPutOutcome::PreconditionFailed => {
                    let Some((remote_manifest, etag)) = self.get_remote_task_manifest(task).await?
                    else {
                        expected_etag = None;
                        continue;
                    };
                    manifest =
                        merge_task_manifests(task, remote_manifest, manifest, required, fallbacks)?;
                    expected_etag = Some(etag);
                }
            }
        }
        bail!("remote task action manifest changed too frequently")
    }

    /// Return a snapshot of this session's cache activity.
    pub fn stats(&self) -> AgentStats {
        AgentStats {
            session_duration_ns: 0,
            lookups: self.stats.lookups.load(Ordering::Relaxed),
            unconsulted: self.stats.unconsulted.load(Ordering::Relaxed),
            incremental_compilations: self.stats.incremental_compilations.load(Ordering::Relaxed),
            hits: self.stats.hits.load(Ordering::Relaxed),
            stores: self.stats.stores.load(Ordering::Relaxed),
            stored_bytes: self.stats.stored_bytes.load(Ordering::Relaxed),
            verifications: self.stats.verifications.load(Ordering::Relaxed),
            divergences: self.stats.divergences.load(Ordering::Relaxed),
            downloaded_bytes: self.stats.downloaded_bytes.load(Ordering::Relaxed),
            uploaded_bytes: self.stats.uploaded_bytes.load(Ordering::Relaxed),
            background_uploads: self.stats.background_uploads.load(Ordering::Relaxed),
            background_upload_failures: self
                .stats
                .background_upload_failures
                .load(Ordering::Relaxed),
            remote_blob_pack_uploads: self.stats.remote_blob_pack_uploads.load(Ordering::Relaxed),
            remote_blob_pack_upload_blobs: self
                .stats
                .remote_blob_pack_upload_blobs
                .load(Ordering::Relaxed),
            upload_drain_duration_ns: self.stats.upload_drain_duration_ns.load(Ordering::Relaxed),
            prefetched_actions: self.stats.prefetched_actions.load(Ordering::Relaxed),
            predictions_loaded: self.stats.predictions_loaded.load(Ordering::Relaxed),
            bypasses: self.stats.bypasses.lock().unwrap().clone(),
            avoided_compiler_duration_ns: self
                .stats
                .avoided_compiler_duration_ns
                .load(Ordering::Relaxed),
            wrapper_phases_ns: self.stats.wrapper_phases_ns.lock().unwrap().clone(),
            compiler: self.stats.compiler.lock().unwrap().clone(),
            slow_compilations: self.stats.slow_compilations.lock().unwrap().clone(),
            unit_outcomes: self.stats.unit_outcomes.lock().unwrap().clone(),
            remote_failures: self.stats.remote_failures.load(Ordering::Relaxed),
            remote_manifest_lookups: self.stats.remote_manifest_lookups.load(Ordering::Relaxed),
            remote_manifest_lookup_duration_ns: self
                .stats
                .remote_manifest_lookup_duration_ns
                .load(Ordering::Relaxed),
            remote_action_lookups: self.stats.remote_action_lookups.load(Ordering::Relaxed),
            remote_action_lookup_duration_ns: self
                .stats
                .remote_action_lookup_duration_ns
                .load(Ordering::Relaxed),
            remote_blob_requests: self.stats.remote_blob_requests.load(Ordering::Relaxed),
            remote_blob_pack_requests: self.stats.remote_blob_pack_requests.load(Ordering::Relaxed),
            remote_blob_pack_blobs: self.stats.remote_blob_pack_blobs.load(Ordering::Relaxed),
            remote_blob_transfer_duration_ns: self
                .stats
                .remote_blob_transfer_duration_ns
                .load(Ordering::Relaxed),
            local_cas_write_duration_ns: self
                .stats
                .local_cas_write_duration_ns
                .load(Ordering::Relaxed),
            prefetch_runs: self.stats.prefetch_runs.load(Ordering::Relaxed),
            prefetch_duration_ns: self.stats.prefetch_duration_ns.load(Ordering::Relaxed),
            materialization_duration_ns: self
                .stats
                .materialization_duration_ns
                .load(Ordering::Relaxed),
            restored_output_files: self.stats.restored_output_files.load(Ordering::Relaxed),
            restored_output_bytes: self.stats.restored_output_bytes.load(Ordering::Relaxed),
            reflinked_output_files: self.stats.reflinked_output_files.load(Ordering::Relaxed),
            reflinked_output_bytes: self.stats.reflinked_output_bytes.load(Ordering::Relaxed),
            hardlinked_output_files: self.stats.hardlinked_output_files.load(Ordering::Relaxed),
            hardlinked_output_bytes: self.stats.hardlinked_output_bytes.load(Ordering::Relaxed),
            copied_output_files: self.stats.copied_output_files.load(Ordering::Relaxed),
            copied_output_bytes: self.stats.copied_output_bytes.load(Ordering::Relaxed),
            reused_output_files: self.stats.reused_output_files.load(Ordering::Relaxed),
            reused_output_bytes: self.stats.reused_output_bytes.load(Ordering::Relaxed),
        }
    }

    /// Handle requests without a transport connection.
    ///
    /// Persistent wrappers use this entry point when Cargo invokes tuist_cargo_cache outside
    /// an orchestrated session. It intentionally has the same response
    /// semantics as [`Self::handle_connection`], while leaving framing and the
    /// version handshake to callers that actually cross a process boundary.
    pub async fn handle_requests(
        &self,
        requests: impl IntoIterator<Item = AgentRequest>,
    ) -> Vec<AgentResponse> {
        let mut connection = ConnectionUploads::default();
        let mut responses = Vec::new();
        for request in requests {
            responses.push(self.respond_on(request, &mut connection).await);
        }
        self.release_bypass(&mut connection);
        responses
    }

    /// Emit a held bypass reason that no compiler run claimed.
    fn release_bypass(&self, connection: &mut ConnectionUploads) {
        if let Some(kind) = connection.take_bypass() {
            self.emit(|| AgentEvent::Bypass { kind });
        }
    }

    fn write_lock(&self, digest: &CacheDigest) -> Arc<tokio::sync::Mutex<()>> {
        Self::digest_lock(&self.write_locks, digest)
    }

    fn action_lock(&self, digest: &CacheDigest) -> Arc<tokio::sync::Mutex<()>> {
        Self::digest_lock(&self.action_locks, digest)
    }

    fn digest_lock(
        locks: &Mutex<BTreeMap<CacheDigest, Weak<tokio::sync::Mutex<()>>>>,
        digest: &CacheDigest,
    ) -> Arc<tokio::sync::Mutex<()>> {
        let mut locks = locks.lock().unwrap();
        locks.retain(|_, lock| lock.strong_count() > 0);
        if let Some(lock) = locks.get(digest).and_then(Weak::upgrade) {
            return lock;
        }
        let lock = Arc::new(tokio::sync::Mutex::new(()));
        locks.insert(digest.clone(), Arc::downgrade(&lock));
        lock
    }

    /// Answer one request outside any connection.
    ///
    /// An upload queued this way has no sibling requests to order against, so
    /// the queue falls back to treating every blob it holds as a prerequisite.
    #[cfg(test)]
    async fn respond(&self, request: AgentRequest) -> AgentResponse {
        let mut connection = ConnectionUploads::default();
        let response = self.respond_on(request, &mut connection).await;
        self.release_bypass(&mut connection);
        response
    }

    async fn respond_on(
        &self,
        request: AgentRequest,
        connection: &mut ConnectionUploads,
    ) -> AgentResponse {
        match &request {
            AgentRequest::FindActionPrediction { task, .. }
            | AgentRequest::RecordActionPrediction { task, .. } => {
                self.ensure_task_loaded(task).await;
            }
            _ => {}
        }
        let result = match request {
            AgentRequest::BeginTask { task } => self
                .begin_task(&task)
                .await
                .map(|run| AgentResponse::TaskBegun { run }),
            AgentRequest::CommitTask { run } => self
                .commit_task(&run)
                .await
                .map(|()| AgentResponse::TaskCommitted),
            AgentRequest::FindBlob { digest } => self.find_blob(&digest).await,
            AgentRequest::FindBlobs { digests } => self.find_blobs(digests).await,
            AgentRequest::StoreBlob { digest, source } => {
                self.store_blob(&digest, &source, connection).await
            }
            // Not counted here: a lookup is counted with the outcome it ends
            // in. One compilation can read several results -- a second
            // candidate key, a flight it waited on, an existing result after
            // it compiled -- and a read whose response is lost cannot say
            // whether it arrived, so counting reads could never agree with
            // the hits and misses they produced.
            AgentRequest::FindActionResult { action } => {
                let started = Instant::now();
                let response = self.find_action_result(&action).await;
                crate::public_cache_report::timing(&action, "read", started);
                response
            }
            AgentRequest::RecordActionHit {
                action,
                restore,
                crate_name,
            } => {
                let diagnostic = connection
                    .take_action_diagnostic("hit", crate_name.as_deref())
                    .map(|diagnostic| AgentEvent::ActionDiagnostic {
                        outcome: "hit".into(),
                        crate_name: crate_name.clone(),
                        diagnostic,
                    });
                self.record_action_hit(&action, restore, crate_name, diagnostic)
            }
            AgentRequest::RecordBypass { kind } => {
                *self
                    .stats
                    .bypasses
                    .lock()
                    .unwrap()
                    .entry(kind.clone())
                    .or_insert(0) += 1;
                // Held until the connection's next compiler run, which is the
                // compilation this bypass describes when the shim reports the
                // two together. A reason nothing claims is emitted on its own.
                if let Some(unclaimed) = connection.hold_bypass(kind) {
                    self.emit(|| AgentEvent::Bypass { kind: unclaimed });
                }
                Ok(AgentResponse::BypassRecorded)
            }
            AgentRequest::RecordUnconsulted => {
                self.stats.unconsulted.fetch_add(1, Ordering::Relaxed);
                self.emit(|| AgentEvent::Unconsulted);
                Ok(AgentResponse::UnconsultedRecorded)
            }
            AgentRequest::RecordWarning { message } => match parse_action_diagnostic(&message) {
                Some(Ok((outcome, crate_name, diagnostic))) => {
                    connection.record_action_diagnostic(outcome, crate_name, diagnostic);
                    Ok(AgentResponse::WarningRecorded)
                }
                Some(Err(error)) => Err(error),
                None => self.record_diagnostic(DiagnosticLevel::Warning, message),
            },
            AgentRequest::RecordDebug { target, message } => (|| {
                if target.is_empty()
                    || target.len() > 256
                    || target.contains(['\n', '\r', '\0'])
                    || message.is_empty()
                    || message.len() > MAX_DIAGNOSTIC_BYTES
                    || message.contains(['\n', '\r', '\0'])
                {
                    bail!("invalid shim debug record");
                }
                if target == "tuist_cargo_cache::unit-outcome" {
                    let (unit, outcome): (String, String) = serde_json::from_str(&message)?;
                    // Recorded as what the cache did, which is the column the
                    // TUI shows. Whether a compilation kept incremental state
                    // is reported by the summary, not per unit.
                    let (outcome, _) = lookup_outcome(&outcome);
                    if unit.len() > 256
                        || !unit.contains(':')
                        || !matches!(
                            outcome,
                            "hit" | "miss" | "bypass" | "unconsulted" | "verification"
                        )
                    {
                        bail!("invalid unit outcome");
                    }
                    self.stats
                        .unit_outcomes
                        .lock()
                        .unwrap()
                        .entry(unit)
                        .or_default()
                        .insert(outcome.to_string());
                } else {
                    debug!(target: &target, "{message}");
                }
                Ok(AgentResponse::DebugRecorded)
            })(),
            AgentRequest::RecordError { message } => {
                self.record_diagnostic(DiagnosticLevel::Error, message)
            }
            AgentRequest::FindFileDigests { scope, files } => self.find_file_digests(scope, files),
            AgentRequest::JoinActionPromise {
                adapter,
                invocation,
            } => self.join_action_promise(&adapter, &invocation).await,
            AgentRequest::CompleteActionPromise { claim, prediction } => {
                self.complete_action_promise(&claim, &prediction).await
            }
            AgentRequest::ResolveFileDigests { scope, files } => {
                self.resolve_file_digests(scope, files).await
            }
            AgentRequest::RecordFileDigests { scope, entries } => {
                self.record_file_digests(scope, entries)
            }
            AgentRequest::RecordWrapperTiming { timing } => (|| {
                if timing.spans.len() > 512
                    || timing.phases_ns.len() > 32
                    || timing.adapter.len() > 64
                    || timing.unit.as_ref().is_some_and(|s| s.len() > 1024)
                    || timing.unit_id.as_ref().is_some_and(|s| s.len() > 256)
                    || timing.dependencies.len() > 4096
                    || timing.dependencies.iter().any(|s| s.len() > 256)
                    || timing.phases_ns.keys().any(|s| s.len() > 64)
                    || timing.spans.iter().any(|s| s.name.len() > 64)
                {
                    bail!("wrapper timing exceeds telemetry limits");
                }
                {
                    let mut phases = self.stats.wrapper_phases_ns.lock().unwrap();
                    for (phase, duration) in &timing.phases_ns {
                        let total = phases.entry(phase.clone()).or_default();
                        *total = total.saturating_add(*duration);
                    }
                }
                self.emit(|| AgentEvent::WrapperTiming { timing });
                Ok(AgentResponse::WrapperTimingRecorded)
            })(),
            AgentRequest::RecordCompilerInvocation {
                outcome,
                crate_name,
                duration_ns,
            } => {
                // Normalized before the diagnostic is claimed: it was stored
                // under the lookup outcome, and an unnormalized name here would
                // never find it.
                let (outcome, incremental) = lookup_outcome(&outcome);
                let outcome = outcome.to_string();
                let bypass = if outcome == "bypass" {
                    connection.take_bypass()
                } else {
                    self.release_bypass(connection);
                    None
                };
                let diagnostic = connection
                    .take_action_diagnostic(&outcome, crate_name.as_deref())
                    .map(|diagnostic| AgentEvent::ActionDiagnostic {
                        outcome: outcome.clone(),
                        crate_name: crate_name.clone(),
                        diagnostic,
                    });
                self.record_compiler_invocation(
                    &outcome,
                    incremental,
                    crate_name.as_deref(),
                    duration_ns,
                    diagnostic,
                    bypass,
                )
            }
            AgentRequest::RecordActionVerification { matched, restore } => {
                self.record_materialization(restore);
                self.stats.verifications.fetch_add(1, Ordering::Relaxed);
                if !matched {
                    self.stats.divergences.fetch_add(1, Ordering::Relaxed);
                }
                self.emit(|| AgentEvent::Verification { matched, restore });
                Ok(AgentResponse::ActionVerificationRecorded)
            }
            AgentRequest::StoreActionResult { result } => {
                let started = Instant::now();
                let response = self.store_action_result(&result, connection).await;
                crate::public_cache_report::timing(&result.action, "write", started);
                response
            }
            AgentRequest::FindActionPrediction { task, invocation } => {
                self.find_action_prediction(&task, &invocation)
            }
            AgentRequest::RecordActionPrediction { task, prediction } => {
                self.record_action_prediction(&task, prediction)
            }
            AgentRequest::FindExecutableIdentity {
                executable,
                environment,
            } => self.find_executable_identity(executable, environment),
            AgentRequest::StoreExecutableIdentity {
                executable,
                environment,
                stdout,
                pins,
            } => self.store_executable_identity(executable, environment, stdout, pins),
            AgentRequest::Hello { .. } => {
                Err(eyre::eyre!("hello is only valid as the first request"))
            }
        };
        result.unwrap_or_else(|error| AgentResponse::Error {
            message: error.to_string(),
        })
    }

    async fn find_blob(&self, digest: &CacheDigest) -> Result<AgentResponse> {
        if let Some(path) = self.find_verified_blob(digest)? {
            return Ok(AgentResponse::Blob { path: Some(path) });
        }
        if !self.remote_mode.reads() {
            return Ok(AgentResponse::Blob { path: None });
        }
        let Some(remote) = &self.remote else {
            return Ok(AgentResponse::Blob { path: None });
        };
        match self.fetch_remote_blob(remote, digest).await {
            Ok(path) => Ok(AgentResponse::Blob { path: Some(path) }),
            Err(error) => {
                warn!(
                    "remote cache blob lookup failed for {}: {error}",
                    digest.hash
                );
                Ok(AgentResponse::Blob { path: None })
            }
        }
    }

    async fn find_blobs(&self, digests: Vec<CacheDigest>) -> Result<AgentResponse> {
        let mut paths = BTreeMap::new();
        let mut missing = Vec::new();
        for digest in &digests {
            match self.find_verified_blob(digest)? {
                Some(path) => {
                    paths.insert(digest.clone(), path);
                }
                None => {
                    missing.push(digest.clone());
                }
            }
        }

        if !missing.is_empty()
            && self.remote_mode.reads()
            && let Some(remote) = &self.remote
        {
            paths.extend(self.fetch_remote_blobs(remote, missing, None).await);
        }

        Ok(AgentResponse::Blobs {
            paths: digests
                .into_iter()
                .map(|digest| paths.get(&digest).cloned())
                .collect(),
        })
    }

    async fn store_blob(
        &self,
        digest: &CacheDigest,
        source: &Path,
        connection: &mut ConnectionUploads,
    ) -> Result<AgentResponse> {
        let path = {
            let lock = self.write_lock(digest);
            let _guard = lock.lock().await;
            if let Some(path) = self.find_verified_blob(digest)? {
                path
            } else {
                let timer = AtomicDurationTimer::start(&self.stats.local_cas_write_duration_ns);
                let path = self.cas.store_file(digest, source)?;
                drop(timer);
                self.remember_verified_blob(digest, &path);
                self.stats.stores.fetch_add(1, Ordering::Relaxed);
                self.stats
                    .stored_bytes
                    .fetch_add(digest.size, Ordering::Relaxed);
                path
            }
        };
        // The object is durable locally, so the build has what it needs and the
        // remote publication can happen after this request returns.
        if let Some(uploads) = &self.uploads {
            uploads.queue_blob(digest, path.clone(), connection);
        }
        Ok(AgentResponse::Stored { path })
    }

    fn find_verified_blob(&self, digest: &CacheDigest) -> Result<Option<PathBuf>> {
        let remembered = self.verified_blobs.lock().unwrap().get(digest).cloned();
        if let Some(remembered) = remembered {
            // The contents behind this digest were hashed in full when the
            // session first reached for them. Hashing again on every later
            // lookup would re-read each dependency's rlib once per crate that
            // links it, so what is rechecked here is that the file has not
            // been written since: an overwrite moves the modification time,
            // and truncation or eviction changes the length or removes it.
            // Only a replacement that reproduces both -- which no writer in
            // the store does, since blobs are published by rename under a
            // content-derived name -- would go unnoticed until `tuist_cargo_cache cache
            // verify` reads the store back in full.
            if remembered.is_unchanged() {
                return Ok(Some(remembered.path));
            }
            self.verified_blobs.lock().unwrap().remove(digest);
        }
        // Blobs are published by rename without an fsync, so a crash can leave
        // one torn under a valid name. It is not restored from, and it is not
        // an error either: the compilation runs again and its publication
        // replaces the bad bytes, the same way a blob that was never stored
        // gets there. Reporting it as a failure would surface a warning for a
        // build that is behaving correctly.
        let path = match self.cas.find(digest) {
            Ok(path) => path,
            Err(error) => {
                warn!(
                    "local CAS blob {} is not restorable and will be republished: {error}",
                    digest.hash
                );
                return Ok(None);
            }
        };
        if let Some(path) = &path {
            self.remember_verified_blob(digest, path);
        }
        Ok(path)
    }

    fn remember_verified_blob(&self, digest: &CacheDigest, path: &Path) {
        let Some(verified) = VerifiedBlob::describe(path) else {
            // Without an identity to compare against there is nothing to
            // shortcut safely, so the digest stays unremembered and every
            // lookup re-reads it.
            return;
        };
        self.verified_blobs
            .lock()
            .unwrap()
            .insert(digest.clone(), verified);
    }

    async fn find_action_result(&self, action: &CacheDigest) -> Result<AgentResponse> {
        if let Some(result) = self.actions.find(action)? {
            return Ok(AgentResponse::ActionResult {
                result: Some(result),
            });
        }
        if !self.remote_mode.reads() {
            return Ok(AgentResponse::ActionResult { result: None });
        }
        let Some(remote) = &self.remote else {
            return Ok(AgentResponse::ActionResult { result: None });
        };
        let lock = self.action_lock(action);
        let _guard = lock.lock().await;
        if let Some(result) = self.actions.find(action)? {
            return Ok(AgentResponse::ActionResult {
                result: Some(result),
            });
        }
        if let Some(result) = self
            .pending_remote_actions
            .lock()
            .unwrap()
            .get(action)
            .cloned()
        {
            return Ok(AgentResponse::ActionResult {
                result: Some(result),
            });
        }
        let _permit = self.remote_transfers.acquire().await?;
        match self.get_remote_action_result(remote, action).await {
            Ok(Some(result)) => {
                self.pending_remote_actions
                    .lock()
                    .unwrap()
                    .insert(action.clone(), result.clone());
                Ok(AgentResponse::ActionResult {
                    result: Some(result),
                })
            }
            Ok(None) => Ok(AgentResponse::ActionResult { result: None }),
            Err(error) => {
                self.note_remote_failure();
                warn!(
                    "remote cache action lookup failed for {}: {error}",
                    action.hash
                );
                Ok(AgentResponse::ActionResult { result: None })
            }
        }
    }

    async fn store_action_result(
        &self,
        result: &RemoteActionResult,
        connection: &ConnectionUploads,
    ) -> Result<AgentResponse> {
        let path = self.actions.store(result)?;
        if let Some(uploads) = &self.uploads {
            uploads.queue_action_result(result, connection);
        }
        Ok(AgentResponse::ActionStored { path })
    }

    async fn join_action_promise(
        &self,
        adapter: &str,
        invocation: &CacheDigest,
    ) -> Result<AgentResponse> {
        if !self.remote_mode.reads() || !self.remote_mode.writes() {
            return Ok(AgentResponse::ActionPromise {
                claim: None,
                prediction: None,
            });
        }
        let Some(remote) = &self.remote else {
            return Ok(AgentResponse::ActionPromise {
                claim: None,
                prediction: None,
            });
        };
        let deadline = Instant::now() + ACTION_PROMISE_WAIT;
        loop {
            let _permit = self.remote_transfers.acquire().await?;
            let state = remote.join_action_promise(invocation, adapter).await;
            drop(_permit);
            match state {
                Ok(Some(ActionPromiseState::Claimed { claim })) => {
                    return Ok(AgentResponse::ActionPromise {
                        claim: Some(claim),
                        prediction: None,
                    });
                }
                Ok(Some(ActionPromiseState::Complete { prediction })) => {
                    return Ok(AgentResponse::ActionPromise {
                        claim: None,
                        prediction: Some(prediction),
                    });
                }
                Ok(Some(ActionPromiseState::Pending { retry_after_ms }))
                    if Instant::now() < deadline =>
                {
                    tokio::time::sleep(Duration::from_millis(retry_after_ms.clamp(10, 5_000)))
                        .await;
                }
                Ok(Some(ActionPromiseState::Pending { .. }) | None) => {
                    return Ok(AgentResponse::ActionPromise {
                        claim: None,
                        prediction: None,
                    });
                }
                Ok(Some(_)) => {
                    return Ok(AgentResponse::ActionPromise {
                        claim: None,
                        prediction: None,
                    });
                }
                Err(error) => {
                    self.note_remote_failure();
                    warn!(
                        "remote cache action promise failed for {}: {error}",
                        invocation.hash
                    );
                    return Ok(AgentResponse::ActionPromise {
                        claim: None,
                        prediction: None,
                    });
                }
            }
        }
    }

    async fn complete_action_promise(
        &self,
        claim: &str,
        prediction: &ActionPrediction,
    ) -> Result<AgentResponse> {
        prediction.validate()?;
        let Some(remote) = &self.remote else {
            return Ok(AgentResponse::ActionPromiseCompleted);
        };
        let Some(uploads) = &self.uploads else {
            return Ok(AgentResponse::ActionPromiseCompleted);
        };
        if uploads
            .wait_for_actions(std::slice::from_ref(&prediction.action))
            .await
            .contains(&prediction.action)
        {
            // Never promise an action result the server does not hold. The
            // server lease expires and another runner gets to repair it.
            return Ok(AgentResponse::ActionPromiseCompleted);
        }
        let completion = ActionPromiseCompletion {
            claim: claim.to_string(),
            prediction: prediction.clone(),
        };
        let _permit = self.remote_transfers.acquire().await?;
        if let Err(error) = remote
            .complete_action_promise(&prediction.invocation, &completion)
            .await
        {
            self.note_remote_failure();
            warn!(
                "remote cache action promise completion failed for {}: {error}",
                prediction.invocation.hash
            );
        }
        Ok(AgentResponse::ActionPromiseCompleted)
    }

    /// Record that a remote operation failed and the build carried on without it.
    fn note_remote_failure(&self) {
        self.stats.remote_failures.fetch_add(1, Ordering::Relaxed);
    }

    async fn get_remote_action_result(
        &self,
        remote: &RemoteCacheClient,
        action: &CacheDigest,
    ) -> Result<Option<RemoteActionResult>> {
        self.stats
            .remote_action_lookups
            .fetch_add(1, Ordering::Relaxed);
        let _timer = AtomicDurationTimer::start(&self.stats.remote_action_lookup_duration_ns);
        remote.get_action_result(action).await
    }

    fn record_action_hit(
        &self,
        action: &CacheDigest,
        restore: RestoreStats,
        crate_name: Option<String>,
        diagnostic: Option<AgentEvent>,
    ) -> Result<AgentResponse> {
        validate_crate_name(crate_name.as_deref())?;
        if self.actions.find(action)?.is_none() {
            let pending = self.pending_remote_actions.lock().unwrap().remove(action);
            if let Some(result) = pending {
                self.actions.store(&result)?;
            } else {
                bail!("cannot record a hit for a missing action result");
            }
        }
        let public_diagnostic = match &diagnostic {
            Some(AgentEvent::ActionDiagnostic { diagnostic, .. }) => Some(diagnostic),
            _ => None,
        };
        crate::public_cache_report::task(action, crate_name.as_deref(), "hit", public_diagnostic);
        self.record_restore(restore);
        self.stats.lookups.fetch_add(1, Ordering::Relaxed);
        self.stats.hits.fetch_add(1, Ordering::Relaxed);
        self.emit_action(
            diagnostic,
            AgentEvent::ActionHit {
                crate_name,
                restore,
            },
        );
        Ok(AgentResponse::ActionHitRecorded)
    }

    fn record_restore(&self, restore: RestoreStats) {
        self.record_materialization(restore);
        atomic_saturating_add(
            &self.stats.avoided_compiler_duration_ns,
            restore.avoided_compiler_duration_ns,
        );
        atomic_saturating_add(&self.stats.restored_output_files, restore.output_files);
        atomic_saturating_add(&self.stats.restored_output_bytes, restore.output_bytes);
        atomic_saturating_add(
            &self.stats.reflinked_output_files,
            restore.reflinked_output_files,
        );
        atomic_saturating_add(
            &self.stats.reflinked_output_bytes,
            restore.reflinked_output_bytes,
        );
        atomic_saturating_add(
            &self.stats.hardlinked_output_files,
            restore.hardlinked_output_files,
        );
        atomic_saturating_add(
            &self.stats.hardlinked_output_bytes,
            restore.hardlinked_output_bytes,
        );
        atomic_saturating_add(&self.stats.copied_output_files, restore.copied_output_files);
        atomic_saturating_add(&self.stats.copied_output_bytes, restore.copied_output_bytes);
        atomic_saturating_add(&self.stats.reused_output_files, restore.reused_output_files);
        atomic_saturating_add(&self.stats.reused_output_bytes, restore.reused_output_bytes);
    }

    fn record_compiler_invocation(
        &self,
        outcome: &str,
        incremental: bool,
        crate_name: Option<&str>,
        duration_ns: u64,
        diagnostic: Option<AgentEvent>,
        bypass: Option<String>,
    ) -> Result<AgentResponse> {
        if !matches!(outcome, "miss" | "unconsulted" | "bypass" | "verification") {
            bail!("invalid compiler invocation outcome");
        }
        validate_crate_name(crate_name)?;
        if !incremental
            && outcome != "bypass"
            && let Some(AgentEvent::ActionDiagnostic { diagnostic, .. }) = &diagnostic
        {
            crate::public_cache_report::task(
                &diagnostic.action,
                crate_name,
                outcome,
                Some(diagnostic),
            );
        }
        if incremental {
            self.stats
                .incremental_compilations
                .fetch_add(1, Ordering::Relaxed);
        }
        // A miss and a verification each ended a lookup, as a hit does.
        if matches!(outcome, "miss" | "verification") {
            self.stats.lookups.fetch_add(1, Ordering::Relaxed);
        }
        let mut compiler = self.stats.compiler.lock().unwrap();
        let stats = compiler.entry(outcome.to_string()).or_default();
        stats.invocations = stats.invocations.saturating_add(1);
        stats.duration_ns = stats.duration_ns.saturating_add(duration_ns);
        drop(compiler);
        if outcome != "verification"
            && let Some(crate_name) = crate_name.filter(|name| !name.is_empty())
        {
            let mut slow = self.stats.slow_compilations.lock().unwrap();
            let duration = slow.entry(crate_name.to_string()).or_default();
            *duration = duration.saturating_add(duration_ns);
        }
        let action = match bypass {
            Some(kind) => AgentEvent::BypassedCompilation {
                kind,
                crate_name: crate_name.map(str::to_string),
                duration_ns,
            },
            None => AgentEvent::CompilerInvocation {
                outcome: outcome.to_string(),
                crate_name: crate_name.map(str::to_string),
                duration_ns,
            },
        };
        self.emit_action(diagnostic, action);
        Ok(AgentResponse::CompilerInvocationRecorded)
    }

    fn record_materialization(&self, restore: RestoreStats) {
        atomic_saturating_add(&self.stats.materialization_duration_ns, restore.duration_ns);
    }

    /// Surface a shim diagnostic on this process's stderr.
    ///
    /// The agent lives in the process that owns the session, so printing here
    /// reaches the terminal running the build rather than the stderr of the
    /// compilation the shim stands in for -- which build scripts read as part
    /// of the compiler's answer. Deduplicated because one cause tends to fire
    /// once per compilation, and capped so a message unique per compilation
    /// cannot scroll the build away. The level is part of the deduplication
    /// key, so a fatal reason is never hidden by an earlier warning with the
    /// same text.
    fn record_diagnostic(&self, level: DiagnosticLevel, message: String) -> Result<AgentResponse> {
        if message.is_empty()
            || message.len() > MAX_DIAGNOSTIC_BYTES
            || message.contains(['\n', '\r', '\0'])
        {
            bail!("invalid shim {}", level.label());
        }
        let mut diagnostics = self.diagnostics.lock().unwrap();
        let key = (level, message.clone());
        if !diagnostics.contains(&key) {
            // An acknowledgement promises the diagnostic was surfaced. A
            // fatal shim error must be able to fall back locally when this
            // channel can no longer display it.
            if diagnostics.len() >= MAX_DIAGNOSTICS {
                bail!("shim diagnostic limit reached");
            }
            eprintln!("tuist_cargo_cache[{}]: {message}", level.label());
            self.emit(|| match level {
                DiagnosticLevel::Warning => AgentEvent::Warning {
                    message: message.clone(),
                },
                DiagnosticLevel::Error => AgentEvent::Error {
                    message: message.clone(),
                },
            });
            diagnostics.insert(key);
        }
        Ok(match level {
            DiagnosticLevel::Warning => AgentResponse::WarningRecorded,
            DiagnosticLevel::Error => AgentResponse::ErrorRecorded,
        })
    }

    /// Answer file-digest lookups from the session ledger.
    ///
    /// A recorded digest is returned only when the requested identity matches
    /// the recorded one exactly. The caller statted the file to build the
    /// identity, so this is the [`VerifiedBlob`] freshness check with the
    /// stat moved to the side that was already making it.
    fn find_file_digests(
        &self,
        scope: FileDigestScope,
        files: Vec<FileIdentity>,
    ) -> Result<AgentResponse> {
        if files.len() > MAX_FILE_DIGEST_BATCH {
            bail!("too many file-digest lookups in one request");
        }
        let ledger = self.file_digests.lock().unwrap();
        let digests = files
            .into_iter()
            .map(|file| {
                let recorded = ledger.get(&(scope, file.path.clone()))?;
                (recorded.file == file).then(|| recorded.digest.clone())
            })
            .collect();
        Ok(AgentResponse::FileDigests { digests })
    }

    /// Resolve ledger misses inside the agent so concurrent shims that name the
    /// same NFS object wait for and reuse one read instead of stampeding it.
    async fn resolve_file_digests(
        &self,
        scope: FileDigestScope,
        files: Vec<FileIdentity>,
    ) -> Result<AgentResponse> {
        if files.len() > MAX_FILE_DIGEST_BATCH {
            bail!("too many file-digest resolutions in one request");
        }
        for file in &files {
            if !file.path.is_absolute() {
                bail!("file-digest resolutions need absolute paths");
            }
        }
        let resolutions = stream::iter(
            files
                .into_iter()
                .map(|file| async move { self.resolve_file_digest(scope, file).await }),
        )
        .buffered(MAX_CONCURRENT_FILE_DIGESTS)
        .collect()
        .await;
        Ok(AgentResponse::FileDigestsResolved { resolutions })
    }

    async fn resolve_file_digest(
        &self,
        scope: FileDigestScope,
        file: FileIdentity,
    ) -> FileDigestResolution {
        let lock = {
            let key = (scope, file.clone());
            let mut locks = self.file_digest_locks.lock().unwrap();
            locks.retain(|_, lock| lock.strong_count() > 0);
            if let Some(lock) = locks.get(&key).and_then(Weak::upgrade) {
                lock
            } else {
                let lock = Arc::new(FileDigestFlight {
                    lock: tokio::sync::Mutex::new(()),
                    resolution: Mutex::new(None),
                });
                locks.insert(key, Arc::downgrade(&lock));
                lock
            }
        };
        let _flight = lock.lock.lock().await;
        if let Some(resolution) = lock.resolution.lock().unwrap().clone() {
            return resolution;
        }
        if let Some(digest) = self
            .file_digests
            .lock()
            .unwrap()
            .get(&(scope, file.path.clone()))
            .filter(|recorded| recorded.file == file)
            .map(|recorded| recorded.digest.clone())
            .filter(|digest| digest.size == file.len && file.still_describes().unwrap_or(false))
        {
            return FileDigestResolution::Digest(digest);
        }
        let Ok(_permit) = self.file_digest_permits.acquire().await else {
            return FileDigestResolution::Unresolved;
        };
        #[cfg(test)]
        self.file_digest_reads.fetch_add(1, Ordering::Relaxed);
        let path = file.path.clone();
        let resolved =
            tokio::task::spawn_blocking(move || digest_file_validated(scope, &path)).await;
        let Ok(Ok(Some(observed))) = resolved else {
            return FileDigestResolution::Unresolved;
        };
        // A racy digest is right for this read but not for reuse: it is
        // returned to this caller, never recorded or handed to waiters, who
        // read the file themselves.
        let reusable = observed.cache_identity.as_ref() == Some(&file);
        if !(reusable || observed.racy && observed.identity == file) {
            return FileDigestResolution::Unresolved;
        }
        let resolution = match observed.resolution {
            FileDigestResolution::Digest(digest) if digest.size == file.len => {
                if reusable {
                    let _ = self.record_file_digests(
                        scope,
                        vec![RecordedFileDigest {
                            file: file.clone(),
                            digest: digest.clone(),
                        }],
                    );
                }
                FileDigestResolution::Digest(digest)
            }
            FileDigestResolution::EmbeddedTimestampMacro => {
                FileDigestResolution::EmbeddedTimestampMacro
            }
            FileDigestResolution::Digest(_) | FileDigestResolution::Unresolved => {
                FileDigestResolution::Unresolved
            }
        };
        if reusable {
            *lock.resolution.lock().unwrap() = Some(resolution.clone());
        }
        resolution
    }

    /// Record digests of files a shim read in full, for later reuse.
    ///
    /// Capped rather than evicted: a session that outgrows the cap loses the
    /// shortcut for the overflow and nothing else, and no workload observed so
    /// far comes near it.
    fn record_file_digests(
        &self,
        scope: FileDigestScope,
        entries: Vec<RecordedFileDigest>,
    ) -> Result<AgentResponse> {
        if entries.len() > MAX_FILE_DIGEST_BATCH {
            bail!("too many file-digest records in one request");
        }
        for entry in &entries {
            validate_file_digest_record(entry)?;
        }
        let mut ledger = self.file_digests.lock().unwrap();
        for entry in entries {
            if ledger.len() >= MAX_FILE_DIGEST_ENTRIES
                && !ledger.contains_key(&(scope, entry.file.path.clone()))
            {
                break;
            }
            ledger.insert((scope, entry.file.path.clone()), entry);
        }
        Ok(AgentResponse::FileDigestsRecorded)
    }

    /// Start the file-digest ledger from entries an earlier session left
    /// behind, so a file nothing has touched since is not read again by the
    /// first compilation of this session that names it.
    ///
    /// Each entry stands only while its recorded identity still matches the
    /// disk, the same rule a lookup applies to what this session recorded, so
    /// a stale seed costs a hash and nothing else. Entries this session has
    /// already recorded are kept over seeded ones. Returns how many were taken.
    pub fn seed_file_digests(&self, entries: Vec<(FileDigestScope, RecordedFileDigest)>) -> usize {
        self.seed_file_digests_with(|| entries)
    }

    /// Seed the ledger from entries produced under its lock.
    ///
    /// A lookup that arrives while `load` is still reading waits for it rather
    /// than missing, so a caller can start the read in the background and let
    /// whatever else the build is doing overlap it.
    pub fn seed_file_digests_with(
        &self,
        load: impl FnOnce() -> Vec<(FileDigestScope, RecordedFileDigest)>,
    ) -> usize {
        let mut ledger = self.file_digests.lock().unwrap();
        let entries = load();
        let mut seeded = 0;
        for (scope, entry) in entries {
            if ledger.len() >= MAX_FILE_DIGEST_ENTRIES {
                break;
            }
            if validate_file_digest_record(&entry).is_err() {
                continue;
            }
            if let std::collections::btree_map::Entry::Vacant(slot) =
                ledger.entry((scope, entry.file.path.clone()))
            {
                slot.insert(entry);
                seeded += 1;
            }
        }
        seeded
    }

    /// Everything the file-digest ledger holds, for a later session to start
    /// from.
    pub fn file_digests(&self) -> Vec<(FileDigestScope, RecordedFileDigest)> {
        self.file_digests
            .lock()
            .unwrap()
            .iter()
            .map(|((scope, _), entry)| (*scope, entry.clone()))
            .collect()
    }

    fn find_action_prediction(
        &self,
        task: &str,
        invocation: &CacheDigest,
    ) -> Result<AgentResponse> {
        validate_task_identity(task)?;
        invocation.validate()?;
        let (prediction, prefetch) = {
            let mut tasks = self.task_actions.lock().unwrap();
            let Some(state) = tasks.get_mut(task) else {
                return Ok(AgentResponse::ActionPrediction { prediction: None });
            };
            activate_prediction_adapter(state, invocation)
        };
        if let Some(prefetch) = prefetch {
            self.spawn_prefetch_predictions(prefetch);
        }
        Ok(AgentResponse::ActionPrediction { prediction })
    }

    fn record_action_prediction(
        &self,
        task: &str,
        prediction: ActionPrediction,
    ) -> Result<AgentResponse> {
        validate_task_identity(task)?;
        prediction.validate()?;
        let mut tasks = self.task_actions.lock().unwrap();
        let state = tasks.entry(task.to_string()).or_default();
        if !state
            .pending_predictions
            .contains_key(&prediction.invocation)
            && state.pending_predictions.len() >= MAX_TASK_ACTION_PREDICTIONS
        {
            bail!("this task run contains too many action predictions");
        }
        let current = state.predictions.get(&prediction.invocation);
        if current != Some(&prediction) {
            match state.changed_predictions.get(&prediction.invocation) {
                // Back to what the manifest held: no longer a change.
                Some(baseline) if baseline.as_ref() == Some(&prediction) => {
                    state.changed_predictions.remove(&prediction.invocation);
                }
                // Changed again; the baseline it left is already recorded.
                Some(_) => {}
                None => {
                    state
                        .changed_predictions
                        .insert(prediction.invocation.clone(), current.cloned());
                }
            }
        }
        state
            .predictions
            .insert(prediction.invocation.clone(), prediction.clone());
        state
            .pending_predictions
            .insert(prediction.invocation.clone(), prediction);
        Ok(AgentResponse::ActionPredictionRecorded)
    }

    fn executable_identity_key(
        &self,
        executable: PathBuf,
        environment: BTreeMap<String, Option<String>>,
    ) -> Result<ExecutableIdentityKey> {
        // Restricted to the variables that actually select what an identity
        // probe reports: the toolchain rustup resolves, the SDK a linker
        // driver builds against, a `-fuse-ld` linker selection, the search
        // path a driver finds its linker on, and the working directory when
        // that search path reaches into it. Anything else would let one key
        // stand for two different compilers.
        if !environment.keys().all(|name| {
            matches!(
                name.as_str(),
                "COMPILER_PATH"
                    | "GCC_EXEC_PREFIX"
                    | "LIBRARY_PATH"
                    | "TUIST_CARGO_CACHE_FUSE_LD"
                    | "TUIST_CARGO_CACHE_WORKING_DIRECTORY"
                    | "PATH"
                    | "RUSTUP_HOME"
                    | "RUSTUP_TOOLCHAIN"
                    | "SDKROOT"
                    | "MACOSX_DEPLOYMENT_TARGET"
                    | "LIB"
                    | "UCRTVersion"
                    | "UniversalCRTSdkDir"
                    | "VCToolsInstallDir"
                    | "VCToolsVersion"
                    | "WindowsSdkDir"
                    | "WindowsSDKVersion"
            )
        }) {
            bail!("executable identity contains an unsupported environment variable");
        }
        Ok(ExecutableIdentityKey {
            executable,
            environment,
        })
    }

    fn find_executable_identity(
        &self,
        executable: PathBuf,
        environment: BTreeMap<String, Option<String>>,
    ) -> Result<AgentResponse> {
        let key = self.executable_identity_key(executable, environment)?;
        let remembered = self
            .executable_identities
            .lock()
            .unwrap()
            .get(&key)
            .cloned();
        let stdout = match remembered {
            Some(stdout) => Some(stdout),
            None => {
                let persisted = self.load_persisted_identity(&key);
                if let Some(stdout) = &persisted {
                    // Memoized like a fresh probe: the pins were checked once
                    // for this session, which is as often as a probe runs.
                    let _ = self.remember_executable_identity(&key, stdout.clone());
                }
                persisted
            }
        };
        Ok(AgentResponse::ExecutableIdentity { stdout })
    }

    fn store_executable_identity(
        &self,
        executable: PathBuf,
        environment: BTreeMap<String, Option<String>>,
        stdout: Vec<u8>,
        pins: Vec<PinnedFile>,
    ) -> Result<AgentResponse> {
        if stdout.len() > MAX_EXECUTABLE_IDENTITY_SIZE {
            bail!("executable identity exceeds {MAX_EXECUTABLE_IDENTITY_SIZE} bytes");
        }
        let key = self.executable_identity_key(executable, environment)?;
        self.remember_executable_identity(&key, stdout.clone())?;
        // Best-effort, like the ledger: a session that cannot write it probes
        // again next time, which is what it would have done anyway. A pin
        // that no longer holds means a file moved under the probe, and what
        // it printed describes neither the old file nor the new one.
        if pins.is_empty() {
        } else if !pins.iter().all(PinnedFile::holds) {
            debug!("executable identity was not persisted: a pinned file changed during the probe");
        } else if let Err(error) = self.persist_executable_identity(&key, pins, &stdout) {
            debug!("executable identity was not persisted: {error:#}");
        }
        Ok(AgentResponse::ExecutableIdentity {
            stdout: Some(stdout),
        })
    }

    fn remember_executable_identity(
        &self,
        key: &ExecutableIdentityKey,
        stdout: Vec<u8>,
    ) -> Result<()> {
        let mut identities = self.executable_identities.lock().unwrap();
        let is_new = !identities.contains_key(key);
        let previous_size = identities.get(key).map_or(0, Vec::len);
        if is_new && identities.len() >= MAX_EXECUTABLE_IDENTITIES {
            bail!("executable identity cache contains too many entries");
        }
        let retained_bytes = identities.values().map(Vec::len).sum::<usize>();
        if retained_bytes - previous_size + stdout.len() > MAX_EXECUTABLE_IDENTITY_BYTES {
            bail!("executable identity cache contains too many bytes");
        }
        identities.insert(key.clone(), stdout);
        Ok(())
    }

    fn persisted_identity_path(&self, key: &ExecutableIdentityKey) -> Result<PathBuf> {
        let selector = serde_json::to_vec(&(&key.executable, &key.environment))?;
        let digest = CacheDigest::blake3(&selector);
        Ok(self.identity_dir.join(format!("{}.json", digest.hash)))
    }

    /// What an earlier session recorded for `key`, if every file it was
    /// pinned to is still as that session saw it.
    fn load_persisted_identity(&self, key: &ExecutableIdentityKey) -> Option<Vec<u8>> {
        let path = self.persisted_identity_path(key).ok()?;
        let bytes = fs::read(path).ok()?;
        let persisted: PersistedExecutableIdentity = serde_json::from_slice(&bytes).ok()?;
        if persisted.version != PERSISTED_EXECUTABLE_IDENTITY_VERSION
            || persisted.executable != key.executable
            || persisted.environment != key.environment
            || persisted.pins.is_empty()
            || persisted.stdout.len() > MAX_EXECUTABLE_IDENTITY_SIZE
        {
            return None;
        }
        persisted
            .pins
            .iter()
            .all(PinnedFile::holds)
            .then(|| persisted.stdout.into_bytes())
    }

    fn persist_executable_identity(
        &self,
        key: &ExecutableIdentityKey,
        pins: Vec<PinnedFile>,
        stdout: &[u8],
    ) -> Result<()> {
        // An identity that is not text is kept for this session only.
        let Ok(stdout) = std::str::from_utf8(stdout) else {
            return Ok(());
        };
        let persisted = PersistedExecutableIdentity {
            version: PERSISTED_EXECUTABLE_IDENTITY_VERSION,
            executable: key.executable.clone(),
            environment: key.environment.clone(),
            pins,
            stdout: stdout.to_owned(),
        };
        let path = self.persisted_identity_path(key)?;
        fs::create_dir_all(self.identity_dir.as_path())?;
        // Not synced: a torn record reads as no record, and costs one probe.
        let mut temporary = tempfile::NamedTempFile::new_in(self.identity_dir.as_path())?;
        std::io::Write::write_all(temporary.as_file_mut(), &serde_json::to_vec(&persisted)?)?;
        temporary.persist(path).map_err(|error| error.error)?;
        Ok(())
    }

    /// Serve newline-delimited protocol requests on an authenticated session stream.
    pub async fn handle_connection<S>(&self, stream: S) -> Result<()>
    where
        S: AsyncRead + AsyncWrite + Unpin,
    {
        let (reader, mut writer) = tokio::io::split(stream);
        let mut reader = BufReader::new(reader);
        let hello = read_request(&mut reader)
            .await?
            .ok_or_else(|| eyre::eyre!("connection closed before the agent handshake"))?;
        let request: AgentRequest = serde_json::from_str(&hello)?;
        match request {
            AgentRequest::Hello {
                protocol,
                client_version,
            } if protocol == AGENT_PROTOCOL_VERSION && client_version == self.version.as_ref() => {}
            AgentRequest::Hello { protocol, .. } if protocol != AGENT_PROTOCOL_VERSION => {
                send_response(
                    &mut writer,
                    &AgentResponse::Error {
                        message: format!(
                            "unsupported agent protocol {protocol}; expected {AGENT_PROTOCOL_VERSION}"
                        ),
                    },
                )
                .await?;
                return Ok(());
            }
            AgentRequest::Hello { client_version, .. } => {
                send_response(
                    &mut writer,
                    &AgentResponse::Error {
                        message: format!(
                            "cache client {client_version} does not match agent {}",
                            self.version
                        ),
                    },
                )
                .await?;
                return Ok(());
            }
            _ => bail!("the first agent request must be hello"),
        }
        send_response(
            &mut writer,
            &AgentResponse::Hello {
                protocol: AGENT_PROTOCOL_VERSION,
                agent_version: self.version.to_string(),
            },
        )
        .await?;

        // Tickets accumulate for the life of the connection because a shim
        // publishes a compilation's blobs and the action result naming them over
        // one connection, in that order.
        let mut connection = ConnectionUploads::default();
        let served = async {
            while let Some(line) = read_request(&mut reader).await? {
                let response = match serde_json::from_str(&line) {
                    Ok(request) => self.respond_on(request, &mut connection).await,
                    Err(error) => AgentResponse::Error {
                        message: format!("invalid agent request: {error}"),
                    },
                };
                send_response(&mut writer, &response).await?;
            }
            Ok(())
        }
        .await;
        // However the connection ended, a reason it reported still counts.
        self.release_bypass(&mut connection);
        served
    }
}

/// Read one newline-delimited request, refusing one that grows past the cap.
///
/// Any process running as this user can open the session socket, so a request
/// that never terminates its line must not be able to grow the agent's memory
/// without bound.
async fn read_request<R>(reader: &mut R) -> Result<Option<String>>
where
    R: AsyncBufRead + Unpin,
{
    let mut line = Vec::new();
    loop {
        let available = reader.fill_buf().await?;
        if available.is_empty() {
            break;
        }
        let (consumed, complete) = match available.iter().position(|byte| *byte == b'\n') {
            Some(index) => (index, true),
            None => (available.len(), false),
        };
        if line.len() + consumed > MAX_REQUEST_BYTES {
            bail!("agent request exceeded {MAX_REQUEST_BYTES} bytes");
        }
        line.extend_from_slice(&available[..consumed]);
        // The newline itself is consumed but never kept.
        reader.consume(consumed + usize::from(complete));
        if complete {
            return Ok(Some(String::from_utf8(line)?));
        }
    }
    if line.is_empty() {
        Ok(None)
    } else {
        Ok(Some(String::from_utf8(line)?))
    }
}

async fn send_response(
    writer: &mut (impl AsyncWrite + Unpin),
    response: &AgentResponse,
) -> Result<()> {
    let mut encoded = serde_json::to_vec(response)?;
    encoded.push(b'\n');
    writer.write_all(&encoded).await?;
    writer.flush().await?;
    Ok(())
}

#[cfg(test)]
#[path = "agent_tests.rs"]
mod tests;
