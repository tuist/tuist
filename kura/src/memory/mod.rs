use std::sync::{
    Arc,
    atomic::{AtomicU8, AtomicU64, Ordering},
};

use tokio::sync::{Notify, OwnedSemaphorePermit};
use tokio::time::timeout;

use crate::metrics::Metrics;

mod cgroup;
mod pools;
mod pressure;
mod reservation;

pub use cgroup::{
    ContainerMemorySnapshot, container_memory_snapshot, container_memory_working_set_bytes,
};
pub use pressure::MemoryPressure;
pub use reservation::{
    ForegroundAdmissionTimeout, ForegroundMemoryReservation, MemoryPermit,
    TransientMemoryReservation,
};

use pools::MemoryPools;
use pressure::transition;
use reservation::{AdmissionClass, FOREGROUND_ADMISSION_TIMEOUT, ForegroundWaiter};

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

struct MemoryControllerInner {
    runtime_limit_bytes: u64,
    soft_limit_bytes: u64,
    hard_limit_bytes: u64,
    foreground_waiters: AtomicU64,
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
        metrics.update_memory_limits(soft_limit_bytes, hard_limit_bytes);
        metrics.update_memory_pressure_state(MemoryPressure::Normal.as_i64());
        Self {
            inner: Arc::new(MemoryControllerInner {
                runtime_limit_bytes,
                soft_limit_bytes,
                hard_limit_bytes,
                foreground_waiters: AtomicU64::new(0),
                state: AtomicU8::new(MemoryPressure::Normal.as_u8()),
                pressure_changed: Notify::new(),
                pools: MemoryPools::new(soft_limit_bytes, hard_limit_bytes),
                metrics,
            }),
        }
    }

    pub fn observe(&self, resident_bytes: u64) -> MemoryPressure {
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

    pub fn transient_capacity_bytes(&self) -> u64 {
        self.inner.pools.transient_capacity_bytes() as u64
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

    pub fn try_acquire_mmap_serving(&self, requested_bytes: usize) -> Option<OwnedSemaphorePermit> {
        if requested_bytes == 0 || self.pressure() != MemoryPressure::Normal {
            return None;
        }
        let permits = u32::try_from(requested_bytes).ok()?;
        self.inner.pools.try_acquire_mmap_serving(permits)
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
            AdmissionClass::Foreground => self.pressure() != MemoryPressure::Critical,
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
        assert!(
            controller
                .try_acquire_mmap_serving(65 * 1024 * 1024)
                .is_none()
        );

        drop(permit);
        controller.observe(128 * 1024 * 1024);
        assert!(controller.try_acquire_mmap_serving(1).is_none());
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
