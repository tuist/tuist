use std::{
    collections::BTreeMap,
    io::Write,
    time::{Duration, Instant},
};

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use futures_util::{StreamExt, future::BoxFuture};
use prost::Message;
use sha2::{Digest as _, Sha256};

use super::{protobuf_shape::inspect_action_result_wire, service::read_manifest_bytes};
use crate::{
    artifact::{manifest::ArtifactManifest, producer::ArtifactProducer},
    state::SharedState,
    utils::blob_key,
};

/// Reserved action key whose lookup returns the namespace's action-cache
/// snapshot instead of a stored result. Clients hash these exact bytes the
/// way they hash a real llcas key, so serving it needs no new RPC surface.
/// Bump the version suffix on any change to the snapshot encoding (v2 added
/// the write-time watermark header and delta responses).
pub const SNAPSHOT_ACTION_KEY: &[u8] = b"tuist-actioncache-snapshot/v2";
pub(super) const SNAPSHOT_OUTPUT_PATH: &str = "tuist-actioncache-snapshot";
/// The floor the compressed path's inclusion budget converges to. A body this
/// size is guaranteed to compress under the wire ceiling, so the shrink
/// retries always terminate at a safe view. Also the size below which no
/// benefit is left on the table: the recency window shed the oldest keys.
pub(super) const SNAPSHOT_MIN_BUDGET_BYTES: usize = 48 << 20;

/// Ceiling on the COMPRESSED wire size, with headroom under the 64MB message
/// limit REAPI clients configure. Same transfer budget as the pre-compression
/// snapshot, but it now carries several times the content — a shared
/// namespace's snapshot rides the recency window down to a small suffix of
/// oldest keys, and those sheds were the per-key ladder that made the snapshot
/// net-negative over the WAN. Entries are encoded newest-first, so what sheds
/// is the oldest; dropped keys resolve through the per-key path.
pub(super) const SNAPSHOT_WIRE_MAX_BYTES: usize = 48 << 20;
pub(super) const SNAPSHOT_WIRE_HEADER_BYTES: usize = 13;

/// Conservative allowance for the level-three compressor context and buffers.
/// Snapshot admission reserves this in addition to the uncompressed body and
/// the final wire allocation.
pub(super) const SNAPSHOT_COMPRESSION_SCRATCH_BYTES: usize = 8 << 20;

/// How much UNCOMPRESSED body to include before it stops adding keys. Sized so
/// the zstd output of a full body lands near the wire ceiling for this data's
/// typical ratio; a body that compresses worse is re-encoded smaller (see
/// `encode`). Also bounded in practice by the index's own entry cap.
pub(super) const SNAPSHOT_CONTENT_BUDGET_BYTES: usize = 144 << 20;

/// Bounded shrink retries when a compressed body overshoots the wire ceiling.
/// Each retry scales the content budget down from the observed ratio and can
/// only fall to `SNAPSHOT_MIN_BUDGET_BYTES` (a provably-safe view), so this
/// bounds the encode work, not the correctness.
pub(super) const SNAPSHOT_COMPRESS_MAX_ATTEMPTS: usize = 3;

/// zstd level for the snapshot body. Level 3 runs at hundreds of MB/s and
/// lands within a few percent of higher levels on hex-id node tables, so the
/// serve stays CPU-cheap while the wire shrinks ~3x.
pub(super) const SNAPSHOT_ZSTD_LEVEL: i32 = 3;
/// `inline_output_files` hint carrying the client's write-time watermark:
/// when present, the response includes only entries written after it (a
/// delta), letting a long-lived client refresh without refetching the world.
pub const SNAPSHOT_AFTER_HINT: &str = "tuist-snapshot-after:";
/// Bound on cached per-namespace snapshot indexes (LRU by last use). A kura
/// node serves one tenant, so this comfortably covers every namespace that
/// actually requests snapshots.
pub(super) const SNAPSHOT_CACHE_MAX_NAMESPACES: usize = 32;

/// The most entries a snapshot index holds, counted from the newest write.
/// This bounds the BUILD's memory the way the wire ceiling bounds the
/// response: reconciling against an unbounded keyspace held every manifest
/// in memory at once, and a namespace with weeks of un-expired CI churn
/// OOM-killed the pod on its first serve. With the cap, the scan buffer
/// (≤2x cap of manifests) plus the moved `current` map dominate the build's
/// transient memory — roughly cap x ~1KB.
pub(super) const SNAPSHOT_INDEX_MAX_ENTRIES: usize = 100_000;

pub(super) fn snapshot_index_max_entries() -> usize {
    std::env::var("KURA_SNAPSHOT_INDEX_MAX_ENTRIES")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(SNAPSHOT_INDEX_MAX_ENTRIES)
}

pub(super) fn snapshot_cache_key(namespace_id: &str, trunk: Option<&str>) -> String {
    match trunk {
        Some(trunk) => format!("{namespace_id}\u{0}{trunk}"),
        None => namespace_id.to_owned(),
    }
}

pub(super) fn snapshot_cache_key_parts(cache_key: &str) -> (&str, Option<&str>) {
    match cache_key.split_once('\u{0}') {
        Some((namespace_id, trunk)) => (namespace_id, Some(trunk)),
        None => (cache_key, None),
    }
}

