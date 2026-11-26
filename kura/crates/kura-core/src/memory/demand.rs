use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

/// Width of one demand window. `/status/rollout` reports the peak over the
/// current window and the one before it, so a reader polling at least this
/// often sees every window's peak at least once, and any number of readers
/// can poll without resetting what the others see.
const DEMAND_WINDOW: Duration = Duration::from_secs(60);

/// What the foreground asked of the floor pool, for sizing the floor.
///
/// Demand is the bytes held plus the bytes foreground callers are queued for,
/// so a burst the pool could not admit shows how far it overshot rather than
/// stopping at the pool's capacity. Memory pressure cannot stand in for this:
/// a pool sized from the floor fills and sheds while the container is far
/// from its watermarks.
pub(super) struct FloorDemand {
    started_at: Instant,
    queued_bytes: AtomicU64,
    waits: AtomicU64,
    timeouts: AtomicU64,
    peaks: Mutex<DemandPeaks>,
}

#[derive(Default)]
struct DemandPeaks {
    window: u64,
    current: u64,
    previous: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FloorDemandSnapshot {
    /// Peak demand over the last one to two windows.
    pub recent_peak_bytes: u64,
    /// Foreground admissions that queued on a full floor pool.
    pub waits: u64,
    /// Queued foreground admissions that gave up, each a shed or a refused
    /// upload.
    pub timeouts: u64,
}

impl FloorDemand {
    pub(super) fn new() -> Self {
        Self {
            started_at: Instant::now(),
            queued_bytes: AtomicU64::new(0),
            waits: AtomicU64::new(0),
            timeouts: AtomicU64::new(0),
            peaks: Mutex::new(DemandPeaks::default()),
        }
    }

    pub(super) fn record_admitted(&self, reserved_bytes: u64) {
        let demand = reserved_bytes.saturating_add(self.queued_bytes.load(Ordering::Acquire));
        self.record_at(demand, Instant::now());
    }

    pub(super) fn begin_wait(&self, reserved_bytes: u64, requested_bytes: u64) {
        self.waits.fetch_add(1, Ordering::Relaxed);
        let queued = self
            .queued_bytes
            .fetch_add(requested_bytes, Ordering::AcqRel)
            .saturating_add(requested_bytes);
        self.record_at(reserved_bytes.saturating_add(queued), Instant::now());
    }

    pub(super) fn end_wait(&self, requested_bytes: u64) {
        self.queued_bytes
            .fetch_sub(requested_bytes, Ordering::AcqRel);
    }

    pub(super) fn record_timeout(&self) {
        self.timeouts.fetch_add(1, Ordering::Relaxed);
    }

    pub(super) fn snapshot(&self) -> FloorDemandSnapshot {
        self.snapshot_at(Instant::now())
    }

    fn window_at(&self, now: Instant) -> u64 {
        now.saturating_duration_since(self.started_at).as_secs() / DEMAND_WINDOW.as_secs()
    }

    fn record_at(&self, demand_bytes: u64, now: Instant) {
        let window = self.window_at(now);
        let mut peaks = self.peaks.lock().unwrap_or_else(|e| e.into_inner());
        peaks.roll_to(window);
        peaks.current = peaks.current.max(demand_bytes);
    }

    fn snapshot_at(&self, now: Instant) -> FloorDemandSnapshot {
        let window = self.window_at(now);
        let recent_peak_bytes = {
            let mut peaks = self.peaks.lock().unwrap_or_else(|e| e.into_inner());
            peaks.roll_to(window);
            peaks.current.max(peaks.previous)
        };
        FloorDemandSnapshot {
            recent_peak_bytes,
            waits: self.waits.load(Ordering::Relaxed),
            timeouts: self.timeouts.load(Ordering::Relaxed),
        }
    }
}

impl DemandPeaks {
    fn roll_to(&mut self, window: u64) {
        if window == self.window {
            return;
        }
        self.previous = if window == self.window + 1 {
            self.current
        } else {
            0
        };
        self.current = 0;
        self.window = window;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recent_peak_survives_one_window_rollover_and_expires_after_two() {
        let demand = FloorDemand::new();
        let start = demand.started_at;
        demand.record_at(700, start + Duration::from_secs(59));
        demand.record_at(100, start + Duration::from_secs(61));

        assert_eq!(
            demand
                .snapshot_at(start + Duration::from_secs(119))
                .recent_peak_bytes,
            700
        );
        assert_eq!(
            demand
                .snapshot_at(start + Duration::from_secs(121))
                .recent_peak_bytes,
            100
        );
        assert_eq!(
            demand
                .snapshot_at(start + Duration::from_secs(181))
                .recent_peak_bytes,
            0
        );
    }

    #[test]
    fn a_skipped_window_drops_the_older_peak() {
        let demand = FloorDemand::new();
        let start = demand.started_at;
        demand.record_at(700, start + Duration::from_secs(10));
        demand.record_at(50, start + Duration::from_secs(130));

        assert_eq!(
            demand
                .snapshot_at(start + Duration::from_secs(131))
                .recent_peak_bytes,
            50
        );
    }

    #[test]
    fn queued_bytes_count_toward_demand_until_the_wait_ends() {
        let demand = FloorDemand::new();
        demand.begin_wait(600, 300);
        demand.begin_wait(600, 200);
        assert_eq!(demand.snapshot().recent_peak_bytes, 1100);
        demand.end_wait(300);
        demand.end_wait(200);
        demand.record_admitted(1200);
        let snapshot = demand.snapshot();
        assert_eq!(snapshot.recent_peak_bytes, 1200);
        assert_eq!(snapshot.waits, 2);
    }
}
