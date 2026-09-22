//! Characterization: what dropping a store's UPSTREAM generation outside a
//! collection does, and how much of the upstream its primary already holds.
//!
//! A store keeps two generations, and a load that resolves in the upstream copies
//! the value graph forward into the primary (`graph_retention.rs`). Dropping the
//! upstream as soon as a build has run against the new primary would keep one
//! generation at rest instead of two. Whether that is safe is a question about
//! Apple's plugin, and whether it is worth it is a question about how much of the
//! upstream is a copy; both are measured here.
//!
//! What these establish, on Xcode 27:
//!
//! - A store whose upstream was deleted under its `lock` opens cleanly, serves
//!   everything its primary holds, takes writes, and rotates again.
//! - A drop leaves EXACTLY what the next rotation plus collection would, for every
//!   way of reading an association: llcas collects by deleting the generation
//!   directory too. A drop is an early collection, not a new state.
//! - So the shapes a drop can strand are the ones a collection already strands: an
//!   association renewed by a lookup that did not load its root (root absent), and
//!   a root stored standalone over children only the upstream held (interior
//!   absent). This crate's read guard (`verified_local_get`) walks the closure and
//!   answers a miss for both; `unbacked_local_hit.rs` covers that on these shapes.
//!
//! The overlap is measured by enumerating each generation's objects and
//! associations from its files and validating every candidate through the plugin
//! (see `Inventory`). Run the measurements with:
//!
//! ```sh
//! cargo test --manifest-path cas-plugin/Cargo.toml --release \
//!   --test generation_drop -- --ignored --nocapture --test-threads=1
//! ```
//!
//! It reads the Xcode 27 plugin's layout (`index.v1`); against a store another
//! Xcode wrote, the measurement says so and skips. Point
//! `the_overlap_of_a_real_store` at a store with
//! `TUIST_CAS_OVERLAP_STORE=<store dir>` (the lane directory holding `v1.N`). It
//! copies each generation to `TUIST_CAS_OVERLAP_SCRATCH` (default: the temp dir)
//! and never opens the store it measures.

use std::collections::{HashMap, HashSet};
use std::ffi::{c_char, c_void, CStr, CString};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::OnceLock;

use tuist_cas_plugin::types::*;
use tuist_cas_plugin::upstream::Upstream;
use tuist_cas_plugin::upstream_path;

const FANOUT: usize = 8;
const CHUNKS_PER_OUTPUT: usize = 4;
const CHUNK_BYTES: usize = 4 * 1024;

// --- Dropping the upstream ------------------------------------------------------

/// The precondition for any drop: the plugin must treat a missing upstream as a
/// store with one generation, not as a damaged one.
#[test]
fn a_store_whose_upstream_was_dropped_opens_and_serves_its_primary() {
    let Some(upstream) = upstream() else { return };
    let dir = TempDir::new("drop-opens");
    let graphs = seed_many(upstream, dir.path(), 4);
    rotate(upstream, dir.path());
    let store = Store::open(upstream, dir.path());
    for graph in &graphs[..2] {
        let (result, value) = store.ac_get(&graph.key);
        assert_eq!(result, LLCAS_LOOKUP_RESULT_SUCCESS);
        assert!(store.load_closure(value), "the upstream serves the graph before the drop");
    }
    store.close();
    assert_eq!(layout(dir.path()), ["lock", "v1.1", "v1.2"]);

    drop_upstream(dir.path());
    assert_eq!(layout(dir.path()), ["lock", "v1.2"]);

    let store = Store::open(upstream, dir.path());
    for graph in &graphs[..2] {
        let (result, value) = store.ac_get(&graph.key);
        assert_eq!(result, LLCAS_LOOKUP_RESULT_SUCCESS, "a graph the build loaded survives the drop");
        assert!(store.load_closure(value), "and so does its whole closure");
    }
    for graph in &graphs[2..] {
        assert_eq!(
            store.ac_get(&graph.key).0,
            LLCAS_LOOKUP_RESULT_NOTFOUND,
            "a graph nothing read is gone with its association: a clean miss"
        );
        assert_eq!(store.load(store.objectid_for(&graph.root)).0, LLCAS_LOOKUP_RESULT_NOTFOUND);
    }
    let written = write_graph(&store, 100);
    store.close();

    // The store still behaves as a chain: it rotates, and the rotation's upstream
    // is the primary that survived the drop.
    rotate(upstream, dir.path());
    assert_eq!(layout(dir.path()), ["lock", "v1.2", "v1.3"]);
    let store = Store::open(upstream, dir.path());
    for graph in graphs[..2].iter().chain([&written]) {
        let (result, value) = store.ac_get(&graph.key);
        assert_eq!(result, LLCAS_LOOKUP_RESULT_SUCCESS);
        assert!(store.load_closure(value));
    }
    store.close();
}