pub(super) fn should_refresh_snapshot_index(reconciled_ago: Duration, idle_for: Duration) -> bool {
    reconciled_ago >= SNAPSHOT_RECONCILE_INTERVAL && idle_for < SNAPSHOT_REFRESH_IDLE_AFTER
}

/// The transient memory a bounded index build is budgeted for, held as a
/// response-materialization-pool permit for the build's duration (adapted
/// down on nodes whose pool is smaller). Matches SNAPSHOT_INDEX_MAX_ENTRIES
/// at ~1KB per entry of scan-buffer + current-map peak, with headroom.
pub(super) const SNAPSHOT_BUILD_BUDGET_BYTES: usize = 192 << 20;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct SnapshotBuildBudgets {
    pub(super) metadata_bytes: usize,
    pub(super) index_bytes: usize,
    pub(super) encoded_bytes: usize,
    pub(super) decoded_bytes: usize,
}

impl SnapshotBuildBudgets {
    pub(super) fn new(total_bytes: usize, index_max_bytes: usize) -> Self {
        let metadata_bytes = total_bytes / 4;
        let index_bytes = (total_bytes / 2).min(index_max_bytes);
        let load_bytes = total_bytes / 4;
        let encoded_bytes = load_bytes / 2;
        let decoded_bytes = load_bytes.saturating_sub(encoded_bytes);
        Self {
            metadata_bytes,
            index_bytes,
            encoded_bytes,
            decoded_bytes,
        }
    }
}

/// How long a snapshot build waits for its memory-pool permit before
/// declining. Generous: the build is background work, and the pool drains as
/// in-flight responses complete — declining is only right when the node is
/// pinned at capacity for this entire window.
pub(super) const SNAPSHOT_BUILD_PERMIT_WAIT: Duration = Duration::from_secs(600);

/// How old a cached snapshot index may grow before it is reconciled. Requests
/// never wait on it — they get the cached
/// view — so this bounds staleness, not latency; it composes with the
/// client's ~2-minute delta cadence.
pub(super) const SNAPSHOT_RECONCILE_INTERVAL: Duration = Duration::from_secs(60);

pub(super) const SNAPSHOT_REFRESH_TICK: Duration = Duration::from_secs(15);

pub(super) const SNAPSHOT_REFRESH_IDLE_AFTER: Duration = Duration::from_secs(30 * 60);

/// How long a COLD serve (no cached index) waits for the build before
/// answering UNAVAILABLE. Long enough that an already-indexed namespace's
/// reconcile completes inline and small namespaces keep one-round-trip
/// semantics; far shorter than any client deadline, so a first-ever backfill
/// of a large namespace sheds requests fast instead of timing them all out.
pub(super) const SNAPSHOT_COLD_SERVE_WAIT: Duration = Duration::from_secs(15);

/// Stranded-node floor below which a cached snapshot index skips compacting
/// its node table (the sweep rewrites every entry's index list).
pub(super) const SNAPSHOT_COMPACT_MIN_GARBAGE: usize = 1024;

/// Minimum age before the presence gate's dead entries are cascade-deleted
/// from the store. Client publication orders blobs before the entry, but peer
/// replication and bootstrap may deliver an entry before its blobs — a young
/// entry with missing blobs is more likely mid-sync than stranded.
pub(super) const SNAPSHOT_CASCADE_GRACE_MS: u64 = 60 * 60 * 1000;

pub(super) fn snapshot_action_hash() -> &'static str {
    static HASH: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    HASH.get_or_init(|| hex::encode(Sha256::digest(SNAPSHOT_ACTION_KEY)))
}

pub(super) struct SnapshotNode {
    pub(super) llcas: Vec<u8>,
    pub(super) blob_hash: [u8; 32],
    pub(super) blob_size: u64,
    /// The blob's keyvalue artifact key, precomputed for the per-serve
    /// presence gate.
    pub(super) blob_key: String,
}

pub(super) struct SnapshotIndexEntry {
    pub(super) version_ms: u64,
    pub(super) nodes: Vec<u32>,
}

/// Incrementally maintained view of one namespace's action cache, so serving
/// a snapshot is a manifest-index reconcile plus an in-memory encode instead
/// of re-reading every stored ActionResult. Reconciliation (rather than
/// write-path hooks) keeps it correct under peer replication and eviction:
/// whatever wrote or removed an entry, the manifest keyspace is the truth
/// this diffs against.
pub(super) struct NamespaceSnapshotIndex {
    pub(super) nodes: Vec<SnapshotNode>,
    pub(super) node_index: BTreeMap<Vec<u8>, u32>,
    pub(super) entries: BTreeMap<[u8; 32], SnapshotIndexEntry>,
    pub(super) estimated_bytes: usize,
    pub(super) last_used: Instant,
    /// When the last successful reconcile finished. Serving reads this to
    /// decide whether the cached view is fresh enough to return as-is.
    pub(super) reconciled_at: Instant,
    /// The namespace's action-cache generation when this index was built. An
    /// empty index is only served while this still matches the store.
    pub(super) built_at_generation: u64,
}

