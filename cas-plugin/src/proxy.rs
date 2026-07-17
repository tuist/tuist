//! The per-machine proxy: one long-lived process owns the REAPI channel,
//! the resolved-key map, the global known-local set, and all publications.
//! Compiler processes stay thin (one unix-socket round trip per cache miss),
//! which is what keeps warm builds near the local-CAS floor: any fixed
//! per-process cost is multiplied by thousands of short-lived frontends.
//!
//! The proxy opens the same on-disk local CAS the compilers use (the store
//! is multi-process by design) and materializes fetched graphs into it
//! before answering a resolve, so consumers' demand loads are local hits.

use std::collections::{HashMap, HashSet, VecDeque};
use std::os::unix::fs::MetadataExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, RwLock};
use std::time::{Duration, Instant, UNIX_EPOCH};

use crate::prefetch::Prefetcher;
use crate::proxy_proto::{
    read_request, write_response, Request, OP_FETCH_OBJECT, OP_INVALIDATE, OP_PUBLISH,
    OP_RESOLVE,
    STATUS_ERROR, STATUS_HIT, STATUS_MISS,
};
use crate::reapi::{self, ManifestEntry, Remote, RemoteConfig};
use crate::token::TokenProvider;
use crate::types::*;
use crate::upstream::Upstream;
use crate::PublishRecord;

// Bounds for the per-path in-memory caches so a long-lived (machine-wide,
// launchd-managed) proxy cannot grow without limit across many builds. They
// are correctness-preserving caches — clearing only forces a re-resolve or a
// re-check, never a wrong answer — so clearing on overflow is safe. The caps sit
// well above a single warm build's working set (a warm build touches ~1.9M
// known-local digests total, i.e. ~60k per shard), so within-build warmth is
// preserved and only cross-build accumulation is reclaimed.
const MAX_RESOLVED: usize = 1_000_000;
const MAX_KNOWN_LOCAL_PER_SHARD: usize = 250_000;
const MAX_PUBLISH_CACHE: usize = 500_000;
// Retained fetch instructions are ~100B each, so the cap is a ~100MB memory
// backstop a real workload never reaches (the CLI fixture peaks at ~37k). A
// cleared map self-heals per object through the snapshot fallback in
// `fetch_object`.
const MAX_PENDING_OBJECTS: usize = 1_000_000;

// Snapshot refresh cadence and cache bounds (see `refresh_snapshots`).
// Default cadence for the incremental (watermark-scoped) snapshot delta of an
// active instance, overridable via TUIST_CAS_SNAPSHOT_DELTA_INTERVAL (seconds).
// A delta is a cheap fetch of only the trunk entries newer than what we hold,
// so this trades trunk freshness against a small periodic round trip.
const SNAPSHOT_DELTA_INTERVAL_DEFAULT_SECS: u64 = 10 * 60;
// How long a FETCH_OBJECT with no registered instruction waits for the
// instance's snapshot to arrive before answering not-found (it runs on a
// compiler worker thread, which demand fetches already block on network I/O).
const SNAPSHOT_FETCH_WAIT: Duration = Duration::from_secs(20);
const SNAPSHOT_FULL_INTERVAL: Duration = Duration::from_secs(30 * 60);
const SNAPSHOT_RETRY_INTERVAL: Duration = Duration::from_secs(60 * 60);
// Ceiling on a compressed snapshot's declared uncompressed size, so a torn or
// hostile length prefix cannot drive an unbounded allocation. Comfortably
// above the server's content budget (144 MiB); a legitimate body never
// approaches it.
const SNAPSHOT_DECOMPRESS_MAX_BYTES: usize = 512 << 20;
// A leader that finds itself alone lingers this long before firing, giving a
// near-simultaneous straggler time to join its batch. Once batches flow the
// followers accumulating during each round trip carry the coalescing, so this
// only pays out at the very start and end of a demand burst; kept far below a
// WAN round trip so a lone fetch is barely delayed.
const DEMAND_BATCH_LINGER: Duration = Duration::from_millis(3);
// Failed fetches retry much sooner than definitive not-found: the server
// answers UNAVAILABLE while it builds a large namespace's snapshot index,
// and timeouts/transport errors are transient by the same token.
const SNAPSHOT_ERROR_RETRY_INTERVAL: Duration = Duration::from_secs(60);
const SNAPSHOT_IDLE_EVICT: Duration = Duration::from_secs(60 * 60);
const SNAPSHOT_MAX_INSTANCES: usize = 8;

// How long after the last CAS operation the machine still counts as busy. A
// build's traffic arrives in bursts with gaps between them (a link step, a test
// run, the developer reading a diagnostic), so a short window would read those
// gaps as idle and start competing with the build it is meant to stay out of.
const BUSY_AFTER_LAST_OP: Duration = Duration::from_secs(90);
// One-minute load average per core above which the machine counts as busy. The
// one-minute figure is the shortest the kernel keeps, so it already lags a
// burst; staying under 1.0 keeps a core's worth of headroom for the developer.
const BUSY_LOAD_PER_CORE: f64 = 0.6;
// How often to say we are holding off. The tick is every 10s, so an unthrottled
// line would bury the log through a long build.
const BUSY_LOG_INTERVAL: Duration = Duration::from_secs(5 * 60);

/// Why a machine in this state is too busy for background snapshot work, or
/// None when it is free enough. `idle` is the time since the last CAS operation
/// (None when no path has served one yet). Pure so the policy is unit-testable.
fn busy_verdict(idle: Option<Duration>, load_per_core: Option<f64>) -> Option<String> {
    if let Some(idle) = idle {
        if idle < BUSY_AFTER_LAST_OP {
            return Some(format!("a build was active {}s ago", idle.as_secs()));
        }
    }
    match load_per_core {
        Some(load) if load > BUSY_LOAD_PER_CORE => Some(format!("load is {load:.2} per core")),
        _ => None,
    }
}

/// The one-minute load average per core, or None if the platform will not say.
fn load_per_core() -> Option<f64> {
    let mut averages = [0f64; 3];
    // SAFETY: getloadavg fills at most `nelem` entries of an array we own, and
    // returns how many it wrote (-1 if it cannot).
    let written = unsafe { libc::getloadavg(averages.as_mut_ptr(), 1) };
    if written < 1 {
        return None;
    }
    let cores = std::thread::available_parallelism().ok()?.get() as f64;
    Some(averages[0] / cores)
}

/// The snapshot delta cadence, honoring TUIST_CAS_SNAPSHOT_DELTA_INTERVAL
/// (seconds) and falling back to SNAPSHOT_DELTA_INTERVAL_DEFAULT_SECS.
fn snapshot_delta_interval() -> Duration {
    std::env::var("TUIST_CAS_SNAPSHOT_DELTA_INTERVAL")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .map(Duration::from_secs)
        .unwrap_or(Duration::from_secs(SNAPSHOT_DELTA_INTERVAL_DEFAULT_SECS))
}
// The bulk-warm budget, in value-graph nodes (each node is one blob fetch).
// Sized past the largest closure a single build replays (~37.5k on the CLI
// fixture) so a right-sized namespace still warms completely.
const PREMATERIALIZE_MAX_NODES: usize = 60_000;

/// The bulk-warm budget, overridable for the full-ingestion layer: `0` lifts
/// the cap entirely so the whole (trunk-scoped) snapshot is materialized into
/// the local CAS ahead of any build. Default keeps the shipped bound.
fn prematerialize_max_nodes() -> usize {
    std::env::var("TUIST_CAS_PREMATERIALIZE_NODES")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(PREMATERIALIZE_MAX_NODES)
}

/// Whether to fully ingest a trunk-scoped snapshot into the local CAS ahead of
/// the build, rather than warming only the newest `PREMATERIALIZE_MAX_NODES`.
///
/// On by default where it is affordable and where it pays: the scoping bounds
/// the warm to the project's trunk closure instead of a whole shared namespace,
/// the warm runs off any build's critical path, it is idempotent (objects
/// already on disk are skipped, so steady state only fetches the delta a new
/// trunk snapshot introduced), and Xcode's own size-LRU bounds the store it
/// lands in. Measured on a mastodon-sized project: ~12s of off-path fetching
/// turns a from-scratch trunk build from ~57s into ~33s at 50ms RTT, cutting
/// demand stalls ~14x.
///
/// `TUIST_CAS_INGEST_TRUNK=0` opts out, for a metered or slow link where
/// pulling the trunk closure up front is not worth it.
/// Suffix of the file that carries a spool record's publish tags. Both this
/// proxy's `sweep` and the plugin's own `sweep_spool` walk the spool directory
/// and must skip it.
pub const TAGS_SUFFIX: &str = ".tags";

/// The sidecar path for a record, keyed off the base name so it is still found
/// once a sweeper has claimed the record as `<base>.claim-<pid>`.
fn tags_path(record_path: &str) -> std::path::PathBuf {
    let path = std::path::Path::new(record_path);
    let name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or_default();
    let base = name.split_once(".claim-").map(|(b, _)| b).unwrap_or(name);
    path.with_file_name(format!("{base}{TAGS_SUFFIX}"))
}

/// `branch\ntrunk`, where an empty field encodes `None`. Neither resolver can
/// yield an empty branch name, so the round trip is lossless: the same encoding
/// the publish queue item uses.
fn encode_tags(branch: &str, trunk: &str) -> Vec<u8> {
    format!("{branch}\n{trunk}").into_bytes()
}

fn decode_tags(bytes: &[u8]) -> Option<(String, String)> {
    let contents = std::str::from_utf8(bytes).ok()?;
    let (branch, trunk) = contents.split_once('\n')?;
    Some((branch.to_string(), trunk.to_string()))
}

/// Deletes a spool record and the tags written beside it. A leaked sidecar
/// would be read back by whatever record later reuses that name.
fn remove_record(record_path: &str) {
    let _ = std::fs::remove_file(record_path);
    let _ = std::fs::remove_file(tags_path(record_path));
}

fn ingest_trunk_enabled() -> bool {
    std::env::var("TUIST_CAS_INGEST_TRUNK").as_deref() != Ok("0")
}
// View refresh: per-key hits taken while a snapshot was Ready get their
// manifests re-published in the background (see Proxy.view_refresh). The
// per-tick batch keeps a full cold build's backlog (~10k keys) draining in
// well under an hour without contending with the build's own traffic; the
// queue cap bounds memory if the server never accepts them.
const VIEW_REFRESH_PER_TICK: usize = 100;
const VIEW_REFRESH_MAX_QUEUE: usize = 50_000;

/// How long a cached miss is served before it is re-resolved. Positive results
/// are content-addressed and kept forever; only negatives expire, so a key
/// published by another machine after our miss becomes visible on the next
/// resolve past this window rather than requiring a proxy restart.
const NEGATIVE_TTL: Duration = Duration::from_secs(60);

/// How long a path may go without a request before its in-memory caches are
/// reclaimed by the maintenance loop. Well beyond a build's internal pauses
/// (planning gaps, incremental rebuilds), so an actively-built project is never
/// reclaimed mid-work; a reclaimed path just re-warms from the remote on its
/// next build. Bounds the RAM a long-lived proxy holds for projects nobody is
/// building, which the size caps alone never release.
const IDLE_RECLAIM: Duration = Duration::from_secs(30 * 60);

/// A cached resolve outcome for a key.
enum Resolution {
    /// A value digest, kept indefinitely (content-addressed, always valid).
    Hit(Vec<u8>),
    /// A miss, with the time it was cached so it can expire (see NEGATIVE_TTL).
    Miss(Instant),
}

/// The pre-single-flight cache decision for a key (see `fast_path`).
enum FastPath {
    /// Serve this value digest: a cached Hit whose value object is still on disk.
    Hit(Vec<u8>),
    /// Serve a fresh negative: a cached Miss still inside NEGATIVE_TTL.
    Miss,
    /// Fall through to a full (re-)resolve under single-flight.
    Resolve,
}

/// Decides what to serve for `key` from the resolved map before entering
/// single-flight. A cached Hit is served ONLY when `present` confirms its value
/// object is still on disk; a Hit whose object is gone (the local CAS was wiped
/// by `xcodebuild clean` or a deleted DerivedData under this long-lived proxy)
/// calls `invalidate` and returns `Resolve`, so the graph is re-materialized
/// instead of handing the compiler a value whose blobs no longer exist (which
/// surfaces as `CAS error: missing object` in the frontend). Kept free of the
/// FFI presence load and of `PathState` so the guard is unit-testable: the map
/// is snapshotted and its lock released before `present` runs, both so the load
/// never serializes other keys and so a Hit can be probed off-lock.
fn fast_path(
    resolved: &Mutex<HashMap<Vec<u8>, Resolution>>,
    key: &[u8],
    present: impl FnOnce(&[u8]) -> bool,
    invalidate: impl FnOnce(),
) -> FastPath {
    let value = {
        let map = resolved.lock().unwrap();
        match map.get(key) {
            Some(Resolution::Hit(value)) => value.clone(),
            Some(Resolution::Miss(at)) if at.elapsed() < NEGATIVE_TTL => return FastPath::Miss,
            _ => return FastPath::Resolve,
        }
    };
    if present(&value) {
        FastPath::Hit(value)
    } else {
        invalidate();
        FastPath::Resolve
    }
}

/// Whether a path's in-memory caches should be reclaimed: its on-disk CAS is
/// gone (deleted project/worktree — it never comes back) or it has been idle
/// past IDLE_RECLAIM. Pure so the policy is unit-testable.
fn should_reclaim(idle: Duration, cas_dir_gone: bool) -> bool {
    cas_dir_gone || idle > IDLE_RECLAIM
}

/// A cheap identity for the on-disk CAS directory. When it changes, the
/// directory was deleted and recreated (`xcodebuild clean` / a deleted
/// DerivedData) under this long-lived proxy, so the in-memory `known_local` and
/// `resolved` marks now describe a store that no longer exists on disk.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
struct CasGeneration {
    ino: u64,
    // Birth time in nanos since the Unix epoch; 0 when the platform can't report
    // it. Guards the (very unlikely) inode reuse when a directory is recreated.
    birth_nanos: u128,
}

/// The CAS directory's current generation, or `None` if it does not exist
/// (deleted and not yet recreated).
fn cas_generation(cas_path: &str) -> Option<CasGeneration> {
    let meta = std::fs::metadata(cas_path).ok()?;
    let birth_nanos = meta
        .created()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    Some(CasGeneration {
        ino: meta.ino(),
        birth_nanos,
    })
}

/// Whether the CAS directory changed identity between two observations, i.e. it
/// was recreated (a wipe). A `None` current generation (the directory is gone)
/// is not a change: a resolve can't run against a missing store anyway, and
/// `reclaim_idle` drops such a path's marks; a `None` stored generation is the
/// first observation. Pure so the wipe policy is unit-testable.
fn generation_changed(stored: Option<CasGeneration>, current: Option<CasGeneration>) -> bool {
    matches!((stored, current), (Some(prev), Some(now)) if prev != now)
}

/// Per-local-CAS-path state. Leaked for 'static lifetime: the proxy runs
/// until killed.
pub struct PathState {
    up: &'static Upstream,
    // The handle addressing the store at `cas_path`. Behind a lock because it
    // is REBOUND when the directory is wiped and recreated: an llcas handle
    // holds the store's files open, so after an `rm -rf DerivedData` the old
    // handle keeps answering from the deleted directory's still-open inodes --
    // reads report objects the compiler cannot see, and writes land where
    // nothing will ever read them. Readers hold the guard across their whole
    // FFI call so a swap can never dispose a handle mid-use.
    cas: RwLock<llcas_cas_t>,
    // The on-disk CAS directory this state wraps, kept so a resolve can restat
    // it for wipe detection (see `generation`).
    cas_path: String,
    // Identity of the CAS directory as last observed by a resolve. A change means
    // the store was deleted and recreated under this long-lived proxy, so the
    // in-memory marks below are stale and must be dropped before they are trusted.
    generation: Mutex<Option<CasGeneration>>,
    // Monotonic counter bumped by every invalidation (a detected wipe or a prune
    // signal). A resolve snapshots it after its wipe check and only commits its
    // known_local / resolved writes if it is unchanged, so a resolve that began
    // under an older store can't reinsert stale marks after the maps were cleared.
    gen_counter: AtomicU64,
    // key digest -> resolved outcome. A local publish updates its entry, so a
    // miss cached during planning turns into a hit once the local build
    // publishes it; misses also carry a timestamp so a key another machine
    // publishes later (overnight CI is the typical writer) stops being served
    // as a miss after NEGATIVE_TTL instead of until the proxy restarts.
    resolved: Mutex<HashMap<Vec<u8>, Resolution>>,
    // Single-flight: concurrent resolves of the same key (the build system
    // plans while the compiler asks) wait for the first instead of
    // duplicating manifest + fetch work.
    inflight: Mutex<HashSet<Vec<u8>>>,
    inflight_cvar: Condvar,
    // Sharded: this set is checked once per manifest entry (~1.9M times per
    // warm build) from every connection thread.
    known_local: [Mutex<HashSet<Vec<u8>>>; 32],
    publish_cache: Mutex<HashMap<Vec<u8>, (reapi::Digest, Vec<Vec<u8>>)>>,
    // Millis since Proxy.epoch of the last request that touched this path, for
    // idle reclamation. Bumped once per resolve/publish (per action key, not per
    // node), so the maintenance loop can free caches of projects nobody builds.
    last_used: AtomicU64,
    // llcas digest -> how to fetch its frame blob, for every node of every
    // value graph this proxy has answered. Inserted right after get_action
    // (before the resolve replies); once a node is stored locally its inlined
    // bytes are dropped but the digest-only instruction is RETAINED — the
    // build system prunes the on-disk CAS mid-build, and a pruned object
    // under an already-served Hit must stay producible through
    // OP_FETCH_OBJECT (clang fails the build on a missing object). Entries
    // are content-addressed (valid across invalidations and wipes), ~100B
    // each, and capped at MAX_PENDING_OBJECTS by `enforce_cache_bounds`;
    // anything dropped is reconstructible from the instance snapshot in
    // `fetch_object`.
    pending_objects: Mutex<HashMap<Vec<u8>, PendingFetch>>,
    pub stats_resolves: AtomicU64,
    pub stats_remote_hits: AtomicU64,
    pub stats_misses: AtomicU64,
    // Keys answered from the instance's action-cache snapshot (no remote
    // lookup at all).
    pub stats_snapshot_hits: AtomicU64,
    // Objects served through OP_FETCH_OBJECT because a demand load outran the
    // background materializer (or a prune removed a node under a served Hit).
    pub stats_demand_fetched: AtomicU64,
    pub stats_blobs_fetched: AtomicU64,
    // Blobs that arrived inlined in the GetActionResult response instead of
    // through a separate BatchReadBlobs round-trip (kura's
    // `inline_output_files: ["*"]` extension).
    pub stats_blobs_inlined: AtomicU64,
    pub stats_published: AtomicU64,
    pub ms_action: AtomicU64,
    pub ms_filter: AtomicU64,
    pub ms_fetch: AtomicU64,
    pub ms_decode: AtomicU64,
    pub ms_store: AtomicU64,
}

/// Fetch instructions for one value-graph node: enough to produce the object
/// on demand without re-resolving its action key.
#[derive(Clone)]
struct PendingFetch {
    blob: reapi::Digest,
    /// Frame bytes the server inlined into the action response; `None` means
    /// the blob must be batch-read.
    contents: Option<Vec<u8>>,
}

/// A value graph whose Hit was already answered; the fetch+store work runs on
/// the materializer pool.
struct MaterializeJob {
    cas_path: String,
    remote: Arc<Remote>,
    manifest: Vec<ManifestEntry>,
    observed: u64,
}

/// The instance's complete action-cache map, fetched from the remote in ONE
/// round trip (the Bazel move — complete metadata up front — taken further:
/// Bazel still pays a GetActionResult per action, this answers every one
/// locally). Keys map to node-index lists into a deduplicated node table;
/// index order preserves the ActionResult's output order, so a key's first
/// node is its value root. Makes a completely cold machine — no keylog, no
/// prior build, an agentic sandbox — resolve like a warm one.
#[derive(Clone)]
pub struct Snapshot {
    nodes: Vec<(Vec<u8>, reapi::Digest)>,
    // llcas digest -> index into `nodes`, kept so delta responses (which carry
    // self-contained node tables) can be merged without duplicating nodes.
    node_index: HashMap<Vec<u8>, u32>,
    keys: HashMap<[u8; 32], Vec<u32>>,
    /// Key hashes in wire order. The server encodes full views newest-first,
    /// so this is the pre-materialization priority: on a shared namespace the
    /// snapshot carries every project's history, and warming it in hash order
    /// pulled ~6x this build's content over the WAN before the keys the build
    /// actually needed (the just-published ones, i.e. the newest) were warm.
    key_order: Vec<[u8; 32]>,
    /// Newest write time the server knew when this view was produced; passed
    /// back as the delta watermark on refresh.
    watermark: u64,
}

/// Per-instance snapshot lifecycle. The initial fetch happens in the
/// background off every resolve path; the maintenance loop then keeps a Ready
/// snapshot fresh with deltas, replaces it wholesale on a longer cadence
/// (deltas only ADD — the periodic full fetch is what re-applies the server's
/// presence gate after evictions), retries Absent occasionally (the server
/// may have been upgraded under a long-lived proxy), and bounds the cache by
/// evicting idle instances. While `Fetching` or `Absent`, resolves use the
/// ordinary per-key path.
enum SnapshotState {
    Fetching,
    Ready {
        snapshot: Arc<Snapshot>,
        full_at: Instant,
        refreshed_at: Instant,
        last_used: Instant,
    },
    Absent {
        checked: Instant,
        /// How long to sit on the per-key path before refetching. An hour
        /// when the server definitively has no snapshot support (not-found);
        /// one minute when the fetch ERRORED — errors are transient by
        /// nature (kura answers UNAVAILABLE while a large namespace's
        /// first-ever index build runs, and it completes within a few of
        /// these ticks), and an hour of per-key traffic was the cost of
        /// treating them as permanent.
        retry_after: Duration,
    },
}

