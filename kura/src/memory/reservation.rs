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
    pub(super) _transient: TransientMemoryReservation,
}

pub struct TransientMemoryReservation {
    pub(super) controller: MemoryController,
    pub(super) permit: Option<OwnedSemaphorePermit>,
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

impl TransientMemoryReservation {
    fn try_resize_foreground(&mut self, requested_bytes: u64) -> Result<(), ()> {
        if requested_bytes > self.bytes {
            if !self
                .controller
                .allow_transient_admission(AdmissionClass::Foreground)
            {
                return Err(());
            }
            let additional_bytes = requested_bytes - self.bytes;
            let additional_permits = u32::try_from(additional_bytes).map_err(|_| ())?;
            let additional = self
                .controller
                .inner
                .pools
                .try_acquire_transient(additional_permits)?;
            match self.permit.as_mut() {
                Some(permit) => permit.merge(additional),
                None => self.permit = Some(additional),
            }
        } else if requested_bytes < self.bytes {
            let released_bytes = usize::try_from(self.bytes - requested_bytes).map_err(|_| ())?;
            let released = self
                .permit
                .as_mut()
                .and_then(|permit| permit.split(released_bytes))
                .ok_or(())?;
            drop(released);
            if requested_bytes == 0 {
                self.permit = None;
            }
        }
        self.bytes = requested_bytes;
        Ok(())
    }
}
