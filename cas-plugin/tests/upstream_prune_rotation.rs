//! Characterization of an upstream defect in Apple's `libToolchainCASPlugin`:
//! a size-driven prune can leave an action-cache association pointing at a value
//! graph that no longer exists, so `llcas_actioncache_get_for_digest` answers
//! `SUCCESS` with a root object that `llcas_cas_contains_object` reports as
//! `NOTFOUND`. Downstream that is the build failure in
//! <https://github.com/tuist/tuist/issues/12245>:
//! `error: CAS operation failed: missing object '0~...'` -- a warning plus a
//! recompile on the Swift lane, fatal on the clang lane.
//!
//! Mechanism, reproduced below with zero Tuist code on the path (the test drives
//! Apple's dylib directly through the raw llcas ABI):
//!
//! 1. The on-disk store is a chain of generations: `v1.1/{v8.data, v8.index,
//!    v3.actions}`. Objects (`v8.*`) and the action cache (`v3.actions`) are
//!    SEPARATE files, so nothing structurally ties an association's lifetime to
//!    its value graph's.
//! 2. `llcas_cas_set_ondisk_size_limit` + `llcas_cas_prune_ondisk_data` -- what
//!    the build system issues on every build -- does not delete in place. It
//!    ROTATES: a new primary generation `v1.2` is created with `v1.1` chained
//!    behind it, read-only, awaiting collection.
//! 3. An ordinary action-cache read then faults the key -> value ASSOCIATION
//!    forward into the new primary, but does NOT copy the value graph forward --
//!    not even the root object.
//! 4. When the old generation is finally collected, the faulted-forward
//!    association survives in the new primary pointing at nothing.
//!
//! The control case (no read between rotation and collection) shows the read is
//! what plants the dangling entry: with nothing faulted forward, the association
//! is collected together with its objects and the lookup correctly misses.
//!
//! These tests assert the CURRENT, ACTUAL behaviour of Xcode's plugin (verified
//! on Xcode 26.3). A FAILURE HERE IS NOT NECESSARILY A REGRESSION IN THIS CRATE:
//! if `dangling_association` starts failing because the association no longer
//! survives collection, Apple has likely fixed the defect, and the workarounds
//! this crate carries for unbacked local hits (see the FETCH_OBJECT fallbacks in
//! `src/proxy.rs`) can be revisited.
//!
//! Collection of the rotated-out generation is SIMULATED by removing the `v1.1`
//! directory. Apple's own collector is time/pressure driven and did not fire
//! within a test's lifetime in any harness tried; removing the directory is
//! exactly what the collector does to the bytes, and the point under test is the
//! state of the NEW generation, which the test never touches.

use std::ffi::{c_char, CStr, CString};
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::OnceLock;

use tuist_cas_plugin::types::*;
use tuist_cas_plugin::upstream::Upstream;
use tuist_cas_plugin::upstream_path;

/// Junk written to push the store past the size limit so the prune has something
/// to reclaim and actually rotates. Small on purpose: 8 MiB is comfortably over
/// the 1 MiB limit below and keeps the test a couple of seconds of I/O.
const JUNK_BLOBS: usize = 8;
const JUNK_BLOB_SIZE: usize = 1 << 20;
/// The budget declared before pruning, mirroring what the build system sets.
const SIZE_LIMIT: i64 = 1 << 20;
/// The generation that is primary while the entry is seeded, and that rotation
/// demotes to a read-only upstream link.
const FIRST_GENERATION: &str = "v1.1";
/// The generation `llcas_cas_prune_ondisk_data` creates as the new primary.
const SECOND_GENERATION: &str = "v1.2";

