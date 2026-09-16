//! The record a compiler process leaves when the proxy fails one of its requests.
//!
//! A failed request degrades to a miss, which is also what a cold cache answers, so
//! a build that never reached the proxy looks exactly like one that found nothing.
//! The record sits beside the proxy socket, where `tuist xcodebuild` and `tuist test`
//! read it once the build finishes, and the process that writes it warns in the build
//! output.
//!
//! Every compiler process of a build loads the plugin, so the record is keyed by the
//! build rather than the process: a compiler's parent is the build service that
//! spawned it, and a record that build service's compilers already wrote is left
//! alone. The build service itself writes nothing (see `is_build_service`).

use std::collections::HashSet;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, SystemTime};

use serde::{Deserialize, Serialize};

pub const RECORD_FILE_NAME: &str = "cas-proxy-failure.json";

/// Xcode keeps one build service across builds, so its compilers share a builder from
/// one build to the next and only age tells their records apart.
const REWRITE_AFTER: Duration = Duration::from_secs(10 * 60);

#[derive(Serialize, Deserialize)]
struct Record {
    socket: String,
    error: String,
    builder_pid: u32,
}

/// Beside the socket, so the CLI finds it from the socket path it already resolves.
pub fn record_path(socket_path: &str) -> Option<PathBuf> {
    Path::new(socket_path)
        .parent()
        .map(|directory| directory.join(RECORD_FILE_NAME))
}

/// Records `error` for this process's build and warns on stderr when this process is
/// the one that recorded it. Each record path is considered once per process.
///
/// The warning is written only alongside a record: a directory the record cannot be
/// written to is one no other compilation can deduplicate against either, and warning
/// from each of them would bury the build output.
pub fn note(socket_path: &str, error: &str) {
    if running_in_build_service() {
        return;
    }
    let Some(path) = record_path(socket_path) else {
        return;
    };
    static CONSIDERED: OnceLock<Mutex<HashSet<PathBuf>>> = OnceLock::new();
    let first_time = CONSIDERED
        .get_or_init(|| Mutex::new(HashSet::new()))
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .insert(path.clone());
    if !first_time {
        return;
    }
    let builder_pid = std::os::unix::process::parent_id();
    if !should_record(existing(&path), builder_pid) {
        return;
    }
    let record = Record {
        socket: socket_path.to_string(),
        error: error.to_string(),
        builder_pid,
    };
    if write(&path, &record).is_err() {
        return;
    }
    let _ = writeln!(std::io::stderr(), "{}", warning(socket_path, error));
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

fn should_record(existing: Option<(u32, Duration)>, builder_pid: u32) -> bool {
    match existing {
        None => true,
        Some((recorded_builder_pid, age)) => {
            recorded_builder_pid != builder_pid || age >= REWRITE_AFTER
        }
    }
}

/// The recorded builder and the record's age. An unreadable record reads as absent, so
/// it is replaced rather than trusted.
fn existing(path: &Path) -> Option<(u32, Duration)> {
    let modified = std::fs::metadata(path).ok()?.modified().ok()?;
    let record: Record = serde_json::from_slice(&std::fs::read(path).ok()?).ok()?;
    let age = SystemTime::now()
        .duration_since(modified)
        .unwrap_or_default();
    Some((record.builder_pid, age))
}

/// Written through a rename so a concurrent reader never sees a partial record.
fn write(path: &Path, record: &Record) -> std::io::Result<()> {
    if let Some(directory) = path.parent() {
        std::fs::create_dir_all(directory)?;
    }
    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
    let bytes = serde_json::to_vec(record).map_err(std::io::Error::other)?;
    std::fs::write(&temporary, bytes)?;
    std::fs::rename(&temporary, path)
}

fn running_in_build_service() -> bool {
    static IN_BUILD_SERVICE: OnceLock<bool> = OnceLock::new();
    *IN_BUILD_SERVICE.get_or_init(|| {
        std::env::current_exe()
            .ok()
            .and_then(|executable| {
                executable
                    .file_name()
                    .map(|name| is_build_service(&name.to_string_lossy()))
            })
            .unwrap_or(false)
    })
}

/// The build service loads the plugin for its own cache queries, but its stderr is not
/// part of any task's output: Xcode never shows it. Its failures are not lost, because
/// a build that needed the proxy runs compilers, and they make the same requests.
fn is_build_service(executable_name: &str) -> bool {
    matches!(executable_name, "SWBBuildService" | "XCBBuildService")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_build_service_is_left_to_its_compilers() {
        assert!(is_build_service("SWBBuildService"));
        assert!(is_build_service("XCBBuildService"));
        assert!(!is_build_service("swift-frontend"));
        assert!(!is_build_service("clang"));
    }

    #[test]
    fn a_build_records_once_and_a_later_build_records_again() {
        assert!(should_record(None, 7));
        assert!(!should_record(Some((7, Duration::from_secs(1))), 7));
        assert!(should_record(Some((8, Duration::from_secs(1))), 7));
        assert!(should_record(Some((7, REWRITE_AFTER)), 7));
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
