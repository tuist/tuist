//! Characterization, not a regression guard: what the on-disk CAS keeps across a
//! generation rotation as a function of how the association was READ, and what
//! each way of asking costs.
//!
//! The question is whether "keep what was recently looked up" can carry a value
//! graph forward, and at what depth, because `AGENTS.md` ("Per-key overhead")
//! commits the hot paths to `llcas_cas_contains_object` and rules out a graph
//! walk on cost grounds. Neither the retention behaviour nor the cost had been
//! measured; both are measured here.
//!
//! What these establish, on Xcode 26.5:
//!
//! - A read that only PROBES renews the association and nothing else, so the
//!   next collection strands it. The read guard is therefore an author of the
//!   dangling state it exists to catch.
//! - A single LOAD of the root carries the whole closure forward. The refs do
//!   not have to be walked to retain them.
//! - Retention is all-or-nothing, so a rotation alone can strand an association
//!   at its ROOT but never at an interior node. The interior shape needs a
//!   writer that stores a root over an absent child, which is what
//!   `Proxy::fetch_object` does on a demand load.
//! - Retaining a graph is not free, and most of the cost is not in the read. A
//!   fault-in is written out when the handle is DISPOSED, so the post-rotation
//!   figures report read and dispose separately and both count. Steady state has
//!   nothing to fault in, and its dispose is measured to show that.
//!
//! These drive Apple's `libToolchainCASPlugin` DIRECTLY rather than this crate's
//! exported surface, so every answer is the store's own: no read guard rewriting
//! SUCCESS to NOTFOUND, no missing-filter, no proxy.
//!
//! All four are `#[ignore]`d measurements. Run them with:
//!
//! ```sh
//! cargo test --manifest-path cas-plugin/Cargo.toml --release \
//!   --test graph_retention -- --ignored --nocapture --test-threads=1
//! ```
//!
//! `--release` and `--test-threads=1` are both load-bearing for the timings: the
//! survival table is exact either way, but the per-operation figures are tens of
//! nanoseconds and four tests sharing a disk skew the post-rotation ones.

use std::ffi::{c_char, c_void, CStr, CString};
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use tuist_cas_plugin::types::*;
use tuist_cas_plugin::upstream::Upstream;
use tuist_cas_plugin::upstream_path;

/// Shaped like a swift compilation's value graph rather than a toy: a root whose
/// refs are the outputs, each of which references its own content chunks. 1 + 8 +
/// 8 * 4 = 41 nodes, which is the order a real `SwiftCachingKeyMaterializer` value
/// carries.
const FANOUT: usize = 8;
const CHUNKS_PER_OUTPUT: usize = 4;
/// Big enough that the graph is worth faulting in and the store crosses a small
/// size limit, small enough that 41 of them stay quick.
const CHUNK_BYTES: usize = 24 * 1024;

// --- What a read renews --------------------------------------------------------

/// The table this whole investigation turns on. For each way of reading an
/// association, what survives a rotation plus a collection.
#[test]
#[ignore = "a measurement, not an assertion"]
fn what_a_read_carries_across_a_rotation() {
    let Some(upstream) = upstream() else { return };

    println!();
    println!("graph: 1 root + {FANOUT} outputs + {} chunks", FANOUT * CHUNKS_PER_OUTPUT);
    println!();
    println!(
        "{:<22} {:>10} {:>10} {:>12} {:>14}",
        "read before rotation", "assoc", "root", "outputs", "chunks"
    );
    println!("{}", "-".repeat(72));

    for arm in Arm::ALL {
        let survival = measure_survival(upstream, arm);
        println!(
            "{:<22} {:>10} {:>10} {:>12} {:>14}",
            arm.label(),
            yes_no(survival.association),
            yes_no(survival.root_loads),
            format!("{}/{}", survival.outputs_load, FANOUT),
            format!("{}/{}", survival.chunks_load, FANOUT * CHUNKS_PER_OUTPUT),
        );
    }

    println!();
    println!("assoc   = the key still resolves to its value id");
    println!("root    = llcas_cas_load_object on the value root succeeds");
    println!("outputs = direct refs of the root that load");
    println!("chunks  = second-level refs that load");
    println!();
}

