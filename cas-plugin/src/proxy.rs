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
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant, UNIX_EPOCH};

use crate::proxy_proto::{
    read_request, write_response, Request, OP_FETCH_OBJECT, OP_INVALIDATE, OP_PUBLISH, OP_RESOLVE,
    STATUS_ERROR,
    STATUS_HIT, STATUS_MISS,
};
use crate::prefetch::Prefetcher;
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

/// Read-ahead bounds: a warm CLI-sized build demands ~11k action keys, so the
/// key cap sits well above one build's set while bounding the on-disk log; the
/// error cap stops the wavefront early when the remote is unreachable.
const MAX_KEYLOG_KEYS: usize = 200_000;
const MAX_READAHEAD_ERRORS: u64 = 32;

/// Read-ahead wavefront width. RTT-bound work: at ~60ms per resolve, 32 workers
/// replay ~11k keys in ~20s, against a multiplexed h2 channel the server side
/// parallelizes. `TUIST_CAS_READAHEAD=0` disables read-ahead entirely.
fn readahead_workers() -> usize {
    std::env::var("TUIST_CAS_READAHEAD")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(64)
}

/// Parses one lowercase-hex keylog line back into raw key bytes.
fn unhex_line(line: &str) -> Option<Vec<u8>> {
    let line = line.trim();
    if line.is_empty() || line.len() % 2 != 0 {
        return None;
    }
    (0..line.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&line[i..i + 2], 16).ok())
        .collect()
}

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
    Some(CasGeneration { ino: meta.ino(), birth_nanos })
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
    cas: llcas_cas_t,
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
    // Read-ahead: action keys requested against this path, persisted by the
    // maintenance loop and speculatively re-resolved (in parallel, off the
    // build's critical path) at the start of the next build. The demand path
    // is serial — the build system and compilers ask one key at a time — so on
    // a real-RTT link a warm build otherwise degenerates into a chain of
    // round trips (measured 702s vs a 176s local floor at ~59ms RTT).
    // Order matters: the log preserves DEMAND order, so the next build's
    // wavefront replays keys in the order the build will ask for them and
    // stays ahead of the serial demand path (a hash-ordered replay left ~65%
    // of demand lookups paying their own round trip; measured 411s vs the
    // ordered target near the local floor).
    keylog: Mutex<(Vec<Vec<u8>>, HashSet<Vec<u8>>)>,
    keylog_dirty: std::sync::atomic::AtomicBool,
    // Whether the read-ahead wavefront was already started for this path (one
    // per build: re-armed when the on-disk CAS is wiped or the path idles out).
    readahead_armed: std::sync::atomic::AtomicBool,
    // llcas digest -> how to fetch its frame blob, for every node of every
    // value graph this proxy has answered. Inserted right after get_action
    // (before the resolve replies); once a node is stored locally its inlined
    // bytes are dropped but the digest-only instruction is RETAINED — the
    // build system prunes the on-disk CAS mid-build, and a pruned object
    // under an already-served Hit must stay producible through
    // OP_FETCH_OBJECT (clang fails the build on a missing object). Bounded by
    // the namespace's unique node count at ~100B per entry; content-addressed,
    // so entries stay valid across invalidations and wipes.
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
pub struct Snapshot {
    nodes: Vec<(Vec<u8>, reapi::Digest)>,
    keys: HashMap<[u8; 32], Vec<u32>>,
}

/// Per-instance snapshot lifecycle: fetched once, in the background, off every
/// resolve path. While `Fetching` (or after `Absent`), resolves use the
/// ordinary per-key path.
enum SnapshotState {
    Fetching,
    Ready(Arc<Snapshot>),
    Absent,
}