/// For every way a build can read an association, a drop leaves the store in the
/// state the next rotation and collection would. Printed as the same table
/// `graph_retention.rs` prints for a collection, so the two can be compared.
#[test]
fn a_drop_leaves_what_the_next_collection_would() {
    let Some(upstream) = upstream() else { return };

    println!();
    println!(
        "{:<22} {:>14} {:>14}",
        "read before the drop", "after a drop", "after a collection"
    );
    for arm in Arm::ALL {
        let dropped = survival(upstream, arm, Ending::Drop);
        let collected = survival(upstream, arm, Ending::RotateAndCollect);
        println!("{:<22} {:>14} {:>14}", arm.label(), dropped.to_string(), collected.to_string());
        assert_eq!(dropped, collected, "{}: a drop must be an early collection", arm.label());
    }
    println!();
    println!("assoc/root/outputs/chunks: the association, then what of its graph loads");
    println!();
}

#[derive(Clone, Copy)]
enum Ending {
    Drop,
    RotateAndCollect,
}

#[derive(Clone, Copy)]
enum Arm {
    NoRead,
    GetOnly,
    ProbeRoot,
    LoadRoot,
    LoadClosure,
    /// The root re-stored on its own into the primary, as `Proxy::fetch_object`
    /// can when a demand load names a root: the one sequence that leaves a root
    /// over absent children.
    RestoreRootStandalone,
}

impl Arm {
    const ALL: [Arm; 6] =
        [Arm::NoRead, Arm::GetOnly, Arm::ProbeRoot, Arm::LoadRoot, Arm::LoadClosure, Arm::RestoreRootStandalone];

    fn label(self) -> &'static str {
        match self {
            Arm::NoRead => "none",
            Arm::GetOnly => "ac_get only",
            Arm::ProbeRoot => "probe root",
            Arm::LoadRoot => "load root",
            Arm::LoadClosure => "load closure",
            Arm::RestoreRootStandalone => "re-store root alone",
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
struct Survival {
    association: bool,
    root: bool,
    outputs: usize,
    chunks: usize,
}

impl std::fmt::Display for Survival {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let yes_no = |value: bool| if value { "yes" } else { "NO" };
        write!(f, "{}/{}/{}/{}", yes_no(self.association), yes_no(self.root), self.outputs, self.chunks)
    }
}

fn survival(upstream: &'static Upstream, arm: Arm, ending: Ending) -> Survival {
    let dir = TempDir::new("drop-survival");
    let graph = seed_many(upstream, dir.path(), 1).remove(0);
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
            let outputs: Vec<_> = graph.outputs.iter().map(|digest| store.objectid_for(digest)).collect();
            let restored = store.store_object(&graph.root_data, &outputs);
            assert_eq!(store.digest_of(restored), graph.root);
        }
    }
    store.close();

    match ending {
        Ending::Drop => drop_upstream(dir.path()),
        Ending::RotateAndCollect => {
            rotate(upstream, dir.path());
            collect(upstream, dir.path());
        }
    }

    // A fresh handle: an open one keeps a deleted generation's files alive.
    let store = Store::open(upstream, dir.path());
    let root = store.objectid_for(&graph.root);
    let loadable = |digests: &[Vec<u8>]| {
        digests
            .iter()
            .filter(|digest| store.load(store.objectid_for(digest)).0 == LLCAS_LOOKUP_RESULT_SUCCESS)
            .count()
    };
    let survival = Survival {
        association: store.ac_get(&graph.key).0 == LLCAS_LOOKUP_RESULT_SUCCESS,
        root: store.load(root).0 == LLCAS_LOOKUP_RESULT_SUCCESS,
        outputs: loadable(&graph.outputs),
        chunks: loadable(&graph.chunks),
    };
    store.close();
    survival
}

