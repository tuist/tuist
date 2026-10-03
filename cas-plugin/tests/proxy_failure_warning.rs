//! A failing proxy degrades every lookup to a miss, which is also what a cold cache
//! answers. The build service reports it as a cache error on its first failed
//! cross-machine lookup, which swift-build turns into a non-fatal warning on the
//! cache key query task, and answers every other lookup with a plain miss.
//!
//! What a lookup returns depends on the process making it, so these run real
//! processes: the test binary re-executes itself as a child, under its own name and
//! copied as `SWBBuildService`, and prints what each lookup returned.

use std::ffi::{c_char, c_void, CStr, CString};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use tuist_cas_plugin::proxy_proto::{
    read_request, write_response, OP_RESOLVE, STATUS_HIT, STATUS_MISS,
};
use tuist_cas_plugin::types::*;
use tuist_cas_plugin::upstream_path;

const SCENARIO: &str = "TUIST_CAS_WARNING_CHILD_SCENARIO";
const STORE: &str = "TUIST_CAS_WARNING_CHILD_STORE";
const MESSAGE: &str = "The Tuist Xcode cache proxy at";

#[test]
fn the_build_service_reports_a_failing_proxy_as_a_cache_error_once() {
    let Some(env) = Fixture::new("once") else {
        return;
    };

    let lookups = env.run_as_build_service("lookups");

    assert_eq!(lookups.len(), 3, "{lookups:?}");
    assert_eq!(lookups[0].result, LLCAS_LOOKUP_RESULT_ERROR, "{lookups:?}");
    assert!(
        lookups[0].error.contains(MESSAGE)
            && lookups[0].error.contains(env.socket.to_str().unwrap()),
        "the error must name the proxy and its socket: {lookups:?}"
    );
    assert_eq!(
        lookups[1].result, LLCAS_LOOKUP_RESULT_NOTFOUND,
        "one warning per outage, not one per lookup: {lookups:?}"
    );
    assert_eq!(
        lookups[2].result, LLCAS_LOOKUP_RESULT_NOTFOUND,
        "a local-only lookup fails the materialize task when it errors: {lookups:?}"
    );
}

/// `clang -cc1` also looks up globally, and an error there fails the compilation.
#[test]
fn a_compiler_never_turns_a_failing_proxy_into_an_error() {
    let Some(env) = Fixture::new("compiler") else {
        return;
    };

    let lookups = env.run_as_compiler("lookups");

    assert_eq!(lookups.len(), 3, "{lookups:?}");
    for lookup in &lookups {
        assert_eq!(lookup.result, LLCAS_LOOKUP_RESULT_NOTFOUND, "{lookups:?}");
        assert!(lookup.error.is_empty(), "{lookups:?}");
    }
}

#[test]
fn the_build_service_reports_again_once_the_proxy_has_answered() {
    let Some(env) = Fixture::new("recovery") else {
        return;
    };

    let lookups = env.run_as_build_service("recovery");

    let results: Vec<_> = lookups.iter().map(|lookup| lookup.result).collect();
    assert_eq!(
        results,
        vec![
            LLCAS_LOOKUP_RESULT_ERROR,
            LLCAS_LOOKUP_RESULT_NOTFOUND,
            LLCAS_LOOKUP_RESULT_ERROR,
        ],
        "a proxy that answered and then failed again is a new outage: {lookups:?}"
    );
}

/// The build service opens its lookup handles for a build, disposes them when the build
/// ends, and looks up through more than one of them at once: in one `SWBBuildService`,
/// `xcodebuild build build` looked up through two handles per build and opened fresh
/// ones for the second build.
#[test]
fn the_build_service_reports_once_per_build_across_its_lookup_handles() {
    let Some(env) = Fixture::new("handles") else {
        return;
    };

    let lookups = env.run_as_build_service("handles");

    let results: Vec<_> = lookups.iter().map(|lookup| lookup.result).collect();
    assert_eq!(
        results,
        vec![
            LLCAS_LOOKUP_RESULT_ERROR,
            LLCAS_LOOKUP_RESULT_NOTFOUND,
            LLCAS_LOOKUP_RESULT_ERROR,
        ],
        "one warning while a build's handles are open, another once the next build's are: {lookups:?}"
    );
}

// --- Child ---------------------------------------------------------------------

