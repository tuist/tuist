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
    read_request, write_response, Request, OP_BACKED, OP_DRAIN, OP_FETCH_OBJECT, OP_INVALIDATE,
    OP_PUBLISH,
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
/// How often the proxy re-asks where the account's cache is.
///
/// Well inside the drain a region gets when an account's cache is placed
/// elsewhere, so a move is picked up while the old region is still serving and
/// nothing has to fail first. This process is a per-machine daemon and can
/// outlive several such moves.
pub const ENDPOINT_REFRESH_INTERVAL: Duration = Duration::from_secs(600);

const MAX_RESOLVED: usize = 1_000_000;
const MAX_KNOWN_LOCAL_PER_SHARD: usize = 250_000;
const MAX_PUBLISH_CACHE: usize = 500_000;
// Retained fetch instructions are ~100B each, so the cap is a ~100MB memory
// backstop a real workload never reaches (the CLI fixture peaks at ~37k). A
// cleared map self-heals per object through the snapshot fallback in
// `fetch_object`.
const MAX_PENDING_OBJECTS: usize = 1_000_000;
/// One entry per value graph the remote could not fully produce. A healthy
/// remote makes none; a badly degraded one makes at most one per resolved key,
/// so this is sized to hold a whole warm build's worth and still be a cap.
const MAX_WITHHELD_ROOTS: usize = 100_000;
/// How deep a withheld root's repair may chase other withheld roots before it
/// gives up and withholds. Value graphs are shallow, and a chain this long means
/// something pathological rather than a graph, so the cap is a stack backstop
/// rather than a tuning knob.
const MAX_REPAIR_DEPTH: usize = 64;

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
// How stale a snapshot may be and still answer a resolve from its own copy of
// the keyspace, measured from the last FULL fetch and never the last delta:
// deltas only ADD, so only the full fetch re-applies the server's eviction
// gate, and a view kept current by deltas alone goes on advertising keys the
// remote has already dropped.
//
// It matters here and not on the per-key path because the per-key path is
// gated at the server on every call — kura refuses to serve an ActionResult
// whose blobs are gone. The snapshot bypasses that: it is a bulk dump, gated
// once when the index was built. So the client's copy is the ONLY thing
// standing between an evicted entry and a compiler that will fail the build on
// it, and how recently it was gated is the whole of its authority.
//
// Twice the full cadence, so healthy operation never trips it — a scheduled
// refresh lands well inside — and what it catches is a refresh loop that
// stopped. That is reachable rather than theoretical: refreshes are held off on
// a loaded machine and while a build is active, and CI runners are both.
const SNAPSHOT_SERVE_MAX_AGE: Duration = Duration::from_secs(2 * 30 * 60);
// How stale a snapshot may be and still answer a BACKED check. Measured from
// the last FULL fetch, never the last delta: deltas only ADD, so only the full
// fetch re-applies the server's eviction gate, and a view refreshed by deltas
// alone keeps advertising keys the remote has already dropped.
//
// Twice the full cadence, so healthy operation never trips it — a scheduled
// refresh lands well inside this — and what it does catch is a refresh loop
// that stopped running. That is reachable: refreshes are held off on a loaded
// machine and while a build is active, and CI runners are both. A snapshot
// left un-gated for hours is exactly the one whose `yes` should not be taken
// on trust.
const SNAPSHOT_BACKING_MAX_AGE: Duration = Duration::from_secs(2 * 30 * 60);
// How long the per-key leg of a BACKED check may wait on the remote: one
// attempt, no retry. The check runs on the build engine's serial task-setup
// thread and its whole value is a few microseconds per hit, so a slow backend
// gets to say so and the check reads as `Unknown` (serve the hit) instead of
// every warm local hit on the machine queueing behind it. Under the client's
// `BACKED_READ_TIMEOUT` on purpose: in the slow case it is the proxy that gives
// up, with an error the client reads as `Unknown`, and not the client walking
// away from a handler still working on its behalf.
const BACKED_REMOTE_DEADLINE: Duration = Duration::from_millis(1500);
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

/// The plugin's write-ahead publication spool for a CAS path. One place, so the
/// sweep, the drain accounting and the plugin agree on the name.
fn spool_dir(cas_path: &str) -> std::path::PathBuf {
    std::path::Path::new(cas_path).join("tuist-spool")
}

/// How many publication records are still spooled under `cas_path`: what this
/// machine recorded and has NOT got onto the remote. A record is deleted only
/// once its publication succeeded (or the policy dropped it), so zero here is
/// the proof a drain waits for.
///
/// Counts exactly what `sweep_path` would try to publish — sidecars are not
/// records, a claimed record still is — so the two cannot disagree about what
/// is owed.
fn spool_records(cas_path: &str) -> usize {
    let Ok(entries) = std::fs::read_dir(spool_dir(cas_path)) else {
        return 0;
    };
    entries
        .flatten()
        .filter(|entry| {
            entry
                .file_name()
                .to_str()
                .is_some_and(|name| !name.ends_with(TAGS_SUFFIX))
        })
        .count()
}

/// How long a drain waits when its caller names no budget of its own.
const DRAIN_TIMEOUT_DEFAULT: Duration = Duration::from_secs(120);
/// Ceiling on a caller-named budget. A drain parks a proxy thread and the
/// request comes from outside this process, so the number is not the caller's
/// to make unbounded.
const DRAIN_TIMEOUT_MAX: Duration = Duration::from_secs(600);
/// Pause between drain attempts. A publication that failed keeps its record and
/// the periodic sweeper is 10s away, which is most of a caller's budget.
const DRAIN_RETRY_BACKOFF: Duration = Duration::from_secs(2);

/// The caller's wait budget, as `u32` big-endian milliseconds. Absent or zero
/// reads as the default, anything above the ceiling is clamped.
fn drain_timeout(payload: &[u8]) -> Duration {
    let Ok(bytes) = <[u8; 4]>::try_from(payload) else {
        return DRAIN_TIMEOUT_DEFAULT;
    };
    match u32::from_be_bytes(bytes) {
        0 => DRAIN_TIMEOUT_DEFAULT,
        millis => Duration::from_millis(u64::from(millis)).min(DRAIN_TIMEOUT_MAX),
    }
}

/// Deletes a spool record and the tags written beside it. A leaked sidecar
/// would be read back by whatever record later reuses that name.
fn remove_record(record_path: &str) {
    let _ = std::fs::remove_file(record_path);
    let _ = std::fs::remove_file(tags_path(record_path));
}

/// Whether a re-put can be dropped without a `publish` round trip. True only
/// when its value matches one we already resolved AND it is not a trunk publish:
/// a trunk publish is the reclaim path and must reach `publish` even on a value
/// match, because the entry it matches may still carry a feature-branch tag that
/// only republishing under the trunk tag can claim into the trunk view. A trunk
/// publish is one that names a branch equal to the trunk it targets.
fn is_redundant_reput(branch: Option<&str>, trunk: Option<&str>, value_matches: bool) -> bool {
    let reclaims_into_trunk = branch.is_some() && branch == trunk;
    value_matches && !reclaims_into_trunk
}

/// How much of a trunk snapshot to pull before a build asks for it. The two
/// layers cost different orders of magnitude and are worth disabling
/// separately, so one setting names all three states rather than leaving the
/// middle one to be spelled with a node budget.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PrefetchMode {
    /// Nothing proactive: no snapshot, no warm. Every resolve is a per-key
    /// round trip and every object arrives on demand.
    Off,
    /// The snapshot only: one round trip for the trunk's keys, no bytes pulled
    /// ahead of the build that needs them. What CI wants: keys are orders of
    /// magnitude lighter than bytes, and a machine whose proxy and build start
    /// together has no window to warm in, so the byte layer would race the build
    /// it is meant to help.
    Keys,
    /// The snapshot and its whole byte closure, materialized ahead of the build.
    ///
    /// The default, because it is affordable and it pays: the trunk scoping
    /// bounds the warm to the project's closure instead of a whole shared
    /// namespace, it runs off any build's critical path, it is idempotent
    /// (objects already on disk are skipped, so steady state only fetches the
    /// delta a new snapshot introduced), and Xcode's size-LRU bounds the store
    /// it lands in. Measured on a mastodon-sized project: ~12s of off-path
    /// fetching turns a from-scratch trunk build from ~57s into ~33s at 50ms
    /// RTT, cutting demand stalls ~14x.
    Full,
}

/// Pure so the policy is testable without writing to the process environment.
/// An unrecognized value reads as `Full`, matching how the other flags treat
/// anything that is not an explicit opt-out: a typo must not silently turn
/// caching down.
fn prefetch_mode_from(value: Option<&str>) -> PrefetchMode {
    match value.map(str::trim).map(str::to_ascii_lowercase).as_deref() {
        Some("0" | "off" | "false" | "no" | "none") => PrefetchMode::Off,
        Some("keys") => PrefetchMode::Keys,
        _ => PrefetchMode::Full,
    }
}

fn prefetch_mode() -> PrefetchMode {
    prefetch_mode_from(std::env::var("TUIST_CAS_PREFETCH").ok().as_deref())
}
// View refresh: per-key hits taken while a snapshot was Ready get their
// manifests re-published in the background (see Proxy.view_refresh). The
// per-tick batch keeps a full cold build's backlog (~10k keys) draining in
// well under an hour without contending with the build's own traffic; the
// queue cap bounds memory if the server never accepts them.
const VIEW_REFRESH_PER_TICK: usize = 100;
/// How many refreshes a proxy remembers having done, to suppress duplicates.
/// Deliberately its own bound: the queue's cap protects memory against a server
/// that never accepts, while this one is a history whose entries are never
/// retired, so reusing that number turned "the queue is full" into "this machine
/// is finished refreshing". Full means forget, never refuse.
const VIEW_REFRESH_HISTORY_MAX: usize = 200_000;
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
/// Which of `owed` needs its bytes batch-read: not already on disk, and named by
/// an instruction that carries a blob digest rather than inlined bytes.
///
/// Everything it declines is declined for a reason the caller must not undo. A
/// node already on disk needs nothing. A node whose instruction is inlined has
/// its bytes already. A node with no instruction here is either a nested
/// withheld root or a snapshot-only node, and both belong to the per-child path,
/// which can recurse and can wait on a snapshot; this one may do neither.
///
/// Pure, so the selection can be tested without a store or a remote.
fn owed_needing_fetch(
    owed: &[Vec<u8>],
    present: impl Fn(&[u8]) -> bool,
    instruction: impl Fn(&[u8]) -> Option<(reapi::Digest, bool)>,
) -> Vec<(Vec<u8>, reapi::Digest)> {
    let mut wanted = Vec::new();
    for child in owed {
        if present(child) {
            continue;
        }
        // An inlined instruction names a blob too, so the flag is what decides,
        // never the presence of a digest.
        if let Some((blob, inlined)) = instruction(child) {
            if !inlined {
                wanted.push((child.clone(), blob));
            }
        }
    }
    wanted
}

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
    // Value-graph roots `materialize_manifest` refused to store because a node
    // in their closure did not land, mapped to the digests that were missing.
    //
    // Withholding the root stops the MATERIALIZER publishing a root over a hole,
    // but `fetch_object` is a second door into the same store: the compiler was
    // already handed the value id, its demand load asks for the root, and the
    // withheld instruction still carries the bytes, so the root goes in
    // standalone and the hole is now permanent (the next build's root probe
    // passes and the association is recorded, and nothing can retract it). This
    // map is what lets that door recognise a root it must not put back on its
    // own.
    //
    // Recorded WITHOUT the `committable` gate the known-local marks take. The
    // record only ever withholds, never permits, so a stale one costs a repair
    // attempt and never a wrong answer.
    //
    // It is never dropped on its own. `invalidate` retains it beside
    // `pending_objects`, and `enforce_withheld_bound` drops each root's
    // instruction with its record: a withhold forgotten while the instruction
    // that produces the root survives is not a smaller version of this bug, it
    // IS this bug.
    withheld_roots: Mutex<HashMap<Vec<u8>, Vec<Vec<u8>>>>,
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
    // Value graphs whose root was withheld because a node in their closure could
    // not be stored. Each one is a key that resolves again next build instead of
    // being served over a hole. Persistently non-zero means the remote is handing
    // out entries whose blobs it cannot produce.
    pub stats_incomplete_closures: AtomicU64,
    // Demand loads of a withheld root that this proxy declined to answer because
    // the closure was still incomplete. Each one is a build that fails on the
    // ROOT instead of silently storing it and failing on an interior node
    // forever after. Its companion is `stats_withheld_roots_repaired`: the same
    // situation where the missing nodes did land on the retry, which is a build
    // that would have failed and now does not.
    pub stats_withheld_roots_refused: AtomicU64,
    pub stats_withheld_roots_repaired: AtomicU64,
    // The BACKED check's own accounting, apart from the resolve counters because
    // it is not a resolve: it fetches nothing and its answer is never
    // self-checking. `per_key` is the number to watch — it is the round trip on
    // the serial task-setup path, paid while the snapshot is still fetching or
    // too old to trust, and a warm cache volume on CI is exactly where many hits
    // land in that window.
    pub stats_backing_checks: AtomicU64,
    pub stats_backing_snapshot: AtomicU64,
    pub stats_backing_per_key: AtomicU64,
    pub stats_backing_unbacked: AtomicU64,
    pub stats_published: AtomicU64,
    pub ms_action: AtomicU64,
    pub ms_filter: AtomicU64,
    pub ms_fetch: AtomicU64,
    pub ms_decode: AtomicU64,
    pub ms_store: AtomicU64,
    // The local half of a publication's cost, separated from the four RPCs it
    // shares `write_duration` with. That one number covering both is why the
    // 40x write regression of 2026-09-02 survived three incompatible
    // explanations for a day: nothing said whether the time was network or
    // disk. It was network, and this is what says so next time.
    //
    // Every llcas read a publication makes, from both of the places it makes
    // them (see `encode_node_blob_accounted`), and nothing else: not the memo
    // lookups or the graph bookkeeping around them, which are not what a slow
    // store makes slow.
    //
    // Microseconds, not the milliseconds the counters above use: a read against
    // a store that has not rotated is tens of nanoseconds, and a millisecond
    // counter reports a whole build of them as zero.
    pub us_publish_local: AtomicU64,
    // The reads those microseconds are spread over. The per-read cost is what
    // the store's generation chain changes, so the total is only readable
    // against the count.
    pub stats_publish_nodes_loaded: AtomicU64,
    // Publications skipped because the remote was inside its shed window. The
    // companion to `us_publish_local`: between them, a `write_duration` that
    // moved says which half moved, and a `write_duration` that did not move
    // says whether that is health or silence.
    pub stats_publish_shed: AtomicU64,
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