/// A drop as the prune would do it: the second-newest generation deleted while
/// the store's `lock` is held exclusively, which no open handle allows.
fn drop_upstream(path: &Path) {
    let lock = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .open(path.join("lock"))
        .expect("open the store lock");
    lock.try_lock().expect("nothing holds the store open");
    let mut generations = generation_dirs(path);
    generations.pop();
    let (_, upstream) = generations.pop().expect("a store with an upstream");
    std::fs::remove_dir_all(upstream).expect("drop the upstream");
}

// --- How much of the upstream is a copy -----------------------------------------

/// The enumeration has to be exact for the overlap figures to mean anything, so
/// it is checked against a store whose contents are known: six graphs, rotated,
/// then two loaded and one only looked up.
#[test]
fn the_overlap_count_matches_what_the_reads_carried_forward() {
    let Some(upstream) = upstream() else { return };
    let dir = TempDir::new("overlap-exact");
    let graphs = seed_many(upstream, dir.path(), 6);
    rotate(upstream, dir.path());
    let store = Store::open(upstream, dir.path());
    for graph in &graphs[..2] {
        let (_, value) = store.ac_get(&graph.key);
        assert!(store.load_closure(value));
    }
    let _ = store.ac_get(&graphs[2].key);
    store.close();

    let scratch = TempDir::new("overlap-exact-scratch");
    let Some(overlap) = Overlap::measure(upstream, dir.path(), scratch.path()) else { return };
    let upstream_inventory = overlap.upstream.as_ref().expect("the store has an upstream");
    let per_graph = 1 + FANOUT + FANOUT * CHUNKS_PER_OUTPUT;
    // Each graph is its nodes plus the object its key is the digest of.
    assert_eq!(upstream_inventory.objects.len(), 6 * (per_graph + 1));
    assert_eq!(upstream_inventory.associations.len(), 6);
    assert_eq!(overlap.primary.objects.len(), 2 * per_graph, "only the loaded graphs were copied");
    assert_eq!(overlap.shared_objects(), 2 * per_graph);
    assert_eq!(
        overlap.shared_bytes(),
        overlap.primary.bytes(),
        "everything the primary holds is a copy: nothing new was written"
    );
    assert_eq!(overlap.primary.associations.len(), 3, "a lookup renews its association");
    assert_eq!(overlap.primary.stranded_at_root, 1, "the one only looked up would be stranded at its root");
    assert_eq!(overlap.primary.stranded_below_root, 0);
}

/// Most of a store's bytes are in objects too large for the data pool, which the
/// plugin keeps in a leaf file of their own, and the session table is read off
/// those files' mtimes. So the naming has to be right: 4 MiB lands in
/// `leaf+0.<offset>.v1`, not the `leaf.<offset>.v1` a smaller one gets, and a
/// scan that knows only the second form reports no sessions at all.
#[test]
fn a_standalone_object_is_counted_in_the_session_that_copied_it() {
    const STANDALONE_BYTES: usize = 4 * 1024 * 1024;
    let Some(upstream) = upstream() else { return };
    let dir = TempDir::new("overlap-standalone");
    let store = Store::open(upstream, dir.path());
    let big = store.store_object(&vec![7u8; STANDALONE_BYTES], &[]);
    let key = store.digest_of(store.store_object(b"cache-key-material-standalone", &[]));
    store.ac_put(&key, big);
    store.close();
    rotate(upstream, dir.path());

    // The next job's lookup, which copies the object into the new primary.
    let store = Store::open(upstream, dir.path());
    let (result, value) = store.ac_get(&key);
    assert_eq!(result, LLCAS_LOOKUP_RESULT_SUCCESS);
    assert!(store.load_closure(value));
    store.close();

    let scratch = TempDir::new("overlap-standalone-scratch");
    let Some(overlap) = Overlap::measure(upstream, dir.path(), scratch.path()) else { return };
    let sessions = overlap.sessions();
    assert_eq!(sessions.len(), 1, "one run of writes copied the object forward");
    assert!(
        sessions[0].copied >= STANDALONE_BYTES as u64,
        "the copy must be accounted to the session that made it, not dropped: copied {}",
        sessions[0].copied
    );
    assert_eq!(sessions[0].new, 0, "nothing was written that the upstream did not have");
}

