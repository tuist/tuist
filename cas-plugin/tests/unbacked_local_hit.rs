//! A local action-cache hit does not prove its value graph is present, and this
//! crate used to hand such a hit straight to the compiler -- the state behind
//! `error: CAS operation failed: missing object '0~...'`
//! (<https://github.com/tuist/tuist/issues/12245>), fatal on the clang lane and
//! permanent: it survives re-runs, fresh CI VMs and fresh DerivedData, because
//! the poisoned local association shadows the remote truth on every later get.
//!
//! These tests drive THIS crate's exported `llcas_*` surface (not Apple's dylib
//! directly -- that is `tests/upstream_prune_rotation.rs`) against a scripted
//! fake proxy on a unix socket, so both the local decision and the fall-through
//! to the remote are observable.
//!
//! The defect state is constructed directly rather than through a prune
//! rotation. Two ABI facts make that exact and cheap: `llcas_cas_get_objectid`
//! mints an id from a digest WITHOUT requiring the object, and
//! `llcas_actioncache_put_for_digest` does NOT validate that the value object
//! exists. So storing an object in a throwaway store to learn a valid digest and
//! then putting `key -> that digest` into a FRESH store reproduces "association
//! present, root absent" in a few lines, with no size limits, no rotation and no
//! directory surgery. `tests/upstream_prune_rotation.rs` separately establishes
//! that Apple's store can REACH that state on its own; these tests assert what
//! we do once we are in it.

use std::ffi::{c_char, c_void, CStr, CString};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

use tuist_cas_plugin::proxy_proto::{
    read_request, write_response, OP_RESOLVE, STATUS_HIT, STATUS_MISS,
};
use tuist_cas_plugin::types::*;
use tuist_cas_plugin::upstream_path;

// --- The behaviour under test --------------------------------------------------

/// The defect: the association survives, its root does not, and the get is the
/// only place that can notice before the compiler does.
#[test]
fn an_unbacked_local_hit_is_not_served_to_the_caller() {
    let Some(env) = Fixture::new("unbacked-sync") else { return };
    let (key, absent_value) = env.seed_unbacked_association();

    // Precondition: this is genuinely a local hit over an absent root.
    let id = env.cas.objectid_for(&absent_value);
    assert_eq!(
        env.cas.contains(id),
        LLCAS_LOOKUP_RESULT_NOTFOUND,
        "the value object must be absent for this test to mean anything"
    );

    env.proxy.answer_resolve_with_miss();
    let (result, _) = env.cas.actioncache_get(&key);

    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_NOTFOUND,
        "an association whose root is absent must not reach the caller as SUCCESS"
    );
    assert_eq!(
        env.proxy.resolves_for(&key),
        1,
        "the unbacked hit must FALL THROUGH to the remote, not short-circuit: a \
         resolve can recover entries fetch_object cannot name (snapshot window, \
         restarted proxy) and registers the whole graph in one round trip"
    );
}

/// The async entry point has its own upstream short-circuit that never reaches
/// `actioncache_get_impl`, so guarding only the sync path would leave the lane
/// the build system actually drives still broken.
#[test]
fn an_unbacked_local_hit_is_not_served_to_the_caller_asynchronously() {
    let Some(env) = Fixture::new("unbacked-async") else { return };
    let (key, _) = env.seed_unbacked_association();

    env.proxy.answer_resolve_with_miss();
    let (result, calls) = env.cas.actioncache_get_async(&key);

    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_NOTFOUND,
        "the async get must apply the same verification as the sync get"
    );
    assert_eq!(calls, 1, "the callback must fire exactly once");
    assert_eq!(env.proxy.resolves_for(&key), 1, "and fall through to the remote");
}

/// The regression that would cost the most: the guard must not turn ordinary
/// warm hits into misses.
#[test]
fn a_backed_local_hit_is_still_served_without_consulting_the_remote() {
    let Some(env) = Fixture::new("backed-sync") else { return };
    let key = env.cas.key_digest(b"backed-key");
    let value = env.cas.store_object(b"a value that is really here");
    env.cas.actioncache_put(&key, value).expect("seeding put");

    let (result, served) = env.cas.actioncache_get(&key);

    assert_eq!(result, LLCAS_LOOKUP_RESULT_SUCCESS);
    assert_eq!(
        env.cas.digest_of(served),
        env.cas.digest_of(value),
        "the served id must name the stored value"
    );
    assert_eq!(
        env.proxy.resolves_for(&key),
        0,
        "a backed local hit must stay purely local -- no proxy round trip"
    );
}

