use std::{
    collections::{BTreeMap, HashMap, HashSet, VecDeque},
    path::{Path, PathBuf},
    pin::Pin,
    sync::{
        Arc, Mutex as StdMutex,
        atomic::{AtomicU64, Ordering},
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
use sha2::{Digest, Sha256};
use tokio::{
    io::{AsyncRead, AsyncWriteExt, ReadBuf},
    sync::{Mutex, Notify},
};
use uuid::Uuid;

use crate::{
    artifact::{
        manifest::{ArtifactManifest, PersistedManifestRecord},
        producer::ArtifactProducer,
        segment_location_record::SegmentLocationRecord,
    },
    config::Config,
    constants::{
        CAS_CAPACITY_DEFAULT_DISK_PERCENT, CAS_CAPACITY_MAX_DISK_PERCENT, DESIRED_CURRENT_SEGMENTS,
        DESIRED_NEW_SEGMENTS, DESIRED_OLD_SEGMENTS, MAX_DESIRED_SEGMENTS, MAX_MODULE_TOTAL_BYTES,
        MAX_SEGMENT_BYTES, REAPI_ACTION_CACHE_REFRESH_DAMPING_MS, ROCKSDB_BYTES_PER_SYNC,
        ROCKSDB_CF_ACTION_CACHE_INDEX, ROCKSDB_CF_KEY_VALUE, ROCKSDB_CF_MANIFESTS,
        ROCKSDB_CF_MULTIPART_UPLOADS, ROCKSDB_CF_NAMESPACE_ARTIFACTS,
        ROCKSDB_CF_NAMESPACE_TOMBSTONES, ROCKSDB_CF_OUTBOX, ROCKSDB_CF_SEGMENT_ARTIFACTS,
        ROCKSDB_CF_SEGMENT_STATE, ROCKSDB_CF_USAGE_OUTBOX, ROCKSDB_HARD_PENDING_COMPACTION_BYTES,
        ROCKSDB_LEVEL0_SLOWDOWN_TRIGGER, ROCKSDB_LEVEL0_STOP_TRIGGER,
        ROCKSDB_SOFT_PENDING_COMPACTION_BYTES, ROCKSDB_WAL_BYTES_PER_SYNC,
        SEGMENT_FREE_SPACE_MARGIN,
    },
    failpoints::{FailpointName, FailpointSet},
    io::{IoController, PersistentFile},
    memory::MemoryController,
    mmap::map_file_region,
    multipart::{error::MultipartError, part::MultipartPart, upload::MultipartUpload},
    replication::{operation::ReplicationOperation, outbox_message::OutboxMessage},
    segment::{
        generation::SegmentGeneration, reader::SegmentReader, reference::SegmentReference,
        state::SegmentState,
    },
    usage::UsageRollup,
    utils::{
        action_cache_index_key, action_cache_index_prefix, action_cache_manifest_hash,
        artifact_storage_id, ensure_tmp_dir_capacity, module_key, namespace_artifact_index_key,
        now_ms, segment_artifact_index_key, segment_artifact_index_prefix, segment_path,
        temp_file_path,
    },
};

const MULTIPART_LOCK_STRIPES: usize = 64;
const ARTIFACT_WRITE_LOCK_STRIPES: usize = 64;
pub const EXISTENCE_CACHE_CAPACITY: usize = 65_536;
const EXISTENCE_CACHE_TTL: Duration = Duration::from_secs(30);

pub struct Store {
    db: DB,
    io: IoController,
    memory: MemoryController,
    tenant_id: String,
    tmp_dir: PathBuf,
    tmp_dir_max_bytes: u64,
    data_dir: PathBuf,
    segment_ring_limits: SegmentRingLimits,
    rocksdb_block_cache_capacity_bytes: usize,
    rocksdb_block_cache: Cache,
    rocksdb_write_buffer_manager: WriteBufferManager,
    segment_write_lock: Mutex<()>,
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
    segment_handles: Mutex<SegmentHandleCache>,
    manifest_cache: StdMutex<ManifestCache>,
    existence_cache: ShardedExistenceCache,
    multipart_locks: [Mutex<()>; MULTIPART_LOCK_STRIPES],
    // Serializes writers for the same artifact so concurrent applies of one key
    // (e.g. a fresh node bootstrapping the same artifact from several peers at
    // once) can't each append their own copy to a segment and orphan all but the
    // last. Striped by artifact id so different keys still write concurrently.
    artifact_write_locks: [Mutex<()>; ARTIFACT_WRITE_LOCK_STRIPES],
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
    failpoints: Arc<FailpointSet>,
}

/// Pending read-path promotions: FIFO order plus a membership set so a hot
/// old artifact read thousands of times enqueues once.
#[derive(Default)]
struct PromotionQueue {
    order: VecDeque<String>,
    pending: HashSet<String>,
}

/// Backstop so an unbounded burst of old-artifact reads cannot grow the
/// promotion queue without limit; far above what one build's value graphs
/// enqueue (tens of thousands of artifacts).
const MAX_PENDING_PROMOTIONS: usize = 262_144;

pub struct StoreSnapshot {
    pub outbox_messages: usize,
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

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ManifestBucketDigest {
    pub prefix: String,
    pub count: u64,
    pub hash: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ManifestDigest {
    pub prefix_len: usize,
    pub buckets: Vec<ManifestBucketDigest>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct NamespaceTombstoneRecord {
    pub namespace_id: String,
    pub version_ms: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct NamespaceTombstonePage {
    pub tombstones: Vec<NamespaceTombstoneRecord>,
    pub next_after: Option<String>,
}

#[derive(Clone, Copy)]
struct PersistArtifactSpec<'a> {
    producer: ArtifactProducer,
    namespace_id: &'a str,
    key: &'a str,
    content_type: &'a str,
    version_ms: u64,
    replication_targets: &'a [String],
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ArtifactApplyOutcome {
    Applied,
    IgnoredStale,
    IgnoredTombstone,
}

impl ArtifactApplyOutcome {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Applied => "applied",
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

    pub(crate) fn applied(self) -> bool {
        matches!(self, Self::Applied)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum PersistArtifactOutcome {
    Applied(ArtifactManifest),
    IgnoredStale(ArtifactManifest),
    IgnoredTombstone,
}

// Result of a client-facing persist. `already_present` reports whether a live
// copy of the artifact (manifest + backing storage) existed before this call,
// evaluated under the per-artifact write lock — so concurrent persists of the
// same key resolve it consistently: exactly one observes `false`. Billing uses
// it to charge only newly-stored bytes; it is deliberately not derived from the
// Applied/IgnoredStale version outcome, because a re-upload with a newer
// version still applies over an already-present artifact.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PersistedArtifact {
    pub manifest: ArtifactManifest,
    pub already_present: bool,
}

impl PersistArtifactOutcome {
    fn apply_outcome(&self) -> ArtifactApplyOutcome {
        match self {
            Self::Applied(_) => ArtifactApplyOutcome::Applied,
            Self::IgnoredStale(_) => ArtifactApplyOutcome::IgnoredStale,
            Self::IgnoredTombstone => ArtifactApplyOutcome::IgnoredTombstone,
        }
    }

    // Converts a client-facing persist outcome into the public result: both
    // Applied and IgnoredStale surface their manifest, while a tombstone
    // rejection is an error (client writes must not be silently dropped).
    fn into_persisted(
        self,
        already_present: bool,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
    ) -> Result<PersistedArtifact, String> {
        match self {
            Self::Applied(manifest) | Self::IgnoredStale(manifest) => Ok(PersistedArtifact {
                manifest,
                already_present,
            }),
            Self::IgnoredTombstone => Err(format!(
                "artifact write for {producer:?}/{namespace_id}/{key} was rejected by a newer tombstone"
            )),
        }
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
        let rocksdb_write_buffer_manager = WriteBufferManager::new_write_buffer_manager_with_cache(
            config.rocksdb_write_buffer_manager_bytes,
            true,
            rocksdb_block_cache.clone(),
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
        let db = DB::open_cf_descriptors(&options, db_path, cfs)
            .map_err(|error| format!("failed to open RocksDB: {error}"))?;
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
            tmp_dir_max_bytes: config.tmp_dir_max_bytes,
            data_dir: config.data_dir.clone(),
            segment_ring_limits,
            rocksdb_block_cache_capacity_bytes: config.rocksdb_block_cache_bytes,
            rocksdb_block_cache,
            rocksdb_write_buffer_manager,
            segment_write_lock: Mutex::new(()),
            segment_fsync_count: Arc::new(AtomicU64::new(0)),
            pending_seq: AtomicU64::new(0),
            durable_seq: AtomicU64::new(0),
            fsync_lock: Mutex::new(()),
            segment_refresh_lock: Mutex::new(()),
            segment_state_lock: Mutex::new(()),
            segment_state_cache: StdMutex::new(Arc::new(SegmentStateSnapshot::default())),
            segment_handles: Mutex::new(SegmentHandleCache::new(config.segment_handle_cache_size)),
            manifest_cache: StdMutex::new(ManifestCache::new(config.manifest_cache_max_bytes)),
            existence_cache: ShardedExistenceCache::new(
                EXISTENCE_CACHE_CAPACITY,
                EXISTENCE_CACHE_TTL,
            ),
            multipart_locks: std::array::from_fn(|_| Mutex::new(())),
            artifact_write_locks: std::array::from_fn(|_| Mutex::new(())),
            promotion_queue: StdMutex::new(PromotionQueue::default()),
            promotion_notify: Notify::new(),
            failpoints: Arc::new(FailpointSet::default()),
        };
        // `load_segment_state_from_db` needs `&self`, so the store must be fully
        // constructed (with a placeholder snapshot) before it can be seeded.
        let segment_state = store.load_segment_state_from_db()?;
        store.replace_segment_state_snapshot(segment_state);
        Ok(store)
    }

    fn multipart_lock_for(&self, upload_id: &str) -> &Mutex<()> {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        std::hash::Hash::hash(upload_id, &mut hasher);
        let index = (std::hash::Hasher::finish(&hasher) as usize) % MULTIPART_LOCK_STRIPES;
        &self.multipart_locks[index]
    }

    fn artifact_write_lock_for(&self, artifact_id: &str) -> &Mutex<()> {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        std::hash::Hash::hash(artifact_id, &mut hasher);
        let index = (std::hash::Hasher::finish(&hasher) as usize) % ARTIFACT_WRITE_LOCK_STRIPES;
        &self.artifact_write_locks[index]
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
                self.maybe_refresh_manifest(manifest).await
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
        source_path: &Path,
        replication_targets: &[String],
    ) -> Result<PersistedArtifact, String> {
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms: now_ms(),
            replication_targets,
        };
        let (outcome, already_present) = self
            .persist_artifact_from_path_with_version(spec, source_path)
            .await?;
        outcome.into_persisted(already_present, producer, namespace_id, key)
    }

    pub async fn apply_replicated_artifact_from_path(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        source_path: &Path,
        version_ms: u64,
    ) -> Result<ArtifactApplyOutcome, String> {
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms,
            replication_targets: &[],
        };
        Ok(self
            .persist_artifact_from_path_with_version(spec, source_path)
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
    ) -> Result<(PersistArtifactOutcome, bool), String> {
        let artifact_id =
            artifact_storage_id(spec.producer, &self.tenant_id, spec.namespace_id, spec.key);
        // Hold the per-artifact write lock across the read-check, segment append,
        // and metadata commit. Without it, concurrent applies of the same key
        // each observe "absent" below, each append a full copy to a segment, and
        // only the last manifest write wins — leaving the rest as orphaned bytes
        // that accumulate to N x on disk (the bootstrap-from-many-peers ENOSPC).
        // Whoever wins the lock commits the manifest; the rest re-read it here and
        // short-circuit to IgnoredStale without appending.
        let _write_guard = self.artifact_write_lock_for(&artifact_id).lock().await;
        let size = self.io.metadata_len(source_path).await?;

        let existing = self.manifest_from_db(&artifact_id)?;
        let already_present = match &existing {
            Some(existing) => self.storage_exists(existing).await?,
            None => false,
        };
        if let Some(existing) = &existing
            && already_present
            && (manifest_version_ms(existing) >= spec.version_ms || spec.version_ms == 0)
        {
            self.note_artifact_exists(&artifact_id);
            self.io.remove_file_if_exists(source_path).await;
            return Ok((
                PersistArtifactOutcome::IgnoredStale(existing.clone()),
                already_present,
            ));
        }
        if self.namespace_tombstone_blocks(spec.namespace_id, spec.version_ms)? {
            self.io.remove_file_if_exists(source_path).await;
            return Ok((PersistArtifactOutcome::IgnoredTombstone, already_present));
        }

        let persisted_version_ms = persisted_version_ms(spec.version_ms);
        let (location, evicted_segments) = self.append_to_segment(source_path, size).await?;

        self.hit_failpoint(FailpointName::AfterArtifactBytesDurableBeforeMetadata)
            .await?;

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
        };
        let metadata = manifest.metadata(&self.tenant_id);

        let mut batch = WriteBatch::default();
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
                    ),
                );
            }
            batch.put_cf(
                self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
                action_cache_index_key(&manifest.namespace_id, manifest.version_ms, action_hash),
                artifact_id.as_bytes(),
            );
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
        self.append_artifact_replication_messages(&mut batch, &manifest, spec.replication_targets)?;

        self.write_batch_sync(batch, "manifest batch")?;
        self.hit_failpoint(FailpointName::AfterMetadataCommitBeforeReturn)
            .await?;
        self.maybe_cache_manifest(manifest.clone());
        self.note_artifact_exists(&artifact_id);

        self.evict_segments(evicted_segments).await?;

        Ok((PersistArtifactOutcome::Applied(manifest), already_present))
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
        let Ok(requested_bytes) = usize::try_from(manifest.size) else {
            return Ok(None);
        };
        let Some(permit) = self.memory.try_acquire_mmap_serving(requested_bytes) else {
            return Ok(None);
        };

        if let Some(segment_id) = &manifest.segment_id {
            let offset = manifest
                .segment_offset
                .ok_or_else(|| "segment-backed manifest is missing segment offset".to_string())?;
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
            // bootstrap silently wedges. Surface a truncated artifact as missing
            // so the serve 404s it; the bootstrap client then skips it
            // (IgnoredStale) and the lost entry re-populates on cache miss.
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
        self.enqueue_promotion(&manifest.artifact_id);
        Ok(Some(manifest))
    }

    /// Queues an artifact served from an Old segment for background promotion
    /// (see [`Store::run_promotion_worker`]). Deduplicated and bounded;
    /// dropping an entry is safe because promotion is a best-effort keep-alive.
    fn enqueue_promotion(&self, artifact_id: &str) {
        {
            let mut queue = self.promotion_queue.lock().expect("promotion queue lock");
            if queue.pending.len() >= MAX_PENDING_PROMOTIONS
                || !queue.pending.insert(artifact_id.to_owned())
            {
                return;
            }
            queue.order.push_back(artifact_id.to_owned());
        }
        self.promotion_notify.notify_one();
    }

    /// Drains the read-path promotion queue, rewriting each artifact from its
    /// Old segment into the current one (the same refresh the serving path
    /// used to run inline). Runs for the life of the process; spawned once at
    /// boot.
    pub async fn run_promotion_worker(&self) {
        loop {
            let next = {
                let mut queue = self.promotion_queue.lock().expect("promotion queue lock");
                match queue.order.pop_front() {
                    Some(artifact_id) => {
                        queue.pending.remove(&artifact_id);
                        Some(artifact_id)
                    }
                    None => None,
                }
            };
            let Some(artifact_id) = next else {
                self.promotion_notify.notified().await;
                continue;
            };
            if let Err(error) = self.promote_artifact(&artifact_id).await {
                self.io.metrics().record_promotion_failure();
                tracing::warn!(artifact_id, error, "segment promotion failed");
            }
        }
    }

    /// Promotes one artifact out of an Old segment, re-validating that the
    /// manifest still exists and still lives in an Old segment (it may have
    /// been promoted by a writer, replaced, or reclaimed since it was queued).
    async fn promote_artifact(&self, artifact_id: &str) -> Result<(), String> {
        let Some(manifest) = self.manifest(artifact_id)? else {
            return Ok(());
        };
        let Some(segment_id) = manifest.segment_id.as_deref() else {
            return Ok(());
        };
        if self.segment_generation(segment_id)? != Some(SegmentGeneration::Old) {
            return Ok(());
        }
        self.maybe_refresh_manifest(manifest).await.map(|_| ())
    }

    async fn maybe_refresh_manifest(
        &self,
        manifest: ArtifactManifest,
    ) -> Result<Option<ArtifactManifest>, String> {
        if !self.memory.allow_segment_refresh() {
            self.io
                .metrics()
                .record_memory_action("segment_refresh_skipped");
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
        let (location, evicted_segments) = self
            .append_reader_to_segment(&mut reader, current.size)
            .await?;
        let mut refreshed = current.clone();
        let previous_segment_id = current_segment_id.to_owned();
        refreshed.inline = false;
        refreshed.blob_path = None;
        refreshed.segment_id = Some(location.segment_id.clone());
        refreshed.segment_offset = Some(location.offset);

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
        self.write_batch_sync(batch, "refreshed manifest")?;
        self.maybe_cache_manifest(refreshed.clone());

        self.io.metrics().record_segment_refresh(
            current.producer,
            "ok",
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
        let artifact_id =
            artifact_storage_id(spec.producer, &self.tenant_id, spec.namespace_id, spec.key);

        let existing = self.manifest_from_db(&artifact_id)?;
        if let Some(existing) = &existing
            && existing.inline
            && self.inline_bytes(&artifact_id)?.is_some()
            && (manifest_version_ms(existing) >= spec.version_ms || spec.version_ms == 0)
        {
            self.note_artifact_exists(&artifact_id);
            return Ok(PersistArtifactOutcome::IgnoredStale(existing.clone()));
        }
        if self.namespace_tombstone_blocks(spec.namespace_id, spec.version_ms)? {
            return Ok(PersistArtifactOutcome::IgnoredTombstone);
        }

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
        };
        let metadata = manifest.metadata(&self.tenant_id);

        let mut batch = WriteBatch::default();
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
                    ),
                );
            }
            batch.put_cf(
                self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
                action_cache_index_key(&manifest.namespace_id, manifest.version_ms, action_hash),
                artifact_id.as_bytes(),
            );
        }
        self.append_artifact_replication_messages(&mut batch, &manifest, spec.replication_targets)?;

        self.write_batch_sync(batch, "keyvalue batch")?;
        self.maybe_cache_manifest(manifest.clone());
        self.note_artifact_exists(&artifact_id);

        self.hit_failpoint(FailpointName::AfterMetadataCommitBeforeReturn)
            .await?;

        Ok(PersistArtifactOutcome::Applied(manifest))
    }

    fn inline_bytes(&self, artifact_id: &str) -> Result<Option<Vec<u8>>, String> {
        self.db
            .get_cf(self.cf(ROCKSDB_CF_KEY_VALUE), artifact_id.as_bytes())
            .map_err(|error| format!("failed to read inline artifact bytes: {error}"))
    }

    async fn append_to_segment(
        &self,
        source_path: &Path,
        size: u64,
    ) -> Result<(SegmentLocation, Vec<SegmentReference>), String> {
        let mut source = self.io.open_file(source_path).await?;
        let result = self.append_reader_to_segment(&mut source, size).await;
        self.io.remove_file_if_exists(source_path).await;
        result
    }

    async fn append_reader_to_segment<R>(
        &self,
        source: &mut R,
        size: u64,
    ) -> Result<(SegmentLocation, Vec<SegmentReference>), String>
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
            let copied = tokio::io::copy(source, &mut destination)
                .await
                .map_err(|error| {
                    format!(
                        "failed to append into segment {}: {error}",
                        segment_path.display()
                    )
                })?;
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
            drop(destination);
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

        self.ensure_segment_durable(durability_seq).await?;

        Ok((location, evicted_segments))
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
            self.evict_segment(&segment.segment_id).await?;
        }
        Ok(())
    }

    async fn evict_segment(&self, segment_id: &str) -> Result<(), String> {
        let prefix = segment_artifact_index_prefix(segment_id);
        let mut batch = WriteBatch::default();
        let mut saw_entries = false;
        let mut removed_artifacts = BTreeMap::<ArtifactProducer, u64>::new();
        let mut removed_artifact_ids = Vec::new();
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS),
            IteratorMode::From(prefix.as_bytes(), rocksdb::Direction::Forward),
        );

        for item in iter {
            let (index_key, _) =
                item.map_err(|error| format!("failed to iterate segment index: {error}"))?;
            if !index_key.starts_with(prefix.as_bytes()) {
                break;
            }
            saw_entries = true;
            let artifact_id = std::str::from_utf8(&index_key[prefix.len()..])
                .map_err(|error| format!("invalid segment index key: {error}"))?
                .to_owned();

            match self.manifest_from_db(&artifact_id)? {
                Some(manifest) if manifest.segment_id.as_deref() == Some(segment_id) => {
                    batch.delete_cf(self.cf(ROCKSDB_CF_MANIFESTS), artifact_id.as_bytes());
                    batch.delete_cf(
                        self.cf(ROCKSDB_CF_NAMESPACE_ARTIFACTS),
                        namespace_artifact_index_key(&manifest.namespace_id, &artifact_id)
                            .as_bytes(),
                    );
                    batch.delete_cf(self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS), &index_key);
                    *removed_artifacts.entry(manifest.producer).or_default() += 1;
                    removed_artifact_ids.push(artifact_id);
                }
                Some(_) | None => {
                    batch.delete_cf(self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS), &index_key);
                }
            }
        }

        if saw_entries {
            self.db
                .write(batch)
                .map_err(|error| format!("failed to evict segment metadata: {error}"))?;
            self.remove_manifest_cache_keys(&removed_artifact_ids);
        }
        self.remove_segment_handle(segment_id).await;
        self.io
            .remove_file_if_exists(&self.segment_path(segment_id))
            .await;
        self.mutate_segment_state(|state| state.remove_segment(segment_id))
            .await?;
        for (producer, artifacts) in removed_artifacts {
            self.io
                .metrics()
                .record_segment_eviction(producer, "ok", artifacts);
        }

        Ok(())
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
        };
        match self
            .persist_inline_artifact_with_version(spec, bytes)
            .await?
        {
            PersistArtifactOutcome::Applied(manifest)
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
    pub async fn persist_inline_artifact_from_bytes_damped_and_enqueue(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        bytes: &[u8],
        replication_targets: &[String],
    ) -> Result<(ArtifactManifest, bool), String> {
        let artifact_id = artifact_storage_id(producer, &self.tenant_id, namespace_id, key);
        if let Some(existing) = self.manifest_from_db(&artifact_id)?
            && existing.inline
            && manifest_version_ms(&existing).saturating_add(REAPI_ACTION_CACHE_REFRESH_DAMPING_MS)
                > now_ms()
            && self.inline_bytes(&artifact_id)?.as_deref() == Some(bytes)
        {
            return Ok((existing, false));
        }
        self.persist_inline_artifact_from_bytes_and_enqueue(
            producer,
            namespace_id,
            key,
            content_type,
            bytes,
            replication_targets,
        )
        .await
        .map(|manifest| (manifest, true))
    }

    pub async fn persist_inline_artifact_from_bytes_and_enqueue(
        &self,
        producer: ArtifactProducer,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        bytes: &[u8],
        replication_targets: &[String],
    ) -> Result<ArtifactManifest, String> {
        let spec = PersistArtifactSpec {
            producer,
            namespace_id,
            key,
            content_type,
            version_ms: now_ms(),
            replication_targets,
        };
        match self
            .persist_inline_artifact_with_version(spec, bytes)
            .await?
        {
            PersistArtifactOutcome::Applied(manifest)
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
        };
        Ok(self
            .persist_artifact_from_bytes_with_version(spec, bytes)
            .await?
            .0
            .apply_outcome())
    }

    pub async fn apply_replicated_inline_artifact_from_bytes(
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
        };
        Ok(self
            .persist_inline_artifact_with_version(spec, bytes)
            .await?
            .apply_outcome())
    }

    async fn persist_artifact_from_bytes_with_version(
        &self,
        spec: PersistArtifactSpec<'_>,
        bytes: &[u8],
    ) -> Result<(PersistArtifactOutcome, bool), String> {
        let temp_path = temp_file_path(&self.tmp_dir.join("uploads"), "replication");
        self.io.write(&temp_path, bytes).await?;
        self.persist_artifact_from_path_with_version(spec, &temp_path)
            .await
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
        if !delete_everything
            && let Some(current_tombstone) = self.namespace_tombstone_version(namespace_id)?
            && current_tombstone >= version_ms
        {
            return Ok(NamespaceDeleteOutcome::IgnoredOlder);
        }
        if !delete_everything {
            batch.put_cf(
                self.cf(ROCKSDB_CF_NAMESPACE_TOMBSTONES),
                namespace_id.as_bytes(),
                version_ms.to_le_bytes(),
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
                        action_cache_index_key(namespace_id, manifest.version_ms, action_hash),
                    );
                }
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

        if !delete_everything {
            self.append_namespace_delete_messages(
                &mut batch,
                namespace_id,
                version_ms,
                replication_targets,
            )?;
        }

        self.write_batch_sync(batch, "delete namespace batch")?;
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
        self.db
            .put_cf(
                self.cf(ROCKSDB_CF_MULTIPART_UPLOADS),
                upload_id.as_bytes(),
                upload_bytes,
            )
            .map_err(|error| format!("failed to store multipart upload: {error}"))?;

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

    pub fn multipart_uploads_older_than(&self, cutoff_ms: u64) -> Result<Vec<String>, String> {
        let iter = self
            .db
            .iterator_cf(self.cf(ROCKSDB_CF_MULTIPART_UPLOADS), IteratorMode::Start);
        let mut stale = Vec::new();
        for item in iter {
            let (key, value) =
                item.map_err(|error| format!("failed to iterate multipart uploads: {error}"))?;
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
                    continue;
                }
            };
            if upload.created_at_ms < cutoff_ms {
                stale.push(upload_id);
            }
        }
        Ok(stale)
    }

    pub async fn add_multipart_part(
        &self,
        upload_id: &str,
        part_number: u32,
        part_path: &Path,
        size: u64,
    ) -> Result<(), MultipartError> {
        let _guard = self.multipart_lock_for(upload_id).lock().await;
        let mut upload = self
            .multipart_upload(upload_id)
            .map_err(MultipartError::Other)?
            .ok_or(MultipartError::NotFound)?;

        let next_total = next_total_size(&upload.parts, part_number, size);
        validate_total_size(next_total, MAX_MODULE_TOTAL_BYTES)?;

        let upload_dir = self.data_dir.join("multipart").join(upload_id);
        self.io.create_dir_all(&upload_dir).await.map_err(|error| {
            MultipartError::Other(format!("failed to create multipart dir: {error}"))
        })?;
        let final_path = upload_dir.join(part_number.to_string());

        if let Err(rename_error) = self.io.rename(part_path, &final_path).await {
            self.io.copy(part_path, &final_path).await.map_err(|error| {
                MultipartError::Other(format!(
                    "failed to store multipart part after rename error ({rename_error}): {error}"
                ))
            })?;
            self.io.remove_file_if_exists(part_path).await;
        }

        upload.parts.insert(
            part_number,
            MultipartPart {
                path: final_path.to_string_lossy().into_owned(),
                size,
            },
        );

        let upload_bytes = serde_json::to_vec(&upload).map_err(|error| {
            MultipartError::Other(format!("failed to encode multipart upload: {error}"))
        })?;
        self.db
            .put_cf(
                self.cf(ROCKSDB_CF_MULTIPART_UPLOADS),
                upload_id.as_bytes(),
                upload_bytes,
            )
            .map_err(|error| {
                MultipartError::Other(format!("failed to update multipart upload: {error}"))
            })?;

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
        ensure_tmp_dir_capacity(&self.tmp_dir, upload_size, self.tmp_dir_max_bytes)
            .await
            .map_err(MultipartError::Other)?;

        let assembled_path = temp_file_path(&self.tmp_dir.join("uploads"), "module");
        let mut assembled = self
            .io
            .create_file(&assembled_path)
            .await
            .map_err(MultipartError::Other)?;

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
            let copied = tokio::io::copy(&mut part_file, &mut assembled)
                .await
                .map_err(|error| {
                    MultipartError::Other(format!("failed to assemble multipart artifact: {error}"))
                })?;
            if copied != part.size {
                return Err(MultipartError::Other(format!(
                    "multipart part {part_number} expected {} bytes but copied {copied}",
                    part.size
                )));
            }
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
                &assembled_path,
                replication_targets,
            )
            .await
            .map_err(MultipartError::Other)?
            .manifest;

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
        if let Some(upload) = self.multipart_upload(upload_id)? {
            self.io
                .remove_dir_all_if_exists(&self.data_dir.join("multipart").join(upload_id))
                .await;
            self.db
                .delete_cf(self.cf(ROCKSDB_CF_MULTIPART_UPLOADS), upload_id.as_bytes())
                .map_err(|error| format!("failed to delete multipart upload: {error}"))?;

            for part in upload.parts.values() {
                self.io.remove_file_if_exists(Path::new(&part.path)).await;
            }
        }

        Ok(())
    }

    #[cfg(test)]
    pub fn enqueue(&self, message: OutboxMessage) -> Result<(), String> {
        let key = outbox_message_key(&message);
        let value = serde_json::to_vec(&message)
            .map_err(|error| format!("failed to encode outbox message: {error}"))?;
        let mut batch = WriteBatch::default();
        batch.put_cf(self.cf(ROCKSDB_CF_OUTBOX), key.as_bytes(), value);
        self.write_batch_sync(batch, "outbox message")
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
        self.count_cf_entries(ROCKSDB_CF_OUTBOX)
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
        let multipart_uploads = self.count_cf_entries(ROCKSDB_CF_MULTIPART_UPLOADS)?;
        let promotion_queue_depth = self
            .promotion_queue
            .lock()
            .expect("promotion queue lock")
            .order
            .len();
        let segment_state = self.segment_state_snapshot();
        let segment_counts = vec![
            ("old", segment_state.state.old.len()),
            ("current", segment_state.state.current.len()),
            ("new", segment_state.state.new.len()),
        ];
        Ok(StoreSnapshot {
            outbox_messages,
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
    /// their own, and an entry re-copied by a later bootstrap just expires
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
            if manifest.producer == ArtifactProducer::Reapi
                && let Some(action_hash) = action_cache_manifest_hash(&manifest.key)
            {
                batch.delete_cf(
                    self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
                    action_cache_index_key(
                        &manifest.namespace_id,
                        manifest.version_ms,
                        action_hash,
                    ),
                );
            }
            if let Some(segment_id) = &manifest.segment_id {
                batch.delete_cf(
                    self.cf(ROCKSDB_CF_SEGMENT_ARTIFACTS),
                    segment_artifact_index_key(segment_id, &manifest.artifact_id).as_bytes(),
                );
            }
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
            let page = self.manifests_page_scoped(after.as_deref(), None, SCAN_PAGE)?;
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
    pub fn action_cache_manifests(
        &self,
        namespace_id: &str,
        max_entries: usize,
    ) -> Result<Vec<ArtifactManifest>, String> {
        if !self.action_cache_index_backfilled(namespace_id)? {
            return self.backfill_action_cache_index(namespace_id, max_entries);
        }
        let prefix = action_cache_index_prefix(namespace_id);
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX),
            IteratorMode::From(&prefix, rocksdb::Direction::Forward),
        );
        let mut manifests = Vec::new();
        // Rows whose manifest is gone or has moved to a different version:
        // overwrites and deletes clean up their own rows, but a row written by
        // a crashed batch or a pre-fix overwrite can linger — drop it here so
        // the index converges instead of paying the dead point-read forever.
        let mut stale_rows: Vec<Vec<u8>> = Vec::new();
        for item in iter {
            let (index_key, artifact_id) =
                item.map_err(|error| format!("failed to iterate action-cache index: {error}"))?;
            if !index_key.starts_with(&prefix) {
                break;
            }
            if manifests.len() >= max_entries {
                break;
            }
            let row_version = index_key
                .get(prefix.len()..prefix.len() + 8)
                .and_then(|bytes| <[u8; 8]>::try_from(bytes).ok())
                .map(|bytes| !u64::from_be_bytes(bytes));
            let artifact_id = std::str::from_utf8(&artifact_id)
                .map_err(|error| format!("invalid action-cache index value: {error}"))?;
            match self.manifest_from_db(artifact_id)? {
                Some(manifest)
                    if manifest.producer == ArtifactProducer::Reapi
                        && manifest.key.starts_with("action_cache/")
                        && row_version == Some(manifest.version_ms) =>
                {
                    manifests.push(manifest);
                }
                _ => stale_rows.push(index_key.to_vec()),
            }
        }
        if !stale_rows.is_empty() {
            let mut batch = WriteBatch::default();
            for row in &stale_rows {
                batch.delete_cf(self.cf(ROCKSDB_CF_ACTION_CACHE_INDEX), row);
            }
            self.write_batch_sync(batch, "action-cache index stale rows")?;
        }
        Ok(manifests)
    }

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
    /// writing an index row for EVERY action-cache manifest it encounters
    /// (the index must be complete for later capped scans to be correct),
    /// then the backfill marker — all in one batch, so a crash mid-scan
    /// leaves the marker unset and the next call redoes the work. Returns
    /// the newest `max_entries` like the indexed path. Only the snapshot
    /// reconcile calls this, from its background build task, so the
    /// scan's cost no longer sits on any request path.
    fn backfill_action_cache_index(
        &self,
        namespace_id: &str,
        max_entries: usize,
    ) -> Result<Vec<ArtifactManifest>, String> {
        let started = std::time::Instant::now();
        let prefix = format!("{namespace_id}\0");
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_NAMESPACE_ARTIFACTS),
            IteratorMode::From(prefix.as_bytes(), rocksdb::Direction::Forward),
        );
        let mut batch = WriteBatch::default();
        let mut rows = 0_usize;
        let mut manifests = Vec::new();
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
                action_cache_index_key(namespace_id, manifest.version_ms, action_hash),
                manifest.artifact_id.as_bytes(),
            );
            rows += 1;
            manifests.push(manifest);
            // Keep the working set bounded while scanning: shed the
            // oldest half whenever the buffer doubles the cap.
            if manifests.len() >= max_entries.saturating_mul(2).max(2) {
                manifests.sort_unstable_by(|a, b| b.version_ms.cmp(&a.version_ms));
                manifests.truncate(max_entries);
            }
        }
        batch.put_cf(
            self.cf(ROCKSDB_CF_KEY_VALUE),
            Self::action_cache_index_marker_key(namespace_id).as_bytes(),
            [],
        );
        self.write_batch_sync(batch, "action-cache index backfill")?;
        if manifests.len() > max_entries {
            manifests.sort_unstable_by(|a, b| b.version_ms.cmp(&a.version_ms));
            manifests.truncate(max_entries);
        }
        tracing::info!(
            namespace_id,
            rows,
            elapsed_ms = started.elapsed().as_millis() as u64,
            "action-cache index backfilled"
        );
        Ok(manifests)
    }

    /// Walk the manifest keyspace, optionally restricted to an `artifact_id`
    /// prefix. When `prefix` is set the walk starts at the prefix's lower bound
    /// (unless a later `after` cursor is supplied) and stops as soon as it
    /// leaves the prefix, so callers can enumerate a single digest bucket's
    /// range without scanning the rest of the keyspace.
    pub fn manifests_page_scoped(
        &self,
        after: Option<&str>,
        prefix: Option<&str>,
        limit: usize,
    ) -> Result<ManifestPage, String> {
        let mut manifests = Vec::new();
        let mut next_after = None;
        let start_key = after.or(prefix).unwrap_or_default();
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
            if let Some(prefix) = prefix
                && !artifact_id.starts_with(prefix)
            {
                break;
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

    /// Summarize the manifest keyspace as per-prefix-bucket digests for
    /// range-based anti-entropy during bootstrap. Buckets partition the sorted
    /// `artifact_id` space by their first `prefix_len` hex characters; each
    /// bucket folds the ordered `(artifact_id, version_ms)` pairs it contains
    /// into a hash so that adds, removes, and version bumps all flip the bucket.
    /// One ordered scan builds every non-empty bucket; empty buckets are
    /// omitted (a bucket present on only one side simply mismatches).
    pub fn manifests_digest(&self, prefix_len: usize) -> Result<Vec<ManifestBucketDigest>, String> {
        let iter = self
            .db
            .iterator_cf(self.cf(ROCKSDB_CF_MANIFESTS), IteratorMode::Start);

        let mut buckets = Vec::new();
        let mut current: Option<(String, u64, Sha256)> = None;

        for item in iter {
            let (artifact_id, payload) =
                item.map_err(|error| format!("failed to iterate manifests: {error}"))?;
            let artifact_id = std::str::from_utf8(&artifact_id)
                .map_err(|error| format!("invalid manifest key: {error}"))?;
            let prefix: String = artifact_id.chars().take(prefix_len).collect();
            let manifest = decode_manifest_record(artifact_id, &payload)?;

            match current.as_mut() {
                Some((bucket_prefix, count, hasher)) if *bucket_prefix == prefix => {
                    hasher.update(artifact_id.as_bytes());
                    hasher.update(manifest.version_ms.to_le_bytes());
                    *count += 1;
                }
                _ => {
                    if let Some((bucket_prefix, count, hasher)) = current.take() {
                        buckets.push(ManifestBucketDigest {
                            prefix: bucket_prefix,
                            count,
                            hash: hex::encode(hasher.finalize()),
                        });
                    }
                    let mut hasher = Sha256::new();
                    hasher.update(artifact_id.as_bytes());
                    hasher.update(manifest.version_ms.to_le_bytes());
                    current = Some((prefix, 1, hasher));
                }
            }
        }

        if let Some((bucket_prefix, count, hasher)) = current.take() {
            buckets.push(ManifestBucketDigest {
                prefix: bucket_prefix,
                count,
                hash: hex::encode(hasher.finalize()),
            });
        }

        Ok(buckets)
    }

    pub fn namespace_tombstones_page(
        &self,
        after: Option<&str>,
        limit: usize,
    ) -> Result<NamespaceTombstonePage, String> {
        let mut tombstones = Vec::new();
        let mut next_after = None;
        let start_key = after.unwrap_or_default();
        let iter = self.db.iterator_cf(
            self.cf(ROCKSDB_CF_NAMESPACE_TOMBSTONES),
            IteratorMode::From(start_key.as_bytes(), rocksdb::Direction::Forward),
        );

        for item in iter {
            let (namespace_id, payload) =
                item.map_err(|error| format!("failed to iterate namespace tombstones: {error}"))?;
            let namespace_id = std::str::from_utf8(&namespace_id)
                .map_err(|error| format!("invalid namespace tombstone key: {error}"))?;
            if after == Some(namespace_id) {
                continue;
            }
            if tombstones.len() == limit {
                next_after = tombstones
                    .last()
                    .map(|record: &NamespaceTombstoneRecord| record.namespace_id.clone());
                break;
            }
            if payload.len() != 8 {
                return Err(format!(
                    "namespace tombstone for {namespace_id} should be 8 bytes, got {}",
                    payload.len()
                ));
            }
            let mut slice = [0_u8; 8];
            slice.copy_from_slice(payload.as_ref());
            tombstones.push(NamespaceTombstoneRecord {
                namespace_id: namespace_id.to_owned(),
                version_ms: u64::from_le_bytes(slice),
            });
        }

        Ok(NamespaceTombstonePage {
            tombstones,
            next_after,
        })
    }

    pub fn delete_outbox_message(&self, key: &[u8]) -> Result<(), String> {
        self.db
            .delete_cf(self.cf(ROCKSDB_CF_OUTBOX), key)
            .map_err(|error| format!("failed to delete outbox entry: {error}"))
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
                if manifest_version_ms(&manifest) < version_ms {
                    ArtifactApplyOutcome::Applied
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

    fn append_artifact_replication_messages(
        &self,
        batch: &mut WriteBatch,
        manifest: &ArtifactManifest,
        replication_targets: &[String],
    ) -> Result<(), String> {
        for target in replication_targets {
            self.append_outbox_message(
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
                    },
                },
            )?;
        }
        Ok(())
    }

    fn append_namespace_delete_messages(
        &self,
        batch: &mut WriteBatch,
        namespace_id: &str,
        version_ms: u64,
        replication_targets: &[String],
    ) -> Result<(), String> {
        for target in replication_targets {
            self.append_outbox_message(
                batch,
                OutboxMessage {
                    target: target.clone(),
                    operation: ReplicationOperation::DeleteNamespace {
                        namespace_id: namespace_id.to_owned(),
                        version_ms,
                    },
                },
            )?;
        }
        Ok(())
    }

    fn append_outbox_message(
        &self,
        batch: &mut WriteBatch,
        message: OutboxMessage,
    ) -> Result<(), String> {
        let key = outbox_message_key(&message);
        let value = serde_json::to_vec(&message)
            .map_err(|error| format!("failed to encode outbox message: {error}"))?;
        batch.put_cf(self.cf(ROCKSDB_CF_OUTBOX), key.as_bytes(), value);
        Ok(())
    }

    fn write_batch_sync(&self, batch: WriteBatch, label: &str) -> Result<(), String> {
        let mut write_options = WriteOptions::default();
        write_options.set_sync(true);
        self.db
            .write_opt(batch, &write_options)
            .map_err(|error| format!("failed to write {label}: {error}"))
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
    manifest.artifact_id.len()
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

    fn total_segments(&self) -> usize {
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

fn manifest_version_ms(manifest: &ArtifactManifest) -> u64 {
    if manifest.version_ms == 0 {
        manifest.created_at_ms
    } else {
        manifest.version_ms
    }
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

fn outbox_message_key(message: &OutboxMessage) -> String {
    let lane = if message.operation.is_bulk() {
        "1"
    } else {
        "0"
    };
    format!("{lane}-{:020}-{}", now_ms(), Uuid::now_v7())
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
mod tests;
