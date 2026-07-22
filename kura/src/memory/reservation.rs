use std::sync::{Arc, atomic::Ordering};

use tokio::sync::OwnedSemaphorePermit;

use super::{MemoryController, MemoryControllerInner};

pub(super) const FOREGROUND_ADMISSION_TIMEOUT: std::time::Duration =
    std::time::Duration::from_secs(30);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum AdmissionClass {
    Foreground,
    Background,
}

pub struct MemoryPermit {
    pub(super) _concurrency: OwnedSemaphorePermit,
    pub(super) _transient: TransientMemoryReservation,
}

pub struct TransientMemoryReservation {
    pub(super) controller: MemoryController,
    pub(super) bytes: u64,
}

pub struct ForegroundMemoryReservation {
    transient: TransientMemoryReservation,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ForegroundAdmissionTimeout;

impl ForegroundMemoryReservation {
    pub(super) fn new(transient: TransientMemoryReservation) -> Self {
        Self { transient }
    }

    pub(crate) fn try_resize(&mut self, requested_bytes: u64) -> Result<(), ()> {
        self.transient.try_resize_foreground(requested_bytes)
    }

    pub(crate) fn has_waiters(&self) -> bool {
        self.transient
            .controller
            .inner
            .foreground_waiters
            .load(Ordering::Acquire)
            > 0
    }

    pub(crate) fn observe_container_memory(&self) {
        #[cfg(not(test))]
        if let Some(current_bytes) = super::container_memory_current_bytes() {
            self.transient.controller.observe(current_bytes);
        }
    }
}

pub(super) struct ForegroundWaiter {
    inner: Arc<MemoryControllerInner>,
}

impl ForegroundWaiter {
    pub(super) fn new(inner: Arc<MemoryControllerInner>) -> Self {
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