impl Snapshot {
    /// Decodes the server's snapshot response. A `"TSNZ"` envelope (magic,
    /// version byte, u64 uncompressed length, zstd stream) — what current kura
    /// always emits — is decompressed into a `"TSNP"` body first; a bare
    /// `"TSNP"` body, which only an OLD kura pod emits (mid mesh-roll, or a
    /// lagging self-hosted node), is decoded directly. Any structural violation
    /// returns `None` and the caller stays on the per-key path rather than
    /// trusting a torn payload.
    fn decode(bytes: &[u8]) -> Option<Snapshot> {
        if bytes.len() >= 13 && &bytes[..4] == b"TSNZ" {
            if bytes[4] != 1 {
                return None;
            }
            let declared = u64::from_le_bytes(bytes[5..13].try_into().ok()?) as usize;
            if declared > SNAPSHOT_DECOMPRESS_MAX_BYTES {
                return None;
            }
            // Decode the stream through a reader capped at `declared + 1` bytes,
            // so a payload whose stream expands PAST its declared length (a zip
            // bomb, or a corrupt frame) is rejected after one extra byte rather
            // than allocating unboundedly. `decode_all` expands the whole stream
            // into a Vec first — the length check below never gets to run. The
            // cap is `declared + 1 <= SNAPSHOT_DECOMPRESS_MAX_BYTES + 1`, so the
            // allocation is bounded regardless of what the stream claims.
            use std::io::Read as _;
            let mut decoder = zstd::stream::read::Decoder::new(&bytes[13..]).ok()?;
            let mut body = Vec::new();
            decoder
                .take(declared as u64 + 1)
                .read_to_end(&mut body)
                .ok()?;
            if body.len() != declared {
                return None;
            }
            return Self::decode_body(&body);
        }
        Self::decode_body(bytes)
    }

    /// Decodes a bare `"TSNP"` body: `"TSNP"` + version byte, u64 write-time
    /// watermark, node table, per-key node-index lists.
    fn decode_body(bytes: &[u8]) -> Option<Snapshot> {
        fn take<'a>(bytes: &mut &'a [u8], n: usize) -> Option<&'a [u8]> {
            if bytes.len() < n {
                return None;
            }
            let (head, tail) = bytes.split_at(n);
            *bytes = tail;
            Some(head)
        }
        fn take_u32(bytes: &mut &[u8]) -> Option<u32> {
            Some(u32::from_le_bytes(take(bytes, 4)?.try_into().ok()?))
        }
        let mut bytes = bytes;
        if take(&mut bytes, 4)? != b"TSNP" || take(&mut bytes, 1)? != [2] {
            return None;
        }
        let watermark = u64::from_le_bytes(take(&mut bytes, 8)?.try_into().ok()?);
        let node_count = take_u32(&mut bytes)? as usize;
        let mut nodes = Vec::with_capacity(node_count);
        for _ in 0..node_count {
            let len = take(&mut bytes, 1)?[0] as usize;
            let llcas = take(&mut bytes, len)?.to_vec();
            let blob_hash = take(&mut bytes, 32)?;
            let size = u64::from_le_bytes(take(&mut bytes, 8)?.try_into().ok()?);
            nodes.push((
                llcas,
                reapi::Digest {
                    hash: reapi::hex(blob_hash),
                    size_bytes: size as i64,
                },
            ));
        }
        let key_count = take_u32(&mut bytes)? as usize;
        let mut keys = HashMap::with_capacity(key_count);
        let mut key_order = Vec::with_capacity(key_count);
        for _ in 0..key_count {
            let action_hash: [u8; 32] = take(&mut bytes, 32)?.try_into().ok()?;
            let entry_count = take_u32(&mut bytes)? as usize;
            let mut indexes = Vec::with_capacity(entry_count);
            for _ in 0..entry_count {
                let index = take_u32(&mut bytes)?;
                if index as usize >= nodes.len() {
                    return None;
                }
                indexes.push(index);
            }
            if indexes.is_empty() {
                return None;
            }
            keys.insert(action_hash, indexes);
            key_order.push(action_hash);
        }
        let node_index = nodes
            .iter()
            .enumerate()
            .map(|(index, (llcas, _))| (llcas.clone(), index as u32))
            .collect();
        Some(Snapshot {
            nodes,
            node_index,
            keys,
            key_order,
            watermark,
        })
    }

    /// Merges a delta view into this one: delta node tables are
    /// self-contained, so nodes are interned by llcas digest and the delta's
    /// keys are remapped onto this snapshot's table. Deltas only add or
    /// replace keys — retraction happens through the periodic full refresh.
    fn merge(&mut self, delta: &Snapshot) {
        let mut remap = Vec::with_capacity(delta.nodes.len());
        for (llcas, blob) in &delta.nodes {
            let index = *self.node_index.entry(llcas.clone()).or_insert_with(|| {
                self.nodes.push((llcas.clone(), blob.clone()));
                (self.nodes.len() - 1) as u32
            });
            remap.push(index);
        }
        let mut fresh_order = Vec::new();
        for (hash, indexes) in &delta.keys {
            if self
                .keys
                .insert(
                    *hash,
                    indexes.iter().map(|&index| remap[index as usize]).collect(),
                )
                .is_none()
            {
                fresh_order.push(*hash);
            }
        }
        // Delta keys are the newest this snapshot knows; keep them at the
        // front of the warm priority.
        self.key_order.splice(0..0, fresh_order);
        self.watermark = self.watermark.max(delta.watermark);
    }

    /// The manifest for an action key's sha256, if the snapshot holds it.
    fn manifest(&self, key_hash: &[u8; 32]) -> Option<Vec<ManifestEntry>> {
        let indexes = self.keys.get(key_hash)?;
        Some(
            indexes
                .iter()
                .map(|&index| {
                    let (llcas, blob) = &self.nodes[index as usize];
                    ManifestEntry {
                        llcas_digest: llcas.clone(),
                        blob: blob.clone(),
                        contents: None,
                    }
                })
                .collect(),
        )
    }
}

impl PathState {
    fn shard(&self, digest: &[u8]) -> &Mutex<HashSet<Vec<u8>>> {
        &self.known_local[digest.first().copied().unwrap_or(0) as usize % 32]
    }

    /// Whether a demand load could still produce this digest even though it is
    /// not (yet) on disk: its fetch instructions are registered, so serving a
    /// Hit that references it is safe.
    fn fetchable(&self, digest: &[u8]) -> bool {
        self.pending_objects.lock().unwrap().contains_key(digest)
    }

    /// Drops all cached knowledge of the on-disk CAS for this path: the
    /// resolved key->value map and the known-local shard sets. Called when a
    /// cached Hit's value object is found missing from disk (`xcodebuild clean`
    /// or a deleted DerivedData wiped the local CAS under this long-lived
    /// proxy), so the re-resolve re-probes every manifest entry authoritatively
    /// and re-materializes the full graph rather than trusting stale in-memory
    /// marks. Content-addressed and correctness-preserving, so clearing only
    /// forces re-work, never a wrong answer.
    ///
    /// The counter is bumped BEFORE the maps are cleared so that a concurrent
    /// in-flight resolve (which checks the counter while holding the same map
    /// lock it is about to write) either sees the new counter and skips its
    /// write, or writes first and then has it cleared here — never inserts a
    /// stale mark that survives the clear.
    fn invalidate(&self) {
        self.gen_counter.fetch_add(1, Ordering::SeqCst);
        // Only the known-local marks are cleared. They are trusted WITHOUT an
        // on-disk probe (they make resolve skip fetching manifest nodes), so a
        // stale mark hands a consumer a graph with missing objects. The
        // `resolved` key->value map is deliberately KEPT: every cached Hit is
        // re-verified on disk before it is served (see `fast_path`'s
        // `load_present` guard), so pruned or wiped values self-heal per key.
        // Clearing it wholesale meant one mid-build prune signal threw away
        // the read-ahead wavefront's work and sent every later lookup back to
        // the remote (measured: ~2x the remote round trips of the key set).
        // Keeping it is only safe while that guard probes the store the
        // consumer reads: a wipe must rebind the handle (see `reopen_cas`)
        // BEFORE this runs, or every retained Hit is re-verified against the
        // deleted store and served as a `missing object` build failure.
        for shard in &self.known_local {
            shard.lock().unwrap().clear();
        }
        // `pending_objects` is also KEPT: entries are content-addressed fetch
        // instructions, valid for any incarnation of the store — after a wipe
        // they let demand loads refill exactly what is asked for.
    }

    /// Rebinds `cas` to the store that now lives at `cas_path`, releasing the
    /// handle to the previous one. Called when a wipe is detected: an llcas
    /// handle keeps the store's files open, so a deleted directory's inodes stay
    /// alive and reachable THROUGH THAT HANDLE ALONE. Everything the proxy does
    /// with it afterwards addresses a store no other process can see -- and
    /// silently: the reads answer SUCCESS and the writes report success.
    /// Dropping the marks is not enough on its own, because `load_present`
    /// re-learns them from that same handle.
    ///
    /// The fresh handle is opened before the lock is taken, so a failure leaves
    /// the existing one in place; the stale handle is disposed only once the
    /// swap holds the write lock, where no thread can be inside a call with it.
    /// Disposing (rather than leaking) also lets go of the deleted store's
    /// inodes, which is what actually returns the disk the user meant to free.
    fn reopen_cas(&self) -> Result<(), String> {
        let fresh = unsafe { open_cas(self.up, &self.cas_path)? };
        let mut cas = self.cas.write().unwrap();
        let stale = std::mem::replace(&mut *cas, fresh);
        unsafe { (self.up.llcas_cas_dispose)(stale) };
        Ok(())
    }

    /// Authoritative on-disk presence for `digest`: an actual llcas load, the
    /// same call the consumer will make, bypassing the known-local cache. Used
    /// both by `is_local` (which memoizes a positive result) and to guard a
    /// cached Hit against a wiped local CAS, where the in-memory marks lie.
    /// Only as authoritative as the handle is current -- see `reopen_cas`.
    fn load_present(&self, digest: &[u8]) -> bool {
        // Held across the probe: a concurrent `reopen_cas` must not dispose the
        // handle between the objectid lookup and the containment check.
        let cas = self.cas.read().unwrap();
        unsafe {
            let digest_t = llcas_digest_t {
                data: digest.as_ptr(),
                size: digest.len(),
            };
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut std::ffi::c_char = std::ptr::null_mut();
            if (self.up.llcas_cas_get_objectid)(*cas, digest_t, &mut id, &mut error) {
                if !error.is_null() {
                    (self.up.llcas_string_dispose)(error);
                }
                return false;
            }
            // Existence check, not a data load: this runs once per served hit
            // and once per manifest-entry probe, so loading object bytes here
            // put real I/O on the resolve path (thousands of loads per warm
            // build). A wiped or pruned store answers NOTFOUND either way,
            // which is all the stale-hit guard needs.
            let mut contains_error: *mut std::ffi::c_char = std::ptr::null_mut();
            let result =
                (self.up.llcas_cas_contains_object)(*cas, id, false, &mut contains_error);
            if !contains_error.is_null() {
                (self.up.llcas_string_dispose)(contains_error);
            }
            result == LLCAS_LOOKUP_RESULT_SUCCESS
        }
    }
}

/// Whether writes from a resolve that observed generation `observed` may still
/// be committed: only if no wipe or prune advanced the path's `gen_counter`
/// since. A stale resolve's known_local / resolved inserts describe a store that
/// has been replaced, so they must be dropped rather than trusted.
fn committable(observed: u64, current: u64) -> bool {
    observed == current
}

// The proxy is single-process and owns these raw handles for its lifetime;
// the llcas API is thread-safe (the same handles are shared across worker
// threads inside compiler processes too).
unsafe impl Send for PathState {}
unsafe impl Sync for PathState {}

/// One queued view refresh: the instance's client, the action key, and the
/// manifest to re-publish.
/// A per-key hit queued for background re-publish, with the tags bound when it
/// was queued rather than when it drains: the drain runs on a maintenance tick,
/// by which point the checkout may have moved.
struct ViewRefresh {
    remote: Arc<Remote>,
    key: Vec<u8>,
    manifest: Vec<ManifestEntry>,
    branch: Option<String>,
    trunk: Option<String>,
    /// Carried so a refresh that never happens can release its claim.
    dedup: RefreshKey,
}

/// What makes a refresh distinct: the instance it belongs to, the action, and the
/// tags it would write.
///
/// All four matter. The key alone collides across projects, and it collides
/// across branches, which is worse: a feature build refreshing a key would
/// suppress the later trunk hit for it, for the proxy's lifetime, and that hit is
/// the only thing that reclaims the entry into the trunk view.
type RefreshKey = (String, Vec<u8>, Option<String>, Option<String>);

/// Result of a coalesced demand fetch, taken by exactly one waiter.
enum DemandResult {
    Present(Vec<u8>),
    Missing,
    Failed(String),
}

/// Coalesces concurrent single-object demand fetches (OP_FETCH_OBJECT, one per
/// compiler worker that outran the materializer) into shared `BatchReadBlobs`
/// calls. A demand build fetched ~7000 objects one round trip each over the
/// WAN; the RTT, not bandwidth, dominated that time. Compiler workers issue
/// their misses in parallel, so a leader drains everything pending into one
/// batch while followers accumulate during its round trip — the batch size
/// self-clocks to the worker concurrency with no fixed wait.
#[derive(Default)]
struct DemandBatch {
    /// Digests waiting to be fetched, deduped by hash.
    pending: HashMap<String, reapi::Digest>,
    /// Fetched results keyed by hash; each removed by the waiter that wanted it.
    results: HashMap<String, DemandResult>,
    /// Whether a leader is currently draining/fetching.
    leader_active: bool,
}

struct DemandCoalescer {
    batch: Mutex<DemandBatch>,
    ready: Condvar,
}

impl DemandCoalescer {
    fn new() -> DemandCoalescer {
        DemandCoalescer {
            batch: Mutex::new(DemandBatch::default()),
            ready: Condvar::new(),
        }
    }

    /// Fetches one blob, coalescing with concurrent callers into shared batch
    /// reads. `fetch_batch` performs the actual multi-blob read; only the
    /// leader of each batch invokes it, and every caller passes the same
    /// closure (a read against the shared remote), so which thread leads does
    /// not matter. Blocking here is free: the caller is a compiler worker
    /// thread that a demand load already parks on network I/O.
    ///
    /// Each result is a one-shot mailbox consumed by the first thread to read
    /// it, so two threads demanding the SAME digest concurrently may each
    /// fetch it — a rare redundant read, never a wrong or dropped result.
    fn fetch<F>(&self, digest: &reapi::Digest, fetch_batch: F) -> Result<Option<Vec<u8>>, String>
    where
        F: Fn(&[reapi::Digest]) -> Result<HashMap<String, Vec<u8>>, String>,
    {
        let hash = digest.hash.clone();
        let mut batch = self.batch.lock().unwrap();
        loop {
            if let Some(result) = batch.results.remove(&hash) {
                // Drop any pending entry we (or a same-hash sibling) registered
                // but that another leader's fetch already satisfied — otherwise
                // it lingers and a later batch re-fetches it, leaking its result.
                batch.pending.remove(&hash);
                return match result {
                    DemandResult::Present(bytes) => Ok(Some(bytes)),
                    DemandResult::Missing => Ok(None),
                    DemandResult::Failed(message) => Err(message),
                };
            }
            batch.pending.insert(hash.clone(), digest.clone());
            if batch.leader_active {
                // A leader is draining/fetching; wait for it to fill results.
                batch = self.ready.wait(batch).unwrap();
                continue;
            }
            // Lead this batch. If alone, linger briefly so a near-simultaneous
            // straggler can join; once batches flow the accumulation during the
            // previous round trip means we are rarely alone.
            batch.leader_active = true;
            if batch.pending.len() == 1 {
                drop(batch);
                std::thread::sleep(DEMAND_BATCH_LINGER);
                batch = self.batch.lock().unwrap();
            }
            let digests: Vec<reapi::Digest> = batch.pending.values().cloned().collect();
            let hashes: Vec<String> = batch.pending.keys().cloned().collect();
            batch.pending.clear();
            drop(batch);

            // Network round trip outside the lock so followers keep queueing.
            let fetched = fetch_batch(&digests);

            batch = self.batch.lock().unwrap();
            match fetched {
                Ok(mut map) => {
                    for hash in hashes {
                        let result = match map.remove(&hash) {
                            Some(bytes) => DemandResult::Present(bytes),
                            None => DemandResult::Missing,
                        };
                        batch.results.insert(hash, result);
                    }
                }
                Err(message) => {
                    for hash in hashes {
                        batch
                            .results
                            .insert(hash, DemandResult::Failed(message.clone()));
                    }
                }
            }
            batch.leader_active = false;
            self.ready.notify_all();
            // Loop: our own hash is now in results (or a follower took it and
            // we re-enqueue for the next batch — correct either way).
        }
    }
}

/// What setup recorded for an instance, memoized on a TTL so a publish does not
/// re-read the registry file.
struct SourceContext {
    read_at: Instant,
    trunk: Option<String>,
    ci_branch: Option<String>,
    upload: bool,
}

/// How long a recorded context is reused before the proxy re-reads the registry,
/// so a project set up after startup is picked up within seconds.
const GIT_CONTEXT_TTL: Duration = Duration::from_secs(15);

/// The (branch, trunk) pair `source_context` resolves, cloned out from under the
/// cache lock.
struct SourceBranches {
    branch: Option<String>,
    trunk: Option<String>,
    upload: bool,
}

/// What `tuist setup cache` recorded for an instance.
///
/// Note what is NOT here: the checkout. Nothing about a publish is read from the
/// working copy any more, which is what makes a moved, renamed, or duplicated one
/// unable to mis-attribute a build. Setup still writes the source root into the
/// registry's second column and this deliberately ignores it, so a proxy from
/// before this change keeps parsing the columns after it.
struct RegisteredSource {
    /// The branch `tuist setup cache` saw in the CI job's environment, recorded
    /// ONLY on CI. A launchd agent does not inherit the job's environment, so the
    /// provider's branch variable is unreachable from here and the command inside
    /// the job has to hand it over.
    ///
    /// `None` off CI, and that is the design rather than a gap: the snapshot is
    /// what trunk looks like as CI built it, so CI is the only publisher whose
    /// branch has to be right. A local publish goes out untagged, stays out of
    /// every trunk view, and is still stored and served per key.
    ci_branch: Option<String>,
    /// The project's default branch, as the server knows it. Which branch is
    /// trunk is a property of the project, not of how this machine happened to
    /// clone it (a fork, a mirror, or a clone whose remote head was never set all
    /// get it wrong locally). `None` when setup could not reach the server, which
    /// means no scoping: what a client too old to ask for it already gets.
    trunk: Option<String>,
    /// The project's `xcodeCache.upload`.
    ///
    /// The plugin checks this too, from a compiler option, but that option only
    /// reaches Swift: swift-build's `CASOptions` carries a plugin PATH and no
    /// plugin options, so the CAS it creates for its Clang caching has no idea
    /// what the project asked for and defaults to uploading. The proxy is the
    /// only place that sees both lanes, so it is where the policy is enforced.
    upload: bool,
}

pub struct Proxy {
    grpc_url: String,
    tokens: Arc<TokenProvider>,
    upstream_plugin: String,
    // Monotonic base for per-path last-used timestamps (see PathState.last_used).
    epoch: Instant,
    // One REAPI client per account/project instance, created on first use.
    // All share the machine's endpoint + token; only the instance the request
    // is scoped to differs. This is what lets one proxy serve every project.
    remotes: Mutex<HashMap<String, Arc<Remote>>>,
    // cas_path -> instance, primed by builds that declare their instance and
    // persisted so an Xcode ⌘B build (which declares none) still routes after
    // a proxy restart. See proxy_proto for why the fallback exists.
    path_instance: Mutex<HashMap<String, String>>,
    registry_path: Option<PathBuf>,
    // instance -> the project's source root, registered by `tuist setup cache`
    // (the per-project step that installs this proxy). The branch and trunk a
    // publish is tagged with are derived live from this repo's git HEAD, so a
    // branch switch needs no re-setup and nothing branch-specific ever enters a
    // build setting (which could pollute the compile cache key).
    instance_sources: Mutex<HashMap<String, RegisteredSource>>,
    // Instances a build has touched since this proxy started; bounds trunk
    // ingestion to projects actually in use (see `instance_active`).
    active_instances: Mutex<HashSet<String>>,
    // instance -> the last git context read from its source root, refreshed on
    // a short TTL so per-publish tagging is a cache hit, not a git fork.
    source_cache: Mutex<HashMap<String, SourceContext>>,
    paths: Mutex<HashMap<String, &'static PathState>>,
    publisher: Prefetcher,
    // Resolves/publishes that arrived with no declared instance and no primed
    // registry mapping. They answer a silent miss by design (an unprimed ⌘B
    // build must degrade, not fail) — but a MISCONFIGURED build looks exactly
    // the same, so the count is logged (first occurrence, then every 1000th)
    // and surfaced in the stats line. A whole benchmark ran cache-less for a
    // day because this path had no visibility.
    unprimed: AtomicU64,
    // Background materializer for demand-path resolves: a RESOLVE from a
    // compiler answers with the value digest right after the action lookup
    // and this pool fetches + stores the graph. Kept OFF the wavefront path —
    // read-ahead workers materialize inline, which naturally bounds how much
    // fetched-but-unstored data sits in memory. Items are 8-byte job ids into
    // `materialize_jobs`.
    materializer: Prefetcher,
    // Bulk content warming straight from a freshly fetched snapshot, on its
    // own small pool so demand-priority materialization is never queued
    // behind it. Purely opportunistic: demand resolves answer from the
    // snapshot regardless and their loads self-heal per object.
    prematerializer: Prefetcher,
    materialize_jobs: Mutex<HashMap<u64, MaterializeJob>>,
    job_counter: AtomicU64,
    // instance -> action-cache snapshot lifecycle. Kicked off in the
    // background on an instance's first resolve; while it is in flight (or
    // when the server has none) resolves use the per-key path.
    snapshots: Mutex<HashMap<String, SnapshotState>>,
    // When we last said a refresh was held off for a busy machine (see
    // `log_busy`).
    busy_logged_at: Mutex<Option<Instant>>,