#[test]
fn actioncache_read_before_collection_leaves_an_association_without_its_objects() {
    let Some(upstream) = upstream() else {
        return skip("Apple's libToolchainCASPlugin is unavailable");
    };
    let store = TempStore::new("dangling");

    let root_digest = seed(upstream, store.path());
    rotate(upstream, store.path());
    assert_rotated(store.path());

    // The step under test: an ordinary hit, exactly what a compiler frontend
    // issues, while both generations are still on disk. This is what faults the
    // association forward into the new primary -- without the value graph.
    let (result, _) = {
        let cas = Cas::open(upstream, store.path());
        let key = cas.key_digest();
        cas.actioncache_get(&key)
    };
    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_SUCCESS,
        "the entry must still resolve before collection, or the test is not \
         exercising the faulting-forward path"
    );

    collect_first_generation(store.path());

    let cas = Cas::open(upstream, store.path());
    let key = cas.key_digest();
    let (result, value) = cas.actioncache_get(&key);
    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_SUCCESS,
        "UPSTREAM DEFECT (see the module docs): the association survived \
         collection of the generation holding its value graph. If this now \
         misses, Apple may have fixed the defect."
    );
    assert_eq!(
        cas.digest_string(&cas.digest_of(value)),
        cas.digest_string(&root_digest),
        "the surviving association still names the original root object"
    );
    assert_eq!(
        cas.contains(value),
        LLCAS_LOOKUP_RESULT_NOTFOUND,
        "UPSTREAM DEFECT: the hit's root object is gone, so the client is handed \
         a cache hit it cannot replay -- 'missing object' at the compiler"
    );
    // Independently by digest, so a stale objectid handle cannot mask the answer.
    let reparsed = cas
        .objectid_for(&root_digest)
        .expect("the root digest is well-formed and parses in the new generation");
    assert_eq!(
        cas.contains(reparsed),
        LLCAS_LOOKUP_RESULT_NOTFOUND,
        "the root object is genuinely absent, not merely unreachable through a \
         stale handle"
    );
}

#[test]
fn without_a_read_before_collection_the_association_is_collected_with_its_objects() {
    let Some(upstream) = upstream() else {
        return skip("Apple's libToolchainCASPlugin is unavailable");
    };
    let store = TempStore::new("control");

    let root_digest = seed(upstream, store.path());
    rotate(upstream, store.path());
    assert_rotated(store.path());

    // The control: identical to the case above except that NOTHING reads the
    // action cache between rotation and collection.
    collect_first_generation(store.path());

    let cas = Cas::open(upstream, store.path());
    let key = cas.key_digest();
    let (result, _) = cas.actioncache_get(&key);
    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_NOTFOUND,
        "with no read to fault it forward, the association is collected with its \
         objects and the lookup correctly misses -- so the read in the other \
         test is what plants the dangling entry"
    );
    let reparsed = cas
        .objectid_for(&root_digest)
        .expect("the root digest is well-formed and parses in the new generation");
    assert_eq!(
        cas.contains(reparsed),
        LLCAS_LOOKUP_RESULT_NOTFOUND,
        "the value graph is gone in the control case too"
    );
}

// --- Phases ------------------------------------------------------------------

/// Publishes `key -> root -> leaf`, verifies it resolves, then bulks the store
/// up and prunes it under a small limit -- the sequence a build performs.
/// Returns the root object's digest bytes for the later checks.
fn seed(upstream: &'static Upstream, store: &Path) -> Vec<u8> {
    let cas = Cas::open(upstream, store);
    let key = cas.key_digest();

    let leaf = cas.store_object(b"leaf-payload-regression", &[]);
    let root = cas.store_object(b"root-payload-regression", &[leaf]);
    cas.actioncache_put(&key, root);

    let (result, _) = cas.actioncache_get(&key);
    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_SUCCESS,
        "the seeded entry resolves"
    );
    assert_eq!(cas.contains(root), LLCAS_LOOKUP_RESULT_SUCCESS);
    assert_eq!(cas.contains(leaf), LLCAS_LOOKUP_RESULT_SUCCESS);
    let root_digest = cas.digest_of(root);

    let mut blob = vec![0u8; JUNK_BLOB_SIZE];
    for index in 0..JUNK_BLOBS {
        blob.fill(index as u8);
        blob[..std::mem::size_of::<usize>()].copy_from_slice(&index.to_le_bytes());
        cas.store_object(&blob, &[]);
    }

    cas.set_ondisk_size_limit(SIZE_LIMIT);
    cas.prune_ondisk_data();
    root_digest
}

/// A later build declaring the same budget and pruning again. This is the call
/// that rotates the generation; a fresh CAS handle stands in for the fresh
/// process a real build brings.
fn rotate(upstream: &'static Upstream, store: &Path) {
    let cas = Cas::open(upstream, store);
    cas.set_ondisk_size_limit(SIZE_LIMIT);
    cas.prune_ondisk_data();
}

