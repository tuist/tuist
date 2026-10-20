//! The per-compilation event stream `tuist_cargo_cache tui` watches.
//!
//! The end-of-build summary says what a build did once the build is over. It
//! cannot say what a build is doing now, and it cannot say which crate any of
//! its numbers belonged to. This module writes the decisions themselves, as
//! they are made, so another process can read them.
//!
//! ```text
//! <store>/sessions/v1/<session>.jsonl   one line per decision
//! <store>/sessions/v1/<session>.lock    held for as long as the build runs
//! ```
//!
//! tuist_cargo_cache has no daemon, so a session identifies itself by holding that lock:
//! whoever can take it is looking at a build that is over, however the build
//! ended. A file whose last line is not [`SessionEvent::SessionFinished`] and
//! whose lock is free belongs to a build that died.
//!
//! Events are history, not cache content: nothing keys on them, the collector
//! removes them on age and count alone, and every failure here is reported once
//! and then ignored -- a build is never worth failing over its own telemetry.

use crate::util::random_string;
use eyre::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use tuist_cargo_cache_core::ActionDiagnostic;

pub(crate) const SESSIONS_DIR: &str = "sessions/v1";
const EVENT_VERSION: u8 = 1;

/// One line of a session's event stream.
///
/// `serde(default)`-friendly and never `deny_unknown_fields`: a stream written
/// by a newer tuist_cargo_cache must degrade to less detail in an older TUI rather than to an
/// error, and every reader already skips a line it cannot parse.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(crate) enum SessionEvent {
    /// Wrapper phase data, separate from action counters.
    WrapperTiming {
        v: u8,
        ts_ms: u64,
        timing: tuist_cargo_cache_core::WrapperTiming,
    },
    /// The build that owns this stream, written before its first decision.
    SessionStarted {
        v: u8,
        ts_ms: u64,
        session: String,
        pid: u32,
        cargo_cache_version: String,
        workspace_root: PathBuf,
        command: Vec<String>,
        /// What this build calls the project, which worktrees of one project
        /// share and unrelated projects do not.
        ///
        /// Absent in streams written before this was recorded, which is why
        /// anything comparing two workspaces has to treat `None` as "no
        /// answer" rather than as a match.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        identity: Option<String>,
    },
    /// One accounted compilation.
    Action {
        v: u8,
        ts_ms: u64,
        outcome: ActionOutcome,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        crate_name: Option<String>,
        /// Restore time for a hit, compiler time for anything that compiled.
        duration_ns: u64,
        #[serde(default, skip_serializing_if = "ActionDetail::is_empty")]
        detail: ActionDetail,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        diagnostic: Option<ActionDiagnostic>,
    },
    /// The stream hit its size cap. Counters continue; rows stop.
    Truncated { v: u8, ts_ms: u64 },
    /// The build ended, and these were its totals.
    SessionFinished {
        v: u8,
        ts_ms: u64,
        stats: serde_json::Value,
    },
}

impl SessionEvent {
    /// The outcome name of an action event.
    #[cfg(test)]
    pub(crate) fn outcome_label(&self) -> Option<&str> {
        match self {
            Self::Action { outcome, .. } => Some(outcome.label()),
            _ => None,
        }
    }
}

/// What tuist_cargo_cache decided about one compilation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub(crate) enum ActionOutcome {
    /// Outputs were restored from the cache.
    Hit,
    /// A lookup happened and found nothing.
    Miss,
    /// No lookup was possible, for want of a key.
    Unconsulted,
    /// A hit that was rebuilt to check it.
    Verification {
        /// Whether the rebuild matched what was cached.
        matched: bool,
    },
    /// tuist_cargo_cache declined to cache this compilation.
    Bypass {
        /// Stable, low-cardinality bypass-reason name.
        ///
        /// The kind only. A full reason carries local paths and is unbounded in
        /// length; `TUIST_CARGO_CACHE_BYPASS_LOG` and `tuist_cargo_cache explain` remain where that lives.
        reason: String,
    },
}

impl ActionOutcome {
    /// The one-word name a reader can group or color by.
    pub(crate) fn label(&self) -> &str {
        match self {
            Self::Hit => "hit",
            Self::Miss => "miss",
            Self::Unconsulted => "unconsulted",
            Self::Verification { .. } => "verification",
            Self::Bypass { reason } => reason,
        }
    }
}