/// A store another Xcode wrote is skipped, not failed. The record shape this
/// scan reads was only checked against the Xcode 27 plugin's `index.v1`, while a
/// supported Xcode 26 install writes `v8.*` and the compilers' lanes `v9.*`, and
/// the plugin that validates candidates is whichever Xcode is active.
#[test]
fn a_store_in_another_xcodes_layout_is_skipped() {
    let Some(upstream) = upstream() else { return };
    let dir = TempDir::new("overlap-foreign-layout");
    std::fs::create_dir_all(dir.path().join("v1.1")).expect("create the generation");
    std::fs::write(dir.path().join("v1.1").join("v8.index"), b"another layout").expect("write the index");
    let scratch = TempDir::new("overlap-foreign-scratch");

    assert!(Overlap::measure(upstream, dir.path(), scratch.path()).is_none());
}

/// The measurement to run against a real store (see the module docs).
#[test]
#[ignore = "a measurement of a store named by TUIST_CAS_OVERLAP_STORE"]
fn the_overlap_of_a_real_store() {
    let Some(upstream) = upstream() else { return };
    let Some(store) = std::env::var_os("TUIST_CAS_OVERLAP_STORE") else {
        eprintln!("skipping: TUIST_CAS_OVERLAP_STORE is not set");
        return;
    };
    let scratch = std::env::var_os("TUIST_CAS_OVERLAP_SCRATCH")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join(format!("tuist-cas-overlap-{}", std::process::id()));
    let overlap = Overlap::measure(upstream, Path::new(&store), &scratch);
    let _ = std::fs::remove_dir_all(&scratch);
    let Some(overlap) = overlap else { return };
    println!();
    println!("{}", overlap.report());
}

struct Overlap {
    primary_name: String,
    primary: Inventory,
    upstream_name: Option<String>,
    upstream: Option<Inventory>,
}

impl Overlap {
    /// `None` for a store this scan cannot read: only the Xcode 27 plugin's
    /// layout has had its record shape checked, and the plugin that would have to
    /// validate the candidates is whichever Xcode is active anyway.
    fn measure(up: &'static Upstream, store: &Path, scratch: &Path) -> Option<Self> {
        let mut generations = generation_dirs(store);
        let (_, primary_path) = generations.pop().expect("a store with a generation");
        if index_file(&primary_path).is_none() {
            eprintln!(
                "skipping: {} is not in the Xcode 27 plugin layout (no {INDEX_FILE})",
                primary_path.display()
            );
            return None;
        }
        let upstream = generations.pop();
        Some(Self {
            primary_name: file_name(&primary_path),
            primary: Inventory::measure(up, &primary_path, &scratch.join("primary")),
            upstream_name: upstream.as_ref().map(|(_, path)| file_name(path)),
            upstream: upstream.map(|(_, path)| Inventory::measure(up, &path, &scratch.join("upstream"))),
        })
    }

    /// The primary's standalone objects grouped into the runs that wrote them,
    /// oldest first. Published jobs write in disjoint windows, so a gap this wide
    /// separates one job's writes from the next's.
    fn sessions(&self) -> Vec<Session> {
        const GAP_SECONDS: u64 = 120;
        let mut written = self.primary.written.clone();
        written.sort();
        let mut sessions: Vec<Session> = Vec::new();
        for (at, digest) in written {
            let size = self.primary.objects.get(&digest).copied().unwrap_or(0);
            let from_upstream =
                self.upstream.as_ref().is_some_and(|upstream| upstream.objects.contains_key(&digest));
            match sessions.last_mut() {
                Some(session) if at <= session.last + GAP_SECONDS => {
                    session.last = at;
                    if from_upstream {
                        session.copied += size;
                    } else {
                        session.new += size;
                    }
                    session.covered.insert(digest);
                }
                _ => {
                    let mut covered = HashSet::new();
                    covered.insert(digest);
                    sessions.push(Session {
                        started: at,
                        last: at,
                        copied: if from_upstream { size } else { 0 },
                        new: if from_upstream { 0 } else { size },
                        covered,
                    });
                }
            }
        }
        sessions
    }

    fn shared_objects(&self) -> usize {
        self.upstream
            .as_ref()
            .map_or(0, |upstream| upstream.objects.keys().filter(|digest| self.primary.objects.contains_key(*digest)).count())
    }

    fn shared_bytes(&self) -> u64 {
        self.upstream.as_ref().map_or(0, |upstream| {
            upstream
                .objects
                .iter()
                .filter(|(digest, _)| self.primary.objects.contains_key(*digest))
                .map(|(_, size)| size)
                .sum()
        })
    }

