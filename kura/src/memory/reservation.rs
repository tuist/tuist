use std::{
    sync::{Arc, atomic::Ordering},
    time::Duration,
};

use tokio::sync::OwnedSemaphorePermit;

use crate::metrics::Metrics;

use super::{MemoryController, MemoryControllerInner};

pub(super) const FOREGROUND_ADMISSION_TIMEOUT: std::time::Duration =
    std::time::Duration::from_secs(30);
pub(super) const RESPONSE_STREAM_ADMISSION_TIMEOUT: Duration = Duration::from_secs(5);
/// How long a caller that can degrade will wait for a full-size reservation.
///
/// Short on purpose. When failing admission meant returning `503` it was worth
/// waiting a long time to avoid that, but a degradable caller's fallback is a
/// served response, so a long wait only delays bytes it could already be
/// sending. This is long enough to ride out the microsecond-to-millisecond
/// contention of a slot being released by a finishing stream, and short enough
/// not to show up in the tail.
pub(super) const DEGRADABLE_RESPONSE_STREAM_ADMISSION_TIMEOUT: Duration =
    Duration::from_millis(250);
pub(super) const DEGRADED_RESPONSE_STREAM_SLOT_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum AdmissionClass {
    Foreground,
    Background,
}

pub struct MemoryPermit {
    pub(super) _transient: TransientMemoryReservation,
}

impl MemoryPermit {
    pub(crate) fn shrink_to(&mut self, retained_bytes: usize) -> Result<(), ()> {
        let retained_bytes = u64::try_from(retained_bytes).map_err(|_| ())?;
        if retained_bytes > self._transient.bytes {
            return Err(());
        }
        self._transient.try_resize_foreground(retained_bytes)
    }
}

pub struct MmapMemoryPermit {
    pub(super) _concurrency: OwnedSemaphorePermit,
    pub(super) _transient: TransientMemoryReservation,
}

pub struct ResponseStreamMemoryPermit {
    pub(super) concurrency: Option<OwnedSemaphorePermit>,
    pub(super) foreground_concurrency: Option<OwnedSemaphorePermit>,
    pub(super) background_concurrency: Option<OwnedSemaphorePermit>,
    pub(super) transient: Option<TransientMemoryReservation>,
    pub(super) metrics: Metrics,
    pub(super) protocol: &'static str,
    pub(super) bytes: u64,
}

impl ResponseStreamMemoryPermit {
    #[cfg(test)]
    pub(super) fn holds_degraded_slot(&self) -> bool {
        self.concurrency.is_some()
    }

    pub fn into_transport_guard(self) -> ResponseTransportGuard {
        ResponseTransportGuard {
            _resources: Arc::new(ResponseTransportResources {
                _stream: Some(self),
                _materialized: Vec::new(),
            }),
        }
    }
}

impl Drop for ResponseStreamMemoryPermit {
    fn drop(&mut self) {
        let controller = self
            .transient
            .as_ref()
            .map(|transient| transient.controller.clone());
        self.metrics
            .remove_response_stream_reservation(self.protocol, self.bytes);
        drop(self.concurrency.take());
        drop(self.foreground_concurrency.take());
        drop(self.background_concurrency.take());
        drop(self.transient.take());
        if let Some(controller) = controller {
            controller.inner.pressure_changed.notify_waiters();
        }
    }
}

#[derive(Clone)]
pub struct ResponseTransportGuard {
    _resources: Arc<ResponseTransportResources>,
}

struct ResponseTransportResources {
    _stream: Option<ResponseStreamMemoryPermit>,
    _materialized: Vec<MemoryPermit>,
}

impl ResponseTransportGuard {
    pub fn from_materialization_permits(permits: Vec<MemoryPermit>) -> Self {
        Self {
            _resources: Arc::new(ResponseTransportResources {
                _stream: None,
                _materialized: permits,
            }),
        }
    }
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ResponseStreamAdmissionError {
    QueueFull,
    Timeout,
}

/// How long admission should wait, decided by what the caller does when it
/// fails. The two response transports differ: an HTTP artifact read degrades to
/// a smaller reservation and still serves the object, while a ByteStream read
/// surfaces `RESOURCE_EXHAUSTED`. Waiting is worth much more to the caller whose
/// alternative is an error, so the patience is the caller's to choose rather
/// than a single constant shared by both.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ResponseStreamAdmissionPatience {
    /// The caller degrades on failure and still serves the response.
    Degradable,
    /// The caller returns a retryable error on failure.
    Blocking,
}

impl ResponseStreamAdmissionPatience {
    pub(super) fn timeout(self) -> Duration {
        match self {
            Self::Degradable => DEGRADABLE_RESPONSE_STREAM_ADMISSION_TIMEOUT,
            Self::Blocking => RESPONSE_STREAM_ADMISSION_TIMEOUT,
        }
    }
}

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

pub(super) struct ResponseStreamWaiter {
    inner: Arc<MemoryControllerInner>,
    protocol: &'static str,
    _queue: OwnedSemaphorePermit,
}

impl ResponseStreamWaiter {
    pub(super) fn new(
        inner: Arc<MemoryControllerInner>,
        protocol: &'static str,
        queue: OwnedSemaphorePermit,
    ) -> Self {
        inner.response_stream_waiters.fetch_add(1, Ordering::AcqRel);
        inner.metrics.add_response_stream_waiter(protocol);
        Self {
            inner,
            protocol,
            _queue: queue,
        }
    }
}

impl Drop for ResponseStreamWaiter {
    fn drop(&mut self) {
        self.inner
            .response_stream_waiters
            .fetch_sub(1, Ordering::AcqRel);
        self.inner
            .metrics
            .remove_response_stream_waiter(self.protocol);
    }
}

impl ForegroundWaiter {
    pub(super) fn new(inner: Arc<MemoryControllerInner>) -> Self {
        let waiters = inner.foreground_waiters.fetch_add(1, Ordering::AcqRel) + 1;
        inner.metrics.update_foreground_memory_waiters(waiters);
        Self { inner }
    }
}

impl Drop for ForegroundWaiter {
    fn drop(&mut self) {
        let waiters = self.inner.foreground_waiters.fetch_sub(1, Ordering::AcqRel) - 1;
        self.inner.metrics.update_foreground_memory_waiters(waiters);
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