/// What a hit was worth, for the rows that show more than an outcome.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub(crate) struct ActionDetail {
    pub avoided_compiler_ns: u64,
    pub output_files: u64,
    pub output_bytes: u64,
    pub reflinked_output_bytes: u64,
    pub hardlinked_output_bytes: u64,
    pub copied_output_bytes: u64,
}

impl ActionDetail {
    fn is_empty(&self) -> bool {
        *self == Self::default()
    }
}

/// Where one session's events are written, and the lock that says it is live.
pub(crate) struct SessionPaths {
    pub events: PathBuf,
    pub lock: PathBuf,
}

/// The paths belonging to session `id` in `store`.
pub(crate) fn session_paths(store: &Path, id: &str) -> SessionPaths {
    let dir = store.join(SESSIONS_DIR);
    SessionPaths {
        events: dir.join(format!("{id}.jsonl")),
        lock: dir.join(format!("{id}.lock")),
    }
}

/// A name for this build's stream: when it started, and who is writing it.
fn new_session_id() -> String {
    format!(
        "{}-{}-{}",
        now_ms(),
        std::process::id(),
        random_string(4).to_lowercase()
    )
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|since| u64::try_from(since.as_millis()).unwrap_or(u64::MAX))
        .unwrap_or(0)
}

struct Open {
    /// Opened for append, and written one whole line at a time.
    ///
    /// Deliberately unbuffered: the point of the stream is that another process
    /// can watch a build in progress, and a buffer would hold every row back
    /// until the build was over. A line is serialized in memory first, so each
    /// row costs one small append -- against a compilation measured in
    /// milliseconds -- and a reader never sees half of one.
    file: File,
    written: u64,
    truncated: bool,
    /// Held for the life of the session. Dropping it is what marks the stream
    /// finished, so it is kept rather than used.
    _lock: fslock::LockFile,
}

/// The writer for one build's event stream.
///
/// Created before the build and dropped after it. A single writer per session
/// by construction: every event tuist_cargo_cache accounts for reaches the agent in this
/// process first, so nothing here contends with another writer.
pub(crate) struct EventWriter {
    id: String,
    paths: SessionPaths,
    /// Most bytes of rows to append before truncating.
    cap: u64,
    /// `None` until the first event, and again once writing has failed.
    state: Mutex<Option<Open>>,
    disabled: Mutex<bool>,
}

impl EventWriter {
    /// Prepare a stream for a build about to run in `store`.
    ///
    /// The file itself is not created until the first event, so a command that
    /// compiles nothing leaves nothing behind.
    /// A stream that stops recording rows after `cap` bytes.
    ///
    /// `None` records the whole build. The counters a build reports are kept in
    /// memory and are complete either way; this bounds only the row-level
    /// history that `tuist_cargo_cache tui` and `tuist_cargo_cache explain` read back.
    pub(crate) fn with_limit(store: &Path, cap: Option<u64>) -> Self {
        Self::with_cap(store, cap.unwrap_or(u64::MAX))
    }

    /// A stream that truncates after `cap` bytes of rows, for tests that need
    /// to reach the cap without writing megabytes to get there.
    #[cfg(test)]
    pub(crate) fn with_cap_for_test(store: &Path, cap: u64) -> Self {
        Self::with_cap(store, cap)
    }

    fn with_cap(store: &Path, cap: u64) -> Self {
        let id = new_session_id();
        Self {
            paths: session_paths(store, &id),
            id,
            cap,
            state: Mutex::new(None),
            disabled: Mutex::new(false),
        }
    }

    /// This session's name, as it appears in the store.
    #[cfg(test)]
    pub(crate) fn id(&self) -> &str {
        &self.id
    }

    /// Append one event, or give up on the stream for the rest of the build.
    pub(crate) fn write(&self, event: &SessionEvent) {
        if let Err(error) = self.try_write(event) {
            let mut disabled = self.disabled.lock().unwrap();
            if !*disabled {
                *disabled = true;
                // Once per session: the build is still fine, and a warning per
                // compilation would be worse than the missing history.
                log::warn!(
                    "session events are not being recorded to {}: {error:#}",
                    self.paths.events.display()
                );
            }
            *self.state.lock().unwrap() = None;
        }
    }

