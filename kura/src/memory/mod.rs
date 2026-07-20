use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering},
};

use tokio::sync::{Notify, OwnedSemaphorePermit, Semaphore};
use tokio::time::timeout;

use crate::metrics::Metrics;

const RECOVERY_NUMERATOR: u64 = 9;
const RECOVERY_DENOMINATOR: u64 = 10;
const MIN_REAPI_RESPONSE_BUDGET_BYTES: usize = 8 * 1024 * 1024;
const MAX_REAPI_RESPONSE_BUDGET_BYTES: usize = 64 * 1024 * 1024;
const MAX_REAPI_MATERIALIZATION_POOL_BYTES: usize = 128 * 1024 * 1024;
const MIN_MMAP_SERVING_POOL_BYTES: usize = 64 * 1024 * 1024;
const MAX_MMAP_SERVING_POOL_BYTES: usize = 512 * 1024 * 1024;
pub const FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES: u64 = 8 * 1024 * 1024;
pub const FOREGROUND_STAGING_WINDOW_BYTES: u64 = 16 * 1024 * 1024;
const FOREGROUND_ADMISSION_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(30);

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
    transient_reserved_bytes: AtomicU64,
    foreground_waiters: AtomicU64,
    state: AtomicU8,
    pressure_changed: Notify,
    reapi_materialization_pool: Arc<Semaphore>,
    mmap_serving_pool: Arc<Semaphore>,
    metrics: Metrics,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum MemoryPressure {
    Normal,
    Constrained,
    Critical,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum AdmissionClass {
    Foreground,
    Background,
}

pub struct MemoryPermit {
    _concurrency: OwnedSemaphorePermit,
    _transient: TransientMemoryReservation,
}

pub struct TransientMemoryReservation {
    controller: MemoryController,
    bytes: u64,
}

pub struct ForegroundMemoryReservation {
    _transient: TransientMemoryReservation,
    file_cache_policy: FileCachePolicy,
    stream_message_high_water_bytes: u64,
    stream_staging_bytes: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FileCachePolicy {
    Adaptive,
    Foreground { reservation_bytes: u64 },
    Bounded,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ForegroundAdmissionTimeout;

impl ForegroundMemoryReservation {
    pub fn file_cache_policy(&self) -> FileCachePolicy {
        self.file_cache_policy
    }

    pub fn try_grow_stream_decode(&mut self, encoded_message_bytes: u64) -> Result<(), ()> {
        let high_water_bytes = self
            .stream_message_high_water_bytes
            .max(encoded_message_bytes);
        let requested_bytes = high_water_bytes
            .saturating_mul(2)
            .saturating_add(self.stream_staging_bytes);
        self._transient.try_resize_foreground(requested_bytes)?;
        self.stream_message_high_water_bytes = high_water_bytes;
        if let FileCachePolicy::Foreground { .. } = self.file_cache_policy {
            self.file_cache_policy = FileCachePolicy::Foreground {
                reservation_bytes: requested_bytes,
            };
        }
        Ok(())
    }

    pub fn try_configure_for_streaming_staging(
        &mut self,
        declared_or_max_bytes: u64,
    ) -> Result<FileCachePolicy, ()> {
        let staging_bytes = declared_or_max_bytes
            .min(FOREGROUND_STAGING_WINDOW_BYTES)
            .saturating_mul(2);
        let requested_bytes = self
            .stream_message_high_water_bytes
            .saturating_mul(2)
            .saturating_add(staging_bytes);
        self._transient.try_resize_foreground(requested_bytes)?;
        self.stream_staging_bytes = staging_bytes;
        self.file_cache_policy = if declared_or_max_bytes > FOREGROUND_STAGING_WINDOW_BYTES {
            FileCachePolicy::Bounded
        } else {
            FileCachePolicy::Foreground {
                reservation_bytes: requested_bytes,
            }
        };
        Ok(self.file_cache_policy)
    }
}

impl Drop for ForegroundMemoryReservation {
    fn drop(&mut self) {
        // Convert the completed upload's real kernel charge into the controller
        // baseline before the transient reservation is released and wakes the
        // next waiter. Otherwise several sub-200 ms uploads can reuse the same
        // stale headroom while their retained segment pages are already charged
        // to the container.
        let controller = &self._transient.controller;
        if (self.file_cache_policy == FileCachePolicy::Bounded
            || controller.inner.foreground_waiters.load(Ordering::Acquire) > 0)
            && let Some(current_bytes) = container_memory_current_bytes()
        {
            controller.observe(current_bytes);
        }
    }
}

impl FileCachePolicy {
    pub fn should_drop(self, pressure: MemoryPressure, transient_reserved_bytes: u64) -> bool {
        match self {
            Self::Adaptive => pressure != MemoryPressure::Normal,
            Self::Foreground { reservation_bytes } => {
                pressure != MemoryPressure::Normal || transient_reserved_bytes > reservation_bytes
            }
            Self::Bounded => true,
        }
    }

    pub fn drop_failure_is_fatal(self) -> bool {
        self != Self::Adaptive
    }
}

struct ForegroundWaiter {
    inner: Arc<MemoryControllerInner>,
}

impl ForegroundWaiter {
    fn new(inner: Arc<MemoryControllerInner>) -> Self {
        inner.foreground_waiters.fetch_add(1, Ordering::AcqRel);
        Self { inner }
    }
}

impl Drop for ForegroundWaiter {
    fn drop(&mut self) {
        self.inner.foreground_waiters.fetch_sub(1, Ordering::AcqRel);
    }
}

impl Drop for TransientMemoryReservation {
    fn drop(&mut self) {
        self.controller
            .inner
            .transient_reserved_bytes
            .fetch_sub(self.bytes, Ordering::AcqRel);
        self.controller.inner.pressure_changed.notify_waiters();
    }
}

impl TransientMemoryReservation {
    fn try_resize_foreground(&mut self, requested_bytes: u64) -> Result<(), ()> {
        if requested_bytes > self.bytes {
            self.controller
                .try_grow_transient(requested_bytes - self.bytes, AdmissionClass::Foreground)?;
        } else if requested_bytes < self.bytes {
            self.controller
                .inner
                .transient_reserved_bytes
                .fetch_sub(self.bytes - requested_bytes, Ordering::AcqRel);
            self.controller.inner.pressure_changed.notify_waiters();
        }
        self.bytes = requested_bytes;
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ContainerMemorySnapshot {
    pub current_bytes: u64,
    pub limit_bytes: Option<u64>,
    pub anon_bytes: Option<u64>,
    pub file_bytes: Option<u64>,
    pub kernel_bytes: Option<u64>,
    pub inactive_file_bytes: Option<u64>,
    pub oom_events: Option<u64>,
    pub oom_kill_events: Option<u64>,
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
                current_bytes: AtomicU64::new(0),
                current_known: AtomicBool::new(false),
                transient_reserved_bytes: AtomicU64::new(0),
                foreground_waiters: AtomicU64::new(0),
                state: AtomicU8::new(MemoryPressure::Normal.as_u8()),
                pressure_changed: Notify::new(),
                reapi_materialization_pool: Arc::new(Semaphore::new(
                    reapi_materialization_pool_bytes(soft_limit_bytes, hard_limit_bytes),
                )),
                mmap_serving_pool: Arc::new(Semaphore::new(mmap_serving_pool_bytes(
                    soft_limit_bytes,
                    hard_limit_bytes,
                ))),
                metrics,
            }),
        }
    }

    pub fn observe(&self, resident_bytes: u64) -> MemoryPressure {
        self.inner
            .current_bytes
            .store(resident_bytes, Ordering::Release);
        self.inner.current_known.store(true, Ordering::Release);
        self.inner.pressure_changed.notify_waiters();
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

    pub fn current_bytes(&self) -> Option<u64> {
        self.inner
            .current_known
            .load(Ordering::Acquire)
            .then(|| self.inner.current_bytes.load(Ordering::Acquire))
    }

    pub fn transient_reserved_bytes(&self) -> u64 {
        self.inner.transient_reserved_bytes.load(Ordering::Acquire)
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
        let normal_budget = clamp_u64(
            self.inner.soft_limit_bytes / 4,
            MIN_REAPI_RESPONSE_BUDGET_BYTES as u64,
            MAX_REAPI_RESPONSE_BUDGET_BYTES as u64,
        ) as usize;
        let normal_budget = normal_budget.min(self.reapi_materialization_pool_bytes());
        match self.pressure() {
            MemoryPressure::Normal => normal_budget,
            MemoryPressure::Constrained => normal_budget / 2,
            MemoryPressure::Critical => 0,
        }
    }

    pub fn reapi_materialization_pool_bytes(&self) -> usize {
        reapi_materialization_pool_bytes(self.inner.soft_limit_bytes, self.inner.hard_limit_bytes)
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
            .reapi_materialization_pool
            .clone()
            .acquire_many_owned(permits)
            .await
            .map_err(|_| ())?;
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
            .reapi_materialization_pool
            .clone()
            .try_acquire_many_owned(permits)
            .map_err(|_| ())?;
        Ok(Some(MemoryPermit {
            _concurrency: concurrency,
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

    /// Reserves the maximum source-plus-destination file-cache working set for
    /// a disk-backed foreground upload. Objects larger than one working window
    /// must keep both staging and segment-copy cache ranges bounded while this
    /// guard is held.
    pub async fn reserve_foreground_staging(
        &self,
        declared_or_max_bytes: u64,
    ) -> Result<ForegroundMemoryReservation, ForegroundAdmissionTimeout> {
        let working_set_bytes = declared_or_max_bytes.min(FOREGROUND_STAGING_WINDOW_BYTES);
        let requested_bytes = working_set_bytes.saturating_mul(2);
        self.reserve_foreground_staging_inner(declared_or_max_bytes, requested_bytes)
            .await
    }

    /// Reserves the first streaming message's exact retained wire buffer and
    /// decoded copy before tonic allocates either. The caller expands this to
    /// the declared stream and disk working sets after decoding the resource
    /// name. Both operations are non-blocking so a rejected HTTP/2 stream is
    /// reset instead of waiting while it consumes shared connection flow-control.
    pub fn try_reserve_foreground_stream_decode(
        &self,
        encoded_message_bytes: u64,
    ) -> Result<ForegroundMemoryReservation, ()> {
        let requested_bytes = encoded_message_bytes.saturating_mul(2);
        let reservation =
            self.try_reserve_transient(requested_bytes, AdmissionClass::Foreground)?;
        Ok(ForegroundMemoryReservation {
            _transient: reservation,
            file_cache_policy: FileCachePolicy::Foreground {
                reservation_bytes: requested_bytes,
            },
            stream_message_high_water_bytes: encoded_message_bytes,
            stream_staging_bytes: 0,
        })
    }

    async fn reserve_foreground_staging_inner(
        &self,
        declared_or_max_bytes: u64,
        requested_bytes: u64,
    ) -> Result<ForegroundMemoryReservation, ForegroundAdmissionTimeout> {
        let mut file_cache_policy = if declared_or_max_bytes > FOREGROUND_STAGING_WINDOW_BYTES {
            FileCachePolicy::Bounded
        } else {
            FileCachePolicy::Foreground {
                reservation_bytes: requested_bytes,
            }
        };

        let reservation =
            match self.try_reserve_transient(requested_bytes, AdmissionClass::Foreground) {
                Ok(reservation) => reservation,
                Err(()) => {
                    // A queued request must not leave another full source and
                    // destination population behind when it eventually runs;
                    // keep its staging and segment-copy ranges bounded even if
                    // the pressure sensor has not crossed a watermark.
                    file_cache_policy = FileCachePolicy::Bounded;
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
                        Ok(Ok(reservation)) => reservation,
                        Ok(Err(())) | Err(_) => {
                            self.inner
                                .metrics
                                .record_memory_action("foreground_upload_admission_timeout");
                            return Err(ForegroundAdmissionTimeout);
                        }
                    }
                }
            };

        Ok(ForegroundMemoryReservation {
            _transient: reservation,
            file_cache_policy,
            stream_message_high_water_bytes: 0,
            stream_staging_bytes: 0,
        })
    }

    pub fn mmap_serving_pool_bytes(&self) -> usize {
        mmap_serving_pool_bytes(self.inner.soft_limit_bytes, self.inner.hard_limit_bytes)
    }

    pub fn try_acquire_mmap_serving(&self, requested_bytes: usize) -> Option<OwnedSemaphorePermit> {
        if requested_bytes == 0 || self.pressure() != MemoryPressure::Normal {
            return None;
        }
        let permits = u32::try_from(requested_bytes).ok()?;
        self.inner
            .mmap_serving_pool
            .clone()
            .try_acquire_many_owned(permits)
            .ok()
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
            });
        }
        self.try_grow_transient(requested_bytes, class)?;
        Ok(TransientMemoryReservation {
            controller: self.clone(),
            bytes: requested_bytes,
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
        let current = self.current_bytes().unwrap_or(0);
        loop {
            let reserved = self.inner.transient_reserved_bytes.load(Ordering::Acquire);
            let available = ceiling.saturating_sub(current).saturating_sub(reserved);
            if requested_bytes > available {
                return Err(());
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
                return Ok(());
            }
        }
    }
}

pub fn container_memory_current_bytes() -> Option<u64> {
    #[cfg(target_os = "linux")]
    {
        read_u64_file("/sys/fs/cgroup/memory.current")
            .or_else(|| read_u64_file("/sys/fs/cgroup/memory/memory.usage_in_bytes"))
    }
    #[cfg(not(target_os = "linux"))]
    {
        None
    }
}

pub fn container_memory_snapshot() -> Option<ContainerMemorySnapshot> {
    #[cfg(target_os = "linux")]
    {
        if let Some(current_bytes) = read_u64_file("/sys/fs/cgroup/memory.current") {
            let stat = std::fs::read_to_string("/sys/fs/cgroup/memory.stat").ok();
            let events = std::fs::read_to_string("/sys/fs/cgroup/memory.events").ok();
            return Some(ContainerMemorySnapshot {
                current_bytes,
                limit_bytes: read_memory_limit_file("/sys/fs/cgroup/memory.max"),
                anon_bytes: stat.as_deref().and_then(|value| named_value(value, "anon")),
                file_bytes: stat.as_deref().and_then(|value| named_value(value, "file")),
                kernel_bytes: stat
                    .as_deref()
                    .and_then(|value| named_value(value, "kernel")),
                inactive_file_bytes: stat
                    .as_deref()
                    .and_then(|value| named_value(value, "inactive_file")),
                oom_events: events
                    .as_deref()
                    .and_then(|value| named_value(value, "oom")),
                oom_kill_events: events
                    .as_deref()
                    .and_then(|value| named_value(value, "oom_kill")),
            });
        }

        let current_bytes = read_u64_file("/sys/fs/cgroup/memory/memory.usage_in_bytes")?;
        let stat = std::fs::read_to_string("/sys/fs/cgroup/memory/memory.stat").ok();
        let events = std::fs::read_to_string("/sys/fs/cgroup/memory/memory.failcnt").ok();
        Some(ContainerMemorySnapshot {
            current_bytes,
            limit_bytes: read_memory_limit_file("/sys/fs/cgroup/memory/memory.limit_in_bytes"),
            anon_bytes: stat.as_deref().and_then(|value| named_value(value, "rss")),
            file_bytes: stat
                .as_deref()
                .and_then(|value| named_value(value, "cache")),
            kernel_bytes: None,
            inactive_file_bytes: stat
                .as_deref()
                .and_then(|value| named_value(value, "total_inactive_file")),
            oom_events: events
                .as_deref()
                .and_then(|value| value.trim().parse::<u64>().ok()),
            oom_kill_events: None,
        })
    }
    #[cfg(not(target_os = "linux"))]
    {
        None
    }
}

#[cfg(target_os = "linux")]
fn read_u64_file(path: &str) -> Option<u64> {
    std::fs::read_to_string(path).ok()?.trim().parse().ok()
}

#[cfg(target_os = "linux")]
fn read_memory_limit_file(path: &str) -> Option<u64> {
    let value = std::fs::read_to_string(path).ok()?;
    let value = value.trim();
    if value.is_empty() || value == "max" {
        None
    } else {
        value.parse().ok()
    }
}

#[cfg(any(target_os = "linux", test))]
fn named_value(input: &str, name: &str) -> Option<u64> {
    input.lines().find_map(|line| {
        let mut fields = line.split_ascii_whitespace();
        if fields.next()? != name {
            return None;
        }
        fields.next()?.parse().ok()
    })
}

fn recovery_bytes(limit: u64) -> u64 {
    limit
        .saturating_mul(RECOVERY_NUMERATOR)
        .saturating_div(RECOVERY_DENOMINATOR)
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
    fn reapi_materialization_pool_is_clamped_from_memory_headroom() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let small = MemoryController::new(metrics.clone(), 24 * 1024 * 1024, 48 * 1024 * 1024);
        let medium = MemoryController::new(metrics.clone(), 128 * 1024 * 1024, 256 * 1024 * 1024);
        let large = MemoryController::new(metrics, 8 * 1024 * 1024 * 1024, 9 * 1024 * 1024 * 1024);

        assert_eq!(small.reapi_materialization_pool_bytes(), 12 * 1024 * 1024);
        assert_eq!(medium.reapi_materialization_pool_bytes(), 64 * 1024 * 1024);
        assert_eq!(large.reapi_materialization_pool_bytes(), 128 * 1024 * 1024);
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
        assert!(
            controller
                .try_acquire_mmap_serving(65 * 1024 * 1024)
                .is_none()
        );

        drop(permit);
        controller.observe(128 * 1024 * 1024);
        assert!(controller.try_acquire_mmap_serving(1).is_none());
    }

    #[test]
    fn parses_named_control_group_memory_values() {
        let stat = "anon 123\nfile 456\ninactive_file 78\n";

        assert_eq!(named_value(stat, "anon"), Some(123));
        assert_eq!(named_value(stat, "file"), Some(456));
        assert_eq!(named_value(stat, "inactive_file"), Some(78));
        assert_eq!(named_value(stat, "missing"), None);
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
                let reservation = controller
                    .reserve_foreground_staging(2 * 1024 * 1024 * 1024)
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
    async fn queued_foreground_uploads_use_bounded_file_cache() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            64 * 1024 * 1024,
            24 * 1024 * 1024,
            32 * 1024 * 1024,
        );
        let first = controller
            .reserve_foreground_staging(FOREGROUND_STAGING_WINDOW_BYTES)
            .await
            .expect("first reservation should fit");
        assert_eq!(
            first.file_cache_policy(),
            FileCachePolicy::Foreground {
                reservation_bytes: 2 * FOREGROUND_STAGING_WINDOW_BYTES,
            }
        );

        let waiting = tokio::spawn({
            let controller = controller.clone();
            async move { controller.reserve_foreground_staging(1024).await }
        });
        tokio::task::yield_now().await;
        assert!(!waiting.is_finished());
        drop(first);

        let second = waiting
            .await
            .expect("reservation task should not panic")
            .expect("queued reservation should fit after release");
        assert_eq!(second.file_cache_policy(), FileCachePolicy::Bounded);
        drop(second);
        assert_eq!(controller.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn foreground_policy_drops_cache_when_uploads_overlap() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let controller = MemoryController::with_runtime_limit(
            metrics,
            128 * 1024 * 1024,
            64 * 1024 * 1024,
            96 * 1024 * 1024,
        );
        let first = controller
            .reserve_foreground_staging(FOREGROUND_STAGING_WINDOW_BYTES)
            .await
            .expect("first reservation should fit");
        assert!(!first.file_cache_policy().should_drop(
            MemoryPressure::Normal,
            controller.transient_reserved_bytes()
        ));

        let second = controller
            .reserve_foreground_staging(1024)
            .await
            .expect("second reservation should fit");
        assert!(first.file_cache_policy().should_drop(
            MemoryPressure::Normal,
            controller.transient_reserved_bytes()
        ));

        drop(second);
        drop(first);
    }

    #[tokio::test]
    async fn streaming_reservation_starts_exact_and_expands_before_the_next_message() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let mebibyte = 1024 * 1024;
        let controller = MemoryController::with_runtime_limit(
            metrics,
            256 * mebibyte,
            180 * mebibyte,
            200 * mebibyte,
        );
        controller.observe(32 * mebibyte);

        let mut reservation = controller
            .try_reserve_foreground_stream_decode(mebibyte)
            .expect("the exact first wire and decoded buffers should fit");

        assert_eq!(controller.transient_reserved_bytes(), 2 * mebibyte);
        assert_eq!(
            reservation.file_cache_policy(),
            FileCachePolicy::Foreground {
                reservation_bytes: 2 * mebibyte
            }
        );
        reservation
            .try_configure_for_streaming_staging(64 * mebibyte)
            .expect("the staging working set should fit");
        assert_eq!(controller.transient_reserved_bytes(), 34 * mebibyte);
        reservation
            .try_grow_stream_decode(64 * mebibyte)
            .expect("a later maximum-sized message should fit before decoding");
        assert_eq!(controller.transient_reserved_bytes(), 160 * mebibyte);
        assert_eq!(reservation.file_cache_policy(), FileCachePolicy::Bounded);
        assert!(
            controller
                .try_reserve_foreground_stream_decode(64 * mebibyte)
                .is_err(),
            "a second decoder must be rejected before it can allocate"
        );
    }
}
