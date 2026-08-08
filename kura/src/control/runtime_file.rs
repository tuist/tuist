//! How the CLI finds the process it should talk to.
//!
//! At startup the node writes a runtime file next to its writer lock naming the
//! control socket, the pid holding the lock, and the identity it resolved. A
//! later `kura runtime inspect` reads it and connects, so an operator who has
//! shelled into a container needs no arguments beyond the data dir the pod spec
//! already exports.
//!
//! The runtime file is deliberately not the source of truth for liveness. Both
//! it and the writer lock survive a crash, and the data dir is a persistent
//! volume that outlives any single pod, so a rollback can leave either behind.
//! Liveness is proven by connecting to the socket: a clean shutdown unlinks it,
//! and a crash leaves a socket whose `connect` fails. The pid recorded here
//! exists so the resulting error can name the process that was expected.

use std::{
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use serde::{Deserialize, Serialize};

use crate::runtime::{DATA_DIR_LOCK_FILE, read_lock_file_pid};

pub const RUNTIME_INFO_FILE: &str = ".kura.runtime.json";
pub const CONTROL_SOCKET_FILE: &str = ".kura.control.sock";

/// Bumped only when a field an older reader depends on changes meaning. Adding
/// optional fields does not bump it, so a new node stays readable by the CLI
/// baked into an older image during a rolling update.
pub const SCHEMA_VERSION: u32 = 1;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct RuntimeInfo {
    pub schema_version: u32,
    pub pid: u32,
    pub version: String,
    pub started_at_unix_ms: u64,
    pub data_dir: PathBuf,
    pub control_socket_path: PathBuf,
    pub port: u16,
    pub internal_port: u16,
    pub node_url: String,
    pub region: String,
    pub tenant_id: String,
}

impl RuntimeInfo {
    pub fn control_socket_path(data_dir: &Path) -> PathBuf {
        data_dir.join(CONTROL_SOCKET_FILE)
    }

    fn path(data_dir: &Path) -> PathBuf {
        data_dir.join(RUNTIME_INFO_FILE)
    }

    /// Writes the runtime file for the process that currently holds the writer
    /// lock. Called after the lock is acquired so the recorded pid is always the
    /// lock holder.
    pub fn write(&self) -> Result<(), String> {
        let path = Self::path(&self.data_dir);
        let serialized = serde_json::to_vec_pretty(self)
            .map_err(|error| format!("failed to serialize runtime info: {error}"))?;
        std::fs::write(&path, serialized)
            .map_err(|error| format!("failed to write {}: {error}", path.display()))?;
        restrict_to_owner(&path)
    }

    /// Removes the runtime file on clean shutdown. Best effort: a crash leaves
    /// it behind, and the socket connect is what actually detects that.
    pub fn remove(data_dir: &Path) {
        let path = Self::path(data_dir);
        if let Err(error) = std::fs::remove_file(&path)
            && error.kind() != std::io::ErrorKind::NotFound
        {
            tracing::warn!("failed to remove {}: {error}", path.display());
        }
    }

    /// Reads the runtime file for a data directory.
    ///
    /// Cross-checks the recorded pid against the writer lock so a runtime file
    /// left by a different process is reported rather than silently trusted.
    pub fn load(data_dir: &Path) -> Result<Self, String> {
        let path = Self::path(data_dir);
        let bytes = std::fs::read(&path).map_err(|error| {
            if error.kind() == std::io::ErrorKind::NotFound {
                format!(
                    "no running Kura node found in {}: {} does not exist. \
                     Point --data-dir (or KURA_DATA_DIR) at the data directory of \
                     the node to inspect.",
                    data_dir.display(),
                    path.display()
                )
            } else {
                format!("failed to read {}: {error}", path.display())
            }
        })?;

        let info: Self = serde_json::from_slice(&bytes)
            .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;

        if info.schema_version != SCHEMA_VERSION {
            return Err(format!(
                "{} has schema version {} but this build understands {}. \
                 The node and the CLI are different versions.",
                path.display(),
                info.schema_version,
                SCHEMA_VERSION
            ));
        }

        if let Some(lock_pid) = read_lock_file_pid(data_dir)
            && lock_pid != info.pid
        {
            return Err(format!(
                "{} records pid {} but {} is held by pid {}. \
                 The runtime file is stale; the node likely restarted without cleaning it up.",
                path.display(),
                info.pid,
                data_dir.join(DATA_DIR_LOCK_FILE).display(),
                lock_pid
            ));
        }

        Ok(info)
    }
}

/// The runtime file names the node's identity and endpoints. The data directory
/// is already private to the pod, but there is no reason for it to be readable
/// more widely than the socket it points at.
#[cfg(unix)]
fn restrict_to_owner(path: &Path) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt as _;

    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
        .map_err(|error| format!("failed to restrict {}: {error}", path.display()))
}

#[cfg(not(unix))]
fn restrict_to_owner(_path: &Path) -> Result<(), String> {
    Ok(())
}

pub fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(data_dir: &Path) -> RuntimeInfo {
        RuntimeInfo {
            schema_version: SCHEMA_VERSION,
            pid: std::process::id(),
            version: "0.8.0".into(),
            started_at_unix_ms: 1_700_000_000_000,
            data_dir: data_dir.to_path_buf(),
            control_socket_path: RuntimeInfo::control_socket_path(data_dir),
            port: 4000,
            internal_port: 7443,
            node_url: "http://node-a:4000".into(),
            region: "eu-central".into(),
            tenant_id: "tenant".into(),
        }
    }

    #[test]
    fn round_trips_through_the_data_directory() {
        let dir = tempfile::tempdir().expect("temp dir");
        let info = sample(dir.path());
        info.write().expect("write runtime info");

        let loaded = RuntimeInfo::load(dir.path()).expect("load runtime info");
        assert_eq!(loaded, info);
    }

    #[test]
    fn missing_runtime_file_explains_how_to_point_at_a_node() {
        let dir = tempfile::tempdir().expect("temp dir");
        let error = RuntimeInfo::load(dir.path()).expect_err("should not find a node");
        assert!(error.contains("no running Kura node found"), "{error}");
        assert!(error.contains("--data-dir"), "{error}");
    }

    #[test]
    fn stale_runtime_file_is_rejected_against_the_writer_lock() {
        let dir = tempfile::tempdir().expect("temp dir");
        let mut info = sample(dir.path());
        info.pid = 999_999;
        info.write().expect("write runtime info");

        // Acquiring the lock records this process as the holder, which no longer
        // matches the runtime file.
        let _lock = crate::runtime::DataDirLock::acquire(dir.path()).expect("acquire lock");

        let error = RuntimeInfo::load(dir.path()).expect_err("stale file should be rejected");
        assert!(error.contains("stale"), "{error}");
        assert!(error.contains("999999"), "{error}");
    }

    #[test]
    fn future_schema_version_is_reported_as_a_version_mismatch() {
        let dir = tempfile::tempdir().expect("temp dir");
        let mut info = sample(dir.path());
        info.schema_version = SCHEMA_VERSION + 1;
        info.write().expect("write runtime info");

        let error = RuntimeInfo::load(dir.path()).expect_err("should reject unknown schema");
        assert!(error.contains("different versions"), "{error}");
    }

    #[test]
    fn remove_is_tolerant_of_an_absent_file() {
        let dir = tempfile::tempdir().expect("temp dir");
        RuntimeInfo::remove(dir.path());
    }
}