/// The disagreement that matters, asked of ONE handle on ONE store state: root
/// depth says the value is here, closure depth says it is not.
///
/// The earlier version of this test compared a probe taken BEFORE a collection
/// with a load taken after, which is two different states and no disagreement at
/// all (after a collection both answer NOTFOUND, as
/// `what_a_read_carries_across_a_rotation`'s `probe root` row shows). The real
/// disagreement is not probe versus load. Both are root depth and both say
/// SUCCESS here. It is root depth versus closure depth, which is why deepening
/// the read guard from `contains(root)` to `load(root)` would not catch the
/// production failure.
#[test]
#[ignore = "a measurement, not an assertion"]
fn root_depth_and_closure_depth_disagree_on_the_same_store() {
    let Some(upstream) = upstream() else { return };
    let dir = TempDir::new("depth-disagreement");
    let graph = seed(upstream, dir.path());

    // Strand the interior: re-store the root on its own into the live generation,
    // the way `Proxy::fetch_object` does when a demand load asks for a root the
    // materializer withheld, then let the generation holding its children go.
    rotate(upstream, dir.path());
    let store = Store::open(upstream, dir.path());
    // Renews the association, exactly as a build's lookup does. Without it the
    // association is collected too and the state under test is a plain miss
    // rather than the production shape.
    let _ = store.ac_get(&graph.key);
    let output_ids: Vec<_> =
        graph.outputs.iter().map(|digest| store.objectid_for(digest)).collect();
    let restored = store.store_object(&graph.root_data, &output_ids);
    assert_eq!(
        store.digest_of(restored),
        graph.root,
        "re-storing the same bytes and refs must mint the same digest"
    );
    store.close();
    rotate(upstream, dir.path());
    collect(upstream, dir.path());

    // Every question below is asked of the same handle on the same state.
    let store = Store::open(upstream, dir.path());
    let root = store.objectid_for(&graph.root);
    println!();
    println!("one store, one handle, an interior node stranded:");
    println!("  ac_get(key)                      : {}", name(store.ac_get(&graph.key).0));
    println!("  contains(root)  [guard today]    : {}", name(store.contains(root)));
    println!("  load(root)      [root depth]     : {}", name(store.load(root).0));
    println!(
        "  outputs that load                : {}/{FANOUT}",
        count_loadable(&store, &graph.outputs)
    );
    println!(
        "  closure loads completely         : {}",
        yes_no(store.load_closure(root))
    );
    println!();
    println!("  root depth cannot distinguish this from a healthy entry;");
    println!("  closure depth is the shallowest that can.");
    println!();
    store.close();
}

// --- What each way of asking costs ---------------------------------------------