    fn try_write(&self, event: &SessionEvent) -> Result<()> {
        if *self.disabled.lock().unwrap() {
            return Ok(());
        }
        let mut state = self.state.lock().unwrap();
        let open = match state.as_mut() {
            Some(open) => open,
            None => state.insert(self.open()?),
        };
        // The cap bounds rows, not the two events that make a stream readable:
        // the one that says which build this is, and the one that says it
        // finished. Without the first, a reader skips the stream and explains
        // an older build; without the second, the TUI reads every long build as
        // having died. A cap below the size of either would otherwise leave a
        // file that says nothing except that something was dropped.
        let structural = matches!(
            event,
            SessionEvent::SessionStarted { .. } | SessionEvent::SessionFinished { .. }
        );
        if open.written >= self.cap && !structural {
            if open.truncated {
                return Ok(());
            }
            open.truncated = true;
            return append(
                open,
                &SessionEvent::Truncated {
                    v: EVENT_VERSION,
                    ts_ms: now_ms(),
                },
            );
        }
        append(open, event)
    }

    fn open(&self) -> Result<Open> {
        let dir = self
            .paths
            .events
            .parent()
            .expect("a session event path has a parent");
        std::fs::create_dir_all(dir)
            .wrap_err_with(|| format!("failed to create {}", dir.display()))?;
        let mut lock = fslock::LockFile::open(&self.paths.lock)?;
        // try_lock, not lock: the id contains this process's pid, so a taken
        // lock is somebody else's bug, not something to wait behind.
        if !lock.try_lock()? {
            eyre::bail!("another process holds {}", self.paths.lock.display());
        }
        let file = File::options()
            .create(true)
            .append(true)
            .open(&self.paths.events)
            .wrap_err_with(|| format!("failed to open {}", self.paths.events.display()))?;
        Ok(Open {
            file,
            written: 0,
            truncated: false,
            _lock: lock,
        })
    }

    /// Record the build that owns this stream.
    pub(crate) fn started(
        &self,
        workspace_root: &Path,
        command: &[String],
        identity: Option<&str>,
    ) {
        self.write(&SessionEvent::SessionStarted {
            v: EVENT_VERSION,
            ts_ms: now_ms(),
            session: self.id.clone(),
            pid: std::process::id(),
            cargo_cache_version: env!("CARGO_PKG_VERSION").to_string(),
            workspace_root: workspace_root.to_path_buf(),
            command: command.to_vec(),
            identity: identity.map(str::to_string),
        });
    }

    /// Record one accounted compilation.
    pub(crate) fn action(
        &self,
        outcome: ActionOutcome,
        crate_name: Option<String>,
        duration_ns: u64,
        detail: ActionDetail,
    ) {
        self.action_with_diagnostic(outcome, crate_name, duration_ns, detail, None);
    }

    /// Record one accounted compilation with cache-key diagnostics.
    pub(crate) fn action_with_diagnostic(
        &self,
        outcome: ActionOutcome,
        crate_name: Option<String>,
        duration_ns: u64,
        detail: ActionDetail,
        diagnostic: Option<ActionDiagnostic>,
    ) {
        self.write(&SessionEvent::Action {
            v: EVENT_VERSION,
            ts_ms: now_ms(),
            outcome,
            crate_name,
            duration_ns,
            detail,
            diagnostic,
        });
    }

    pub(crate) fn wrapper_timing(&self, timing: tuist_cargo_cache_core::WrapperTiming) {
        self.write(&SessionEvent::WrapperTiming {
            v: EVENT_VERSION,
            ts_ms: now_ms(),
            timing,
        });
    }

    /// Close the stream with the totals the summary reports.
    pub(crate) fn finished(&self, stats: serde_json::Value) {
        self.write(&SessionEvent::SessionFinished {
            v: EVENT_VERSION,
            ts_ms: now_ms(),
            stats,
        });
    }
}

fn append(open: &mut Open, event: &SessionEvent) -> Result<()> {
    let mut line = serde_json::to_vec(event)?;
    line.push(b'\n');
    open.file.write_all(&line)?;
    open.written = open.written.saturating_add(line.len() as u64);
    Ok(())
}

/// Parse the events in `contents`, skipping any line that will not parse.
///
/// A stream is read while it is being written, so the last line may be a
/// partial one; a reader that stopped at the first unparseable line would show
/// nothing for the rest of the build.
pub(crate) fn parse_events(contents: &str) -> Vec<SessionEvent> {
    contents
        .lines()
        .filter_map(|line| serde_json::from_str(line).ok())
        .collect()
}

/// Read one counter out of a finished session's totals.
///
/// The totals travel as the summary's own JSON rather than a second copy of its
/// schema, so a reader asks for the fields it shows and tolerates the rest
/// changing shape.
pub(crate) fn stat(stats: &serde_json::Value, key: &str) -> u64 {
    stats
        .get(key)
        .and_then(serde_json::Value::as_u64)
        .unwrap_or(0)
}

