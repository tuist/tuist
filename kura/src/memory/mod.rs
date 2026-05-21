use std::sync::{
    Arc,
    atomic::{AtomicU8, Ordering},
};

use tokio::sync::{OwnedSemaphorePermit, Semaphore};

use crate::metrics::Metrics;

const RECOVERY_NUMERATOR: u64 = 9;
const RECOVERY_DENOMINATOR: u64 = 10;
const MIN_REAPI_RESPONSE_BUDGET_BYTES: usize = 8 * 1024 * 1024;
const MAX_REAPI_RESPONSE_BUDGET_BYTES: usize = 64 * 1024 * 1024;
const MIN_REAPI_MATERIALIZATION_POOL_BYTES: usize = 16 * 1024 * 1024;
const MAX_REAPI_MATERIALIZATION_POOL_BYTES: usize = 128 * 1024 * 1024;

#[derive(Clone)]
pub struct MemoryController {
    inner: Arc<MemoryControllerInner>,
}

struct MemoryControllerInner {
    soft_limit_bytes: u64,
    hard_limit_bytes: u64,
    state: AtomicU8,
    reapi_materialization_pool: Arc<Semaphore>,
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
                reapi_materialization_pool: Arc::new(Semaphore::new(
                    reapi_materialization_pool_bytes(soft_limit_bytes),
                )),
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

    pub fn bounded_cache_target_entries(&self, capacity: usize) -> usize {
        match self.pressure() {
            MemoryPressure::Normal => capacity,
            MemoryPressure::Constrained => capacity / 2,
            MemoryPressure::Critical => 0,
        }
    }

    pub fn reapi_response_budget_bytes(&self) -> usize {
        let normal_budget = clamp_u64(
            self.inner.soft_limit_bytes / 4,
            MIN_REAPI_RESPONSE_BUDGET_BYTES as u64,
            MAX_REAPI_RESPONSE_BUDGET_BYTES as u64,
        ) as usize;
        match self.pressure() {
            MemoryPressure::Normal => normal_budget,
            MemoryPressure::Constrained => normal_budget / 2,
            MemoryPressure::Critical => 0,
        }
    }

    pub fn reapi_materialization_pool_bytes(&self) -> usize {
        reapi_materialization_pool_bytes(self.inner.soft_limit_bytes)
    }

    pub fn try_acquire_reapi_materialization(
        &self,
        requested_bytes: usize,
    ) -> Result<Option<OwnedSemaphorePermit>, ()> {
        if requested_bytes == 0 {
            return Ok(None);
        }
        let permits = u32::try_from(requested_bytes).map_err(|_| ())?;
        self.inner
            .reapi_materialization_pool
            .clone()
            .try_acquire_many_owned(permits)
            .map(Some)
            .map_err(|_| ())
    }
}

fn recovery_bytes(limit: u64) -> u64 {
    limit
        .saturating_mul(RECOVERY_NUMERATOR)
        .saturating_div(RECOVERY_DENOMINATOR)
}

fn clamp_u64(value: u64, minimum: u64, maximum: u64) -> u64 {
    value.max(minimum).min(maximum)
}

fn reapi_materialization_pool_bytes(soft_limit_bytes: u64) -> usize {
    clamp_u64(
        soft_limit_bytes / 2,
        MIN_REAPI_MATERIALIZATION_POOL_BYTES as u64,
        MAX_REAPI_MATERIALIZATION_POOL_BYTES as u64,
    ) as usize
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

    #[test]
    fn reapi_response_budget_shrinks_with_memory_pressure() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::new(metrics, 128 * 1024 * 1024, 256 * 1024 * 1024);

        assert_eq!(controller.reapi_response_budget_bytes(), 32 * 1024 * 1024);

        controller.observe(128 * 1024 * 1024);
        assert_eq!(controller.reapi_response_budget_bytes(), 16 * 1024 * 1024);

        controller.observe(256 * 1024 * 1024);
        assert_eq!(controller.reapi_response_budget_bytes(), 0);
    }

    #[test]
    fn reapi_materialization_pool_is_clamped_from_soft_limit() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let small = MemoryController::new(metrics.clone(), 24 * 1024 * 1024, 48 * 1024 * 1024);
        let medium = MemoryController::new(metrics.clone(), 128 * 1024 * 1024, 256 * 1024 * 1024);
        let large = MemoryController::new(metrics, 8 * 1024 * 1024 * 1024, 9 * 1024 * 1024 * 1024);

        assert_eq!(small.reapi_materialization_pool_bytes(), 16 * 1024 * 1024);
        assert_eq!(medium.reapi_materialization_pool_bytes(), 64 * 1024 * 1024);
        assert_eq!(large.reapi_materialization_pool_bytes(), 128 * 1024 * 1024);
    }
}