/// Where a BACKED check may take its answer from, decided from one read of the
/// instance's snapshot state. `Snapshot` is a copy gated within
/// `SNAPSHOT_BACKING_MAX_AGE`, so it may answer a key it holds and the remote
/// answers the rest; `PerKey` is the remote alone, for the transient window
/// while a snapshot is still fetching and for a snapshot too old to trust;
/// `Decline` is the durably snapshotless state, where a round trip per served
/// hit would cost more than the check is worth.
enum BackingSource {
    Snapshot(Arc<Snapshot>),
    PerKey,
    Decline,
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
        //
        // `withheld_roots` is KEPT for exactly the same reason, and the symmetry
        // is the whole point: it must be at least as durable as the instruction
        // that makes the hazard possible. Clearing it here while retaining the
        // root's instruction is precisely the state this guard exists to
        // prevent, since the next demand load would find something that produces
        // the root and nothing saying it must not. Its digests are content
        // addresses like the instructions', and its claim is about what the
        // REMOTE could not produce, not about any incarnation of the local
        // store, so a wipe does not make it stale. A record whose nodes are in
        // fact present costs one repair pass that short-circuits on
        // `load_present` and then drops itself.
    }

    /// Bounds `withheld_roots`, dropping each root's fetch INSTRUCTION with it.
    ///
    /// A withhold may never be forgotten on its own. Forgetting one while the
    /// root's instruction survives is the pre-fix bug rather than a smaller
    /// version of it: the next demand load finds something that produces the
    /// root and nothing saying it must not. Dropping both leaves a demand load
    /// with nothing to produce it from, which is the conservative answer and the
    /// one the caller can recover from with a resolve.
    ///
    /// Split out from `enforce_cache_bounds` so the pairing is testable without
    /// a registered path or a maintenance tick.
    fn enforce_withheld_bound(&self, cap: usize) {
        // ONE critical section on `withheld_roots`, held across the instruction
        // removal. Snapshotting the keys, releasing the lock to clean
        // `pending_objects`, then re-locking to clear left a window in which a
        // withhold recorded by a materializer worker was dropped by the clear
        // (it was not in the snapshot, so its instruction was never removed),
        // which is precisely the "record forgotten while the instruction
        // survives" state this function exists to avoid. The regime that fills
        // this map is the same regime the materializer pool writes to it hardest,
        // so the trigger and the window coincide rather than being independent.
        //
        // `take` rather than `clear` for the same reason: the map must never be
        // observable half-emptied, and an insert that arrives mid-operation
        // blocks and then lands in the fresh map with its instruction intact.
        //
        // Lock order is `withheld_roots` then `pending_objects`, and nothing
        // takes them the other way round: the recording site in
        // `materialize_manifest` holds only `withheld_roots`, and `prefetch_owed`
        // and the instruction sites hold only `pending_objects`. Keep it that way.
        let mut withheld = self.withheld_roots.lock().unwrap();
        if withheld.len() <= cap {
            return;
        }
        let dropped = std::mem::take(&mut *withheld);
        let mut pending = self.pending_objects.lock().unwrap();
        for root in dropped.keys() {
            pending.remove(root);
        }
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
/// working copy, which is what makes a moved, renamed, or duplicated one unable
/// to mis-attribute a build.
#[derive(serde::Deserialize)]
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
    #[serde(default, rename = "branch")]
    ci_branch: Option<String>,
    /// The project's default branch, as the server knows it. Which branch is
    /// trunk is a property of the project, not of how this machine happened to
    /// clone it (a fork, a mirror, or a clone whose remote head was never set all
    /// get it wrong locally). `None` when setup could not reach the server, which
    /// means no scoping: what a client too old to ask for it already gets.
    #[serde(default)]
    trunk: Option<String>,
    /// The project's `xcodeCache.upload`.
    ///
    /// The plugin checks this too, from a compiler option, but that option only
    /// reaches Swift: swift-build's `CASOptions` carries a plugin PATH and no
    /// plugin options, so the CAS it creates for its Clang caching has no idea
    /// what the project asked for and defaults to uploading. The proxy is the
    /// only place that sees both lanes, so it is where the policy is enforced.
    ///
    /// Absent is permissive: nothing recorded is nothing to withhold.
    #[serde(default = "uploads_by_default")]
    upload: bool,
}

fn uploads_by_default() -> bool {
    true
}

pub struct Proxy {
    // Replaceable: the endpoint an account is served from moves when its cache
    // is placed in another region, and this process outlives the value it was
    // launched with. See `refresh_endpoint`.
    grpc_url: RwLock<String>,
    // Epoch-ms of the last endpoint resolution, so the sweep can carry the
    // interval without a timer of its own. 0 means never resolved.
    endpoint_resolved_at_ms: AtomicU64,
    // Bumped on every adoption. Only ever compared for equality.
    endpoint_generation: AtomicU64,
    tokens: Arc<TokenProvider>,
    upstream_plugin: String,
    // Monotonic base for per-path last-used timestamps (see PathState.last_used).
    epoch: Instant,
    // One REAPI client per account/project instance, created on first use.
    // All share the machine's endpoint + token; only the instance the request
    // is scoped to differs. This is what lets one proxy serve every project.
    // Each client is stamped with the endpoint generation it was built
    // against, because a client outlives the address it dialled. Publication
    // and adoption cannot be ordered against each other -- two first-sight
    // requests race, and the slower one can publish a client built from the
    // old address after the faster one has already adopted and cleared -- so
    // the stamp is what makes that harmless: a client from a previous
    // generation is never handed out, whenever it arrived.
    remotes: Mutex<HashMap<String, (u64, Arc<Remote>)>>,
    // cas_path -> instance, primed by builds that declare their instance and
    // persisted so an Xcode ⌘B build (which declares none) still routes after
    // a proxy restart. See proxy_proto for why the fallback exists.
    path_instance: Mutex<HashMap<String, String>>,
    registry_path: Option<PathBuf>,
    // instance -> what `tuist setup cache` recorded for it: the project's trunk,
    // the CI job's branch, and the upload policy. Not the checkout: nothing about
    // a publish is read from a working copy, which is what stops a moved,
    // renamed or duplicated one mis-attributing a build. Nothing branch-specific
    // enters a build setting either, which could pollute the compile cache key.
    instance_sources: Mutex<HashMap<String, RegisteredSource>>,
    // Instances a build has touched since this proxy started; bounds trunk
    // ingestion to projects actually in use (see `instance_active`).
    active_instances: Mutex<HashSet<String>>,
    // instance -> the last context read from the registry, refreshed on a short
    // TTL so per-publish tagging is a cache hit rather than a file read.
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
    // Instances already reported as serving per key because their snapshot aged
    // out; see `note_stale_snapshot`. One line per instance, not per resolve.
    stale_snapshot_logged: Mutex<HashSet<String>>,

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
            grpc_url: RwLock::new(grpc_url),
            endpoint_resolved_at_ms: AtomicU64::new(0),
            endpoint_generation: AtomicU64::new(0),
            tokens,
            upstream_plugin,
            epoch: Instant::now(),
            remotes: Mutex::new(HashMap::new()),
            path_instance: Mutex::new(path_instance),
            instance_sources: Mutex::new(
                registry_path
                    .as_deref()
                    .and_then(|path| load_sources(&sources_path_for(path)))
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
            stale_snapshot_logged: Mutex::new(HashSet::new()),
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
        if let Some(remote) = self.current_remote(instance) {
            return remote;
        }
        // First sight of this instance. On a proxy whose registry was empty at
        // startup this is the first moment anything is known to serve, so the
        // maintenance sweep has had nothing to resolve for and the endpoint is
        // still the one this process was launched with -- which may be a region
        // the account has since left. Resolved before a client is bound to it,
        // not after the client has started missing. The lock above is released;
        // adopting a moved endpoint takes it.
        self.ensure_endpoint_fresh(instance);

        if let Some(remote) = self.current_remote(instance) {
            return remote;
        }

        // Sampled before the address, never after. An adoption landing between
        // these two reads can then only leave the stamp behind the address,
        // which publishes a client that is ignored and rebuilt; sampling the
        // other way round would stamp the new generation onto a client dialled
        // at the old address, which is the one outcome that must not happen.
        // Neither lock is held across the other: adoption takes the address
        // then the map, so this must never take the map then the address.
        let generation = self.endpoint_generation.load(Ordering::Acquire);
        let grpc_url = self.grpc_url.read().unwrap().clone();

        let remote = Remote::new(
            RemoteConfig {
                grpc_url,
                instance: reapi::reapi_instance(instance).to_string(),
            },
            self.tokens.clone(),
        );

        self.remotes
            .lock()
            .unwrap()
            .insert(instance.to_string(), (generation, remote.clone()));

        remote
    }

