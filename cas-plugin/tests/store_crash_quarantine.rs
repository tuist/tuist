//! A corrupt local store must not crash-loop the proxy.
//!
//! Apple's on-disk CAS does not report every kind of damage as an error. A
//! corrupted index faults inside `llcas_cas_get_objectid`
//! (`OnDiskHashMappedTrie::insertLazy`), and a corrupted data record aborts with
//! `LLVM ERROR: OnDiskCAS: corrupt internal reference`. Neither can be caught
//! in-process, and launchd restarts the proxy into the same store.
//!
//! This drives the real `tuist-cas-proxy` binary the way launchd does: start it,
//! send the request that touches the store, and start it again when it dies. The
//! store is damaged the way the crash reports show, by overwriting the root of
//! its index trie. The proxy must stop opening the store after
//! `STORE_CRASH_LIMIT` crashes, keep serving every other store, and open it again
//! once it is recreated.

use std::ffi::{c_char, c_void, CString};
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::ptr;
use std::time::{Duration, Instant};

use tuist_cas_plugin::proxy_proto::{ProxyClient, Resolution};
use tuist_cas_plugin::store_quarantine::STORE_CRASH_LIMIT;
use tuist_cas_plugin::types::*;
use tuist_cas_plugin::upstream::Upstream;
use tuist_cas_plugin::upstream_path;

const INSTANCE: &str = "tuist/store-crash-quarantine";

#[test]
fn a_store_that_keeps_crashing_the_proxy_is_quarantined_across_restarts() {
    let Some(up) = upstream() else {
        return;
    };
    let fixture = Fixture::new("quarantine");
    let corrupt = fixture.root.join("corrupt-store");
    let healthy = fixture.root.join("healthy-store");
    seed_store(up, &corrupt);
    seed_store(up, &healthy);
    corrupt_index(&corrupt);

    let mut crashes = 0;
    let (mut proxy, answer) = loop {
        let mut proxy = fixture.start_proxy();
        let answer = proxy.client.fetch_object(&path(&corrupt), INSTANCE, &unknown_digest());
        if answer.is_ok() {
            break (proxy, answer);
        }
        let status = proxy
            .wait_for_exit(Duration::from_secs(10))
            .unwrap_or_else(|| panic!("the request failed without crashing the proxy: {answer:?}"));
        assert!(
            status.signal().is_some(),
            "the proxy may only die of the store's crash, not exit on its own: {status:?}"
        );
        crashes += 1;
        assert!(
            crashes <= STORE_CRASH_LIMIT,
            "the proxy crashed {crashes} times on one store and is still opening it"
        );
    };

    assert_eq!(
        crashes, STORE_CRASH_LIMIT,
        "the fixture has to crash the proxy, or this test proves nothing"
    );
    assert_eq!(
        answer,
        Ok(false),
        "a quarantined store answers a miss, so the compiler compiles"
    );
    assert!(
        matches!(
            proxy.client.resolve(&path(&corrupt), INSTANCE, b"a-key"),
            Ok(Resolution::Miss)
        ),
        "so does a resolve, without asking the remote, which is unreachable here"
    );
    assert_eq!(
        proxy
            .client
            .fetch_object(&path(&healthy), INSTANCE, &unknown_digest()),
        Ok(false),
        "every other store keeps being served"
    );
    assert!(
        proxy.wait_for_exit(Duration::from_millis(500)).is_none(),
        "and serving them does not crash the proxy"
    );
    let quarantined = format!("cas store {} is quarantined", path(&corrupt));
    let log = fixture.log();
    assert!(log.contains(&quarantined), "the quarantine is logged:\n{log}");
    // A developer machine's proxy runs without `TUIST_CAS_LOG`, and launchd
    // writes its stderr to the agent's log file.
    let stderr = std::fs::read_to_string(fixture.root.join("proxy.stderr")).unwrap();
    assert!(stderr.contains(&quarantined), "and written to stderr:\n{stderr}");
    proxy.stop();

    // A quarantine survives a restart that nothing crashed.
    let mut proxy = fixture.start_proxy();
    assert_eq!(
        proxy
            .client
            .fetch_object(&path(&corrupt), INSTANCE, &unknown_digest()),
        Ok(false)
    );
    assert!(proxy.wait_for_exit(Duration::from_millis(500)).is_none());
    proxy.stop();

    // Deleting the store is how a user repairs it, and the build recreates it.
    // A new directory is a new store, so the quarantine no longer applies.
    std::fs::remove_dir_all(&corrupt).unwrap();
    seed_store(up, &corrupt);
    let mut proxy = fixture.start_proxy();
    assert_eq!(
        proxy
            .client
            .fetch_object(&path(&corrupt), INSTANCE, &unknown_digest()),
        Ok(false)
    );
    assert!(proxy.wait_for_exit(Duration::from_millis(500)).is_none());
    assert!(
        fixture.log().contains(&format!("cas store {} was recreated", path(&corrupt))),
        "the release is logged:\n{}",
        fixture.log()
    );
    proxy.stop();
}

struct Fixture {
    root: PathBuf,
}