/// What each child process runs. A no-op when the suite itself runs.
#[test]
fn child_runs_a_lookup_scenario() {
    let (Ok(scenario), Ok(store)) = (std::env::var(SCENARIO), std::env::var(STORE)) else {
        return;
    };
    let store = PathBuf::from(store);
    let socket = PathBuf::from(std::env::var("TUIST_CAS_PROXY_SOCKET").expect("socket"));
    match scenario.as_str() {
        "lookups" => {
            let cas = PluginCas::open(&store);
            print_lookup(cas.get(&cas.key_digest(b"first"), true));
            print_lookup(cas.get(&cas.key_digest(b"second"), true));
            print_lookup(cas.get(&cas.key_digest(b"local"), false));
        }
        "recovery" => {
            let cas = PluginCas::open(&store);
            print_lookup(cas.get(&cas.key_digest(b"before"), true));
            let proxy = FakeProxy::listening(&socket);
            print_lookup(cas.get(&cas.key_digest(b"answered"), true));
            drop(proxy);
            print_lookup(cas.get(&cas.key_digest(b"after"), true));
        }
        "handles" => {
            let first = PluginCas::open(&store.join("first"));
            let second = PluginCas::open(&store.join("second"));
            print_lookup(first.get(&first.key_digest(b"first"), true));
            print_lookup(second.get(&second.key_digest(b"second"), true));
            drop(first);
            drop(second);
            let next_build = PluginCas::open(&store.join("next-build"));
            print_lookup(next_build.get(&next_build.key_digest(b"next-build"), true));
        }
        other => panic!("unknown scenario {other}"),
    }
}

fn print_lookup((result, error): (llcas_lookup_result_t, String)) {
    println!("LOOKUP result={result} error={error}");
}

#[derive(Debug)]
struct Lookup {
    result: llcas_lookup_result_t,
    error: String,
}

// --- Fixture -------------------------------------------------------------------

struct Fixture {
    socket: PathBuf,
    store: TempDir,
    socket_dir: TempDir,
    bin: TempDir,
}

impl Fixture {
    fn new(label: &str) -> Option<Self> {
        if !Path::new(&upstream_path()).exists() {
            eprintln!("skipping {label}: Apple's libToolchainCASPlugin is unavailable");
            return None;
        }
        // A unix socket path is capped near 104 bytes.
        let socket_dir = TempDir::under(PathBuf::from("/tmp"), label);
        Some(Self {
            socket: socket_dir.path().join("proxy.sock"),
            store: TempDir::under(std::env::temp_dir(), label),
            socket_dir,
            bin: TempDir::under(std::env::temp_dir(), &format!("{label}-bin")),
        })
    }

    fn run_as_build_service(&self, scenario: &str) -> Vec<Lookup> {
        let build_service = self.bin.path().join("SWBBuildService");
        std::fs::copy(std::env::current_exe().unwrap(), &build_service)
            .expect("copy the test binary");
        self.run(&build_service, scenario)
    }

    fn run_as_compiler(&self, scenario: &str) -> Vec<Lookup> {
        self.run(&std::env::current_exe().unwrap(), scenario)
    }

    fn run(&self, binary: &Path, scenario: &str) -> Vec<Lookup> {
        let _ = &self.socket_dir;
        let output = Command::new(binary)
            .args([
                "child_runs_a_lookup_scenario",
                "--exact",
                "--nocapture",
                "--test-threads",
                "1",
            ])
            .env(SCENARIO, scenario)
            .env(STORE, self.store.path())
            .env("TUIST_CAS_PROXY_SOCKET", &self.socket)
            .env("TUIST_CAS_UPLOAD", "false")
            .env("TUIST_CAS_LOG", "")
            .output()
            .expect("run child");
        assert!(
            output.status.success(),
            "child failed:\n{}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8_lossy(&output.stdout)
            .lines()
            // libtest prints the test's name without a newline before the test runs, so
            // the first line a child prints can share a line with it.
            .filter_map(|line| {
                line.find("LOOKUP result=")
                    .map(|at| &line[at + "LOOKUP result=".len()..])
            })
            .map(|rest| {
                let (result, error) = rest.split_once(" error=").unwrap_or((rest, ""));
                Lookup {
                    result: result.parse().expect("lookup result"),
                    error: error.to_string(),
                }
            })
            .collect()
    }
}

struct PluginCas {
    raw: llcas_cas_t,
}

impl PluginCas {
    fn open(store: &Path) -> Self {
        std::fs::create_dir_all(store).expect("create store");
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
        unsafe {
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let failed = tuist_cas_plugin::llcas_cas_store_object(
                self.raw,
                llcas_data_t {
                    data: object.as_ptr() as *const c_void,
                    size: object.len(),
                },
                ptr::null(),
                0,
                &mut id,
                &mut error,
            );
            assert!(!failed, "llcas_cas_store_object: {}", take_error(error));
            let digest = tuist_cas_plugin::llcas_objectid_get_digest(self.raw, id);
            std::slice::from_raw_parts(digest.data, digest.size).to_vec()
        }
    }

    fn get(&self, key: &[u8], globally: bool) -> (llcas_lookup_result_t, String) {
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
                globally,
                &mut error,
            );
            (result, take_error(error))
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
        let _ = std::fs::remove_file(socket);
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
    fn under(root: PathBuf, label: &str) -> Self {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let path = root.join(format!(
            "tuist-cas-warning-{label}-{}-{}",
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
