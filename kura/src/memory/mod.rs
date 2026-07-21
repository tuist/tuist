use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering},
};
use std::time::Instant;
use tokio::sync::Notify;
use tokio::time::timeout;

use crate::metrics::Metrics;

mod cgroup;
mod pools;
mod pressure;
mod reservation;

pub use cgroup::{
    ContainerMemoryPressureSample, ContainerMemorySnapshot, container_memory_pressure_sample,
    container_memory_snapshot,
};
pub use pressure::MemoryPressure;
pub use reservation::{
    ForegroundAdmissionTimeout, ForegroundMemoryReservation, MemoryPermit, MmapMemoryPermit,
    ResponseStreamAdmissionError, ResponseStreamMemoryPermit, ResponseTransportGuard,
    TransientMemoryReservation,
};

use pools::MemoryPools;
use pressure::transition;
use reservation::{
    AdmissionClass, FOREGROUND_ADMISSION_TIMEOUT, ForegroundWaiter,
    RESPONSE_STREAM_ADMISSION_TIMEOUT, ResponseStreamWaiter,
};

#[derive(Clone)]
pub struct MemoryController {
    inner: Arc<MemoryControllerInner>,
}

struct MemoryControllerInner {
    runtime_limit_bytes: u64,
    soft_limit_bytes: u64,
    hard_limit_bytes: u64,
    current_bytes: AtomicU64,
    current_known: AtomicBool,
    container_accounting_selected: AtomicBool,
    observation_sequence: AtomicU64,
    transient_reserved_bytes: AtomicU64,
    deferred_release_bytes: AtomicU64,
    deferred_release: Mutex<DeferredRelease>,
    foreground_waiters: AtomicU64,
    response_stream_waiters: AtomicU64,
    state: AtomicU8,
    pressure_changed: Notify,
    pools: MemoryPools,
    metrics: Metrics,
}

#[derive(Default)]
struct DeferredRelease {
    eligible_bytes: u64,
    pending_bytes: u64,
}

impl DeferredRelease {
    fn total_bytes(&self) -> u64 {
        self.eligible_bytes.saturating_add(self.pending_bytes)
    }
}

impl MemoryController {
    #[cfg(test)]
    pub fn new(metrics: Metrics, soft_limit_bytes: u64, hard_limit_bytes: u64) -> Self {
        let runtime_limit_bytes = hard_limit_bytes
            .saturating_mul(100)
            .saturating_div(85)
            .max(hard_limit_bytes.saturating_add(1));
        Self::with_runtime_limit(
            metrics,
            runtime_limit_bytes,
            soft_limit_bytes,
            hard_limit_bytes,
        )
    }

    pub fn with_runtime_limit(
        metrics: Metrics,
        runtime_limit_bytes: u64,
        soft_limit_bytes: u64,
        hard_limit_bytes: u64,
    ) -> Self {
        metrics.update_memory_limits(soft_limit_bytes, hard_limit_bytes);
        metrics.update_memory_pressure_state(MemoryPressure::Normal.as_i64());
        let pools = MemoryPools::new(runtime_limit_bytes, soft_limit_bytes, hard_limit_bytes);
        metrics.update_response_stream_pool_capacity(
            pools.response_streaming_bytes(),
            pools.foreground_response_streaming_bytes(),
        );
        Self {
            inner: Arc::new(MemoryControllerInner {
                runtime_limit_bytes,
                soft_limit_bytes,
                hard_limit_bytes,
                current_bytes: AtomicU64::new(0),
                current_known: AtomicBool::new(false),
                container_accounting_selected: AtomicBool::new(false),
                observation_sequence: AtomicU64::new(0),
                transient_reserved_bytes: AtomicU64::new(0),
                deferred_release_bytes: AtomicU64::new(0),
                deferred_release: Mutex::new(DeferredRelease::default()),
                foreground_waiters: AtomicU64::new(0),
                response_stream_waiters: AtomicU64::new(0),
                state: AtomicU8::new(MemoryPressure::Normal.as_u8()),
                pressure_changed: Notify::new(),
                pools,
                metrics,
            }),
        }
    }

    #[cfg(any(not(target_os = "linux"), test))]
    pub fn observe(&self, resident_bytes: u64) -> MemoryPressure {
        self.begin_observation();
        self.observe_prepared(resident_bytes)
    }

    pub(crate) fn begin_observation(&self) {
        if self.inner.deferred_release_bytes.load(Ordering::Relaxed) == 0 {
            return;
        }
        let mut deferred = self
            .inner
            .deferred_release
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        deferred.eligible_bytes = deferred
            .eligible_bytes
            .saturating_add(deferred.pending_bytes);
        deferred.pending_bytes = 0;
    }