    // Keys answered by a per-key lookup while a snapshot was Ready: they fell
    // out of the server's size-capped wire view, which ranks by version — a
    // rank publish-dedup never refreshes, so a project's stable keys decay
    // out of the view and every cold machine pays a WAN round trip per key
    // (measured 165 of 10,676 resolves snapshot-served on a fresh index).
    // Re-publishing the fetched manifest bumps the entry back into the view,
    // so each cold build heals the view for the next machine. Drained a batch
    // per maintenance tick; deduped for the proxy's lifetime; the server damps
    // identical re-publishes of entries fresher than a day, so a fleet of
    // cold machines cannot stampede version bumps.
    view_refresh: Mutex<VecDeque<ViewRefresh>>,
    view_refreshed: Mutex<HashSet<RefreshKey>>,

    // instance -> demand-fetch coalescer, created on first demand miss. Groups
    // concurrent OP_FETCH_OBJECT blob reads into shared BatchReadBlobs calls.
    demand_coalescers: Mutex<HashMap<String, Arc<DemandCoalescer>>>,

    // Per-node transfer analytics, written to cas_analytics.db for parity with
    // the Swift `CASAnalyticsDatabase`. `None` when no analytics path was configured.
    analytics: Option<crate::analytics::Analytics>,
}

impl Proxy {
    pub fn new(
        grpc_url: String,
        tokens: Arc<TokenProvider>,
        upstream_plugin: String,
        registry_path: Option<PathBuf>,
        analytics: Option<crate::analytics::Analytics>,
    ) -> &'static Proxy {
        let path_instance = registry_path
            .as_deref()
            .map(load_registry)
            .unwrap_or_default();
        let proxy: &'static Proxy = Box::leak(Box::new(Proxy {
            grpc_url,
            tokens,
            upstream_plugin,
            epoch: Instant::now(),
            remotes: Mutex::new(HashMap::new()),
            path_instance: Mutex::new(path_instance),
            instance_sources: Mutex::new(
                registry_path
                    .as_deref()
                    .map(|path| load_sources(&sources_path_for(path)))
                    .unwrap_or_default(),
            ),
            source_cache: Mutex::new(HashMap::new()),
            registry_path,
            paths: Mutex::new(HashMap::new()),
            publisher: Prefetcher::new(),
            materializer: Prefetcher::new(),
            prematerializer: Prefetcher::new(),
            materialize_jobs: Mutex::new(HashMap::new()),
            job_counter: AtomicU64::new(0),
            snapshots: Mutex::new(HashMap::new()),
            busy_logged_at: Mutex::new(None),
            unprimed: AtomicU64::new(0),
            view_refresh: Mutex::new(VecDeque::new()),
            view_refreshed: Mutex::new(HashSet::new()),
            demand_coalescers: Mutex::new(HashMap::new()),
            active_instances: Mutex::new(HashSet::new()),
            analytics,
        }));
        let proxy_addr = proxy as *const Proxy as usize;
        proxy.publisher.configure(8, move |item| {
            let proxy = unsafe { &*(proxy_addr as *const Proxy) };
            proxy.publish_item(&item);
        });
        // Demand jobs arrive at the build engine's serial rate, so a small
        // pool keeps up; the wavefront's bulk work does not flow through here.
        proxy.materializer.configure(16, move |item| {
            let proxy = unsafe { &*(proxy_addr as *const Proxy) };
            proxy.materialize_job(&item);
        });
        proxy.prematerializer.configure(8, move |item| {
            let proxy = unsafe { &*(proxy_addr as *const Proxy) };
            proxy.materialize_job(&item);
        });
        proxy
    }

    /// The REAPI client for an instance, created and cached on first use.
    ///
    /// `instance` is the `account/project` full handle used to key the client
    /// map (two accounts may own like-named projects). The REAPI `instance_name`
    /// itself is the project segment only; the account rides on the bearer token
    /// and Kura assembles the authz identifier as `{tenant}/{instance_name}`.
    fn remote_for(&self, instance: &str) -> Arc<Remote> {
        if let Some(remote) = self.remotes.lock().unwrap().get(instance) {
            return remote.clone();
        }
        let remote = Remote::new(
            RemoteConfig {
                grpc_url: self.grpc_url.clone(),
                instance: reapi::reapi_instance(instance).to_string(),
            },
            self.tokens.clone(),
        );
        self.remotes
            .lock()
            .unwrap()
            .entry(instance.to_string())
            .or_insert(remote)
            .clone()
    }

    /// The instance a connection routes to. A declared (non-empty) instance is
    /// authoritative and primes the cas_path mapping for later ⌘B builds; an
    /// empty one falls back to whatever a prior build primed. `None` means an
    /// unprimed ⌘B build: the caller degrades it to a miss.
    fn resolve_instance(&self, cas_path: &str, declared: &str) -> Option<String> {
        let instance = if !declared.is_empty() {
            let mut map = self.path_instance.lock().unwrap();
            if map.get(cas_path).map(String::as_str) != Some(declared) {
                map.insert(cas_path.to_string(), declared.to_string());
                self.persist_registry(&map);
            }
            Some(declared.to_string())
        } else {
            self.path_instance.lock().unwrap().get(cas_path).cloned()
        };
        // Every caller of this is real build traffic (a resolve, a demand fetch,
        // a publish), and nothing else reaches it — the startup prefetch does
        // not. So this is the seam where "a project is being built on this
        // machine" is known, which is what bounds trunk ingestion (see
        // `instance_active`).
        if let Some(instance) = &instance {
            // `insert` reports the transition, and the guard is dropped before
            // the hook: what it kicks off takes locks of its own.
            let newly_active = self
                .active_instances
                .lock()
                .unwrap()
                .insert(instance.clone());
            if newly_active {
                self.ingest_on_activation(instance);
            }
        }
        instance
    }

    /// Ingests the trunk closure of an instance that has just become active but
    /// whose snapshot arrived before it did.
    ///
    /// The startup prefetch warms under the node budget by design: nothing is
    /// active that early, and that is exactly what stops a restart from pulling
    /// the closure of every project the registry has ever seen. But the budget
    /// then sticks. The snapshot is Ready, nothing re-materializes it, and the
    /// first build after a restart — the build the prefetch exists to help —
    /// would wait out SNAPSHOT_FULL_INTERVAL for the closure it was meant to
    /// have. So the same signal that bounds the fan-out lifts the budget, for
    /// this one instance, the moment it stops being a guess.
    ///
    /// Reachable once per instance per proxy lifetime. It no-ops unless a
    /// snapshot is already Ready: an instance whose snapshot lands after the
    /// build (the on-demand path) is materialized with the instance already
    /// active and needs nothing here.
    fn ingest_on_activation(&self, instance: &str) {
        if self.snapshot_ready(instance).is_none() {
            return;
        }
        let proxy: &'static Proxy = unsafe { &*(self as *const Proxy) };
        let instance = instance.to_string();
        // Off-thread: this runs from a resolve, and `resolve_trunk` can fork git.
        std::thread::spawn(move || {
            if !ingest_trunk_enabled() || proxy.resolve_trunk(&instance).is_none() {
                return;
            }
            let Some(snapshot) = proxy.snapshot_ready(&instance) else {
                return;
            };
            crate::log_line(&format!(
                "ingesting {instance}'s trunk closure: prefetched before any build, so it warmed under the node budget"
            ));
            proxy.prematerialize_snapshot(&instance, &snapshot);
        });
    }

    /// Whether this instance's project allows uploading.
    ///
    /// Read here rather than trusted from the client, because the client cannot
    /// speak for the whole build. The plugin's own check sees a compiler option,
    /// which reaches Swift; swift-build's Clang caching runs against a CAS
    /// created with a plugin path and no options, so that lane defaults to
    /// uploading and would publish straight through an explicit opt-out. Every
    /// publication passes through here, from either lane and from the sweeper,
    /// so this is the one place the project's answer can be made to hold.
    fn upload_enabled(&self, instance: &str) -> bool {
        self.source_context(instance).upload
    }

    /// Whether a build for this instance has touched this proxy since it
    /// started. Trunk ingestion is gated on it, because the registry accumulates
    /// every project ever built on the machine: without this, one proxy restart
    /// would fan out and pull the full trunk closure of all of them (GBs) for
    /// projects the developer may not have opened in months. In-memory on
    /// purpose — a fresh proxy ingests nothing until you actually build, which
    /// is the conservative direction.
    ///
    /// It gates the budget rather than the warm, so a prefetched-but-inactive
    /// instance still warms its newest nodes; `ingest_on_activation` is what
    /// lifts the budget once the guess resolves into a real build.
    fn instance_active(&self, instance: &str) -> bool {
        self.active_instances.lock().unwrap().contains(instance)
    }

    fn persist_registry(&self, map: &HashMap<String, String>) {
        let Some(path) = &self.registry_path else {
            return;
        };
        let mut body = String::new();
        for (cas_path, instance) in map {
            if !cas_path.contains(['\t', '\n']) && !instance.contains(['\t', '\n']) {
                body.push_str(cas_path);
                body.push('\t');
                body.push_str(instance);
                body.push('\n');
            }
        }
        let _ = std::fs::write(path, body);
    }

    fn path_state(&self, cas_path: &str) -> Result<&'static PathState, String> {
        if let Some(state) = self.paths.lock().unwrap().get(cas_path) {
            return Ok(state);
        }
        let up = unsafe { Upstream::load(&self.upstream_plugin)? };
        let up: &'static Upstream = Box::leak(Box::new(up));
        let cas = unsafe { open_cas(up, cas_path)? };
        let state: &'static PathState = Box::leak(Box::new(PathState {
            up,
            cas: RwLock::new(cas),
            cas_path: cas_path.to_string(),
            generation: Mutex::new(cas_generation(cas_path)),
            gen_counter: AtomicU64::new(0),
            resolved: Mutex::new(HashMap::new()),
            inflight: Mutex::new(HashSet::new()),
            inflight_cvar: Condvar::new(),
            known_local: std::array::from_fn(|_| Mutex::new(HashSet::new())),
            publish_cache: Mutex::new(HashMap::new()),
            last_used: AtomicU64::new(self.epoch.elapsed().as_millis() as u64),
            pending_objects: Mutex::new(HashMap::new()),
            stats_resolves: AtomicU64::new(0),
            stats_remote_hits: AtomicU64::new(0),
            stats_misses: AtomicU64::new(0),
            stats_snapshot_hits: AtomicU64::new(0),
            stats_demand_fetched: AtomicU64::new(0),
            stats_blobs_fetched: AtomicU64::new(0),
            stats_blobs_inlined: AtomicU64::new(0),
            stats_published: AtomicU64::new(0),
            ms_action: AtomicU64::new(0),
            ms_filter: AtomicU64::new(0),
            ms_fetch: AtomicU64::new(0),
            ms_decode: AtomicU64::new(0),
            ms_store: AtomicU64::new(0),
        }));
        self.paths
            .lock()
            .unwrap()
            .insert(cas_path.to_string(), state);
        Ok(state)
    }

    /// Serves one RESOLVE: answer from the resolved map, else read-through
    /// (manifest + batched fetch of globally-missing blobs + local store).
    ///
    /// Every resolve is issued by a compiler over the unix socket and runs on
    /// swift-build's SERIAL task-setup path — the llbuild engine thread that
    /// schedules every task in the build — so it answers right after the
    /// action lookup (or straight from the snapshot) and leaves graph
    /// materialization to the background pools; a demand load that outruns
    /// them self-heals through OP_FETCH_OBJECT.
    fn resolve(
        &self,
        remote: &Arc<Remote>,
        instance: &str,
        state: &'static PathState,
        key: &[u8],
        snapshot: Option<&Snapshot>,
    ) -> Result<Option<Vec<u8>>, String> {
        state.stats_resolves.fetch_add(1, Ordering::Relaxed);
        state
            .last_used
            .store(self.epoch.elapsed().as_millis() as u64, Ordering::Relaxed);
        // Drop stale marks if the on-disk CAS was wiped and recreated. This runs
        // before the fast path and before resolve_uncached's manifest filter, so
        // an uncached/changed key or a parallel build can't trust known_local
        // marks for a store that no longer exists (which would skip re-fetching
        // wiped nodes and hand back a value whose graph is missing on disk).
        self.check_generation(state);
        // Fast path, outside single-flight so the presence load never
        // serializes other keys: serve a cached Hit only after confirming its
        // value object is still on disk. A long-lived proxy keeps Hits in memory
        // across builds, but a wiped DerivedData removes the value graph; serving
        // the stale Hit then fails the compiler with `missing object`. On absence
        // the path's stale caches are dropped and we re-resolve below.
        // A value that is not on disk but has registered fetch instructions is
        // as good as present: the materializer is filling it in and demand
        // loads self-heal through OP_FETCH_OBJECT, so don't force a re-resolve
        // (a duplicate action lookup on the engine thread).
        match fast_path(
            &state.resolved,
            key,
            |value| state.load_present(value) || state.fetchable(value),
            || state.invalidate(),
        ) {
            FastPath::Hit(value) => return Ok(Some(value)),
            FastPath::Miss => return Ok(None),
            FastPath::Resolve => {}
        }
        // Snapshot path: the instance's complete action-cache map answers the
        // key with its full manifest locally — no remote lookup at all, cold
        // machine or not. Deliberately outside single-flight: there is no
        // remote call to deduplicate, commit/pending registration are
        // idempotent, and a raced duplicate materialize job no-ops against
        // `is_local`. Keys the snapshot lacks (published after it was taken,
        // or genuinely absent) fall through to the per-key path below.
        if let Some(snapshot) = snapshot {
            use sha2::{Digest, Sha256};
            let key_hash: [u8; 32] = Sha256::digest(key).into();
            if let Some(manifest) = snapshot.manifest(&key_hash) {
                state.stats_snapshot_hits.fetch_add(1, Ordering::Relaxed);
                let observed = state.gen_counter.load(Ordering::SeqCst);
                return self.commit_and_materialize(remote, state, key, manifest, observed);
            }
        }
        // Single-flight: wait out a concurrent resolve of the same key.
        {
            let mut inflight = state.inflight.lock().unwrap();
            loop {
                // Re-peek: clone under the map lock, probe outside it. A Hit
                // here was usually just materialized by the winning resolver
                // (or a local publish) — but `resolved` also survives
                // invalidation now (see `invalidate`), so a waiter can wake
                // across a prune/wipe and find a pre-invalidation entry.
                // Verify presence before serving; on absence fall through and
                // resolve it ourselves.
                let peeked = match state.resolved.lock().unwrap().get(key) {
                    Some(Resolution::Hit(value)) => Some(value.clone()),
                    // A fresh miss answers without a round-trip; a stale one
                    // falls through to re-resolve so a key published later
                    // (by another machine) can still land.
                    Some(Resolution::Miss(at)) if at.elapsed() < NEGATIVE_TTL => return Ok(None),
                    _ => None,
                };
                if let Some(value) = peeked {
                    if state.load_present(&value) || state.fetchable(&value) {
                        return Ok(Some(value));
                    }
                }
                if !inflight.contains(key) {
                    inflight.insert(key.to_vec());
                    break;
                }
                inflight = state.inflight_cvar.wait(inflight).unwrap();
            }
        }
        // Re-check the generation now that we hold the single-flight slot: a wipe
        // during the wait must be caught before resolve_uncached trusts
        // known_local. `observed` is snapshotted here so the write guard drops
        // this resolve's marks if a wipe/prune advances the counter mid-resolve.
        self.check_generation(state);
        let observed = state.gen_counter.load(Ordering::SeqCst);
        let outcome =
            self.resolve_uncached(remote, instance, state, key, observed, snapshot.is_some());
        {
            let mut inflight = state.inflight.lock().unwrap();
            inflight.remove(key);
            state.inflight_cvar.notify_all();
        }
        outcome
    }

    fn resolve_uncached(
        &self,
        remote: &Arc<Remote>,
        instance: &str,
        state: &'static PathState,
        key: &[u8],
        observed: u64,
        snapshot_ready: bool,
    ) -> Result<Option<Vec<u8>>, String> {
        let op_start = Instant::now();
        let phase = Instant::now();
        let manifest = match remote.get_action(key)? {
            Some(manifest) if !manifest.is_empty() => manifest,
            _ => {
                // A local compiler may have published (and locally stored) this
                // key between our get_action miss and now; the publisher pool
                // runs outside this resolve's single-flight guard. Never clobber
                // that Some with a negative entry, or the long-lived proxy would
                // answer misses for a key it can actually serve. Prefer the
                // freshly-published value if present.
                {
                    let mut resolved = state.resolved.lock().unwrap();
                    if let Some(Resolution::Hit(value)) = resolved.get(key) {
                        return Ok(Some(value.clone()));
                    }
                    resolved.insert(key.to_vec(), Resolution::Miss(Instant::now()));
                }
                state.stats_misses.fetch_add(1, Ordering::Relaxed);
                if let Some(analytics) = &self.analytics {
                    analytics.record_keyvalue(key, "read", op_start.elapsed().as_secs_f64());
                }
                return Ok(None);
            }
        };
        state.stats_remote_hits.fetch_add(1, Ordering::Relaxed);
        // A per-key hit with a Ready snapshot means this key exists remotely
        // but fell out of the snapshot's size-capped view; queue its manifest
        // for a background re-publish so it ranks back in for the next cold
        // machine. Without a snapshot, per-key is just the normal path and
        // says nothing about view membership.
        if snapshot_ready {
            self.queue_view_refresh(remote, instance, key, &manifest);
        }
        let action_ms = phase.elapsed().as_millis() as u64;
        state.ms_action.fetch_add(action_ms, Ordering::Relaxed);

        if let Some(analytics) = &self.analytics {
            analytics.record_keyvalue(key, "read", op_start.elapsed().as_secs_f64());
        }
        self.commit_and_materialize(remote, state, key, manifest, observed)
    }

    /// Answers a resolve from a known manifest: commit the Hit, register every
    /// node's fetch instructions, then materialize — in the background for a
    /// the background — the caller is the build engine's serial task-setup
    /// thread, where every millisecond spent here is a millisecond no other
    /// task gets scheduled. Shared by the action-lookup path and the snapshot
    /// path.
    fn commit_and_materialize(
        &self,
        remote: &Arc<Remote>,
        state: &'static PathState,
        key: &[u8],
        manifest: Vec<ManifestEntry>,
        observed: u64,
    ) -> Result<Option<Vec<u8>>, String> {
        let value = manifest[0].llcas_digest.clone();
        // Commit BEFORE materialization; only if no wipe/prune advanced the
        // generation while the answer was being produced.
        let committed = {
            let mut resolved = state.resolved.lock().unwrap();
            if committable(observed, state.gen_counter.load(Ordering::SeqCst)) {
                resolved.insert(key.to_vec(), Resolution::Hit(value.clone()));
                true
            } else {
                false
            }
        };
        if !committed {
            return Ok(None);
        }
        // Register fetch instructions for every graph node BEFORE answering, so
        // a consumer can never observe a served Hit without a way to produce
        // its objects: a demand load that runs ahead of the materializer
        // fetches per object through OP_FETCH_OBJECT using these.
        {
            let mut pending = state.pending_objects.lock().unwrap();
            for entry in &manifest {
                pending
                    .entry(entry.llcas_digest.clone())
                    .or_insert_with(|| PendingFetch {
                        blob: entry.blob.clone(),
                        contents: entry.contents.clone(),
                    });
            }
        }
        self.enqueue_materialize(state, remote, manifest, observed);
        Ok(Some(value))
    }

    /// Fetches and locally stores every node of `manifest` the on-disk CAS is
    /// missing. Each node's fetch instructions stay registered afterwards with
    /// their inlined bytes dropped (blob digest only): the build system prunes
    /// the on-disk CAS several times per build, and a pruned object under an
    /// already-served Hit must remain producible on demand — clang FAILS THE
    /// BUILD on a missing object, it does not recompile. Blob-level problems
    /// (a node absent on the server, a decode failure) skip that node; a
    /// transport error aborts and leaves the remaining instructions intact.
    fn materialize_manifest(
        &self,
        remote: &Remote,
        state: &'static PathState,
        manifest: &[ManifestEntry],
        observed: u64,
    ) -> Result<(), String> {
        let phase = Instant::now();
        let missing: Vec<&ManifestEntry> = manifest
            .iter()
            .filter(|entry| !self.is_local(state, observed, &entry.llcas_digest))
            .collect();
        state
            .ms_filter
            .fetch_add(phase.elapsed().as_millis() as u64, Ordering::Relaxed);
        // Nodes already on disk keep their instructions too, but shed any
        // inlined bytes — the digest-only form is what bounds this map's
        // memory (the bytes live in the local CAS now; a re-fetch after a
        // prune goes to the remote by blob digest).
        {
            let missing_set: HashSet<&[u8]> = missing
                .iter()
                .map(|entry| entry.llcas_digest.as_slice())
                .collect();
            let mut pending = state.pending_objects.lock().unwrap();
            for entry in manifest {
                if !missing_set.contains(entry.llcas_digest.as_slice()) {
                    if let Some(instruction) = pending.get_mut(&entry.llcas_digest) {
                        instruction.contents = None;
                    }
                }
            }
        }
        if !missing.is_empty() {
            // Blobs the server inlined into the GetActionResult response (see
            // reapi::ManifestEntry::contents) need no second round-trip;
            // batch-read only the remainder (older kura, or a value graph the
            // server's response budget could not fully afford). One batch per
            // resolve: the server parallelizes blob reads internally, so
            // client-side fragmentation only multiplies per-RPC overhead
            // (measured: 6-way splitting of ~23-blob sets pinned per-resolve
            // latency at per-RPC cost times groups).
            let phase = Instant::now();
            let digests: Vec<_> = missing
                .iter()
                .filter(|entry| entry.contents.is_none())
                .map(|entry| entry.blob.clone())
                .collect();
            let contents = if digests.is_empty() {
                HashMap::new()
            } else {
                remote.batch_read(&digests)?
            };
            let fetch_elapsed = phase.elapsed();
            state
                .ms_fetch
                .fetch_add(fetch_elapsed.as_millis() as u64, Ordering::Relaxed);
            // TEMP diagnostics: per-resolve batch shape + per-leg wall time, to
            // attribute where in-build fetch latency goes (size tail vs uniform
            // slowdown). Gated so normal runs stay quiet.
            if std::env::var_os("TUIST_CAS_LOG_RESOLVES").is_some() {
                let bytes: i64 = digests.iter().map(|digest| digest.size_bytes).sum();
                crate::log_line(&format!(
                    "materialize manifest={} fetched={} bytes={} fetch_ms={}",
                    manifest.len(),
                    digests.len(),
                    bytes,
                    fetch_elapsed.as_millis()
                ));
            }
            // The fetch is one batch RPC; attribute its wall time to each
            // batch-read node in proportion to that node's compressed bytes
            // for the per-node transfer analytics. Inlined nodes rode the
            // action lookup, so they carry no share of the fetch time.
            let total_compressed: i64 = missing
                .iter()
                .filter(|entry| entry.contents.is_none())
                .map(|entry| entry.blob.size_bytes)
                .sum::<i64>()
                .max(1);
            for entry in &missing {
                let (blob, inlined) = match &entry.contents {
                    Some(bytes) => (bytes, true),
                    None => match contents.get(&entry.blob.hash) {
                        Some(bytes) => (bytes, false),
                        // Incomplete graph on the server (the writer may still
                        // be uploading): skip the node, keeping its fetch
                        // instructions registered so the demand load that
                        // needs it retries — and surfaces the failure —
                        // per object.
                        None => continue,
                    },
                };
                let phase = Instant::now();
                let Some(frame) = reapi::decompress_frame(blob) else {
                    continue;
                };
                let Some(node) = reapi::decode_frame(&frame) else {
                    continue;
                };
                let codec_elapsed = phase.elapsed();
                state
                    .ms_decode
                    .fetch_add(codec_elapsed.as_millis() as u64, Ordering::Relaxed);
                if let Some(analytics) = &self.analytics {
                    let compressed = entry.blob.size_bytes;
                    let transfer = if inlined {
                        0.0
                    } else {
                        fetch_elapsed.as_secs_f64() * (compressed as f64 / total_compressed as f64)
                    };
                    let codec = codec_elapsed.as_secs_f64();
                    // This node's own transfer, keyed by its content-digest hex
                    // (which equals the checksum in its parent's reference).
                    analytics.record_cas_output(
                        &crate::analytics::hex_upper(&entry.llcas_digest),
                        frame.len() as i64,
                        compressed,
                        transfer + codec,
                        transfer,
                        codec,
                    );
                    // The (casID -> checksum) references this node makes, for the
                    // nodes table the server maps build-log node ids through.
                    for (cas_id, hex) in crate::analytics::parse_cas_references(&node.data) {
                        analytics.record_node(&cas_id, &hex);
                    }
                }
                let phase = Instant::now();
                unsafe { store_node(state, &node)? };
                state
                    .ms_store
                    .fetch_add(phase.elapsed().as_millis() as u64, Ordering::Relaxed);
                // Mark local only while still on this generation, checked under
                // the shard lock: a wipe/prune that clears the shards after this
                // must not leave the freshly-fetched digest behind as a mark for
                // a store it did not write. (invalidate bumps the counter before
                // clearing, so a stale insert either loses the race or is cleared.)
                {
                    let mut shard = state.shard(&entry.llcas_digest).lock().unwrap();
                    if committable(observed, state.gen_counter.load(Ordering::SeqCst)) {
                        shard.insert(entry.llcas_digest.clone());
                    }
                }
                if inlined {
                    state.stats_blobs_inlined.fetch_add(1, Ordering::Relaxed);
                } else {
                    state.stats_blobs_fetched.fetch_add(1, Ordering::Relaxed);
                }
                if let Some(instruction) = state
                    .pending_objects
                    .lock()
                    .unwrap()
                    .get_mut(&entry.llcas_digest)
                {
                    instruction.contents = None;
                }
            }
        }
        Ok(())
    }

    /// Queues a demand-path value graph for the materializer pool.
    fn enqueue_materialize(
        &self,
        state: &PathState,
        remote: &Arc<Remote>,
        manifest: Vec<ManifestEntry>,
        observed: u64,
    ) {
        let id = self.job_counter.fetch_add(1, Ordering::Relaxed);
        self.materialize_jobs.lock().unwrap().insert(
            id,
            MaterializeJob {
                cas_path: state.cas_path.clone(),
                remote: remote.clone(),
                manifest,
                observed,
            },
        );
        self.materializer.enqueue(id.to_be_bytes().to_vec());
    }

    fn materialize_job(&self, item: &[u8]) {
        let Ok(id_bytes) = <[u8; 8]>::try_from(item) else {
            return;
        };
        let job = self
            .materialize_jobs
            .lock()
            .unwrap()
            .remove(&u64::from_be_bytes(id_bytes));
        let Some(job) = job else { return };
        let Ok(state) = self.path_state(&job.cas_path) else {
            return;
        };
        if let Err(message) =
            self.materialize_manifest(&job.remote, state, &job.manifest, job.observed)
        {
            crate::log_line(&format!("background materialize failed: {message}"));
        }
    }

    /// The demand-fetch coalescer for an instance, created on first use.
    fn coalescer_for(&self, instance: &str) -> Arc<DemandCoalescer> {
        let mut coalescers = self.demand_coalescers.lock().unwrap();
        coalescers
            .entry(instance.to_string())
            .or_insert_with(|| Arc::new(DemandCoalescer::new()))
            .clone()
    }

    /// Fetches one blob for a demand load, coalescing with other demand fetches
    /// in flight for the same instance into a shared `BatchReadBlobs`.
    fn demand_fetch(
        &self,
        instance: &str,
        remote: &Arc<Remote>,
        digest: &reapi::Digest,
    ) -> Result<Option<Vec<u8>>, String> {
        self.coalescer_for(instance)
            .fetch(digest, |digests| remote.batch_read(digests))
    }

    /// Serves one FETCH_OBJECT: a demand load found `digest` missing from the
    /// local CAS. Present now (the materializer won the race) answers
    /// immediately; a registered pending fetch is executed inline (this runs
    /// on a compiler worker thread, never the build engine's serial path);
    /// anything else is a genuine not-found.
    fn fetch_object(
        &self,
        state: &'static PathState,
        cas_path: &str,
        declared_instance: &str,
        digest: &[u8],
    ) -> Result<bool, String> {
        // Restat before answering. A demand fetch can be the FIRST thing to
        // arrive after a wipe: the compiler asks for an object it could not
        // load, and nothing makes a resolve come first. Every answer below is
        // about whatever store this handle is bound to, so bound to a deleted
        // one, `load_present` reports an object the compiler cannot see and a
        // fetch stores into a directory nothing reads. Both end as the
        // `missing object` the rebind exists to prevent, and clang does not
        // survive that one. The resolve path restats for the same reason; this
        // is the door it does not cover.
        self.check_generation(state);
        // And a demand fetch IS the build working. The resolves all land during
        // planning, so a long compile phase afterwards is nothing but these: with
        // only resolves and publishes stamping this, the machine reads as idle
        // ~90s into the phase that is most bandwidth-bound, and the idle gate
        // starts the refresh whose whole purpose was to stay out of the build's
        // way, competing for the link the fetch below is waiting on.
        state
            .last_used
            .store(self.epoch.elapsed().as_millis() as u64, Ordering::Relaxed);
        if state.load_present(digest) {
            return Ok(true);
        }
        let pending = state.pending_objects.lock().unwrap().get(digest).cloned();
        // Second source of fetch instructions: nodes this machine PUBLISHED.
        // A Hit served for a locally-published entry never fetched a manifest
        // (its objects were local), so a prune that removes them leaves no
        // pending entry — but the publisher's node cache knows the uploaded
        // blob digest, and the blob is on the remote by publish order.
        let pending = pending.or_else(|| {
            state
                .publish_cache
                .lock()
                .unwrap()
                .get(digest)
                .map(|(blob, _refs)| PendingFetch {
                    blob: blob.clone(),
                    contents: None,
                })
        });
        // Third source: the instance's snapshot node table. A restarted proxy
        // has empty maps while Apple's persistent local action cache keeps
        // serving associations that never pass through RESOLVE, so a prune of
        // their objects lands here with no instruction anywhere — but the
        // snapshot knows every advertised node's blob.
        let pending = match pending {
            Some(pending) => Some(pending),
            None => self.snapshot_fetch_instruction(cas_path, declared_instance, digest),
        };
        let Some(pending) = pending else {
            return Ok(false);
        };
        let blob = pending.blob.clone();
        let blob_bytes = match pending.contents {
            Some(bytes) => bytes,
            None => {
                let Some(instance) = self.resolve_instance(cas_path, declared_instance) else {
                    return Ok(false);
                };
                let remote = self.remote_for(&instance);
                match self.demand_fetch(&instance, &remote, &blob)? {
                    Some(bytes) => bytes,
                    None => return Ok(false),
                }
            }
        };
        let Some(frame) = reapi::decompress_frame(&blob_bytes) else {
            return Ok(false);
        };
        let Some(node) = reapi::decode_frame(&frame) else {
            return Ok(false);
        };
        unsafe { store_node(state, &node)? };
        // Retain the digest-only instruction — including one the snapshot
        // fallback just reconstructed — so the next prune of this object is
        // produced without another snapshot wait.
        state
            .pending_objects
            .lock()
            .unwrap()
            .entry(digest.to_vec())
            .and_modify(|instruction| instruction.contents = None)
            .or_insert(PendingFetch {
                blob,
                contents: None,
            });
        state.stats_demand_fetched.fetch_add(1, Ordering::Relaxed);
        Ok(true)
    }

    /// Fetch instructions reconstructed from the instance's snapshot, for a
    /// digest neither `pending_objects` nor `publish_cache` knows. Kicks off
    /// the snapshot fetch when the instance has none yet (after a restart,
    /// FETCH_OBJECT can arrive before any RESOLVE) and waits briefly for it —
    /// this path already blocks a compiler worker thread on network I/O.
    fn snapshot_fetch_instruction(
        &self,
        cas_path: &str,
        declared_instance: &str,
        digest: &[u8],
    ) -> Option<PendingFetch> {
        let instance = self.resolve_instance(cas_path, declared_instance)?;
        let remote = self.remote_for(&instance);
        self.ensure_snapshot(&instance, &remote);
        let deadline = Instant::now() + SNAPSHOT_FETCH_WAIT;
        let snapshot = loop {
            if let Some(snapshot) = self.snapshot_ready(&instance) {
                break snapshot;
            }
            let fetching = matches!(
                self.snapshots.lock().unwrap().get(&instance),
                Some(SnapshotState::Fetching)
            );
            if !fetching || Instant::now() >= deadline {
                return None;
            }
            std::thread::sleep(Duration::from_millis(50));
        };
        let index = *snapshot.node_index.get(digest)?;
        let (_, blob) = &snapshot.nodes[index as usize];
        Some(PendingFetch {
            blob: blob.clone(),
            contents: None,
        })
    }

    /// Detects a wiped-and-recreated on-disk CAS (a deleted DerivedData under
    /// this long-lived proxy) from a change in the CAS directory's identity,
    /// rebinds the CAS handle to the new store, and drops the now-stale
    /// in-memory marks (`resolved`, `known_local`, `publish_cache`) so a resolve
    /// re-probes and re-materializes authoritatively. Called at the head of
    /// every resolve, so it covers uncached/changed keys and parallel builds,
    /// not only re-requested cached Hits. The generation lock is held across the
    /// invalidation so a concurrent resolve can't observe the new generation as
    /// unchanged and filter against `known_local` while it is being cleared.
    ///
    /// The handle is rebound BEFORE the counter is bumped, so a resolve that
    /// probed the old store cannot have its answer committed: it snapshotted
    /// `observed` before the bump, so `committable` drops the write. Dropping
    /// the marks without rebinding would achieve nothing -- `load_present` would
    /// re-learn every one of them from the deleted store (see `reopen_cas`).
    fn check_generation(&self, state: &PathState) {
        let Some(current) = cas_generation(&state.cas_path) else {
            return;
        };
        let mut stored = state.generation.lock().unwrap();
        if generation_changed(*stored, Some(current)) {
            if let Err(message) = state.reopen_cas() {
                // Leave `stored` untouched so the next resolve retries: serving
                // from the old handle is answering about a store that no longer
                // exists, which fails the compiler with `missing object`.
                crate::log_line(&format!(
                    "cas reopen after wipe failed for {}: {message}",
                    state.cas_path
                ));
                return;
            }
            state.invalidate();
            state.publish_cache.lock().unwrap().clear();
        }
        *stored = Some(current);
    }

    fn is_local(&self, state: &PathState, observed: u64, digest: &[u8]) -> bool {
        if state.shard(digest).lock().unwrap().contains(digest) {
            return true;
        }
        if state.load_present(digest) {
            // Memoize the authoritative load only while still on this generation:
            // a wipe/prune that cleared the shards must not have this present-now
            // fact re-inserted for what may already be a replaced store.
            let mut shard = state.shard(digest).lock().unwrap();
            if committable(observed, state.gen_counter.load(Ordering::SeqCst)) {
                shard.insert(digest.to_vec());
            }
            true
        } else {
            false
        }
    }

    /// PUBLISH notify: queue the record for the publisher pool. Items encode
    /// The tags to publish a record under, preferring the pair bound the first
    /// time we accepted it.
    ///
    /// Binding at accept only holds for as long as we hold the queue, and the
    /// record outlives that. It sits in the spool until its upload drains, so a
    /// proxy restart mid-drain, or an unprimed Xcode build that spools before any
    /// project has primed the path, leaves it for a later `sweep` or for the
    /// plugin's own sweeper to re-send. Resolving there reads whatever is checked
    /// out by then, which is exactly how a trunk build's orphaned outputs come
    /// back tagged with the feature branch someone checked out afterwards.
    ///
    /// So the first accept, the closest we ever stand to the producing build,
    /// writes the pair beside the record, and every later re-enqueue reads it
    /// back. Best-effort by design: a record we never accepted while primed has
    /// no sidecar, and resolving live is the only guess left.
    fn record_tags(&self, instance: &str, record_path: &str) -> (String, String) {
        let sidecar = tags_path(record_path);
        if let Ok(contents) = std::fs::read(&sidecar) {
            if let Some((branch, trunk)) = decode_tags(&contents) {
                return (branch, trunk);
            }
        }
        let branch = self.resolve_branch(instance).unwrap_or_default();
        let trunk = self.resolve_trunk(instance).unwrap_or_default();
        // A torn write would be read back as "no sidecar" and re-resolved, so
        // failing here costs a re-resolve, never a wrong tag.
        let _ = std::fs::write(&sidecar, encode_tags(&branch, &trunk));
        (branch, trunk)
    }

    /// instance + cas_path + the (branch, trunk) bound here + record path.
    ///
    /// The tags are resolved NOW, when the build hands us the record, and not
    /// where they are used (the upload, which runs after the queue wait, the
    /// existence probe and the closure's blob transfers, tens of seconds over
    /// a WAN link, and mostly AFTER the build that produced them has exited).
    ///
    /// Resolving there would read whatever the registry says by then, and the
    /// registry moves: a shared CI runner rewrites it on every job's setup. So
    /// job A's still-draining outputs would be tagged with job B's branch, and a
    /// trunk build's outputs would land tagged `feature` and drop out of the
    /// trunk view they belong in.
    ///
    /// Binding at accept costs nothing: the context is memoized, so this reads
    /// the registry at most once per TTL per instance, never per publish.
    fn enqueue_publish(&self, cas_path: &str, instance: &str, record_path: &str) {
        // The project's answer, enforced where both lanes meet. The plugin
        // declines to publish when its own option says so, but that option only
        // reaches Swift: the build system's Clang caching creates its CAS with a
        // plugin path and no options, so it asks to publish regardless. Its
        // records arrive here, and so do the sweeper's, so refusing here is what
        // makes `upload: false` mean it.
        if !self.upload_enabled(instance) {
            return;
        }
        let (branch, trunk) = self.record_tags(instance, record_path);
        let mut item = Vec::with_capacity(
            8 + instance.len() + cas_path.len() + branch.len() + trunk.len() + record_path.len(),
        );
        item.extend_from_slice(&(instance.len() as u16).to_be_bytes());
        item.extend_from_slice(instance.as_bytes());
        item.extend_from_slice(&(cas_path.len() as u16).to_be_bytes());
        item.extend_from_slice(cas_path.as_bytes());
        // Empty encodes `None`: neither resolver can yield an empty branch name
        // (both reject it), so the round trip is lossless.
        item.extend_from_slice(&(branch.len() as u16).to_be_bytes());
        item.extend_from_slice(branch.as_bytes());
        item.extend_from_slice(&(trunk.len() as u16).to_be_bytes());
        item.extend_from_slice(trunk.as_bytes());
        item.extend_from_slice(record_path.as_bytes());
        self.publisher.enqueue(item);
    }

    fn publish_item(&self, item: &[u8]) {
        let Some((instance, rest)) = take_u16_field(item) else {
            return;
        };
        let Some((cas_path, rest)) = take_u16_field(rest) else {
            return;
        };
        let Some((branch, rest)) = take_u16_field(rest) else {
            return;
        };
        let Some((trunk, record_path)) = take_u16_field(rest) else {
            return;
        };
        let instance = String::from_utf8_lossy(instance).into_owned();
        let cas_path = String::from_utf8_lossy(cas_path).into_owned();
        let branch = non_empty(&String::from_utf8_lossy(branch));
        let trunk = non_empty(&String::from_utf8_lossy(trunk));
        let record_path = String::from_utf8_lossy(record_path).into_owned();
        let remote = self.remote_for(&instance);
        let Ok(state) = self.path_state(&cas_path) else {
            return;
        };
        state
            .last_used
            .store(self.epoch.elapsed().as_millis() as u64, Ordering::Relaxed);
        let Ok(bytes) = std::fs::read(&record_path) else {
            return;
        };
        let Some(record) =
            PublishRecord::decode_body(&bytes, Some(std::path::PathBuf::from(&record_path)))
        else {
            remove_record(&record_path);
            return;
        };
        // The client re-puts replayed results at the end of its job, so a warm
        // build spools thousands of records whose (key, value) this proxy
        // resolved FROM the remote minutes earlier. `publish` would discover
        // that with a get_action round trip per record; the resolved map
        // already knows, so drop those records here for free. A Hit with a
        // DIFFERENT value (a genuine local recompute) still publishes.
        if let Some(Resolution::Hit(value)) = state.resolved.lock().unwrap().get(&record.key) {
            if value == &record.value_digest {
                remove_record(&record_path);
                return;
            }
        }
        match self.publish(&remote, state, &record, branch.as_deref(), trunk.as_deref()) {
            Ok(()) => {
                remove_record(&record_path);
                state.stats_published.fetch_add(1, Ordering::Relaxed);
                state.resolved.lock().unwrap().insert(
                    record.key.clone(),
                    Resolution::Hit(record.value_digest.clone()),
                );
            }
            Err(reason) => {
                crate::log_line(&format!("proxy publish failed ({reason}); record kept"));
            }
        }
    }

    /// `branch`/`trunk` are the tags bound when this record was accepted (see
    /// `enqueue_publish`), not resolved here: by now the checkout may have moved.
    fn publish(
        &self,
        remote: &Remote,
        state: &'static PathState,
        record: &PublishRecord,
        branch: Option<&str>,
        trunk: Option<&str>,
    ) -> Result<(), String> {
        let op_start = Instant::now();
        // Existence probe: only the first entry's digest is compared, so skip
        // the wildcard inline hint the resolve path uses.
        if let Ok(Some(manifest)) = remote.probe_action(&record.key) {
            if manifest.first().map(|entry| entry.llcas_digest.as_slice())
                == Some(record.value_digest.as_slice())
            {
                // Same bytes, so there is nothing to upload. That used to end
                // it, which meant a trunk build could recompute a result a
                // feature branch had published first and never take the tag
                // back: the entry stayed `feature` and stayed out of the trunk
                // view forever, which is the reclaim half of what this scoping
                // is for. Bytes are no longer the whole of an entry's identity,
                // so re-send the manifest we just probed, carrying our tags and
                // nothing else. The server damps a true no-op; we cannot tell
                // one from here without asking what tag it holds, which is the
                // round trip this would be making anyway.
                if branch.is_some() || trunk.is_some() {
                    remote.update_action(&record.key, &manifest, branch, trunk)?;
                }
                return Ok(());
            }
        }
        let mut entries: Vec<ManifestEntry> = Vec::new();
        let mut blobs: Vec<Option<Vec<u8>>> = Vec::new();
        let mut visited = HashSet::new();
        let mut pending = VecDeque::from([record.value_digest.clone()]);
        while let Some(digest) = pending.pop_front() {
            if !visited.insert(digest.clone()) {
                continue;
            }
            if let Some((blob_digest, children)) =
                state.publish_cache.lock().unwrap().get(&digest).cloned()
            {
                entries.push(ManifestEntry {
                    llcas_digest: digest,
                    blob: blob_digest,
                    contents: None,
                });
                blobs.push(None);
                pending.extend(children);
                continue;
            }
            let (blob, children) = unsafe { encode_node_blob(state, &digest)? };
            let blob_digest = reapi::blob_digest(&blob);
            state
                .publish_cache
                .lock()
                .unwrap()
                .insert(digest.clone(), (blob_digest.clone(), children.clone()));
            entries.push(ManifestEntry {
                llcas_digest: digest,
                blob: blob_digest,
                contents: None,
            });
            blobs.push(Some(blob));
            pending.extend(children);
        }
        let missing =
            remote.find_missing(entries.iter().map(|entry| entry.blob.clone()).collect())?;
        let missing_set: HashSet<(String, i64)> = missing
            .into_iter()
            .map(|digest| (digest.hash, digest.size_bytes))
            .collect();
        let mut uploads: Vec<(reapi::Digest, Vec<u8>)> = Vec::new();
        // (llcas_digest, uncompressed size, compressed size, node data) per
        // uploaded node, recorded once the batch transfer time is known.
        let mut upload_meta: Vec<(Vec<u8>, i64, i64, Vec<u8>)> = Vec::new();
        for (entry, blob) in entries.iter().zip(blobs) {
            if !missing_set.contains(&(entry.blob.hash.clone(), entry.blob.size_bytes)) {
                continue;
            }
            let bytes = match blob {
                Some(bytes) => bytes,
                None => unsafe { encode_node_blob(state, &entry.llcas_digest)?.0 },
            };
            if self.analytics.is_some() {
                let (size, data) = reapi::decompress_frame(&bytes)
                    .and_then(|frame| {
                        reapi::decode_frame(&frame).map(|node| (frame.len(), node.data))
                    })
                    .unwrap_or((bytes.len(), Vec::new()));
                upload_meta.push((
                    entry.llcas_digest.clone(),
                    size as i64,
                    entry.blob.size_bytes,
                    data,
                ));
            }
            uploads.push((entry.blob.clone(), bytes));
        }
        if !uploads.is_empty() {
            let upload_start = Instant::now();
            remote.batch_update(uploads)?;
            if let Some(analytics) = &self.analytics {
                let elapsed = upload_start.elapsed().as_secs_f64();
                let total: i64 = upload_meta.iter().map(|(_, _, c, _)| c).sum::<i64>().max(1);
                for (digest, size, compressed, data) in &upload_meta {
                    let transfer = elapsed * (*compressed as f64 / total as f64);
                    analytics.record_cas_output(
                        &crate::analytics::hex_upper(digest),
                        *size,
                        *compressed,
                        transfer,
                        transfer,
                        0.0,
                    );
                    for (cas_id, hex) in crate::analytics::parse_cas_references(data) {
                        analytics.record_node(&cas_id, &hex);
                    }
                }
            }
        }
        let result = remote.update_action(&record.key, &entries, branch, trunk);
        if let Some(analytics) = &self.analytics {
            analytics.record_keyvalue(&record.key, "write", op_start.elapsed().as_secs_f64());
        }
        result
    }

    /// Clears any per-path cache grown past its bound. Called from the periodic
    /// maintenance loop; a no-op while every map stays under its cap.
    pub fn enforce_cache_bounds(&self) {
        let states: Vec<&'static PathState> =
            self.paths.lock().unwrap().values().copied().collect();
        for state in states {
            if state.resolved.lock().unwrap().len() > MAX_RESOLVED {
                state.resolved.lock().unwrap().clear();
            }
            if state.publish_cache.lock().unwrap().len() > MAX_PUBLISH_CACHE {
                state.publish_cache.lock().unwrap().clear();
            }
            for shard in &state.known_local {
                if shard.lock().unwrap().len() > MAX_KNOWN_LOCAL_PER_SHARD {
                    shard.lock().unwrap().clear();
                }
            }
            if state.pending_objects.lock().unwrap().len() > MAX_PENDING_OBJECTS {
                state.pending_objects.lock().unwrap().clear();
            }
        }
    }

    /// Reclaims the in-memory caches (resolved map, known-local shards, publish
    /// cache) of paths whose on-disk CAS is gone or that have been idle past
    /// IDLE_RECLAIM. Called from the maintenance loop; complements
    /// `enforce_cache_bounds`, which only releases memory when a single build
    /// overruns a size cap and never for projects that simply stop being built.
    ///
    /// The PathState shell (llcas handle + now-empty maps, ~KB) is retained: a
    /// later build at the same path finds it and re-warms from the remote. These
    /// caches are correctness-preserving, so clearing only forces re-work.
    pub fn reclaim_idle(&self) {
        let now = self.epoch.elapsed();
        let paths: Vec<(String, &'static PathState)> = self
            .paths
            .lock()
            .unwrap()
            .iter()
            .map(|(cas_path, state)| (cas_path.clone(), *state))
            .collect();
        for (cas_path, state) in paths {
            let last = Duration::from_millis(state.last_used.load(Ordering::Relaxed));
            let idle = now.saturating_sub(last);
            let cas_dir_gone = std::fs::symlink_metadata(&cas_path).is_err();
            if should_reclaim(idle, cas_dir_gone) {
                state.invalidate();
                state.publish_cache.lock().unwrap().clear();
            }
        }
    }

    /// Why background snapshot work should wait, or None when the machine is
    /// free enough to do it. Two signals, both cheap enough for every tick:
    ///
    /// - a recent CAS operation, meaning a build is running (or just was). This
    ///   is the traffic a refresh would actually be stealing from, and it is the
    ///   one case where slowing the machine down also slows down the very build
    ///   the cache exists to make fast.
    /// - the load average per core, which catches whatever else is running,
    ///   since a machine busy with something other than a build never touches
    ///   the CAS and would otherwise read as idle.
    ///
    /// Note this does not sense network throughput. A build's own fetches are
    /// covered by the first signal; unrelated saturation (a big download) is
    /// not, and would need per-interface counters to see.
    fn busy_reason(&self) -> Option<String> {
        let now = self.epoch.elapsed();
        let idle = self
            .paths
            .lock()
            .unwrap()
            .values()
            .map(|state| Duration::from_millis(state.last_used.load(Ordering::Relaxed)))
            .max()
            .map(|last_op| now.saturating_sub(last_op));
        busy_verdict(idle, load_per_core())
    }

    /// Rate-limits the "holding off" line to BUSY_LOG_INTERVAL.
    fn log_busy(&self, reason: &str) {
        let mut logged_at = self.busy_logged_at.lock().unwrap();
        let now = Instant::now();
        if logged_at.is_some_and(|at| now.duration_since(at) < BUSY_LOG_INTERVAL) {
            return;
        }
        *logged_at = Some(now);
        crate::log_line(&format!("snapshot refresh held off: {reason}"));
    }

    /// Sweeps orphaned publication records for every known CAS path whose
    /// instance the proxy knows (an unprimed path has nothing to publish to).
    pub fn sweep(&self) {
        let paths: Vec<String> = self.paths.lock().unwrap().keys().cloned().collect();
        for cas_path in paths {
            let Some(instance) = self.path_instance.lock().unwrap().get(&cas_path).cloned() else {
                continue;
            };
            let spool = std::path::Path::new(&cas_path).join("tuist-spool");
            let Ok(entries) = std::fs::read_dir(&spool) else {
                continue;
            };
            for entry in entries.flatten() {
                if let Some(name) = entry.file_name().to_str() {
                    // A sidecar is not a record. Publishing one would fail to
                    // decode and delete it, throwing away the tags it exists to
                    // carry, and the record beside it would then resolve live.
                    if name.ends_with(TAGS_SUFFIX) {
                        continue;
                    }
                    // Claims are ours alone now; reclaim anything.
                    let base = name.split_once(".claim-").map(|(b, _)| b.to_string());
                    let path = match base {
                        Some(base) => {
                            let claimed =
                                spool.join(format!("{base}.claim-{}", std::process::id()));
                            if std::fs::rename(entry.path(), &claimed).is_err() {
                                continue;
                            }
                            claimed
                        }
                        None => entry.path(),
                    };
                    self.enqueue_publish(&cas_path, &instance, &path.to_string_lossy());
                }
            }
        }
    }

    /// Refreshes the bearer only when it is within `lead` of its JWT expiry,
    /// keeping a long-lived proxy authenticated without re-auth'ing on a fixed
    /// cadence. Called every maintenance tick (cheap); a no-op in env-only (CI)
    /// mode or for opaque, non-expiring tokens.
    pub fn maintain_token(&self, lead: std::time::Duration) {
        self.tokens.refresh_if_expiring(lead);
    }

    /// Queues a per-key-served manifest for a background re-publish (see
    /// `Proxy.view_refresh`). Inlined contents are stripped: the refresh only
    /// re-sends the llcas→blob mapping, and the blobs are already on the
    /// server (the per-key hit proved the entry serveable).
    fn queue_view_refresh(
        &self,
        remote: &Arc<Remote>,
        instance: &str,
        key: &[u8],
        manifest: &[ManifestEntry],
    ) {
        // A refresh is a write, and this one is ours, not the build's: nothing
        // the compiler asked for produced it. A machine told not to upload does
        // not get to write to the server because the proxy found reading
        // interesting, so the read-only case declines and pays the per-key round
        // trip it was always paying.
        if !self.upload_enabled(instance) {
            return;
        }
        let branch = self.resolve_branch(instance);
        let trunk = self.resolve_trunk(instance);
        let dedup: RefreshKey = (
            instance.to_string(),
            key.to_vec(),
            branch.clone(),
            trunk.clone(),
        );
        {
            let mut refreshed = self.view_refreshed.lock().unwrap();
            if refreshed.len() >= VIEW_REFRESH_MAX_QUEUE || !refreshed.insert(dedup.clone()) {
                return;
            }
        }
        let stripped: Vec<ManifestEntry> = manifest
            .iter()
            .map(|entry| ManifestEntry {
                llcas_digest: entry.llcas_digest.clone(),
                blob: entry.blob.clone(),
                contents: None,
            })
            .collect();
        let mut queue = self.view_refresh.lock().unwrap();
        if queue.len() < VIEW_REFRESH_MAX_QUEUE {
            queue.push_back(ViewRefresh {
                remote: remote.clone(),
                key: key.to_vec(),
                manifest: stripped,
                branch,
                trunk,
                dedup,
            });
        } else {
            // Claimed but not queued: hold the claim and this refresh never
            // happens and can never be asked for again.
            drop(queue);
            self.view_refreshed.lock().unwrap().remove(&dedup);
        }
    }

    /// Drains a batch of queued view refreshes, one small UpdateActionResult
    /// each. Best-effort: a failure drops the batch's remainder — the next
    /// cold build that pays the per-key round trip re-queues the key.
    pub fn refresh_view_keys(&self) {
        let mut sent = 0_usize;
        while sent < VIEW_REFRESH_PER_TICK {
            let Some(refresh) = self.view_refresh.lock().unwrap().pop_front() else {
                break;
            };
            // Carrying the tags of the build that took the hit is what makes this
            // the reclaim path. These entries are, by definition, outside the
            // trunk view, and this is often the only thing that will ever put one
            // back: sending no tags would re-attribute every one of them to
            // nobody, and an untagged entry is in NO trunk view, so trunk's own
            // keys would be dropped from it by the very act of reading them. With
            // the tags, a feature hit stays out and a trunk hit takes the entry
            // back.
            if refresh
                .remote
                .update_action(
                    &refresh.key,
                    &refresh.manifest,
                    refresh.branch.as_deref(),
                    refresh.trunk.as_deref(),
                )
                .is_err()
            {
                // Release the claim so a later hit can ask again. This item is
                // the one being dropped (the rest of the batch stays queued and
                // retries next tick, so their claims stand), and without letting
                // go of it, "the next cold build that pays the per-key round trip
                // re-queues the key" describes something that cannot happen: the
                // claim outlives the work and suppresses every later attempt.
                self.view_refreshed.lock().unwrap().remove(&refresh.dedup);
                break;
            }
            sent += 1;
        }
        if sent > 0 {
            let remaining = self.view_refresh.lock().unwrap().len();
            crate::log_line(&format!(
                "view refresh: {sent} keys re-published ({remaining} queued)"
            ));
        }
    }

    /// Kicks off snapshot fetches for every instance the persisted registry
    /// knows. Called once at proxy startup, so a machine's first build after
    /// a restart already has the snapshot (and its bulk warm) in flight
    /// instead of opening the fetch window mid-build — the fetch used to
    /// start on the first resolve, which put the transfer and the server's
    /// first index build inside the build the user was waiting on.
    pub fn prefetch_known_snapshots(&self) {
        let instances: std::collections::HashSet<String> = self
            .path_instance
            .lock()
            .unwrap()
            .values()
            .cloned()
            .collect();
        for instance in instances {
            let remote = self.remote_for(&instance);
            self.ensure_snapshot(&instance, &remote);
        }
    }

    /// Kicks off the instance's snapshot fetch on first sight, in the
    /// background — never on a resolve path. One fetch per proxy lifetime:
    /// entries published later resolve through the ordinary per-key path.
    fn ensure_snapshot(&self, instance: &str, remote: &Arc<Remote>) {
        {
            let mut snapshots = self.snapshots.lock().unwrap();
            if snapshots.contains_key(instance) {
                return;
            }
            snapshots.insert(instance.to_string(), SnapshotState::Fetching);
        }
        let proxy: &'static Proxy = unsafe { &*(self as *const Proxy) };
        let instance = instance.to_string();
        let remote = remote.clone();
        std::thread::spawn(move || {
            let outcome = proxy.fetch_full_snapshot(&instance, &remote);
            proxy.snapshots.lock().unwrap().insert(instance, outcome);
        });
    }

    /// One full snapshot fetch + decode, returning the resulting state.
    fn fetch_full_snapshot(&self, instance: &str, remote: &Arc<Remote>) -> SnapshotState {
        match remote.get_snapshot(None, self.resolve_trunk(instance).as_deref()) {
            Ok(Some(bytes)) => match Snapshot::decode(&bytes) {
                Some(snapshot) => {
                    crate::log_line(&format!(
                        "snapshot: {} keys / {} nodes ({} bytes, watermark {}) for {instance}",
                        snapshot.keys.len(),
                        snapshot.nodes.len(),
                        bytes.len(),
                        snapshot.watermark,
                    ));
                    let snapshot = Arc::new(snapshot);
                    self.prematerialize_snapshot(instance, &snapshot);
                    SnapshotState::Ready {
                        snapshot,
                        full_at: Instant::now(),
                        refreshed_at: Instant::now(),
                        last_used: Instant::now(),
                    }
                }
                None => {
                    crate::log_line(&format!(
                        "snapshot: undecodable payload for {instance}; staying on the per-key path"
                    ));
                    SnapshotState::Absent {
                        checked: Instant::now(),
                        retry_after: SNAPSHOT_RETRY_INTERVAL,
                    }
                }
            },
            Ok(None) => SnapshotState::Absent {
                checked: Instant::now(),
                retry_after: SNAPSHOT_RETRY_INTERVAL,
            },
            Err(message) => {
                crate::log_line(&format!("snapshot fetch failed for {instance}: {message}"));
                SnapshotState::Absent {
                    checked: Instant::now(),
                    retry_after: SNAPSHOT_ERROR_RETRY_INTERVAL,
                }
            }
        }
    }

    /// Called from the maintenance loop: keeps Ready snapshots fresh with
    /// deltas (snapshot_delta_interval), replaces them wholesale on
    /// SNAPSHOT_FULL_INTERVAL (deltas only ADD; the full fetch re-applies the
    /// server's blob-presence gate after evictions), retries Absent after
    /// SNAPSHOT_RETRY_INTERVAL (the server may have been upgraded under this
    /// long-lived proxy), and BOUNDS the cache: instances idle past
    /// SNAPSHOT_IDLE_EVICT are dropped and the map is capped at
    /// SNAPSHOT_MAX_INSTANCES by evicting the least recently used.
    ///
    /// All of that fetching waits for a machine that is not busy (see
    /// `busy_reason`); the point of a refresh is to have the trunk ready for the
    /// *next* build, which makes it worth nothing and costly now if it lands in
    /// the middle of this one. An instance's FIRST snapshot is not this path
    /// (`ensure_snapshot` on demand, `prefetch_known_snapshots` at startup) and
    /// is never held off: it is what the build in front of us is waiting on.
    pub fn refresh_snapshots(&self) {
        let now = Instant::now();
        enum Plan {
            Delta { instance: String, watermark: u64 },
            Full { instance: String },
        }
        // Plan under the lock, fetch outside it.
        let mut plans: Vec<Plan> = Vec::new();
        {
            let mut snapshots = self.snapshots.lock().unwrap();
            snapshots.retain(|_, state| match state {
                SnapshotState::Ready { last_used, .. } => {
                    now.duration_since(*last_used) < SNAPSHOT_IDLE_EVICT
                }
                _ => true,
            });
            while snapshots.len() > SNAPSHOT_MAX_INSTANCES {
                let oldest = snapshots
                    .iter()
                    .filter_map(|(instance, state)| match state {
                        SnapshotState::Ready { last_used, .. } => {
                            Some((instance.clone(), *last_used))
                        }
                        _ => None,
                    })
                    .min_by_key(|(_, last_used)| *last_used)
                    .map(|(instance, _)| instance);
                let Some(oldest) = oldest else { break };
                snapshots.remove(&oldest);
            }
            for (instance, state) in snapshots.iter() {
                match state {
                    SnapshotState::Ready {
                        snapshot,
                        full_at,
                        refreshed_at,
                        ..
                    } => {
                        if now.duration_since(*full_at) > SNAPSHOT_FULL_INTERVAL {
                            plans.push(Plan::Full {
                                instance: instance.clone(),
                            });
                        } else if now.duration_since(*refreshed_at) > snapshot_delta_interval() {
                            plans.push(Plan::Delta {
                                instance: instance.clone(),
                                watermark: snapshot.watermark,
                            });
                        }
                    }
                    SnapshotState::Absent {
                        checked,
                        retry_after,
                    } if now.duration_since(*checked) > *retry_after => {
                        plans.push(Plan::Full {
                            instance: instance.clone(),
                        });
                    }
                    _ => {}
                }
            }
        }
        // Everything above is bookkeeping over what we already hold, so it runs
        // regardless; what follows fetches and ingests, so it waits for a free
        // machine. Checked only when something is actually due, both to keep the
        // held-off line honest and because a due refresh is the only thing the
        // wait costs: the next tick re-plans it, so nothing is dropped, it is
        // deferred. A machine that is never free simply keeps the view it has,
        // which costs hits and never correctness.
        if !plans.is_empty() {
            if let Some(reason) = self.busy_reason() {
                self.log_busy(&reason);
                return;
            }
        }
        for plan in plans {
            match plan {
                Plan::Full { instance } => {
                    let remote = self.remote_for(&instance);
                    let outcome = self.fetch_full_snapshot(&instance, &remote);
                    self.snapshots.lock().unwrap().insert(instance, outcome);
                }
                Plan::Delta {
                    instance,
                    watermark,
                } => {
                    let remote = self.remote_for(&instance);
                    let trunk = self.resolve_trunk(&instance);
                    match remote.get_snapshot(Some(watermark), trunk.as_deref()) {
                        Ok(Some(bytes)) => {
                            let Some(delta) = Snapshot::decode(&bytes) else {
                                continue;
                            };
                            let warm = {
                                let mut snapshots = self.snapshots.lock().unwrap();
                                let Some(SnapshotState::Ready {
                                    snapshot,
                                    refreshed_at,
                                    ..
                                }) = snapshots.get_mut(&instance)
                                else {
                                    continue;
                                };
                                *refreshed_at = now;
                                let mut updated = (**snapshot).clone();
                                // The server's delta cursor is inclusive (its
                                // millisecond versions are not unique), so
                                // boundary entries are re-sent every tick;
                                // only keys we do not already hold with the
                                // same manifest are new work.
                                let fresh: Vec<[u8; 32]> = delta
                                    .keys
                                    .keys()
                                    .filter(|hash| updated.manifest(hash) != delta.manifest(hash))
                                    .copied()
                                    .collect();
                                if fresh.is_empty() {
                                    // Still advance the echoed watermark.
                                    updated.watermark = updated.watermark.max(delta.watermark);
                                    *snapshot = Arc::new(updated);
                                    None
                                } else {
                                    crate::log_line(&format!(
                                        "snapshot delta: {} keys for {instance}",
                                        fresh.len()
                                    ));
                                    updated.merge(&delta);
                                    *snapshot = Arc::new(updated);
                                    let mut warm = delta;
                                    warm.keys.retain(|hash, _| fresh.contains(hash));
                                    warm.key_order.retain(|hash| fresh.contains(hash));
                                    Some(warm)
                                }
                            };
                            // Warm the new keys' content like the initial fetch.
                            if let Some(delta) = warm {
                                self.prematerialize_snapshot(&instance, &delta);
                            }
                        }
                        Ok(None) => {}
                        Err(message) => {
                            crate::log_line(&format!(
                                "snapshot delta fetch failed for {instance}: {message}"
                            ));
                        }
                    }
                }
            }
        }
    }

    /// Queues materialization of every graph the snapshot describes: bulk
    /// content warming with no keylog and no demand ordering — resolves
    /// answer from the snapshot regardless and loads self-heal per object,
    /// so this only keeps the link busy so most loads find bytes already
    /// local. Once per snapshot fetch (i.e. per proxy lifetime per
    /// instance); after a mid-day wipe, demand-driven jobs and per-object
    /// self-heals carry re-materialization.
    /// The git branch a publish for this instance is attributed to: the env
    /// override first (a manual build or a bench), then the branch derived live
    /// from the instance's registered source root, then the branch
    /// `tuist setup cache` recorded for a CI checkout.
    ///
    /// The branch to attribute a publish to: the env override, then what setup
    /// recorded from the CI job's environment.
    ///
    /// Nothing derives this from the checkout. The snapshot is what trunk looks
    /// like as CI built it, so CI is the only publisher whose branch has to be
    /// right, and CI is exactly where a checkout cannot answer anyway, its HEAD
    /// being detached. Deleting the live derivation deleted a class of bug with
    /// it: a registered root could be moved, renamed, or shared by two worktrees
    /// of one project, and each of those quietly attributed a build to the wrong
    /// branch. None of it is reachable from a value the CI job told us about
    /// itself.
    fn resolve_branch(&self, instance: &str) -> Option<String> {
        if let Ok(branch) = std::env::var("TUIST_CAS_BRANCH") {
            if !branch.is_empty() {
                return Some(branch);
            }
        }
        self.source_context(instance).branch
    }

    /// The trunk to scope this instance's snapshot to: the env override, then the
    /// project's configured default branch. A server decision, never the
    /// checkout's `origin/HEAD`.
    fn resolve_trunk(&self, instance: &str) -> Option<String> {
        if let Ok(trunk) = std::env::var("TUIST_CAS_TRUNK_BRANCH") {
            if !trunk.is_empty() {
                return Some(trunk);
            }
        }
        self.source_context(instance).trunk
    }

    /// What setup recorded for the instance, memoized on GIT_CONTEXT_TTL so a
    /// publish does not re-read the registry. A refresh re-reads it, so a project
    /// set up after this proxy started is picked up without a restart.
    fn source_context(&self, instance: &str) -> SourceBranches {
        {
            let cache = self.source_cache.lock().unwrap();
            if let Some(context) = cache.get(instance) {
                if context.read_at.elapsed() < GIT_CONTEXT_TTL {
                    return SourceBranches {
                        branch: context.ci_branch.clone(),
                        trunk: context.trunk.clone(),
                        upload: context.upload,
                    };
                }
            }
        }
        let source = self.registered_source(instance);
        let trunk = source.as_ref().and_then(|source| source.trunk.clone());
        let branch = source.as_ref().and_then(|source| source.ci_branch.clone());
        // Unknown instance: nothing recorded, so nothing to withhold.
        let upload = source.as_ref().map(|source| source.upload).unwrap_or(true);
        {
            let cache = self.source_cache.lock().unwrap();
            let changed = cache
                .get(instance)
                .map(|context| context.ci_branch != branch || context.trunk != trunk)
                .unwrap_or(true);
            if changed {
                crate::log_line(&format!(
                    "source context for {instance}: branch={branch:?} trunk={trunk:?}"
                ));
            }
        }
        self.source_cache.lock().unwrap().insert(
            instance.to_string(),
            SourceContext {
                read_at: Instant::now(),
                trunk: trunk.clone(),
                ci_branch: branch.clone(),
                upload,
            },
        );
        SourceBranches { branch, trunk, upload }
    }

    /// What setup registered for the instance, reloading the sources registry so
    /// a mapping written after startup is visible. Cheap: only runs on a TTL
    /// miss in `git_context`.
    fn registered_source(&self, instance: &str) -> Option<RegisteredSource> {
        let clone = |source: &RegisteredSource| RegisteredSource {
            trunk: source.trunk.clone(),
            ci_branch: source.ci_branch.clone(),
            upload: source.upload,
        };
        if let Some(path) = self.registry_path.as_deref() {
            let sources = load_sources(&sources_path_for(path));
            let source = sources.get(instance).map(clone);
            *self.instance_sources.lock().unwrap() = sources;
            source
        } else {
            self.instance_sources.lock().unwrap().get(instance).map(clone)
        }
    }

    fn prematerialize_snapshot(&self, instance: &str, snapshot: &Snapshot) {
        let cas_paths: Vec<String> = self
            .path_instance
            .lock()
            .unwrap()
            .iter()
            .filter(|(_, mapped)| mapped.as_str() == instance)
            .map(|(cas_path, _)| cas_path.clone())
            .collect();
        let remote = self.remote_for(instance);
        for cas_path in cas_paths {
            let Ok(state) = self.path_state(&cas_path) else {
                continue;
            };
            // Restat before warming. Nothing else on this path is a resolve, so
            // without this a snapshot arriving after a wipe warms through a
            // handle bound to the deleted store: the fetches cost bandwidth, the
            // stores land where nothing reads them, and they hold the wiped
            // directory's inodes on disk. The resolve that eventually rebinds
            // discards it all. One restat per snapshot, not per key.
            self.check_generation(state);
            let observed = state.gen_counter.load(Ordering::SeqCst);
            // Warm newest-first (the wire order) and stop at the node budget:
            // a shared namespace's snapshot carries every project's history,
            // and warming all of it pulled ~6x this build's content over the
            // link the demand loads share (562s vs the 134s a right-sized
            // namespace measured). The budget covers a large build's closure;
            // everything past it stays resolvable and self-heals on demand.
            // With a trunk-scoped snapshot the closure IS the budget's target,
            // so full ingestion (the layer above key caching) warms all of it —
            // the scoping already bounds it to the trunk, not the whole polluted
            // namespace. Unscoped, or opted out, keep the node budget.
            let configured = if self.resolve_trunk(instance).is_some()
                && ingest_trunk_enabled()
                && self.instance_active(instance)
            {
                0
            } else {
                prematerialize_max_nodes()
            };
            let mut budget = configured;
            let mut enqueued = 0usize;
            for key_hash in &snapshot.key_order {
                let Some(manifest) = snapshot.manifest(key_hash) else {
                    continue;
                };
                if configured != 0 {
                    budget = budget.saturating_sub(manifest.len());
                }
                let id = self.job_counter.fetch_add(1, Ordering::Relaxed);
                self.materialize_jobs.lock().unwrap().insert(
                    id,
                    MaterializeJob {
                        cas_path: cas_path.clone(),
                        remote: remote.clone(),
                        manifest,
                        observed,
                    },
                );
                self.prematerializer.enqueue(id.to_be_bytes().to_vec());
                enqueued += 1;
                if configured != 0 && budget == 0 {
                    break;
                }
            }
            if enqueued < snapshot.key_order.len() {
                crate::log_line(&format!(
                    "snapshot warm capped for {instance}: {enqueued} newest of {} keys enqueued",
                    snapshot.key_order.len()
                ));
            }
            if enqueued > 0 {
                // Drain watcher: logs when the warm's jobs have all been
                // processed, with wall time — the cost side of proactive
                // ingestion, and the bench's "ingested, off critical path"
                // gate. Watches the shared job map, so it reads drained only
                // once demand jobs are also quiet (fine: the warm phase
                // precedes any build).
                let proxy: &'static Proxy = unsafe { &*(self as *const Proxy) };
                let instance = instance.to_string();
                let started = Instant::now();
                std::thread::spawn(move || loop {
                    std::thread::sleep(std::time::Duration::from_millis(500));
                    if proxy.materialize_jobs.lock().unwrap().is_empty() {
                        crate::log_line(&format!(
                            "snapshot warm drained for {instance}: {enqueued} keys in {:.1}s",
                            started.elapsed().as_secs_f64()
                        ));
                        return;
                    }
                });
            }
        }
    }

    fn snapshot_ready(&self, instance: &str) -> Option<Arc<Snapshot>> {
        match self.snapshots.lock().unwrap().get_mut(instance) {
            Some(SnapshotState::Ready {
                snapshot,
                last_used,
                ..
            }) => {
                *last_used = Instant::now();
                Some(snapshot.clone())
            }
            _ => None,
        }
    }

    /// Counts (and occasionally logs) a request that could not be routed to an
    /// instance. Logged on the first occurrence and every 1000th after.
    fn note_unprimed(&self, cas_path: &str) {
        let count = self.unprimed.fetch_add(1, Ordering::Relaxed) + 1;
        if count == 1 || count % 1000 == 0 {
            crate::log_line(&format!(
                "unprimed request #{count} for {cas_path}: no instance declared and none registered — \
                 answering local-only misses (is the build carrying its tuist-instance option or \
                 TUIST_CAS_ACCOUNT/TUIST_CAS_PROJECT?)"
            ));
        }
    }

    pub fn stats_line(&self) -> String {
        let paths = self.paths.lock().unwrap();
        let mut parts = Vec::new();
        for (path, state) in paths.iter() {
            parts.push(format!(
                "{}: resolves={} remote_hits={} snapshot_hits={} misses={} demand_fetched={} pending={} blobs={} inlined={} published={} | ms action={} filter={} fetch={} decode={} store={}",
                path,
                state.stats_resolves.load(Ordering::Relaxed),
                state.stats_remote_hits.load(Ordering::Relaxed),
                state.stats_snapshot_hits.load(Ordering::Relaxed),
                state.stats_misses.load(Ordering::Relaxed),
                state.stats_demand_fetched.load(Ordering::Relaxed),
                state.pending_objects.lock().unwrap().len(),
                state.stats_blobs_fetched.load(Ordering::Relaxed),
                state.stats_blobs_inlined.load(Ordering::Relaxed),
                state.stats_published.load(Ordering::Relaxed),
                state.ms_action.load(Ordering::Relaxed),
                state.ms_filter.load(Ordering::Relaxed),
                state.ms_fetch.load(Ordering::Relaxed),
                state.ms_decode.load(Ordering::Relaxed),
                state.ms_store.load(Ordering::Relaxed),
            ));
        }
        parts.join(" | ")
    }

    pub fn serve(&'static self, listener: UnixListener) {
        for stream in listener.incoming() {
            let Ok(stream) = stream else { continue };
            std::thread::spawn(move || {
                let _ = self.handle(stream);
            });
        }
    }

    fn handle(&self, mut stream: UnixStream) -> std::io::Result<()> {
        let request: Request = read_request(&mut stream)?;
        // A plugin from a different CLI version speaks a different frame layout;
        // reject rather than misparse, so the plugin degrades to a local miss.
        if request.version != crate::proxy_proto::PROTOCOL_VERSION {
            return write_response(
                &mut stream,
                STATUS_ERROR,
                b"proxy protocol version mismatch",
            );
        }
        match request.op {
            OP_RESOLVE => {
                let Some(instance) = self.resolve_instance(&request.cas_path, &request.instance)
                else {
                    // Unprimed ⌘B build: no instance to route to. Degrade to a
                    // miss so the compiler proceeds on the local CAS — but say
                    // so, since a build that lost its instance configuration
                    // looks identical and silently runs cache-less.
                    self.note_unprimed(&request.cas_path);
                    return write_response(&mut stream, STATUS_MISS, &[]);
                };
                let remote = self.remote_for(&instance);
                self.ensure_snapshot(&instance, &remote);
                let snapshot = self.snapshot_ready(&instance);
                let outcome = self.path_state(&request.cas_path).and_then(|state| {
                    self.resolve(&remote, &instance, state, &request.payload, snapshot.as_deref())
                });
                match outcome {
                    Ok(Some(value)) => write_response(&mut stream, STATUS_HIT, &value),
                    Ok(None) => write_response(&mut stream, STATUS_MISS, &[]),
                    Err(message) => {
                        crate::log_line(&format!("proxy resolve failed: {message}"));
                        write_response(&mut stream, STATUS_ERROR, message.as_bytes())
                    }
                }
            }
            OP_PUBLISH => {
                // Ack even when unprimed: the record stays spooled for a later
                // sweep once a build primes the instance.
                if let Some(instance) = self.resolve_instance(&request.cas_path, &request.instance)
                {
                    let record_path = String::from_utf8_lossy(&request.payload).into_owned();
                    self.enqueue_publish(&request.cas_path, &instance, &record_path);
                } else {
                    self.note_unprimed(&request.cas_path);
                }
                write_response(&mut stream, STATUS_HIT, &[])
            }
            OP_INVALIDATE => {
                // A prune emptied this path's on-disk CAS in place; drop our marks
                // so a resolve re-fetches. Only if we already track the path — an
                // unknown path has nothing cached, and we must not open a CAS
                // handle for it here. Bind first so the `paths` lock is released
                // before invalidating.
                let state = self.paths.lock().unwrap().get(&request.cas_path).copied();
                if let Some(state) = state {
                    state.invalidate();
                    state.publish_cache.lock().unwrap().clear();
                }
                write_response(&mut stream, STATUS_HIT, &[])
            }
            OP_FETCH_OBJECT => {
                // Bind the path when the request is routable: a proxy that
                // restarted under a persistent local action cache must still
                // produce pruned objects (fetch_object reconstructs the
                // instruction from the instance snapshot). An unroutable
                // request stays a miss without opening a CAS handle.
                //
                // The lookup MUST release the `paths` guard before the match
                // runs: a match scrutinee's temporary lives across every arm,
                // and the fallback arm re-enters `path_state` — a self-
                // deadlock on the non-reentrant `paths` mutex — and takes
                // `path_instance` while holding `paths`, inverting the
                // resolve path's lock order. One unroutable demand fetch
                // wedged the whole proxy permanently (165 threads parked,
                // every build on the machine silently degraded to cache-less
                // compiles).
                let known = self.paths.lock().unwrap().get(&request.cas_path).copied();
                let state = match known {
                    Some(state) => Ok(Some(state)),
                    None if self
                        .resolve_instance(&request.cas_path, &request.instance)
                        .is_some() =>
                    {
                        self.path_state(&request.cas_path).map(Some)
                    }
                    None => Ok(None),
                };
                let outcome = state.and_then(|state| match state {
                    Some(state) => self.fetch_object(
                        state,
                        &request.cas_path,
                        &request.instance,
                        &request.payload,
                    ),
                    None => Ok(false),
                });
                match outcome {
                    Ok(true) => write_response(&mut stream, STATUS_HIT, &[]),
                    Ok(false) => write_response(&mut stream, STATUS_MISS, &[]),
                    Err(message) => {
                        crate::log_line(&format!("proxy fetch_object failed: {message}"));
                        write_response(&mut stream, STATUS_ERROR, message.as_bytes())
                    }
                }
            }
            _ => write_response(&mut stream, STATUS_ERROR, b"bad op"),
        }
    }
}

