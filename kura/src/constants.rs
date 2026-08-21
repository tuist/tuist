// Xcode compilation-cache outputs have a heavy tail (fat debug-info objects,
// asset-catalog outputs). At 25 MiB that tail could never publish, so the
// affected tasks missed on every rebuild AND re-attempted the doomed upload
// each time, which made the cache net-negative for app-shaped projects.
// Uploads stream to the budgeted tmp dir (never RAM), so the binding ceiling
// is MAX_SEGMENT_BYTES; 256 MiB stays well under it.
pub const MAX_XCODE_BYTES: u64 = 256 * 1024 * 1024;
pub const MAX_GRADLE_BYTES: u64 = 100 * 1024 * 1024;
pub const MAX_MODULE_PART_BYTES: u64 = 10 * 1024 * 1024;
pub const MAX_MODULE_TOTAL_BYTES: u64 = 2 * 1024 * 1024 * 1024;
pub const MAX_SEGMENT_BYTES: u64 = 512 * 1024 * 1024;
pub const MAX_REPLICATION_BODY_BYTES: u64 = 4 * MAX_SEGMENT_BYTES;
pub const DEFAULT_TMP_DIR_MAX_BYTES: u64 = 4 * MAX_REPLICATION_BODY_BYTES;
pub const DESIRED_OLD_SEGMENTS: usize = 1;
pub const DESIRED_CURRENT_SEGMENTS: usize = 2;
pub const DESIRED_NEW_SEGMENTS: usize = 2;
// CAS capacity policy. When KURA_CAS_CAPACITY_BYTES is unset the segment-ring
// budget derives from the data-dir filesystem size; the max-percent ceiling
// also applies to configured values so rotation (which appends a new segment
// before evicting the oldest one) can never run the disk full. The legacy
// 1/2/2 generation counts above remain the floor, so nodes without disk-size
// information keep today's behavior.
pub const CAS_CAPACITY_DEFAULT_DISK_PERCENT: u64 = 50;
pub const CAS_CAPACITY_MAX_DISK_PERCENT: u64 = 80;
pub const MAX_DESIRED_SEGMENTS: usize = 16_384;
pub const REPLICATION_RETRY_SECS: u64 = 2;
pub const REPLICATION_BACKOFF_BASE_SECS: u64 = 2;
pub const REPLICATION_BACKOFF_MAX_SECS: u64 = 60;
// How long an outbox artifact upload may go without producing another body
// chunk before the attempt is abandoned. Chunk production tracks socket
// progress (the next chunk is pulled only when the transport accepts bytes),
// and the body stream re-arms the window when it terminates, so the response
// wait gets one whole window of its own — the receiver still has to copy the
// staged body into a segment and fsync it under a node-wide lock before it
// answers. A stalled receiver therefore fails fast while a slow-but-
// progressing transfer of any size completes. The upload client itself
// carries no read timeout: the response side is silent for the whole upload,
// so a read timeout there is a hard ceiling on total upload time and
// permanently strands large artifacts. Tunable per node with
// KURA_REPLICATION_UPLOAD_STALL_MS, since this is now the only deadline on
// the path.
pub const DEFAULT_REPLICATION_UPLOAD_STALL_MS: u64 = 60_000;
pub const ROCKSDB_BYTES_PER_SYNC: u64 = 1024 * 1024;
pub const ROCKSDB_WAL_BYTES_PER_SYNC: u64 = 1024 * 1024;

pub const ROCKSDB_LEVEL0_SLOWDOWN_TRIGGER: i32 = 20;
pub const ROCKSDB_LEVEL0_STOP_TRIGGER: i32 = 36;
pub const ROCKSDB_SOFT_PENDING_COMPACTION_BYTES: u64 = 64 * 1024 * 1024 * 1024;
pub const ROCKSDB_HARD_PENDING_COMPACTION_BYTES: u64 = 256 * 1024 * 1024 * 1024;

