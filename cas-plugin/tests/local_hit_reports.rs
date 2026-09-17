//! Local action-cache hits reach the proxy as `OP_LOCAL_HITS` reports, driven
//! through the exported `llcas_*` surface against a recording fake proxy.

use std::collections::HashSet;
use std::ffi::{c_char, c_void, CStr, CString};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant};

use tuist_cas_plugin::proxy_proto::{
    read_request, write_response, OP_RESOLVE, STATUS_ERROR, STATUS_HIT, STATUS_MISS,
};
use tuist_cas_plugin::types::*;
use tuist_cas_plugin::upstream_path;

/// Pinned rather than imported: released proxies match on this value.
const OP_LOCAL_HITS: u8 = 9;

#[test]
fn a_long_lived_handle_reports_local_hits_before_it_is_disposed() {
    let Some(env) = Fixture::new("reports-live") else {
        return;
    };
    let keys = env.seed_backed_associations("live", 2_000);

    for key in &keys {
        assert_eq!(
            env.cas().actioncache_get(key).0,
            LLCAS_LOOKUP_RESULT_SUCCESS
        );
    }

    // Most compiler processes exit without disposing.
    let reported = env
        .proxy
        .wait_for_reported(Duration::from_secs(5), |reported| !reported.is_empty());
    assert!(
        !reported.is_empty(),
        "a long-lived handle must report before it is disposed"
    );
    assert!(
        reported.iter().all(|key| keys.contains(key)),
        "only keys this handle answered locally are reported"
    );
    assert_eq!(
        env.proxy.resolves(),
        0,
        "a local hit still costs no resolve"
    );
}

#[test]
fn every_local_hit_is_reported_once_the_handle_is_disposed() {
    let Some(mut env) = Fixture::new("reports-dispose") else {
        return;
    };
    let keys = env.seed_backed_associations("dispose", 600);

    for key in &keys {
        assert_eq!(
            env.cas().actioncache_get(key).0,
            LLCAS_LOOKUP_RESULT_SUCCESS
        );
        assert_eq!(
            env.cas().actioncache_get_async(key).0,
            LLCAS_LOOKUP_RESULT_SUCCESS
        );
    }
    env.dispose();

    let reported = env
        .proxy
        .wait_for_reported(Duration::from_secs(5), |reported| {
            reported.len() == keys.len()
        });
    assert_eq!(
        reported, keys,
        "every key answered locally is reported, the tail at dispose"
    );
}

#[test]
fn only_hits_answered_from_the_local_store_are_reported() {
    let Some(mut env) = Fixture::new("reports-scope") else {
        return;
    };

    // Kura served this one.
    let remote_key = env.cas().key_digest(b"remote");
    let remote_value = env
        .cas()
        .digest_of(env.cas().store_object(b"materialized by the proxy"));
    env.proxy.answer_resolve_with_hit(&remote_value);
    assert_eq!(
        env.cas().actioncache_get(&remote_key).0,
        LLCAS_LOOKUP_RESULT_SUCCESS
    );
    env.proxy.answer_resolve_with_miss();

    let unbacked_key = env.cas().key_digest(b"unbacked");
    let absent = env.cas().objectid_for(&env.absent_value_digest());
    env.cas()
        .actioncache_put(&unbacked_key, absent)
        .expect("seeding put");
    assert_eq!(
        env.cas().actioncache_get(&unbacked_key).0,
        LLCAS_LOOKUP_RESULT_NOTFOUND
    );

    let local_keys = env.seed_backed_associations("scope", 3);
    for key in &local_keys {
        assert_eq!(
            env.cas().actioncache_get(key).0,
            LLCAS_LOOKUP_RESULT_SUCCESS
        );
    }
    // Answered locally this time.
    assert_eq!(
        env.cas().actioncache_get(&remote_key).0,
        LLCAS_LOOKUP_RESULT_SUCCESS
    );
    env.dispose();

    let mut expected = local_keys.clone();
    expected.insert(remote_key.clone());
    let reported = env
        .proxy
        .wait_for_reported(Duration::from_secs(5), |reported| {
            reported.len() >= expected.len()
        });
    assert_eq!(reported, expected);
    assert!(!reported.contains(&unbacked_key));
}