/// An owned copy of `value`, or `None` when it is empty. Publisher items encode
/// an absent branch or trunk as a zero-length field.
fn non_empty(value: &str) -> Option<String> {
    (!value.is_empty()).then(|| value.to_owned())
}

/// Reads a `u16`-length-prefixed field from the front of `buf`, returning it
/// and the remainder. `None` if the buffer is truncated.
fn take_u16_field(buf: &[u8]) -> Option<(&[u8], &[u8])> {
    if buf.len() < 2 {
        return None;
    }
    let len = u16::from_be_bytes([buf[0], buf[1]]) as usize;
    let rest = &buf[2..];
    if rest.len() < len {
        return None;
    }
    Some((&rest[..len], &rest[len..]))
}

/// Loads the persisted `cas_path -> instance` registry (tab-separated lines).
fn load_registry(path: &Path) -> HashMap<String, String> {
    let mut map = HashMap::new();
    if let Ok(body) = std::fs::read_to_string(path) {
        for line in body.lines() {
            if let Some((cas_path, instance)) = line.split_once('\t') {
                map.insert(cas_path.to_string(), instance.to_string());
            }
        }
    }
    map
}

/// The instance -> source-root registry sits next to the cas_path registry,
/// written by `tuist setup cache` (which knows both the full handle and the
/// project path). `<registry>.sources`, TSV `instance\tsource-root`.
fn sources_path_for(registry: &Path) -> PathBuf {
    let mut path = registry.to_path_buf().into_os_string();
    path.push(".sources");
    PathBuf::from(path)
}