pub const DEFAULT_OUTBOX_MAX_DEPTH: usize = 100_000;
pub const DEFAULT_MULTIPART_UPLOAD_TTL_MS: u64 = 24 * 60 * 60 * 1000;
pub const DEFAULT_MULTIPART_JANITOR_INTERVAL_MS: u64 = 10 * 60 * 1000;
pub const DEFAULT_MULTIPART_MAX_ACTIVE_UPLOADS: usize = 128;
// REAPI action-cache entries are append-only from the client's perspective
// (every source change publishes new keys), so a recency sweep is what bounds
// the namespace keyspace. An expired entry costs its next reader one
// recompile + republish, which also refreshes it fleet-wide; the deletes-per-
// sweep cap smooths the first sweep over a store that never expired anything.
pub const REAPI_ACTION_CACHE_TTL_MS: u64 = 30 * 24 * 60 * 60 * 1000;
pub const REAPI_ACTION_CACHE_EXPIRY_INTERVAL_MS: u64 = 6 * 60 * 60 * 1000;
pub const REAPI_ACTION_CACHE_EXPIRY_MAX_DELETES: usize = 100_000;
// Clients re-publish an entry's unchanged manifest when a per-key lookup
// reveals it fell out of the snapshot's size-capped wire view (the view ranks
// by version, which publish-dedup never refreshes). The damping window keeps
// a fleet of cold machines from stampeding version bumps for the same entry:
// an identical re-publish only applies when the stored version has aged past
// it — one refresh per entry per window fleet-wide.
pub const REAPI_ACTION_CACHE_REFRESH_DAMPING_MS: u64 = 24 * 60 * 60 * 1000;
// How many manifest READS a trunk-scoped snapshot build may pay per entry it is
// allowed to keep. Not rows examined: a row carrying its branch answers the trunk
// filter from the key, so rejecting feature churn costs a sequential step over a
// compact CF and is deliberately not counted here. What this bounds is the random
// read into the manifests CF, which is the work, and which only rows written
// before the branch was recorded (plus stale rows) still need.
//
// So the walk itself is bounded by the namespace's prefix rather than by this,
// and that is the intended trade: bounding the walk would truncate the trunk view
// under exactly the feature churn this scoping exists to see through, which is
// the bug the branch-keyed rows fixed. The reads are what had to be bounded, and
// they are. Generous on purpose: a backstop against a namespace with a large
// pre-branch backlog, not a tuning knob, and one that trips it logs how far it
// walked to get there.
pub const ACTION_CACHE_TRUNK_SCAN_FACTOR: usize = 8;
pub const SEGMENT_FREE_SPACE_MARGIN: u64 = 2;
pub const DEFAULT_USAGE_WINDOW_SECS: u64 = 60;
pub const DEFAULT_USAGE_FLUSH_INTERVAL_MS: u64 = 60_000;
pub const DEFAULT_USAGE_DELIVERY_INTERVAL_MS: u64 = 5_000;
pub const DEFAULT_USAGE_BATCH_SIZE: usize = 1_000;
pub const DEFAULT_USAGE_MAX_BUCKETS: usize = 10_000;
pub const DEFAULT_USAGE_OUTBOX_MAX_DEPTH: usize = 100_000;

// Ceilings a peer-facing listing page is read under: the response body a
// requester will buffer, and the row count it will accept in one page.
pub const MAX_PEER_PAGE_BYTES: u64 = 32 * 1024 * 1024;
pub const MAX_PEER_PAGE_ITEMS: usize = 2048;
pub const MAX_INLINE_REPLICATION_BODY_BYTES: u64 = 4 * 1024 * 1024;
pub const RESPONSE_STREAM_CHUNK_BYTES: usize = 512 * 1024;
pub const RESPONSE_STREAM_SEND_BUFFER_BYTES: usize = 512 * 1024;
pub const RESPONSE_STREAM_MIN_CHUNK_BYTES: usize = 8 * 1024;
pub const RESPONSE_STREAM_ENCODING_OVERHEAD_BYTES: usize = 16;

