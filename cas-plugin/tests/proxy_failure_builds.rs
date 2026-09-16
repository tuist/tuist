//! A proxy failure is warned about once per build, across the many compiler
//! processes a build spawns, and recorded for the CLI whichever process saw it.
//!
//! These run real processes: the test binary re-executes itself as children that
//! each note one failure, because concurrency between compilations and the identity
//! of the process noting the failure are exactly what a single process cannot show.
//! Every child shares this test process as its parent, the way a build's compilers
//! share their build service.

use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::SystemTime;

const WARNING: &str = "warning: The Tuist Xcode cache proxy";
const CHILD_SOCKET: &str = "TUIST_CAS_FAILURE_CHILD_SOCKET";

/// What each child process runs. A no-op when the suite itself runs.
#[test]
fn child_notes_a_proxy_failure() {
    let Ok(socket) = std::env::var(CHILD_SOCKET) else {
        return;
    };
    tuist_cas_plugin::proxy_failure::note(
        &socket,
        "proxy connect: Connection refused (os error 61)",
    );
}

#[test]
fn concurrent_compilations_of_one_build_warn_once() {
    let directory = TempDir::new("concurrent");
    for round in 0..5 {
        let socket = directory
            .path()
            .join(format!("round-{round}"))
            .join("cas-proxy.sock");
        std::fs::create_dir_all(socket.parent().unwrap()).unwrap();

        let children: Vec<Child> = (0..16)
            .map(|_| {
                child(&this_binary(), &socket, Some("1111"))
                    .spawn()
                    .expect("spawn child")
            })
            .collect();
        let warnings: usize = children
            .into_iter()
            .map(|child| warnings_in(&child.wait_with_output().expect("wait for child")))
            .sum();

        assert_eq!(
            warnings, 1,
            "round {round}: one build warns once, however many of its compilations fail at the same moment"
        );
    }
}

/// Xcode keeps one build service across builds, so its compilers share a parent from
/// one build to the next.
#[test]
fn a_later_build_under_the_same_build_service_warns_again() {
    let directory = TempDir::new("later-build");
    let socket = directory.path().join("cas-proxy.sock");
    assert_eq!(
        warnings_in(&run(child(&this_binary(), &socket, Some("1111")))),
        1
    );

    let second_build_started = SystemTime::now();
    let second_build = run(child(&this_binary(), &socket, Some("2222")));

    assert_eq!(
        warnings_in(&second_build),
        1,
        "a new build under the same build service warns again"
    );
    assert!(
        newest_change(directory.path()).is_some_and(|changed| changed >= second_build_started),
        "the second build's failure must be recorded after it started, or the CLI ignores it"
    );
}

/// With frontend replay disabled and uploads off, the build service can be the only
/// process that talks to the proxy.
#[test]
fn a_failure_only_the_build_service_sees_is_recorded_without_a_warning() {
    let directory = TempDir::new("build-service");
    let state = directory.path().join("state");
    std::fs::create_dir_all(&state).unwrap();
    let socket = state.join("cas-proxy.sock");
    let build_service = directory.path().join("bin").join("SWBBuildService");
    std::fs::create_dir_all(build_service.parent().unwrap()).unwrap();
    std::fs::copy(this_binary(), &build_service).expect("copy the test binary");

    let started = SystemTime::now();
    let output = run(child(&build_service, &socket, None));

    assert_eq!(
        warnings_in(&output),
        0,
        "the build service's stderr is not part of any task's output"
    );
    assert!(
        newest_change(&state).is_some_and(|changed| changed >= started),
        "the build service's failure must still be recorded for the CLI"
    );

    let compilation = run(child(&this_binary(), &socket, Some("3333")));
    assert_eq!(
        warnings_in(&compilation),
        1,
        "a record the build service wrote must not silence the compilations that can warn"
    );
}

// --- Children ------------------------------------------------------------------

fn this_binary() -> PathBuf {
    std::env::current_exe().expect("current test binary")
}

fn child(binary: &Path, socket: &Path, build_id: Option<&str>) -> Command {
    let mut command = Command::new(binary);
    command
        .args([
            "child_notes_a_proxy_failure",
            "--exact",
            "--test-threads",
            "1",
            "--quiet",
        ])
        .env(CHILD_SOCKET, socket)
        .env_remove("LLBUILD_BUILD_ID")
        .stdout(Stdio::null())
        .stderr(Stdio::piped());
    if let Some(build_id) = build_id {
        command.env("LLBUILD_BUILD_ID", build_id);
    }
    command
}

fn run(mut command: Command) -> Output {
    let output = command.output().expect("run child");
    assert!(
        output.status.success(),
        "child failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    output
}

fn warnings_in(output: &Output) -> usize {
    String::from_utf8_lossy(&output.stderr)
        .matches(WARNING)
        .count()
}

/// The latest modification time of anything under `directory`, whatever layout the
/// record uses.
fn newest_change(directory: &Path) -> Option<SystemTime> {
    let mut newest: Option<SystemTime> = None;
    let mut pending = vec![directory.to_path_buf()];
    while let Some(path) = pending.pop() {
        let Ok(entries) = std::fs::read_dir(&path) else {
            continue;
        };
        for entry in entries.flatten() {
            let Ok(metadata) = entry.metadata() else {
                continue;
            };
            if metadata.is_dir() {
                pending.push(entry.path());
            } else if let Ok(modified) = metadata.modified() {
                newest = Some(newest.map_or(modified, |current| current.max(modified)));
            }
        }
    }
    newest
}

struct TempDir(PathBuf);

impl TempDir {
    fn new(label: &str) -> Self {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let path = std::env::temp_dir().join(format!(
            "tuist-cas-builds-{label}-{}-{}",
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