    fn report(&self) -> String {
        let mut lines = vec![format!("primary  {}: {}", self.primary_name, self.primary.summary())];
        let Some(upstream) = &self.upstream else {
            lines.push("no upstream: there is nothing a drop would remove".into());
            return lines.join("\n");
        };
        lines.push(format!("upstream {}: {}", self.upstream_name.as_deref().unwrap_or("?"), upstream.summary()));
        let shared = self.shared_bytes();
        let shared_keys =
            upstream.associations.keys().filter(|key| self.primary.associations.contains_key(*key)).count();
        lines.push(format!(
            "upstream objects the primary also holds: {}/{} objects, {} of {} ({:.1}% of the upstream's bytes)",
            self.shared_objects(),
            upstream.objects.len(),
            mib(shared),
            mib(upstream.bytes()),
            percent(shared, upstream.bytes())
        ));
        lines.push(format!("only in the upstream (what a drop removes): {}", mib(upstream.bytes() - shared)));
        lines.push(format!("only in the primary (new since the rotation): {}", mib(self.primary.bytes() - shared)));
        lines.push(format!(
            "upstream associations the primary also holds: {shared_keys}/{} ({:.1}%)",
            upstream.associations.len(),
            percent(shared_keys as u64, upstream.associations.len() as u64)
        ));
        lines.push(format!(
            "primary associations a drop would strand: {} at the root, {} below it, of {}",
            self.primary.stranded_at_root,
            self.primary.stranded_below_root,
            self.primary.associations.len()
        ));
        lines.push(String::new());
        lines.push("the primary's standalone objects by write session (a gap of 2+ minutes starts one):".into());
        lines.push(format!("  {:<20} {:>12} {:>12} {:>16}", "started (UTC)", "copied", "new", "upstream covered"));
        let mut covered: HashSet<Digest> = HashSet::new();
        for session in self.sessions() {
            covered.extend(session.covered.iter().copied());
            let covered_bytes: u64 = covered.iter().filter_map(|digest| upstream.objects.get(digest)).sum();
            lines.push(format!(
                "  {:<20} {:>12} {:>12} {:>15.1}%",
                utc(session.started),
                mib(session.copied),
                mib(session.new),
                percent(covered_bytes, upstream.bytes())
            ));
        }
        lines.push("  (upstream covered = share of the upstream's bytes the primary held by the end of that session,".into());
        lines.push("   counting standalone objects only)".into());
        lines.join("\n")
    }
}

fn utc(seconds: u64) -> String {
    let output = std::process::Command::new("date")
        .args(["-u", "-r", &seconds.to_string(), "+%Y-%m-%dT%H:%M:%S"])
        .output()
        .ok();
    output.map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string()).unwrap_or_default()
}

/// One run of writes into the primary: what it copied forward from the upstream,
/// and what it wrote that the upstream never had.
struct Session {
    started: u64,
    last: u64,
    copied: u64,
    new: u64,
    covered: HashSet<Digest>,
}

/// One generation's objects and associations, read from its files and validated
/// through the plugin.
///
/// Xcode 27's plugin keeps a generation's object index in `index.v1` and its
/// action cache in `actions.v1`, and both are tries whose records are an 8-byte
/// value followed by a 65-byte digest (a kind byte, 0 for objects, then the hash),
/// starting 8-byte aligned. An action record's value is the offset of its value's
/// record in `index.v1`. The scan takes every aligned window of that shape whose
/// hash half looks like a hash; a candidate only counts once it LOADS from a copy
/// of this generation opened on its own, so a misread record cannot be counted,
/// and neither generation can answer for the other.
struct Inventory {
    /// Object digest -> data bytes.
    objects: HashMap<Digest, u64>,
    /// Action-cache key -> value digest.
    associations: HashMap<Digest, Digest>,
    unloadable_records: usize,
    stranded_at_root: usize,
    stranded_below_root: usize,
    allocated: u64,
    /// When each standalone object was written: the mtime of its leaf file, whose
    /// trailing number is the offset of the object's record in `index.v1`.
    /// Standalone objects are the large ones, so this covers most of the bytes.
    written: Vec<(u64, Digest)>,
}

