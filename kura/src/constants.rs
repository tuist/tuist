pub const MAX_XCODE_BYTES: u64 = 25 * 1024 * 1024;
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
pub const ROCKSDB_BYTES_PER_SYNC: u64 = 1024 * 1024;
pub const ROCKSDB_WAL_BYTES_PER_SYNC: u64 = 1024 * 1024;

pub const ROCKSDB_LEVEL0_SLOWDOWN_TRIGGER: i32 = 20;
pub const ROCKSDB_LEVEL0_STOP_TRIGGER: i32 = 36;
pub const ROCKSDB_SOFT_PENDING_COMPACTION_BYTES: u64 = 64 * 1024 * 1024 * 1024;
pub const ROCKSDB_HARD_PENDING_COMPACTION_BYTES: u64 = 256 * 1024 * 1024 * 1024;

pub const DEFAULT_OUTBOX_MAX_DEPTH: usize = 100_000;
pub const DEFAULT_MULTIPART_UPLOAD_TTL_MS: u64 = 24 * 60 * 60 * 1000;
pub const DEFAULT_MULTIPART_JANITOR_INTERVAL_MS: u64 = 10 * 60 * 1000;
pub const DEFAULT_BOOTSTRAP_TIMEOUT_MS: u64 = 30 * 60 * 1000;
pub const SEGMENT_FREE_SPACE_MARGIN: u64 = 2;
pub const DEFAULT_USAGE_WINDOW_SECS: u64 = 60;
pub const DEFAULT_USAGE_FLUSH_INTERVAL_MS: u64 = 60_000;
pub const DEFAULT_USAGE_DELIVERY_INTERVAL_MS: u64 = 5_000;
pub const DEFAULT_USAGE_BATCH_SIZE: usize = 1_000;
pub const DEFAULT_USAGE_MAX_BUCKETS: usize = 10_000;
pub const DEFAULT_USAGE_OUTBOX_MAX_DEPTH: usize = 100_000;

pub const MAX_BOOTSTRAP_PAGE_BYTES: u64 = 32 * 1024 * 1024;
pub const MAX_INLINE_REPLICATION_BODY_BYTES: u64 = 4 * 1024 * 1024;
pub const DEFAULT_BOOTSTRAP_MAX_CONCURRENT_PEERS: usize = 8;
// Per-peer artifact fetch+apply fan-out during bootstrap. Each CAS blob is an
// independent HTTP round-trip plus a local write, so the serial path is
// RTT-bound and leaves the replication bandwidth budget idle; fetching several
// at once fills it without exceeding the aggregate bandwidth limiter.
pub const DEFAULT_BOOTSTRAP_MAX_CONCURRENT_ARTIFACTS_PER_PEER: usize = 16;

pub const ROCKSDB_CF_MANIFESTS: &str = "manifests";
pub const ROCKSDB_CF_KEY_VALUE: &str = "key_value";
pub const ROCKSDB_CF_NAMESPACE_ARTIFACTS: &str = "project_artifacts";
pub const ROCKSDB_CF_NAMESPACE_TOMBSTONES: &str = "namespace_tombstones";
pub const ROCKSDB_CF_MULTIPART_UPLOADS: &str = "multipart_uploads";
pub const ROCKSDB_CF_OUTBOX: &str = "outbox";
pub const ROCKSDB_CF_USAGE_OUTBOX: &str = "usage_outbox";
pub const ROCKSDB_CF_SEGMENT_ARTIFACTS: &str = "segment_artifacts";
pub const ROCKSDB_CF_SEGMENT_STATE: &str = "segment_state";