impl Fixture {
    fn new(label: &str) -> Self {
        let root = std::env::temp_dir().join(format!(
            "tuist-store-crash-{label}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        Self { root }
    }

    fn start_proxy(&self) -> RunningProxy {
        let socket = self.root.join("proxy.sock");
        let child = Command::new(env!("CARGO_BIN_EXE_tuist-cas-proxy"))
            .env("TUIST_CAS_PROXY_SOCKET", &socket)
            .env("TUIST_CAS_PROXY_REGISTRY", self.root.join("registry"))
            .env("TUIST_CAS_REMOTE_GRPC_URL", "http://127.0.0.1:1")
            .env("TUIST_CAS_TOKEN", "test")
            .env("TUIST_CAS_PREFETCH", "0")
            .env("TUIST_CAS_LOG", self.root.join("cas.log"))
            .env_remove("TUIST_CAS_TUIST_BIN")
            .stdout(Stdio::null())
            .stderr(
                std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(self.root.join("proxy.stderr"))
                    .unwrap(),
            )
            .spawn()
            .expect("spawn tuist-cas-proxy");
        let mut proxy = RunningProxy {
            child,
            client: ProxyClient {
                socket_path: path(&socket),
            },
        };
        let deadline = Instant::now() + Duration::from_secs(10);
        while std::os::unix::net::UnixStream::connect(&socket).is_err() {
            assert!(
                proxy.wait_for_exit(Duration::ZERO).is_none(),
                "the proxy exited before it listened"
            );
            assert!(Instant::now() < deadline, "the proxy never listened");
            std::thread::sleep(Duration::from_millis(20));
        }
        proxy
    }

    fn log(&self) -> String {
        std::fs::read_to_string(self.root.join("cas.log")).unwrap_or_default()
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

struct RunningProxy {
    child: Child,
    client: ProxyClient,
}

impl RunningProxy {
    fn wait_for_exit(&mut self, timeout: Duration) -> Option<std::process::ExitStatus> {
        let deadline = Instant::now() + timeout;
        loop {
            if let Some(status) = self.child.try_wait().unwrap() {
                return Some(status);
            }
            if Instant::now() >= deadline {
                return None;
            }
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    fn stop(mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

impl Drop for RunningProxy {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn path(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

/// A well-formed digest nothing stored. Looking it up inserts into the index
/// trie, which is where a damaged index faults.
fn unknown_digest() -> Vec<u8> {
    let mut digest = vec![0u8; 65];
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    for (index, byte) in digest.iter_mut().enumerate().skip(1) {
        *byte = (nanos >> (index % 16 * 8)) as u8 ^ index as u8;
    }
    digest
}

/// Fills a store past its first index page, so the root of the trie has
/// populated slots to corrupt.
fn seed_store(up: &'static Upstream, store: &Path) {
    std::fs::create_dir_all(store).unwrap();
    unsafe {
        let options = (up.llcas_cas_options_create)();
        (up.llcas_cas_options_set_client_version)(options, LLCAS_VERSION_MAJOR, LLCAS_VERSION_MINOR);
        let c_path = CString::new(path(store)).unwrap();
        (up.llcas_cas_options_set_ondisk_path)(options, c_path.as_ptr());
        let mut error: *mut c_char = ptr::null_mut();
        let cas = (up.llcas_cas_create)(options, &mut error);
        (up.llcas_cas_options_dispose)(options);
        assert!(!cas.is_null(), "llcas_cas_create failed");
        for index in 0..5_000u32 {
            let payload = format!("store-crash-quarantine-{index}");
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let failed = (up.llcas_cas_store_object)(
                cas,
                llcas_data_t {
                    data: payload.as_ptr() as *const c_void,
                    size: payload.len(),
                },
                ptr::null(),
                0,
                &mut id,
                &mut error,
            );
            assert!(!failed, "llcas_cas_store_object failed");
        }
        (up.llcas_cas_dispose)(cas);
    }
}

/// Overwrites the slots of the index trie's root table, past the file header.
fn corrupt_index(store: &Path) {
    use std::io::{Seek, SeekFrom, Write};
    let index = std::fs::read_dir(store)
        .unwrap()
        .flatten()
        .filter(|entry| entry.file_name().to_string_lossy().starts_with("v1."))
        .flat_map(|generation| std::fs::read_dir(generation.path()).unwrap().flatten())
        .map(|entry| entry.path())
        .find(|file| {
            let name = file.file_name().unwrap().to_string_lossy().into_owned();
            name.ends_with(".index")
        })
        .expect("the store has an index file");
    let mut file = std::fs::OpenOptions::new().write(true).open(index).unwrap();
    file.seek(SeekFrom::Start(0x60)).unwrap();
    file.write_all(&[0x11; 800]).unwrap();
}

fn upstream() -> Option<&'static Upstream> {
    let path = upstream_path();
    if !Path::new(&path).exists() {
        eprintln!("skipping: Apple's libToolchainCASPlugin is unavailable at {path}");
        return None;
    }
    let loaded = unsafe { Upstream::load(&path) }.expect("load libToolchainCASPlugin");
    Some(Box::leak(Box::new(loaded)))
}