    /// The instance's client, if one was built against the endpoint currently
    /// in force. A client from an earlier generation is not one of this
    /// account's clients any more; it is bound to a region it has left.
    fn current_remote(&self, instance: &str) -> Option<Arc<Remote>> {
        let generation = self.endpoint_generation.load(Ordering::Acquire);

        self.remotes
            .lock()
            .unwrap()
            .get(instance)
            .and_then(|(built_at, remote)| (*built_at == generation).then(|| remote.clone()))
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
            if prefetch_mode() != PrefetchMode::Full || proxy.resolve_trunk(&instance).is_none() {
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
            withheld_roots: Mutex::new(HashMap::new()),
            stats_resolves: AtomicU64::new(0),
            stats_remote_hits: AtomicU64::new(0),
            stats_misses: AtomicU64::new(0),
            stats_snapshot_hits: AtomicU64::new(0),
            stats_demand_fetched: AtomicU64::new(0),
            stats_blobs_fetched: AtomicU64::new(0),
            stats_blobs_inlined: AtomicU64::new(0),
            stats_incomplete_closures: AtomicU64::new(0),
            stats_withheld_roots_refused: AtomicU64::new(0),
            stats_withheld_roots_repaired: AtomicU64::new(0),
            stats_backing_checks: AtomicU64::new(0),
            stats_backing_snapshot: AtomicU64::new(0),
            stats_backing_per_key: AtomicU64::new(0),
            stats_backing_unbacked: AtomicU64::new(0),
            stats_published: AtomicU64::new(0),
            ms_action: AtomicU64::new(0),
            ms_filter: AtomicU64::new(0),
            ms_fetch: AtomicU64::new(0),
            ms_decode: AtomicU64::new(0),
            ms_store: AtomicU64::new(0),
            us_publish_local: AtomicU64::new(0),
            stats_publish_nodes_loaded: AtomicU64::new(0),
            stats_publish_shed: AtomicU64::new(0),
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
                    analytics.record_keyvalue(
                        key,
                        "read",
                        crate::analytics::millis(op_start.elapsed()),
                    );
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
            analytics.record_keyvalue(key, "read", crate::analytics::millis(op_start.elapsed()));
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
            let root_digest = manifest.first().map(|entry| entry.llcas_digest.clone());
            let is_root = |entry: &ManifestEntry| Some(&entry.llcas_digest) == root_digest.as_ref();
            // Whether the root is ours to publish at all. A root already present
            // locally is not in `missing`, and its absence from the loop is not a
            // withheld closure.
            let root_pending = missing.iter().any(|entry| is_root(entry));
            // The withhold goes in FIRST, before anything that can fail, and is
            // narrowed or dropped only once the pass has actually decided.
            //
            // Recording it at the end instead left the hazard wide open on every
            // error path: `batch_read_after_action_result` and `store_node` both
            // `?`-return, and `commit_and_materialize` has already registered
            // this root's instruction WITH its inlined bytes. An early return
            // therefore left an instruction that produces the root and no record
            // saying it must not be produced, which is the exact bug this guard
            // exists to close.
            //
            // Owed is every other node this pass is responsible for fetching, so
            // the claim starts as strong as it can be and only weakens on
            // evidence. A pessimistic set costs a repair pass that mostly
            // short-circuits on `load_present`, never correctness.
            if root_pending {
                if let Some(root) = &root_digest {
                    let owed: Vec<Vec<u8>> = missing
                        .iter()
                        .filter(|entry| !is_root(entry))
                        .map(|entry| entry.llcas_digest.clone())
                        .collect();
                    state.withheld_roots.lock().unwrap().insert(root.clone(), owed);
                }
            }
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
                remote.batch_read_after_action_result(&digests)?
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
            // The value ROOT goes in LAST, and only if every other node landed.
            //
            // Skipping a node below is a DESIGNED outcome (an incomplete graph on
            // the server, a writer still uploading), so "root present, child
            // absent" is reachable in normal operation rather than only after a
            // prune. That shape is invisible to a reader: the get path probes the
            // ROOT and nothing deeper, because verifying a closure there means a
            // load per node on the serial task-setup thread. Storing the root
            // first therefore published a graph we already knew was incomplete.
            //
            // Ordering it last stops THIS writer publishing a root over a hole.
            // That is not enough on its own, because `fetch_object` is a second
            // door into the same store: the compiler already holds the value id,
            // its demand load asks for the root, and a withheld root keeps its
            // instruction WITH the inlined bytes, so the load used to put the
            // root back standalone and the hole became permanent. The withheld
            // root is therefore RECORDED below, against the nodes that did not
            // land, and `fetch_object` declines it until they do. Naming those
            // nodes is what keeps the check off the transitive walk the
            // root-only probe exists to avoid: the demand path repairs exactly
            // what this pass was owed, not the graph.
            //
            // Repair is per object and on demand: every skipped node keeps its
            // fetch instructions, and the load that needs one fetches it. The
            // graph is not re-materialized on the next build, because the
            // `resolved` fast path counts a value with registered instructions as
            // present and serves the cached Hit. Latency, not a safety hole.
            let mut ordered: Vec<&ManifestEntry> =
                missing.iter().copied().filter(|entry| !is_root(entry)).collect();
            ordered.extend(missing.iter().copied().filter(|entry| is_root(entry)));
            let mut root_stored = false;
            // The OTHER nodes only. A root that fails on its own is not evidence
            // about its children, and reporting it as one of them would
            // misdescribe which side of the graph the remote could not produce.
            //
            // Kept as digests rather than a count because `fetch_object` needs
            // to know WHICH nodes were missing: a demand load of a withheld root
            // can only be answered once those exact nodes are present, and
            // re-deriving them there would mean the transitive walk the root-only
            // probe exists to avoid.
            let mut skipped_digests: Vec<Vec<u8>> = Vec::new();

            let skip = |digest: &[u8], is_root: bool, skipped: &mut Vec<Vec<u8>>| {
                if !is_root {
                    skipped.push(digest.to_vec());
                }
            };
            for entry in ordered {
                let entry_is_root = is_root(entry);
                if entry_is_root && !skipped_digests.is_empty() {
                    continue;
                }
                let (blob, inlined) = match &entry.contents {
                    Some(bytes) => (bytes, true),
                    None => match contents.get(&entry.blob.hash) {
                        Some(bytes) => (bytes, false),
                        // Incomplete graph on the server (the writer may still
                        // be uploading): skip the node, keeping its fetch
                        // instructions registered so the demand load that
                        // needs it retries — and surfaces the failure —
                        // per object.
                        None => {
                            skip(&entry.llcas_digest, entry_is_root, &mut skipped_digests);
                            continue;
                        }
                    },
                };
                let phase = Instant::now();
                let Some(frame) = reapi::decompress_frame(blob) else {
                    skip(&entry.llcas_digest, entry_is_root, &mut skipped_digests);
                    continue;
                };
                let Some(node) = reapi::decode_frame(&frame) else {
                    skip(&entry.llcas_digest, entry_is_root, &mut skipped_digests);
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
                        crate::analytics::millis(fetch_elapsed)
                            * (compressed as f64 / total_compressed as f64)
                    };
                    let codec = crate::analytics::millis(codec_elapsed);
                    // This node's own transfer. Keyed by the node, not by a hex
                    // of its digest: the checksum the server joins on is the
                    // separate digest this node's PARENT carries next to its
                    // casID, which the root of this graph records below.
                    analytics.record_cas_output(
                        &entry.llcas_digest,
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
                root_stored |= entry_is_root;
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
            // Reported once, AFTER the pass, in three distinct shapes. Deciding
            // it at the root's turn in the loop saw only the first: nothing runs
            // after the root, and a root already on disk never enters the loop at
            // all. The counts are against `missing`, not `manifest`, because that
            // is the set this pass was actually responsible for fetching:
            // measuring against the whole graph reads as `skipped=1 of 40` when
            // only two nodes were in play, which under-reports the failure rate
            // this counter exists to trend.
            let root_already_local = !root_pending;
            let skipped = skipped_digests.len();
            // Now narrow the pessimistic record to what the pass actually
            // found, or drop it. Only reached when nothing above returned early,
            // which is the point: an error path leaves the strong claim standing.
            if let Some(root) = &root_digest {
                let mut withheld = state.withheld_roots.lock().unwrap();
                if root_stored {
                    // This pass published the root over a complete closure, so
                    // there is nothing left to withhold.
                    withheld.remove(root);
                } else if skipped > 0 {
                    withheld.insert(root.clone(), std::mem::take(&mut skipped_digests));
                } else if root_pending {
                    // Children all landed and the root's own blob did not. The
                    // absence of a usable instruction is what refuses it, and an
                    // empty owed set would make the guard wave it through.
                    withheld.remove(root);
                }
            }
            if skipped > 0 || (root_pending && !root_stored) {
                state.stats_incomplete_closures.fetch_add(1, Ordering::Relaxed);
                let root_hex = root_digest
                    .as_deref()
                    .map(crate::analytics::hex_upper)
                    .unwrap_or_default();
                if root_already_local {
                    // The one this crate cannot withhold its way out of: the root
                    // was stored by an earlier pass or a demand load, so it is
                    // present over a closure this pass just failed to complete.
                    // The read guard's probe passes and the association gets
                    // recorded, which is why it is counted rather than treated as
                    // a non-event.
                    crate::log_line(&format!(
                        "incomplete closure, root already local: root={} skipped={} of {}",
                        root_hex,
                        skipped,
                        missing.len()
                    ));
                } else if skipped > 0 {
                    crate::log_line(&format!(
                        "incomplete closure, root withheld: root={} skipped={} of {}",
                        root_hex,
                        skipped,
                        missing.len()
                    ));
                } else {
                    // The remote produced the children but not the root itself,
                    // so the graph is unusable for a different reason than the
                    // withhold: retrying it is pointless until the root's blob is
                    // actually serveable.
                    crate::log_line(&format!(
                        "incomplete closure, root unavailable: root={} of {}",
                        root_hex,
                        missing.len()
                    ));
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

    /// Batch-reads every owed node whose instruction this proxy already holds and
    /// whose bytes it does not, seeding those bytes back into `pending_objects`
    /// so the repair loop stores them without a round trip each.
    ///
    /// Deliberately best-effort and side-effect-only. Nodes already local, nodes
    /// whose instruction is inlined, and nodes only the snapshot can name are all
    /// left for the loop to handle per child; an unroutable instance or a failed
    /// batch simply seeds nothing and the loop behaves as it did before. So this
    /// can make the repair cheaper and can never make it wrong.
    fn prefetch_owed(
        &self,
        state: &'static PathState,
        cas_path: &str,
        declared_instance: &str,
        owed: &[Vec<u8>],
    ) {
        let wanted = {
            let pending = state.pending_objects.lock().unwrap();
            let publish = state.publish_cache.lock().unwrap();
            owed_needing_fetch(
                owed,
                |child| state.load_present(child),
                |child| match pending.get(child) {
                    Some(PendingFetch { blob, contents }) => {
                        Some((blob.clone(), contents.is_some()))
                    }
                    None => publish.get(child).map(|(blob, _refs)| (blob.clone(), false)),
                },
            )
        };
        if wanted.is_empty() {
            return;
        }
        let Some(instance) = self.resolve_instance(cas_path, declared_instance) else {
            return;
        };
        let remote = self.remote_for(&instance);
        let digests: Vec<reapi::Digest> = wanted.iter().map(|(_, blob)| blob.clone()).collect();
        let Ok(contents) = remote.batch_read(&digests) else {
            return;
        };
        let mut pending = state.pending_objects.lock().unwrap();
        for (child, blob) in wanted {
            let Some(bytes) = contents.get(&blob.hash) else {
                continue;
            };
            pending
                .entry(child)
                .and_modify(|instruction| instruction.contents = Some(bytes.clone()))
                .or_insert_with(|| PendingFetch {
                    blob: blob.clone(),
                    contents: Some(bytes.clone()),
                });
        }
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
        let mut repairing = Vec::new();
        self.fetch_object_inner(state, cas_path, declared_instance, digest, &mut repairing)
    }

    /// The body of `fetch_object`. `repairing` is the stack of withheld roots
    /// whose repair is in progress, which both breaks cycles and bounds depth.
    fn fetch_object_inner(
        &self,
        state: &'static PathState,
        cas_path: &str,
        declared_instance: &str,
        digest: &[u8],
        repairing: &mut Vec<Vec<u8>>,
    ) -> Result<bool, String> {
        if state.load_present(digest) {
            return Ok(true);
        }
        // A root the materializer withheld must not be put back on its own.
        //
        // Withholding it there was the whole point: the closure had a hole, and
        // storing the root anyway makes that hole permanent, because the next
        // build's root probe passes, the association is recorded, and the ABI
        // has no way to retract it. Answering this call is the second door into
        // the same store, and before this guard it walked straight through.
        //
        // Try the hole first. The missing nodes kept their fetch instructions,
        // so this is the per-object repair the materializer's comment promises,
        // narrowed to the exact nodes that did not land rather than a transitive
        // walk: if the remote can produce them now (a writer that has since
        // finished uploading, a blob declined under momentary memory pressure)
        // the closure is whole and the root is safe to store. If it still
        // cannot, decline, and the build fails naming the ROOT rather than
        // storing it and failing on an interior node on this and every later
        // build of that key.
        // The guard applies at EVERY level, not just the one the compiler asked
        // for. A digest is an interior node of one value graph and the root of
        // another whenever two actions share an output, so repairing one root
        // can walk into a second root that is itself withheld. Producing that
        // one unguarded would store it over its OWN hole and poison an
        // association this fetch was never about.
        let owed = state.withheld_roots.lock().unwrap().get(digest).cloned();
        if let Some(owed) = owed {
            // Content addressing makes the object graph acyclic, but this stack
            // walks the withheld map, which is ordinary state and carries no such
            // promise. A repeat visit means the closure cannot be proven whole
            // from here, and unproven withholds.
            if repairing.iter().any(|root| root == digest) || repairing.len() >= MAX_REPAIR_DEPTH {
                state
                    .stats_withheld_roots_refused
                    .fetch_add(1, Ordering::Relaxed);
                crate::log_line(&format!(
                    "withheld root not produced, repair chain cycled or ran too deep: root={} depth={}",
                    crate::analytics::hex_upper(digest),
                    repairing.len()
                ));
                return Ok(false);
            }
            repairing.push(digest.to_vec());
            // ONE batch read for everything the repair is about to need.
            //
            // Without this the loop below calls `demand_fetch` per child, and
            // `demand_fetch` only coalesces with requests already in flight from
            // OTHER threads, so a serial loop never coalesces with itself: N
            // children became N `BatchReadBlobs` round trips. `materialize_manifest`
            // makes the argument against exactly that a few hundred lines up,
            // with a measurement behind it (6-way splitting of ~23-blob sets
            // pinned per-resolve latency at per-RPC cost times groups), and the
            // repair has the whole owed list up front, so it has no excuse.
            //
            // Seeding the instructions rather than storing here keeps every other
            // rule in one place: the loop below still handles nested withheld
            // roots, snapshot-sourced instructions and the cycle guard, and it
            // drops each `contents` as soon as the node is stored, so the bytes
            // are held only across this repair.
            self.prefetch_owed(state, cas_path, declared_instance, &owed);
            let mut repaired = true;
            for child in &owed {
                match self.fetch_object_inner(state, cas_path, declared_instance, child, repairing) {
                    Ok(true) => {}
                    // A transport failure is not evidence the closure is
                    // whole, so it withholds like an absence.
                    Ok(false) | Err(_) => {
                        repaired = false;
                        break;
                    }
                }
            }
            repairing.pop();
            if !repaired {
                state
                    .stats_withheld_roots_refused
                    .fetch_add(1, Ordering::Relaxed);
                crate::log_line(&format!(
                    "withheld root not produced, closure still incomplete: root={} owed={}",
                    crate::analytics::hex_upper(digest),
                    owed.len()
                ));
                return Ok(false);
            }
            state.withheld_roots.lock().unwrap().remove(digest);
            state
                .stats_withheld_roots_repaired
                .fetch_add(1, Ordering::Relaxed);
            crate::log_line(&format!(
                "withheld root repaired, closure completed on demand: root={} owed={}",
                crate::analytics::hex_upper(digest),
                owed.len()
            ));
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
            // The record is already durable. The Clang lane wrote it before
            // asking, because its plugin instance never saw the policy, so
            // refusing the request without dropping the record leaves it for
            // every later sweep to find: the spool grows without bound, and the
            // first time the policy reads as enabled (the project turns uploads
            // on, or a registry read fails open) it hands the sweeper a backlog
            // of everything produced while the project was read-only.
            remove_record(record_path);
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
        //
        // But `resolved` remembers the value, not the tag it carries remotely,
        // and a trunk build's re-put is the reclaim path: the entry it matches
        // may still be tagged with a feature branch, and only republishing it
        // under the trunk tag pulls it into the trunk view (`sticky_branch`
        // then lets trunk claim it). So a trunk re-put must reach `publish` even
        // when the value matches; only a feature, local, or untagged re-put,
        // which reclaims nothing into trunk, is free to drop here.
        let value_matches = {
            let resolved = state.resolved.lock().unwrap();
            matches!(resolved.get(&record.key), Some(Resolution::Hit(value)) if value == &record.value_digest)
        };
        if is_redundant_reput(branch.as_deref(), trunk.as_deref(), value_matches) {
            remove_record(&record_path);
            return;
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
                // A shed is already reported once per window by the breaker that
                // armed it, and every publication queued behind it fails for the
                // same reason. Saying so per record buries the line that
                // explains them in thousands of copies of itself.
                if reason != "remote shedding writes" {
                    crate::log_line(&format!("proxy publish failed ({reason}); record kept"));
                }
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
        // Asked before anything else. A node shedding writes will refuse this
        // publication at its last RPC whatever happens in between, so the probe,
        // the closure walk and the missing-blob query would be three round trips
        // and a pile of local reads spent to reach a refusal already known. The
        // record stays on disk and the next sweep retries it, which is the same
        // contract every other publication failure has.
        if remote.shedding_writes() {
            remote.record_shed_write();
            state.stats_publish_shed.fetch_add(1, Ordering::Relaxed);
            return Err("remote shedding writes".into());
        }
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
        let (entries, blobs) = walk_closure(state, &record.value_digest)?;
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
                None => encode_node_blob_accounted(state, &entry.llcas_digest)?.0,
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
                let elapsed = crate::analytics::millis(upload_start.elapsed());
                let total: i64 = upload_meta.iter().map(|(_, _, c, _)| c).sum::<i64>().max(1);
                for (digest, size, compressed, data) in &upload_meta {
                    let transfer = elapsed * (*compressed as f64 / total as f64);
                    analytics.record_cas_output(
                        digest,
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
            analytics.record_keyvalue(
                &record.key,
                "write",
                crate::analytics::millis(op_start.elapsed()),
            );
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
            state.enforce_withheld_bound(MAX_WITHHELD_ROOTS);
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
            self.sweep_path(&cas_path, &instance);
        }
    }

    /// Re-enqueues every publication record still spooled under one CAS path.
    fn sweep_path(&self, cas_path: &str, instance: &str) {
        let spool = spool_dir(cas_path);
        let Ok(entries) = std::fs::read_dir(&spool) else {
            return;
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
                        let claimed = spool.join(format!("{base}.claim-{}", std::process::id()));
                        if std::fs::rename(entry.path(), &claimed).is_err() {
                            continue;
                        }
                        claimed
                    }
                    None => entry.path(),
                };
                self.enqueue_publish(cas_path, instance, &path.to_string_lossy());
            }
        }
    }

    /// Waits for everything this machine recorded under `cas_path` to reach the
    /// remote, and reports how many records are still owed.
    ///
    /// Zero is a promote gate's green light. A runner folds its CAS store into
    /// the cache image it promotes as the account's master, and every host that
    /// later clones that master inherits its `key -> value` associations while
    /// its only repair path for an object the store does not hold is the remote.
    /// So an association whose blobs are still spooled here is one that no host
    /// can ever satisfy — and nothing retracts it (the llcas ABI has no delete,
    /// and re-putting the key with another value is refused), so it fails every
    /// later build of that key until the store generation rolls. An empty spool
    /// is what rules that out: a record is deleted only by a publication that
    /// succeeded.
    ///
    /// It sweeps before waiting because the plugin writes its record BEFORE
    /// notifying the proxy — a frontend that died between the two leaves one
    /// nothing has queued, and waiting on the pool alone would read that spool
    /// as drained. Then it waits on the publisher pool, which is machine-wide:
    /// a drain also waits out other instances' publications. That is deliberate
    /// rather than incidental — per-path accounting would have to track
    /// in-flight items by path, and the caller this exists for (a runner VM's
    /// teardown) has exactly one.
    ///
    /// `instance` is the already-resolved routing target. `None` means the path
    /// is unroutable, so nothing CAN be published and whatever is spooled is
    /// owed — the one case where "nothing queued" must not read as "nothing
    /// owed".
    ///
    /// Best-effort by nature, and no substitute for the read-side guard: a host
    /// that panics, or a job cancelled mid-upload, promotes without ever
    /// reaching this.
    fn drain_publications(
        &self,
        cas_path: &str,
        instance: Option<&str>,
        timeout: Duration,
    ) -> usize {
        let deadline = Instant::now() + timeout;
        // The common case: the job's publications drained while it was still
        // building, so teardown owes nothing and waits for nothing.
        let owed = spool_records(cas_path);
        if owed == 0 {
            return 0;
        }
        let Some(instance) = instance else {
            return owed;
        };
        loop {
            self.sweep_path(cas_path, instance);
            self.publisher
                .wait_idle(deadline.saturating_duration_since(Instant::now()));
            let owed = spool_records(cas_path);
            let remaining = deadline.saturating_duration_since(Instant::now());
            if owed == 0 || remaining.is_zero() {
                return owed;
            }
            // A publication that failed keeps its record, and its retry is a
            // sweep away. Spending what is left of the budget on another attempt
            // beats parking on it: the alternative for the caller is the account
            // losing this job's entire warm image over one transient failure.
            std::thread::sleep(DRAIN_RETRY_BACKOFF.min(remaining));
        }
    }

    /// The instance a drain routes to, WITHOUT going through `resolve_instance`.
    /// That one is the seam where "a project is being built on this machine" is
    /// known, and it acts on the transition (trunk ingestion, registry persist).
    /// A drain is the opposite signal — the build is over — so it reads the
    /// mapping and leaves that machinery alone.
    fn drain_instance(&self, cas_path: &str, declared: &str) -> Option<String> {
        if !declared.is_empty() {
            return Some(declared.to_string());
        }
        self.path_instance.lock().unwrap().get(cas_path).cloned()
    }

    /// Refreshes the bearer only when it is within `lead` of its JWT expiry,
    /// keeping a long-lived proxy authenticated without re-auth'ing on a fixed
    /// cadence. Called every maintenance tick (cheap); a no-op in env-only (CI)
    /// mode or for opaque, non-expiring tokens.
    pub fn maintain_token(&self, lead: std::time::Duration) {
        self.tokens.refresh_if_expiring(lead);
    }

    /// Re-resolves the machine's cache endpoint, at most once per `interval`.
    ///
    /// The endpoint this process was launched with belongs to an account whose
    /// cache can be placed in another region. The region being left serves for
    /// a drain window and is then torn down, and its hostname goes out of DNS
    /// with it — so a proxy that never asks again eventually holds a name that
    /// resolves to nothing and turns every lookup into a local miss, reporting
    /// no error because a miss is a legitimate answer from a cache. Asking well
    /// inside the drain window means the move is picked up before anything
    /// fails, rather than recovered from afterwards.
    ///
    /// Resolved for an instance this proxy is already serving: the endpoint is
    /// per-account and every instance here shares it, so any known full handle
    /// answers the question. Before the first build there is none — and nothing
    /// depending on the answer either.
    ///
    /// A resolution that fails changes nothing. A CLI that is absent, logged
    /// out or offline says nothing about where the cache went, and dropping a
    /// working endpoint on its say-so would turn a local problem into a cold
    /// cache.
    pub fn refresh_endpoint(&self) {
        let Some(instance) = self.remotes.lock().unwrap().keys().next().cloned() else {
            // Nothing is being served, so nothing depends on the answer. First
            // sight of an instance resolves before binding a client to it.
            return;
        };
        self.ensure_endpoint_fresh(&instance);
    }

    /// Re-resolves the endpoint for `instance` unless it was resolved within
    /// `ENDPOINT_REFRESH_INTERVAL`.
    ///
    /// The endpoint is per-account and every instance this proxy serves shares
    /// it, so any of them answers the question; the caller passes the one it
    /// has, which is what lets first sight resolve before there is anything in
    /// the client map to look one up from.
    ///
    /// Never called with a lock held: adopting a moved endpoint takes the
    /// client map.
    fn ensure_endpoint_fresh(&self, instance: &str) {
        let Some(fetch) = self.tokens.cli_fetch() else {
            return;
        };
        if !self.claim_endpoint_resolution(crate::reapi::now_ms(), ENDPOINT_REFRESH_INTERVAL) {
            return;
        }
        if let Some(resolved) =
            crate::endpoint::resolve(&fetch.tuist_bin, fetch.server_url.as_deref(), instance)
        {
            self.adopt_endpoint(resolved);
        }
    }

    /// Whether this caller should do the resolution, stamping the attempt when
    /// it says yes.
    ///
    /// Stamped on the attempt rather than on success, so a CLI that is slow or
    /// failing is retried on the interval instead of on every request that
    /// finds the endpoint unresolved.
    fn claim_endpoint_resolution(&self, now: u64, interval: Duration) -> bool {
        let last = self.endpoint_resolved_at_ms.load(Ordering::Relaxed);
        if last != 0 && now.saturating_sub(last) < interval.as_millis() as u64 {
            return false;
        }
        self.endpoint_resolved_at_ms.store(now, Ordering::Relaxed);
        true
    }

    /// Points the proxy at `resolved`, returning whether it was a move.
    ///
    /// Both halves have to go together. The clients hold channels opened
    /// against the old address and would go on using them, so they are dropped
    /// here rather than left to fail on their own schedule; each rebuilds
    /// against the new endpoint on its next request. Keeping the old clients
    /// would mean the endpoint had changed in name only.
    fn adopt_endpoint(&self, resolved: String) -> bool {
        if resolved == *self.grpc_url.read().unwrap() {
            return false;
        }
        *self.grpc_url.write().unwrap() = resolved.clone();
        // Bumped before the clear, so a client published in the window between
        // them carries the superseded generation and is ignored rather than
        // surviving as the one entry the clear did not see.
        self.endpoint_generation.fetch_add(1, Ordering::AcqRel);
        self.remotes.lock().unwrap().clear();
        crate::log_line(&format!("proxy cache endpoint moved to {resolved}"));
        true
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
            // Forget everything rather than refuse everything. A successful claim
            // is never removed, so this set is a lifetime history, and bounding
            // it the way the QUEUE is bounded meant that once a machine had
            // refreshed enough keys it would never refresh another one, however
            // empty the queue. Identity now includes the instance and the tags,
            // so a few large projects or a run of branches reach that sooner.
            //
            // Dropping the history costs at most a re-publish of something
            // already published, which the server damps.
            if refreshed.len() >= VIEW_REFRESH_HISTORY_MAX {
                refreshed.clear();
            }
            if !refreshed.insert(dedup.clone()) {
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
        // The one place a snapshot enters the map, so this is the whole of what
        // `PrefetchMode::Off` has to stop. Nothing downstream can run without a
        // snapshot: the refresh only plans deltas for instances already here,
        // the warm walks a snapshot's keys, and a fetch instruction gives up
        // immediately when no fetch is in flight rather than waiting one out.
        if prefetch_mode() == PrefetchMode::Off {
            return;
        }
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
            match load_sources(&sources_path_for(path)) {
                Some(sources) => {
                    let source = sources.get(instance).map(clone);
                    *self.instance_sources.lock().unwrap() = sources;
                    source
                }
                // Unreadable: keep what we last saw rather than forgetting every
                // project's policy because one read lost a race with setup.
                None => self.instance_sources.lock().unwrap().get(instance).map(clone),
            }
        } else {
            self.instance_sources.lock().unwrap().get(instance).map(clone)
        }
    }

    /// Queues materialization of every graph the snapshot describes: bulk
    /// content warming with no keylog and no demand ordering. Resolves answer
    /// from the snapshot regardless and loads self-heal per object, so this only
    /// keeps the link busy so most loads find bytes already local. Once per
    /// snapshot fetch (i.e. per proxy lifetime per instance); after a mid-day
    /// wipe, demand-driven jobs and per-object self-heals carry
    /// re-materialization.
    fn prematerialize_snapshot(&self, instance: &str, snapshot: &Snapshot) {
        // `Keys` buys the snapshot's breadth and declines to pull its bytes. The
        // budget below cannot express that: its zero means "no cap", and its
        // smallest honest value still warms a node, so the only way to fetch
        // nothing is not to start.
        if prefetch_mode() == PrefetchMode::Keys {
            return;
        }
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
            // so full ingestion (the layer above key caching) warms all of it:
            // the scoping already bounds it to the trunk, not the whole polluted
            // namespace. Unscoped, or not yet a real build, keep the node budget.
            // The mode is necessarily Full here, the other two having stopped
            // above.
            let configured = if self.resolve_trunk(instance).is_some()
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

    /// Whether a snapshot that old may answer a BACKED check. Pure, and split out
    /// from `handle` so the policy is testable without a CAS on disk or a remote
    /// to talk to.
    ///
    /// `None` (no Ready snapshot) is not fresh: there is nothing to answer from.
    /// That is a separate outcome from the durably-snapshotless decline, which
    /// `handle` decides before this runs.
    fn snapshot_may_answer_backing(full_fetch_age: Option<Duration>) -> bool {
        full_fetch_age.is_some_and(|age| age <= SNAPSHOT_BACKING_MAX_AGE)
    }

    /// Classifies the instance's snapshot state for a BACKED check, under ONE
    /// lock, so the snapshot, its lifecycle state and its age describe the same
    /// instant. Read separately they did not: a `Fetching -> Ready` transition
    /// landing between two reads answered "no snapshot" and served the unverified
    /// hit, and a full refresh landing between the snapshot read and the age read
    /// blessed the OLD snapshot with the NEW timestamp.
    ///
    /// `Fetching` is the window the check exists for. The proxy and the build
    /// start together on CI, so the first build's gets land mid-fetch, on the cold
    /// freshly promoted cache volume where an inherited association is most
    /// likely to be hollow; declining there would leave the original failure
    /// fully reachable, so it goes per key. Anything else without a snapshot is
    /// durable — an hour for a server without snapshot support, forever under
    /// `TUIST_CAS_PREFETCH=0` — and a round trip per served hit for that long
    /// would undo the reason a local hit is worth having.
    fn backing_source(&self, instance: &str) -> BackingSource {
        let mut snapshots = self.snapshots.lock().unwrap();
        match snapshots.get_mut(instance) {
            Some(SnapshotState::Ready {
                snapshot,
                full_at,
                last_used,
                ..
            }) => {
                *last_used = Instant::now();
                if Self::snapshot_may_answer_backing(Some(full_at.elapsed())) {
                    BackingSource::Snapshot(snapshot.clone())
                } else {
                    BackingSource::PerKey
                }
            }
            Some(SnapshotState::Fetching) => BackingSource::PerKey,
            _ => BackingSource::Decline,
        }
    }

    /// The lookup behind a BACKED check. Deliberately NOT `resolve`.
    ///
    /// `resolve` serves `resolved` first, and `resolved` holds every hit this
    /// proxy has ever answered — remote-sourced ones included — for as long as it
    /// runs. A resolve may trust that, because it goes on to FETCH the blobs: a
    /// key the remote has since dropped fails materialization and is withheld,
    /// so the answer checks itself. A BACKED check authorises serving a graph
    /// that is ALREADY local, fetches nothing, and would never discover the entry
    /// was gone. Its `yes` may therefore only come from the two sources that
    /// describe the remote NOW: a snapshot gated within
    /// `SNAPSHOT_BACKING_MAX_AGE`, or the remote itself. Nor may a miss fall
    /// back to `resolved` the way `resolve_uncached` does for a just-published
    /// key: the remote has just said no, and an older yes does not outrank it.
    ///
    /// The per-key leg is one attempt under `BACKED_REMOTE_DEADLINE`, and there
    /// is no single-flight: two frontends asking about one key in the same
    /// moment pay two round trips, which is rare and cheaper than the lock they
    /// would otherwise share with every resolve.
    fn backing_lookup(
        &self,
        remote: &Arc<Remote>,
        state: &'static PathState,
        key: &[u8],
        source: BackingSource,
    ) -> Result<Option<Vec<u8>>, String> {
        state.stats_backing_checks.fetch_add(1, Ordering::Relaxed);
        self.check_generation(state);
        let observed = state.gen_counter.load(Ordering::SeqCst);
        let manifest = match source {
            BackingSource::Decline => return Err("no snapshot".into()),
            BackingSource::Snapshot(snapshot) => {
                use sha2::{Digest, Sha256};
                let key_hash: [u8; 32] = Sha256::digest(key).into();
                match snapshot.manifest(&key_hash) {
                    Some(manifest) => {
                        state.stats_backing_snapshot.fetch_add(1, Ordering::Relaxed);
                        Some(manifest)
                    }
                    None => self.backing_per_key(remote, state, key)?,
                }
            }
            BackingSource::PerKey => self.backing_per_key(remote, state, key)?,
        };
        let Some(manifest) = manifest.filter(|manifest| !manifest.is_empty()) else {
            state.stats_backing_unbacked.fetch_add(1, Ordering::Relaxed);
            return Ok(None);
        };
        match self.commit_and_materialize(remote, state, key, manifest, observed)? {
            Some(value) => Ok(Some(value)),
            // The store's generation moved while the remote was being asked (a
            // wipe or a prune), so the answer describes a store that is gone.
            // That says nothing about the remote and must not read as a miss.
            None => Err("store generation changed during the check".into()),
        }
    }

    fn backing_per_key(
        &self,
        remote: &Arc<Remote>,
        state: &PathState,
        key: &[u8],
    ) -> Result<Option<Vec<ManifestEntry>>, String> {
        state.stats_backing_per_key.fetch_add(1, Ordering::Relaxed);
        remote.get_action_within(key, BACKED_REMOTE_DEADLINE)
    }

    /// How long ago this instance's snapshot last had a FULL fetch, which is the
    /// only refresh that re-applies the server's eviction gate. `None` when
    /// there is no Ready snapshot to age.
    fn snapshot_full_fetch_age(&self, instance: &str) -> Option<Duration> {
        match self.snapshots.lock().unwrap().get(instance) {
            Some(SnapshotState::Ready { full_at, .. }) => Some(full_at.elapsed()),
            _ => None,
        }
    }

    /// Whether a snapshot that old may still answer resolves. Pure, and split
    /// out from the serving path so the policy is testable without a store on
    /// disk or a remote to talk to.
    ///
    /// `None` (no Ready snapshot) is not fresh: there is nothing to answer from,
    /// and the per-key path already handles that case.
    fn snapshot_may_serve(full_fetch_age: Option<Duration>) -> bool {
        full_fetch_age.is_some_and(|age| age <= SNAPSHOT_SERVE_MAX_AGE)
    }

    /// Whether this instance's stale snapshot is worth reporting, and claims the
    /// report if so. Split from the logging because that is the half a test can
    /// see: `log_line` writes to a file named by an env var, and mutating the
    /// environment races every other test in the binary.
    fn should_report_stale_snapshot(&self, instance: &str) -> bool {
        self.stale_snapshot_logged
            .lock()
            .unwrap()
            .insert(instance.to_string())
    }

    /// Says once per instance that its snapshot has aged out of serving. Worth a
    /// line: the effect is silent otherwise — resolves keep succeeding, just via
    /// a round trip each — so a refresh loop that stopped would surface only as
    /// "builds got slower" with nothing naming the cause.
    fn note_stale_snapshot(&self, instance: &str, age: Duration) {
        if self.should_report_stale_snapshot(instance) {
            crate::log_line(&format!(
                "snapshot for {instance} last fully fetched {}s ago (limit {}s); \
                 serving resolves per key until it refreshes",
                age.as_secs(),
                SNAPSHOT_SERVE_MAX_AGE.as_secs()
            ));
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
                "{}: resolves={} remote_hits={} snapshot_hits={} misses={} demand_fetched={} pending={} blobs={} inlined={} published={} incomplete_closures={} withheld_refused={} withheld_repaired={} backing checks={} snapshot={} per_key={} unbacked={} | ms action={} filter={} fetch={} decode={} store={} | us publish_local={} nodes_loaded={} shed={}",
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
                state.stats_incomplete_closures.load(Ordering::Relaxed),
                state.stats_withheld_roots_refused.load(Ordering::Relaxed),
                state.stats_withheld_roots_repaired.load(Ordering::Relaxed),
                state.stats_backing_checks.load(Ordering::Relaxed),
                state.stats_backing_snapshot.load(Ordering::Relaxed),
                state.stats_backing_per_key.load(Ordering::Relaxed),
                state.stats_backing_unbacked.load(Ordering::Relaxed),
                state.ms_action.load(Ordering::Relaxed),
                state.ms_filter.load(Ordering::Relaxed),
                state.ms_fetch.load(Ordering::Relaxed),
                state.ms_decode.load(Ordering::Relaxed),
                state.ms_store.load(Ordering::Relaxed),
                state.us_publish_local.load(Ordering::Relaxed),
                state.stats_publish_nodes_loaded.load(Ordering::Relaxed),
                state.stats_publish_shed.load(Ordering::Relaxed),
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
                // A snapshot answers from a copy of the remote's keyspace, so
                // its authority expires. Past the bound, stop serving from it
                // and let the key take the per-key path, which kura gates on
                // every call. Dropping it here rather than inside `resolve` also
                // suppresses the view refresh that a per-key hit would otherwise
                // queue: that refresh exists to re-rank a key that fell out of a
                // CURRENT view, which says nothing when the view is stale.
                let snapshot = self.snapshot_ready(&instance).filter(|_| {
                    let age = self.snapshot_full_fetch_age(&instance);
                    let fresh = Self::snapshot_may_serve(age);
                    if !fresh {
                        if let Some(age) = age {
                            self.note_stale_snapshot(&instance, age);
                        }
                    }
                    fresh
                });
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
            OP_BACKED => {
                // The plugin holds a local association and wants to know whether
                // its closure is producible before serving it. NOT a resolve:
                // the answer must describe the remote now, and `resolve` serves
                // `resolved` first, which describes whatever this proxy answered
                // at any point in its life. See `backing_lookup`.
                let Some(instance) = self.resolve_instance(&request.cas_path, &request.instance)
                else {
                    self.note_unprimed(&request.cas_path);
                    return write_response(&mut stream, STATUS_ERROR, b"unprimed instance");
                };
                // A project that does not upload keeps its results off the
                // remote on purpose, so a remote miss says nothing about whether
                // its associations dangle and vetoing them would recompile the
                // whole build, every build. Read the policy HERE and not from
                // the plugin's own `upload` flag, for the same reason
                // `upload_enabled` exists at all: that flag comes from a
                // compiler option that reaches Swift, while swift-build's Clang
                // caching runs against a CAS created with a plugin path and no
                // options, so the Clang lane reads as uploading even under an
                // explicit opt-out — and the Clang lane is the one that fails
                // the build. Deciding this client-side would have left exactly
                // that lane recompiling forever.
                if !self.upload_enabled(&instance) {
                    return write_response(&mut stream, STATUS_ERROR, b"uploads disabled");
                }
                let remote = self.remote_for(&instance);
                self.ensure_snapshot(&instance, &remote);
                // One read of the snapshot state decides where the answer may
                // come from: `backing_source` is where `Fetching` goes per key
                // and a durable absence declines, and why.
                let source = match self.backing_source(&instance) {
                    BackingSource::Decline => {
                        return write_response(&mut stream, STATUS_ERROR, b"no snapshot");
                    }
                    source => source,
                };
                let outcome = self.path_state(&request.cas_path).and_then(|state| {
                    self.backing_lookup(&remote, state, &request.payload, source)
                });
                match outcome {
                    // The value digest goes back with the verdict: the
                    // instructions just registered describe the REMOTE's graph,
                    // and only the plugin can tell whether that is the same
                    // graph as the association it is about to serve.
                    Ok(Some(value)) => write_response(&mut stream, STATUS_HIT, &value),
                    Ok(None) => {
                        // The remote does not hold this key, yet the local store
                        // has an association for it. Nothing can retract that
                        // association, so it will be offered on every later get
                        // until the store generation rolls; the plugin declining
                        // to serve it is the only thing standing between it and
                        // a `missing object` build failure.
                        crate::log_line(&format!(
                            "unbacked association: instance={instance} key={} \
                             (local hit the remote cannot back; serving a recompile instead)",
                            reapi::hex(&request.payload)
                        ));
                        write_response(&mut stream, STATUS_MISS, &[])
                    }
                    Err(message) => {
                        crate::log_line(&format!("proxy backed check failed: {message}"));
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
            OP_DRAIN => {
                let owed = self.drain_publications(
                    &request.cas_path,
                    self.drain_instance(&request.cas_path, &request.instance)
                        .as_deref(),
                    drain_timeout(&request.payload),
                );
                if owed == 0 {
                    write_response(&mut stream, STATUS_HIT, &[])
                } else {
                    crate::log_line(&format!(
                        "proxy drain: {owed} publication(s) never reached the remote for {}",
                        request.cas_path
                    ));
                    write_response(&mut stream, STATUS_MISS, owed.to_string().as_bytes())
                }
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

/// The sources registry sits next to the cas_path registry, written by
/// `tuist setup cache` (the only place that has the project's configuration).
/// `<registry>.sources`: a JSON object of instance -> `RegisteredSource`. JSON
/// because the writer is Swift and the reader is here, and a format each side
/// hand-rolls is one each side can drift on.
fn sources_path_for(registry: &Path) -> PathBuf {
    let mut path = registry.to_path_buf().into_os_string();
    path.push(".sources");
    PathBuf::from(path)
}

/// `None` when the registry could not be read at all, which is NOT the same as
/// an empty one: setup rewrites this file, and a read landing mid-rewrite would
/// otherwise turn every project on the machine into an unknown one. Unknown
/// means "no policy recorded", and the answer there has to be permissive, so a
/// transient read error would quietly hand an opted-out project an upload
/// window.
fn load_sources(path: &Path) -> Option<HashMap<String, RegisteredSource>> {
    let body = std::fs::read_to_string(path).ok()?;
    // A file torn or truncated under us reads as unreadable rather than as a
    // subset of the projects, which is the answer that matters: a project this
    // read forgot would come back as unknown, and unknown has to be allowed to
    // upload.
    serde_json::from_str(&body)
        .map_err(|error| {
            crate::log_line(&format!("sources registry at {}: {error}", path.display()));
            error
        })
        .ok()
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

/// The manifest for the value graph rooted at `root`, in visit order, plus the
/// encoded blob for every node THIS walk had to read (a memo hit yields `None`,
/// because the bytes are only needed for the nodes the remote turns out to be
/// missing and re-reading them then is cheaper than holding every closure in
/// memory).
///
/// Each node the memo does not already hold costs an `llcas_cas_load_object`,
/// and what that load costs depends on the on-disk store's state: once the
/// store crosses `COMPILATION_CACHE_LIMIT_SIZE` it enforces the limit by
/// starting a new generation and demoting the old one, and a load resolving in
/// a demoted generation copies the object forward. Measured on Xcode 26.5
/// (`tests/graph_retention.rs`), the same 41-node walk is ~1.5us against a
/// store that has not rotated and ~167us/key on the first pass after one.
///
/// Worth knowing and worth measuring (`us_publish_local`), but worth keeping in
/// proportion: 100x a number this size is still small against one RPC, and a
/// publication makes four. A walk cost is not a candidate explanation for a
/// `write_duration` regression measured in hundreds of milliseconds.
/// `encode_node_blob` with the local-cost accounting attached. Every llcas read
/// a publication makes goes through here, because a publication makes them from
/// TWO places and the counters are worth nothing if they only see one: the walk
/// below reads each node it has not memoized, and the upload leg reads again for
/// any node the memo answered from cache that the remote then turns out to be
/// missing. That second read is local CAS latency sitting inside
/// `write_duration` exactly like the first, and accounting for only the first
/// would let the counters report no local work while the store was the thing
/// being slow, which is the one conclusion they exist to prevent.
fn encode_node_blob_accounted(
    state: &'static PathState,
    digest: &[u8],
) -> Result<(Vec<u8>, Vec<Vec<u8>>), String> {
    let started = Instant::now();
    let loaded = unsafe { encode_node_blob(state, digest) };
    state
        .us_publish_local
        .fetch_add(started.elapsed().as_micros() as u64, Ordering::Relaxed);
    state
        .stats_publish_nodes_loaded
        .fetch_add(1, Ordering::Relaxed);
    loaded
}

fn walk_closure(
    state: &'static PathState,
    root: &[u8],
) -> Result<(Vec<ManifestEntry>, Vec<Option<Vec<u8>>>), String> {
    let mut entries: Vec<ManifestEntry> = Vec::new();
    let mut blobs: Vec<Option<Vec<u8>>> = Vec::new();
    let mut visited = HashSet::new();
    let mut pending = VecDeque::from([root.to_vec()]);
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
        let (blob, children) = encode_node_blob_accounted(state, &digest)?;
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
    Ok((entries, blobs))
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

    /// The churn-skip must not swallow the reclaim: a trunk build re-putting a
    /// value it already resolved may be republishing an entry that is still
    /// tagged with a feature branch, and only that publish pulls it into the
    /// trunk view.
    #[test]
    fn a_trunk_reput_is_never_dropped_as_churn() {
        // Feature, local (no branch), and fully untagged re-puts reclaim nothing
        // into trunk, so a value match is genuine churn.
        assert!(is_redundant_reput(Some("feature/x"), Some("main"), true));
        assert!(is_redundant_reput(None, Some("main"), true));
        assert!(is_redundant_reput(None, None, true));

        // A trunk publish (branch == trunk) is the reclaim path: even on a value
        // match it must reach `publish`, so it is never redundant.
        assert!(!is_redundant_reput(Some("main"), Some("main"), true));

        // A value mismatch is a genuine recompute and always publishes, trunk or
        // not.
        assert!(!is_redundant_reput(Some("feature/x"), Some("main"), false));
        assert!(!is_redundant_reput(Some("main"), Some("main"), false));
    }

    /// The two layers cost different orders of magnitude, so the middle state is
    /// the one CI runs on and the one this parse exists to keep reachable. A
    /// value that fell through to `Full` here would turn CI's one round trip
    /// into a full closure pull, which is the failure this pins.
    /// A snapshot's answer is only as good as the last time its copy of the
    /// remote's keyspace was gated, and only a FULL fetch re-gates it — deltas
    /// add and never remove. Past the bound it stops serving and keys take the
    /// per-key path, which kura gates on every call.
    #[test]
    fn a_snapshot_stops_serving_once_its_gate_is_stale() {
        assert!(Proxy::snapshot_may_serve(Some(Duration::from_secs(0))));
        assert!(Proxy::snapshot_may_serve(Some(SNAPSHOT_SERVE_MAX_AGE)));
        assert!(!Proxy::snapshot_may_serve(Some(
            SNAPSHOT_SERVE_MAX_AGE + Duration::from_secs(1)
        )));
        // Nothing to serve from is not "fresh"; the per-key path covers it.
        assert!(!Proxy::snapshot_may_serve(None));
        // A scheduled full refresh lands at SNAPSHOT_FULL_INTERVAL, so healthy
        // operation must never trip this. Tightening the bound below the cadence
        // would put every build on per-key round trips.
        assert!(
            SNAPSHOT_SERVE_MAX_AGE > SNAPSHOT_FULL_INTERVAL,
            "the bound must leave room for the refresh cadence meant to keep it fresh"
        );
    }

    /// The field choice is the substance, and it is the easy one to get wrong:
    /// age comes from the last FULL fetch, never the last delta. Deltas only
    /// ADD, so a view refreshed by deltas alone looks continuously fresh while
    /// never re-applying the server's eviction gate — which is precisely the
    /// state that serves keys the remote has dropped.
    #[test]
    fn snapshot_age_comes_from_the_full_fetch_not_the_delta() {
        let dir = std::env::temp_dir().join(format!("tuist-snapage-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let registry = dir.join("registry");
        std::fs::write(
            sources_path_for(&registry),
            r#"{"tuist/writer":{"trunk":"main"}}"#,
        )
        .expect("write sources");
        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            String::new(),
            Some(registry),
            None,
        );

        // What a held-off refresh loop leaves behind: deltas kept landing, the
        // full re-gate did not.
        let stale = Instant::now()
            .checked_sub(SNAPSHOT_SERVE_MAX_AGE + Duration::from_secs(60))
            .expect("clock has enough history");
        proxy.snapshots.lock().unwrap().insert(
            "tuist/writer".to_string(),
            SnapshotState::Ready {
                snapshot: Arc::new(Snapshot {
                    nodes: Vec::new(),
                    node_index: HashMap::new(),
                    keys: HashMap::new(),
                    key_order: Vec::new(),
                    watermark: 0,
                }),
                full_at: stale,
                refreshed_at: Instant::now(),
                last_used: Instant::now(),
            },
        );

        let age = proxy
            .snapshot_full_fetch_age("tuist/writer")
            .expect("a Ready snapshot has an age");
        assert!(
            age > SNAPSHOT_SERVE_MAX_AGE,
            "reading `refreshed_at` instead of `full_at` would have called this fresh"
        );
        assert!(!Proxy::snapshot_may_serve(Some(age)));

        std::fs::remove_dir_all(&dir).ok();
    }

    /// One line per instance, not one per resolve: the condition persists for as
    /// long as the refresh stays stuck, and a warm build issues thousands of
    /// resolves through it.
    #[test]
    fn an_aged_out_snapshot_is_reported_once_per_instance() {
        let dir = std::env::temp_dir().join(format!("tuist-snaplog-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            String::new(),
            Some(dir.join("registry")),
            None,
        );

        assert!(
            proxy.should_report_stale_snapshot("tuist/writer"),
            "the first resolve through a stale view reports it"
        );
        for _ in 0..5 {
            assert!(
                !proxy.should_report_stale_snapshot("tuist/writer"),
                "and the thousands behind it in a warm build do not"
            );
        }
        assert!(
            proxy.should_report_stale_snapshot("tuist/other"),
            "a second instance is its own report"
        );

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn prefetch_keys_is_its_own_mode_and_not_a_way_of_spelling_off() {
        assert_eq!(prefetch_mode_from(Some("keys")), PrefetchMode::Keys);
        assert_eq!(prefetch_mode_from(Some("KEYS")), PrefetchMode::Keys);
        assert_eq!(prefetch_mode_from(Some(" keys ")), PrefetchMode::Keys);

        for off in ["0", "off", "false", "no", "none", "OFF"] {
            assert_eq!(prefetch_mode_from(Some(off)), PrefetchMode::Off, "{off}");
        }

        // Unset is the default, and so is anything unrecognized: a typo must not
        // quietly turn caching down, which is the direction that costs a build.
        assert_eq!(prefetch_mode_from(None), PrefetchMode::Full);
        assert_eq!(prefetch_mode_from(Some("full")), PrefetchMode::Full);
        assert_eq!(prefetch_mode_from(Some("kyes")), PrefetchMode::Full);
        assert_eq!(prefetch_mode_from(Some("")), PrefetchMode::Full);
    }

    #[test]
    fn sources_registry_keeps_reading_entries_written_without_a_trunk() {
        let dir = std::env::temp_dir().join(format!("tuist-sources-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("temp dir");
        let path = dir.join("registry.sources");
        // Row 1 is what a setup that reached the server writes; row 2 is a setup
        // that could not, so it knows the project but not its trunk. Both must
        // parse, and the bare row must leave the proxy unscoped rather than
        // dropping the project entirely, which would read as "no policy" and
        // hand an opted-out project an upload.
        std::fs::write(
            &path,
            r#"{"tuist/mastodon":{"trunk":"main"},"tuist/legacy":{}}"#,
        )
        .expect("write registry");

        let sources = load_sources(&path).expect("a readable registry parses");
        assert_eq!(sources.len(), 2);
        // Unreadable is not the same as empty, and the difference decides whether
        // an opted-out project keeps its policy: setup rewrites this file, and a
        // read landing mid-rewrite must not be mistaken for "no projects here".
        assert!(
            load_sources(&dir.join("does-not-exist")).is_none(),
            "a registry that cannot be read reports so, rather than reporting none"
        );
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
                format!(r#"{{"tuist/mastodon":{{"trunk":"main","branch":"{branch}"}}}}"#),
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
                format!(r#"{{"tuist/mastodon":{{"trunk":"main","branch":"{branch}"}}}}"#),
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

        let captured: Arc<Mutex<Vec<Vec<u8>>>> = Arc::new(Mutex::new(Vec::new()));
        // One per proxy: a publisher is owned by the process that ran it, and
        // draining one stops it for good.
        let start_proxy = || {
            let proxy = Proxy::new(
                "http://127.0.0.1:1".into(),
                crate::token::TokenProvider::from_env(),
                String::new(),
                Some(registry.clone()),
                None,
            );
            let sink = Arc::clone(&captured);
            proxy
                .publisher
                .configure(1, move |item| sink.lock().unwrap().push(item));
            proxy
        };

        // The build hands us the record while the main job owns the registry.
        let producing = start_proxy();
        producing.enqueue_publish(&cas_path.to_string_lossy(), "tuist/mastodon", &record_path);
        assert!(
            spool.join("1234-0.tags").exists(),
            "accepting a record writes its tags beside it"
        );
        producing
            .publisher
            .drain_stop_timeout(std::time::Duration::from_secs(10));

        // The next job on this runner runs setup, rewriting the registry, and a
        // later sweep finds the record still there. That sweep runs in a proxy
        // that never saw the build: a fresh process, so nothing but the sidecar
        // survives to tell it which branch produced this record.
        record_branch("feature/theirs");
        let sweeping = start_proxy();
        sweeping.enqueue_publish(&cas_path.to_string_lossy(), "tuist/mastodon", &record_path);
        sweeping
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

    /// Builds a proxy whose publisher, instead of uploading, runs `publish` for
    /// each queued item — the seam the drain tests use to decide which records
    /// "reach the remote" and which are left behind.
    fn proxy_with_publisher<F>(registry: std::path::PathBuf, publish: F) -> &'static Proxy
    where
        F: Fn(&str) + Send + Sync + 'static,
    {
        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            String::new(),
            Some(registry),
            None,
        );
        proxy.publisher.configure(1, move |item| {
            let Some((_, rest)) = take_u16_field(&item) else { return };
            let Some((_, rest)) = take_u16_field(rest) else { return };
            let Some((_, rest)) = take_u16_field(rest) else { return };
            let Some((_, record_path)) = take_u16_field(rest) else { return };
            publish(&String::from_utf8_lossy(record_path));
        });
        proxy
    }

    fn drain_fixture(name: &str) -> (std::path::PathBuf, std::path::PathBuf) {
        let dir = std::env::temp_dir().join(format!("tuist-drain-{name}-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let registry = dir.join("registry");
        std::fs::write(
            sources_path_for(&registry),
            r#"{"tuist/mastodon":{"trunk":"main","branch":"main"}}"#,
        )
        .expect("write sources");
        let spool = dir.join("cas").join("tuist-spool");
        std::fs::create_dir_all(&spool).expect("spool");
        (dir, registry)
    }

    /// The promote gate a runner's teardown stands on: has everything this job
    /// recorded actually reached the remote? A record is deleted ONLY by a
    /// successful publish, so an empty spool is the proof, and the drain is what
    /// waits for it rather than sampling it.
    #[test]
    fn a_drain_reports_a_spool_the_publisher_emptied_as_clean() {
        let (dir, registry) = drain_fixture("clean");
        let spool = dir.join("cas").join("tuist-spool");
        std::fs::write(spool.join("1234-0"), b"record").expect("record");
        std::fs::write(spool.join("1234-1"), b"record").expect("record");

        let proxy = proxy_with_publisher(registry, |record_path| remove_record(record_path));
        let remaining = proxy.drain_publications(
            &dir.join("cas").to_string_lossy(),
            Some("tuist/mastodon"),
            std::time::Duration::from_secs(10),
        );

        assert_eq!(remaining, 0);
        std::fs::remove_dir_all(&dir).ok();
    }

    /// A publication the proxy could not send keeps its record, and the drain has
    /// to say so. Promoting that image anyway is the whole defect: every host
    /// that later clones the master inherits associations naming objects no kura
    /// holds, and nothing can retract them.
    #[test]
    fn a_drain_reports_the_records_publication_left_behind() {
        let (dir, registry) = drain_fixture("dirty");
        let spool = dir.join("cas").join("tuist-spool");
        std::fs::write(spool.join("1234-0"), b"published").expect("record");
        std::fs::write(spool.join("1234-1"), b"stuck").expect("record");

        // The publisher keeps the record whose upload failed, exactly as
        // `publish_item` does.
        let proxy = proxy_with_publisher(registry, |record_path| {
            if record_path.ends_with("1234-0") {
                remove_record(record_path);
            }
        });
        // A budget of a couple of retries: the drain re-sweeps a failed
        // publication until the caller's deadline, so a generous one here would
        // only make this test wait out the backoff.
        let remaining = proxy.drain_publications(
            &dir.join("cas").to_string_lossy(),
            Some("tuist/mastodon"),
            std::time::Duration::from_millis(2500),
        );

        assert_eq!(remaining, 1, "the record that never landed is still counted");
        std::fs::remove_dir_all(&dir).ok();
    }

    /// The plugin writes its record BEFORE notifying the proxy, so a frontend
    /// that exited without reaching the socket leaves one nothing has queued.
    /// Waiting on the pool alone would call that spool drained while its records
    /// sit there, so the drain sweeps first.
    #[test]
    fn a_drain_sweeps_records_the_proxy_was_never_notified_about() {
        let (dir, registry) = drain_fixture("unnotified");
        let spool = dir.join("cas").join("tuist-spool");
        std::fs::write(spool.join("1234-0"), b"never announced").expect("record");

        let published: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
        let seen = Arc::clone(&published);
        let proxy = proxy_with_publisher(registry, move |record_path| {
            seen.lock().unwrap().push(record_path.to_string());
            remove_record(record_path);
        });
        let remaining = proxy.drain_publications(
            &dir.join("cas").to_string_lossy(),
            Some("tuist/mastodon"),
            std::time::Duration::from_secs(10),
        );

        assert_eq!(remaining, 0);
        assert_eq!(
            published.lock().unwrap().len(),
            1,
            "the drain swept the record and published it"
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    /// Without a routable instance there is nothing to publish TO, so records
    /// cannot have reached the remote — the drain must report them rather than
    /// read "nothing queued" as "nothing owed".
    #[test]
    fn a_drain_of_an_unroutable_path_reports_its_records_as_owed() {
        let (dir, registry) = drain_fixture("unrouted");
        let spool = dir.join("cas").join("tuist-spool");
        std::fs::write(spool.join("1234-0"), b"record").expect("record");

        let proxy = proxy_with_publisher(registry, |record_path| remove_record(record_path));
        let remaining = proxy.drain_publications(
            &dir.join("cas").to_string_lossy(),
            None,
            std::time::Duration::from_secs(10),
        );

        assert_eq!(remaining, 1);
        std::fs::remove_dir_all(&dir).ok();
    }

    /// A path that never published has no spool directory at all, which is the
    /// common case on a runner whose job used the builtin lane. It has to read as
    /// drained, or every such job would withhold its promote.
    #[test]
    fn a_path_that_never_published_drains_immediately() {
        let (dir, registry) = drain_fixture("empty");
        let proxy = proxy_with_publisher(registry, |record_path| remove_record(record_path));

        let remaining = proxy.drain_publications(
            &dir.join("never-built").to_string_lossy(),
            Some("tuist/mastodon"),
            std::time::Duration::from_secs(10),
        );

        assert_eq!(remaining, 0);
        std::fs::remove_dir_all(&dir).ok();
    }

    /// The wait is the caller's budget: the guest holds a VM (and its warm-pool
    /// slot) open for it. An absent or absurd value must not turn into an
    /// unbounded park on a proxy thread.
    #[test]
    fn a_drain_request_carries_a_bounded_timeout() {
        assert_eq!(
            drain_timeout(&5_000u32.to_be_bytes()),
            Duration::from_secs(5)
        );
        assert_eq!(drain_timeout(&[]), DRAIN_TIMEOUT_DEFAULT);
        assert_eq!(drain_timeout(&0u32.to_be_bytes()), DRAIN_TIMEOUT_DEFAULT);
        assert_eq!(drain_timeout(&u32::MAX.to_be_bytes()), DRAIN_TIMEOUT_MAX);
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

    /// The CI branch, which `tuist setup cache` records only from inside a CI job
    /// (the proxy is a launchd agent and never sees the provider's branch
    /// variable). Every field here is optional, so what this pins is that an
    /// absent one reads as its default rather than as its neighbour's value:
    /// setup writes only what it knows, and it usually does not know all three.
    #[test]
    fn sources_registry_defaults_every_field_setup_did_not_record() {
        let dir = std::env::temp_dir().join(format!("tuist-sources-ci-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("temp dir");
        let path = dir.join("registry.sources");
        std::fs::write(
            &path,
            r#"{
                "tuist/ci":        {"trunk": "main", "branch": "feature/x"},
                "tuist/no-trunk":  {"branch": "feature/y"},
                "tuist/read-only": {"trunk": "main", "upload": false},
                "tuist/newer":     {"trunk": "main", "something-we-do-not-know": 1},
                "tuist/dev":       {"trunk": "main"},
                "tuist/bare":      {}
            }"#,
        )
        .expect("write registry");

        let sources = load_sources(&path).expect("a readable registry parses");
        let ci = sources.get("tuist/ci").expect("ci entry");
        assert_eq!(ci.trunk.as_deref(), Some("main"));
        assert_eq!(ci.ci_branch.as_deref(), Some("feature/x"));
        assert!(ci.upload, "an absent upload is permissive");

        // A branch without a trunk. Setup records these separately (the trunk is
        // the server's answer, the branch the job's), so either can be missing.
        let no_trunk = sources.get("tuist/no-trunk").expect("no-trunk entry");
        assert_eq!(no_trunk.trunk, None);
        assert_eq!(no_trunk.ci_branch.as_deref(), Some("feature/y"));

        assert!(!sources.get("tuist/read-only").expect("read-only entry").upload);

        // A setup newer than this proxy: unknown fields are ignored rather than
        // failing the whole file, which would take every project's policy with it.
        let newer = sources.get("tuist/newer").expect("newer entry");
        assert_eq!(newer.trunk.as_deref(), Some("main"));

        let dev = sources.get("tuist/dev").expect("dev entry");
        assert_eq!(
            dev.ci_branch, None,
            "off CI nothing records a branch, so a developer's publishes stay untagged"
        );

        let bare = sources.get("tuist/bare").expect("bare entry");
        assert_eq!(bare.trunk, None);
        assert_eq!(bare.ci_branch, None);
        assert!(bare.upload, "nothing recorded is nothing to withhold");

        // Unreadable is not the same as empty: a project this read forgot would
        // come back as unknown, and unknown has to be allowed to upload.
        std::fs::write(&path, "{not json").expect("write garbage");
        assert!(
            load_sources(&path).is_none(),
            "a registry that cannot be decoded reports so, rather than reporting none"
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
    #[test]
    fn the_endpoint_is_resolved_once_per_interval_not_once_per_request() {
        // Every first sight of an instance asks, and on a busy proxy that is
        // often. Resolution shells out to the CLI, so the interval is what
        // keeps it from becoming a process spawn per request.
        let proxy = test_proxy();
        let interval = Duration::from_secs(600);
        let start = 1_000_000_u64;

        assert!(proxy.claim_endpoint_resolution(start, interval));
        assert!(!proxy.claim_endpoint_resolution(start + 1, interval));
        assert!(!proxy.claim_endpoint_resolution(start + 599_999, interval));
        assert!(proxy.claim_endpoint_resolution(start + 600_000, interval));
    }

    #[test]
    fn a_failing_resolution_is_retried_on_the_interval_not_on_every_request() {
        // The stamp is taken on the attempt, not on success. Stamping only on
        // success would spawn the CLI for every request while it is failing —
        // exactly when the machine is least able to afford it.
        let proxy = test_proxy();
        let interval = Duration::from_secs(600);

        assert!(proxy.claim_endpoint_resolution(1_000_000, interval));
        // No adoption follows; the next caller still has to wait its turn.
        assert!(!proxy.claim_endpoint_resolution(1_000_100, interval));
    }

    #[test]
    fn a_client_built_before_a_move_is_not_served_after_it() {
        // The interleaving two first-sight requests can produce: both miss,
        // the first resolves and adopts while the second is still building,
        // and the second then publishes its client after the clear has already
        // run. Nothing orders those two, so the published client has to be
        // recognised as belonging to the endpoint it was dialled at.
        let proxy = test_proxy();
        let before_move = proxy.remote_for("acme/app");
        let generation = proxy.endpoint_generation.load(Ordering::Acquire);

        assert!(proxy.adopt_endpoint("http://127.0.0.1:2".to_string()));

        // The slower request publishes what it built, after the clear.
        proxy
            .remotes
            .lock()
            .unwrap()
            .insert("acme/app".to_string(), (generation, before_move.clone()));

        let served = proxy.remote_for("acme/app");

        assert!(
            !Arc::ptr_eq(&before_move, &served),
            "a client stamped before the move must not be served after it"
        );
        assert_eq!(
            proxy.remotes.lock().unwrap().get("acme/app").unwrap().0,
            proxy.endpoint_generation.load(Ordering::Acquire),
            "the rebuilt client carries the endpoint now in force"
        );
    }

    #[test]
    fn adopting_a_moved_endpoint_drops_the_clients_bound_to_the_old_one() {
        // A client holds a channel opened against the address it was built
        // with. Leaving it in place would move the endpoint in name only, and
        // the proxy would go on talking to a region that is being torn down.
        let proxy = test_proxy();
        let _ = proxy.remote_for("acme/app");
        assert_eq!(proxy.remotes.lock().unwrap().len(), 1);

        assert!(proxy.adopt_endpoint("http://127.0.0.1:2".to_string()));

        assert_eq!(*proxy.grpc_url.read().unwrap(), "http://127.0.0.1:2");
        assert!(
            proxy.remotes.lock().unwrap().is_empty(),
            "clients bound to the old endpoint must not survive the move"
        );
    }

    #[test]
    fn re_resolving_to_the_same_endpoint_keeps_the_clients() {
        // The common case by far. Rebuilding every client each time the
        // endpoint is re-read would throw away warm connections on a schedule
        // for no reason.
        let proxy = test_proxy();
        let before = proxy.remote_for("acme/app");
        let current = proxy.grpc_url.read().unwrap().clone();

        assert!(!proxy.adopt_endpoint(current));

        let after = proxy.remote_for("acme/app");
        assert!(
            Arc::ptr_eq(&before, &after),
            "an unchanged endpoint must not rebuild the client"
        );
    }

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
            withheld_roots: Mutex::new(HashMap::new()),
            stats_resolves: AtomicU64::new(0),
            stats_remote_hits: AtomicU64::new(0),
            stats_misses: AtomicU64::new(0),
            stats_snapshot_hits: AtomicU64::new(0),
            stats_demand_fetched: AtomicU64::new(0),
            stats_blobs_fetched: AtomicU64::new(0),
            stats_blobs_inlined: AtomicU64::new(0),
            stats_incomplete_closures: AtomicU64::new(0),
            stats_withheld_roots_refused: AtomicU64::new(0),
            stats_withheld_roots_repaired: AtomicU64::new(0),
            stats_backing_checks: AtomicU64::new(0),
            stats_backing_snapshot: AtomicU64::new(0),
            stats_backing_per_key: AtomicU64::new(0),
            stats_backing_unbacked: AtomicU64::new(0),
            stats_published: AtomicU64::new(0),
            ms_action: AtomicU64::new(0),
            ms_filter: AtomicU64::new(0),
            ms_fetch: AtomicU64::new(0),
            ms_decode: AtomicU64::new(0),
            ms_store: AtomicU64::new(0),
            us_publish_local: AtomicU64::new(0),
            stats_publish_nodes_loaded: AtomicU64::new(0),
            stats_publish_shed: AtomicU64::new(0),
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
                    r#"{{"tuist/one":{{"trunk":"main","branch":"{branch}"}},"tuist/two":{{"trunk":"main","branch":"{branch}"}}}}"#
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
            r#"{"tuist/one":{"trunk":"main","branch":"main"}}"#,
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
            r#"{"tuist/reader":{"trunk":"main","upload":false},"tuist/writer":{"trunk":"main"}}"#,
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

    /// The backing check must read the upload policy from HERE, for the reason
    /// `upload_enabled` exists: the plugin's own flag comes from a compiler
    /// option that reaches Swift, and swift-build's Clang caching runs against a
    /// CAS created with a plugin path and no options, so the Clang lane reads as
    /// uploading even under an explicit opt-out.
    ///
    /// Deciding it client-side therefore looks correct on the Swift lane and is
    /// wrong on the one that fails builds: a read-only project keeps every
    /// result off the remote by design, so a per-key lookup calls all of its
    /// associations unbacked, and the Clang lane would recompile the whole
    /// project on every build forever. Declining is what prevents that.
    #[test]
    fn a_read_only_project_is_never_told_its_association_is_unbacked() {
        use crate::proxy_proto::{read_response, write_request, PROTOCOL_VERSION};

        let dir = std::env::temp_dir().join(format!("tuist-backed-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let registry = dir.join("registry");
        std::fs::write(
            sources_path_for(&registry),
            r#"{"tuist/reader":{"trunk":"main","upload":false}}"#,
        )
        .expect("write sources");

        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            String::new(),
            Some(registry),
            None,
        );

        let (mut client, server) = UnixStream::pair().expect("socketpair");
        write_request(
            &mut client,
            &Request {
                version: PROTOCOL_VERSION,
                op: OP_BACKED,
                cas_path: "/cas".into(),
                instance: "tuist/reader".into(),
                payload: b"some-action-key".to_vec(),
            },
        )
        .expect("send");
        proxy.handle(server).expect("handle");
        let (status, body) = read_response(&mut client).expect("recv");

        assert_eq!(
            status, STATUS_ERROR,
            "a read-only project must be declined, not answered `unbacked`: only a MISS \
             withholds the hit, and every one of its keys would miss"
        );
        assert_eq!(body, b"uploads disabled");

        std::fs::remove_dir_all(&dir).ok();
    }

    /// `resolve`'s fast path serves `resolved` first, and `resolved` keeps every
    /// hit this proxy has ever answered, remote-sourced ones included, for as
    /// long as it runs. A check routed through it vouched for a key from that
    /// cache after the remote had dropped it, and `fetchable` made the value read
    /// as present without a byte on disk. That is the long-lived proxy — a
    /// developer's LaunchAgent, a long runner — serving a locally hollow graph
    /// hours after the remote stopped backing it.
    ///
    /// Here: a fresh snapshot that lacks the key, a `resolved` Hit for it with a
    /// registered instruction, and a remote that cannot be reached. The cache is
    /// the only thing that says yes, and it must not be consulted. The honest
    /// answer is `Unknown`.
    #[test]
    fn a_backing_check_never_vouches_from_the_resolved_cache() {
        use crate::proxy_proto::{read_response, write_request, PROTOCOL_VERSION};

        if !std::path::Path::new(&crate::upstream_path()).exists() {
            eprintln!("skipping: Apple's libToolchainCASPlugin is unavailable");
            return;
        }
        let dir = std::env::temp_dir().join(format!("tuist-backed-resolved-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let registry = dir.join("registry");
        std::fs::write(
            sources_path_for(&registry),
            r#"{"tuist/writer":{"trunk":"main"}}"#,
        )
        .expect("write sources");
        let cas_dir = dir.join("cas");
        std::fs::create_dir_all(&cas_dir).expect("cas dir");

        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            crate::upstream_path(),
            Some(registry),
            None,
        );
        // Fresh, and silent about the key.
        proxy.snapshots.lock().unwrap().insert(
            "tuist/writer".to_string(),
            SnapshotState::Ready {
                snapshot: Arc::new(Snapshot {
                    nodes: Vec::new(),
                    node_index: HashMap::new(),
                    keys: HashMap::new(),
                    key_order: Vec::new(),
                    watermark: 0,
                }),
                full_at: Instant::now(),
                refreshed_at: Instant::now(),
                last_used: Instant::now(),
            },
        );
        // What a long-lived proxy holds: the hit it answered earlier, and the
        // instruction that makes its value read as present with nothing on disk.
        let key = b"a-key-the-remote-has-since-dropped".to_vec();
        let value = vec![0xAB; 32];
        let cas_path = cas_dir.to_string_lossy().into_owned();
        let state = proxy.path_state(&cas_path).expect("path state");
        state
            .resolved
            .lock()
            .unwrap()
            .insert(key.clone(), Resolution::Hit(value.clone()));
        state.pending_objects.lock().unwrap().insert(
            value,
            PendingFetch {
                blob: reapi::Digest {
                    hash: "cd".repeat(32),
                    size_bytes: 1,
                },
                contents: None,
            },
        );

        let (mut client, server) = UnixStream::pair().expect("socketpair");
        write_request(
            &mut client,
            &Request {
                version: PROTOCOL_VERSION,
                op: OP_BACKED,
                cas_path: cas_path.clone(),
                instance: "tuist/writer".into(),
                payload: key,
            },
        )
        .expect("send");
        proxy.handle(server).expect("handle");
        let (status, _) = read_response(&mut client).expect("recv");

        assert_ne!(
            status, STATUS_HIT,
            "a stale `resolved` entry must never vouch for a local hit"
        );
        assert_eq!(
            status, STATUS_ERROR,
            "with the snapshot silent and the remote unreachable, the only honest verdict is Unknown"
        );
        assert_eq!(
            state.stats_backing_per_key.load(Ordering::Relaxed),
            1,
            "and the remote was actually asked, once"
        );

        std::fs::remove_dir_all(&dir).ok();
    }

    /// One read, one lock, one classification. The three states the handler used
    /// to read separately, plus the age, come back together so a transition
    /// cannot land between them.
    #[test]
    fn a_backing_source_is_classified_from_one_read_of_the_snapshot_state() {
        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            String::new(),
            None,
            None,
        );
        let empty = || {
            Arc::new(Snapshot {
                nodes: Vec::new(),
                node_index: HashMap::new(),
                keys: HashMap::new(),
                key_order: Vec::new(),
                watermark: 0,
            })
        };
        let ready = |full_at: Instant| SnapshotState::Ready {
            snapshot: empty(),
            full_at,
            refreshed_at: Instant::now(),
            last_used: Instant::now(),
        };
        let stale = Instant::now()
            .checked_sub(SNAPSHOT_BACKING_MAX_AGE + Duration::from_secs(60))
            .expect("clock has enough history");

        assert!(
            matches!(proxy.backing_source("never-registered"), BackingSource::Decline),
            "an instance the proxy has never heard of is durably snapshotless"
        );

        proxy.snapshots.lock().unwrap().insert("i".into(), ready(Instant::now()));
        let fresh = proxy.snapshots.lock().unwrap().get("i").map(|s| match s {
            SnapshotState::Ready { snapshot, .. } => snapshot.clone(),
            _ => unreachable!(),
        });
        match proxy.backing_source("i") {
            BackingSource::Snapshot(snapshot) => assert!(
                Arc::ptr_eq(&snapshot, fresh.as_ref().unwrap()),
                "a fresh snapshot answers, and it is THIS one"
            ),
            _ => panic!("a fresh Ready snapshot must answer the check"),
        }

        proxy.snapshots.lock().unwrap().insert("i".into(), ready(stale));
        assert!(
            matches!(proxy.backing_source("i"), BackingSource::PerKey),
            "a snapshot past the backing age is not trusted; the remote is asked"
        );

        proxy.snapshots.lock().unwrap().insert("i".into(), SnapshotState::Fetching);
        assert!(
            matches!(proxy.backing_source("i"), BackingSource::PerKey),
            "mid-fetch is the window the check exists for; it goes per key"
        );

        proxy.snapshots.lock().unwrap().insert(
            "i".into(),
            SnapshotState::Absent {
                checked: Instant::now(),
                retry_after: SNAPSHOT_RETRY_INTERVAL,
            },
        );
        assert!(
            matches!(proxy.backing_source("i"), BackingSource::Decline),
            "durably absent declines rather than paying a round trip per hit"
        );
    }

    /// Two deadlines, one ordering: the proxy must give up on its remote before
    /// the plugin gives up on the proxy, or the slow case ends with a client that
    /// has stopped listening and a handler thread still working for it.
    #[test]
    fn the_proxy_abandons_its_remote_before_the_client_abandons_the_proxy() {
        assert!(BACKED_REMOTE_DEADLINE < crate::proxy_proto::BACKED_READ_TIMEOUT);
    }

    /// A snapshot's `yes` is a claim about the last time its copy of the remote's
    /// keyspace was gated, and only a FULL fetch re-gates it — deltas add and
    /// never remove. So a view kept alive by deltas alone, or one whose refresh
    /// loop stopped (refreshes are held off on loaded machines and during
    /// builds, and CI runners are both), goes on advertising keys the remote has
    /// already evicted. Past the bound the check stops trusting it and falls to
    /// the per-key lookup, which asks the remote now.
    #[test]
    fn a_stale_snapshot_does_not_get_to_answer_the_backing_check() {
        assert!(Proxy::snapshot_may_answer_backing(Some(Duration::from_secs(0))));
        assert!(Proxy::snapshot_may_answer_backing(Some(
            SNAPSHOT_BACKING_MAX_AGE
        )));
        assert!(!Proxy::snapshot_may_answer_backing(Some(
            SNAPSHOT_BACKING_MAX_AGE + Duration::from_secs(1)
        )));
        // No Ready snapshot is not "fresh" — there is nothing to answer from.
        // Whether that declines or falls through to a per-key lookup is decided
        // separately, by how durable the absence is.
        assert!(!Proxy::snapshot_may_answer_backing(None));
        // A scheduled full refresh lands at SNAPSHOT_FULL_INTERVAL, so healthy
        // operation must never trip this. If someone tightens the bound below
        // the cadence, every build starts paying per-key round trips.
        assert!(
            SNAPSHOT_BACKING_MAX_AGE > SNAPSHOT_FULL_INTERVAL,
            "the bound must leave room for the refresh cadence that is supposed to keep it fresh"
        );
    }

    /// The field choice is the whole point, and it is the easy one to get wrong:
    /// age is measured from the last FULL fetch, never the last delta. Deltas
    /// only ADD, so a view refreshed by deltas alone looks continuously fresh
    /// while never re-applying the server's eviction gate.
    #[test]
    fn snapshot_age_is_measured_from_the_full_fetch_not_the_delta() {
        let dir = std::env::temp_dir().join(format!("tuist-snapage-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let registry = dir.join("registry");
        std::fs::write(
            sources_path_for(&registry),
            r#"{"tuist/writer":{"trunk":"main"}}"#,
        )
        .expect("write sources");
        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            String::new(),
            Some(registry),
            None,
        );

        // What a held-off refresh loop leaves behind: deltas kept arriving, the
        // full re-gate did not.
        let stale = Instant::now()
            .checked_sub(SNAPSHOT_BACKING_MAX_AGE + Duration::from_secs(60))
            .expect("clock has enough history");
        proxy.snapshots.lock().unwrap().insert(
            "tuist/writer".to_string(),
            SnapshotState::Ready {
                snapshot: Arc::new(Snapshot {
                    nodes: Vec::new(),
                    node_index: HashMap::new(),
                    keys: HashMap::new(),
                    key_order: Vec::new(),
                    watermark: 0,
                }),
                full_at: stale,
                refreshed_at: Instant::now(),
                last_used: Instant::now(),
            },
        );

        let age = proxy
            .snapshot_full_fetch_age("tuist/writer")
            .expect("a Ready snapshot has an age");
        assert!(
            age > SNAPSHOT_BACKING_MAX_AGE,
            "reading `refreshed_at` instead of `full_at` would have called this fresh"
        );
        assert!(!Proxy::snapshot_may_answer_backing(Some(age)));

        std::fs::remove_dir_all(&dir).ok();
    }

    /// A per-key lookup is authoritative with or without a snapshot, but it is a
    /// network round trip on the build engine's serial task-setup path, so it is
    /// only affordable while the absence is TRANSIENT.
    ///
    /// `Fetching` is seconds and must be covered: the proxy and the build start
    /// together on CI, so the first build's gets land mid-fetch. `Absent` is an
    /// hour for a server with no snapshot support, and `TUIST_CAS_PREFETCH=0`
    /// never registers the instance at all — paying a round trip per served hit
    /// for that long would undo the reason a local hit is worth having, which is
    /// a worse outcome than the hole declining leaves.
    #[test]
    fn a_durably_snapshotless_instance_is_declined_rather_than_looked_up_per_key() {
        use crate::proxy_proto::{read_response, write_request, PROTOCOL_VERSION};

        let dir = std::env::temp_dir().join(format!("tuist-noprefetch-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let registry = dir.join("registry");
        std::fs::write(
            sources_path_for(&registry),
            r#"{"tuist/writer":{"trunk":"main"}}"#,
        )
        .expect("write sources");

        let proxy = Proxy::new(
            "http://127.0.0.1:1".into(),
            crate::token::TokenProvider::from_env(),
            String::new(),
            Some(registry),
            None,
        );
        // What a server with no snapshot support leaves behind. Seeded directly
        // rather than through the environment: `TUIST_CAS_PREFETCH` is process
        // global and cargo runs these as threads, so setting it would race every
        // other test rather than fail honestly.
        proxy.snapshots.lock().unwrap().insert(
            "tuist/writer".to_string(),
            SnapshotState::Absent {
                checked: Instant::now(),
                retry_after: Duration::from_secs(3600),
            },
        );

        let (mut client, server) = UnixStream::pair().expect("socketpair");
        write_request(
            &mut client,
            &Request {
                version: PROTOCOL_VERSION,
                op: OP_BACKED,
                cas_path: "/cas".into(),
                instance: "tuist/writer".into(),
                payload: b"some-action-key".to_vec(),
            },
        )
        .expect("send");
        proxy.handle(server).expect("handle");
        let (status, body) = read_response(&mut client).expect("recv");

        assert_eq!(status, STATUS_ERROR);
        assert_eq!(
            body, b"no snapshot",
            "declined for want of a snapshot, not answered from a per-key round trip"
        );

        std::fs::remove_dir_all(&dir).ok();
    }

    /// The case withholding cannot address: the root is ALREADY on disk, so it
    /// never enters the loop (`missing` filters out whatever `is_local` answers
    /// yes for) and there is nothing to withhold. An earlier pass or a demand
    /// load put it there, and this pass then fails to complete its closure. The
    /// read guard's probe passes and the association is recorded over the hole,
    /// which makes this the shape most worth counting, not the least.
    #[test]
    fn an_incomplete_closure_under_an_already_local_root_is_counted() {
        let dir = TempCasDir::new("root-already-local");
        let state = path_state_for(&dir.path());
        let proxy = test_proxy();
        let remote = proxy.remote_for("tuist/already-local");
        let observed = state.gen_counter.load(Ordering::SeqCst);

        let root = vec![0x31];
        let child = vec![0x32];
        let root_entry = ManifestEntry {
            llcas_digest: root.clone(),
            blob: reapi::Digest { hash: "1a".repeat(32), size_bytes: 4 },
            contents: Some(reapi::compress_frame(&reapi::encode_frame(&[], b"root"))),
        };

        // First pass: the root alone, which lands.
        proxy
            .materialize_manifest(&remote, state, &[root_entry.clone()], observed)
            .expect("materialize");
        assert!(proxy.is_local(state, observed, &root), "the root is on disk now");

        // Second pass over the same key, now with a child that cannot decode.
        let manifest = vec![
            root_entry,
            ManifestEntry {
                llcas_digest: child.clone(),
                blob: reapi::Digest { hash: "1b".repeat(32), size_bytes: 5 },
                contents: Some(b"not a frame".to_vec()),
            },
        ];
        proxy
            .materialize_manifest(&remote, state, &manifest, observed)
            .expect("materialize");

        assert!(!proxy.is_local(state, observed, &child), "the child still did not land");
        assert!(
            proxy.is_local(state, observed, &root),
            "and the root stays present, because this pass never had it to withhold"
        );
        assert_eq!(
            state.stats_incomplete_closures.load(Ordering::Relaxed),
            1,
            "so it must be COUNTED: keying the report off the withhold alone left \
             the one case the read guard cannot catch as the only silent one"
        );
    }

    /// The root can also fail on its own terms, and nothing runs after it: the
    /// withhold decision is made at its turn in the loop, so deciding there left
    /// a corrupt root uncounted and unlogged. Its children landing is exactly
    /// what makes this case distinct, and why it reports a different reason than
    /// a withhold: retrying is pointless until the remote can serve the root.
    #[test]
    fn a_root_that_fails_on_its_own_is_still_reported() {
        let dir = TempCasDir::new("corrupt-root");
        let state = path_state_for(&dir.path());
        let proxy = test_proxy();
        let remote = proxy.remote_for("tuist/corrupt-root");
        let observed = state.gen_counter.load(Ordering::SeqCst);

        // The child is sound and the ROOT is the undecodable one, which is the
        // inverse of the case above.
        let root = vec![0x21];
        let child = vec![0x22];
        let manifest = vec![
            ManifestEntry {
                llcas_digest: root.clone(),
                blob: reapi::Digest { hash: "ee".repeat(32), size_bytes: 4 },
                contents: Some(b"not a frame".to_vec()),
            },
            ManifestEntry {
                llcas_digest: child.clone(),
                blob: reapi::Digest { hash: "ff".repeat(32), size_bytes: 5 },
                contents: Some(reapi::compress_frame(&reapi::encode_frame(&[], b"child"))),
            },
        ];

        proxy
            .materialize_manifest(&remote, state, &manifest, observed)
            .expect("a corrupt root is not an error either, it is the case being handled");

        assert!(proxy.is_local(state, observed, &child), "the child landed");
        assert!(
            !proxy.is_local(state, observed, &root),
            "and the root did not, so no association can be recorded over it"
        );
        assert_eq!(
            state.stats_incomplete_closures.load(Ordering::Relaxed),
            1,
            "the root failing on its own must be counted too: it is the store's \
             most consequential outcome, and deciding this at the root's turn in \
             the loop reported only the case where a CHILD was skipped"
        );
    }

    /// Skipping a node is a designed outcome here, so "root present, child
    /// absent" is reachable without any prune — and invisible to a reader, whose
    /// guard probes the ROOT and nothing deeper. Storing the root last, and only
    /// when the rest of its closure landed, is what makes that probe mean
    /// "complete". Without it this manifest publishes a root over a hole.
    #[test]
    fn an_incomplete_closure_withholds_its_root() {
        let dir = TempCasDir::new("incomplete-closure");
        let state = path_state_for(&dir.path());
        let proxy = test_proxy();
        let remote = proxy.remote_for("tuist/incomplete");
        let observed = state.gen_counter.load(Ordering::SeqCst);

        // Root first, as an ActionResult's output order puts it. Both arrive
        // inlined, so nothing is fetched and the remote is never consulted; the
        // child's bytes are not a frame, which is one of the ways a node is
        // skipped.
        let root = vec![0x01];
        let child = vec![0x02];
        let manifest = vec![
            ManifestEntry {
                llcas_digest: root.clone(),
                blob: reapi::Digest { hash: "aa".repeat(32), size_bytes: 4 },
                contents: Some(reapi::compress_frame(&reapi::encode_frame(&[], b"root"))),
            },
            ManifestEntry {
                llcas_digest: child.clone(),
                blob: reapi::Digest { hash: "bb".repeat(32), size_bytes: 4 },
                contents: Some(b"not a frame".to_vec()),
            },
        ];

        proxy
            .materialize_manifest(&remote, state, &manifest, observed)
            .expect("a skipped node is not an error, it is the case being handled");

        assert!(
            !proxy.is_local(state, observed, &root),
            "the root must NOT be published when a node in its closure was skipped: \
             a later get probes only the root, so storing it here is what turns an \
             incomplete graph into a hit that fails at load on the child"
        );
        assert!(!proxy.is_local(state, observed, &child), "and the child did not land");
        assert_eq!(
            state.stats_incomplete_closures.load(Ordering::Relaxed),
            1,
            "and the condition is counted rather than silent -- it was the silence \
             that let this go undiagnosed"
        );
    }

    /// The other half: withholding must be conditional, or no graph would ever
    /// become locally resolvable and every build would re-resolve every key.
    #[test]
    fn a_complete_closure_publishes_its_root() {
        let dir = TempCasDir::new("complete-closure");
        let state = path_state_for(&dir.path());
        let proxy = test_proxy();
        let remote = proxy.remote_for("tuist/complete");
        let observed = state.gen_counter.load(Ordering::SeqCst);

        let root = vec![0x11];
        let child = vec![0x12];
        let manifest = vec![
            ManifestEntry {
                llcas_digest: root.clone(),
                blob: reapi::Digest { hash: "cc".repeat(32), size_bytes: 4 },
                contents: Some(reapi::compress_frame(&reapi::encode_frame(&[], b"root"))),
            },
            ManifestEntry {
                llcas_digest: child.clone(),
                blob: reapi::Digest { hash: "dd".repeat(32), size_bytes: 5 },
                contents: Some(reapi::compress_frame(&reapi::encode_frame(&[], b"child"))),
            },
        ];

        proxy
            .materialize_manifest(&remote, state, &manifest, observed)
            .expect("materialize");

        assert!(proxy.is_local(state, observed, &child), "the child landed");
        assert!(
            proxy.is_local(state, observed, &root),
            "so the root is published and the key resolves locally next build"
        );
        assert_eq!(state.stats_incomplete_closures.load(Ordering::Relaxed), 0);
    }

    /// Registers fetch instructions the way `commit_and_materialize` does before
    /// it answers, so the tests below drive the production sequence rather than
    /// a materialization with no demand path behind it.
    fn register_instructions(state: &PathState, manifest: &[ManifestEntry]) {
        let mut pending = state.pending_objects.lock().unwrap();
        for entry in manifest {
            pending
                .entry(entry.llcas_digest.clone())
                .or_insert_with(|| PendingFetch {
                    blob: entry.blob.clone(),
                    contents: entry.contents.clone(),
                });
        }
    }

    /// A root and a child whose bytes are not a frame, which is one of the ways
    /// a node is skipped.
    fn incomplete_manifest(root: &[u8], child: &[u8], child_bytes: Vec<u8>) -> Vec<ManifestEntry> {
        vec![
            ManifestEntry {
                llcas_digest: root.to_vec(),
                blob: reapi::Digest { hash: "ee".repeat(32), size_bytes: 4 },
                contents: Some(reapi::compress_frame(&reapi::encode_frame(&[], b"root"))),
            },
            ManifestEntry {
                llcas_digest: child.to_vec(),
                blob: reapi::Digest { hash: "ff".repeat(32), size_bytes: 5 },
                contents: Some(child_bytes),
            },
        ]
    }

    /// Withholding the root in the materializer is only half a guard: the
    /// compiler was already handed the value id, and its demand load asks for
    /// that exact root. The instruction is still registered WITH its inlined
    /// bytes (a skipped node keeps them), so before this guard the demand load
    /// decoded them and put the root back standalone -- over the same hole the
    /// materializer had just refused to publish over.
    ///
    /// That is what makes the state permanent rather than transient: the next
    /// build's root probe passes, the association is recorded, and the ABI has
    /// no delete and refuses a differing re-put.
    #[test]
    fn a_withheld_root_is_not_put_back_by_a_demand_load() {
        let dir = TempCasDir::new("withheld-root-demand");
        let state = path_state_for(&dir.path());
        let proxy = test_proxy();
        let remote = proxy.remote_for("tuist/withheld");
        let observed = state.gen_counter.load(Ordering::SeqCst);

        let root = vec![0x21];
        let child = vec![0x22];
        let manifest = incomplete_manifest(&root, &child, b"not a frame".to_vec());
        register_instructions(state, &manifest);
        proxy
            .materialize_manifest(&remote, state, &manifest, observed)
            .expect("a skipped node is the case being handled, not an error");
        assert!(
            !proxy.is_local(state, observed, &root),
            "precondition: the root was withheld"
        );

        let produced = proxy
            .fetch_object(state, &dir.path(), "", &root)
            .expect("a declined fetch is an answer, not an error");

        assert!(
            !produced,
            "a demand load must not produce a root whose closure is still \
             incomplete: storing it here is what makes the hole permanent"
        );
        assert!(
            !proxy.is_local(state, observed, &root),
            "and nothing was written, so the next build's root probe still fails \
             and the association is still not recorded"
        );
        assert_eq!(
            state.stats_withheld_roots_refused.load(Ordering::Relaxed),
            1
        );
    }

    /// The other half, or the guard would turn a recoverable graph into a
    /// permanent miss. The nodes that did not land kept their instructions, so
    /// the demand load repairs exactly those and then produces the root. This is
    /// the per-object repair the materializer's comment promises, narrowed to
    /// the nodes actually owed instead of a transitive walk.
    #[test]
    fn a_withheld_root_is_produced_once_its_closure_is_completed() {
        let dir = TempCasDir::new("withheld-root-repair");
        let state = path_state_for(&dir.path());
        let proxy = test_proxy();
        let remote = proxy.remote_for("tuist/withheld-repair");
        let observed = state.gen_counter.load(Ordering::SeqCst);

        let root = vec![0x31];
        let child = vec![0x32];
        let manifest = incomplete_manifest(&root, &child, b"not a frame".to_vec());
        register_instructions(state, &manifest);
        proxy
            .materialize_manifest(&remote, state, &manifest, observed)
            .expect("materialize");
        assert!(
            !proxy.is_local(state, observed, &root),
            "precondition: withheld"
        );

        // The writer finished uploading, or the blob was declined under a
        // momentary memory limit and is serveable now.
        state
            .pending_objects
            .lock()
            .unwrap()
            .insert(
                child.clone(),
                PendingFetch {
                    blob: reapi::Digest { hash: "ff".repeat(32), size_bytes: 5 },
                    contents: Some(reapi::compress_frame(&reapi::encode_frame(&[], b"child"))),
                },
            );

        let produced = proxy
            .fetch_object(state, &dir.path(), "", &root)
            .expect("fetch");

        assert!(
            produced,
            "the closure is whole now, so the root is safe to produce"
        );
        // Two objects went in, the owed node first and the root only after it:
        // counted rather than probed because `is_local` answers from the
        // known-local marks, which only `materialize_manifest` writes, and these
        // digests are fixtures rather than real content addresses.
        assert_eq!(
            state.stats_demand_fetched.load(Ordering::Relaxed),
            2,
            "the owed node was produced, and then the root"
        );
        assert_eq!(
            state.stats_withheld_roots_repaired.load(Ordering::Relaxed),
            1
        );
        assert_eq!(
            state.stats_withheld_roots_refused.load(Ordering::Relaxed),
            0
        );
        assert!(
            !state.withheld_roots.lock().unwrap().contains_key(&root),
            "and the record is dropped, so later loads take the plain path"
        );
    }

    /// A materialization that completes what an earlier one could not must drop
    /// the record, or the root stays unproducible on demand for the life of the
    /// proxy even though its closure is whole on disk.
    #[test]
    fn a_completed_closure_clears_an_earlier_withhold() {
        let dir = TempCasDir::new("withheld-root-cleared");
        let state = path_state_for(&dir.path());
        let proxy = test_proxy();
        let remote = proxy.remote_for("tuist/withheld-cleared");
        let observed = state.gen_counter.load(Ordering::SeqCst);

        let root = vec![0x41];
        let child = vec![0x42];
        let broken = incomplete_manifest(&root, &child, b"not a frame".to_vec());
        register_instructions(state, &broken);
        proxy
            .materialize_manifest(&remote, state, &broken, observed)
            .expect("materialize");
        assert!(
            state.withheld_roots.lock().unwrap().contains_key(&root),
            "precondition: the withhold was recorded"
        );

        let whole = incomplete_manifest(
            &root,
            &child,
            reapi::compress_frame(&reapi::encode_frame(&[], b"child")),
        );
        proxy
            .materialize_manifest(&remote, state, &whole, observed)
            .expect("materialize");

        assert!(
            proxy.is_local(state, observed, &root),
            "the second pass published the root"
        );
        assert!(
            !state.withheld_roots.lock().unwrap().contains_key(&root),
            "so the record must go with it"
        );
    }

    /// The repair has the whole owed list up front, so it must ask for it in one
    /// batch. `demand_fetch` coalesces only with requests already in flight from
    /// OTHER threads, so a serial loop never coalesces with itself and each child
    /// became its own `BatchReadBlobs`. `materialize_manifest` argues against
    /// exactly that fragmentation, with a measurement behind it.
    ///
    /// This covers WHICH nodes go into that batch. Everything left out is left to
    /// the per-child path, which can do things this step must not: recurse into a
    /// nested withheld root, and wait on a snapshot.
    #[test]
    fn a_repair_batches_only_the_owed_nodes_whose_bytes_it_lacks() {
        let on_disk = vec![0xA1];
        let inlined = vec![0xA2];
        let digest_only = vec![0xA3];
        let no_instruction = vec![0xA4];
        let from_publish_cache = vec![0xA5];
        let owed = vec![
            on_disk.clone(),
            inlined.clone(),
            digest_only.clone(),
            no_instruction.clone(),
            from_publish_cache.clone(),
        ];
        let blob_for = |tag: u8| reapi::Digest { hash: format!("{tag:02x}").repeat(32), size_bytes: 4 };

        let wanted = owed_needing_fetch(
            &owed,
            |child| child == on_disk.as_slice(),
            // Every one of these except `no_instruction` names a blob, including
            // the inlined one and the one already on disk. Only the flag and the
            // presence check may exclude them, or the test proves nothing about
            // either.
            |child| match child {
                c if c == on_disk.as_slice() => Some((blob_for(0xA1), false)),
                c if c == inlined.as_slice() => Some((blob_for(0xA2), true)),
                c if c == digest_only.as_slice() => Some((blob_for(0xA3), false)),
                c if c == from_publish_cache.as_slice() => Some((blob_for(0xA5), false)),
                _ => None,
            },
        );

        let requested: Vec<Vec<u8>> = wanted.iter().map(|(child, _)| child.clone()).collect();
        assert_eq!(
            requested,
            vec![digest_only, from_publish_cache],
            "one request carrying every owed node that needs bytes, and nothing \
             that already has them or that only the per-child path can resolve"
        );
    }

    /// The guard must be at least as durable as the instruction that makes the
    /// hazard possible. `invalidate` deliberately RETAINS `pending_objects`
    /// (content-addressed, valid for any incarnation of the store), so clearing
    /// the withhold beside it would leave a wipe or a prune signal with an
    /// instruction that produces the root and nothing saying it must not.
    #[test]
    fn a_wipe_keeps_the_withheld_roots() {
        let dir = TempCasDir::new("withheld-root-invalidate");
        let state = path_state_for(&dir.path());
        let root = vec![0x51];
        state
            .withheld_roots
            .lock()
            .unwrap()
            .insert(root.clone(), vec![vec![0x52]]);
        state.pending_objects.lock().unwrap().insert(
            root.clone(),
            PendingFetch {
                blob: reapi::Digest { hash: "51".repeat(32), size_bytes: 4 },
                contents: None,
            },
        );

        state.invalidate();

        assert!(
            state.pending_objects.lock().unwrap().contains_key(&root),
            "precondition: the instruction survives invalidation by design"
        );
        assert!(
            state.withheld_roots.lock().unwrap().contains_key(&root),
            "so the withhold must survive it too -- the claim is about what the \
             REMOTE could not produce, which no local wipe changes"
        );
    }

    /// The bound has the same requirement as `invalidate`, and cannot meet it by
    /// dropping the record alone.
    #[test]
    fn dropping_a_withheld_root_on_overflow_drops_its_instruction_too() {
        let dir = TempCasDir::new("withheld-root-overflow");
        let state = path_state_for(&dir.path());
        let root = vec![0x61];
        let other = vec![0x62];
        state
            .withheld_roots
            .lock()
            .unwrap()
            .insert(root.clone(), vec![vec![0x63]]);
        for digest in [&root, &other] {
            state.pending_objects.lock().unwrap().insert(
                digest.clone(),
                PendingFetch {
                    blob: reapi::Digest { hash: "61".repeat(32), size_bytes: 4 },
                    contents: None,
                },
            );
        }

        state.enforce_withheld_bound(0);

        assert!(state.withheld_roots.lock().unwrap().is_empty(), "the bound was enforced");
        assert!(
            !state.pending_objects.lock().unwrap().contains_key(&root),
            "and the instruction went with it: keeping one without the other is \
             the pre-fix bug, not a smaller version of it"
        );
        assert!(
            state.pending_objects.lock().unwrap().contains_key(&other),
            "while an instruction that was never withheld is untouched"
        );
    }

    /// The pairing has to survive a concurrent recorder, not just a quiet map.
    ///
    /// The earlier version snapshotted the keys, released the lock to clean
    /// `pending_objects`, then re-locked and cleared. A withhold recorded in that
    /// gap was dropped by the clear with its instruction untouched, because it was
    /// never in the snapshot. That is the one state the bound exists to prevent,
    /// and the regime that fills the map is the same regime the materializer pool
    /// is writing to it hardest, so the two coincide.
    ///
    /// Production order is instruction first, then record (`commit_and_materialize`
    /// registers instructions, `materialize_manifest` records the withhold), which
    /// is also the order that exposes the window.
    #[test]
    fn enforcing_the_withheld_bound_never_strands_an_instruction() {
        let dir = TempCasDir::new("withheld-bound-race");
        let state = path_state_for(&dir.path());
        let root_at = |index: u32| {
            let mut digest = vec![0xC0];
            digest.extend_from_slice(&index.to_le_bytes());
            digest
        };
        let instruction = || PendingFetch {
            blob: reapi::Digest { hash: "c0".repeat(32), size_bytes: 4 },
            contents: None,
        };
        // Enough resident entries that removing their instructions takes real
        // time, which is what made the old window wide enough to hit.
        const RESIDENT: u32 = 2_000;
        const RACING: u32 = 2_000;
        for index in 0..RESIDENT {
            let root = root_at(index);
            state.pending_objects.lock().unwrap().insert(root.clone(), instruction());
            state.withheld_roots.lock().unwrap().insert(root, vec![vec![0xC1]]);
        }

        let recorder = std::thread::spawn(move || {
            for index in RESIDENT..RESIDENT + RACING {
                let root = root_at(index);
                state.pending_objects.lock().unwrap().insert(root.clone(), instruction());
                state.withheld_roots.lock().unwrap().insert(root, vec![vec![0xC1]]);
            }
        });
        while !recorder.is_finished() {
            state.enforce_withheld_bound(0);
        }
        recorder.join().expect("recorder");
        state.enforce_withheld_bound(0);

        // Every root is either fully recorded (record AND instruction) or fully
        // dropped (neither). The forbidden state is an instruction with no record
        // saying its root must not be produced.
        let withheld = state.withheld_roots.lock().unwrap();
        let pending = state.pending_objects.lock().unwrap();
        let stranded: Vec<u32> = (0..RESIDENT + RACING)
            .filter(|index| {
                let root = root_at(*index);
                pending.contains_key(&root) && !withheld.contains_key(&root)
            })
            .collect();
        assert!(
            stranded.is_empty(),
            "{} root(s) kept an instruction after their withhold was dropped, so a \
             demand load could put them back over their own hole: first few {:?}",
            stranded.len(),
            &stranded[..stranded.len().min(5)]
        );
    }

    /// Materialization can fail before it ever reaches its own bookkeeping: the
    /// batch read and every `store_node` are `?`-returns, and by then
    /// `commit_and_materialize` has already registered this root's instruction
    /// WITH its inlined bytes. Recording the withhold only at the end therefore
    /// left every error path exactly as exposed as before the guard existed.
    #[test]
    fn a_materialization_that_fails_still_withholds_its_root() {
        let dir = TempCasDir::new("withheld-root-error");
        let state = path_state_for(&dir.path());
        let proxy = test_proxy();
        // Nothing is listening on this endpoint, so the batch read fails.
        let remote = proxy.remote_for("tuist/failing");
        let observed = state.gen_counter.load(Ordering::SeqCst);

        let root = vec![0x71];
        let child = vec![0x72];
        let manifest = vec![
            ManifestEntry {
                llcas_digest: root.clone(),
                blob: reapi::Digest { hash: "71".repeat(32), size_bytes: 4 },
                contents: Some(reapi::compress_frame(&reapi::encode_frame(&[], b"root"))),
            },
            // Not inlined, so this pass must go to the remote for it.
            ManifestEntry {
                llcas_digest: child.clone(),
                blob: reapi::Digest { hash: "72".repeat(32), size_bytes: 5 },
                contents: None,
            },
        ];
        register_instructions(state, &manifest);

        let outcome = proxy.materialize_manifest(&remote, state, &manifest, observed);

        assert!(outcome.is_err(), "precondition: the pass failed rather than skipping");
        assert!(
            state.withheld_roots.lock().unwrap().contains_key(&root),
            "the withhold must already be in place when the pass errors out"
        );
        assert!(
            !proxy
                .fetch_object(state, &dir.path(), "", &root)
                .expect("a declined fetch is an answer"),
            "so the demand load that follows still cannot put the root back"
        );
    }

    /// A digest is an interior node of one value graph and the ROOT of another
    /// whenever two actions share an output. Repairing the first root walks into
    /// the second, and producing that one unguarded stores it over its own hole,
    /// poisoning an association this fetch was never about.
    #[test]
    fn a_repair_does_not_produce_a_nested_withheld_root() {
        let dir = TempCasDir::new("withheld-root-nested");
        let state = path_state_for(&dir.path());
        let proxy = test_proxy();

        // outer owes inner; inner is itself a withheld root owing a node that
        // nothing can produce.
        let outer = vec![0x81];
        let inner = vec![0x82];
        let unobtainable = vec![0x83];
        {
            let mut withheld = state.withheld_roots.lock().unwrap();
            withheld.insert(outer.clone(), vec![inner.clone()]);
            withheld.insert(inner.clone(), vec![unobtainable.clone()]);
        }
        // Both roots have usable inlined instructions, so only the guard stands
        // between them and the store.
        for digest in [&outer, &inner] {
            state.pending_objects.lock().unwrap().insert(
                digest.clone(),
                PendingFetch {
                    blob: reapi::Digest { hash: "81".repeat(32), size_bytes: 4 },
                    contents: Some(reapi::compress_frame(&reapi::encode_frame(&[], b"node"))),
                },
            );
        }

        let produced = proxy
            .fetch_object(state, &dir.path(), "", &outer)
            .expect("a declined fetch is an answer");

        assert!(!produced, "the outer root is still owed a closure it cannot get");
        assert!(
            state.withheld_roots.lock().unwrap().contains_key(&inner),
            "and the nested root was NOT produced on the way: its own hole is \
             still open, so its own association must stay unbacked"
        );
        assert_eq!(
            state.stats_demand_fetched.load(Ordering::Relaxed),
            0,
            "nothing was stored at any level"
        );
    }

    /// The stack that breaks a cycle also bounds depth. Unproven withholds, so a
    /// record that points back at itself refuses rather than recursing.
    #[test]
    fn a_withheld_root_that_owes_itself_refuses_instead_of_recursing() {
        let dir = TempCasDir::new("withheld-root-cycle");
        let state = path_state_for(&dir.path());
        let proxy = test_proxy();

        let root = vec![0x91];
        state
            .withheld_roots
            .lock()
            .unwrap()
            .insert(root.clone(), vec![root.clone()]);
        state.pending_objects.lock().unwrap().insert(
            root.clone(),
            PendingFetch {
                blob: reapi::Digest { hash: "91".repeat(32), size_bytes: 4 },
                contents: Some(reapi::compress_frame(&reapi::encode_frame(&[], b"node"))),
            },
        );

        let produced = proxy
            .fetch_object(state, &dir.path(), "", &root)
            .expect("a declined fetch is an answer");

        assert!(!produced, "a closure that cannot be proven whole is withheld");
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