/// The number that decides whether the guard can be deepened. A probe is the
/// current cost; the alternative has to be paid on swift-build's serial
/// task-setup path, once per served hit.
///
/// Two regimes, and only the second is interesting. In steady state a load is a
/// probe plus a pointer; the cost that matters is the FIRST load after a
/// rotation, which is where `FullTree` copies the graph forward. That is real
/// work, but it is the same work the store would do lazily anyway, and it is paid
/// once per rotation rather than once per build.
#[test]
#[ignore = "a measurement, not an assertion"]
fn what_each_depth_costs() {
    let Some(upstream) = upstream() else { return };

    // --- Steady state, warm store ---
    let dir = TempDir::new("depth-cost");
    let graph = seed(upstream, dir.path());
    let store = Store::open(upstream, dir.path());
    let root = store.objectid_for(&graph.root);

    const ITERATIONS: u32 = 200_000;
    for _ in 0..2_000 {
        let _ = store.contains(root);
        let _ = store.load(root);
    }
    // Best of five: these are tens of nanoseconds, where a single scheduler blip
    // is larger than the difference being measured.
    let probe = best_of(5, || time(ITERATIONS, || { let _ = store.contains(root); }));
    let load_root = best_of(5, || time(ITERATIONS, || { let _ = store.load(root); }));
    let walk = best_of(5, || {
        time(ITERATIONS / 100, || {
            let _ = store.load_closure(root);
        })
    });
    // The same blind spot the post-rotation figures below had: a fault-in is
    // written out on dispose. Measured here to show there is nothing to fault in
    // when no rotation happened, so these per-operation numbers stand alone.
    let disposing = Instant::now();
    store.close();
    let steady_dispose = disposing.elapsed();

    println!();
    println!("STEADY STATE (warm store, no rotation), per operation");
    println!("  contains(root)                {probe:>12?}");
    println!("  load(root)                    {load_root:>12?}");
    println!("  load closure ({:>2} nodes)       {walk:>12?}", graph.node_count());
    println!();
    println!("  extrapolated to a 13,500-key warm build:");
    println!("    contains(root)              {:>12?}", probe * 13_500);
    println!("    load(root)                  {:>12?}", load_root * 13_500);
    println!("    load closure                {:>12?}", walk * 13_500);
    println!();
    println!("  dispose after all of the above  {steady_dispose:>12?}  (nothing was faulted in)");

    // --- First build after a rotation ---
    // Many keys rather than one: the question is what a whole build pays, and a
    // single graph cannot show whether the copy amortizes.
    const KEYS: usize = 250;
    const COLD_CHUNK_BYTES: usize = 4 * 1024;

    // Filesystem work in a temp directory, so a single sample is worth little:
    // repeat each depth on fresh stores and keep the median.
    const REPEATS: usize = 3;
    let mut totals = Vec::new();
    for (label, depth) in [
        ("probe every root", Depth::Probe),
        ("load every root", Depth::Root),
        ("walk every closure", Depth::Closure),
    ] {
        let mut reads = Vec::new();
        let mut disposes = Vec::new();
        let mut totals_combined = Vec::new();
        let mut intact = 0;
        for _ in 0..REPEATS {
            let (read, dispose, survived) = cold_pass(upstream, KEYS, COLD_CHUNK_BYTES, depth);
            reads.push(read);
            disposes.push(dispose);
            totals_combined.push(read + dispose);
            intact = survived;
        }
        reads.sort();
        disposes.sort();
        totals_combined.sort();
        totals.push((
            label,
            reads[REPEATS / 2],
            disposes[REPEATS / 2],
            totals_combined[REPEATS / 2],
            intact,
        ));
    }

    println!();
    println!(
        "FIRST BUILD AFTER A ROTATION ({KEYS} keys, {} nodes each, {} KiB chunks, median of {REPEATS})",
        1 + FANOUT + FANOUT * CHUNKS_PER_OUTPUT,
        COLD_CHUNK_BYTES / 1024
    );
    println!(
        "  {:<18} {:>12} {:>12} {:>12} {:>12}  {}",
        "", "read", "dispose", "read+dispose", "per key", "graphs intact"
    );
    for (label, read, dispose, combined, intact) in &totals {
        println!(
            "  {label:<18} {:>12?} {:>12?} {:>12?} {:>12?}  {intact}/{KEYS}",
            read,
            dispose,
            combined,
            *combined / KEYS as u32
        );
    }
    println!();
}

