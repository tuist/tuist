//! The record a process leaves when the proxy fails one of its requests, and the one
//! warning per build that goes with it.
//!
//! A failed request degrades to a miss, which is also what a cold cache answers, so a
//! build that never reached the proxy looks exactly like one that found nothing.
//! Records live in `cas-proxy-failures/` beside the proxy socket, where `tuist
//! xcodebuild` and `tuist test` read them once the build finishes.
//!
//! Every compiler process of a build loads the plugin, so the warning is keyed by the
//! build rather than the process. llbuild hands every process it spawns for one build
//! the same random `LLBUILD_BUILD_ID` and draws a new one per build, so a compiler keys
//! its record on its parent (the build service) plus that id. That tells apart two
//! builds of one long-lived build service, which Xcode keeps across builds. The check
//! and the claim run under an exclusive lock on the directory, so concurrent
//! compilations cannot both claim a build.
//!
//! The build service records under its own key and never warns: its stderr is not part
//! of any task's output, but with frontend replay disabled and uploads off it can be the
//! only process that talks to the proxy, and its failure still counts for the CLI.

use std::collections::HashMap;
use std::io::Write;
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

pub const RECORD_DIRECTORY_NAME: &str = "cas-proxy-failures";

/// Without a build id nothing tells one build from the next under the same parent, so a
/// failure after this long without one counts as a new build.
const QUIET_PERIOD_MS: u64 = 10 * 60 * 1000;

/// A process that keeps failing refreshes its record at most this often, so the CLI sees
/// a failure newer than the build's start without every request taking the lock.
const REFRESH_INTERVAL_MS: u64 = 1_000;

/// Records older than this are removed whenever a new one is written.
const RETENTION_MS: u64 = 24 * 60 * 60 * 1000;

#[derive(Serialize, Deserialize)]
struct Record {
    socket: String,
    error: String,
    failed_at_ms: u64,
}

#[derive(Clone, Debug, PartialEq)]
enum Role {
    BuildService,
    Compiler { build_id: Option<String> },
}

/// Beside the socket, so the CLI finds it from the socket path it already resolves.
pub fn record_directory(socket_path: &str) -> Option<PathBuf> {
    Path::new(socket_path)
        .parent()
        .map(|directory| directory.join(RECORD_DIRECTORY_NAME))
}

/// Records `error` for this process's build, and warns on stderr when this process is
/// the one that claimed the build.
pub fn note(socket_path: &str, error: &str) {
    let Some(directory) = record_directory(socket_path) else {
        return;
    };
    let role = current_role();
    let key = record_key(
        role,
        std::process::id(),
        std::os::unix::process::parent_id(),
    );
    let path = directory.join(format!("{key}.json"));
    let now = now_ms();

    static LAST_NOTED: OnceLock<Mutex<HashMap<PathBuf, u64>>> = OnceLock::new();
    {
        let mut last_noted = LAST_NOTED
            .get_or_init(|| Mutex::new(HashMap::new()))
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if let Some(noted_at) = last_noted.get(&path) {
            if now.saturating_sub(*noted_at) < REFRESH_INTERVAL_MS {
                return;
            }
        }
        last_noted.insert(path.clone(), now);
    }

    let record = Record {
        socket: socket_path.to_string(),
        error: error.to_string(),
        failed_at_ms: now,
    };
    let Ok(warn) = claim(&directory, &path, role, &record) else {
        return;
    };
    if warn {
        let _ = writeln!(std::io::stderr(), "{}", warning(socket_path, error));
    }
}

/// Writes `record` and decides whether this process warns, under an exclusive lock so
/// that reading the previous record and replacing it cannot interleave with another
/// process doing the same. The lock is released when the lock file closes.
fn claim(directory: &Path, path: &Path, role: &Role, record: &Record) -> std::io::Result<bool> {
    std::fs::create_dir_all(directory)?;
    let lock = std::fs::File::options()
        .create(true)
        .truncate(false)
        .write(true)
        .open(directory.join(".lock"))?;
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX) } != 0 {
        return Err(std::io::Error::last_os_error());
    }

    let previous_failure_at = std::fs::read(path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Record>(&bytes).ok())
        .map(|previous| previous.failed_at_ms);
    let warn = should_warn(role, previous_failure_at, record.failed_at_ms);
    if previous_failure_at.is_none() {
        remove_expired(directory, record.failed_at_ms);
    }
    write(path, record)?;
    Ok(warn)
}

/// One line starting with `warning: `, which is what `tuist xcodebuild`'s formatter and
/// CI log annotations recognise.
fn warning(socket_path: &str, error: &str) -> String {
    format!(
        "warning: The Tuist Xcode cache proxy at {socket_path} failed ({error}). Compilations \
         that needed it used the local cache only, without remote cache hits. Their uploads are \
         kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the \
         proxy is not running."
    )
}