const DIGEST_BYTES: usize = 65;
const INDEX_FILE: &str = "index.v1";
type Digest = [u8; DIGEST_BYTES];

/// The generation's object index, if it is in the one layout this scan reads.
/// Xcode 26.5's plugin writes `v8.index` and the compilers' lanes `v9.index`,
/// whose record shape has not been checked.
fn index_file(generation: &Path) -> Option<PathBuf> {
    let index = generation.join(INDEX_FILE);
    index.exists().then_some(index)
}

impl Inventory {
    fn measure(up: &'static Upstream, generation: &Path, scratch: &Path) -> Self {
        let index = index_file(generation)
            .unwrap_or_else(|| panic!("{} is not in the Xcode 27 plugin layout", generation.display()));
        let index_records = scan_records(&index);
        let by_offset: HashMap<u64, Digest> =
            index_records.iter().map(|record| (record.offset, record.digest)).collect();
        let associations: HashMap<Digest, Digest> = scan_records(&generation.join("actions.v1"))
            .into_iter()
            .filter_map(|record| Some((record.digest, *by_offset.get(&record.value)?)))
            .collect();

        let _ = std::fs::remove_dir_all(scratch);
        std::fs::create_dir_all(scratch).expect("create the scratch store");
        let copied = std::process::Command::new("cp")
            .arg("-cR")
            .arg(generation)
            .arg(scratch.join("v1.1"))
            .status()
            .expect("run cp");
        assert!(copied.success(), "copy {}", generation.display());
        let store = Store::open(up, scratch);

        let mut objects = HashMap::new();
        let mut unloadable_records = 0;
        for record in &index_records {
            match store.size_of(&record.digest) {
                Some(size) => {
                    objects.insert(record.digest, size);
                }
                None => unloadable_records += 1,
            }
        }
        let mut stranded_at_root = 0;
        let mut stranded_below_root = 0;
        let mut complete = HashSet::new();
        for value in associations.values() {
            if !objects.contains_key(value) {
                stranded_at_root += 1;
            } else if !store.closure_loads_by_digest(value, &mut complete) {
                stranded_below_root += 1;
            }
        }
        store.close();
        let _ = std::fs::remove_dir_all(scratch);
        let written = std::fs::read_dir(generation)
            .map(|entries| {
                entries
                    .flatten()
                    .filter_map(|entry| {
                        let name = entry.file_name().to_string_lossy().into_owned();
                        // `leaf.<offset>.v1` and `leaf+<n>.<offset>.v1` both occur.
                        let offset: u64 =
                            name.strip_prefix("leaf")?.strip_suffix(".v1")?.rsplit('.').next()?.parse().ok()?;
                        let digest = *by_offset.get(&offset)?;
                        let modified = entry.metadata().ok()?.modified().ok()?;
                        let seconds = modified.duration_since(std::time::UNIX_EPOCH).ok()?.as_secs();
                        Some((seconds, digest))
                    })
                    .collect()
            })
            .unwrap_or_default();
        Self {
            objects,
            associations,
            unloadable_records,
            stranded_at_root,
            stranded_below_root,
            allocated: allocated_bytes(generation),
            written,
        }
    }

    fn bytes(&self) -> u64 {
        self.objects.values().sum()
    }

    fn summary(&self) -> String {
        format!(
            "{} objects holding {}, {} associations, {} allocated ({} index records do not load)",
            self.objects.len(),
            mib(self.bytes()),
            self.associations.len(),
            mib(self.allocated),
            self.unloadable_records
        )
    }
}

struct Record {
    /// Where the record starts in its file, which is what an action record's
    /// value names.
    offset: u64,
    value: u64,
    digest: Digest,
}