/// One "first build after a rotation": seed `keys` graphs, rotate so they are all
/// in the demoted generation, read every association at `depth`, then rotate and
/// collect and count how many graphs are still whole.
///
/// Returns the READ time and the DISPOSE time separately, and both are part of
/// the cost. A fault-in is not finished when the load returns: the copied nodes
/// are written out when the handle is disposed, so timing only the read loop
/// attributes none of the retention work to the depth that caused it. Disposal
/// is on the build's critical path in production too, since the build service
/// disposes its CAS handle before the build is done.
fn cold_pass(
    upstream: &'static Upstream,
    keys: usize,
    chunk_bytes: usize,
    depth: Depth,
) -> (Duration, Duration, usize) {
    let dir = TempDir::new("cold-cost");
    let graphs = seed_many(upstream, dir.path(), keys, chunk_bytes);
    rotate(upstream, dir.path());

    let store = Store::open(upstream, dir.path());
    let started = Instant::now();
    for graph in &graphs {
        let (result, value) = store.ac_get(&graph.key);
        if result != LLCAS_LOOKUP_RESULT_SUCCESS {
            continue;
        }
        match depth {
            Depth::Probe => {
                let _ = store.contains(value);
            }
            Depth::Root => {
                let _ = store.load(value);
            }
            Depth::Closure => {
                    let _ = store.load_closure(value);
                }
        }
    }
    let read = started.elapsed();
    let disposing = Instant::now();
    store.close();
    let dispose = disposing.elapsed();

    rotate(upstream, dir.path());
    collect(upstream, dir.path());
    let store = Store::open(upstream, dir.path());
    let intact = graphs
        .iter()
        .filter(|graph| {
            let root = store.objectid_for(&graph.root);
            store.load(root).0 == LLCAS_LOOKUP_RESULT_SUCCESS
                && count_loadable(&store, &graph.outputs) == FANOUT
                && count_loadable(&store, &graph.chunks) == FANOUT * CHUNKS_PER_OUTPUT
        })
        .count();
    store.close();
    (read, dispose, intact)
}

/// How deep a served hit is verified.
#[derive(Clone, Copy)]
enum Depth {
    /// `llcas_cas_contains_object` on the root: what ships today.
    Probe,
    /// `llcas_cas_load_object` on the root.
    Root,
    /// Every node reachable from the root.
    Closure,
}

/// Repeats a timing and keeps the best sample. At tens of nanoseconds per
/// operation the noise floor is wider than the effect.
fn best_of(samples: u32, mut body: impl FnMut() -> Duration) -> Duration {
    (0..samples).map(|_| body()).min().expect("at least one sample")
}

// --- The measurement ------------------------------------------------------------

#[derive(Clone, Copy)]
enum Arm {
    /// The association is never touched between rotations. The control.
    NoRead,
    /// `llcas_actioncache_get_for_digest` and nothing else: the get-without-load
    /// shape issue 12245's correction called a real but unproven sequence.
    GetOnly,
    /// What `verified_local_get` does today.
    ProbeRoot,
    /// The cheapest deepening on the table.
    LoadRoot,
    /// What a materializing compiler does, and the upper bound on cost.
    LoadClosure,
    /// Not a read at all: the root re-stored on its own into the live
    /// generation, which is what `Proxy::fetch_object` does when a demand load
    /// asks for a root the materializer withheld (`AGENTS.md`, "Materialization
    /// publishes a value graph's ROOT last"). Included because it is the only
    /// sequence here that can leave a root present over an absent child, and that
    /// is the shape production actually fails on.
    RestoreRootStandalone,
}

impl Arm {
    const ALL: [Arm; 6] = [
        Arm::NoRead,
        Arm::GetOnly,
        Arm::ProbeRoot,
        Arm::LoadRoot,
        Arm::LoadClosure,
        Arm::RestoreRootStandalone,
    ];

    fn label(self) -> &'static str {
        match self {
            Arm::NoRead => "none",
            Arm::GetOnly => "ac_get only",
            Arm::ProbeRoot => "probe root (today)",
            Arm::LoadRoot => "load root",
            Arm::LoadClosure => "load closure",
            Arm::RestoreRootStandalone => "re-store root alone",
        }
    }
}

struct Survival {
    association: bool,
    root_loads: bool,
    outputs_load: usize,
    chunks_load: usize,
}

