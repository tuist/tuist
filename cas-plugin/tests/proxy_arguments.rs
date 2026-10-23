//! What a hand-run `tuist-cas-proxy` may do to the machine's socket. Serving
//! unlinks the socket path and binds its own, so anything other than a bare
//! start (`version`, `--help`, a typo) must leave the socket alone, and a bare
//! start must not take a socket from a proxy that is still listening on it.

use std::os::unix::fs::MetadataExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output, Stdio};
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};

const PROXY: &str = env!("CARGO_BIN_EXE_tuist-cas-proxy");
const VERSION: &str = match option_env!("TUIST_CAS_RELEASE_VERSION") {
    Some(version) => version,
    None => env!("CARGO_PKG_VERSION"),
};
const EXIT_DEADLINE: Duration = Duration::from_secs(10);

// One test at a time: a proxy spawned by one test can inherit a socket another
// test is binding before close-on-exec is set, and keep it listening.
static SERIAL: Mutex<()> = Mutex::new(());

fn serial() -> MutexGuard<'static, ()> {
    SERIAL.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("tuist-proxy-args-{}-{name}", std::process::id()));
    std::fs::remove_dir_all(&dir).ok();
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir
}

fn proxy(dir: &Path, arguments: &[&str]) -> Child {
    Command::new(PROXY)
        .args(arguments)
        .env_clear()
        .env("HOME", dir)
        .env("PATH", "/usr/bin:/bin")
        .env("TUIST_CAS_PROXY_SOCKET", dir.join("proxy.sock"))
        .env("TUIST_CAS_PROXY_REGISTRY", dir.join("registry"))
        .env("TUIST_CAS_UPSTREAM_PLUGIN", "")
        .env("TUIST_CAS_REMOTE_GRPC_URL", "")
        .env("TUIST_CAS_TOKEN", "test")
        .env("TUIST_CAS_TUIST_BIN", "/usr/bin/false")
        .env("TUIST_CAS_PREFETCH", "0")
        .env("TUIST_CAS_LOG", dir.join("proxy.log"))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn tuist-cas-proxy")
}

/// Runs the proxy to completion. One that is still running at the deadline
/// went on to serve, and is killed so the test fails instead of hanging.
fn run(dir: &Path, arguments: &[&str]) -> Output {
    let mut child = proxy(dir, arguments);
    let started = Instant::now();
    while child.try_wait().expect("poll proxy").is_none() {
        if started.elapsed() > EXIT_DEADLINE {
            child.kill().ok();
            let output = child.wait_with_output().expect("proxy output");
            panic!(
                "tuist-cas-proxy {arguments:?} kept running: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    child.wait_with_output().expect("proxy output")
}

fn inode(path: &Path) -> u64 {
    std::fs::metadata(path).expect("socket metadata").ino()
}

fn assert_still_served(socket: &Path, listener: &UnixListener, original: u64) {
    assert_eq!(inode(socket), original, "the socket was replaced");
    UnixStream::connect(socket).expect("the socket still accepts connections");
    listener.set_nonblocking(true).expect("nonblocking");
    listener.accept().expect("the connection reached the original listener");
}

#[test]
fn version_prints_the_version_without_touching_the_socket() {
    let _serial = serial();
    for argument in ["version", "--version", "-V"] {
        let dir = scratch(&format!("version{argument}"));
        let socket = dir.join("proxy.sock");

        let output = run(&dir, &[argument]);
        assert!(output.status.success(), "{argument}: {output:?}");
        assert_eq!(String::from_utf8_lossy(&output.stdout), format!("{VERSION}\n"), "{argument}");
        assert!(!socket.exists(), "{argument} created the socket");
        assert!(!dir.join("registry").exists(), "{argument} created the registry");

        let listener = UnixListener::bind(&socket).expect("bind");
        let original = inode(&socket);
        let output = run(&dir, &[argument]);
        assert!(output.status.success(), "{argument}: {output:?}");
        assert_still_served(&socket, &listener, original);
        std::fs::remove_dir_all(&dir).ok();
    }
}

#[test]
fn help_prints_usage_without_touching_the_socket() {
    let _serial = serial();
    for argument in ["help", "--help", "-h"] {
        let dir = scratch(&format!("help{argument}"));
        let socket = dir.join("proxy.sock");

        let output = run(&dir, &[argument]);
        assert!(output.status.success(), "{argument}: {output:?}");
        assert!(String::from_utf8_lossy(&output.stdout).starts_with("usage: tuist-cas-proxy"), "{argument}");
        assert!(!socket.exists(), "{argument} created the socket");
        std::fs::remove_dir_all(&dir).ok();
    }
}

#[test]
fn an_unrecognized_argument_fails_without_touching_the_socket() {
    let _serial = serial();
    for arguments in [&["verison"][..], &["serve"], &["--version", "--help"], &["--socket", "/tmp/other.sock"]] {
        let dir = scratch("unrecognized");
        let socket = dir.join("proxy.sock");

        let output = run(&dir, arguments);
        assert_eq!(output.status.code(), Some(64), "{arguments:?}: {output:?}");
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(stderr.contains("unrecognized arguments"), "{arguments:?}: {stderr}");
        assert!(stderr.contains("usage: tuist-cas-proxy"), "{arguments:?}: {stderr}");
        assert!(output.stdout.is_empty(), "{arguments:?}");
        assert!(!socket.exists(), "{arguments:?} created the socket");

        let listener = UnixListener::bind(&socket).expect("bind");
        let original = inode(&socket);
        let output = run(&dir, arguments);
        assert_eq!(output.status.code(), Some(64), "{arguments:?}: {output:?}");
        assert_still_served(&socket, &listener, original);
        std::fs::remove_dir_all(&dir).ok();
    }
}

#[test]
fn a_bare_start_leaves_a_listening_proxy_alone() {
    let _serial = serial();
    let dir = scratch("live");
    let socket = dir.join("proxy.sock");
    let listener = UnixListener::bind(&socket).expect("bind");
    let original = inode(&socket);

    let output = run(&dir, &[]);
    assert_eq!(output.status.code(), Some(2), "{output:?}");
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("already listening"),
        "{output:?}"
    );
    assert_still_served(&socket, &listener, original);
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn a_bare_start_replaces_a_stale_socket_and_serves() {
    let _serial = serial();
    let dir = scratch("stale");
    let socket = dir.join("proxy.sock");
    // A proxy that exited (crash, idle upgrade, bootout) leaves its socket file
    // behind with nothing listening.
    drop(UnixListener::bind(&socket).expect("bind"));
    let stale = inode(&socket);
    assert!(UnixStream::connect(&socket).is_err(), "nothing listens on a stale socket");

    let mut child = proxy(&dir, &[]);
    let started = Instant::now();
    let served = loop {
        if let Some(status) = child.try_wait().expect("poll proxy") {
            let output = child.wait_with_output().expect("proxy output");
            panic!("the proxy exited ({status}) instead of serving: {}", String::from_utf8_lossy(&output.stderr));
        }
        if UnixStream::connect(&socket).is_ok() {
            break true;
        }
        if started.elapsed() > EXIT_DEADLINE {
            break false;
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    let replaced = std::fs::metadata(&socket).map(|metadata| metadata.ino() != stale).unwrap_or(false);
    child.kill().ok();
    child.wait().ok();

    assert!(served, "the proxy never listened on {}", socket.display());
    assert!(replaced, "the proxy listened without replacing the stale socket");
    std::fs::remove_dir_all(&dir).ok();
}