fn load_sources(path: &Path) -> HashMap<String, RegisteredSource> {
    let mut map = HashMap::new();
    if let Ok(body) = std::fs::read_to_string(path) {
        for line in body.lines() {
            // `instance \t source-root [\t trunk [\t ci-branch]]`. Both trailing
            // columns are optional: a registry written by an older setup, or by
            // one that could not reach the server, still parses and leaves the
            // trunk to be derived from the checkout. The trunk's place is held
            // empty when a branch was recorded without one, so the columns stay
            // positional.
            let mut columns = line.split('\t');
            // The second column is the source root. Setup still writes it and
            // this deliberately steps over it: nothing here reads the checkout
            // any more, but a proxy from before that keeps parsing the columns
            // after it, so the format does not have to move.
            let (Some(instance), Some(_root)) = (columns.next(), columns.next()) else {
                continue;
            };
            if instance.is_empty() {
                continue;
            }
            map.insert(
                instance.to_string(),
                RegisteredSource {
                    trunk: columns.next().filter(|trunk| !trunk.is_empty()).map(str::to_owned),
                    ci_branch: columns.next().filter(|branch| !branch.is_empty()).map(str::to_owned),
                    // Absent is a registry written before the column, and
                    // uploading is what that machine already does.
                    upload: columns.next() != Some("0"),
                },
            );
        }
    }
    map
}

