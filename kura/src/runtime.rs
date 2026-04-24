use std::{
    fs::{File, OpenOptions},
    io::Write,
    path::Path,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
};

#[cfg(test)]
use std::path::PathBuf;

use crate::metrics::Metrics;

const DATA_DIR_LOCK_FILE: &str = ".kura.writer.lock";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrafficState {
    Joining,
    Serving,
    Draining,
}

impl TrafficState {
    pub fn as_i64(self) -> i64 {
        match self {
            Self::Joining => 0,
            Self::Serving => 1,
            Self::Draining => 2,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Joining => "joining",
            Self::Serving => "serving",
            Self::Draining => "draining",
        }
    }
}

pub struct RuntimeState {
    draining: AtomicBool,
    serving: AtomicBool,
    initial_discovery_completed: AtomicBool,
    writer_lock_owned: AtomicBool,
    http_inflight: AtomicUsize,
    grpc_inflight: AtomicUsize,
}

impl RuntimeState {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            draining: AtomicBool::new(false),
            serving: AtomicBool::new(false),
            initial_discovery_completed: AtomicBool::new(false),
            writer_lock_owned: AtomicBool::new(true),
            http_inflight: AtomicUsize::new(0),
            grpc_inflight: AtomicUsize::new(0),
        })
    }

    pub fn request_drain(&self) -> bool {
        !self.draining.swap(true, Ordering::SeqCst)
    }

    pub fn is_draining(&self) -> bool {
        self.draining.load(Ordering::SeqCst)
    }

    pub fn mark_serving(&self) -> bool {
        !self.serving.swap(true, Ordering::SeqCst)
    }

    pub fn is_serving(&self) -> bool {
        self.serving.load(Ordering::SeqCst)
    }

    pub fn mark_initial_discovery_completed(&self) -> bool {
        !self
            .initial_discovery_completed
            .swap(true, Ordering::SeqCst)
    }

    pub fn initial_discovery_completed(&self) -> bool {
        self.initial_discovery_completed.load(Ordering::SeqCst)
    }

    pub fn writer_lock_owned(&self) -> bool {
        self.writer_lock_owned.load(Ordering::SeqCst)
    }

    pub fn traffic_state(&self) -> TrafficState {
        if self.is_draining() {
            TrafficState::Draining
        } else if self.is_serving() {
            TrafficState::Serving
        } else {
            TrafficState::Joining
        }
    }

    pub fn http_inflight(&self) -> usize {
        self.http_inflight.load(Ordering::SeqCst)
    }

    pub fn grpc_inflight(&self) -> usize {
        self.grpc_inflight.load(Ordering::SeqCst)
    }

    pub fn start_http_request(self: &Arc<Self>, metrics: &Metrics) -> InflightGuard {
        let count = self.http_inflight.fetch_add(1, Ordering::SeqCst) + 1;
        metrics.update_http_inflight(count);
        InflightGuard::new(self.clone(), metrics.clone(), InflightKind::Http)
    }

    pub fn start_grpc_request(self: &Arc<Self>, metrics: &Metrics) -> InflightGuard {
        let count = self.grpc_inflight.fetch_add(1, Ordering::SeqCst) + 1;
        metrics.update_grpc_inflight(count);
        InflightGuard::new(self.clone(), metrics.clone(), InflightKind::Grpc)
    }
}

#[derive(Clone, Copy)]
enum InflightKind {
    Http,
    Grpc,
}

pub struct InflightGuard {
    runtime: Arc<RuntimeState>,
    metrics: Metrics,
    kind: InflightKind,
    active: bool,
}

impl InflightGuard {
    fn new(runtime: Arc<RuntimeState>, metrics: Metrics, kind: InflightKind) -> Self {
        Self {
            runtime,
            metrics,
            kind,
            active: true,
        }
    }
}

impl Drop for InflightGuard {
    fn drop(&mut self) {
        if !self.active {
            return;
        }
        self.active = false;
        match self.kind {
            InflightKind::Http => {
                let previous = self.runtime.http_inflight.fetch_sub(1, Ordering::SeqCst);
                self.metrics
                    .update_http_inflight(previous.saturating_sub(1));
            }
            InflightKind::Grpc => {
                let previous = self.runtime.grpc_inflight.fetch_sub(1, Ordering::SeqCst);
                self.metrics
                    .update_grpc_inflight(previous.saturating_sub(1));
            }
        }
    }
}

pub struct DataDirLock {
    _file: File,
    #[cfg(test)]
    path: PathBuf,
}

impl DataDirLock {
    pub fn acquire(data_dir: &Path) -> Result<Self, String> {
        let path = data_dir.join(DATA_DIR_LOCK_FILE);
        let mut file = OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .truncate(false)
            .open(&path)
            .map_err(|error| {
                format!(
                    "failed to open writer lock file {}: {error}",
                    path.display()
                )
            })?;

        try_lock_exclusive(&file).map_err(|error| {
            format!("failed to acquire writer lock {}: {error}", path.display())
        })?;

        file.set_len(0).map_err(|error| {
            format!(
                "failed to reset writer lock file {}: {error}",
                path.display()
            )
        })?;
        writeln!(file, "pid={}", std::process::id()).map_err(|error| {
            format!(
                "failed to write writer lock file {}: {error}",
                path.display()
            )
        })?;
        file.flush().map_err(|error| {
            format!(
                "failed to flush writer lock file {}: {error}",
                path.display()
            )
        })?;

        Ok(Self {
            _file: file,
            #[cfg(test)]
            path,
        })
    }

    #[cfg(test)]
    pub fn path(&self) -> &Path {
        &self.path
    }
}

#[cfg(unix)]
fn try_lock_exclusive(file: &File) -> Result<(), std::io::Error> {
    use std::os::fd::AsRawFd;

    let result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if result == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}

#[cfg(not(unix))]
fn try_lock_exclusive(_file: &File) -> Result<(), std::io::Error> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use tempfile::tempdir;

    use super::*;

    #[test]
    fn data_dir_lock_rejects_second_owner() {
        let temp_dir = tempdir().expect("failed to create temp dir");
        let first = DataDirLock::acquire(temp_dir.path()).expect("first lock should succeed");
        let second = DataDirLock::acquire(temp_dir.path());
        assert!(second.is_err(), "second lock acquisition should fail");
        assert_eq!(
            first.path(),
            temp_dir.path().join(DATA_DIR_LOCK_FILE).as_path()
        );
    }
}