#[test]
fn a_backed_local_hit_is_still_served_asynchronously() {
    let Some(env) = Fixture::new("backed-async") else { return };
    let key = env.cas.key_digest(b"backed-key-async");
    let value = env.cas.store_object(b"a value that is really here, twice");
    env.cas.actioncache_put(&key, value).expect("seeding put");

    let (result, calls) = env.cas.actioncache_get_async(&key);

    assert_eq!(result, LLCAS_LOOKUP_RESULT_SUCCESS);
    assert_eq!(calls, 1);
    assert_eq!(env.proxy.resolves_for(&key), 0);
}

/// `p_value` is nullable in the ABI, and the verification needs an object id to
/// probe -- so the guard must not depend on the caller supplying the slot.
#[test]
fn a_null_out_parameter_is_handled_on_both_verdicts() {
    let Some(env) = Fixture::new("null-out") else { return };

    let backed_key = env.cas.key_digest(b"null-out-backed");
    let value = env.cas.store_object(b"present value");
    env.cas.actioncache_put(&backed_key, value).expect("seeding put");
    assert_eq!(
        env.cas.actioncache_get_without_out_param(&backed_key),
        LLCAS_LOOKUP_RESULT_SUCCESS
    );

    let (unbacked_key, _) = env.seed_unbacked_association();
    env.proxy.answer_resolve_with_miss();
    assert_eq!(
        env.cas.actioncache_get_without_out_param(&unbacked_key),
        LLCAS_LOOKUP_RESULT_NOTFOUND
    );
}

/// `globally = true` must not mask the condition: the point is to detect that the
/// LOCAL graph is gone, and a healthy remote answers yes to a global probe.
#[test]
fn a_global_lookup_still_verifies_locally() {
    let Some(env) = Fixture::new("globally") else { return };
    let (key, _) = env.seed_unbacked_association();

    env.proxy.answer_resolve_with_miss();
    let (result, _) = env.cas.actioncache_get_globally(&key);

    assert_eq!(result, LLCAS_LOOKUP_RESULT_NOTFOUND);
}

/// The two ABI facts the defect state is built from. If a future toolchain starts
/// validating puts, this fails loudly here rather than silently invalidating
/// every test above.
#[test]
fn a_put_for_a_never_stored_value_succeeds_and_leaves_the_root_absent() {
    let Some(env) = Fixture::new("preconditions") else { return };
    let absent = env.absent_value_digest();

    let id = env.cas.objectid_for(&absent);
    assert_eq!(
        env.cas.contains(id),
        LLCAS_LOOKUP_RESULT_NOTFOUND,
        "get_objectid must mint an id without requiring the object"
    );

    let key = env.cas.key_digest(b"precondition-key");
    env.cas
        .actioncache_put(&key, id)
        .expect("put_for_digest must not validate that the value object exists");
}

// --- The failure the verification makes reachable ------------------------------

/// The store refuses to change an association, and the verification deliberately
/// drives recompiles on exactly the keys whose associations are stale. Surfacing
/// the refusal would trade a `missing object` build failure for a `cache poisoned`
/// one, which is no better.
#[test]
fn re_putting_a_key_with_a_different_value_is_not_a_failure() {
    let Some(env) = Fixture::new("poisoned-put") else { return };
    let key = env.cas.key_digest(b"poisoned-put");
    let original = env.cas.store_object(b"the value the store already has");
    let recompiled = env.cas.store_object(b"what a non-reproducible recompile made");
    env.cas.actioncache_put(&key, original).expect("seeding put");

    env.cas
        .actioncache_put(&key, recompiled)
        .expect("a refused re-put must not reach the build system as a failure");

    let (result, served) = env.cas.actioncache_get(&key);
    assert_eq!(result, LLCAS_LOOKUP_RESULT_SUCCESS);
    assert_eq!(
        env.cas.digest_of(served),
        env.cas.digest_of(original),
        "reporting success must not be mistaken for having CHANGED the association \
         -- the original survives, which is why the key stays degraded until the \
         store generation rolls"
    );
}