/// What a build's stream is doing right now.
///
/// `Live` is the default because a stream discovered before its first read has
/// not been probed yet, and treating an unread stream as dead would flicker
/// every running build through "abandoned" on the tick it is found.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) enum SessionState {
    /// A build is holding the lock and still appending.
    #[default]
    Live,
    /// The stream ends with its totals.
    Finished,
    /// Nobody holds the lock and the totals never arrived.
    Abandoned,
}

impl SessionState {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::Live => "live",
            Self::Finished => "finished",
            Self::Abandoned => "abandoned",
        }
    }
}

/// A session's stream, read incrementally.
///
/// Holds the offset it has consumed so a tick reads only what was appended
/// since the last one, and holds back a trailing partial line until its newline
/// arrives.
#[derive(Debug)]
pub(crate) struct SessionTail {
    id: String,
    paths_events: PathBuf,
    paths_lock: PathBuf,
    offset: u64,
    partial: String,
    finished: bool,
}

impl SessionTail {
    fn new(store: &Path, id: String) -> Self {
        let paths = session_paths(store, &id);
        Self {
            id,
            paths_events: paths.events,
            paths_lock: paths.lock,
            offset: 0,
            partial: String::new(),
            finished: false,
        }
    }

    pub(crate) fn id(&self) -> &str {
        &self.id
    }

    pub(crate) fn state(&self) -> SessionState {
        if self.finished {
            SessionState::Finished
        } else if locked(&self.paths_lock) {
            SessionState::Live
        } else {
            SessionState::Abandoned
        }
    }

    /// Consume and return whatever has been appended since the last read.
    pub(crate) fn read(&mut self) -> Vec<SessionEvent> {
        use std::io::{Read, Seek, SeekFrom};

        let Ok(mut file) = File::open(&self.paths_events) else {
            return Vec::new();
        };
        if file.seek(SeekFrom::Start(self.offset)).is_err() {
            return Vec::new();
        }
        let mut appended = Vec::new();
        if file.read_to_end(&mut appended).is_err() {
            return Vec::new();
        }
        self.offset = self.offset.saturating_add(appended.len() as u64);
        let Ok(appended) = String::from_utf8(appended) else {
            return Vec::new();
        };
        self.partial.push_str(&appended);
        // Everything through the last newline is complete; the remainder is a
        // line still being written, and is kept for the next read.
        let complete = match self.partial.rfind('\n') {
            Some(end) => self.partial.drain(..=end).collect::<String>(),
            None => return Vec::new(),
        };
        let events = parse_events(&complete);
        if events
            .iter()
            .any(|event| matches!(event, SessionEvent::SessionFinished { .. }))
        {
            self.finished = true;
        }
        events
    }
}

/// Whether a build still holds `lock`.
///
/// Taking the lock is the probe: an unlocked stream belongs to a process that is
/// gone, whether it finished or was killed, because the OS releases the lock
/// either way. Nothing waits on this lock, so a probe never blocks a build.
fn locked(lock: &Path) -> bool {
    match fslock::LockFile::open(lock) {
        Ok(mut lock) => match lock.try_lock() {
            // Taking it means nobody else had it. Released again at once: this
            // is a probe, not a claim.
            Ok(true) => {
                let _ = lock.unlock();
                false
            }
            Ok(false) => true,
            Err(_) => false,
        },
        Err(_) => false,
    }
}

/// The session streams present in `store`, oldest name first.
///
/// Ids begin with the start time in milliseconds and are fixed width for the
/// next several centuries, so sorting them by name sorts them by age.
pub(crate) fn session_ids(store: &Path) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(store.join(SESSIONS_DIR)) else {
        return Vec::new();
    };
    let mut ids: Vec<String> = entries
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            name.strip_suffix(".jsonl").map(str::to_string)
        })
        .collect();
    ids.sort();
    ids
}

/// Open tails for every stream in `store`, newest first, at most `limit`.
pub(crate) fn open_tails(store: &Path, limit: usize) -> Vec<SessionTail> {
    let mut ids = session_ids(store);
    if ids.len() > limit {
        ids.drain(..ids.len() - limit);
    }
    ids.reverse();
    ids.into_iter()
        .map(|id| SessionTail::new(store, id))
        .collect()
}

#[cfg(test)]
#[path = "events_tests.rs"]
mod tests;
