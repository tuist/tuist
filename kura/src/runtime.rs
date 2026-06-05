use std::{
    fs::{File, OpenOptions},
    io::Write,
    path::Path,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[cfg(test)]
use std::path::PathBuf;

use tokio::sync::{Notify, futures::Notified};

use crate::metrics::Metrics;

const DATA_DIR_LOCK_FILE: &str = ".kura.writer.lock";
const PUBLIC_REQUEST_LATENCY_EWMA_DENOMINATOR: u64 = 8;
const PUBLIC_REQUEST_LATENCY_STALE_MS: u64 = 30_000;
const MAX_PUBLIC_LATENCY_PRESSURE_DIVISOR: usize = 64;

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
    writer_lock_owned: AtomicBool,
    http_inflight: AtomicUsize,
    public_http_inflight: AtomicUsize,
    grpc_inflight: AtomicUsize,
    public_request_latency_ewma_micros: AtomicU64,
    public_request_latency_sampled_at_ms: AtomicU64,
    outbox_depth: AtomicUsize,
    inflight_changed: Notify,
}

impl RuntimeState {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            draining: AtomicBool::new(false),
            serving: AtomicBool::new(false),
            writer_lock_owned: AtomicBool::new(true),
            http_inflight: AtomicUsize::new(0),
            public_http_inflight: AtomicUsize::new(0),
            grpc_inflight: AtomicUsize::new(0),
            public_request_latency_ewma_micros: AtomicU64::new(0),
            public_request_latency_sampled_at_ms: AtomicU64::new(0),
            outbox_depth: AtomicUsize::new(0),
            inflight_changed: Notify::new(),
        })
    }

    pub fn update_outbox_depth(&self, depth: usize) {
        self.outbox_depth.store(depth, Ordering::Relaxed);
    }

    pub fn outbox_depth(&self) -> usize {
        self.outbox_depth.load(Ordering::Relaxed)
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

    pub fn clear_serving(&self) -> bool {
        self.serving.swap(false, Ordering::SeqCst)
    }

    pub fn is_serving(&self) -> bool {
        self.serving.load(Ordering::SeqCst)
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

    pub fn public_http_inflight(&self) -> usize {
        self.public_http_inflight.load(Ordering::SeqCst)
    }

    pub fn grpc_inflight(&self) -> usize {
        self.grpc_inflight.load(Ordering::SeqCst)
    }

    pub fn public_inflight(&self) -> usize {
        self.public_http_inflight() + self.grpc_inflight()
    }

    #[cfg(test)]
    pub fn public_request_latency_ewma(&self) -> Option<Duration> {
        let micros = self
            .public_request_latency_ewma_micros
            .load(Ordering::SeqCst);
        if micros == 0 {
            None
        } else {
            Some(Duration::from_micros(micros))
        }
    }

    pub fn public_latency_pressure_divisor(&self, target_ms: u64) -> usize {
        if target_ms == 0 {
            return 1;
        }

        let ewma_micros = self
            .public_request_latency_ewma_micros
            .load(Ordering::SeqCst);
        if ewma_micros == 0 {
            return 1;
        }

        let sampled_at_ms = self
            .public_request_latency_sampled_at_ms
            .load(Ordering::SeqCst);
        if sampled_at_ms == 0
            || now_ms().saturating_sub(sampled_at_ms) > PUBLIC_REQUEST_LATENCY_STALE_MS
        {
            return 1;
        }

        let target_micros = target_ms.saturating_mul(1_000).max(1);
        let divisor = ewma_micros.div_ceil(target_micros).max(1) as usize;
        divisor.min(MAX_PUBLIC_LATENCY_PRESSURE_DIVISOR)
    }

    pub fn total_inflight(&self) -> usize {
        self.http_inflight() + self.grpc_inflight()
    }

    pub fn inflight_changed(&self) -> Notified<'_> {
        self.inflight_changed.notified()
    }

    pub fn start_http_request(
        self: &Arc<Self>,
        metrics: &Metrics,
        traffic_class: HttpTrafficClass,
    ) -> InflightGuard {
        let count = self.http_inflight.fetch_add(1, Ordering::SeqCst) + 1;
        metrics.update_http_inflight(count);
        if traffic_class.contributes_to_public_load() {
            let count = self.public_http_inflight.fetch_add(1, Ordering::SeqCst) + 1;
            metrics.update_public_http_inflight(count);
        }
        self.inflight_changed.notify_waiters();
        InflightGuard::new(
            self.clone(),
            metrics.clone(),
            InflightKind::Http {
                public_load: traffic_class.contributes_to_public_load(),
            },
        )
    }

    pub fn start_grpc_request(self: &Arc<Self>, metrics: &Metrics) -> InflightGuard {
        let count = self.grpc_inflight.fetch_add(1, Ordering::SeqCst) + 1;
        metrics.update_grpc_inflight(count);
        self.inflight_changed.notify_waiters();
        InflightGuard::new(self.clone(), metrics.clone(), InflightKind::Grpc)
    }

    fn record_public_request_latency(&self, metrics: &Metrics, duration: Duration) {
        let sample_micros = duration.as_micros().min(u64::MAX as u128) as u64;
        if sample_micros == 0 {
            return;
        }

        let mut current = self
            .public_request_latency_ewma_micros
            .load(Ordering::SeqCst);
        loop {
            let next = if current == 0 {
                sample_micros
            } else {
                ((current * (PUBLIC_REQUEST_LATENCY_EWMA_DENOMINATOR - 1)) + sample_micros)
                    / PUBLIC_REQUEST_LATENCY_EWMA_DENOMINATOR
            };
            match self.public_request_latency_ewma_micros.compare_exchange(
                current,
                next,
                Ordering::SeqCst,
                Ordering::SeqCst,
            ) {
                Ok(_) => {
                    self.public_request_latency_sampled_at_ms
                        .store(now_ms(), Ordering::SeqCst);
                    metrics.update_public_request_latency_ewma(Duration::from_micros(next));
                    break;
                }
                Err(actual) => current = actual,
            }
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HttpTrafficClass {
    Public,
    Background,
}

impl HttpTrafficClass {
    fn contributes_to_public_load(self) -> bool {
        matches!(self, Self::Public)
    }
}

#[derive(Clone, Copy)]
enum InflightKind {
    Http { public_load: bool },
    Grpc,
}

pub struct InflightGuard {
    runtime: Arc<RuntimeState>,
    metrics: Metrics,
    kind: InflightKind,
    started_at: Instant,
    active: bool,
}

impl InflightGuard {
    fn new(runtime: Arc<RuntimeState>, metrics: Metrics, kind: InflightKind) -> Self {
        Self {
            runtime,
            metrics,
            kind,
            started_at: Instant::now(),
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
        let public_load = matches!(
            self.kind,
            InflightKind::Http { public_load: true } | InflightKind::Grpc
        );
        match self.kind {
            InflightKind::Http { public_load } => {
                let previous = self.runtime.http_inflight.fetch_sub(1, Ordering::SeqCst);
                self.metrics
                    .update_http_inflight(previous.saturating_sub(1));
                if public_load {
                    let previous = self
                        .runtime
                        .public_http_inflight
                        .fetch_sub(1, Ordering::SeqCst);
                    self.metrics
                        .update_public_http_inflight(previous.saturating_sub(1));
                }
            }
            InflightKind::Grpc => {
                let previous = self.runtime.grpc_inflight.fetch_sub(1, Ordering::SeqCst);
                self.metrics
                    .update_grpc_inflight(previous.saturating_sub(1));
            }
        }
        if public_load {
            self.runtime
                .record_public_request_latency(&self.metrics, self.started_at.elapsed());
        }
        self.runtime.inflight_changed.notify_waiters();
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0))
        .as_millis() as u64
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
    use std::time::Duration;

    use tempfile::tempdir;
    use tokio::time::timeout;

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

    #[tokio::test]
    async fn inflight_change_notification_resolves_on_request_completion() {
        let runtime = RuntimeState::new();
        let metrics = Metrics::new("region".into(), "tenant".into());
        let guard = runtime.start_http_request(&metrics, HttpTrafficClass::Public);

        let notified = runtime.inflight_changed();
        drop(guard);

        timeout(Duration::from_secs(1), notified)
            .await
            .expect("request completion should wake inflight waiters");
    }

    #[test]
    fn public_http_inflight_excludes_background_http_requests() {
        let runtime = RuntimeState::new();
        let metrics = Metrics::new("region".into(), "tenant".into());

        let background = runtime.start_http_request(&metrics, HttpTrafficClass::Background);
        assert_eq!(runtime.http_inflight(), 1);
        assert_eq!(runtime.public_http_inflight(), 0);

        let public = runtime.start_http_request(&metrics, HttpTrafficClass::Public);
        assert_eq!(runtime.http_inflight(), 2);
        assert_eq!(runtime.public_http_inflight(), 1);
        assert_eq!(runtime.public_inflight(), 1);

        drop(public);
        assert_eq!(runtime.http_inflight(), 1);
        assert_eq!(runtime.public_http_inflight(), 0);

        drop(background);
        assert_eq!(runtime.http_inflight(), 0);
        assert_eq!(runtime.public_http_inflight(), 0);
    }

    #[test]
    fn public_latency_pressure_divisor_tracks_recent_request_latency() {
        let runtime = RuntimeState::new();
        let metrics = Metrics::new("region".into(), "tenant".into());

        assert_eq!(runtime.public_latency_pressure_divisor(100), 1);

        runtime.record_public_request_latency(&metrics, Duration::from_millis(250));

        assert_eq!(
            runtime.public_request_latency_ewma(),
            Some(Duration::from_millis(250))
        );
        assert_eq!(runtime.public_latency_pressure_divisor(100), 3);
        assert_eq!(runtime.public_latency_pressure_divisor(0), 1);
    }
}
