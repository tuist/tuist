use std::{
    borrow::Cow,
    error::Error,
    pin::Pin,
    task::{Context, Poll},
    time::Instant,
};

use bytes::Bytes;
use futures_util::future::BoxFuture;
use http_body_util::{BodyExt, combinators::UnsyncBoxBody};
use tonic::{
    Status,
    codegen::{Body as HttpBody, Service, http},
};
use tower::Layer;

use super::{protobuf_shape::*, service::REAPI_MAX_DECODING_MESSAGE_SIZE};
use crate::{
    file_cache::{
        FOREGROUND_STAGING_WINDOW_BYTES, FileCachePolicy, ForegroundFileCacheReservation,
    },
    memory::{MemoryController, MemoryPressure},
    state::SharedState,
};

type BoxError = Box<dyn Error + Send + Sync + 'static>;
type GrpcAccountingBody = UnsyncBoxBody<Bytes, BoxError>;

pub(super) const BYTESTREAM_WRITE_PATH: &str = "/google.bytestream.ByteStream/Write";
pub(super) const BYTESTREAM_READ_PATH: &str = "/google.bytestream.ByteStream/Read";
pub(super) const ACTION_CACHE_UPDATE_PATH: &str =
    "/build.bazel.remote.execution.v2.ActionCache/UpdateActionResult";
pub(super) const CAS_BATCH_UPDATE_PATH: &str =
    "/build.bazel.remote.execution.v2.ContentAddressableStorage/BatchUpdateBlobs";
#[derive(Clone)]
pub(super) struct GrpcWriteAdmission {
    reservation: std::sync::Arc<std::sync::Mutex<GrpcWriteReservation>>,
    metrics: crate::metrics::Metrics,
}

struct GrpcWriteReservation {
    file_cache: ForegroundFileCacheReservation,
    stream_message_high_water_bytes: u64,
    decode_structural_high_water_bytes: u64,
    stream_staging_bytes: u64,
    decode_copy_multiplier: u64,
    /// The node's whole transient budget, captured once so the staging window
    /// can be bounded by it. A window wider than the budget it is admitted
    /// against can never be granted, however idle the node is.
    transient_capacity_bytes: u64,
}

impl GrpcWriteReservation {
    fn new(memory: &MemoryController, decode_copy_multiplier: u64) -> Result<Self, ()> {
        let reservation = memory.try_reserve_foreground_memory(0)?;
        Ok(Self {
            file_cache: ForegroundFileCacheReservation::new(
                reservation,
                FileCachePolicy::Foreground {
                    reservation_bytes: 0,
                },
            ),
            stream_message_high_water_bytes: 0,
            decode_structural_high_water_bytes: 0,
            stream_staging_bytes: 0,
            decode_copy_multiplier: decode_copy_multiplier.max(1),
            transient_capacity_bytes: memory.transient_capacity_bytes(),
        })
    }

    fn try_grow_decode(
        &mut self,
        encoded_message_bytes: u64,
        decoded_structural_bytes: u64,
    ) -> Result<(), ()> {
        let high_water_bytes = self
            .stream_message_high_water_bytes
            .max(encoded_message_bytes);
        let structural_high_water_bytes = self
            .decode_structural_high_water_bytes
            .max(decoded_structural_bytes);
        let requested_bytes = high_water_bytes
            .saturating_mul(self.decode_copy_multiplier)
            .saturating_add(structural_high_water_bytes)
            .saturating_add(self.stream_staging_bytes);
        self.file_cache.try_resize(requested_bytes)?;
        self.stream_message_high_water_bytes = high_water_bytes;
        self.decode_structural_high_water_bytes = structural_high_water_bytes;
        if let FileCachePolicy::Foreground { .. } = self.file_cache.file_cache_policy() {
            self.file_cache.set_policy(FileCachePolicy::Foreground {
                reservation_bytes: requested_bytes,
            });
        }
        Ok(())
    }