fn measure_survival(upstream: &'static Upstream, arm: Arm) -> Survival {
    let dir = TempDir::new("survival");
    let graph = seed(upstream, dir.path());

    // The graph is now in the oldest generation. One rotation demotes it to
    // upstream, where it is still readable and where a fault-in can still copy it
    // forward; the second orphans it. The arm's read goes in between, which is
    // the only window that decides what survives.
    rotate(upstream, dir.path());

    let store = Store::open(upstream, dir.path());
    let root = store.objectid_for(&graph.root);
    match arm {
        Arm::NoRead => {}
        Arm::GetOnly => {
            let _ = store.ac_get(&graph.key);
        }
        Arm::ProbeRoot => {
            let _ = store.ac_get(&graph.key);
            let _ = store.contains(root);
        }
        Arm::LoadRoot => {
            let _ = store.ac_get(&graph.key);
            let _ = store.load(root);
        }
        Arm::LoadClosure => {
            let _ = store.ac_get(&graph.key);
            let _ = store.load_closure(root);
        }
        Arm::RestoreRootStandalone => {
            let _ = store.ac_get(&graph.key);
            let output_ids: Vec<_> =
                graph.outputs.iter().map(|digest| store.objectid_for(digest)).collect();
            let restored = store.store_object(&graph.root_data, &output_ids);
            assert_eq!(
                store.digest_of(restored),
                graph.root,
                "re-storing the same bytes and refs must mint the same digest"
            );
        }
    }
    store.close();

    rotate(upstream, dir.path());
    collect(upstream, dir.path());

    // Observed through a handle opened after the collection: an open handle keeps
    // the deleted generation's inodes alive and would answer out of them.
    let store = Store::open(upstream, dir.path());
    let (association, _) = store.ac_get(&graph.key);
    let root = store.objectid_for(&graph.root);
    let survival = Survival {
        association: association == LLCAS_LOOKUP_RESULT_SUCCESS,
        root_loads: store.load(root).0 == LLCAS_LOOKUP_RESULT_SUCCESS,
        outputs_load: count_loadable(&store, &graph.outputs),
        chunks_load: count_loadable(&store, &graph.chunks),
    };
    store.close();
    survival
}

fn count_loadable(store: &Store, digests: &[Vec<u8>]) -> usize {
    digests
        .iter()
        .filter(|digest| store.load(store.objectid_for(digest)).0 == LLCAS_LOOKUP_RESULT_SUCCESS)
        .count()
}

/// Writes the graph and its association into a fresh store, then closes it.
fn seed(upstream: &'static Upstream, path: &Path) -> Graph {
    let store = Store::open(upstream, path);
    let graph = write_graph(&store, 0, CHUNK_BYTES);
    store.close();
    graph
}

/// `count` distinct graphs and associations in one store, which is the shape a
/// build's key set has: many independent value graphs behind many keys.
fn seed_many(
    upstream: &'static Upstream,
    path: &Path,
    count: usize,
    chunk_bytes: usize,
) -> Vec<Graph> {
    let store = Store::open(upstream, path);
    let graphs = (0..count).map(|salt| write_graph(&store, salt, chunk_bytes)).collect();
    store.close();
    graphs
}

/// One value graph plus the association naming it. `salt` keeps graphs distinct,
/// since content addressing would otherwise fold them into one.
fn write_graph(store: &Store, salt: usize, chunk_bytes: usize) -> Graph {
    let mut outputs = Vec::new();
    let mut chunks = Vec::new();
    let mut output_ids = Vec::new();
    for output in 0..FANOUT {
        let mut chunk_ids = Vec::new();
        for chunk in 0..CHUNKS_PER_OUTPUT {
            let mut data = vec![0u8; chunk_bytes];
            // Distinct content per chunk and per graph, so nothing dedupes into
            // one object and the store really holds `count` separate graphs.
            let stamp = format!("{salt}-{output}-{chunk}");
            data[..stamp.len()].copy_from_slice(stamp.as_bytes());
            let id = store.store_object(&data, &[]);
            chunks.push(store.digest_of(id));
            chunk_ids.push(id);
        }
        let id = store.store_object(format!("output-{salt}-{output}").as_bytes(), &chunk_ids);
        outputs.push(store.digest_of(id));
        output_ids.push(id);
    }
    let root_data = format!("value-root-{salt}").into_bytes();
    let root_id = store.store_object(&root_data, &output_ids);
    let root = store.digest_of(root_id);

    // The key is formed the way a real one is: the digest of a small object.
    let key_id = store.store_object(format!("cache-key-material-{salt}").as_bytes(), &[]);
    let key = store.digest_of(key_id);
    store.ac_put(&key, root_id).expect("seeding the association");

    Graph { key, root, root_data, outputs, chunks }
}