    pub(crate) fn observe_prepared_container(
        &self,
        sample: ContainerMemoryPressureSample,
    ) -> MemoryPressure {
        self.inner
            .container_accounting_selected
            .store(true, Ordering::Release);
        let accounted_bytes = self.accounted_container_bytes(sample);
        self.inner.metrics.update_memory_accounting(
            accounted_bytes,
            self.reclaim_credit_bytes(),
            accounted_bytes > sample.working_set_bytes,
        );
        self.observe_prepared(accounted_bytes)
    }

    pub(crate) fn accounted_container_bytes(&self, sample: ContainerMemoryPressureSample) -> u64 {
        sample.working_set_bytes.max(
            sample
                .current_bytes
                .saturating_sub(self.reclaim_credit_bytes()),
        )
    }

    pub fn reclaim_credit_bytes(&self) -> u64 {
        self.inner
            .runtime_limit_bytes
            .saturating_sub(self.inner.hard_limit_bytes)
            / 2
    }

    pub(crate) fn observe_prepared(&self, resident_bytes: u64) -> MemoryPressure {
        self.update_current_bytes(resident_bytes);
        self.transition_pressure(resident_bytes)
    }

    #[cfg(target_os = "linux")]
    pub fn observe_container(&self, sample: ContainerMemoryPressureSample) -> MemoryPressure {
        self.begin_observation();
        self.observe_prepared_container(sample)
    }

    fn update_current_bytes(&self, current_bytes: u64) {
        let released = self.take_observed_deferred();
        self.inner
            .observation_sequence
            .fetch_add(1, Ordering::AcqRel);
        self.inner
            .current_bytes
            .store(current_bytes, Ordering::Release);
        self.inner.current_known.store(true, Ordering::Release);
        if released > 0 {
            self.inner
                .transient_reserved_bytes
                .fetch_sub(released, Ordering::AcqRel);
        }
        self.inner
            .observation_sequence
            .fetch_add(1, Ordering::AcqRel);
        self.inner.pressure_changed.notify_waiters();
    }

    fn take_observed_deferred(&self) -> u64 {
        if self.inner.deferred_release_bytes.load(Ordering::Relaxed) == 0 {
            return 0;
        }
        {
            let mut deferred = self
                .inner
                .deferred_release
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            let released = deferred.eligible_bytes;
            deferred.eligible_bytes = 0;
            let remaining = deferred.total_bytes();
            self.inner
                .deferred_release_bytes
                .store(remaining, Ordering::Release);
            self.inner
                .metrics
                .update_memory_deferred_release_bytes(remaining);
            released
        }
    }

    fn defer_transient_release(&self, bytes: u64) -> u64 {
        let mut deferred = self
            .inner
            .deferred_release
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let deferred_bytes = bytes.min(
            self.inner
                .hard_limit_bytes
                .saturating_sub(deferred.total_bytes()),
        );
        if deferred_bytes == 0 {
            return 0;
        }
        deferred.pending_bytes = deferred.pending_bytes.saturating_add(deferred_bytes);
        let total = deferred.total_bytes();
        self.inner
            .deferred_release_bytes
            .store(total, Ordering::Release);
        self.inner
            .metrics
            .update_memory_deferred_release_bytes(total);
        deferred_bytes
    }

