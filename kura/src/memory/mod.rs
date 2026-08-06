use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering},
};
use std::time::Instant;
use tokio::sync::Notify;
use tokio::time::timeout;

use crate::constants::RESPONSE_STREAM_SEND_BUFFER_BYTES;
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
    ResponseStreamAdmissionError, ResponseStreamAdmissionPatience, ResponseStreamMemoryPermit,
    ResponseTransportGuard, TransientMemoryReservation,
};

use pools::MemoryPools;
use pressure::transition;
use reservation::{
    AdmissionClass, DEGRADED_RESPONSE_STREAM_SLOT_TIMEOUT, FOREGROUND_ADMISSION_TIMEOUT,
    ForegroundWaiter, ResponseStreamWaiter,
};

/// Coordinates deterministic admission for memory that Kura allocates on behalf of a request.
///
/// Live transient permits never exceed `hard_limit_bytes - soft_limit_bytes`. Waiting
/// acquisitions are fair, every growth while already holding a permit is non-blocking, and the
/// permit stays with the allocation that owns the bytes. Sampled container usage never enters
/// this budget. It drives pressure-based cache trimming and background load shedding instead.
///
/// Mapped-file serving has a separate try-only limit because it covers already-resident,
/// reclaimable pages and always falls back to streaming. This controller bounds admitted work,
/// not allocations made outside its permits by the metadata store, network stack, or allocator.
#[derive(Clone)]
pub struct MemoryController {
    inner: Arc<MemoryControllerInner>,
}

/// Parses the `KURA_TEST_FORCE_MEMORY_PRESSURE` override value. Accepts the
/// [`MemoryPressure::as_str`] spellings (case-insensitive). Any other value
/// (including the unset variable) yields `None`, so a misspelled override
/// fails open to real accounting rather than silently pinning the node.
fn parse_forced_memory_pressure(value: &str) -> Option<MemoryPressure> {
    match value.trim().to_ascii_lowercase().as_str() {
        "normal" => Some(MemoryPressure::Normal),
        "constrained" => Some(MemoryPressure::Constrained),
        "critical" => Some(MemoryPressure::Critical),
        _ => None,
    }
}

/// Reads `KURA_TEST_FORCE_MEMORY_PRESSURE` once at construction. See
/// [`parse_forced_memory_pressure`].
fn forced_memory_pressure_for_tests() -> Option<MemoryPressure> {
    parse_forced_memory_pressure(&std::env::var("KURA_TEST_FORCE_MEMORY_PRESSURE").ok()?)
}

