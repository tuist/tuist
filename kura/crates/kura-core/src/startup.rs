//! Startup recovery progress, which the store reports as it cleans segments. The kura crate's
//! `startup` module serves it on the bootstrap listener and ties it to the process's drain state.
use std::{
    sync::{Arc, Mutex},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use tokio::time::Instant;

use crate::metrics::Metrics;

/// Whether the process has started draining, so recovery stops at its next safe boundary.
pub trait DrainSignal: Send + Sync {
    fn is_draining(&self) -> bool;
}

pub const PROGRESS_TIMEOUT: Duration = Duration::from_secs(300);
// RocksDB open/replay is opaque to the application. Bound that phase
// separately rather than pretending a timer tick is recovery progress.
pub const STORE_OPEN_TIMEOUT: Duration = Duration::from_secs(900);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Preparing = 0,
    OpeningStore = 1,
    CleaningSegments = 2,
    Configuring = 3,
    Complete = 4,
    Failed = 5,
}

#[derive(Debug)]
pub enum RecoveryError {
    Interrupted,
    Failed(String),
}

impl RecoveryError {
    pub fn context(self, context: &str) -> Self {
        match self {
            Self::Interrupted => Self::Interrupted,
            Self::Failed(error) => Self::Failed(format!("{context}: {error}")),
        }
    }
}

impl From<String> for RecoveryError {
    fn from(error: String) -> Self {
        Self::Failed(error)
    }
}

impl std::fmt::Display for RecoveryError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Interrupted => formatter.write_str("startup recovery interrupted by shutdown"),
            Self::Failed(error) => formatter.write_str(error),
        }
    }
}

pub struct Recovery {
    progress: Mutex<(Phase, Instant)>,
    metrics: Metrics,
    runtime: Arc<dyn DrainSignal>,
}

impl Recovery {
    pub fn new(metrics: Metrics, runtime: Arc<dyn DrainSignal>) -> Arc<Self> {
        let recovery = Arc::new(Self {
            progress: Mutex::new((Phase::Preparing, Instant::now())),
            metrics,
            runtime,
        });
        recovery.set_phase(Phase::Preparing);
        recovery
    }

    pub fn set_phase(&self, phase: Phase) {
        *self.progress.lock().expect("startup progress poisoned") = (phase, Instant::now());
        self.metrics.record_startup_phase(phase as i64);
        self.record_timestamp();
        tracing::info!(?phase, "startup recovery phase changed");
    }

    fn record_timestamp(&self) {
        self.metrics.record_startup_progress_timestamp(
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs() as i64,
        );
    }

    pub fn check_running(&self) -> Result<(), RecoveryError> {
        if self.runtime.is_draining() {
            return Err(RecoveryError::Interrupted);
        }
        Ok(())
    }

    pub fn completed_work(&self, committed: bool) -> Result<(), RecoveryError> {
        let mut progress = self.progress.lock().expect("startup progress poisoned");
        if progress.0 != Phase::CleaningSegments {
            return Ok(());
        }
        progress.1 = Instant::now();
        self.record_timestamp();
        self.metrics.record_startup_work(committed);
        drop(progress);
        self.check_running()
    }

    pub fn metrics(&self) -> &Metrics {
        &self.metrics
    }

    pub fn healthy(&self) -> bool {
        let (phase, last_progress) = *self.progress.lock().expect("startup progress poisoned");
        // A requested drain is not a liveness failure. The signal handler
        // prevents activation and recovery stops at the next safe boundary.
        phase != Phase::Failed
            && (phase == Phase::Complete
                || last_progress.elapsed()
                    < if phase == Phase::OpeningStore {
                        STORE_OPEN_TIMEOUT
                    } else {
                        PROGRESS_TIMEOUT
                    })
    }
}

/// A drain flag for tests that exercise recovery without the kura crate's runtime state.
#[cfg(test)]
#[derive(Default)]
pub struct TestDrain(std::sync::atomic::AtomicBool);

#[cfg(test)]
impl TestDrain {
    pub fn request_drain(&self) {
        self.0.store(true, std::sync::atomic::Ordering::SeqCst);
    }
}

#[cfg(test)]
impl DrainSignal for TestDrain {
    fn is_draining(&self) -> bool {
        self.0.load(std::sync::atomic::Ordering::SeqCst)
    }
}