impl NamespaceSnapshotIndex {
    pub(super) fn new() -> Self {
        let mut index = Self {
            nodes: Vec::new(),
            node_index: BTreeMap::new(),
            entries: BTreeMap::new(),
            estimated_bytes: 0,
            last_used: Instant::now(),
            reconciled_at: Instant::now(),
            built_at_generation: 0,
        };
        index.recompute_estimated_bytes();
        index
    }

    #[cfg(test)]
    pub(super) fn intern_node(
        &mut self,
        llcas: Vec<u8>,
        blob_hash: [u8; 32],
        blob_size: u64,
    ) -> u32 {
        self.try_intern_node(llcas, blob_hash, blob_size, usize::MAX)
            .expect("unbounded snapshot node admission should succeed")
    }

    pub(super) fn try_intern_node(
        &mut self,
        llcas: Vec<u8>,
        blob_hash: [u8; 32],
        blob_size: u64,
        max_bytes: usize,
    ) -> Option<u32> {
        if let Some(&index) = self.node_index.get(&llcas) {
            return Some(index);
        }
        let blob_key = blob_key(&format!("{}/{}", hex::encode(blob_hash), blob_size));
        let added_bytes = estimated_snapshot_node_bytes(llcas.len(), blob_key.len());
        if self.estimated_bytes.saturating_add(added_bytes) > max_bytes {
            return None;
        }
        let index = self.nodes.len() as u32;
        self.nodes.push(SnapshotNode {
            llcas: llcas.clone(),
            blob_hash,
            blob_size,
            blob_key,
        });
        self.node_index.insert(llcas, index);
        self.estimated_bytes = self.estimated_bytes.saturating_add(added_bytes);
        Some(index)
    }

    fn remove_entry(&mut self, hash: &[u8; 32]) {
        if let Some(entry) = self.entries.remove(hash) {
            self.estimated_bytes = self
                .estimated_bytes
                .saturating_sub(estimated_snapshot_entry_bytes(entry.nodes.len()));
        }
    }

    pub(super) fn insert_entry(&mut self, hash: [u8; 32], entry: SnapshotIndexEntry) {
        self.remove_entry(&hash);
        self.estimated_bytes = self
            .estimated_bytes
            .saturating_add(estimated_snapshot_entry_bytes(entry.nodes.len()));
        self.entries.insert(hash, entry);
    }

    pub(super) fn estimated_bytes(&self) -> usize {
        self.estimated_bytes
    }

    fn recompute_estimated_bytes(&mut self) {
        self.estimated_bytes = std::mem::size_of::<Self>()
            .saturating_add(
                self.nodes
                    .iter()
                    .map(|node| {
                        estimated_snapshot_node_bytes(node.llcas.len(), node.blob_key.len())
                    })
                    .sum::<usize>(),
            )
            .saturating_add(
                self.entries
                    .values()
                    .map(|entry| estimated_snapshot_entry_bytes(entry.nodes.len()))
                    .sum::<usize>(),
            );
    }

    /// Rebuilds the node table around the nodes that live entries still
    /// reference. Entry churn (republished keys, evicted action results)
    /// strands nodes nothing references anymore; `intern_node` only ever
    /// appends, so without this sweep a long-cached index for an actively
    /// written namespace would grow its node table for the life of the
    /// process. Skipped while the garbage share is too small to be worth
    /// rewriting every entry's index list.
    pub(super) fn compact_nodes(&mut self) {
        let mut remap: Vec<Option<u32>> = vec![None; self.nodes.len()];
        let mut live: u32 = 0;
        for entry in self.entries.values() {
            for &node in &entry.nodes {
                if remap[node as usize].is_none() {
                    remap[node as usize] = Some(live);
                    live += 1;
                }
            }
        }
        let garbage = self.nodes.len() - live as usize;
        if garbage < SNAPSHOT_COMPACT_MIN_GARBAGE || garbage * 2 < self.nodes.len() {
            return;
        }
        let old_nodes = std::mem::take(&mut self.nodes);
        let mut new_nodes: Vec<Option<SnapshotNode>> = Vec::new();
        new_nodes.resize_with(live as usize, || None);
        for (old_index, node) in old_nodes.into_iter().enumerate() {
            if let Some(new_index) = remap[old_index] {
                new_nodes[new_index as usize] = Some(node);
            }
        }
        self.nodes = new_nodes.into_iter().flatten().collect();
        self.node_index = self
            .nodes
            .iter()
            .enumerate()
            .map(|(index, node)| (node.llcas.clone(), index as u32))
            .collect();
        for entry in self.entries.values_mut() {
            for node in &mut entry.nodes {
                *node = remap[*node as usize].expect("live entry references a swept node");
            }
        }
        self.recompute_estimated_bytes();
    }

    /// Encodes a view for the wire, always zstd-compressed into the `TSNZ`
    /// envelope. The body is included up to the larger content budget then
    /// compressed; a body that compresses worse than budgeted is re-encoded
    /// with a smaller budget scaled from the observed ratio, bounded to a few
    /// tries that can only converge on the provably-safe minimum budget.
    ///
    /// Every snapshot client decodes `TSNZ`; the plain `TSNP` body still exists
    /// (see `encode_body`) only because a NEW client may hit an OLD server mid
    /// kura-mesh-roll and must read what those pods emit — this server never
    /// emits it. The client falls back to the per-key path on any body it can't
    /// decode, so there is nothing to negotiate.
    #[cfg(test)]
    pub(super) fn encode(&self, after: u64) -> Vec<u8> {
        self.encode_with_budget(after, SNAPSHOT_CONTENT_BUDGET_BYTES)
            .expect("the default snapshot budget should fit the wire ceiling")
    }

