//! What the client sees when an llcas call fails.
//!
//! LLVM's plugin client wraps every error string a plugin returns as an
//! `inconvertibleErrorCode()` error, and its CAS-backed file system converts lookup
//! errors with `errorToErrorCode`, which aborts the process on exactly that code.
//! Xcode runs dependency scans inside its build service, so one failed load there
//! crashes the build service and fails every task in flight with
//! `LLVM ERROR: Inconvertible error value`. A not-found load reaches the same
//! callers as an ordinary `invalid_argument` "missing object" error instead, which
//! fails only the task that needed the object.
//!
//! An abort also loses the message, so every error the plugin returns is logged
//! before it is returned.
//!
//! The failing load is an object id Apple's store rejects (`file offset too
//! large`), which it answers with an error rather than crashing.

use std::ffi::{c_char, c_void, CStr, CString};
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, MutexGuard, OnceLock};

use tuist_cas_plugin::types::*;
use tuist_cas_plugin::upstream_path;

const UNKNOWN_OBJECT: llcas_objectid_t = llcas_objectid_t { opaque: 1 << 20 };

#[test]
fn a_failed_load_is_answered_as_not_found() {
    let Some(fixture) = Fixture::new("sync-load") else { return };
    let (result, error) = fixture.load(UNKNOWN_OBJECT);
    assert_eq!(result, LLCAS_LOOKUP_RESULT_NOTFOUND, "load error: {error}");
    assert_eq!(error, "", "a not-found answer carries no error");
}

#[test]
fn a_failed_async_load_is_answered_as_not_found() {
    let Some(fixture) = Fixture::new("async-load") else { return };
    let (result, error) = fixture.load_async(UNKNOWN_OBJECT);
    assert_eq!(result, LLCAS_LOOKUP_RESULT_NOTFOUND, "load error: {error}");
    assert_eq!(error, "", "a not-found answer carries no error");
}

#[test]
fn a_failed_load_is_logged() {
    let Some(fixture) = Fixture::new("logged-load") else { return };
    fixture.load(UNKNOWN_OBJECT);
    let log = fixture.log();
    assert!(log.contains("file offset too large"), "log:\n{log}");
}

#[test]
fn an_error_returned_to_the_client_is_logged() {
    let Some(fixture) = Fixture::new("logged-store") else { return };
    let missing = fixture.store.path().join("missing-input");
    let (failed, error) = fixture.store_from_filepath(&missing);
    assert!(failed, "storing a file that does not exist fails");
    assert!(!error.is_empty(), "a failed store carries an error");
    let log = fixture.log();
    assert!(log.contains(&error), "log:\n{log}");
}

// --- Fixture -------------------------------------------------------------------

/// One test at a time: the plugin reads its configuration from the environment,
/// and cargo runs a file's tests as threads of one process.
fn serialized() -> MutexGuard<'static, ()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(())).lock().unwrap_or_else(|error| error.into_inner())
}

struct Fixture {
    cas: llcas_cas_t,
    store: TempDir,
    _serialized: MutexGuard<'static, ()>,
}

impl Fixture {
    fn new(label: &str) -> Option<Self> {
        if !Path::new(&upstream_path()).exists() {
            eprintln!("skipping {label}: Apple's libToolchainCASPlugin is unavailable");
            return None;
        }
        let serialized = serialized();
        let store = TempDir::new(label);
        std::env::set_var("TUIST_CAS_LOG", store.path().join("cas.log"));
        std::env::set_var("TUIST_CAS_PROXY_SOCKET", store.path().join("absent.sock"));
        std::env::set_var("TUIST_CAS_UPLOAD", "false");
        let cas = unsafe {
            let options = tuist_cas_plugin::llcas_cas_options_create();
            tuist_cas_plugin::llcas_cas_options_set_client_version(
                options,
                LLCAS_VERSION_MAJOR,
                LLCAS_VERSION_MINOR,
            );
            let path = CString::new(store.path().join("cas").to_str().unwrap()).unwrap();
            tuist_cas_plugin::llcas_cas_options_set_ondisk_path(options, path.as_ptr());
            let mut error: *mut c_char = ptr::null_mut();
            let cas = tuist_cas_plugin::llcas_cas_create(options, &mut error);
            tuist_cas_plugin::llcas_cas_options_dispose(options);
            assert!(!cas.is_null(), "llcas_cas_create: {}", take_error(error));
            cas
        };
        Some(Self { cas, store, _serialized: serialized })
    }

    fn load(&self, id: llcas_objectid_t) -> (llcas_lookup_result_t, String) {
        unsafe {
            let mut loaded = llcas_loaded_object_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let result = tuist_cas_plugin::llcas_cas_load_object(self.cas, id, &mut loaded, &mut error);
            (result, take_error(error))
        }
    }

    fn load_async(&self, id: llcas_objectid_t) -> (llcas_lookup_result_t, String) {
        struct Answer {
            result: llcas_lookup_result_t,
            error: String,
            calls: usize,
        }
        unsafe extern "C" fn answered(
            context: *mut c_void,
            result: llcas_lookup_result_t,
            _loaded: llcas_loaded_object_t,
            error: *mut c_char,
        ) {
            let answer = &mut *(context as *mut Answer);
            answer.result = result;
            answer.error = take_error(error);
            answer.calls += 1;
        }
        let mut answer = Answer { result: LLCAS_LOOKUP_RESULT_SUCCESS, error: String::new(), calls: 0 };
        unsafe {
            tuist_cas_plugin::llcas_cas_load_object_async(
                self.cas,
                id,
                &mut answer as *mut Answer as *mut c_void,
                answered,
                ptr::null_mut(),
            );
        }
        assert_eq!(answer.calls, 1, "the callback fires exactly once, on the caller's thread");
        (answer.result, answer.error)
    }

    fn store_from_filepath(&self, path: &Path) -> (bool, String) {
        let path = CString::new(path.to_str().unwrap()).unwrap();
        unsafe {
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let failed =
                tuist_cas_plugin::llcas_cas_store_from_filepath(self.cas, path.as_ptr(), &mut id, &mut error);
            (failed, take_error(error))
        }
    }

    fn log(&self) -> String {
        std::fs::read_to_string(self.store.path().join("cas.log")).unwrap_or_default()
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        unsafe { tuist_cas_plugin::llcas_cas_dispose(self.cas) };
        std::env::remove_var("TUIST_CAS_LOG");
        std::env::remove_var("TUIST_CAS_PROXY_SOCKET");
        std::env::remove_var("TUIST_CAS_UPLOAD");
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

struct TempDir(PathBuf);

impl TempDir {
    fn new(label: &str) -> Self {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let path = std::env::temp_dir().join(format!(
            "tuist-cas-client-errors-{label}-{}-{}",
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