fn should_warn(role: &Role, previous_failure_at: Option<u64>, now: u64) -> bool {
    match role {
        Role::BuildService => false,
        Role::Compiler { build_id: Some(_) } => previous_failure_at.is_none(),
        Role::Compiler { build_id: None } => previous_failure_at
            .is_none_or(|failed_at| now.saturating_sub(failed_at) >= QUIET_PERIOD_MS),
    }
}

fn record_key(role: &Role, pid: u32, parent_pid: u32) -> String {
    match role {
        Role::BuildService => format!("service-{pid}"),
        Role::Compiler {
            build_id: Some(build_id),
        } => format!("build-{parent_pid}-{build_id}"),
        Role::Compiler { build_id: None } => format!("parent-{parent_pid}"),
    }
}

fn current_role() -> &'static Role {
    static ROLE: OnceLock<Role> = OnceLock::new();
    ROLE.get_or_init(|| {
        let executable = std::env::current_exe()
            .ok()
            .and_then(|path| {
                path.file_name()
                    .map(|name| name.to_string_lossy().into_owned())
            })
            .unwrap_or_default();
        role_for(
            &executable,
            std::env::var("LLBUILD_BUILD_ID").ok().as_deref(),
        )
    })
}

fn role_for(executable_name: &str, build_id: Option<&str>) -> Role {
    if matches!(executable_name, "SWBBuildService" | "XCBBuildService") {
        return Role::BuildService;
    }
    let build_id = build_id
        .map(|id| {
            id.chars()
                .filter(char::is_ascii_alphanumeric)
                .collect::<String>()
        })
        .filter(|id| !id.is_empty());
    Role::Compiler { build_id }
}

/// Written through a rename so a reader never sees a partial record.
fn write(path: &Path, record: &Record) -> std::io::Result<()> {
    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
    let bytes = serde_json::to_vec(record).map_err(std::io::Error::other)?;
    std::fs::write(&temporary, bytes)?;
    std::fs::rename(&temporary, path)
}

fn remove_expired(directory: &Path, now: u64) {
    let Ok(entries) = std::fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let is_record = path
            .extension()
            .is_some_and(|extension| extension == "json" || extension == "tmp");
        let modified_ms = entry
            .metadata()
            .and_then(|metadata| metadata.modified())
            .ok()
            .and_then(|modified| modified.duration_since(UNIX_EPOCH).ok())
            .map(|age| age.as_millis() as u64);
        if is_record
            && modified_ms.is_some_and(|modified| now.saturating_sub(modified) > RETENTION_MS)
        {
            let _ = std::fs::remove_file(path);
        }
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_build_service_is_told_apart_by_its_executable() {
        assert_eq!(role_for("SWBBuildService", Some("1")), Role::BuildService);
        assert_eq!(role_for("XCBBuildService", None), Role::BuildService);
        assert_eq!(
            role_for("swift-frontend", Some("3871203995")),
            Role::Compiler {
                build_id: Some("3871203995".into())
            }
        );
        assert_eq!(role_for("clang", None), Role::Compiler { build_id: None });
    }

    #[test]
    fn a_build_id_cannot_escape_the_record_directory() {
        assert_eq!(
            role_for("clang", Some("../../etc")),
            Role::Compiler {
                build_id: Some("etc".into())
            }
        );
        assert_eq!(
            role_for("clang", Some("/..")),
            Role::Compiler { build_id: None }
        );
    }

    #[test]
    fn compilers_of_one_build_share_a_key_and_the_build_service_has_its_own() {
        let compiler = Role::Compiler {
            build_id: Some("1111".into()),
        };
        assert_eq!(record_key(&compiler, 7, 42), "build-42-1111");
        assert_eq!(record_key(&compiler, 8, 42), "build-42-1111");
        assert_eq!(record_key(&Role::BuildService, 42, 1), "service-42");
        assert_eq!(
            record_key(&Role::Compiler { build_id: None }, 7, 42),
            "parent-42"
        );
    }

    #[test]
    fn only_the_first_failure_of_a_build_warns() {
        let with_build = Role::Compiler {
            build_id: Some("1111".into()),
        };
        assert!(should_warn(&with_build, None, 1_000));
        assert!(!should_warn(&with_build, Some(1), 1_000 + QUIET_PERIOD_MS));
        assert!(!should_warn(&Role::BuildService, None, 1_000));

        let without_build = Role::Compiler { build_id: None };
        assert!(should_warn(&without_build, None, 1_000));
        assert!(!should_warn(&without_build, Some(1_000), 2_000));
        assert!(should_warn(
            &without_build,
            Some(1_000),
            1_000 + QUIET_PERIOD_MS
        ));
    }

    #[test]
    fn the_warning_is_a_single_line_the_formatter_recognises() {
        let line = warning(
            "/Users/me/.local/state/tuist/cas-proxy.sock",
            "proxy connect: refused",
        );
        assert!(line.starts_with("warning: "));
        assert!(!line.contains('\n'));
    }
}