    fn transition_pressure(&self, resident_bytes: u64) -> MemoryPressure {
        let current = self.pressure();
        let next = transition(
            current,
            resident_bytes,
            self.inner.soft_limit_bytes,
            self.inner.hard_limit_bytes,
        );

        if next != current {
            self.inner.state.store(next.as_u8(), Ordering::Relaxed);
            self.inner.pressure_changed.notify_waiters();
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

    pub fn allow_background_admission(&self) -> bool {
        self.pressure() == MemoryPressure::Normal
    }

    pub async fn wait_for_background_headroom(&self) {
        while !self.allow_background_admission() {
            let changed = self.inner.pressure_changed.notified();
            if self.allow_background_admission() {
                return;
            }
            changed.await;
        }
    }

    pub fn runtime_limit_bytes(&self) -> u64 {
        self.inner.runtime_limit_bytes
    }

    pub fn hard_limit_bytes(&self) -> u64 {
        self.inner.hard_limit_bytes
    }

    pub fn current_bytes(&self) -> Option<u64> {
        self.inner
            .current_known
            .load(Ordering::Acquire)
            .then(|| self.inner.current_bytes.load(Ordering::Acquire))
    }

    pub fn uses_container_accounting(&self) -> bool {
        self.inner
            .container_accounting_selected
            .load(Ordering::Acquire)
    }

    pub fn observation_sequence(&self) -> u64 {
        self.inner.observation_sequence.load(Ordering::Acquire)
    }

    pub fn transient_reserved_bytes(&self) -> u64 {
        self.inner.transient_reserved_bytes.load(Ordering::Acquire)
    }

    pub fn deferred_release_bytes(&self) -> u64 {
        self.inner.deferred_release_bytes.load(Ordering::Acquire)
    }

    pub fn snapshot_cache_target_bytes(&self, capacity_bytes: usize) -> usize {
        match self.pressure() {
            MemoryPressure::Normal => capacity_bytes,
            MemoryPressure::Constrained => capacity_bytes / 2,
            MemoryPressure::Critical => 0,
        }
    }

    pub fn bootstrap_staging_budget_bytes(&self) -> u64 {
        self.inner
            .hard_limit_bytes
            .saturating_sub(self.inner.soft_limit_bytes)
            .saturating_div(2)
            .clamp(1, 256 * 1024 * 1024)
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
        self.inner
            .pools
            .reapi_response_budget_bytes(self.inner.soft_limit_bytes, self.pressure())
    }

    pub fn reapi_materialization_pool_bytes(&self) -> usize {
        self.inner.pools.reapi_materialization_bytes()
    }

    /// Like `try_acquire_reapi_materialization`, but waits for headroom.
    /// For background work (snapshot index builds) that should queue behind
    /// in-flight response materialization rather than fail because of it.
    pub async fn acquire_background_reapi_materialization(
        &self,
        requested_bytes: usize,
    ) -> Result<Option<MemoryPermit>, ()> {
        if requested_bytes == 0 {
            return Ok(None);
        }
        let permits = u32::try_from(requested_bytes).map_err(|_| ())?;
        let transient = self
            .reserve_transient(requested_bytes as u64, AdmissionClass::Background)
            .await?;
        let concurrency = self
            .inner
            .pools
            .acquire_reapi_materialization(permits)
            .await?;
        Ok(Some(MemoryPermit {
            _concurrency: concurrency,
            _transient: transient,
        }))
    }

    pub fn try_acquire_reapi_materialization(
        &self,
        requested_bytes: usize,
    ) -> Result<Option<MemoryPermit>, ()> {
        if requested_bytes == 0 {
            return Ok(None);
        }
        let permits = u32::try_from(requested_bytes).map_err(|_| ())?;
        let transient =
            self.try_reserve_transient(requested_bytes as u64, AdmissionClass::Foreground)?;
        let concurrency = self
            .inner
            .pools
            .try_acquire_reapi_materialization(permits)?;
        Ok(Some(MemoryPermit {
            _concurrency: concurrency,
            _transient: transient,
        }))
    }

    pub fn try_acquire_reapi_response_materialization(
        &self,
        content_bytes: usize,
    ) -> Result<Option<MemoryPermit>, ()> {
        self.try_acquire_reapi_materialization(content_bytes.checked_mul(2).ok_or(())?)
    }

    /// Admits a public read that could not reserve its full streaming buffers.
    ///
    /// A cache read must never fail because the node is busy. Clients we do not
    /// control — older CLIs, Gradle build-cache clients, Metro — treat a 5xx on
    /// a read as a hard error rather than a retryable miss, so shedding a read
    /// turns node pressure into a broken build. The degraded stream keeps the
    /// smallest chunk the reader supports, so its footprint is bounded by
    /// connection concurrency rather than the weighted pool, and it still
    /// charges the transient ledger when headroom exists so the bytes stay
    /// visible to pressure accounting.
    pub fn acquire_degraded_response_stream_memory(
        &self,
        requested_bytes: usize,
        protocol: &'static str,
    ) -> ResponseStreamMemoryPermit {
        let bytes = requested_bytes as u64;
        let transient = self
            .try_reserve_transient(bytes, AdmissionClass::Foreground)
            .ok();
        self.inner.metrics.record_response_stream_admission(
            protocol,
            "degraded",
            std::time::Duration::ZERO,
        );
        self.inner
            .metrics
            .add_response_stream_reservation(protocol, bytes);
        ResponseStreamMemoryPermit {
            concurrency: None,
            foreground_concurrency: None,
            background_concurrency: None,
            transient,
            metrics: self.inner.metrics.clone(),
            protocol,
            bytes,
        }
    }

    pub async fn reserve_background_transient(
        &self,
        requested_bytes: u64,
    ) -> Result<TransientMemoryReservation, ()> {
        self.reserve_transient(requested_bytes, AdmissionClass::Background)
            .await
    }

    pub(crate) fn try_reserve_foreground_memory(
        &self,
        requested_bytes: u64,
    ) -> Result<ForegroundMemoryReservation, ()> {
        self.try_reserve_transient(requested_bytes, AdmissionClass::Foreground)
            .map(ForegroundMemoryReservation::new)
    }

    pub(crate) async fn reserve_foreground_memory(
        &self,
        requested_bytes: u64,
    ) -> Result<(ForegroundMemoryReservation, bool), ForegroundAdmissionTimeout> {
        match self.try_reserve_foreground_memory(requested_bytes) {
            Ok(reservation) => Ok((reservation, false)),
            Err(()) => {
                self.inner
                    .metrics
                    .record_memory_action("foreground_upload_admission_wait");
                let _waiter = ForegroundWaiter::new(self.inner.clone());
                match timeout(
                    FOREGROUND_ADMISSION_TIMEOUT,
                    self.reserve_transient(requested_bytes, AdmissionClass::Foreground),
                )
                .await
                {
                    Ok(Ok(reservation)) => {
                        Ok((ForegroundMemoryReservation::new(reservation), true))
                    }
                    Ok(Err(())) | Err(_) => {
                        self.inner
                            .metrics
                            .record_memory_action("foreground_upload_admission_timeout");
                        Err(ForegroundAdmissionTimeout)
                    }
                }
            }
        }
    }

    pub fn mmap_serving_pool_bytes(&self) -> usize {
        self.inner.pools.mmap_serving_bytes()
    }

    pub fn try_acquire_mmap_serving(&self, requested_bytes: usize) -> Option<MmapMemoryPermit> {
        if requested_bytes == 0 || self.pressure() != MemoryPressure::Normal {
            return None;
        }
        let permits = u32::try_from(requested_bytes).ok()?;
        let concurrency = self.inner.pools.try_acquire_mmap_serving(permits)?;
        let transient = self
            .try_reserve_transient(requested_bytes as u64, AdmissionClass::Foreground)
            .ok()?;
        // The caller releases this reservation with the response body instead
        // of deferring it to a later sample. mmap serving admits only pages
        // already resident in the sampled container charge, so a deferred
        // handoff would double-count them and throttle hot reads at sensor pace.
        Some(MmapMemoryPermit {
            _concurrency: concurrency,
            _transient: transient,
        })
    }

    pub fn response_streaming_pool_bytes(&self) -> usize {
        self.inner.pools.response_streaming_bytes()
    }

    #[cfg(test)]
    pub fn foreground_response_streaming_pool_bytes(&self) -> usize {
        self.inner.pools.foreground_response_streaming_bytes()
    }

    pub async fn acquire_response_stream_memory(
        &self,
        requested_bytes: usize,
        protocol: &'static str,
    ) -> Result<ResponseStreamMemoryPermit, ResponseStreamAdmissionError> {
        let started_at = Instant::now();
        if self.inner.response_stream_waiters.load(Ordering::Acquire) == 0
            && let Ok(permit) = self.try_acquire_response_stream_memory(requested_bytes, protocol)
        {
            self.inner.metrics.record_response_stream_admission(
                protocol,
                "immediate",
                started_at.elapsed(),
            );
            return Ok(permit);
        }

        if requested_bytes > self.response_streaming_pool_bytes() {
            self.inner.metrics.record_response_stream_admission(
                protocol,
                "queue_full",
                started_at.elapsed(),
            );
            return Err(ResponseStreamAdmissionError::QueueFull);
        }

        let queue = self
            .inner
            .pools
            .try_acquire_response_stream_waiter()
            .map_err(|()| {
                self.inner.metrics.record_response_stream_admission(
                    protocol,
                    "queue_full",
                    started_at.elapsed(),
                );
                ResponseStreamAdmissionError::QueueFull
            })?;
        let _waiter = ResponseStreamWaiter::new(self.inner.clone(), protocol, queue);
        let result = timeout(RESPONSE_STREAM_ADMISSION_TIMEOUT, async {
            let _turn = self
                .inner
                .pools
                .acquire_response_stream_admission_turn()
                .await;
            loop {
                let changed = self.inner.pressure_changed.notified();
                tokio::pin!(changed);
                changed.as_mut().enable();
                if let Ok(permit) =
                    self.try_acquire_response_stream_memory(requested_bytes, protocol)
                {
                    return permit;
                }
                changed.await;
            }
        })
        .await;

        match result {
            Ok(permit) => {
                self.inner.metrics.record_response_stream_admission(
                    protocol,
                    "waited",
                    started_at.elapsed(),
                );
                Ok(permit)
            }
            Err(_) => {
                self.inner.metrics.record_response_stream_admission(
                    protocol,
                    "timeout",
                    started_at.elapsed(),
                );
                Err(ResponseStreamAdmissionError::Timeout)
            }
        }
    }

    fn try_acquire_response_stream_memory(
        &self,
        requested_bytes: usize,
        protocol: &'static str,
    ) -> Result<ResponseStreamMemoryPermit, ()> {
        let permits = u32::try_from(requested_bytes).map_err(|_| ())?;
        let foreground_concurrency = self
            .inner
            .pools
            .try_acquire_foreground_response_streaming(permits)?;
        let concurrency = self.inner.pools.try_acquire_response_streaming(permits)?;
        let transient =
            self.try_reserve_transient(requested_bytes as u64, AdmissionClass::Foreground)?;
        Ok(self.response_stream_memory_permit(
            concurrency,
            Some(foreground_concurrency),
            None,
            transient,
            protocol,
            requested_bytes as u64,
        ))
    }

    pub fn try_acquire_background_response_stream_memory(
        &self,
        requested_bytes: usize,
        protocol: &'static str,
    ) -> Result<ResponseStreamMemoryPermit, ResponseStreamAdmissionError> {
        let started_at = Instant::now();
        let result = (|| {
            if requested_bytes > self.response_streaming_pool_bytes() {
                return Err(());
            }
            let permits = u32::try_from(requested_bytes).map_err(|_| ())?;
            let background_concurrency = self
                .inner
                .pools
                .try_acquire_background_response_streaming(permits)?;
            let concurrency = self.inner.pools.try_acquire_response_streaming(permits)?;
            let transient =
                self.try_reserve_transient(requested_bytes as u64, AdmissionClass::Background)?;
            Ok(self.response_stream_memory_permit(
                concurrency,
                None,
                Some(background_concurrency),
                transient,
                protocol,
                requested_bytes as u64,
            ))
        })();
        match result {
            Ok(permit) => {
                self.inner.metrics.record_response_stream_admission(
                    protocol,
                    "immediate",
                    started_at.elapsed(),
                );
                Ok(permit)
            }
            Err(()) => {
                self.inner.metrics.record_response_stream_admission(
                    protocol,
                    "queue_full",
                    started_at.elapsed(),
                );
                Err(ResponseStreamAdmissionError::QueueFull)
            }
        }
    }

    fn response_stream_memory_permit(
        &self,
        concurrency: tokio::sync::OwnedSemaphorePermit,
        foreground_concurrency: Option<tokio::sync::OwnedSemaphorePermit>,
        background_concurrency: Option<tokio::sync::OwnedSemaphorePermit>,
        transient: TransientMemoryReservation,
        protocol: &'static str,
        bytes: u64,
    ) -> ResponseStreamMemoryPermit {
        self.inner
            .metrics
            .add_response_stream_reservation(protocol, bytes);
        ResponseStreamMemoryPermit {
            concurrency: Some(concurrency),
            foreground_concurrency,
            background_concurrency,
            transient: Some(transient),
            metrics: self.inner.metrics.clone(),
            protocol,
            bytes,
        }
    }

    async fn reserve_transient(
        &self,
        requested_bytes: u64,
        class: AdmissionClass,
    ) -> Result<TransientMemoryReservation, ()> {
        loop {
            match self.try_reserve_transient(requested_bytes, class) {
                Ok(reservation) => return Ok(reservation),
                Err(()) => {
                    let changed = self.inner.pressure_changed.notified();
                    tokio::pin!(changed);
                    // Notify::notify_waiters stores no permit. Register before
                    // rechecking headroom so a reservation release racing this
                    // check cannot leave the waiter asleep indefinitely.
                    changed.as_mut().enable();
                    if let Ok(reservation) = self.try_reserve_transient(requested_bytes, class) {
                        return Ok(reservation);
                    }
                    changed.await;
                }
            }
        }
    }

    fn try_reserve_transient(
        &self,
        requested_bytes: u64,
        class: AdmissionClass,
    ) -> Result<TransientMemoryReservation, ()> {
        if requested_bytes == 0 {
            return Ok(TransientMemoryReservation {
                controller: self.clone(),
                bytes: 0,
                defer_release_until_observation: false,
            });
        }
        self.try_grow_transient(requested_bytes, class)?;
        Ok(TransientMemoryReservation {
            controller: self.clone(),
            bytes: requested_bytes,
            defer_release_until_observation: false,
        })
    }

    fn try_grow_transient(&self, requested_bytes: u64, class: AdmissionClass) -> Result<(), ()> {
        if requested_bytes == 0 {
            return Ok(());
        }
        if class == AdmissionClass::Background && !self.allow_background_admission() {
            return Err(());
        }
        let ceiling = match class {
            AdmissionClass::Foreground => self.inner.hard_limit_bytes,
            AdmissionClass::Background => self.inner.soft_limit_bytes,
        };
        let mut observation_spins = 0_u8;
        loop {
            let observation = self.inner.observation_sequence.load(Ordering::Acquire);
            if !observation.is_multiple_of(2) {
                if observation_spins < 16 {
                    std::hint::spin_loop();
                    observation_spins += 1;
                } else {
                    std::thread::yield_now();
                    observation_spins = 0;
                }
                continue;
            }
            observation_spins = 0;
            let current = self.current_bytes().unwrap_or(0);
            loop {
                let reserved = self.inner.transient_reserved_bytes.load(Ordering::Acquire);
                let available = ceiling.saturating_sub(current).saturating_sub(reserved);
                if requested_bytes > available {
                    if self.inner.observation_sequence.load(Ordering::Acquire) == observation {
                        return Err(());
                    }
                    break;
                }
                if self
                    .inner
                    .transient_reserved_bytes
                    .compare_exchange_weak(
                        reserved,
                        reserved.saturating_add(requested_bytes),
                        Ordering::AcqRel,
                        Ordering::Acquire,
                    )
                    .is_ok()
                {
                    if self.inner.observation_sequence.load(Ordering::Acquire) == observation {
                        return Ok(());
                    }
                    self.inner
                        .transient_reserved_bytes
                        .fetch_sub(requested_bytes, Ordering::AcqRel);
                    self.inner.pressure_changed.notify_waiters();
                    break;
                }
            }
        }
    }
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
    fn deferred_release_waits_for_a_fresh_memory_observation() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::new(metrics, 100, 200);
        controller.observe(80);
        let mut first = controller
            .try_reserve_foreground_memory(50)
            .expect("reservation should fit");
        let mut second = controller
            .try_reserve_foreground_memory(60)
            .expect("second reservation should fit");
        first.defer_release_until_observation();
        second.defer_release_until_observation();
        drop(first);
        drop(second);

        assert_eq!(controller.transient_reserved_bytes(), 110);
        assert_eq!(controller.deferred_release_bytes(), 110);
        controller.observe(90);
        assert_eq!(controller.current_bytes(), Some(90));
        assert_eq!(controller.transient_reserved_bytes(), 0);
        assert_eq!(controller.deferred_release_bytes(), 0);
    }

    #[test]
    fn an_observation_does_not_release_a_newer_completion() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::new(metrics, 100, 200);
        controller.observe(80);
        controller.begin_observation();
        let mut completed = controller
            .try_reserve_foreground_memory(50)
            .expect("reservation should fit");
        completed.defer_release_until_observation();
        drop(completed);

        controller.observe_prepared_container(ContainerMemoryPressureSample {
            current_bytes: 90,
            working_set_bytes: 90,
            reclaimable_inactive_file_bytes: 0,
            limit_bytes: Some(200),
        });
        assert_eq!(controller.deferred_release_bytes(), 50);
        assert_eq!(controller.transient_reserved_bytes(), 50);

        controller.begin_observation();
        controller.observe_prepared_container(ContainerMemoryPressureSample {
            current_bytes: 95,
            working_set_bytes: 95,
            reclaimable_inactive_file_bytes: 0,
            limit_bytes: Some(200),
        });
        assert_eq!(controller.deferred_release_bytes(), 0);
        assert_eq!(controller.transient_reserved_bytes(), 0);
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
    fn container_accounting_limits_reclaim_credit_to_half_the_runtime_headroom() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(metrics, 1_000, 700, 850);
        let sample = ContainerMemoryPressureSample {
            current_bytes: 800,
            working_set_bytes: 200,
            reclaimable_inactive_file_bytes: 600,
            limit_bytes: Some(1_000),
        };

        assert_eq!(controller.reclaim_credit_bytes(), 75);
        assert_eq!(controller.accounted_container_bytes(sample), 725);
    }