    fn try_configure_staging(&mut self, declared_or_max_bytes: u64) -> Result<FileCachePolicy, ()> {
        // Staging charges source plus destination -- the incoming bytes and the
        // segment range they are copied into are both resident while the copy
        // runs -- so the window costs twice itself. Bound the window by half the
        // transient budget before doubling, the way `reserve_foreground_staging`
        // does on the non-gRPC path: an unbounded window asks for a flat 32 MiB
        // on every write of a full window or more, which a node whose whole
        // budget is smaller than that can never grant, at any concurrency. That
        // turns a small instance into one that refuses large blobs outright
        // rather than staging them in narrower passes.
        // The decode buffers are already reserved by the time the handler
        // configures staging -- the codec grows them as it starts each message,
        // and the first chunk carries the resource name this is derived from --
        // so the window is bounded by what is left of the budget, not by the
        // whole of it. Halving what remains keeps source plus destination
        // inside it.
        let decode_bytes = self
            .stream_message_high_water_bytes
            .saturating_mul(self.decode_copy_multiplier)
            .saturating_add(self.decode_structural_high_water_bytes);
        let staging_budget_bytes = self.transient_capacity_bytes.saturating_sub(decode_bytes);
        let desired_window_bytes = declared_or_max_bytes.min(FOREGROUND_STAGING_WINDOW_BYTES);
        let window_bytes = desired_window_bytes.min(staging_budget_bytes.saturating_div(2));
        let window_was_clamped = window_bytes < desired_window_bytes;
        let staging_bytes = window_bytes.saturating_mul(2);
        let requested_bytes = decode_bytes.saturating_add(staging_bytes);
        self.file_cache.try_resize(requested_bytes)?;
        self.stream_staging_bytes = staging_bytes;
        // A clamped window holds less than the upload will move, so completed
        // ranges have to be released as it goes rather than at the end.
        let policy =
            if window_was_clamped || declared_or_max_bytes > FOREGROUND_STAGING_WINDOW_BYTES {
                FileCachePolicy::Bounded
            } else {
                FileCachePolicy::Foreground {
                    reservation_bytes: requested_bytes,
                }
            };
        self.file_cache.set_policy(policy);
        Ok(policy)
    }
}

impl GrpcWriteAdmission {
    pub(super) fn new(
        memory: &MemoryController,
        decode_copy_multiplier: u64,
        metrics: crate::metrics::Metrics,
    ) -> Result<Self, ()> {
        Ok(Self {
            reservation: std::sync::Arc::new(std::sync::Mutex::new(GrpcWriteReservation::new(
                memory,
                decode_copy_multiplier,
            )?)),
            metrics,
        })
    }

    fn try_grow_decode(
        &self,
        encoded_message_bytes: u64,
        decoded_structural_bytes: u64,
    ) -> Result<(), Status> {
        let mut reservation = self
            .reservation
            .lock()
            .map_err(|_| Status::internal("gRPC write memory admission lock was poisoned"))?;
        reservation
            .try_grow_decode(encoded_message_bytes, decoded_structural_bytes)
            .map_err(|_| {
                self.metrics
                    .record_memory_action("grpc_write_decode_admission_rejected");
                self.metrics
                    .record_capacity_shed(crate::metrics::shed_kind::REAPI_WRITE_DECODE);
                Status::resource_exhausted(
                    "server is limiting concurrent remote-execution write decoding; retry the write",
                )
            })
    }

    pub(super) fn try_configure_staging(
        &self,
        declared_or_max_bytes: u64,
    ) -> Result<FileCachePolicy, Status> {
        let mut reservation = self
            .reservation
            .lock()
            .map_err(|_| Status::internal("gRPC write memory admission lock was poisoned"))?;
        reservation
            .try_configure_staging(declared_or_max_bytes)
            .map_err(|_| {
                self.metrics
                    .record_memory_action("bytestream_staging_admission_rejected");
                self.metrics
                    .record_capacity_shed(crate::metrics::shed_kind::REAPI_WRITE_DECODE);
                Status::resource_exhausted(
                    "server is limiting concurrent ByteStream staging; retry the write",
                )
            })
    }
}

