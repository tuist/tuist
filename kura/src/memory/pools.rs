use std::sync::Arc;

use tokio::sync::{OwnedSemaphorePermit, Semaphore};

use super::MemoryPressure;

const MIN_REAPI_RESPONSE_BUDGET_BYTES: usize = 8 * 1024 * 1024;
const MAX_REAPI_RESPONSE_BUDGET_BYTES: usize = 64 * 1024 * 1024;
const MAX_REAPI_MATERIALIZATION_POOL_BYTES: usize = 128 * 1024 * 1024;
const MAX_MMAP_SERVING_POOL_BYTES: usize = 512 * 1024 * 1024;

pub(super) struct MemoryPools {
    transient: Arc<Semaphore>,
    mmap_serving: Arc<Semaphore>,
    transient_capacity_bytes: usize,
    reapi_materialization_limit_bytes: usize,
    mmap_serving_bytes: usize,
}

impl MemoryPools {
    pub(super) fn new(soft_limit_bytes: u64, hard_limit_bytes: u64) -> Self {
        let headroom_bytes = hard_limit_bytes.saturating_sub(soft_limit_bytes);
        let transient_capacity_bytes = semaphore_capacity(headroom_bytes);
        let reapi_materialization_limit_bytes =
            reapi_materialization_limit_bytes(transient_capacity_bytes);
        let mmap_serving_bytes = mmap_serving_bytes(headroom_bytes);
        Self {
            transient: Arc::new(Semaphore::new(transient_capacity_bytes)),
            mmap_serving: Arc::new(Semaphore::new(mmap_serving_bytes)),
            transient_capacity_bytes,
            reapi_materialization_limit_bytes,
            mmap_serving_bytes,
        }
    }

    pub(super) fn reapi_response_budget_bytes(
        &self,
        soft_limit_bytes: u64,
        pressure: MemoryPressure,
    ) -> usize {
        let normal_budget = clamp_u64(
            soft_limit_bytes / 4,
            MIN_REAPI_RESPONSE_BUDGET_BYTES as u64,
            MAX_REAPI_RESPONSE_BUDGET_BYTES as u64,
        ) as usize;
        let normal_budget = normal_budget.min(self.reapi_materialization_limit_bytes);
        match pressure {
            MemoryPressure::Normal => normal_budget,
            MemoryPressure::Constrained => normal_budget / 2,
            MemoryPressure::Critical => 0,
        }
    }

    pub(super) fn reapi_materialization_limit_bytes(&self) -> usize {
        self.reapi_materialization_limit_bytes
    }

    pub(super) fn transient_capacity_bytes(&self) -> usize {
        self.transient_capacity_bytes
    }

    pub(super) fn transient_reserved_bytes(&self) -> usize {
        self.transient_capacity_bytes
            .saturating_sub(self.transient.available_permits())
    }

    pub(super) async fn acquire_transient(&self, permits: u32) -> Result<OwnedSemaphorePermit, ()> {
        self.transient
            .clone()
            .acquire_many_owned(permits)
            .await
            .map_err(|_| ())
    }

    pub(super) fn try_acquire_transient(&self, permits: u32) -> Result<OwnedSemaphorePermit, ()> {
        self.transient
            .clone()
            .try_acquire_many_owned(permits)
            .map_err(|_| ())
    }

    pub(super) fn mmap_serving_bytes(&self) -> usize {
        self.mmap_serving_bytes
    }

    pub(super) fn try_acquire_mmap_serving(&self, permits: u32) -> Option<OwnedSemaphorePermit> {
        self.mmap_serving
            .clone()
            .try_acquire_many_owned(permits)
            .ok()
    }
}

fn clamp_u64(value: u64, minimum: u64, maximum: u64) -> u64 {
    value.max(minimum).min(maximum)
}

fn semaphore_capacity(bytes: u64) -> usize {
    usize::try_from(bytes)
        .unwrap_or(usize::MAX)
        .min(Semaphore::MAX_PERMITS)
}

fn reapi_materialization_limit_bytes(transient_capacity_bytes: usize) -> usize {
    transient_capacity_bytes
        .saturating_div(2)
        .clamp(1, MAX_REAPI_MATERIALIZATION_POOL_BYTES)
}

fn mmap_serving_bytes(headroom_bytes: u64) -> usize {
    semaphore_capacity(headroom_bytes).min(MAX_MMAP_SERVING_POOL_BYTES)
}