#[test]
fn re_putting_a_key_with_a_different_value_is_not_a_failure_asynchronously() {
    let Some(env) = Fixture::new("poisoned-put-async") else { return };
    let key = env.cas.key_digest(b"poisoned-put-async");
    let original = env.cas.store_object(b"the value the store already has");
    let recompiled = env.cas.store_object(b"what a non-reproducible recompile made");
    env.cas.actioncache_put(&key, original).expect("seeding put");

    let (failed, calls, error) = env.cas.actioncache_put_async(&key, recompiled);

    assert!(!failed, "a refused re-put must be reported as success");
    assert_eq!(calls, 1, "the callback must fire exactly once");
    assert!(error.is_empty(), "and must carry no error string: {error}");
}

/// The hazard the verification CREATES, and the reason it cannot ship without the
/// downgrade above: a stale association naming X falls through, the remote answers
/// with a different digest Y, and caching that association is refused. Failing the
/// get there would be strictly worse than the bug being fixed.
#[test]
fn a_remote_value_that_contradicts_a_stale_association_is_still_served() {
    let Some(env) = Fixture::new("contradicting-remote") else { return };
    let (key, _) = env.seed_unbacked_association();
    let remote_value = env.cas.digest_of(env.cas.store_object(b"what the remote actually holds"));
    env.proxy.answer_resolve_with_hit(&remote_value);

    let (result, served) = env.cas.actioncache_get(&key);

    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_SUCCESS,
        "the resolve succeeded; only caching its association was refused"
    );
    assert_eq!(
        env.cas.digest_of(served),
        remote_value,
        "and the value served must be the one the remote resolved"
    );
}

/// Not an assertion -- the record of what the verification costs, and the reason
/// there is no memoization of the verdict behind it.
///
/// Measured on an M-series Mac with Xcode 26.3, release profile: a served local
/// hit is ~50ns end to end, of which the probe is ~12ns. At the ~13.5k hits of a
/// warm runner build that is a sixth of a millisecond for the whole build, so
/// caching the verdict would buy nothing measurable while putting a mutex on the
/// serial task-setup path and introducing a stale-positive window (another
/// process pruning the shared store does not clear this process's cache).
///
/// Re-run with `cargo test --release -- --ignored --nocapture probe_cost` if the
/// verification ever grows beyond a single root probe.
#[test]
#[ignore = "a measurement, not an assertion"]
fn probe_cost() {
    let Some(env) = Fixture::new("probe-cost") else { return };
    let key = env.cas.key_digest(b"probe-cost");
    let value = env.cas.store_object(b"a value that is really here");
    env.cas.actioncache_put(&key, value).expect("seeding put");
    let id = env.cas.objectid_for(&env.cas.digest_of(value));

    const ITERATIONS: u32 = 20_000;
    for _ in 0..1_000 {
        let _ = env.cas.actioncache_get(&key);
    }

    let started = std::time::Instant::now();
    for _ in 0..ITERATIONS {
        let _ = env.cas.actioncache_get(&key);
    }
    let served = started.elapsed();

    let started = std::time::Instant::now();
    for _ in 0..ITERATIONS {
        let _ = env.cas.contains(id);
    }
    let probe = started.elapsed();

    eprintln!("verified get: {:?}/op", served / ITERATIONS);
    eprintln!("probe alone:  {:?}/op", probe / ITERATIONS);
}

// --- Fixture -------------------------------------------------------------------

/// A plugin CAS over a fresh store, wired to a scripted proxy, plus the
/// throwaway store used to mint digests for objects the real store never holds.
struct Fixture {
    cas: PluginCas,
    proxy: FakeProxy,
    _store: TempDir,
    _socket_dir: TempDir,
    // Held for the whole test: see `serialize_tests`.
    _serialized: MutexGuard<'static, ()>,
}