#[test]
fn a_proxy_that_does_not_know_the_report_is_asked_once_per_handle() {
    let Some(mut env) = Fixture::new("reports-old-proxy") else {
        return;
    };
    env.proxy.supports_reports.store(false, Ordering::SeqCst);
    let keys = env.seed_backed_associations("old-proxy", 3_000);

    for key in &keys {
        assert_eq!(
            env.cas().actioncache_get(key).0,
            LLCAS_LOOKUP_RESULT_SUCCESS
        );
    }
    env.proxy.wait_for_requests(Duration::from_secs(5), 1);
    std::thread::sleep(Duration::from_millis(300));
    env.dispose();
    std::thread::sleep(Duration::from_millis(300));

    assert_eq!(
        env.proxy.report_requests(),
        1,
        "an older proxy answers `bad op`; asking again on every batch is a round trip per batch for nothing"
    );
}

/// Measures what reporting adds to a local hit on the serial lookup path.
/// Run with `cargo test --release --test local_hit_reports report_cost -- --ignored --nocapture`.
#[test]
#[ignore = "a measurement, not an assertion"]
fn report_cost() {
    let Some(env) = Fixture::new("report-cost") else {
        return;
    };
    let keys: Vec<Vec<u8>> = env
        .seed_backed_associations("cost", 20_000)
        .into_iter()
        .collect();
    for key in &keys {
        let _ = env.cas().actioncache_get(key);
    }
    for round in 0..3 {
        let started = Instant::now();
        for key in &keys {
            let _ = env.cas().actioncache_get(key);
        }
        eprintln!(
            "round {round}: {:?}/local hit over {} keys",
            started.elapsed() / keys.len() as u32,
            keys.len()
        );
    }
}

// --- Fixture -------------------------------------------------------------------

struct Fixture {
    cas: Option<PluginCas>,
    proxy: FakeProxy,
    _store: TempDir,
    _socket_dir: TempDir,
    _serialized: MutexGuard<'static, ()>,
}

impl Fixture {
    fn new(label: &str) -> Option<Self> {
        // `llcas_cas_create` reads the environment; see `unbacked_local_hit.rs`.
        let serialized = serialize_tests();
        if !Path::new(&upstream_path()).exists() {
            eprintln!("skipping {label}: Apple's libToolchainCASPlugin is unavailable");
            return None;
        }
        let store = TempDir::new(label);
        let socket_dir = TempDir::in_tmp(label);
        let proxy = FakeProxy::listening(&socket_dir.path().join("proxy.sock"));
        std::env::set_var("TUIST_CAS_PROXY_SOCKET", proxy.socket());
        std::env::set_var("TUIST_CAS_UPLOAD", "false");
        let cas = PluginCas::open(store.path());
        Some(Self {
            cas: Some(cas),
            proxy,
            _store: store,
            _socket_dir: socket_dir,
            _serialized: serialized,
        })
    }

    fn cas(&self) -> &PluginCas {
        self.cas.as_ref().expect("the handle is still open")
    }

    fn seed_backed_associations(&self, label: &str, count: usize) -> HashSet<Vec<u8>> {
        (0..count)
            .map(|index| {
                let key = self
                    .cas()
                    .key_digest(format!("{label}-key-{index}").as_bytes());
                let value = self
                    .cas()
                    .store_object(format!("{label}-value-{index}").as_bytes());
                self.cas()
                    .actioncache_put(&key, value)
                    .expect("seeding put");
                key
            })
            .collect()
    }

    fn absent_value_digest(&self) -> Vec<u8> {
        let elsewhere = TempDir::new("elsewhere");
        let other = PluginCas::open(elsewhere.path());
        other.digest_of(other.store_object(b"a value that exists only somewhere else"))
    }

    fn dispose(&mut self) {
        drop(self.cas.take());
    }
}

fn serialize_tests() -> MutexGuard<'static, ()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
        .lock()
        .unwrap_or_else(|e| e.into_inner())
}