unsafe fn open_cas(up: &'static Upstream, path: &str) -> Result<llcas_cas_t, String> {
    let options = (up.llcas_cas_options_create)();
    let c_path = std::ffi::CString::new(path).map_err(|_| "bad cas path".to_string())?;
    (up.llcas_cas_options_set_client_version)(options, 0, 1);
    (up.llcas_cas_options_set_ondisk_path)(options, c_path.as_ptr());
    let mut error: *mut std::ffi::c_char = std::ptr::null_mut();
    let cas = (up.llcas_cas_create)(options, &mut error);
    (up.llcas_cas_options_dispose)(options);
    if cas.is_null() {
        let message = if error.is_null() {
            "cas_create failed".to_string()
        } else {
            let text = std::ffi::CStr::from_ptr(error)
                .to_string_lossy()
                .into_owned();
            (up.llcas_string_dispose)(error);
            text
        };
        return Err(message);
    }
    Ok(cas)
}

unsafe fn store_node(state: &PathState, node: &reapi::Node) -> Result<(), String> {
    // Held for the whole store: the ref objectids are only meaningful to the
    // handle that minted them, and a wipe must not swap it out mid-write.
    let cas_guard = state.cas.read().unwrap();
    let cas = *cas_guard;
    let mut ref_ids = Vec::with_capacity(node.refs.len());
    for reference in &node.refs {
        let digest = llcas_digest_t {
            data: reference.as_ptr(),
            size: reference.len(),
        };
        let mut id = llcas_objectid_t { opaque: 0 };
        let mut error: *mut std::ffi::c_char = std::ptr::null_mut();
        if (state.up.llcas_cas_get_objectid)(cas, digest, &mut id, &mut error) {
            if !error.is_null() {
                (state.up.llcas_string_dispose)(error);
            }
            return Err("objectid".into());
        }
        ref_ids.push(id);
    }
    let data = llcas_data_t {
        data: node.data.as_ptr() as *const std::ffi::c_void,
        size: node.data.len(),
    };
    let mut stored = llcas_objectid_t { opaque: 0 };
    let mut error: *mut std::ffi::c_char = std::ptr::null_mut();
    let failed = (state.up.llcas_cas_store_object)(
        cas,
        data,
        ref_ids.as_ptr(),
        ref_ids.len(),
        &mut stored,
        &mut error,
    );
    if failed {
        if !error.is_null() {
            (state.up.llcas_string_dispose)(error);
        }
        return Err("store".into());
    }
    Ok(())
}