/// The rotation is the premise of both tests, so assert the on-disk shape rather
/// than trusting it: the old generation demoted, a new primary alongside it.
fn assert_rotated(store: &Path) {
    assert!(
        store.join(FIRST_GENERATION).is_dir(),
        "the seeded generation {FIRST_GENERATION} is still on disk after the prune"
    );
    assert!(
        store.join(SECOND_GENERATION).is_dir(),
        "the prune rotated to a new primary generation {SECOND_GENERATION} instead \
         of deleting in place; without a rotation neither test means anything"
    );
}

/// Stands in for Apple's collector reclaiming the rotated-out generation (see
/// the module docs for why this is simulated).
fn collect_first_generation(store: &Path) {
    std::fs::remove_dir_all(store.join(FIRST_GENERATION))
        .expect("remove the rotated-out generation");
}

// --- Upstream plugin ---------------------------------------------------------

/// Apple's plugin, loaded once for the whole test binary, or `None` when it is
/// not installed. Resolved exactly like the plugin resolves it at runtime
/// (`TUIST_CAS_UPSTREAM_PLUGIN`, else the active developer dir).
fn upstream() -> Option<&'static Upstream> {
    static UPSTREAM: OnceLock<Option<&'static Upstream>> = OnceLock::new();
    *UPSTREAM.get_or_init(|| {
        let path = upstream_path();
        if !Path::new(&path).exists() {
            return None;
        }
        let loaded = unsafe { Upstream::load(&path) }.ok()?;
        let loaded: &'static Upstream = Box::leak(Box::new(loaded));
        // The prune entry points are optional in the ABI table. A plugin without
        // them cannot rotate, so there is nothing to characterize.
        loaded.llcas_cas_set_ondisk_size_limit?;
        loaded.llcas_cas_prune_ondisk_data?;
        Some(loaded)
    })
}

fn skip(reason: &str) {
    eprintln!("skipping upstream prune-rotation characterization: {reason}");
}

/// An open handle on the on-disk CAS, disposed when it goes out of scope. Each
/// phase takes its own handle: reopening is what a real build does, and it is
/// also what forces the plugin to re-read the generation chain from disk.
struct Cas {
    upstream: &'static Upstream,
    raw: llcas_cas_t,
}

impl Cas {
    fn open(upstream: &'static Upstream, path: &Path) -> Self {
        unsafe {
            let options = (upstream.llcas_cas_options_create)();
            (upstream.llcas_cas_options_set_client_version)(
                options,
                LLCAS_VERSION_MAJOR,
                LLCAS_VERSION_MINOR,
            );
            let c_path = CString::new(path.to_str().expect("utf-8 store path")).unwrap();
            (upstream.llcas_cas_options_set_ondisk_path)(options, c_path.as_ptr());
            let mut error: *mut c_char = ptr::null_mut();
            let raw = (upstream.llcas_cas_create)(options, &mut error);
            (upstream.llcas_cas_options_dispose)(options);
            assert!(
                !raw.is_null(),
                "llcas_cas_create: {}",
                take_error(upstream, error)
            );
            Self { upstream, raw }
        }
    }

    /// The action key, formed the way a real one is: the digest of a small
    /// object. Deterministic, so every phase derives the same key.
    fn key_digest(&self) -> Vec<u8> {
        let key_object = self.store_object(b"regression-cache-key-material", &[]);
        self.digest_of(key_object)
    }

    fn store_object(&self, data: &[u8], refs: &[llcas_objectid_t]) -> llcas_objectid_t {
        unsafe {
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let failed = (self.upstream.llcas_cas_store_object)(
                self.raw,
                llcas_data_t {
                    data: data.as_ptr() as *const _,
                    size: data.len(),
                },
                refs.as_ptr(),
                refs.len(),
                &mut id,
                &mut error,
            );
            assert!(
                !failed,
                "llcas_cas_store_object: {}",
                take_error(self.upstream, error)
            );
            id
        }
    }

    /// Copies the digest bytes out: the buffer the plugin returns belongs to the
    /// CAS handle and does not outlive it.
    fn digest_of(&self, id: llcas_objectid_t) -> Vec<u8> {
        unsafe {
            let digest = (self.upstream.llcas_objectid_get_digest)(self.raw, id);
            std::slice::from_raw_parts(digest.data, digest.size).to_vec()
        }
    }