pub(super) struct GrpcWriteAdmissionBody {
    inner: axum::body::Body,
    admission: GrpcWriteAdmission,
    policy: GrpcWriteShapePolicy,
    header: [u8; GRPC_MESSAGE_HEADER_BYTES],
    header_bytes: usize,
    payload_bytes_remaining: usize,
    validation_message_bytes: usize,
    validation_payload: Option<Vec<u8>>,
    messages_seen: usize,
    failed: bool,
}

impl GrpcWriteAdmissionBody {
    pub(super) fn new(
        inner: axum::body::Body,
        admission: GrpcWriteAdmission,
        policy: GrpcWriteShapePolicy,
    ) -> Self {
        Self {
            inner,
            admission,
            policy,
            header: [0; GRPC_MESSAGE_HEADER_BYTES],
            header_bytes: 0,
            payload_bytes_remaining: 0,
            validation_message_bytes: 0,
            validation_payload: None,
            messages_seen: 0,
            failed: false,
        }
    }

    fn start_message(&mut self, encoded_message_bytes: usize) -> Result<(), Status> {
        if self.policy.is_unary() && self.messages_seen > 0 {
            return Err(Status::invalid_argument(
                "unary remote-execution write contains more than one message",
            ));
        }
        self.admission
            .try_grow_decode(encoded_message_bytes as u64, 0)?;
        self.messages_seen += 1;
        self.validation_message_bytes = encoded_message_bytes;
        self.payload_bytes_remaining = encoded_message_bytes;
        if self.policy.is_unary() {
            let mut payload = Vec::new();
            payload
                .try_reserve_exact(encoded_message_bytes)
                .map_err(|_| {
                    Status::resource_exhausted(
                        "server could not reserve memory to validate the remote-execution write",
                    )
                })?;
            self.validation_payload = Some(payload);
        }
        if encoded_message_bytes == 0 {
            self.finish_message()?;
        }
        Ok(())
    }

    fn finish_message(&mut self) -> Result<(), Status> {
        let Some(payload) = self.validation_payload.take() else {
            return Ok(());
        };
        let shape = match self.policy {
            GrpcWriteShapePolicy::ByteStream => DecodeShape::default(),
            GrpcWriteShapePolicy::BatchUpdate => inspect_batch_update_wire(&payload)?,
            GrpcWriteShapePolicy::ActionUpdate => inspect_action_update_wire(&payload)?,
        };
        self.admission
            .try_grow_decode(self.validation_message_bytes as u64, shape.structural_bytes)?;
        Ok(())
    }

    fn inspect_data(&mut self, data: &Bytes) -> Result<(), Status> {
        let mut offset = 0;
        while offset < data.len() {
            if self.payload_bytes_remaining > 0 {
                let consumed = self.payload_bytes_remaining.min(data.len() - offset);
                if let Some(payload) = &mut self.validation_payload {
                    payload.extend_from_slice(&data[offset..offset + consumed]);
                }
                self.payload_bytes_remaining -= consumed;
                offset += consumed;
                if self.payload_bytes_remaining == 0 {
                    self.finish_message()?;
                }
                continue;
            }

            let copied = (GRPC_MESSAGE_HEADER_BYTES - self.header_bytes).min(data.len() - offset);
            self.header[self.header_bytes..self.header_bytes + copied]
                .copy_from_slice(&data[offset..offset + copied]);
            self.header_bytes += copied;
            offset += copied;
            if self.header_bytes < GRPC_MESSAGE_HEADER_BYTES {
                continue;
            }

            if self.header[0] != 0 {
                return Err(Status::unimplemented(
                    "compressed remote-execution writes are not supported",
                ));
            }
            let encoded_message_bytes = u32::from_be_bytes([
                self.header[1],
                self.header[2],
                self.header[3],
                self.header[4],
            ]) as usize;
            if encoded_message_bytes > REAPI_MAX_DECODING_MESSAGE_SIZE {
                return Err(Status::out_of_range(format!(
                    "decoded message length {encoded_message_bytes} exceeds the {REAPI_MAX_DECODING_MESSAGE_SIZE}-byte limit"
                )));
            }
            self.header_bytes = 0;
            self.start_message(encoded_message_bytes)?;
        }
        Ok(())
    }
}