/// Every record-shaped window in an llcas trie file, read in chunks so a large
/// sparse index is never held in memory at once.
fn scan_records(path: &Path) -> Vec<Record> {
    const CHUNK: usize = 64 * 1024 * 1024;
    const OVERLAP: usize = 8 + DIGEST_BYTES + 7;
    let Ok(mut file) = std::fs::File::open(path) else { return Vec::new() };
    let mut records = Vec::new();
    let mut seen = HashSet::new();
    let mut buffer: Vec<u8> = Vec::new();
    // File offset of buffer[0]; always 8-aligned.
    let mut base: u64 = 0;
    let mut chunk = vec![0u8; CHUNK];
    loop {
        let read = file.read(&mut chunk).expect("read trie file");
        if read == 0 {
            break;
        }
        buffer.extend_from_slice(&chunk[..read]);
        let mut at = 0;
        while at + 8 + DIGEST_BYTES <= buffer.len() {
            // Trie files are mostly zero pages; skip them a page at a time.
            if at % 4096 == 0 && at + 4096 <= buffer.len() && buffer[at..at + 4096].iter().all(|byte| *byte == 0) {
                at += 4096;
                continue;
            }
            let value = u64::from_le_bytes(buffer[at..at + 8].try_into().unwrap());
            let digest = &buffer[at + 8..at + 8 + DIGEST_BYTES];
            // A zero value is a real record too: an object a reference named before
            // any data for it was stored, which is what a renewed association's
            // value is when the lookup did not load it.
            if digest[0] == 0 && looks_like_a_hash(&digest[1..]) {
                let digest: Digest = digest.try_into().unwrap();
                if seen.insert(digest) {
                    records.push(Record { offset: base + at as u64, value, digest });
                }
            }
            at += 8;
        }
        let keep_from = at.min(buffer.len().saturating_sub(OVERLAP)) & !7;
        base += keep_from as u64;
        buffer.drain(..keep_from);
    }
    records
}

fn looks_like_a_hash(bytes: &[u8]) -> bool {
    let distinct: HashSet<u8> = bytes.iter().copied().collect();
    distinct.len() >= 24 && !bytes.windows(4).any(|window| window == [0, 0, 0, 0])
}

fn allocated_bytes(path: &Path) -> u64 {
    use std::os::unix::fs::MetadataExt;
    std::fs::read_dir(path)
        .map(|entries| entries.flatten().filter_map(|entry| entry.metadata().ok()).map(|meta| meta.blocks() * 512).sum())
        .unwrap_or(0)
}

fn mib(bytes: u64) -> String {
    format!("{:.1} MiB", bytes as f64 / (1024.0 * 1024.0))
}

fn percent(part: u64, whole: u64) -> f64 {
    if whole == 0 {
        0.0
    } else {
        100.0 * part as f64 / whole as f64
    }
}

// --- Stores and graphs ------------------------------------------------------------

struct Graph {
    key: Vec<u8>,
    root: Vec<u8>,
    root_data: Vec<u8>,
    outputs: Vec<Vec<u8>>,
    chunks: Vec<Vec<u8>>,
}

fn seed_many(upstream: &'static Upstream, path: &Path, count: usize) -> Vec<Graph> {
    let store = Store::open(upstream, path);
    let graphs = (0..count).map(|salt| write_graph(&store, salt)).collect();
    store.close();
    graphs
}

