use std::sync::Arc;

use tokio::sync::{Mutex, OwnedMutexGuard, OwnedSemaphorePermit, Semaphore};

use crate::constants::{
    MAX_INLINE_REPLICATION_BODY_BYTES, RESPONSE_STREAM_CHUNK_BYTES,
    RESPONSE_STREAM_MIN_CHUNK_BYTES, RESPONSE_STREAM_SEND_BUFFER_BYTES,
};

use super::MemoryPressure;

const MIN_REAPI_RESPONSE_BUDGET_BYTES: usize = 8 * 1024 * 1024;
const MAX_REAPI_RESPONSE_BUDGET_BYTES: usize = 64 * 1024 * 1024;
const MAX_REAPI_MATERIALIZATION_POOL_BYTES: usize = 128 * 1024 * 1024;
const MIN_MMAP_SERVING_POOL_BYTES: usize = 64 * 1024 * 1024;
const MAX_MMAP_SERVING_POOL_BYTES: usize = 512 * 1024 * 1024;
const MAX_ENCODED_RESPONSE_STREAM_CHUNK_BYTES: usize =
    RESPONSE_STREAM_CHUNK_BYTES + RESPONSE_STREAM_MIN_CHUNK_BYTES;
const MAX_RESPONSE_STREAM_RESERVATION_BYTES: usize = MAX_ENCODED_RESPONSE_STREAM_CHUNK_BYTES * 4;
const MIN_RESPONSE_STREAM_POOL_BYTES: usize =
    MAX_INLINE_REPLICATION_BODY_BYTES as usize + MAX_RESPONSE_STREAM_RESERVATION_BYTES;
const MAX_RESPONSE_STREAM_POOL_BYTES: usize = 64 * 1024 * 1024;
const MAX_BOOTSTRAP_RESPONSE_STREAM_RESERVATION_BYTES: usize =
    MAX_INLINE_REPLICATION_BODY_BYTES as usize + RESPONSE_STREAM_CHUNK_BYTES * 4;
const MIN_BACKGROUND_RESPONSE_STREAM_POOL_BYTES: usize =
    MAX_BOOTSTRAP_RESPONSE_STREAM_RESERVATION_BYTES;
const MAX_BACKGROUND_RESPONSE_STREAM_POOL_BYTES: usize = RESPONSE_STREAM_CHUNK_BYTES * 4 * 16;

pub(super) struct MemoryPools {
    reapi_materialization: Arc<Semaphore>,
    mmap_serving: Arc<Semaphore>,
    response_streaming: Arc<Semaphore>,
    foreground_response_streaming: Arc<Semaphore>,
    background_response_streaming: Arc<Semaphore>,
    response_stream_waiters: Arc<Semaphore>,
    response_stream_admission: Arc<Mutex<()>>,
    degraded_response_streaming: Arc<Semaphore>,
    reapi_materialization_bytes: usize,
    mmap_serving_bytes: usize,
    response_streaming_bytes: usize,
    foreground_response_streaming_bytes: usize,
    degraded_response_stream_slots: usize,
}

