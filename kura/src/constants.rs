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
pub const ROCKSDB_BYTES_PER_SYNC: u64 = 1024 * 1024;
pub const ROCKSDB_WAL_BYTES_PER_SYNC: u64 = 1024 * 1024;

pub const ROCKSDB_LEVEL0_SLOWDOWN_TRIGGER: i32 = 20;
pub const ROCKSDB_LEVEL0_STOP_TRIGGER: i32 = 36;
pub const ROCKSDB_SOFT_PENDING_COMPACTION_BYTES: u64 = 64 * 1024 * 1024 * 1024;
pub const ROCKSDB_HARD_PENDING_COMPACTION_BYTES: u64 = 256 * 1024 * 1024 * 1024;

pub const DEFAULT_OUTBOX_MAX_DEPTH: usize = 100_000;
pub const DEFAULT_MULTIPART_UPLOAD_TTL_MS: u64 = 24 * 60 * 60 * 1000;
pub const DEFAULT_MULTIPART_JANITOR_INTERVAL_MS: u64 = 10 * 60 * 1000;
// REAPI action-cache entries are append-only from the client's perspective
// (every source change publishes new keys), so a recency sweep is what bounds
// the namespace keyspace. An expired entry costs its next reader one
// recompile + republish, which also refreshes it fleet-wide; the deletes-per-
// sweep cap smooths the first sweep over a store that never expired anything.
pub const REAPI_ACTION_CACHE_TTL_MS: u64 = 30 * 24 * 60 * 60 * 1000;
pub const REAPI_ACTION_CACHE_EXPIRY_INTERVAL_MS: u64 = 6 * 60 * 60 * 1000;
pub const REAPI_ACTION_CACHE_EXPIRY_MAX_DELETES: usize = 100_000;
// Not a cap on total bootstrap runtime — it is the maximum time a bootstrap may
// go *without forward progress* (a fetched page or applied artifact) before it
// is abandoned and retried. A large cold pull that keeps making progress runs to
// completion however long that takes; only a genuinely stalled one is dropped.
pub const DEFAULT_BOOTSTRAP_TIMEOUT_MS: u64 = 30 * 60 * 1000;
pub const SEGMENT_FREE_SPACE_MARGIN: u64 = 2;
pub const DEFAULT_USAGE_WINDOW_SECS: u64 = 60;
pub const DEFAULT_USAGE_FLUSH_INTERVAL_MS: u64 = 60_000;
pub const DEFAULT_USAGE_DELIVERY_INTERVAL_MS: u64 = 5_000;
pub const DEFAULT_USAGE_BATCH_SIZE: usize = 1_000;
pub const DEFAULT_USAGE_MAX_BUCKETS: usize = 10_000;
pub const DEFAULT_USAGE_OUTBOX_MAX_DEPTH: usize = 100_000;

pub const MAX_BOOTSTRAP_PAGE_BYTES: u64 = 32 * 1024 * 1024;
// Range-digest anti-entropy: partition the sorted `artifact_id` keyspace by its
// leading hex characters. 3 nibbles = 4096 buckets (~340 artifacts/bucket at
// 1.4M), enough to make a mostly-in-sync bootstrap O(delta) while keeping the
// digest payload small. `artifact_id` is a 64-char hex SHA-256, so the prefix
// length is capped well under its width.
pub const BOOTSTRAP_DIGEST_DEFAULT_PREFIX_LEN: usize = 3;
pub const BOOTSTRAP_DIGEST_MAX_PREFIX_LEN: usize = 8;
pub const MAX_INLINE_REPLICATION_BODY_BYTES: u64 = 4 * 1024 * 1024;
pub const DEFAULT_BOOTSTRAP_MAX_CONCURRENT_PEERS: usize = 8;
// Stripes for the per-artifact bootstrap fetch gate that single-flights the
// body download across peers. Sized well above the peak concurrent fetches
// (bootstrap_max_concurrent_peers x per-peer fetch concurrency) so distinct
// keys rarely share a stripe; false sharing only over-serializes briefly and is
// correctness-neutral because the gate is paired with an exact per-artifact
// presence recheck.
pub const BOOTSTRAP_FETCH_LOCK_STRIPES: usize = 1024;

pub const ROCKSDB_CF_MANIFESTS: &str = "manifests";
pub const ROCKSDB_CF_KEY_VALUE: &str = "key_value";
pub const ROCKSDB_CF_NAMESPACE_ARTIFACTS: &str = "project_artifacts";
pub const ROCKSDB_CF_NAMESPACE_TOMBSTONES: &str = "namespace_tombstones";
pub const ROCKSDB_CF_MULTIPART_UPLOADS: &str = "multipart_uploads";
pub const ROCKSDB_CF_OUTBOX: &str = "outbox";
pub const ROCKSDB_CF_USAGE_OUTBOX: &str = "usage_outbox";
pub const ROCKSDB_CF_SEGMENT_ARTIFACTS: &str = "segment_artifacts";
pub const ROCKSDB_CF_SEGMENT_STATE: &str = "segment_state";