struct Graph {
    key: Vec<u8>,
    root: Vec<u8>,
    /// The root node's own bytes, so a test can re-store it standalone the way
    /// `Proxy::fetch_object` does on a demand load.
    root_data: Vec<u8>,
    outputs: Vec<Vec<u8>>,
    chunks: Vec<Vec<u8>>,
}

impl Graph {
    fn node_count(&self) -> usize {
        1 + self.outputs.len() + self.chunks.len()
    }
}

/// One generation rotation. The store applies its size limit when the handle is
/// DISPOSED, not on open and not on prune: with the limit exceeded, dispose
/// demotes the current generation to upstream and the next open starts a fresh
/// primary. Observed, not assumed: see `how_a_rotation_is_triggered`.
fn rotate(upstream: &'static Upstream, path: &Path) {
    let store = Store::open(upstream, path);
    store.set_size_limit(1);
    store.close();
}

/// Collects generations no longer reachable. Only the two newest are kept, so a
/// generation is orphaned by the SECOND rotation after it, never the first.
fn collect(upstream: &'static Upstream, path: &Path) {
    let store = Store::open(upstream, path);
    store.prune();
    store.close();
}

/// The store's own directory names. `UnifiedOnDiskCache` keeps one directory per
/// generation, so this is how a rotation and a collection are actually observed
/// rather than assumed.
fn layout(path: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(path)
        .map(|entries| {
            entries
                .flatten()
                .map(|entry| entry.file_name().to_string_lossy().into_owned())
                .collect()
        })
        .unwrap_or_default();
    names.sort();
    names
}

fn time(iterations: u32, mut body: impl FnMut()) -> Duration {
    let started = Instant::now();
    for _ in 0..iterations {
        body();
    }
    started.elapsed() / iterations
}

fn yes_no(value: bool) -> &'static str {
    if value {
        "yes"
    } else {
        "NO"
    }
}

fn name(result: llcas_lookup_result_t) -> &'static str {
    match result {
        LLCAS_LOOKUP_RESULT_SUCCESS => "SUCCESS",
        LLCAS_LOOKUP_RESULT_NOTFOUND => "NOTFOUND",
        _ => "ERROR",
    }
}

// --- Apple's plugin, driven directly --------------------------------------------

fn upstream() -> Option<&'static Upstream> {
    static UPSTREAM: OnceLock<Option<&'static Upstream>> = OnceLock::new();
    *UPSTREAM.get_or_init(|| {
        let path = upstream_path();
        if !Path::new(&path).exists() {
            eprintln!("skipping: Apple's libToolchainCASPlugin is unavailable at {path}");
            return None;
        }
        // Leaked on purpose: the table outlives every store in the run and
        // disposing it would unload the dylib out from under open handles.
        let loaded = unsafe { Upstream::load(&path) }.expect("load libToolchainCASPlugin");
        Some(&*Box::leak(Box::new(loaded)))
    })
}

struct Store {
    up: &'static Upstream,
    cas: llcas_cas_t,
}

impl Store {
    fn open(up: &'static Upstream, path: &Path) -> Self {
        unsafe {
            let options = (up.llcas_cas_options_create)();
            (up.llcas_cas_options_set_client_version)(
                options,
                LLCAS_VERSION_MAJOR,
                LLCAS_VERSION_MINOR,
            );
            let c_path = CString::new(path.to_str().expect("utf-8 store path")).unwrap();
            (up.llcas_cas_options_set_ondisk_path)(options, c_path.as_ptr());
            let mut error: *mut c_char = ptr::null_mut();
            let cas = (up.llcas_cas_create)(options, &mut error);
            (up.llcas_cas_options_dispose)(options);
            assert!(!cas.is_null(), "llcas_cas_create: {}", take_error(up, error));
            Self { up, cas }
        }
    }

