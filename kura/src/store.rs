use std::{
    collections::{BTreeMap, HashMap},
    path::{Path, PathBuf},
    pin::Pin,
    sync::{Arc, Mutex as StdMutex},
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
    io::{AsyncRead, AsyncWriteExt, ReadBuf},
    sync::Mutex,
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
        DESIRED_CURRENT_SEGMENTS, DESIRED_NEW_SEGMENTS, DESIRED_OLD_SEGMENTS,
        MAX_MODULE_TOTAL_BYTES, MAX_SEGMENT_BYTES, ROCKSDB_BYTES_PER_SYNC, ROCKSDB_CF_KEY_VALUE,
        ROCKSDB_CF_MANIFESTS, ROCKSDB_CF_MULTIPART_UPLOADS, ROCKSDB_CF_NAMESPACE_ARTIFACTS,
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
        artifact_storage_id, module_key, namespace_artifact_index_key, now_ms,
        segment_artifact_index_key, segment_artifact_index_prefix, segment_path, temp_file_path,
    },
};

const MULTIPART_LOCK_STRIPES: usize = 64;
pub const EXISTENCE_CACHE_CAPACITY: usize = 65_536;
const EXISTENCE_CACHE_TTL: Duration = Duration::from_secs(30);

pub struct Store {
    db: DB,
    io: IoController,
    memory: MemoryController,
    tenant_id: String,
    tmp_dir: PathBuf,
    data_dir: PathBuf,
    rocksdb_block_cache_capacity_bytes: usize,
    rocksdb_block_cache: Cache,
    rocksdb_write_buffer_manager: WriteBufferManager,
    segment_write_lock: Mutex<()>,
    segment_refresh_lock: Mutex<()>,
    segment_handles: Mutex<SegmentHandleCache>,
    manifest_cache: StdMutex<ManifestCache>,
    existence_cache: StdMutex<ExistenceCache>,
    multipart_locks: [Mutex<()>; MULTIPART_LOCK_STRIPES],
    failpoints: Arc<FailpointSet>,
}