    fn digest_string(&self, digest: &[u8]) -> String {
        unsafe {
            let mut printed: *mut c_char = ptr::null_mut();
            let mut error: *mut c_char = ptr::null_mut();
            let failed = (self.upstream.llcas_digest_print)(
                self.raw,
                llcas_digest_t {
                    data: digest.as_ptr(),
                    size: digest.len(),
                },
                &mut printed,
                &mut error,
            );
            assert!(
                !failed,
                "llcas_digest_print: {}",
                take_error(self.upstream, error)
            );
            let text = CStr::from_ptr(printed).to_string_lossy().into_owned();
            (self.upstream.llcas_string_dispose)(printed);
            text
        }
    }

    fn objectid_for(&self, digest: &[u8]) -> Option<llcas_objectid_t> {
        unsafe {
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let failed = (self.upstream.llcas_cas_get_objectid)(
                self.raw,
                llcas_digest_t {
                    data: digest.as_ptr(),
                    size: digest.len(),
                },
                &mut id,
                &mut error,
            );
            if failed {
                let _ = take_error(self.upstream, error);
                return None;
            }
            Some(id)
        }
    }

    fn contains(&self, id: llcas_objectid_t) -> llcas_lookup_result_t {
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let result = (self.upstream.llcas_cas_contains_object)(self.raw, id, false, &mut error);
            assert_ne!(
                result,
                LLCAS_LOOKUP_RESULT_ERROR,
                "llcas_cas_contains_object: {}",
                take_error(self.upstream, error)
            );
            result
        }
    }

    fn actioncache_put(&self, key: &[u8], value: llcas_objectid_t) {
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let failed = (self.upstream.llcas_actioncache_put_for_digest)(
                self.raw,
                llcas_digest_t {
                    data: key.as_ptr(),
                    size: key.len(),
                },
                value,
                false,
                &mut error,
            );
            assert!(
                !failed,
                "llcas_actioncache_put_for_digest: {}",
                take_error(self.upstream, error)
            );
        }
    }

    fn actioncache_get(&self, key: &[u8]) -> (llcas_lookup_result_t, llcas_objectid_t) {
        unsafe {
            let mut value = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let result = (self.upstream.llcas_actioncache_get_for_digest)(
                self.raw,
                llcas_digest_t {
                    data: key.as_ptr(),
                    size: key.len(),
                },
                &mut value,
                false,
                &mut error,
            );
            assert_ne!(
                result,
                LLCAS_LOOKUP_RESULT_ERROR,
                "llcas_actioncache_get_for_digest: {}",
                take_error(self.upstream, error)
            );
            (result, value)
        }
    }

    fn set_ondisk_size_limit(&self, limit: i64) {
        unsafe {
            let entry = self
                .upstream
                .llcas_cas_set_ondisk_size_limit
                .expect("checked when the upstream was loaded");
            let mut error: *mut c_char = ptr::null_mut();
            let failed = entry(self.raw, limit, &mut error);
            assert!(
                !failed,
                "llcas_cas_set_ondisk_size_limit: {}",
                take_error(self.upstream, error)
            );
        }
    }

    fn prune_ondisk_data(&self) {
        unsafe {
            let entry = self
                .upstream
                .llcas_cas_prune_ondisk_data
                .expect("checked when the upstream was loaded");
            let mut error: *mut c_char = ptr::null_mut();
            let failed = entry(self.raw, &mut error);
            assert!(
                !failed,
                "llcas_cas_prune_ondisk_data: {}",
                take_error(self.upstream, error)
            );
        }
    }
}

impl Drop for Cas {
    fn drop(&mut self) {
        unsafe { (self.upstream.llcas_cas_dispose)(self.raw) }
    }
}

/// Copies an upstream error string and releases it through the plugin's own
/// allocator, so the message can be reported without leaking it.
fn take_error(upstream: &Upstream, error: *mut c_char) -> String {
    if error.is_null() {
        return "<no error message>".into();
    }
    unsafe {
        let text = CStr::from_ptr(error).to_string_lossy().into_owned();
        (upstream.llcas_string_dispose)(error);
        text
    }
}

/// A store directory removed on drop, including when a test panics, so the
/// junk objects never outlive the run.
struct TempStore(PathBuf);

impl TempStore {
    fn new(label: &str) -> Self {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("system clock after the epoch")
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "tuist-cas-prune-rotation-{label}-{}-{unique}",
            std::process::id()
        ));
        std::fs::create_dir_all(&path).expect("create the temporary CAS store");
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempStore {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
