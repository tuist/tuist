use std::sync::Arc;

use tokio::sync::{OwnedSemaphorePermit, Semaphore};

use super::MemoryPressure;

const MIN_REAPI_RESPONSE_BUDGET_BYTES: usize = 8 * 1024 * 1024;
const MAX_REAPI_RESPONSE_BUDGET_BYTES: usize = 64 * 1024 * 1024;
const MAX_REAPI_MATERIALIZATION_POOL_BYTES: usize = 128 * 1024 * 1024;
const MIN_MMAP_SERVING_POOL_BYTES: usize = 64 * 1024 * 1024;
const MAX_MMAP_SERVING_POOL_BYTES: usize = 512 * 1024 * 1024;

pub(super) struct MemoryPools {
    reapi_materialization: Arc<Semaphore>,
    mmap_serving: Arc<Semaphore>,
    reapi_materialization_bytes: usize,
    mmap_serving_bytes: usize,
}

impl MemoryPools {
    pub(super) fn new(soft_limit_bytes: u64, hard_limit_bytes: u64) -> Self {
        let reapi_materialization_bytes =
            reapi_materialization_pool_bytes(soft_limit_bytes, hard_limit_bytes);
        let mmap_serving_bytes = mmap_serving_pool_bytes(soft_limit_bytes, hard_limit_bytes);
        Self {
            reapi_materialization: Arc::new(Semaphore::new(reapi_materialization_bytes)),
            mmap_serving: Arc::new(Semaphore::new(mmap_serving_bytes)),
            reapi_materialization_bytes,
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
        let normal_budget = normal_budget.min(self.reapi_materialization_bytes);
        match pressure {
            MemoryPressure::Normal => normal_budget,
            MemoryPressure::Constrained => normal_budget / 2,
            MemoryPressure::Critical => 0,
        }
    }

    pub(super) fn reapi_materialization_bytes(&self) -> usize {
        self.reapi_materialization_bytes
    }

    pub(super) async fn acquire_reapi_materialization(
        &self,
        permits: u32,
    ) -> Result<OwnedSemaphorePermit, ()> {
        self.reapi_materialization
            .clone()
            .acquire_many_owned(permits)
            .await
            .map_err(|_| ())
    }

    pub(super) fn try_acquire_reapi_materialization(
        &self,
        permits: u32,
    ) -> Result<OwnedSemaphorePermit, ()> {
        self.reapi_materialization
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

fn reapi_materialization_pool_bytes(soft_limit_bytes: u64, hard_limit_bytes: u64) -> usize {
    let headroom_bytes = hard_limit_bytes.saturating_sub(soft_limit_bytes) / 2;
    clamp_u64(
        headroom_bytes,
        1,
        MAX_REAPI_MATERIALIZATION_POOL_BYTES as u64,
    ) as usize
}

fn mmap_serving_pool_bytes(soft_limit_bytes: u64, hard_limit_bytes: u64) -> usize {
    let headroom_bytes = hard_limit_bytes.saturating_sub(soft_limit_bytes);
    clamp_u64(
        headroom_bytes,
        MIN_MMAP_SERVING_POOL_BYTES as u64,
        MAX_MMAP_SERVING_POOL_BYTES as u64,
    ) as usize
}