    fn close(self) {
        unsafe { (self.up.llcas_cas_dispose)(self.cas) };
    }

    fn store_object(&self, data: &[u8], refs: &[llcas_objectid_t]) -> llcas_objectid_t {
        unsafe {
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let failed = (self.up.llcas_cas_store_object)(
                self.cas,
                llcas_data_t { data: data.as_ptr() as *const c_void, size: data.len() },
                refs.as_ptr(),
                refs.len(),
                &mut id,
                &mut error,
            );
            assert!(!failed, "llcas_cas_store_object: {}", take_error(self.up, error));
            id
        }
    }

    fn digest_of(&self, id: llcas_objectid_t) -> Vec<u8> {
        unsafe {
            let digest = (self.up.llcas_objectid_get_digest)(self.cas, id);
            std::slice::from_raw_parts(digest.data, digest.size).to_vec()
        }
    }

    fn objectid_for(&self, digest: &[u8]) -> llcas_objectid_t {
        unsafe {
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let failed = (self.up.llcas_cas_get_objectid)(
                self.cas,
                llcas_digest_t { data: digest.as_ptr(), size: digest.len() },
                &mut id,
                &mut error,
            );
            assert!(!failed, "llcas_cas_get_objectid: {}", take_error(self.up, error));
            id
        }
    }

    fn contains(&self, id: llcas_objectid_t) -> llcas_lookup_result_t {
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let result =
                (self.up.llcas_cas_contains_object)(self.cas, id, false, &mut error);
            let message = take_error(self.up, error);
            assert_ne!(result, LLCAS_LOOKUP_RESULT_ERROR, "contains_object: {message}");
            result
        }
    }

    fn load(&self, id: llcas_objectid_t) -> (llcas_lookup_result_t, llcas_loaded_object_t) {
        unsafe {
            let mut loaded = llcas_loaded_object_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let result =
                (self.up.llcas_cas_load_object)(self.cas, id, &mut loaded, &mut error);
            let message = take_error(self.up, error);
            assert_ne!(result, LLCAS_LOOKUP_RESULT_ERROR, "load_object: {message}");
            (result, loaded)
        }
    }

    fn refs_of(&self, loaded: llcas_loaded_object_t) -> Vec<llcas_objectid_t> {
        unsafe {
            let refs = (self.up.llcas_loaded_object_get_refs)(self.cas, loaded);
            let count = (self.up.llcas_object_refs_get_count)(self.cas, refs);
            (0..count)
                .map(|index| (self.up.llcas_object_refs_get_id)(self.cas, refs, index))
                .collect()
        }
    }

    /// Loads every node reachable from `id`, which is what a materializing
    /// compiler does and the only depth at which "root present" implies
    /// "closure present". Returns whether every reachable node loaded, which is
    /// the verdict a closure-depth guard would act on.
    fn load_closure(&self, id: llcas_objectid_t) -> bool {
        let mut pending = vec![id];
        let mut complete = true;
        while let Some(next) = pending.pop() {
            let (result, loaded) = self.load(next);
            if result != LLCAS_LOOKUP_RESULT_SUCCESS {
                complete = false;
                continue;
            }
            pending.extend(self.refs_of(loaded));
        }
        complete
    }

    fn ac_put(&self, key: &[u8], value: llcas_objectid_t) -> Result<(), String> {
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let failed = (self.up.llcas_actioncache_put_for_digest)(
                self.cas,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                value,
                false,
                &mut error,
            );
            let message = take_error(self.up, error);
            if failed {
                Err(message)
            } else {
                Ok(())
            }
        }
    }

    fn ac_get(&self, key: &[u8]) -> (llcas_lookup_result_t, llcas_objectid_t) {
        unsafe {
            let mut value = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let result = (self.up.llcas_actioncache_get_for_digest)(
                self.cas,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                &mut value,
                false,
                &mut error,
            );
            let message = take_error(self.up, error);
            assert_ne!(result, LLCAS_LOOKUP_RESULT_ERROR, "actioncache_get: {message}");
            (result, value)
        }
    }

    fn ondisk_size(&self) -> i64 {
        let Some(size) = self.up.llcas_cas_get_ondisk_size else { return -1 };
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let value = size(self.cas, &mut error);
            let _ = take_error(self.up, error);
            value
        }
    }

    fn set_size_limit(&self, bytes: i64) {
        let Some(set_limit) = self.up.llcas_cas_set_ondisk_size_limit else {
            panic!("this Xcode's plugin has no llcas_cas_set_ondisk_size_limit");
        };
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let failed = set_limit(self.cas, bytes, &mut error);
            let message = take_error(self.up, error);
            assert!(!failed, "set_ondisk_size_limit: {message}");
        }
    }

    fn prune(&self) {
        let Some(prune) = self.up.llcas_cas_prune_ondisk_data else {
            panic!("this Xcode's plugin has no llcas_cas_prune_ondisk_data");
        };
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let failed = prune(self.cas, &mut error);
            let message = take_error(self.up, error);
            assert!(!failed, "prune_ondisk_data: {message}");
        }
    }
}