pub fn response_stream_chunk_bytes(body_bytes: u64) -> usize {
    body_bytes
        .min(RESPONSE_STREAM_CHUNK_BYTES as u64)
        .max(RESPONSE_STREAM_MIN_CHUNK_BYTES as u64) as usize
}

pub fn encoded_response_stream_chunk_bytes(body_bytes: u64) -> usize {
    response_stream_chunk_bytes(body_bytes)
        .saturating_add(RESPONSE_STREAM_ENCODING_OVERHEAD_BYTES)
        .div_ceil(RESPONSE_STREAM_MIN_CHUNK_BYTES)
        .saturating_mul(RESPONSE_STREAM_MIN_CHUNK_BYTES)
}
// Backfill horizon margin (KURA_BACKFILL_MARGIN_PERCENT default): the share
// of the age-ordered segment ring, counted from the newest, whose boundary
// segment's seal-time stat becomes the horizon. The margin's share of the
// ring's time span is the backfill window's structural slack — a peer absence
// shorter than that span is always re-covered. 40% matches the "new" band
// under the legacy 1:2:2 old/current/new ring ratio, so on a warm ordered
// ring the default slack is exactly the new band.
pub const DEFAULT_BACKFILL_MARGIN_PERCENT: u64 = 40;

/// Default for `KURA_BACKFILL_READY_RING_PERCENT` — the segment-ring fullness
/// at which a node still running its initial backfill cycle marks itself
/// ready. Derived as half the backfill margin (margin 40 → ready at 20)
/// rather than fixed: the margin's share of the ring is the recency band a
/// backfill re-covers first, so half of it is data the node has provably
/// caught up on before taking traffic, and retuning the margin per mesh moves
/// the readiness point with it. Floored at 1 so a 1% margin cannot derive a
/// zero threshold (which would mark every cold node ready immediately).
pub const fn default_backfill_ready_ring_percent(margin_percent: u64) -> u64 {
    let derived = margin_percent / 2;
    if derived == 0 { 1 } else { derived }
}
// Clock-skew allowance subtracted from a pass's start point before it becomes
// the per-peer watermark. `version_ms` values are stamped by writer clocks, so
// a writer running behind the requester's clock can stamp entries below an
// exact start-point watermark, and later windows over that peer would skip
// them for good. One minute comfortably covers NTP-disciplined fleet drift;
// its cost is one minute of re-listed (presence-checked, not re-fetched)
// entries per completed pass. Compiled rather than env-exposed: no
// demonstrated per-mesh tuning need.
pub const BACKFILL_WATERMARK_SKEW_ALLOWANCE_MS: u64 = 60_000;
// Backfill index maintenance-stamp cadence. Each stamp is one tiny put of the
// DB's latest sequence number into `backfill/meta/last_maintained_seq`; a
// short cadence keeps the unclean-shutdown staleness slack (below) small.
pub const BACKFILL_SEQ_STAMP_INTERVAL_MS: u64 = 5_000;
// Sequence-number slack for rollback-window staleness detection after an
// UNCLEAN shutdown (after a clean-shutdown stamp, any gap at all triggers a
// rebuild). The gap a crash legitimately leaves is the sequence numbers
// consumed between the last periodic stamp and the crash: every key in every
// WriteBatch consumes one, an artifact apply writes ~10 keys, and replication
// bursts have been observed in the tens of thousands of applies per second —
// so one 5s stamp interval can legitimately consume a few million sequence
// numbers. The slack must exceed that per-interval burst or a crash under
// load triggers a spurious multi-hour rebuild. The cost of the margin is the
// documented residual band: a crash immediately followed by a pre-AB binary
// window that writes fewer than this many sequence numbers goes undetected
// on that boot (known limitation; the common rollback shape — drain, roll
// back, roll forward — is fully covered by the clean-shutdown stamp instead).
// The band is bounded cumulatively, not per boot: each forgiven sub-slack gap
// is added to the persisted `backfill/meta/forgiven_seqs` ledger, and once
// the running total exceeds this same slack the next boot rebuilds anyway —
// so repeated crash→foreign-window→reboot cycles can never push the total
// undetected exposure past one slack's worth of sequence numbers. The ledger
// resets on any full rebuild and on a gap-free clean-shutdown boot.
pub const BACKFILL_SEQ_STAMP_SLACK_SEQS: u64 = 8_000_000;
// Per-chunk row budget for the one-off backfill index build. The build resumes
// each chunk from a key cursor with a fresh short-lived iterator: one
// long-lived iterator would pin a RocksDB snapshot for the whole scan (hours
// on multi-million-entry nodes), blocking compaction of everything written
// since it opened.
pub const BACKFILL_INDEX_BUILD_CHUNK_ROWS: usize = 4_096;
// How many segment-index rows a CAS eviction scans between yields. The scan is
// entirely synchronous RocksDB work (a manifest read per artifact, plus a
// reverse-row prefix scan and an inline-bytes read per cascaded action-cache
// entry), so without a yield one eviction parks a runtime worker for its whole
// duration and the process stops answering probes it could otherwise serve
// from process-local state. Smaller than the snapshot gate's stride because
// each row here costs several reads rather than one cache hit.
pub const SEGMENT_EVICTION_YIELD_ROWS: usize = 256;
// Byte ceiling of one backfill bodies batch: the sum of body bytes one
// `POST /_internal/backfill/bodies` response may carry, and the per-entry
// oversized cutoff (entries larger than this route to the per-artifact
// endpoint). The requester composes batches from listed sizes against this
// SAME constant and the serving side enforces it — sender and receiver limits
// pinned to one definition so they can never diverge (the inline-413 lesson:
// a receive limit keyed off a different constant than the send path 413'd
// every 1–4 MiB inline artifact and poisoned replication passes).
pub const BACKFILL_BODIES_BATCH_BYTES: u64 = 32 * 1024 * 1024;
// Tuple-count bound for one bodies request, shared by the requester (batch
// composition) and the serving side (request validation). Bounds the request
// JSON and the per-frame header overhead of a batch composed entirely of tiny
// entries.
pub const MAX_BACKFILL_BODIES_ENTRIES: usize = 65_536;
// Read cap for the bodies request JSON itself. Sized for
// MAX_BACKFILL_BODIES_ENTRIES tuples of (kind name, 64-char hex id,
// version_ms) with JSON overhead.
pub const MAX_BACKFILL_BODIES_REQUEST_BYTES: u64 = 16 * 1024 * 1024;
// Requester-side byte threshold for composing one bodies batch
// (KURA_BACKFILL_BATCH_BYTES default), and the oversized cutoff above which a
// listed entry routes to the per-artifact endpoint up front. Defaults to the
// shared response ceiling so batches arrive as full as the serving side will
// ever stream them; config parsing rejects values above the ceiling because
// entries between the two bounds would compose into batches the serving side
// bounces back as fetch-individually frames. The value itself is a
// deferred-to-implementation measurement: it is finalized against real Bazel
// small-artifact profiles in the e2e throughput check and a staging mesh
// before the tuist flag flip.
pub const DEFAULT_BACKFILL_BATCH_BYTES: u64 = BACKFILL_BODIES_BATCH_BYTES;
// Deadline for a composed-but-unfilled bodies batch. Bazel workloads list
// hundreds of thousands of tiny entries, so a byte threshold alone could park
// claimed tuples in a half-full batch for as long as listing keeps paginating;
// the interval bounds the listing-to-apply latency of every claimed tuple.
// Compiled rather than env-exposed: a timing internal with no per-mesh
// geometry dependence (same standard as the retry backoff bounds below).
pub const BACKFILL_BATCH_FLUSH_INTERVAL_MS: u64 = 1_000;
// Records per phase-3 group commit of one backfill bodies batch: staged
// applies (segmented and inline alike) commit through ONE shared non-sync
// WriteBatch per group of up to this many records, instead of one WriteBatch
// per record. A live cold-node pass showed the per-record commits dominating
// disk IOPS (~4,110 WAL appends per batch at 85–92% device utilization for
// only 25–35 MB/s); grouping cuts that to ~ceil(records / this) appends. The
// value bounds three things at once: how many artifact write-lock stripes one
// group holds across its commit (lock-hold time for concurrent live writers),
// how large the shared WriteBatch grows (inline bodies ride inside it), and
// how much work a mid-commit failure re-lists. 64 matches the write-lock
// stripe count — one group can at worst sweep every stripe once (inline
// bytes are additionally bounded by the spooled batch itself, at most
// BACKFILL_BODIES_BATCH_BYTES across ALL groups of a batch). Compiled rather
// than env-exposed: a durability-batching internal with no per-mesh geometry
// dependence.
pub const BACKFILL_APPLY_GROUP_RECORDS: usize = 64;
// Bounded backoff for budget-exempt retryable peer responses (index building,
// endpoint-absent, peer busy, tmp budget, generic Retry-After backpressure).
// The pass retries without failing and reports cumulative retry-sleep time so
// the lifecycle layer can enforce the per-peer wall-clock cap.
pub const BACKFILL_RETRY_BACKOFF_BASE_MS: u64 = 250;
pub const BACKFILL_RETRY_BACKOFF_MAX_MS: u64 = 5_000;
// Capacity of the lister→fetcher claimed-tuple queue inside one backfill
// pass. A full queue blocks the listing walk, which bounds how many claimed
// tuples a pass can hold un-fetched (claim-set growth and re-list cost after
// a failure) while still letting listing run well ahead of body transfers.
pub const BACKFILL_FETCH_QUEUE_TUPLES: usize = 4_096;
// Per-peer failure budget for the initial join cycle: how many budget-charged
// pass failures (hard errors plus wall-clock-cap conversions) one peer may
// accumulate before it stops counting toward the node's "backfilling" state.
// Keyed by peer identity and never reset within the cycle — a flapping peer
// that reset its own budget would hold first readiness open forever, the
// exact livelock class the backfill redesign removes. Sized so routine
// transience (a rolling peer restart costs one or two charges) never
// exhausts it, while the worst case bounds the cycle at budget × max pass
// backoff per peer. Background retries continue after exhaustion.
pub const BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET: u32 = 5;
// Wall-clock cap on one pass's cumulative budget-exempt retry backoff
// (index building, not-capable/endpoint-absent, backpressure, tmp budget).
// Past the cap the lifecycle cancels the pass and charges the failure budget:
// uncapped, a cold node whose in-cycle peers are all stuck in an exempt class
// (a peer at sustained Critical memory pressure sheds bodies responses for
// hours) never charges budget and never latches ready — the politeness
// exemption would recreate the never-ready livelock. Sized to ride out an
// index build on a large peer without holding first readiness open
// indefinitely.
pub const BACKFILL_RETRYABLE_WAIT_CAP_MS: u64 = 30 * 60 * 1000;
// Tighter wall-clock cap on the not-capable class alone. A 404 means the peer
// permanently lacks the backfill routes until its own binary is replaced —
// and under an OrderedReady rolling update that replacement is *blocked
// behind this node's readiness*, so unlike an index build there is nothing to
// politely wait out: every second spent in this class is pure rollout stall.
// With the shared 30-minute cap a quiet mesh (empty recency ring, so the
// ring-fullness readiness arm can't open) held first readiness for cap ×
// failure budget = 2.5 h per updated pod on a mixed-version fleet. One minute
// still absorbs 404 blips from a peer mid-restart while converting a genuine
// pre-AB peer to a capability charge in minutes, not hours.
pub const BACKFILL_NOT_CAPABLE_WAIT_CAP_MS: u64 = 60 * 1000;
// Poll cadence of the cap watchdogs above. Coarse is fine: the caps are
// livelock backstops measured in minutes, not precise deadlines.
pub const BACKFILL_CAP_POLL_INTERVAL_MS: u64 = 1_000;
// Bounded backoff between passes over a peer whose previous pass was
// budget-charged. Distinct from BACKFILL_RETRY_BACKOFF_* (which paces
// request retries inside a pass): this paces whole-pass retries, including
// the metered background retries that continue after budget exhaustion.
pub const BACKFILL_PASS_RETRY_BACKOFF_BASE_MS: u64 = 5_000;
pub const BACKFILL_PASS_RETRY_BACKOFF_MAX_MS: u64 = 300_000;
// Delay of the single follow-up pass after a newly discovered peer's first
// completed pass: ~2× the 2s membership cadence, long enough for the peer to
// have discovered this node and applied writes that raced the bilateral
// discovery seam. Cost is one listing re-walk of the slack window. Sub-tick
// flaps remain an accepted residual (see the dirty-flag site).
pub const BACKFILL_SEAM_FOLLOWUP_DELAY_MS: u64 = 4_000;
// Retention for per-peer `backfill/wm/` watermark rows, judged by the row's
// completion-time `refreshed_at` against the local clock. A live peer that
// completes no pass for 90 days is pathological; the cost of a GC'd row is
// one unbounded-window listing re-walk on the next pass, not a correctness
// loss. A GC delete racing a late completion write is benign (the row
// resurrects and is GC'd again).
pub const BACKFILL_WATERMARK_RETENTION_MS: u64 = 90 * 24 * 60 * 60 * 1000;
// How often watermark GC runs, piggybacked on the maintenance-stamp loop (it
// also runs once at startup). The keyspace is tens of tiny rows, so daily is
// generous.
pub const BACKFILL_WATERMARK_GC_INTERVAL_MS: u64 = 24 * 60 * 60 * 1000;