impl HttpBody for GrpcWriteAdmissionBody {
    type Data = Bytes;
    type Error = Status;

    fn poll_frame(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Option<Result<http_body::Frame<Self::Data>, Self::Error>>> {
        let this = self.get_mut();
        if this.failed {
            return Poll::Ready(None);
        }
        match Pin::new(&mut this.inner).poll_frame(cx) {
            Poll::Ready(Some(Ok(frame))) => {
                if let Some(data) = frame.data_ref()
                    && let Err(status) = this.inspect_data(data)
                {
                    this.failed = true;
                    return Poll::Ready(Some(Err(status)));
                }
                Poll::Ready(Some(Ok(frame)))
            }
            Poll::Ready(Some(Err(error))) => Poll::Ready(Some(Err(Status::internal(format!(
                "failed to read remote-execution request body: {error}"
            ))))),
            Poll::Ready(None) => Poll::Ready(None),
            Poll::Pending => Poll::Pending,
        }
    }

    fn is_end_stream(&self) -> bool {
        self.inner.is_end_stream()
    }

    fn size_hint(&self) -> http_body::SizeHint {
        self.inner.size_hint()
    }
}

pub(super) async fn reject_overloaded_grpc_writes(
    axum::extract::State(state): axum::extract::State<SharedState>,
    request: axum::extract::Request,
    next: axum::middleware::Next,
) -> axum::response::Response {
    if !is_reapi_write_path(request.uri().path()) {
        return next.run(request).await;
    }
    if state.memory.pressure() == MemoryPressure::Critical {
        state
            .metrics
            .record_memory_action("grpc_write_rejected_critical");
        return grpc_status_response(Status::resource_exhausted(
            "server is shedding writes due to memory pressure; retry the write",
        ));
    }
    if state.store.outbox_depth() >= state.config.outbox_max_depth {
        state
            .metrics
            .record_memory_action("grpc_write_rejected_outbox");
        return grpc_status_response(Status::resource_exhausted(
            "server is shedding writes while replication catches up; retry the write",
        ));
    }
    next.run(request).await
}

pub(super) fn is_reapi_write_path(path: &str) -> bool {
    matches!(
        path,
        BYTESTREAM_WRITE_PATH | ACTION_CACHE_UPDATE_PATH | CAS_BATCH_UPDATE_PATH
    )
}

pub(super) async fn admit_grpc_write_decode(
    axum::extract::State(state): axum::extract::State<SharedState>,
    mut request: axum::extract::Request,
    next: axum::middleware::Next,
) -> axum::response::Response {
    let Some(policy) = grpc_write_shape_policy(request.uri().path()) else {
        return next.run(request).await;
    };

    let admission = match GrpcWriteAdmission::new(
        &state.memory,
        policy.decode_copy_multiplier(),
        state.metrics.clone(),
    ) {
        Ok(admission) => admission,
        Err(()) => {
            return grpc_status_response(Status::resource_exhausted(
                "server is limiting concurrent remote-execution write decoding; retry the write",
            ));
        }
    };
    request.extensions_mut().insert(admission.clone());
    let body = std::mem::take(request.body_mut());
    *request.body_mut() =
        axum::body::Body::new(GrpcWriteAdmissionBody::new(body, admission, policy));
    next.run(request).await
}

pub(super) fn grpc_write_shape_policy(path: &str) -> Option<GrpcWriteShapePolicy> {
    match path {
        BYTESTREAM_WRITE_PATH => Some(GrpcWriteShapePolicy::ByteStream),
        CAS_BATCH_UPDATE_PATH => Some(GrpcWriteShapePolicy::BatchUpdate),
        ACTION_CACHE_UPDATE_PATH => Some(GrpcWriteShapePolicy::ActionUpdate),
        _ => None,
    }
}

fn grpc_status_response(status: Status) -> axum::response::Response {
    status.into_http::<axum::body::Body>()
}

#[derive(Clone)]
pub(super) struct GrpcRequestAccountingLayer {
    pub(super) state: SharedState,
}

impl<S> Layer<S> for GrpcRequestAccountingLayer {
    type Service = GrpcRequestAccountingService<S>;

