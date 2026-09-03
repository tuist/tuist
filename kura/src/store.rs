use std::{
    collections::{BTreeMap, HashMap, HashSet, VecDeque},
    path::{Path, PathBuf},
    pin::Pin,
    sync::{
        Arc, Mutex as StdMutex,
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
    },
    task::{Context, Poll},
    time::{Duration, Instant},
};

use bytes::Bytes;
use rocksdb::{
    BlockBasedOptions, Cache, ColumnFamily, ColumnFamilyDescriptor, DB, IteratorMode, Options,
    WriteBatch, WriteBufferManager, WriteOptions,
};
use serde::{Deserialize, Serialize};
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWriteExt, ReadBuf},
    sync::{Mutex, Notify, RwLock},
};
use uuid::Uuid;

use crate::{
    action_cache_refs::referenced_blob_keys,
    artifact::{
        manifest::{ArtifactManifest, PersistedManifestRecord},
        producer::ArtifactProducer,
        segment_location_record::SegmentLocationRecord,
    },
    config::Config,
    constants::{
        ACTION_CACHE_TRUNK_SCAN_FACTOR, BACKFILL_APPLY_GROUP_RECORDS,
        BACKFILL_INDEX_BUILD_CHUNK_ROWS, BACKFILL_SEQ_STAMP_SLACK_SEQS,
        CAS_CAPACITY_DEFAULT_DISK_PERCENT, CAS_CAPACITY_MAX_DISK_PERCENT, DESIRED_CURRENT_SEGMENTS,
        DESIRED_NEW_SEGMENTS, DESIRED_OLD_SEGMENTS, MAX_DESIRED_SEGMENTS, MAX_MODULE_TOTAL_BYTES,
        MAX_SEGMENT_BYTES, REAPI_ACTION_CACHE_REFRESH_DAMPING_MS, ROCKSDB_BYTES_PER_SYNC,
        ROCKSDB_CF_ACTION_CACHE_INDEX, ROCKSDB_CF_KEY_VALUE, ROCKSDB_CF_MANIFESTS,
        ROCKSDB_CF_MULTIPART_UPLOADS, ROCKSDB_CF_NAMESPACE_ARTIFACTS,
        ROCKSDB_CF_NAMESPACE_TOMBSTONES, ROCKSDB_CF_OUTBOX, ROCKSDB_CF_SEGMENT_ARTIFACTS,
        ROCKSDB_CF_SEGMENT_STATE, ROCKSDB_CF_USAGE_OUTBOX, ROCKSDB_HARD_PENDING_COMPACTION_BYTES,
        ROCKSDB_LEVEL0_SLOWDOWN_TRIGGER, ROCKSDB_LEVEL0_STOP_TRIGGER,
        ROCKSDB_SOFT_PENDING_COMPACTION_BYTES, ROCKSDB_WAL_BYTES_PER_SYNC,
        SEGMENT_EVICTION_MAX_BATCH_BYTES, SEGMENT_EVICTION_YIELD_ROWS, SEGMENT_FREE_SPACE_MARGIN,
    },
    failpoints::{FailpointName, FailpointSet},
    file_cache::{
        FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES, FileCachePolicy, reserve_foreground_staging,
    },
    io::{IoController, PersistentFile},
    memory::MemoryController,
    mmap::{map_file_region, mapped_span_bytes},
    multipart::{error::MultipartError, part::MultipartPart, upload::MultipartUpload},
    replication::{operation::ReplicationOperation, outbox_message::OutboxMessage},
    segment::{
        generation::SegmentGeneration, reader::SegmentReader, reference::SegmentReference,
        state::SegmentState,
    },
    usage::UsageRollup,
    utils::{
        BACKFILL_IDX_PREFIX, BACKFILL_WM_PREFIX, BackfillIndexRow, BackfillRecordKind,
        IndexRowBranch, TempFileCleanup, TmpBudget, action_cache_blob_ref_key,
        action_cache_blob_ref_prefix, action_cache_index_key, action_cache_index_key_branch,
        action_cache_index_prefix, action_cache_manifest_hash, artifact_storage_id,
        backfill_index_key, backfill_index_prefix_upper_bound, backfill_index_value,
        backfill_meta_key, backfill_wm_key, backfill_wm_prefix_upper_bound,
        decode_backfill_index_row, decode_backfill_watermark_value, drop_staging_cache_range,
        encode_backfill_watermark_value, module_key, namespace_artifact_index_key, now_ms,
        segment_artifact_index_key, segment_artifact_index_prefix, segment_path, temp_file_path,
        try_path_size_bytes,
    },
};

const MULTIPART_LOCK_STRIPES: usize = 64;
const MAX_MULTIPART_PARTS: usize = 10_000;
const MAX_MULTIPART_RECORD_BYTES: usize = 8 << 20;
const MULTIPART_RECONCILE_DELETE_BATCH: usize = 256;
const ACTION_CACHE_STALE_DELETE_BATCH: usize = 1_024;
// Flush threshold for stale backfill-index row retirement collected across
// one bodies request (same shape as ACTION_CACHE_STALE_DELETE_BATCH).
pub(crate) const BACKFILL_STALE_RETIRE_BATCH: usize = 1_024;
const ARTIFACT_WRITE_LOCK_STRIPES: usize = 64;
// Coordinates a namespace delete against everything that writes into that
// namespace. The delete resolves its tombstone with a read-compare-write that
// spans the namespace scan, and its scan is a snapshot: an artifact applied
// after the iterator was created is invisible to the delete batch, while the
// apply's own tombstone check ran before the tombstone was committed. Neither
// side sees the other and the row survives its own tombstone, which is what
// `namespace_tombstone_blocks` then stops rejecting.
//
// So deletes take the write side (which also serializes delete against delete,
// keeping the newest tombstone) and artifact applies take the read side across
// their precheck and commit. Applies stay concurrent with each other; only a
// delete excludes them, and only for its own namespace. Striped so different
// namespaces never wait on each other's scan.
const NAMESPACE_LOCK_STRIPES: usize = 16;
pub const EXISTENCE_CACHE_CAPACITY: usize = 65_536;
const EXISTENCE_CACHE_TTL: Duration = Duration::from_secs(30);
const SEGMENT_COPY_BUFFER_BYTES: usize = 256 * 1024;
const OUTBOX_FULL_ERROR: &str = "replication outbox capacity exhausted";
const MULTIPART_CAPACITY_ERROR: &str = "multipart capacity exhausted";
// The production backfill averaged thousands of reverse rows per action-cache
// manifest. Checkpoint every manifest so a large historical cache cannot turn
// the one-time migration into an unbounded RocksDB and page-cache burst.
const ACTION_CACHE_BLOB_REFS_BACKFILL_MANIFESTS_PER_STEP: usize = 1;
const ACTION_CACHE_BLOB_REFS_BACKFILL_ROWS_PER_BATCH: usize = 1_024;

pub struct ActionCacheBlobRefsBackfillStep {
    pub rows: usize,
    pub complete: bool,
}

const BACKFILL_META_BUILD_COMPLETE: &str = "build_complete";
const BACKFILL_META_LAST_MAINTAINED_SEQ: &str = "last_maintained_seq";
const BACKFILL_META_FORGIVEN_SEQS: &str = "forgiven_seqs";

pub fn is_outbox_full_error(error: &str) -> bool {
    error.starts_with(OUTBOX_FULL_ERROR)
}

pub fn is_multipart_capacity_error(error: &str) -> bool {
    error.starts_with(MULTIPART_CAPACITY_ERROR)
}

// Ring-rotation evictions queued for the usage reporter, capped so a stalled
// or unconfigured reporter cannot grow the queue without bound. Oldest entries
// drop first: the newest evictions describe the ring's current fit.
const MAX_PENDING_CAPACITY_EVICTIONS: usize = 4_096;

/// One segment evicted by ring rotation, i.e. shed under size pressure. The
/// startup orphan sweep never lands here: it removes files the ring no longer
/// references and says nothing about ring fit.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CapacityEviction {
    pub segment_id: String,
    pub segment_created_at_ms: u64,
    pub newest_content_at_ms: u64,
    pub evicted_at_ms: u64,
    pub artifact_count: u64,
    pub bytes: u64,
}

/// Point-in-time view of the segment ring against its budget, reported to the
/// control plane so claim sizing can tell an oversized ring (occupancy stays
/// low, nothing evicts) from an undersized one (full and churning).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StorageSnapshotData {
    pub ring_budget_bytes: u64,
    pub desired_segment_count: u64,
    pub live_segment_count: u64,
    pub live_segment_bytes: u64,
    pub oldest_segment_created_at_ms: Option<u64>,
    pub newest_content_at_ms: Option<u64>,
}

pub struct Store {
    db: Arc<DB>,
    io: IoController,
    memory: MemoryController,
    tenant_id: String,
    tmp_dir: PathBuf,
    tmp_staging_budget: Arc<TmpBudget>,
    data_dir: PathBuf,
    segment_ring_limits: SegmentRingLimits,
    rocksdb_block_cache_capacity_bytes: usize,
    rocksdb_block_cache: Cache,
    rocksdb_write_buffer_manager: WriteBufferManager,
    outbox_depth: AtomicUsize,
    // Depth of the bulk lane alone. `outbox_depth` is what the cap and the
    // write gate are enforced against; this splits it so a backlog can be
    // attributed to the lane that is actually deep, which decides whether the
    // lever is `OUTBOX_MAX_INFLIGHT` or `drain_metadata_batches`.
    outbox_bulk_depth: AtomicUsize,
    outbox_max_depth: usize,
    multipart_uploads: AtomicUsize,
    multipart_stored_bytes: AtomicU64,
    multipart_max_active_uploads: usize,
    multipart_max_stored_bytes: u64,
    segment_write_lock: Mutex<()>,
    pending_capacity_evictions: StdMutex<VecDeque<CapacityEviction>>,
    /// Payload ceiling of one segment-eviction write batch. Mirrors
    /// `SEGMENT_EVICTION_MAX_BATCH_BYTES`; it is a field rather than the
    /// constant read inline so tests can drive the chunk boundary without
    /// staging the megabytes of rows it would otherwise take to cross it.
    eviction_batch_budget_bytes: usize,
    /// What the eviction commits actually did. Test-only: the commit runs
    /// behind an opaque FFI call inside a closure that captures no `&self`, so
    /// neither the thread it lands on nor the size of each committed chunk is
    /// observable from outside.
    #[cfg(test)]
    eviction_commits: Arc<StdMutex<EvictionCommitLog>>,
    /// Notified with the thread each request-path write commits on. Test-only,
    /// for the same reason as `eviction_commits`: the write is an opaque FFI
    /// call inside a closure that captures no `&self`.
    #[cfg(test)]
    #[allow(clippy::type_complexity)]
    write_thread_observer: Arc<StdMutex<Option<Arc<dyn Fn(std::thread::ThreadId) + Send + Sync>>>>,
    /// Bumped whenever a namespace's action cache changes, so a snapshot index
    /// that came back EMPTY can tell "nothing to show" from "out of date". An
    /// empty index is otherwise indistinguishable from a stale one and has to be
    /// rebuilt on every serve to find out, which is a namespace scan per build
    /// for every namespace whose trunk view is legitimately empty. In memory and
    /// per node: it only ever gates a local cache, a fresh process rebuilds once,
    /// and the apply path bumps it too so a peer's write is not missed.
    action_cache_generations: StdMutex<HashMap<String, u64>>,
    // Counts segment fsyncs so tests can assert durability is batched across
    // concurrent writers rather than one fsync per write under the global lock.
    segment_fsync_count: Arc<AtomicU64>,
    // Group-commit durability. Writers reserve a monotonic `pending_seq` while
    // holding `segment_write_lock` (so their bytes are appended in order), then
    // a single fsync — serialized by `fsync_lock` — advances `durable_seq` to
    // cover every writer that appended before it. A writer whose seq is already
    // <= `durable_seq` skips the fsync entirely.
    pending_seq: AtomicU64,
    durable_seq: AtomicU64,
    fsync_lock: Mutex<()>,
    segment_refresh_lock: Mutex<()>,
    segment_state_lock: Mutex<()>,
    // Wrapped in `Arc` so readers clone the snapshot under a brief lock and then
    // use it without holding the mutex (unlike the sibling caches below, which
    // are read and mutated in place under their lock).
    segment_state_cache: StdMutex<Arc<SegmentStateSnapshot>>,
    // Running max effective `version_ms` of manifests committed into the
    // active segment, keyed by segment id; drained into the outgoing
    // `SegmentReference::max_version_ms` when the segment seals (rotation).
    // In-memory only — `rederive_active_segment_max_version` restores it at
    // boot so a restart mid-segment does not under-report the eventual seal.
    active_segment_max_versions: StdMutex<HashMap<String, u64>>,
    segment_handles: Mutex<SegmentHandleCache>,
    manifest_cache: StdMutex<ManifestCache>,
    existence_cache: ShardedExistenceCache,
    multipart_locks: [Mutex<()>; MULTIPART_LOCK_STRIPES],
    // Serializes writers for the same artifact so concurrent applies of one key
    // (e.g. a fresh node backfilling the same artifact from several peers at
    // once) can't each append their own copy to a segment and orphan all but the
    // last. Striped by artifact id so different keys still write concurrently.
    artifact_write_locks: [Mutex<()>; ARTIFACT_WRITE_LOCK_STRIPES],
    namespace_locks: [RwLock<()>; NAMESPACE_LOCK_STRIPES],
    // Artifacts served from an Old-generation segment queue here for background
    // promotion into the current segment instead of refreshing inline on the
    // read path: one value-graph read can touch thousands of tiny old
    // artifacts, and per-read refreshes serialize them all on
    // `segment_refresh_lock` (measured 3.9ms per 200-byte artifact, turning an
    // 800KB batch read into 15s). Promotion stays best-effort: a dropped entry
    // only means the artifact may be reclaimed with its segment later, the same
    // outcome as the pre-existing memory-pressure skip.
    promotion_queue: StdMutex<PromotionQueue>,
    promotion_notify: Notify,
    // Whether evicting a blob cascades to the action-cache entries referencing
    // it. Operator-controlled (see `action_cache_cascade_active`).
    action_cache_eviction_cascade_enabled: bool,
    // Set once the one-time startup backfill has rebuilt the blob-refs reverse
    // map from the entries already on disk. This widens cascade coverage to
    // entries that predate the reverse map; it does not gate the cascade, which
    // runs against whatever rows exist. Reverse-row maintenance on the
    // write/delete paths runs regardless, so the map is live for entries
    // written after start.
    action_cache_blob_refs_ready: AtomicBool,
    // Whether the backfill per-entry index covers the pre-existing dataset
    // (`backfill/meta/build_complete` present and not invalidated by the
    // rollback-window staleness check at open). Write-path maintenance runs
    // regardless; this only gates what the listing endpoint may serve.
    backfill_index_built: AtomicBool,
    // WAL write accounting so tests can pin durability semantics: live apply
    // paths must keep producing sync WriteBatch commits, and only the backfill
    // batch-apply path may produce deferred (non-sync) commits plus WAL
    // flushes (see [`ApplyDurability`]).
    wal_sync_write_count: AtomicU64,
    wal_deferred_write_count: AtomicU64,
    wal_flush_count: AtomicU64,
    failpoints: Arc<FailpointSet>,
}

/// Pending read-path promotions: two FIFOs plus a membership map so a hot old
/// artifact read thousands of times enqueues once, carrying the trigger that
/// queued it.
///
/// Vouched work drains ahead of serve-path work rather than sharing one queue.
/// Reserving admission is not enough on its own: a vouched refresh admitted
/// behind a long serve backlog still waits for the whole backlog to copy, which
/// is exactly the window the vouch is supposed to close. `pending` is the
/// authoritative set, so a deque may hold an id already promoted through the
/// other lane (the trigger upgrade path pushes into `vouched`); those pop as
/// misses and are skipped.
#[derive(Default)]
struct PromotionQueue {
    vouched: VecDeque<String>,
    serve: VecDeque<String>,
    pending: HashMap<String, RefreshTrigger>,
}

impl PromotionQueue {
    fn depth(&self) -> usize {
        self.pending.len()
    }

    fn push(&mut self, artifact_id: &str, trigger: RefreshTrigger) {
        if trigger.extends_vouched_lifetime() {
            self.vouched.push_back(artifact_id.to_owned());
        } else {
            self.serve.push_back(artifact_id.to_owned());
        }
    }

    /// The next artifact to promote, vouched lane first. Ids left behind by a
    /// lane switch are skipped here rather than removed at switch time, which
    /// would be a linear scan of the queue.
    fn pop(&mut self) -> Option<(String, RefreshTrigger)> {
        loop {
            let artifact_id = self
                .vouched
                .pop_front()
                .or_else(|| self.serve.pop_front())?;
            if let Some(trigger) = self.pending.remove(&artifact_id) {
                return Some((artifact_id, trigger));
            }
        }
    }
}

/// What drove a segment refresh: the metric label, and the selector for which
/// memory-pressure gate applies.
///
/// `GetActionResult` and `FindMissingBlobs` promise that the blobs they report
/// on stay fetchable afterwards (REAPI asks that "the lifetimes of the
/// referenced blobs SHOULD be increased if necessary and applicable"), so they
/// refresh one pressure tier deeper than serve-path promotion. Dropping a
/// vouched-for blob's refresh reopens that promise's gap exactly when eviction
/// is most aggressive, whereas serve-path promotion carries no promise: its
/// read already succeeded and the refresh only speeds up future ones.
/// Both stop at `Critical`, where a read-path write would compound the squeeze.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum RefreshTrigger {
    /// Background promotion of an artifact just served from an Old segment.
    Serve,
    /// A `GetActionResult` that passed its presence gate and is being served.
    ActionCache,
    /// A `FindMissingBlobs` that reported the blob present.
    FindMissing,
}

impl RefreshTrigger {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Serve => "serve",
            Self::ActionCache => "action_cache",
            Self::FindMissing => "find_missing",
        }
    }

    /// Whether this refresh backs a lifetime the node has vouched for, and so
    /// runs under the wider pressure gate.
    fn extends_vouched_lifetime(self) -> bool {
        !matches!(self, Self::Serve)
    }
}

/// Backstop so an unbounded burst of old-artifact reads cannot grow the
/// promotion queue without limit; far above what one build's value graphs
/// enqueue (tens of thousands of artifacts).
const MAX_PENDING_PROMOTIONS: usize = 262_144;

/// Slice of [`MAX_PENDING_PROMOTIONS`] that only a vouched-for refresh may
/// occupy. Serve-path promotion is best-effort keep-alive: losing one costs a
/// later read some latency. A vouched refresh backs a promise already made to a
/// client, and losing it can hand that client a missing object it hard-fails
/// the build on, so a flood of serve-path reads must not be able to fill the
/// queue ahead of one. Reserving a slice rather than raising the ceiling keeps
/// the queue's total memory bound unchanged.
const VOUCHED_PROMOTION_RESERVE: usize = 65_536;

pub struct StoreSnapshot {
    pub outbox_messages: usize,
    /// How many of `outbox_messages` sit in the bulk lane. The rest are the
    /// metadata lane, which `drain_metadata_batches` amortizes separately.
    pub outbox_bulk_messages: usize,
    pub multipart_uploads: usize,
    pub promotion_queue_depth: usize,
    pub segment_counts: Vec<(&'static str, usize)>,
    pub segment_fsync_count: u64,
    pub rocksdb_block_cache_usage_bytes: u64,
    pub rocksdb_block_cache_pinned_usage_bytes: u64,
    pub rocksdb_block_cache_capacity_bytes: u64,
    pub rocksdb_write_buffer_usage_bytes: u64,
    pub rocksdb_write_buffer_capacity_bytes: u64,
}

pub enum ArtifactReader {
    Inline { bytes: Bytes, offset: usize },
    FileRange(SegmentReader),
}

#[derive(Clone)]
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub struct AcceleratedArtifactFile {
    pub handle: Arc<PersistentFile>,
    pub offset: u64,
    pub size: u64,
    pub content_type: String,
    pub version_ms: u64,
}

impl AsyncRead for ArtifactReader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        match &mut *self {
            Self::Inline { bytes, offset } => {
                if *offset >= bytes.len() {
                    return Poll::Ready(Ok(()));
                }
                let copy_len = (bytes.len() - *offset).min(buf.remaining());
                buf.put_slice(&bytes[*offset..*offset + copy_len]);
                *offset += copy_len;
                Poll::Ready(Ok(()))
            }
            Self::FileRange(reader) => Pin::new(reader).poll_read(cx, buf),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ManifestPage {
    pub manifests: Vec<ArtifactManifest>,
    pub next_after: Option<String>,
}

/// One newest-first page of the backfill per-entry index. `next_after` is the
/// raw key of the last returned row, fed back as the next page's `after`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackfillIndexPage {
    pub entries: Vec<BackfillIndexRow>,
    pub next_after: Option<Vec<u8>>,
}

/// Durability mode of a replicated apply's storage writes.
///
/// `Sync` is the live-path contract and the default everywhere: each record's
/// segment bytes are fsynced before its manifest commits with a synced WAL
/// write, so a record is durable the moment its apply returns. Every public
/// apply/persist entry point keeps this mode; `DeferredBatch` is reachable
/// only through the backfill batch-apply API
/// ([`Store::stage_backfill_segmented_apply`],
/// [`Store::stage_backfill_inline_apply`],
/// [`Store::commit_backfill_apply_batch`]).
///
/// `DeferredBatch` amortizes durability to one segment fsync, one shared
/// non-sync WriteBatch per group of up to [`BACKFILL_APPLY_GROUP_RECORDS`]
/// records, and one synced WAL flush per spooled backfill bodies batch,
/// instead of ~2 fsyncs per record. Its correctness rests on three facts:
///
/// - Backfill's crash contract already tolerates losing un-fsynced applies: a
///   pass that does not complete never advances the peer watermark, so a
///   restart re-lists the window and LWW absorbs the replays (see the
///   `crash_*` tests in `backfill::pass`).
/// - The watermark written on pass completion
///   ([`Store::write_backfill_watermark`], driven by `backfill::lifecycle`)
///   commits with a SYNC WriteBatch through the same WAL. RocksDB WAL syncs
///   are prefix-ordered, so a durable watermark implies every earlier
///   non-sync manifest record in the WAL is durable too — a completed pass
///   still means "everything it applied is durable".
/// - The live invariant "durable manifest ⇒ durable segment bytes" is never
///   weakened. Any concurrent sync write can flush the WAL at any moment,
///   making earlier non-sync records durable early, so a batch's segment
///   bytes are fully fsynced (phase 2) BEFORE any of its manifests is written
///   to the WAL (phase 3). Inline artifacts are WAL-only and have no such
///   ordering dependency; they simply take the non-sync commit and ride the
///   batch-end barrier.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ApplyDurability {
    Sync,
    DeferredBatch,
}

/// Phase accumulator for one backfill bodies batch applied under
/// [`ApplyDurability::DeferredBatch`]. The protocol, driven by
/// `backfill::pass::apply_spooled_batch`:
///
/// 1. Phase 1 — [`Store::stage_backfill_segmented_apply`] appends each
///    Present segmented body to the active segment (no per-record fsync) and
///    records the manifest inputs here; inline bodies stage their bytes here
///    via [`Store::stage_backfill_inline_apply`] without touching the DB.
/// 2. Phase 2 — one group-commit fsync covers every staged append (rotation
///    already fsyncs any segment that sealed mid-batch).
/// 3. Phase 3 — staged records commit in groups of up to
///    [`BACKFILL_APPLY_GROUP_RECORDS`]: each group re-runs the authoritative
///    prechecks under the records' write locks and stages every surviving
///    manifest/metadata mutation — through the same LWW/outcome/index code
///    paths as live applies — into ONE shared non-sync WriteBatch.
/// 4. Phase 4 — one synced WAL flush is the batch durability barrier.
///
/// Dropping the accumulator without committing (batch error, cancellation)
/// is safe: staged appends without manifests are unreferenced segment bytes,
/// reclaimed when their segment is evicted, staged inline bytes are dropped
/// with it, and the failed pass re-lists.
#[derive(Default)]
pub(crate) struct BackfillApplyBatch {
    staged: Vec<StagedBackfillApply>,
    max_durability_seq: u64,
}

impl BackfillApplyBatch {
    pub(crate) fn new() -> Self {
        Self::default()
    }
}

/// Whether a phase-1 stage call queued the record for a phase-3 group commit
/// (`Staged` — the caller must defer its claim resolution to the group
/// callback of [`Store::commit_backfill_apply_batch`]) or found it already
/// converged (`Converged` — local copy newer/equal or tombstoned; nothing
/// queued, the record is readable now and resolves immediately).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum BackfillStageOutcome {
    Staged,
    Converged,
}

/// One phase-1-staged apply awaiting its phase-3 group commit.
enum StagedBackfillApply {
    Segmented(StagedBackfillSegmentApply),
    Inline(StagedBackfillInlineApply),
}

impl StagedBackfillApply {
    fn artifact_id(&self) -> &str {
        match self {
            Self::Segmented(staged) => &staged.artifact_id,
            Self::Inline(staged) => &staged.artifact_id,
        }
    }

    fn namespace_id(&self) -> &str {
        match self {
            Self::Segmented(staged) => &staged.namespace_id,
            Self::Inline(staged) => &staged.namespace_id,
        }
    }
}

/// A segmented apply whose bytes already sit (un-fsynced) in a segment.
struct StagedBackfillSegmentApply {
    producer: ArtifactProducer,
    namespace_id: String,
    key: String,
    content_type: String,
    version_ms: u64,
    artifact_id: String,
    location: SegmentLocation,
    size: u64,
}

impl StagedBackfillSegmentApply {
    fn spec(&self) -> PersistArtifactSpec<'_> {
        PersistArtifactSpec {
            producer: self.producer,
            namespace_id: &self.namespace_id,
            key: &self.key,
            content_type: &self.content_type,
            version_ms: self.version_ms,
            replication_targets: &[],
            branch: None,
            trunk: None,
        }
    }
}

/// An inline apply whose bytes are held in memory until its group commit
/// writes them (memory-bounded by the spooled bodies batch that produced
/// them, at most `BACKFILL_BODIES_BATCH_BYTES`).
struct StagedBackfillInlineApply {
    producer: ArtifactProducer,
    namespace_id: String,
    key: String,
    content_type: String,
    version_ms: u64,
    branch: Option<String>,
    artifact_id: String,
    bytes: Vec<u8>,
}

impl StagedBackfillInlineApply {
    fn spec(&self) -> PersistArtifactSpec<'_> {
        PersistArtifactSpec {
            producer: self.producer,
            namespace_id: &self.namespace_id,
            key: &self.key,
            content_type: &self.content_type,
            version_ms: self.version_ms,
            replication_targets: &[],
            branch: self.branch.as_deref(),
            trunk: None,
        }
    }
}

/// Post-commit bookkeeping owed by one record of a phase-3 group after the
/// group's shared WriteBatch lands (mirrors what the per-record sync paths do
/// right after their own commit).
enum CommittedGroupRecord {
    Segmented {
        manifest: ArtifactManifest,
        segment_id: String,
    },
    Inline {
        manifest: ArtifactManifest,
        wrote_action_cache_index: bool,
    },
}

#[derive(Clone, Copy)]
struct PersistArtifactSpec<'a> {
    producer: ArtifactProducer,
    namespace_id: &'a str,
    key: &'a str,
    content_type: &'a str,
    version_ms: u64,
    replication_targets: &'a [String],
    branch: Option<&'a str>,
    /// Rides the replication messages this persist enqueues so a peer can
    /// re-run the trunk-sticky rule against its own view. Not stored: the
    /// trunk is a property of the publishing build, not of the artifact.
    trunk: Option<&'a str>,
}

struct OutboxReservation<'a> {
    depth: &'a AtomicUsize,
    bulk_depth: &'a AtomicUsize,
    slots: usize,
    committed: bool,
}

struct MultipartUploadReservation<'a> {
    uploads: &'a AtomicUsize,
    committed: bool,
}

impl MultipartUploadReservation<'_> {
    fn commit(mut self) {
        self.committed = true;
    }
}

impl Drop for MultipartUploadReservation<'_> {
    fn drop(&mut self) {
        if !self.committed {
            release_atomic_slots(self.uploads, 1);
        }
    }
}

struct MultipartByteReservation<'a> {
    bytes: &'a AtomicU64,
    added: u64,
    committed: bool,
}

impl MultipartByteReservation<'_> {
    fn commit(mut self, released: u64) {
        release_atomic_bytes(self.bytes, released);
        self.committed = true;
    }
}

impl Drop for MultipartByteReservation<'_> {
    fn drop(&mut self) {
        if !self.committed {
            release_atomic_bytes(self.bytes, self.added);
        }
    }
}

impl OutboxReservation<'_> {
    /// `bulk_slots` is how many of the reserved slots were written to the bulk
    /// lane. It is taken here rather than at reservation time because the lane
    /// is only known once the messages are built, and it is applied on success
    /// so a dropped reservation leaves the split untouched.
    fn commit(mut self, bulk_slots: usize) {
        self.committed = true;
        if bulk_slots > 0 {
            self.bulk_depth.fetch_add(bulk_slots, Ordering::AcqRel);
        }
    }
}

impl Drop for OutboxReservation<'_> {
    fn drop(&mut self) {
        if !self.committed && self.slots > 0 {
            release_atomic_slots(self.depth, self.slots);
        }
    }
}

// `IgnoredEqual` (incoming version equals the stored one — both sides already
// hold the identical entry) is reported separately from `IgnoredStale`
// (incoming strictly older — a real LWW rejection, the peer is behind) so
// anti-entropy diagnosis can tell a re-walk churning already-converged data
// from genuine one-directional version skew. The apply decision is the same
// for both: local wins.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ArtifactApplyOutcome {
    Applied,
    IgnoredEqual,
    IgnoredStale,
    IgnoredTombstone,
}

impl ArtifactApplyOutcome {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Applied => "applied",
            Self::IgnoredEqual => "ignored_equal",
            Self::IgnoredStale => "ignored_stale",
            Self::IgnoredTombstone => "ignored_tombstone",
        }
    }

    pub(crate) fn applied(self) -> bool {
        matches!(self, Self::Applied)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NamespaceDeleteOutcome {
    Applied,
    IgnoredOlder,
}

impl NamespaceDeleteOutcome {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Applied => "applied",
            Self::IgnoredOlder => "ignored_older",
        }
    }

    #[cfg(test)]
    pub(crate) fn applied(self) -> bool {
        matches!(self, Self::Applied)
    }
}

/// Result of the LWW/tombstone gate a segment-backed apply runs under the
/// per-artifact write lock before appending bytes (and again before a
/// deferred phase-3 manifest commit).
enum SegmentApplyPrecheck {
    Proceed {
        existing: Option<ArtifactManifest>,
        already_present: bool,
    },
    Ignored {
        outcome: PersistArtifactOutcome,
        already_present: bool,
    },
}

/// Result of the LWW/tombstone gate an inline apply runs under the
/// per-artifact write lock before staging its WriteBatch mutations (run
/// advisorily at backfill phase-1 staging and authoritatively again before a
/// phase-3 group commit).
enum InlineApplyPrecheck {
    Proceed { existing: Option<ArtifactManifest> },
    Ignored { outcome: PersistArtifactOutcome },
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum PersistArtifactOutcome {
    Applied(ArtifactManifest),
    IgnoredEqual(ArtifactManifest),
    IgnoredStale(ArtifactManifest),
    IgnoredTombstone,
}

// Result of a client-facing persist. `already_present` reports whether a live
// copy of the artifact (manifest + backing storage) existed before this call,
// evaluated under the per-artifact write lock — so concurrent persists of the
// same key resolve it consistently: exactly one observes `false`. Billing uses
// it to charge only newly-stored bytes; it is deliberately not derived from the
// Applied-vs-ignored version outcome, because a re-upload with a newer
// version still applies over an already-present artifact.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PersistedArtifact {
    pub manifest: ArtifactManifest,
    pub already_present: bool,
}

#[derive(Clone, Copy)]
pub struct StagedArtifactPath<'a> {
    path: &'a Path,
    file_cache_policy: FileCachePolicy,
}

impl<'a> StagedArtifactPath<'a> {
    pub fn new(path: &'a Path, file_cache_policy: FileCachePolicy) -> Self {
        Self {
            path,
            file_cache_policy,
        }
    }
}

#[cfg(test)]
impl<'a> From<&'a Path> for StagedArtifactPath<'a> {
    fn from(path: &'a Path) -> Self {
        Self::new(path, FileCachePolicy::Adaptive)
    }
}

#[cfg(test)]
impl<'a> From<&'a PathBuf> for StagedArtifactPath<'a> {
    fn from(path: &'a PathBuf) -> Self {
        Self::from(path.as_path())
    }
}

impl PersistArtifactOutcome {
    fn ignored(existing: ArtifactManifest, incoming_version_ms: u64) -> Self {
        if versions_converged(manifest_version_ms(&existing), incoming_version_ms) {
            Self::IgnoredEqual(existing)
        } else {
            Self::IgnoredStale(existing)
        }
    }

    fn apply_outcome(&self) -> ArtifactApplyOutcome {
        match self {
            Self::Applied(_) => ArtifactApplyOutcome::Applied,
            Self::IgnoredEqual(_) => ArtifactApplyOutcome::IgnoredEqual,
            Self::IgnoredStale(_) => ArtifactApplyOutcome::IgnoredStale,
            Self::IgnoredTombstone => ArtifactApplyOutcome::IgnoredTombstone,
        }
    }

    // Converts a client-facing persist outcome into the public result: every
    // non-tombstone outcome surfaces its manifest, while a tombstone
    // rejection is an error (client writes must not be silently dropped).
    fn into_persisted(
        self,
        already_present: bool,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
    ) -> Result<PersistedArtifact, String> {
        match self {
            Self::Applied(manifest)
            | Self::IgnoredEqual(manifest)
            | Self::IgnoredStale(manifest) => Ok(PersistedArtifact {
                manifest,
                already_present,
            }),
            Self::IgnoredTombstone => Err(format!(
                "artifact write for {producer:?}/{namespace_id}/{key} was rejected by a newer tombstone"
            )),
        }
    }
}

/// What `Store::commit_eviction_chunk` did, recorded for tests only.
#[cfg(test)]
#[derive(Default)]
struct EvictionCommitLog {
    threads: Vec<std::thread::ThreadId>,
    chunk_bytes: Vec<usize>,
}

/// Bookkeeping for the action-cache entries one segment eviction cascades.
///
/// Everything here is scoped to the *current chunk* and reset on every commit.
/// `seen` de-duplicates entries that two blobs in the same chunk both
/// reference, so the second reference does not stage a redundant delete.
///
/// It deliberately does **not** de-duplicate across the whole segment, which is
/// what it did when a segment was one batch. Once the eviction commits in
/// chunks, an entry removed by an early chunk can be republished against a
/// different blob in the same segment before that blob is reached; a
/// segment-wide `seen` skips it there and leaves it pointing at a blob this
/// eviction is deleting — the strand #12152 closed. Per-chunk scoping makes the
/// later blob re-examine it and re-validate it against its current
/// `ActionResult`. Nothing is double-counted by the reset: an entry an earlier
/// chunk really did delete no longer has a manifest, so the lookup below skips
/// it before it reaches `record`.
///
/// `total` is the segment-wide count, kept separately because the rest resets.
#[derive(Default)]
struct CascadeProgress {
    seen: HashSet<String>,
    pending_entries: Vec<String>,
    pending_namespaces: HashSet<String>,
    total: usize,
}

impl CascadeProgress {
    fn contains(&self, entry_id: &str) -> bool {
        self.seen.contains(entry_id)
    }

    fn record(&mut self, namespace_id: &str, entry_id: String) {
        if !self.seen.insert(entry_id.clone()) {
            return;
        }
        self.pending_namespaces.insert(namespace_id.to_owned());
        self.pending_entries.push(entry_id);
        self.total += 1;
    }
}

impl Store {
    pub fn open(
        config: &Config,
        io: IoController,
        memory: MemoryController,
    ) -> Result<Self, String> {
        let rebuild_started = std::time::Instant::now();
        let rocksdb_block_cache = Cache::new_lru_cache(config.rocksdb_block_cache_bytes);
        // Deliberately NOT `new_write_buffer_manager_with_cache`: charging
        // memtable growth to the block cache made the two budgets one, so a
        // write burst evicted the read cache that the eviction scan itself
        // depends on, and the cache ran far over its own capacity because the
        // index/filter blocks pinned below cannot be evicted to make room
        // (measured at 169% of capacity during the 2026-08-24 stall). They are
        // separate allocations now; `Config::anon_admission_budget_bytes`
        // subtracts both, which is correct precisely because they no longer
        // overlap. `allow_stall` stays on: without it a saturated pool grows
        // the memtables without bound, which on these memory limits is an
        // OOMKill instead of a stall. See #12556.
        let rocksdb_write_buffer_manager = WriteBufferManager::new_write_buffer_manager(
            config.rocksdb_write_buffer_manager_bytes,
            true,
        );
        let mut options = Options::default();
        options.create_if_missing(true);
        options.create_missing_column_families(true);
        options.set_compression_type(rocksdb::DBCompressionType::Lz4);
        options.set_max_open_files(config.rocksdb_max_open_files);
        options.set_max_background_jobs(config.rocksdb_max_background_jobs);
        options.set_bytes_per_sync(ROCKSDB_BYTES_PER_SYNC);
        options.set_wal_bytes_per_sync(ROCKSDB_WAL_BYTES_PER_SYNC);
        options.set_write_buffer_manager(&rocksdb_write_buffer_manager);

        let cfs = vec![
            ColumnFamilyDescriptor::new(
                ROCKSDB_CF_MANIFESTS,
                rocksdb_column_family_options(
                    config,
                    &rocksdb_block_cache,
                    &rocksdb_write_buffer_manager,
                ),
            ),
            ColumnFamilyDescriptor::new(
                ROCKSDB_CF_KEY_VALUE,
                rocksdb_column_family_options(
                    config,
                    &rocksdb_block_cache,
                    &rocksdb_write_buffer_manager,
                ),
            ),
            ColumnFamilyDescriptor::new(
                ROCKSDB_CF_NAMESPACE_ARTIFACTS,
                rocksdb_column_family_options(
                    config,
                    &rocksdb_block_cache,
                    &rocksdb_write_buffer_manager,
                ),
            ),
            ColumnFamilyDescriptor::new(
                ROCKSDB_CF_NAMESPACE_TOMBSTONES,
                rocksdb_column_family_options(
                    config,
                    &rocksdb_block_cache,
                    &rocksdb_write_buffer_manager,
                ),
            ),
            ColumnFamilyDescriptor::new(
                ROCKSDB_CF_MULTIPART_UPLOADS,
                rocksdb_column_family_options(
                    config,
                    &rocksdb_block_cache,
                    &rocksdb_write_buffer_manager,
                ),
            ),
            ColumnFamilyDescriptor::new(
                ROCKSDB_CF_OUTBOX,
                rocksdb_column_family_options(
                    config,
                    &rocksdb_block_cache,
                    &rocksdb_write_buffer_manager,
                ),
            ),
            ColumnFamilyDescriptor::new(
                ROCKSDB_CF_USAGE_OUTBOX,
                rocksdb_column_family_options(
                    config,
                    &rocksdb_block_cache,
                    &rocksdb_write_buffer_manager,
                ),
            ),
            ColumnFamilyDescriptor::new(
                ROCKSDB_CF_SEGMENT_ARTIFACTS,
                rocksdb_column_family_options(
                    config,
                    &rocksdb_block_cache,
                    &rocksdb_write_buffer_manager,
                ),
            ),
            ColumnFamilyDescriptor::new(
                ROCKSDB_CF_SEGMENT_STATE,
                rocksdb_column_family_options(
                    config,
                    &rocksdb_block_cache,
                    &rocksdb_write_buffer_manager,
                ),
            ),
            ColumnFamilyDescriptor::new(
                ROCKSDB_CF_ACTION_CACHE_INDEX,
                rocksdb_column_family_options(
                    config,
                    &rocksdb_block_cache,
                    &rocksdb_write_buffer_manager,
                ),
            ),
        ];

        let db_path = config.data_dir.join("rocksdb");
        let db = Arc::new(
            DB::open_cf_descriptors(&options, db_path, cfs)
                .map_err(|error| format!("failed to open RocksDB: {error}"))?,
        );
        io.metrics()
            .update_manifest_cache_capacity_bytes(config.manifest_cache_max_bytes);
        io.metrics().update_manifest_index_entries(0);
        io.metrics().update_manifest_cache_bytes(0);
        io.metrics()
            .record_manifest_index_rebuild("ok", rebuild_started.elapsed());
        io.metrics()
            .update_segment_handle_cache_capacity(config.segment_handle_cache_size);
        io.metrics().update_segment_handles_cached(0);
        io.metrics().update_rocksdb_memory(
            rocksdb_block_cache.get_usage() as u64,
            rocksdb_block_cache.get_pinned_usage() as u64,
            config.rocksdb_block_cache_bytes as u64,
            rocksdb_write_buffer_manager.get_usage() as u64,
            rocksdb_write_buffer_manager.get_buffer_size() as u64,
        );

        let segment_ring_limits = resolve_segment_ring_limits(
            config.cas_capacity_bytes,
            total_disk_bytes(&config.data_dir),
        );
        tracing::info!(
            desired_old_segments = segment_ring_limits.desired_old_segments,
            desired_current_segments = segment_ring_limits.desired_current_segments,
            desired_new_segments = segment_ring_limits.desired_new_segments,
            capacity_bytes = segment_ring_limits.capacity_bytes(),
            "resolved CAS segment ring limits"
        );

        let store = Self {
            db,
            io,
            memory,
            tenant_id: config.tenant_id.clone(),
            tmp_dir: config.tmp_dir.clone(),
            tmp_staging_budget: TmpBudget::new(config.tmp_dir_max_bytes),
            data_dir: config.data_dir.clone(),
            segment_ring_limits,
            rocksdb_block_cache_capacity_bytes: config.rocksdb_block_cache_bytes,
            rocksdb_block_cache,
            rocksdb_write_buffer_manager,
            outbox_depth: AtomicUsize::new(0),
            outbox_bulk_depth: AtomicUsize::new(0),
            outbox_max_depth: config.outbox_max_depth,
            multipart_uploads: AtomicUsize::new(0),
            multipart_stored_bytes: AtomicU64::new(0),
            multipart_max_active_uploads: config.multipart_max_active_uploads,
            multipart_max_stored_bytes: config.multipart_max_stored_bytes,
            segment_write_lock: Mutex::new(()),
            pending_capacity_evictions: StdMutex::new(VecDeque::new()),
            eviction_batch_budget_bytes: SEGMENT_EVICTION_MAX_BATCH_BYTES,
            #[cfg(test)]
            eviction_commits: Arc::new(StdMutex::new(EvictionCommitLog::default())),
            #[cfg(test)]
            write_thread_observer: Arc::new(StdMutex::new(None)),
            action_cache_generations: StdMutex::new(HashMap::new()),
            segment_fsync_count: Arc::new(AtomicU64::new(0)),
            pending_seq: AtomicU64::new(0),
            durable_seq: AtomicU64::new(0),
            fsync_lock: Mutex::new(()),
            segment_refresh_lock: Mutex::new(()),
            segment_state_lock: Mutex::new(()),
            segment_state_cache: StdMutex::new(Arc::new(SegmentStateSnapshot::default())),
            active_segment_max_versions: StdMutex::new(HashMap::new()),
            segment_handles: Mutex::new(SegmentHandleCache::new(config.segment_handle_cache_size)),
            manifest_cache: StdMutex::new(ManifestCache::new(config.manifest_cache_max_bytes)),
            existence_cache: ShardedExistenceCache::new(
                EXISTENCE_CACHE_CAPACITY,
                EXISTENCE_CACHE_TTL,
            ),
            multipart_locks: std::array::from_fn(|_| Mutex::new(())),
            artifact_write_locks: std::array::from_fn(|_| Mutex::new(())),
            namespace_locks: std::array::from_fn(|_| RwLock::new(())),
            promotion_queue: StdMutex::new(PromotionQueue::default()),
            promotion_notify: Notify::new(),
            action_cache_eviction_cascade_enabled: config.action_cache_eviction_cascade_enabled,
            action_cache_blob_refs_ready: AtomicBool::new(false),
            backfill_index_built: AtomicBool::new(false),
            wal_sync_write_count: AtomicU64::new(0),
            wal_deferred_write_count: AtomicU64::new(0),
            wal_flush_count: AtomicU64::new(0),
            failpoints: Arc::new(FailpointSet::default()),
        };
        // `load_segment_state_from_db` needs `&self`, so the store must be fully
        // constructed (with a placeholder snapshot) before it can be seeded.
        let segment_state = store.load_segment_state_from_db()?;
        store.replace_segment_state_snapshot(segment_state);
        store.rederive_active_segment_max_version()?;
        store.init_backfill_index_state()?;
        let (outbox_depth, outbox_bulk_depth) = store.count_outbox_entries_exact()?;
        store.outbox_depth.store(outbox_depth, Ordering::Release);
        store
            .outbox_bulk_depth
            .store(outbox_bulk_depth, Ordering::Release);
        let (multipart_uploads, multipart_stored_bytes) = store.reconcile_multipart_storage()?;
        store
            .multipart_uploads
            .store(multipart_uploads, Ordering::Release);
        store
            .multipart_stored_bytes
            .store(multipart_stored_bytes, Ordering::Release);
        if multipart_uploads > store.multipart_max_active_uploads
            || multipart_stored_bytes > store.multipart_max_stored_bytes
        {
            tracing::warn!(
                multipart_uploads,
                multipart_stored_bytes,
                max_active_uploads = store.multipart_max_active_uploads,
                max_stored_bytes = store.multipart_max_stored_bytes,
                "persisted multipart usage starts above its configured limits; rejecting growth until the janitor reclaims it"
            );
        }
        Ok(store)
    }

    pub fn tmp_staging_budget(&self) -> Arc<TmpBudget> {
        self.tmp_staging_budget.clone()
    }

    pub fn outbox_depth(&self) -> usize {
        self.outbox_depth.load(Ordering::Acquire)
    }

    /// Bulk-lane depth. Capped at the total, because the two counters are read
    /// separately and a delete landing between them could otherwise show a
    /// bulk depth above the total and a negative metadata lane.
    pub fn outbox_bulk_depth(&self) -> usize {
        self.outbox_bulk_depth
            .load(Ordering::Acquire)
            .min(self.outbox_depth())
    }

    fn reserve_outbox_slots(&self, slots: usize) -> Result<OutboxReservation<'_>, String> {
        if slots == 0 {
            return Ok(OutboxReservation {
                depth: &self.outbox_depth,
                bulk_depth: &self.outbox_bulk_depth,
                slots,
                committed: false,
            });
        }

        let mut current = self.outbox_depth.load(Ordering::Acquire);
        loop {
            let requested = current.saturating_add(slots);
            if requested > self.outbox_max_depth {
                return Err(format!(
                    "{OUTBOX_FULL_ERROR}: {current} messages queued, {slots} slots requested, {} allowed",
                    self.outbox_max_depth
                ));
            }
            match self.outbox_depth.compare_exchange_weak(
                current,
                requested,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => {
                    return Ok(OutboxReservation {
                        depth: &self.outbox_depth,
                        bulk_depth: &self.outbox_bulk_depth,
                        slots,
                        committed: false,
                    });
                }
                Err(observed) => current = observed,
            }
        }
    }

    fn reserve_multipart_upload(&self) -> Result<MultipartUploadReservation<'_>, String> {
        let mut current = self.multipart_uploads.load(Ordering::Acquire);
        loop {
            let requested = current.saturating_add(1);
            if requested > self.multipart_max_active_uploads {
                return Err(format!(
                    "{MULTIPART_CAPACITY_ERROR}: {current} active uploads, {} allowed",
                    self.multipart_max_active_uploads
                ));
            }
            match self.multipart_uploads.compare_exchange_weak(
                current,
                requested,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => {
                    return Ok(MultipartUploadReservation {
                        uploads: &self.multipart_uploads,
                        committed: false,
                    });
                }
                Err(observed) => current = observed,
            }
        }
    }

    fn reserve_multipart_bytes(
        &self,
        next_bytes: u64,
    ) -> Result<MultipartByteReservation<'_>, MultipartError> {
        let added = next_bytes;
        let mut current = self.multipart_stored_bytes.load(Ordering::Acquire);
        loop {
            let requested = current.saturating_add(added);
            if requested > self.multipart_max_stored_bytes {
                return Err(MultipartError::CapacityExceeded);
            }
            match self.multipart_stored_bytes.compare_exchange_weak(
                current,
                requested,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => {
                    return Ok(MultipartByteReservation {
                        bytes: &self.multipart_stored_bytes,
                        added,
                        committed: false,
                    });
                }
                Err(observed) => current = observed,
            }
        }
    }

    fn multipart_lock_for(&self, upload_id: &str) -> &Mutex<()> {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        std::hash::Hash::hash(upload_id, &mut hasher);
        let index = (std::hash::Hasher::finish(&hasher) as usize) % MULTIPART_LOCK_STRIPES;
        &self.multipart_locks[index]
    }

    fn artifact_write_lock_index(&self, artifact_id: &str) -> usize {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        std::hash::Hash::hash(artifact_id, &mut hasher);
        (std::hash::Hasher::finish(&hasher) as usize) % ARTIFACT_WRITE_LOCK_STRIPES
    }

    fn artifact_write_lock_for(&self, artifact_id: &str) -> &Mutex<()> {
        &self.artifact_write_locks[self.artifact_write_lock_index(artifact_id)]
    }

    fn namespace_lock_index(&self, namespace_id: &str) -> usize {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        std::hash::Hash::hash(namespace_id, &mut hasher);
        (std::hash::Hasher::finish(&hasher) as usize) % NAMESPACE_LOCK_STRIPES
    }

    fn namespace_lock_for(&self, namespace_id: &str) -> &RwLock<()> {
        &self.namespace_locks[self.namespace_lock_index(namespace_id)]
    }

    pub async fn artifact_exists(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
    ) -> Result<bool, String> {
        let artifact_id = artifact_storage_id(producer, &self.tenant_id, namespace_id, key);
        if self.existence_cache_contains(&artifact_id) {
            return Ok(true);
        }
        match self.manifest(&artifact_id)? {
            Some(manifest) => {
                let exists = self.storage_exists(&manifest).await?;
                if exists {
                    self.note_artifact_exists(&artifact_id);
                }
                Ok(exists)
            }
            None => Ok(false),
        }
    }

    /// Whether an artifact's manifest exists, without probing backing storage.
    /// Manifest presence is the right gate for advertising content (eviction
    /// removes the manifest together with the data), and skipping
    /// `storage_exists` keeps it cheap enough to run per snapshot node and
    /// immune to transient mid-promotion states.
    pub fn artifact_manifest_exists(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
    ) -> Result<bool, String> {
        let artifact_id = artifact_storage_id(producer, &self.tenant_id, namespace_id, key);
        if self.existence_cache_contains(&artifact_id) {
            return Ok(true);
        }
        Ok(self.manifest(&artifact_id)?.is_some())
    }

    /// The stored manifest for a logical artifact key, if any.
    pub fn manifest_for_key(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
    ) -> Result<Option<ArtifactManifest>, String> {
        self.manifest(&artifact_storage_id(
            producer,
            &self.tenant_id,
            namespace_id,
            key,
        ))
    }

    pub fn manifest(&self, artifact_id: &str) -> Result<Option<ArtifactManifest>, String> {
        if let Some(manifest) = self.manifest_cache_get(artifact_id) {
            self.io.metrics().record_manifest_cache_lookup("hit");
            return Ok(Some(manifest));
        }

        self.io.metrics().record_manifest_cache_lookup("miss");
        let manifest = self.manifest_from_db(artifact_id)?;
        if let Some(manifest) = &manifest {
            self.maybe_cache_manifest(manifest.clone());
        }
        Ok(manifest)
    }

    pub async fn fetch_artifact(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
    ) -> Result<Option<ArtifactManifest>, String> {
        let artifact_id = artifact_storage_id(producer, &self.tenant_id, namespace_id, key);
        match self.manifest(&artifact_id)? {
            Some(manifest) if self.storage_exists(&manifest).await? => {
                self.maybe_refresh_manifest(manifest, RefreshTrigger::Serve)
                    .await
            }
            Some(_) => Ok(None),
            None => Ok(None),
        }
    }

    pub async fn fetch_artifact_for_serving(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
    ) -> Result<Option<ArtifactManifest>, String> {
        let artifact_id = artifact_storage_id(producer, &self.tenant_id, namespace_id, key);
        match self.manifest(&artifact_id)? {
            Some(manifest) => self.prepare_artifact_for_serving(manifest).await,
            None => Ok(None),
        }
    }

    pub async fn fetch_artifact_by_id_for_serving(
        &self,
        artifact_id: &str,
    ) -> Result<Option<ArtifactManifest>, String> {
        match self.manifest(artifact_id)? {
            Some(manifest) => self.prepare_artifact_for_serving(manifest).await,
            None => Ok(None),
        }
    }

    pub fn fetch_inline_artifact_bytes(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
    ) -> Result<Option<Vec<u8>>, String> {
        let artifact_id = artifact_storage_id(producer, &self.tenant_id, namespace_id, key);
        let bytes = self.inline_bytes(&artifact_id)?;
        if bytes.is_some() {
            self.note_artifact_exists(&artifact_id);
        }
        Ok(bytes)
    }

    pub async fn persist_artifact_from_path_and_enqueue(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        staged: StagedArtifactPath<'_>,
        replication_targets: &[String],
    ) -> Result<PersistedArtifact, String> {
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms: now_ms(),
            replication_targets,
            branch: None,
            trunk: None,
        };
        let (outcome, already_present) = self
            .persist_artifact_from_path_with_version(spec, staged.path, staged.file_cache_policy)
            .await?;
        outcome.into_persisted(already_present, producer, namespace_id, key)
    }

    pub async fn apply_replicated_artifact_from_path<'a>(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        staged: impl Into<StagedArtifactPath<'a>>,
        version_ms: u64,
    ) -> Result<ArtifactApplyOutcome, String> {
        let staged = staged.into();
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms,
            replication_targets: &[],
            branch: None,
            trunk: None,
        };
        Ok(self
            .persist_artifact_from_path_with_version(spec, staged.path, staged.file_cache_policy)
            .await?
            .0
            .apply_outcome())
    }

    // The second element of the returned pair is `already_present` (see
    // [`PersistedArtifact`]), evaluated under the write lock below.
    async fn persist_artifact_from_path_with_version(
        &self,
        spec: PersistArtifactSpec<'_>,
        source_path: &Path,
        file_cache_policy: FileCachePolicy,
    ) -> Result<(PersistArtifactOutcome, bool), String> {
        // Read side of the namespace lock, held across this apply's tombstone
        // precheck and its commit. A delete taking the write side therefore
        // cannot commit its snapshot-scanned batch in between and leave this
        // row alive under a newer tombstone.
        let _namespace_guard = self.namespace_lock_for(spec.namespace_id).read().await;
        let artifact_id =
            artifact_storage_id(spec.producer, &self.tenant_id, spec.namespace_id, spec.key);
        // Hold the per-artifact write lock across the read-check, segment append,
        // and metadata commit. Without it, concurrent applies of the same key
        // each observe "absent" below, each append a full copy to a segment, and
        // only the last manifest write wins — leaving the rest as orphaned bytes
        // that accumulate to N x on disk (the backfill-from-many-peers ENOSPC).
        // Whoever wins the lock commits the manifest; the rest re-read it here and
        // short-circuit to IgnoredEqual without appending.
        let _write_guard = self.artifact_write_lock_for(&artifact_id).lock().await;
        let size = self.io.metadata_len(source_path).await?;

        let (existing, already_present) =
            match self.segment_apply_precheck(&artifact_id, &spec).await? {
                SegmentApplyPrecheck::Ignored {
                    outcome,
                    already_present,
                } => {
                    self.io.remove_file_if_exists(source_path).await;
                    return Ok((outcome, already_present));
                }
                SegmentApplyPrecheck::Proceed {
                    existing,
                    already_present,
                } => (existing, already_present),
            };
        let outbox_reservation = self.reserve_outbox_slots(spec.replication_targets.len())?;

        let (location, evicted_segments, _durability_seq) = self
            .append_to_segment(source_path, size, file_cache_policy, ApplyDurability::Sync)
            .await?;

        self.hit_failpoint(FailpointName::AfterArtifactBytesDurableBeforeMetadata)
            .await?;

        let manifest = self
            .commit_segment_manifest(
                &spec,
                &artifact_id,
                existing.as_ref(),
                &location,
                size,
                outbox_reservation,
            )
            .await?;

        self.evict_segments(evicted_segments).await?;

        Ok((PersistArtifactOutcome::Applied(manifest), already_present))
    }

    /// The LWW/tombstone gate of a segment-backed apply, evaluated under the
    /// per-artifact write lock the caller holds. Split out so the deferred
    /// backfill batch path can re-run the exact same check at phase-3 commit
    /// time (its phase-1 run is advisory: the lock is released between the
    /// two phases).
    async fn segment_apply_precheck(
        &self,
        artifact_id: &str,
        spec: &PersistArtifactSpec<'_>,
    ) -> Result<SegmentApplyPrecheck, String> {
        let existing = self.manifest_from_db(artifact_id)?;
        let already_present = match &existing {
            Some(existing) => self.storage_exists(existing).await?,
            None => false,
        };
        if let Some(existing_manifest) = &existing
            && already_present
            && (manifest_version_ms(existing_manifest) >= spec.version_ms || spec.version_ms == 0)
        {
            self.note_artifact_exists(artifact_id);
            return Ok(SegmentApplyPrecheck::Ignored {
                outcome: PersistArtifactOutcome::ignored(
                    existing_manifest.clone(),
                    spec.version_ms,
                ),
                already_present,
            });
        }
        if self.namespace_tombstone_blocks(spec.namespace_id, spec.version_ms)? {
            return Ok(SegmentApplyPrecheck::Ignored {
                outcome: PersistArtifactOutcome::IgnoredTombstone,
                already_present,
            });
        }
        Ok(SegmentApplyPrecheck::Proceed {
            existing,
            already_present,
        })
    }

    /// Builds and synchronously commits the manifest/metadata WriteBatch for
    /// a live segment-backed apply whose bytes already sit (fsynced) at
    /// `location`. The caller must hold the per-artifact write lock.
    async fn commit_segment_manifest(
        &self,
        spec: &PersistArtifactSpec<'_>,
        artifact_id: &str,
        existing: Option<&ArtifactManifest>,
        location: &SegmentLocation,
        size: u64,
        outbox_reservation: OutboxReservation<'_>,
    ) -> Result<ArtifactManifest, String> {
        let mut batch = WriteBatch::default();
        let mut bulk_outbox = 0;
        let manifest = self.stage_segment_manifest(
            &mut batch,
            spec,
            artifact_id,
            existing,
            location,
            size,
            &mut bulk_outbox,
        )?;
        self.write_batch_with_durability_off_runtime(
            batch,
            "manifest batch",
            ApplyDurability::Sync,
        )
        .await?;
        outbox_reservation.commit(bulk_outbox);
        self.note_segment_manifest_committed(&manifest, &location.segment_id)
            .await?;
        Ok(manifest)
    }

    /// Stages the manifest/metadata mutations of a segment-backed apply into
    /// `batch` without writing it. The caller must hold the per-artifact
    /// write lock across the precheck that produced `existing`, this staging,
    /// and the batch write, and must guarantee the segment bytes at
    /// `location` are durable before the write may reach the WAL: on the
    /// `Sync` path the append fsynced them; on the `DeferredBatch` path phase
    /// 2 of [`BackfillApplyBatch`] fsynced them before any phase-3 commit.
    #[allow(clippy::too_many_arguments)]
    fn stage_segment_manifest(
        &self,
        batch: &mut WriteBatch,
        spec: &PersistArtifactSpec<'_>,
        artifact_id: &str,
        existing: Option<&ArtifactManifest>,
        location: &SegmentLocation,
        size: u64,
        bulk_outbox: &mut usize,
    ) -> Result<ArtifactManifest, String> {
        let artifact_id = artifact_id.to_owned();
        let persisted_version_ms = persisted_version_ms(spec.version_ms);
        let manifest = ArtifactManifest {
            artifact_id: artifact_id.clone(),
            producer: spec.producer,
            namespace_id: spec.namespace_id.to_owned(),
            key: spec.key.to_owned(),
            content_type: spec.content_type.to_owned(),
            inline: false,
            blob_path: None,
            segment_id: Some(location.segment_id.clone()),
            segment_offset: Some(location.offset),
            size,
            version_ms: persisted_version_ms,
            created_at_ms: persisted_version_ms,
            branch: spec.branch.map(str::to_owned),
        };
        let metadata = manifest.metadata(&self.tenant_id);

        let manifest_bytes = encode_manifest_record(&manifest)?;
        batch.put_cf(
            self.cf(ROCKSDB_CF_MANIFESTS),
            artifact_id.as_bytes(),
            manifest_bytes,
        );
        batch.put_cf(
            self.cf(ROCKSDB_CF_NAMESPACE_ARTIFACTS),
            namespace_artifact_index_key(&metadata.namespace_id, &artifact_id).as_bytes(),
            [],
        );
        if manifest.producer == ArtifactProducer::Reapi
            && let Some(action_hash) = action_cache_manifest_hash(&manifest.key)
        {
            if let Some(previous_manifest) = &existing
                && let Some(previous_hash) = action_cache_manifest_hash(&previous_manifest.key)
                && previous_manifest.version_ms != manifest.version_ms
            {
                batch.delete_cf(
                    self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
                    action_cache_index_key(
                        &manifest.namespace_id,
                        previous_manifest.version_ms,
                        previous_hash,
                        // The row was keyed under the tag it held then, not the
                        // one being written now.
                        previous_manifest.branch.as_deref(),
                    ),
                );
            }
            batch.put_cf(
                self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
                action_cache_index_key(
                    &manifest.namespace_id,
                    manifest.version_ms,
                    action_hash,
                    manifest.branch.as_deref(),
                ),
                artifact_id.as_bytes(),
            );
            self.bump_action_cache_generation(&manifest.namespace_id);
            // No blob-refs (reverse index) maintenance for a segment-backed
            // entry. Every current write path keeps action-cache entries inline
            // (`update_action_result` rejects a body over
            // MAX_INLINE_REPLICATION_BODY_BYTES), so their reverse rows are staged
            // on the inline path. A segment-backed entry is still a structurally
            // supported shape, but the reverse index deliberately does not cover
            // it: this path, the startup backfill, and the delete paths all derive
            // reverse rows from inline bytes and skip a manifest without them. Such
            // an entry therefore gets no reverse rows and is never cascaded; the
            // serve-side presence gates (the same backstop the cascade lifts load
            // from) are its sole cover, which is safe.
        }
        if let Some(previous_manifest) = &existing
            && let Some(previous_segment_id) = &previous_manifest.segment_id
            && manifest.segment_id.as_deref() != Some(previous_segment_id.as_str())
        {
            batch.delete_cf(
                self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS),
                segment_artifact_index_key(previous_segment_id, &artifact_id).as_bytes(),
            );
        }
        if let Some(segment_id) = &manifest.segment_id {
            batch.put_cf(
                self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS),
                segment_artifact_index_key(segment_id, &artifact_id).as_bytes(),
                [],
            );
        }
        self.stage_backfill_index_update(batch, existing, &manifest);
        *bulk_outbox += self.append_artifact_replication_messages(
            batch,
            &manifest,
            spec.replication_targets,
            spec.trunk,
        )?;

        Ok(manifest)
    }

    /// Post-commit bookkeeping of a segment-backed apply, run right after the
    /// WriteBatch carrying its manifest lands (per record on the sync path,
    /// per group member on the deferred path).
    async fn note_segment_manifest_committed(
        &self,
        manifest: &ArtifactManifest,
        segment_id: &str,
    ) -> Result<(), String> {
        self.note_segment_version(segment_id, manifest_version_ms(manifest))
            .await?;
        self.hit_failpoint(FailpointName::AfterMetadataCommitBeforeReturn)
            .await?;
        self.maybe_cache_manifest(manifest.clone());
        self.note_artifact_exists(&manifest.artifact_id);
        Ok(())
    }

    pub async fn open_artifact_reader(
        &self,
        manifest: &ArtifactManifest,
    ) -> Result<ArtifactReader, String> {
        self.open_manifest_reader_with_range(manifest, 0, None)
            .await
    }

    pub async fn open_accelerated_artifact_file(
        &self,
        manifest: &ArtifactManifest,
    ) -> Result<Option<AcceleratedArtifactFile>, String> {
        if manifest.inline {
            return Ok(None);
        }

        if let Some(segment_id) = &manifest.segment_id {
            let offset = manifest
                .segment_offset
                .ok_or_else(|| "segment-backed manifest is missing segment offset".to_string())?;
            let handle = self.segment_handle(segment_id).await?;
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(Some(AcceleratedArtifactFile {
                handle,
                offset,
                size: manifest.size,
                content_type: manifest.content_type.clone(),
                version_ms: manifest.version_ms,
            }));
        }

        if let Some(blob_path) = &manifest.blob_path {
            let handle = self.blob_handle(blob_path).await?;
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(Some(AcceleratedArtifactFile {
                handle,
                offset: 0,
                size: manifest.size,
                content_type: manifest.content_type.clone(),
                version_ms: manifest.version_ms,
            }));
        }

        Ok(None)
    }

    /// Opportunistically maps an artifact's bytes for zero-copy serving.
    ///
    /// Returns `Ok(None)` whenever mmap serving is not appropriate, so callers
    /// fall back to the streaming reader path: inline artifacts, artifacts
    /// larger than the serving budget, no memory headroom, or a region whose
    /// pages are not already resident in the page cache. The residency gate
    /// means serving never faults disk I/O onto async workers; cold artifacts go
    /// through [`Self::read_artifact_bytes`], which isolates blocking reads with
    /// `spawn_blocking`. The mappings rely on segment and blob files being
    /// append-only and reclaimed by unlink, never truncated; see [`crate::mmap`]
    /// for the SIGBUS invariant this upholds.
    pub async fn try_mmap_artifact_bytes(
        &self,
        manifest: &ArtifactManifest,
    ) -> Result<Option<Bytes>, String> {
        if manifest.inline || manifest.size > self.memory.mmap_serving_pool_bytes() as u64 {
            return Ok(None);
        }

        if let Some(segment_id) = &manifest.segment_id {
            let offset = manifest
                .segment_offset
                .ok_or_else(|| "segment-backed manifest is missing segment offset".to_string())?;
            let Some(requested_bytes) = mapped_span_bytes(offset, manifest.size) else {
                return Ok(None);
            };
            let Some(permit) = self.memory.try_acquire_mmap_serving(requested_bytes) else {
                return Ok(None);
            };
            let handle = self.segment_handle(segment_id).await?;
            let Some(serve) = map_file_region(handle.as_std(), offset, manifest.size, permit)?
            else {
                return Ok(None);
            };
            if serve.partial_page_exempted {
                self.io.metrics().record_mmap_partial_page_exemption();
            }
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(Some(serve.bytes));
        }

        if let Some(blob_path) = &manifest.blob_path {
            let Some(requested_bytes) = mapped_span_bytes(0, manifest.size) else {
                return Ok(None);
            };
            let Some(permit) = self.memory.try_acquire_mmap_serving(requested_bytes) else {
                return Ok(None);
            };
            let handle = self.blob_handle(blob_path).await?;
            let Some(serve) = map_file_region(handle.as_std(), 0, manifest.size, permit)? else {
                return Ok(None);
            };
            if serve.partial_page_exempted {
                self.io.metrics().record_mmap_partial_page_exemption();
            }
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(Some(serve.bytes));
        }

        Ok(None)
    }

    pub async fn read_artifact_bytes(
        &self,
        manifest: &ArtifactManifest,
    ) -> Result<Vec<u8>, String> {
        if manifest.inline {
            let bytes = self
                .inline_bytes(&manifest.artifact_id)?
                .ok_or_else(|| "inline artifact bytes are missing".to_string())?;
            self.hit_failpoint(FailpointName::AfterReadArtifactBytesBeforeReturn)
                .await?;
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(bytes);
        }

        if let Some(segment_id) = &manifest.segment_id {
            let offset = manifest
                .segment_offset
                .ok_or_else(|| "segment-backed manifest is missing segment offset".to_string())?;
            let handle = self.segment_handle(segment_id).await?;
            let size = manifest.size;
            let bytes =
                tokio::task::spawn_blocking(move || read_bytes_at(handle.as_std(), offset, size))
                    .await
                    .map_err(|error| format!("failed to join segment read task: {error}"))??;
            self.hit_failpoint(FailpointName::AfterReadArtifactBytesBeforeReturn)
                .await?;
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(bytes);
        }

        if let Some(blob_path) = &manifest.blob_path {
            let handle = self.blob_handle(blob_path).await?;
            let size = manifest.size;
            let bytes =
                tokio::task::spawn_blocking(move || read_bytes_at(handle.as_std(), 0, size))
                    .await
                    .map_err(|error| format!("failed to join blob read task: {error}"))??;
            self.hit_failpoint(FailpointName::AfterReadArtifactBytesBeforeReturn)
                .await?;
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(bytes);
        }

        Err("manifest does not have a readable storage location".to_string())
    }

    /// Reads a served artifact's bytes, tolerating a concurrent background
    /// promotion (see [`Store::enqueue_promotion`]). A promotion can rewrite the
    /// artifact into the current segment and evict the old one between the
    /// caller's manifest read and the file open in `read_artifact_bytes`, so a
    /// stale manifest's open loses the race to the unlink. On the first read
    /// failure, re-resolve the manifest once against the DB: if the artifact
    /// moved (promoted), read from its new, live location; if it is genuinely
    /// gone, report a miss (`Ok(None)`) rather than an error; otherwise the
    /// failure was not a relocation and the original error stands.
    ///
    /// Only one retry is needed: the promoted copy lands in the current
    /// generation, which is not itself eligible for eviction, so it cannot be
    /// unlinked out from under the retried read.
    pub async fn read_artifact_bytes_tolerating_promotion(
        &self,
        manifest: &ArtifactManifest,
    ) -> Result<Option<Vec<u8>>, String> {
        match self.read_artifact_bytes(manifest).await {
            Ok(bytes) => Ok(Some(bytes)),
            Err(first_error) => match self.manifest_from_db(&manifest.artifact_id)? {
                Some(fresh) if fresh.segment_id != manifest.segment_id => {
                    self.read_artifact_bytes(&fresh).await.map(Some)
                }
                Some(_) => Err(first_error),
                None => Ok(None),
            },
        }
    }

    /// Opens a served artifact's reader, tolerating a concurrent background
    /// promotion — the streaming-read counterpart of
    /// [`Store::read_artifact_bytes_tolerating_promotion`], with the same
    /// resolution rules: on the first open failure, re-resolve the manifest
    /// once; if the artifact moved (promoted), open at its new, live location;
    /// if it is genuinely gone, report a miss (`Ok(None)`); otherwise the
    /// original error stands. Returns the manifest that was actually opened so
    /// callers derive response metadata (size, content type) from the copy the
    /// bytes come from.
    pub async fn open_artifact_reader_range_tolerating_promotion(
        &self,
        manifest: &ArtifactManifest,
        read_offset: u64,
        read_limit: Option<u64>,
    ) -> Result<Option<(ArtifactManifest, ArtifactReader)>, String> {
        match self
            .open_manifest_reader_with_range(manifest, read_offset, read_limit)
            .await
        {
            Ok(reader) => Ok(Some((manifest.clone(), reader))),
            Err(first_error) => match self.manifest_from_db(&manifest.artifact_id)? {
                Some(fresh) if fresh.segment_id != manifest.segment_id => self
                    .open_manifest_reader_with_range(&fresh, read_offset, read_limit)
                    .await
                    .map(|reader| Some((fresh, reader))),
                Some(_) => Err(first_error),
                None => Ok(None),
            },
        }
    }

    async fn open_manifest_reader(
        &self,
        manifest: &ArtifactManifest,
    ) -> Result<ArtifactReader, String> {
        self.open_manifest_reader_with_range(manifest, 0, None)
            .await
    }

    async fn open_manifest_reader_with_range(
        &self,
        manifest: &ArtifactManifest,
        read_offset: u64,
        read_limit: Option<u64>,
    ) -> Result<ArtifactReader, String> {
        if read_offset > manifest.size {
            return Err(format!(
                "requested read offset {read_offset} exceeds artifact size {}",
                manifest.size
            ));
        }
        let readable_bytes = manifest.size.saturating_sub(read_offset);
        let limit = read_limit.unwrap_or(readable_bytes).min(readable_bytes);

        if manifest.inline
            && let Some(bytes) = self.inline_bytes(&manifest.artifact_id)?
        {
            let start = read_offset as usize;
            let end = start.saturating_add(limit as usize).min(bytes.len());
            let chunk = Bytes::from(bytes).slice(start..end);
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(ArtifactReader::Inline {
                bytes: chunk,
                offset: 0,
            });
        }

        if let Some(segment_id) = &manifest.segment_id {
            let offset = manifest
                .segment_offset
                .ok_or_else(|| "segment-backed manifest is missing segment offset".to_string())?;
            let handle = self.segment_handle(segment_id).await?;
            // Guard the append-only / never-truncated invariant the serving path
            // relies on (see `try_mmap_artifact_bytes`). A truncated segment would
            // otherwise yield a short read that streams a body shorter than the
            // declared Content-Length — peers see an undecodable response and
            // backfill silently wedges. Surface a truncated artifact as missing
            // so the serve 404s it; the backfilling peer classifies that as
            // absent (`classify_backfill_response`) and moves on, and the lost
            // entry re-populates on cache miss.
            let needed = offset.saturating_add(read_offset).saturating_add(limit);
            let have = handle
                .as_std()
                .metadata()
                .map_err(|error| format!("failed to stat segment {segment_id}: {error}"))?
                .len();
            if have < needed {
                return Err(format!(
                    "segment {segment_id} truncated: holds {have} bytes but artifact {} needs {needed}",
                    manifest.artifact_id
                ));
            }
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(ArtifactReader::FileRange(SegmentReader::new(
                handle,
                offset + read_offset,
                limit,
            )));
        }

        if let Some(blob_path) = &manifest.blob_path {
            let handle = self.blob_handle(blob_path).await?;
            let needed = read_offset.saturating_add(limit);
            let have = handle
                .as_std()
                .metadata()
                .map_err(|error| format!("failed to stat blob {blob_path}: {error}"))?
                .len();
            if have < needed {
                return Err(format!(
                    "blob {blob_path} truncated: holds {have} bytes but artifact {} needs {needed}",
                    manifest.artifact_id
                ));
            }
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(ArtifactReader::FileRange(SegmentReader::new(
                handle,
                read_offset,
                limit,
            )));
        }

        Err("manifest does not have a readable storage location".to_string())
    }

    async fn prepare_artifact_for_serving(
        &self,
        manifest: ArtifactManifest,
    ) -> Result<Option<ArtifactManifest>, String> {
        let Some(segment_id) = manifest.segment_id.as_deref() else {
            return Ok(Some(manifest));
        };
        if self.segment_generation(segment_id)? != Some(SegmentGeneration::Old) {
            return Ok(Some(manifest));
        }
        // Serve straight from the Old segment and promote in the background.
        // Refreshing inline here serialized every reader of old data on
        // `segment_refresh_lock`, one artifact at a time; serving without the
        // refresh is already the store's behavior under memory pressure (see
        // maybe_refresh_manifest), so the only change is when the promotion
        // happens, not whether serving old data is allowed. The read itself is
        // safe against a concurrent reclaim: segments are unlinked, never
        // truncated, so an open handle stays readable, and a lost race simply
        // degrades that lookup to a miss as before.
        self.enqueue_promotion(&manifest.artifact_id, RefreshTrigger::Serve);
        Ok(Some(manifest))
    }

    /// Queues an artifact from an Old segment for background promotion (see
    /// [`Store::run_promotion_worker`]). Deduplicated and bounded, with
    /// [`VOUCHED_PROMOTION_RESERVE`] of the bound admitting vouched-for
    /// refreshes only.
    ///
    /// A dropped entry is recorded on `kura_promotion_drops_total`. Dropping a
    /// serve-path entry is safe, since that read already succeeded and the
    /// promotion is a keep-alive for later ones. Dropping a vouched entry means
    /// the node answered an RPC that promises the blob stays fetchable and then
    /// did nothing to keep it, so it is the signal that read-triggered
    /// extension is not keeping up.
    fn enqueue_promotion(&self, artifact_id: &str, trigger: RefreshTrigger) {
        {
            let mut queue = self.promotion_queue.lock().expect("promotion queue lock");
            if let Some(pending) = queue.pending.get_mut(artifact_id) {
                // Already queued: take the strongest trigger seen, so a
                // serve-path enqueue cannot downgrade a vouched-for blob out of
                // the wider pressure gate. An upgrade also re-queues it in the
                // vouched lane, since waiting out the serve backlog would leave
                // the vouch unbacked for as long as a drop would.
                let upgraded = trigger > *pending;
                *pending = (*pending).max(trigger);
                if upgraded && trigger.extends_vouched_lifetime() {
                    queue.vouched.push_back(artifact_id.to_owned());
                }
                return;
            }
            let ceiling = if trigger.extends_vouched_lifetime() {
                MAX_PENDING_PROMOTIONS
            } else {
                MAX_PENDING_PROMOTIONS - VOUCHED_PROMOTION_RESERVE
            };
            if queue.depth() >= ceiling {
                drop(queue);
                self.io.metrics().record_promotion_drop(trigger.as_str());
                return;
            }
            queue.pending.insert(artifact_id.to_owned(), trigger);
            queue.push(artifact_id, trigger);
        }
        self.promotion_notify.notify_one();
    }

    /// Whether any segment has aged into the Old generation, which is the only
    /// state in which lifetime extension has work to do. Read-path callers
    /// hoist this so a node whose data all sits in live segments pays one
    /// state-snapshot read for a whole request instead of a manifest lookup per
    /// blob.
    pub fn segment_ring_is_aging(&self) -> bool {
        !self.segment_state_snapshot().state.old.is_empty()
    }

    /// Presence check that extends the blob's lifetime from the *same* manifest
    /// lookup, for read paths whose request size the client controls.
    ///
    /// [`Store::artifact_exists`] followed by
    /// [`Store::extend_artifact_lifetimes`] would resolve every key twice, and
    /// the second pass lands on RocksDB whenever manifest-cache admission is
    /// closed, which is exactly the `Constrained` tier read-triggered refresh
    /// still runs at. Callers gate this on [`Store::segment_ring_is_aging`] and
    /// otherwise use the plain existence check, whose existence-cache
    /// short-circuit this necessarily gives up: that cache answers presence but
    /// carries no segment, so it cannot say whether a blob needs promoting.
    pub async fn artifact_exists_extending_lifetime(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        trigger: RefreshTrigger,
    ) -> Result<bool, String> {
        let artifact_id = artifact_storage_id(producer, &self.tenant_id, namespace_id, key);
        let Some(manifest) = self.manifest(&artifact_id)? else {
            return Ok(false);
        };
        if !self.storage_exists(&manifest).await? {
            return Ok(false);
        }
        self.note_artifact_exists(&artifact_id);
        if let Some(segment_id) = manifest.segment_id.as_deref()
            && self.segment_generation(segment_id)? == Some(SegmentGeneration::Old)
        {
            self.enqueue_promotion(&artifact_id, trigger);
        }
        Ok(true)
    }

    /// Extends the lifetimes of blobs a REAPI read path has just vouched for.
    ///
    /// `GetActionResult` presence-gates an entry and `FindMissingBlobs` reports
    /// a blob present, but both answer from metadata alone
    /// ([`Store::artifact_manifest_exists`], [`Store::artifact_exists`]) and
    /// neither routes through [`Store::prepare_artifact_for_serving`], the only
    /// caller that keeps a blob alive. Without this, eviction can remove a blob
    /// between the node vouching for it and the client's `BatchReadBlobs`.
    ///
    /// Copy-forward rather than a reservation: promotion makes the blob
    /// genuinely young again, so the ordinary eviction policy needs no special
    /// case, nothing has to be honored later, and the extension survives a
    /// restart. Best-effort and off the request path: this only queues work for
    /// [`Store::run_promotion_worker`], which re-validates every entry and is
    /// serialized by `segment_refresh_lock`. A blob already in a live
    /// segment costs one manifest lookup, and a node holding no Old segments
    /// costs a single state-snapshot read for the whole batch.
    pub fn extend_artifact_lifetimes(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        keys: &[String],
        trigger: RefreshTrigger,
    ) {
        let segment_state = self.segment_state_snapshot();
        if segment_state.state.old.is_empty() {
            return;
        }

        for key in keys {
            let artifact_id = artifact_storage_id(producer, &self.tenant_id, namespace_id, key);
            let Ok(Some(manifest)) = self.manifest(&artifact_id) else {
                continue;
            };
            let Some(segment_id) = manifest.segment_id.as_deref() else {
                continue;
            };
            if segment_state.generations.get(segment_id).copied() == Some(SegmentGeneration::Old) {
                self.enqueue_promotion(&artifact_id, trigger);
            }
        }
    }

    /// Drains the read-path promotion queue, rewriting each artifact from its
    /// Old segment into the current one (the same refresh the serving path
    /// used to run inline). Runs for the life of the process; spawned once at
    /// boot.
    pub async fn run_promotion_worker(&self) {
        loop {
            let next = self
                .promotion_queue
                .lock()
                .expect("promotion queue lock")
                .pop();
            let Some((artifact_id, trigger)) = next else {
                self.promotion_notify.notified().await;
                continue;
            };
            if let Err(error) = self.promote_artifact(&artifact_id, trigger).await {
                self.io.metrics().record_promotion_failure();
                tracing::warn!(artifact_id, error, "segment promotion failed");
            }
        }
    }

    /// Promotes one artifact out of an Old segment, re-validating that the
    /// manifest still exists and still lives in an Old segment (it may have
    /// been promoted by a writer, replaced, or reclaimed since it was queued).
    async fn promote_artifact(
        &self,
        artifact_id: &str,
        trigger: RefreshTrigger,
    ) -> Result<(), String> {
        let Some(manifest) = self.manifest(artifact_id)? else {
            return Ok(());
        };
        let Some(segment_id) = manifest.segment_id.as_deref() else {
            return Ok(());
        };
        if self.segment_generation(segment_id)? != Some(SegmentGeneration::Old) {
            return Ok(());
        }
        self.maybe_refresh_manifest(manifest, trigger)
            .await
            .map(|_| ())
    }

    async fn maybe_refresh_manifest(
        &self,
        manifest: ArtifactManifest,
        trigger: RefreshTrigger,
    ) -> Result<Option<ArtifactManifest>, String> {
        let allowed = if trigger.extends_vouched_lifetime() {
            self.memory.allow_read_triggered_refresh()
        } else {
            self.memory.allow_segment_refresh()
        };
        if !allowed {
            self.io
                .metrics()
                .record_memory_action("segment_refresh_skipped");
            self.io
                .metrics()
                .record_segment_refresh_skipped(manifest.producer, trigger.as_str());
            return Ok(Some(manifest));
        }
        let Some(segment_id) = manifest.segment_id.as_deref() else {
            return Ok(Some(manifest));
        };
        if self.segment_generation(segment_id)? != Some(SegmentGeneration::Old) {
            return Ok(Some(manifest));
        }

        let refresh_started = std::time::Instant::now();
        let _guard = self.segment_refresh_lock.lock().await;
        let Some(current) = self.manifest(&manifest.artifact_id)? else {
            return Ok(None);
        };
        let Some(current_segment_id) = current.segment_id.as_deref() else {
            return Ok(Some(current));
        };
        if self.segment_generation(current_segment_id)? != Some(SegmentGeneration::Old) {
            return Ok(Some(current));
        }
        if !self.storage_exists(&current).await? {
            return Ok(None);
        }

        let mut reader = self.open_manifest_reader(&current).await?;
        let (location, evicted_segments, _durability_seq) = self
            .append_reader_to_segment(
                &mut reader,
                current.size,
                None,
                FileCachePolicy::Adaptive,
                ApplyDurability::Sync,
            )
            .await?;
        let mut refreshed = current.clone();
        let previous_segment_id = current_segment_id.to_owned();
        refreshed.inline = false;
        refreshed.blob_path = None;
        refreshed.segment_id = Some(location.segment_id.clone());
        refreshed.segment_offset = Some(location.offset);

        // Deliberately NOT instrumented for the backfill index: promotion
        // keeps the artifact's version, kind (segment-backed in, segment-backed
        // out), and size, so its index row's key and value are unchanged.
        let mut batch = WriteBatch::default();
        let manifest_bytes = encode_manifest_record(&refreshed)?;
        batch.put_cf(
            self.cf(ROCKSDB_CF_MANIFESTS),
            refreshed.artifact_id.as_bytes(),
            manifest_bytes,
        );
        batch.delete_cf(
            self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS),
            segment_artifact_index_key(&previous_segment_id, &current.artifact_id).as_bytes(),
        );
        batch.put_cf(
            self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS),
            segment_artifact_index_key(&location.segment_id, &current.artifact_id).as_bytes(),
            [],
        );
        self.write_batch_with_durability_off_runtime(
            batch,
            "refreshed manifest",
            ApplyDurability::Sync,
        )
        .await?;
        // The promoted entry keeps its original version, which the max-only
        // stat semantics absorb without dragging the destination segment's
        // seal-time max down.
        self.note_segment_version(&location.segment_id, manifest_version_ms(&refreshed))
            .await?;
        self.maybe_cache_manifest(refreshed.clone());

        self.io.metrics().record_segment_refresh(
            current.producer,
            "ok",
            trigger.as_str(),
            current.size,
            refresh_started.elapsed(),
        );
        self.evict_segments(evicted_segments).await?;

        Ok(Some(refreshed))
    }

    async fn storage_exists(&self, manifest: &ArtifactManifest) -> Result<bool, String> {
        if manifest.inline && self.inline_bytes(&manifest.artifact_id)?.is_some() {
            return Ok(true);
        }
        if manifest.is_segment_backed() {
            let segment_id = manifest
                .segment_id
                .as_ref()
                .expect("segment-backed manifest should have a segment id");
            return self.io.path_exists(&self.segment_path(segment_id)).await;
        }
        if let Some(blob_path) = &manifest.blob_path {
            return self.io.path_exists(Path::new(blob_path)).await;
        }
        Ok(false)
    }

    async fn persist_inline_artifact_with_version(
        &self,
        spec: PersistArtifactSpec<'_>,
        bytes: &[u8],
    ) -> Result<PersistArtifactOutcome, String> {
        // Read side of the namespace lock, held across this apply's tombstone
        // precheck and its commit. A delete taking the write side therefore
        // cannot commit its snapshot-scanned batch in between and leave this
        // row alive under a newer tombstone.
        let _namespace_guard = self.namespace_lock_for(spec.namespace_id).read().await;
        let artifact_id =
            artifact_storage_id(spec.producer, &self.tenant_id, spec.namespace_id, spec.key);

        // Hold the per-artifact write lock across the read, the sticky-tag
        // decision and the commit. The tag is a read-modify-write over the
        // stored manifest, so computing it from a read taken outside the lock
        // lets a feature build that observed "no entry" resume after a trunk
        // build committed `main`, and overwrite it with the `feature` tag it
        // precomputed, and with a newer version, so nothing downstream rejects
        // it. The key then leaves the trunk baseline it had just joined.
        let _write_guard = self.artifact_write_lock_for(&artifact_id).lock().await;

        let existing = match self.inline_apply_precheck(&artifact_id, &spec).await? {
            InlineApplyPrecheck::Ignored { outcome } => return Ok(outcome),
            InlineApplyPrecheck::Proceed { existing } => existing,
        };
        // Resolved here, under the lock, from the precheck's read: every inline
        // writer goes through this function or the backfill group commit, so
        // the tag decision and the write it feeds cannot be split by a racing
        // peer.
        let branch = sticky_branch(existing.as_ref(), spec.branch, spec.trunk);
        let outbox_reservation = self.reserve_outbox_slots(spec.replication_targets.len())?;

        let mut batch = WriteBatch::default();
        let mut bulk_outbox = 0;
        let (manifest, wrote_action_cache_index) = self.stage_inline_manifest(
            &mut batch,
            &spec,
            &artifact_id,
            existing.as_ref(),
            branch,
            bytes,
            &mut bulk_outbox,
        )?;

        self.write_batch_with_durability_off_runtime(
            batch,
            "keyvalue batch",
            ApplyDurability::Sync,
        )
        .await?;
        outbox_reservation.commit(bulk_outbox);
        self.note_inline_manifest_committed(&manifest, wrote_action_cache_index);

        self.hit_failpoint(FailpointName::AfterMetadataCommitBeforeReturn)
            .await?;

        Ok(PersistArtifactOutcome::Applied(manifest))
    }

    /// The LWW/tombstone gate of an inline apply, evaluated under the
    /// per-artifact write lock the caller holds. Split out so the backfill
    /// group commit can re-run the exact same check at phase-3 commit time
    /// (its phase-1 run is advisory: the lock is released between the two
    /// phases).
    async fn inline_apply_precheck(
        &self,
        artifact_id: &str,
        spec: &PersistArtifactSpec<'_>,
    ) -> Result<InlineApplyPrecheck, String> {
        let existing = self.manifest_from_db(artifact_id)?;
        // Widens the read-to-commit window a racing writer would have to hit.
        self.hit_failpoint(FailpointName::AfterInlineManifestReadBeforeCommit)
            .await?;
        if let Some(existing_manifest) = &existing
            && existing_manifest.inline
            && self.inline_bytes(artifact_id)?.is_some()
            && (manifest_version_ms(existing_manifest) >= spec.version_ms || spec.version_ms == 0)
        {
            self.note_artifact_exists(artifact_id);
            return Ok(InlineApplyPrecheck::Ignored {
                outcome: PersistArtifactOutcome::ignored(
                    existing_manifest.clone(),
                    spec.version_ms,
                ),
            });
        }
        if self.namespace_tombstone_blocks(spec.namespace_id, spec.version_ms)? {
            return Ok(InlineApplyPrecheck::Ignored {
                outcome: PersistArtifactOutcome::IgnoredTombstone,
            });
        }
        Ok(InlineApplyPrecheck::Proceed { existing })
    }

    /// Stages the manifest/bytes/index mutations of an inline apply into
    /// `batch` without writing it. The caller must hold the per-artifact
    /// write lock across the precheck that produced `existing` and `branch`,
    /// this staging, and the batch write. Returns the manifest and whether an
    /// action-cache index row was staged (whose generation bump the caller
    /// owes AFTER the batch commits — see
    /// [`Self::note_inline_manifest_committed`]).
    #[allow(clippy::too_many_arguments)]
    fn stage_inline_manifest(
        &self,
        batch: &mut WriteBatch,
        spec: &PersistArtifactSpec<'_>,
        artifact_id: &str,
        existing: Option<&ArtifactManifest>,
        branch: Option<&str>,
        bytes: &[u8],
        bulk_outbox: &mut usize,
    ) -> Result<(ArtifactManifest, bool), String> {
        let artifact_id = artifact_id.to_owned();
        let persisted_version_ms = persisted_version_ms(spec.version_ms);

        let manifest = ArtifactManifest {
            artifact_id: artifact_id.clone(),
            producer: spec.producer,
            namespace_id: spec.namespace_id.to_owned(),
            key: spec.key.to_owned(),
            content_type: spec.content_type.to_owned(),
            inline: true,
            blob_path: None,
            segment_id: None,
            segment_offset: None,
            size: bytes.len() as u64,
            version_ms: persisted_version_ms,
            created_at_ms: persisted_version_ms,
            branch: branch.map(str::to_owned),
        };
        let metadata = manifest.metadata(&self.tenant_id);

        let manifest_bytes = encode_manifest_record(&manifest)?;
        batch.put_cf(
            self.cf(ROCKSDB_CF_MANIFESTS),
            artifact_id.as_bytes(),
            manifest_bytes,
        );
        batch.put_cf(self.cf(ROCKSDB_CF_KEY_VALUE), artifact_id.as_bytes(), bytes);
        batch.put_cf(
            self.cf(ROCKSDB_CF_NAMESPACE_ARTIFACTS),
            namespace_artifact_index_key(&metadata.namespace_id, &artifact_id).as_bytes(),
            [],
        );
        let mut wrote_action_cache_index = false;
        if manifest.producer == ArtifactProducer::Reapi
            && let Some(action_hash) = action_cache_manifest_hash(&manifest.key)
        {
            if let Some(previous_manifest) = &existing
                && let Some(previous_hash) = action_cache_manifest_hash(&previous_manifest.key)
                && previous_manifest.version_ms != manifest.version_ms
            {
                batch.delete_cf(
                    self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
                    action_cache_index_key(
                        &manifest.namespace_id,
                        previous_manifest.version_ms,
                        previous_hash,
                        // The row was keyed under the tag it held then, not the
                        // one being written now.
                        previous_manifest.branch.as_deref(),
                    ),
                );
            }
            batch.put_cf(
                self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
                action_cache_index_key(
                    &manifest.namespace_id,
                    manifest.version_ms,
                    action_hash,
                    manifest.branch.as_deref(),
                ),
                artifact_id.as_bytes(),
            );
            wrote_action_cache_index = true;

            // Reverse index (blob -> referencing entry) maintenance, committed in
            // the same batch as the entry so eviction can cascade this entry when
            // a blob it references is dropped, rather than stranding it. On a
            // re-publish the previous version's rows are removed first: the entry
            // id is stable across versions, only the referenced blob set can
            // change, and a delete-then-put on an unchanged blob leaves the row
            // in place (the put is applied after the delete within the batch).
            if existing.is_some()
                && let Some(previous_bytes) = self.inline_bytes(&artifact_id)?
            {
                self.stage_action_cache_blob_refs_delete(
                    batch,
                    &manifest.namespace_id,
                    &artifact_id,
                    &previous_bytes,
                );
            }
            self.stage_action_cache_blob_refs_put(
                batch,
                &manifest.namespace_id,
                &artifact_id,
                bytes,
            );
        }
        self.stage_backfill_index_update(batch, existing, &manifest);
        *bulk_outbox += self.append_artifact_replication_messages(
            batch,
            &manifest,
            spec.replication_targets,
            spec.trunk,
        )?;

        Ok((manifest, wrote_action_cache_index))
    }

    /// Post-commit bookkeeping of an inline apply, run right after the
    /// WriteBatch carrying its manifest lands (per record on the sync path,
    /// per group member on the deferred path).
    fn note_inline_manifest_committed(
        &self,
        manifest: &ArtifactManifest,
        wrote_action_cache_index: bool,
    ) {
        // Only after the batch commits: the generation is what a snapshot serve
        // reads to decide its cached view is current, and the new index row is
        // not visible to that scan until the write lands. Bumping before the
        // commit lets a concurrent serve stamp the pre-commit (row-less) view
        // with the new generation and then answer later requests from it.
        if wrote_action_cache_index {
            self.bump_action_cache_generation(&manifest.namespace_id);
        }
        self.maybe_cache_manifest(manifest.clone());
        self.note_artifact_exists(&manifest.artifact_id);
    }

    pub(crate) fn inline_bytes(&self, artifact_id: &str) -> Result<Option<Vec<u8>>, String> {
        self.db
            .get_cf(self.cf(ROCKSDB_CF_KEY_VALUE), artifact_id.as_bytes())
            .map_err(|error| format!("failed to read inline artifact bytes: {error}"))
    }

    async fn append_to_segment(
        &self,
        source_path: &Path,
        size: u64,
        file_cache_policy: FileCachePolicy,
        durability: ApplyDurability,
    ) -> Result<(SegmentLocation, Vec<SegmentReference>, u64), String> {
        let mut source = self.io.open_file(source_path).await?;
        let result = self
            .append_reader_to_segment(
                &mut source,
                size,
                Some(source_path),
                file_cache_policy,
                durability,
            )
            .await;
        self.io.remove_file_if_exists(source_path).await;
        result
    }

    /// The returned `u64` is the append's group-commit durability sequence.
    /// Under [`ApplyDurability::Sync`] it is already covered by the fsync this
    /// function performs; under [`ApplyDurability::DeferredBatch`] the caller
    /// must pass it to [`Self::ensure_segment_durable`] before committing any
    /// manifest that references the appended bytes.
    async fn append_reader_to_segment<R>(
        &self,
        source: &mut R,
        size: u64,
        source_cache_path: Option<&Path>,
        file_cache_policy: FileCachePolicy,
        durability: ApplyDurability,
    ) -> Result<(SegmentLocation, Vec<SegmentReference>, u64), String>
    where
        R: AsyncRead + Unpin,
    {
        // Append the bytes under the write lock (which also fsyncs the outgoing
        // segment on rotation), then reserve a durability sequence. The fsync
        // itself happens after the lock so concurrent writers coalesce into a
        // single group-commit fsync rather than serializing one fsync each.
        let (location, evicted_segments, durability_seq) = {
            let _guard = self.segment_write_lock.lock().await;
            let (segment, evicted_segments) = self.active_segment(size).await?;
            let segment_path = self.segment_path(&segment.segment_id);
            let segment_dir = segment_path
                .parent()
                .ok_or_else(|| "missing segment parent directory".to_string())?;
            self.io.create_dir_all(segment_dir).await?;

            let segment_already_exists = self.io.path_exists(&segment_path).await?;
            let offset = if segment_already_exists {
                self.io.metadata_len(&segment_path).await?
            } else {
                0
            };

            let mut destination = self.io.open_append_file(&segment_path).await?;
            let mut buffer = vec![0_u8; SEGMENT_COPY_BUFFER_BYTES];
            let mut copied = 0_u64;
            let mut advised_through = 0_u64;
            while copied < size {
                let remaining = usize::try_from((size - copied).min(buffer.len() as u64))
                    .expect("copy chunk fits usize");
                let read = source
                    .read(&mut buffer[..remaining])
                    .await
                    .map_err(|error| {
                        format!(
                            "failed to read source while appending into segment {}: {error}",
                            segment_path.display()
                        )
                    })?;
                if read == 0 {
                    break;
                }
                destination
                    .write_all(&buffer[..read])
                    .await
                    .map_err(|error| {
                        format!(
                            "failed to append into segment {}: {error}",
                            segment_path.display()
                        )
                    })?;
                copied = copied.saturating_add(read as u64);

                if copied.saturating_sub(advised_through)
                    >= FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES
                    && file_cache_policy.should_drop(
                        self.memory.should_reclaim_file_cache(),
                        self.memory.transient_reserved_bytes(),
                    )
                {
                    destination = match self
                        .io
                        .sync_drop_cache_and_reopen_append(
                            destination,
                            &segment_path,
                            offset.saturating_add(advised_through),
                            copied - advised_through,
                        )
                        .await
                    {
                        Ok(destination) => destination,
                        Err(error) => {
                            self.io
                                .metrics()
                                .record_memory_action("segment_file_cache_drop_failed");
                            return Err(format!(
                                "failed to bound segment file cache for {}: {error}",
                                segment_path.display()
                            ));
                        }
                    };
                    if let Some(source_path) = source_cache_path
                        && let Err(error) = self
                            .io
                            .drop_cached_pages(
                                source_path,
                                advised_through,
                                copied - advised_through,
                            )
                            .await
                    {
                        self.io
                            .metrics()
                            .record_memory_action("source_file_cache_drop_failed");
                        tracing::warn!("failed to release source file cache: {error}");
                        if file_cache_policy.drop_failure_is_fatal() {
                            return Err(format!(
                                "failed to bound source file cache while appending {}: {error}",
                                segment_path.display()
                            ));
                        }
                    }
                    advised_through = copied;
                    self.io
                        .metrics()
                        .record_memory_action("segment_file_cache_drop");
                }
            }
            if copied != size {
                return Err(format!(
                    "appended {copied} bytes into segment {}, expected {size}",
                    segment_path.display()
                ));
            }
            destination.flush().await.map_err(|error| {
                format!(
                    "failed to flush segment {}: {error}",
                    segment_path.display()
                )
            })?;
            let drop_final_range = copied > advised_through
                && file_cache_policy.should_drop(
                    self.memory.should_reclaim_file_cache(),
                    self.memory.transient_reserved_bytes(),
                );
            if drop_final_range {
                destination.sync_data().await.map_err(|error| {
                    format!("failed to sync segment {}: {error}", segment_path.display())
                })?;
                drop(destination);
                if let Err(error) = self
                    .io
                    .drop_cached_pages(
                        &segment_path,
                        offset.saturating_add(advised_through),
                        copied - advised_through,
                    )
                    .await
                {
                    self.io
                        .metrics()
                        .record_memory_action("segment_file_cache_drop_failed");
                    tracing::warn!(
                        path = %segment_path.display(),
                        "failed to release segment file cache: {error}"
                    );
                    if file_cache_policy.drop_failure_is_fatal() {
                        return Err(format!(
                            "failed to bound segment file cache for {}: {error}",
                            segment_path.display()
                        ));
                    }
                }
                if let Some(source_path) = source_cache_path
                    && let Err(error) = self
                        .io
                        .drop_cached_pages(source_path, advised_through, copied - advised_through)
                        .await
                {
                    self.io
                        .metrics()
                        .record_memory_action("source_file_cache_drop_failed");
                    tracing::warn!("failed to release source file cache: {error}");
                    if file_cache_policy.drop_failure_is_fatal() {
                        return Err(format!(
                            "failed to bound source file cache while appending {}: {error}",
                            segment_path.display()
                        ));
                    }
                }
            } else {
                drop(destination);
            }
            if !segment_already_exists {
                self.io.sync_directory(segment_dir).await?;
            }

            let durability_seq = self.pending_seq.fetch_add(1, Ordering::AcqRel) + 1;
            (
                SegmentLocation {
                    segment_id: segment.segment_id,
                    offset,
                },
                evicted_segments,
                durability_seq,
            )
        };

        if durability == ApplyDurability::Sync {
            self.ensure_segment_durable(durability_seq).await?;
        }

        Ok((location, evicted_segments, durability_seq))
    }

    /// Group-commit fsync: makes every append with sequence `<= seq` durable.
    ///
    /// Writers reserve `pending_seq` in append order while holding the write
    /// lock, then call this. The first writer to win `fsync_lock` performs one
    /// fsync of the active segment and advances `durable_seq` to the latest
    /// reserved sequence. That is correct because a segment is fsynced when it
    /// rotates out (see `active_segment`), so only the active segment can hold
    /// un-synced bytes — and if the active segment rotated between a writer's
    /// append and this fsync, that writer's bytes were already made durable by
    /// the rotation. Writers already covered by a prior fsync return without
    /// syncing.
    async fn ensure_segment_durable(&self, seq: u64) -> Result<(), String> {
        if self.durable_seq.load(Ordering::Acquire) >= seq {
            return Ok(());
        }
        let _commit = self.fsync_lock.lock().await;
        if self.durable_seq.load(Ordering::Acquire) >= seq {
            return Ok(());
        }
        self.hit_failpoint(FailpointName::BeforeSegmentFsync)
            .await?;
        // Capture after winning the commit lock so the fsync covers writers that
        // appended while we queued.
        let target = self.pending_seq.load(Ordering::Acquire);
        self.fsync_active_segment().await?;
        self.durable_seq.store(target, Ordering::Release);
        Ok(())
    }

    /// Fsyncs the current active segment file. A fresh handle is fine: `sync_data`
    /// flushes the inode's dirty pages regardless of which descriptor wrote them.
    async fn fsync_active_segment(&self) -> Result<(), String> {
        let snapshot = self.segment_state_snapshot();
        let Some(active) = snapshot.state.active() else {
            return Ok(());
        };
        let path = self.segment_path(&active.segment_id);
        if !self.io.path_exists(&path).await? {
            return Ok(());
        }
        let file = self.io.open_append_file(&path).await?;
        self.segment_fsync_count.fetch_add(1, Ordering::Relaxed);
        file.sync_data()
            .await
            .map_err(|error| format!("failed to sync segment {}: {error}", path.display()))?;
        Ok(())
    }

    async fn active_segment(
        &self,
        incoming_size: u64,
    ) -> Result<(SegmentReference, Vec<SegmentReference>), String> {
        let snapshot = self.segment_state_snapshot();
        let needs_new_segment = match snapshot.state.active() {
            Some(segment) => {
                let path = self.segment_path(&segment.segment_id);
                let current_size = if self.io.path_exists(&path).await? {
                    self.io.metadata_len(&path).await?
                } else {
                    0
                };
                current_size.saturating_add(incoming_size) > MAX_SEGMENT_BYTES
            }
            None => true,
        };

        if needs_new_segment {
            let required_bytes = segment_rotation_required_bytes(incoming_size);
            if let Some(available) = available_disk_bytes(&self.data_dir)
                && available < required_bytes
            {
                return Err(format!(
                    "{DISK_FULL_MARKER}: insufficient free space for segment rotation: \
                    {available} bytes available, {required_bytes} required"
                ));
            }
            // Group commit no longer fsyncs each write, so the outgoing active
            // segment may hold un-synced appends; make them durable before it
            // stops being the fsync target.
            if let Some(active) = snapshot.state.active() {
                let path = self.segment_path(&active.segment_id);
                if self.io.path_exists(&path).await? {
                    let file = self.io.open_append_file(&path).await?;
                    self.segment_fsync_count.fetch_add(1, Ordering::Relaxed);
                    file.sync_data().await.map_err(|error| {
                        format!(
                            "failed to sync rotating segment {}: {error}",
                            path.display()
                        )
                    })?;
                }
            }
            let outgoing_segment_id = snapshot
                .state
                .active()
                .map(|active| active.segment_id.clone());
            let segment = SegmentReference::new(Uuid::now_v7().to_string(), now_ms());
            // The rotate decision above used a snapshot taken before the
            // state lock; that stays valid because evictions, the only other
            // mutator, never remove the active segment.
            let evicted_segments = self
                .mutate_segment_state(|state| {
                    state.push_new(
                        segment.clone(),
                        self.segment_ring_limits.desired_old_segments,
                        self.segment_ring_limits.desired_current_segments,
                        self.segment_ring_limits.desired_new_segments,
                    )
                })
                .await?;
            // Seal stat: drain the outgoing segment's running max only after
            // the snapshot above was replaced (the new segment is active), so
            // a manifest commit racing this rotation either landed in the map
            // before the drain or observes "not active" in
            // `note_segment_version` and raises the sealed reference itself.
            if let Some(outgoing_segment_id) = outgoing_segment_id {
                let sealed_max = self
                    .active_segment_max_versions
                    .lock()
                    .expect("active segment max versions lock poisoned")
                    .remove(&outgoing_segment_id);
                if let Some(sealed_max) = sealed_max {
                    self.mutate_segment_state(|state| {
                        state.raise_max_version_ms(&outgoing_segment_id, sealed_max)
                    })
                    .await?;
                }
            }
            Ok((segment, evicted_segments))
        } else {
            Ok((
                snapshot
                    .state
                    .active()
                    .cloned()
                    .expect("current segment should exist when not rotating"),
                Vec::new(),
            ))
        }
    }

    fn is_active_segment(&self, segment_id: &str) -> bool {
        self.segment_state_snapshot()
            .state
            .active()
            .is_some_and(|active| active.segment_id == segment_id)
    }

    /// Records a committed manifest's effective `version_ms` against the
    /// segment holding its bytes, feeding the seal-time `max_version_ms`
    /// stat. The bytes append and the metadata commit sit on opposite sides
    /// of the segment write lock, so a commit can land after its segment
    /// already sealed; such a commit raises the sealed reference in place
    /// (max-only, so replays and promotion-driven old entries never lower
    /// the stat).
    async fn note_segment_version(&self, segment_id: &str, version_ms: u64) -> Result<(), String> {
        {
            let mut maxes = self
                .active_segment_max_versions
                .lock()
                .expect("active segment max versions lock poisoned");
            if self.is_active_segment(segment_id) {
                let entry = maxes.entry(segment_id.to_owned()).or_default();
                *entry = (*entry).max(version_ms);
                // Re-check after inserting: the seal drains the map after
                // replacing the snapshot, so if the segment is still active
                // here the drain has not run yet and will pick this entry up.
                if self.is_active_segment(segment_id) {
                    return Ok(());
                }
                // Sealed while inserting — the drain may have missed the
                // entry; fall through to the in-place raise (idempotent).
                maxes.remove(segment_id);
            }
        }
        self.mutate_segment_state(|state| state.raise_max_version_ms(segment_id, version_ms))
            .await
    }

    /// Restores the active segment's running max `version_ms` at boot. The
    /// running max is in-memory only, so without this a restart mid-segment
    /// would seal the segment under-reported. Bounded by one segment's
    /// `segment_artifacts` rows and runs once at startup.
    fn rederive_active_segment_max_version(&self) -> Result<(), String> {
        let snapshot = self.segment_state_snapshot();
        let Some(active) = snapshot.state.active() else {
            return Ok(());
        };
        let prefix = segment_artifact_index_prefix(&active.segment_id);
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS),
            IteratorMode::From(prefix.as_bytes(), rocksdb::Direction::Forward),
        );
        let mut max_version_ms: Option<u64> = None;
        for item in iter {
            let (index_key, _) =
                item.map_err(|error| format!("failed to iterate segment index: {error}"))?;
            if !index_key.starts_with(prefix.as_bytes()) {
                break;
            }
            let artifact_id = std::str::from_utf8(&index_key[prefix.len()..])
                .map_err(|error| format!("invalid segment index key: {error}"))?;
            if let Some(manifest) = self.manifest_from_db(artifact_id)?
                && manifest.segment_id.as_deref() == Some(active.segment_id.as_str())
            {
                let version_ms = manifest_version_ms(&manifest);
                max_version_ms = Some(max_version_ms.map_or(version_ms, |max| max.max(version_ms)));
            }
        }
        if let Some(max_version_ms) = max_version_ms {
            self.active_segment_max_versions
                .lock()
                .expect("active segment max versions lock poisoned")
                .insert(active.segment_id.clone(), max_version_ms);
        }
        Ok(())
    }

    /// Reads the segment ring state from the metadata store. Only seeds the
    /// in-memory snapshot at startup; runtime readers go through
    /// [`Self::segment_state_snapshot`], which stays current because every
    /// mutation funnels through [`Self::save_segment_state`].
    fn load_segment_state_from_db(&self) -> Result<SegmentState, String> {
        let key = b"shared";
        let Some(bytes) = self
            .db
            .get_cf(self.cf(ROCKSDB_CF_SEGMENT_STATE), key)
            .map_err(|error| format!("failed to read segment state: {error}"))?
        else {
            return Ok(SegmentState::default());
        };

        serde_json::from_slice::<SegmentState>(&bytes)
            .map_err(|error| format!("failed to decode segment state: {error}"))
    }

    fn segment_state_snapshot(&self) -> Arc<SegmentStateSnapshot> {
        self.segment_state_cache
            .lock()
            .expect("segment state cache lock poisoned")
            .clone()
    }

    fn replace_segment_state_snapshot(&self, state: SegmentState) {
        let snapshot = Arc::new(SegmentStateSnapshot::new(state));
        *self
            .segment_state_cache
            .lock()
            .expect("segment state cache lock poisoned") = snapshot;
    }

    /// Applies a mutation to the segment ring state and persists the result.
    /// Every read-modify-write of the state must go through here: the
    /// [`Self::segment_state_lock`] serializes mutators (rotation and
    /// eviction) so none of them can overwrite another's update with a stale
    /// copy. The mutation runs on a fresh copy of the latest state, and
    /// nothing is persisted when the state is left unchanged.
    async fn mutate_segment_state<T>(
        &self,
        mutate: impl FnOnce(&mut SegmentState) -> T,
    ) -> Result<T, String> {
        let _guard = self.segment_state_lock.lock().await;
        let snapshot = self.segment_state_snapshot();
        let mut state = snapshot.state.clone();
        let result = mutate(&mut state);
        if state != snapshot.state {
            self.save_segment_state(&state)?;
        }
        Ok(result)
    }

    /// Persists `state` to RocksDB and then atomically replaces the in-memory
    /// snapshot. Every segment-ring mutation must funnel through here; a direct
    /// `put_cf` to `ROCKSDB_CF_SEGMENT_STATE` that bypasses this function would
    /// leave [`Self::segment_state_snapshot`] stale until the next restart.
    fn save_segment_state(&self, state: &SegmentState) -> Result<(), String> {
        let bytes = serde_json::to_vec(state)
            .map_err(|error| format!("failed to encode segment state: {error}"))?;
        self.db
            .put_cf(self.cf(ROCKSDB_CF_SEGMENT_STATE), b"shared", bytes)
            .map_err(|error| format!("failed to persist segment state: {error}"))?;
        self.replace_segment_state_snapshot(state.clone());
        Ok(())
    }

    fn segment_generation(&self, segment_id: &str) -> Result<Option<SegmentGeneration>, String> {
        Ok(self
            .segment_state_snapshot()
            .generations
            .get(segment_id)
            .copied())
    }

    async fn evict_segments(&self, evicted_segments: Vec<SegmentReference>) -> Result<(), String> {
        for segment in evicted_segments {
            let bytes = try_path_size_bytes(&self.segment_path(&segment.segment_id)).unwrap_or(0);
            let artifact_count = self.evict_segment(&segment.segment_id).await?;
            self.record_capacity_eviction(&segment, artifact_count, bytes);
        }
        Ok(())
    }

    fn record_capacity_eviction(
        &self,
        segment: &SegmentReference,
        artifact_count: u64,
        bytes: u64,
    ) {
        let evicted_at_ms = now_ms();
        let newest_content_at_ms = segment.effective_max_version_ms();
        self.io.metrics().record_segment_shed_age(
            evicted_at_ms.saturating_sub(newest_content_at_ms) as f64 / 1_000.0,
        );

        let mut pending = self
            .pending_capacity_evictions
            .lock()
            .expect("pending capacity evictions poisoned");
        while pending.len() >= MAX_PENDING_CAPACITY_EVICTIONS {
            pending.pop_front();
            self.io.metrics().record_capacity_eviction_report_dropped();
        }
        pending.push_back(CapacityEviction {
            segment_id: segment.segment_id.clone(),
            segment_created_at_ms: segment.created_at_ms,
            newest_content_at_ms,
            evicted_at_ms,
            artifact_count,
            bytes,
        });
    }

    pub fn take_pending_capacity_evictions(&self) -> Vec<CapacityEviction> {
        let mut pending = self
            .pending_capacity_evictions
            .lock()
            .expect("pending capacity evictions poisoned");
        pending.drain(..).collect()
    }

    /// Ring occupancy against the resolved budget. The per-segment stat walks
    /// the live segment files; a file that disappears mid-walk (a concurrent
    /// rotation) counts as zero, which the next snapshot corrects.
    pub fn storage_snapshot(&self) -> StorageSnapshotData {
        let snapshot = self.segment_state_snapshot();
        let references: Vec<&SegmentReference> = snapshot
            .state
            .old
            .iter()
            .chain(snapshot.state.current.iter())
            .chain(snapshot.state.new.iter())
            .collect();

        let live_segment_bytes = references
            .iter()
            .map(|reference| {
                try_path_size_bytes(&self.segment_path(&reference.segment_id)).unwrap_or(0)
            })
            .sum();

        StorageSnapshotData {
            ring_budget_bytes: self.segment_ring_limits.capacity_bytes(),
            desired_segment_count: self.segment_ring_limits.total_segments() as u64,
            live_segment_count: references.len() as u64,
            live_segment_bytes,
            oldest_segment_created_at_ms: references
                .iter()
                .map(|reference| reference.created_at_ms)
                .min(),
            newest_content_at_ms: references
                .iter()
                .map(|reference| reference.effective_max_version_ms())
                .max(),
        }
    }

    async fn evict_segment(&self, segment_id: &str) -> Result<u64, String> {
        let prefix = segment_artifact_index_prefix(segment_id);
        let mut batch = WriteBatch::default();
        let mut saw_entries = false;
        let mut removed_artifacts = BTreeMap::<ArtifactProducer, u64>::new();
        let mut removed_artifact_ids = Vec::new();
        // The cascade is engaged whenever the operator has it enabled. It acts on
        // whatever reverse rows exist, so coverage grows as entries are written;
        // the serve-side presence gates remain the safety net for the rest.
        let cascade_active = self.action_cache_cascade_active();
        let mut cascade = CascadeProgress::default();
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS),
            IteratorMode::From(prefix.as_bytes(), rocksdb::Direction::Forward),
        );

        let mut scanned_rows = 0;
        for item in iter {
            let (index_key, _) =
                item.map_err(|error| format!("failed to iterate segment index: {error}"))?;
            if !index_key.starts_with(prefix.as_bytes()) {
                break;
            }
            // Everything below is synchronous RocksDB work, so without this the
            // whole segment's scan runs in one poll and parks a runtime worker.
            yield_scanned_row(&mut scanned_rows).await;
            // A crash between chunks is safe: the segment stays in the ring
            // state, and its file on disk, until this whole loop is done, so a
            // restart re-runs the eviction and the `Some(_) | None` arm below
            // absorbs whatever the previous attempt already removed.
            if batch.size_in_bytes() >= self.eviction_batch_budget_bytes {
                self.commit_eviction_chunk(
                    std::mem::take(&mut batch),
                    &mut removed_artifact_ids,
                    &mut cascade,
                )
                .await?;
            }
            saw_entries = true;
            let artifact_id = std::str::from_utf8(&index_key[prefix.len()..])
                .map_err(|error| format!("invalid segment index key: {error}"))?
                .to_owned();

            match self.manifest_from_db(&artifact_id)? {
                Some(manifest) if manifest.segment_id.as_deref() == Some(segment_id) => {
                    // Cascade first, and let it commit chunks of its own: this
                    // blob is going away, so every action-cache entry that
                    // references it must go too, and per-blob fanout is
                    // unbounded (a common output blob is referenced by very
                    // many action results). Staging a whole cascade before
                    // checking the budget is what let one blob carry the batch
                    // far past it.
                    //
                    // Splitting here is legal because #12152's invariant is
                    // one-directional: it forbids an *entry* outliving its
                    // blob, not a blob outliving its entries. Entries committed
                    // ahead of the blob leave, at worst, a blob with no
                    // referrers — which this eviction removes moments later,
                    // and which a crash in between leaves for the re-run.
                    if cascade_active && manifest.producer == ArtifactProducer::Reapi {
                        self.stage_action_cache_cascade_for_blob(
                            &mut batch,
                            &artifact_id,
                            &mut cascade,
                            &mut removed_artifact_ids,
                            &mut scanned_rows,
                        )
                        .await?;
                    }
                    // The blob's own rows go last, so they can only land in a
                    // chunk committed after every entry referencing it is gone.
                    batch.delete_cf(self.cf(ROCKSDB_CF_MANIFESTS), artifact_id.as_bytes());
                    batch.delete_cf(
                        self.cf(ROCKSDB_CF_NAMESPACE_ARTIFACTS),
                        namespace_artifact_index_key(&manifest.namespace_id, &artifact_id)
                            .as_bytes(),
                    );
                    batch.delete_cf(self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS), &index_key);
                    self.stage_backfill_index_delete(&mut batch, &manifest);
                    *removed_artifacts.entry(manifest.producer).or_default() += 1;
                    removed_artifact_ids.push(artifact_id);
                }
                Some(_) | None => {
                    batch.delete_cf(self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS), &index_key);
                }
            }
        }

        if saw_entries {
            self.commit_eviction_chunk(batch, &mut removed_artifact_ids, &mut cascade)
                .await?;
            if cascade.total > 0 {
                self.io
                    .metrics()
                    .record_action_cache_cascade(cascade.total as u64);
                tracing::info!(
                    segment_id,
                    cascaded_entries = cascade.total,
                    "cascaded action-cache entries stranded by segment eviction"
                );
            }
        }
        self.remove_segment_handle(segment_id).await;
        self.io
            .remove_file_if_exists(&self.segment_path(segment_id))
            .await;
        self.mutate_segment_state(|state| state.remove_segment(segment_id))
            .await?;
        let mut total_artifacts = 0;
        for (producer, artifacts) in removed_artifacts {
            total_artifacts += artifacts;
            self.io
                .metrics()
                .record_segment_eviction(producer, "ok", artifacts);
        }

        Ok(total_artifacts)
    }

    /// Commits one chunk of a segment eviction and then invalidates exactly the
    /// caches that chunk just made unreachable.
    ///
    /// The write runs on the blocking pool rather than inline. The metadata
    /// store is built with `allow_stall = true`, so a saturated write-buffer
    /// pool blocks the calling thread inside RocksDB until a flush drains it —
    /// which is the point of the flag, but on a tokio worker it parks the
    /// runtime rather than one task. That is how a pod stops answering `/up`
    /// and `/metrics` while still running: both read process-local state and
    /// take no lock, so only scheduling starvation can stop them. Off the
    /// worker threads, a stall costs a blocking-pool thread and the runtime
    /// keeps scheduling — probes answer, the metrics snapshot task keeps
    /// publishing, and inbound request bodies keep draining. See #12556.
    ///
    /// `WriteBatch` is not `Send` (it is a raw `rocksdb_writebatch_t` pointer),
    /// so the batch crosses the thread boundary as its own serialized
    /// representation, which is the same encoding RocksDB puts in the WAL and
    /// preserves column-family targeting. That costs one copy, bounded by
    /// `SEGMENT_EVICTION_MAX_BATCH_BYTES`.
    async fn commit_eviction_chunk(
        &self,
        batch: WriteBatch,
        removed_artifact_ids: &mut Vec<String>,
        cascade: &mut CascadeProgress,
    ) -> Result<(), String> {
        // An empty batch still carries a 12-byte header, so `size_in_bytes()`
        // is never zero and a small budget can trip the check before anything
        // is staged. Skip the write rather than spend a WAL append on nothing;
        // the invalidations below are no-ops when nothing is pending.
        if batch.is_empty() {
            return Ok(());
        }

        let payload = batch.data().to_vec();
        // Invalidate before the commit as well as after. `spawn_blocking` work
        // is never cancelled, but the future awaiting it can be dropped — and
        // eviction runs on the request path, under an axum handler whose client
        // may disconnect. The write would still land while the post-commit
        // invalidation never ran, leaving the manifest cache serving rows the
        // store no longer has and snapshots advertising cascaded entries: the
        // `CAS error: missing object` class again. Clearing early is safe in
        // the other direction, because a miss just re-reads a row that is still
        // there, and it costs only a re-read if the commit then fails.
        self.invalidate_committed_eviction(removed_artifact_ids, cascade);
        let db = Arc::clone(&self.db);
        #[cfg(test)]
        let commits = Arc::clone(&self.eviction_commits);
        #[cfg(test)]
        let chunk_bytes = payload.len();
        tokio::task::spawn_blocking(move || {
            #[cfg(test)]
            {
                let mut commits = commits
                    .lock()
                    .expect("eviction commit log lock should not be poisoned");
                commits.threads.push(std::thread::current().id());
                commits.chunk_bytes.push(chunk_bytes);
            }
            db.write(WriteBatch::from_data(&payload))
        })
        .await
        .map_err(|error| format!("segment eviction commit task failed: {error}"))?
        .map_err(|error| format!("failed to evict segment metadata: {error}"))?;

        // Again after the commit, which is what closes the window where a
        // concurrent read repopulated the cache from rows that were still
        // present a moment ago. This is the pass that clears the pending state.
        self.invalidate_committed_eviction(removed_artifact_ids, cascade);
        removed_artifact_ids.clear();
        cascade.pending_entries.clear();
        cascade.pending_namespaces.clear();
        // Dedup is per-chunk; see `CascadeProgress`.
        cascade.seen.clear();
        Ok(())
    }

    /// Drops the manifest-cache keys one eviction chunk makes unreachable and
    /// bumps the action-cache generation of every namespace it touched, so a
    /// cached snapshot rebuilds against the pruned index. Idempotent, because
    /// `commit_eviction_chunk` runs it on both sides of the commit.
    fn invalidate_committed_eviction(
        &self,
        removed_artifact_ids: &[String],
        cascade: &CascadeProgress,
    ) {
        self.remove_manifest_cache_keys(removed_artifact_ids);
        self.remove_manifest_cache_keys(&cascade.pending_entries);
        for namespace_id in &cascade.pending_namespaces {
            self.bump_action_cache_generation(namespace_id);
        }
    }

    /// Cascade-delete the action-cache entries that reference `blob_artifact_id`
    /// into `batch`, staging the removal of each entry's manifest, inline bytes,
    /// namespace/action-cache index rows, and reverse rows, plus the blob's own
    /// reverse rows. `cascaded_entries` de-duplicates entries referenced by more
    /// than one evicted blob in the same segment; `cascaded_namespaces` collects
    /// the namespaces whose snapshot generation must be bumped after commit.
    ///
    /// Each candidate is re-validated against the entry's current `ActionResult`
    /// before removal: a reverse pair left stale by a re-publish that moved the
    /// entry onto a different blob, or by an already-deleted entry, only deletes
    /// itself and never takes out a live, unrelated entry.
    ///
    /// The validation is deliberately not serialized with `artifact_write_lock_for`
    /// against a concurrent re-publish of the same key. Eviction runs from
    /// segment rotation *inside* `persist_artifact_from_path_with_version` while
    /// that path already holds an `artifact_write_lock` stripe, and the striped
    /// locks can hash-collide a blob id with an entry id, so taking the entry
    /// lock here could self-deadlock. The residual race (a re-publish commits a
    /// new version between this read and the batch commit, so the fresh entry is
    /// removed on a stale validation) is bounded and self-healing: the entry
    /// degrades to a `NOT_FOUND` the client recomputes and republishes, the
    /// snapshot reconcile skips any index row whose manifest is gone, and the
    /// orphaned reverse row is reclaimed when its blob is later evicted. This is
    /// the same read-then-delete-without-writer-lock race that
    /// `expire_stale_action_cache_entries` already accepts.
    async fn stage_action_cache_cascade_for_blob(
        &self,
        batch: &mut WriteBatch,
        blob_artifact_id: &str,
        cascade: &mut CascadeProgress,
        removed_artifact_ids: &mut Vec<String>,
        scanned_rows: &mut usize,
    ) -> Result<(), String> {
        let prefix = action_cache_blob_ref_prefix(blob_artifact_id);
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            IteratorMode::From(prefix.as_bytes(), rocksdb::Direction::Forward),
        );
        for item in iter {
            let (ref_key, _) =
                item.map_err(|error| format!("failed to iterate blob refs: {error}"))?;
            if !ref_key.starts_with(prefix.as_bytes()) {
                break;
            }
            yield_scanned_row(scanned_rows).await;
            let entry_id = std::str::from_utf8(&ref_key[prefix.len()..])
                .map_err(|error| format!("invalid blob-ref key: {error}"))?
                .to_owned();
            // The blob is going away, so its reverse row goes regardless of what
            // we decide about the entry below.
            batch.delete_cf(self.cf(ROCKSDB_CF_KEY_VALUE), &ref_key);

            if cascade.contains(&entry_id) {
                continue;
            }
            let Some(entry_manifest) = self.manifest_from_db(&entry_id)? else {
                // Entry already removed; the reverse row was stale.
                continue;
            };
            if entry_manifest.producer != ArtifactProducer::Reapi
                || action_cache_manifest_hash(&entry_manifest.key).is_none()
            {
                continue;
            }
            let Some(entry_bytes) = self.inline_bytes(&entry_id)? else {
                continue;
            };
            let still_references = self
                .action_cache_entry_blob_ids(&entry_manifest.namespace_id, &entry_bytes)
                .iter()
                .any(|id| id == blob_artifact_id);
            if !still_references {
                // Stale pair from a re-publish that moved the entry off this
                // blob; deleting the pair above is enough, leave the live entry.
                continue;
            }
            self.stage_action_cache_entry_delete(batch, &entry_manifest, &entry_bytes);
            cascade.record(&entry_manifest.namespace_id, entry_id);
            // Bound the batch inside the cascade, not just between blobs. The
            // caller stages this blob's own rows only after this returns, so
            // committing here can never publish a blob deletion ahead of an
            // entry that references it.
            if batch.size_in_bytes() >= self.eviction_batch_budget_bytes {
                self.commit_eviction_chunk(std::mem::take(batch), removed_artifact_ids, cascade)
                    .await?;
            }
        }
        Ok(())
    }

    /// Stage the full removal of a single action-cache entry into `batch`: its
    /// manifest, inline bytes, namespace index, action-cache index, and reverse
    /// rows. Entries are always inline, so there is no segment-index row.
    fn stage_action_cache_entry_delete(
        &self,
        batch: &mut WriteBatch,
        entry_manifest: &ArtifactManifest,
        entry_bytes: &[u8],
    ) {
        let entry_id = &entry_manifest.artifact_id;
        batch.delete_cf(self.cf(ROCKSDB_CF_MANIFESTS), entry_id.as_bytes());
        batch.delete_cf(self.cf(ROCKSDB_CF_KEY_VALUE), entry_id.as_bytes());
        batch.delete_cf(
            self.cf(ROCKSDB_CF_NAMESPACE_ARTIFACTS),
            namespace_artifact_index_key(&entry_manifest.namespace_id, entry_id).as_bytes(),
        );
        if let Some(action_hash) = action_cache_manifest_hash(&entry_manifest.key) {
            batch.delete_cf(
                self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
                action_cache_index_key(
                    &entry_manifest.namespace_id,
                    entry_manifest.version_ms,
                    action_hash,
                    entry_manifest.branch.as_deref(),
                ),
            );
        }
        self.stage_action_cache_blob_refs_delete(
            batch,
            &entry_manifest.namespace_id,
            entry_id,
            entry_bytes,
        );
        self.stage_backfill_index_delete(batch, entry_manifest);
    }

    /// Removes segment files that the segment ring state no longer
    /// references, along with any metadata still pointing at them.
    ///
    /// Rotation persists the ring state without the evicted segment before
    /// the file is unlinked, so a crash (or an error) in that window strands
    /// the file — and the manifests of the artifacts inside it — with no code
    /// path left to reclaim them. Must run at startup, under the data-dir
    /// writer lock and before any traffic, so it cannot race a rotation
    /// creating a segment whose state entry is not yet visible.
    pub async fn sweep_orphaned_segments(&self) -> Result<usize, String> {
        let segments_dir = self.data_dir.join("segments");
        let mut entries = match tokio::fs::read_dir(&segments_dir).await {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(0),
            Err(error) => {
                return Err(format!(
                    "failed to list segments directory {}: {error}",
                    segments_dir.display()
                ));
            }
        };

        let snapshot = self.segment_state_snapshot();
        let mut swept = 0;
        loop {
            let entry = entries.next_entry().await.map_err(|error| {
                format!(
                    "failed to read segments directory {}: {error}",
                    segments_dir.display()
                )
            })?;
            let Some(entry) = entry else {
                break;
            };
            let file_name = entry.file_name();
            let Some(segment_id) = file_name
                .to_str()
                .and_then(|name| name.strip_suffix(".seg"))
            else {
                continue;
            };
            if snapshot.generations.contains_key(segment_id) {
                continue;
            }
            tracing::warn!(segment_id, "removing orphaned segment");
            self.evict_segment(segment_id).await?;
            swept += 1;
        }

        Ok(swept)
    }

    fn segment_path(&self, segment_id: &str) -> PathBuf {
        segment_path(&self.data_dir, segment_id)
    }

    async fn segment_handle(&self, segment_id: &str) -> Result<Arc<PersistentFile>, String> {
        let path = self.segment_path(segment_id);
        self.persistent_file_handle(segment_handle_cache_key(segment_id), &path, "segment")
            .await
    }

    async fn blob_handle(&self, blob_path: &str) -> Result<Arc<PersistentFile>, String> {
        self.persistent_file_handle(
            blob_handle_cache_key(blob_path),
            Path::new(blob_path),
            "blob",
        )
        .await
    }

    async fn persistent_file_handle(
        &self,
        cache_key: String,
        path: &Path,
        storage_kind: &'static str,
    ) -> Result<Arc<PersistentFile>, String> {
        if let Some(handle) = self.segment_handle_cache_get(&cache_key).await {
            self.io.metrics().record_segment_handle_cache_lookup("hit");
            return Ok(handle);
        }
        self.io.metrics().record_segment_handle_cache_lookup("miss");

        let handle = Arc::new(
            self.io
                .open_persistent_read_file(path)
                .await
                .map_err(|error| {
                    format!(
                        "failed to open {storage_kind} persistent file {}: {error}",
                        path.display()
                    )
                })?,
        );
        let mut cache = self.segment_handles.lock().await;
        if let Some(existing) = cache.touch(&cache_key) {
            return Ok(existing);
        }
        let evicted = cache.insert(cache_key, handle.clone());
        let cached = cache.len();
        drop(cache);
        self.io.metrics().update_segment_handles_cached(cached);
        self.io
            .metrics()
            .record_segment_handle_evictions("capacity", evicted as u64);
        Ok(handle)
    }

    async fn remove_segment_handle(&self, segment_id: &str) {
        self.remove_cached_file_handle(&segment_handle_cache_key(segment_id), "segment_eviction")
            .await;
    }

    async fn remove_blob_handle(&self, blob_path: &str) {
        self.remove_cached_file_handle(&blob_handle_cache_key(blob_path), "blob_delete")
            .await;
    }

    async fn remove_cached_file_handle(&self, cache_key: &str, reason: &str) {
        let mut cache = self.segment_handles.lock().await;
        let removed = cache.remove(cache_key);
        let cached = cache.len();
        drop(cache);
        self.io.metrics().update_segment_handles_cached(cached);
        if removed {
            self.io.metrics().record_segment_handle_evictions(reason, 1);
        }
    }

    async fn segment_handle_cache_get(&self, cache_key: &str) -> Option<Arc<PersistentFile>> {
        let mut cache = self.segment_handles.lock().await;
        cache.touch(cache_key)
    }

    pub async fn trim_segment_handle_cache_to(&self, target_entries: usize, reason: &str) -> usize {
        let mut cache = self.segment_handles.lock().await;
        let evicted = cache.trim_to(target_entries);
        let cached = cache.len();
        drop(cache);
        self.io.metrics().update_segment_handles_cached(cached);
        if evicted > 0 {
            self.io
                .metrics()
                .record_segment_handle_evictions(reason, evicted as u64);
        }
        evicted
    }

    #[cfg(test)]
    pub async fn persist_artifact_from_bytes(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        bytes: &[u8],
    ) -> Result<ArtifactManifest, String> {
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms: now_ms(),
            replication_targets: &[],
            branch: None,
            trunk: None,
        };
        let (outcome, already_present) = self
            .persist_artifact_from_bytes_with_version(spec, bytes)
            .await?;
        outcome
            .into_persisted(already_present, producer, namespace_id, key)
            .map(|persisted| persisted.manifest)
    }

    pub async fn persist_artifact_from_bytes_and_enqueue(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        bytes: &[u8],
        replication_targets: &[String],
    ) -> Result<PersistedArtifact, String> {
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms: now_ms(),
            replication_targets,
            branch: None,
            trunk: None,
        };
        let (outcome, already_present) = self
            .persist_artifact_from_bytes_with_version(spec, bytes)
            .await?;
        outcome.into_persisted(already_present, producer, namespace_id, key)
    }

    #[cfg(test)]
    pub async fn persist_inline_artifact_from_bytes(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        bytes: &[u8],
    ) -> Result<ArtifactManifest, String> {
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms: now_ms(),
            replication_targets: &[],
            branch: None,
            trunk: None,
        };
        match self
            .persist_inline_artifact_with_version(spec, bytes)
            .await?
        {
            PersistArtifactOutcome::Applied(manifest)
            | PersistArtifactOutcome::IgnoredEqual(manifest)
            | PersistArtifactOutcome::IgnoredStale(manifest) => Ok(manifest),
            PersistArtifactOutcome::IgnoredTombstone => Err(format!(
                "artifact write for {producer:?}/{namespace_id}/{key} was rejected by a newer tombstone"
            )),
        }
    }

    /// Persist an inline artifact, treating a byte-identical re-publish of an
    /// entry whose stored version is younger than the refresh damping window
    /// as already applied (returns the existing manifest, writes and
    /// replicates nothing). Clients refresh action-cache entries back into
    /// the snapshot's ranked wire view by re-publishing their unchanged
    /// manifests; without damping, every cold machine in a fleet would bump
    /// the same entries' versions (and replicate the rewrites) on the same
    /// day.
    #[allow(clippy::too_many_arguments)]
    pub async fn persist_inline_artifact_from_bytes_damped_and_enqueue(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        bytes: &[u8],
        replication_targets: &[String],
        branch: Option<&str>,
        trunk: Option<&str>,
    ) -> Result<(ArtifactManifest, bool), String> {
        let artifact_id = artifact_storage_id(producer, &self.tenant_id, namespace_id, key);
        let existing = self.manifest_from_db(&artifact_id)?;
        // Damping compares the TAG as well as the bytes, because an entry is no
        // longer identified by its bytes alone. Without it, a trunk build that
        // recomputes a result a feature branch published first is damped on the
        // bytes and its tag never lands, so the entry stays feature-scoped and
        // stays out of the trunk view: the reclaim the client is asking for is
        // dropped here, silently, by the one check it has to pass.
        //
        // This was tried once and reverted, for reasons that no longer hold. The
        // refresh path then re-published with no branch, so comparing tags saw
        // `Some("feature")` against `None`, declined to damp, and wrote the entry
        // untagged into what was then the trunk baseline. That path now carries
        // its tags, `sticky_branch` no longer lets an absent branch overwrite a
        // present one, and untagged is no longer the baseline. Three reasons the
        // old shape was a trap, all gone.
        //
        // Resolving the tag here is a probe, not the decision: the persist below
        // re-resolves it under the per-artifact write lock. A peer committing in
        // between can only cost a damp we should have taken, or a write we did
        // not need, and the next publish settles it either way.
        if let Some(existing) = &existing
            && existing.inline
            && manifest_version_ms(existing).saturating_add(REAPI_ACTION_CACHE_REFRESH_DAMPING_MS)
                > now_ms()
            && sticky_branch(Some(existing), branch, trunk) == existing.branch.as_deref()
            && self.inline_bytes(&artifact_id)?.as_deref() == Some(bytes)
        {
            return Ok((existing.clone(), false));
        }
        // The tag is resolved by the persist below, under the per-artifact write
        // lock. Deciding it from `existing` here would race: this read is only
        // the damping probe, and a peer can commit between it and the write.
        self.persist_inline_artifact_from_bytes_and_enqueue(
            producer,
            namespace_id,
            key,
            content_type,
            bytes,
            replication_targets,
            branch,
            trunk,
        )
        .await
        .map(|manifest| (manifest, true))
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn persist_inline_artifact_from_bytes_and_enqueue(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        bytes: &[u8],
        replication_targets: &[String],
        branch: Option<&str>,
        trunk: Option<&str>,
    ) -> Result<ArtifactManifest, String> {
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms: now_ms(),
            replication_targets,
            branch,
            trunk,
        };
        match self
            .persist_inline_artifact_with_version(spec, bytes)
            .await?
        {
            PersistArtifactOutcome::Applied(manifest)
            | PersistArtifactOutcome::IgnoredEqual(manifest)
            | PersistArtifactOutcome::IgnoredStale(manifest) => Ok(manifest),
            PersistArtifactOutcome::IgnoredTombstone => Err(format!(
                "artifact write for {producer:?}/{namespace_id}/{key} was rejected by a newer tombstone"
            )),
        }
    }

    #[cfg(test)]
    pub async fn apply_replicated_artifact_from_bytes(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        bytes: &[u8],
        version_ms: u64,
    ) -> Result<ArtifactApplyOutcome, String> {
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms,
            replication_targets: &[],
            branch: None,
            trunk: None,
        };
        Ok(self
            .persist_artifact_from_bytes_with_version(spec, bytes)
            .await?
            .0
            .apply_outcome())
    }

    /// Apply an inline artifact replicated from a peer. `branch` is the tag the
    /// origin resolved and `trunk` the publishing build's trunk; a peer that
    /// sends neither (an older node, or any non-REAPI write) applies untagged,
    /// exactly as before.
    #[allow(clippy::too_many_arguments)]
    pub async fn apply_replicated_inline_artifact_from_bytes(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        bytes: &[u8],
        version_ms: u64,
        branch: Option<&str>,
        trunk: Option<&str>,
    ) -> Result<ArtifactApplyOutcome, String> {
        // The trunk-sticky rule is re-run against THIS node's view by the persist
        // below (under the per-artifact write lock, from its own read). The origin
        // could only apply the rule against its own view: a feature build
        // publishing a trunk key to a peer that does not hold it yet resolves the
        // tag to `feature`, and applying that verbatim would steal the key out of
        // the trunk baseline here: the same theft the rule prevents locally, just
        // arriving over replication. Forwarding `trunk` is what asks for the
        // re-run; a peer that sends none applies untagged, exactly as before.
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms,
            replication_targets: &[],
            branch,
            trunk,
        };
        Ok(self
            .persist_inline_artifact_with_version(spec, bytes)
            .await?
            .apply_outcome())
    }

    /// Phase 1 of the deferred backfill batch protocol for an inline record
    /// (see [`BackfillApplyBatch`]): runs the advisory LWW/tombstone
    /// pre-check under the per-artifact write lock and, when the record still
    /// applies, stages its bytes in memory for the phase-3 group commit —
    /// nothing touches the DB here. The lock is released until the group
    /// commit re-takes it, so the pre-check is advisory and the phase-3
    /// re-check is authoritative. A record the pre-check ignores (local copy
    /// newer or equal, or tombstoned) is already converged and stages
    /// nothing.
    #[allow(clippy::too_many_arguments)]
    pub(crate) async fn stage_backfill_inline_apply(
        &self,
        batch: &mut BackfillApplyBatch,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        bytes: &[u8],
        version_ms: u64,
        branch: Option<&str>,
    ) -> Result<BackfillStageOutcome, String> {
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms,
            replication_targets: &[],
            branch,
            trunk: None,
        };
        let artifact_id = artifact_storage_id(producer, &self.tenant_id, namespace_id, key);
        {
            let _write_guard = self.artifact_write_lock_for(&artifact_id).lock().await;
            if let InlineApplyPrecheck::Ignored { .. } =
                self.inline_apply_precheck(&artifact_id, &spec).await?
            {
                return Ok(BackfillStageOutcome::Converged);
            }
        }
        batch
            .staged
            .push(StagedBackfillApply::Inline(StagedBackfillInlineApply {
                producer,
                namespace_id: namespace_id.to_owned(),
                key: key.to_owned(),
                content_type: content_type.to_owned(),
                version_ms,
                branch: branch.map(str::to_owned),
                artifact_id,
                bytes: bytes.to_vec(),
            }));
        Ok(BackfillStageOutcome::Staged)
    }

    /// Phase 1 of the deferred backfill batch protocol for a segmented
    /// record (see [`BackfillApplyBatch`]): appends a Present segmented body
    /// to the active segment without a per-record fsync and stages its
    /// manifest inputs for the phase-3 group commit. The LWW/tombstone
    /// pre-check and the append run under the per-artifact write lock — the
    /// same duplicate-copy protection as the live path — but the lock is
    /// released until the group commit re-takes it, so this check is
    /// advisory and the phase-3 re-check is authoritative. A record the
    /// pre-check ignores (local copy newer or equal, or tombstoned) is
    /// already converged and stages nothing.
    #[allow(clippy::too_many_arguments)]
    pub(crate) async fn stage_backfill_segmented_apply(
        &self,
        batch: &mut BackfillApplyBatch,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        staged: StagedArtifactPath<'_>,
        version_ms: u64,
    ) -> Result<BackfillStageOutcome, String> {
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms,
            replication_targets: &[],
            branch: None,
            trunk: None,
        };
        let artifact_id = artifact_storage_id(producer, &self.tenant_id, namespace_id, key);
        let size = self.io.metadata_len(staged.path).await?;
        let (location, evicted_segments, durability_seq) = {
            let _write_guard = self.artifact_write_lock_for(&artifact_id).lock().await;
            match self.segment_apply_precheck(&artifact_id, &spec).await? {
                SegmentApplyPrecheck::Ignored { .. } => {
                    self.io.remove_file_if_exists(staged.path).await;
                    return Ok(BackfillStageOutcome::Converged);
                }
                SegmentApplyPrecheck::Proceed { .. } => {}
            }
            self.append_to_segment(
                staged.path,
                size,
                staged.file_cache_policy,
                ApplyDurability::DeferredBatch,
            )
            .await?
        };
        self.evict_segments(evicted_segments).await?;
        batch.max_durability_seq = batch.max_durability_seq.max(durability_seq);
        batch
            .staged
            .push(StagedBackfillApply::Segmented(StagedBackfillSegmentApply {
                producer,
                namespace_id: namespace_id.to_owned(),
                key: key.to_owned(),
                content_type: content_type.to_owned(),
                version_ms,
                artifact_id,
                location,
                size,
            }));
        Ok(BackfillStageOutcome::Staged)
    }

    /// Phases 2–4 of the deferred backfill batch protocol (see
    /// [`BackfillApplyBatch`]). `on_group_committed` fires after each phase-3
    /// group's shared WriteBatch has landed and its write locks are released,
    /// with the number of staged records that group covered (skipped-because-
    /// superseded records included — they are converged either way); groups
    /// cover `batch`'s staged records in staging order, so the caller can
    /// resolve claims for exactly the records that are now readable. On an
    /// error anywhere in here the caller propagates it as a pass failure:
    /// groups already committed non-sync are safe (any later sync write
    /// flushes them, WAL replay recovers them on a clean restart, and a crash
    /// that loses them is absorbed by the re-list contract), and staged
    /// records not yet committed are just unreferenced segment bytes or
    /// dropped in-memory inline bodies.
    pub(crate) async fn commit_backfill_apply_batch(
        &self,
        batch: BackfillApplyBatch,
        mut on_group_committed: impl FnMut(usize),
    ) -> Result<(), String> {
        if batch.staged.is_empty() {
            return Ok(());
        }
        if batch
            .staged
            .iter()
            .any(|record| matches!(record, StagedBackfillApply::Segmented(_)))
        {
            // Phase 2: one group-commit fsync makes every staged append
            // durable before any of the batch's manifests can reach the WAL.
            // Covering every touched segment file with this single call is
            // exactly the `ensure_segment_durable` correctness argument: only
            // the active segment can hold un-synced bytes, because rotation
            // fsyncs the outgoing segment before it stops being the fsync
            // target — so a mid-batch rotation already made the sealed file's
            // appends durable, and this call covers the rest.
            self.ensure_segment_durable(batch.max_durability_seq)
                .await?;
        }
        // Phase 3: group commits — one shared non-sync WriteBatch per up to
        // BACKFILL_APPLY_GROUP_RECORDS staged records.
        let mut wrote_any = false;
        let mut groups = batch.staged.chunks(BACKFILL_APPLY_GROUP_RECORDS).peekable();
        while let Some(group) = groups.next() {
            wrote_any |= self.commit_backfill_apply_group(group).await?;
            on_group_committed(group.len());
            if groups.peek().is_some() {
                self.hit_failpoint(FailpointName::BetweenBackfillGroupCommits)
                    .await?;
            }
        }
        if !wrote_any {
            // Every record was superseded between staging and commit; there
            // is nothing of this batch in the WAL to make durable.
            return Ok(());
        }
        self.hit_failpoint(FailpointName::AfterBackfillBatchCommitBeforeWalFlush)
            .await?;
        // Phase 4: the batch durability barrier.
        self.flush_wal_barrier()
    }

    /// Phase-3 commit of one group of staged records: re-takes each record's
    /// per-artifact write lock, re-runs the authoritative LWW/tombstone
    /// checks, stages every surviving record's manifest/metadata mutations —
    /// through the same code paths as live applies — into ONE shared
    /// WriteBatch, writes it non-sync while still holding every lock, then
    /// runs the records' post-commit bookkeeping and releases the locks.
    /// Returns whether anything was written. A record superseded by a
    /// concurrent write between staging and commit is simply not staged into
    /// the shared batch; a superseded segmented record leaves its staged
    /// bytes orphaned in their segment — bounded by one batch and reclaimed
    /// at segment eviction, exactly like any LWW-overwritten copy.
    async fn commit_backfill_apply_group(
        &self,
        group: &[StagedBackfillApply],
    ) -> Result<bool, String> {
        // Holding up to BACKFILL_APPLY_GROUP_RECORDS write locks at once is
        // deadlock-free by ordering: the artifact write locks are striped, so
        // the group locks the deduplicated set of stripes its records hash to
        // in ascending stripe order, and every other path in the store only
        // ever holds ONE artifact write lock at a time (and never acquires a
        // second while holding it), so no cycle can involve them. Two
        // concurrent group commits (different backfill peers) both acquire in
        // the same ascending order and therefore cannot deadlock each other.
        // Stripe dedup also means two group records that share a stripe (or
        // an artifact) are covered by one guard rather than self-deadlocking.
        // Namespace read guards first, in the same ascending-stripe order and
        // for the same reason: this group's prechecks and its commit have to
        // span a concurrent namespace delete rather than interleave with it.
        // Taking them ahead of the artifact locks cannot invert, because the
        // delete path holds a namespace lock and never acquires an artifact
        // one.
        let mut namespace_stripes: Vec<usize> = group
            .iter()
            .map(|record| self.namespace_lock_index(record.namespace_id()))
            .collect();
        namespace_stripes.sort_unstable();
        namespace_stripes.dedup();
        let mut namespace_guards = Vec::with_capacity(namespace_stripes.len());
        for stripe in namespace_stripes {
            namespace_guards.push(self.namespace_locks[stripe].read().await);
        }

        let mut stripes: Vec<usize> = group
            .iter()
            .map(|record| self.artifact_write_lock_index(record.artifact_id()))
            .collect();
        stripes.sort_unstable();
        stripes.dedup();
        let mut guards = Vec::with_capacity(stripes.len());
        for stripe in stripes {
            guards.push(self.artifact_write_locks[stripe].lock().await);
        }

        let mut batch = WriteBatch::default();
        let mut committed = Vec::with_capacity(group.len());
        for record in group {
            match record {
                StagedBackfillApply::Segmented(staged) => {
                    let spec = staged.spec();
                    match self
                        .segment_apply_precheck(&staged.artifact_id, &spec)
                        .await?
                    {
                        SegmentApplyPrecheck::Ignored { .. } => {}
                        SegmentApplyPrecheck::Proceed { existing, .. } => {
                            // Backfill specs carry no replication targets, so
                            // this stages no outbox messages and the tally is
                            // always zero.
                            let mut bulk_outbox = 0;
                            let manifest = self.stage_segment_manifest(
                                &mut batch,
                                &spec,
                                &staged.artifact_id,
                                existing.as_ref(),
                                &staged.location,
                                staged.size,
                                &mut bulk_outbox,
                            )?;
                            committed.push(CommittedGroupRecord::Segmented {
                                manifest,
                                segment_id: staged.location.segment_id.clone(),
                            });
                        }
                    }
                }
                StagedBackfillApply::Inline(staged) => {
                    let spec = staged.spec();
                    match self
                        .inline_apply_precheck(&staged.artifact_id, &spec)
                        .await?
                    {
                        InlineApplyPrecheck::Ignored { .. } => {}
                        InlineApplyPrecheck::Proceed { existing } => {
                            // Same sticky-tag rule as the live inline path,
                            // resolved under the lock from the authoritative
                            // re-read (backfill never forwards a trunk).
                            let branch =
                                sticky_branch(existing.as_ref(), staged.branch.as_deref(), None);
                            let mut bulk_outbox = 0;
                            let (manifest, wrote_action_cache_index) = self.stage_inline_manifest(
                                &mut batch,
                                &spec,
                                &staged.artifact_id,
                                existing.as_ref(),
                                branch,
                                &staged.bytes,
                                &mut bulk_outbox,
                            )?;
                            committed.push(CommittedGroupRecord::Inline {
                                manifest,
                                wrote_action_cache_index,
                            });
                        }
                    }
                }
            }
        }
        if batch.is_empty() {
            return Ok(false);
        }
        self.write_batch_with_durability_off_runtime(
            batch,
            "backfill group batch",
            ApplyDurability::DeferredBatch,
        )
        .await?;
        for record in committed {
            match record {
                CommittedGroupRecord::Segmented {
                    manifest,
                    segment_id,
                } => {
                    self.note_segment_manifest_committed(&manifest, &segment_id)
                        .await?;
                }
                CommittedGroupRecord::Inline {
                    manifest,
                    wrote_action_cache_index,
                } => {
                    self.note_inline_manifest_committed(&manifest, wrote_action_cache_index);
                    self.hit_failpoint(FailpointName::AfterMetadataCommitBeforeReturn)
                        .await?;
                }
            }
        }
        Ok(true)
    }

    async fn persist_artifact_from_bytes_with_version(
        &self,
        spec: PersistArtifactSpec<'_>,
        bytes: &[u8],
    ) -> Result<(PersistArtifactOutcome, bool), String> {
        let disk_reservation = self.tmp_staging_budget.try_reserve(bytes.len() as u64)?;
        let temp_path = temp_file_path(&self.tmp_dir.join("uploads"), "replication");
        let mut cleanup = TempFileCleanup::new(temp_path.clone(), disk_reservation);
        self.io.write(&temp_path, bytes).await?;
        let result = self
            .persist_artifact_from_path_with_version(spec, &temp_path, FileCachePolicy::Adaptive)
            .await;
        cleanup.remove_and_disarm(&self.io).await;
        result
    }

    #[cfg(test)]
    pub async fn delete_namespace(&self, namespace_id: &str) -> Result<u64, String> {
        let version_ms = now_ms();
        self.delete_namespace_with_version(namespace_id, version_ms, &[])
            .await
            .map(|_| version_ms)
    }

    pub async fn delete_namespace_and_enqueue(
        &self,
        namespace_id: &str,
        replication_targets: &[String],
    ) -> Result<u64, String> {
        let version_ms = now_ms();
        self.delete_namespace_with_version(namespace_id, version_ms, replication_targets)
            .await
            .map(|_| version_ms)
    }

    pub async fn apply_replicated_namespace_delete(
        &self,
        namespace_id: &str,
        version_ms: u64,
    ) -> Result<NamespaceDeleteOutcome, String> {
        self.delete_namespace_with_version(namespace_id, version_ms, &[])
            .await
    }

    async fn delete_namespace_with_version(
        &self,
        namespace_id: &str,
        version_ms: u64,
        replication_targets: &[String],
    ) -> Result<NamespaceDeleteOutcome, String> {
        let prefix = format!("{namespace_id}\0");
        let mut batch = WriteBatch::default();
        let mut blob_paths = Vec::new();
        let mut removed_artifact_ids = Vec::new();
        let delete_everything = version_ms == 0;

        self.hit_failpoint(FailpointName::BeforeApplyReplicatedTombstone)
            .await?;
        // Held until the batch commits below. The tombstone decision is a
        // read, a compare, and a write separated by the namespace scan, so
        // without this two deletes for one namespace can both read the same
        // previous version, both decide they are newer, and commit in the
        // wrong order — leaving the older version as the tombstone and
        // un-blocking every artifact the newer delete removed. Peer deliveries
        // for one namespace arrive concurrently now that the outbox drain is
        // pipelined, and a re-delete of the same namespace is the ordinary way
        // to produce two of them.
        let _delete_guard = self.namespace_lock_for(namespace_id).write().await;
        let previous_tombstone = self.namespace_tombstone_version(namespace_id)?;
        if !delete_everything
            && let Some(current_tombstone) = previous_tombstone
            && current_tombstone >= version_ms
        {
            return Ok(NamespaceDeleteOutcome::IgnoredOlder);
        }
        let outbox_reservation = self.reserve_outbox_slots(if delete_everything {
            0
        } else {
            replication_targets.len()
        })?;
        if !delete_everything {
            batch.put_cf(
                self.cf(ROCKSDB_CF_NAMESPACE_TOMBSTONES),
                namespace_id.as_bytes(),
                version_ms.to_le_bytes(),
            );
            // A re-delete overwrites the tombstone in place, so its previous
            // backfill index row (keyed by the old version) goes with it.
            if let Some(previous_version_ms) = previous_tombstone {
                batch.delete_cf(
                    self.cf(ROCKSDB_CF_KEY_VALUE),
                    backfill_index_key(
                        previous_version_ms,
                        BackfillRecordKind::NamespaceTombstone,
                        namespace_id,
                    ),
                );
            }
            batch.put_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                backfill_index_key(
                    version_ms,
                    BackfillRecordKind::NamespaceTombstone,
                    namespace_id,
                ),
                backfill_index_value(None),
            );
        }

        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_NAMESPACE_ARTIFACTS),
            IteratorMode::From(prefix.as_bytes(), rocksdb::Direction::Forward),
        );

        for item in iter {
            let (index_key, _) =
                item.map_err(|error| format!("failed to iterate namespace index: {error}"))?;
            if !index_key.starts_with(prefix.as_bytes()) {
                break;
            }

            let artifact_id = std::str::from_utf8(&index_key[prefix.len()..])
                .map_err(|error| format!("invalid namespace index key: {error}"))?
                .to_owned();

            if let Some(manifest) = self.manifest_from_db(&artifact_id)? {
                if !delete_everything && manifest_version_ms(&manifest) > version_ms {
                    continue;
                }
                if manifest.inline {
                    batch.delete_cf(self.cf(ROCKSDB_CF_KEY_VALUE), artifact_id.as_bytes());
                }
                if manifest.producer == ArtifactProducer::Reapi
                    && let Some(action_hash) = action_cache_manifest_hash(&manifest.key)
                {
                    batch.delete_cf(
                        self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
                        action_cache_index_key(
                            namespace_id,
                            manifest.version_ms,
                            action_hash,
                            manifest.branch.as_deref(),
                        ),
                    );
                    // Drop the entry's reverse rows. Every blob-refs row for this
                    // namespace has its entry in this namespace, so deleting each
                    // removed entry's rows clears the namespace's rows without a
                    // separate per-blob scan. Read before the KEY_VALUE delete
                    // above commits.
                    if let Some(action_result_bytes) = self.inline_bytes(&artifact_id)? {
                        self.stage_action_cache_blob_refs_delete(
                            &mut batch,
                            namespace_id,
                            &artifact_id,
                            &action_result_bytes,
                        );
                    }
                }
                // Covers the `version_ms == 0` purge branch too: every removed
                // manifest — whatever its version — loses its index row here.
                self.stage_backfill_index_delete(&mut batch, &manifest);
                if let Some(blob_path) = manifest.blob_path {
                    blob_paths.push(blob_path);
                }
                if let Some(segment_id) = manifest.segment_id {
                    batch.delete_cf(
                        self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS),
                        segment_artifact_index_key(&segment_id, &artifact_id).as_bytes(),
                    );
                }
            }

            batch.delete_cf(self.cf(ROCKSDB_CF_NAMESPACE_ARTIFACTS), index_key);
            batch.delete_cf(self.cf(ROCKSDB_CF_MANIFESTS), artifact_id.as_bytes());
            removed_artifact_ids.push(artifact_id);
        }

        // Reset the action-cache index migration: surviving newer manifests
        // keep their rows, but a wiped namespace must re-backfill rather than
        // trust a marker written for the deleted keyspace.
        batch.delete_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            Self::action_cache_index_marker_key(namespace_id).as_bytes(),
        );

        let mut bulk_outbox = 0;
        if !delete_everything {
            bulk_outbox += self.append_namespace_delete_messages(
                &mut batch,
                namespace_id,
                version_ms,
                replication_targets,
            )?;
        }

        self.write_batch_with_durability_off_runtime(
            batch,
            "delete namespace batch",
            ApplyDurability::Sync,
        )
        .await?;
        outbox_reservation.commit(bulk_outbox);
        self.remove_manifest_cache_keys(&removed_artifact_ids);

        for path in blob_paths {
            self.remove_blob_handle(&path).await;
            self.io.remove_file_if_exists(Path::new(&path)).await;
        }

        self.hit_failpoint(FailpointName::AfterApplyReplicatedTombstone)
            .await?;

        Ok(NamespaceDeleteOutcome::Applied)
    }

    pub fn start_multipart_upload(
        &self,
        tenant_id: &str,
        namespace_id: &str,
        category: &str,
        hash: &str,
        name: &str,
    ) -> Result<String, String> {
        let reservation = self.reserve_multipart_upload()?;
        let upload_id = Uuid::now_v7().to_string();
        let upload = MultipartUpload {
            upload_id: upload_id.clone(),
            tenant_id: tenant_id.to_owned(),
            namespace_id: namespace_id.to_owned(),
            category: category.to_owned(),
            hash: hash.to_owned(),
            name: name.to_owned(),
            parts: BTreeMap::new(),
            created_at_ms: now_ms(),
        };

        let upload_bytes = serde_json::to_vec(&upload)
            .map_err(|error| format!("failed to encode multipart upload: {error}"))?;
        if upload_bytes.len() > MAX_MULTIPART_RECORD_BYTES {
            return Err(format!(
                "{MULTIPART_CAPACITY_ERROR}: multipart upload metadata exceeds {MAX_MULTIPART_RECORD_BYTES} bytes"
            ));
        }
        self.db
            .put_cf(
                self.cf(ROCKSDB_CF_MULTIPART_UPLOADS),
                upload_id.as_bytes(),
                upload_bytes,
            )
            .map_err(|error| format!("failed to store multipart upload: {error}"))?;

        reservation.commit();
        Ok(upload_id)
    }

    pub fn multipart_upload(&self, upload_id: &str) -> Result<Option<MultipartUpload>, String> {
        let raw = self
            .db
            .get_cf(self.cf(ROCKSDB_CF_MULTIPART_UPLOADS), upload_id.as_bytes())
            .map_err(|error| format!("failed to load multipart upload: {error}"))?;

        raw.map(|bytes| {
            serde_json::from_slice(&bytes)
                .map_err(|error| format!("failed to decode multipart upload: {error}"))
        })
        .transpose()
    }

    pub fn multipart_uploads_older_than_bounded(
        &self,
        cutoff_ms: u64,
        after: Option<&[u8]>,
        max_scanned: usize,
    ) -> Result<(Vec<String>, Option<Vec<u8>>), String> {
        if max_scanned == 0 {
            return Ok((Vec::new(), None));
        }
        let mode = after.map_or(IteratorMode::Start, |after| {
            IteratorMode::From(after, rocksdb::Direction::Forward)
        });
        let iter = self
            .db
            .iterator_cf(self.cf(ROCKSDB_CF_MULTIPART_UPLOADS), mode);
        let mut stale = Vec::with_capacity(max_scanned);
        let mut scanned = 0_usize;
        let mut next_after = None;
        for item in iter {
            let (key, value) =
                item.map_err(|error| format!("failed to iterate multipart uploads: {error}"))?;
            if after.is_some_and(|after| key.as_ref() <= after) {
                continue;
            }
            scanned += 1;
            next_after = Some(key.to_vec());
            let upload_id = match std::str::from_utf8(&key) {
                Ok(value) => value.to_owned(),
                Err(error) => {
                    return Err(format!("invalid multipart upload key: {error}"));
                }
            };
            let upload: MultipartUpload = match serde_json::from_slice(&value) {
                Ok(upload) => upload,
                Err(error) => {
                    tracing::warn!("failed to decode multipart upload {upload_id}: {error}");
                    if scanned == max_scanned {
                        break;
                    }
                    continue;
                }
            };
            if upload.created_at_ms < cutoff_ms {
                stale.push(upload_id);
            }
            if scanned == max_scanned {
                break;
            }
        }
        if scanned < max_scanned {
            next_after = None;
        }
        Ok((stale, next_after))
    }

    pub async fn add_multipart_part(
        &self,
        upload_id: &str,
        part_number: u32,
        part_path: &Path,
        size: u64,
    ) -> Result<(), MultipartError> {
        if part_number == 0 || part_number as usize > MAX_MULTIPART_PARTS {
            return Err(MultipartError::PartsMismatch);
        }
        let _guard = self.multipart_lock_for(upload_id).lock().await;
        let mut upload = self
            .multipart_upload(upload_id)
            .map_err(MultipartError::Other)?
            .ok_or(MultipartError::NotFound)?;
        if !upload.parts.contains_key(&part_number) && upload.parts.len() >= MAX_MULTIPART_PARTS {
            return Err(MultipartError::CapacityExceeded);
        }

        let next_total = next_total_size(&upload.parts, part_number, size);
        validate_total_size(next_total, MAX_MODULE_TOTAL_BYTES)?;
        let previous_part = upload.parts.get(&part_number).cloned();
        let previous_size = previous_part.as_ref().map(|part| part.size).unwrap_or(0);
        // The candidate and the previous immutable part coexist until the
        // durable upload record points at the candidate. Reserve that physical
        // overlap so replacement traffic cannot temporarily exceed the quota.
        let byte_reservation = self.reserve_multipart_bytes(size)?;

        let upload_dir = self.data_dir.join("multipart").join(upload_id);
        self.io.create_dir_all(&upload_dir).await.map_err(|error| {
            MultipartError::Other(format!("failed to create multipart dir: {error}"))
        })?;
        let candidate_path = upload_dir.join(format!("{part_number}-{}", Uuid::now_v7()));

        let store_result: Result<(), MultipartError> = async {
            if let Err(rename_error) = self.io.rename(part_path, &candidate_path).await {
                self.io.copy(part_path, &candidate_path).await.map_err(|error| {
                    MultipartError::Other(format!(
                        "failed to store multipart part after rename error ({rename_error}): {error}"
                    ))
                })?;
                self.io.remove_file_if_exists_result(part_path).await.map_err(|error| {
                    MultipartError::Other(format!("failed to remove staged multipart part: {error}"))
                })?;
            }
            let physical_size = self
                .io
                .metadata_len(&candidate_path)
                .await
                .map_err(MultipartError::Other)?;
            if physical_size != size {
                return Err(MultipartError::Other(format!(
                    "multipart part declared {size} bytes but stored {physical_size} bytes"
                )));
            }
            let stored_part = self
                .io
                .open_file(&candidate_path)
                .await
                .map_err(MultipartError::Other)?;
            stored_part.sync_data().await.map_err(|error| {
                MultipartError::Other(format!("failed to sync multipart part: {error}"))
            })?;
            drop(stored_part);
            self.io
                .drop_cached_pages(&candidate_path, 0, size)
                .await
                .map_err(MultipartError::Other)?;
            self.io
                .metrics()
                .record_memory_action("multipart_part_file_cache_drop");
            self.io
                .sync_dir(&upload_dir)
                .await
                .map_err(MultipartError::Other)?;

            upload.parts.insert(
                part_number,
                MultipartPart {
                    path: candidate_path.to_string_lossy().into_owned(),
                    size,
                },
            );
            let upload_bytes = serde_json::to_vec(&upload).map_err(|error| {
                MultipartError::Other(format!("failed to encode multipart upload: {error}"))
            })?;
            if upload_bytes.len() > MAX_MULTIPART_RECORD_BYTES {
                return Err(MultipartError::CapacityExceeded);
            }
            let mut batch = WriteBatch::default();
            batch.put_cf(
                self.cf(ROCKSDB_CF_MULTIPART_UPLOADS),
                upload_id.as_bytes(),
                upload_bytes,
            );
            self.write_batch_with_durability_off_runtime(
                batch,
                "multipart upload replacement",
                ApplyDurability::Sync,
            )
            .await
            .map_err(MultipartError::Other)?;
            Ok(())
        }
        .await;

        if let Err(error) = store_result {
            match self.io.remove_file_if_exists_result(&candidate_path).await {
                Ok(()) => return Err(error),
                Err(cleanup_error) => {
                    // The failed candidate remains on disk, so keep its full
                    // reservation. Startup reconciliation will retry cleanup.
                    byte_reservation.commit(0);
                    return Err(MultipartError::Other(format!(
                        "{error:?}; failed to remove the uncommitted multipart candidate: {cleanup_error}"
                    )));
                }
            }
        }

        if let Some(previous_part) = previous_part {
            match self
                .io
                .remove_file_if_exists_result(Path::new(&previous_part.path))
                .await
            {
                Ok(()) => byte_reservation.commit(previous_size),
                Err(error) => {
                    // The database already committed the candidate. Keep both
                    // physical files accounted and let startup or abort reclaim
                    // the unreferenced predecessor.
                    byte_reservation.commit(0);
                    self.io
                        .metrics()
                        .record_memory_action("multipart_replaced_part_cleanup_failed");
                    tracing::warn!(
                        upload_id,
                        part_number,
                        path = previous_part.path,
                        "failed to remove replaced multipart part: {error}"
                    );
                }
            }
        } else {
            byte_reservation.commit(0);
        }
        Ok(())
    }

    #[cfg(test)]
    pub async fn complete_multipart_upload(
        &self,
        upload_id: &str,
        expected_parts: &[u32],
    ) -> Result<ArtifactManifest, MultipartError> {
        self.complete_multipart_upload_and_enqueue(upload_id, expected_parts, &[])
            .await
    }

    pub async fn complete_multipart_upload_and_enqueue(
        &self,
        upload_id: &str,
        expected_parts: &[u32],
        replication_targets: &[String],
    ) -> Result<ArtifactManifest, MultipartError> {
        if expected_parts.is_empty()
            || expected_parts.len() > MAX_MULTIPART_PARTS
            || expected_parts
                .iter()
                .any(|part| *part == 0 || *part as usize > MAX_MULTIPART_PARTS)
        {
            return Err(MultipartError::PartsMismatch);
        }
        let _guard = self.multipart_lock_for(upload_id).lock().await;
        let upload = self
            .multipart_upload(upload_id)
            .map_err(MultipartError::Other)?
            .ok_or(MultipartError::NotFound)?;

        let uploaded: Vec<u32> = upload.parts.keys().copied().collect();
        if uploaded.is_empty() || uploaded != expected_parts {
            return Err(MultipartError::PartsMismatch);
        }
        let upload_size: u64 = upload.parts.values().map(|part| part.size).sum();
        let memory_reservation = reserve_foreground_staging(&self.memory, upload_size)
            .await
            .map_err(|_| MultipartError::MemoryPressure)?;
        let file_cache_policy = memory_reservation.file_cache_policy();
        let disk_reservation = self
            .tmp_staging_budget
            .try_reserve(upload_size)
            .map_err(MultipartError::Other)?;

        let assembled_path = temp_file_path(&self.tmp_dir.join("uploads"), "module");
        let mut cleanup = TempFileCleanup::new(assembled_path.clone(), disk_reservation);
        let mut assembled = self
            .io
            .create_file(&assembled_path)
            .await
            .map_err(MultipartError::Other)?;
        let mut assembled_bytes = 0_u64;
        let mut advised_through = 0_u64;
        let mut copy_buffer = vec![0_u8; SEGMENT_COPY_BUFFER_BYTES];

        for part_number in expected_parts {
            let part = upload
                .parts
                .get(part_number)
                .ok_or(MultipartError::PartsMismatch)?;
            let mut part_file = self
                .io
                .open_file(Path::new(&part.path))
                .await
                .map_err(MultipartError::Other)?;
            let mut copied = 0_u64;
            while copied < part.size {
                let remaining = usize::try_from((part.size - copied).min(copy_buffer.len() as u64))
                    .expect("multipart copy chunk fits usize");
                let read = part_file
                    .read(&mut copy_buffer[..remaining])
                    .await
                    .map_err(|error| {
                        MultipartError::Other(format!(
                            "failed to read multipart part {part_number}: {error}"
                        ))
                    })?;
                if read == 0 {
                    break;
                }
                assembled
                    .write_all(&copy_buffer[..read])
                    .await
                    .map_err(|error| {
                        MultipartError::Other(format!(
                            "failed to assemble multipart artifact: {error}"
                        ))
                    })?;
                copied = copied.saturating_add(read as u64);
                assembled_bytes = assembled_bytes.saturating_add(read as u64);
                if file_cache_policy.should_drop(
                    self.memory.should_reclaim_file_cache(),
                    self.memory.transient_reserved_bytes(),
                ) && assembled_bytes.saturating_sub(advised_through)
                    >= FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES
                {
                    assembled = drop_staging_cache_range(
                        assembled,
                        &assembled_path,
                        advised_through,
                        assembled_bytes - advised_through,
                        &self.io,
                    )
                    .await
                    .map_err(MultipartError::Other)?;
                    advised_through = assembled_bytes;
                }
            }
            if copied != part.size {
                return Err(MultipartError::Other(format!(
                    "multipart part {part_number} expected {} bytes but copied {copied}",
                    part.size
                )));
            }
            drop(part_file);
            self.io
                .drop_cached_pages(Path::new(&part.path), 0, part.size)
                .await
                .map_err(MultipartError::Other)?;
        }
        assembled.flush().await.map_err(|error| {
            MultipartError::Other(format!("failed to flush assembled artifact: {error}"))
        })?;

        let key = module_key(&upload.category, &upload.hash, &upload.name);
        let manifest = self
            .persist_artifact_from_path_and_enqueue(
                ArtifactProducer::Module,
                &upload.namespace_id,
                &key,
                "application/octet-stream",
                StagedArtifactPath::new(&assembled_path, file_cache_policy),
                replication_targets,
            )
            .await
            .map_err(MultipartError::Other)?
            .manifest;
        cleanup.remove_and_disarm(&self.io).await;
        drop(memory_reservation);

        self.abort_multipart_upload_locked(upload_id)
            .await
            .map_err(MultipartError::Other)?;

        Ok(manifest)
    }

    pub async fn abort_multipart_upload(&self, upload_id: &str) -> Result<(), String> {
        let _guard = self.multipart_lock_for(upload_id).lock().await;
        self.abort_multipart_upload_locked(upload_id).await
    }

    async fn abort_multipart_upload_locked(&self, upload_id: &str) -> Result<(), String> {
        let upload_dir = self.data_dir.join("multipart").join(upload_id);
        let upload_exists = self.multipart_upload(upload_id)?.is_some();

        let stored_before = path_size_bytes_on_blocking_pool(upload_dir.clone())
            .await
            .map_err(|error| {
            format!(
                "failed to account multipart upload {upload_id} before removal; its durable record was retained: {error}"
            )
            })?;
        let removal = self.io.remove_dir_all_if_exists(&upload_dir).await;
        let stored_after = path_size_bytes_on_blocking_pool(upload_dir)
            .await
            .map_err(|error| {
            format!(
                "failed to account multipart upload {upload_id} after removal; its durable record was retained: {error}"
            )
            })?;
        let reclaimed = stored_before.saturating_sub(stored_after);
        if reclaimed > 0 {
            release_atomic_bytes(&self.multipart_stored_bytes, reclaimed);
        }
        removal?;

        if upload_exists {
            let mut batch = WriteBatch::default();
            batch.delete_cf(self.cf(ROCKSDB_CF_MULTIPART_UPLOADS), upload_id.as_bytes());
            self.write_batch_with_durability_off_runtime(
                batch,
                "multipart upload deletion",
                ApplyDurability::Sync,
            )
            .await?;
            release_atomic_slots(&self.multipart_uploads, 1);
        }

        Ok(())
    }

    #[cfg(test)]
    pub fn enqueue(&self, message: OutboxMessage) -> Result<(), String> {
        let outbox_reservation = self.reserve_outbox_slots(1)?;
        let key = outbox_message_key(&message);
        let value = serde_json::to_vec(&message)
            .map_err(|error| format!("failed to encode outbox message: {error}"))?;
        let mut batch = WriteBatch::default();
        batch.put_cf(self.cf(ROCKSDB_CF_OUTBOX), key.as_bytes(), value);
        self.write_batch_sync(batch, "outbox message")?;
        outbox_reservation.commit(usize::from(is_bulk_outbox_key(key.as_bytes())));
        Ok(())
    }

    pub fn next_outbox_message(
        &self,
        after: Option<&[u8]>,
    ) -> Result<Option<(Vec<u8>, OutboxMessage)>, String> {
        let iter = match after {
            Some(after) => self.db.iterator_cf(
                self.cf(ROCKSDB_CF_OUTBOX),
                IteratorMode::From(after, rocksdb::Direction::Forward),
            ),
            None => self
                .db
                .iterator_cf(self.cf(ROCKSDB_CF_OUTBOX), IteratorMode::Start),
        };

        for item in iter {
            let (key, value) =
                item.map_err(|error| format!("failed to iterate outbox: {error}"))?;
            if after.is_some_and(|cursor| key.as_ref() == cursor) {
                continue;
            }
            let message = serde_json::from_slice::<OutboxMessage>(&value)
                .map_err(|error| format!("failed to decode outbox message: {error}"))?;
            return Ok(Some((key.to_vec(), message)));
        }
        Ok(None)
    }

    pub fn outbox_message_count(&self) -> Result<usize, String> {
        Ok(self.outbox_depth())
    }

    pub fn append_usage_rollups(&self, rollups: &[UsageRollup]) -> Result<(), String> {
        if rollups.is_empty() {
            return Ok(());
        }

        let mut batch = WriteBatch::default();
        for rollup in rollups {
            let value = serde_json::to_vec(rollup)
                .map_err(|error| format!("failed to encode usage rollup: {error}"))?;
            batch.put_cf(
                self.cf(ROCKSDB_CF_USAGE_OUTBOX),
                rollup.event_id.as_bytes(),
                value,
            );
        }
        self.write_batch_sync(batch, "usage rollups")
    }

    pub fn next_usage_rollups(&self, limit: usize) -> Result<Vec<(Vec<u8>, UsageRollup)>, String> {
        let mut rollups = Vec::new();
        let iter = self
            .db
            .iterator_cf(self.cf(ROCKSDB_CF_USAGE_OUTBOX), IteratorMode::Start);

        for item in iter {
            let (key, value) =
                item.map_err(|error| format!("failed to iterate usage outbox: {error}"))?;
            let rollup = serde_json::from_slice::<UsageRollup>(&value)
                .map_err(|error| format!("failed to decode usage rollup: {error}"))?;
            rollups.push((key.to_vec(), rollup));
            if rollups.len() >= limit {
                break;
            }
        }

        Ok(rollups)
    }

    pub fn usage_outbox_message_count(&self) -> Result<usize, String> {
        self.count_cf_entries(ROCKSDB_CF_USAGE_OUTBOX)
    }

    pub fn delete_usage_rollups(&self, keys: &[Vec<u8>]) -> Result<(), String> {
        if keys.is_empty() {
            return Ok(());
        }

        let mut batch = WriteBatch::default();
        for key in keys {
            batch.delete_cf(self.cf(ROCKSDB_CF_USAGE_OUTBOX), key);
        }
        self.write_batch_sync(batch, "usage rollup deletes")
    }

    #[cfg(test)]
    pub fn outbox_messages(&self) -> Result<Vec<(Vec<u8>, OutboxMessage)>, String> {
        let mut messages = Vec::new();
        let mut after = None::<Vec<u8>>;
        while let Some((key, message)) = self.next_outbox_message(after.as_deref())? {
            after = Some(key.clone());
            messages.push((key, message));
        }
        Ok(messages)
    }

    pub fn snapshot(&self) -> Result<StoreSnapshot, String> {
        let outbox_messages = self.outbox_message_count()?;
        let outbox_bulk_messages = self.outbox_bulk_depth();
        let multipart_uploads = self.count_cf_entries(ROCKSDB_CF_MULTIPART_UPLOADS)?;
        let promotion_queue_depth = self
            .promotion_queue
            .lock()
            .expect("promotion queue lock")
            .depth();
        let segment_state = self.segment_state_snapshot();
        let segment_counts = vec![
            ("old", segment_state.state.old.len()),
            ("current", segment_state.state.current.len()),
            ("new", segment_state.state.new.len()),
        ];
        Ok(StoreSnapshot {
            outbox_messages,
            outbox_bulk_messages,
            multipart_uploads,
            promotion_queue_depth,
            segment_counts,
            segment_fsync_count: self.segment_fsync_count.load(Ordering::Relaxed),
            rocksdb_block_cache_usage_bytes: self.rocksdb_block_cache.get_usage() as u64,
            rocksdb_block_cache_pinned_usage_bytes: self.rocksdb_block_cache.get_pinned_usage()
                as u64,
            rocksdb_block_cache_capacity_bytes: self.rocksdb_block_cache_capacity_bytes as u64,
            rocksdb_write_buffer_usage_bytes: self.rocksdb_write_buffer_manager.get_usage() as u64,
            rocksdb_write_buffer_capacity_bytes: self.rocksdb_write_buffer_manager.get_buffer_size()
                as u64,
        })
    }

    /// Deletes artifact metadata: the manifest, its namespace and segment
    /// index entries, and the lookup caches. Bytes already in segments are
    /// left for segment reclamation — the records this serves (action-cache
    /// expiry) are a few hundred bytes each. Deletion is node-local: peers
    /// running the same policy over the replicated `version_ms` converge on
    /// their own, and an entry re-copied by a later backfill just expires
    /// again on the next sweep. A concurrent republish of the same key can
    /// race the batch and lose its fresh manifest — benign, the client
    /// recompiles and republishes.
    pub fn delete_artifact_metadata(&self, manifests: &[ArtifactManifest]) -> Result<(), String> {
        if manifests.is_empty() {
            return Ok(());
        }
        let mut batch = WriteBatch::default();
        let mut ids = Vec::with_capacity(manifests.len());
        for manifest in manifests {
            batch.delete_cf(
                self.cf(ROCKSDB_CF_MANIFESTS),
                manifest.artifact_id.as_bytes(),
            );
            batch.delete_cf(
                self.cf(ROCKSDB_CF_NAMESPACE_ARTIFACTS),
                namespace_artifact_index_key(&manifest.namespace_id, &manifest.artifact_id)
                    .as_bytes(),
            );
            // Inline artifacts keep their bytes in the key-value column family
            // keyed by artifact_id; without this the manifest is gone but the
            // bytes leak (as the namespace-delete path already handles).
            if manifest.inline {
                batch.delete_cf(
                    self.cf(ROCKSDB_CF_KEY_VALUE),
                    manifest.artifact_id.as_bytes(),
                );
            }
            if manifest.producer == ArtifactProducer::Reapi
                && let Some(action_hash) = action_cache_manifest_hash(&manifest.key)
            {
                batch.delete_cf(
                    self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
                    action_cache_index_key(
                        &manifest.namespace_id,
                        manifest.version_ms,
                        action_hash,
                        manifest.branch.as_deref(),
                    ),
                );
                // Drop this entry's reverse rows so the blob-refs map does not
                // retain references to an entry that no longer exists: otherwise
                // a later eviction of those blobs would try to cascade an
                // already-removed entry, and the rows would leak for blobs that
                // outlive it. Read before the KEY_VALUE delete above commits.
                if let Some(action_result_bytes) = self.inline_bytes(&manifest.artifact_id)? {
                    self.stage_action_cache_blob_refs_delete(
                        &mut batch,
                        &manifest.namespace_id,
                        &manifest.artifact_id,
                        &action_result_bytes,
                    );
                }
            }
            if let Some(segment_id) = &manifest.segment_id {
                batch.delete_cf(
                    self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS),
                    segment_artifact_index_key(segment_id, &manifest.artifact_id).as_bytes(),
                );
            }
            self.stage_backfill_index_delete(&mut batch, manifest);
            ids.push(manifest.artifact_id.clone());
        }
        self.write_batch_sync(batch, "artifact metadata deletes")?;
        self.remove_manifest_cache_keys(&ids);
        Ok(())
    }

    /// Walks the manifest keyspace and deletes REAPI action-cache entries
    /// whose `version_ms` predates `cutoff_ms`, up to `max_deletes` per call
    /// (the remainder ages out on later sweeps, which smooths the first sweep
    /// after this ships over a store that never expired anything). Entries
    /// are append-only otherwise — every source change publishes new keys and
    /// nothing removed the stale ones, so an actively developed namespace
    /// grew its keyspace, and with it the snapshot reconcile scan, without
    /// bound.
    pub fn expire_stale_action_cache_entries(
        &self,
        cutoff_ms: u64,
        max_deletes: usize,
    ) -> Result<usize, String> {
        const SCAN_PAGE: usize = 4096;
        let mut after: Option<String> = None;
        let mut expired: Vec<ArtifactManifest> = Vec::new();
        loop {
            let page = self.manifests_page(after.as_deref(), SCAN_PAGE)?;
            for manifest in page.manifests {
                if manifest.producer == ArtifactProducer::Reapi
                    && manifest.key.starts_with("action_cache/")
                    && manifest.version_ms < cutoff_ms
                {
                    expired.push(manifest);
                    if expired.len() >= max_deletes {
                        break;
                    }
                }
            }
            if expired.len() >= max_deletes {
                break;
            }
            match page.next_after {
                Some(next) => after = Some(next),
                None => break,
            }
        }
        let count = expired.len();
        for chunk in expired.chunks(1024) {
            self.delete_artifact_metadata(chunk)?;
        }
        Ok(count)
    }

    /// Every REAPI action-cache manifest in a namespace, for the instance-wide
    /// snapshot the REAPI layer serves (one round trip primes a cold client
    /// with every key→value association), capped at the NEWEST `max_entries`
    /// by write time.
    ///
    /// Served from the dedicated action-cache index: a forward prefix scan
    /// yields rows newest-first (the key embeds `!version_ms`), so the scan
    /// touches at most `max_entries` action-cache rows plus their manifest
    /// point-reads. The previous implementation walked the ENTIRE namespace
    /// index and point-read every manifest just to filter out blobs — tens of
    /// minutes on production namespaces where blobs outnumber action-cache
    /// entries a thousand to one, which starved every snapshot fetch into a
    /// client timeout. Namespaces written before the index existed are
    /// backfilled with one legacy scan on first use.
    ///
    /// When `trunk` is `Some`, only entries whose manifest carries that branch
    /// only (an untagged entry is not in the baseline: see `branch_in_trunk`)
    /// are returned; the cap counts kept entries only. `None` returns every
    /// action-cache entry regardless of branch.
    #[cfg(test)]
    pub fn action_cache_manifests(
        &self,
        namespace_id: &str,
        max_entries: usize,
        trunk: Option<&str>,
    ) -> Result<Vec<ArtifactManifest>, String> {
        self.action_cache_manifests_bounded(namespace_id, max_entries, usize::MAX, trunk)
    }

    pub fn action_cache_manifests_bounded(
        &self,
        namespace_id: &str,
        max_entries: usize,
        max_working_bytes: usize,
        trunk: Option<&str>,
    ) -> Result<Vec<ArtifactManifest>, String> {
        if !self.action_cache_index_backfilled(namespace_id)? {
            self.backfill_action_cache_index(namespace_id)?;
        }
        let prefix = action_cache_index_prefix(namespace_id);
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
            IteratorMode::From(&prefix, rocksdb::Direction::Forward),
        );
        let mut manifests = Vec::new();
        let mut working_bytes = 0_usize;
        let mut stale_working_bytes = 0_usize;
        // Rows whose manifest is gone or has moved to a different version:
        // overwrites and deletes clean up their own rows, but a row written by
        // a crashed batch or a pre-fix overwrite can linger — drop it here so
        // the index converges instead of paying the dead point-read forever.
        let mut stale_rows: Vec<Vec<u8>> = Vec::with_capacity(ACTION_CACHE_STALE_DELETE_BATCH);
        // Bounds the point-reads, which are the work: each is a random read into
        // the manifests CF, where advancing the iterator is a sequential step over
        // a compact CF. A row that carries its branch answers the trunk filter
        // without being read at all, so feature churn no longer costs anything to
        // reject and no longer eats this budget. What remains under it is rows
        // written before the branch was recorded, plus stale rows: both have to
        // ask the manifest, and both are finite and self-clearing. Newest-first
        // means the rows examined first are the ones worth keeping, so stopping
        // early yields a smaller but still current trunk view rather than a wrong
        // one.
        let read_budget = max_entries.saturating_mul(ACTION_CACHE_TRUNK_SCAN_FACTOR);
        let mut read = 0usize;
        // Not a budget, an observation: rejecting a row is free now, so the walk
        // is bounded by the namespace rather than by `read_budget`. Reporting it
        // is what makes a namespace whose walk dwarfs its view visible instead of
        // something to infer.
        let mut scanned = 0usize;
        for item in iter {
            let (index_key, artifact_id) =
                item.map_err(|error| format!("failed to iterate action-cache index: {error}"))?;
            if !index_key.starts_with(&prefix) {
                break;
            }
            scanned += 1;
            if manifests.len() >= max_entries {
                break;
            }
            // The row's own tag settles the filter for every entry indexed since
            // the branch was recorded, which is the whole point of carrying it.
            if let IndexRowBranch::Known(branch) =
                action_cache_index_key_branch(&index_key, prefix.len())
                && !branch_in_trunk(branch, trunk)
            {
                continue;
            }
            let artifact_id = std::str::from_utf8(&artifact_id)
                .map_err(|error| format!("invalid action-cache index value: {error}"))?;
            read += 1;
            if trunk.is_some() && read > read_budget {
                // Say so rather than quietly return a short view: a namespace
                // that trips this is telling us its trunk entries are buried
                // under feature churn, which is what a branch-keyed index would
                // fix at the source.
                tracing::warn!(
                    namespace_id,
                    read,
                    scanned,
                    kept = manifests.len(),
                    "action-cache trunk scan hit its read budget; view truncated"
                );
                break;
            }
            let row_version = index_key
                .get(prefix.len()..prefix.len() + 8)
                .and_then(|bytes| <[u8; 8]>::try_from(bytes).ok())
                .map(|bytes| !u64::from_be_bytes(bytes));
            match self.manifest_from_db(artifact_id)? {
                Some(manifest)
                    if manifest.producer == ArtifactProducer::Reapi
                        && manifest.key.starts_with("action_cache/")
                        && row_version == Some(manifest.version_ms) =>
                {
                    // A valid entry outside the trunk filter is skipped, not
                    // deleted: it is a live entry for another branch.
                    if !manifest_in_trunk(&manifest, trunk) {
                        continue;
                    }
                    if !stale_rows.is_empty() {
                        self.delete_stale_action_cache_rows(&mut stale_rows)?;
                        working_bytes = working_bytes.saturating_sub(stale_working_bytes);
                        stale_working_bytes = 0;
                    }
                    let charge = estimated_manifest_working_bytes(&manifest);
                    if working_bytes.saturating_add(charge) > max_working_bytes {
                        break;
                    }
                    working_bytes = working_bytes.saturating_add(charge);
                    manifests.push(manifest);
                }
                _ => {
                    if stale_rows.len() == ACTION_CACHE_STALE_DELETE_BATCH {
                        self.delete_stale_action_cache_rows(&mut stale_rows)?;
                        working_bytes = working_bytes.saturating_sub(stale_working_bytes);
                        stale_working_bytes = 0;
                    }
                    let charge = std::mem::size_of::<Vec<u8>>().saturating_add(index_key.len());
                    let flush_peak = working_bytes
                        .saturating_add(stale_working_bytes)
                        .saturating_add(charge.saturating_mul(2));
                    if flush_peak > max_working_bytes {
                        break;
                    }
                    working_bytes = working_bytes.saturating_add(charge);
                    stale_working_bytes = stale_working_bytes.saturating_add(charge);
                    stale_rows.push(index_key.to_vec());
                }
            }
        }
        self.delete_stale_action_cache_rows(&mut stale_rows)?;
        Ok(manifests)
    }

    fn delete_stale_action_cache_rows(&self, stale_rows: &mut Vec<Vec<u8>>) -> Result<(), String> {
        if stale_rows.is_empty() {
            return Ok(());
        }
        let mut batch = WriteBatch::default();
        for row in std::mem::take(stale_rows) {
            batch.delete_cf(self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX), row);
        }
        self.write_batch_sync(batch, "action-cache index stale rows")
    }

    /// The namespace's action-cache generation. A snapshot index records this at
    /// build time; if it has not moved, the index still describes the namespace,
    /// including when the index is empty.
    pub fn action_cache_generation(&self, namespace_id: &str) -> u64 {
        self.action_cache_generations
            .lock()
            .expect("action-cache generations lock poisoned")
            .get(namespace_id)
            .copied()
            .unwrap_or(0)
    }

    fn bump_action_cache_generation(&self, namespace_id: &str) {
        *self
            .action_cache_generations
            .lock()
            .expect("action-cache generations lock poisoned")
            .entry(namespace_id.to_owned())
            .or_insert(0) += 1;
    }

    /// Deliberately NOT versioned to force a rebuild when the branch joined the
    /// key. The branch is part of the key, so rewriting a row under the new
    /// format writes a second row rather than overwriting the old one, and a
    /// forced rebuild would leave every entry indexed twice.
    ///
    /// It needs no rebuild. A row written before the branch reports its tag as
    /// unknown and asks the manifest, exactly as it did before, and the next
    /// publish of that entry supersedes it: the new row carries the tag, and the
    /// old one is left pointing at a stale version, which the scan already
    /// retires. The migration therefore rides along with the republishes that
    /// re-tagging needs anyway.
    fn action_cache_index_marker_key(namespace_id: &str) -> String {
        format!("action_cache_index/backfilled/{namespace_id}")
    }

    fn action_cache_index_backfilled(&self, namespace_id: &str) -> Result<bool, String> {
        self.db
            .get_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                Self::action_cache_index_marker_key(namespace_id).as_bytes(),
            )
            .map(|marker| marker.is_some())
            .map_err(|error| format!("failed to read action-cache index marker: {error}"))
    }

    /// One-time migration per namespace: the legacy full namespace scan,
    /// writing an index row for every action-cache manifest it encounters
    /// (the index must be complete for later capped scans to be correct),
    /// then the backfill marker. Idempotent bounded batches keep the migration
    /// working set fixed; a crash before the marker safely repeats them.
    fn backfill_action_cache_index(&self, namespace_id: &str) -> Result<(), String> {
        let started = std::time::Instant::now();
        let prefix = format!("{namespace_id}\0");
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_NAMESPACE_ARTIFACTS),
            IteratorMode::From(prefix.as_bytes(), rocksdb::Direction::Forward),
        );
        let mut batch = WriteBatch::default();
        let mut rows = 0_usize;
        let mut pending_rows = 0_usize;
        for item in iter {
            let (index_key, _) =
                item.map_err(|error| format!("failed to iterate namespace index: {error}"))?;
            if !index_key.starts_with(prefix.as_bytes()) {
                break;
            }
            let artifact_id = std::str::from_utf8(&index_key[prefix.len()..])
                .map_err(|error| format!("invalid namespace index key: {error}"))?;
            let Some(manifest) = self.manifest_from_db(artifact_id)? else {
                continue;
            };
            if manifest.producer != ArtifactProducer::Reapi {
                continue;
            }
            let Some(action_hash) = action_cache_manifest_hash(&manifest.key) else {
                continue;
            };
            batch.put_cf(
                self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
                action_cache_index_key(
                    namespace_id,
                    manifest.version_ms,
                    action_hash,
                    manifest.branch.as_deref(),
                ),
                manifest.artifact_id.as_bytes(),
            );
            rows += 1;
            pending_rows += 1;
            if pending_rows == 1_024 {
                self.write_batch_sync(
                    std::mem::take(&mut batch),
                    "action-cache index backfill batch",
                )?;
                pending_rows = 0;
            }
        }
        if pending_rows > 0 {
            self.write_batch_sync(batch, "action-cache index backfill batch")?;
        }
        let mut marker_batch = WriteBatch::default();
        marker_batch.put_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            Self::action_cache_index_marker_key(namespace_id).as_bytes(),
            [],
        );
        self.write_batch_sync(marker_batch, "action-cache index backfill marker")?;
        tracing::info!(
            namespace_id,
            rows,
            elapsed_ms = started.elapsed().as_millis() as u64,
            "action-cache index backfilled"
        );
        Ok(())
    }

    /// The physical blob ids an action-cache entry references, derived from its
    /// inline `ActionResult` bytes. Each referenced blob key resolves to the
    /// same `artifact_storage_id` the CAS write path assigns it, so the reverse
    /// index keys line up with the blob ids `evict_segment` iterates.
    fn action_cache_entry_blob_ids(
        &self,
        namespace_id: &str,
        action_result_bytes: &[u8],
    ) -> Vec<String> {
        referenced_blob_keys(action_result_bytes)
            .into_iter()
            .map(|blob_key| {
                artifact_storage_id(
                    ArtifactProducer::Reapi,
                    &self.tenant_id,
                    namespace_id,
                    &blob_key,
                )
            })
            .collect()
    }

    /// Stage the reverse rows for an entry into `batch`: one `{blob}\0{entry}`
    /// pair per referenced blob. Called in the same batch that writes the entry,
    /// so the entry and its reverse rows commit together or not at all.
    fn stage_action_cache_blob_refs_put(
        &self,
        batch: &mut WriteBatch,
        namespace_id: &str,
        entry_artifact_id: &str,
        action_result_bytes: &[u8],
    ) {
        for blob_id in self.action_cache_entry_blob_ids(namespace_id, action_result_bytes) {
            batch.put_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                action_cache_blob_ref_key(&blob_id, entry_artifact_id).as_bytes(),
                [],
            );
        }
    }

    /// Stage deletion of an entry's reverse rows into `batch`, derived from the
    /// entry's (old) `ActionResult` bytes. Used on re-publish (drop the previous
    /// version's rows) and on every delete path (so the map does not leak rows
    /// for entries that no longer exist).
    fn stage_action_cache_blob_refs_delete(
        &self,
        batch: &mut WriteBatch,
        namespace_id: &str,
        entry_artifact_id: &str,
        action_result_bytes: &[u8],
    ) {
        for blob_id in self.action_cache_entry_blob_ids(namespace_id, action_result_bytes) {
            batch.delete_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                action_cache_blob_ref_key(&blob_id, entry_artifact_id).as_bytes(),
            );
        }
    }

    fn action_cache_blob_refs_marker_key() -> &'static str {
        "action_cache_blob_refs/backfilled"
    }

    fn action_cache_blob_refs_cursor_key() -> &'static str {
        "action_cache_blob_refs/cursor"
    }

    fn action_cache_blob_refs_backfilled(&self) -> Result<bool, String> {
        self.db
            .get_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                Self::action_cache_blob_refs_marker_key().as_bytes(),
            )
            .map(|marker| marker.is_some())
            .map_err(|error| format!("failed to read blob-refs backfill marker: {error}"))
    }

    /// Whether the eviction cascade should run. Operator-controlled only: the
    /// cascade is safe against an incomplete reverse map because it re-validates
    /// every pair against the entry before removing it, so a missing row can
    /// only under-cascade (the serve-side presence gates still cover those),
    /// never remove a live entry.
    ///
    /// Deliberately NOT gated on the backfill having completed. The backfill
    /// waits on background headroom (`app.rs`), and a warm serving node parks
    /// clean page cache at the hard watermark as its steady state, so that gate
    /// never opens in production: the cascade stayed inert across every eviction
    /// sweep since it shipped. Waiting for full coverage bought nothing and cost
    /// all of it. Rows for entries written since boot are maintained by the
    /// write path regardless, so the cascade is useful from the first eviction.
    fn action_cache_cascade_active(&self) -> bool {
        self.action_cache_eviction_cascade_enabled
    }

    /// One-time startup migration: rebuild the blob-refs reverse map from the
    /// action-cache entries already on disk, so the eviction cascade also covers
    /// entries that predate the reverse map. The cascade does not wait on this;
    /// it runs against whatever rows exist. Idempotent: a marker in the key-value CF
    /// records completion, so a restart after a completed backfill only reads the
    /// marker and arms the flag. A crash mid-backfill safely repeats: the rows
    /// are blind puts (re-adding an existing pair is a no-op) and the marker is
    /// written last.
    ///
    /// Concurrency: entries written or re-published while this runs maintain
    /// their own rows through the write path. A stale pair this backfill might
    /// re-add just after a concurrent overwrite removed it is harmless, because
    /// the eviction cascade re-checks that an entry still references the evicted
    /// blob before removing it and drops only the stale pair otherwise, so the
    /// scan does not need to lock each entry.
    pub fn backfill_action_cache_blob_refs_step(
        &self,
    ) -> Result<ActionCacheBlobRefsBackfillStep, String> {
        if self.action_cache_blob_refs_backfilled()? {
            self.action_cache_blob_refs_ready
                .store(true, Ordering::Release);
            return Ok(ActionCacheBlobRefsBackfillStep {
                rows: 0,
                complete: true,
            });
        }

        let after = self
            .db
            .get_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                Self::action_cache_blob_refs_cursor_key().as_bytes(),
            )
            .map_err(|error| format!("failed to read blob-refs backfill cursor: {error}"))?
            .map(|cursor| {
                String::from_utf8(cursor.to_vec())
                    .map_err(|error| format!("invalid blob-refs backfill cursor: {error}"))
            })
            .transpose()?;
        let page = self.manifests_page(
            after.as_deref(),
            ACTION_CACHE_BLOB_REFS_BACKFILL_MANIFESTS_PER_STEP,
        )?;
        let mut batch = WriteBatch::default();
        let mut pending = 0_usize;
        let mut rows = 0_usize;
        for manifest in &page.manifests {
            if manifest.producer != ArtifactProducer::Reapi
                || action_cache_manifest_hash(&manifest.key).is_none()
            {
                continue;
            }
            // Segment-backed entries are skipped here (as on the write and
            // delete paths): the reverse index only covers inline entries,
            // and the serve-side gates cover the rest.
            let Some(bytes) = self.inline_bytes(&manifest.artifact_id)? else {
                continue;
            };
            for blob_id in self.action_cache_entry_blob_ids(&manifest.namespace_id, &bytes) {
                batch.put_cf(
                    self.cf(ROCKSDB_CF_KEY_VALUE),
                    action_cache_blob_ref_key(&blob_id, &manifest.artifact_id).as_bytes(),
                    [],
                );
                pending += 1;
                rows += 1;
                if pending == ACTION_CACHE_BLOB_REFS_BACKFILL_ROWS_PER_BATCH {
                    self.write_batch_sync(
                        std::mem::take(&mut batch),
                        "action-cache blob-refs backfill batch",
                    )?;
                    pending = 0;
                }
            }
        }
        if pending > 0 {
            self.write_batch_sync(batch, "action-cache blob-refs backfill batch")?;
        }

        let complete = page.next_after.is_none();
        let mut progress_batch = WriteBatch::default();
        if complete {
            progress_batch.put_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                Self::action_cache_blob_refs_marker_key().as_bytes(),
                [],
            );
            progress_batch.delete_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                Self::action_cache_blob_refs_cursor_key().as_bytes(),
            );
        } else if let Some(cursor) = page.manifests.last() {
            progress_batch.put_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                Self::action_cache_blob_refs_cursor_key().as_bytes(),
                cursor.artifact_id.as_bytes(),
            );
        }
        self.write_batch_sync(progress_batch, "action-cache blob-refs backfill progress")?;
        if complete {
            self.action_cache_blob_refs_ready
                .store(true, Ordering::Release);
        }
        Ok(ActionCacheBlobRefsBackfillStep { rows, complete })
    }

    #[cfg(test)]
    fn backfill_action_cache_blob_refs(&self) -> Result<usize, String> {
        let mut rows = 0_usize;
        loop {
            let step = self.backfill_action_cache_blob_refs_step()?;
            rows += step.rows;
            if step.complete {
                return Ok(rows);
            }
        }
    }

    /// Every namespace delete tombstone as `(namespace_id, version_ms)`, in
    /// key order. Test-only: nothing in production reads tombstones in bulk
    /// since the legacy bootstrap walker was retired — replication carries
    /// each delete individually and the backfill index lists them as entries.
    #[cfg(test)]
    pub fn namespace_tombstones(&self) -> Result<Vec<(String, u64)>, String> {
        let mut tombstones = Vec::new();
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_NAMESPACE_TOMBSTONES),
            IteratorMode::Start,
        );
        for item in iter {
            let (namespace_id, payload) =
                item.map_err(|error| format!("failed to iterate namespace tombstones: {error}"))?;
            let namespace_id = std::str::from_utf8(&namespace_id)
                .map_err(|error| format!("invalid namespace tombstone key: {error}"))?
                .to_owned();
            let slice: [u8; 8] = payload.as_ref().try_into().map_err(|_| {
                format!(
                    "namespace tombstone for {namespace_id} should be 8 bytes, got {}",
                    payload.len()
                )
            })?;
            tombstones.push((namespace_id, u64::from_le_bytes(slice)));
        }
        Ok(tombstones)
    }

    /// Walk the manifest keyspace in `artifact_id` order from an optional
    /// cursor. The prefix-restricted variant went out with the range-digest
    /// walker that enumerated one digest bucket at a time; every caller here
    /// walks the whole keyspace in pages.
    pub fn manifests_page(
        &self,
        after: Option<&str>,
        limit: usize,
    ) -> Result<ManifestPage, String> {
        let mut manifests = Vec::new();
        let mut next_after = None;
        let start_key = after.unwrap_or_default();
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_MANIFESTS),
            IteratorMode::From(start_key.as_bytes(), rocksdb::Direction::Forward),
        );

        for item in iter {
            let (artifact_id, payload) =
                item.map_err(|error| format!("failed to iterate manifests: {error}"))?;
            let artifact_id = std::str::from_utf8(&artifact_id)
                .map_err(|error| format!("invalid manifest key: {error}"))?;
            if after == Some(artifact_id) {
                continue;
            }
            if manifests.len() == limit {
                next_after = manifests
                    .last()
                    .map(|manifest: &ArtifactManifest| manifest.artifact_id.clone());
                break;
            }
            manifests.push(decode_manifest_record(artifact_id, &payload)?);
        }

        Ok(ManifestPage {
            manifests,
            next_after,
        })
    }

    // ---- Backfill per-entry index (`backfill/` keyspace in `key_value`) ----
    //
    // Every mutation path below maintains the index inside its own WriteBatch
    // (delete-old-row + put-new-row, the `action_cache_index` pattern). The
    // invariant is EVENTUALLY exact, not exact: the background build races
    // live deletes, and the delete paths do not hold the per-artifact write
    // lock the persist paths hold, so rows can dangle. Readers recompute the
    // expected key from the current manifest at serve time and retire rows
    // that do not match; nothing here tries to close those races.

    /// Stage the index maintenance for a manifest commit: remove the previous
    /// version's row and write the new one. The old key is derived ENTIRELY
    /// from the previous manifest — old kind and old effective version — since
    /// a record can flip inline<->segment across versions, so the guard is
    /// "old key != new key", not a version comparison.
    fn stage_backfill_index_update(
        &self,
        batch: &mut WriteBatch,
        previous: Option<&ArtifactManifest>,
        manifest: &ArtifactManifest,
    ) {
        let new_key = backfill_index_key(
            manifest_version_ms(manifest),
            backfill_record_kind(manifest),
            &manifest.artifact_id,
        );
        if let Some(previous) = previous {
            let old_key = backfill_index_key(
                manifest_version_ms(previous),
                backfill_record_kind(previous),
                &previous.artifact_id,
            );
            if old_key != new_key {
                batch.delete_cf(self.cf(ROCKSDB_CF_KEY_VALUE), old_key);
            }
        }
        batch.put_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            new_key,
            backfill_index_value(Some(manifest.size)),
        );
    }

    /// Stage the removal of a deleted manifest's index row, keyed by the
    /// manifest as it was read by the deleting path.
    fn stage_backfill_index_delete(&self, batch: &mut WriteBatch, manifest: &ArtifactManifest) {
        batch.delete_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            backfill_index_key(
                manifest_version_ms(manifest),
                backfill_record_kind(manifest),
                &manifest.artifact_id,
            ),
        );
    }

    /// Whether the index covers the pre-existing dataset. Serving is never
    /// gated on this; the backfill listing endpoint answers "index building"
    /// while it is false.
    pub fn backfill_index_built(&self) -> bool {
        self.backfill_index_built.load(Ordering::Acquire)
    }

    /// One page of the backfill index, newest-first. `after` is the raw key of
    /// the last row a previous page returned (opaque to callers); the scan
    /// resumes strictly after it. The cursor is a key position, not a
    /// snapshot: rows written or removed between pages are reflected, and the
    /// scan always terminates because keys only move forward.
    pub fn backfill_index_page(
        &self,
        after: Option<&[u8]>,
        limit: usize,
    ) -> Result<BackfillIndexPage, String> {
        let prefix = BACKFILL_IDX_PREFIX.as_bytes();
        let start = after.unwrap_or(prefix);
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            IteratorMode::From(start, rocksdb::Direction::Forward),
        );
        let mut entries = Vec::new();
        let mut last_key: Option<Vec<u8>> = None;
        let mut next_after = None;
        for item in iter {
            let (key, value) =
                item.map_err(|error| format!("failed to iterate backfill index: {error}"))?;
            if after.is_some_and(|after| key.as_ref() <= after) {
                continue;
            }
            if !key.starts_with(prefix) {
                break;
            }
            if entries.len() == limit {
                next_after = last_key.take();
                break;
            }
            entries.push(decode_backfill_index_row(&key, &value)?);
            last_key = Some(key.to_vec());
        }
        Ok(BackfillIndexPage {
            entries,
            next_after,
        })
    }

    /// Resolves one requested backfill tuple against the CURRENT manifest —
    /// the read side of the eventually-exact index contract.
    ///
    /// The requested (kind, id, version) key is recomputed from the current
    /// manifest; a requested row that no longer matches it is RETIRED
    /// (deleted), because the unlocked delete paths and the build/live
    /// race can leave rows nothing will ever delete (the
    /// `delete_stale_action_cache_rows` precedent). Retirement is what keeps a
    /// dangling row a one-time absent round-trip instead of a permanent
    /// per-pass listing tax. The stale key is pushed onto `stale_rows` rather
    /// than deleted here: each delete is a WAL-fsynced write, so the caller
    /// accumulates keys across a request and flushes them batched through
    /// [`Self::retire_backfill_index_rows`].
    ///
    /// Returns `None` when the record has no current manifest (framed absent
    /// by the caller, never an error). When a manifest exists it is the
    /// CURRENT one, so a tuple LWW-overwritten between listing and fetch
    /// resolves to the current version and current body (stamped by the
    /// caller via [`manifest_version_ms`] / [`backfill_record_kind`]).
    ///
    /// Deliberately does NOT enqueue read-path promotion: bulk backfill reads
    /// are peer catch-up, not client demand, and promoting them would rewrite
    /// cold data into the active segment wholesale.
    pub fn resolve_backfill_body(
        &self,
        requested_kind: BackfillRecordKind,
        record_id: &str,
        requested_version_ms: u64,
        stale_rows: &mut Vec<Vec<u8>>,
    ) -> Result<Option<ArtifactManifest>, String> {
        let requested_key = backfill_index_key(requested_version_ms, requested_kind, record_id);
        let manifest = self.manifest(record_id)?;
        let current_key = manifest.as_ref().map(|manifest| {
            backfill_index_key(
                manifest_version_ms(manifest),
                backfill_record_kind(manifest),
                &manifest.artifact_id,
            )
        });
        if current_key.as_deref() != Some(requested_key.as_slice()) {
            stale_rows.push(requested_key);
        }
        Ok(manifest)
    }

    /// Snapshot of the ring-fullness inputs of the marginal-trade capacity
    /// test (`backfill::window::capacity_complete`). Re-read as a pass's
    /// cursor descends: applies rotate segments, so the live count and the
    /// next evictee move underneath a running pass.
    pub(crate) fn backfill_capacity_inputs(&self) -> BackfillCapacityInputs {
        let snapshot = self.segment_state_snapshot();
        let state = &snapshot.state;
        BackfillCapacityInputs {
            segment_count: state.old.len() + state.current.len() + state.new.len(),
            ring_total_segments: self.segment_ring_limits.total_segments(),
            next_evictee_stat_ms: state
                .next_evictee()
                .map(SegmentReference::effective_max_version_ms),
        }
    }

    /// The backfill presence pre-check: whether a listed tuple is already
    /// covered locally, so listing it into the claim set (and fetching it)
    /// would be wasted work. Mirrors [`Self::artifact_apply_outcome`]
    /// semantics keyed by record id: covered = a local record whose effective
    /// version is at or above the listed one, or a local state the apply
    /// path would ignore anyway (blocking tombstone). The tombstone
    /// short-circuit is only reachable pre-purge, while a stale local
    /// manifest still exists to supply the namespace id — the listing tuple
    /// carries none. Once the purge removes the manifest this returns
    /// `Ok(false)`, so tombstone-blocked entries are re-fetched and rejected
    /// at apply time by `namespace_tombstone_blocks` (wasted work, not
    /// resurrection). An older local version is NOT covered — it is fetched
    /// and LWW-refreshed (R10). Reads only the manifest/tombstone row, like
    /// the apply-time check; eviction deletes manifests in the same batch as
    /// the bytes, so manifest presence tracks body presence.
    pub(crate) fn backfill_locally_covered(
        &self,
        kind: BackfillRecordKind,
        record_id: &str,
        version_ms: u64,
    ) -> Result<bool, String> {
        if kind == BackfillRecordKind::NamespaceTombstone {
            return Ok(self
                .namespace_tombstone_version(record_id)?
                .is_some_and(|local_version_ms| local_version_ms >= version_ms));
        }
        let Some(manifest) = self.manifest(record_id)? else {
            return Ok(false);
        };
        if manifest_version_ms(&manifest) >= version_ms {
            return Ok(true);
        }
        self.namespace_tombstone_blocks(&manifest.namespace_id, version_ms)
    }

    /// Test hook: replaces the segment ring state wholesale so tests can
    /// fabricate ring-full shapes without writing gigabytes of segments.
    #[cfg(test)]
    pub(crate) async fn install_segment_state_for_testing(
        &self,
        state: SegmentState,
    ) -> Result<(), String> {
        self.mutate_segment_state(|current| *current = state).await
    }

    /// Retires collected stale `backfill/idx/` rows in ONE durable write and
    /// drains the collector, mirroring [`Self::delete_stale_action_cache_rows`]:
    /// batching keeps a request that resolves many dangling rows to a handful
    /// of WAL fsyncs instead of one per row.
    pub(crate) fn retire_backfill_index_rows(
        &self,
        stale_rows: &mut Vec<Vec<u8>>,
    ) -> Result<(), String> {
        if stale_rows.is_empty() {
            return Ok(());
        }
        let mut batch = WriteBatch::default();
        for row in std::mem::take(stale_rows) {
            batch.delete_cf(self.cf(ROCKSDB_CF_KEY_VALUE), row);
        }
        self.write_batch_sync(batch, "backfill index retired rows")
    }

    /// Test hook: plants a raw `backfill/idx/` row so tests can fabricate the
    /// dangling-row states (build/live races, unlocked deletes) that normal
    /// write paths clean up after themselves.
    #[cfg(test)]
    pub fn insert_backfill_index_row_for_testing(
        &self,
        version_ms: u64,
        kind: BackfillRecordKind,
        record_id: &str,
        size: Option<u64>,
    ) -> Result<(), String> {
        let mut batch = WriteBatch::default();
        batch.put_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            backfill_index_key(version_ms, kind, record_id),
            backfill_index_value(size),
        );
        self.write_batch_sync(batch, "backfill index test row")
    }

    // ---- Backfill per-peer watermarks (`backfill/wm/` keyspace) ----

    /// Reads a peer's persisted backfill watermark. An unreadable row decodes
    /// to an error the caller may treat as "no watermark" — the cost is an
    /// unshallowed (wider) window, never a correctness loss.
    pub fn backfill_watermark(&self, node_url: &str) -> Result<Option<u64>, String> {
        let value = self
            .db
            .get_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                backfill_wm_key(node_url).as_bytes(),
            )
            .map_err(|error| format!("failed to read backfill watermark: {error}"))?;
        match value {
            Some(value) => {
                let (watermark_ms, _refreshed_at_ms) = decode_backfill_watermark_value(&value)?;
                Ok(Some(watermark_ms))
            }
            None => Ok(None),
        }
    }

    /// Persists a peer's watermark under a monotonic max guard: a stale write
    /// (an older pass completing after a newer one, or a completion racing
    /// peer removal) can never regress the row. `refreshed_at_ms` is the
    /// local-clock completion stamp retention GC judges the row by — written
    /// on completion only, never periodically touched.
    pub fn write_backfill_watermark(
        &self,
        node_url: &str,
        watermark_ms: u64,
        refreshed_at_ms: u64,
    ) -> Result<(), String> {
        let watermark_ms = self
            .backfill_watermark(node_url)?
            .map_or(watermark_ms, |existing| existing.max(watermark_ms));
        let mut batch = WriteBatch::default();
        batch.put_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            backfill_wm_key(node_url).as_bytes(),
            encode_backfill_watermark_value(watermark_ms, refreshed_at_ms),
        );
        self.write_batch_sync(batch, "backfill watermark")
    }

    /// Removes watermark rows whose completion-time `refreshed_at` is older
    /// than the retention by the local clock, plus rows that no longer decode.
    /// Returns how many rows were removed. A GC'd row's only cost is one
    /// unbounded-window listing re-walk on the next pass over that peer.
    pub fn gc_backfill_watermarks(&self, now_ms: u64, retention_ms: u64) -> Result<usize, String> {
        let prefix = BACKFILL_WM_PREFIX.as_bytes();
        let upper_bound = backfill_wm_prefix_upper_bound();
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            IteratorMode::From(prefix, rocksdb::Direction::Forward),
        );
        let mut batch = WriteBatch::default();
        let mut removed = 0_usize;
        for item in iter {
            let (key, value) =
                item.map_err(|error| format!("failed to iterate backfill watermarks: {error}"))?;
            if key.as_ref() >= upper_bound.as_slice() {
                break;
            }
            let expired = match decode_backfill_watermark_value(&value) {
                Ok((_watermark_ms, refreshed_at_ms)) => {
                    now_ms.saturating_sub(refreshed_at_ms) > retention_ms
                }
                Err(_) => true,
            };
            if expired {
                batch.delete_cf(self.cf(ROCKSDB_CF_KEY_VALUE), key);
                removed += 1;
            }
        }
        if removed > 0 {
            self.write_batch_sync(batch, "backfill watermark gc")?;
        }
        Ok(removed)
    }

    /// The ring's age-ordered seal-time stats, the horizon input of
    /// `backfill::window::compute_window`.
    pub(crate) fn backfill_age_ordered_stats(&self) -> Vec<u64> {
        self.segment_state_snapshot()
            .state
            .age_ordered_references()
            .iter()
            .map(|reference| reference.effective_max_version_ms())
            .collect()
    }

    /// One-off background build of the backfill index over a pre-existing
    /// dataset, run at startup when `backfill/meta/build_complete` is absent.
    /// Returns whether a build ran.
    ///
    /// Always starts from a range-delete over `backfill/idx/`: a rebuild
    /// triggered by rollback-window staleness must also drop rows for entries
    /// deleted while maintenance was absent, and re-running from scratch after
    /// a crash mid-build is what makes the build idempotent (keys are
    /// deterministic, so a re-scan converges on the same rows). Live
    /// maintenance runs concurrently; a manifest deleted between a chunk's
    /// read and its write can leave a dangling row, which readers retire
    /// (eventually-exact invariant).
    pub fn run_backfill_index_build(&self) -> Result<bool, String> {
        if self.backfill_index_built() {
            return Ok(false);
        }
        let started = std::time::Instant::now();
        self.db
            .delete_range_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                BACKFILL_IDX_PREFIX.as_bytes(),
                &backfill_index_prefix_upper_bound(),
            )
            .map_err(|error| format!("failed to clear backfill index keyspace: {error}"))?;

        let mut indexed = 0_usize;
        let mut cursor: Option<Vec<u8>> = None;
        loop {
            let (rows, next) = self.backfill_build_manifests_chunk(cursor.as_deref())?;
            indexed += rows;
            match next {
                Some(next) => cursor = Some(next),
                None => break,
            }
        }
        let mut cursor: Option<Vec<u8>> = None;
        loop {
            let (rows, next) = self.backfill_build_tombstones_chunk(cursor.as_deref())?;
            indexed += rows;
            match next {
                Some(next) => cursor = Some(next),
                None => break,
            }
        }

        // Stamp completion and a fresh maintenance sequence together, so a
        // crash immediately after the build still has a stamp to check the
        // next boot's sequence gap against. A full build also resets the
        // crash-forgiveness ledger: everything previously forgiven is now
        // indexed.
        let mut batch = WriteBatch::default();
        batch.put_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            backfill_meta_key(BACKFILL_META_BUILD_COMPLETE).as_bytes(),
            [],
        );
        batch.put_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            backfill_meta_key(BACKFILL_META_LAST_MAINTAINED_SEQ).as_bytes(),
            encode_backfill_seq_stamp(self.db.latest_sequence_number(), false),
        );
        batch.delete_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            backfill_meta_key(BACKFILL_META_FORGIVEN_SEQS).as_bytes(),
        );
        self.write_batch_sync(batch, "backfill index build completion")?;
        self.backfill_index_built.store(true, Ordering::Release);
        tracing::info!(
            indexed,
            elapsed_ms = started.elapsed().as_millis() as u64,
            "backfill index build complete"
        );
        Ok(true)
    }

    /// One bounded chunk of the build's manifest scan, resumed by key cursor.
    /// The iterator lives only for this chunk so the scan never pins a RocksDB
    /// snapshot across the whole (potentially hours-long) build.
    fn backfill_build_manifests_chunk(
        &self,
        after: Option<&[u8]>,
    ) -> Result<(usize, Option<Vec<u8>>), String> {
        let mode = after.map_or(IteratorMode::Start, |after| {
            IteratorMode::From(after, rocksdb::Direction::Forward)
        });
        let iter = self.db.iterator_cf(self.cf(ROCKSDB_CF_MANIFESTS), mode);
        let mut batch = WriteBatch::default();
        let mut rows = 0_usize;
        let mut last_key: Option<Vec<u8>> = None;
        for item in iter {
            let (key, payload) =
                item.map_err(|error| format!("failed to iterate manifests: {error}"))?;
            if after.is_some_and(|after| key.as_ref() <= after) {
                continue;
            }
            let artifact_id = std::str::from_utf8(&key)
                .map_err(|error| format!("invalid manifest key: {error}"))?;
            let manifest = decode_manifest_record(artifact_id, &payload)?;
            batch.put_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                backfill_index_key(
                    manifest_version_ms(&manifest),
                    backfill_record_kind(&manifest),
                    artifact_id,
                ),
                backfill_index_value(Some(manifest.size)),
            );
            rows += 1;
            last_key = Some(key.to_vec());
            if rows == BACKFILL_INDEX_BUILD_CHUNK_ROWS {
                break;
            }
        }
        // Plain (non-sync) write: the build is idempotent, so losing a chunk
        // to a crash only means re-scanning it.
        if rows > 0 {
            self.db
                .write(batch)
                .map_err(|error| format!("failed to write backfill index chunk: {error}"))?;
        }
        self.failpoints
            .hit_blocking(FailpointName::AfterBackfillIndexBuildChunk)?;
        let next = (rows == BACKFILL_INDEX_BUILD_CHUNK_ROWS)
            .then_some(last_key)
            .flatten();
        Ok((rows, next))
    }

    /// One bounded chunk of the build's namespace-tombstone scan.
    fn backfill_build_tombstones_chunk(
        &self,
        after: Option<&[u8]>,
    ) -> Result<(usize, Option<Vec<u8>>), String> {
        let mode = after.map_or(IteratorMode::Start, |after| {
            IteratorMode::From(after, rocksdb::Direction::Forward)
        });
        let iter = self
            .db
            .iterator_cf(self.cf(ROCKSDB_CF_NAMESPACE_TOMBSTONES), mode);
        let mut batch = WriteBatch::default();
        let mut rows = 0_usize;
        let mut last_key: Option<Vec<u8>> = None;
        for item in iter {
            let (key, payload) =
                item.map_err(|error| format!("failed to iterate namespace tombstones: {error}"))?;
            if after.is_some_and(|after| key.as_ref() <= after) {
                continue;
            }
            let namespace_id = std::str::from_utf8(&key)
                .map_err(|error| format!("invalid namespace tombstone key: {error}"))?;
            if payload.len() != 8 {
                return Err(format!(
                    "namespace tombstone for {namespace_id} should be 8 bytes, got {}",
                    payload.len()
                ));
            }
            let version_ms = u64::from_le_bytes(payload.as_ref().try_into().expect("checked len"));
            batch.put_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                backfill_index_key(
                    version_ms,
                    BackfillRecordKind::NamespaceTombstone,
                    namespace_id,
                ),
                backfill_index_value(None),
            );
            rows += 1;
            last_key = Some(key.to_vec());
            if rows == BACKFILL_INDEX_BUILD_CHUNK_ROWS {
                break;
            }
        }
        if rows > 0 {
            self.db
                .write(batch)
                .map_err(|error| format!("failed to write backfill index chunk: {error}"))?;
        }
        self.failpoints
            .hit_blocking(FailpointName::AfterBackfillIndexBuildChunk)?;
        let next = (rows == BACKFILL_INDEX_BUILD_CHUNK_ROWS)
            .then_some(last_key)
            .flatten();
        Ok((rows, next))
    }

    /// Periodic maintenance stamp: records the DB's latest sequence number so
    /// the next boot can bound how many writes happened after this binary
    /// stopped maintaining the index.
    pub fn stamp_backfill_maintained_seq(&self) -> Result<(), String> {
        self.db
            .put_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                backfill_meta_key(BACKFILL_META_LAST_MAINTAINED_SEQ).as_bytes(),
                encode_backfill_seq_stamp(self.db.latest_sequence_number(), false),
            )
            .map_err(|error| format!("failed to stamp backfill maintenance sequence: {error}"))
    }

    /// Synchronous clean-shutdown stamp. After it, ANY sequence gap observed
    /// at the next boot means a foreign (index-unaware) binary wrote in
    /// between — the common rollback shape (drain, roll back, roll forward) —
    /// and forces a rebuild. The stamp write itself consumes a sequence
    /// number, so converge on an exact stamp by re-reading; the DB should be
    /// quiescent post-drain, and if a straggling background write keeps racing
    /// us, the leftover inexact stamp only costs a spurious (safe) rebuild.
    pub fn stamp_backfill_maintained_seq_clean_shutdown(&self) -> Result<(), String> {
        for _ in 0..8 {
            let before = self.db.latest_sequence_number();
            let mut batch = WriteBatch::default();
            batch.put_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                backfill_meta_key(BACKFILL_META_LAST_MAINTAINED_SEQ).as_bytes(),
                encode_backfill_seq_stamp(before, true),
            );
            self.write_batch_sync(batch, "backfill clean-shutdown stamp")?;
            if self.db.latest_sequence_number() == before + 1 {
                return Ok(());
            }
        }
        Ok(())
    }

    /// The cumulative crash-forgiveness ledger (`backfill/meta/forgiven_seqs`):
    /// the sum of sub-slack sequence gaps forgiven across unclean-shutdown
    /// boots. Without it, every crash→foreign-window→reboot cycle would get a
    /// fresh slack allowance and the cumulative undetected loss would be
    /// unbounded.
    fn backfill_forgiven_seqs(&self) -> Result<u64, String> {
        Ok(self
            .db
            .get_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                backfill_meta_key(BACKFILL_META_FORGIVEN_SEQS).as_bytes(),
            )
            .map_err(|error| format!("failed to read backfill forgiveness ledger: {error}"))?
            .as_deref()
            .and_then(|bytes| <[u8; 8]>::try_from(bytes).ok())
            .map(u64::from_le_bytes)
            .unwrap_or(0))
    }

    fn write_backfill_forgiven_seqs(&self, forgiven_seqs: u64) -> Result<(), String> {
        self.db
            .put_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                backfill_meta_key(BACKFILL_META_FORGIVEN_SEQS).as_bytes(),
                forgiven_seqs.to_le_bytes(),
            )
            .map_err(|error| format!("failed to write backfill forgiveness ledger: {error}"))
    }

    fn clear_backfill_forgiven_seqs(&self) -> Result<(), String> {
        self.db
            .delete_cf(
                self.cf(ROCKSDB_CF_KEY_VALUE),
                backfill_meta_key(BACKFILL_META_FORGIVEN_SEQS).as_bytes(),
            )
            .map_err(|error| format!("failed to clear backfill forgiveness ledger: {error}"))
    }

    /// Startup half of rollback-window staleness detection (see the stamp
    /// writers above). Runs once in `Store::open`, before any traffic. When a
    /// completed index cannot be trusted — a sequence gap after a
    /// clean-shutdown stamp, a beyond-slack gap after an unclean one, a
    /// missing stamp, or a cumulative forgiven total beyond the slack — the
    /// `build_complete` marker is cleared so the startup build task rebuilds.
    /// A crash followed by a foreign window smaller than the slack is the
    /// documented undetected band, but only until the forgiveness ledger
    /// (`backfill/meta/forgiven_seqs`) fills: forgiven gaps accumulate across
    /// unclean boots and force a rebuild once their sum exceeds the slack, so
    /// the total undetected exposure is bounded by one slack's worth of
    /// sequence numbers rather than N crashes × slack.
    fn init_backfill_index_state(&self) -> Result<(), String> {
        let build_complete_key = backfill_meta_key(BACKFILL_META_BUILD_COMPLETE);
        let build_complete = self
            .db
            .get_cf(self.cf(ROCKSDB_CF_KEY_VALUE), build_complete_key.as_bytes())
            .map_err(|error| format!("failed to read backfill build marker: {error}"))?
            .is_some();
        if build_complete {
            let stamp = self
                .db
                .get_cf(
                    self.cf(ROCKSDB_CF_KEY_VALUE),
                    backfill_meta_key(BACKFILL_META_LAST_MAINTAINED_SEQ).as_bytes(),
                )
                .map_err(|error| format!("failed to read backfill maintenance stamp: {error}"))?
                .as_deref()
                .and_then(decode_backfill_seq_stamp);
            let latest = self.db.latest_sequence_number();
            let rebuild = match stamp {
                None => {
                    tracing::warn!(
                        "backfill index is marked complete but has no maintenance stamp; rebuilding"
                    );
                    true
                }
                Some((stamped_seq, clean_shutdown)) => {
                    // The stamp write itself consumed one sequence number
                    // after `stamped_seq` was read.
                    let gap = latest.saturating_sub(stamped_seq.saturating_add(1));
                    let mut rebuild = backfill_rebuild_required(
                        clean_shutdown,
                        gap,
                        BACKFILL_SEQ_STAMP_SLACK_SEQS,
                    );
                    if rebuild {
                        tracing::warn!(
                            gap,
                            clean_shutdown,
                            "backfill index missed writes from an index-unaware binary; rebuilding"
                        );
                    } else if clean_shutdown {
                        // A gap-free clean boot proves no foreign window ran,
                        // so the crash-forgiveness ledger resets (any clean-
                        // shutdown gap already rebuilds above).
                        self.clear_backfill_forgiven_seqs()?;
                    } else if gap > 0 {
                        // A sub-slack gap after a crash is individually
                        // forgiven, but repeated crash→foreign-window→reboot
                        // cycles must not each earn a fresh allowance: the
                        // forgiven gaps accumulate in the persisted ledger
                        // and force a rebuild once their sum exceeds the
                        // same slack bound.
                        let forgiven_seqs = self.backfill_forgiven_seqs()?.saturating_add(gap);
                        if forgiven_seqs > BACKFILL_SEQ_STAMP_SLACK_SEQS {
                            rebuild = true;
                            tracing::warn!(
                                gap,
                                forgiven_seqs,
                                "cumulative forgiven sequence gaps across unclean shutdowns exceed the staleness slack; rebuilding"
                            );
                        } else {
                            self.write_backfill_forgiven_seqs(forgiven_seqs)?;
                        }
                    }
                    rebuild
                }
            };
            if rebuild {
                self.db
                    .delete_cf(self.cf(ROCKSDB_CF_KEY_VALUE), build_complete_key.as_bytes())
                    .map_err(|error| format!("failed to clear backfill build marker: {error}"))?;
            } else {
                self.backfill_index_built.store(true, Ordering::Release);
            }
        }
        // Overwrite any leftover clean-shutdown stamp right away: writes this
        // binary makes before its first periodic stamp ARE maintained, and
        // must not read as a foreign gap if we crash before then.
        self.stamp_backfill_maintained_seq()
    }

    pub fn delete_outbox_message(&self, key: &[u8]) -> Result<(), String> {
        self.db
            .delete_cf(self.cf(ROCKSDB_CF_OUTBOX), key)
            .map_err(|error| format!("failed to delete outbox entry: {error}"))?;
        release_atomic_slots(&self.outbox_depth, 1);
        if is_bulk_outbox_key(key) {
            release_atomic_slots(&self.outbox_bulk_depth, 1);
        }
        Ok(())
    }

    #[cfg(test)]
    pub fn artifact_version_is_current(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        version_ms: u64,
    ) -> Result<bool, String> {
        Ok(
            self.artifact_apply_outcome(producer, namespace_id, key, version_ms)?
                == ArtifactApplyOutcome::Applied,
        )
    }

    pub fn artifact_apply_outcome(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        version_ms: u64,
    ) -> Result<ArtifactApplyOutcome, String> {
        let artifact_id = artifact_storage_id(producer, &self.tenant_id, namespace_id, key);
        if self.namespace_tombstone_blocks(namespace_id, version_ms)? {
            return Ok(ArtifactApplyOutcome::IgnoredTombstone);
        }

        Ok(self
            .manifest_from_db(&artifact_id)?
            .map(|manifest| {
                let existing_version_ms = manifest_version_ms(&manifest);
                if existing_version_ms < version_ms {
                    ArtifactApplyOutcome::Applied
                } else if versions_converged(existing_version_ms, version_ms) {
                    ArtifactApplyOutcome::IgnoredEqual
                } else {
                    ArtifactApplyOutcome::IgnoredStale
                }
            })
            .unwrap_or(ArtifactApplyOutcome::Applied))
    }

    pub(crate) async fn hit_failpoint(&self, name: FailpointName) -> Result<(), String> {
        self.failpoints.hit(name).await
    }

    #[cfg(test)]
    pub(crate) fn failpoints(&self) -> Arc<FailpointSet> {
        self.failpoints.clone()
    }

    fn cf(&self, name: &str) -> &ColumnFamily {
        self.db
            .cf_handle(name)
            .expect("missing RocksDB column family")
    }

    /// Returns how many of the appended messages went to the bulk lane.
    fn append_artifact_replication_messages(
        &self,
        batch: &mut WriteBatch,
        manifest: &ArtifactManifest,
        replication_targets: &[String],
        trunk: Option<&str>,
    ) -> Result<usize, String> {
        let mut bulk = 0_usize;
        for target in replication_targets {
            bulk += usize::from(self.append_outbox_message(
                batch,
                OutboxMessage {
                    target: target.clone(),
                    operation: ReplicationOperation::UpsertArtifact {
                        producer: manifest.producer,
                        namespace_id: manifest.namespace_id.clone(),
                        key: manifest.key.clone(),
                        content_type: manifest.content_type.clone(),
                        artifact_id: manifest.artifact_id.clone(),
                        inline: manifest.inline,
                        version_ms: manifest.version_ms,
                        // The tag as resolved here, so the peer does not have to
                        // infer it from a request header it never saw.
                        branch: manifest.branch.clone(),
                        trunk: trunk.map(str::to_owned),
                    },
                },
            )?);
        }
        Ok(bulk)
    }

    /// Returns how many of the appended messages went to the bulk lane. Namespace
    /// deletes are metadata-lane by construction, so this is always zero; it is
    /// reported anyway so the lane stays derived from the key rather than assumed.
    fn append_namespace_delete_messages(
        &self,
        batch: &mut WriteBatch,
        namespace_id: &str,
        version_ms: u64,
        replication_targets: &[String],
    ) -> Result<usize, String> {
        let mut bulk = 0_usize;
        for target in replication_targets {
            bulk += usize::from(self.append_outbox_message(
                batch,
                OutboxMessage {
                    target: target.clone(),
                    operation: ReplicationOperation::DeleteNamespace {
                        namespace_id: namespace_id.to_owned(),
                        version_ms,
                    },
                },
            )?);
        }
        Ok(bulk)
    }

    /// Returns whether the message went to the bulk lane, so the caller can
    /// tally it for `OutboxReservation::commit`.
    fn append_outbox_message(
        &self,
        batch: &mut WriteBatch,
        message: OutboxMessage,
    ) -> Result<bool, String> {
        let key = outbox_message_key(&message);
        let value = serde_json::to_vec(&message)
            .map_err(|error| format!("failed to encode outbox message: {error}"))?;
        batch.put_cf(self.cf(ROCKSDB_CF_OUTBOX), key.as_bytes(), value);
        Ok(is_bulk_outbox_key(key.as_bytes()))
    }

    fn write_batch_sync(&self, batch: WriteBatch, label: &str) -> Result<(), String> {
        self.write_batch_with_durability(batch, label, ApplyDurability::Sync)
    }

    fn write_batch_with_durability(
        &self,
        batch: WriteBatch,
        label: &str,
        durability: ApplyDurability,
    ) -> Result<(), String> {
        let mut write_options = WriteOptions::default();
        match durability {
            ApplyDurability::Sync => {
                write_options.set_sync(true);
                self.wal_sync_write_count.fetch_add(1, Ordering::Relaxed);
            }
            ApplyDurability::DeferredBatch => {
                write_options.set_sync(false);
                self.wal_deferred_write_count
                    .fetch_add(1, Ordering::Relaxed);
            }
        }
        #[cfg(test)]
        if let Some(observer) = self
            .write_thread_observer
            .lock()
            .expect("write observer lock should not be poisoned")
            .clone()
        {
            observer(std::thread::current().id());
        }
        self.db
            .write_opt(batch, &write_options)
            .map_err(|error| format!("failed to write {label}: {error}"))
    }

    /// Request-path sibling of [`Self::write_batch_with_durability`] that
    /// commits on the blocking pool.
    ///
    /// Getting segment eviction off the worker threads is not by itself enough
    /// (#12587): `allow_stall = true` blocks *whichever* thread is inside
    /// RocksDB, so once the pool is saturated every writer that still runs
    /// inline parks a worker, and enough concurrent writers park the runtime
    /// even though no eviction is involved.
    ///
    /// The callers that matter are the ones already `async` — the artifact and
    /// action-cache write paths, promotion, and multipart — because those are
    /// what run at request concurrency. The remaining callers of the sync
    /// funnel are backfill, GC and startup work: low-concurrency, off the
    /// serving path, and converting them would mean making a chain of sync
    /// functions async for no change in the failure this addresses.
    async fn write_batch_with_durability_off_runtime(
        &self,
        batch: WriteBatch,
        label: &'static str,
        durability: ApplyDurability,
    ) -> Result<(), String> {
        // `WriteBatch` is not `Send`, so the batch crosses as its serialized
        // representation — the same encoding RocksDB writes to the WAL, with
        // column-family targeting preserved. See `commit_eviction_chunk`.
        let payload = batch.data().to_vec();
        let db = Arc::clone(&self.db);
        let mut write_options = WriteOptions::default();
        match durability {
            ApplyDurability::Sync => {
                write_options.set_sync(true);
                self.wal_sync_write_count.fetch_add(1, Ordering::Relaxed);
            }
            ApplyDurability::DeferredBatch => {
                write_options.set_sync(false);
                self.wal_deferred_write_count
                    .fetch_add(1, Ordering::Relaxed);
            }
        }
        #[cfg(test)]
        let observer = self
            .write_thread_observer
            .lock()
            .expect("write observer lock should not be poisoned")
            .clone();
        tokio::task::spawn_blocking(move || {
            #[cfg(test)]
            if let Some(observer) = observer {
                observer(std::thread::current().id());
            }
            db.write_opt(WriteBatch::from_data(&payload), &write_options)
        })
        .await
        .map_err(|error| format!("{label} write task failed: {error}"))?
        .map_err(|error| format!("failed to write {label}: {error}"))
    }

    /// The deferred batch's phase-4 durability barrier: one synced WAL flush
    /// makes every WAL-only commit before it durable.
    fn flush_wal_barrier(&self) -> Result<(), String> {
        self.wal_flush_count.fetch_add(1, Ordering::Relaxed);
        self.db
            .flush_wal(true)
            .map_err(|error| format!("failed to flush WAL: {error}"))
    }

    /// (sync WriteBatch commits, deferred WriteBatch commits, WAL flushes) —
    /// the durability-accounting counters tests pin path semantics with.
    #[cfg(test)]
    pub(crate) fn wal_write_counts(&self) -> (u64, u64, u64) {
        (
            self.wal_sync_write_count.load(Ordering::Relaxed),
            self.wal_deferred_write_count.load(Ordering::Relaxed),
            self.wal_flush_count.load(Ordering::Relaxed),
        )
    }

    fn namespace_tombstone_version(&self, namespace_id: &str) -> Result<Option<u64>, String> {
        let Some(bytes) = self
            .db
            .get_cf(
                self.cf(ROCKSDB_CF_NAMESPACE_TOMBSTONES),
                namespace_id.as_bytes(),
            )
            .map_err(|error| format!("failed to read namespace tombstone: {error}"))?
        else {
            return Ok(None);
        };

        if bytes.len() != 8 {
            return Err(format!(
                "namespace tombstone for {namespace_id} should be 8 bytes, got {}",
                bytes.len()
            ));
        }
        let mut slice = [0_u8; 8];
        slice.copy_from_slice(bytes.as_ref());
        Ok(Some(u64::from_le_bytes(slice)))
    }

    fn namespace_tombstone_blocks(
        &self,
        namespace_id: &str,
        version_ms: u64,
    ) -> Result<bool, String> {
        Ok(self
            .namespace_tombstone_version(namespace_id)?
            .map(|tombstone_version_ms| version_ms == 0 || tombstone_version_ms >= version_ms)
            .unwrap_or(false))
    }

    fn count_cf_entries(&self, name: &str) -> Result<usize, String> {
        match self
            .db
            .property_int_value_cf(self.cf(name), "rocksdb.estimate-num-keys")
        {
            Ok(Some(count)) => Ok(count as usize),
            Ok(None) => {
                let iter = self.db.iterator_cf(self.cf(name), IteratorMode::Start);
                let mut count = 0_usize;
                for item in iter {
                    item.map_err(|error| format!("failed to iterate {name}: {error}"))?;
                    count += 1;
                }
                Ok(count)
            }
            Err(error) => Err(format!("failed to inspect {name} size: {error}")),
        }
    }

    pub fn trim_manifest_cache_to(&self, target_bytes: usize, reason: &str) -> usize {
        let mut cache = self
            .manifest_cache
            .lock()
            .expect("manifest cache lock poisoned");
        let evicted = cache.trim_to(target_bytes);
        self.record_manifest_cache_state(&cache);
        if evicted > 0 {
            self.io
                .metrics()
                .record_manifest_cache_evictions(reason, evicted as u64);
        }
        evicted
    }

    pub fn trim_existence_cache_to(&self, target_entries: usize) -> usize {
        self.existence_cache.trim_to(target_entries)
    }

    fn manifest_from_db(&self, artifact_id: &str) -> Result<Option<ArtifactManifest>, String> {
        self.db
            .get_cf(self.cf(ROCKSDB_CF_MANIFESTS), artifact_id.as_bytes())
            .map_err(|error| format!("failed to read manifest from RocksDB: {error}"))?
            .map(|bytes| decode_manifest_record(artifact_id, &bytes))
            .transpose()
    }

    fn manifest_cache_get(&self, artifact_id: &str) -> Option<ArtifactManifest> {
        let mut cache = self
            .manifest_cache
            .lock()
            .expect("manifest cache lock poisoned");
        cache.get(artifact_id)
    }

    fn maybe_cache_manifest(&self, manifest: ArtifactManifest) {
        if !self.memory.allow_manifest_cache_admission() {
            self.io
                .metrics()
                .record_manifest_cache_admission("pressure_skipped");
            self.io
                .metrics()
                .record_memory_action("manifest_cache_skip");
            return;
        }

        let mut cache = self
            .manifest_cache
            .lock()
            .expect("manifest cache lock poisoned");
        match cache.insert(manifest) {
            ManifestCacheInsertResult::Admitted { evicted } => {
                self.io
                    .metrics()
                    .record_manifest_cache_admission("admitted");
                if evicted > 0 {
                    self.io
                        .metrics()
                        .record_manifest_cache_evictions("capacity", evicted as u64);
                }
            }
            ManifestCacheInsertResult::Updated { evicted } => {
                self.io.metrics().record_manifest_cache_admission("updated");
                if evicted > 0 {
                    self.io
                        .metrics()
                        .record_manifest_cache_evictions("capacity", evicted as u64);
                }
            }
            ManifestCacheInsertResult::Oversized => self
                .io
                .metrics()
                .record_manifest_cache_admission("oversized"),
        }
        self.record_manifest_cache_state(&cache);
    }

    fn remove_manifest_cache_keys(&self, artifact_ids: &[String]) {
        if artifact_ids.is_empty() {
            return;
        }

        let mut cache = self
            .manifest_cache
            .lock()
            .expect("manifest cache lock poisoned");
        cache.remove_many(artifact_ids);
        self.record_manifest_cache_state(&cache);
        drop(cache);

        self.existence_cache.remove_many(artifact_ids);
    }

    fn record_manifest_cache_state(&self, cache: &ManifestCache) {
        self.io.metrics().update_manifest_index_entries(cache.len());
        self.io
            .metrics()
            .update_manifest_cache_bytes(cache.total_bytes());
    }

    fn existence_cache_contains(&self, artifact_id: &str) -> bool {
        self.existence_cache.contains(artifact_id)
    }

    fn note_artifact_exists(&self, artifact_id: &str) {
        self.existence_cache.insert(artifact_id);
    }

    /// Total and bulk-lane outbox depth in one pass, for seeding both counters
    /// at open. Runs once per process, so it iterates rather than keeping a
    /// second persisted tally that could disagree with the entries on disk.
    fn count_outbox_entries_exact(&self) -> Result<(usize, usize), String> {
        let iter = self
            .db
            .iterator_cf(self.cf(ROCKSDB_CF_OUTBOX), IteratorMode::Start);
        let mut total = 0_usize;
        let mut bulk = 0_usize;
        for item in iter {
            let (key, _) =
                item.map_err(|error| format!("failed to iterate {ROCKSDB_CF_OUTBOX}: {error}"))?;
            total = total.saturating_add(1);
            if is_bulk_outbox_key(&key) {
                bulk = bulk.saturating_add(1);
            }
        }
        Ok((total, bulk))
    }

    #[cfg(test)]
    fn count_cf_entries_exact(&self, name: &str) -> Result<usize, String> {
        let iter = self.db.iterator_cf(self.cf(name), IteratorMode::Start);
        let mut count = 0_usize;
        for item in iter {
            item.map_err(|error| format!("failed to iterate {name}: {error}"))?;
            count = count.saturating_add(1);
        }
        Ok(count)
    }

    fn delete_invalid_multipart_records(
        &self,
        invalid_keys: &mut Vec<Vec<u8>>,
    ) -> Result<(), String> {
        if invalid_keys.is_empty() {
            return Ok(());
        }
        let mut batch = WriteBatch::default();
        for key in std::mem::take(invalid_keys) {
            batch.delete_cf(self.cf(ROCKSDB_CF_MULTIPART_UPLOADS), key);
        }
        self.write_batch_sync(batch, "invalid multipart upload cleanup")
    }

    fn reconcile_multipart_storage(&self) -> Result<(usize, u64), String> {
        let multipart_root = self.data_dir.join("multipart");
        let iter = self
            .db
            .iterator_cf(self.cf(ROCKSDB_CF_MULTIPART_UPLOADS), IteratorMode::Start);
        let mut uploads = 0_usize;
        let mut stored_bytes = 0_u64;
        let mut invalid_keys = Vec::with_capacity(MULTIPART_RECONCILE_DELETE_BATCH);
        for item in iter {
            let (key, value) =
                item.map_err(|error| format!("failed to iterate multipart uploads: {error}"))?;
            let upload = if value.len() > MAX_MULTIPART_RECORD_BYTES {
                tracing::warn!(
                    record_bytes = value.len(),
                    max_record_bytes = MAX_MULTIPART_RECORD_BYTES,
                    "discarding an oversized multipart upload record during startup"
                );
                None
            } else {
                match serde_json::from_slice::<MultipartUpload>(&value) {
                    Ok(upload) if upload.upload_id.as_bytes() == key.as_ref() => Some(upload),
                    Ok(upload) => {
                        tracing::warn!(
                            record_upload_id = upload.upload_id,
                            "discarding a multipart record whose key does not match its upload id"
                        );
                        None
                    }
                    Err(error) => {
                        tracing::warn!(
                            "discarding an undecodable multipart upload record during startup: {error}"
                        );
                        None
                    }
                }
            };
            let Some(upload) = upload else {
                invalid_keys.push(key.to_vec());
                if invalid_keys.len() == MULTIPART_RECONCILE_DELETE_BATCH {
                    self.delete_invalid_multipart_records(&mut invalid_keys)?;
                }
                continue;
            };

            let upload_dir = multipart_root.join(&upload.upload_id);
            let mut referenced_paths = HashSet::with_capacity(upload.parts.len());
            let valid = upload.parts.len() <= MAX_MULTIPART_PARTS
                && upload.parts.iter().all(|(part_number, part)| {
                    if *part_number == 0 || *part_number as usize > MAX_MULTIPART_PARTS {
                        return false;
                    }
                    let path = PathBuf::from(&part.path);
                    if path.parent() != Some(upload_dir.as_path())
                        || !referenced_paths.insert(path.clone())
                    {
                        return false;
                    }
                    std::fs::metadata(path)
                        .map(|metadata| metadata.is_file() && metadata.len() == part.size)
                        .unwrap_or(false)
                });
            if !valid {
                tracing::warn!(
                    upload_id = upload.upload_id,
                    "discarding an incomplete multipart upload with missing or mismatched part files"
                );
                invalid_keys.push(key.to_vec());
                if invalid_keys.len() == MULTIPART_RECONCILE_DELETE_BATCH {
                    self.delete_invalid_multipart_records(&mut invalid_keys)?;
                }
                continue;
            }

            uploads = uploads.saturating_add(1);
            stored_bytes = stored_bytes
                .saturating_add(upload.parts.values().map(|part| part.size).sum::<u64>());

            match std::fs::read_dir(&upload_dir) {
                Ok(entries) => {
                    for entry in entries {
                        let entry = entry.map_err(|error| {
                            format!(
                                "failed to enumerate multipart upload {}: {error}",
                                upload.upload_id
                            )
                        })?;
                        let path = entry.path();
                        if referenced_paths.contains(&path) {
                            continue;
                        }
                        let reclaimed = entry
                            .file_type()
                            .map(|kind| {
                                if kind.is_dir() {
                                    std::fs::remove_dir_all(&path)
                                } else {
                                    std::fs::remove_file(&path)
                                }
                            })
                            .unwrap_or_else(Err);
                        if let Err(error) = reclaimed {
                            let retained = try_path_size_bytes(&path).map_err(|accounting_error| {
                                format!(
                                    "failed to account unreclaimed multipart path {} after {error}: {accounting_error}",
                                    path.display()
                                )
                            })?;
                            stored_bytes = stored_bytes.saturating_add(retained);
                            tracing::warn!(
                                path = %path.display(),
                                retained,
                                "failed to reclaim an unreferenced multipart file during startup: {error}"
                            );
                        }
                    }
                }
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => {
                    return Err(format!(
                        "failed to enumerate multipart upload {}: {error}",
                        upload.upload_id
                    ));
                }
            }
        }
        self.delete_invalid_multipart_records(&mut invalid_keys)?;

        match std::fs::read_dir(&multipart_root) {
            Ok(entries) => {
                for entry in entries {
                    let entry = entry.map_err(|error| {
                        format!("failed to enumerate multipart storage: {error}")
                    })?;
                    let upload_id = entry.file_name().to_string_lossy().into_owned();
                    let has_record = self
                        .db
                        .get_cf(self.cf(ROCKSDB_CF_MULTIPART_UPLOADS), upload_id.as_bytes())
                        .map_err(|error| {
                            format!("failed to inspect multipart upload {upload_id}: {error}")
                        })?
                        .is_some();
                    if has_record {
                        continue;
                    }
                    let path = entry.path();
                    let reclaimed = entry
                        .file_type()
                        .map(|kind| {
                            if kind.is_dir() {
                                std::fs::remove_dir_all(&path)
                            } else {
                                std::fs::remove_file(&path)
                            }
                        })
                        .unwrap_or_else(Err);
                    if let Err(error) = reclaimed {
                        let retained = try_path_size_bytes(&path).map_err(|accounting_error| {
                            format!(
                                "failed to account unreclaimed orphaned multipart path {} after {error}: {accounting_error}",
                                path.display()
                            )
                        })?;
                        stored_bytes = stored_bytes.saturating_add(retained);
                        tracing::warn!(
                            path = %path.display(),
                            retained,
                            "failed to reclaim an orphaned multipart path during startup: {error}"
                        );
                    }
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(format!(
                    "failed to enumerate multipart storage {}: {error}",
                    multipart_root.display()
                ));
            }
        }
        Ok((uploads, stored_bytes))
    }

    #[cfg(test)]
    fn multipart_usage(&self) -> (usize, u64) {
        (
            self.multipart_uploads.load(Ordering::Acquire),
            self.multipart_stored_bytes.load(Ordering::Acquire),
        )
    }
}

fn release_atomic_slots(depth: &AtomicUsize, slots: usize) {
    let _ = depth.fetch_update(Ordering::AcqRel, Ordering::Acquire, |current| {
        Some(current.saturating_sub(slots))
    });
}

async fn path_size_bytes_on_blocking_pool(path: PathBuf) -> Result<u64, String> {
    tokio::task::spawn_blocking(move || try_path_size_bytes(&path))
        .await
        .map_err(|error| format!("filesystem accounting task failed: {error}"))?
        .map_err(|error| error.to_string())
}

fn release_atomic_bytes(bytes: &AtomicU64, released: u64) {
    let _ = bytes.fetch_update(Ordering::AcqRel, Ordering::Acquire, |current| {
        Some(current.saturating_sub(released))
    });
}

fn estimated_manifest_working_bytes(manifest: &ArtifactManifest) -> usize {
    let strings = manifest
        .artifact_id
        .len()
        .saturating_add(manifest.namespace_id.len())
        .saturating_add(manifest.key.len())
        .saturating_add(manifest.content_type.len())
        .saturating_add(manifest.blob_path.as_ref().map_or(0, String::len))
        .saturating_add(manifest.segment_id.as_ref().map_or(0, String::len));
    std::mem::size_of::<ArtifactManifest>()
        .saturating_add(strings)
        .saturating_mul(2)
        .saturating_add(256)
}

fn next_total_size(parts: &BTreeMap<u32, MultipartPart>, part_number: u32, size: u64) -> u64 {
    let current_total: u64 = parts.values().map(|part| part.size).sum();
    let replaced_size = parts.get(&part_number).map(|part| part.size).unwrap_or(0);
    current_total - replaced_size + size
}

fn validate_total_size(next_total: u64, max_total: u64) -> Result<(), MultipartError> {
    if next_total > max_total {
        Err(MultipartError::TotalSizeExceeded)
    } else {
        Ok(())
    }
}

/// Least-recently-used ordering shared by the in-memory caches. It mirrors the
/// owning cache's keys in a map from a monotonic access counter to key, so the
/// least-recently-used entry is `pop_lru()` in O(log n) instead of the O(n)
/// scan of the whole cache that eviction otherwise runs on every insert. Each
/// cache entry stores the order returned by `touch` and passes it back on the
/// next touch or removal so the mirror stays in sync with the entry map.
struct AccessOrder {
    order: BTreeMap<u64, String>,
    next: u64,
}

impl AccessOrder {
    fn new() -> Self {
        Self {
            order: BTreeMap::new(),
            next: 0,
        }
    }

    /// Assigns a fresh access order to `key`, dropping its previous order (from
    /// an earlier touch or insert) when supplied. Returns the new order to
    /// store on the entry.
    fn touch(&mut self, key: &str, previous: Option<u64>) -> u64 {
        if let Some(previous) = previous {
            self.order.remove(&previous);
        }
        self.next = self.next.wrapping_add(1);
        self.order.insert(self.next, key.to_owned());
        self.next
    }

    fn forget(&mut self, access_order: u64) {
        self.order.remove(&access_order);
    }

    /// Removes and returns the least-recently-used key.
    fn pop_lru(&mut self) -> Option<String> {
        self.order.pop_first().map(|(_, key)| key)
    }
}

struct ManifestCache {
    entries: HashMap<String, CachedManifest>,
    total_bytes: usize,
    access: AccessOrder,
    max_bytes: usize,
}

/// The existence cache is touched on every artifact read and existence
/// check; a single lock around it convoys under concurrent serving
/// (profiled: read-heavy REAPI batches capped near 1k blobs/s with readers
/// queued on this mutex). Sharding bounds contention; LRU order and TTL are
/// preserved per shard.
struct ShardedExistenceCache {
    shards: [StdMutex<ExistenceCache>; EXISTENCE_CACHE_SHARDS],
}

const EXISTENCE_CACHE_SHARDS: usize = 32;

impl ShardedExistenceCache {
    fn new(capacity: usize, ttl: Duration) -> Self {
        let per_shard = (capacity / EXISTENCE_CACHE_SHARDS).max(1);
        Self {
            shards: std::array::from_fn(|_| StdMutex::new(ExistenceCache::new(per_shard, ttl))),
        }
    }

    fn shard(&self, artifact_id: &str) -> &StdMutex<ExistenceCache> {
        let mut hash = 0xcbf29ce484222325u64;
        for byte in artifact_id.as_bytes() {
            hash ^= u64::from(*byte);
            hash = hash.wrapping_mul(0x100000001b3);
        }
        &self.shards[(hash % EXISTENCE_CACHE_SHARDS as u64) as usize]
    }

    fn contains(&self, artifact_id: &str) -> bool {
        self.shard(artifact_id)
            .lock()
            .expect("existence cache lock poisoned")
            .contains(artifact_id)
    }

    fn insert(&self, artifact_id: &str) {
        self.shard(artifact_id)
            .lock()
            .expect("existence cache lock poisoned")
            .insert(artifact_id.to_owned());
    }

    fn remove_many(&self, artifact_ids: &[String]) {
        for artifact_id in artifact_ids {
            self.shard(artifact_id)
                .lock()
                .expect("existence cache lock poisoned")
                .remove_many(std::slice::from_ref(artifact_id));
        }
    }

    fn trim_to(&self, target_entries: usize) -> usize {
        let per_shard = target_entries / EXISTENCE_CACHE_SHARDS;
        let mut evicted = 0;
        for shard in &self.shards {
            evicted += shard
                .lock()
                .expect("existence cache lock poisoned")
                .trim_to(per_shard);
        }
        evicted
    }
}

struct ExistenceCache {
    entries: HashMap<String, CachedExistence>,
    access: AccessOrder,
    capacity: usize,
    ttl: Duration,
}

struct CachedExistence {
    inserted_at: Instant,
    access_order: u64,
}

struct CachedManifest {
    manifest: ArtifactManifest,
    size_bytes: usize,
    access_order: u64,
}

enum ManifestCacheInsertResult {
    Admitted { evicted: usize },
    Updated { evicted: usize },
    Oversized,
}

impl ManifestCache {
    fn new(max_bytes: usize) -> Self {
        Self {
            entries: HashMap::new(),
            total_bytes: 0,
            access: AccessOrder::new(),
            max_bytes,
        }
    }

    fn len(&self) -> usize {
        self.entries.len()
    }

    fn total_bytes(&self) -> usize {
        self.total_bytes
    }

    fn get(&mut self, artifact_id: &str) -> Option<ArtifactManifest> {
        let previous_order = self.entries.get(artifact_id)?.access_order;
        let access_order = self.access.touch(artifact_id, Some(previous_order));
        let cached = self.entries.get_mut(artifact_id)?;
        cached.access_order = access_order;
        Some(cached.manifest.clone())
    }

    fn insert(&mut self, manifest: ArtifactManifest) -> ManifestCacheInsertResult {
        let artifact_id = manifest.artifact_id.clone();
        let size_bytes = estimated_manifest_bytes(&manifest);
        if size_bytes > self.max_bytes {
            if let Some(removed) = self.entries.remove(&artifact_id) {
                self.total_bytes = self.total_bytes.saturating_sub(removed.size_bytes);
                self.access.forget(removed.access_order);
            }
            return ManifestCacheInsertResult::Oversized;
        }

        let existed = self.entries.remove(&artifact_id);
        let previous_order = existed.as_ref().map(|removed| {
            self.total_bytes = self.total_bytes.saturating_sub(removed.size_bytes);
            removed.access_order
        });
        let access_order = self.access.touch(&artifact_id, previous_order);
        self.entries.insert(
            artifact_id,
            CachedManifest {
                manifest,
                size_bytes,
                access_order,
            },
        );
        self.total_bytes = self.total_bytes.saturating_add(size_bytes);
        let evicted = self.trim_to(self.max_bytes);

        if existed.is_some() {
            ManifestCacheInsertResult::Updated { evicted }
        } else {
            ManifestCacheInsertResult::Admitted { evicted }
        }
    }

    fn remove_many(&mut self, artifact_ids: &[String]) {
        for artifact_id in artifact_ids {
            if let Some(removed) = self.entries.remove(artifact_id) {
                self.total_bytes = self.total_bytes.saturating_sub(removed.size_bytes);
                self.access.forget(removed.access_order);
            }
        }
    }

    fn trim_to(&mut self, target_bytes: usize) -> usize {
        let mut evicted = 0_usize;
        while self.total_bytes > target_bytes {
            let Some(oldest_key) = self.access.pop_lru() else {
                break;
            };
            if let Some(removed) = self.entries.remove(&oldest_key) {
                self.total_bytes = self.total_bytes.saturating_sub(removed.size_bytes);
                evicted += 1;
            }
        }
        evicted
    }
}

impl ExistenceCache {
    fn new(capacity: usize, ttl: Duration) -> Self {
        Self {
            entries: HashMap::new(),
            access: AccessOrder::new(),
            capacity,
            ttl,
        }
    }

    fn contains(&mut self, artifact_id: &str) -> bool {
        let Some((inserted_at, previous_order)) = self
            .entries
            .get(artifact_id)
            .map(|entry| (entry.inserted_at, entry.access_order))
        else {
            return false;
        };
        if Instant::now().duration_since(inserted_at) > self.ttl {
            self.entries.remove(artifact_id);
            self.access.forget(previous_order);
            return false;
        }
        let access_order = self.access.touch(artifact_id, Some(previous_order));
        if let Some(entry) = self.entries.get_mut(artifact_id) {
            entry.access_order = access_order;
        }
        true
    }

    fn insert(&mut self, artifact_id: String) {
        let previous_order = self
            .entries
            .get(&artifact_id)
            .map(|entry| entry.access_order);
        let access_order = self.access.touch(&artifact_id, previous_order);
        self.entries.insert(
            artifact_id,
            CachedExistence {
                inserted_at: Instant::now(),
                access_order,
            },
        );
        self.evict_over_capacity();
    }

    fn remove_many(&mut self, artifact_ids: &[String]) {
        for artifact_id in artifact_ids {
            if let Some(removed) = self.entries.remove(artifact_id) {
                self.access.forget(removed.access_order);
            }
        }
    }

    fn trim_to(&mut self, target_entries: usize) -> usize {
        let mut evicted = 0_usize;
        while self.entries.len() > target_entries {
            let Some(oldest_key) = self.access.pop_lru() else {
                break;
            };
            self.entries.remove(&oldest_key);
            evicted += 1;
        }
        evicted
    }

    fn evict_over_capacity(&mut self) {
        while self.entries.len() > self.capacity {
            let Some(oldest_key) = self.access.pop_lru() else {
                break;
            };
            self.entries.remove(&oldest_key);
        }
    }
}

fn estimated_manifest_bytes(manifest: &ArtifactManifest) -> usize {
    let optional_blob_path = manifest.blob_path.as_deref().map(str::len).unwrap_or(0);
    let optional_segment_id = manifest.segment_id.as_deref().map(str::len).unwrap_or(0);
    // The artifact id is owned three times: inside the manifest, as the
    // HashMap key, and in AccessOrder's BTreeMap value.
    manifest.artifact_id.len().saturating_mul(3)
        + manifest.namespace_id.len()
        + manifest.key.len()
        + manifest.content_type.len()
        + optional_blob_path
        + optional_segment_id
        + std::mem::size_of::<ArtifactManifest>()
}

pub const DISK_FULL_MARKER: &str = "disk_full";

pub fn is_disk_full_error(error: &str) -> bool {
    error.contains(DISK_FULL_MARKER)
}

/// Free bytes a rotation must see before creating a new segment: room for the
/// incoming artifact, which is appended whole and can exceed
/// `MAX_SEGMENT_BYTES`, plus the same again as slack for writers the rotation
/// check cannot see (metadata store flushes and compactions, the evicted
/// segment that is not yet unlinked, and tmp staging when it shares the
/// filesystem — the staged source and the segment copy coexist during the
/// append).
/// Hands a CAS eviction's synchronous scan back to the scheduler every
/// `SEGMENT_EVICTION_YIELD_ROWS` rows.
///
/// The counter is threaded through the segment scan and every nested cascade
/// scan it starts, rather than kept per scan. A per-scan budget restarts at
/// zero for each blob, so a segment holding many small blobs, each referenced
/// by many action-cache entries, stays under the stride on both scans while
/// running their product in a single poll.
async fn yield_scanned_row(scanned_rows: &mut usize) {
    *scanned_rows += 1;
    if (*scanned_rows).is_multiple_of(SEGMENT_EVICTION_YIELD_ROWS) {
        tokio::task::yield_now().await;
    }
}

fn segment_rotation_required_bytes(incoming_size: u64) -> u64 {
    MAX_SEGMENT_BYTES
        .max(incoming_size)
        .saturating_mul(SEGMENT_FREE_SPACE_MARGIN)
}

#[cfg(unix)]
fn available_disk_bytes(path: &Path) -> Option<u64> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;

    let path = CString::new(path.as_os_str().as_bytes()).ok()?;
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    let result = unsafe { libc::statvfs(path.as_ptr(), &mut stat) };
    if result != 0 {
        return None;
    }
    #[allow(clippy::unnecessary_cast)]
    let f_bavail = stat.f_bavail as u64;
    #[allow(clippy::unnecessary_cast)]
    let f_frsize = stat.f_frsize as u64;
    Some(f_bavail.saturating_mul(f_frsize))
}

#[cfg(not(unix))]
fn available_disk_bytes(_path: &Path) -> Option<u64> {
    None
}

#[cfg(unix)]
fn total_disk_bytes(path: &Path) -> Option<u64> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;

    let path = CString::new(path.as_os_str().as_bytes()).ok()?;
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    let result = unsafe { libc::statvfs(path.as_ptr(), &mut stat) };
    if result != 0 {
        return None;
    }
    #[allow(clippy::unnecessary_cast)]
    let f_blocks = stat.f_blocks as u64;
    #[allow(clippy::unnecessary_cast)]
    let f_frsize = stat.f_frsize as u64;
    Some(f_blocks.saturating_mul(f_frsize))
}

#[cfg(not(unix))]
fn total_disk_bytes(_path: &Path) -> Option<u64> {
    None
}

/// Ring-fullness inputs of the backfill marginal-trade capacity test, read
/// through [`Store::backfill_capacity_inputs`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct BackfillCapacityInputs {
    pub segment_count: usize,
    pub ring_total_segments: usize,
    pub next_evictee_stat_ms: Option<u64>,
}

/// Resolved generation counts for the CAS segment ring.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct SegmentRingLimits {
    pub desired_old_segments: usize,
    pub desired_current_segments: usize,
    pub desired_new_segments: usize,
}

impl SegmentRingLimits {
    fn legacy_floor() -> Self {
        Self {
            desired_old_segments: DESIRED_OLD_SEGMENTS,
            desired_current_segments: DESIRED_CURRENT_SEGMENTS,
            desired_new_segments: DESIRED_NEW_SEGMENTS,
        }
    }

    pub(crate) fn total_segments(&self) -> usize {
        self.desired_old_segments + self.desired_current_segments + self.desired_new_segments
    }

    fn capacity_bytes(&self) -> u64 {
        (self.total_segments() as u64).saturating_mul(MAX_SEGMENT_BYTES)
    }
}

/// Resolves the segment-ring generation counts from the operator-configured
/// capacity and the data-dir filesystem size.
///
/// The budget is `configured_capacity_bytes` when set, otherwise
/// `CAS_CAPACITY_DEFAULT_DISK_PERCENT` of the filesystem. Either way it is
/// capped at `CAS_CAPACITY_MAX_DISK_PERCENT` of the filesystem so resident
/// segments plus the extra segment a rotation appends before evicting the
/// oldest one can never run the disk full, and floored at the legacy 1/2/2
/// ring so small disks (or hosts where the filesystem size cannot be
/// determined) keep the pre-existing behavior. Generations keep the legacy
/// 1:2:2 old/current/new proportions.
fn resolve_segment_ring_limits(
    configured_capacity_bytes: Option<u64>,
    disk_total_bytes: Option<u64>,
) -> SegmentRingLimits {
    let floor = SegmentRingLimits::legacy_floor();

    let ceiling_bytes = disk_total_bytes.map(|total| total / 100 * CAS_CAPACITY_MAX_DISK_PERCENT);
    let budget_bytes = match (configured_capacity_bytes, ceiling_bytes) {
        (Some(configured), Some(ceiling)) => Some(configured.min(ceiling)),
        (Some(configured), None) => Some(configured),
        (None, Some(_)) => {
            disk_total_bytes.map(|total| total / 100 * CAS_CAPACITY_DEFAULT_DISK_PERCENT)
        }
        (None, None) => None,
    };
    let Some(budget_bytes) = budget_bytes else {
        return floor;
    };

    let total_segments = usize::try_from(budget_bytes / MAX_SEGMENT_BYTES)
        .unwrap_or(MAX_DESIRED_SEGMENTS)
        .clamp(floor.total_segments(), MAX_DESIRED_SEGMENTS);

    let desired_old_segments = (total_segments / 5).max(DESIRED_OLD_SEGMENTS);
    let remainder = total_segments - desired_old_segments;
    let desired_current_segments = (remainder / 2).max(DESIRED_CURRENT_SEGMENTS);
    let desired_new_segments = (remainder - desired_current_segments).max(DESIRED_NEW_SEGMENTS);

    SegmentRingLimits {
        desired_old_segments,
        desired_current_segments,
        desired_new_segments,
    }
}

fn rocksdb_column_family_options(
    config: &Config,
    block_cache: &Cache,
    write_buffer_manager: &WriteBufferManager,
) -> Options {
    let mut options = Options::default();
    options.set_compression_type(rocksdb::DBCompressionType::Lz4);
    options.set_write_buffer_size(config.rocksdb_write_buffer_size_bytes);
    options.set_max_write_buffer_number(config.rocksdb_max_write_buffer_number);
    options.set_write_buffer_manager(write_buffer_manager);
    options.set_level_zero_slowdown_writes_trigger(ROCKSDB_LEVEL0_SLOWDOWN_TRIGGER);
    options.set_level_zero_stop_writes_trigger(ROCKSDB_LEVEL0_STOP_TRIGGER);
    options.set_soft_pending_compaction_bytes_limit(ROCKSDB_SOFT_PENDING_COMPACTION_BYTES as usize);
    options.set_hard_pending_compaction_bytes_limit(ROCKSDB_HARD_PENDING_COMPACTION_BYTES as usize);

    let mut block_based = BlockBasedOptions::default();
    block_based.set_block_cache(block_cache);
    block_based.set_cache_index_and_filter_blocks(true);
    block_based.set_pin_l0_filter_and_index_blocks_in_cache(true);
    options.set_block_based_table_factory(&block_based);
    options
}

/// Parsed segment ring state plus a by-id generation index, kept in memory so
/// the serving path never re-reads and re-parses the persisted state. The
/// process is the only writer of the metadata store (enforced by the data-dir
/// writer lock), so the snapshot can only go stale if a mutation bypasses
/// [`Store::save_segment_state`].
#[derive(Default)]
struct SegmentStateSnapshot {
    state: SegmentState,
    generations: HashMap<String, SegmentGeneration>,
}

impl SegmentStateSnapshot {
    fn new(state: SegmentState) -> Self {
        let mut generations =
            HashMap::with_capacity(state.old.len() + state.current.len() + state.new.len());
        for segment in &state.old {
            generations.insert(segment.segment_id.clone(), SegmentGeneration::Old);
        }
        for segment in &state.current {
            generations.insert(segment.segment_id.clone(), SegmentGeneration::Current);
        }
        for segment in &state.new {
            generations.insert(segment.segment_id.clone(), SegmentGeneration::New);
        }
        Self { state, generations }
    }
}

struct SegmentLocation {
    segment_id: String,
    offset: u64,
}

struct SegmentHandleCache {
    entries: HashMap<String, CachedSegmentHandle>,
    access: AccessOrder,
    capacity: usize,
}

struct CachedSegmentHandle {
    handle: Arc<PersistentFile>,
    access_order: u64,
}

impl SegmentHandleCache {
    fn new(capacity: usize) -> Self {
        Self {
            entries: HashMap::new(),
            access: AccessOrder::new(),
            capacity,
        }
    }

    fn len(&self) -> usize {
        self.entries.len()
    }

    fn touch(&mut self, cache_key: &str) -> Option<Arc<PersistentFile>> {
        let previous_order = self.entries.get(cache_key)?.access_order;
        let access_order = self.access.touch(cache_key, Some(previous_order));
        let entry = self.entries.get_mut(cache_key)?;
        entry.access_order = access_order;
        Some(entry.handle.clone())
    }

    fn insert(&mut self, cache_key: String, handle: Arc<PersistentFile>) -> usize {
        let previous_order = self.entries.get(&cache_key).map(|entry| entry.access_order);
        let access_order = self.access.touch(&cache_key, previous_order);
        self.entries.insert(
            cache_key,
            CachedSegmentHandle {
                handle,
                access_order,
            },
        );
        self.evict_over_capacity()
    }

    fn remove(&mut self, cache_key: &str) -> bool {
        if let Some(removed) = self.entries.remove(cache_key) {
            self.access.forget(removed.access_order);
            true
        } else {
            false
        }
    }

    fn trim_to(&mut self, target_entries: usize) -> usize {
        let original_capacity = self.capacity;
        self.capacity = target_entries;
        let evicted = self.evict_over_capacity();
        self.capacity = original_capacity;
        evicted
    }

    fn evict_over_capacity(&mut self) -> usize {
        let mut evicted = 0;
        while self.entries.len() > self.capacity {
            let Some(lru_key) = self.access.pop_lru() else {
                break;
            };
            self.entries.remove(&lru_key);
            evicted += 1;
        }
        evicted
    }
}

fn segment_handle_cache_key(segment_id: &str) -> String {
    format!("segment:{segment_id}")
}

fn blob_handle_cache_key(blob_path: &str) -> String {
    format!("blob:{blob_path}")
}

pub(crate) fn manifest_version_ms(manifest: &ArtifactManifest) -> u64 {
    if manifest.version_ms == 0 {
        manifest.created_at_ms
    } else {
        manifest.version_ms
    }
}

/// The backfill index kind of a manifest. Legacy blob-backed artifacts ride
/// as `SegmentArtifact`: the kind distinguishes "body is inline bytes" from
/// "body is file-backed", which is what the transfer path cares about.
pub(crate) fn backfill_record_kind(manifest: &ArtifactManifest) -> BackfillRecordKind {
    if manifest.inline {
        BackfillRecordKind::InlineArtifact
    } else {
        BackfillRecordKind::SegmentArtifact
    }
}

/// Value of `backfill/meta/last_maintained_seq`: the latest sequence number
/// observed just before the stamp write, plus whether the stamp marks a clean
/// shutdown.
fn encode_backfill_seq_stamp(seq: u64, clean_shutdown: bool) -> [u8; 9] {
    let mut value = [0_u8; 9];
    value[..8].copy_from_slice(&seq.to_le_bytes());
    value[8] = clean_shutdown as u8;
    value
}

fn decode_backfill_seq_stamp(bytes: &[u8]) -> Option<(u64, bool)> {
    let (seq, flag) = bytes.split_at_checked(8)?;
    if flag.len() != 1 {
        return None;
    }
    Some((
        u64::from_le_bytes(seq.try_into().expect("split at 8")),
        flag[0] != 0,
    ))
}

/// Whether the sequence gap since the last maintenance stamp invalidates a
/// completed backfill index. After a clean-shutdown stamp any gap at all is a
/// foreign write; after a crash, gaps up to the stamping slack are this
/// binary's own writes since its last stamp.
fn backfill_rebuild_required(clean_shutdown: bool, sequence_gap: u64, slack: u64) -> bool {
    if clean_shutdown {
        sequence_gap > 0
    } else {
        sequence_gap > slack
    }
}

// True when a rejected (local-wins) apply carries the version we already
// store, i.e. both sides hold the identical entry. An incoming version of 0
// carries no ordering information (the persist path re-stamps it with
// now_ms()), so it can never attest convergence and classifies as stale.
fn versions_converged(existing_version_ms: u64, incoming_version_ms: u64) -> bool {
    incoming_version_ms != 0 && existing_version_ms == incoming_version_ms
}

fn read_bytes_at(file: &std::fs::File, offset: u64, size: u64) -> Result<Vec<u8>, String> {
    let size = usize::try_from(size)
        .map_err(|_| format!("artifact size {size} exceeds addressable memory"))?;
    let mut bytes = vec![0; size];
    let mut read_offset = 0_usize;
    while read_offset < bytes.len() {
        let bytes_read = read_at(file, &mut bytes[read_offset..], offset + read_offset as u64)
            .map_err(|error| {
                format!("failed to read artifact bytes at offset {offset}: {error}")
            })?;
        if bytes_read == 0 {
            return Err(format!(
                "unexpected EOF while reading {} bytes at offset {offset}",
                bytes.len()
            ));
        }
        read_offset += bytes_read;
    }
    Ok(bytes)
}

#[cfg(unix)]
fn read_at(file: &std::fs::File, bytes: &mut [u8], offset: u64) -> std::io::Result<usize> {
    use std::os::unix::fs::FileExt;

    file.read_at(bytes, offset)
}

#[cfg(windows)]
fn read_at(file: &std::fs::File, bytes: &mut [u8], offset: u64) -> std::io::Result<usize> {
    use std::os::windows::fs::FileExt;

    file.seek_read(bytes, offset)
}

fn persisted_version_ms(version_ms: u64) -> u64 {
    if version_ms == 0 {
        now_ms()
    } else {
        version_ms
    }
}

/// Every outbox key at or past this prefix belongs to the bulk lane. Keys are
/// ordered `"0-…"` (metadata lane) < `"0000…"` (legacy unprefixed zero-padded
/// timestamps, drained between the lanes across a rolling upgrade) < `"1-…"`
/// (bulk lane), so a fresh action-cache entry replicates ahead of a blob
/// backlog instead of waiting out gigabytes of it — measured as ~30 minutes
/// of cross-pod snapshot staleness during a cache populate.
pub const OUTBOX_BULK_LANE_PREFIX: &str = "1-";

/// Whether an outbox key belongs to the bulk lane. The lane is the key's first
/// byte, so this reads it without decoding the message.
pub fn is_bulk_outbox_key(key: &[u8]) -> bool {
    key.starts_with(OUTBOX_BULK_LANE_PREFIX.as_bytes())
}

fn outbox_message_key(message: &OutboxMessage) -> String {
    let lane = if message.operation.is_bulk() {
        "1"
    } else {
        "0"
    };
    format!("{lane}-{:020}-{}", now_ms(), Uuid::now_v7())
}

/// The branch tag a publish should land with, honoring trunk-stickiness: a key
/// already in the trunk baseline (tagged with the trunk branch) keeps its tag. A
/// feature build recomputing the same action republishes it, often with byte
/// wobble that defeats the refresh damping, and must not steal the key from the
/// trunk view. A publish FROM the trunk always (re)claims it, and with no trunk
/// to compare against the publish's own tag stands.
///
/// An untagged entry has nothing to protect: it is not in the baseline, so the
/// first publisher to name a branch may claim it, which is how the fleet retags
/// what it inherited.
fn sticky_branch<'a>(
    existing: Option<&'a ArtifactManifest>,
    branch: Option<&'a str>,
    trunk: Option<&str>,
) -> Option<&'a str> {
    match (existing, trunk) {
        (Some(existing), Some(trunk))
            if branch != Some(trunk) && existing.branch.as_deref() == Some(trunk) =>
        {
            existing.branch.as_deref()
        }
        // A publisher that names no branch is not asserting that the entry has
        // none; it is saying it cannot tell. It must not overwrite what a
        // publisher that could tell recorded, or a node too old to send the
        // header would untag a trunk key and drop it out of the trunk view by
        // republishing it.
        (Some(existing), _) if branch.is_none() => existing.branch.as_deref(),
        _ => branch,
    }
}

/// Whether a manifest belongs in a trunk-scoped snapshot: only entries tagged
/// with the trunk branch form the scoped baseline. An untagged entry is NOT in
/// it, and neither is one tagged with a different branch. `None` (no trunk
/// asked for) keeps every entry.
fn manifest_in_trunk(manifest: &ArtifactManifest, trunk: Option<&str>) -> bool {
    branch_in_trunk(manifest.branch.as_deref(), trunk)
}

/// The same rule against a bare tag, so an index row and a manifest cannot drift
/// apart on what belongs in a trunk view.
///
/// An untagged entry is NOT in the trunk baseline. `None` means the publisher
/// could not tell us which branch produced it (no registered checkout, a moved
/// or renamed one, a node older than the tag), and treating "unknown" as "trunk"
/// resolves every one of those the least safe way: silently, into the one view
/// this scoping exists to keep clean. Excluded, an unknown entry costs a per-key
/// round trip and gets re-tagged by the refresh path the first time it is read.
fn branch_in_trunk(branch: Option<&str>, trunk: Option<&str>) -> bool {
    match trunk {
        Some(trunk) => branch == Some(trunk),
        None => true,
    }
}

fn encode_manifest_record(manifest: &ArtifactManifest) -> Result<Vec<u8>, String> {
    if manifest.is_segment_backed() {
        return SegmentLocationRecord::from_manifest(manifest).map(|record| record.encode());
    }

    serde_json::to_vec(&PersistedManifestRecord::from_manifest(manifest))
        .map_err(|error| format!("failed to encode manifest: {error}"))
}

fn decode_manifest_record(artifact_id: &str, bytes: &[u8]) -> Result<ArtifactManifest, String> {
    if let Some(manifest) = SegmentLocationRecord::decode(bytes, artifact_id)? {
        return Ok(manifest);
    }

    serde_json::from_slice::<PersistedManifestRecord>(bytes)
        .map_err(|error| format!("failed to decode manifest: {error}"))?
        .into_manifest(artifact_id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use bazel_remote_apis::build::bazel::remote::execution::v2::{
        ActionResult as ReapiActionResult, Digest as ReapiDigest, OutputFile as ReapiOutputFile,
    };
    use tempfile::TempDir;

    use crate::utils::blob_key;

    use crate::{
        config::{AcceleratedFileServingConfig, AcceleratedFileServingMode, Config},
        failpoints::{FailpointAction, FailpointName},
        io::IoController,
        memory::MemoryController,
        metrics::Metrics,
        replication::operation::ReplicationOperation,
        segment::{reference::SegmentReference, state::SegmentState},
    };

    const GIB: u64 = 1024 * 1024 * 1024;

    #[test]
    fn segment_ring_limits_fall_back_to_legacy_floor_without_disk_information() {
        let limits = resolve_segment_ring_limits(None, None);

        assert_eq!(limits, SegmentRingLimits::legacy_floor());
    }

    #[test]
    fn segment_ring_limits_derive_from_disk_size_when_unconfigured() {
        // 50% of 100 GiB = 50 GiB = 100 segments, split 1:2:2.
        let limits = resolve_segment_ring_limits(None, Some(100 * GIB));

        assert_eq!(limits.desired_old_segments, 20);
        assert_eq!(limits.desired_current_segments, 40);
        assert_eq!(limits.desired_new_segments, 40);
        assert_eq!(limits.capacity_bytes(), 50 * GIB);
    }

    #[test]
    fn segment_ring_limits_use_configured_capacity() {
        // 20 GiB = 40 segments.
        let limits = resolve_segment_ring_limits(Some(20 * GIB), Some(100 * GIB));

        assert_eq!(limits.desired_old_segments, 8);
        assert_eq!(limits.desired_current_segments, 16);
        assert_eq!(limits.desired_new_segments, 16);
    }

    #[test]
    fn segment_ring_limits_cap_configured_capacity_below_disk_size() {
        // 80% of 10 GiB rounds down to 15 whole segments, regardless of the
        // configured 1 TiB.
        let limits = resolve_segment_ring_limits(Some(1024 * GIB), Some(10 * GIB));

        assert_eq!(limits.total_segments(), 15);
        assert!(limits.capacity_bytes() <= 10 * GIB * 80 / 100);
    }

    #[test]
    fn segment_ring_limits_never_drop_below_legacy_floor() {
        let tiny_configured = resolve_segment_ring_limits(Some(1), Some(100 * GIB));
        assert_eq!(
            tiny_configured.total_segments(),
            SegmentRingLimits::legacy_floor().total_segments()
        );

        // 50% of 1 GiB = 512 MiB = 1 segment, floored to the legacy ring.
        let tiny_disk = resolve_segment_ring_limits(None, Some(GIB));
        assert_eq!(
            tiny_disk.total_segments(),
            SegmentRingLimits::legacy_floor().total_segments()
        );
    }

    #[test]
    fn segment_ring_limits_use_configured_capacity_without_disk_information() {
        let limits = resolve_segment_ring_limits(Some(20 * GIB), None);

        assert_eq!(limits.total_segments(), 40);
    }

    fn temp_store() -> (TempDir, Config, Store) {
        temp_store_with(|_| {})
    }

    fn temp_store_at_pressure(pressure: crate::memory::MemoryPressure) -> (TempDir, Config, Store) {
        let (temp_dir, config, _) = temp_store_with(|_| {});
        let io = IoController::new(
            Metrics::new(config.region.clone(), config.tenant_id.clone()),
            config.file_descriptor_pool_size,
            std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
            vec![config.tmp_dir.clone(), config.data_dir.clone()],
        )
        .expect("failed to create io controller");
        let memory = MemoryController::new_with_forced_pressure(
            io.metrics(),
            config.memory_soft_limit_bytes,
            config.memory_hard_limit_bytes,
            pressure,
        );
        let store = Store::open(&config, io, memory).expect("failed to open store");
        (temp_dir, config, store)
    }

    fn temp_store_with<F>(override_config: F) -> (TempDir, Config, Store)
    where
        F: FnOnce(&mut Config),
    {
        let temp_dir = tempfile::tempdir().expect("failed to create temp dir");
        let mut config = Config {
            port: 0,
            internal_port: 7443,
            tenant_id: "test-tenant".into(),
            region: "local".into(),
            tmp_dir: temp_dir.path().join("tmp"),
            data_dir: temp_dir.path().join("data"),
            tmp_dir_max_bytes: 8 * 1024 * 1024 * 1024,
            cas_capacity_bytes: None,
            node_url: "http://127.0.0.1:7443".into(),
            peer_gateway_url: None,
            peers: vec!["http://127.0.0.1:7443".into()],
            discovery_dns_name: None,
            global_discovery_dns_name: None,
            peer_tls: None,
            public_tls: None,
            https_port: 0,
            accelerated_file_serving: AcceleratedFileServingConfig {
                enabled: true,
                mode: AcceleratedFileServingMode::Splice,
                max_concurrent: 32,
                chunk_bytes: 1024 * 1024,
            },
            action_cache_eviction_cascade_enabled: true,
            file_descriptor_pool_size: 32,
            file_descriptor_acquire_timeout_ms: 5_000,
            drain_completion_timeout_ms: 240_000,
            segment_handle_cache_size: 8,
            memory_limit_bytes: 512 * 1024 * 1024,
            memory_soft_limit_bytes: 128 * 1024 * 1024,
            memory_hard_limit_bytes: 256 * 1024 * 1024,
            memory_floor_bytes: None,
            anon_cache_fit: None,
            snapshot_cache_max_bytes: 32 * 1024 * 1024,
            manifest_cache_max_bytes: 8 * 1024 * 1024,
            max_keyvalue_bytes: 512 * 1024,
            rocksdb_max_open_files: 256,
            rocksdb_max_background_jobs: 2,
            rocksdb_block_cache_bytes: 32 * 1024 * 1024,
            rocksdb_write_buffer_manager_bytes: 32 * 1024 * 1024,
            rocksdb_write_buffer_size_bytes: 8 * 1024 * 1024,
            rocksdb_max_write_buffer_number: 4,
            outbox_max_depth: 100_000,
            replication_bandwidth_limit_bytes_per_second: 0,
            replication_public_latency_target_ms: 100,
            replication_upload_stall_ms: crate::constants::DEFAULT_REPLICATION_UPLOAD_STALL_MS,
            multipart_upload_ttl_ms: 24 * 60 * 60 * 1000,
            multipart_janitor_interval_ms: 10 * 60 * 1000,
            multipart_max_active_uploads: 128,
            multipart_max_stored_bytes: 8 * 1024 * 1024 * 1024,
            backfill_margin_percent: 40,
            backfill_ready_ring_percent: crate::constants::default_backfill_ready_ring_percent(40),
            backfill_batch_bytes: crate::constants::DEFAULT_BACKFILL_BATCH_BYTES,
            analytics: None,
            usage: None,
            otlp_traces_endpoint: Some("http://127.0.0.1:4318/v1/traces".into()),
            otel_service_name: "kura-test".into(),
            otel_deployment_environment: "test".into(),
            sentry_dsn: None,
            request_log_sample_rate: 0.0,
            slow_request_threshold_ms: 30_000,
            warning_log_interval_ms: 60_000,
            node_country_override: None,
            node_subdivision_override: None,
        };
        override_config(&mut config);
        std::fs::create_dir_all(config.tmp_dir.join("uploads"))
            .expect("failed to create upload temp dir");
        std::fs::create_dir_all(config.data_dir.join("rocksdb"))
            .expect("failed to create rocksdb dir");
        std::fs::create_dir_all(config.data_dir.join("blobs")).expect("failed to create blobs dir");
        std::fs::create_dir_all(config.data_dir.join("segments"))
            .expect("failed to create segments dir");
        std::fs::create_dir_all(config.data_dir.join("multipart"))
            .expect("failed to create multipart dir");
        let io = IoController::new(
            Metrics::new(config.region.clone(), config.tenant_id.clone()),
            config.file_descriptor_pool_size,
            std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
            vec![config.tmp_dir.clone(), config.data_dir.clone()],
        )
        .expect("failed to create io controller");
        let memory = MemoryController::new(
            io.metrics(),
            config.memory_soft_limit_bytes,
            config.memory_hard_limit_bytes,
        );
        let store = Store::open(&config, io, memory).expect("failed to open store");
        (temp_dir, config, store)
    }

    async fn read_manifest_bytes(store: &Store, manifest: &ArtifactManifest) -> Vec<u8> {
        store
            .read_artifact_bytes(manifest)
            .await
            .expect("artifact bytes should read")
    }

    #[tokio::test]
    async fn concurrent_replicated_applies_of_same_key_write_once() {
        // Several peers replicating the same artifact concurrently (same key,
        // same version) must not each append their own copy to a segment. The
        // per-key apply lock serializes them: the first writer commits the
        // manifest and the rest re-read it and short-circuit to IgnoredEqual. A
        // sleep failpoint between the durable append and the metadata commit
        // forces the writers to overlap, so without the lock every copy would be
        // appended (writer_count x on disk). This guards the store invariant
        // directly, independent of the backfill-level fetch gate.
        let (_temp_dir, config, store) = temp_store();
        store.failpoints().set_always(
            FailpointName::AfterArtifactBytesDurableBeforeMetadata,
            FailpointAction::Sleep(std::time::Duration::from_millis(150)),
        );

        let writer_count = 4_usize;
        let artifact_len = 128 * 1024_usize;
        let bytes = vec![9_u8; artifact_len];
        let version_ms = 100_u64;

        let mut sources = Vec::new();
        for index in 0..writer_count {
            let path = config.tmp_dir.join("uploads").join(format!("src-{index}"));
            std::fs::write(&path, &bytes).expect("source should write");
            sources.push(path);
        }

        let applies = sources.iter().map(|source_path| {
            store.apply_replicated_artifact_from_path(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                source_path,
                version_ms,
            )
        });
        let outcomes = futures_util::future::join_all(applies).await;

        let outcomes: Vec<ArtifactApplyOutcome> = outcomes
            .into_iter()
            .map(|outcome| outcome.expect("apply should succeed"))
            .collect();
        let applied = outcomes.iter().filter(|outcome| outcome.applied()).count();
        assert_eq!(
            applied, 1,
            "exactly one concurrent same-key apply should write"
        );
        let equal = outcomes
            .iter()
            .filter(|outcome| **outcome == ArtifactApplyOutcome::IgnoredEqual)
            .count();
        assert_eq!(
            equal,
            writer_count - 1,
            "the losers re-read the committed manifest and report the converged duplicate"
        );

        let segments_bytes = crate::utils::directory_size_bytes(&config.data_dir.join("segments"));
        assert!(
            segments_bytes <= (artifact_len as u64) * 2,
            "segment store held {segments_bytes} bytes, expected ~{artifact_len} (one copy); \
             concurrent same-key applies amplified on-disk data"
        );
    }

    #[tokio::test]
    async fn replicated_path_apply_preserves_the_staged_file_cache_policy() {
        let (_temp_dir, config, store) = temp_store();
        let source = config.tmp_dir.join("uploads").join("bounded-replication");
        let payload = vec![
            0xAB;
            usize::try_from(FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES + 1)
                .expect("test payload should fit usize")
        ];
        std::fs::write(&source, payload).expect("source should write");

        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Gradle,
                "ios",
                "bounded-artifact",
                "application/octet-stream",
                StagedArtifactPath::new(&source, FileCachePolicy::Bounded),
                100,
            )
            .await
            .expect("bounded replicated artifact should persist");

        assert!(
            store
                .io
                .metrics()
                .render()
                .contains("action=\"segment_file_cache_drop\""),
            "the bounded staging policy should reach the segment copy"
        );
    }

    #[tokio::test]
    async fn damped_persist_skips_identical_republish_of_a_fresh_entry() {
        let (_temp_dir, _config, store) = temp_store();
        let day = 24 * 60 * 60 * 1000;

        // Seed the entry with an aged version (a replicated apply preserves
        // the origin's version), so the first damped refresh applies.
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/aa/10",
                "application/x-protobuf",
                b"graph",
                now_ms() - 2 * day,
                None,
                None,
            )
            .await
            .expect("seed should persist");

        let (refreshed, applied) = store
            .persist_inline_artifact_from_bytes_damped_and_enqueue(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/aa/10",
                "application/x-protobuf",
                b"graph",
                &[],
                None,
                None,
            )
            .await
            .expect("aged refresh should persist");
        assert!(applied, "an aged identical re-publish applies");

        let (damped, applied) = store
            .persist_inline_artifact_from_bytes_damped_and_enqueue(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/aa/10",
                "application/x-protobuf",
                b"graph",
                &[],
                None,
                None,
            )
            .await
            .expect("damped refresh should succeed");
        assert!(
            !applied,
            "an identical re-publish inside the window is damped"
        );
        assert_eq!(damped.version_ms, refreshed.version_ms);

        let (changed, applied) = store
            .persist_inline_artifact_from_bytes_damped_and_enqueue(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/aa/10",
                "application/x-protobuf",
                b"graph-v2",
                &[],
                None,
                None,
            )
            .await
            .expect("changed publish should persist");
        assert!(applied, "changed content always applies");
        assert!(changed.version_ms >= refreshed.version_ms);
    }

    #[tokio::test]
    async fn action_cache_manifests_scope_to_the_trunk_branch() {
        let (_temp_dir, _config, store) = temp_store();
        async fn publish(store: &Store, key: &str, branch: Option<&str>) {
            store
                .persist_inline_artifact_from_bytes_damped_and_enqueue(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    "application/x-protobuf",
                    b"graph",
                    &[],
                    branch,
                    None,
                )
                .await
                .expect("action-cache entry should persist");
        }
        publish(&store, "action_cache/aa/10", Some("main")).await;
        publish(&store, "action_cache/bb/10", Some("feature")).await;

        let trunk = store
            .action_cache_manifests("ios", 10, Some("main"))
            .expect("trunk scan should succeed");
        assert_eq!(trunk.len(), 1, "the trunk snapshot excludes other branches");
        assert_eq!(trunk[0].key, "action_cache/aa/10");
        assert_eq!(trunk[0].branch.as_deref(), Some("main"));

        let all = store
            .action_cache_manifests("ios", 10, None)
            .expect("unfiltered scan should succeed");
        assert_eq!(all.len(), 2, "the unfiltered snapshot keeps every branch");

        // An untagged entry is not in the trunk baseline: its publisher could not
        // say which branch produced it, and a trunk view is the wrong place to
        // resolve that doubt. It is still served per key, and the first publisher
        // to name a branch claims it.
        publish(&store, "action_cache/cc/10", None).await;
        let trunk = store
            .action_cache_manifests("ios", 10, Some("main"))
            .expect("trunk scan should succeed");
        let keys: Vec<&str> = trunk.iter().map(|manifest| manifest.key.as_str()).collect();
        assert!(keys.contains(&"action_cache/aa/10"));
        assert!(!keys.contains(&"action_cache/cc/10"));
        assert!(!keys.contains(&"action_cache/bb/10"));
        let all = store
            .action_cache_manifests("ios", 10, None)
            .expect("unfiltered scan should succeed");
        assert_eq!(all.len(), 3, "an unscoped view still keeps every entry");
    }

    /// The rollback contract, pinned. A node that predates the branch reads the
    /// version out of the key at a fixed offset and the artifact id out of the
    /// value, and never parses what sits between them. Both have to survive the
    /// branch being appended, or that node retires every row it cannot read and
    /// deletes the index out from under itself.
    #[test]
    fn an_index_key_keeps_its_version_where_an_older_node_looks_for_it() {
        let prefix = action_cache_index_prefix("ios");
        for branch in [None, Some("main"), Some("feature/some-long-name")] {
            let key = action_cache_index_key("ios", 1_234, "abc123", branch);
            assert!(
                key.starts_with(&prefix),
                "namespace prefix scan still matches"
            );
            let version = key
                .get(prefix.len()..prefix.len() + 8)
                .expect("version sits at a fixed offset");
            let version = !u64::from_be_bytes(version.try_into().expect("8 bytes"));
            assert_eq!(version, 1_234, "an older node still reads the version");
        }
    }

    #[test]
    fn an_index_row_reports_its_branch_and_a_pre_branch_row_admits_it_cannot() {
        let prefix_len = action_cache_index_prefix("ios").len();
        let tagged = action_cache_index_key("ios", 1, "abc123", Some("main"));
        assert!(matches!(
            action_cache_index_key_branch(&tagged, prefix_len),
            IndexRowBranch::Known(Some("main"))
        ));
        // Untagged is known, and distinct from unknown: it answers the filter.
        let untagged = action_cache_index_key("ios", 1, "abc123", None);
        assert!(matches!(
            action_cache_index_key_branch(&untagged, prefix_len),
            IndexRowBranch::Known(None)
        ));
        // A row written before the branch: no separator after the action hash.
        let mut legacy = action_cache_index_prefix("ios");
        legacy.extend_from_slice(&(!1u64).to_be_bytes());
        legacy.extend_from_slice(b"abc123");
        assert!(matches!(
            action_cache_index_key_branch(&legacy, prefix_len),
            IndexRowBranch::Unknown
        ));
    }

    /// Trunk entries have to be reachable when they are buried under feature
    /// churn, which is the whole situation this scoping exists for. Rejecting a
    /// feature row costs nothing now that the row carries its own tag, so the
    /// churn cannot exhaust the budget that bounds reads before the walk reaches
    /// the trunk entries underneath it.
    #[tokio::test]
    async fn action_cache_manifests_reach_trunk_entries_buried_under_feature_churn() {
        let (_temp_dir, _config, store) = temp_store();
        async fn publish(store: &Store, key: &str, branch: Option<&str>) {
            store
                .persist_inline_artifact_from_bytes_damped_and_enqueue(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    "application/x-protobuf",
                    b"graph",
                    &[],
                    branch,
                    None,
                )
                .await
                .expect("action-cache entry should persist");
        }
        // Oldest, and last in the index under either ordering: it loses the
        // newest-first comparison on version, and `zzz` loses the action-hash tie
        // that a same-millisecond publish falls back on.
        publish(&store, "action_cache/zzz", Some("main")).await;
        // Enough feature rows ahead of it to exceed `max_entries * FACTOR`, which
        // is what used to end the walk before it ever arrived.
        for index in 0..(ACTION_CACHE_TRUNK_SCAN_FACTOR * 2) {
            publish(
                &store,
                &format!("action_cache/f{index:02}"),
                Some("feature"),
            )
            .await;
        }

        // The first call backfills and sets the marker; only after it does the
        // indexed path (the one with the budget) run at all.
        store
            .action_cache_manifests("ios", 1, Some("main"))
            .expect("backfill should succeed");
        let trunk = store
            .action_cache_manifests("ios", 1, Some("main"))
            .expect("indexed trunk scan should succeed");
        assert_eq!(
            trunk.len(),
            1,
            "the trunk entry is found under the feature churn instead of the view being truncated"
        );
        assert_eq!(trunk[0].key, "action_cache/zzz");
    }

    /// The reclaim the whole scoping depends on, in the shape it actually happens:
    /// two builds computing the same action produce the SAME bytes, so nothing
    /// about the value changes and only the tag does. Damping is the one check
    /// that stands between the client's tag-only update and the entry.
    #[tokio::test]
    async fn trunk_reclaims_an_identical_result_a_feature_published_first() {
        let (_temp_dir, _config, store) = temp_store();
        async fn publish(store: &Store, branch: Option<&str>) -> ArtifactManifest {
            store
                .persist_inline_artifact_from_bytes_damped_and_enqueue(
                    ArtifactProducer::Reapi,
                    "ios",
                    "action_cache/aa/10",
                    "application/x-protobuf",
                    b"identical",
                    &[],
                    branch,
                    Some("main"),
                )
                .await
                .expect("action-cache entry should persist")
                .0
        }
        // A feature build gets there first.
        publish(&store, Some("feature")).await;
        // Distinct version_ms: a same-millisecond republish is dropped as stale
        // before any tagging runs, which makes this pass or fail on the clock.
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
        // Trunk recomputes it: same bytes, well inside the damping window.
        let reclaimed = publish(&store, Some("main")).await;
        assert_eq!(
            reclaimed.branch.as_deref(),
            Some("main"),
            "a tag-only update is not a no-op, so damping must not swallow it"
        );
        let trunk = store
            .action_cache_manifests("ios", 10, Some("main"))
            .expect("trunk scan should succeed");
        assert_eq!(trunk.len(), 1, "and the entry is back in the trunk view");
    }

    /// A node too old to send the header, or a publisher whose checkout it could
    /// not resolve, says nothing about provenance. Letting that erase a tag would
    /// evict a trunk key from the trunk view by republishing it.
    #[tokio::test]
    async fn a_publish_that_names_no_branch_does_not_erase_one() {
        let (_temp_dir, _config, store) = temp_store();
        async fn publish(store: &Store, bytes: &[u8], branch: Option<&str>) -> ArtifactManifest {
            store
                .persist_inline_artifact_from_bytes_damped_and_enqueue(
                    ArtifactProducer::Reapi,
                    "ios",
                    "action_cache/aa/10",
                    "application/x-protobuf",
                    bytes,
                    &[],
                    branch,
                    // No trunk either: an older client sends neither header.
                    None,
                )
                .await
                .expect("action-cache entry should persist")
                .0
        }
        publish(&store, b"graph", Some("main")).await;
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
        // Different bytes, so damping cannot be what saves the tag.
        let after = publish(&store, b"graph-wobble", None).await;
        assert_eq!(
            after.branch.as_deref(),
            Some("main"),
            "an untagged republish keeps the tag someone who knew it recorded"
        );
    }

    #[tokio::test]
    async fn trunk_baseline_tags_stick_against_feature_republishes() {
        let (_temp_dir, _config, store) = temp_store();
        async fn publish(store: &Store, key: &str, bytes: &[u8], branch: Option<&str>) {
            store
                .persist_inline_artifact_from_bytes_damped_and_enqueue(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    "application/x-protobuf",
                    bytes,
                    &[],
                    branch,
                    Some("main"),
                )
                .await
                .expect("action-cache entry should persist");
        }
        // Distinct version_ms per publish: a same-millisecond republish is
        // dropped as stale before any tagging logic runs.
        let tick = || tokio::time::sleep(std::time::Duration::from_millis(2));
        // A feature build recomputing a trunk key (even with byte wobble that
        // defeats damping) must not steal it from the trunk baseline.
        publish(&store, "action_cache/aa/10", b"graph", Some("main")).await;
        tick().await;
        publish(
            &store,
            "action_cache/aa/10",
            b"graph-wobble",
            Some("feature"),
        )
        .await;
        // An untagged entry is NOT in the baseline, so it has nothing to protect:
        // the feature publish below claims it, and it leaves the trunk view.
        publish(&store, "action_cache/bb/10", b"graph", None).await;
        tick().await;
        publish(
            &store,
            "action_cache/bb/10",
            b"graph-wobble",
            Some("feature"),
        )
        .await;
        // A trunk publish reclaims a feature-tagged key.
        publish(&store, "action_cache/cc/10", b"graph", Some("feature")).await;
        tick().await;
        publish(&store, "action_cache/cc/10", b"graph-wobble", Some("main")).await;

        let trunk = store
            .action_cache_manifests("ios", 10, Some("main"))
            .expect("trunk scan should succeed");
        let mut keys: Vec<&str> = trunk.iter().map(|manifest| manifest.key.as_str()).collect();
        keys.sort_unstable();
        assert_eq!(
            keys,
            vec!["action_cache/aa/10", "action_cache/cc/10"],
            "a trunk key survives a feature republish (aa) and is reclaimed by a \
             trunk one (cc); an untagged key is claimed by whoever names a branch (bb)"
        );
    }

    // The tag is a read-modify-write over the stored manifest, so it is only as
    // sound as the serialization around it. Two builds publishing the same shared
    // action concurrently (routine: one namespace, many machines) must not be able
    // to interleave their read and their commit, or the feature build writes the
    // `feature` tag it decided on when the key looked absent, over the `main` the
    // trunk build committed meanwhile, and with a version nothing downstream
    // rejects. The failpoint pins that interleaving instead of racing for it.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_concurrent_feature_publish_cannot_overwrite_the_trunk_tag() {
        let (_temp_dir, _config, store) = temp_store();
        let store = Arc::new(store);
        store.failpoints().set_once(
            FailpointName::AfterInlineManifestReadBeforeCommit,
            FailpointAction::Sleep(std::time::Duration::from_millis(300)),
        );

        let feature_store = Arc::clone(&store);
        // Reads first (and stalls on the failpoint holding nothing but its own
        // read), so it is the one whose decision is stale by the time it writes.
        let feature = tokio::spawn(async move {
            feature_store
                .persist_inline_artifact_from_bytes_damped_and_enqueue(
                    ArtifactProducer::Reapi,
                    "ios",
                    "action_cache/aa/10",
                    "application/x-protobuf",
                    b"graph-from-feature",
                    &[],
                    Some("feature"),
                    Some("main"),
                )
                .await
                .expect("feature publish should persist");
        });
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        let trunk_store = Arc::clone(&store);
        let trunk = tokio::spawn(async move {
            trunk_store
                .persist_inline_artifact_from_bytes_damped_and_enqueue(
                    ArtifactProducer::Reapi,
                    "ios",
                    "action_cache/aa/10",
                    "application/x-protobuf",
                    b"graph-from-trunk",
                    &[],
                    Some("main"),
                    Some("main"),
                )
                .await
                .expect("trunk publish should persist");
        });
        feature.await.expect("feature task");
        trunk.await.expect("trunk task");

        let trunk_view = store
            .action_cache_manifests("ios", 10, Some("main"))
            .expect("trunk scan should succeed");
        let keys: Vec<&str> = trunk_view
            .iter()
            .map(|manifest| manifest.key.as_str())
            .collect();
        assert_eq!(
            keys,
            vec!["action_cache/aa/10"],
            "the key stays in the trunk baseline whichever publish commits first"
        );
    }

    #[tokio::test]
    async fn replicated_entries_carry_their_branch_across_the_mesh() {
        let (_temp_dir, _config, store) = temp_store();
        async fn apply(store: &Store, key: &str, version_ms: u64, branch: Option<&str>) {
            store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    "application/x-protobuf",
                    b"graph",
                    version_ms,
                    branch,
                    None,
                )
                .await
                .expect("replicated entry should apply");
        }
        // A peer's feature entry keeps its tag instead of landing untagged in
        // this node's trunk baseline — the pollution the branch tag exists to
        // prevent, arriving over replication rather than from a client.
        apply(&store, "action_cache/aa/10", 1_000, Some("feature")).await;
        // A message from a node that predates the field carries no branch. It
        // applies untagged, and untagged is not the trunk baseline: an older
        // node's entries do not get to claim trunk by omission.
        apply(&store, "action_cache/bb/10", 1_000, None).await;
        apply(&store, "action_cache/cc/10", 1_000, Some("main")).await;

        let trunk = store
            .action_cache_manifests("ios", 10, Some("main"))
            .expect("trunk scan should succeed");
        let mut keys: Vec<&str> = trunk.iter().map(|manifest| manifest.key.as_str()).collect();
        keys.sort_unstable();
        assert_eq!(
            keys,
            vec!["action_cache/cc/10"],
            "only a replicated entry tagged with the trunk is in the trunk view"
        );
    }

    // An identical re-publish inside the window is damped, which is what keeps a
    // fleet of cold machines from stampeding version bumps for the same entry.
    #[tokio::test]
    async fn identical_trunk_republish_stays_damped_when_the_tag_already_matches() {
        let (_temp_dir, _config, store) = temp_store();
        for _ in 0..1 {
            store
                .persist_inline_artifact_from_bytes_damped_and_enqueue(
                    ArtifactProducer::Reapi,
                    "ios",
                    "action_cache/aa/10",
                    "application/x-protobuf",
                    b"graph",
                    &[],
                    Some("main"),
                    Some("main"),
                )
                .await
                .expect("trunk entry should persist");
        }
        let (_manifest, applied) = store
            .persist_inline_artifact_from_bytes_damped_and_enqueue(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/aa/10",
                "application/x-protobuf",
                b"graph",
                &[],
                Some("main"),
                Some("main"),
            )
            .await
            .expect("identical republish should succeed");
        assert!(!applied, "nothing changes, so the write is damped");
    }

    #[tokio::test]
    async fn replicated_feature_entries_cannot_steal_a_trunk_baseline_key() {
        let (_temp_dir, _config, store) = temp_store();
        // The origin resolves the tag against ITS OWN view, so a feature build
        // publishing a trunk key to a peer that does not hold it yet resolves
        // `feature` and replicates that. This node holds the key in its trunk
        // baseline and must not hand it over.
        store
            .persist_inline_artifact_from_bytes_damped_and_enqueue(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/aa/10",
                "application/x-protobuf",
                b"graph",
                &[],
                Some("main"),
                Some("main"),
            )
            .await
            .expect("trunk entry should persist");
        let seeded = store
            .action_cache_manifests("ios", 10, Some("main"))
            .expect("trunk scan should succeed");
        assert_eq!(seeded.len(), 1, "the key starts in the trunk baseline");

        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/aa/10",
                "application/x-protobuf",
                b"graph-wobble",
                seeded[0].version_ms + 1_000,
                Some("feature"),
                Some("main"),
            )
            .await
            .expect("replicated republish should apply");

        let trunk = store
            .action_cache_manifests("ios", 10, Some("main"))
            .expect("trunk scan should succeed");
        assert_eq!(
            trunk.len(),
            1,
            "the key stays in the trunk view against a replicated feature republish"
        );
        assert_eq!(trunk[0].branch.as_deref(), Some("main"));

        // A replicated publish FROM the trunk still reclaims the key.
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/bb/10",
                "application/x-protobuf",
                b"graph",
                1_000,
                Some("feature"),
                Some("main"),
            )
            .await
            .expect("replicated feature entry should apply");
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/bb/10",
                "application/x-protobuf",
                b"graph-wobble",
                2_000,
                Some("main"),
                Some("main"),
            )
            .await
            .expect("replicated trunk entry should apply");
        let reclaimed = store
            .manifest_from_db(&artifact_storage_id(
                ArtifactProducer::Reapi,
                &store.tenant_id,
                "ios",
                "action_cache/bb/10",
            ))
            .expect("manifest read should succeed")
            .expect("entry should exist");
        assert_eq!(reclaimed.branch.as_deref(), Some("main"));
    }

    #[tokio::test]
    async fn expiry_sweep_deletes_only_stale_action_cache_entries() {
        let (_temp_dir, config, store) = temp_store();
        async fn write(
            store: &Store,
            config: &Config,
            key: &str,
            producer: ArtifactProducer,
            version_ms: u64,
        ) {
            let path = config.tmp_dir.join("uploads").join(key.replace('/', "-"));
            std::fs::write(&path, b"payload").expect("source should write");
            store
                .apply_replicated_artifact_from_path(
                    producer,
                    "ios",
                    key,
                    "application/octet-stream",
                    &path,
                    version_ms,
                )
                .await
                .expect("artifact should persist");
        }
        write(
            &store,
            &config,
            "action_cache/aa/10",
            ArtifactProducer::Reapi,
            1_000,
        )
        .await;
        write(
            &store,
            &config,
            "action_cache/bb/10",
            ArtifactProducer::Reapi,
            9_000,
        )
        .await;
        write(
            &store,
            &config,
            "blob/cc/10",
            ArtifactProducer::Reapi,
            1_000,
        )
        .await;
        write(&store, &config, "artifact", ArtifactProducer::Gradle, 1_000).await;

        let expired = store
            .expire_stale_action_cache_entries(5_000, 100)
            .expect("sweep should succeed");
        assert_eq!(expired, 1, "only the stale action-cache entry expires");

        let exists = |producer, key| {
            store
                .artifact_manifest_exists(producer, "ios", key)
                .expect("existence check should succeed")
        };
        assert!(!exists(ArtifactProducer::Reapi, "action_cache/aa/10"));
        assert!(exists(ArtifactProducer::Reapi, "action_cache/bb/10"));
        assert!(
            exists(ArtifactProducer::Reapi, "blob/cc/10"),
            "blobs are not the sweep's to delete, however old"
        );
        assert!(exists(ArtifactProducer::Gradle, "artifact"));
        assert!(
            store
                .action_cache_manifests("ios", 1_000, None)
                .expect("namespace scan should succeed")
                .iter()
                .all(|manifest| manifest.key != "action_cache/aa/10"),
            "the namespace index entry is deleted with the manifest"
        );

        // The per-sweep cap defers the remainder to the next sweep.
        write(
            &store,
            &config,
            "action_cache/dd/10",
            ArtifactProducer::Reapi,
            1_000,
        )
        .await;
        write(
            &store,
            &config,
            "action_cache/ee/10",
            ArtifactProducer::Reapi,
            1_000,
        )
        .await;
        assert_eq!(
            store
                .expire_stale_action_cache_entries(5_000, 1)
                .expect("capped sweep should succeed"),
            1
        );
        assert_eq!(
            store
                .expire_stale_action_cache_entries(5_000, 100)
                .expect("follow-up sweep should succeed"),
            1
        );
        assert_eq!(
            store
                .expire_stale_action_cache_entries(5_000, 100)
                .expect("idle sweep should succeed"),
            0
        );
    }

    #[tokio::test]
    async fn action_cache_manifest_scan_keeps_only_the_newest_entries() {
        let (_temp_dir, config, store) = temp_store();
        async fn write(store: &Store, config: &Config, key: &str, version_ms: u64) {
            let path = config.tmp_dir.join("uploads").join(key.replace('/', "-"));
            std::fs::write(&path, b"payload").expect("source should write");
            store
                .apply_replicated_artifact_from_path(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    "application/octet-stream",
                    &path,
                    version_ms,
                )
                .await
                .expect("artifact should persist");
        }
        write(&store, &config, "action_cache/aa/10", 1_000).await;
        write(&store, &config, "action_cache/bb/10", 3_000).await;
        write(&store, &config, "action_cache/cc/10", 2_000).await;

        let manifests = store
            .action_cache_manifests("ios", 2, None)
            .expect("scan should succeed");
        let mut keys: Vec<&str> = manifests.iter().map(|m| m.key.as_str()).collect();
        keys.sort_unstable();
        assert_eq!(
            keys,
            vec!["action_cache/bb/10", "action_cache/cc/10"],
            "the cap keeps the newest entries by write time"
        );
        assert_eq!(
            store
                .action_cache_manifests("ios", 10, None)
                .expect("scan should succeed")
                .len(),
            3
        );
    }

    #[tokio::test]
    async fn action_cache_manifest_scan_sheds_mid_scan_at_twice_the_cap() {
        let (_temp_dir, config, store) = temp_store();
        let source = config.tmp_dir.join("uploads").join("payload");
        for version in 1..=5u64 {
            std::fs::write(&source, b"payload").expect("source should write");
            store
                .apply_replicated_artifact_from_path(
                    ArtifactProducer::Reapi,
                    "ios",
                    &format!("action_cache/{version:064}/10"),
                    "application/octet-stream",
                    &source,
                    version * 100,
                )
                .await
                .expect("artifact should persist");
        }
        // Five entries against a cap of two crosses the in-scan shed
        // threshold (2x cap) as well as the final truncation.
        let manifests = store
            .action_cache_manifests("ios", 2, None)
            .expect("scan should succeed");
        let mut versions: Vec<u64> = manifests.iter().map(|m| m.version_ms).collect();
        versions.sort_unstable();
        assert_eq!(versions, vec![400, 500], "newest two survive the shed");
    }

    #[tokio::test]
    async fn action_cache_index_serves_entries_written_after_backfill() {
        let (_temp_dir, config, store) = temp_store();
        let source = config.tmp_dir.join("uploads").join("payload");
        std::fs::write(&source, b"payload").expect("source should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/aa/10",
                "application/octet-stream",
                &source,
                1_000,
            )
            .await
            .expect("artifact should persist");
        // First scan backfills the index; later writes must land in it
        // through the persist path rather than re-scanning the namespace.
        assert_eq!(
            store.action_cache_manifests("ios", 10, None).unwrap().len(),
            1
        );
        std::fs::write(&source, b"payload").expect("source should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/bb/10",
                "application/octet-stream",
                &source,
                2_000,
            )
            .await
            .expect("artifact should persist");
        let manifests = store
            .action_cache_manifests("ios", 10, None)
            .expect("indexed scan should succeed");
        let mut keys: Vec<&str> = manifests.iter().map(|m| m.key.as_str()).collect();
        keys.sort_unstable();
        assert_eq!(keys, vec!["action_cache/aa/10", "action_cache/bb/10"]);
    }

    #[tokio::test]
    async fn action_cache_index_replaces_the_row_on_overwrite() {
        let (_temp_dir, config, store) = temp_store();
        let source = config.tmp_dir.join("uploads").join("payload");
        std::fs::write(&source, b"payload").expect("source should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/aa/10",
                "application/octet-stream",
                &source,
                1_000,
            )
            .await
            .expect("artifact should persist");
        // Backfill, then overwrite the same key at a newer version: the old
        // row must go, or capped indexed scans would double-count the key.
        assert_eq!(
            store.action_cache_manifests("ios", 10, None).unwrap().len(),
            1
        );
        std::fs::write(&source, b"payload").expect("source should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/aa/10",
                "application/octet-stream",
                &source,
                5_000,
            )
            .await
            .expect("overwrite should persist");
        let manifests = store
            .action_cache_manifests("ios", 10, None)
            .expect("indexed scan should succeed");
        assert_eq!(manifests.len(), 1, "one row per live key");
        assert_eq!(manifests[0].version_ms, 5_000);
    }

    #[tokio::test]
    async fn action_cache_index_drops_rows_with_deleted_manifests() {
        let (_temp_dir, config, store) = temp_store();
        let source = config.tmp_dir.join("uploads").join("payload");
        for (hash, version) in [("aa", 1_000_u64), ("bb", 2_000)] {
            std::fs::write(&source, b"payload").expect("source should write");
            store
                .apply_replicated_artifact_from_path(
                    ArtifactProducer::Reapi,
                    "ios",
                    &format!("action_cache/{hash}/10"),
                    "application/octet-stream",
                    &source,
                    version,
                )
                .await
                .expect("artifact should persist");
        }
        assert_eq!(
            store.action_cache_manifests("ios", 10, None).unwrap().len(),
            2
        );
        let expired = store
            .expire_stale_action_cache_entries(1_500, 10)
            .expect("expiry should succeed");
        assert_eq!(expired, 1);
        let manifests = store
            .action_cache_manifests("ios", 10, None)
            .expect("indexed scan should succeed");
        assert_eq!(manifests.len(), 1);
        assert_eq!(manifests[0].key, "action_cache/bb/10");
    }

    #[tokio::test]
    async fn persist_reports_already_present_across_re_uploads() {
        // `already_present` must reflect presence, not the Applied-vs-ignored
        // version outcome: a re-upload takes a newer version and still applies,
        // yet billing must see it as already present.
        let (_temp_dir, _config, store) = temp_store();

        let persisted = store
            .persist_artifact_from_bytes_and_enqueue(
                ArtifactProducer::Reapi,
                "ios",
                "blob/abc",
                "application/octet-stream",
                b"payload",
                &[],
            )
            .await
            .expect("first persist should succeed");
        assert!(
            !persisted.already_present,
            "first persist of a key should report the artifact as newly stored"
        );

        let re_persisted = store
            .persist_artifact_from_bytes_and_enqueue(
                ArtifactProducer::Reapi,
                "ios",
                "blob/abc",
                "application/octet-stream",
                b"payload",
                &[],
            )
            .await
            .expect("re-persist should succeed");
        assert!(
            re_persisted.already_present,
            "a re-upload of a stored key should report the artifact as already present"
        );
    }

    #[tokio::test]
    async fn concurrent_persists_of_same_missing_key_report_one_not_present() {
        // `already_present` is evaluated under the per-artifact write lock, so
        // concurrent uploads of the same missing key must resolve to exactly one
        // "newly stored" — the signal billing uses to avoid double-charging the
        // losers of the race. The sleep failpoint holds the first writer between
        // its durable append and metadata commit so the others genuinely overlap.
        let (_temp_dir, _config, store) = temp_store();
        store.failpoints().set_always(
            FailpointName::AfterArtifactBytesDurableBeforeMetadata,
            FailpointAction::Sleep(std::time::Duration::from_millis(150)),
        );

        let persists = (0..4).map(|_| {
            store.persist_artifact_from_bytes_and_enqueue(
                ArtifactProducer::Reapi,
                "ios",
                "blob/raced",
                "application/octet-stream",
                b"payload",
                &[],
            )
        });
        let outcomes = futures_util::future::join_all(persists).await;

        let newly_stored = outcomes
            .into_iter()
            .map(|outcome| outcome.expect("persist should succeed"))
            .filter(|persisted| !persisted.already_present)
            .count();
        assert_eq!(
            newly_stored, 1,
            "exactly one concurrent persist of a missing key should report it as newly stored"
        );
    }

    #[tokio::test]
    async fn persist_and_fetch_segment_backed_artifact_round_trip() {
        let (_temp_dir, _config, store) = temp_store();

        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");

        assert!(
            store
                .artifact_exists(ArtifactProducer::Xcode, "ios", "artifact-1")
                .await
                .expect("failed to check artifact existence")
        );

        let fetched = store
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact-1")
            .await
            .expect("failed to fetch artifact")
            .expect("artifact should exist");

        assert_eq!(fetched, manifest);
        assert!(manifest.is_segment_backed());
        assert_eq!(read_manifest_bytes(&store, &manifest).await, b"hello");
        assert_eq!(store.segment_handles.lock().await.len(), 1);
        let raw = store
            .db
            .get_cf(
                store.cf(ROCKSDB_CF_MANIFESTS),
                manifest.artifact_id.as_bytes(),
            )
            .expect("failed to read raw manifest bytes")
            .expect("manifest bytes should exist");
        assert_eq!(
            raw[0], 2,
            "segment-backed manifest should use compact record"
        );
    }

    #[tokio::test]
    async fn mmap_artifact_bytes_is_opportunistic_under_memory_pressure() {
        let (_temp_dir, config, store) = temp_store();

        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");

        let mmap_bytes = store
            .try_mmap_artifact_bytes(&manifest)
            .await
            .expect("mmap lookup should not fail")
            .expect("normal memory pressure should permit mmap serving");
        assert_eq!(&mmap_bytes[..], b"hello");

        store.memory.observe(config.memory_soft_limit_bytes);
        let mmap_bytes = store
            .try_mmap_artifact_bytes(&manifest)
            .await
            .expect("mmap lookup should not fail");

        assert!(mmap_bytes.is_none());
    }

    #[tokio::test]
    async fn mmap_artifact_bytes_maps_non_zero_segment_offsets() {
        let (_temp_dir, _config, store) = temp_store();

        let first = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-first",
                "application/octet-stream",
                b"first-artifact-payload",
            )
            .await
            .expect("failed to persist first artifact");

        let second = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-second",
                "application/octet-stream",
                b"second-artifact-payload",
            )
            .await
            .expect("failed to persist second artifact");

        assert_eq!(
            first.segment_id, second.segment_id,
            "both artifacts should share the same append-only segment"
        );
        assert!(
            second.segment_offset.unwrap_or(0) > first.segment_offset.unwrap_or(0),
            "second artifact should land at a non-zero offset within the segment"
        );

        let mmap_bytes = store
            .try_mmap_artifact_bytes(&second)
            .await
            .expect("mmap lookup should not fail")
            .expect("normal memory pressure should permit mmap serving");

        assert_eq!(&mmap_bytes[..], b"second-artifact-payload");
    }

    #[tokio::test]
    async fn artifact_exists_cache_is_invalidated_by_namespace_delete() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");

        assert!(
            store
                .artifact_exists(ArtifactProducer::Xcode, "ios", "artifact-1")
                .await
                .expect("failed to check artifact existence")
        );

        store
            .delete_namespace("ios")
            .await
            .expect("failed to delete namespace");

        assert!(
            !store
                .artifact_exists(ArtifactProducer::Xcode, "ios", "artifact-1")
                .await
                .expect("failed to re-check artifact existence")
        );
    }

    #[tokio::test]
    async fn artifact_exists_cache_is_invalidated_by_replicated_namespace_delete() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
                100,
            )
            .await
            .expect("failed to apply replicated artifact");

        assert!(
            store
                .artifact_exists(ArtifactProducer::Xcode, "ios", "artifact-1")
                .await
                .expect("failed to check artifact existence")
        );

        assert!(
            store
                .apply_replicated_namespace_delete("ios", 200)
                .await
                .expect("failed to apply replicated namespace delete")
                .applied()
        );

        assert!(
            !store
                .artifact_exists(ArtifactProducer::Xcode, "ios", "artifact-1")
                .await
                .expect("failed to re-check artifact existence")
        );
    }

    #[test]
    fn existence_cache_expires_entries_after_ttl() {
        let mut cache = ExistenceCache::new(8, Duration::from_millis(10));
        cache.insert("artifact-1".into());
        assert!(cache.contains("artifact-1"));
        std::thread::sleep(Duration::from_millis(20));
        assert!(!cache.contains("artifact-1"));
    }

    #[test]
    fn existence_cache_evicts_least_recently_used() {
        let mut cache = ExistenceCache::new(3, Duration::from_secs(60));
        for id in ["a", "b", "c"] {
            cache.insert(id.into());
        }
        // Touch "a" so "b" becomes the least-recently-used entry.
        assert!(cache.contains("a"));
        cache.insert("d".into());

        assert!(!cache.contains("b"), "LRU entry should have been evicted");
        for id in ["a", "c", "d"] {
            assert!(cache.contains(id), "{id} should still be present");
        }
    }

    #[test]
    fn existence_cache_bounds_size_and_mirrors_index_past_capacity() {
        let capacity = 64;
        let mut cache = ExistenceCache::new(capacity, Duration::from_secs(60));
        // Insert far past capacity: O(log n) eviction must keep the entry map
        // and its access-order mirror bounded and equal in size.
        for index in 0..capacity * 20 {
            cache.insert(format!("artifact-{index}"));
        }
        assert_eq!(cache.entries.len(), capacity);
        assert_eq!(
            cache.access.order.len(),
            cache.entries.len(),
            "access-order index must mirror the entry map exactly"
        );
        // The most recently inserted entry survives.
        assert!(cache.contains(&format!("artifact-{}", capacity * 20 - 1)));
    }

    #[tokio::test]
    async fn persist_and_fetch_rocksdb_backed_keyvalue_round_trip() {
        let (_temp_dir, _config, store) = temp_store();

        let manifest = store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/json",
                br#"{"hello":"world"}"#,
            )
            .await
            .expect("failed to persist artifact");

        assert!(!manifest.is_segment_backed());
        assert!(manifest.blob_path.is_none());
        assert!(manifest.segment_id.is_none());
        assert_eq!(
            store
                .inline_bytes(&manifest.artifact_id)
                .expect("failed to read inline bytes")
                .expect("inline bytes should exist"),
            br#"{"hello":"world"}"#
        );
        assert_eq!(
            store
                .fetch_inline_artifact_bytes(ArtifactProducer::Xcode, "ios", "artifact-1")
                .expect("failed to fetch inline artifact bytes")
                .expect("inline artifact bytes should exist"),
            br#"{"hello":"world"}"#
        );
        assert_eq!(
            read_manifest_bytes(&store, &manifest).await,
            br#"{"hello":"world"}"#
        );
        let raw = store
            .db
            .get_cf(
                store.cf(ROCKSDB_CF_MANIFESTS),
                manifest.artifact_id.as_bytes(),
            )
            .expect("failed to read raw manifest bytes")
            .expect("manifest bytes should exist");
        assert_eq!(
            raw[0], b'{',
            "keyvalue manifest should keep json encoding for now"
        );
    }

    #[tokio::test]
    async fn manifest_index_rebuilds_from_rocksdb_on_restart() {
        let (_temp_dir, config, store) = temp_store();
        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Module,
                "ios",
                "builds/hash-1/Module.framework",
                "application/octet-stream",
                b"module-bytes",
            )
            .await
            .expect("failed to persist artifact");

        drop(store);

        let reopened_metrics = Metrics::new(config.region.clone(), config.tenant_id.clone());
        let reopened_io = IoController::new(
            reopened_metrics,
            config.file_descriptor_pool_size,
            std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
            vec![config.tmp_dir.clone(), config.data_dir.clone()],
        )
        .expect("failed to create reopened io controller");
        let reopened_memory = MemoryController::new(
            reopened_io.metrics(),
            config.memory_soft_limit_bytes,
            config.memory_hard_limit_bytes,
        );
        let reopened =
            Store::open(&config, reopened_io, reopened_memory).expect("failed to reopen store");

        let rebuilt = reopened
            .manifest(&manifest.artifact_id)
            .expect("manifest lookup should succeed")
            .expect("manifest should be present after rebuild");
        assert_eq!(rebuilt, manifest);
        assert_eq!(
            read_manifest_bytes(&reopened, &rebuilt).await,
            b"module-bytes"
        );
    }

    fn reopen_store(config: &Config) -> Store {
        let metrics = Metrics::new(config.region.clone(), config.tenant_id.clone());
        let io = IoController::new(
            metrics,
            config.file_descriptor_pool_size,
            std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
            vec![config.tmp_dir.clone(), config.data_dir.clone()],
        )
        .expect("failed to create reopened io controller");
        let memory = MemoryController::new(
            io.metrics(),
            config.memory_soft_limit_bytes,
            config.memory_hard_limit_bytes,
        );
        Store::open(config, io, memory).expect("failed to reopen store")
    }

    /// Forces a rotation of the (non-empty) active segment and returns the
    /// sealed segment's id.
    async fn seal_active_segment(store: &Store) -> String {
        let outgoing = store
            .segment_state_snapshot()
            .state
            .active()
            .expect("an active segment should exist")
            .segment_id
            .clone();
        store
            .active_segment(MAX_SEGMENT_BYTES)
            .await
            .expect("rotation should seal the active segment");
        outgoing
    }

    fn ring_reference(store: &Store, segment_id: &str) -> SegmentReference {
        let snapshot = store.segment_state_snapshot();
        snapshot
            .state
            .old
            .iter()
            .chain(snapshot.state.current.iter())
            .chain(snapshot.state.new.iter())
            .find(|reference| reference.segment_id == segment_id)
            .expect("segment should still be in the ring")
            .clone()
    }

    async fn stage_deferred_segmented(
        store: &Store,
        config: &Config,
        batch: &mut BackfillApplyBatch,
        key: &str,
        body: &[u8],
        version_ms: u64,
    ) -> BackfillStageOutcome {
        let path = config
            .tmp_dir
            .join("uploads")
            .join(format!("staged-{key}-{version_ms}"));
        std::fs::write(&path, body).expect("staged source should write");
        store
            .stage_backfill_segmented_apply(
                batch,
                ArtifactProducer::Gradle,
                "ios",
                key,
                "application/octet-stream",
                StagedArtifactPath::new(&path, FileCachePolicy::Adaptive),
                version_ms,
            )
            .await
            .expect("segmented record should stage")
    }

    async fn stage_deferred_inline(
        store: &Store,
        batch: &mut BackfillApplyBatch,
        producer: ArtifactProducer,
        key: &str,
        body: &[u8],
        version_ms: u64,
    ) -> BackfillStageOutcome {
        store
            .stage_backfill_inline_apply(
                batch,
                producer,
                "ios",
                key,
                "application/octet-stream",
                body,
                version_ms,
                None,
            )
            .await
            .expect("inline record should stage")
    }

    /// Every action-cache index row (key and value) under `namespace_id`,
    /// for comparing index maintenance across apply paths.
    fn action_cache_index_rows(store: &Store, namespace_id: &str) -> Vec<(Vec<u8>, Vec<u8>)> {
        let prefix = action_cache_index_prefix(namespace_id);
        store
            .db
            .iterator_cf(
                store.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
                IteratorMode::From(&prefix, rocksdb::Direction::Forward),
            )
            .map(|entry| entry.expect("action cache index row should read"))
            .take_while(|(key, _)| key.starts_with(&prefix))
            .map(|(key, value)| (key.to_vec(), value.to_vec()))
            .collect()
    }

    #[tokio::test]
    async fn deferred_batch_apply_matches_per_record_sync_state() {
        let (_sync_dir, _sync_config, sync_store) = temp_store();
        let (_deferred_dir, deferred_config, deferred_store) = temp_store();

        let segmented = [
            ("seg-a", vec![0xA1_u8; 64 * 1024], 1_000_u64),
            ("seg-b", vec![0xB2_u8; 8 * 1024], 900),
        ];
        let inline_body = b"inline-body".to_vec();
        // A REAPI action-cache entry, so the equivalence check covers the
        // action-cache index rows the inline staging maintains.
        let action_cache_key = "action_cache/0badc0de";
        let action_cache_body = b"action-result".to_vec();

        for (key, body, version_ms) in &segmented {
            sync_store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    key,
                    "application/octet-stream",
                    body,
                    *version_ms,
                )
                .await
                .expect("sync segmented apply should succeed");
        }
        for (producer, key, body, version_ms) in [
            (ArtifactProducer::Xcode, "inl-c", &inline_body, 800),
            (
                ArtifactProducer::Reapi,
                action_cache_key,
                &action_cache_body,
                700,
            ),
        ] {
            sync_store
                .apply_replicated_inline_artifact_from_bytes(
                    producer,
                    "ios",
                    key,
                    "application/octet-stream",
                    body,
                    version_ms,
                    None,
                    None,
                )
                .await
                .expect("sync inline apply should succeed");
        }

        let mut batch = BackfillApplyBatch::new();
        for (key, body, version_ms) in &segmented {
            let staged = stage_deferred_segmented(
                &deferred_store,
                &deferred_config,
                &mut batch,
                key,
                body,
                *version_ms,
            )
            .await;
            assert_eq!(staged, BackfillStageOutcome::Staged);
        }
        for (producer, key, body, version_ms) in [
            (ArtifactProducer::Xcode, "inl-c", &inline_body, 800),
            (
                ArtifactProducer::Reapi,
                action_cache_key,
                &action_cache_body,
                700,
            ),
        ] {
            let staged =
                stage_deferred_inline(&deferred_store, &mut batch, producer, key, body, version_ms)
                    .await;
            assert_eq!(staged, BackfillStageOutcome::Staged);
        }
        let mut resolved = 0_usize;
        deferred_store
            .commit_backfill_apply_batch(batch, |group_len| resolved += group_len)
            .await
            .expect("deferred batch should commit");
        assert_eq!(resolved, 4, "every staged record resolves with its group");

        let mut expectations: Vec<(ArtifactProducer, &str, &[u8])> = segmented
            .iter()
            .map(|(key, body, _)| (ArtifactProducer::Gradle, *key, body.as_slice()))
            .collect();
        expectations.push((ArtifactProducer::Xcode, "inl-c", inline_body.as_slice()));
        expectations.push((
            ArtifactProducer::Reapi,
            action_cache_key,
            action_cache_body.as_slice(),
        ));
        for (producer, key, body) in expectations {
            let sync_manifest = sync_store
                .fetch_artifact(producer, "ios", key)
                .await
                .expect("sync fetch should succeed")
                .expect("sync record should exist");
            let deferred_manifest = deferred_store
                .fetch_artifact(producer, "ios", key)
                .await
                .expect("deferred fetch should succeed")
                .expect("deferred record should exist");
            // Everything but the segment identity (fresh UUID per store) must
            // match the per-record sync outcome exactly.
            assert_eq!(deferred_manifest.artifact_id, sync_manifest.artifact_id);
            assert_eq!(deferred_manifest.version_ms, sync_manifest.version_ms);
            assert_eq!(deferred_manifest.created_at_ms, sync_manifest.created_at_ms);
            assert_eq!(deferred_manifest.size, sync_manifest.size);
            assert_eq!(deferred_manifest.inline, sync_manifest.inline);
            assert_eq!(deferred_manifest.content_type, sync_manifest.content_type);
            assert_eq!(deferred_manifest.branch, sync_manifest.branch);
            assert_eq!(deferred_manifest.blob_path, sync_manifest.blob_path);
            assert_eq!(
                read_manifest_bytes(&deferred_store, &deferred_manifest).await,
                body
            );
            assert_eq!(read_manifest_bytes(&sync_store, &sync_manifest).await, body);
        }

        let sync_rows = sync_store
            .backfill_index_page(None, 16)
            .expect("sync index page should read");
        let deferred_rows = deferred_store
            .backfill_index_page(None, 16)
            .expect("deferred index page should read");
        assert_eq!(deferred_rows.entries, sync_rows.entries);
        assert_eq!(sync_rows.entries.len(), 4);

        let sync_index = action_cache_index_rows(&sync_store, "ios");
        let deferred_index = action_cache_index_rows(&deferred_store, "ios");
        assert_eq!(deferred_index, sync_index);
        assert_eq!(sync_index.len(), 1);
    }

    #[tokio::test]
    async fn deferred_batch_rotation_mid_batch_keeps_every_body_readable_after_reopen() {
        let (_temp_dir, config, store) = temp_store();
        let first_body = vec![0x11_u8; 32 * 1024];
        let second_body = vec![0x22_u8; 32 * 1024];

        let mut batch = BackfillApplyBatch::new();
        stage_deferred_segmented(&store, &config, &mut batch, "rot-a", &first_body, 1_000).await;
        // Rotate mid-batch: the first record's segment seals (and is fsynced
        // by the rotation) while the second lands in the fresh active
        // segment, which phase 2's group-commit fsync covers.
        let sealed_id = seal_active_segment(&store).await;
        stage_deferred_segmented(&store, &config, &mut batch, "rot-b", &second_body, 1_100).await;
        store
            .commit_backfill_apply_batch(batch, |_| {})
            .await
            .expect("deferred batch should commit across the rotation");

        let first = store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "rot-a")
            .await
            .expect("first fetch should succeed")
            .expect("first record should exist");
        let second = store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "rot-b")
            .await
            .expect("second fetch should succeed")
            .expect("second record should exist");
        assert_eq!(first.segment_id.as_deref(), Some(sealed_id.as_str()));
        assert_ne!(first.segment_id, second.segment_id);
        assert_eq!(read_manifest_bytes(&store, &first).await, first_body);
        assert_eq!(read_manifest_bytes(&store, &second).await, second_body);

        drop(store);
        let store = reopen_store(&config);
        for (key, body) in [("rot-a", &first_body), ("rot-b", &second_body)] {
            let manifest = store
                .fetch_artifact(ArtifactProducer::Gradle, "ios", key)
                .await
                .expect("post-reopen fetch should succeed")
                .expect("record should survive reopen");
            assert_eq!(read_manifest_bytes(&store, &manifest).await, *body);
        }
    }

    #[tokio::test]
    async fn live_apply_paths_keep_per_record_sync_commits() {
        let (_temp_dir, config, store) = temp_store();
        // Warm the store so the active segment exists: the first append's
        // ring-state initialization would otherwise pollute the deltas below.
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "warm",
                "application/octet-stream",
                b"warm-body",
                100,
            )
            .await
            .expect("warm apply should succeed");

        // Live replicated applies commit sync, never deferred, and never
        // flush the WAL as a separate barrier.
        let (sync_before, deferred_before, flush_before) = store.wal_write_counts();
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "live-seg",
                "application/octet-stream",
                b"live-segment-body",
                1_000,
            )
            .await
            .expect("live segmented apply should succeed");
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "live-inl",
                "application/octet-stream",
                b"live-inline-body",
                900,
                None,
                None,
            )
            .await
            .expect("live inline apply should succeed");
        let (sync_after, deferred_after, flush_after) = store.wal_write_counts();
        assert_eq!(
            deferred_after, deferred_before,
            "live applies must not take deferred commits"
        );
        assert_eq!(flush_after, flush_before);
        assert!(sync_after >= sync_before + 2);

        // The backfill batch path is the inverse: ceil(records / group size)
        // deferred group commits plus one WAL-flush barrier, zero sync
        // commits. Two staged records fit one group.
        let (sync_before, deferred_before, flush_before) = store.wal_write_counts();
        let mut batch = BackfillApplyBatch::new();
        stage_deferred_segmented(
            &store,
            &config,
            &mut batch,
            "bf-seg",
            b"bf-segment-body",
            2_000,
        )
        .await;
        stage_deferred_inline(
            &store,
            &mut batch,
            ArtifactProducer::Xcode,
            "bf-inl",
            b"bf-inline-body",
            1_900,
        )
        .await;
        store
            .commit_backfill_apply_batch(batch, |_| {})
            .await
            .expect("deferred batch should commit");
        let (sync_after, deferred_after, flush_after) = store.wal_write_counts();
        assert_eq!(
            sync_after, sync_before,
            "the backfill batch path must not take per-record sync commits"
        );
        assert_eq!(deferred_after, deferred_before + 1);
        assert_eq!(flush_after, flush_before + 1);

        // One record over the group bound splits into exactly two group
        // WriteBatches, still under one WAL-flush barrier.
        let (sync_before, deferred_before, flush_before) = store.wal_write_counts();
        let mut batch = BackfillApplyBatch::new();
        for index in 0..=BACKFILL_APPLY_GROUP_RECORDS {
            stage_deferred_inline(
                &store,
                &mut batch,
                ArtifactProducer::Xcode,
                &format!("bf-grp-{index:03}"),
                b"group-body",
                3_000 + index as u64,
            )
            .await;
        }
        let mut group_lens = Vec::new();
        store
            .commit_backfill_apply_batch(batch, |group_len| group_lens.push(group_len))
            .await
            .expect("deferred batch should commit");
        let (sync_after, deferred_after, flush_after) = store.wal_write_counts();
        assert_eq!(sync_after, sync_before);
        assert_eq!(deferred_after, deferred_before + 2);
        assert_eq!(flush_after, flush_before + 1);
        assert_eq!(group_lens, vec![BACKFILL_APPLY_GROUP_RECORDS, 1]);
    }

    #[tokio::test]
    async fn group_commit_skips_records_superseded_between_staging_and_commit() {
        let (_temp_dir, config, store) = temp_store();

        let mut batch = BackfillApplyBatch::new();
        assert_eq!(
            stage_deferred_segmented(&store, &config, &mut batch, "sup-seg", b"stale-seg", 1_000)
                .await,
            BackfillStageOutcome::Staged
        );
        assert_eq!(
            stage_deferred_inline(
                &store,
                &mut batch,
                ArtifactProducer::Xcode,
                "sup-inl",
                b"stale-inline",
                900,
            )
            .await,
            BackfillStageOutcome::Staged
        );
        assert_eq!(
            stage_deferred_segmented(&store, &config, &mut batch, "ok-seg", b"good-seg", 500).await,
            BackfillStageOutcome::Staged
        );

        // Concurrent newer writes land between staging and the group commit;
        // the phase-3 authoritative re-check must skip the staged records
        // without corrupting the rest of the group.
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "sup-seg",
                "application/octet-stream",
                b"newer-seg",
                2_000,
            )
            .await
            .expect("concurrent segmented apply should succeed");
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "sup-inl",
                "application/octet-stream",
                b"newer-inline",
                1_900,
                None,
                None,
            )
            .await
            .expect("concurrent inline apply should succeed");

        let mut resolved = 0_usize;
        store
            .commit_backfill_apply_batch(batch, |group_len| resolved += group_len)
            .await
            .expect("deferred batch should commit");
        // Skipped records still count in their group's callback: they are
        // converged (the concurrent write is what the store serves) and
        // resolve like the per-record path resolved an LWW-ignored apply.
        assert_eq!(resolved, 3);

        let superseded_seg = store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "sup-seg")
            .await
            .expect("fetch should succeed")
            .expect("record should exist");
        assert_eq!(superseded_seg.version_ms, 2_000);
        assert_eq!(
            read_manifest_bytes(&store, &superseded_seg).await,
            b"newer-seg"
        );
        let superseded_inl = store
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "sup-inl")
            .await
            .expect("fetch should succeed")
            .expect("record should exist");
        assert_eq!(superseded_inl.version_ms, 1_900);
        assert_eq!(
            read_manifest_bytes(&store, &superseded_inl).await,
            b"newer-inline"
        );
        let committed = store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "ok-seg")
            .await
            .expect("fetch should succeed")
            .expect("record should exist");
        assert_eq!(committed.version_ms, 500);
        assert_eq!(read_manifest_bytes(&store, &committed).await, b"good-seg");
    }

    #[tokio::test]
    async fn sealing_stamps_the_max_version_of_mixed_appends() {
        let (_temp_dir, _config, store) = temp_store();
        for (key, version_ms) in [
            ("artifact-a", 300),
            ("artifact-b", 100),
            ("artifact-c", 200),
        ] {
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    key,
                    "application/octet-stream",
                    b"bytes",
                    version_ms,
                )
                .await
                .expect("artifact should apply");
        }

        let sealed_id = seal_active_segment(&store).await;

        assert_eq!(ring_reference(&store, &sealed_id).max_version_ms, Some(300));
        // The freshly opened active segment starts without the stat.
        assert_eq!(
            store
                .segment_state_snapshot()
                .state
                .active()
                .expect("rotation should open a new active segment")
                .max_version_ms,
            None
        );
    }

    #[tokio::test]
    async fn promotion_of_an_old_entry_never_lowers_the_running_max() {
        let (_temp_dir, _config, store) = temp_store();
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "old-artifact",
                "application/octet-stream",
                b"old-bytes",
                1_000,
            )
            .await
            .expect("old artifact should apply");
        let old_artifact_id = artifact_storage_id(
            ArtifactProducer::Xcode,
            &store.tenant_id,
            "ios",
            "old-artifact",
        );
        let old_manifest = store
            .manifest(&old_artifact_id)
            .expect("manifest lookup should succeed")
            .expect("old artifact manifest should exist");
        let old_segment_id = old_manifest
            .segment_id
            .clone()
            .expect("segment-backed artifact should have a segment id");
        store
            .save_segment_state(&SegmentState {
                old: vec![SegmentReference::new(old_segment_id, 1)],
                current: Vec::new(),
                new: vec![SegmentReference::new("fresh-segment".into(), 2)],
            })
            .expect("failed to seed segment state");

        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "hot-artifact",
                "application/octet-stream",
                b"hot-bytes",
                9_000,
            )
            .await
            .expect("hot artifact should apply");
        let promoted = store
            .maybe_refresh_manifest(old_manifest, RefreshTrigger::Serve)
            .await
            .expect("promotion should succeed")
            .expect("promoted manifest should exist");
        assert_eq!(promoted.segment_id.as_deref(), Some("fresh-segment"));

        let sealed_id = seal_active_segment(&store).await;

        assert_eq!(sealed_id, "fresh-segment");
        assert_eq!(
            ring_reference(&store, &sealed_id).max_version_ms,
            Some(9_000)
        );
    }

    #[tokio::test]
    async fn restart_mid_active_segment_rederives_the_running_max() {
        let (_temp_dir, config, store) = temp_store();
        for (key, version_ms) in [("artifact-a", 300), ("artifact-b", 100)] {
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    key,
                    "application/octet-stream",
                    b"bytes",
                    version_ms,
                )
                .await
                .expect("artifact should apply");
        }
        drop(store);

        let store = reopen_store(&config);
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-c",
                "application/octet-stream",
                b"bytes",
                200,
            )
            .await
            .expect("artifact should apply after restart");

        // The sealed stat matches what a run without the restart would stamp.
        let sealed_id = seal_active_segment(&store).await;
        assert_eq!(ring_reference(&store, &sealed_id).max_version_ms, Some(300));
    }

    #[tokio::test]
    async fn rederivation_falls_back_to_created_at_for_zero_version_manifests() {
        let (_temp_dir, config, store) = temp_store();
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "legacy-artifact",
                "application/octet-stream",
                b"legacy-bytes",
                1_111,
            )
            .await
            .expect("artifact should apply");
        let artifact_id = artifact_storage_id(
            ArtifactProducer::Xcode,
            &store.tenant_id,
            "ios",
            "legacy-artifact",
        );
        // Rewrite the stored manifest into the legacy shape (version_ms == 0),
        // which no current write path produces.
        let mut manifest = store
            .manifest_from_db(&artifact_id)
            .expect("manifest lookup should succeed")
            .expect("manifest should exist");
        manifest.version_ms = 0;
        manifest.created_at_ms = 4_321;
        store
            .db
            .put_cf(
                store.cf(ROCKSDB_CF_MANIFESTS),
                artifact_id.as_bytes(),
                encode_manifest_record(&manifest).expect("manifest should encode"),
            )
            .expect("manifest rewrite should succeed");
        drop(store);

        let store = reopen_store(&config);
        let sealed_id = seal_active_segment(&store).await;

        assert_eq!(
            ring_reference(&store, &sealed_id).max_version_ms,
            Some(4_321)
        );
    }

    #[tokio::test]
    async fn late_manifest_commit_raises_a_sealed_reference_in_place() {
        let (_temp_dir, _config, store) = temp_store();
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-a",
                "application/octet-stream",
                b"bytes",
                500,
            )
            .await
            .expect("artifact should apply");
        let sealed_id = seal_active_segment(&store).await;
        assert_eq!(ring_reference(&store, &sealed_id).max_version_ms, Some(500));

        // A manifest commit that lost the race with the rotation raises the
        // sealed reference directly; a stale one never lowers it.
        store
            .note_segment_version(&sealed_id, 900)
            .await
            .expect("late raise should succeed");
        assert_eq!(ring_reference(&store, &sealed_id).max_version_ms, Some(900));
        store
            .note_segment_version(&sealed_id, 700)
            .await
            .expect("stale raise should succeed");
        assert_eq!(ring_reference(&store, &sealed_id).max_version_ms, Some(900));
    }

    #[tokio::test]
    async fn segment_state_persisted_by_the_previous_release_loads_cleanly() {
        let (_temp_dir, _config, store) = temp_store();
        // The exact JSON a pre-stat release persists for the ring.
        let legacy_json =
            br#"{"old":[],"current":[],"new":[{"segment_id":"legacy-segment","created_at_ms":5}]}"#;
        store
            .db
            .put_cf(store.cf(ROCKSDB_CF_SEGMENT_STATE), b"shared", legacy_json)
            .expect("legacy ring state should persist");

        let state = store
            .load_segment_state_from_db()
            .expect("legacy ring state should load");

        let active = state.active().expect("active segment should exist");
        assert_eq!(active.max_version_ms, None);
        assert_eq!(active.effective_max_version_ms(), 5);
    }

    #[tokio::test]
    async fn manifests_page_returns_results_in_artifact_id_order() {
        let (_temp_dir, _config, store) = temp_store();

        let first = store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "action-a",
                "application/json",
                br#"{"a":1}"#,
            )
            .await
            .expect("failed to persist first artifact");
        let second = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact-b",
                "application/octet-stream",
                b"gradle",
            )
            .await
            .expect("failed to persist second artifact");

        let first_page = store
            .manifests_page(None, 1)
            .expect("failed to load first manifest page");
        assert_eq!(first_page.manifests.len(), 1);
        assert!(
            first_page.manifests[0].artifact_id == first.artifact_id
                || first_page.manifests[0].artifact_id == second.artifact_id
        );
        assert_eq!(
            first_page.next_after,
            Some(first_page.manifests[0].artifact_id.clone())
        );

        let second_page = store
            .manifests_page(first_page.next_after.as_deref(), 1)
            .expect("failed to load second manifest page");
        assert_eq!(second_page.manifests.len(), 1);
        assert_ne!(
            second_page.manifests[0].artifact_id,
            first_page.manifests[0].artifact_id
        );
        assert!(
            second_page.manifests[0].artifact_id == first.artifact_id
                || second_page.manifests[0].artifact_id == second.artifact_id
        );
    }

    #[tokio::test]
    async fn namespace_tombstones_returns_written_tombstones() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .apply_replicated_namespace_delete("ios", 100)
            .await
            .expect("failed to apply first tombstone");
        store
            .apply_replicated_namespace_delete("android", 200)
            .await
            .expect("failed to apply second tombstone");

        let tombstones = store
            .namespace_tombstones()
            .expect("failed to load tombstones");
        assert_eq!(
            tombstones,
            vec![("android".to_owned(), 200), ("ios".to_owned(), 100)]
        );
    }

    #[tokio::test]
    async fn manifest_cache_stays_within_configured_byte_budget() {
        let (_temp_dir, _config, store) = temp_store_with(|config| {
            config.manifest_cache_max_bytes = 256;
        });

        let first = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"first",
            )
            .await
            .expect("failed to persist first artifact");
        let second = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact-2",
                "application/octet-stream",
                b"second",
            )
            .await
            .expect("failed to persist second artifact");

        {
            let cache = store
                .manifest_cache
                .lock()
                .expect("manifest cache lock poisoned");
            assert!(
                cache.total_bytes() <= 256,
                "manifest cache should stay within its configured byte budget"
            );
            assert!(
                cache.len() < 2,
                "manifest cache should evict once it cannot hold every manifest"
            );
        }

        store.trim_manifest_cache_to(0, "test");
        let reloaded = store
            .manifest(&first.artifact_id)
            .expect("manifest lookup should succeed")
            .expect("first manifest should reload from RocksDB");
        assert_eq!(reloaded.artifact_id, first.artifact_id);
        let reloaded = store
            .manifest(&second.artifact_id)
            .expect("manifest lookup should succeed")
            .expect("second manifest should reload from RocksDB");
        assert_eq!(reloaded.artifact_id, second.artifact_id);
    }

    #[tokio::test]
    async fn segment_handle_cache_evicts_least_recently_used_handles_when_full() {
        let (_temp_dir, _config, store) = temp_store_with(|config| {
            config.segment_handle_cache_size = 1;
        });

        let xcode = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"xcode",
            )
            .await
            .expect("failed to persist xcode artifact");
        let gradle = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "android",
                "artifact-2",
                "application/octet-stream",
                b"gradle",
            )
            .await
            .expect("failed to persist gradle artifact");

        let _ = read_manifest_bytes(&store, &xcode).await;
        {
            let cache = store.segment_handles.lock().await;
            assert_eq!(cache.len(), 1);
            assert!(
                cache.entries.contains_key(&segment_handle_cache_key(
                    xcode
                        .segment_id
                        .as_deref()
                        .expect("xcode manifest should have a segment id")
                ))
            );
        }

        let _ = read_manifest_bytes(&store, &gradle).await;
        {
            let cache = store.segment_handles.lock().await;
            assert_eq!(cache.len(), 1);
            assert!(
                cache.entries.contains_key(&segment_handle_cache_key(
                    gradle
                        .segment_id
                        .as_deref()
                        .expect("gradle manifest should have a segment id")
                ))
            );
            if xcode.segment_id != gradle.segment_id {
                assert!(
                    !cache.entries.contains_key(&segment_handle_cache_key(
                        xcode
                            .segment_id
                            .as_deref()
                            .expect("xcode manifest should have a segment id")
                    ))
                );
            }
        }
    }

    #[tokio::test]
    async fn blob_handle_cache_is_bounded_and_dropped_before_namespace_delete() {
        let (_temp_dir, config, store) = temp_store_with(|config| {
            config.segment_handle_cache_size = 1;
        });
        let blob_path = config.data_dir.join("blobs").join("legacy-blob");
        std::fs::write(&blob_path, b"legacy-blob-payload").expect("failed to write blob");
        let blob_path_string = blob_path.to_string_lossy().into_owned();
        let artifact_id = artifact_storage_id(
            ArtifactProducer::Module,
            &config.tenant_id,
            "ios",
            "legacy-key",
        );
        let manifest = ArtifactManifest {
            artifact_id: artifact_id.clone(),
            producer: ArtifactProducer::Module,
            namespace_id: "ios".to_owned(),
            key: "legacy-key".to_owned(),
            content_type: "application/octet-stream".to_owned(),
            inline: false,
            blob_path: Some(blob_path_string.clone()),
            segment_id: None,
            segment_offset: None,
            size: b"legacy-blob-payload".len() as u64,
            version_ms: 100,
            created_at_ms: 100,
            branch: None,
        };

        store
            .db
            .put_cf(
                store.cf(ROCKSDB_CF_MANIFESTS),
                artifact_id.as_bytes(),
                encode_manifest_record(&manifest).expect("manifest should encode"),
            )
            .expect("failed to persist manifest");
        store
            .db
            .put_cf(
                store.cf(ROCKSDB_CF_NAMESPACE_ARTIFACTS),
                namespace_artifact_index_key("ios", &artifact_id).as_bytes(),
                [],
            )
            .expect("failed to persist namespace index");

        assert_eq!(
            read_manifest_bytes(&store, &manifest).await,
            b"legacy-blob-payload"
        );
        {
            let cache = store.segment_handles.lock().await;
            assert_eq!(cache.len(), 1);
            assert!(
                cache
                    .entries
                    .contains_key(&blob_handle_cache_key(&blob_path_string))
            );
        }

        store
            .delete_namespace("ios")
            .await
            .expect("failed to delete namespace");

        {
            let cache = store.segment_handles.lock().await;
            assert!(
                !cache
                    .entries
                    .contains_key(&blob_handle_cache_key(&blob_path_string))
            );
        }
        assert!(!blob_path.exists());
    }

    #[tokio::test]
    async fn fetch_artifact_refreshes_old_segment_backed_artifacts() {
        let (_temp_dir, _config, store) = temp_store();

        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");
        let original_segment_id = manifest
            .segment_id
            .clone()
            .expect("segment-backed artifact should have a segment id");
        store
            .save_segment_state(&SegmentState {
                old: vec![SegmentReference::new(original_segment_id.clone(), 1)],
                current: Vec::new(),
                new: vec![SegmentReference::new("fresh-segment".into(), 2)],
            })
            .expect("failed to seed segment state");

        let fetched = store
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact-1")
            .await
            .expect("failed to fetch artifact")
            .expect("artifact should still exist");

        assert_ne!(fetched.segment_id, Some(original_segment_id));
        assert_eq!(read_manifest_bytes(&store, &fetched).await, b"hello");
        assert_eq!(
            store
                .manifest(&fetched.artifact_id)
                .expect("failed to load manifest")
                .expect("refreshed manifest should still exist"),
            fetched
        );
        assert_eq!(store.segment_handles.lock().await.len(), 2);
    }

    #[tokio::test]
    async fn serving_defers_old_segment_promotion_off_the_read_path() {
        let (_temp_dir, _config, store) = temp_store();

        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");
        let original_segment_id = manifest
            .segment_id
            .clone()
            .expect("segment-backed artifact should have a segment id");
        store
            .save_segment_state(&SegmentState {
                old: vec![SegmentReference::new(original_segment_id.clone(), 1)],
                current: Vec::new(),
                new: vec![SegmentReference::new("fresh-segment".into(), 2)],
            })
            .expect("failed to seed segment state");

        // The serving path answers straight from the Old segment (no inline
        // refresh) and queues the artifact for background promotion.
        let served = store
            .fetch_artifact_for_serving(ArtifactProducer::Xcode, "ios", "artifact-1")
            .await
            .expect("failed to fetch artifact for serving")
            .expect("artifact should still exist");
        assert_eq!(served.segment_id, Some(original_segment_id.clone()));
        assert_eq!(read_manifest_bytes(&store, &served).await, b"hello");
        {
            let queue = store.promotion_queue.lock().expect("queue lock");
            assert_eq!(queue.depth(), 1);
            assert!(queue.pending.contains_key(&served.artifact_id));
        }

        // A second read of the same artifact does not enqueue it twice.
        store
            .fetch_artifact_for_serving(ArtifactProducer::Xcode, "ios", "artifact-1")
            .await
            .expect("failed to fetch artifact for serving")
            .expect("artifact should still exist");
        assert_eq!(store.promotion_queue.lock().expect("queue lock").depth(), 1);

        // Applying the queued promotion rewrites the artifact into the current
        // segment, exactly like the refresh the read path used to run inline.
        store
            .promote_artifact(&served.artifact_id, RefreshTrigger::Serve)
            .await
            .expect("promotion should succeed");
        let promoted = store
            .manifest(&served.artifact_id)
            .expect("failed to load manifest")
            .expect("promoted manifest should exist");
        assert_ne!(promoted.segment_id, Some(original_segment_id));
        assert_eq!(read_manifest_bytes(&store, &promoted).await, b"hello");
    }

    #[tokio::test]
    async fn tolerant_read_reresolves_when_a_concurrent_promotion_evicted_the_old_segment() {
        let (_temp_dir, _config, store) = temp_store();

        // Persist, then promote so the live manifest points at a new segment,
        // then evict the original segment out from under the pre-promotion
        // manifest -- the exact race a background promotion opens against a
        // serving read that already captured the old manifest.
        let stale = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");
        let old_segment = stale
            .segment_id
            .clone()
            .expect("segment-backed artifact should have a segment id");
        store
            .save_segment_state(&SegmentState {
                old: vec![SegmentReference::new(old_segment.clone(), 1)],
                current: Vec::new(),
                new: vec![SegmentReference::new("fresh-segment".into(), 2)],
            })
            .expect("failed to seed segment state");
        store
            .promote_artifact(&stale.artifact_id, RefreshTrigger::Serve)
            .await
            .expect("promotion should succeed");
        assert_ne!(
            store
                .manifest(&stale.artifact_id)
                .expect("lookup")
                .expect("manifest")
                .segment_id,
            stale.segment_id,
            "promotion should have relocated the artifact"
        );
        store
            .evict_segment(&old_segment)
            .await
            .expect("eviction should succeed");

        // The pre-promotion manifest can no longer be read directly...
        assert!(store.read_artifact_bytes(&stale).await.is_err());
        // ...but the tolerant read re-resolves to the promoted location.
        assert_eq!(
            store
                .read_artifact_bytes_tolerating_promotion(&stale)
                .await
                .expect("tolerant read should succeed"),
            Some(b"hello".to_vec())
        );
    }

    #[tokio::test]
    async fn tolerant_read_reports_a_miss_when_the_artifact_was_actually_evicted() {
        let (_temp_dir, _config, store) = temp_store();

        let stale = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");
        let old_segment = stale
            .segment_id
            .clone()
            .expect("segment-backed artifact should have a segment id");
        // Evict while the artifact still lives in the old segment (not promoted)
        // so its manifest is deleted and the file unlinked: a genuine miss.
        store
            .save_segment_state(&SegmentState {
                old: vec![SegmentReference::new(old_segment.clone(), 1)],
                current: Vec::new(),
                new: vec![SegmentReference::new("fresh-segment".into(), 2)],
            })
            .expect("failed to seed segment state");
        store
            .evict_segment(&old_segment)
            .await
            .expect("eviction should succeed");

        assert_eq!(
            store
                .read_artifact_bytes_tolerating_promotion(&stale)
                .await
                .expect("tolerant read should not error on a miss"),
            None
        );
    }

    #[tokio::test]
    async fn evict_segments_queues_capacity_eviction_reports() {
        let (_temp_dir, _config, store) = temp_store();

        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");
        let segment_id = manifest
            .segment_id
            .clone()
            .expect("segment-backed artifact should have a segment id");
        let mut reference = SegmentReference::new(segment_id.clone(), 1_000);
        reference.max_version_ms = Some(2_000);
        store
            .save_segment_state(&SegmentState {
                old: vec![reference.clone()],
                current: Vec::new(),
                new: vec![SegmentReference::new("fresh-segment".into(), 3_000)],
            })
            .expect("failed to seed segment state");

        store
            .evict_segments(vec![reference])
            .await
            .expect("eviction should succeed");

        let reports = store.take_pending_capacity_evictions();
        assert_eq!(reports.len(), 1);
        let report = &reports[0];
        assert_eq!(report.segment_id, segment_id);
        assert_eq!(report.segment_created_at_ms, 1_000);
        assert_eq!(report.newest_content_at_ms, 2_000);
        assert!(report.evicted_at_ms >= 2_000);
        assert_eq!(report.artifact_count, 1);
        assert!(
            report.bytes > 0,
            "should stat the segment file before unlinking it"
        );

        assert!(store.take_pending_capacity_evictions().is_empty());
    }

    #[tokio::test]
    async fn capacity_eviction_report_falls_back_to_created_at_without_a_seal_stat() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .evict_segments(vec![SegmentReference::new("segment-1".into(), 5_000)])
            .await
            .expect("eviction of an absent segment should still succeed");

        let reports = store.take_pending_capacity_evictions();
        assert_eq!(reports.len(), 1);
        assert_eq!(reports[0].newest_content_at_ms, 5_000);
        assert_eq!(reports[0].artifact_count, 0);
        assert_eq!(reports[0].bytes, 0);
    }

    #[tokio::test]
    async fn orphan_sweep_does_not_queue_capacity_eviction_reports() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");
        // A ring state that no longer references the persisted segment makes
        // its file an orphan: the sweep removes it as crash debris, which says
        // nothing about ring fit and must not read as churn.
        store
            .save_segment_state(&SegmentState {
                old: Vec::new(),
                current: Vec::new(),
                new: vec![SegmentReference::new("fresh-segment".into(), 2)],
            })
            .expect("failed to seed segment state");

        let swept = store
            .sweep_orphaned_segments()
            .await
            .expect("sweep should succeed");

        assert!(swept >= 1);
        assert!(store.take_pending_capacity_evictions().is_empty());
    }

    #[tokio::test]
    async fn capacity_eviction_reports_cap_drops_oldest() {
        let (_temp_dir, _config, store) = temp_store();

        for index in 0..(MAX_PENDING_CAPACITY_EVICTIONS + 5) {
            store.record_capacity_eviction(
                &SegmentReference::new(format!("segment-{index}"), index as u64),
                0,
                0,
            );
        }

        let reports = store.take_pending_capacity_evictions();
        assert_eq!(reports.len(), MAX_PENDING_CAPACITY_EVICTIONS);
        assert_eq!(reports[0].segment_id, "segment-5");
    }

    #[tokio::test]
    async fn storage_snapshot_reports_ring_occupancy() {
        let (_temp_dir, _config, store) = temp_store();

        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");
        assert!(manifest.segment_id.is_some());

        let snapshot = store.storage_snapshot();
        assert!(snapshot.ring_budget_bytes > 0);
        assert!(snapshot.desired_segment_count > 0);
        assert!(snapshot.live_segment_count >= 1);
        assert!(snapshot.live_segment_bytes > 0);
        assert!(snapshot.oldest_segment_created_at_ms.is_some());
        assert!(snapshot.newest_content_at_ms.is_some());
    }

    async fn drain_reader(mut reader: ArtifactReader) -> Vec<u8> {
        use tokio::io::AsyncReadExt;
        let mut bytes = Vec::new();
        reader
            .read_to_end(&mut bytes)
            .await
            .expect("reader should drain");
        bytes
    }

    #[tokio::test]
    async fn tolerant_reader_reresolves_when_a_concurrent_promotion_evicted_the_old_segment() {
        let (_temp_dir, _config, store) = temp_store();

        let stale = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");
        let old_segment = stale
            .segment_id
            .clone()
            .expect("segment-backed artifact should have a segment id");
        store
            .save_segment_state(&SegmentState {
                old: vec![SegmentReference::new(old_segment.clone(), 1)],
                current: Vec::new(),
                new: vec![SegmentReference::new("fresh-segment".into(), 2)],
            })
            .expect("failed to seed segment state");
        store
            .promote_artifact(&stale.artifact_id, RefreshTrigger::Serve)
            .await
            .expect("promotion should succeed");
        store
            .evict_segment(&old_segment)
            .await
            .expect("eviction should succeed");

        // The stale manifest can no longer be opened directly...
        assert!(store.open_artifact_reader(&stale).await.is_err());
        // ...but the tolerant open re-resolves to the promoted location and
        // hands back the manifest the bytes actually come from.
        let (fresh, reader) = store
            .open_artifact_reader_range_tolerating_promotion(&stale, 0, None)
            .await
            .expect("tolerant open should succeed")
            .expect("artifact should still be served");
        assert_ne!(fresh.segment_id, stale.segment_id);
        assert_eq!(drain_reader(reader).await, b"hello");
    }

    /// A resume reads from partway into a segment that already holds other
    /// artifacts, so the read has to add the request's offset to the segment
    /// offset. Getting that wrong yields a plausible-looking body from the
    /// wrong place, which a resuming client would silently append.
    #[tokio::test]
    async fn a_ranged_read_starts_at_the_offset_within_the_artifact_not_the_segment() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-before",
                "application/octet-stream",
                b"padding-that-shifts-the-next-artifact",
            )
            .await
            .expect("failed to persist leading artifact");
        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-ranged",
                "application/octet-stream",
                b"0123456789",
            )
            .await
            .expect("failed to persist artifact");

        let (_, tail) = store
            .open_artifact_reader_range_tolerating_promotion(&manifest, 6, None)
            .await
            .expect("ranged open should succeed")
            .expect("artifact should be readable");
        assert_eq!(drain_reader(tail).await, b"6789");

        let (_, window) = store
            .open_artifact_reader_range_tolerating_promotion(&manifest, 2, Some(3))
            .await
            .expect("ranged open should succeed")
            .expect("artifact should be readable");
        assert_eq!(drain_reader(window).await, b"234");

        let (_, last) = store
            .open_artifact_reader_range_tolerating_promotion(&manifest, 9, Some(1))
            .await
            .expect("ranged open should succeed")
            .expect("artifact should be readable");
        assert_eq!(drain_reader(last).await, b"9");
    }

    #[tokio::test]
    async fn tolerant_reader_reports_a_miss_when_the_artifact_was_actually_evicted() {
        let (_temp_dir, _config, store) = temp_store();

        let stale = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");
        let old_segment = stale
            .segment_id
            .clone()
            .expect("segment-backed artifact should have a segment id");
        store
            .save_segment_state(&SegmentState {
                old: vec![SegmentReference::new(old_segment.clone(), 1)],
                current: Vec::new(),
                new: vec![SegmentReference::new("fresh-segment".into(), 2)],
            })
            .expect("failed to seed segment state");
        store
            .evict_segment(&old_segment)
            .await
            .expect("eviction should succeed");

        assert!(
            store
                .open_artifact_reader_range_tolerating_promotion(&stale, 0, None)
                .await
                .expect("tolerant open should not error on a miss")
                .is_none()
        );
    }

    #[tokio::test]
    async fn promotion_worker_drains_reads_queued_from_old_segments() {
        let (_temp_dir, _config, store) = temp_store();
        let store = Arc::new(store);

        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");
        let original_segment_id = manifest
            .segment_id
            .clone()
            .expect("segment-backed artifact should have a segment id");
        store
            .save_segment_state(&SegmentState {
                old: vec![SegmentReference::new(original_segment_id.clone(), 1)],
                current: Vec::new(),
                new: vec![SegmentReference::new("fresh-segment".into(), 2)],
            })
            .expect("failed to seed segment state");

        let worker_store = Arc::clone(&store);
        tokio::spawn(async move { worker_store.run_promotion_worker().await });

        store
            .fetch_artifact_for_serving(ArtifactProducer::Xcode, "ios", "artifact-1")
            .await
            .expect("failed to fetch artifact for serving")
            .expect("artifact should still exist");

        let promoted = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let manifest = store
                    .manifest(&manifest.artifact_id)
                    .expect("failed to load manifest")
                    .expect("manifest should exist");
                if manifest.segment_id != Some(original_segment_id.clone()) {
                    return manifest;
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .expect("worker should promote the artifact");
        assert_eq!(read_manifest_bytes(&store, &promoted).await, b"hello");
    }

    /// Seeds one artifact into an Old segment and one into the live segment,
    /// returning the aged artifact's id.
    async fn store_with_one_aged_blob(store: &Store) -> String {
        let aged = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                "blob-aged",
                "application/octet-stream",
                b"aged",
            )
            .await
            .expect("failed to persist artifact");
        let aged_segment = aged
            .segment_id
            .clone()
            .expect("segment-backed artifact should have a segment id");
        store
            .save_segment_state(&SegmentState {
                old: vec![SegmentReference::new(aged_segment, 1)],
                current: Vec::new(),
                new: vec![SegmentReference::new("fresh-segment".into(), 2)],
            })
            .expect("failed to seed segment state");
        aged.artifact_id
    }

    #[tokio::test]
    async fn extending_lifetimes_queues_only_the_blobs_sitting_in_old_segments() {
        let (_temp_dir, _config, store) = temp_store();
        let aged_id = store_with_one_aged_blob(&store).await;
        let live = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                "blob-live",
                "application/octet-stream",
                b"live",
            )
            .await
            .expect("failed to persist artifact");
        assert_eq!(live.segment_id.as_deref(), Some("fresh-segment"));

        store.extend_artifact_lifetimes(
            ArtifactProducer::Reapi,
            "ios",
            &[
                "blob-aged".to_owned(),
                "blob-live".to_owned(),
                "blob-absent".to_owned(),
            ],
            RefreshTrigger::ActionCache,
        );

        let queue = store.promotion_queue.lock().expect("queue lock");
        assert_eq!(
            queue.serve.iter().chain(&queue.vouched).collect::<Vec<_>>(),
            vec![&aged_id],
            "only a blob whose segment is aging out needs copying forward"
        );
        assert_eq!(
            queue.pending.get(&aged_id),
            Some(&RefreshTrigger::ActionCache),
            "the queued promotion is attributed to the RPC that vouched for it"
        );
    }

    #[tokio::test]
    async fn a_serve_flood_cannot_crowd_out_vouched_refreshes() {
        let (_temp_dir, _config, store) = temp_store();
        let serve_ceiling = MAX_PENDING_PROMOTIONS - VOUCHED_PROMOTION_RESERVE;
        for index in 0..serve_ceiling {
            store.enqueue_promotion(&format!("serve-{index}"), RefreshTrigger::Serve);
        }
        let depth = || store.promotion_queue.lock().expect("queue lock").depth();
        assert_eq!(depth(), serve_ceiling);

        store.enqueue_promotion("serve-overflow", RefreshTrigger::Serve);
        assert_eq!(
            depth(),
            serve_ceiling,
            "best-effort serve promotion stops at its own ceiling"
        );

        store.enqueue_promotion("vouched", RefreshTrigger::ActionCache);
        assert_eq!(
            depth(),
            serve_ceiling + 1,
            "the reserve admits a refresh backing a promise already made to a client"
        );
    }

    #[tokio::test]
    async fn vouched_refreshes_drain_ahead_of_a_serve_backlog() {
        let (_temp_dir, _config, store) = temp_store();
        store.enqueue_promotion("shared", RefreshTrigger::Serve);
        for index in 0..64 {
            store.enqueue_promotion(&format!("serve-{index}"), RefreshTrigger::Serve);
        }
        store.enqueue_promotion("vouched", RefreshTrigger::FindMissing);
        // Upgrading an entry already queued behind the backlog has to move it
        // too: admitting it and then making it wait out the backlog leaves the
        // vouch unbacked for just as long as dropping it would.
        store.enqueue_promotion("shared", RefreshTrigger::ActionCache);

        let mut queue = store.promotion_queue.lock().expect("queue lock");
        assert_eq!(
            queue.pop(),
            Some(("vouched".to_owned(), RefreshTrigger::FindMissing)),
            "a vouched refresh does not wait out a serve backlog"
        );
        assert_eq!(
            queue.pop(),
            Some(("shared".to_owned(), RefreshTrigger::ActionCache)),
            "an upgraded entry moves to the vouched lane"
        );
        assert_eq!(
            queue.pop().map(|(artifact_id, _)| artifact_id),
            Some("serve-0".to_owned()),
            "serve work resumes in order once nothing is vouched"
        );
        assert_eq!(
            queue.depth(),
            63,
            "the upgraded entry's stale serve-lane slot is skipped, not promoted twice"
        );
    }

    #[tokio::test]
    async fn the_presence_check_extends_a_blob_lifetime_in_the_same_lookup() {
        let (_temp_dir, _config, store) = temp_store();
        let aged_id = store_with_one_aged_blob(&store).await;
        assert!(store.segment_ring_is_aging());
        let exists = async |key: &str| {
            store
                .artifact_exists_extending_lifetime(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    RefreshTrigger::FindMissing,
                )
                .await
                .expect("existence check should succeed")
        };

        assert!(exists("blob-aged").await);
        {
            let queue = store.promotion_queue.lock().expect("queue lock");
            assert_eq!(queue.depth(), 1);
            assert_eq!(
                queue.pending.get(&aged_id),
                Some(&RefreshTrigger::FindMissing),
                "the same lookup that answers presence queues the copy-forward"
            );
        }

        assert!(!exists("blob-absent").await);
        store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                "blob-live",
                "application/octet-stream",
                b"live",
            )
            .await
            .expect("failed to persist artifact");
        assert!(exists("blob-live").await);
        assert_eq!(
            store.promotion_queue.lock().expect("queue lock").depth(),
            1,
            "an absent blob and one already in a live segment queue nothing"
        );
    }

    #[tokio::test]
    async fn extending_lifetimes_is_a_no_op_while_no_segment_has_aged() {
        let (_temp_dir, _config, store) = temp_store();
        store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                "blob-live",
                "application/octet-stream",
                b"live",
            )
            .await
            .expect("failed to persist artifact");

        store.extend_artifact_lifetimes(
            ArtifactProducer::Reapi,
            "ios",
            &["blob-live".to_owned()],
            RefreshTrigger::FindMissing,
        );

        assert!(
            store
                .promotion_queue
                .lock()
                .expect("queue lock")
                .pending
                .is_empty(),
            "a node holding no Old segments does the whole batch from one state read"
        );
    }

    #[tokio::test]
    async fn vouching_upgrades_a_promotion_already_queued_by_serving() {
        let (_temp_dir, _config, store) = temp_store();
        let aged_id = store_with_one_aged_blob(&store).await;

        store
            .fetch_artifact_for_serving(ArtifactProducer::Reapi, "ios", "blob-aged")
            .await
            .expect("failed to fetch artifact for serving")
            .expect("artifact should still exist");
        assert_eq!(
            store
                .promotion_queue
                .lock()
                .expect("queue lock")
                .pending
                .get(&aged_id),
            Some(&RefreshTrigger::Serve)
        );

        store.extend_artifact_lifetimes(
            ArtifactProducer::Reapi,
            "ios",
            &["blob-aged".to_owned()],
            RefreshTrigger::ActionCache,
        );
        {
            let queue = store.promotion_queue.lock().expect("queue lock");
            assert_eq!(queue.depth(), 1, "the entry is queued exactly once");
            assert_eq!(
                queue.pending.get(&aged_id),
                Some(&RefreshTrigger::ActionCache),
                "vouching widens the pressure gate the queued refresh runs under"
            );
        }

        // A later serve-path read must not undo that.
        store
            .fetch_artifact_for_serving(ArtifactProducer::Reapi, "ios", "blob-aged")
            .await
            .expect("failed to fetch artifact for serving")
            .expect("artifact should still exist");
        assert_eq!(
            store
                .promotion_queue
                .lock()
                .expect("queue lock")
                .pending
                .get(&aged_id),
            Some(&RefreshTrigger::ActionCache),
            "a serve-path enqueue cannot downgrade a vouched-for blob"
        );
    }

    #[tokio::test]
    async fn constrained_pressure_keeps_vouched_refreshes_but_drops_serve_promotions() {
        let (_temp_dir, _config, store) =
            temp_store_at_pressure(crate::memory::MemoryPressure::Constrained);
        let aged_id = store_with_one_aged_blob(&store).await;
        let segment_of = |id: &str| {
            store
                .manifest(id)
                .expect("manifest lookup should succeed")
                .expect("manifest should exist")
                .segment_id
        };

        store
            .promote_artifact(&aged_id, RefreshTrigger::Serve)
            .await
            .expect("promotion should succeed");
        assert_ne!(
            segment_of(&aged_id).as_deref(),
            Some("fresh-segment"),
            "serve-path promotion is a pure optimization and yields under pressure"
        );

        store
            .promote_artifact(&aged_id, RefreshTrigger::ActionCache)
            .await
            .expect("promotion should succeed");
        assert_eq!(
            segment_of(&aged_id).as_deref(),
            Some("fresh-segment"),
            "a blob the node vouched for is still copied forward at this tier"
        );
    }

    #[tokio::test]
    async fn critical_pressure_drops_vouched_refreshes_too() {
        let (_temp_dir, _config, store) =
            temp_store_at_pressure(crate::memory::MemoryPressure::Critical);
        let aged_id = store_with_one_aged_blob(&store).await;

        store
            .promote_artifact(&aged_id, RefreshTrigger::ActionCache)
            .await
            .expect("promotion should succeed");
        assert_ne!(
            store
                .manifest(&aged_id)
                .expect("manifest lookup should succeed")
                .expect("manifest should exist")
                .segment_id
                .as_deref(),
            Some("fresh-segment"),
            "at Critical the read path's own write would compound the squeeze"
        );
    }

    #[tokio::test]
    async fn evict_segment_removes_segment_backed_manifests() {
        let (_temp_dir, _config, store) = temp_store();

        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "android",
                "artifact-1",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("failed to persist artifact");
        let segment_id = manifest
            .segment_id
            .clone()
            .expect("segment-backed artifact should have a segment id");
        let segment_path = store.segment_path(&segment_id);

        store
            .evict_segment(&segment_id)
            .await
            .expect("failed to evict segment");

        assert!(
            store
                .fetch_artifact(ArtifactProducer::Gradle, "android", "artifact-1")
                .await
                .expect("failed to fetch artifact")
                .is_none()
        );
        assert!(
            store
                .manifest(&manifest.artifact_id)
                .expect("failed to load manifest")
                .is_none()
        );
        assert!(!segment_path.exists());
        assert_eq!(store.segment_handles.lock().await.len(), 0);
    }

    #[tokio::test]
    async fn evict_segment_yields_so_the_runtime_keeps_scheduling() {
        // Production regression (2026-08-21): `evict_segment` scanned a whole
        // 512 MiB segment's artifact index with no await anywhere in the loop,
        // so one eviction parked a runtime worker for the entire scan and
        // commit. On the production mesh every liveness-probe restart followed
        // an eviction by 49 to 63 seconds, which is three failed `/up` probes
        // at `periodSeconds: 20`. `up()` reads nothing but process-local config
        // and takes no lock, so it can only have been starved of a scheduler
        // slot. This runs on the single-threaded test runtime, where a task
        // that never yields is the only way a concurrent task can starve.
        let (_temp_dir, _config, store) = temp_store();
        let store = Arc::new(store);

        let mut artifact_ids = Vec::new();
        for index in 0..(SEGMENT_EVICTION_YIELD_ROWS + 64) {
            let manifest = store
                .persist_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "android",
                    &format!("artifact-{index}"),
                    "application/octet-stream",
                    b"hello",
                )
                .await
                .expect("failed to persist artifact");
            artifact_ids.push(manifest.artifact_id);
        }
        let segment_id = store
            .manifest(&artifact_ids[0])
            .expect("failed to load manifest")
            .expect("artifact should exist")
            .segment_id
            .expect("artifact should be segment-backed");

        let eviction_started = Arc::new(AtomicBool::new(false));
        let observed_mid_scan = Arc::new(AtomicBool::new(false));
        let probe = tokio::spawn({
            let store = Arc::clone(&store);
            let artifact_id = artifact_ids[0].clone();
            let eviction_started = Arc::clone(&eviction_started);
            let observed_mid_scan = Arc::clone(&observed_mid_scan);
            async move {
                loop {
                    // The eviction commits every deletion in one batch at the
                    // very end, so seeing the manifest still present after the
                    // eviction started means this task was scheduled while the
                    // scan was still running.
                    if eviction_started.load(Ordering::SeqCst)
                        && store
                            .manifest(&artifact_id)
                            .expect("failed to load manifest")
                            .is_some()
                    {
                        observed_mid_scan.store(true, Ordering::SeqCst);
                    }
                    tokio::task::yield_now().await;
                }
            }
        });
        // Let the probe reach its first yield so it is parked and runnable.
        tokio::task::yield_now().await;

        eviction_started.store(true, Ordering::SeqCst);
        store
            .evict_segment(&segment_id)
            .await
            .expect("failed to evict segment");
        probe.abort();

        assert!(
            observed_mid_scan.load(Ordering::SeqCst),
            "evict_segment ran its entire scan without yielding, so nothing \
             else on the runtime could be scheduled between the eviction \
             starting and its batch being committed"
        );
        assert!(
            store
                .manifest(&artifact_ids[0])
                .expect("failed to load manifest")
                .is_none(),
            "the eviction must still remove every artifact in the segment"
        );
    }

    #[tokio::test]
    async fn evict_segment_shares_its_yield_budget_with_the_cascade_scan() {
        // A per-scan budget is not enough: `scanned` restarting at zero for
        // every blob means a segment of many small blobs, each referenced by
        // many action-cache entries, never reaches the stride on either scan
        // while running their product in one poll. The shape below is under
        // the stride on both scans individually (8 segment rows, 40 reverse
        // rows per blob) and well over it in total, so it only yields if the
        // two scans share one budget.
        const BLOBS: usize = 8;
        const ENTRIES_PER_BLOB: u8 = 40;
        const { assert!(BLOBS < SEGMENT_EVICTION_YIELD_ROWS) };
        const { assert!((ENTRIES_PER_BLOB as usize) < SEGMENT_EVICTION_YIELD_ROWS) };
        const { assert!(BLOBS * (ENTRIES_PER_BLOB as usize) > SEGMENT_EVICTION_YIELD_ROWS) };

        let (_temp_dir, _config, store) = temp_store();
        let store = Arc::new(store);

        let mut blob_ids = Vec::new();
        for blob in 0..BLOBS {
            // One namespace per blob so every entry can keep a low marker: the
            // marker is a byte and the artifact id is namespaced, so this is
            // what keeps 320 distinct entries addressable.
            let namespace_id = format!("cascade-{blob}");
            let digest = reapi_digest(blob as u8, 5);
            let manifest = persist_reapi_blob(&store, &namespace_id, &digest, b"hello").await;
            for marker in 0..ENTRIES_PER_BLOB {
                persist_action_cache_entry(
                    &store,
                    &namespace_id,
                    marker,
                    &action_result_referencing(&[&digest]),
                    1,
                )
                .await;
            }
            blob_ids.push(manifest.artifact_id);
        }
        let segment_id = store
            .manifest(&blob_ids[0])
            .expect("failed to load manifest")
            .expect("blob should exist")
            .segment_id
            .expect("blob should be segment-backed");

        let eviction_started = Arc::new(AtomicBool::new(false));
        let observed_mid_scan = Arc::new(AtomicBool::new(false));
        let probe = tokio::spawn({
            let store = Arc::clone(&store);
            let blob_id = blob_ids[0].clone();
            let eviction_started = Arc::clone(&eviction_started);
            let observed_mid_scan = Arc::clone(&observed_mid_scan);
            async move {
                loop {
                    if eviction_started.load(Ordering::SeqCst)
                        && store
                            .manifest(&blob_id)
                            .expect("failed to load manifest")
                            .is_some()
                    {
                        observed_mid_scan.store(true, Ordering::SeqCst);
                    }
                    tokio::task::yield_now().await;
                }
            }
        });
        tokio::task::yield_now().await;

        eviction_started.store(true, Ordering::SeqCst);
        store
            .evict_segment(&segment_id)
            .await
            .expect("failed to evict segment");
        probe.abort();

        assert!(
            observed_mid_scan.load(Ordering::SeqCst),
            "the cascade scan restarted the yield budget per blob, so the \
             eviction ran every reverse row of every blob in one poll"
        );
        assert!(
            store
                .manifest(&blob_ids[0])
                .expect("failed to load manifest")
                .is_none(),
            "the eviction must still remove every blob in the segment"
        );
    }

    #[tokio::test]
    async fn one_high_fanout_blob_cannot_blow_past_the_chunk_budget() {
        // Review finding (#12587): the budget is checked *before* a blob is
        // staged, and a blob's cascade is unbounded, so the real ceiling was
        // `budget + one blob's entire cascade` rather than the budget. That
        // matters because per-blob fanout is genuinely unbounded — a common
        // output blob (an empty file, a shared header) is referenced by very
        // many action results — which is the same shape that saturated the
        // pool in the first place.
        //
        // Splitting inside a cascade is legal, and this is the reasoning the
        // original chunking missed: #12152's invariant is one-directional. It
        // forbids an entry outliving its blob, not a blob outliving its
        // entries. Committing a blob's entries *before* the blob leaves, at
        // worst, an orphaned blob mid-eviction — which this very eviction is
        // about to delete anyway.
        const ENTRIES: u8 = 60;

        let (_temp_dir, _config, mut store) = temp_store();
        store.eviction_batch_budget_bytes = 4096;
        let store = Arc::new(store);

        let digest = reapi_digest(1, 5);
        let manifest = persist_reapi_blob(&store, "fanout", &digest, b"hello").await;
        for marker in 0..ENTRIES {
            persist_action_cache_entry(
                &store,
                "fanout",
                marker,
                &action_result_referencing(&[&digest]),
                1,
            )
            .await;
        }
        let segment_id = manifest
            .segment_id
            .clone()
            .expect("blob should be segment-backed");

        store
            .evict_segment(&segment_id)
            .await
            .expect("failed to evict segment");

        let chunk_bytes = store
            .eviction_commits
            .lock()
            .expect("eviction commit log lock should not be poisoned")
            .chunk_bytes
            .clone();
        let largest = chunk_bytes.iter().copied().max().unwrap_or_default();
        // One chunk may still overshoot by the last entry staged before the
        // check plus the blob's own rows; what it may not do is carry the whole
        // cascade. Twice the budget is comfortably above the former and far
        // below the latter.
        assert!(
            largest <= store.eviction_batch_budget_bytes * 2,
            "a single chunk reached {largest} bytes against a {} byte budget, so \
             one blob's cascade is still committed as one batch",
            store.eviction_batch_budget_bytes
        );
    }

    #[tokio::test]
    async fn a_republished_entry_is_not_skipped_by_an_earlier_chunks_dedup() {
        // Review finding (#12587): `CascadeProgress::seen` de-duplicated across
        // the whole segment, which was right when the segment was one batch. It
        // is wrong once the eviction commits in chunks — an entry removed by an
        // early chunk and then republished against a *different* blob in the
        // same segment is skipped when that blob is reached, and survives
        // pointing at a blob this eviction is deleting. Exactly the strand
        // #12152 closed.
        //
        // The eviction is driven by hand rather than raced against a probe
        // task. The hazard needs the republish to land strictly between the
        // chunk that deletes the entry and the scan reaching the second blob,
        // and a concurrent probe only hits that window by luck — it stopped
        // hitting it as soon as the request-path writes gained an await.
        // Stepping the future makes the ordering the test's, not the
        // scheduler's.
        //
        // The scan order also matters and is not creation order: the segment
        // index is walked by artifact id, so the entry is pinned to the blob
        // scanned first and the republish aimed at the one scanned last.
        let (_temp_dir, _config, mut store) = temp_store();
        store.eviction_batch_budget_bytes = 1;
        let store = Arc::new(store);

        let digests = [reapi_digest(1, 5), reapi_digest(2, 5)];
        let mut blobs = Vec::new();
        for (index, digest) in digests.iter().enumerate() {
            let manifest = persist_reapi_blob(
                &store,
                "republish",
                digest,
                format!("body{index}").as_bytes(),
            )
            .await;
            blobs.push((manifest.artifact_id, digest.clone()));
        }
        let segment_id = store
            .manifest(&blobs[0].0)
            .expect("failed to load manifest")
            .expect("blob should exist")
            .segment_id
            .expect("blob should be segment-backed");

        let prefix = segment_artifact_index_prefix(&segment_id);
        let mut scan_order = Vec::new();
        for item in store.db.iterator_cf(
            store.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS),
            IteratorMode::From(prefix.as_bytes(), rocksdb::Direction::Forward),
        ) {
            let (index_key, _) = item.expect("failed to iterate segment index");
            if !index_key.starts_with(prefix.as_bytes()) {
                break;
            }
            scan_order.push(
                std::str::from_utf8(&index_key[prefix.len()..])
                    .expect("valid segment index key")
                    .to_owned(),
            );
        }
        let first_scanned = scan_order
            .first()
            .expect("segment should hold blobs")
            .clone();
        let last_scanned = scan_order
            .last()
            .expect("segment should hold blobs")
            .clone();
        assert_ne!(
            first_scanned, last_scanned,
            "both blobs must share the segment being evicted"
        );
        let digest_of = |artifact_id: &str| {
            blobs
                .iter()
                .find(|(id, _)| id == artifact_id)
                .map(|(_, digest)| digest.clone())
                .expect("every scanned row should be one of the blobs")
        };

        let entry = persist_action_cache_entry(
            &store,
            "republish",
            0,
            &action_result_referencing(&[&digest_of(&first_scanned)]),
            1,
        )
        .await;
        let entry_id = entry.artifact_id.clone();

        let mut context = std::task::Context::from_waker(std::task::Waker::noop());
        let mut eviction = Box::pin(store.evict_segment(&segment_id));

        // Step until the chunk carrying the entry's deletion has landed.
        let mut entry_removed = false;
        for _ in 0..10_000 {
            if std::pin::Pin::new(&mut eviction)
                .poll(&mut context)
                .is_ready()
            {
                break;
            }
            if store
                .manifest_from_db(&entry_id)
                .expect("failed to read manifest")
                .is_none()
            {
                entry_removed = true;
                break;
            }
            tokio::task::yield_now().await;
        }
        assert!(
            entry_removed,
            "the eviction finished before removing the entry, so this asserts nothing"
        );
        assert!(
            store
                .manifest_from_db(&last_scanned)
                .expect("failed to read manifest")
                .is_some(),
            "the republish target was already evicted, so this asserts nothing"
        );

        // Republish the same entry onto the blob the scan has not reached yet.
        persist_action_cache_entry(
            &store,
            "republish",
            0,
            &action_result_referencing(&[&digest_of(&last_scanned)]),
            2,
        )
        .await;
        assert!(
            store
                .manifest_from_db(&entry_id)
                .expect("failed to read manifest")
                .is_some(),
            "the republish did not land, so this asserts nothing"
        );

        for _ in 0..10_000 {
            if std::pin::Pin::new(&mut eviction)
                .poll(&mut context)
                .is_ready()
            {
                break;
            }
            tokio::task::yield_now().await;
        }
        drop(eviction);

        assert!(
            store
                .manifest_from_db(&last_scanned)
                .expect("failed to read manifest")
                .is_none(),
            "the republish target should have been evicted"
        );
        assert!(
            store
                .manifest_from_db(&entry_id)
                .expect("failed to read manifest")
                .is_none(),
            "the republished entry survived its blob: an earlier chunk's dedup \
             skipped it, leaving it pointing at a blob this eviction removed"
        );
    }

    #[tokio::test]
    async fn a_cancelled_eviction_still_drops_the_caches_for_what_it_committed() {
        // Review finding (#12587): `spawn_blocking` work is never cancelled,
        // but the future awaiting it can be dropped — and eviction runs on the
        // request path, under a handler whose client may disconnect. Invalidate
        // only after the await and the write still lands while the manifest
        // cache keeps serving rows the store no longer has, which is the
        // `CAS error: missing object` class #12152 closed.
        //
        // The cancellation point is exact rather than timed: the future is
        // polled by hand until a commit closure has recorded itself, then
        // dropped on the spot, so the drop always lands with a commit in
        // flight instead of wherever a timeout happened to fall.
        let (_temp_dir, _config, mut store) = temp_store();
        store.eviction_batch_budget_bytes = 1;
        let store = Arc::new(store);

        let mut artifact_ids = Vec::new();
        for index in 0..6 {
            let digest = reapi_digest(index as u8, 5);
            let manifest = persist_reapi_blob(
                &store,
                "cancelled",
                &digest,
                format!("body{index}").as_bytes(),
            )
            .await;
            let entry = persist_action_cache_entry(
                &store,
                "cancelled",
                index as u8,
                &action_result_referencing(&[&digest]),
                1,
            )
            .await;
            // Entries as well as blobs: the cascade commits an entry chunk
            // before the blob's own rows, so the first landed chunk is an
            // entry deletion and watching only blobs would miss it.
            artifact_ids.push(manifest.artifact_id);
            artifact_ids.push(entry.artifact_id);
        }
        let segment_id = store
            .manifest(&artifact_ids[0])
            .expect("failed to load manifest")
            .expect("blob should exist")
            .segment_id
            .expect("blob should be segment-backed");

        // Warm the manifest cache so there is something to go stale.
        for artifact_id in &artifact_ids {
            store
                .manifest(artifact_id)
                .expect("failed to load manifest")
                .expect("blob should exist");
        }

        let mut eviction = Box::pin(store.evict_segment(&segment_id));
        let mut context = std::task::Context::from_waker(std::task::Waker::noop());
        let mut committed = false;
        for _ in 0..10_000 {
            if std::pin::Pin::new(&mut eviction)
                .poll(&mut context)
                .is_ready()
            {
                break;
            }
            if !store
                .eviction_commits
                .lock()
                .expect("eviction commit log lock should not be poisoned")
                .chunk_bytes
                .is_empty()
            {
                committed = true;
                break;
            }
            tokio::task::yield_now().await;
        }
        drop(eviction);
        assert!(
            committed,
            "no chunk was committed before the drop, so this asserts nothing"
        );

        // The detached commit is still finishing on its blocking thread.
        let mut evicted = Vec::new();
        for _ in 0..10_000 {
            evicted = artifact_ids
                .iter()
                .filter(|artifact_id| {
                    store
                        .manifest_from_db(artifact_id)
                        .expect("failed to read manifest")
                        .is_none()
                })
                .cloned()
                .collect();
            if !evicted.is_empty() {
                break;
            }
            tokio::task::yield_now().await;
        }
        assert!(
            !evicted.is_empty(),
            "the detached commit never landed, so this asserts nothing"
        );

        // Peek rather than `manifest()`, which would repopulate what it reads.
        let cache = store
            .manifest_cache
            .lock()
            .expect("manifest cache lock should not be poisoned");
        for artifact_id in &evicted {
            assert!(
                !cache.entries.contains_key(artifact_id),
                "the eviction was cancelled mid-commit, so {artifact_id} was \
                 deleted from the store while the manifest cache kept serving it"
            );
        }
    }

    #[tokio::test]
    async fn request_path_writes_also_commit_off_the_runtime_worker() {
        // Review finding (#12587): getting eviction off the worker threads is
        // not enough on its own. `allow_stall = true` blocks whichever thread
        // is inside RocksDB, so once the pool is saturated every writer still
        // running inline parks a worker, and enough concurrent writers park the
        // runtime with no eviction involved at all.
        //
        // Same reasoning as the eviction commit: `#[tokio::test]` is a
        // current-thread runtime, so an inline write would land on this very
        // thread. Persisting an artifact and an action-cache entry covers the
        // two hottest write paths.
        let (_temp_dir, _config, store) = temp_store();
        let runtime_thread = std::thread::current().id();
        let observed = Arc::new(StdMutex::new(Vec::new()));

        {
            let observed = Arc::clone(&observed);
            let previous = store
                .write_thread_observer
                .lock()
                .expect("write observer lock should not be poisoned")
                .replace(Arc::new(move |thread| {
                    observed
                        .lock()
                        .expect("observed lock should not be poisoned")
                        .push(thread);
                }));
            assert!(previous.is_none());
        }

        let digest = reapi_digest(1, 5);
        persist_reapi_blob(&store, "offloaded", &digest, b"hello").await;
        persist_action_cache_entry(
            &store,
            "offloaded",
            0,
            &action_result_referencing(&[&digest]),
            1,
        )
        .await;

        let observed = observed
            .lock()
            .expect("observed lock should not be poisoned");
        assert!(
            !observed.is_empty(),
            "no request-path write was observed, so this asserts nothing"
        );
        assert!(
            observed.iter().all(|thread| *thread != runtime_thread),
            "a request-path write committed inline on the thread driving the \
             runtime, so a saturated write-buffer pool would park it"
        );
    }

    #[tokio::test]
    async fn evict_segment_commits_off_the_thread_that_drives_the_runtime() {
        // The layer that makes the 2026-08-24 stall survivable (#12556). The
        // metadata store runs `allow_stall = true`, so a saturated write-buffer
        // pool blocks whichever thread is inside `db.write` until a flush
        // drains it. That is the flag working as intended — the fault was that
        // the call ran inline, so it blocked a tokio worker and parked the
        // runtime: probe handlers stopped being scheduled even though `/up`
        // reads process-local state and takes no lock, which is why the pod
        // held `up == 1` for 25 minutes without ever failing liveness.
        //
        // `#[tokio::test]` is a current-thread runtime, so every task — and
        // every `.await` below — runs on this one thread. If the commit still
        // ran inline it would be this thread, and a stall would take the whole
        // runtime with it. Asserting the commit lands somewhere else is exactly
        // the property, and it is deterministic rather than timing-dependent.
        let (_temp_dir, _config, store) = temp_store();
        let store = Arc::new(store);

        let digest = reapi_digest(1, 5);
        let manifest = persist_reapi_blob(&store, "offloaded", &digest, b"hello").await;
        let segment_id = manifest
            .segment_id
            .clone()
            .expect("blob should be segment-backed");

        let runtime_thread = std::thread::current().id();
        store
            .evict_segment(&segment_id)
            .await
            .expect("failed to evict segment");

        let threads = store
            .eviction_commits
            .lock()
            .expect("eviction commit log lock should not be poisoned")
            .threads
            .clone();
        assert!(
            !threads.is_empty(),
            "the eviction should have committed at least one chunk"
        );
        assert!(
            threads.iter().all(|thread| *thread != runtime_thread),
            "the eviction committed inline on the thread driving the runtime, so \
             a write-buffer stall inside RocksDB would park the runtime itself"
        );
    }

    #[test]
    fn an_empty_write_batch_survives_the_serialized_round_trip() {
        // `commit_eviction_chunk` moves the batch to the blocking pool as its
        // serialized representation, because `WriteBatch` is not `Send`. The
        // tail commit of an eviction can hand it an empty batch — every row
        // already went out on a chunk boundary — so the round trip has to hold
        // for one, rather than `from_data` choking on a bare header.
        let batch = WriteBatch::default();
        assert!(batch.is_empty());
        let round_tripped = WriteBatch::from_data(batch.data());
        assert!(round_tripped.is_empty());
        assert_eq!(round_tripped.len(), 0);
    }

    #[tokio::test]
    async fn evict_segment_commits_in_chunks_so_one_eviction_cannot_saturate_the_pool() {
        // Production regression (2026-08-24, #12556): one eviction staged its
        // whole segment index plus every cascade into a single `WriteBatch` —
        // 21,749 artifacts and 10,377 cascaded entries — and committed it in
        // one call. The metadata store runs `allow_stall = true`, so a batch
        // that large against a 32 MiB pool blocked every writer inside RocksDB
        // and the pod went silent for 25 minutes without ever failing liveness.
        //
        // The budget is dropped to a byte here so every blob boundary crosses
        // it; the point is that a bounded batch commits more than once, not the
        // production byte figure.
        const BLOBS: usize = 6;

        let (_temp_dir, _config, mut store) = temp_store();
        store.eviction_batch_budget_bytes = 1;
        let store = Arc::new(store);

        let mut blob_ids = Vec::new();
        for blob in 0..BLOBS {
            let namespace_id = format!("chunked-{blob}");
            let digest = reapi_digest(blob as u8, 5);
            let manifest = persist_reapi_blob(&store, &namespace_id, &digest, b"hello").await;
            persist_action_cache_entry(
                &store,
                &namespace_id,
                0,
                &action_result_referencing(&[&digest]),
                1,
            )
            .await;
            blob_ids.push(manifest.artifact_id);
        }
        let segment_id = store
            .manifest(&blob_ids[0])
            .expect("failed to load manifest")
            .expect("blob should exist")
            .segment_id
            .expect("blob should be segment-backed");

        let eviction_started = Arc::new(AtomicBool::new(false));
        let observed_partial_commit = Arc::new(AtomicBool::new(false));
        let probe = tokio::spawn({
            let store = Arc::clone(&store);
            let blob_ids = blob_ids.clone();
            let eviction_started = Arc::clone(&eviction_started);
            let observed_partial_commit = Arc::clone(&observed_partial_commit);
            async move {
                loop {
                    if eviction_started.load(Ordering::SeqCst) {
                        let present = blob_ids
                            .iter()
                            .filter(|id| {
                                store
                                    .manifest(id)
                                    .expect("failed to load manifest")
                                    .is_some()
                            })
                            .count();
                        if present > 0 && present < BLOBS {
                            observed_partial_commit.store(true, Ordering::SeqCst);
                        }
                    }
                    tokio::task::yield_now().await;
                }
            }
        });
        tokio::task::yield_now().await;

        eviction_started.store(true, Ordering::SeqCst);
        store
            .evict_segment(&segment_id)
            .await
            .expect("failed to evict segment");
        probe.abort();

        assert!(
            observed_partial_commit.load(Ordering::SeqCst),
            "the eviction committed every blob in one batch, so a single \
             segment can still push the write-buffer pool past its size"
        );
        for blob_id in &blob_ids {
            assert!(
                store
                    .manifest(blob_id)
                    .expect("failed to load manifest")
                    .is_none(),
                "chunking must still remove every blob in the segment"
            );
        }
    }

    #[tokio::test]
    async fn evict_segment_never_commits_a_blob_without_its_cascaded_entries() {
        // The invariant chunking must not break (#12152): an action-cache entry
        // may never outlive the blob it references. A blob and its own cascade
        // therefore have to share a batch — but two *different* blobs never had
        // to, which is what makes the chunking above legal. This probes for the
        // state that would prove otherwise: a blob gone while an entry that
        // referenced it is still readable.
        const BLOBS: usize = 6;
        const ENTRIES_PER_BLOB: u8 = 8;

        let (_temp_dir, _config, mut store) = temp_store();
        store.eviction_batch_budget_bytes = 1;
        let store = Arc::new(store);

        let mut blobs = Vec::new();
        for blob in 0..BLOBS {
            let namespace_id = format!("atomic-{blob}");
            let digest = reapi_digest(blob as u8, 5);
            let manifest = persist_reapi_blob(&store, &namespace_id, &digest, b"hello").await;
            let mut entry_ids = Vec::new();
            for marker in 0..ENTRIES_PER_BLOB {
                let entry = persist_action_cache_entry(
                    &store,
                    &namespace_id,
                    marker,
                    &action_result_referencing(&[&digest]),
                    1,
                )
                .await;
                entry_ids.push(entry.artifact_id);
            }
            blobs.push((manifest.artifact_id, entry_ids));
        }
        let segment_id = store
            .manifest(&blobs[0].0)
            .expect("failed to load manifest")
            .expect("blob should exist")
            .segment_id
            .expect("blob should be segment-backed");

        let stranded = Arc::new(AtomicBool::new(false));
        let probe = tokio::spawn({
            let store = Arc::clone(&store);
            let blobs = blobs.clone();
            let stranded = Arc::clone(&stranded);
            async move {
                loop {
                    for (blob_id, entry_ids) in &blobs {
                        let blob_gone = store
                            .manifest(blob_id)
                            .expect("failed to load manifest")
                            .is_none();
                        if !blob_gone {
                            continue;
                        }
                        let entry_alive = entry_ids.iter().any(|entry_id| {
                            store
                                .manifest(entry_id)
                                .expect("failed to load manifest")
                                .is_some()
                        });
                        if entry_alive {
                            stranded.store(true, Ordering::SeqCst);
                        }
                    }
                    tokio::task::yield_now().await;
                }
            }
        });
        tokio::task::yield_now().await;

        store
            .evict_segment(&segment_id)
            .await
            .expect("failed to evict segment");
        probe.abort();

        assert!(
            !stranded.load(Ordering::SeqCst),
            "a chunk boundary fell inside a blob's cascade, leaving an \
             action-cache entry pointing at a blob that was already gone"
        );
        for (blob_id, entry_ids) in &blobs {
            assert!(
                store
                    .manifest(blob_id)
                    .expect("failed to load manifest")
                    .is_none()
            );
            for entry_id in entry_ids {
                assert!(
                    store
                        .manifest(entry_id)
                        .expect("failed to load manifest")
                        .is_none(),
                    "every cascaded entry must be removed with its blob"
                );
            }
        }
    }

    // ---- Action-cache blob-refs reverse index + eviction cascade ----

    fn reapi_digest(marker: u8, size: i64) -> ReapiDigest {
        ReapiDigest {
            hash: format!("{:02x}", marker).repeat(32),
            size_bytes: size,
        }
    }

    fn action_result_referencing(digests: &[&ReapiDigest]) -> Vec<u8> {
        use prost::Message;
        let output_files = digests
            .iter()
            .enumerate()
            .map(|(index, digest)| ReapiOutputFile {
                path: format!("out/{index}"),
                digest: Some((*digest).clone()),
                ..Default::default()
            })
            .collect();
        ReapiActionResult {
            output_files,
            ..Default::default()
        }
        .encode_to_vec()
    }

    async fn persist_reapi_blob(
        store: &Store,
        namespace_id: &str,
        digest: &ReapiDigest,
        bytes: &[u8],
    ) -> ArtifactManifest {
        let key = blob_key(&format!("{}/{}", digest.hash, digest.size_bytes));
        store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                namespace_id,
                &key,
                "application/octet-stream",
                bytes,
            )
            .await
            .expect("failed to persist blob")
    }

    async fn persist_action_cache_entry(
        store: &Store,
        namespace_id: &str,
        action_marker: u8,
        action_result_bytes: &[u8],
        version_ms: u64,
    ) -> ArtifactManifest {
        let key = crate::utils::action_cache_key(&format!(
            "{}/0",
            format!("{:02x}", action_marker).repeat(32)
        ));
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                namespace_id,
                &key,
                "application/octet-stream",
                action_result_bytes,
                version_ms,
                None,
                None,
            )
            .await
            .expect("failed to persist action-cache entry");
        store
            .manifest(&artifact_storage_id(
                ArtifactProducer::Reapi,
                &store.tenant_id,
                namespace_id,
                &key,
            ))
            .expect("failed to load entry manifest")
            .expect("entry manifest should exist")
    }

    fn blob_ref_entry_ids(store: &Store, blob_artifact_id: &str) -> Vec<String> {
        let prefix = action_cache_blob_ref_prefix(blob_artifact_id);
        let iter = store.db.iterator_cf(
            store.cf(ROCKSDB_CF_KEY_VALUE),
            IteratorMode::From(prefix.as_bytes(), rocksdb::Direction::Forward),
        );
        let mut entry_ids = Vec::new();
        for item in iter {
            let (key, _) = item.expect("failed to iterate blob refs");
            if !key.starts_with(prefix.as_bytes()) {
                break;
            }
            entry_ids.push(String::from_utf8(key[prefix.len()..].to_vec()).expect("utf8 entry id"));
        }
        entry_ids
    }

    #[tokio::test]
    async fn write_path_records_blob_refs_for_action_cache_entries() {
        let (_temp_dir, _config, store) = temp_store();
        let digest = reapi_digest(0xaa, 5);
        let blob = persist_reapi_blob(&store, "acme", &digest, b"hello").await;
        let entry = persist_action_cache_entry(
            &store,
            "acme",
            0xbb,
            &action_result_referencing(&[&digest]),
            1,
        )
        .await;

        assert_eq!(
            blob_ref_entry_ids(&store, &blob.artifact_id),
            vec![entry.artifact_id.clone()]
        );
    }

    #[tokio::test]
    async fn republish_moves_blob_refs_to_the_new_referenced_blobs() {
        let (_temp_dir, _config, store) = temp_store();
        let digest_a = reapi_digest(0xa1, 5);
        let digest_b = reapi_digest(0xb2, 7);
        let blob_a = persist_reapi_blob(&store, "acme", &digest_a, b"hello").await;
        let blob_b = persist_reapi_blob(&store, "acme", &digest_b, b"goodbye").await;

        let entry = persist_action_cache_entry(
            &store,
            "acme",
            0xcc,
            &action_result_referencing(&[&digest_a]),
            1,
        )
        .await;
        assert_eq!(
            blob_ref_entry_ids(&store, &blob_a.artifact_id),
            vec![entry.artifact_id.clone()]
        );

        persist_action_cache_entry(
            &store,
            "acme",
            0xcc,
            &action_result_referencing(&[&digest_b]),
            2,
        )
        .await;
        assert!(
            blob_ref_entry_ids(&store, &blob_a.artifact_id).is_empty(),
            "previous version's reverse row should be dropped on re-publish"
        );
        assert_eq!(
            blob_ref_entry_ids(&store, &blob_b.artifact_id),
            vec![entry.artifact_id]
        );
    }

    #[tokio::test]
    async fn delete_artifact_metadata_drops_blob_refs() {
        let (_temp_dir, _config, store) = temp_store();
        let digest = reapi_digest(0xaa, 5);
        let blob = persist_reapi_blob(&store, "acme", &digest, b"hello").await;
        let entry = persist_action_cache_entry(
            &store,
            "acme",
            0xbb,
            &action_result_referencing(&[&digest]),
            1,
        )
        .await;

        store
            .delete_artifact_metadata(&[entry])
            .expect("failed to delete entry metadata");

        assert!(blob_ref_entry_ids(&store, &blob.artifact_id).is_empty());
    }

    #[tokio::test]
    async fn namespace_delete_drops_blob_refs() {
        let (_temp_dir, _config, store) = temp_store();
        let digest = reapi_digest(0xaa, 5);
        let blob = persist_reapi_blob(&store, "acme", &digest, b"hello").await;
        persist_action_cache_entry(
            &store,
            "acme",
            0xbb,
            &action_result_referencing(&[&digest]),
            1,
        )
        .await;

        store
            .delete_namespace("acme")
            .await
            .expect("failed to delete namespace");

        assert!(blob_ref_entry_ids(&store, &blob.artifact_id).is_empty());
    }

    #[tokio::test]
    async fn backfill_reconstructs_blob_refs_for_entries_predating_the_map() {
        let (_temp_dir, _config, store) = temp_store();
        let digest = reapi_digest(0xaa, 5);
        let blob = persist_reapi_blob(&store, "acme", &digest, b"hello").await;
        let entry = persist_action_cache_entry(
            &store,
            "acme",
            0xbb,
            &action_result_referencing(&[&digest]),
            1,
        )
        .await;

        // Wipe the reverse rows the write path created so the backfill has to
        // rebuild them from the entries alone.
        let mut wipe = WriteBatch::default();
        for entry_id in blob_ref_entry_ids(&store, &blob.artifact_id) {
            wipe.delete_cf(
                store.cf(ROCKSDB_CF_KEY_VALUE),
                action_cache_blob_ref_key(&blob.artifact_id, &entry_id).as_bytes(),
            );
        }
        store.db.write(wipe).expect("failed to wipe blob refs");
        assert!(blob_ref_entry_ids(&store, &blob.artifact_id).is_empty());
        // The cascade is live throughout: it never waited on the backfill, it
        // just had no row for this pre-existing entry to act on.
        assert!(store.action_cache_cascade_active());

        store
            .backfill_action_cache_blob_refs()
            .expect("backfill failed");

        assert_eq!(
            blob_ref_entry_ids(&store, &blob.artifact_id),
            vec![entry.artifact_id]
        );
        assert!(store.action_cache_cascade_active());
    }

    #[tokio::test]
    async fn blob_refs_backfill_resumes_from_its_persisted_cursor() {
        let (_temp_dir, _config, store) = temp_store();
        let digest = reapi_digest(0xaa, 5);
        let blob = persist_reapi_blob(&store, "acme", &digest, b"hello").await;
        persist_action_cache_entry(
            &store,
            "acme",
            0xbb,
            &action_result_referencing(&[&digest]),
            1,
        )
        .await;

        let first = store
            .backfill_action_cache_blob_refs_step()
            .expect("first backfill step failed");
        assert!(!first.complete);
        assert!(
            store
                .db
                .get_cf(
                    store.cf(ROCKSDB_CF_KEY_VALUE),
                    Store::action_cache_blob_refs_cursor_key().as_bytes(),
                )
                .expect("failed to read persisted cursor")
                .is_some(),
            "an interrupted migration must leave a cursor for the next start"
        );
        assert!(store.action_cache_cascade_active());

        loop {
            let step = store
                .backfill_action_cache_blob_refs_step()
                .expect("resumed backfill step failed");
            if step.complete {
                break;
            }
        }

        assert_eq!(blob_ref_entry_ids(&store, &blob.artifact_id).len(), 1);
        assert!(store.action_cache_cascade_active());
        assert!(
            store
                .db
                .get_cf(
                    store.cf(ROCKSDB_CF_KEY_VALUE),
                    Store::action_cache_blob_refs_cursor_key().as_bytes(),
                )
                .expect("failed to read cleared cursor")
                .is_none()
        );
    }

    #[tokio::test]
    async fn evicting_a_referenced_blob_cascades_the_action_cache_entry() {
        let (_temp_dir, _config, store) = temp_store();
        let digest = reapi_digest(0xaa, 5);
        let blob = persist_reapi_blob(&store, "acme", &digest, b"hello").await;
        let entry = persist_action_cache_entry(
            &store,
            "acme",
            0xbb,
            &action_result_referencing(&[&digest]),
            1,
        )
        .await;
        store
            .backfill_action_cache_blob_refs()
            .expect("backfill failed");

        let segment_id = blob
            .segment_id
            .clone()
            .expect("blob should be segment-backed");
        store
            .evict_segment(&segment_id)
            .await
            .expect("failed to evict segment");

        assert!(
            store
                .manifest(&entry.artifact_id)
                .expect("failed to load entry manifest")
                .is_none(),
            "the entry stranded by the evicted blob should be cascaded away"
        );
        assert!(blob_ref_entry_ids(&store, &blob.artifact_id).is_empty());
    }

    #[tokio::test]
    async fn cascade_runs_without_the_backfill_having_completed() {
        // Production regression: the cascade used to wait on the one-time
        // blob-refs backfill, which waits on background headroom, which a warm
        // node at the page-cache watermark never grants. The cascade stayed
        // inert across every eviction sweep and stranded entries kept being
        // served, failing builds with `missing object`. Entries written since
        // boot get their rows from the write path, so no backfill is required.
        let (_temp_dir, _config, store) = temp_store();
        let digest = reapi_digest(0xaa, 5);
        let blob = persist_reapi_blob(&store, "acme", &digest, b"hello").await;
        let entry = persist_action_cache_entry(
            &store,
            "acme",
            0xbb,
            &action_result_referencing(&[&digest]),
            1,
        )
        .await;

        let segment_id = blob
            .segment_id
            .clone()
            .expect("blob should be segment-backed");
        store
            .evict_segment(&segment_id)
            .await
            .expect("failed to evict segment");

        assert!(
            store
                .manifest(&entry.artifact_id)
                .expect("failed to load entry manifest")
                .is_none(),
            "the entry stranded by the evicted blob should be cascaded away \
             without any backfill having run"
        );
        assert!(blob_ref_entry_ids(&store, &blob.artifact_id).is_empty());
    }

    #[tokio::test]
    async fn cascade_removes_an_entry_referencing_two_blobs_in_one_segment_once() {
        let (_temp_dir, _config, store) = temp_store();
        let digest_a = reapi_digest(0xa1, 5);
        let digest_b = reapi_digest(0xb2, 7);
        let blob_a = persist_reapi_blob(&store, "acme", &digest_a, b"hello").await;
        let blob_b = persist_reapi_blob(&store, "acme", &digest_b, b"goodbye").await;
        // The one-action-several-outputs shape: both outputs land in the same
        // current segment, so a single eviction drops both blobs and the second
        // blob's scan must hit the `cascaded_entries` dedupe rather than
        // re-removing the entry or double-counting it.
        let segment_id = blob_a
            .segment_id
            .clone()
            .expect("blob should be segment-backed");
        assert_eq!(
            blob_b.segment_id.as_deref(),
            Some(segment_id.as_str()),
            "test assumes both small blobs co-locate in one segment"
        );

        let entry = persist_action_cache_entry(
            &store,
            "acme",
            0xcc,
            &action_result_referencing(&[&digest_a, &digest_b]),
            1,
        )
        .await;
        store
            .backfill_action_cache_blob_refs()
            .expect("backfill failed");

        store
            .evict_segment(&segment_id)
            .await
            .expect("failed to evict segment");

        assert!(
            store
                .manifest(&entry.artifact_id)
                .expect("failed to load entry manifest")
                .is_none(),
            "the entry should be cascaded away once both of its blobs are evicted"
        );
        assert!(blob_ref_entry_ids(&store, &blob_a.artifact_id).is_empty());
        assert!(blob_ref_entry_ids(&store, &blob_b.artifact_id).is_empty());
        // prometheus-client appends `_total` to a counter's sample line, and this
        // repo registers counters already suffixed `_total` (so the sample is
        // `_total_total`, matching every sibling counter). Assert the value is 1,
        // not 2, to lock in that the entry is counted once, not once per blob.
        assert!(
            store
                .io
                .metrics()
                .render()
                .contains("kura_action_cache_cascade_removed_total_total 1"),
            "the entry must be counted once, not once per referenced blob"
        );
    }

    #[tokio::test]
    async fn eviction_does_not_cascade_when_the_operator_disables_it() {
        // The operator flag is the only gate left, so it is the only way to get
        // the pre-cascade behaviour back if this ever needs turning off in
        // production. Eviction must then leave the entry for the serve-side
        // presence gates to handle, exactly as before the cascade shipped.
        let (_temp_dir, _config, store) =
            temp_store_with(|config| config.action_cache_eviction_cascade_enabled = false);
        let digest = reapi_digest(0xaa, 5);
        let blob = persist_reapi_blob(&store, "acme", &digest, b"hello").await;
        let entry = persist_action_cache_entry(
            &store,
            "acme",
            0xbb,
            &action_result_referencing(&[&digest]),
            1,
        )
        .await;
        store
            .backfill_action_cache_blob_refs()
            .expect("backfill failed");

        assert!(!store.action_cache_cascade_active());
        let segment_id = blob.segment_id.clone().expect("segment-backed");
        store
            .evict_segment(&segment_id)
            .await
            .expect("failed to evict segment");

        assert!(
            store
                .manifest(&entry.artifact_id)
                .expect("failed to load entry manifest")
                .is_some(),
            "with the cascade disabled the entry must remain in place"
        );
    }

    #[tokio::test]
    async fn cascade_ignores_a_stale_reverse_row_to_a_live_unrelated_entry() {
        let (_temp_dir, _config, store) = temp_store();
        let digest_a = reapi_digest(0xa1, 5);
        // Blob B is referenced by the entry but persisted into no segment here, so
        // evicting A's segment cannot legitimately take the entry (persisting B
        // would land it in the same current segment as A and evict both).
        let digest_b = reapi_digest(0xb2, 7);
        let blob_a = persist_reapi_blob(&store, "acme", &digest_a, b"hello").await;
        // The entry references B only.
        let entry = persist_action_cache_entry(
            &store,
            "acme",
            0xcc,
            &action_result_referencing(&[&digest_b]),
            1,
        )
        .await;
        store
            .backfill_action_cache_blob_refs()
            .expect("backfill failed");

        // Inject a stale reverse row claiming the entry references blob A (as a
        // re-publish that moved off A could momentarily leave), then evict A.
        let mut stale = WriteBatch::default();
        stale.put_cf(
            store.cf(ROCKSDB_CF_KEY_VALUE),
            action_cache_blob_ref_key(&blob_a.artifact_id, &entry.artifact_id).as_bytes(),
            [],
        );
        store.db.write(stale).expect("failed to inject stale row");

        let segment_a = blob_a.segment_id.clone().expect("segment-backed");
        store
            .evict_segment(&segment_a)
            .await
            .expect("failed to evict segment");

        assert!(
            store
                .manifest(&entry.artifact_id)
                .expect("failed to load entry manifest")
                .is_some(),
            "a stale reverse row must not take out a live entry that no longer references the blob"
        );
        assert!(
            blob_ref_entry_ids(&store, &blob_a.artifact_id).is_empty(),
            "the stale row itself should be cleaned up by the eviction"
        );
    }

    #[tokio::test]
    async fn delete_namespace_removes_keyvalue_payloads() {
        let (_temp_dir, _config, store) = temp_store();

        let manifest = store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "android",
                "gradle-1",
                "application/json",
                br#"{"gradle":"cache"}"#,
            )
            .await
            .expect("failed to persist artifact");

        store
            .delete_namespace("android")
            .await
            .expect("failed to delete namespace");

        assert!(
            store
                .fetch_artifact(ArtifactProducer::Xcode, "android", "gradle-1")
                .await
                .expect("failed to fetch artifact")
                .is_none()
        );
        assert!(
            store
                .inline_bytes(&manifest.artifact_id)
                .expect("failed to read inline bytes")
                .is_none()
        );
    }

    #[tokio::test]
    async fn a_stale_apply_cannot_outlive_a_concurrent_namespace_delete() {
        // The delete's artifact scan is a snapshot: a row applied after its
        // iterator was created is invisible to the delete batch, while that
        // apply's own tombstone check ran before the tombstone was committed.
        // Neither side sees the other, and the row survives its own tombstone
        // — after which namespace_tombstone_blocks stops rejecting it, because
        // the tombstone reads newer than the row. Serializing delete against
        // delete does not cover this; the apply has to take the read side.
        let (_temp_dir, _config, store) = temp_store();
        let store = Arc::new(store);

        let delete = tokio::spawn({
            let store = store.clone();
            async move { store.apply_replicated_namespace_delete("ios", 200).await }
        });
        let apply = tokio::spawn({
            let store = store.clone();
            async move {
                store
                    .apply_replicated_inline_artifact_from_bytes(
                        ArtifactProducer::Xcode,
                        "ios",
                        "entry",
                        "application/octet-stream",
                        b"stale",
                        150,
                        None,
                        None,
                    )
                    .await
            }
        });

        delete
            .await
            .expect("delete task should join")
            .expect("delete should apply");
        // The apply may be rejected by the tombstone or may land first and be
        // swept; either is correct, so only its absence afterwards is asserted.
        let _ = apply.await.expect("apply task should join");

        assert!(
            store
                .fetch_artifact(ArtifactProducer::Xcode, "ios", "entry")
                .await
                .expect("fetch should succeed")
                .is_none(),
            "an artifact older than the namespace tombstone survived the delete"
        );
    }

    #[tokio::test]
    async fn concurrent_namespace_deletes_keep_the_newest_tombstone() {
        // The tombstone decision reads the previous version, compares, and only
        // then writes, with the namespace scan in between. Deliveries for one
        // namespace arrive concurrently now that the outbox drain is pipelined,
        // so without a lock across that span both can read the same previous
        // version, both conclude they are newer, and the older one can commit
        // last. The tombstone would then read 100 with artifacts up to 200
        // removed, and `namespace_tombstone_blocks` would stop rejecting the
        // stale upserts that tombstone exists to reject.
        let (_temp_dir, _config, store) = temp_store();
        let store = Arc::new(store);

        let newer = tokio::spawn({
            let store = store.clone();
            async move { store.apply_replicated_namespace_delete("ios", 200).await }
        });
        let older = tokio::spawn({
            let store = store.clone();
            async move { store.apply_replicated_namespace_delete("ios", 100).await }
        });
        newer
            .await
            .expect("newer delete task should join")
            .expect("newer delete should apply");
        older
            .await
            .expect("older delete task should join")
            .expect("older delete should resolve");

        let tombstones = store
            .namespace_tombstones()
            .expect("tombstones should load");
        let (_namespace, version_ms) = tombstones
            .iter()
            .find(|(namespace, _)| namespace == "ios")
            .expect("the namespace should carry a tombstone");
        assert_eq!(
            *version_ms, 200,
            "the older delete regressed the tombstone, so artifacts it should block are live again"
        );
    }

    #[tokio::test]
    async fn replicated_namespace_tombstones_reject_stale_upserts() {
        let (_temp_dir, _config, store) = temp_store();

        assert!(
            store
                .apply_replicated_namespace_delete("ios", 200)
                .await
                .expect("namespace delete should apply")
                .applied()
        );

        assert_eq!(
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    "artifact-1",
                    "application/octet-stream",
                    b"stale",
                    100,
                )
                .await
                .expect("stale artifact should be ignored"),
            ArtifactApplyOutcome::IgnoredTombstone
        );
        assert!(
            !store
                .artifact_version_is_current(ArtifactProducer::Gradle, "ios", "artifact-1", 100)
                .expect("version check should succeed")
        );
        assert!(
            store
                .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact-1")
                .await
                .expect("artifact fetch should succeed")
                .is_none()
        );
    }

    #[tokio::test]
    async fn replicated_namespace_delete_only_removes_older_artifacts() {
        let (_temp_dir, _config, store) = temp_store();

        assert!(
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    "artifact-old",
                    "application/octet-stream",
                    b"old",
                    100,
                )
                .await
                .expect("old artifact should apply")
                .applied()
        );
        assert!(
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    "artifact-new",
                    "application/octet-stream",
                    b"new",
                    300,
                )
                .await
                .expect("new artifact should apply")
                .applied()
        );

        assert!(
            store
                .apply_replicated_namespace_delete("ios", 200)
                .await
                .expect("namespace delete should apply")
                .applied()
        );

        assert!(
            store
                .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact-old")
                .await
                .expect("old artifact fetch should succeed")
                .is_none()
        );
        let remaining = store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact-new")
            .await
            .expect("new artifact fetch should succeed")
            .expect("newer artifact should remain");
        assert_eq!(remaining.version_ms, 300);
        assert_eq!(read_manifest_bytes(&store, &remaining).await, b"new");
    }

    // Characterization: pins the pre-existing `version_ms == 0` purge branch
    // before the backfill index extends it. A purge removes every artifact
    // regardless of version, always applies, and neither writes a tombstone
    // nor removes an existing one.
    #[tokio::test]
    async fn namespace_purge_removes_every_artifact_and_leaves_tombstone_state_alone() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .apply_replicated_namespace_delete("ios", 100)
            .await
            .expect("tombstone should apply");
        for (key, version_ms) in [("artifact-old", 150_u64), ("artifact-new", 900)] {
            assert!(
                store
                    .apply_replicated_artifact_from_bytes(
                        ArtifactProducer::Gradle,
                        "ios",
                        key,
                        "application/octet-stream",
                        b"payload",
                        version_ms,
                    )
                    .await
                    .expect("artifact should apply")
                    .applied()
            );
        }

        assert_eq!(
            store
                .apply_replicated_namespace_delete("ios", 0)
                .await
                .expect("purge should succeed"),
            NamespaceDeleteOutcome::Applied
        );

        for key in ["artifact-old", "artifact-new"] {
            assert!(
                store
                    .fetch_artifact(ArtifactProducer::Gradle, "ios", key)
                    .await
                    .expect("artifact fetch should succeed")
                    .is_none(),
                "a purge removes {key} regardless of its version"
            );
        }
        assert_eq!(
            store
                .namespace_tombstones()
                .expect("tombstones should load"),
            vec![("ios".to_owned(), 100)],
            "the purge writes no tombstone and the pre-existing one survives"
        );
    }

    // Characterization: pins tombstone overwrite on re-delete before the
    // backfill index adds its own row maintenance to that path.
    #[tokio::test]
    async fn redeleting_a_tombstoned_namespace_advances_the_stored_tombstone_version() {
        let (_temp_dir, _config, store) = temp_store();

        assert!(
            store
                .apply_replicated_namespace_delete("ios", 100)
                .await
                .expect("first delete should apply")
                .applied()
        );
        assert!(
            store
                .apply_replicated_namespace_delete("ios", 200)
                .await
                .expect("newer delete should apply")
                .applied()
        );

        assert_eq!(
            store
                .namespace_tombstones()
                .expect("tombstones should load"),
            vec![("ios".to_owned(), 200)],
            "re-delete overwrites in place"
        );
    }

    // ---- Backfill per-entry index ----

    fn backfill_rows(store: &Store) -> Vec<BackfillIndexRow> {
        store
            .backfill_index_page(None, usize::MAX)
            .expect("backfill index page should load")
            .entries
    }

    /// Opens the data dir the way a pre-backfill binary would: raw RocksDB,
    /// no index maintenance, no maintenance stamps.
    fn open_foreign_db(config: &Config) -> DB {
        let cfs = [
            ROCKSDB_CF_MANIFESTS,
            ROCKSDB_CF_KEY_VALUE,
            ROCKSDB_CF_NAMESPACE_ARTIFACTS,
            ROCKSDB_CF_NAMESPACE_TOMBSTONES,
            ROCKSDB_CF_MULTIPART_UPLOADS,
            ROCKSDB_CF_OUTBOX,
            ROCKSDB_CF_USAGE_OUTBOX,
            ROCKSDB_CF_SEGMENT_ARTIFACTS,
            ROCKSDB_CF_SEGMENT_STATE,
            ROCKSDB_CF_ACTION_CACHE_INDEX,
        ]
        .map(|name| ColumnFamilyDescriptor::new(name, Options::default()));
        DB::open_cf_descriptors(&Options::default(), config.data_dir.join("rocksdb"), cfs)
            .expect("failed to open data dir as a foreign binary")
    }

    fn inline_manifest_record(
        tenant_id: &str,
        namespace_id: &str,
        key: &str,
        version_ms: u64,
        created_at_ms: u64,
        bytes: &[u8],
    ) -> (String, Vec<u8>) {
        let artifact_id =
            artifact_storage_id(ArtifactProducer::Gradle, tenant_id, namespace_id, key);
        let manifest = ArtifactManifest {
            artifact_id: artifact_id.clone(),
            producer: ArtifactProducer::Gradle,
            namespace_id: namespace_id.to_owned(),
            key: key.to_owned(),
            content_type: "application/octet-stream".to_owned(),
            inline: true,
            blob_path: None,
            segment_id: None,
            segment_offset: None,
            size: bytes.len() as u64,
            version_ms,
            created_at_ms,
            branch: None,
        };
        let record = encode_manifest_record(&manifest).expect("manifest should encode");
        (artifact_id, record)
    }

    #[tokio::test]
    async fn backfill_rows_scan_newest_first_with_kinds_and_sizes() {
        let (_temp_dir, _config, store) = temp_store();

        let segmented = store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "segmented",
                "application/octet-stream",
                b"segmented-body",
                2_000,
            )
            .await
            .expect("segmented artifact should apply");
        assert!(segmented.applied());
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "inline",
                "application/octet-stream",
                b"inline",
                1_000,
                None,
                None,
            )
            .await
            .expect("inline artifact should apply");
        store
            .apply_replicated_namespace_delete("android", 1_500)
            .await
            .expect("tombstone should apply");

        let rows = backfill_rows(&store);
        assert_eq!(
            rows.iter()
                .map(|row| (row.version_ms, row.kind, row.size))
                .collect::<Vec<_>>(),
            vec![
                (2_000, BackfillRecordKind::SegmentArtifact, Some(14)),
                (1_500, BackfillRecordKind::NamespaceTombstone, None),
                (1_000, BackfillRecordKind::InlineArtifact, Some(6)),
            ],
            "rows scan newest-first with their kinds and sizes"
        );
        assert_eq!(rows[1].record_id, "android");
    }

    #[tokio::test]
    async fn lww_overwrite_leaves_exactly_one_backfill_row() {
        let (_temp_dir, _config, store) = temp_store();

        for version_ms in [100_u64, 200] {
            store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    "artifact",
                    "application/octet-stream",
                    b"payload",
                    version_ms,
                    None,
                    None,
                )
                .await
                .expect("artifact should apply");
        }

        let rows = backfill_rows(&store);
        assert_eq!(rows.len(), 1, "the old-version row is deleted in the batch");
        assert_eq!(rows[0].version_ms, 200);
    }

    #[tokio::test]
    async fn evict_segment_removes_backfill_rows_for_every_evicted_artifact() {
        let (_temp_dir, _config, store) = temp_store();

        let first = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"one",
            )
            .await
            .expect("first artifact should persist");
        store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact-2",
                "application/octet-stream",
                b"two",
            )
            .await
            .expect("second artifact should persist");
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "survivor",
                "application/octet-stream",
                b"inline",
                50,
                None,
                None,
            )
            .await
            .expect("inline artifact should apply");
        assert_eq!(backfill_rows(&store).len(), 3);

        store
            .evict_segment(
                first
                    .segment_id
                    .as_deref()
                    .expect("artifact should be segment-backed"),
            )
            .await
            .expect("eviction should succeed");

        let rows = backfill_rows(&store);
        assert_eq!(rows.len(), 1, "only the inline survivor keeps a row");
        assert_eq!(rows[0].kind, BackfillRecordKind::InlineArtifact);
        assert_eq!(rows[0].version_ms, 50);
    }

    #[tokio::test]
    async fn action_cache_expiry_removes_backfill_rows() {
        let (_temp_dir, _config, store) = temp_store();

        for (key, version_ms) in [
            ("action_cache/aa/10", 1_000_u64),
            ("action_cache/bb/10", 9_000),
        ] {
            store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    "application/octet-stream",
                    b"result",
                    version_ms,
                    None,
                    None,
                )
                .await
                .expect("action-cache entry should apply");
        }

        assert_eq!(
            store
                .expire_stale_action_cache_entries(5_000, 100)
                .expect("sweep should succeed"),
            1
        );

        let rows = backfill_rows(&store);
        assert_eq!(rows.len(), 1, "the expired entry's row is deleted");
        assert_eq!(rows[0].version_ms, 9_000);
        assert_eq!(rows[0].kind, BackfillRecordKind::InlineArtifact);
    }

    #[tokio::test]
    async fn namespace_delete_removes_backfill_rows_and_adds_the_tombstone_row() {
        let (_temp_dir, _config, store) = temp_store();

        for (key, version_ms) in [("artifact-old", 100_u64), ("artifact-new", 300)] {
            store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    key,
                    "application/octet-stream",
                    b"payload",
                    version_ms,
                    None,
                    None,
                )
                .await
                .expect("artifact should apply");
        }

        store
            .apply_replicated_namespace_delete("ios", 200)
            .await
            .expect("tombstone should apply");

        let rows = backfill_rows(&store);
        assert_eq!(
            rows.iter()
                .map(|row| (row.version_ms, row.kind))
                .collect::<Vec<_>>(),
            vec![
                (300, BackfillRecordKind::InlineArtifact),
                (200, BackfillRecordKind::NamespaceTombstone),
            ],
            "the deleted manifest loses its row, the survivor keeps its row, the tombstone gains one"
        );
    }

    #[tokio::test]
    async fn redelete_of_a_tombstoned_namespace_leaves_exactly_one_tombstone_row() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .apply_replicated_namespace_delete("ios", 100)
            .await
            .expect("first delete should apply");
        store
            .apply_replicated_namespace_delete("ios", 200)
            .await
            .expect("newer delete should apply");
        // An older re-delete is rejected and must not touch the index.
        assert_eq!(
            store
                .apply_replicated_namespace_delete("ios", 150)
                .await
                .expect("older delete should be ignored"),
            NamespaceDeleteOutcome::IgnoredOlder
        );

        let rows = backfill_rows(&store);
        assert_eq!(rows.len(), 1);
        assert_eq!(
            rows[0].version_ms, 200,
            "only the newest tombstone row remains"
        );
        assert_eq!(rows[0].kind, BackfillRecordKind::NamespaceTombstone);
    }

    #[tokio::test]
    async fn namespace_purge_removes_backfill_rows_for_every_removed_manifest() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .apply_replicated_namespace_delete("ios", 100)
            .await
            .expect("tombstone should apply");
        for (key, version_ms) in [("artifact-old", 150_u64), ("artifact-new", 900)] {
            store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    key,
                    "application/octet-stream",
                    b"payload",
                    version_ms,
                    None,
                    None,
                )
                .await
                .expect("artifact should apply");
        }

        store
            .apply_replicated_namespace_delete("ios", 0)
            .await
            .expect("purge should succeed");

        let rows = backfill_rows(&store);
        assert_eq!(
            rows.iter()
                .map(|row| (row.version_ms, row.kind))
                .collect::<Vec<_>>(),
            vec![(100, BackfillRecordKind::NamespaceTombstone)],
            "the purge removes every artifact row and leaves the tombstone row consistent with its CF"
        );
    }

    #[tokio::test]
    async fn version_zero_records_index_under_their_effective_version() {
        let (_temp_dir, config, store) = temp_store();

        // A legacy record with `version_ms == 0` is only decodable from disk
        // (new writes are re-stamped), so inject one directly.
        let (artifact_id, record) = inline_manifest_record(
            &config.tenant_id,
            "ios",
            "legacy",
            0,
            4_242,
            b"legacy-bytes",
        );
        store
            .db
            .put_cf(
                store.cf(ROCKSDB_CF_MANIFESTS),
                artifact_id.as_bytes(),
                record,
            )
            .expect("legacy manifest should write");
        store
            .db
            .put_cf(
                store.cf(ROCKSDB_CF_KEY_VALUE),
                artifact_id.as_bytes(),
                b"legacy-bytes",
            )
            .expect("legacy bytes should write");

        assert!(
            store
                .run_backfill_index_build()
                .expect("build should succeed")
        );
        let rows = backfill_rows(&store);
        assert_eq!(rows.len(), 1);
        assert_eq!(
            rows[0].version_ms, 4_242,
            "the build keys the row under the created_at_ms fallback"
        );

        // A live overwrite must derive the old row's key from the same
        // effective version, or the legacy row dangles.
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "legacy",
                "application/octet-stream",
                b"fresh-bytes",
                9_000,
                None,
                None,
            )
            .await
            .expect("overwrite should apply");
        let rows = backfill_rows(&store);
        assert_eq!(rows.len(), 1, "the effective-version old row is deleted");
        assert_eq!(rows[0].version_ms, 9_000);
    }

    #[tokio::test]
    async fn record_flipping_between_inline_and_segment_leaves_one_backfill_row() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"inline-v1",
                100,
                None,
                None,
            )
            .await
            .expect("inline version should apply");
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"segment-v2",
                200,
            )
            .await
            .expect("segmented version should apply");

        let rows = backfill_rows(&store);
        assert_eq!(rows.len(), 1, "the old inline-kind key is deleted");
        assert_eq!(rows[0].kind, BackfillRecordKind::SegmentArtifact);
        assert_eq!(rows[0].version_ms, 200);

        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"inline-v3",
                300,
                None,
                None,
            )
            .await
            .expect("inline re-flip should apply");

        let rows = backfill_rows(&store);
        assert_eq!(rows.len(), 1, "the old segment-kind key is deleted");
        assert_eq!(rows[0].kind, BackfillRecordKind::InlineArtifact);
        assert_eq!(rows[0].version_ms, 300);
    }

    async fn populate_mixed_dataset(store: &Store) {
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "segmented",
                "application/octet-stream",
                b"segmented-v1",
                100,
            )
            .await
            .expect("segmented artifact should apply");
        // LWW overwrite so the live index exercised delete-old + put-new.
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "segmented",
                "application/octet-stream",
                b"segmented-v2",
                300,
            )
            .await
            .expect("segmented overwrite should apply");
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                "action_cache/aa/10",
                "application/octet-stream",
                b"action-result",
                400,
                None,
                None,
            )
            .await
            .expect("action-cache entry should apply");
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "android",
                "removed-by-tombstone",
                "application/octet-stream",
                b"doomed",
                240,
                None,
                None,
            )
            .await
            .expect("doomed artifact should apply");
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "android",
                "survives-tombstone",
                "application/octet-stream",
                b"survivor",
                260,
                None,
                None,
            )
            .await
            .expect("surviving artifact should apply");
        store
            .apply_replicated_namespace_delete("android", 250)
            .await
            .expect("tombstone should apply");
    }

    #[tokio::test]
    async fn background_build_over_a_quiescent_store_matches_live_maintenance() {
        let (_temp_dir, _config, store) = temp_store();
        populate_mixed_dataset(&store).await;
        let live_rows = backfill_rows(&store);
        assert!(!live_rows.is_empty());

        // Simulate a pre-existing dataset that was never maintained: wipe the
        // index keyspace and rebuild from the manifests + tombstones CFs.
        store
            .db
            .delete_range_cf(
                store.cf(ROCKSDB_CF_KEY_VALUE),
                BACKFILL_IDX_PREFIX.as_bytes(),
                &backfill_index_prefix_upper_bound(),
            )
            .expect("index wipe should succeed");
        assert!(backfill_rows(&store).is_empty());

        assert!(
            store
                .run_backfill_index_build()
                .expect("build should succeed")
        );
        assert!(store.backfill_index_built());
        assert_eq!(
            backfill_rows(&store),
            live_rows,
            "the built index is identical to the live-maintained one"
        );
        assert!(
            !store
                .run_backfill_index_build()
                .expect("no-op build should succeed"),
            "a completed build does not run again"
        );
    }

    #[tokio::test]
    async fn crash_mid_build_then_rerun_completes_without_duplicate_or_missing_rows() {
        let (_temp_dir, _config, store) = temp_store();
        populate_mixed_dataset(&store).await;
        let live_rows = backfill_rows(&store);
        store
            .db
            .delete_range_cf(
                store.cf(ROCKSDB_CF_KEY_VALUE),
                BACKFILL_IDX_PREFIX.as_bytes(),
                &backfill_index_prefix_upper_bound(),
            )
            .expect("index wipe should succeed");

        // Crash after the first chunk: some rows are written, no completion.
        store.failpoints().set_once(
            FailpointName::AfterBackfillIndexBuildChunk,
            FailpointAction::Error("crash mid-build".into()),
        );
        assert!(store.run_backfill_index_build().is_err());
        assert!(!store.backfill_index_built());

        assert!(
            store
                .run_backfill_index_build()
                .expect("re-run should complete")
        );
        assert_eq!(
            backfill_rows(&store),
            live_rows,
            "the re-run leaves no duplicate or missing rows"
        );
    }

    #[tokio::test]
    async fn rollback_window_after_a_clean_shutdown_triggers_a_rebuild() {
        let (_temp_dir, config, store) = temp_store();
        populate_mixed_dataset(&store).await;
        assert!(
            store
                .run_backfill_index_build()
                .expect("build should succeed")
        );
        store
            .stamp_backfill_maintained_seq_clean_shutdown()
            .expect("clean-shutdown stamp should write");
        drop(store);

        // A pre-backfill binary runs in the rollback window: its writes bump
        // the sequence number but maintain no index rows.
        let (artifact_id, record) = inline_manifest_record(
            &config.tenant_id,
            "ios",
            "written-during-rollback",
            7_777,
            7_777,
            b"foreign",
        );
        {
            let foreign = open_foreign_db(&config);
            let manifests = foreign
                .cf_handle(ROCKSDB_CF_MANIFESTS)
                .expect("manifests CF should exist");
            foreign
                .put_cf(manifests, artifact_id.as_bytes(), record)
                .expect("foreign manifest should write");
            let key_value = foreign
                .cf_handle(ROCKSDB_CF_KEY_VALUE)
                .expect("key_value CF should exist");
            foreign
                .put_cf(key_value, artifact_id.as_bytes(), b"foreign")
                .expect("foreign bytes should write");
        }

        let store = reopen_store(&config);
        assert!(
            !store.backfill_index_built(),
            "any sequence gap after a clean-shutdown stamp forces a rebuild"
        );
        assert!(
            store
                .run_backfill_index_build()
                .expect("rebuild should succeed")
        );
        assert!(
            backfill_rows(&store)
                .iter()
                .any(|row| row.record_id == artifact_id && row.version_ms == 7_777),
            "the rebuild indexes the rollback-window write"
        );
    }

    #[tokio::test]
    async fn clean_restart_without_foreign_writes_keeps_the_built_index() {
        let (_temp_dir, config, store) = temp_store();
        populate_mixed_dataset(&store).await;
        assert!(
            store
                .run_backfill_index_build()
                .expect("build should succeed")
        );
        let rows = backfill_rows(&store);
        store
            .stamp_backfill_maintained_seq_clean_shutdown()
            .expect("clean-shutdown stamp should write");
        drop(store);

        let store = reopen_store(&config);
        assert!(store.backfill_index_built(), "no gap, no rebuild");
        assert_eq!(backfill_rows(&store), rows);
    }

    #[tokio::test]
    async fn crash_then_small_foreign_window_is_the_documented_undetected_band() {
        let (_temp_dir, config, store) = temp_store();
        populate_mixed_dataset(&store).await;
        assert!(
            store
                .run_backfill_index_build()
                .expect("build should succeed")
        );
        // No clean-shutdown stamp: the process crashed. The last stamp is the
        // build completion's periodic (unclean) one.
        drop(store);

        let (artifact_id, record) = inline_manifest_record(
            &config.tenant_id,
            "ios",
            "written-after-crash",
            8_888,
            8_888,
            b"foreign",
        );
        {
            let foreign = open_foreign_db(&config);
            let manifests = foreign
                .cf_handle(ROCKSDB_CF_MANIFESTS)
                .expect("manifests CF should exist");
            foreign
                .put_cf(manifests, artifact_id.as_bytes(), record)
                .expect("foreign manifest should write");
        }

        let store = reopen_store(&config);
        assert!(
            store.backfill_index_built(),
            "a below-slack gap after an unclean shutdown does not rebuild"
        );
        assert!(
            !backfill_rows(&store)
                .iter()
                .any(|row| row.record_id == artifact_id),
            "the foreign write is missing from the index: the documented crash+light-traffic band"
        );
    }

    #[tokio::test]
    async fn repeated_forgiven_crash_windows_accumulate_until_a_rebuild() {
        let (_temp_dir, config, store) = temp_store();
        populate_mixed_dataset(&store).await;
        assert!(
            store
                .run_backfill_index_build()
                .expect("build should succeed")
        );
        // Crash (no clean-shutdown stamp), then a small foreign window.
        drop(store);
        let (first_artifact_id, record) = inline_manifest_record(
            &config.tenant_id,
            "ios",
            "foreign-window-one",
            8_888,
            8_888,
            b"foreign",
        );
        {
            let foreign = open_foreign_db(&config);
            let manifests = foreign
                .cf_handle(ROCKSDB_CF_MANIFESTS)
                .expect("manifests CF should exist");
            foreign
                .put_cf(manifests, first_artifact_id.as_bytes(), record)
                .expect("foreign manifest should write");
        }

        // First boot after the crash: the sub-slack gap is forgiven but
        // recorded in the persisted ledger.
        let store = reopen_store(&config);
        assert!(
            store.backfill_index_built(),
            "a single sub-slack window is forgiven"
        );
        let first_forgiven = store.backfill_forgiven_seqs().expect("ledger should read");
        assert!(first_forgiven > 0, "the forgiven gap must be recorded");

        // Crash again with a second sub-slack foreign window. The prior
        // forgiven windows are simulated by pre-filling the ledger to the
        // slack (writing millions of real foreign rows would be
        // prohibitive); what matters is that this window's gap is under the
        // slack on its own while the accumulated sum is not.
        drop(store);
        let (second_artifact_id, record) = inline_manifest_record(
            &config.tenant_id,
            "ios",
            "foreign-window-two",
            9_999,
            9_999,
            b"foreign",
        );
        {
            let foreign = open_foreign_db(&config);
            let manifests = foreign
                .cf_handle(ROCKSDB_CF_MANIFESTS)
                .expect("manifests CF should exist");
            foreign
                .put_cf(manifests, second_artifact_id.as_bytes(), record)
                .expect("foreign manifest should write");
            let key_value = foreign
                .cf_handle(ROCKSDB_CF_KEY_VALUE)
                .expect("key_value CF should exist");
            foreign
                .put_cf(
                    key_value,
                    backfill_meta_key(BACKFILL_META_FORGIVEN_SEQS).as_bytes(),
                    BACKFILL_SEQ_STAMP_SLACK_SEQS.to_le_bytes(),
                )
                .expect("forgiveness ledger should write");
        }

        let store = reopen_store(&config);
        assert!(
            !store.backfill_index_built(),
            "a cumulative forgiven total past the slack forces a rebuild"
        );
        assert!(
            store
                .run_backfill_index_build()
                .expect("rebuild should succeed")
        );
        assert!(
            backfill_rows(&store)
                .iter()
                .any(|row| row.record_id == second_artifact_id),
            "the rebuild indexes the previously missed foreign writes"
        );
        assert_eq!(
            store.backfill_forgiven_seqs().expect("ledger should read"),
            0,
            "a full rebuild resets the forgiveness ledger"
        );
    }

    #[tokio::test]
    async fn forgiven_crash_window_then_clean_restart_keeps_the_index_and_resets_the_ledger() {
        let (_temp_dir, config, store) = temp_store();
        populate_mixed_dataset(&store).await;
        assert!(
            store
                .run_backfill_index_build()
                .expect("build should succeed")
        );
        drop(store);
        let (artifact_id, record) = inline_manifest_record(
            &config.tenant_id,
            "ios",
            "written-after-crash",
            8_888,
            8_888,
            b"foreign",
        );
        {
            let foreign = open_foreign_db(&config);
            let manifests = foreign
                .cf_handle(ROCKSDB_CF_MANIFESTS)
                .expect("manifests CF should exist");
            foreign
                .put_cf(manifests, artifact_id.as_bytes(), record)
                .expect("foreign manifest should write");
        }

        let store = reopen_store(&config);
        assert!(
            store.backfill_index_built(),
            "a single sub-slack window is forgiven"
        );
        assert!(
            store.backfill_forgiven_seqs().expect("ledger should read") > 0,
            "the forgiven gap must be recorded"
        );

        store
            .stamp_backfill_maintained_seq_clean_shutdown()
            .expect("clean-shutdown stamp should write");
        drop(store);

        let store = reopen_store(&config);
        assert!(
            store.backfill_index_built(),
            "a gap-free clean restart does not rebuild"
        );
        assert_eq!(
            store.backfill_forgiven_seqs().expect("ledger should read"),
            0,
            "a gap-free clean boot resets the forgiveness ledger"
        );
        assert!(
            !backfill_rows(&store)
                .iter()
                .any(|row| row.record_id == artifact_id),
            "the forgiven window stays the documented undetected band"
        );
    }

    #[test]
    fn backfill_rebuild_decision_applies_slack_only_after_unclean_shutdowns() {
        // Clean shutdown: any gap at all is a foreign write.
        assert!(!backfill_rebuild_required(true, 0, 1_000));
        assert!(backfill_rebuild_required(true, 1, 1_000));
        // Unclean shutdown: gaps up to the slack are this binary's own
        // unstamped writes.
        assert!(!backfill_rebuild_required(false, 1_000, 1_000));
        assert!(backfill_rebuild_required(false, 1_001, 1_000));
    }

    #[tokio::test]
    async fn backfill_rows_coexist_with_inline_bytes_and_blob_refs() {
        let (_temp_dir, _config, store) = temp_store();

        // Populate all three `key_value` keyspaces: inline artifact bytes
        // (hex-id keys), blob_ref/ reverse rows (via an action-cache entry
        // referencing a blob), and backfill/ rows.
        let digest = reapi_digest(0xaa, 4);
        let blob = persist_reapi_blob(&store, "ios", &digest, b"blob").await;
        let entry = persist_action_cache_entry(
            &store,
            "ios",
            0xbb,
            &action_result_referencing(&[&digest]),
            1_000,
        )
        .await;
        store
            .apply_replicated_namespace_delete("android", 2_000)
            .await
            .expect("tombstone should apply");
        store
            .stamp_backfill_maintained_seq()
            .expect("maintenance stamp should write");

        // Each keyspace round-trips independently.
        assert!(
            store
                .inline_bytes(&entry.artifact_id)
                .expect("inline bytes should read")
                .is_some(),
            "inline artifact bytes are untouched by backfill rows"
        );
        let ref_prefix = action_cache_blob_ref_prefix(&blob.artifact_id);
        let blob_ref_rows = store
            .db
            .iterator_cf(
                store.cf(ROCKSDB_CF_KEY_VALUE),
                IteratorMode::From(ref_prefix.as_bytes(), rocksdb::Direction::Forward),
            )
            .map(|item| item.expect("blob-ref iteration should succeed"))
            .take_while(|(key, _)| key.starts_with(ref_prefix.as_bytes()))
            .count();
        assert_eq!(blob_ref_rows, 1, "blob_ref/ rows are intact");
        let rows = backfill_rows(&store);
        assert_eq!(
            rows.len(),
            3,
            "the index scan sees exactly the blob, the entry, and the tombstone — \
            never the meta stamp or sibling keyspaces"
        );
    }

    #[tokio::test]
    async fn backfill_index_pages_walk_every_row_with_stable_cursors() {
        let (_temp_dir, _config, store) = temp_store();
        for version_ms in 1..=5_u64 {
            store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    &format!("artifact-{version_ms}"),
                    "application/octet-stream",
                    b"payload",
                    version_ms * 100,
                    None,
                    None,
                )
                .await
                .expect("artifact should apply");
        }

        let mut versions = Vec::new();
        let mut after: Option<Vec<u8>> = None;
        loop {
            let page = store
                .backfill_index_page(after.as_deref(), 2)
                .expect("page should load");
            versions.extend(page.entries.iter().map(|row| row.version_ms));
            // Rows removed between pages neither repeat nor skip survivors:
            // delete the newest not-yet-listed artifact mid-walk.
            if versions.len() == 2 {
                let manifest = store
                    .manifest_for_key(ArtifactProducer::Xcode, "ios", "artifact-3")
                    .expect("manifest should read")
                    .expect("manifest should exist");
                store
                    .delete_artifact_metadata(&[manifest])
                    .expect("delete should succeed");
            }
            match page.next_after {
                Some(next) => after = Some(next),
                None => break,
            }
        }
        assert_eq!(
            versions,
            vec![500, 400, 200, 100],
            "pagination is newest-first, loss-free for survivors, and terminates"
        );
    }

    #[tokio::test]
    async fn newer_replicated_upserts_win_over_older_ones() {
        let (_temp_dir, _config, store) = temp_store();

        assert!(
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    "artifact",
                    "application/octet-stream",
                    b"v1",
                    100,
                )
                .await
                .expect("initial artifact should apply")
                .applied()
        );
        assert!(
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    "artifact",
                    "application/octet-stream",
                    b"v2",
                    200,
                )
                .await
                .expect("newer artifact should apply")
                .applied()
        );
        assert_eq!(
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    "artifact",
                    "application/octet-stream",
                    b"stale",
                    150,
                )
                .await
                .expect("stale artifact should resolve cleanly"),
            ArtifactApplyOutcome::IgnoredStale
        );
        assert_eq!(
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    "artifact",
                    "application/octet-stream",
                    b"v2",
                    200,
                )
                .await
                .expect("equal-version artifact should resolve cleanly"),
            ArtifactApplyOutcome::IgnoredEqual
        );

        let manifest = store
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .expect("artifact should remain");
        assert_eq!(manifest.version_ms, 200);
        assert_eq!(read_manifest_bytes(&store, &manifest).await, b"v2");
    }

    #[test]
    fn versions_converged_requires_a_non_zero_matching_incoming_version() {
        assert!(versions_converged(100, 100));
        assert!(!versions_converged(100, 50));
        assert!(!versions_converged(100, 0));
        // Both sides zero: only this pair exercises the non-zero guard, and a
        // zero incoming version still attests nothing.
        assert!(!versions_converged(0, 0));
    }

    #[tokio::test]
    async fn apply_outcome_distinguishes_equal_from_strictly_older() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
                100,
                None,
                None,
            )
            .await
            .expect("initial inline artifact should apply");

        assert_eq!(
            store
                .artifact_apply_outcome(ArtifactProducer::Gradle, "ios", "artifact", 150)
                .expect("outcome should resolve"),
            ArtifactApplyOutcome::Applied
        );
        assert_eq!(
            store
                .artifact_apply_outcome(ArtifactProducer::Gradle, "ios", "artifact", 100)
                .expect("outcome should resolve"),
            ArtifactApplyOutcome::IgnoredEqual
        );
        assert_eq!(
            store
                .artifact_apply_outcome(ArtifactProducer::Gradle, "ios", "artifact", 50)
                .expect("outcome should resolve"),
            ArtifactApplyOutcome::IgnoredStale
        );
        // Version 0 carries no ordering information, so it never reports equal.
        assert_eq!(
            store
                .artifact_apply_outcome(ArtifactProducer::Gradle, "ios", "artifact", 0)
                .expect("outcome should resolve"),
            ArtifactApplyOutcome::IgnoredStale
        );

        assert_eq!(
            store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    "artifact",
                    "application/octet-stream",
                    b"payload",
                    100,
                    None,
                    None,
                )
                .await
                .expect("equal-version inline apply should resolve cleanly"),
            ArtifactApplyOutcome::IgnoredEqual
        );
        assert_eq!(
            store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    "artifact",
                    "application/octet-stream",
                    b"payload",
                    50,
                    None,
                    None,
                )
                .await
                .expect("older inline apply should resolve cleanly"),
            ArtifactApplyOutcome::IgnoredStale
        );
    }

    #[tokio::test]
    async fn multipart_upload_round_trip() {
        let (_temp_dir, config, store) = temp_store();
        let upload_id = store
            .start_multipart_upload("acme", "ios", "builds", "hash-1", "Module.framework")
            .expect("failed to start upload");

        let part_1 = config.tmp_dir.join("part-1");
        let part_2 = config.tmp_dir.join("part-2");
        std::fs::write(&part_1, b"part-one-").expect("failed to write part 1");
        std::fs::write(&part_2, b"part-two").expect("failed to write part 2");

        store
            .add_multipart_part(&upload_id, 1, &part_1, 9)
            .await
            .expect("failed to store part 1");
        store
            .add_multipart_part(&upload_id, 2, &part_2, 8)
            .await
            .expect("failed to store part 2");

        let manifest = store
            .complete_multipart_upload(&upload_id, &[1, 2])
            .await
            .expect("failed to complete upload");

        assert_eq!(
            read_manifest_bytes(&store, &manifest).await,
            b"part-one-part-two"
        );
        assert!(
            store
                .multipart_upload(&upload_id)
                .expect("failed to load multipart upload")
                .is_none()
        );
    }

    #[test]
    fn multipart_start_rejects_oversized_initial_metadata_without_reserving_a_slot() {
        let (_temp_dir, _config, store) = temp_store();
        let oversized_name = "x".repeat(MAX_MULTIPART_RECORD_BYTES);

        let error = store
            .start_multipart_upload("acme", "ios", "builds", "hash-1", &oversized_name)
            .expect_err("oversized initial metadata should be rejected");

        assert!(is_multipart_capacity_error(&error));
        assert_eq!(store.multipart_usage(), (0, 0));
        assert_eq!(
            store
                .count_cf_entries_exact(ROCKSDB_CF_MULTIPART_UPLOADS)
                .expect("multipart records should count"),
            0
        );
    }

    #[tokio::test]
    async fn multipart_quotas_survive_restart_and_release_on_abort() {
        let (_temp_dir, config, store) = temp_store_with(|config| {
            config.multipart_max_active_uploads = 1;
            config.multipart_max_stored_bytes = 20;
        });
        let upload_id = store
            .start_multipart_upload("acme", "ios", "builds", "hash-1", "Module.framework")
            .expect("first upload should fit");
        assert!(is_multipart_capacity_error(
            &store
                .start_multipart_upload("acme", "ios", "builds", "hash-2", "Other.framework")
                .expect_err("active upload limit should reject another upload")
        ));

        let part_1 = config.tmp_dir.join("bounded-part-1");
        let part_2 = config.tmp_dir.join("bounded-part-2");
        std::fs::write(&part_1, b"1234567").expect("write first part");
        std::fs::write(&part_2, b"1234").expect("write second part");
        let mismatched = config.tmp_dir.join("bounded-mismatched-part");
        std::fs::write(&mismatched, b"1234").expect("write mismatched part");
        let mismatch_error = store
            .add_multipart_part(&upload_id, 1, &mismatched, 3)
            .await
            .expect_err("declared size must match physical storage");
        assert!(matches!(mismatch_error, MultipartError::Other(_)));
        assert_eq!(store.multipart_usage(), (1, 0));
        assert_eq!(
            store.add_multipart_part(&upload_id, 0, &part_1, 7).await,
            Err(MultipartError::PartsMismatch)
        );
        assert_eq!(
            store
                .add_multipart_part(&upload_id, (MAX_MULTIPART_PARTS + 1) as u32, &part_1, 7,)
                .await,
            Err(MultipartError::PartsMismatch)
        );
        store
            .add_multipart_part(&upload_id, 1, &part_1, 7)
            .await
            .expect("first part should fit");
        assert_eq!(store.multipart_usage(), (1, 7));
        let oversized = config.tmp_dir.join("bounded-oversized-part");
        std::fs::write(&oversized, vec![b'x'; 14]).expect("write oversized part");
        assert_eq!(
            store
                .add_multipart_part(&upload_id, 2, &oversized, 14)
                .await,
            Err(MultipartError::CapacityExceeded)
        );

        let replacement = config.tmp_dir.join("bounded-part-replacement");
        std::fs::write(&replacement, b"12345").expect("write replacement part");
        store
            .add_multipart_part(&upload_id, 1, &replacement, 5)
            .await
            .expect("smaller replacement should release capacity");
        store
            .add_multipart_part(&upload_id, 2, &part_2, 4)
            .await
            .expect("released capacity should be reusable");
        assert_eq!(store.multipart_usage(), (1, 9));

        let orphan = config
            .data_dir
            .join("multipart")
            .join(&upload_id)
            .join("uncommitted-candidate");
        std::fs::write(&orphan, b"orphan").expect("write orphaned candidate");

        drop(store);
        let io = IoController::new(
            Metrics::new(config.region.clone(), config.tenant_id.clone()),
            config.file_descriptor_pool_size,
            std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
            vec![config.tmp_dir.clone(), config.data_dir.clone()],
        )
        .expect("reopened io controller should build");
        let memory = MemoryController::new(
            io.metrics(),
            config.memory_soft_limit_bytes,
            config.memory_hard_limit_bytes,
        );
        let reopened = Store::open(&config, io, memory).expect("store should reopen");
        assert_eq!(reopened.multipart_usage(), (1, 9));
        assert!(!orphan.exists(), "startup must reclaim orphaned candidates");
        assert!(is_multipart_capacity_error(
            &reopened
                .start_multipart_upload("acme", "ios", "builds", "hash-3", "Third.framework")
                .expect_err("reopened store should enforce durable upload count")
        ));

        reopened
            .abort_multipart_upload(&upload_id)
            .await
            .expect("abort should release quota");
        assert_eq!(reopened.multipart_usage(), (0, 0));
        reopened
            .start_multipart_upload("acme", "ios", "builds", "hash-4", "Fourth.framework")
            .expect("released upload slot should be reusable");
    }

    #[tokio::test]
    async fn multipart_startup_discards_records_with_mismatched_files() {
        let (_temp_dir, config, store) = temp_store();
        let upload_id = store
            .start_multipart_upload("acme", "ios", "builds", "hash", "Module.framework")
            .expect("upload should start");
        let staged = config.tmp_dir.join("mismatched-part");
        std::fs::write(&staged, b"original").expect("write staged part");
        store
            .add_multipart_part(&upload_id, 1, &staged, 8)
            .await
            .expect("part should be stored");
        let stored = store
            .multipart_upload(&upload_id)
            .expect("upload lookup should succeed")
            .expect("upload should exist");
        let stored_path = PathBuf::from(&stored.parts[&1].path);
        std::fs::write(&stored_path, b"wrong").expect("corrupt stored part");
        drop(store);

        let io = IoController::new(
            Metrics::new(config.region.clone(), config.tenant_id.clone()),
            config.file_descriptor_pool_size,
            std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
            vec![config.tmp_dir.clone(), config.data_dir.clone()],
        )
        .expect("reopened io controller should build");
        let memory = MemoryController::new(
            io.metrics(),
            config.memory_soft_limit_bytes,
            config.memory_hard_limit_bytes,
        );
        let reopened = Store::open(&config, io, memory).expect("store should reopen");
        assert_eq!(reopened.multipart_usage(), (0, 0));
        assert!(
            reopened
                .multipart_upload(&upload_id)
                .expect("upload lookup should succeed")
                .is_none(),
            "a mismatched incomplete upload cannot complete safely"
        );
        assert!(!stored_path.exists());
    }

    #[tokio::test]
    async fn multipart_startup_preserves_records_above_the_active_limit() {
        let (_temp_dir, mut config, store) = temp_store_with(|config| {
            config.multipart_max_active_uploads = 3;
        });
        let mut upload_ids = Vec::new();
        for index in 0..3 {
            upload_ids.push(
                store
                    .start_multipart_upload(
                        "acme",
                        "ios",
                        "builds",
                        &format!("hash-{index}"),
                        &format!("Module-{index}.framework"),
                    )
                    .expect("upload should start"),
            );
        }
        drop(store);

        config.multipart_max_active_uploads = 1;
        let io = IoController::new(
            Metrics::new(config.region.clone(), config.tenant_id.clone()),
            config.file_descriptor_pool_size,
            std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
            vec![config.tmp_dir.clone(), config.data_dir.clone()],
        )
        .expect("reopened io controller should build");
        let memory = MemoryController::new(
            io.metrics(),
            config.memory_soft_limit_bytes,
            config.memory_hard_limit_bytes,
        );
        let reopened = Store::open(&config, io, memory).expect("store should reopen");
        assert_eq!(reopened.multipart_usage(), (3, 0));
        assert_eq!(
            reopened
                .count_cf_entries_exact(ROCKSDB_CF_MULTIPART_UPLOADS)
                .expect("multipart records should count"),
            3
        );
        assert!(is_multipart_capacity_error(
            &reopened
                .start_multipart_upload("acme", "ios", "builds", "new", "New.framework")
                .expect_err("persisted overage should reject growth")
        ));
        for upload_id in upload_ids {
            reopened
                .abort_multipart_upload(&upload_id)
                .await
                .expect("preserved upload should remain abortable");
        }
        reopened
            .start_multipart_upload("acme", "ios", "builds", "new", "New.framework")
            .expect("a new upload should start after the overage is reclaimed");
    }

    #[test]
    fn multipart_janitor_scan_pages_durable_uploads_with_a_fixed_bound() {
        let (_temp_dir, _config, store) = temp_store();
        for index in 0..3 {
            store
                .start_multipart_upload(
                    "acme",
                    "ios",
                    "builds",
                    &format!("hash-{index}"),
                    &format!("Module-{index}.framework"),
                )
                .expect("upload should start");
        }

        let (first, cursor) = store
            .multipart_uploads_older_than_bounded(u64::MAX, None, 2)
            .expect("first page should scan");
        assert_eq!(first.len(), 2);
        let (second, cursor) = store
            .multipart_uploads_older_than_bounded(u64::MAX, cursor.as_deref(), 2)
            .expect("second page should scan");
        assert_eq!(second.len(), 1);
        assert!(cursor.is_none(), "the final page should reset the cursor");
    }

    #[tokio::test]
    async fn concurrent_multipart_part_writes_do_not_lose_updates() {
        let (_temp_dir, config, store) = temp_store();
        let upload_id = store
            .start_multipart_upload("acme", "ios", "builds", "hash-1", "Module.framework")
            .expect("failed to start upload");
        let store = Arc::new(store);

        let mut handles = Vec::new();
        for part_number in 1u32..=8 {
            let part_path = config.tmp_dir.join(format!("part-{part_number}"));
            std::fs::write(&part_path, format!("part-{part_number}")).expect("write part");
            let store = store.clone();
            let upload_id = upload_id.clone();
            handles.push(tokio::spawn(async move {
                store
                    .add_multipart_part(&upload_id, part_number, &part_path, 6)
                    .await
                    .expect("part should persist");
            }));
        }
        for handle in handles {
            handle.await.expect("part task should complete");
        }

        let upload = store
            .multipart_upload(&upload_id)
            .expect("failed to load multipart upload")
            .expect("upload should exist");
        assert_eq!(upload.parts.len(), 8, "all 8 parts should be persisted");
        for part_number in 1u32..=8 {
            assert!(
                upload.parts.contains_key(&part_number),
                "missing part {part_number}"
            );
        }
    }

    #[test]
    fn multipart_size_validation_accounts_for_replaced_parts() {
        let mut parts = BTreeMap::new();
        parts.insert(
            1,
            MultipartPart {
                path: "part-1".into(),
                size: 10,
            },
        );
        parts.insert(
            2,
            MultipartPart {
                path: "part-2".into(),
                size: 5,
            },
        );

        assert_eq!(next_total_size(&parts, 1, 8), 13);
        assert_eq!(
            validate_total_size(101, 100),
            Err(MultipartError::TotalSizeExceeded)
        );
        assert_eq!(validate_total_size(100, 100), Ok(()));
    }

    #[test]
    fn outbox_queue_round_trip() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .enqueue(OutboxMessage {
                target: "http://peer".into(),
                operation: ReplicationOperation::DeleteNamespace {
                    namespace_id: "ios".into(),
                    version_ms: 123,
                },
            })
            .expect("failed to enqueue outbox message");

        let messages = store
            .outbox_messages()
            .expect("failed to read outbox messages");
        assert_eq!(messages.len(), 1);

        let (key, message) = &messages[0];
        assert_eq!(
            *message,
            OutboxMessage {
                target: "http://peer".into(),
                operation: ReplicationOperation::DeleteNamespace {
                    namespace_id: "ios".into(),
                    version_ms: 123,
                },
            }
        );

        store
            .delete_outbox_message(key)
            .expect("failed to delete outbox message");
        assert!(
            store
                .outbox_messages()
                .expect("failed to read outbox messages")
                .is_empty()
        );
    }

    #[tokio::test]
    async fn outbox_capacity_is_enforced_atomically_across_writers() {
        let (_temp_dir, _config, store) = temp_store_with(|config| {
            config.outbox_max_depth = 5;
        });
        let store = Arc::new(store);
        let mut writers = Vec::new();
        for index in 0..20 {
            let store = store.clone();
            writers.push(tokio::spawn(async move {
                store
                    .persist_inline_artifact_from_bytes_and_enqueue(
                        ArtifactProducer::Reapi,
                        "ios",
                        &format!("action_cache/{index}"),
                        "application/x-protobuf",
                        b"value",
                        &["http://peer".into()],
                        None,
                        None,
                    )
                    .await
            }));
        }

        let mut accepted = 0;
        let mut rejected = 0;
        for writer in writers {
            match writer.await.expect("writer task") {
                Ok(_) => accepted += 1,
                Err(error) if is_outbox_full_error(&error) => rejected += 1,
                Err(error) => panic!("unexpected write failure: {error}"),
            }
        }

        assert_eq!(accepted, 5);
        assert_eq!(rejected, 15);
        assert_eq!(store.outbox_depth(), 5);
        assert_eq!(store.outbox_message_count().expect("outbox count"), 5);
    }

    #[tokio::test]
    async fn deleting_an_outbox_message_releases_capacity() {
        let (_temp_dir, _config, store) = temp_store_with(|config| {
            config.outbox_max_depth = 1;
        });
        let message = OutboxMessage {
            target: "http://peer".into(),
            operation: ReplicationOperation::DeleteNamespace {
                namespace_id: "ios".into(),
                version_ms: 123,
            },
        };
        store.enqueue(message.clone()).expect("first enqueue");
        assert!(is_outbox_full_error(
            &store
                .enqueue(message.clone())
                .expect_err("capacity rejection")
        ));

        let (key, _) = store
            .next_outbox_message(None)
            .expect("outbox read")
            .expect("queued message");
        store.delete_outbox_message(&key).expect("outbox deletion");
        store.enqueue(message).expect("capacity should be reusable");
        assert_eq!(store.outbox_depth(), 1);
    }

    #[test]
    fn reopening_the_store_rebuilds_exact_outbox_depth() {
        let (_temp_dir, config, store) = temp_store_with(|config| {
            config.outbox_max_depth = 1;
        });
        let message = OutboxMessage {
            target: "http://peer".into(),
            operation: ReplicationOperation::DeleteNamespace {
                namespace_id: "ios".into(),
                version_ms: 123,
            },
        };
        store.enqueue(message.clone()).expect("seed outbox");
        drop(store);

        let io = IoController::new(
            Metrics::new(config.region.clone(), config.tenant_id.clone()),
            config.file_descriptor_pool_size,
            std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
            vec![config.tmp_dir.clone(), config.data_dir.clone()],
        )
        .expect("failed to recreate io controller");
        let memory = MemoryController::new(
            io.metrics(),
            config.memory_soft_limit_bytes,
            config.memory_hard_limit_bytes,
        );
        let reopened = Store::open(&config, io, memory).expect("failed to reopen store");

        assert_eq!(reopened.outbox_depth(), 1);
        assert!(is_outbox_full_error(
            &reopened
                .enqueue(message)
                .expect_err("reopened store must enforce persisted depth")
        ));
    }

    #[test]
    fn outbox_drains_metadata_before_earlier_bulk_messages() {
        let (_temp_dir, _config, store) = temp_store();

        // Bulk first (earlier timestamp), metadata second: the metadata-lane
        // key must still sort first so an inline action-cache entry is not
        // parked behind a segment-blob backlog.
        store
            .enqueue(OutboxMessage {
                target: "http://peer".into(),
                operation: ReplicationOperation::UpsertArtifact {
                    producer: ArtifactProducer::Reapi,
                    namespace_id: "ios".into(),
                    key: "blob/aabb".into(),
                    content_type: "application/octet-stream".into(),
                    artifact_id: "blob-artifact".into(),
                    inline: false,
                    version_ms: 1,
                    branch: None,
                    trunk: None,
                },
            })
            .expect("failed to enqueue bulk message");
        store
            .enqueue(OutboxMessage {
                target: "http://peer".into(),
                operation: ReplicationOperation::UpsertArtifact {
                    producer: ArtifactProducer::Reapi,
                    namespace_id: "ios".into(),
                    key: "action_cache/ccdd".into(),
                    content_type: "application/x-protobuf".into(),
                    artifact_id: "entry-artifact".into(),
                    inline: true,
                    version_ms: 2,
                    branch: None,
                    trunk: None,
                },
            })
            .expect("failed to enqueue metadata message");

        let messages = store
            .outbox_messages()
            .expect("failed to read outbox messages");
        let keys: Vec<&str> = messages
            .iter()
            .map(|(key, _)| std::str::from_utf8(key).expect("outbox key should be utf-8"))
            .collect();
        assert!(
            keys[0].starts_with("0-") && keys[1].starts_with(OUTBOX_BULK_LANE_PREFIX),
            "expected metadata lane before bulk lane, got {keys:?}"
        );
        let (_, first) = &messages[0];
        assert!(!first.operation.is_bulk());
        // Legacy unprefixed keys (zero-padded timestamps) drain between the
        // lanes across a rolling upgrade.
        let legacy = format!("{:020}-legacy", crate::utils::now_ms());
        assert!(keys[0] < legacy.as_str() && legacy.as_str() < keys[1]);
    }

    fn bulk_outbox_message(key: &str) -> OutboxMessage {
        OutboxMessage {
            target: "http://peer".into(),
            operation: ReplicationOperation::UpsertArtifact {
                producer: ArtifactProducer::Reapi,
                namespace_id: "ios".into(),
                key: key.into(),
                content_type: "application/octet-stream".into(),
                artifact_id: format!("{key}-artifact"),
                inline: false,
                version_ms: 1,
                branch: None,
                trunk: None,
            },
        }
    }

    fn metadata_outbox_message(key: &str) -> OutboxMessage {
        OutboxMessage {
            target: "http://peer".into(),
            operation: ReplicationOperation::UpsertArtifact {
                producer: ArtifactProducer::Reapi,
                namespace_id: "ios".into(),
                key: key.into(),
                content_type: "application/x-protobuf".into(),
                artifact_id: format!("{key}-artifact"),
                inline: true,
                version_ms: 2,
                branch: None,
                trunk: None,
            },
        }
    }

    #[test]
    fn outbox_lane_depth_tracks_enqueue_and_delete() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .enqueue(bulk_outbox_message("blob/aa"))
            .expect("failed to enqueue bulk message");
        store
            .enqueue(bulk_outbox_message("blob/bb"))
            .expect("failed to enqueue bulk message");
        store
            .enqueue(metadata_outbox_message("action_cache/cc"))
            .expect("failed to enqueue metadata message");

        assert_eq!(store.outbox_depth(), 3);
        assert_eq!(store.outbox_bulk_depth(), 2);

        // The metadata lane sorts first, so the head is the inline entry.
        let (metadata_key, _) = store
            .next_outbox_message(None)
            .expect("outbox read")
            .expect("queued message");
        assert!(!is_bulk_outbox_key(&metadata_key));
        store
            .delete_outbox_message(&metadata_key)
            .expect("outbox deletion");
        assert_eq!(store.outbox_depth(), 2);
        assert_eq!(store.outbox_bulk_depth(), 2);

        let (bulk_key, _) = store
            .next_outbox_message(None)
            .expect("outbox read")
            .expect("queued message");
        assert!(is_bulk_outbox_key(&bulk_key));
        store
            .delete_outbox_message(&bulk_key)
            .expect("outbox deletion");
        assert_eq!(store.outbox_depth(), 1);
        assert_eq!(store.outbox_bulk_depth(), 1);
    }

    #[test]
    fn reopening_the_store_rebuilds_outbox_lane_depths() {
        let (_temp_dir, config, store) = temp_store();
        store
            .enqueue(bulk_outbox_message("blob/aa"))
            .expect("seed bulk lane");
        store
            .enqueue(bulk_outbox_message("blob/bb"))
            .expect("seed bulk lane");
        store
            .enqueue(metadata_outbox_message("action_cache/cc"))
            .expect("seed metadata lane");
        drop(store);

        let io = IoController::new(
            Metrics::new(config.region.clone(), config.tenant_id.clone()),
            config.file_descriptor_pool_size,
            std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
            vec![config.tmp_dir.clone(), config.data_dir.clone()],
        )
        .expect("failed to recreate io controller");
        let memory = MemoryController::new(
            io.metrics(),
            config.memory_soft_limit_bytes,
            config.memory_hard_limit_bytes,
        );
        let reopened = Store::open(&config, io, memory).expect("failed to reopen store");

        assert_eq!(reopened.outbox_depth(), 3);
        assert_eq!(reopened.outbox_bulk_depth(), 2);
    }

    #[test]
    fn snapshot_reports_outbox_depth_without_loading_messages() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .enqueue(OutboxMessage {
                target: "http://peer-a".into(),
                operation: ReplicationOperation::DeleteNamespace {
                    namespace_id: "ios".into(),
                    version_ms: 123,
                },
            })
            .expect("failed to enqueue first outbox message");
        store
            .enqueue(OutboxMessage {
                target: "http://peer-b".into(),
                operation: ReplicationOperation::DeleteNamespace {
                    namespace_id: "android".into(),
                    version_ms: 456,
                },
            })
            .expect("failed to enqueue second outbox message");

        assert_eq!(
            store
                .outbox_message_count()
                .expect("outbox count should load"),
            2
        );

        let snapshot = store.snapshot().expect("snapshot should load");
        assert_eq!(snapshot.outbox_messages, 2);
        assert_eq!(
            snapshot.rocksdb_block_cache_capacity_bytes,
            _config.rocksdb_block_cache_bytes as u64
        );
        assert_eq!(
            snapshot.rocksdb_write_buffer_capacity_bytes,
            _config.rocksdb_write_buffer_manager_bytes as u64
        );
    }

    #[tokio::test]
    async fn local_write_enqueues_replication_targets_in_same_store_operation() {
        let (_temp_dir, _config, store) = temp_store();
        let targets = vec!["http://peer-a".to_string(), "http://peer-b".to_string()];

        let manifest = store
            .persist_inline_artifact_from_bytes_and_enqueue(
                ArtifactProducer::Xcode,
                "ios",
                "cas-1",
                "application/json",
                br#"{"ok":true}"#,
                &targets,
                None,
                None,
            )
            .await
            .expect("artifact should persist");

        let queued = store
            .outbox_messages()
            .expect("outbox messages should load")
            .into_iter()
            .map(|(_, message)| message)
            .collect::<Vec<_>>();

        assert_eq!(queued.len(), 2);
        assert_eq!(queued[0].target, "http://peer-a");
        assert_eq!(queued[1].target, "http://peer-b");
        for message in queued {
            assert_eq!(
                message.operation,
                ReplicationOperation::UpsertArtifact {
                    producer: ArtifactProducer::Xcode,
                    namespace_id: "ios".into(),
                    key: "cas-1".into(),
                    content_type: "application/json".into(),
                    artifact_id: manifest.artifact_id.clone(),
                    version_ms: manifest.version_ms,
                    inline: true,
                    branch: None,
                    trunk: None,
                }
            );
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_artifact_writes_batch_segment_fsyncs() {
        let (_temp_dir, config, store) = temp_store();
        let store = Arc::new(store);

        // Slow every segment fsync so all writers reach the durability barrier
        // within one window. With one fsync per write under the global segment
        // write lock these serialize (one fsync each); group commit must
        // coalesce them into far fewer.
        store.failpoints().set_always(
            FailpointName::BeforeSegmentFsync,
            FailpointAction::Sleep(std::time::Duration::from_millis(50)),
        );

        let writers = 16u64;
        let mut handles = Vec::new();
        for i in 0..writers {
            let store = store.clone();
            let path = config.tmp_dir.join(format!("artifact-{i}"));
            std::fs::write(&path, format!("artifact-body-{i}")).expect("write artifact body");
            handles.push(tokio::spawn(async move {
                store
                    .persist_artifact_from_path_and_enqueue(
                        ArtifactProducer::Xcode,
                        "ns",
                        &format!("key-{i}"),
                        "application/octet-stream",
                        StagedArtifactPath::new(&path, FileCachePolicy::Adaptive),
                        &[],
                    )
                    .await
                    .expect("artifact should persist");
            }));
        }
        for handle in handles {
            handle.await.expect("writer task should complete");
        }

        let fsyncs = store
            .segment_fsync_count
            .load(std::sync::atomic::Ordering::Relaxed);
        assert!(
            fsyncs <= 4,
            "expected concurrent writes to batch segment fsyncs (<=4) but observed {fsyncs} \
             for {writers} writers — every write is fsyncing under the global segment write lock"
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_replicated_artifact_applies_batch_segment_fsyncs() {
        let (_temp_dir, _config, store) = temp_store();
        let store = Arc::new(store);

        // A fresh node backfilling an account applies inbound artifacts
        // concurrently (the pass pipelines its fetch and apply stages). Inbound
        // applies share the foreground write's segment-append + durability path
        // (`persist_artifact_from_path_with_version`), so group commit must
        // coalesce their fsyncs too — otherwise the parallel backfill fetch just
        // re-serializes one fsync per inbound write and gains nothing. Slow every
        // fsync so all appliers reach the durability barrier within one window.
        store.failpoints().set_always(
            FailpointName::BeforeSegmentFsync,
            FailpointAction::Sleep(std::time::Duration::from_millis(50)),
        );

        let appliers = 16u64;
        let mut handles = Vec::new();
        for i in 0..appliers {
            let store = store.clone();
            handles.push(tokio::spawn(async move {
                store
                    .apply_replicated_artifact_from_bytes(
                        ArtifactProducer::Xcode,
                        "ns",
                        &format!("key-{i}"),
                        "application/octet-stream",
                        format!("artifact-body-{i}").as_bytes(),
                        1_000 + i,
                    )
                    .await
                    .expect("replicated artifact should apply");
            }));
        }
        for handle in handles {
            handle.await.expect("applier task should complete");
        }

        let fsyncs = store
            .segment_fsync_count
            .load(std::sync::atomic::Ordering::Relaxed);
        assert!(
            fsyncs <= 4,
            "expected concurrent replicated applies to batch segment fsyncs (<=4) but observed \
             {fsyncs} for {appliers} appliers — inbound backfill writes are fsyncing per write \
             under the global segment write lock"
        );
    }

    #[tokio::test]
    async fn local_namespace_delete_enqueues_replication_targets_in_same_store_operation() {
        let (_temp_dir, _config, store) = temp_store();
        let targets = vec!["http://peer-a".to_string(), "http://peer-b".to_string()];

        store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "cas-1",
                "application/json",
                br#"{"ok":true}"#,
            )
            .await
            .expect("artifact should persist");

        let version_ms = store
            .delete_namespace_and_enqueue("ios", &targets)
            .await
            .expect("namespace delete should succeed");

        let queued = store
            .outbox_messages()
            .expect("outbox messages should load")
            .into_iter()
            .map(|(_, message)| message)
            .collect::<Vec<_>>();

        assert_eq!(queued.len(), 2);
        for message in queued {
            assert_eq!(
                message.operation,
                ReplicationOperation::DeleteNamespace {
                    namespace_id: "ios".into(),
                    version_ms,
                }
            );
        }
    }

    #[tokio::test]
    async fn segment_backed_write_remains_visible_after_post_commit_error_and_restart() {
        let (_temp_dir, config, store) = temp_store();
        store.failpoints().set_once(
            FailpointName::AfterMetadataCommitBeforeReturn,
            FailpointAction::Error("post-commit failure".into()),
        );

        let error = store
            .persist_artifact_from_bytes_and_enqueue(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"segment-bytes",
                &["http://peer-a".to_string()],
            )
            .await
            .expect_err("write should fail after the durable commit");
        assert!(error.contains("post-commit failure"));

        drop(store);

        let reopened_metrics = Metrics::new(config.region.clone(), config.tenant_id.clone());
        let reopened_io = IoController::new(
            reopened_metrics,
            config.file_descriptor_pool_size,
            std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
            vec![config.tmp_dir.clone(), config.data_dir.clone()],
        )
        .expect("failed to create reopened io controller");
        let reopened_memory = MemoryController::new(
            reopened_io.metrics(),
            config.memory_soft_limit_bytes,
            config.memory_hard_limit_bytes,
        );
        let reopened =
            Store::open(&config, reopened_io, reopened_memory).expect("failed to reopen store");

        let manifest = reopened
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .expect("artifact should remain visible after restart");
        assert_eq!(
            read_manifest_bytes(&reopened, &manifest).await,
            b"segment-bytes"
        );
        assert_eq!(
            reopened
                .outbox_message_count()
                .expect("outbox count should load"),
            1
        );
    }

    #[tokio::test]
    async fn keyvalue_write_remains_visible_after_post_commit_error_and_restart() {
        let (_temp_dir, config, store) = temp_store();
        store.failpoints().set_once(
            FailpointName::AfterMetadataCommitBeforeReturn,
            FailpointAction::Error("post-commit failure".into()),
        );

        let error = store
            .persist_inline_artifact_from_bytes_and_enqueue(
                ArtifactProducer::Xcode,
                "ios",
                "cas-1",
                "application/json",
                br#"{"value":"ok"}"#,
                &["http://peer-a".to_string()],
                None,
                None,
            )
            .await
            .expect_err("write should fail after the durable commit");
        assert!(error.contains("post-commit failure"));

        drop(store);

        let reopened_metrics = Metrics::new(config.region.clone(), config.tenant_id.clone());
        let reopened_io = IoController::new(
            reopened_metrics,
            config.file_descriptor_pool_size,
            std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
            vec![config.tmp_dir.clone(), config.data_dir.clone()],
        )
        .expect("failed to create reopened io controller");
        let reopened_memory = MemoryController::new(
            reopened_io.metrics(),
            config.memory_soft_limit_bytes,
            config.memory_hard_limit_bytes,
        );
        let reopened =
            Store::open(&config, reopened_io, reopened_memory).expect("failed to reopen store");

        let manifest = reopened
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "cas-1")
            .await
            .expect("artifact fetch should succeed")
            .expect("keyvalue should remain visible after restart");
        assert_eq!(
            read_manifest_bytes(&reopened, &manifest).await,
            br#"{"value":"ok"}"#
        );
        assert_eq!(
            reopened
                .outbox_message_count()
                .expect("outbox count should load"),
            1
        );
    }

    #[tokio::test]
    async fn duplicate_replicated_upserts_and_deletes_are_idempotent() {
        let (_temp_dir, _config, store) = temp_store();

        assert_eq!(
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    "artifact",
                    "application/octet-stream",
                    b"payload",
                    100,
                )
                .await
                .expect("first artifact apply should succeed"),
            ArtifactApplyOutcome::Applied
        );
        assert_eq!(
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    "artifact",
                    "application/octet-stream",
                    b"payload",
                    100,
                )
                .await
                .expect("duplicate artifact apply should succeed"),
            ArtifactApplyOutcome::IgnoredEqual
        );
        assert_eq!(
            store
                .apply_replicated_namespace_delete("ios", 150)
                .await
                .expect("first delete should succeed"),
            NamespaceDeleteOutcome::Applied
        );
        assert_eq!(
            store
                .apply_replicated_namespace_delete("ios", 150)
                .await
                .expect("duplicate delete should succeed"),
            NamespaceDeleteOutcome::IgnoredOlder
        );
        assert!(
            store
                .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
                .await
                .expect("artifact fetch should succeed")
                .is_none()
        );
    }

    #[tokio::test]
    async fn reordered_delivery_converges_to_the_same_winner() {
        let (_temp_dir_a, _config_a, first) = temp_store();
        let (_temp_dir_b, _config_b, second) = temp_store();

        first
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"v1",
                100,
            )
            .await
            .expect("initial write should succeed");
        first
            .apply_replicated_namespace_delete("ios", 150)
            .await
            .expect("delete should succeed");
        first
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"v1",
                100,
            )
            .await
            .expect("duplicate stale write should succeed");
        first
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"v2",
                200,
            )
            .await
            .expect("newer write should succeed");

        second
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"v2",
                200,
            )
            .await
            .expect("newer write should succeed");
        second
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"v1",
                100,
            )
            .await
            .expect("older duplicate write should succeed");
        second
            .apply_replicated_namespace_delete("ios", 150)
            .await
            .expect("delete should succeed");
        second
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"v1",
                100,
            )
            .await
            .expect("older duplicate write should succeed");

        let first_manifest = first
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
            .await
            .expect("first fetch should succeed")
            .expect("artifact should remain");
        let second_manifest = second
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
            .await
            .expect("second fetch should succeed")
            .expect("artifact should remain");

        assert_eq!(first_manifest.version_ms, 200);
        assert_eq!(second_manifest.version_ms, 200);
        assert_eq!(read_manifest_bytes(&first, &first_manifest).await, b"v2");
        assert_eq!(read_manifest_bytes(&second, &second_manifest).await, b"v2");
    }

    #[test]
    fn segment_rotation_requires_margin_for_oversized_artifacts() {
        assert_eq!(
            segment_rotation_required_bytes(0),
            MAX_SEGMENT_BYTES * SEGMENT_FREE_SPACE_MARGIN
        );
        assert_eq!(
            segment_rotation_required_bytes(MAX_SEGMENT_BYTES),
            MAX_SEGMENT_BYTES * SEGMENT_FREE_SPACE_MARGIN
        );
        assert_eq!(
            segment_rotation_required_bytes(3 * MAX_SEGMENT_BYTES),
            3 * MAX_SEGMENT_BYTES * SEGMENT_FREE_SPACE_MARGIN
        );
    }

    #[tokio::test]
    async fn sweep_orphaned_segments_returns_zero_without_segments_dir() {
        let (_temp_dir, _config, store) = temp_store();

        let swept = store
            .sweep_orphaned_segments()
            .await
            .expect("sweep should succeed");

        assert_eq!(swept, 0);
    }

    #[tokio::test]
    async fn sweep_orphaned_segments_removes_stray_files_and_keeps_live_segments() {
        let (_temp_dir, config, store) = temp_store();
        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("artifact should persist");
        let stray_path = config.data_dir.join("segments").join("stray.seg");
        std::fs::write(&stray_path, b"junk").expect("stray segment should be written");

        let swept = store
            .sweep_orphaned_segments()
            .await
            .expect("sweep should succeed");

        assert_eq!(swept, 1);
        assert!(!stray_path.exists());
        let bytes = store
            .read_artifact_bytes(&manifest)
            .await
            .expect("live artifact should remain readable");
        assert_eq!(bytes, b"payload");
    }

    #[tokio::test]
    async fn sweep_orphaned_segments_reclaims_crash_window_segment_and_metadata() {
        let (_temp_dir, _config, store) = temp_store();
        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("artifact should persist");
        let segment_id = manifest
            .segment_id
            .clone()
            .expect("artifact should be segment-backed");
        let segment_file = store.segment_path(&segment_id);
        assert!(segment_file.exists());

        // Simulate the crash window: rotation saved the ring state without
        // the evicted segment, but the process died before the unlink.
        let mut state = store
            .load_segment_state_from_db()
            .expect("state should load");
        assert!(state.remove_segment(&segment_id));
        store.save_segment_state(&state).expect("state should save");

        let swept = store
            .sweep_orphaned_segments()
            .await
            .expect("sweep should succeed");

        assert_eq!(swept, 1);
        assert!(!segment_file.exists());
        assert!(
            store
                .manifest(&manifest.artifact_id)
                .expect("manifest lookup should succeed")
                .is_none()
        );
    }

    #[tokio::test]
    async fn segment_generation_tracks_saved_state() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .save_segment_state(&SegmentState {
                old: vec![SegmentReference::new("aged".into(), 1)],
                current: vec![SegmentReference::new("settled".into(), 2)],
                new: vec![SegmentReference::new("fresh".into(), 3)],
            })
            .expect("state should save");

        assert_eq!(
            store.segment_generation("aged").expect("lookup"),
            Some(SegmentGeneration::Old)
        );
        assert_eq!(
            store.segment_generation("settled").expect("lookup"),
            Some(SegmentGeneration::Current)
        );
        assert_eq!(
            store.segment_generation("fresh").expect("lookup"),
            Some(SegmentGeneration::New)
        );
        assert_eq!(store.segment_generation("missing").expect("lookup"), None);
    }

    #[tokio::test]
    async fn evicting_a_segment_updates_the_cached_generation() {
        let (_temp_dir, _config, store) = temp_store();
        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("artifact should persist");
        let segment_id = manifest
            .segment_id
            .clone()
            .expect("artifact should be segment-backed");
        assert_eq!(
            store.segment_generation(&segment_id).expect("lookup"),
            Some(SegmentGeneration::New)
        );

        store
            .evict_segment(&segment_id)
            .await
            .expect("eviction should succeed");

        assert_eq!(store.segment_generation(&segment_id).expect("lookup"), None);
    }

    #[tokio::test]
    async fn segment_state_snapshot_survives_reopen() {
        let (_temp_dir, config, store) = temp_store();
        let manifest = store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("artifact should persist");
        let segment_id = manifest
            .segment_id
            .clone()
            .expect("artifact should be segment-backed");
        drop(store);

        let io = IoController::new(
            Metrics::new(config.region.clone(), config.tenant_id.clone()),
            config.file_descriptor_pool_size,
            std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
            vec![config.tmp_dir.clone(), config.data_dir.clone()],
        )
        .expect("io controller should build");
        let memory = MemoryController::new(
            io.metrics(),
            config.memory_soft_limit_bytes,
            config.memory_hard_limit_bytes,
        );
        let reopened = Store::open(&config, io, memory).expect("store should reopen");

        assert_eq!(
            reopened.segment_generation(&segment_id).expect("lookup"),
            Some(SegmentGeneration::New)
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_state_mutations_do_not_lose_updates() {
        let (_temp_dir, _config, store) = temp_store();
        let store = Arc::new(store);

        let mut tasks = Vec::new();
        for index in 0..16u64 {
            let store = store.clone();
            tasks.push(tokio::spawn(async move {
                store
                    .mutate_segment_state(|state| {
                        state.push_new(
                            SegmentReference::new(format!("segment-{index}"), index),
                            16,
                            16,
                            16,
                        )
                    })
                    .await
                    .expect("mutation should succeed");
            }));
        }
        for task in tasks {
            task.await.expect("mutation task should finish");
        }

        for index in 0..16u64 {
            assert!(
                store
                    .segment_generation(&format!("segment-{index}"))
                    .expect("lookup")
                    .is_some(),
                "segment-{index} should survive concurrent mutations"
            );
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_evictions_do_not_lose_state_updates() {
        let (_temp_dir, _config, store) = temp_store();
        let store = Arc::new(store);
        let segments: Vec<SegmentReference> = (0..16)
            .map(|index| SegmentReference::new(format!("segment-{index}"), index as u64))
            .collect();
        store
            .save_segment_state(&SegmentState {
                old: segments.clone(),
                current: Vec::new(),
                new: Vec::new(),
            })
            .expect("state should save");

        let mut tasks = Vec::new();
        for segment in &segments {
            let store = store.clone();
            let segment_id = segment.segment_id.clone();
            tasks.push(tokio::spawn(async move {
                store
                    .evict_segment(&segment_id)
                    .await
                    .expect("eviction should succeed");
            }));
        }
        for task in tasks {
            task.await.expect("eviction task should finish");
        }

        for segment in &segments {
            assert_eq!(
                store
                    .segment_generation(&segment.segment_id)
                    .expect("lookup"),
                None,
                "{} should be gone after concurrent evictions",
                segment.segment_id
            );
        }
    }
}