pub const ROCKSDB_CF_MANIFESTS: &str = "manifests";

pub const ROCKSDB_CF_KEY_VALUE: &str = "key_value";
pub const ROCKSDB_CF_NAMESPACE_ARTIFACTS: &str = "project_artifacts";
pub const ROCKSDB_CF_NAMESPACE_TOMBSTONES: &str = "namespace_tombstones";
pub const ROCKSDB_CF_MULTIPART_UPLOADS: &str = "multipart_uploads";
pub const ROCKSDB_CF_OUTBOX: &str = "outbox";
pub const ROCKSDB_CF_USAGE_OUTBOX: &str = "usage_outbox";
pub const ROCKSDB_CF_SEGMENT_ARTIFACTS: &str = "segment_artifacts";
pub const ROCKSDB_CF_SEGMENT_STATE: &str = "segment_state";
/// Per-namespace index of REAPI action-cache entries ordered newest-first
/// (the key embeds `!version_ms`), so the snapshot reconcile reads exactly
/// its entry cap instead of scanning the whole namespace — point-reading
/// millions of blob manifests just to filter them out took tens of minutes
/// on production namespaces and every snapshot fetch timed out against it.
/// Backfilled lazily per namespace on first use.
pub const ROCKSDB_CF_ACTION_CACHE_INDEX: &str = "action_cache_index";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn response_stream_chunks_follow_payload_size_with_bounded_allocation_granularity() {
        assert_eq!(
            response_stream_chunk_bytes(0),
            RESPONSE_STREAM_MIN_CHUNK_BYTES
        );
        assert_eq!(response_stream_chunk_bytes(32 * 1024), 32 * 1024);
        assert_eq!(
            response_stream_chunk_bytes(u64::MAX),
            RESPONSE_STREAM_CHUNK_BYTES
        );
        assert_eq!(
            encoded_response_stream_chunk_bytes(0),
            RESPONSE_STREAM_MIN_CHUNK_BYTES * 2
        );
        assert_eq!(
            encoded_response_stream_chunk_bytes(RESPONSE_STREAM_CHUNK_BYTES as u64),
            RESPONSE_STREAM_CHUNK_BYTES + RESPONSE_STREAM_MIN_CHUNK_BYTES
        );
    }
}
