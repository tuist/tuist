//! A proxy the plugin cannot reach was visible only in `TUIST_CAS_LOG`: every
//! failed request degrades to a miss, so a build with no remote cache looked exactly
//! like a build with a cold one. The plugin now records the failure beside the proxy
//! socket, where the CLI looks after a build, and warns once in the build output.
//!
//! These drive the exported `llcas_*` surface against a socket nothing listens on,
//! with a proxy that answers as the control: a miss is a legitimate answer from a
//! cache and must never be recorded as a failure.

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

#[test]
fn a_lookup_the_proxy_cannot_answer_is_recorded_beside_its_socket() {
    let Some(env) = Fixture::new("lookup", Proxy::Absent) else {
        return;
    };
    let key = env.cas.key_digest(b"lookup");
    let started_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64;

    let result = env.cas.actioncache_get(&key);

    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_NOTFOUND,
        "an unreachable proxy must still degrade to a miss, never fail the lookup"
    );
    let record = env
        .record()
        .expect("the failure must be recorded beside the socket");
    assert_eq!(record["socket"], env.socket().to_str().unwrap());
    assert!(
        record["error"]
            .as_str()
            .unwrap_or_default()
            .contains("proxy connect"),
        "the record must carry the failure the build hit: {record}"
    );
    assert!(
        record["failed_at_ms"]
            .as_u64()
            .is_some_and(|failed_at| failed_at >= started_ms),
        "the record must say when the build hit the failure: {record}"
    );
}

/// The path swift-frontend takes under swift-build, which disables replay in the
/// frontend: it never resolves, so a publication is the only proxy request it makes.
#[test]
fn a_publication_the_proxy_cannot_take_is_recorded() {
    let Some(env) = Fixture::new("publish", Proxy::Absent) else {
        return;
    };
    let value = env.cas.store_object(b"a compiled output");
    let key = env.cas.key_digest(b"publish");

    env.cas
        .actioncache_put(&key, value)
        .expect("the local put succeeds whatever the proxy does");

    assert!(
        env.record().is_some(),
        "a publication that never reached the proxy must be recorded"
    );
}

#[test]
fn a_proxy_that_answers_leaves_no_record() {
    let Some(env) = Fixture::new("healthy", Proxy::AnsweringMisses) else {
        return;
    };
    let key = env.cas.key_digest(b"healthy");
    let value = env.cas.store_object(b"a compiled output");

    assert_eq!(env.cas.actioncache_get(&key), LLCAS_LOOKUP_RESULT_NOTFOUND);
    env.cas.actioncache_put(&key, value).expect("local put");

    assert!(env.record().is_none(), "a miss is an answer, not a failure");
}

// --- Fixture -------------------------------------------------------------------

const RECORD_DIRECTORY: &str = "cas-proxy-failures";

enum Proxy {
    Absent,
    AnsweringMisses,
}

struct Fixture {
    cas: PluginCas,
    _proxy: Option<FakeProxy>,
    socket_dir: TempDir,
    _store: TempDir,
    _serialized: MutexGuard<'static, ()>,
}

impl Fixture {
    fn new(label: &str, proxy: Proxy) -> Option<Self> {
        let serialized = serialize_tests();
        if !Path::new(&upstream_path()).exists() {
            eprintln!("skipping {label}: Apple's libToolchainCASPlugin is unavailable");
            return None;
        }
        let store = TempDir::new(label);
        // A unix socket path is capped near 104 bytes, which macOS's per-user temp
        // dir can exceed on its own.
        let socket_dir = TempDir::in_tmp(label);
        let socket = socket_dir.path().join("proxy.sock");
        let proxy = match proxy {
            Proxy::Absent => None,
            Proxy::AnsweringMisses => Some(FakeProxy::listening(&socket)),
        };
        std::env::set_var("TUIST_CAS_PROXY_SOCKET", &socket);
        std::env::set_var("TUIST_CAS_UPLOAD", "true");
        let cas = PluginCas::open(store.path());
        Some(Self {
            cas,
            _proxy: proxy,
            socket_dir,
            _store: store,
            _serialized: serialized,
        })
    }

    fn socket(&self) -> PathBuf {
        self.socket_dir.path().join("proxy.sock")
    }

    fn record(&self) -> Option<serde_json::Value> {
        let directory = self.socket_dir.path().join(RECORD_DIRECTORY);
        let mut records: Vec<PathBuf> = std::fs::read_dir(&directory)
            .ok()?
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| {
                path.extension()
                    .is_some_and(|extension| extension == "json")
            })
            .collect();
        assert!(
            records.len() <= 1,
            "one process leaves one record: {records:?}"
        );
        let bytes = std::fs::read(records.pop()?).ok()?;
        Some(serde_json::from_slice(&bytes).expect("the record is JSON"))
    }
}

/// `llcas_cas_create` reads its socket from the environment, and cargo runs a file's
/// tests as threads of one process, where a `set_var` racing a `var` is a data race.
fn serialize_tests() -> MutexGuard<'static, ()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
        .lock()
        .unwrap_or_else(|e| e.into_inner())
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

    fn key_digest(&self, material: &[u8]) -> Vec<u8> {
        let mut object = b"cache-key-material:".to_vec();
        object.extend_from_slice(material);
        let id = self.store_object(&object);
        unsafe {
            let digest = tuist_cas_plugin::llcas_objectid_get_digest(self.raw, id);
            std::slice::from_raw_parts(digest.data, digest.size).to_vec()
        }
    }

    fn store_object(&self, data: &[u8]) -> llcas_objectid_t {
        unsafe {
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let failed = tuist_cas_plugin::llcas_cas_store_object(
                self.raw,
                llcas_data_t {
                    data: data.as_ptr() as *const c_void,
                    size: data.len(),
                },
                ptr::null(),
                0,
                &mut id,
                &mut error,
            );
            assert!(!failed, "llcas_cas_store_object: {}", take_error(error));
            id
        }
    }

    fn actioncache_get(&self, key: &[u8]) -> llcas_lookup_result_t {
        unsafe {
            let mut value = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let result = tuist_cas_plugin::llcas_actioncache_get_for_digest(
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
                llcas_digest_t {
                    data: key.as_ptr(),
                    size: key.len(),
                },
                value,
                false,
                &mut error,
            );
            let message = take_error(error);
            if failed {
                Err(message)
            } else {
                Ok(())
            }
        }
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

/// Answers every resolve with a miss and acknowledges everything else.
struct FakeProxy {
    socket: PathBuf,
    stopping: Arc<AtomicBool>,
}

impl FakeProxy {
    fn listening(socket: &Path) -> Self {
        let listener = UnixListener::bind(socket).expect("bind fake proxy socket");
        let stopping = Arc::new(AtomicBool::new(false));
        let worker_stopping = stopping.clone();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                if worker_stopping.load(Ordering::SeqCst) {
                    return;
                }
                let Ok(mut stream) = stream else { return };
                let Ok(request) = read_request(&mut stream) else {
                    continue;
                };
                let status = if request.op == OP_RESOLVE {
                    STATUS_MISS
                } else {
                    STATUS_HIT
                };
                let _ = write_response(&mut stream, status, &[]);
            }
        });
        Self {
            socket: socket.to_path_buf(),
            stopping,
        }
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
    fn new(label: &str) -> Self {
        Self::under(std::env::temp_dir(), label)
    }

    fn in_tmp(label: &str) -> Self {
        Self::under(PathBuf::from("/tmp"), label)
    }

    fn under(root: PathBuf, label: &str) -> Self {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let path = root.join(format!(
            "tuist-cas-failure-{label}-{}-{}",
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