unsafe fn encode_node_blob(
    state: &PathState,
    digest: &[u8],
) -> Result<(Vec<u8>, Vec<Vec<u8>>), String> {
    // Held for the whole decode: the loaded object and every id/digest borrowed
    // out of it below belong to this handle, so a wipe must not dispose it here.
    let cas_guard = state.cas.read().unwrap();
    let cas = *cas_guard;
    let digest_t = llcas_digest_t {
        data: digest.as_ptr(),
        size: digest.len(),
    };
    let mut id = llcas_objectid_t { opaque: 0 };
    let mut id_error: *mut std::ffi::c_char = std::ptr::null_mut();
    if (state.up.llcas_cas_get_objectid)(cas, digest_t, &mut id, &mut id_error) {
        if !id_error.is_null() {
            (state.up.llcas_string_dispose)(id_error);
        }
        return Err("objectid".into());
    }
    let mut loaded = llcas_loaded_object_t { opaque: 0 };
    let mut load_error: *mut std::ffi::c_char = std::ptr::null_mut();
    let result = (state.up.llcas_cas_load_object)(cas, id, &mut loaded, &mut load_error);
    if !load_error.is_null() {
        (state.up.llcas_string_dispose)(load_error);
    }
    if result != LLCAS_LOOKUP_RESULT_SUCCESS {
        return Err("local load".into());
    }
    let data = (state.up.llcas_loaded_object_get_data)(cas, loaded);
    let node_data = std::slice::from_raw_parts(data.data as *const u8, data.size);
    let refs = (state.up.llcas_loaded_object_get_refs)(cas, loaded);
    let count = (state.up.llcas_object_refs_get_count)(cas, refs);
    let mut ref_digests = Vec::with_capacity(count);
    for index in 0..count {
        let child = (state.up.llcas_object_refs_get_id)(cas, refs, index);
        let digest = (state.up.llcas_objectid_get_digest)(cas, child);
        ref_digests.push(std::slice::from_raw_parts(digest.data, digest.size).to_vec());
    }
    let blob = reapi::compress_frame(&reapi::encode_frame(&ref_digests, node_data));
    Ok((blob, ref_digests))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    #[test]
    fn sources_registry_keeps_reading_entries_written_without_a_trunk() {
        let dir = std::env::temp_dir().join(format!("tuist-sources-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("temp dir");
        let path = dir.join("registry.sources");
        // Row 1 is what a setup that reached the server writes; row 2 is the
        // older two-column form (and what a setup that could not reach the
        // server still writes). Both must parse, and an absent trunk column must
        // stay absent rather than swallowing the column after it.
        //
        // The second column is the source root, which nothing reads any more.
        // Setup still writes it, and stepping over it rather than dropping it is
        // what lets a proxy from before that keep parsing the columns after it.
        std::fs::write(
            &path,
            "tuist/mastodon\t/src/mastodon\tmain\ntuist/legacy\t/src/legacy\n",
        )
        .expect("write registry");

        let sources = load_sources(&path);
        assert_eq!(sources.len(), 2);
        let scoped = sources.get("tuist/mastodon").expect("scoped entry");
        assert_eq!(
            scoped.trunk.as_deref(),
            Some("main"),
            "the trunk is read from the third column, not the second"
        );
        let legacy = sources.get("tuist/legacy").expect("legacy entry");
        assert_eq!(legacy.trunk, None, "an absent trunk column is not a path");
        assert_eq!(
            scoped.ci_branch, None,
            "a registry written before the branch column carries no branch"
        );

        std::fs::remove_dir_all(&dir).ok();
    }

    /// Publishing is asynchronous and durable: a record is queued, then uploaded
    /// after the queue wait, the existence probe and the closure's transfers,
    /// which is typically after the build that produced it has exited. Resolving
    /// the tags at the upload would read whatever the registry says by then.
    ///
    /// A shared CI runner is where that bites: job A's still-draining outputs
    /// would be tagged with job B's branch, because B's setup rewrote the row A
    /// was accepted under.
    #[test]
    fn a_queued_publish_keeps_the_branch_it_was_accepted_on() {
        let dir = std::env::temp_dir().join(format!("tuist-publish-tag-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let registry = dir.join("registry");
        let sources = sources_path_for(&registry);
        let record_branch = |branch: &str| {
            std::fs::write(
                &sources,
                format!("tuist/mastodon\t/src/mastodon\tmain\t{branch}\n"),
            )
            .expect("write sources");
        };
        record_branch("release/4.2");

        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            String::new(),
            Some(registry),
            None,
        );
        let captured: Arc<Mutex<Vec<Vec<u8>>>> = Arc::new(Mutex::new(Vec::new()));
        let sink = Arc::clone(&captured);
        // Replaces the publisher's real worker before any enqueue starts it, so
        // the queued items land here instead of being uploaded to a remote.
        proxy
            .publisher
            .configure(1, move |item| sink.lock().unwrap().push(item));

        proxy.enqueue_publish("/cas", "tuist/mastodon", "/spool/from-the-release-job");
        // The next job on this runner runs setup, which rewrites the row.
        record_branch("main");
        // The proxy would otherwise reuse the memoized context for the TTL;
        // expiring it is what the next job gets for free by taking longer.
        proxy.source_cache.lock().unwrap().clear();
        proxy.enqueue_publish("/cas", "tuist/mastodon", "/spool/from-the-main-job");

        proxy
            .publisher
            .drain_stop_timeout(std::time::Duration::from_secs(10));
        let items = captured.lock().unwrap();
        assert_eq!(items.len(), 2, "both records queued");
        let tags = |item: &[u8]| {
            let (_, rest) = take_u16_field(item).expect("instance");
            let (_, rest) = take_u16_field(rest).expect("cas path");
            let (branch, rest) = take_u16_field(rest).expect("branch");
            let (trunk, record) = take_u16_field(rest).expect("trunk");
            (
                String::from_utf8_lossy(branch).into_owned(),
                String::from_utf8_lossy(trunk).into_owned(),
                String::from_utf8_lossy(record).into_owned(),
            )
        };
        let (branch, trunk, record) = tags(&items[0]);
        assert_eq!(record, "/spool/from-the-release-job");
        assert_eq!(
            branch, "release/4.2",
            "the record keeps the branch it was accepted under, after the next \
             job on this runner rewrote the registry"
        );
        assert_eq!(trunk, "main");
        let (branch, trunk, record) = tags(&items[1]);
        assert_eq!(record, "/spool/from-the-main-job");
        assert_eq!(branch, "main", "a later record takes the new branch");
        assert_eq!(trunk, "main", "the trunk is the project's either way");

        drop(items);
        std::fs::remove_dir_all(&dir).ok();
    }

    /// A sweeper claims a record the producing build left behind, and it resolves
    /// tags at sweep time, long after that build is gone. The sidecar is what
    /// carries the answer forward: without it a record swept on the next job
    /// would be tagged with that job's branch.
    #[test]
    fn a_reswept_record_keeps_the_branch_that_produced_it() {
        let dir = std::env::temp_dir().join(format!("tuist-sidecar-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let registry = dir.join("registry");
        let sources = sources_path_for(&registry);
        let record_branch = |branch: &str| {
            std::fs::write(
                &sources,
                format!("tuist/mastodon\t/src/mastodon\tmain\t{branch}\n"),
            )
            .expect("write sources");
        };
        record_branch("main");

        let cas_path = dir.join("cas");
        let spool = cas_path.join("tuist-spool");
        std::fs::create_dir_all(&spool).expect("spool");
        let record = spool.join("1234-0");
        std::fs::write(&record, b"record").expect("record");
        let record_path = record.to_string_lossy().into_owned();

        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            String::new(),
            Some(registry),
            None,
        );
        let captured: Arc<Mutex<Vec<Vec<u8>>>> = Arc::new(Mutex::new(Vec::new()));
        let sink = Arc::clone(&captured);
        proxy
            .publisher
            .configure(1, move |item| sink.lock().unwrap().push(item));

        // The build hands us the record while the main job owns the registry.
        proxy.enqueue_publish(&cas_path.to_string_lossy(), "tuist/mastodon", &record_path);
        assert!(
            spool.join("1234-0.tags").exists(),
            "accepting a record writes its tags beside it"
        );

        // The proxy dies before draining. The next job on this runner runs setup,
        // rewriting the registry, and a later sweep finds the record still there.
        record_branch("feature/theirs");
        proxy.source_cache.lock().unwrap().clear();
        proxy.enqueue_publish(&cas_path.to_string_lossy(), "tuist/mastodon", &record_path);

        proxy
            .publisher
            .drain_stop_timeout(std::time::Duration::from_secs(10));
        let items = captured.lock().unwrap();
        assert_eq!(items.len(), 2);
        let branch_of = |item: &[u8]| {
            let (_, rest) = take_u16_field(item).expect("instance");
            let (_, rest) = take_u16_field(rest).expect("cas path");
            let (branch, _) = take_u16_field(rest).expect("branch");
            String::from_utf8_lossy(branch).into_owned()
        };
        assert_eq!(branch_of(&items[0]), "main");
        assert_eq!(
            branch_of(&items[1]),
            "main",
            "the re-enqueued record keeps the branch that produced it, not the one \
             whose job happens to own the registry when it is swept"
        );

        drop(items);
        std::fs::remove_dir_all(&dir).ok();
    }

    /// A sweeper claims a record by renaming it to `<base>.claim-<pid>`, so the
    /// sidecar has to be found from the claimed name too.
    #[test]
    fn a_claimed_record_still_finds_its_tags() {
        assert_eq!(tags_path("/spool/1234-0"), tags_path("/spool/1234-0.claim-9"));
        assert_eq!(
            tags_path("/spool/1234-0"),
            std::path::PathBuf::from("/spool/1234-0.tags")
        );
    }

    #[test]
    fn tags_round_trip_through_the_sidecar() {
        let encoded = encode_tags("feature/tags", "main");
        assert_eq!(
            decode_tags(&encoded),
            Some(("feature/tags".to_string(), "main".to_string()))
        );
        // An absent branch is the empty field, the same encoding the queue uses.
        assert_eq!(
            decode_tags(&encode_tags("", "main")),
            Some((String::new(), "main".to_string()))
        );
        assert_eq!(decode_tags(b"garbage"), None, "a torn write re-resolves");
    }

    // The CI branch column, which `tuist setup cache` writes only from inside a CI
    // job (the proxy is a launchd agent and never sees the provider's branch
    // variable). A branch recorded without a trunk keeps the trunk's place, so the
    // columns stay positional.
    #[test]
    fn sources_registry_reads_the_ci_branch_column() {
        let dir = std::env::temp_dir().join(format!("tuist-sources-ci-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("temp dir");
        let path = dir.join("registry.sources");
        std::fs::write(
            &path,
            "tuist/ci\t/src/ci\tmain\tfeature/x\n\
             tuist/no-trunk\t/src/no-trunk\t\tfeature/y\n\
             tuist/dev\t/src/dev\tmain\n",
        )
        .expect("write registry");

        let sources = load_sources(&path);
        let ci = sources.get("tuist/ci").expect("ci entry");
        assert_eq!(ci.trunk.as_deref(), Some("main"));
        assert_eq!(ci.ci_branch.as_deref(), Some("feature/x"));

        let no_trunk = sources.get("tuist/no-trunk").expect("no-trunk entry");
        assert_eq!(no_trunk.trunk, None, "the empty trunk column is not a trunk");
        assert_eq!(
            no_trunk.ci_branch.as_deref(),
            Some("feature/y"),
            "the branch is still found in its own column"
        );

        let dev = sources.get("tuist/dev").expect("dev entry");
        assert_eq!(
            dev.ci_branch, None,
            "a developer's row records no branch: the proxy reads git live"
        );

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn snapshot_decodes_the_server_wire_format() {
        // Hand-encode kura's format: two nodes, one key referencing both
        // (root first).
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"TSNP");
        bytes.push(2);
        bytes.extend_from_slice(&777u64.to_le_bytes());
        bytes.extend_from_slice(&2u32.to_le_bytes());
        for (llcas, blob_byte, size) in [(vec![0xAAu8, 0xBB], 7u8, 10u64), (vec![0xCC], 8, 20)] {
            bytes.push(llcas.len() as u8);
            bytes.extend_from_slice(&llcas);
            bytes.extend_from_slice(&[blob_byte; 32]);
            bytes.extend_from_slice(&size.to_le_bytes());
        }
        bytes.extend_from_slice(&1u32.to_le_bytes());
        bytes.extend_from_slice(&[5u8; 32]);
        bytes.extend_from_slice(&2u32.to_le_bytes());
        bytes.extend_from_slice(&1u32.to_le_bytes());
        bytes.extend_from_slice(&0u32.to_le_bytes());

        let snapshot = Snapshot::decode(&bytes).expect("decodes");
        assert_eq!(snapshot.watermark, 777);
        let manifest = snapshot.manifest(&[5u8; 32]).expect("key present");
        assert_eq!(manifest.len(), 2);
        // Root = the key's first node (index 1 = the [0xCC] node).
        assert_eq!(manifest[0].llcas_digest, vec![0xCC]);
        assert_eq!(manifest[0].blob.size_bytes, 20);
        assert_eq!(manifest[1].llcas_digest, vec![0xAA, 0xBB]);
        assert!(manifest.iter().all(|entry| entry.contents.is_none()));
        assert!(snapshot.manifest(&[6u8; 32]).is_none());
        // The per-node lookup fetch_object's snapshot fallback uses: llcas
        // digest -> the node's blob digest.
        let index = *snapshot
            .node_index
            .get(&vec![0xCCu8])
            .expect("node indexed");
        assert_eq!(snapshot.nodes[index as usize].1.size_bytes, 20);
        assert!(!snapshot.node_index.contains_key(&vec![0xFFu8]));

        // Structural violations refuse to decode rather than misparse.
        assert!(Snapshot::decode(&bytes[..bytes.len() - 1]).is_none());
        let mut bad_index = bytes.clone();
        let at = bad_index.len() - 4;
        bad_index[at..].copy_from_slice(&9u32.to_le_bytes());
        assert!(Snapshot::decode(&bad_index).is_none());

        // A delta merges by llcas digest: shared nodes dedup, new keys land,
        // the watermark advances.
        let mut delta_bytes = Vec::new();
        delta_bytes.extend_from_slice(b"TSNP");
        delta_bytes.push(2);
        delta_bytes.extend_from_slice(&900u64.to_le_bytes());
        delta_bytes.extend_from_slice(&2u32.to_le_bytes());
        for (llcas, blob_byte, size) in [(vec![0xEEu8], 3u8, 40u64), (vec![0xCC], 8, 20)] {
            delta_bytes.push(llcas.len() as u8);
            delta_bytes.extend_from_slice(&llcas);
            delta_bytes.extend_from_slice(&[blob_byte; 32]);
            delta_bytes.extend_from_slice(&size.to_le_bytes());
        }
        delta_bytes.extend_from_slice(&1u32.to_le_bytes());
        delta_bytes.extend_from_slice(&[9u8; 32]);
        delta_bytes.extend_from_slice(&2u32.to_le_bytes());
        delta_bytes.extend_from_slice(&0u32.to_le_bytes());
        delta_bytes.extend_from_slice(&1u32.to_le_bytes());
        let delta = Snapshot::decode(&delta_bytes).expect("delta decodes");
        let mut merged = snapshot.clone();
        merged.merge(&delta);
        assert_eq!(merged.watermark, 900);
        assert_eq!(merged.nodes.len(), 3, "shared [0xCC] node deduplicated");
        let new_key = merged.manifest(&[9u8; 32]).expect("delta key present");
        assert_eq!(new_key[0].llcas_digest, vec![0xEE]);
        assert_eq!(new_key[1].llcas_digest, vec![0xCC]);
        assert!(merged.manifest(&[5u8; 32]).is_some(), "existing key kept");
        // Wire order is the warm priority (the server encodes newest-first),
        // and merged delta keys — the newest — move to the front of it.
        assert_eq!(snapshot.key_order, vec![[5u8; 32]]);
        assert_eq!(merged.key_order, vec![[9u8; 32], [5u8; 32]]);
    }

    #[test]
    fn snapshot_decodes_the_compressed_envelope() {
        // A minimal valid TSNP body: one node, one key referencing it.
        let mut body = Vec::new();
        body.extend_from_slice(b"TSNP");
        body.push(2);
        body.extend_from_slice(&555u64.to_le_bytes());
        body.extend_from_slice(&1u32.to_le_bytes());
        body.push(1);
        body.push(0xAB);
        body.extend_from_slice(&[7u8; 32]);
        body.extend_from_slice(&10u64.to_le_bytes());
        body.extend_from_slice(&1u32.to_le_bytes());
        body.extend_from_slice(&[5u8; 32]);
        body.extend_from_slice(&1u32.to_le_bytes());
        body.extend_from_slice(&0u32.to_le_bytes());

        // Wrap it in the TSNZ envelope the way kura does and confirm the client
        // decodes the compressed and plain forms identically.
        let compressed = zstd::stream::encode_all(&body[..], 3).unwrap();
        let mut wire = Vec::new();
        wire.extend_from_slice(b"TSNZ");
        wire.push(1);
        wire.extend_from_slice(&(body.len() as u64).to_le_bytes());
        wire.extend_from_slice(&compressed);

        let from_zstd = Snapshot::decode(&wire).expect("compressed decodes");
        let from_plain = Snapshot::decode(&body).expect("plain decodes");
        assert_eq!(from_zstd.watermark, 555);
        assert_eq!(from_zstd.watermark, from_plain.watermark);
        assert_eq!(from_zstd.nodes.len(), from_plain.nodes.len());
        assert!(from_zstd.manifest(&[5u8; 32]).is_some());

        // A declared length that disagrees with the real body is a torn
        // payload: refuse rather than serve a half-decoded view.
        let mut wrong_len = wire.clone();
        wrong_len[5..13].copy_from_slice(&(body.len() as u64 + 1).to_le_bytes());
        assert!(Snapshot::decode(&wrong_len).is_none());

        // An absurd declared length must be rejected before allocating.
        let mut huge = wire.clone();
        huge[5..13].copy_from_slice(&(u64::MAX).to_le_bytes());
        assert!(Snapshot::decode(&huge).is_none());

        // Zip bomb: a stream that expands far past a small declared length must
        // be rejected — and the bounded decode stops one byte past `declared`
        // rather than expanding the whole stream. The stream here inflates to
        // 100 KiB while the envelope claims 8 bytes.
        let bomb_body = vec![0u8; 100 * 1024];
        let bomb_stream = zstd::stream::encode_all(&bomb_body[..], 3).unwrap();
        let mut bomb = Vec::new();
        bomb.extend_from_slice(b"TSNZ");
        bomb.push(1);
        bomb.extend_from_slice(&8u64.to_le_bytes());
        bomb.extend_from_slice(&bomb_stream);
        assert!(Snapshot::decode(&bomb).is_none());
    }

    #[test]
    fn demand_coalescer_routes_concurrent_fetches_correctly() {
        use std::sync::atomic::AtomicUsize;

        let coalescer = Arc::new(DemandCoalescer::new());
        // Sums digests.len() over every batch call: with each hash fetched at
        // most once, coalescing can only lower the CALL count, never change
        // this sum — so a total above the worker count would mean a hash was
        // fetched twice, and below it would mean one was dropped.
        let fetched_total = Arc::new(AtomicUsize::new(0));

        let digest = |n: u8| reapi::Digest {
            hash: reapi::hex(&[n; 32]),
            size_bytes: 3,
        };

        let mut handles = Vec::new();
        for n in 0..8u8 {
            let coalescer = coalescer.clone();
            let fetched_total = fetched_total.clone();
            handles.push(std::thread::spawn(move || {
                coalescer
                    .fetch(&digest(n), |digests| {
                        fetched_total.fetch_add(digests.len(), Ordering::SeqCst);
                        Ok(digests
                            .iter()
                            .map(|d| (d.hash.clone(), d.hash.clone().into_bytes()))
                            .collect())
                    })
                    .expect("fetch succeeds")
                    .expect("blob present")
            }));
        }
        for (n, handle) in handles.into_iter().enumerate() {
            let bytes = handle.join().unwrap();
            assert_eq!(
                bytes,
                digest(n as u8).hash.into_bytes(),
                "each worker gets its own blob"
            );
        }
        assert_eq!(
            fetched_total.load(Ordering::SeqCst),
            8,
            "every hash fetched exactly once across all batches"
        );
    }

    #[test]
    fn demand_coalescer_reports_missing_and_failure_per_waiter() {
        let coalescer = DemandCoalescer::new();
        let present = reapi::Digest {
            hash: reapi::hex(&[1; 32]),
            size_bytes: 3,
        };
        // A hash the batch read does not return is a miss (Ok(None)).
        let missing = coalescer
            .fetch(&present, |_| Ok(HashMap::new()))
            .expect("no transport error");
        assert!(missing.is_none(), "absent blob is a miss");

        // A present hash returns its bytes.
        let hit = coalescer
            .fetch(&present, |d| {
                Ok(d.iter().map(|d| (d.hash.clone(), vec![0xAB])).collect())
            })
            .expect("no transport error");
        assert_eq!(hit, Some(vec![0xAB]));

        // A transport error surfaces to the caller.
        let err = coalescer.fetch(&present, |_| Err("boom".to_string()));
        assert_eq!(err.unwrap_err(), "boom");
    }

    fn resolved_with(entries: Vec<(Vec<u8>, Resolution)>) -> Mutex<HashMap<Vec<u8>, Resolution>> {
        let mut map = HashMap::new();
        for (key, resolution) in entries {
            map.insert(key, resolution);
        }
        Mutex::new(map)
    }

    // The reported bug: a long-lived proxy caches an action-cache Hit, the user
    // wipes DerivedData, and the next resolve returns the stale Hit for a value
    // graph no longer on disk (compiler fails with `missing object`). The fix
    // makes the fast path verify presence: a Hit whose value object is gone must
    // NOT be served, and the path's stale in-memory state must be invalidated so
    // the re-resolve re-materializes the graph.
    #[test]
    fn cached_hit_with_wiped_value_reresolves_and_invalidates() {
        let key = b"action-key".to_vec();
        let value = b"value-digest".to_vec();
        let resolved = resolved_with(vec![(key.clone(), Resolution::Hit(value.clone()))]);

        let invalidated = Cell::new(false);
        let decision = fast_path(
            &resolved,
            &key,
            |probed| {
                assert_eq!(probed, value.as_slice());
                false // value object absent on disk (wiped)
            },
            || invalidated.set(true),
        );

        assert!(matches!(decision, FastPath::Resolve));
        assert!(
            invalidated.get(),
            "a Hit whose value object is missing must invalidate the path's stale caches"
        );
    }

    // The warm path must stay fast: a Hit whose value object is present is served
    // directly, without invalidation.
    #[test]
    fn cached_hit_present_is_served() {
        let key = b"action-key".to_vec();
        let value = b"value-digest".to_vec();
        let resolved = resolved_with(vec![(key.clone(), Resolution::Hit(value.clone()))]);

        let decision = fast_path(
            &resolved,
            &key,
            |_| true,
            || panic!("a present Hit must not invalidate"),
        );

        match decision {
            FastPath::Hit(served) => assert_eq!(served, value),
            _ => panic!("expected the present Hit to be served"),
        }
    }

    // A fresh negative is answered without a round trip and without probing disk.
    #[test]
    fn fresh_miss_is_served_without_probe() {
        let key = b"action-key".to_vec();
        let resolved = resolved_with(vec![(key.clone(), Resolution::Miss(Instant::now()))]);

        let decision = fast_path(
            &resolved,
            &key,
            |_| panic!("a Miss must not probe the value object"),
            || panic!("a Miss must not invalidate"),
        );

        assert!(matches!(decision, FastPath::Miss));
    }

    // A miss older than NEGATIVE_TTL falls through to a full resolve so a key
    // published later (by another machine) can still land.
    #[test]
    fn stale_miss_falls_through_to_resolve() {
        let key = b"action-key".to_vec();
        let stale = Instant::now() - NEGATIVE_TTL - Duration::from_secs(1);
        let resolved = resolved_with(vec![(key.clone(), Resolution::Miss(stale))]);

        let decision = fast_path(
            &resolved,
            &key,
            |_| panic!("a stale Miss must not probe the value object"),
            || panic!("a stale Miss must not invalidate"),
        );

        assert!(matches!(decision, FastPath::Resolve));
    }

    // No cache entry falls through to a full resolve.
    #[test]
    fn absent_key_falls_through_to_resolve() {
        let resolved = resolved_with(vec![]);

        let decision = fast_path(
            &resolved,
            b"unknown-key",
            |_| panic!("an absent key must not probe the value object"),
            || panic!("an absent key must not invalidate"),
        );

        assert!(matches!(decision, FastPath::Resolve));
    }

    // A present path idle less than IDLE_RECLAIM is kept.
    #[test]
    fn active_path_is_not_reclaimed() {
        assert!(!should_reclaim(Duration::from_secs(0), false));
        assert!(!should_reclaim(
            IDLE_RECLAIM - Duration::from_secs(1),
            false
        ));
    }

    // A present path idle past IDLE_RECLAIM is reclaimed.
    #[test]
    fn long_idle_path_is_reclaimed() {
        assert!(should_reclaim(IDLE_RECLAIM + Duration::from_secs(1), false));
    }

    // A path whose on-disk CAS is gone is reclaimed immediately, however recently
    // it was used (a deleted project/worktree never comes back).
    #[test]
    fn gone_cas_dir_is_reclaimed_regardless_of_idle() {
        assert!(should_reclaim(Duration::from_secs(0), true));
        assert!(should_reclaim(IDLE_RECLAIM + Duration::from_secs(1), true));
    }

    // A build that touched the CAS moments ago holds off a refresh, however
    // quiet the CPU looks: between two bursts of compiles the load average has
    // not caught up yet, and the build is exactly who we would be stealing from.
    #[test]
    fn recent_build_holds_off_a_refresh() {
        let reason = busy_verdict(Some(BUSY_AFTER_LAST_OP - Duration::from_secs(1)), Some(0.0));
        assert!(reason.is_some_and(|reason| reason.contains("build")));
    }

    // Once the build is long done and the machine is quiet, the refresh runs.
    #[test]
    fn quiet_machine_refreshes() {
        assert!(
            busy_verdict(Some(BUSY_AFTER_LAST_OP + Duration::from_secs(1)), Some(0.1)).is_none()
        );
        // A proxy that has served nothing yet has no last op to go on.
        assert!(busy_verdict(None, Some(0.1)).is_none());
    }

    // Something other than a build can keep the machine busy: it never touches
    // the CAS, so load is the only thing that sees it.
    #[test]
    fn loaded_machine_holds_off_a_refresh_with_no_build() {
        let reason = busy_verdict(
            Some(BUSY_AFTER_LAST_OP + Duration::from_secs(1)),
            Some(BUSY_LOAD_PER_CORE + 0.1),
        );
        assert!(reason.is_some_and(|reason| reason.contains("load")));
    }

    // A platform that will not report load must not wedge the refresh forever.
    #[test]
    fn unknown_load_does_not_hold_off_a_refresh() {
        assert!(busy_verdict(Some(BUSY_AFTER_LAST_OP + Duration::from_secs(1)), None).is_none());
    }

    fn generation(ino: u64, birth_nanos: u128) -> CasGeneration {
        CasGeneration { ino, birth_nanos }
    }

    // A recreated CAS directory (a wipe) is a change; a stable one, the first
    // observation, and a disappeared directory are not.
    #[test]
    fn generation_change_is_detected_only_on_recreate() {
        let g1 = generation(1, 100);
        let g2 = generation(2, 200);
        assert!(generation_changed(Some(g1), Some(g2)));
        assert!(generation_changed(Some(g2), Some(g1)));
        assert!(!generation_changed(Some(g1), Some(g1)));
        assert!(
            !generation_changed(None, Some(g1)),
            "first observation is not a change"
        );
        assert!(
            !generation_changed(Some(g1), None),
            "a gone dir is left to reclaim_idle"
        );
    }

    // A resolve's writes commit only if the generation it observed still holds;
    // a wipe/prune that advanced the counter mid-resolve drops them.
    #[test]
    fn writes_commit_only_on_the_observed_generation() {
        assert!(committable(7, 7));
        assert!(
            !committable(7, 8),
            "an advanced generation must drop stale writes"
        );
    }

    // Keylog lines round-trip: lowercase hex parses back to the raw key; blank
    // and malformed lines are dropped rather than corrupting the wavefront.

    // Deleting and recreating a directory at the same path yields a different
    // generation, which is the signal check_generation invalidates on. This is
    // the exact DerivedData-wipe reproduction, at the filesystem layer.
    #[test]
    fn recreated_directory_has_a_new_generation() {
        let dir = std::env::temp_dir().join(format!("cas-generation-{}", std::process::id()));
        let path = dir.to_string_lossy().into_owned();

        std::fs::create_dir_all(&dir).unwrap();
        let before = cas_generation(&path);

        std::fs::remove_dir_all(&dir).unwrap();
        std::fs::create_dir_all(&dir).unwrap();
        let after = cas_generation(&path);

        let _ = std::fs::remove_dir_all(&dir);

        assert!(before.is_some() && after.is_some());
        assert_ne!(
            before, after,
            "a recreated CAS directory must read as a new generation"
        );
    }

    // A Proxy with no remote: the wipe tests only drive `check_generation`,
    // which is local-only (restat, rebind, drop marks).
    fn test_proxy() -> &'static Proxy {
        Proxy::new(
            "http://127.0.0.1:1".to_string(),
            crate::token::TokenProvider::from_env(),
            crate::upstream_path(),
            None,
            None,
        )
    }

    // Builds a PathState over a real on-disk CAS at `path`, the way `path_state`
    // does, so the wipe tests drive the production probe rather than a copy.
    fn path_state_for(path: &str) -> &'static PathState {
        let up = unsafe { Upstream::load(&crate::upstream_path()).unwrap() };
        let up: &'static Upstream = Box::leak(Box::new(up));
        let cas = unsafe { open_cas(up, path).unwrap() };
        Box::leak(Box::new(PathState {
            up,
            cas: RwLock::new(cas),
            cas_path: path.to_string(),
            generation: Mutex::new(cas_generation(path)),
            gen_counter: AtomicU64::new(0),
            resolved: Mutex::new(HashMap::new()),
            inflight: Mutex::new(HashSet::new()),
            inflight_cvar: Condvar::new(),
            known_local: std::array::from_fn(|_| Mutex::new(HashSet::new())),
            publish_cache: Mutex::new(HashMap::new()),
            last_used: AtomicU64::new(0),
            pending_objects: Mutex::new(HashMap::new()),
            stats_resolves: AtomicU64::new(0),
            stats_remote_hits: AtomicU64::new(0),
            stats_misses: AtomicU64::new(0),
            stats_snapshot_hits: AtomicU64::new(0),
            stats_demand_fetched: AtomicU64::new(0),
            stats_blobs_fetched: AtomicU64::new(0),
            stats_blobs_inlined: AtomicU64::new(0),
            stats_published: AtomicU64::new(0),
            ms_action: AtomicU64::new(0),
            ms_filter: AtomicU64::new(0),
            ms_fetch: AtomicU64::new(0),
            ms_decode: AtomicU64::new(0),
            ms_store: AtomicU64::new(0),
        }))
    }

    // Stores a childless object and returns its digest.
    fn store_probe_object(state: &PathState, payload: &[u8]) -> Vec<u8> {
        unsafe {
            let cas = *state.cas.read().unwrap();
            let data = llcas_data_t {
                data: payload.as_ptr() as *const std::ffi::c_void,
                size: payload.len(),
            };
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut std::ffi::c_char = std::ptr::null_mut();
            assert!(
                !(state.up.llcas_cas_store_object)(
                    cas,
                    data,
                    std::ptr::null(),
                    0,
                    &mut id,
                    &mut error
                ),
                "store must succeed"
            );
            let digest = (state.up.llcas_objectid_get_digest)(cas, id);
            std::slice::from_raw_parts(digest.data, digest.size).to_vec()
        }
    }

    struct TempCasDir(std::path::PathBuf);

    impl TempCasDir {
        fn new(tag: &str) -> Self {
            let dir = std::env::temp_dir().join(format!("cas-{tag}-{}", std::process::id()));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(&dir).unwrap();
            Self(dir)
        }
        fn path(&self) -> String {
            self.0.to_string_lossy().into_owned()
        }
        // The user action: `rm -rf DerivedData`, then the build recreates it.
        fn wipe(&self) {
            std::fs::remove_dir_all(&self.0).unwrap();
            std::fs::create_dir_all(&self.0).unwrap();
        }
    }

    impl Drop for TempCasDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    // The regression this whole guard exists for. An llcas handle pins the store
    // it opened: after the directory is wiped, the pre-wipe handle still answers
    // from the deleted inodes, so `load_present` reports objects the compiler
    // cannot see. `is_local` trusts it, skips re-fetching, and clang -- which
    // FAILS rather than recompiles on a missing object -- breaks the build.
    // Rebinding the handle is what makes the probe authoritative again.
    #[test]
    fn load_present_does_not_answer_from_a_wiped_store() {
        let dir = TempCasDir::new("wipe-read");
        let state = path_state_for(&dir.path());
        let digest = store_probe_object(state, b"tuist-cas-wipe-probe");
        assert!(
            state.load_present(&digest),
            "sanity: the object is present before the wipe"
        );

        dir.wipe();
        state.reopen_cas().unwrap();

        assert!(
            !state.load_present(&digest),
            "a wiped store must read as empty: reporting the object present              skips the re-fetch and fails the compiler with `missing object`"
        );
    }

    // The write half: a store through a pre-wipe handle reports success but
    // lands in the deleted store, so re-fetching alone could never heal the
    // build. After rebinding, what the proxy writes is what the compiler reads.
    #[test]
    fn stores_after_a_wipe_land_in_the_live_store() {
        let dir = TempCasDir::new("wipe-write");
        let state = path_state_for(&dir.path());

        dir.wipe();
        state.reopen_cas().unwrap();

        let digest = store_probe_object(state, b"stored-after-the-wipe");
        // A handle opened fresh is what the compiler in its own process gets.
        let compiler_view = path_state_for(&dir.path());
        assert!(
            compiler_view.load_present(&digest),
            "an object stored after the wipe must be visible to a handle opened              independently: otherwise the proxy is writing into a deleted store"
        );
    }

    /// The idle gate reads `last_used`, and a build that has finished planning
    /// does nothing but demand fetches. If they do not count as activity, the
    /// machine looks idle exactly while it is most bandwidth-bound.
    #[test]
    fn a_demand_fetch_counts_as_the_machine_being_busy() {
        let dir = TempCasDir::new("busy-fetch");
        let state = path_state_for(&dir.path());
        let proxy = test_proxy();
        // A sentinel rather than 0: the proxy's epoch is fresh here, so a real
        // stamp is ~0ms and would be indistinguishable from never having run.
        state.last_used.store(u64::MAX, Ordering::Relaxed);

        let _ = proxy.fetch_object(state, &dir.path(), "", &[0xAB; 32]);

        assert!(
            state.last_used.load(Ordering::Relaxed) < u64::MAX,
            "a demand fetch must keep the machine marked busy, or the idle gate \
             starts competing with the build it is meant to avoid"
        );
    }

    /// The reclaim path only works if a trunk hit can still be asked for after a
    /// feature hit for the same action. On a shared runner that ordering is
    /// routine, and a dedup keyed on the action alone would suppress the trunk
    /// hit for the proxy's lifetime, quietly disabling the mechanism the whole
    /// scoping leans on.
    #[test]
    fn a_refresh_is_distinct_per_instance_and_per_tag() {
        let dir = std::env::temp_dir().join(format!("tuist-refresh-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let registry = dir.join("registry");
        let sources = sources_path_for(&registry);
        let record = |branch: &str| {
            std::fs::write(
                &sources,
                format!(
                    "tuist/one\t/src/one\tmain\t{branch}\ntuist/two\t/src/two\tmain\t{branch}\n"
                ),
            )
            .expect("write sources");
        };
        record("feature");

        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            String::new(),
            Some(registry),
            None,
        );
        let manifest = vec![ManifestEntry {
            llcas_digest: vec![0xAA],
            blob: reapi::Digest {
                hash: "bb".repeat(32),
                size_bytes: 7,
            },
            contents: None,
        }];
        let queued = || proxy.view_refresh.lock().unwrap().len();
        let one = proxy.remote_for("tuist/one");

        proxy.queue_view_refresh(&one, "tuist/one", b"shared-key", &manifest);
        assert_eq!(queued(), 1);
        // Same everything: the second one is the same work.
        proxy.queue_view_refresh(&one, "tuist/one", b"shared-key", &manifest);
        assert_eq!(queued(), 1, "an identical refresh is not queued twice");

        // Same action, another project. Keys collide across instances.
        let two = proxy.remote_for("tuist/two");
        proxy.queue_view_refresh(&two, "tuist/two", b"shared-key", &manifest);
        assert_eq!(queued(), 2, "another project's identical key is its own refresh");

        // The trunk job now takes a hit on the key the feature job refreshed.
        record("main");
        proxy.source_cache.lock().unwrap().clear();
        proxy.queue_view_refresh(&one, "tuist/one", b"shared-key", &manifest);
        assert_eq!(
            queued(),
            3,
            "a trunk hit reclaims a key a feature hit refreshed first: suppressing \
             it would disable the reclaim path entirely"
        );

        std::fs::remove_dir_all(&dir).ok();
    }

    /// The remote here cannot be reached, so the drain fails, which is the point:
    /// a refresh that did not happen must be askable again.
    #[test]
    fn a_failed_refresh_can_be_asked_for_again() {
        let dir = std::env::temp_dir().join(format!("tuist-refresh-fail-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let registry = dir.join("registry");
        std::fs::write(
            sources_path_for(&registry),
            "tuist/one\t/src/one\tmain\tmain\n",
        )
        .expect("write sources");

        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            String::new(),
            Some(registry),
            None,
        );
        let manifest = vec![ManifestEntry {
            llcas_digest: vec![0xAA],
            blob: reapi::Digest {
                hash: "bb".repeat(32),
                size_bytes: 7,
            },
            contents: None,
        }];
        let one = proxy.remote_for("tuist/one");

        proxy.queue_view_refresh(&one, "tuist/one", b"key", &manifest);
        assert_eq!(proxy.view_refresh.lock().unwrap().len(), 1);
        proxy.refresh_view_keys();
        assert_eq!(
            proxy.view_refresh.lock().unwrap().len(),
            0,
            "the failed item is dropped from the queue"
        );

        proxy.queue_view_refresh(&one, "tuist/one", b"key", &manifest);
        assert_eq!(
            proxy.view_refresh.lock().unwrap().len(),
            1,
            "and it can be queued again, which is what the retry comment promises"
        );

        std::fs::remove_dir_all(&dir).ok();
    }

    /// `upload: false` has to hold for the whole build, and only the proxy can
    /// make it. The plugin checks a compiler option, which reaches Swift;
    /// swift-build's Clang caching creates its CAS with a plugin path and NO
    /// options, so that lane never sees the project's answer and asks to publish
    /// regardless. Its records arrive at `enqueue_publish`, and so do the
    /// sweeper's, which is why the refusal lives there and not in the client.
    #[test]
    fn a_read_only_project_publishes_nothing_and_refreshes_nothing() {
        let dir = std::env::temp_dir().join(format!("tuist-upload-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let registry = dir.join("registry");
        let sources = sources_path_for(&registry);
        std::fs::write(
            &sources,
            "tuist/reader\t/src/reader\tmain\t\t0\ntuist/writer\t/src/writer\tmain\n",
        )
        .expect("write sources");

        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            String::new(),
            Some(registry),
            None,
        );
        let captured: Arc<Mutex<Vec<Vec<u8>>>> = Arc::new(Mutex::new(Vec::new()));
        let sink = Arc::clone(&captured);
        proxy
            .publisher
            .configure(1, move |item| sink.lock().unwrap().push(item));

        // What the Clang lane does: it never saw the option, so it asks.
        proxy.enqueue_publish("/cas", "tuist/reader", "/spool/from-the-clang-lane");
        proxy
            .publisher
            .drain_stop_timeout(std::time::Duration::from_secs(10));
        assert!(
            captured.lock().unwrap().is_empty(),
            "a project that opted out publishes nothing, however the record got here"
        );

        let manifest = vec![ManifestEntry {
            llcas_digest: vec![0xAA],
            blob: reapi::Digest {
                hash: "bb".repeat(32),
                size_bytes: 7,
            },
            contents: None,
        }];
        let remote = proxy.remote_for("tuist/reader");
        proxy.queue_view_refresh(&remote, "tuist/reader", b"key-1", &manifest);
        assert_eq!(
            proxy.view_refresh.lock().unwrap().len(),
            0,
            "and it does not write on the proxy's own initiative either"
        );

        // A project that did not opt out is untouched.
        let remote = proxy.remote_for("tuist/writer");
        proxy.queue_view_refresh(&remote, "tuist/writer", b"key-2", &manifest);
        assert_eq!(proxy.view_refresh.lock().unwrap().len(), 1);

        std::fs::remove_dir_all(&dir).ok();
    }

    // A demand fetch is a door into the same store, and it does not have to come
    // after a resolve: the compiler asks for an object the moment it fails to
    // load one. If a wipe lands in between, this is the first thing to touch the
    // dead handle, and answering "present" from it tells the compiler an object
    // is there that its own live CAS has never seen.
    #[test]
    fn a_demand_fetch_arriving_first_after_a_wipe_does_not_answer_from_the_dead_store() {
        let dir = TempCasDir::new("wipe-fetch");
        let state = path_state_for(&dir.path());
        let digest = store_probe_object(state, b"present-before-the-wipe");
        let proxy = test_proxy();
        assert!(
            proxy
                .fetch_object(state, &dir.path(), "", &digest)
                .expect("fetch should not error"),
            "sanity: served from the live store before the wipe"
        );

        // No resolve in between: the wipe, then the fetch.
        dir.wipe();

        assert!(
            !proxy
                .fetch_object(state, &dir.path(), "", &digest)
                .expect("fetch should not error"),
            "a fetch after a wipe must not report an object the compiler's own CAS \
             cannot see: that is the `missing object` this rebind exists to prevent"
        );
    }

    // check_generation is the only caller that rebinds, and it must do so from
    // the wipe signal alone -- the marks it drops are worthless while the handle
    // they get re-learned through still points at the deleted store.
    #[test]
    fn a_wipe_rebinds_the_handle_and_drops_the_marks() {
        let dir = TempCasDir::new("wipe-guard");
        let state = path_state_for(&dir.path());
        let digest = store_probe_object(state, b"marked-local-before-the-wipe");
        state.shard(&digest).lock().unwrap().insert(digest.clone());
        let before = state.gen_counter.load(Ordering::SeqCst);

        dir.wipe();
        let proxy = test_proxy();
        proxy.check_generation(state);

        assert!(
            state.gen_counter.load(Ordering::SeqCst) > before,
            "a wipe must advance the generation so in-flight writes are dropped"
        );
        assert!(
            !state.shard(&digest).lock().unwrap().contains(&digest),
            "the known-local mark must be dropped"
        );
        assert!(
            !state.load_present(&digest),
            "and the probe behind it must now read the live store"
        );
    }
}