    #[test]
    fn reapi_materialization_pool_is_clamped_from_memory_headroom() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let small = MemoryController::new(metrics.clone(), 24 * 1024 * 1024, 48 * 1024 * 1024);
        let medium = MemoryController::new(metrics.clone(), 128 * 1024 * 1024, 256 * 1024 * 1024);
        let large = MemoryController::new(metrics, 8 * 1024 * 1024 * 1024, 9 * 1024 * 1024 * 1024);

        assert_eq!(small.reapi_materialization_pool_bytes(), 24 * 1024 * 1024);
        assert_eq!(medium.reapi_materialization_pool_bytes(), 128 * 1024 * 1024);
        assert_eq!(large.reapi_materialization_pool_bytes(), 128 * 1024 * 1024);
    }

    #[test]
    fn default_runtime_preserves_the_sixty_four_mebibyte_response_contract() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            1024 * 1024 * 1024,
            716 * 1024 * 1024,
            870 * 1024 * 1024,
        );

        assert_eq!(
            controller.reapi_materialization_pool_bytes(),
            128 * 1024 * 1024
        );
        assert_eq!(controller.reapi_response_budget_bytes(), 64 * 1024 * 1024);
    }

    #[test]
    fn mmap_serving_pool_is_bounded_by_memory_headroom() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let small = MemoryController::new(metrics.clone(), 128 * 1024 * 1024, 192 * 1024 * 1024);
        let medium = MemoryController::new(metrics.clone(), 512 * 1024 * 1024, 768 * 1024 * 1024);
        let large = MemoryController::new(metrics, 2 * 1024 * 1024 * 1024, 4 * 1024 * 1024 * 1024);

        assert_eq!(small.mmap_serving_pool_bytes(), 64 * 1024 * 1024);
        assert_eq!(medium.mmap_serving_pool_bytes(), 256 * 1024 * 1024);
        assert_eq!(large.mmap_serving_pool_bytes(), 512 * 1024 * 1024);
    }

    #[test]
    fn mmap_serving_permits_are_non_blocking_and_pressure_sensitive() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::new(metrics, 128 * 1024 * 1024, 256 * 1024 * 1024);

        let permit = controller
            .try_acquire_mmap_serving(64 * 1024 * 1024)
            .expect("permit should be available");
        assert_eq!(controller.transient_reserved_bytes(), 64 * 1024 * 1024);
        assert!(
            controller
                .try_acquire_mmap_serving(65 * 1024 * 1024)
                .is_none()
        );

        drop(permit);
        controller.observe(128 * 1024 * 1024);
        assert_eq!(controller.transient_reserved_bytes(), 0);
        assert!(controller.try_acquire_mmap_serving(1).is_none());
    }

    #[test]
    fn response_streaming_pool_preserves_memory_headroom() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let small = MemoryController::with_runtime_limit(
            metrics.clone(),
            256 * 1024 * 1024,
            179 * 1024 * 1024,
            217 * 1024 * 1024,
        );
        let large = MemoryController::with_runtime_limit(
            metrics,
            4 * 1024 * 1024 * 1024,
            2 * 1024 * 1024 * 1024,
            3 * 1024 * 1024 * 1024,
        );

        assert_eq!(small.response_streaming_pool_bytes(), 19 * 1024 * 1024);
        assert_eq!(
            small.foreground_response_streaming_pool_bytes(),
            13 * 1024 * 1024
        );
        assert_eq!(large.response_streaming_pool_bytes(), 64 * 1024 * 1024);
        assert_eq!(
            large.foreground_response_streaming_pool_bytes(),
            58 * 1024 * 1024
        );
    }

    #[tokio::test]
    async fn response_stream_permit_is_held_until_the_last_transport_guard_drops() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            256 * 1024 * 1024,
            128 * 1024 * 1024,
            192 * 1024 * 1024,
        );
        let permit = controller
            .acquire_response_stream_memory(1024 * 1024, "http")
            .await
            .expect("stream permit should be admitted");
        assert_eq!(controller.transient_reserved_bytes(), 1024 * 1024);

        let guard = permit.into_transport_guard();
        let transport_owned = guard.clone();
        drop(guard);
        assert_eq!(controller.transient_reserved_bytes(), 1024 * 1024);
        drop(transport_owned);
        #[cfg(target_os = "linux")]
        {
            assert_eq!(controller.deferred_release_bytes(), 1024 * 1024);
            controller.observe(0);
        }
        assert_eq!(controller.transient_reserved_bytes(), 0);
        controller
            .acquire_response_stream_memory(
                controller.foreground_response_streaming_pool_bytes(),
                "bytestream",
            )
            .await
            .expect("dropping the body should release every stream permit");
    }

    #[test]
    fn failed_response_stream_admission_rolls_back_the_weighted_pool() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            256 * 1024 * 1024,
            128 * 1024 * 1024,
            192 * 1024 * 1024,
        );
        controller.observe(controller.hard_limit_bytes());
        assert!(
            controller
                .try_acquire_response_stream_memory(1024 * 1024, "http")
                .is_err()
        );

        controller.observe(0);
        controller
            .try_acquire_response_stream_memory(
                controller.foreground_response_streaming_pool_bytes(),
                "http",
            )
            .expect("failed transient admission must not leak weighted permits");
    }

    #[test]
    fn bootstrap_keeps_a_progress_quantum_while_leaving_half_for_public_responses() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            256 * 1024 * 1024,
            128 * 1024 * 1024,
            192 * 1024 * 1024,
        );
        controller.observe(0);
        let foreground_bytes = controller.foreground_response_streaming_pool_bytes();
        let foreground = controller
            .try_acquire_response_stream_memory(foreground_bytes, "http")
            .expect("foreground ceiling should be available");
        controller
            .inner
            .response_stream_waiters
            .store(1, Ordering::Release);
        let bootstrap_quantum = 6 * 1024 * 1024;
        let bootstrap = controller
            .try_acquire_background_response_stream_memory(bootstrap_quantum, "bootstrap")
            .expect("one maximum bootstrap response must progress despite a public waiter");
        assert_eq!(
            controller.transient_reserved_bytes(),
            (foreground_bytes + bootstrap_quantum) as u64
        );
        assert!(
            controller
                .try_acquire_background_response_stream_memory(1, "bootstrap")
                .is_err(),
            "the shared pool must remain a hard aggregate bound"
        );
        drop(bootstrap);
        drop(foreground);

        controller
            .inner
            .response_stream_waiters
            .store(0, Ordering::Release);
        let background_bytes = controller.response_streaming_pool_bytes() / 2;
        let permit = controller
            .try_acquire_background_response_stream_memory(background_bytes, "bootstrap")
            .expect("background half should be available");
        assert!(
            controller
                .try_acquire_background_response_stream_memory(1, "bootstrap")
                .is_err(),
            "bootstrap must leave the other half available for public responses"
        );
        drop(permit);
    }

    #[tokio::test]
    async fn background_work_waits_until_memory_pressure_recovers() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::new(metrics, 100, 200);
        controller.observe(100);

        let wait = tokio::spawn({
            let controller = controller.clone();
            async move { controller.wait_for_background_headroom().await }
        });
        tokio::task::yield_now().await;
        assert!(!wait.is_finished());

        controller.observe(90);
        wait.await.expect("memory waiter should finish");
    }

    #[test]
    fn transient_reservations_use_live_headroom_and_release_it() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(metrics, 1_000, 700, 850);
        controller.observe(800);

        assert!(controller.try_acquire_reapi_materialization(51).is_err());
        let permit = controller
            .try_acquire_reapi_materialization(50)
            .expect("foreground reservation should fit exactly")
            .expect("non-zero reservation should return a permit");
        assert_eq!(controller.transient_reserved_bytes(), 50);
        drop(permit);
        assert_eq!(controller.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn background_reservations_wait_for_normal_pressure() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(metrics, 1_000, 700, 850);
        controller.observe(700);

        let reservation = tokio::spawn({
            let controller = controller.clone();
            async move { controller.reserve_background_transient(10).await }
        });
        tokio::task::yield_now().await;
        assert!(!reservation.is_finished());

        controller.observe(630);
        let reservation = reservation
            .await
            .expect("reservation task should finish")
            .expect("reservation should succeed after recovery");
        assert_eq!(controller.transient_reserved_bytes(), 10);
        drop(reservation);
        assert_eq!(controller.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn foreground_reservation_waiters_wake_as_capacity_is_released() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            512 * 1024 * 1024,
            128 * 1024 * 1024,
            256 * 1024 * 1024,
        );
        let mut tasks = Vec::new();
        for _ in 0..24 {
            let controller = controller.clone();
            tasks.push(tokio::spawn(async move {
                let (reservation, _) = controller
                    .reserve_foreground_memory(32 * 1024 * 1024)
                    .await
                    .expect("foreground reservation should eventually fit");
                tokio::task::yield_now().await;
                drop(reservation);
            }));
        }

        tokio::time::timeout(std::time::Duration::from_secs(2), async {
            for task in tasks {
                task.await.expect("reservation task should not panic");
            }
        })
        .await
        .expect("all reservation waiters should be notified");
        assert_eq!(controller.transient_reserved_bytes(), 0);
    }
}