fn take_error(up: &Upstream, error: *mut c_char) -> String {
    if error.is_null() {
        return String::new();
    }
    unsafe {
        let text = CStr::from_ptr(error).to_string_lossy().into_owned();
        (up.llcas_string_dispose)(error);
        text
    }
}

// --- Temporary directories -------------------------------------------------------

struct TempDir(PathBuf);

impl TempDir {
    fn new(label: &str) -> Self {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let path = std::env::temp_dir().join(format!(
            "tuist-cas-retention-{label}-{}-{}",
            std::process::id(),
            SEQ.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).expect("create temp dir");
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

// --- Exploration: how a rotation is actually triggered --------------------------

/// How the rotation used by the tests above is actually driven, kept because it
/// is not guessable from the ABI: the size limit is applied when the handle is
/// DISPOSED (not on open, not on prune), and only the two newest generations are
/// kept, so a generation is orphaned by the SECOND rotation after it.
#[test]
#[ignore = "a measurement, not an assertion"]
fn how_a_rotation_is_triggered() {
    let Some(upstream) = upstream() else { return };
    let dir = TempDir::new("rotation-probe");
    let graph = seed(upstream, dir.path());
    println!();
    println!("after seeding                     : {:?}", layout(dir.path()));

    // Rotation 1: the limit is applied when the handle is disposed.
    let store = Store::open(upstream, dir.path());
    println!("  on-disk size                    : {}", store.ondisk_size());
    store.set_size_limit(1);
    println!("  after set_size_limit(1)         : {:?}", layout(dir.path()));
    store.prune();
    println!("  after prune (no rotation yet)   : {:?}", layout(dir.path()));
    store.close();
    println!("after rotation 1                  : {:?}", layout(dir.path()));

    // Rotation 2, with NO read in between.
    let store = Store::open(upstream, dir.path());
    store.set_size_limit(1);
    store.close();
    println!("after rotation 2                  : {:?}", layout(dir.path()));

    // Collect whatever is now orphaned.
    let store = Store::open(upstream, dir.path());
    store.prune();
    store.close();
    println!("after prune                       : {:?}", layout(dir.path()));

    let store = Store::open(upstream, dir.path());
    let root = store.objectid_for(&graph.root);
    println!("  assoc                           : {}", name(store.ac_get(&graph.key).0));
    println!("  contains(root)                  : {}", name(store.contains(root)));
    println!("  load(root)                      : {}", name(store.load(root).0));
    let outputs = count_loadable(&store, &graph.outputs);
    let chunks = count_loadable(&store, &graph.chunks);
    println!("  outputs load                    : {outputs}/{FANOUT}");
    println!("  chunks load                     : {chunks}/{}", FANOUT * CHUNKS_PER_OUTPUT);
    store.close();
    println!();
}