    pub(super) fn encode_with_budget(
        &self,
        after: u64,
        max_content_bytes: usize,
    ) -> Result<Vec<u8>, SnapshotEncodeError> {
        let mut budget = SNAPSHOT_CONTENT_BUDGET_BYTES.min(max_content_bytes.max(1));
        let minimum_budget = SNAPSHOT_MIN_BUDGET_BYTES.min(budget);
        for attempt in 0..SNAPSHOT_COMPRESS_MAX_ATTEMPTS {
            let body = self.encode_body(after, budget);
            if let Some(wire) = compress_snapshot(&body) {
                return Ok(wire);
            }
            // The size-limited writer discarded the failed wire allocation.
            // Drop the input before starting another attempt so retries never
            // retain two uncompressed bodies at once.
            drop(body);
            if attempt + 1 == SNAPSHOT_COMPRESS_MAX_ATTEMPTS {
                return Err(SnapshotEncodeError::WireLimitExceeded);
            }
            // Move halfway toward the proven-safe floor, reaching it for the
            // final attempt even when the first body is incompressible.
            budget = if attempt + 2 == SNAPSHOT_COMPRESS_MAX_ATTEMPTS {
                minimum_budget
            } else {
                ((budget + minimum_budget) / 2).max(minimum_budget)
            };
        }
        Err(SnapshotEncodeError::WireLimitExceeded)
    }

    /// The uncompressed body, including keys until `budget` bytes of wire are
    /// accounted, with a response-local node table so every view is
    /// self-contained. `after == 0` is a full newest-first recency window (an
    /// oversized namespace degrades to "the most recent keys, the rest
    /// per-key"); a delta (`after > 0`) includes entries with
    /// `version_ms >= after` — inclusive, because millisecond timestamps are
    /// not unique and a write landing in an already-served millisecond must
    /// reappear (re-sent boundary entries merge idempotently client-side) —
    /// assembled oldest-first with the header watermark set to the newest
    /// entry actually included, so an overflowing delta paginates rather than
    /// skipping what it dropped. This is `encode`'s pre-compression input; it
    /// is also the exact `TSNP` layout old kura pods still serve on the wire.
    pub(super) fn encode_body(&self, after: u64, budget: usize) -> Vec<u8> {
        let full = after == 0;
        let mut included: Vec<(&[u8; 32], &SnapshotIndexEntry)> = self
            .entries
            .iter()
            .filter(|(_, entry)| full || entry.version_ms >= after)
            .collect();
        if full {
            included.sort_by(|a, b| b.1.version_ms.cmp(&a.1.version_ms));
        } else {
            included.sort_by(|a, b| a.1.version_ms.cmp(&b.1.version_ms));
        }

        // Response-local node remap: only nodes the included keys reference.
        let total = included.len();
        let mut remap: BTreeMap<u32, u32> = BTreeMap::new();
        let mut response_nodes: Vec<u32> = Vec::new();
        let mut keys: Vec<(&[u8; 32], Vec<u32>)> = Vec::new();
        let mut estimated = 0usize;
        let mut watermark = after;
        for (hash, entry) in included {
            let mut key_cost = 32 + 4 + entry.nodes.len() * 4;
            for &node in &entry.nodes {
                if !remap.contains_key(&node) {
                    key_cost += 1 + self.nodes[node as usize].llcas.len() + 32 + 8;
                }
            }
            if estimated + key_cost > budget {
                if full {
                    // Recency window: this key is out, smaller older ones may fit.
                    continue;
                }
                // Pagination: everything from here on is newer than the
                // watermark being returned, so it arrives on the next delta.
                break;
            }
            estimated += key_cost;
            watermark = watermark.max(entry.version_ms);
            let indexes = entry
                .nodes
                .iter()
                .map(|&node| {
                    *remap.entry(node).or_insert_with(|| {
                        response_nodes.push(node);
                        (response_nodes.len() - 1) as u32
                    })
                })
                .collect();
            keys.push((hash, indexes));
        }
        let dropped = total - keys.len();
        if dropped > 0 {
            if full {
                tracing::warn!(
                    "action-cache snapshot truncated: {dropped} oldest keys over the size ceiling"
                );
            } else {
                tracing::info!(
                    "action-cache snapshot delta paginated: {dropped} newest keys deferred to the next delta"
                );
            }
        }

        let mut out = Vec::with_capacity(estimated + 32);
        out.extend_from_slice(b"TSNP");
        out.push(2);
        out.extend_from_slice(&watermark.to_le_bytes());
        out.extend_from_slice(&(response_nodes.len() as u32).to_le_bytes());
        for &node in &response_nodes {
            let node = &self.nodes[node as usize];
            out.push(node.llcas.len() as u8);
            out.extend_from_slice(&node.llcas);
            out.extend_from_slice(&node.blob_hash);
            out.extend_from_slice(&node.blob_size.to_le_bytes());
        }
        out.extend_from_slice(&(keys.len() as u32).to_le_bytes());
        for (hash, indexes) in &keys {
            out.extend_from_slice(*hash);
            out.extend_from_slice(&(indexes.len() as u32).to_le_bytes());
            for index in indexes {
                out.extend_from_slice(&index.to_le_bytes());
            }
        }
        out
    }
}

