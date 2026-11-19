//! What the running daemon reports about itself, written to `status.json` every
//! few seconds so the app can show it without a socket or a second protocol.
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::paths;

/// After this long without a heartbeat the app treats the daemon as stopped.
pub const STALE_AFTER_SECONDS: u64 = 15;

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Status {
    pub pid: u32,
    pub version: String,
    /// Unix seconds of the last heartbeat.
    pub heartbeat: u64,
    /// The folders that exist and are shared, after resolving them.
    pub folders: usize,
    /// `idle` or `busy`.
    pub activity: String,
    /// The server connection: `not_connected`, `connecting`, `connected`,
    /// `offline` or `unauthorized`.
    pub connection: String,
    /// The server it connects to, when it has one.
    pub server: Option<String>,
    pub keeping_awake: bool,
    /// The daemon's own Screen Recording and Accessibility grants. Only the
    /// daemon can report them: macOS checks a process the app starts against
    /// the app's grants instead.
    pub screen_recording: Option<bool>,
    pub accessibility: Option<bool>,
}

pub fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs())
}

impl Status {
    pub fn read(state: &Path) -> Option<Self> {
        let bytes = std::fs::read(paths::status_file(state)).ok()?;
        serde_json::from_slice(&bytes).ok()
    }

    pub fn write(&self, state: &Path) -> std::io::Result<()> {
        paths::write_atomically(&paths::status_file(state), &serde_json::to_vec(self)?)
    }

    pub fn fresh(&self, now: u64) -> bool {
        now.saturating_sub(self.heartbeat) <= STALE_AFTER_SECONDS
    }
}
