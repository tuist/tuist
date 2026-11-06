//! When the build system runs its own remote cache queries (the CAS is created
//! with `remote-service-path`), swift-build asks every key twice: a local-only
//! lookup (`globally = false`) from the materialize task's setup on llbuild's
//! single scheduling thread, then, for a local miss, a separate key query task
//! (`globally = true`) that runs concurrently with the rest of the build. A
//! local-only lookup that waits on the remote serializes every key behind one
//! round trip and leaves the build idle while it does.
//!
//! These drive THIS crate's exported `llcas_*` surface against a scripted fake
//! proxy, which records the resolves the plugin asks for.

use std::ffi::{c_char, c_void, CStr, CString};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

use tuist_cas_plugin::proxy_proto::{
    read_request, write_response, OP_PREPARE_ACTION, OP_RESOLVE, STATUS_HIT, STATUS_MISS,
};
use tuist_cas_plugin::types::*;
use tuist_cas_plugin::upstream_path;

#[test]
fn a_local_only_lookup_does_not_ask_the_remote_when_the_build_system_queries_it() {
    let Some(env) = Fixture::new("local-only", Remote::QueriedByBuildSystem) else { return };
    let key = env.cas.key_digest(b"local-only");

    assert_eq!(env.cas.get(&key, false), LLCAS_LOOKUP_RESULT_NOTFOUND);
    assert_eq!(
        env.proxy.resolves_for(&key),
        0,
        "the build system's key query asks the remote; a local-only lookup must not wait on it"
    );
}

#[test]
fn an_asynchronous_local_only_lookup_does_not_ask_the_remote_either() {
    let Some(env) = Fixture::new("local-only-async", Remote::QueriedByBuildSystem) else { return };
    let key = env.cas.key_digest(b"local-only-async");

    assert_eq!(env.cas.get_async(&key, false), (LLCAS_LOOKUP_RESULT_NOTFOUND, 1));
    assert_eq!(env.proxy.resolves_for(&key), 0);
}

#[test]
fn the_build_systems_global_query_reads_through_and_later_local_lookups_hit() {
    let Some(env) = Fixture::new("global-query", Remote::QueriedByBuildSystem) else { return };
    let key = env.cas.key_digest(b"global-query");
    let value = env.absent_value_digest();
    env.proxy.answer_resolve_with_hit(&value);
    let store = env.store.path().to_path_buf();
    *env.proxy.materialize.lock().unwrap() = Some(Box::new(move || {
        PluginCas::open(&store, Remote::Unconfigured).store_object(VALUE_CONTENT);
    }));

    assert_eq!(env.cas.get(&key, true), LLCAS_LOOKUP_RESULT_SUCCESS);
    assert_eq!(env.proxy.resolves_for(&key), 1);
    assert_eq!(env.proxy.preparations_for(&value), 1);

    assert_eq!(
        env.cas.get(&key, false),
        LLCAS_LOOKUP_RESULT_SUCCESS,
        "the global query records the association, so the dependent compile's local lookup hits"
    );
    assert_eq!(env.proxy.resolves_for(&key), 1);
}

#[test]
fn a_local_only_lookup_still_reads_through_when_nothing_else_queries_the_remote() {
    let Some(env) = Fixture::new("read-through", Remote::Unconfigured) else { return };
    let key = env.cas.key_digest(b"read-through");

    assert_eq!(env.cas.get(&key, false), LLCAS_LOOKUP_RESULT_NOTFOUND);
    assert_eq!(
        env.proxy.resolves_for(&key),
        1,
        "without the build system's key queries, this lookup is the only way a remote entry is found"
    );
    assert_eq!(env.cas.get_async(&key, false), (LLCAS_LOOKUP_RESULT_NOTFOUND, 1));
    assert_eq!(env.proxy.resolves_for(&key), 2);
}

// --- Fixture -------------------------------------------------------------------

const VALUE_CONTENT: &[u8] = b"a value that exists only on the remote";

#[derive(Clone, Copy)]
enum Remote {
    /// The build system queries the remote itself: `remote-service-path` is set.
    QueriedByBuildSystem,
    Unconfigured,
}

struct Fixture {
    cas: PluginCas,
    proxy: FakeProxy,
    store: TempDir,
    _socket_dir: TempDir,
    _serialized: MutexGuard<'static, ()>,
}

impl Fixture {
    fn new(label: &str, remote: Remote) -> Option<Self> {
        // Taken before anything reads the environment: `llcas_cas_create` reads
        // `TUIST_CAS_PROXY_SOCKET`, and cargo runs tests as threads of one process.
        let serialized = serialize_tests();
        if !Path::new(&upstream_path()).exists() {
            eprintln!("skipping {label}: Apple's libToolchainCASPlugin is unavailable");
            return None;
        }
        let store = TempDir::under(std::env::temp_dir(), label);
        // Unix socket paths are capped near 104 bytes.
        let socket_dir = TempDir::under(PathBuf::from("/tmp"), label);
        let proxy = FakeProxy::listening(&socket_dir.path().join("proxy.sock"));
        std::env::set_var("TUIST_CAS_PROXY_SOCKET", &proxy.socket);
        std::env::set_var("TUIST_CAS_UPLOAD", "false");
        let cas = PluginCas::open(store.path(), remote);
        Some(Self { cas, proxy, store, _socket_dir: socket_dir, _serialized: serialized })
    }

    /// A digest valid for the store's schema whose object the store never holds.
    fn absent_value_digest(&self) -> Vec<u8> {
        let elsewhere = TempDir::under(std::env::temp_dir(), "elsewhere");
        let other = PluginCas::open(elsewhere.path(), Remote::Unconfigured);
        other.digest_of(other.store_object(VALUE_CONTENT))
    }
}

