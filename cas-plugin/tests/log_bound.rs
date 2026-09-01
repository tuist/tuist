//! The `TUIST_CAS_LOG` file is bounded. It is written by the proxy and by a
//! plugin instance in every compiler frontend on the machine, `tuist setup cache`
//! defaults it on for CI, and nothing else rotates it, so an unbounded one fills
//! the disk of the machine it was meant to diagnose.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, MutexGuard, OnceLock};

use tuist_cas_plugin::log_line;

const MAX_LOG_BYTES: u64 = 32 * 1024 * 1024;
const CHECK_INTERVAL: u64 = 64 * 1024;

/// One test at a time: `log_line` reads `TUIST_CAS_LOG` from the environment and
/// cargo runs a file's tests as parallel threads of one process, where a
/// `set_var` racing another thread's `var` is a data race. Poisoning is ignored,
/// since a panicking test leaves nothing behind that the next one reads.
fn serialized() -> MutexGuard<'static, ()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(())).lock().unwrap_or_else(|error| error.into_inner())
}

struct CapturedLog {
    directory: TempDir,
    _serialized: MutexGuard<'static, ()>,
}

impl CapturedLog {
    fn new(label: &str) -> Self {
        let serialized = serialized();
        let directory = TempDir::new(label);
        std::env::set_var("TUIST_CAS_LOG", directory.path().join("cas.log"));
        Self { directory, _serialized: serialized }
    }

    fn path(&self) -> PathBuf {
        self.directory.path().join("cas.log")
    }

    fn size(&self) -> u64 {
        std::fs::metadata(self.path()).map(|metadata| metadata.len()).unwrap_or(0)
    }

    fn contents(&self) -> String {
        std::fs::read_to_string(self.path()).unwrap_or_default()
    }

    /// Grows the file to just past the cap without writing 32 MiB: `set_len` on a
    /// fresh file leaves it sparse, and the bound reads the file's LENGTH.
    fn seed_over_cap(&self) {
        let file = std::fs::File::create(self.path()).expect("seed the log file");
        file.set_len(MAX_LOG_BYTES + 1).expect("grow past the cap");
    }

    /// The size check is amortized — one `metadata` call per `CHECK_INTERVAL`
    /// bytes a process writes — and the counter behind it is process-global, so a
    /// test that logs a handful of lines may ride an earlier test's credit and
    /// never check at all. Writing past the interval makes the check certain
    /// regardless of what ran before. Returns the last line's message.
    fn log_past_the_check_interval(&self, label: &str) -> String {
        let filler = "x".repeat(100);
        let lines = (CHECK_INTERVAL / 100) * 2;
        for index in 0..lines {
            log_line(&format!("{label} {index} {filler}"));
        }
        format!("{label} {} ", lines - 1)
    }
}

impl Drop for CapturedLog {
    fn drop(&mut self) {
        std::env::remove_var("TUIST_CAS_LOG");
    }
}

#[test]
fn truncates_in_place_once_over_the_cap() {
    let capture = CapturedLog::new("over-cap");
    capture.seed_over_cap();

    let last = capture.log_past_the_check_interval("after the cap");

    assert!(capture.size() < MAX_LOG_BYTES, "expected a truncated file, got {} bytes", capture.size());
    // Truncation keeps the file at the same path rather than renaming it away, so
    // the writers all stay on one inode.
    assert!(capture.path().exists(), "expected the log file to survive the rollover");
    // The RECENT output is what survives: writing continues past the rollover
    // instead of stopping at a ceiling, which is what makes the end of a failed
    // build readable.
    assert!(
        capture.contents().contains(&last),
        "expected the newest line {last:?} to survive, got {:?}",
        tail(&capture.contents())
    );
}

#[test]
fn leaves_an_under_cap_file_alone() {
    let capture = CapturedLog::new("under-cap");

    let last = capture.log_past_the_check_interval("under the cap");
    let contents = capture.contents();

    // Same number of written bytes as the rollover case, so this pins that the
    // check fired and declined to truncate, not that it never ran.
    assert!(contents.contains("under the cap 0 "), "expected the oldest line to survive, got {:?}", tail(&contents));
    assert!(contents.contains(&last), "expected the newest line {last:?} to survive");
}

/// Each line costs one `write` syscall, so lines from the many processes sharing
/// the path cannot interleave mid-line.
#[test]
fn writes_whole_lines() {
    let capture = CapturedLog::new("whole-lines");

    log_line("a message with spaces and = signs");

    let contents = capture.contents();
    assert_eq!(contents.lines().count(), 1, "expected exactly one line, got {contents:?}");
    assert!(contents.ends_with('\n'), "expected a terminated line, got {contents:?}");
    assert!(contents.contains("a message with spaces and = signs"));
}

fn tail(contents: &str) -> String {
    contents.lines().rev().take(3).collect::<Vec<_>>().join(" | ")
}

struct TempDir(PathBuf);

impl TempDir {
    fn new(label: &str) -> Self {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let path = std::env::temp_dir().join(format!(
            "tuist-cas-log-{label}-{}-{}",
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