impl MemoryPools {
    pub(super) fn new(
        runtime_limit_bytes: u64,
        soft_limit_bytes: u64,
        hard_limit_bytes: u64,
    ) -> Self {
        let reapi_materialization_bytes =
            reapi_materialization_pool_bytes(soft_limit_bytes, hard_limit_bytes);
        let mmap_serving_bytes = mmap_serving_pool_bytes(soft_limit_bytes, hard_limit_bytes);
        let response_streaming_bytes =
            response_streaming_pool_bytes(runtime_limit_bytes, soft_limit_bytes, hard_limit_bytes);
        let bootstrap_reserved_bytes =
            if response_streaming_bytes >= MAX_BOOTSTRAP_RESPONSE_STREAM_RESERVATION_BYTES * 2 {
                MAX_BOOTSTRAP_RESPONSE_STREAM_RESERVATION_BYTES
            } else {
                0
            };
        let foreground_response_streaming_bytes =
            response_streaming_bytes.saturating_sub(bootstrap_reserved_bytes);
        let response_stream_waiters = response_streaming_bytes
            .div_ceil(MAX_RESPONSE_STREAM_RESERVATION_BYTES)
            .max(1);
        let background_response_streaming_bytes = (response_streaming_bytes / 2)
            .clamp(
                MIN_BACKGROUND_RESPONSE_STREAM_POOL_BYTES,
                MAX_BACKGROUND_RESPONSE_STREAM_POOL_BYTES,
            )
            .min(response_streaming_bytes);
        // A degraded stream reserves only the 8 KiB chunk floor, but Hyper can
        // still hold up to one `RESPONSE_STREAM_SEND_BUFFER_BYTES` send buffer
        // per stream for a slow client. Counting degraded streams at that real
        // per-stream cost keeps their aggregate footprint inside the same
        // budget the weighted pool already accounts for, instead of letting it
        // grow with the file-descriptor pool.
        let degraded_response_stream_slots =
            (response_streaming_bytes / RESPONSE_STREAM_SEND_BUFFER_BYTES).max(1);
        Self {
            reapi_materialization: Arc::new(Semaphore::new(reapi_materialization_bytes)),
            mmap_serving: Arc::new(Semaphore::new(mmap_serving_bytes)),
            response_streaming: Arc::new(Semaphore::new(response_streaming_bytes)),
            foreground_response_streaming: Arc::new(Semaphore::new(
                foreground_response_streaming_bytes,
            )),
            background_response_streaming: Arc::new(Semaphore::new(
                background_response_streaming_bytes,
            )),
            response_stream_waiters: Arc::new(Semaphore::new(response_stream_waiters)),
            response_stream_admission: Arc::new(Mutex::new(())),
            degraded_response_streaming: Arc::new(Semaphore::new(degraded_response_stream_slots)),
            reapi_materialization_bytes,
            mmap_serving_bytes,
            response_streaming_bytes,
            foreground_response_streaming_bytes,
            degraded_response_stream_slots,
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
        let normal_budget = normal_budget.min(self.reapi_materialization_bytes / 2);
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

    pub(super) fn response_streaming_bytes(&self) -> usize {
        self.response_streaming_bytes
    }

    pub(super) fn try_acquire_response_streaming(
        &self,
        permits: u32,
    ) -> Result<OwnedSemaphorePermit, ()> {
        self.response_streaming
            .clone()
            .try_acquire_many_owned(permits)
            .map_err(|_| ())
    }

    pub(super) fn foreground_response_streaming_bytes(&self) -> usize {
        self.foreground_response_streaming_bytes
    }

    pub(super) fn try_acquire_foreground_response_streaming(
        &self,
        permits: u32,
    ) -> Result<OwnedSemaphorePermit, ()> {
        self.foreground_response_streaming
            .clone()
            .try_acquire_many_owned(permits)
            .map_err(|_| ())
    }

    pub(super) fn try_acquire_response_stream_waiter(&self) -> Result<OwnedSemaphorePermit, ()> {
        self.response_stream_waiters
            .clone()
            .try_acquire_owned()
            .map_err(|_| ())
    }

    pub(super) fn try_acquire_background_response_streaming(
        &self,
        permits: u32,
    ) -> Result<OwnedSemaphorePermit, ()> {
        self.background_response_streaming
            .clone()
            .try_acquire_many_owned(permits)
            .map_err(|_| ())
    }

    pub(super) async fn acquire_response_stream_admission_turn(&self) -> OwnedMutexGuard<()> {
        self.response_stream_admission.clone().lock_owned().await
    }

    pub(super) fn degraded_response_stream_slots(&self) -> usize {
        self.degraded_response_stream_slots
    }

    pub(super) async fn acquire_degraded_response_stream(&self) -> Option<OwnedSemaphorePermit> {
        self.degraded_response_streaming
            .clone()
            .acquire_owned()
            .await
            .ok()
    }
}

fn clamp_u64(value: u64, minimum: u64, maximum: u64) -> u64 {
    value.max(minimum).min(maximum)
}

fn reapi_materialization_pool_bytes(soft_limit_bytes: u64, hard_limit_bytes: u64) -> usize {
    let headroom_bytes = hard_limit_bytes.saturating_sub(soft_limit_bytes);
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

fn response_streaming_pool_bytes(
    runtime_limit_bytes: u64,
    soft_limit_bytes: u64,
    hard_limit_bytes: u64,
) -> usize {
    let pressure_gap = hard_limit_bytes.saturating_sub(soft_limit_bytes) / 2;
    let runtime_gap = runtime_limit_bytes.saturating_sub(hard_limit_bytes) / 2;
    clamp_u64(
        pressure_gap.min(runtime_gap),
        MIN_RESPONSE_STREAM_POOL_BYTES as u64,
        MAX_RESPONSE_STREAM_POOL_BYTES as u64,
    ) as usize
}