fn serialize_tests() -> MutexGuard<'static, ()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(())).lock().unwrap_or_else(|e| e.into_inner())
}

struct PluginCas {
    raw: llcas_cas_t,
}

impl PluginCas {
    fn open(store: &Path, remote: Remote) -> Self {
        unsafe {
            let options = tuist_cas_plugin::llcas_cas_options_create();
            tuist_cas_plugin::llcas_cas_options_set_client_version(
                options,
                LLCAS_VERSION_MAJOR,
                LLCAS_VERSION_MINOR,
            );
            let path = CString::new(store.to_str().expect("utf-8 store path")).unwrap();
            tuist_cas_plugin::llcas_cas_options_set_ondisk_path(options, path.as_ptr());
            if let Remote::QueriedByBuildSystem = remote {
                let name = CString::new("remote-service-path").unwrap();
                let value = CString::new("/tmp/build-system-remote.sock").unwrap();
                let mut error: *mut c_char = ptr::null_mut();
                tuist_cas_plugin::llcas_cas_options_set_option(
                    options,
                    name.as_ptr(),
                    value.as_ptr(),
                    &mut error,
                );
            }
            let mut error: *mut c_char = ptr::null_mut();
            let raw = tuist_cas_plugin::llcas_cas_create(options, &mut error);
            tuist_cas_plugin::llcas_cas_options_dispose(options);
            assert!(!raw.is_null(), "llcas_cas_create: {}", take_error(error));
            Self { raw }
        }
    }

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

    fn digest_of(&self, id: llcas_objectid_t) -> Vec<u8> {
        unsafe {
            let digest = tuist_cas_plugin::llcas_objectid_get_digest(self.raw, id);
            std::slice::from_raw_parts(digest.data, digest.size).to_vec()
        }
    }

    fn get(&self, key: &[u8], globally: bool) -> llcas_lookup_result_t {
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
            assert_ne!(result, LLCAS_LOOKUP_RESULT_ERROR, "get: {}", take_error(error));
            result
        }
    }

    /// The verdict and how many times the callback fired.
    fn get_async(&self, key: &[u8], globally: bool) -> (llcas_lookup_result_t, usize) {
        unsafe extern "C" fn callback(
            ctx: *mut c_void,
            result: llcas_lookup_result_t,
            _value: llcas_objectid_t,
            error: *mut c_char,
        ) {
            let slot = &mut *(ctx as *mut (llcas_lookup_result_t, usize));
            slot.0 = result;
            slot.1 += 1;
            take_error(error);
        }

        let mut slot: (llcas_lookup_result_t, usize) = (LLCAS_LOOKUP_RESULT_ERROR, 0);
        unsafe {
            tuist_cas_plugin::llcas_actioncache_get_for_digest_async(
                self.raw,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                globally,
                &mut slot as *mut (llcas_lookup_result_t, usize) as *mut c_void,
                callback,
                ptr::null_mut(),
            );
        }
        slot
    }
}

impl Drop for PluginCas {
    fn drop(&mut self) {
        unsafe { tuist_cas_plugin::llcas_cas_dispose(self.raw) };
    }
}

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

type MaterializeOnRequest = Arc<Mutex<Option<Box<dyn FnOnce() + Send>>>>;

/// Answers RESOLVE with the scripted value and PREPARE_ACTION by running the
/// scripted materialization, and records every request it receives.
struct FakeProxy {
    socket: PathBuf,
    seen: Arc<Mutex<Vec<(u8, Vec<u8>)>>>,
    resolve_answer: Arc<Mutex<Option<Vec<u8>>>>,
    materialize: MaterializeOnRequest,
    stopping: Arc<AtomicBool>,
}

impl FakeProxy {
    fn listening(socket: &Path) -> Self {
        let listener = UnixListener::bind(socket).expect("bind fake proxy socket");
        let proxy = Self {
            socket: socket.to_path_buf(),
            seen: Arc::default(),
            resolve_answer: Arc::default(),
            materialize: Arc::default(),
            stopping: Arc::default(),
        };
        let (seen, resolve_answer, materialize, stopping) = (
            proxy.seen.clone(),
            proxy.resolve_answer.clone(),
            proxy.materialize.clone(),
            proxy.stopping.clone(),
        );
        std::thread::spawn(move || {
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
                    OP_PREPARE_ACTION => match materialize.lock().unwrap().take() {
                        Some(prepare) => {
                            prepare();
                            (STATUS_HIT, Vec::new())
                        }
                        None => (STATUS_MISS, Vec::new()),
                    },
                    _ => (STATUS_MISS, Vec::new()),
                };
                let _ = write_response(&mut stream, status, &body);
            }
        });
        proxy
    }

    fn answer_resolve_with_hit(&self, value_digest: &[u8]) {
        *self.resolve_answer.lock().unwrap() = Some(value_digest.to_vec());
    }

    fn count(&self, op: u8, payload: &[u8]) -> usize {
        self.seen
            .lock()
            .unwrap()
            .iter()
            .filter(|(seen_op, seen_payload)| *seen_op == op && seen_payload == payload)
            .count()
    }

    fn resolves_for(&self, key: &[u8]) -> usize {
        self.count(OP_RESOLVE, key)
    }

    fn preparations_for(&self, digest: &[u8]) -> usize {
        self.count(OP_PREPARE_ACTION, digest)
    }
}

impl Drop for FakeProxy {
    fn drop(&mut self) {
        self.stopping.store(true, Ordering::SeqCst);
        let _ = UnixStream::connect(&self.socket);
        let _ = std::fs::remove_file(&self.socket);
    }
}

struct TempDir(PathBuf);

impl TempDir {
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
