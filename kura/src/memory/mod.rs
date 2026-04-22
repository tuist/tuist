use std::sync::{
    Arc,
    atomic::{AtomicU8, Ordering},
};

use crate::metrics::Metrics;

const RECOVERY_NUMERATOR: u64 = 9;
const RECOVERY_DENOMINATOR: u64 = 10;

#[derive(Clone)]
pub struct MemoryController {
    inner: Arc<MemoryControllerInner>,
}

struct MemoryControllerInner {
    soft_limit_bytes: u64,
    hard_limit_bytes: u64,
    state: AtomicU8,
    metrics: Metrics,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum MemoryPressure {
    Normal,
    Constrained,
    Critical,
}

impl MemoryPressure {
    fn as_u8(self) -> u8 {
        match self {
            Self::Normal => 0,
            Self::Constrained => 1,
            Self::Critical => 2,
        }
    }

    pub fn as_i64(self) -> i64 {
        self.as_u8() as i64
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Normal => "normal",
            Self::Constrained => "constrained",
            Self::Critical => "critical",
        }
    }

    fn from_u8(value: u8) -> Self {
        match value {
            1 => Self::Constrained,
            2 => Self::Critical,
            _ => Self::Normal,
        }
    }
}

impl MemoryController {
    pub fn new(metrics: Metrics, soft_limit_bytes: u64, hard_limit_bytes: u64) -> Self {
        metrics.update_memory_limits(soft_limit_bytes, hard_limit_bytes);
        metrics.update_memory_pressure_state(MemoryPressure::Normal.as_i64());
        Self {
            inner: Arc::new(MemoryControllerInner {
                soft_limit_bytes,
                hard_limit_bytes,
                state: AtomicU8::new(MemoryPressure::Normal.as_u8()),
                metrics,
            }),
        }
    }

    pub fn observe(&self, resident_bytes: u64) -> MemoryPressure {
        let current = self.pressure();
        let next = match current {
            MemoryPressure::Normal => {
                if resident_bytes >= self.inner.hard_limit_bytes {
                    MemoryPressure::Critical
                } else if resident_bytes >= self.inner.soft_limit_bytes {
                    MemoryPressure::Constrained
                } else {
                    MemoryPressure::Normal
                }
            }
            MemoryPressure::Constrained => {
                if resident_bytes >= self.inner.hard_limit_bytes {
                    MemoryPressure::Critical
                } else if resident_bytes <= recovery_bytes(self.inner.soft_limit_bytes) {
                    MemoryPressure::Normal
                } else {
                    MemoryPressure::Constrained
                }
            }
            MemoryPressure::Critical => {
                if resident_bytes <= recovery_bytes(self.inner.soft_limit_bytes) {
                    MemoryPressure::Normal
                } else if resident_bytes <= recovery_bytes(self.inner.hard_limit_bytes) {
                    MemoryPressure::Constrained
                } else {
                    MemoryPressure::Critical
                }
            }
        };

        if next != current {
            self.inner.state.store(next.as_u8(), Ordering::Relaxed);
            self.inner
                .metrics
                .record_memory_pressure_transition(current.as_str(), next.as_str());
        }
        self.inner
            .metrics
            .update_memory_pressure_state(next.as_i64());
        next
    }

    pub fn pressure(&self) -> MemoryPressure {
        MemoryPressure::from_u8(self.inner.state.load(Ordering::Relaxed))
    }

    pub fn allow_manifest_cache_admission(&self) -> bool {
        self.pressure() == MemoryPressure::Normal
    }

    pub fn allow_segment_refresh(&self) -> bool {
        self.pressure() == MemoryPressure::Normal
    }

    pub fn pause_outbox(&self) -> bool {
        self.pressure() == MemoryPressure::Critical
    }

    pub fn manifest_cache_target_bytes(&self, capacity_bytes: usize) -> usize {
        match self.pressure() {
            MemoryPressure::Normal => capacity_bytes,
            MemoryPressure::Constrained => capacity_bytes / 2,
            MemoryPressure::Critical => 0,
        }
    }
}

fn recovery_bytes(limit: u64) -> u64 {
    limit
        .saturating_mul(RECOVERY_NUMERATOR)
        .saturating_div(RECOVERY_DENOMINATOR)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pressure_uses_hysteresis_before_recovering() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::new(metrics, 100, 200);

        assert_eq!(controller.observe(150), MemoryPressure::Constrained);
        assert_eq!(controller.observe(95), MemoryPressure::Constrained);
        assert_eq!(controller.observe(90), MemoryPressure::Normal);
        assert_eq!(controller.observe(220), MemoryPressure::Critical);
        assert_eq!(controller.observe(185), MemoryPressure::Critical);
        assert_eq!(controller.observe(180), MemoryPressure::Constrained);
    }
}