    fn layer(&self, inner: S) -> Self::Service {
        GrpcRequestAccountingService {
            inner,
            state: self.state.clone(),
        }
    }
}

#[derive(Clone)]
pub(super) struct GrpcRequestAccountingService<S> {
    inner: S,
    state: SharedState,
}

// Generic over the request body so the same accounting wraps both the dedicated
// gRPC transport (`TonicBody`) and the co-hosted listener's axum router
// (`axum::body::Body`).
impl<S, ReqBody, ResBody> Service<http::Request<ReqBody>> for GrpcRequestAccountingService<S>
where
    S: Service<http::Request<ReqBody>, Response = http::Response<ResBody>> + Send + 'static,
    S::Future: Send + 'static,
    S::Error: Send + 'static,
    ResBody: HttpBody<Data = Bytes> + Send + 'static,
    ResBody::Error: Into<BoxError> + 'static,
{
    type Response = http::Response<GrpcAccountingBody>;
    type Error = S::Error;
    type Future = BoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: http::Request<ReqBody>) -> Self::Future {
        let started_at = Instant::now();
        let route = match request.uri().path() {
            BYTESTREAM_READ_PATH => Cow::Borrowed(BYTESTREAM_READ_PATH),
            path => Cow::Owned(path.to_owned()),
        };
        let guard = self.state.start_grpc_request();
        let state = self.state.clone();
        let future = self.inner.call(request);
        Box::pin(async move {
            let response = future.await?;
            // Sample latency once the response is ready, before the body
            // streams, so long ByteStream reads do not inflate the signal.
            state.runtime.record_public_request_latency(
                &state.metrics,
                "grpc",
                &route,
                started_at.elapsed(),
            );
            Ok(response.map(|body| {
                body.map_frame(move |frame| {
                    let _guard = &guard;
                    frame
                })
                .map_err(|error| -> BoxError { error.into() })
                .boxed_unsync()
            }))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The remote-execution shed has to reach `kura_capacity_sheds_total`, the
    // counter operators are told to reach for before the per-subsystem ones.
    // It answers RESOURCE_EXHAUSTED rather than an HTTP status, so nothing else
    // in the shed taxonomy would show a node turning writes away.
    #[test]
    fn a_shed_write_is_counted_as_a_capacity_shed() {
        let metrics = crate::metrics::Metrics::new("eu-west".into(), "tenant".into());
        let mebibyte = 1024 * 1024;
        let memory = MemoryController::with_runtime_limit(
            metrics.clone(),
            256 * mebibyte,
            64 * mebibyte,
            96 * mebibyte,
        );
        memory.observe(mebibyte);

        let admission = GrpcWriteAdmission::new(&memory, 2, metrics.clone())
            .expect("the initial reservation should fit");
        // Far past the whole transient budget, so admission must refuse it.
        admission
            .try_grow_decode(memory.transient_capacity_bytes() * 2, 0)
            .expect_err("a message larger than the budget must be shed");

        let rendered = metrics.render();
        assert!(
            rendered
                .lines()
                .any(|line| line.starts_with("kura_capacity_sheds_total")
                    && line.contains("reapi_write_decode")
                    && !line.ends_with(" 0")),
            "the write shed did not reach kura_capacity_sheds_total"
        );
    }

    // A node whose whole transient budget is smaller than two full staging
    // windows must still accept a large blob. Before the window was bounded by
    // the budget, a write of one window or more asked for a flat 32 MiB and a
    // 32 MiB node refused every one of them at concurrency one -- not under
    // load, but always.
    #[test]
    fn a_large_write_fits_a_budget_smaller_than_two_staging_windows() {
        let metrics = crate::metrics::Metrics::new("eu-west".into(), "tenant".into());
        let mebibyte = 1024 * 1024;
        // Watermarks chosen so the transient budget lands at 32 MiB, the pool a
        // 176 MiB memory floor fits to.
        let memory = MemoryController::with_runtime_limit(
            metrics.clone(),
            256 * mebibyte,
            64 * mebibyte,
            96 * mebibyte,
        );
        memory.observe(mebibyte);
        assert_eq!(memory.transient_capacity_bytes(), 32 * mebibyte);

        let admission = GrpcWriteAdmission::new(&memory, 2, metrics.clone())
            .expect("the initial reservation should fit");
        // The codec reserves the first chunk's decode buffers before the
        // handler reaches staging, so staging sees a budget already spent into.
        admission
            .try_grow_decode(256 * 1024, 0)
            .expect("the first chunk's decode buffers should fit");
        let policy = admission
            .try_configure_staging(FOREGROUND_STAGING_WINDOW_BYTES)
            .expect("a full-window write must be admitted on a 32 MiB budget");
        // Bounded, not Foreground: the window is narrower than the upload, so
        // completed ranges are released as it goes.
        assert_eq!(policy, FileCachePolicy::Bounded);
        assert!(
            memory.transient_reserved_bytes() <= memory.transient_capacity_bytes(),
            "staging reserved {} of a {} budget",
            memory.transient_reserved_bytes(),
            memory.transient_capacity_bytes()
        );
    }

    // The clamp must not shrink a window the budget can afford, or every node
    // large enough to stage at full width would start dropping page cache it
    // had room to keep.
    #[test]
    fn a_budget_with_room_keeps_the_full_staging_window() {
        let metrics = crate::metrics::Metrics::new("eu-west".into(), "tenant".into());
        let mebibyte = 1024 * 1024;
        let memory = MemoryController::with_runtime_limit(
            metrics.clone(),
            1024 * mebibyte,
            256 * mebibyte,
            512 * mebibyte,
        );
        memory.observe(mebibyte);
        assert!(memory.transient_capacity_bytes() >= 2 * FOREGROUND_STAGING_WINDOW_BYTES);

        let admission = GrpcWriteAdmission::new(&memory, 2, metrics.clone())
            .expect("the initial reservation should fit");
        admission
            .try_configure_staging(FOREGROUND_STAGING_WINDOW_BYTES)
            .expect("a full-window write fits a budget with room");
        assert_eq!(
            memory.transient_reserved_bytes(),
            2 * FOREGROUND_STAGING_WINDOW_BYTES,
            "an unclamped window still charges source plus destination"
        );
    }

    #[test]
    fn streaming_reservation_expands_before_the_next_message() {
        let metrics = crate::metrics::Metrics::new("eu-west".into(), "tenant".into());
        let mebibyte = 1024 * 1024;
        let memory = MemoryController::with_runtime_limit(
            metrics.clone(),
            256 * mebibyte,
            32 * mebibyte,
            200 * mebibyte,
        );
        memory.observe(32 * mebibyte);

        let admission = GrpcWriteAdmission::new(&memory, 2, metrics.clone())
            .expect("the initial reservation should fit");
        admission
            .try_grow_decode(mebibyte, 0)
            .expect("the exact first wire and decoded buffers should fit");
        assert_eq!(memory.transient_reserved_bytes(), 2 * mebibyte);
        assert_eq!(
            admission
                .reservation
                .lock()
                .expect("reservation lock")
                .file_cache
                .file_cache_policy(),
            FileCachePolicy::Foreground {
                reservation_bytes: 2 * mebibyte,
            }
        );

        admission
            .try_configure_staging(64 * mebibyte)
            .expect("the staging working set should fit");
        assert_eq!(memory.transient_reserved_bytes(), 34 * mebibyte);
        admission
            .try_grow_decode(64 * mebibyte, 0)
            .expect("a later maximum-sized message should fit before decoding");
        assert_eq!(memory.transient_reserved_bytes(), 160 * mebibyte);
        assert_eq!(
            admission
                .reservation
                .lock()
                .expect("reservation lock")
                .file_cache
                .file_cache_policy(),
            FileCachePolicy::Bounded
        );

        let second =
            GrpcWriteAdmission::new(&memory, 2, metrics).expect("zero-byte admission should fit");
        assert!(
            second.try_grow_decode(64 * mebibyte, 0).is_err(),
            "a second decoder must be rejected before it can allocate"
        );
    }
}