// --- The plugin under test -----------------------------------------------------

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
        self.digest_of(self.store_object(&object))
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
                llcas_digest_t {
                    data: digest.as_ptr(),
                    size: digest.len(),
                },
                &mut id,
                &mut error,
            );
            assert!(!failed, "llcas_cas_get_objectid: {}", take_error(error));
            id
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

    fn actioncache_get(&self, key: &[u8]) -> (llcas_lookup_result_t, llcas_objectid_t) {
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
            (result, value)
        }
    }

    fn actioncache_get_async(&self, key: &[u8]) -> (llcas_lookup_result_t, usize) {
        struct AsyncGet {
            result: llcas_lookup_result_t,
            calls: usize,
        }
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
        let mut slot = AsyncGet {
            result: LLCAS_LOOKUP_RESULT_ERROR,
            calls: 0,
        };
        unsafe {
            tuist_cas_plugin::llcas_actioncache_get_for_digest_async(
                self.raw,
                llcas_digest_t {
                    data: key.as_ptr(),
                    size: key.len(),
                },
                false,
                &mut slot as *mut AsyncGet as *mut c_void,
                callback,
                ptr::null_mut(),
            );
        }
        (slot.result, slot.calls)
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

// --- A recording proxy ---------------------------------------------------------

struct FakeProxy {
    socket: PathBuf,
    seen: Arc<Mutex<Vec<(u8, Vec<u8>)>>>,
    resolve_answer: Arc<Mutex<Option<Vec<u8>>>>,
    supports_reports: Arc<AtomicBool>,
    stopping: Arc<AtomicBool>,
}

impl FakeProxy {
    fn listening(socket: &Path) -> Self {
        let listener = UnixListener::bind(socket).expect("bind fake proxy socket");
        let seen: Arc<Mutex<Vec<(u8, Vec<u8>)>>> = Arc::new(Mutex::new(Vec::new()));
        let resolve_answer: Arc<Mutex<Option<Vec<u8>>>> = Arc::new(Mutex::new(None));
        let supports_reports = Arc::new(AtomicBool::new(true));
        let stopping = Arc::new(AtomicBool::new(false));
        let worker = (
            seen.clone(),
            resolve_answer.clone(),
            supports_reports.clone(),
            stopping.clone(),
        );
        std::thread::spawn(move || {
            let (seen, resolve_answer, supports_reports, stopping) = worker;
            for stream in listener.incoming() {
                if stopping.load(Ordering::SeqCst) {
                    return;
                }
                let Ok(mut stream) = stream else { return };
                let Ok(request) = read_request(&mut stream) else {
                    continue;
                };
                seen.lock()
                    .unwrap()
                    .push((request.op, request.payload.clone()));
                let (status, body) = match request.op {
                    OP_RESOLVE => match resolve_answer.lock().unwrap().clone() {
                        Some(value) => (STATUS_HIT, value),
                        None => (STATUS_MISS, Vec::new()),
                    },
                    OP_LOCAL_HITS if !supports_reports.load(Ordering::SeqCst) => {
                        (STATUS_ERROR, b"bad op".to_vec())
                    }
                    _ => (STATUS_HIT, Vec::new()),
                };
                let _ = write_response(&mut stream, status, &body);
            }
        });
        Self {
            socket: socket.to_path_buf(),
            seen,
            resolve_answer,
            supports_reports,
            stopping,
        }
    }

    fn socket(&self) -> &Path {
        &self.socket
    }

    fn answer_resolve_with_hit(&self, value_digest: &[u8]) {
        *self.resolve_answer.lock().unwrap() = Some(value_digest.to_vec());
    }

    fn answer_resolve_with_miss(&self) {
        *self.resolve_answer.lock().unwrap() = None;
    }

    fn resolves(&self) -> usize {
        self.seen
            .lock()
            .unwrap()
            .iter()
            .filter(|(op, _)| *op == OP_RESOLVE)
            .count()
    }

    fn report_requests(&self) -> usize {
        self.seen
            .lock()
            .unwrap()
            .iter()
            .filter(|(op, _)| *op == OP_LOCAL_HITS)
            .count()
    }

    fn reported(&self) -> HashSet<Vec<u8>> {
        self.seen
            .lock()
            .unwrap()
            .iter()
            .filter(|(op, _)| *op == OP_LOCAL_HITS)
            .flat_map(|(_, payload)| decode_keys(payload))
            .collect()
    }

    fn wait_for_reported(
        &self,
        timeout: Duration,
        done: impl Fn(&HashSet<Vec<u8>>) -> bool,
    ) -> HashSet<Vec<u8>> {
        let deadline = Instant::now() + timeout;
        loop {
            let reported = self.reported();
            if done(&reported) || Instant::now() >= deadline {
                return reported;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    }

    fn wait_for_requests(&self, timeout: Duration, count: usize) {
        let deadline = Instant::now() + timeout;
        while self.report_requests() < count && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
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

/// `u8 len | key`, repeated.
fn decode_keys(mut payload: &[u8]) -> Vec<Vec<u8>> {
    let mut keys = Vec::new();
    while let Some((&len, rest)) = payload.split_first() {
        let len = len as usize;
        assert!(rest.len() >= len, "a report frame must not truncate a key");
        keys.push(rest[..len].to_vec());
        payload = &rest[len..];
    }
    keys
}

// --- Temporary directories -----------------------------------------------------

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