impl Fixture {
    /// `None` when Apple's plugin is unavailable (non-macOS, or no Xcode), which
    /// the caller turns into a skip -- there is nothing to wrap and nothing the
    /// assertions would mean.
    fn new(label: &str) -> Option<Self> {
        // Taken BEFORE anything reads the environment, and held for the whole
        // test. `llcas_cas_create` learns its proxy socket from
        // `TUIST_CAS_PROXY_SOCKET`, and cargo runs tests as parallel threads of
        // one process, where a `set_var` racing another thread's `var` is a data
        // race that segfaults rather than misbehaving politely.
        let serialized = serialize_tests();
        if !Path::new(&upstream_path()).exists() {
            eprintln!("skipping {label}: Apple's libToolchainCASPlugin is unavailable");
            return None;
        }
        let store = TempDir::new(label);
        // Sockets live under /tmp, not the store: a unix socket path is capped
        // near 104 bytes and macOS's per-user temp dir is long enough to blow it.
        let socket_dir = TempDir::in_tmp(label);
        let proxy = FakeProxy::listening(&socket_dir.path().join("proxy.sock"));
        std::env::set_var("TUIST_CAS_PROXY_SOCKET", proxy.socket());
        // Publishing is irrelevant here and would spool records into the store
        // on every put; read behaviour is unaffected by it.
        std::env::set_var("TUIST_CAS_UPLOAD", "false");
        let cas = PluginCas::open(store.path());
        Some(Self {
            cas,
            proxy,
            _store: store,
            _socket_dir: socket_dir,
            _serialized: serialized,
        })
    }

    /// A digest that is well-formed for the store's hash schema but names an
    /// object this store has never held: minted in a throwaway store that is then
    /// discarded. Content addressing makes the digest valid in both.
    fn absent_value_digest(&self) -> Vec<u8> {
        let elsewhere = TempDir::new("elsewhere");
        let other = PluginCas::open(elsewhere.path());
        let id = other.store_object(b"a value that exists only somewhere else");
        other.digest_of(id)
    }

    /// The defect state: `key -> value` recorded in the store, with the value's
    /// object never stored there.
    fn seed_unbacked_association(&self) -> (Vec<u8>, Vec<u8>) {
        let value_digest = self.absent_value_digest();
        let key = self.cas.key_digest(&value_digest);
        let value_id = self.cas.objectid_for(&value_digest);
        self.cas
            .actioncache_put(&key, value_id)
            .expect("seeding the dangling association");
        (key, value_digest)
    }
}

// --- The plugin under test -----------------------------------------------------

/// One test at a time. `llcas_cas_create` reads `TUIST_CAS_PROXY_SOCKET` from the
/// environment and cargo runs tests as parallel threads of one process, where a
/// `set_var` racing another thread's `var` is a data race that takes the whole
/// binary down with SIGSEGV. Taken as the first thing each test does, before any
/// environment read, and held until it ends. Poisoning is ignored: a panicking
/// test has already failed and must not cascade into the rest.
fn serialize_tests() -> MutexGuard<'static, ()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(())).lock().unwrap_or_else(|e| e.into_inner())
}

struct PluginCas {
    raw: llcas_cas_t,
}

impl PluginCas {
    fn open(store: &Path) -> Self {
        unsafe {
            let options = tuist_cas_plugin::llcas_cas_options_create();
            tuist_cas_plugin::llcas_cas_options_set_client_version(
                options,
                LLCAS_VERSION_MAJOR,
                LLCAS_VERSION_MINOR,
            );
            let path = CString::new(store.to_str().expect("utf-8 store path")).unwrap();
            tuist_cas_plugin::llcas_cas_options_set_ondisk_path(options, path.as_ptr());
            let mut error: *mut c_char = ptr::null_mut();
            let raw = tuist_cas_plugin::llcas_cas_create(options, &mut error);
            tuist_cas_plugin::llcas_cas_options_dispose(options);
            assert!(!raw.is_null(), "llcas_cas_create: {}", take_error(error));
            Self { raw }
        }
    }

    /// An action key formed the way a real one is: the digest of a small object.
    fn key_digest(&self, material: &[u8]) -> Vec<u8> {
        let mut object = b"cache-key-material:".to_vec();
        object.extend_from_slice(material);
        self.digest_of(self.store_object(&object))
    }

    fn store_object(&self, data: &[u8]) -> llcas_objectid_t {
        unsafe {
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let failed = tuist_cas_plugin::llcas_cas_store_object(
                self.raw,
                llcas_data_t { data: data.as_ptr() as *const c_void, size: data.len() },
                ptr::null(),
                0,
                &mut id,
                &mut error,
            );
            assert!(!failed, "llcas_cas_store_object: {}", take_error(error));
            id
        }
    }

    /// Copies the bytes out: the buffer belongs to the CAS handle.
    fn digest_of(&self, id: llcas_objectid_t) -> Vec<u8> {
        unsafe {
            let digest = tuist_cas_plugin::llcas_objectid_get_digest(self.raw, id);
            std::slice::from_raw_parts(digest.data, digest.size).to_vec()
        }
    }