impl Snapshot {
    /// Decodes the server's snapshot wire format (see kura's
    /// `encode_actioncache_snapshot`): `"TSNP"` + version byte, node table,
    /// per-key node-index lists. `None` on any structural violation — the
    /// caller stays on the per-key path rather than trusting a torn payload.
    fn decode(bytes: &[u8]) -> Option<Snapshot> {
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
        if take(&mut bytes, 4)? != b"TSNP" || take(&mut bytes, 1)? != [1] {
            return None;
        }
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
        }
        Some(Snapshot { nodes, keys })
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
        for shard in &self.known_local {
            shard.lock().unwrap().clear();
        }
        // The local store may have lost objects: re-run the read-ahead
        // wavefront so they are re-materialized off the critical path (keys
        // still resolved in the map turn into cheap local presence probes).
        self.readahead_armed
            .store(false, std::sync::atomic::Ordering::SeqCst);
        // `pending_objects` is also KEPT: entries are content-addressed fetch
        // instructions, valid for any incarnation of the store — after a wipe
        // they let demand loads refill exactly what is asked for.
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
    paths: Mutex<HashMap<String, &'static PathState>>,
    publisher: Prefetcher,
    // Read-ahead pool: replays the previous build's key set through `resolve`
    // in parallel at the start of a build, so the serial demand path finds its
    // keys already resolved and its graphs already materialized. Items encode
    // (instance, cas_path, key) like publisher items. Damped on transport
    // errors so an unreachable remote cannot turn the wavefront into a storm.
    readahead: Prefetcher,
    readahead_errors: AtomicU64,
    readahead_done: AtomicU64,
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
    materialize_jobs: Mutex<HashMap<u64, MaterializeJob>>,
    job_counter: AtomicU64,
    // instance -> action-cache snapshot lifecycle. Kicked off in the
    // background on an instance's first resolve; while it is in flight (or
    // when the server has none) resolves use the per-key path.
    snapshots: Mutex<HashMap<String, SnapshotState>>,
    keylog_dir: Option<PathBuf>,
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
        let path_instance = registry_path.as_deref().map(load_registry).unwrap_or_default();
        let keylog_dir = registry_path
            .as_deref()
            .and_then(Path::parent)
            .map(|parent| parent.join("cas-keylogs"));
        let proxy: &'static Proxy = Box::leak(Box::new(Proxy {
            grpc_url,
            tokens,
            upstream_plugin,
            epoch: Instant::now(),
            remotes: Mutex::new(HashMap::new()),
            path_instance: Mutex::new(path_instance),
            registry_path,
            paths: Mutex::new(HashMap::new()),
            publisher: Prefetcher::new(),
            readahead: Prefetcher::new(),
            readahead_errors: AtomicU64::new(0),
            readahead_done: AtomicU64::new(0),
            materializer: Prefetcher::new(),
            materialize_jobs: Mutex::new(HashMap::new()),
            job_counter: AtomicU64::new(0),
            snapshots: Mutex::new(HashMap::new()),
            unprimed: AtomicU64::new(0),
            keylog_dir,
            analytics,
        }));
        let proxy_addr = proxy as *const Proxy as usize;
        proxy.publisher.configure(8, move |item| {
            let proxy = unsafe { &*(proxy_addr as *const Proxy) };
            proxy.publish_item(&item);
        });
        proxy.readahead.configure(readahead_workers(), move |item| {
            let proxy = unsafe { &*(proxy_addr as *const Proxy) };
            proxy.readahead_item(&item);
        });
        // Demand jobs arrive at the build engine's serial rate, so a small
        // pool keeps up; the wavefront's bulk work does not flow through here.
        proxy.materializer.configure(16, move |item| {
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
        if !declared.is_empty() {
            let mut map = self.path_instance.lock().unwrap();
            if map.get(cas_path).map(String::as_str) != Some(declared) {
                map.insert(cas_path.to_string(), declared.to_string());
                self.persist_registry(&map);
            }
            return Some(declared.to_string());
        }
        self.path_instance.lock().unwrap().get(cas_path).cloned()
    }

    fn persist_registry(&self, map: &HashMap<String, String>) {
        let Some(path) = &self.registry_path else { return };
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
            cas,
            cas_path: cas_path.to_string(),
            generation: Mutex::new(cas_generation(cas_path)),
            gen_counter: AtomicU64::new(0),
            resolved: Mutex::new(HashMap::new()),
            inflight: Mutex::new(HashSet::new()),
            inflight_cvar: Condvar::new(),
            known_local: std::array::from_fn(|_| Mutex::new(HashSet::new())),
            publish_cache: Mutex::new(HashMap::new()),
            last_used: AtomicU64::new(self.epoch.elapsed().as_millis() as u64),
            keylog: Mutex::new((Vec::new(), HashSet::new())),
            keylog_dirty: std::sync::atomic::AtomicBool::new(false),
            readahead_armed: std::sync::atomic::AtomicBool::new(false),
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
    /// `demand` marks a resolve issued by a compiler over the unix socket.
    /// Those run on swift-build's SERIAL task-setup path — the llbuild engine
    /// thread that schedules every task in the build — so they answer right
    /// after the action lookup and leave graph materialization to the
    /// background pool (a demand load that outruns it self-heals through
    /// OP_FETCH_OBJECT). Wavefront resolves (`demand = false`) materialize
    /// inline: they run on the read-ahead pool where blocking is free, and
    /// inline work bounds how much fetched-but-unstored data sits in memory.
    fn resolve(
        &self,
        remote: &Arc<Remote>,
        state: &'static PathState,
        key: &[u8],
        demand: bool,
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
        // For a DEMAND caller, a value that is not on disk but has registered
        // fetch instructions is as good as present: the materializer is
        // filling it in and demand loads self-heal through OP_FETCH_OBJECT,
        // so don't force a re-resolve (a duplicate action lookup on the
        // engine thread). The WAVEFRONT must not take that shortcut:
        // instructions are retained after materialization, so post-wipe they
        // exist for everything, and accepting them would skip the bulk
        // re-materialization that is the wavefront's whole job (leaving every
        // object to a serial per-load demand fetch).
        match fast_path(
            &state.resolved,
            key,
            |value| self.load_present(state, value) || (demand && state.fetchable(value)),
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
                return self
                    .commit_and_materialize(remote, state, key, manifest, observed, demand);
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
                    Some(Resolution::Miss(at)) if at.elapsed() < NEGATIVE_TTL => {
                        return Ok(None)
                    }
                    _ => None,
                };
                if let Some(value) = peeked {
                    if self.load_present(state, &value) || (demand && state.fetchable(&value)) {
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
        let outcome = self.resolve_uncached(remote, state, key, observed, demand);
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
        state: &'static PathState,
        key: &[u8],
        observed: u64,
        demand: bool,
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
        let action_ms = phase.elapsed().as_millis() as u64;
        state.ms_action.fetch_add(action_ms, Ordering::Relaxed);

        if let Some(analytics) = &self.analytics {
            analytics.record_keyvalue(key, "read", op_start.elapsed().as_secs_f64());
        }
        self.commit_and_materialize(remote, state, key, manifest, observed, demand)
    }

    /// Answers a resolve from a known manifest: commit the Hit, register every
    /// node's fetch instructions, then materialize — in the background for a
    /// demand caller (the build engine's serial task-setup thread, where every
    /// millisecond spent here is a millisecond no other task gets scheduled),
    /// inline for the wavefront. Shared by the action-lookup path and the
    /// snapshot path.
    fn commit_and_materialize(
        &self,
        remote: &Arc<Remote>,
        state: &'static PathState,
        key: &[u8],
        manifest: Vec<ManifestEntry>,
        observed: u64,
        demand: bool,
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
        if demand {
            self.enqueue_materialize(state, remote, manifest, observed);
        } else {
            // Wavefront path: materialize inline. The Hit is already committed
            // and every node has fetch instructions, so an error here only
            // dampens the wavefront — demand loads self-heal per object.
            self.materialize_manifest(remote, state, &manifest, observed)?;
        }
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
                if let Some(instruction) =
                    state.pending_objects.lock().unwrap().get_mut(&entry.llcas_digest)
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
        let Ok(id_bytes) = <[u8; 8]>::try_from(item) else { return };
        let job = self
            .materialize_jobs
            .lock()
            .unwrap()
            .remove(&u64::from_be_bytes(id_bytes));
        let Some(job) = job else { return };
        let Ok(state) = self.path_state(&job.cas_path) else { return };
        if let Err(message) =
            self.materialize_manifest(&job.remote, state, &job.manifest, job.observed)
        {
            crate::log_line(&format!("background materialize failed: {message}"));
        }
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
        if self.load_present(state, digest) {
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
                .map(|(blob, _refs)| PendingFetch { blob: blob.clone(), contents: None })
        });
        let Some(pending) = pending else { return Ok(false) };
        let blob_bytes = match pending.contents {
            Some(bytes) => bytes,
            None => {
                let Some(instance) = self.resolve_instance(cas_path, declared_instance) else {
                    return Ok(false);
                };
                let remote = self.remote_for(&instance);
                let contents = remote.batch_read(&[pending.blob.clone()])?;
                match contents.get(&pending.blob.hash) {
                    Some(bytes) => bytes.clone(),
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
        if let Some(instruction) = state.pending_objects.lock().unwrap().get_mut(digest) {
            instruction.contents = None;
        }
        state.stats_demand_fetched.fetch_add(1, Ordering::Relaxed);
        Ok(true)
    }

    /// Detects a wiped-and-recreated on-disk CAS (a deleted DerivedData under
    /// this long-lived proxy) from a change in the CAS directory's identity and
    /// drops the now-stale in-memory marks (`resolved`, `known_local`,
    /// `publish_cache`) so a resolve re-probes and re-materializes authoritatively.
    /// Called at the head of every resolve, so it covers uncached/changed keys
    /// and parallel builds, not only re-requested cached Hits. The generation
    /// lock is held across the invalidation so a concurrent resolve can't observe
    /// the new generation as unchanged and filter against `known_local` while it
    /// is being cleared.
    fn check_generation(&self, state: &PathState) {
        let Some(current) = cas_generation(&state.cas_path) else { return };
        let mut stored = state.generation.lock().unwrap();
        if generation_changed(*stored, Some(current)) {
            state.invalidate();
            state.publish_cache.lock().unwrap().clear();
        }
        *stored = Some(current);
    }

    fn is_local(&self, state: &PathState, observed: u64, digest: &[u8]) -> bool {
        if state.shard(digest).lock().unwrap().contains(digest) {
            return true;
        }
        if self.load_present(state, digest) {
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

    /// Authoritative on-disk presence for `digest`: an actual llcas load, the
    /// same call the consumer will make, bypassing the known-local cache. Used
    /// both by `is_local` (which memoizes a positive result) and to guard a
    /// cached Hit against a wiped local CAS, where the in-memory marks lie.
    fn load_present(&self, state: &PathState, digest: &[u8]) -> bool {
        unsafe {
            let digest_t = llcas_digest_t { data: digest.as_ptr(), size: digest.len() };
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut std::ffi::c_char = std::ptr::null_mut();
            if (state.up.llcas_cas_get_objectid)(state.cas, digest_t, &mut id, &mut error) {
                if !error.is_null() {
                    (state.up.llcas_string_dispose)(error);
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
                (state.up.llcas_cas_contains_object)(state.cas, id, false, &mut contains_error);
            if !contains_error.is_null() {
                (state.up.llcas_string_dispose)(contains_error);
            }
            result == LLCAS_LOOKUP_RESULT_SUCCESS
        }
    }

    /// Records a demanded key into the path's keylog and, on the first resolve
    /// of a build (or the first after a wipe), starts the read-ahead wavefront:
    /// the previous build's keys are replayed through `resolve` in parallel so
    /// the serial demand path behind it finds local hits instead of paying one
    /// WAN round trip per key.
    fn record_and_arm_readahead(&self, state: &'static PathState, cas_path: &str, key: &[u8]) {
        {
            let mut keylog = state.keylog.lock().unwrap();
            let (order, seen) = &mut *keylog;
            if order.len() < MAX_KEYLOG_KEYS && seen.insert(key.to_vec()) {
                order.push(key.to_vec());
                state
                    .keylog_dirty
                    .store(true, std::sync::atomic::Ordering::Relaxed);
            }
        }
        if state
            .readahead_armed
            .swap(true, std::sync::atomic::Ordering::SeqCst)
        {
            return;
        }
        let Some(keys) = self.load_keylog(cas_path) else { return };
        crate::log_line(&format!(
            "readahead: enqueuing {} keys for {}",
            keys.len(),
            cas_path
        ));
        for key in keys {
            let mut item = Vec::with_capacity(2 + cas_path.len() + key.len());
            item.extend_from_slice(&(cas_path.len() as u16).to_be_bytes());
            item.extend_from_slice(cas_path.as_bytes());
            item.extend_from_slice(&key);
            self.readahead.enqueue(item);
        }
    }

    fn readahead_item(&self, item: &[u8]) {
        // Damp on repeated transport errors: an unreachable remote must not
        // turn the wavefront into a retry storm.
        if self.readahead_errors.load(Ordering::Relaxed) > MAX_READAHEAD_ERRORS {
            return;
        }
        let Some((cas_path, key)) = take_u16_field(item) else { return };
        let cas_path = String::from_utf8_lossy(cas_path).into_owned();
        let Some(instance) = self.path_instance.lock().unwrap().get(&cas_path).cloned() else {
            return;
        };
        let remote = self.remote_for(&instance);
        let Ok(state) = self.path_state(&cas_path) else { return };
        let snapshot = self.snapshot_ready(&instance);
        match self.resolve(&remote, state, key, false, snapshot.as_deref()) {
            Ok(_) => {
                let done = self.readahead_done.fetch_add(1, Ordering::Relaxed) + 1;
                if done % 1000 == 0 {
                    crate::log_line(&format!("readahead: {done} keys done"));
                }
            }
            Err(_reason) => {
                self.readahead_errors.fetch_add(1, Ordering::Relaxed);
            }
        }
    }

    fn keylog_path(&self, cas_path: &str) -> Option<PathBuf> {
        use sha2::{Digest, Sha256};
        let dir = self.keylog_dir.as_ref()?;
        let mut hex = String::with_capacity(32);
        for byte in &Sha256::digest(cas_path.as_bytes())[..16] {
            hex.push_str(&format!("{byte:02x}"));
        }
        Some(dir.join(format!("{hex}.keys")))
    }

    fn load_keylog(&self, cas_path: &str) -> Option<Vec<Vec<u8>>> {
        let body = std::fs::read_to_string(self.keylog_path(cas_path)?).ok()?;
        let keys: Vec<Vec<u8>> = body.lines().filter_map(unhex_line).collect();
        (!keys.is_empty()).then_some(keys)
    }

    /// Persists dirty keylogs. Called from the maintenance loop, so a build's
    /// keys survive the proxy for the next build (and the next proxy).
    pub fn flush_keylogs(&self) {
        let paths: Vec<(String, &'static PathState)> = self
            .paths
            .lock()
            .unwrap()
            .iter()
            .map(|(cas_path, state)| (cas_path.clone(), *state))
            .collect();
        for (cas_path, state) in paths {
            if !state
                .keylog_dirty
                .swap(false, std::sync::atomic::Ordering::Relaxed)
            {
                continue;
            }
            let Some(path) = self.keylog_path(&cas_path) else { continue };
            if let Some(parent) = path.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            let keylog = state.keylog.lock().unwrap();
            let mut body = String::with_capacity(keylog.0.len() * 65);
            for key in keylog.0.iter() {
                for byte in key {
                    body.push_str(&format!("{byte:02x}"));
                }
                body.push('\n');
            }
            drop(keylog);
            let _ = std::fs::write(path, body);
        }
    }

    /// PUBLISH notify: queue the record for the publisher pool. Items encode
    /// instance + cas_path + record path.
    fn enqueue_publish(&self, cas_path: &str, instance: &str, record_path: &str) {
        let mut item = Vec::with_capacity(4 + instance.len() + cas_path.len() + record_path.len());
        item.extend_from_slice(&(instance.len() as u16).to_be_bytes());
        item.extend_from_slice(instance.as_bytes());
        item.extend_from_slice(&(cas_path.len() as u16).to_be_bytes());
        item.extend_from_slice(cas_path.as_bytes());
        item.extend_from_slice(record_path.as_bytes());
        self.publisher.enqueue(item);
    }

    fn publish_item(&self, item: &[u8]) {
        let Some((instance, rest)) = take_u16_field(item) else { return };
        let Some((cas_path, record_path)) = take_u16_field(rest) else { return };
        let instance = String::from_utf8_lossy(instance).into_owned();
        let cas_path = String::from_utf8_lossy(cas_path).into_owned();
        let record_path = String::from_utf8_lossy(record_path).into_owned();
        let remote = self.remote_for(&instance);
        let Ok(state) = self.path_state(&cas_path) else { return };
        state
            .last_used
            .store(self.epoch.elapsed().as_millis() as u64, Ordering::Relaxed);
        let Ok(bytes) = std::fs::read(&record_path) else { return };
        let Some(record) =
            PublishRecord::decode_body(&bytes, Some(std::path::PathBuf::from(&record_path)))
        else {
            let _ = std::fs::remove_file(&record_path);
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
                let _ = std::fs::remove_file(&record_path);
                return;
            }
        }
        match self.publish(&remote, state, &record) {
            Ok(()) => {
                let _ = std::fs::remove_file(&record_path);
                state.stats_published.fetch_add(1, Ordering::Relaxed);
                state
                    .resolved
                    .lock()
                    .unwrap()
                    .insert(record.key.clone(), Resolution::Hit(record.value_digest.clone()));
            }
            Err(reason) => {
                crate::log_line(&format!("proxy publish failed ({reason}); record kept"));
            }
        }
    }

    fn publish(
        &self,
        remote: &Remote,
        state: &'static PathState,
        record: &PublishRecord,
    ) -> Result<(), String> {
        let op_start = Instant::now();
        if let Ok(Some(manifest)) = remote.get_action(&record.key) {
            if manifest.first().map(|entry| entry.llcas_digest.as_slice())
                == Some(record.value_digest.as_slice())
            {
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
                entries.push(ManifestEntry { llcas_digest: digest, blob: blob_digest, contents: None });
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
            entries.push(ManifestEntry { llcas_digest: digest, blob: blob_digest, contents: None });
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
                    .and_then(|frame| reapi::decode_frame(&frame).map(|node| (frame.len(), node.data)))
                    .unwrap_or((bytes.len(), Vec::new()));
                upload_meta.push((entry.llcas_digest.clone(), size as i64, entry.blob.size_bytes, data));
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
        let result = remote.update_action(&record.key, &entries);
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

    /// Sweeps orphaned publication records for every known CAS path whose
    /// instance the proxy knows (an unprimed path has nothing to publish to).
    pub fn sweep(&self) {
        let paths: Vec<String> = self.paths.lock().unwrap().keys().cloned().collect();
        for cas_path in paths {
            let Some(instance) = self.path_instance.lock().unwrap().get(&cas_path).cloned() else {
                continue;
            };
            let spool = std::path::Path::new(&cas_path).join("tuist-spool");
            let Ok(entries) = std::fs::read_dir(&spool) else { continue };
            for entry in entries.flatten() {
                if let Some(name) = entry.file_name().to_str() {
                    // Claims are ours alone now; reclaim anything.
                    let base = name.split_once(".claim-").map(|(b, _)| b.to_string());
                    let path = match base {
                        Some(base) => {
                            let claimed = spool.join(format!("{base}.claim-{}", std::process::id()));
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
            let outcome = match remote.get_snapshot() {
                Ok(Some(bytes)) => match Snapshot::decode(&bytes) {
                    Some(snapshot) => {
                        crate::log_line(&format!(
                            "snapshot: {} keys / {} nodes ({} bytes) for {instance}",
                            snapshot.keys.len(),
                            snapshot.nodes.len(),
                            bytes.len(),
                        ));
                        SnapshotState::Ready(Arc::new(snapshot))
                    }
                    None => {
                        crate::log_line(&format!(
                            "snapshot: undecodable payload for {instance}; staying on the per-key path"
                        ));
                        SnapshotState::Absent
                    }
                },
                Ok(None) => SnapshotState::Absent,
                Err(message) => {
                    crate::log_line(&format!("snapshot fetch failed for {instance}: {message}"));
                    SnapshotState::Absent
                }
            };
            proxy.snapshots.lock().unwrap().insert(instance, outcome);
        });
    }

    fn snapshot_ready(&self, instance: &str) -> Option<Arc<Snapshot>> {
        match self.snapshots.lock().unwrap().get(instance) {
            Some(SnapshotState::Ready(snapshot)) => Some(snapshot.clone()),
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
            return write_response(&mut stream, STATUS_ERROR, b"proxy protocol version mismatch");
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
                let outcome = self
                    .path_state(&request.cas_path)
                    .and_then(|state| {
                        self.record_and_arm_readahead(state, &request.cas_path, &request.payload);
                        self.resolve(&remote, state, &request.payload, true, snapshot.as_deref())
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
                if let Some(instance) = self.resolve_instance(&request.cas_path, &request.instance) {
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
                // Only for a path we already track: a proxy that restarted
                // mid-build has no pending fetches, so there is nothing to
                // produce (and no reason to open a CAS handle).
                let state = self.paths.lock().unwrap().get(&request.cas_path).copied();
                let outcome = match state {
                    Some(state) => self.fetch_object(
                        state,
                        &request.cas_path,
                        &request.instance,
                        &request.payload,
                    ),
                    None => Ok(false),
                };
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

unsafe fn open_cas(up: &'static Upstream, path: &str) -> Result<llcas_cas_t, String> {
    let options = (up.llcas_cas_options_create)();
    let c_path =
        std::ffi::CString::new(path).map_err(|_| "bad cas path".to_string())?;
    (up.llcas_cas_options_set_client_version)(options, 0, 1);
    (up.llcas_cas_options_set_ondisk_path)(options, c_path.as_ptr());
    let mut error: *mut std::ffi::c_char = std::ptr::null_mut();
    let cas = (up.llcas_cas_create)(options, &mut error);
    (up.llcas_cas_options_dispose)(options);
    if cas.is_null() {
        let message = if error.is_null() {
            "cas_create failed".to_string()
        } else {
            let text = std::ffi::CStr::from_ptr(error).to_string_lossy().into_owned();
            (up.llcas_string_dispose)(error);
            text
        };
        return Err(message);
    }
    Ok(cas)
}

unsafe fn store_node(state: &PathState, node: &reapi::Node) -> Result<(), String> {
    let mut ref_ids = Vec::with_capacity(node.refs.len());
    for reference in &node.refs {
        let digest = llcas_digest_t { data: reference.as_ptr(), size: reference.len() };
        let mut id = llcas_objectid_t { opaque: 0 };
        let mut error: *mut std::ffi::c_char = std::ptr::null_mut();
        if (state.up.llcas_cas_get_objectid)(state.cas, digest, &mut id, &mut error) {
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
        state.cas,
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
    let digest_t = llcas_digest_t { data: digest.as_ptr(), size: digest.len() };
    let mut id = llcas_objectid_t { opaque: 0 };
    let mut id_error: *mut std::ffi::c_char = std::ptr::null_mut();
    if (state.up.llcas_cas_get_objectid)(state.cas, digest_t, &mut id, &mut id_error) {
        if !id_error.is_null() {
            (state.up.llcas_string_dispose)(id_error);
        }
        return Err("objectid".into());
    }
    let mut loaded = llcas_loaded_object_t { opaque: 0 };
    let mut load_error: *mut std::ffi::c_char = std::ptr::null_mut();
    let result = (state.up.llcas_cas_load_object)(state.cas, id, &mut loaded, &mut load_error);
    if !load_error.is_null() {
        (state.up.llcas_string_dispose)(load_error);
    }
    if result != LLCAS_LOOKUP_RESULT_SUCCESS {
        return Err("local load".into());
    }
    let data = (state.up.llcas_loaded_object_get_data)(state.cas, loaded);
    let node_data = std::slice::from_raw_parts(data.data as *const u8, data.size);
    let refs = (state.up.llcas_loaded_object_get_refs)(state.cas, loaded);
    let count = (state.up.llcas_object_refs_get_count)(state.cas, refs);
    let mut ref_digests = Vec::with_capacity(count);
    for index in 0..count {
        let child = (state.up.llcas_object_refs_get_id)(state.cas, refs, index);
        let digest = (state.up.llcas_objectid_get_digest)(state.cas, child);
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
    fn snapshot_decodes_the_server_wire_format() {
        // Hand-encode kura's format: two nodes, one key referencing both
        // (root first).
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"TSNP");
        bytes.push(1);
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
        let manifest = snapshot.manifest(&[5u8; 32]).expect("key present");
        assert_eq!(manifest.len(), 2);
        // Root = the key's first node (index 1 = the [0xCC] node).
        assert_eq!(manifest[0].llcas_digest, vec![0xCC]);
        assert_eq!(manifest[0].blob.size_bytes, 20);
        assert_eq!(manifest[1].llcas_digest, vec![0xAA, 0xBB]);
        assert!(manifest.iter().all(|entry| entry.contents.is_none()));
        assert!(snapshot.manifest(&[6u8; 32]).is_none());

        // Structural violations refuse to decode rather than misparse.
        assert!(Snapshot::decode(&bytes[..bytes.len() - 1]).is_none());
        let mut bad_index = bytes.clone();
        let at = bad_index.len() - 4;
        bad_index[at..].copy_from_slice(&9u32.to_le_bytes());
        assert!(Snapshot::decode(&bad_index).is_none());
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
        assert!(!should_reclaim(IDLE_RECLAIM - Duration::from_secs(1), false));
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
        assert!(!generation_changed(None, Some(g1)), "first observation is not a change");
        assert!(!generation_changed(Some(g1), None), "a gone dir is left to reclaim_idle");
    }

    // A resolve's writes commit only if the generation it observed still holds;
    // a wipe/prune that advanced the counter mid-resolve drops them.
    #[test]
    fn writes_commit_only_on_the_observed_generation() {
        assert!(committable(7, 7));
        assert!(!committable(7, 8), "an advanced generation must drop stale writes");
    }

    // Keylog lines round-trip: lowercase hex parses back to the raw key; blank
    // and malformed lines are dropped rather than corrupting the wavefront.
    #[test]
    fn keylog_lines_round_trip_and_reject_garbage() {
        assert_eq!(unhex_line("00ff10"), Some(vec![0x00, 0xff, 0x10]));
        assert_eq!(unhex_line("  00ff10\n"), Some(vec![0x00, 0xff, 0x10]));
        assert_eq!(unhex_line(""), None);
        assert_eq!(unhex_line("abc"), None, "odd length is malformed");
        assert_eq!(unhex_line("zz"), None, "non-hex is malformed");
    }

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
        assert_ne!(before, after, "a recreated CAS directory must read as a new generation");
    }
}