fn estimated_map_item_bytes(payload_bytes: usize) -> usize {
    payload_bytes
        .saturating_add(4 * std::mem::size_of::<usize>())
        .saturating_mul(3)
        / 2
}

fn estimated_snapshot_node_bytes(llcas_bytes: usize, blob_key_bytes: usize) -> usize {
    estimated_map_item_bytes(
        std::mem::size_of::<SnapshotNode>()
            .saturating_add(std::mem::size_of::<(Vec<u8>, u32)>())
            .saturating_add(llcas_bytes.saturating_mul(2))
            .saturating_add(blob_key_bytes),
    )
}

fn estimated_snapshot_entry_bytes(node_count: usize) -> usize {
    estimated_map_item_bytes(
        std::mem::size_of::<([u8; 32], SnapshotIndexEntry)>()
            .saturating_add(node_count.saturating_mul(std::mem::size_of::<u32>())),
    )
}

/// Wraps a `TSNP` body in the `TSNZ` envelope: magic, version, the u64
/// uncompressed length (so the client can size its buffer and reject a torn
/// payload), then the zstd stream. Only clients that advertise zstd support
/// receive this; everyone else gets the raw body.
#[derive(Debug)]
pub(super) enum SnapshotEncodeError {
    WireLimitExceeded,
}

struct SnapshotWireWriter {
    bytes: Vec<u8>,
    max_bytes: usize,
}

impl SnapshotWireWriter {
    fn new(uncompressed_bytes: usize) -> Self {
        Self::with_limit(uncompressed_bytes, SNAPSHOT_WIRE_MAX_BYTES)
    }

    fn with_limit(uncompressed_bytes: usize, max_bytes: usize) -> Self {
        let capacity = zstd::zstd_safe::compress_bound(uncompressed_bytes)
            .saturating_add(SNAPSHOT_WIRE_HEADER_BYTES)
            .min(max_bytes);
        let mut bytes = Vec::with_capacity(capacity);
        bytes.extend_from_slice(b"TSNZ");
        bytes.push(1);
        bytes.extend_from_slice(&(uncompressed_bytes as u64).to_le_bytes());
        Self { bytes, max_bytes }
    }
}