    fn objectid_for(&self, digest: &[u8]) -> llcas_objectid_t {
        unsafe {
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let failed = tuist_cas_plugin::llcas_cas_get_objectid(
                self.raw,
                llcas_digest_t { data: digest.as_ptr(), size: digest.len() },
                &mut id,
                &mut error,
            );
            assert!(!failed, "llcas_cas_get_objectid: {}", take_error(error));
            id
        }
    }

    fn contains(&self, id: llcas_objectid_t) -> llcas_lookup_result_t {
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let result =
                tuist_cas_plugin::llcas_cas_contains_object(self.raw, id, false, &mut error);
            assert_ne!(
                result,
                LLCAS_LOOKUP_RESULT_ERROR,
                "llcas_cas_contains_object: {}",
                take_error(error)
            );
            result
        }
    }

    fn actioncache_put(&self, key: &[u8], value: llcas_objectid_t) -> Result<(), String> {
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let failed = tuist_cas_plugin::llcas_actioncache_put_for_digest(
                self.raw,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                value,
                false,
                &mut error,
            );
            let message = take_error(error);
            if failed {
                Err(message)
            } else {
                assert!(message.is_empty(), "a successful put must not report an error");
                Ok(())
            }
        }
    }

    fn actioncache_get(&self, key: &[u8]) -> (llcas_lookup_result_t, llcas_objectid_t) {
        self.get(key, false)
    }

    fn actioncache_get_globally(&self, key: &[u8]) -> (llcas_lookup_result_t, llcas_objectid_t) {
        self.get(key, true)
    }

    fn get(&self, key: &[u8], globally: bool) -> (llcas_lookup_result_t, llcas_objectid_t) {
        unsafe {
            let mut value = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let result = tuist_cas_plugin::llcas_actioncache_get_for_digest(
                self.raw,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                &mut value,
                globally,
                &mut error,
            );
            assert_ne!(
                result,
                LLCAS_LOOKUP_RESULT_ERROR,
                "llcas_actioncache_get_for_digest: {}",
                take_error(error)
            );
            (result, value)
        }
    }

    fn actioncache_get_without_out_param(&self, key: &[u8]) -> llcas_lookup_result_t {
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let result = tuist_cas_plugin::llcas_actioncache_get_for_digest(
                self.raw,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                ptr::null_mut(),
                false,
                &mut error,
            );
            assert_ne!(
                result,
                LLCAS_LOOKUP_RESULT_ERROR,
                "llcas_actioncache_get_for_digest: {}",
                take_error(error)
            );
            result
        }
    }

    /// Returns the callback's verdict and how many times it fired -- exactly once
    /// is part of the contract, and a build waits forever if it is not.
    fn actioncache_get_async(&self, key: &[u8]) -> (llcas_lookup_result_t, usize) {
        unsafe extern "C" fn callback(
            ctx: *mut c_void,
            result: llcas_lookup_result_t,
            _value: llcas_objectid_t,
            error: *mut c_char,
        ) {
            let slot = &mut *(ctx as *mut AsyncGet);
            slot.result = result;
            slot.calls += 1;
            if !error.is_null() {
                tuist_cas_plugin::llcas_string_dispose(error);
            }
        }

        let mut slot = AsyncGet { result: LLCAS_LOOKUP_RESULT_ERROR, calls: 0 };
        unsafe {
            tuist_cas_plugin::llcas_actioncache_get_for_digest_async(
                self.raw,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                false,
                &mut slot as *mut AsyncGet as *mut c_void,
                callback,
                ptr::null_mut(),
            );
        }
        (slot.result, slot.calls)
    }

    /// Returns the verdict, how many times the callback fired, and any error it
    /// carried.
    fn actioncache_put_async(&self, key: &[u8], value: llcas_objectid_t) -> (bool, usize, String) {
        unsafe extern "C" fn callback(ctx: *mut c_void, failed: bool, error: *mut c_char) {
            let slot = &mut *(ctx as *mut AsyncPut);
            slot.failed = failed;
            slot.calls += 1;
            slot.error = take_error(error);
        }

        let mut slot = AsyncPut { failed: true, calls: 0, error: String::new() };
        unsafe {
            tuist_cas_plugin::llcas_actioncache_put_for_digest_async(
                self.raw,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                value,
                false,
                &mut slot as *mut AsyncPut as *mut c_void,
                callback,
                ptr::null_mut(),
            );
        }
        (slot.failed, slot.calls, slot.error)
    }
}