struct MemoryControllerInner {
    runtime_limit_bytes: u64,
    soft_limit_bytes: u64,
    hard_limit_bytes: u64,
    /// Test-only override that pins the pressure state regardless of the
    /// resident-bytes samples, so an end-to-end run can reproduce a
    /// pressure tier deterministically (a real node never stays exactly on
    /// a tier for long). Sourced from `KURA_TEST_FORCE_MEMORY_PRESSURE`;
    /// unset in every non-test environment, so production behaviour is
    /// untouched. `pressure()` is the single reader, so every admission
    /// and shedding decision reflects it.
    forced_pressure: Option<MemoryPressure>,
    container_accounting_selected: AtomicBool,
    reclaim_file_cache: AtomicBool,
    /// Set while the raw cgroup charge (`memory.current`, which includes clean
    /// file cache) sits at or above the hard watermark. Background work must
    /// stop in that state because the charge counts against the container limit
    /// until the kernel actually reclaims it, but it is deliberately kept out of
    /// the global pressure tier: a warm serving node parks clean artifact pages
    /// there as a matter of course, and denying foreground admission for that
    /// would shed customer reads that cost no additional memory.
    container_at_hard_limit: AtomicBool,
    working_set_state: AtomicU8,
    observation_sequence: AtomicU64,
    foreground_waiters: AtomicU64,
    response_stream_waiters: AtomicU64,
    state: AtomicU8,
    pressure_changed: Notify,
    pools: MemoryPools,
    metrics: Metrics,
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
        Self::with_runtime_limit_and_forced(
            metrics,
            runtime_limit_bytes,
            soft_limit_bytes,
            hard_limit_bytes,
            forced_memory_pressure_for_tests(),
        )
    }

    /// Test-only constructor that pins the controller to a forced pressure tier,
    /// mirroring `KURA_TEST_FORCE_MEMORY_PRESSURE` without touching the process
    /// environment (which is shared state across parallel tests).
    #[cfg(test)]
    pub fn new_with_forced_pressure(
        metrics: Metrics,
        soft_limit_bytes: u64,
        hard_limit_bytes: u64,
        forced: MemoryPressure,
    ) -> Self {
        let runtime_limit_bytes = hard_limit_bytes
            .saturating_mul(100)
            .saturating_div(85)
            .max(hard_limit_bytes.saturating_add(1));
        Self::with_runtime_limit_and_forced(
            metrics,
            runtime_limit_bytes,
            soft_limit_bytes,
            hard_limit_bytes,
            Some(forced),
        )
    }

    fn with_runtime_limit_and_forced(
        metrics: Metrics,
        runtime_limit_bytes: u64,
        soft_limit_bytes: u64,
        hard_limit_bytes: u64,
        forced_pressure: Option<MemoryPressure>,
    ) -> Self {
        metrics.update_memory_limits(soft_limit_bytes, hard_limit_bytes);
        metrics.update_memory_pressure_state(MemoryPressure::Normal.as_i64());
        let pools = MemoryPools::new(runtime_limit_bytes, soft_limit_bytes, hard_limit_bytes);
        metrics.update_response_stream_pool_capacity(
            pools.response_streaming_bytes(),
            pools.foreground_response_streaming_bytes(),
            pools.degraded_response_stream_slots(),
        );
        Self {
            inner: Arc::new(MemoryControllerInner {
                runtime_limit_bytes,
                soft_limit_bytes,
                hard_limit_bytes,
                forced_pressure,
                container_accounting_selected: AtomicBool::new(false),
                reclaim_file_cache: AtomicBool::new(false),
                container_at_hard_limit: AtomicBool::new(false),
                working_set_state: AtomicU8::new(MemoryPressure::Normal.as_u8()),
                observation_sequence: AtomicU64::new(0),
                foreground_waiters: AtomicU64::new(0),
                response_stream_waiters: AtomicU64::new(0),
                state: AtomicU8::new(MemoryPressure::Normal.as_u8()),
                pressure_changed: Notify::new(),
                pools,
                metrics,
            }),
        }
    }

    pub fn observe(&self, resident_bytes: u64) -> MemoryPressure {
        // A forced tier is the test override; ignore the resident-bytes sample
        // so the pin holds instead of flickering with the real reading. Still
        // advance the observation sequence: the stall watchdog in
        // spawn_memory_pressure_tasks treats an unchanged sequence as a dead
        // sensor and terminates the process, so a pinned tier must look like
        // an ongoing observation rather than a frozen sensor.
        if let Some(forced) = self.inner.forced_pressure {
            self.inner
                .observation_sequence
                .fetch_add(1, Ordering::Release);
            self.inner
                .metrics
                .update_memory_pressure_state(forced.as_i64());
            return forced;
        }
        self.inner
            .observation_sequence
            .fetch_add(1, Ordering::Release);
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

    pub fn observe_container(&self, sample: ContainerMemoryPressureSample) -> MemoryPressure {
        self.inner
            .container_accounting_selected
            .store(true, Ordering::Release);
        // File-cache reclaim has two independent arms.
        //
        // The working-set arm asks demand to trade clean file-cache warmth for request
        // capacity once the conventional working set crosses the soft watermark. Because that
        // working set is exactly the quantity that can swing more than a gibibyte between two
        // 200 ms samples as the kernel reclassifies clean artifact pages, a raw threshold would
        // flip mmap serving and drop-behind on and off every sample near the soft watermark. It
        // runs through the same hysteretic pressure state machine as admission so it only clears
        // after recovering roughly 10% below the soft watermark.
        //
        // The raw `memory.current >= hard_limit` arm is deliberately un-hysteresed. On a warm
        // serving node the kernel keeps clean page cache charged until forced to reclaim, so once
        // the cumulative footprint crosses the hard watermark this stays effectively steady state.
        // That is the intended trade for cache nodes: hold drop-behind and mmap-serving denial on
        // so request serving keeps borrowing from clean file cache instead of the container
        // sitting close to its limit.
        let working_set_reclaim =
            self.observe_working_set(sample.working_set_bytes) != MemoryPressure::Normal;
        self.inner.reclaim_file_cache.store(
            working_set_reclaim || sample.current_bytes >= self.inner.hard_limit_bytes,
            Ordering::Relaxed,
        );
        // `memory.current` is charged against the control-group limit even when
        // most of it is clean file cache. Reclaim alone is not enough once it
        // reaches the hard watermark: a concurrent bootstrap or database write
        // can consume the remaining headroom before the kernel reclaims it.
        // Close every background admission gate on that condition so the node
        // stops adding charge before the kernel has to kill the process.
        //
        // This deliberately does not move the global pressure tier. That tier
        // also gates foreground admission (public reads and writes, REAPI, and
        // response-stream reservations), and a warm serving node holds clean
        // artifact pages at the hard watermark as its normal steady state.
        // Folding the raw charge into the tier sheds customer traffic that a
        // single reclaim would have made room for. The tier stays driven by
        // `pressure_bytes`, which already excludes clean file cache.
        let at_hard_limit = sample.current_bytes >= self.inner.hard_limit_bytes;
        if self
            .inner
            .container_at_hard_limit
            .swap(at_hard_limit, Ordering::Release)
            != at_hard_limit
        {
            self.inner.pressure_changed.notify_waiters();
        }
        self.observe(sample.pressure_bytes)
    }

    fn observe_working_set(&self, working_set_bytes: u64) -> MemoryPressure {
        let current = MemoryPressure::from_u8(self.inner.working_set_state.load(Ordering::Relaxed));
        let next = transition(
            current,
            working_set_bytes,
            self.inner.soft_limit_bytes,
            self.inner.hard_limit_bytes,
        );
        if next != current {
            self.inner
                .working_set_state
                .store(next.as_u8(), Ordering::Relaxed);
        }
        next
    }

    pub fn pressure(&self) -> MemoryPressure {
        if let Some(forced) = self.inner.forced_pressure {
            return forced;
        }
        MemoryPressure::from_u8(self.inner.state.load(Ordering::Relaxed))
    }

    /// True while the raw cgroup charge sits at or above the hard watermark.
    /// Background gates consult this alongside the pressure tier; foreground
    /// admission deliberately does not, because the charge is dominated by
    /// reclaimable clean file cache on a warm serving node.
    pub fn container_at_hard_limit(&self) -> bool {
        self.inner.container_at_hard_limit.load(Ordering::Acquire)
    }

    pub fn allow_manifest_cache_admission(&self) -> bool {
        self.pressure() == MemoryPressure::Normal && !self.container_at_hard_limit()
    }

    pub fn allow_segment_refresh(&self) -> bool {
        self.pressure() == MemoryPressure::Normal && !self.container_at_hard_limit()
    }

    /// Gates the *usage* (metering) outbox only. Replication delivery is
    /// deliberately never paused: its durable backlog is bounded by
    /// `KURA_OUTBOX_MAX_DEPTH`, and a full replication outbox rejects cache
    /// writes, so pausing it converts a memory problem into a correctness and
    /// availability one. Metering has no such feedback — a delayed usage batch
    /// costs nothing but freshness — so it stays sheddable.
    pub fn pause_usage_outbox(&self) -> bool {
        self.pressure() == MemoryPressure::Critical || self.container_at_hard_limit()
    }

    pub fn allow_background_admission(&self) -> bool {
        self.pressure() == MemoryPressure::Normal && !self.container_at_hard_limit()
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

    pub fn transient_capacity_bytes(&self) -> u64 {
        self.inner.pools.transient_capacity_bytes() as u64
    }

    pub fn hard_limit_bytes(&self) -> u64 {
        self.inner.hard_limit_bytes
    }

    pub fn uses_container_accounting(&self) -> bool {
        self.inner
            .container_accounting_selected
            .load(Ordering::Acquire)
    }

    pub fn should_reclaim_file_cache(&self) -> bool {
        self.inner.reclaim_file_cache.load(Ordering::Relaxed)
            || self.pressure() != MemoryPressure::Normal
    }

    pub fn observation_sequence(&self) -> u64 {
        self.inner.observation_sequence.load(Ordering::Acquire)
    }

    pub fn transient_reserved_bytes(&self) -> u64 {
        self.inner.pools.transient_reserved_bytes() as u64
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

    pub fn reapi_materialization_limit_bytes(&self) -> usize {
        self.inner.pools.reapi_materialization_limit_bytes()
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
        if requested_bytes > self.reapi_materialization_limit_bytes() {
            return Err(());
        }
        let transient = self
            .reserve_transient(requested_bytes as u64, AdmissionClass::Background)
            .await?;
        Ok(Some(MemoryPermit {
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
        if requested_bytes > self.reapi_materialization_limit_bytes() {
            return Err(());
        }
        let transient =
            self.try_reserve_transient(requested_bytes as u64, AdmissionClass::Foreground)?;
        Ok(Some(MemoryPermit {
            _transient: transient,
        }))
    }

    pub fn try_acquire_response_materialization(
        &self,
        content_bytes: usize,
    ) -> Result<Option<MemoryPermit>, ()> {
        self.try_acquire_reapi_materialization(content_bytes.checked_mul(2).ok_or(())?)
    }

    /// Non-waiting admission for the mmap fast path.
    ///
    /// mmap serving is an optimization over the streaming reader, so queueing
    /// for it would spend the admission budget twice: once here, and again in
    /// the streaming path this falls back to, delaying a read by up to two full
    /// admission timeouts before it degrades. A miss returns immediately and is
    /// not counted as a rejection, because the read still proceeds by another
    /// route.
    pub fn try_acquire_mmap_response_stream_memory(
        &self,
        requested_bytes: usize,
        protocol: &'static str,
    ) -> Option<ResponseStreamMemoryPermit> {
        let (permit, elastic) = self
            .try_acquire_response_stream_memory(requested_bytes, protocol)
            .ok()?;
        self.inner.metrics.record_response_stream_admission(
            protocol,
            if elastic { "elastic" } else { "immediate" },
            std::time::Duration::ZERO,
        );
        Some(permit)
    }

    /// Admits a public read that could not reserve its full streaming buffers.
    ///
    /// A degraded stream keeps the smallest reader chunk but holds a slot
    /// counted at Hyper's real per-stream send buffer, not at that chunk size.
    /// Both the slot and the transient reservation are mandatory so slow
    /// readers cannot escape the process-wide memory bound. The wait and its
    /// queue are bounded: once either fills, the caller sheds the response with
    /// a retryable error instead of opening an unaccounted stream.
    pub async fn acquire_degraded_response_stream_memory(
        &self,
        requested_bytes: usize,
        protocol: &'static str,
    ) -> Result<ResponseStreamMemoryPermit, ResponseStreamAdmissionError> {
        let started_at = Instant::now();
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
        let slot = timeout(
            DEGRADED_RESPONSE_STREAM_SLOT_TIMEOUT,
            self.inner.pools.acquire_degraded_response_stream(),
        )
        .await
        .ok()
        .flatten()
        .ok_or_else(|| {
            self.inner.metrics.record_response_stream_admission(
                protocol,
                "degraded_timeout",
                started_at.elapsed(),
            );
            ResponseStreamAdmissionError::Timeout
        })?;
        // The 8 KiB degraded reader chunk is not the stream's complete memory
        // cost. Hyper may retain a much larger per-stream send buffer while a
        // client is slow, so charge that real upper bound against live
        // headroom as well as using it to size the concurrency pool. Inline
        // values can be larger still and remain fully charged.
        let bytes = requested_bytes.max(RESPONSE_STREAM_SEND_BUFFER_BYTES) as u64;
        let transient = self
            .try_reserve_transient(bytes, AdmissionClass::Foreground)
            .map_err(|()| {
                self.inner.metrics.record_response_stream_admission(
                    protocol,
                    "degraded_memory_unavailable",
                    started_at.elapsed(),
                );
                ResponseStreamAdmissionError::QueueFull
            })?;
        self.inner.metrics.record_response_stream_admission(
            protocol,
            "degraded",
            started_at.elapsed(),
        );
        self.inner
            .metrics
            .add_response_stream_reservation(protocol, bytes);
        Ok(ResponseStreamMemoryPermit {
            concurrency: Some(slot),
            foreground_concurrency: None,
            background_concurrency: None,
            elastic_concurrency: None,
            transient: Some(transient),
            metrics: self.inner.metrics.clone(),
            protocol,
            bytes,
        })
    }

    #[cfg(test)]
    pub fn degraded_response_stream_slots(&self) -> usize {
        self.inner.pools.degraded_response_stream_slots()
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
        if requested_bytes > 0 && self.inner.foreground_waiters.load(Ordering::Acquire) > 0 {
            return Err(());
        }
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
        if requested_bytes == 0 || self.should_reclaim_file_cache() {
            return None;
        }
        let permits = u32::try_from(requested_bytes).ok()?;
        let concurrency = self.inner.pools.try_acquire_mmap_serving(permits)?;
        let transient = self
            .try_reserve_transient(requested_bytes as u64, AdmissionClass::Foreground)
            .ok()?;
        // The caller releases this reservation with the response body. Sampled
        // container usage does not enter transient admission arithmetic.
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

    #[cfg(test)]
    pub fn elastic_foreground_response_streaming_pool_bytes(&self) -> usize {
        self.inner
            .pools
            .elastic_foreground_response_streaming_bytes()
    }

    pub async fn acquire_response_stream_memory(
        &self,
        requested_bytes: usize,
        protocol: &'static str,
        patience: ResponseStreamAdmissionPatience,
    ) -> Result<ResponseStreamMemoryPermit, ResponseStreamAdmissionError> {
        let started_at = Instant::now();
        if self.inner.response_stream_waiters.load(Ordering::Acquire) == 0
            && let Ok((permit, elastic)) =
                self.try_acquire_response_stream_memory(requested_bytes, protocol)
        {
            self.inner.metrics.record_response_stream_admission(
                protocol,
                if elastic { "elastic" } else { "immediate" },
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
        let result = timeout(patience.timeout(), async {
            let _turn = self
                .inner
                .pools
                .acquire_response_stream_admission_turn()
                .await;
            loop {
                let changed = self.inner.pressure_changed.notified();
                tokio::pin!(changed);
                changed.as_mut().enable();
                if let Ok((permit, elastic)) =
                    self.try_acquire_response_stream_memory(requested_bytes, protocol)
                {
                    return (permit, elastic);
                }
                changed.await;
            }
        })
        .await;

        match result {
            Ok((permit, elastic)) => {
                self.inner.metrics.record_response_stream_admission(
                    protocol,
                    if elastic { "elastic" } else { "waited" },
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
    ) -> Result<(ResponseStreamMemoryPermit, bool), ()> {
        let permits = u32::try_from(requested_bytes).map_err(|_| ())?;
        let fixed: Result<ResponseStreamMemoryPermit, ()> = (|| {
            let foreground_concurrency = self
                .inner
                .pools
                .try_acquire_foreground_response_streaming(permits)?;
            let concurrency = self.inner.pools.try_acquire_response_streaming(permits)?;
            let transient =
                self.try_reserve_transient(requested_bytes as u64, AdmissionClass::Foreground)?;
            Ok(self.response_stream_memory_permit(
                (Some(concurrency), Some(foreground_concurrency), None, None),
                transient,
                protocol,
                requested_bytes as u64,
            ))
        })();
        if let Ok(permit) = fixed {
            return Ok((permit, false));
        }

        // A normal-memory node may lend unused transient capacity to public
        // response streams. The dedicated elastic semaphore and the retained
        // foreground reserve keep this from starving uploads or turning a
        // burst of slow clients into unbounded memory use.
        if self.pressure() != MemoryPressure::Normal {
            return Err(());
        }
        let elastic_concurrency = self
            .inner
            .pools
            .try_acquire_elastic_foreground_response_streaming(permits)?;
        let transient =
            self.try_reserve_transient(requested_bytes as u64, AdmissionClass::Foreground)?;
        Ok((
            self.response_stream_memory_permit(
                (None, None, None, Some(elastic_concurrency)),
                transient,
                protocol,
                requested_bytes as u64,
            ),
            true,
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
                self.try_reserve_transient(requested_bytes as u64, AdmissionClass::PeerResponse)?;
            Ok(self.response_stream_memory_permit(
                (Some(concurrency), None, Some(background_concurrency), None),
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
        (concurrency, foreground_concurrency, background_concurrency, elastic_concurrency): (
            Option<tokio::sync::OwnedSemaphorePermit>,
            Option<tokio::sync::OwnedSemaphorePermit>,
            Option<tokio::sync::OwnedSemaphorePermit>,
            Option<tokio::sync::OwnedSemaphorePermit>,
        ),
        transient: TransientMemoryReservation,
        protocol: &'static str,
        bytes: u64,
    ) -> ResponseStreamMemoryPermit {
        self.inner
            .metrics
            .add_response_stream_reservation(protocol, bytes);
        ResponseStreamMemoryPermit {
            concurrency,
            foreground_concurrency,
            background_concurrency,
            elastic_concurrency,
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
        if requested_bytes == 0 {
            return Ok(TransientMemoryReservation {
                controller: self.clone(),
                permit: None,
                bytes: 0,
            });
        }
        if requested_bytes > self.transient_capacity_bytes() {
            return Err(());
        }
        let permits = u32::try_from(requested_bytes).map_err(|_| ())?;
        loop {
            self.wait_until_admission_allowed(class).await;
            let permit = self.inner.pools.acquire_transient(permits).await?;
            if self.allow_transient_admission(class) {
                return Ok(TransientMemoryReservation {
                    controller: self.clone(),
                    permit: Some(permit),
                    bytes: requested_bytes,
                });
            }
            drop(permit);
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
                permit: None,
                bytes: 0,
            });
        }
        if !self.allow_transient_admission(class)
            || requested_bytes > self.transient_capacity_bytes()
        {
            return Err(());
        }
        let permits = u32::try_from(requested_bytes).map_err(|_| ())?;
        let permit = self.inner.pools.try_acquire_transient(permits)?;
        Ok(TransientMemoryReservation {
            controller: self.clone(),
            permit: Some(permit),
            bytes: requested_bytes,
        })
    }

    fn allow_transient_admission(&self, class: AdmissionClass) -> bool {
        match class {
            AdmissionClass::Foreground | AdmissionClass::PeerResponse => {
                self.pressure() != MemoryPressure::Critical
            }
            AdmissionClass::Background => self.allow_background_admission(),
        }
    }

    async fn wait_until_admission_allowed(&self, class: AdmissionClass) {
        while !self.allow_transient_admission(class) {
            let changed = self.inner.pressure_changed.notified();
            if self.allow_transient_admission(class) {
                return;
            }
            changed.await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        constants::RESPONSE_STREAM_MIN_CHUNK_BYTES,
        memory::reservation::RESPONSE_STREAM_ADMISSION_TIMEOUT,
    };
    use tokio::sync::Barrier;
    use tokio::task::JoinSet;

    #[test]
    fn forced_pressure_override_parses_only_known_spellings() {
        // Fails open: a misspelled or unset value never pins the node.
        assert_eq!(parse_forced_memory_pressure(""), None);
        assert_eq!(parse_forced_memory_pressure("nope"), None);
        assert_eq!(parse_forced_memory_pressure("  Critical-ish "), None);
        // Known tiers, case- and whitespace-insensitive.
        assert_eq!(
            parse_forced_memory_pressure("normal"),
            Some(MemoryPressure::Normal)
        );
        assert_eq!(
            parse_forced_memory_pressure("  CONSTRAINED "),
            Some(MemoryPressure::Constrained)
        );
        assert_eq!(
            parse_forced_memory_pressure("Critical"),
            Some(MemoryPressure::Critical)
        );
    }

    #[test]
    fn forced_pressure_still_advances_the_observation_sequence() {
        // The stall watchdog in spawn_memory_pressure_tasks terminates Kura
        // when observation_sequence stops advancing. A forced tier must still
        // look like an ongoing observation, or the pinned-pressure scenario
        // self-terminates within five seconds.
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::new_with_forced_pressure(
            metrics,
            100,
            200,
            MemoryPressure::Constrained,
        );
        let before = controller.observation_sequence();
        let pressure = controller.observe(50);
        assert_eq!(pressure, MemoryPressure::Constrained);
        assert!(
            controller.observation_sequence() > before,
            "a forced tier must still advance the observation sequence so the stall watchdog does not terminate the process"
        );
    }

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
    fn clean_file_cache_at_the_hard_limit_closes_background_admission() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(metrics, 240, 100, 200);

        assert_eq!(
            controller.observe_container(ContainerMemoryPressureSample {
                current_bytes: 220,
                pressure_bytes: 60,
                working_set_bytes: 180,
                reclaimable_inactive_file_bytes: 40,
                limit_bytes: Some(240),
            }),
            // The tier follows `pressure_bytes`, which excludes the clean file
            // cache making up the bulk of the charge, so foreground admission
            // stays open and public reads keep being served.
            MemoryPressure::Normal
        );
        assert!(controller.should_reclaim_file_cache());
        assert!(controller.try_acquire_mmap_serving(1).is_none());
        assert!(controller.container_at_hard_limit());
        assert!(!controller.allow_background_admission());
        assert!(!controller.allow_segment_refresh());
        assert!(!controller.allow_manifest_cache_admission());
        assert!(controller.pause_usage_outbox());
        assert!(
            controller.allow_transient_admission(AdmissionClass::Foreground),
            "clean file cache at the hard watermark must not shed public reads"
        );

        assert_eq!(
            controller.observe_container(ContainerMemoryPressureSample {
                current_bytes: 80,
                pressure_bytes: 60,
                working_set_bytes: 60,
                reclaimable_inactive_file_bytes: 20,
                limit_bytes: Some(240),
            }),
            MemoryPressure::Normal
        );
        assert!(!controller.should_reclaim_file_cache());
        assert!(controller.try_acquire_mmap_serving(1).is_some());
        assert!(!controller.container_at_hard_limit());
        assert!(controller.allow_background_admission());
    }

    #[test]
    fn working_set_reclaim_arm_recovers_with_hysteresis() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        // soft = 100, hard = 200, recovery clears at 90 (10% below the soft watermark).
        let controller = MemoryController::with_runtime_limit(metrics, 240, 100, 200);

        assert_eq!(
            controller.observe_container(ContainerMemoryPressureSample {
                current_bytes: 150,
                pressure_bytes: 40,
                working_set_bytes: 180,
                reclaimable_inactive_file_bytes: 40,
                limit_bytes: Some(240),
            }),
            MemoryPressure::Normal
        );
        assert!(controller.should_reclaim_file_cache());

        // Working set dips below the soft watermark but stays above the recovery
        // threshold. A raw threshold would clear reclaim here; hysteresis keeps it on.
        assert_eq!(
            controller.observe_container(ContainerMemoryPressureSample {
                current_bytes: 120,
                pressure_bytes: 40,
                working_set_bytes: 95,
                reclaimable_inactive_file_bytes: 25,
                limit_bytes: Some(240),
            }),
            MemoryPressure::Normal
        );
        assert!(controller.should_reclaim_file_cache());

        // Only once the working set recovers below the hysteresis threshold does the
        // reclaim signal clear.
        assert_eq!(
            controller.observe_container(ContainerMemoryPressureSample {
                current_bytes: 110,
                pressure_bytes: 40,
                working_set_bytes: 85,
                reclaimable_inactive_file_bytes: 25,
                limit_bytes: Some(240),
            }),
            MemoryPressure::Normal
        );
        assert!(!controller.should_reclaim_file_cache());
    }

    #[test]
    fn raw_hard_limit_closes_background_admission_without_hysteresis() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(metrics, 240, 100, 200);

        // Container charge at the hard watermark with a low working set must stop
        // background work immediately. Clean file cache is reclaimable, but it is
        // still charged against the hard container limit until that reclaim happens.
        // Foreground serving is left alone: the working set is far below the soft
        // watermark, so the charge is page cache the kernel can hand back.
        assert_eq!(
            controller.observe_container(ContainerMemoryPressureSample {
                current_bytes: 200,
                pressure_bytes: 40,
                working_set_bytes: 40,
                reclaimable_inactive_file_bytes: 160,
                limit_bytes: Some(240),
            }),
            MemoryPressure::Normal
        );
        assert!(controller.should_reclaim_file_cache());
        assert!(controller.container_at_hard_limit());
        assert!(!controller.allow_background_admission());
        assert!(controller.allow_transient_admission(AdmissionClass::Foreground));

        // The raw arm is un-hysteresed: dropping back below the watermark reopens
        // background work on the next sample.
        assert_eq!(
            controller.observe_container(ContainerMemoryPressureSample {
                current_bytes: 150,
                pressure_bytes: 40,
                working_set_bytes: 40,
                reclaimable_inactive_file_bytes: 110,
                limit_bytes: Some(240),
            }),
            MemoryPressure::Normal
        );
        assert!(!controller.container_at_hard_limit());
        assert!(controller.allow_background_admission());
    }

    #[test]
    fn a_warm_serving_node_keeps_admitting_public_reads_with_page_cache_at_the_limit() {
        // Mirrors a production 2 GiB cache node: the cgroup charge sits just over
        // the 85% hard watermark because the kernel is holding clean artifact
        // pages, while the real working set is a small fraction of the limit.
        // This is the steady state of a warm node, not an overload, and it must
        // not shed reads.
        let metrics = Metrics::new("us-east".into(), "tenant".into());
        let runtime_limit = 2 * 1024 * 1024 * 1024_u64;
        let soft_limit = runtime_limit * 60 / 100;
        let hard_limit = runtime_limit * 85 / 100;
        let controller =
            MemoryController::with_runtime_limit(metrics, runtime_limit, soft_limit, hard_limit);

        assert_eq!(
            controller.observe_container(ContainerMemoryPressureSample {
                current_bytes: 1_852_125_184,
                pressure_bytes: 192_602_112,
                working_set_bytes: 191_483_904,
                reclaimable_inactive_file_bytes: 1_600_000_000,
                limit_bytes: Some(runtime_limit),
            }),
            MemoryPressure::Normal
        );
        assert!(controller.container_at_hard_limit());
        assert!(controller.should_reclaim_file_cache());
        assert!(!controller.allow_background_admission());
        assert!(
            controller
                .try_acquire_response_stream_memory(
                    crate::constants::response_stream_chunk_bytes(4 * 1024 * 1024),
                    "http"
                )
                .is_ok(),
            "a public artifact read must be admitted while the charge is clean file cache"
        );
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
    fn reapi_materialization_limit_is_clamped_from_memory_headroom() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let small = MemoryController::new(metrics.clone(), 24 * 1024 * 1024, 48 * 1024 * 1024);
        let medium = MemoryController::new(metrics.clone(), 128 * 1024 * 1024, 256 * 1024 * 1024);
        let large = MemoryController::new(metrics, 8 * 1024 * 1024 * 1024, 9 * 1024 * 1024 * 1024);

        assert_eq!(small.reapi_materialization_limit_bytes(), 12 * 1024 * 1024);
        assert_eq!(medium.reapi_materialization_limit_bytes(), 64 * 1024 * 1024);
        assert_eq!(large.reapi_materialization_limit_bytes(), 128 * 1024 * 1024);
    }

    #[test]
    fn default_runtime_preserves_the_sixty_four_mebibyte_response_contract() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            1024 * 1024 * 1024,
            614 * 1024 * 1024,
            870 * 1024 * 1024,
        );

        assert_eq!(
            controller.reapi_materialization_limit_bytes(),
            128 * 1024 * 1024
        );
        assert_eq!(controller.reapi_response_budget_bytes(), 64 * 1024 * 1024);
    }

    #[test]
    fn mmap_serving_pool_is_bounded_by_memory_headroom() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let tiny = MemoryController::new(metrics.clone(), 89 * 1024 * 1024, 108 * 1024 * 1024);
        let small = MemoryController::new(metrics.clone(), 128 * 1024 * 1024, 192 * 1024 * 1024);
        let medium = MemoryController::new(metrics.clone(), 512 * 1024 * 1024, 768 * 1024 * 1024);
        let large = MemoryController::new(metrics, 2 * 1024 * 1024 * 1024, 4 * 1024 * 1024 * 1024);

        assert_eq!(tiny.mmap_serving_pool_bytes(), 19 * 1024 * 1024);
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
    fn response_streaming_pool_scales_with_memory_headroom() {
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
        assert_eq!(large.response_streaming_pool_bytes(), 512 * 1024 * 1024);
        assert_eq!(
            large.foreground_response_streaming_pool_bytes(),
            506 * 1024 * 1024
        );
        assert_eq!(
            large.elastic_foreground_response_streaming_pool_bytes(),
            256 * 1024 * 1024
        );
    }

    #[test]
    fn small_runtime_keeps_a_full_bootstrap_response_reservation() {
        let controller = MemoryController::with_runtime_limit(
            Metrics::new("eu-west".into(), "tenant".into()),
            128 * 1024 * 1024,
            76 * 1024 * 1024,
            108 * 1024 * 1024,
        );

        assert_eq!(controller.response_streaming_pool_bytes(), 10 * 1024 * 1024);
        assert_eq!(
            controller.foreground_response_streaming_pool_bytes(),
            4 * 1024 * 1024
        );
        controller
            .try_acquire_background_response_stream_memory(6 * 1024 * 1024, "bootstrap")
            .expect("small profiles must bootstrap the largest supported inline artifact");
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
            .acquire_response_stream_memory(
                1024 * 1024,
                "http",
                ResponseStreamAdmissionPatience::Degradable,
            )
            .await
            .expect("stream permit should be admitted");
        assert_eq!(controller.transient_reserved_bytes(), 1024 * 1024);

        let guard = permit.into_transport_guard();
        let transport_owned = guard.clone();
        drop(guard);
        assert_eq!(controller.transient_reserved_bytes(), 1024 * 1024);
        drop(transport_owned);
        assert_eq!(controller.transient_reserved_bytes(), 0);
        controller
            .acquire_response_stream_memory(
                controller.foreground_response_streaming_pool_bytes(),
                "bytestream",
                ResponseStreamAdmissionPatience::Blocking,
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
    fn bootstrap_keeps_a_progress_quantum_without_consuming_public_response_capacity() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            256 * 1024 * 1024,
            128 * 1024 * 1024,
            192 * 1024 * 1024,
        );
        assert_eq!(
            controller.observe(128 * 1024 * 1024),
            MemoryPressure::Constrained
        );
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
        let bootstrap = controller
            .try_acquire_background_response_stream_memory(bootstrap_quantum, "bootstrap")
            .expect("the reserved bootstrap quantum should be available");
        let foreground = controller
            .try_acquire_response_stream_memory(foreground_bytes, "http")
            .expect("bootstrap must not consume capacity promised to public responses");
        assert!(
            controller
                .try_acquire_background_response_stream_memory(1, "bootstrap")
                .is_err(),
            "bootstrap must remain bounded to its reserved progress quantum"
        );
        drop(foreground);
        drop(bootstrap);
    }

    #[test]
    fn public_response_streams_borrow_a_bounded_elastic_tier_only_while_normal() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            512 * 1024 * 1024,
            256 * 1024 * 1024,
            384 * 1024 * 1024,
        );
        let foreground_bytes = controller.foreground_response_streaming_pool_bytes();
        let elastic_bytes = controller.elastic_foreground_response_streaming_pool_bytes();
        let (_fixed, fixed_elastic) = controller
            .try_acquire_response_stream_memory(foreground_bytes, "http")
            .expect("fixed response-stream capacity should be available");
        assert!(!fixed_elastic);
        let (_elastic, elastic) = controller
            .try_acquire_response_stream_memory(elastic_bytes, "http")
            .expect("normal-memory nodes should lend bounded transient capacity");
        assert!(elastic);
        assert!(
            controller
                .try_acquire_response_stream_memory(1, "http")
                .is_err(),
            "the elastic tier must remain a bounded pool"
        );
        assert!(
            controller
                .try_reserve_foreground_memory(32 * 1024 * 1024)
                .is_ok(),
            "elastic serving must retain foreground capacity for uploads"
        );

        let constrained = MemoryController::with_runtime_limit(
            Metrics::new("eu-west".into(), "tenant".into()),
            512 * 1024 * 1024,
            256 * 1024 * 1024,
            384 * 1024 * 1024,
        );
        let foreground_bytes = constrained.foreground_response_streaming_pool_bytes();
        let _fixed = constrained
            .try_acquire_response_stream_memory(foreground_bytes, "http")
            .expect("fixed capacity should be available");
        constrained.observe(256 * 1024 * 1024);
        assert!(
            constrained
                .try_acquire_response_stream_memory(1, "http")
                .is_err(),
            "elastic response serving must stop under memory pressure"
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn public_response_burst_uses_elastic_capacity_without_displacing_bootstrap() {
        const REQUEST_BYTES: usize = 512 * 1024;
        const EXTRA_REQUESTS: usize = 64;

        let controller = MemoryController::with_runtime_limit(
            Metrics::new("eu-west".into(), "tenant".into()),
            2 * 1024 * 1024 * 1024,
            1200 * 1024 * 1024,
            1700 * 1024 * 1024,
        );
        let bootstrap = controller
            .try_acquire_background_response_stream_memory(6 * 1024 * 1024, "bootstrap")
            .expect("the bootstrap progress quantum should be available");
        let expected_admitted = (controller.foreground_response_streaming_pool_bytes()
            + controller.elastic_foreground_response_streaming_pool_bytes())
            / REQUEST_BYTES;
        let requests = expected_admitted + EXTRA_REQUESTS;
        let barrier = Arc::new(Barrier::new(requests));
        let started_at = Instant::now();
        let mut tasks = JoinSet::new();

        for _ in 0..requests {
            let controller = controller.clone();
            let barrier = barrier.clone();
            tasks.spawn(async move {
                barrier.wait().await;
                controller.try_acquire_response_stream_memory(REQUEST_BYTES, "http")
            });
        }

        let mut admitted = Vec::with_capacity(expected_admitted);
        let mut full_size_unavailable = 0;
        while let Some(result) = tasks.join_next().await {
            match result.expect("burst task should not panic") {
                Ok((permit, _)) => admitted.push(permit),
                Err(()) => full_size_unavailable += 1,
            }
        }

        eprintln!(
            "admitted {} public response streams in {:?}",
            admitted.len(),
            started_at.elapsed()
        );
        assert_eq!(admitted.len(), expected_admitted);
        assert_eq!(full_size_unavailable, EXTRA_REQUESTS);
        assert_eq!(
            controller.transient_reserved_bytes(),
            (6 * 1024 * 1024 + admitted.len() * REQUEST_BYTES) as u64
        );

        let barrier = Arc::new(Barrier::new(EXTRA_REQUESTS));
        let mut tasks = JoinSet::new();
        for _ in 0..EXTRA_REQUESTS {
            let controller = controller.clone();
            let barrier = barrier.clone();
            tasks.spawn(async move {
                barrier.wait().await;
                assert!(
                    controller
                        .acquire_response_stream_memory(
                            REQUEST_BYTES,
                            "http",
                            ResponseStreamAdmissionPatience::Degradable,
                        )
                        .await
                        .is_err(),
                    "the full-size tier should remain exhausted"
                );
                controller
                    .acquire_degraded_response_stream_memory(
                        RESPONSE_STREAM_MIN_CHUNK_BYTES * 4,
                        "http",
                    )
                    .await
            });
        }

        let mut degraded = Vec::with_capacity(EXTRA_REQUESTS);
        while let Some(result) = tasks.join_next().await {
            degraded.push(
                result
                    .expect("degraded burst task should not panic")
                    .expect("public requests should fall back to bounded degraded streams"),
            );
        }
        assert_eq!(degraded.len(), EXTRA_REQUESTS);

        drop(degraded);
        drop(admitted);
        drop(bootstrap);
    }

    #[tokio::test]
    async fn a_degradable_caller_gives_up_far_sooner_than_one_that_would_error() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            256 * 1024 * 1024,
            128 * 1024 * 1024,
            192 * 1024 * 1024,
        );
        controller.observe(0);
        // Occupy the whole pool so neither caller can be admitted.
        let _fixed = controller
            .try_acquire_response_stream_memory(
                controller.foreground_response_streaming_pool_bytes(),
                "http",
            )
            .expect("the pool should start empty");
        let _elastic = controller
            .try_acquire_response_stream_memory(
                controller.elastic_foreground_response_streaming_pool_bytes(),
                "http",
            )
            .expect("the elastic pool should start empty");

        let started_at = Instant::now();
        assert!(
            controller
                .acquire_response_stream_memory(
                    1024 * 1024,
                    "http",
                    ResponseStreamAdmissionPatience::Degradable,
                )
                .await
                .is_err()
        );
        let degradable_wait = started_at.elapsed();

        // An HTTP read still serves the object after this returns, so waiting
        // longer would only delay bytes it could already be sending.
        assert!(
            degradable_wait < RESPONSE_STREAM_ADMISSION_TIMEOUT / 2,
            "a degradable caller must not pay the blocking timeout, waited {degradable_wait:?}"
        );
        assert!(
            ResponseStreamAdmissionPatience::Blocking.timeout()
                > ResponseStreamAdmissionPatience::Degradable.timeout(),
            "a caller whose fallback is an error must be the more patient one"
        );
    }

    #[tokio::test]
    async fn degraded_streams_are_capped_at_the_real_per_stream_send_buffer() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            256 * 1024 * 1024,
            128 * 1024 * 1024,
            192 * 1024 * 1024,
        );
        controller.observe(0);

        // The cap counts Hyper's per-stream send buffer, not the degraded
        // reader's 8 KiB chunk floor, so the aggregate stays bounded.
        let slots = controller.degraded_response_stream_slots();
        assert_eq!(
            slots,
            controller.response_streaming_pool_bytes() / RESPONSE_STREAM_SEND_BUFFER_BYTES
        );

        let mut held = Vec::new();
        for _ in 0..slots {
            held.push(
                controller
                    .acquire_degraded_response_stream_memory(8 * 1024, "http")
                    .await
                    .expect("a stream inside the cap must be admitted"),
            );
        }
        assert!(
            held.iter().all(|permit| permit.holds_degraded_slot()),
            "every stream inside the cap must hold a slot"
        );
        assert_eq!(
            controller.transient_reserved_bytes(),
            (slots * RESPONSE_STREAM_SEND_BUFFER_BYTES) as u64,
            "each degraded stream must reserve its complete transport buffer cost"
        );

        // Past the cap the wait stays bounded and no unaccounted stream is
        // returned to the caller.
        let overflow = controller
            .acquire_degraded_response_stream_memory(8 * 1024, "http")
            .await;
        assert_eq!(overflow.err(), Some(ResponseStreamAdmissionError::Timeout));
        assert!(
            controller
                .inner
                .metrics
                .render()
                .contains("outcome=\"degraded_timeout\"")
        );

        drop(held.pop());
        assert!(
            controller
                .acquire_degraded_response_stream_memory(8 * 1024, "http")
                .await
                .expect("a released slot must admit another stream")
                .holds_degraded_slot(),
            "a released slot must become reusable"
        );
    }

    #[tokio::test]
    async fn degraded_streams_require_transient_memory_headroom() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            256 * 1024 * 1024,
            128 * 1024 * 1024,
            192 * 1024 * 1024,
        );
        controller.observe(192 * 1024 * 1024);

        let result = controller
            .acquire_degraded_response_stream_memory(8 * 1024, "http")
            .await;

        assert_eq!(result.err(), Some(ResponseStreamAdmissionError::QueueFull));
        assert!(
            controller
                .inner
                .metrics
                .render()
                .contains("outcome=\"degraded_memory_unavailable\"")
        );
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
    fn transient_permits_use_a_fixed_budget_independent_of_samples() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(metrics, 1_000, 700, 850);
        controller.observe(800);

        let first = controller
            .try_acquire_reapi_materialization(75)
            .expect("first half of the transient budget should fit")
            .expect("non-zero reservation should return a permit");
        let second = controller
            .try_acquire_reapi_materialization(75)
            .expect("second half should fit despite the sampled usage")
            .expect("non-zero reservation should return a permit");
        assert!(controller.try_acquire_reapi_materialization(1).is_err());
        assert_eq!(controller.transient_reserved_bytes(), 150);
        drop((first, second));
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

    #[test]
    fn peer_response_reservations_continue_while_constrained() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(metrics, 1_000, 700, 850);

        assert_eq!(controller.observe(700), MemoryPressure::Constrained);
        let permit = controller
            .try_acquire_background_response_stream_memory(10, "bootstrap")
            .expect("bounded peer responses should remain available while constrained");
        drop(permit);

        assert_eq!(controller.observe(850), MemoryPressure::Critical);
        assert!(
            controller
                .try_acquire_background_response_stream_memory(10, "bootstrap")
                .is_err(),
            "critical pressure must still shed peer responses"
        );
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

    #[tokio::test]
    async fn foreground_waiter_is_not_bypassed_by_a_smaller_new_arrival() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(metrics, 100, 40, 50);
        let (first, _) = controller
            .reserve_foreground_memory(10)
            .await
            .expect("the first reservation should fill the budget");

        let (older_acquired_tx, older_acquired_rx) = tokio::sync::oneshot::channel();
        let (release_older_tx, release_older_rx) = tokio::sync::oneshot::channel();
        let older = tokio::spawn({
            let controller = controller.clone();
            async move {
                let (reservation, _) = controller
                    .reserve_foreground_memory(10)
                    .await
                    .expect("the older waiter should acquire the whole budget");
                older_acquired_tx
                    .send(())
                    .expect("the acquisition signal should be observed");
                let _ = release_older_rx.await;
                drop(reservation);
            }
        });
        while controller.inner.foreground_waiters.load(Ordering::Acquire) == 0 {
            tokio::task::yield_now().await;
        }

        let younger = tokio::spawn({
            let controller = controller.clone();
            async move {
                let (reservation, _) = controller
                    .reserve_foreground_memory(1)
                    .await
                    .expect("the younger waiter should eventually acquire");
                drop(reservation);
            }
        });
        drop(first);

        tokio::time::timeout(std::time::Duration::from_secs(1), older_acquired_rx)
            .await
            .expect("the older waiter should acquire first")
            .expect("the older waiter should send its signal");
        assert!(!younger.is_finished());
        release_older_tx
            .send(())
            .expect("the older reservation should still be held");
        older.await.expect("the older task should finish");
        younger.await.expect("the younger task should finish");
    }
}