impl Write for SnapshotWireWriter {
    fn write(&mut self, buffer: &[u8]) -> std::io::Result<usize> {
        if self.bytes.len().saturating_add(buffer.len()) > self.max_bytes {
            return Err(std::io::Error::new(
                std::io::ErrorKind::FileTooLarge,
                "snapshot wire ceiling exceeded",
            ));
        }
        self.bytes.extend_from_slice(buffer);
        Ok(buffer.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn compress_snapshot(body: &[u8]) -> Option<Vec<u8>> {
    let writer = SnapshotWireWriter::new(body.len());
    let mut encoder = zstd::stream::write::Encoder::new(writer, SNAPSHOT_ZSTD_LEVEL)
        .expect("zstd encoder construction should succeed");
    encoder.write_all(body).ok()?;
    Some(encoder.finish().ok()?.bytes)
}

#[cfg(test)]
#[test]
fn snapshot_wire_writer_rejects_bytes_past_its_limit() {
    let mut writer = SnapshotWireWriter::with_limit(1, SNAPSHOT_WIRE_HEADER_BYTES + 1);
    writer
        .write_all(&[0xAA])
        .expect("the final byte inside the limit should fit");
    assert!(writer.write_all(&[0xBB]).is_err());
}

/// Completed snapshot indexes (bounded by SNAPSHOT_CACHE_MAX_NAMESPACES, LRU
/// by last use) plus the in-flight builds producing them. Builds run as
/// DETACHED tasks shared by every concurrent request for a namespace: the
/// first build of a large namespace can outlive a gateway's upstream timeout,
/// and dropping the work with the aborted request meant every retry rebuilt
/// from scratch and timed out the same way — the snapshot never became
/// servable. A detached build completes and caches regardless of who is
/// still waiting.
pub(crate) struct SnapshotCache {
    pub(super) indexes: std::sync::Mutex<BTreeMap<String, NamespaceSnapshotIndex>>,
    pub(super) builds: std::sync::Mutex<std::collections::HashMap<String, SharedIndexBuild>>,
    /// The last FULL (`after == 0`) encoded snapshot per namespace. A reconcile
    /// takes its index out of `indexes` for the build's duration, so a serve
    /// landing during a rebuild would otherwise find nothing and shed a cold
    /// client to UNAVAILABLE. Serving this last full view instead keeps them on
    /// the (slightly stale) snapshot. Bounded at the wire ceiling per entry and
    /// pruned with the index LRU — unlike cloning the whole index, whose
    /// node table the entry cap does not bound.
    pub(super) served_full: std::sync::Mutex<BTreeMap<String, std::sync::Arc<Vec<u8>>>>,
    pub(super) build_lock: tokio::sync::Mutex<()>,
    pub(super) max_bytes: usize,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct SnapshotCacheStats {
    pub(crate) bytes: usize,
    pub(crate) namespaces: usize,
    pub(crate) entries: usize,
    pub(crate) nodes: usize,
    pub(crate) served_full_bytes: usize,
}

impl Default for SnapshotCache {
    fn default() -> Self {
        Self::new(256 << 20)
    }
}

impl SnapshotCache {
    pub(crate) fn new(max_bytes: usize) -> Self {
        Self {
            indexes: Default::default(),
            builds: Default::default(),
            served_full: Default::default(),
            build_lock: Default::default(),
            max_bytes: max_bytes.max(1),
        }
    }

    pub(super) fn index_max_bytes(&self) -> usize {
        self.max_bytes
            .saturating_sub((self.max_bytes / 4).min(SNAPSHOT_WIRE_MAX_BYTES))
            .max(1)
    }

    pub(crate) fn stats(&self) -> SnapshotCacheStats {
        let indexes = self.indexes.lock().expect("snapshot cache lock poisoned");
        let served_full = self
            .served_full
            .lock()
            .expect("snapshot served_full lock poisoned");
        Self::stats_locked(&indexes, &served_full)
    }

    fn stats_locked(
        indexes: &BTreeMap<String, NamespaceSnapshotIndex>,
        served_full: &BTreeMap<String, std::sync::Arc<Vec<u8>>>,
    ) -> SnapshotCacheStats {
        let entries = indexes.values().map(|index| index.entries.len()).sum();
        let nodes = indexes.values().map(|index| index.nodes.len()).sum();
        let index_bytes = indexes
            .iter()
            .map(|(namespace, index)| {
                index
                    .estimated_bytes()
                    .saturating_add(estimated_map_item_bytes(namespace.len()))
            })
            .sum::<usize>();
        let served_full_bytes = served_full
            .iter()
            .map(|(namespace, bytes)| {
                bytes
                    .capacity()
                    .saturating_add(estimated_map_item_bytes(namespace.len()))
            })
            .sum();
        SnapshotCacheStats {
            bytes: index_bytes.saturating_add(served_full_bytes),
            namespaces: indexes.len(),
            entries,
            nodes,
            served_full_bytes,
        }
    }

    pub(crate) fn update_metrics(&self, metrics: &crate::metrics::Metrics) {
        let stats = self.stats();
        metrics.update_snapshot_cache(
            stats.bytes,
            self.max_bytes,
            stats.namespaces,
            stats.entries,
            stats.nodes,
            stats.served_full_bytes,
        );
    }

    pub(crate) fn trim_to(
        &self,
        target_bytes: usize,
        reason: &str,
        metrics: &crate::metrics::Metrics,
    ) -> usize {
        let target_bytes = target_bytes.min(self.max_bytes);
        let mut indexes = self.indexes.lock().expect("snapshot cache lock poisoned");
        let mut served_full = self
            .served_full
            .lock()
            .expect("snapshot served_full lock poisoned");
        let mut evicted = 0;
        loop {
            let stats = Self::stats_locked(&indexes, &served_full);
            if stats.bytes <= target_bytes {
                metrics.update_snapshot_cache(
                    stats.bytes,
                    self.max_bytes,
                    stats.namespaces,
                    stats.entries,
                    stats.nodes,
                    stats.served_full_bytes,
                );
                break;
            }
            let oldest = indexes
                .iter()
                .min_by_key(|(_, index)| index.last_used)
                .map(|(namespace, _)| namespace.clone())
                .or_else(|| served_full.keys().next().cloned());
            let Some(oldest) = oldest else { break };
            indexes.remove(&oldest);
            served_full.remove(&oldest);
            evicted += 1;
        }
        if evicted > 0 {
            metrics.record_memory_action("snapshot_cache_trim");
            tracing::warn!(
                evicted,
                reason,
                target_bytes,
                "trimmed action-cache snapshot cache"
            );
        }
        evicted
    }
}

pub(super) type SharedIndexBuild =
    futures_util::future::Shared<BoxFuture<'static, Result<(), String>>>;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum IndexBuildTrigger {
    Serve,
    Refresh,
}

/// Reconciles a namespace's snapshot index against the manifest keyspace:
/// one namespace-index scan, action-result reads only for new-or-changed
/// entries, the manifest-existence presence gate with its cascade delete,
/// and node-table compaction. On failure the caller gets the index back so
/// progress survives transient store errors.
pub(super) async fn reconcile_snapshot_index(
    state: &SharedState,
    namespace_id: &str,
    trunk: Option<&str>,
    mut index: NamespaceSnapshotIndex,
    budgets: SnapshotBuildBudgets,
) -> Result<NamespaceSnapshotIndex, (NamespaceSnapshotIndex, String)> {
    let started = Instant::now();
    if index.estimated_bytes() > budgets.index_bytes {
        index = NamespaceSnapshotIndex::new();
    }
    let store = state.store.clone();
    let scan_namespace_id = namespace_id.to_owned();
    let scan_trunk = trunk.map(str::to_owned);
    let manifests = match tokio::task::spawn_blocking(move || {
        store.action_cache_manifests_bounded(
            &scan_namespace_id,
            snapshot_index_max_entries(),
            budgets.metadata_bytes,
            scan_trunk.as_deref(),
        )
    })
    .await
    {
        Ok(Ok(manifests)) => manifests,
        Ok(Err(error)) => {
            return Err((
                index,
                format!("failed to enumerate the action cache: {error}"),
            ));
        }
        Err(error) => {
            return Err((
                index,
                format!("action-cache enumeration task failed: {error}"),
            ));
        }
    };
    let scan_ms = started.elapsed().as_millis() as u64;
    // Diff the cached entries against the manifest keyspace: load only
    // new-or-changed entries, drop entries whose artifacts are gone.
    // Manifests are MOVED into the map (never cloned), and action results
    // stream through a bounded window below instead of being collected —
    // building the first index for a large namespace with layered full-size
    // copies OOM-killed 2Gi production pods even with the scan capped.
    let mut current: BTreeMap<[u8; 32], (u64, ArtifactManifest)> = BTreeMap::new();
    for manifest in manifests {
        let Some(hash) = manifest
            .key
            .strip_prefix("action_cache/")
            .and_then(|rest| rest.split('/').next())
            .and_then(|hash| hex::decode(hash).ok())
            .and_then(|hash| <[u8; 32]>::try_from(hash.as_slice()).ok())
        else {
            continue;
        };
        let version = manifest.version_ms;
        current.insert(hash, (version, manifest));
    }
    index.entries.retain(|hash, _| current.contains_key(hash));
    index.recompute_estimated_bytes();
    let mut changed: Vec<([u8; 32], u64)> = current
        .iter()
        .filter(|(hash, (version, _))| {
            index
                .entries
                .get(*hash)
                .is_none_or(|entry| entry.version_ms != *version)
        })
        .map(|(hash, (version, _))| (*hash, *version))
        .collect();
    changed.sort_unstable_by(|(_, left), (_, right)| right.cmp(left));
    // Manifests move out for the load and move back with the result, so the
    // stream owns everything it captures (the whole reconcile runs inside a
    // 'static spawned task) without duplicating a single manifest.
    let mut to_load = Vec::with_capacity(changed.len());
    for (hash, _) in changed {
        if let Some((version, manifest)) = current.remove(&hash) {
            to_load.push((hash, version, manifest));
        }
    }
    let changed_count = to_load.len();
    let mut loads_failed = 0_usize;
    let mut invalid = 0_usize;
    let mut budget_rejected = 0_usize;
    let encoded_load_budget =
        std::sync::Arc::new(tokio::sync::Semaphore::new(budgets.encoded_bytes.max(1)));
    let decoded_load_budget =
        std::sync::Arc::new(tokio::sync::Semaphore::new(budgets.decoded_bytes.max(1)));
    let mut loading =
        futures_util::stream::iter(to_load.into_iter().map(|(hash, version, manifest)| {
            let state = state.clone();
            let encoded_load_budget = encoded_load_budget.clone();
            async move {
                let encoded_bytes = manifest.size.max(1);
                let Ok(encoded_permits) = u32::try_from(encoded_bytes) else {
                    return (hash, version, manifest, None, true);
                };
                if encoded_bytes > budgets.encoded_bytes as u64 {
                    return (hash, version, manifest, None, true);
                }
                let encoded_permit = encoded_load_budget
                    .acquire_many_owned(encoded_permits)
                    .await
                    .expect("snapshot encoded load budget is never closed");
                let bytes = read_manifest_bytes(&state, &manifest).await.ok();
                let Some(bytes) = bytes else {
                    return (hash, version, manifest, None, false);
                };
                let Ok(shape) = inspect_action_result_wire(&bytes) else {
                    return (hash, version, manifest, None, false);
                };
                let decoded_bytes = shape.estimated_decoded_bytes();
                let Ok(decoded_permits) = u32::try_from(decoded_bytes) else {
                    return (hash, version, manifest, None, true);
                };
                if decoded_bytes > budgets.decoded_bytes as u64 {
                    return (hash, version, manifest, None, true);
                }
                (
                    hash,
                    version,
                    manifest,
                    Some((bytes, decoded_permits, encoded_permit)),
                    false,
                )
            }
        }))
        .buffered(32);
    while let Some((hash, version_ms, manifest, loaded, load_rejected)) = loading.next().await {
        current.insert(hash, (version_ms, manifest));
        index.remove_entry(&hash);
        if load_rejected {
            budget_rejected += 1;
            continue;
        }
        let (action_result, load_permit) =
            if let Some((bytes, decoded_permits, encoded_permit)) = loaded {
                // Decode in stream order after the concurrent reads complete.
                // If later loads acquired decoded permits inside their futures,
                // an earlier slow read could wait behind ready results that
                // `buffered` cannot yield yet, deadlocking the bounded pool.
                let decoded_permit = decoded_load_budget
                    .clone()
                    .acquire_many_owned(decoded_permits)
                    .await
                    .expect("snapshot decoded load budget is never closed");
                (
                    reapi::ActionResult::decode(bytes.as_slice()).ok(),
                    Some((encoded_permit, decoded_permit)),
                )
            } else {
                (None, None)
            };
        let Some(action_result) = action_result else {
            loads_failed += 1;
            continue;
        };
        let entry_bytes = estimated_snapshot_entry_bytes(action_result.output_files.len());
        if index.estimated_bytes().saturating_add(entry_bytes) > budgets.index_bytes {
            budget_rejected += 1;
            continue;
        }
        let mut nodes = Vec::with_capacity(action_result.output_files.len());
        let mut valid = !action_result.output_files.is_empty();
        for file in &action_result.output_files {
            let (Ok(llcas), Some(digest)) = (hex::decode(&file.path), file.digest.as_ref()) else {
                valid = false;
                break;
            };
            let (Ok(blob_hash), true) = (
                hex::decode(&digest.hash)
                    .map_err(|_| ())
                    .and_then(|hash| <[u8; 32]>::try_from(hash.as_slice()).map_err(|_| ())),
                digest.size_bytes >= 0,
            ) else {
                valid = false;
                break;
            };
            let node_budget = budgets.index_bytes.saturating_sub(entry_bytes);
            let Some(node) =
                index.try_intern_node(llcas, blob_hash, digest.size_bytes as u64, node_budget)
            else {
                valid = false;
                budget_rejected += 1;
                break;
            };
            nodes.push(node);
        }
        if valid {
            index.insert_entry(hash, SnapshotIndexEntry { version_ms, nodes });
        } else {
            invalid += 1;
        }
        drop(load_permit);
        if !state.memory.allow_background_admission() {
            drop(loading);
            index.compact_nodes();
            return Err((
                index,
                "memory pressure interrupted snapshot reconcile".into(),
            ));
        }
    }
    drop(loading);
    let load_ms = started.elapsed().as_millis() as u64 - scan_ms;

    // Presence gate: an entry only stays advertised while every node's
    // blob manifest exists (CAS eviction outlives action-cache entries,
    // and clang fails the build on a missing object). Mostly
    // existence-cache hits; a dead entry is dropped from the cache too —
    // a republish bumps its version and reloads it. The store reads are
    // synchronous, so yield periodically: on a cold cache this loop is
    // hundreds of thousands of point reads, and unbroken it parks a whole
    // runtime worker for their duration.
    let mut dead: Vec<[u8; 32]> = Vec::new();
    for (gated, (hash, entry)) in index.entries.iter().enumerate() {
        if gated % 1024 == 1023 {
            tokio::task::yield_now().await;
        }
        let missing = entry.nodes.iter().any(|&node| {
            !state
                .store
                .artifact_manifest_exists(
                    ArtifactProducer::Reapi,
                    namespace_id,
                    &index.nodes[node as usize].blob_key,
                )
                .unwrap_or(false)
        });
        if missing {
            dead.push(*hash);
        }
    }
    // Cascade: an entry whose blobs were evicted is unserveable by
    // construction (the per-key path would hand out a manifest whose
    // batch_read then misses), so delete it from the store too, not just
    // from the cached index. The grace window keeps this from fighting
    // peer replication that delivers an entry before its blobs finish
    // syncing.
    let now = crate::utils::now_ms();
    let cascade: Vec<ArtifactManifest> = dead
        .iter()
        .filter_map(|hash| current.get(hash))
        .filter(|(version_ms, _)| now.saturating_sub(*version_ms) > SNAPSHOT_CASCADE_GRACE_MS)
        .map(|(_, manifest)| manifest.clone())
        .collect();
    for hash in dead {
        index.remove_entry(&hash);
    }
    if !cascade.is_empty() {
        match state.store.delete_artifact_metadata(&cascade) {
            Ok(()) => tracing::info!(
                deleted = cascade.len(),
                namespace_id,
                "deleted action-cache entries whose blobs were evicted"
            ),
            Err(error) => tracing::warn!("action-cache cascade delete failed: {error}"),
        }
    }
    index.compact_nodes();

    // One line per reconcile: production served a stale snapshot for hours
    // and nothing said whether builds were running, how much they scanned, or
    // what the index held afterwards — this is the Loki breadcrumb that turns
    // that from archaeology into a query.
    // `changed` counts entries whose scanned version differed from the cached
    // index; a load or parse failure there silently retains the entry's OLD
    // version, which is exactly the shape of a frozen watermark — these
    // counters are what distinguish "nothing new was published" from "new
    // versions were published but every reload failed".
    tracing::info!(
        namespace_id,
        entries = index.entries.len(),
        nodes = index.nodes.len(),
        watermark = index
            .entries
            .values()
            .map(|entry| entry.version_ms)
            .max()
            .unwrap_or(0),
        changed = changed_count,
        loads_failed,
        invalid,
        budget_rejected,
        estimated_bytes = index.estimated_bytes(),
        index_max_bytes = budgets.index_bytes,
        scan_ms,
        load_ms,
        gate_ms = started.elapsed().as_millis() as u64 - scan_ms - load_ms,
        elapsed_ms = started.elapsed().as_millis() as u64,
        "action-cache snapshot index reconciled"
    );
    Ok(index)
}