pub struct StoreSnapshot {
    pub outbox_messages: usize,
    pub multipart_uploads: usize,
    pub segment_counts: Vec<(&'static str, usize)>,
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

impl PersistArtifactOutcome {
    fn apply_outcome(&self) -> ArtifactApplyOutcome {
        match self {
            Self::Applied(_) => ArtifactApplyOutcome::Applied,
            Self::IgnoredStale(_) => ArtifactApplyOutcome::IgnoredStale,
            Self::IgnoredTombstone => ArtifactApplyOutcome::IgnoredTombstone,
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

        Ok(Self {
            db,
            io,
            memory,
            tenant_id: config.tenant_id.clone(),
            tmp_dir: config.tmp_dir.clone(),
            data_dir: config.data_dir.clone(),
            rocksdb_block_cache_capacity_bytes: config.rocksdb_block_cache_bytes,
            rocksdb_block_cache,
            rocksdb_write_buffer_manager,
            segment_write_lock: Mutex::new(()),
            segment_refresh_lock: Mutex::new(()),
            segment_handles: Mutex::new(SegmentHandleCache::new(config.segment_handle_cache_size)),
            manifest_cache: StdMutex::new(ManifestCache::new(config.manifest_cache_max_bytes)),
            existence_cache: StdMutex::new(ExistenceCache::new(
                EXISTENCE_CACHE_CAPACITY,
                EXISTENCE_CACHE_TTL,
            )),
            multipart_locks: std::array::from_fn(|_| Mutex::new(())),
            failpoints: Arc::new(FailpointSet::default()),
        })
    }

    fn multipart_lock_for(&self, upload_id: &str) -> &Mutex<()> {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        std::hash::Hash::hash(upload_id, &mut hasher);
        let index = (std::hash::Hasher::finish(&hasher) as usize) % MULTIPART_LOCK_STRIPES;
        &self.multipart_locks[index]
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
            .persist_artifact_from_path_with_version(spec, source_path)
            .await?
        {
            PersistArtifactOutcome::Applied(manifest)
            | PersistArtifactOutcome::IgnoredStale(manifest) => Ok(manifest),
            PersistArtifactOutcome::IgnoredTombstone => Err(format!(
                "artifact write for {producer:?}/{namespace_id}/{key} was rejected by a newer tombstone"
            )),
        }
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
            .apply_outcome())
    }

    async fn persist_artifact_from_path_with_version(
        &self,
        spec: PersistArtifactSpec<'_>,
        source_path: &Path,
    ) -> Result<PersistArtifactOutcome, String> {
        let artifact_id =
            artifact_storage_id(spec.producer, &self.tenant_id, spec.namespace_id, spec.key);
        let size = self.io.metadata_len(source_path).await?;

        let existing = self.manifest_from_db(&artifact_id)?;
        if let Some(existing) = &existing
            && self.storage_exists(existing).await?
            && (manifest_version_ms(existing) >= spec.version_ms || spec.version_ms == 0)
        {
            self.note_artifact_exists(&artifact_id);
            self.io.remove_file_if_exists(source_path).await;
            return Ok(PersistArtifactOutcome::IgnoredStale(existing.clone()));
        }
        if self.namespace_tombstone_blocks(spec.namespace_id, spec.version_ms)? {
            self.io.remove_file_if_exists(source_path).await;
            return Ok(PersistArtifactOutcome::IgnoredTombstone);
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

        Ok(PersistArtifactOutcome::Applied(manifest))
    }

    pub async fn open_artifact_reader(
        &self,
        manifest: &ArtifactManifest,
    ) -> Result<ArtifactReader, String> {
        self.open_manifest_reader_with_range(manifest, 0, None)
            .await
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
            let Some(bytes) = map_file_region(handle.as_std(), offset, manifest.size, permit)?
            else {
                return Ok(None);
            };
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(Some(bytes));
        }

        if let Some(blob_path) = &manifest.blob_path {
            let handle = self.blob_handle(blob_path).await?;
            let Some(bytes) = map_file_region(handle.as_std(), 0, manifest.size, permit)? else {
                return Ok(None);
            };
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(Some(bytes));
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

    pub async fn open_artifact_reader_range(
        &self,
        manifest: &ArtifactManifest,
        read_offset: u64,
        read_limit: Option<u64>,
    ) -> Result<ArtifactReader, String> {
        self.open_manifest_reader_with_range(manifest, read_offset, read_limit)
            .await
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
            self.note_artifact_exists(&manifest.artifact_id);
            return Ok(ArtifactReader::FileRange(SegmentReader::new(
                handle,
                offset + read_offset,
                limit,
            )));
        }

        if let Some(blob_path) = &manifest.blob_path {
            let handle = self.blob_handle(blob_path).await?;
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
        self.maybe_refresh_manifest(manifest).await
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
        destination.sync_data().await.map_err(|error| {
            format!("failed to sync segment {}: {error}", segment_path.display())
        })?;
        drop(destination);
        if !segment_already_exists {
            self.io.sync_directory(segment_dir).await?;
        }

        Ok((
            SegmentLocation {
                segment_id: segment.segment_id,
                offset,
            },
            evicted_segments,
        ))
    }

    async fn active_segment(
        &self,
        incoming_size: u64,
    ) -> Result<(SegmentReference, Vec<SegmentReference>), String> {
        let mut state = self.load_segment_state()?;
        let needs_new_segment = match state.active() {
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
            let required_bytes = MAX_SEGMENT_BYTES.saturating_mul(SEGMENT_FREE_SPACE_MARGIN);
            if let Some(available) = available_disk_bytes(&self.data_dir)
                && available < required_bytes
            {
                return Err(format!(
                    "{DISK_FULL_MARKER}: insufficient free space for segment rotation: \
                    {available} bytes available, {required_bytes} required"
                ));
            }
            let segment = SegmentReference::new(Uuid::now_v7().to_string(), now_ms());
            let evicted_segments = state.push_new(
                segment.clone(),
                DESIRED_OLD_SEGMENTS,
                DESIRED_CURRENT_SEGMENTS,
                DESIRED_NEW_SEGMENTS,
            );
            self.save_segment_state(&state)?;
            Ok((segment, evicted_segments))
        } else {
            Ok((
                state
                    .active()
                    .cloned()
                    .expect("current segment should exist when not rotating"),
                Vec::new(),
            ))
        }
    }

    fn load_segment_state(&self) -> Result<SegmentState, String> {
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

    fn save_segment_state(&self, state: &SegmentState) -> Result<(), String> {
        let bytes = serde_json::to_vec(state)
            .map_err(|error| format!("failed to encode segment state: {error}"))?;
        self.db
            .put_cf(self.cf(ROCKSDB_CF_SEGMENT_STATE), b"shared", bytes)
            .map_err(|error| format!("failed to persist segment state: {error}"))
    }

    fn segment_generation(&self, segment_id: &str) -> Result<Option<SegmentGeneration>, String> {
        Ok(self.load_segment_state()?.generation_of(segment_id))
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
        let mut state = self.load_segment_state()?;
        if state.remove_segment(segment_id) {
            self.save_segment_state(&state)?;
        }
        for (producer, artifacts) in removed_artifacts {
            self.io
                .metrics()
                .record_segment_eviction(producer, "ok", artifacts);
        }

        Ok(())
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
        match self
            .persist_artifact_from_bytes_with_version(spec, bytes)
            .await?
        {
            PersistArtifactOutcome::Applied(manifest)
            | PersistArtifactOutcome::IgnoredStale(manifest) => Ok(manifest),
            PersistArtifactOutcome::IgnoredTombstone => Err(format!(
                "artifact write for {producer:?}/{namespace_id}/{key} was rejected by a newer tombstone"
            )),
        }
    }

    pub async fn persist_artifact_from_bytes_and_enqueue(
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
            .persist_artifact_from_bytes_with_version(spec, bytes)
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
    ) -> Result<PersistArtifactOutcome, String> {
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
            .map_err(MultipartError::Other)?;

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
        let key = format!("{:020}-{}", now_ms(), Uuid::now_v7());
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
        let state = self.load_segment_state()?;
        let segment_counts = vec![
            ("old", state.old.len()),
            ("current", state.current.len()),
            ("new", state.new.len()),
        ];
        Ok(StoreSnapshot {
            outbox_messages,
            multipart_uploads,
            segment_counts,
            rocksdb_block_cache_usage_bytes: self.rocksdb_block_cache.get_usage() as u64,
            rocksdb_block_cache_pinned_usage_bytes: self.rocksdb_block_cache.get_pinned_usage()
                as u64,
            rocksdb_block_cache_capacity_bytes: self.rocksdb_block_cache_capacity_bytes as u64,
            rocksdb_write_buffer_usage_bytes: self.rocksdb_write_buffer_manager.get_usage() as u64,
            rocksdb_write_buffer_capacity_bytes: self.rocksdb_write_buffer_manager.get_buffer_size()
                as u64,
        })
    }

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
        let key = format!("{:020}-{}", now_ms(), Uuid::now_v7());
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
        let mut cache = self
            .existence_cache
            .lock()
            .expect("existence cache lock poisoned");
        cache.trim_to(target_entries)
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

        let mut existence_cache = self
            .existence_cache
            .lock()
            .expect("existence cache lock poisoned");
        existence_cache.remove_many(artifact_ids);
    }

    fn record_manifest_cache_state(&self, cache: &ManifestCache) {
        self.io.metrics().update_manifest_index_entries(cache.len());
        self.io
            .metrics()
            .update_manifest_cache_bytes(cache.total_bytes());
    }

    fn existence_cache_contains(&self, artifact_id: &str) -> bool {
        let mut cache = self
            .existence_cache
            .lock()
            .expect("existence cache lock poisoned");
        cache.contains(artifact_id)
    }

    fn note_artifact_exists(&self, artifact_id: &str) {
        let mut cache = self
            .existence_cache
            .lock()
            .expect("existence cache lock poisoned");
        cache.insert(artifact_id.to_owned());
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

struct ManifestCache {
    entries: HashMap<String, CachedManifest>,
    total_bytes: usize,
    next_access_order: u64,
    max_bytes: usize,
}

struct ExistenceCache {
    entries: HashMap<String, CachedExistence>,
    next_access_order: u64,
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
            next_access_order: 0,
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
        let access_order = self.next_access_order();
        self.entries.get_mut(artifact_id).map(|cached| {
            cached.access_order = access_order;
            cached.manifest.clone()
        })
    }

    fn insert(&mut self, manifest: ArtifactManifest) -> ManifestCacheInsertResult {
        let artifact_id = manifest.artifact_id.clone();
        let size_bytes = estimated_manifest_bytes(&manifest);
        if size_bytes > self.max_bytes {
            if let Some(removed) = self.entries.remove(&artifact_id) {
                self.total_bytes = self.total_bytes.saturating_sub(removed.size_bytes);
            }
            return ManifestCacheInsertResult::Oversized;
        }

        let existed = self.entries.remove(&artifact_id);
        if let Some(removed) = &existed {
            self.total_bytes = self.total_bytes.saturating_sub(removed.size_bytes);
        }
        let access_order = self.next_access_order();
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
            }
        }
    }

    fn trim_to(&mut self, target_bytes: usize) -> usize {
        let mut evicted = 0_usize;
        while self.total_bytes > target_bytes {
            let Some(oldest_key) = self
                .entries
                .iter()
                .min_by_key(|(_, cached)| cached.access_order)
                .map(|(artifact_id, _)| artifact_id.clone())
            else {
                break;
            };
            if let Some(removed) = self.entries.remove(&oldest_key) {
                self.total_bytes = self.total_bytes.saturating_sub(removed.size_bytes);
                evicted += 1;
            }
        }
        evicted
    }

    fn next_access_order(&mut self) -> u64 {
        self.next_access_order = self.next_access_order.wrapping_add(1);
        self.next_access_order
    }
}

impl ExistenceCache {
    fn new(capacity: usize, ttl: Duration) -> Self {
        Self {
            entries: HashMap::new(),
            next_access_order: 0,
            capacity,
            ttl,
        }
    }

    fn contains(&mut self, artifact_id: &str) -> bool {
        let now = Instant::now();
        if self
            .entries
            .get(artifact_id)
            .is_some_and(|entry| now.duration_since(entry.inserted_at) > self.ttl)
        {
            self.entries.remove(artifact_id);
            return false;
        }
        let access_order = self.next_access_order();
        self.entries
            .get_mut(artifact_id)
            .map(|entry| {
                entry.access_order = access_order;
            })
            .is_some()
    }

    fn insert(&mut self, artifact_id: String) {
        let access_order = self.next_access_order();
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
            self.entries.remove(artifact_id);
        }
    }

    fn trim_to(&mut self, target_entries: usize) -> usize {
        let mut evicted = 0_usize;
        while self.entries.len() > target_entries {
            let Some(oldest_key) = self
                .entries
                .iter()
                .min_by_key(|(_, entry)| entry.access_order)
                .map(|(artifact_id, _)| artifact_id.clone())
            else {
                break;
            };
            self.entries.remove(&oldest_key);
            evicted += 1;
        }
        evicted
    }

    fn evict_over_capacity(&mut self) {
        while self.entries.len() > self.capacity {
            let Some(oldest_key) = self
                .entries
                .iter()
                .min_by_key(|(_, entry)| entry.access_order)
                .map(|(artifact_id, _)| artifact_id.clone())
            else {
                break;
            };
            self.entries.remove(&oldest_key);
        }
    }

    fn next_access_order(&mut self) -> u64 {
        self.next_access_order = self.next_access_order.wrapping_add(1);
        self.next_access_order
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

struct SegmentLocation {
    segment_id: String,
    offset: u64,
}

struct SegmentHandleCache {
    entries: HashMap<String, CachedSegmentHandle>,
    next_access_order: u64,
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
            next_access_order: 0,
            capacity,
        }
    }

    fn len(&self) -> usize {
        self.entries.len()
    }

    fn touch(&mut self, cache_key: &str) -> Option<Arc<PersistentFile>> {
        let access_order = self.next_access_order();
        self.entries.get_mut(cache_key).map(|entry| {
            entry.access_order = access_order;
            entry.handle.clone()
        })
    }

    fn insert(&mut self, cache_key: String, handle: Arc<PersistentFile>) -> usize {
        let access_order = self.next_access_order();
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
        self.entries.remove(cache_key).is_some()
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
            let Some(lru_key) = self
                .entries
                .iter()
                .min_by_key(|(_, entry)| entry.access_order)
                .map(|(key, _)| key.clone())
            else {
                break;
            };
            self.entries.remove(&lru_key);
            evicted += 1;
        }
        evicted
    }

    fn next_access_order(&mut self) -> u64 {
        self.next_access_order = self.next_access_order.wrapping_add(1);
        self.next_access_order
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
    use tempfile::TempDir;

    use crate::{
        config::Config,
        failpoints::{FailpointAction, FailpointName},
        io::IoController,
        memory::MemoryController,
        metrics::Metrics,
        replication::operation::ReplicationOperation,
        segment::{reference::SegmentReference, state::SegmentState},
    };

    fn temp_store() -> (TempDir, Config, Store) {
        temp_store_with(|_| {})
    }

    fn temp_store_with<F>(override_config: F) -> (TempDir, Config, Store)
    where
        F: FnOnce(&mut Config),
    {
        let temp_dir = tempfile::tempdir().expect("failed to create temp dir");
        let mut config = Config {
            port: 0,
            grpc_port: 0,
            internal_port: 7443,
            tenant_id: "test-tenant".into(),
            region: "local".into(),
            tmp_dir: temp_dir.path().join("tmp"),
            data_dir: temp_dir.path().join("data"),
            node_url: "http://127.0.0.1:7443".into(),
            peers: vec!["http://127.0.0.1:7443".into()],
            discovery_dns_name: None,
            peer_tls: None,
            grpc_tls: None,
            public_tls: None,
            https_port: 0,
            file_descriptor_pool_size: 32,
            file_descriptor_acquire_timeout_ms: 5_000,
            drain_completion_timeout_ms: 240_000,
            segment_handle_cache_size: 8,
            memory_soft_limit_bytes: 128 * 1024 * 1024,
            memory_hard_limit_bytes: 256 * 1024 * 1024,
            manifest_cache_max_bytes: 8 * 1024 * 1024,
            max_keyvalue_bytes: 512 * 1024,
            rocksdb_max_open_files: 256,
            rocksdb_max_background_jobs: 2,
            rocksdb_block_cache_bytes: 32 * 1024 * 1024,
            rocksdb_write_buffer_manager_bytes: 32 * 1024 * 1024,
            rocksdb_write_buffer_size_bytes: 8 * 1024 * 1024,
            rocksdb_max_write_buffer_number: 4,
            outbox_max_depth: 100_000,
            multipart_upload_ttl_ms: 24 * 60 * 60 * 1000,
            multipart_janitor_interval_ms: 10 * 60 * 1000,
            bootstrap_timeout_ms: 30 * 60 * 1000,
            bootstrap_max_concurrent_peers: 8,
            analytics: None,
            usage: None,
            otlp_traces_endpoint: Some("http://127.0.0.1:4318/v1/traces".into()),
            otel_service_name: "kura-test".into(),
            otel_deployment_environment: "test".into(),
            sentry_dsn: None,
            geoip_refresh_interval_secs: 0,
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
    async fn namespace_tombstones_page_returns_written_tombstones() {
        let (_temp_dir, _config, store) = temp_store();

        store
            .apply_replicated_namespace_delete("ios", 100)
            .await
            .expect("failed to apply first tombstone");
        store
            .apply_replicated_namespace_delete("android", 200)
            .await
            .expect("failed to apply second tombstone");

        let page = store
            .namespace_tombstones_page(None, 8)
            .expect("failed to load tombstone page");
        assert_eq!(page.tombstones.len(), 2);
        assert_eq!(page.tombstones[0].namespace_id, "android");
        assert_eq!(page.tombstones[0].version_ms, 200);
        assert_eq!(page.tombstones[1].namespace_id, "ios");
        assert_eq!(page.tombstones[1].version_ms, 100);
        assert_eq!(page.next_after, None);
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

        let manifest = store
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .expect("artifact should remain");
        assert_eq!(manifest.version_ms, 200);
        assert_eq!(read_manifest_bytes(&store, &manifest).await, b"v2");
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
                }
            );
        }
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
            ArtifactApplyOutcome::IgnoredStale
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
}
