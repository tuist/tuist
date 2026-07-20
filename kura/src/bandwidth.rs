use std::{sync::Arc, time::Duration};

use tokio::{
    sync::Mutex,
    time::{Instant, sleep},
};

use crate::runtime::RuntimeState;

pub struct BandwidthLimiter {
    bytes_per_second: u64,
    public_latency_target_ms: u64,
    runtime: Arc<RuntimeState>,
    next_available: Mutex<Instant>,
}

impl BandwidthLimiter {
    pub fn new(
        bytes_per_second: u64,
        public_latency_target_ms: u64,
        runtime: Arc<RuntimeState>,
    ) -> Option<Self> {
        if bytes_per_second == 0 {
            return None;
        }

        Some(Self {
            bytes_per_second,
            public_latency_target_ms,
            runtime,
            next_available: Mutex::new(Instant::now()),
        })
    }

    pub async fn acquire(&self, bytes: usize) {
        if bytes == 0 {
            return;
        }

        let bytes_per_second = effective_bytes_per_second(
            self.bytes_per_second,
            self.runtime.public_inflight(),
            self.runtime
                .public_latency_pressure_divisor(self.public_latency_target_ms),
        );
        let wait = {
            let mut next_available = self.next_available.lock().await;
            let now = Instant::now();
            let start = (*next_available).max(now);
            *next_available = start + duration_for_bytes(bytes, bytes_per_second);
            start.saturating_duration_since(now)
        };

        if !wait.is_zero() {
            sleep(wait).await;
        }
    }

    pub fn effective_bytes_per_second(&self) -> u64 {
        effective_bytes_per_second(
            self.bytes_per_second,
            self.runtime.public_inflight(),
            self.runtime
                .public_latency_pressure_divisor(self.public_latency_target_ms),
        )
    }
}

pub fn effective_bytes_per_second(
    configured_bytes_per_second: u64,
    public_inflight: usize,
    latency_pressure_divisor: usize,
) -> u64 {
    if configured_bytes_per_second == 0 {
        return 0;
    }

    let divisor = (public_inflight as u64)
        .saturating_add(1)
        .max(latency_pressure_divisor.max(1) as u64);
    configured_bytes_per_second
        .checked_div(divisor)
        .unwrap_or(1)
        .max(1)
}

fn duration_for_bytes(bytes: usize, bytes_per_second: u64) -> Duration {
    let nanos = (bytes as u128)
        .saturating_mul(1_000_000_000)
        .div_ceil(bytes_per_second as u128)
        .min(u64::MAX as u128);
    Duration::from_nanos(nanos as u64)
}

#[cfg(test)]
mod tests;