/// A value graph shaped like a compilation's (a root over outputs over content
/// chunks) plus the association naming it. `salt` keeps graphs distinct.
fn write_graph(store: &Store, salt: usize) -> Graph {
    let mut outputs = Vec::new();
    let mut chunks = Vec::new();
    let mut output_ids = Vec::new();
    for output in 0..FANOUT {
        let mut chunk_ids = Vec::new();
        for chunk in 0..CHUNKS_PER_OUTPUT {
            let mut data = vec![0u8; CHUNK_BYTES];
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
    let key_id = store.store_object(format!("cache-key-material-{salt}").as_bytes(), &[]);
    let key = store.digest_of(key_id);
    store.ac_put(&key, root_id);
    Graph { key, root, root_data, outputs, chunks }
}

/// One rotation: the plugin applies a size limit when the handle is disposed.
fn rotate(upstream: &'static Upstream, path: &Path) {
    let store = Store::open(upstream, path);
    store.set_size_limit(1);
    store.close();
}

/// llcas's own collection of the generations behind the newest two.
fn collect(upstream: &'static Upstream, path: &Path) {
    let store = Store::open(upstream, path);
    store.prune();
    store.close();
}

fn generation_dirs(path: &Path) -> Vec<(u64, PathBuf)> {
    let mut generations: Vec<(u64, PathBuf)> = std::fs::read_dir(path)
        .expect("read the store")
        .flatten()
        .filter_map(|entry| {
            let index = entry.file_name().to_string_lossy().strip_prefix("v1.")?.parse().ok()?;
            entry.path().is_dir().then_some((index, entry.path()))
        })
        .collect();
    generations.sort();
    generations
}

fn layout(path: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(path)
        .map(|entries| entries.flatten().map(|entry| entry.file_name().to_string_lossy().into_owned()).collect())
        .unwrap_or_default();
    names.sort();
    names
}

fn file_name(path: &Path) -> String {
    path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default()
}

fn upstream() -> Option<&'static Upstream> {
    static UPSTREAM: OnceLock<Option<&'static Upstream>> = OnceLock::new();
    *UPSTREAM.get_or_init(|| {
        let path = upstream_path();
        if !Path::new(&path).exists() {
            eprintln!("skipping: Apple's libToolchainCASPlugin is unavailable at {path}");
            return None;
        }
        // Leaked: the table outlives every store in the run.
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
            (up.llcas_cas_options_set_client_version)(options, LLCAS_VERSION_MAJOR, LLCAS_VERSION_MINOR);
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
            let result = (self.up.llcas_cas_contains_object)(self.cas, id, false, &mut error);
            let message = take_error(self.up, error);
            assert_ne!(result, LLCAS_LOOKUP_RESULT_ERROR, "contains_object: {message}");
            result
        }
    }

    fn load(&self, id: llcas_objectid_t) -> (llcas_lookup_result_t, llcas_loaded_object_t) {
        unsafe {
            let mut loaded = llcas_loaded_object_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let result = (self.up.llcas_cas_load_object)(self.cas, id, &mut loaded, &mut error);
            let message = take_error(self.up, error);
            assert_ne!(result, LLCAS_LOOKUP_RESULT_ERROR, "load_object: {message}");
            (result, loaded)
        }
    }

    fn refs_of(&self, loaded: llcas_loaded_object_t) -> Vec<llcas_objectid_t> {
        unsafe {
            let refs = (self.up.llcas_loaded_object_get_refs)(self.cas, loaded);
            let count = (self.up.llcas_object_refs_get_count)(self.cas, refs);
            (0..count).map(|index| (self.up.llcas_object_refs_get_id)(self.cas, refs, index)).collect()
        }
    }

    /// Loads every node reachable from `id`; whether all of them loaded.
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

    /// `load_closure` from a digest, memoizing nodes already proven complete so a
    /// real store's shared subgraphs are walked once.
    fn closure_loads_by_digest(&self, root: &Digest, complete: &mut HashSet<Digest>) -> bool {
        let mut pending = vec![*root];
        let mut visited = HashSet::new();
        while let Some(digest) = pending.pop() {
            if complete.contains(&digest) || !visited.insert(digest) {
                continue;
            }
            let (result, loaded) = self.load(self.objectid_for(&digest));
            if result != LLCAS_LOOKUP_RESULT_SUCCESS {
                return false;
            }
            for child in self.refs_of(loaded) {
                if let Ok(child) = Digest::try_from(self.digest_of(child).as_slice()) {
                    pending.push(child);
                }
            }
        }
        complete.extend(visited);
        true
    }

    fn size_of(&self, digest: &[u8]) -> Option<u64> {
        let (result, loaded) = self.load(self.objectid_for(digest));
        (result == LLCAS_LOOKUP_RESULT_SUCCESS)
            .then(|| unsafe { (self.up.llcas_loaded_object_get_data)(self.cas, loaded) }.size as u64)
    }

    fn ac_put(&self, key: &[u8], value: llcas_objectid_t) {
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let failed = (self.up.llcas_actioncache_put_for_digest)(
                self.cas,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                value,
                false,
                &mut error,
            );
            assert!(!failed, "actioncache_put: {}", take_error(self.up, error));
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

    fn set_size_limit(&self, bytes: i64) {
        let set_limit = self.up.llcas_cas_set_ondisk_size_limit.expect("llcas_cas_set_ondisk_size_limit");
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let failed = set_limit(self.cas, bytes, &mut error);
            assert!(!failed, "set_ondisk_size_limit: {}", take_error(self.up, error));
        }
    }

    fn prune(&self) {
        let prune = self.up.llcas_cas_prune_ondisk_data.expect("llcas_cas_prune_ondisk_data");
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let failed = prune(self.cas, &mut error);
            assert!(!failed, "prune_ondisk_data: {}", take_error(self.up, error));
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

struct TempDir(PathBuf);

impl TempDir {
    fn new(label: &str) -> Self {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let path = std::env::temp_dir().join(format!(
            "tuist-cas-drop-{label}-{}-{}",
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