struct AsyncGet {
    result: llcas_lookup_result_t,
    calls: usize,
}

struct AsyncPut {
    failed: bool,
    calls: usize,
    error: String,
}

impl Drop for PluginCas {
    fn drop(&mut self) {
        unsafe { tuist_cas_plugin::llcas_cas_dispose(self.raw) };
    }
}

/// Adopts and frees a string the plugin allocated. Empty when there was none.
fn take_error(error: *mut c_char) -> String {
    if error.is_null() {
        return String::new();
    }
    unsafe {
        let text = CStr::from_ptr(error).to_string_lossy().into_owned();
        tuist_cas_plugin::llcas_string_dispose(error);
        text
    }
}

// --- A scripted proxy ----------------------------------------------------------

/// Answers the plugin's unix-socket requests with whatever the test scripts, and
/// records what it was asked. Without it a fall-through would be
/// indistinguishable from a short-circuit: both end in NOTFOUND.
struct FakeProxy {
    socket: PathBuf,
    seen: Arc<Mutex<Vec<(u8, Vec<u8>)>>>,
    resolve_answer: Arc<Mutex<Option<Vec<u8>>>>,
    stopping: Arc<AtomicBool>,
}

impl FakeProxy {
    fn listening(socket: &Path) -> Self {
        let listener = UnixListener::bind(socket).expect("bind fake proxy socket");
        let seen: Arc<Mutex<Vec<(u8, Vec<u8>)>>> = Arc::new(Mutex::new(Vec::new()));
        let resolve_answer: Arc<Mutex<Option<Vec<u8>>>> = Arc::new(Mutex::new(None));
        let stopping = Arc::new(AtomicBool::new(false));

        let worker = (seen.clone(), resolve_answer.clone(), stopping.clone());
        std::thread::spawn(move || {
            let (seen, resolve_answer, stopping) = worker;
            for stream in listener.incoming() {
                if stopping.load(Ordering::SeqCst) {
                    return;
                }
                let Ok(mut stream) = stream else { return };
                let Ok(request) = read_request(&mut stream) else { continue };
                seen.lock().unwrap().push((request.op, request.payload.clone()));
                let (status, body) = match request.op {
                    OP_RESOLVE => match resolve_answer.lock().unwrap().clone() {
                        Some(value) => (STATUS_HIT, value),
                        None => (STATUS_MISS, Vec::new()),
                    },
                    // Everything else (publish, invalidate) is acknowledged.
                    _ => (STATUS_HIT, Vec::new()),
                };
                let _ = write_response(&mut stream, status, &body);
            }
        });

        Self { socket: socket.to_path_buf(), seen, resolve_answer, stopping }
    }

    fn socket(&self) -> &Path {
        &self.socket
    }

    fn answer_resolve_with_miss(&self) {
        *self.resolve_answer.lock().unwrap() = None;
    }

    fn answer_resolve_with_hit(&self, value_digest: &[u8]) {
        *self.resolve_answer.lock().unwrap() = Some(value_digest.to_vec());
    }

    fn resolves_for(&self, key: &[u8]) -> usize {
        self.seen
            .lock()
            .unwrap()
            .iter()
            .filter(|(op, payload)| *op == OP_RESOLVE && payload == key)
            .count()
    }
}

impl Drop for FakeProxy {
    fn drop(&mut self) {
        self.stopping.store(true, Ordering::SeqCst);
        // Unblock the accept so the thread observes the flag and returns.
        let _ = UnixStream::connect(&self.socket);
        let _ = std::fs::remove_file(&self.socket);
    }
}

// --- Temporary directories -----------------------------------------------------

struct TempDir(PathBuf);

impl TempDir {
    fn new(label: &str) -> Self {
        Self::under(std::env::temp_dir(), label)
    }

    /// `/tmp` rather than the per-user temp dir, for paths that must stay short
    /// (unix sockets).
    fn in_tmp(label: &str) -> Self {
        Self::under(PathBuf::from("/tmp"), label)
    }

    fn under(root: PathBuf, label: &str) -> Self {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let path = root.join(format!(
            "tuist-cas-{label}-{}-{}",
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
