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
pub(super) const DEGRADED_RESPONSE_STREAM_SLOT_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum AdmissionClass {
    Foreground,
    Background,
}

pub struct MemoryPermit {
    pub(super) _concurrency: OwnedSemaphorePermit,
    pub(super) _transient: TransientMemoryReservation,
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

    pub fn into_transport_guard(mut self) -> ResponseTransportGuard {
        if let Some(transient) = &mut self.transient {
            transient.defer_release_until_observation = cfg!(target_os = "linux");
        }
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
    pub fn from_materialization_permits(mut permits: Vec<MemoryPermit>) -> Self {
        for permit in &mut permits {
            permit._transient.defer_release_until_observation = cfg!(target_os = "linux");
        }
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
    pub(super) bytes: u64,
    pub(super) defer_release_until_observation: bool,
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

    pub(crate) fn defer_release_until_observation(&mut self) {
        self.transient.defer_release_until_observation = true;
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

impl Drop for TransientMemoryReservation {
    fn drop(&mut self) {
        let deferred = if self.defer_release_until_observation {
            self.controller.defer_transient_release(self.bytes)
        } else {
            0
        };
        let released = self.bytes.saturating_sub(deferred);
        if released == 0 {
            return;
        }
        self.controller
            .inner
            .transient_reserved_bytes
            .fetch_sub(released, Ordering::AcqRel);
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
