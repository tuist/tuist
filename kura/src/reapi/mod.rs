use std::{
    collections::BTreeMap,
    error::Error,
    pin::Pin,
    task::{Context, Poll},
    time::{Duration, Instant},
};

use bazel_remote_apis::{
    build::bazel::{
        remote::execution::v2::{
            self as reapi,
            action_cache_server::{ActionCache, ActionCacheServer},
            capabilities_server::{Capabilities, CapabilitiesServer},
            content_addressable_storage_server::{
                ContentAddressableStorage, ContentAddressableStorageServer,
            },
        },
        semver::SemVer,
    },
    google::{
        bytestream::{
            self,
            byte_stream_server::{ByteStream, ByteStreamServer},
        },
        rpc::Status as RpcStatus,
    },
};
use bytes::Bytes;
use futures_util::{FutureExt, StreamExt, future::BoxFuture};
use http_body_util::{BodyExt, combinators::UnsyncBoxBody};
use prost::Message;
use sha2::{Digest as _, Sha256};
use tokio_util::io::ReaderStream;
use tonic::{
    Request, Response, Status,
    codegen::{Body as HttpBody, Service, http},
};
use tower::Layer;

use crate::{
    artifact::{manifest::ArtifactManifest, producer::ArtifactProducer},
    constants::MAX_MODULE_TOTAL_BYTES,
    extension::{AccessDecision, ExtensionContext, Principal},
    io::is_fd_pool_exhausted_error,
    memory::{
        FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES, FileCachePolicy, ForegroundMemoryReservation,
        MemoryPressure,
    },
    replication::replication_targets,
    state::SharedState,
    store::{StagedArtifactPath, is_outbox_full_error},
    utils::{
        TempFileCleanup, action_cache_key, blob_key, drop_staging_cache_range, temp_file_path,
    },
};

const DEFAULT_INSTANCE_NAME: &str = "default";
const REAPI_READ_STREAM_CHUNK_BYTES: usize = 512 * 1024;
const REAPI_MATERIALIZATION_REJECTED_ACTION: &str = "reapi_materialization_rejected";
const BYTESTREAM_WRITE_PATH: &str = "/google.bytestream.ByteStream/Write";
const ACTION_CACHE_UPDATE_PATH: &str =
    "/build.bazel.remote.execution.v2.ActionCache/UpdateActionResult";
const CAS_BATCH_UPDATE_PATH: &str =
    "/build.bazel.remote.execution.v2.ContentAddressableStorage/BatchUpdateBlobs";
// This duplicates Tonic's five-byte gRPC envelope so memory is admitted before
// Tonic retains and decodes each message. Keep it aligned with Tonic's decoder:
// https://github.com/hyperium/tonic/blob/v0.14.5/tonic/src/codec/decode.rs
const GRPC_MESSAGE_HEADER_BYTES: usize = 5;

// Abort a ByteStream upload only when no chunk arrives within this window. The
// timer resets on every chunk received, so an actively transferring upload is
// never interrupted, while a stalled or vanished client is reclaimed promptly.
const REAPI_WRITE_STALL_TIMEOUT: Duration = Duration::from_secs(60);
type BoxError = Box<dyn Error + Send + Sync + 'static>;
type GrpcAccountingBody = UnsyncBoxBody<Bytes, BoxError>;

#[derive(Clone)]
struct ByteStreamWriteAdmission {
    reservation: std::sync::Arc<std::sync::Mutex<ForegroundMemoryReservation>>,
    metrics: crate::metrics::Metrics,
}

impl ByteStreamWriteAdmission {
    fn new(reservation: ForegroundMemoryReservation, metrics: crate::metrics::Metrics) -> Self {
        Self {
            reservation: std::sync::Arc::new(std::sync::Mutex::new(reservation)),
            metrics,
        }
    }

    fn try_grow_decode(&self, encoded_message_bytes: u64) -> Result<(), Status> {
        let mut reservation = self
            .reservation
            .lock()
            .map_err(|_| Status::internal("ByteStream memory admission lock was poisoned"))?;
        reservation
            .try_grow_stream_decode(encoded_message_bytes)
            .map_err(|_| {
                self.metrics
                    .record_memory_action("bytestream_decode_admission_rejected");
                Status::resource_exhausted(
                    "server is limiting concurrent ByteStream decoding; retry the write",
                )
            })
    }

    fn try_configure_staging(&self, declared_or_max_bytes: u64) -> Result<FileCachePolicy, Status> {
        let mut reservation = self
            .reservation
            .lock()
            .map_err(|_| Status::internal("ByteStream memory admission lock was poisoned"))?;
        reservation
            .try_configure_for_streaming_staging(declared_or_max_bytes)
            .map_err(|_| {
                self.metrics
                    .record_memory_action("bytestream_staging_admission_rejected");
                Status::resource_exhausted(
                    "server is limiting concurrent ByteStream staging; retry the write",
                )
            })
    }
}

struct ByteStreamAdmissionBody {
    inner: axum::body::Body,
    admission: ByteStreamWriteAdmission,
    header: [u8; GRPC_MESSAGE_HEADER_BYTES],
    header_bytes: usize,
    payload_bytes_remaining: usize,
    failed: bool,
}

impl ByteStreamAdmissionBody {
    fn new(inner: axum::body::Body, admission: ByteStreamWriteAdmission) -> Self {
        Self {
            inner,
            admission,
            header: [0; GRPC_MESSAGE_HEADER_BYTES],
            header_bytes: 0,
            payload_bytes_remaining: 0,
            failed: false,
        }
    }

    fn inspect_data(&mut self, data: &Bytes) -> Result<(), Status> {
        let mut offset = 0;
        while offset < data.len() {
            if self.payload_bytes_remaining > 0 {
                let consumed = self.payload_bytes_remaining.min(data.len() - offset);
                self.payload_bytes_remaining -= consumed;
                offset += consumed;
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
                    "compressed ByteStream writes are not supported",
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
            self.admission
                .try_grow_decode(encoded_message_bytes as u64)?;
            self.header_bytes = 0;
            self.payload_bytes_remaining = encoded_message_bytes;
        }
        Ok(())
    }
}

impl HttpBody for ByteStreamAdmissionBody {
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
                "failed to read ByteStream request body: {error}"
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

#[derive(Clone)]
pub struct ReapiService {
    state: SharedState,
    // Per-namespace action-cache snapshot indexes and their in-flight
    // builds, shared across the service clones tonic hands each server.
    snapshot_cache: std::sync::Arc<SnapshotCache>,
}

/// Completed snapshot indexes (bounded by SNAPSHOT_CACHE_MAX_NAMESPACES, LRU
/// by last use) plus the in-flight builds producing them. Builds run as
/// DETACHED tasks shared by every concurrent request for a namespace: the
/// first build of a large namespace can outlive a gateway's upstream timeout,
/// and dropping the work with the aborted request meant every retry rebuilt
/// from scratch and timed out the same way — the snapshot never became
/// servable. A detached build completes and caches regardless of who is
/// still waiting.
pub(crate) struct SnapshotCache {
    indexes: std::sync::Mutex<BTreeMap<String, NamespaceSnapshotIndex>>,
    builds: std::sync::Mutex<std::collections::HashMap<String, SharedIndexBuild>>,
    /// The last FULL (`after == 0`) encoded snapshot per namespace. A reconcile
    /// takes its index out of `indexes` for the build's duration, so a serve
    /// landing during a rebuild would otherwise find nothing and shed a cold
    /// client to UNAVAILABLE. Serving this last full view instead keeps them on
    /// the (slightly stale) snapshot. Bounded at the wire ceiling per entry and
    /// pruned with the index LRU — unlike cloning the whole index, whose
    /// node table the entry cap does not bound.
    served_full: std::sync::Mutex<BTreeMap<String, std::sync::Arc<Vec<u8>>>>,
    build_lock: tokio::sync::Mutex<()>,
    max_bytes: usize,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct SnapshotCacheStats {
    pub(crate) bytes: usize,
    pub(crate) namespaces: usize,
    pub(crate) entries: usize,
    pub(crate) nodes: usize,
    pub(crate) served_full_bytes: usize,
}

impl Default for SnapshotCache {
    fn default() -> Self {
        Self::new(256 << 20)
    }
}

impl SnapshotCache {
    pub(crate) fn new(max_bytes: usize) -> Self {
        Self {
            indexes: Default::default(),
            builds: Default::default(),
            served_full: Default::default(),
            build_lock: Default::default(),
            max_bytes: max_bytes.max(1),
        }
    }

    fn index_max_bytes(&self) -> usize {
        self.max_bytes
            .saturating_sub((self.max_bytes / 4).min(SNAPSHOT_WIRE_MAX_BYTES))
            .max(1)
    }

    pub(crate) fn stats(&self) -> SnapshotCacheStats {
        let indexes = self.indexes.lock().expect("snapshot cache lock poisoned");
        let served_full = self
            .served_full
            .lock()
            .expect("snapshot served_full lock poisoned");
        Self::stats_locked(&indexes, &served_full)
    }

    fn stats_locked(
        indexes: &BTreeMap<String, NamespaceSnapshotIndex>,
        served_full: &BTreeMap<String, std::sync::Arc<Vec<u8>>>,
    ) -> SnapshotCacheStats {
        let entries = indexes.values().map(|index| index.entries.len()).sum();
        let nodes = indexes.values().map(|index| index.nodes.len()).sum();
        let index_bytes = indexes
            .iter()
            .map(|(namespace, index)| {
                index
                    .estimated_bytes()
                    .saturating_add(estimated_map_item_bytes(namespace.len()))
            })
            .sum::<usize>();
        let served_full_bytes = served_full
            .iter()
            .map(|(namespace, bytes)| {
                bytes
                    .capacity()
                    .saturating_add(estimated_map_item_bytes(namespace.len()))
            })
            .sum();
        SnapshotCacheStats {
            bytes: index_bytes.saturating_add(served_full_bytes),
            namespaces: indexes.len(),
            entries,
            nodes,
            served_full_bytes,
        }
    }

    pub(crate) fn update_metrics(&self, metrics: &crate::metrics::Metrics) {
        let stats = self.stats();
        metrics.update_snapshot_cache(
            stats.bytes,
            self.max_bytes,
            stats.namespaces,
            stats.entries,
            stats.nodes,
            stats.served_full_bytes,
        );
    }

    pub(crate) fn trim_to(
        &self,
        target_bytes: usize,
        reason: &str,
        metrics: &crate::metrics::Metrics,
    ) -> usize {
        let target_bytes = target_bytes.min(self.max_bytes);
        let mut indexes = self.indexes.lock().expect("snapshot cache lock poisoned");
        let mut served_full = self
            .served_full
            .lock()
            .expect("snapshot served_full lock poisoned");
        let mut evicted = 0;
        loop {
            let stats = Self::stats_locked(&indexes, &served_full);
            if stats.bytes <= target_bytes {
                metrics.update_snapshot_cache(
                    stats.bytes,
                    self.max_bytes,
                    stats.namespaces,
                    stats.entries,
                    stats.nodes,
                    stats.served_full_bytes,
                );
                break;
            }
            let oldest = indexes
                .iter()
                .min_by_key(|(_, index)| index.last_used)
                .map(|(namespace, _)| namespace.clone())
                .or_else(|| served_full.keys().next().cloned());
            let Some(oldest) = oldest else { break };
            indexes.remove(&oldest);
            served_full.remove(&oldest);
            evicted += 1;
        }
        if evicted > 0 {
            metrics.record_memory_action("snapshot_cache_trim");
            tracing::warn!(
                evicted,
                reason,
                target_bytes,
                "trimmed action-cache snapshot cache"
            );
        }
        evicted
    }
}

type SharedIndexBuild = futures_util::future::Shared<BoxFuture<'static, Result<(), String>>>;

#[derive(Clone)]
struct GrpcExtensionSpec<'a> {
    route: &'a str,
    operation: &'a str,
    namespace_id: Option<&'a str>,
    producer: Option<&'a str>,
    artifact_key: Option<String>,
    artifact_hash: Option<String>,
}

const REAPI_MAX_DECODING_MESSAGE_SIZE: usize = 64 << 20;

type ReapiServers = (
    CapabilitiesServer<ReapiService>,
    ActionCacheServer<ReapiService>,
    ContentAddressableStorageServer<ReapiService>,
    ByteStreamServer<ReapiService>,
);

// The four REAPI gRPC services with their shared decoding limits.
fn reapi_servers(state: SharedState) -> ReapiServers {
    let service = ReapiService {
        snapshot_cache: state.snapshot_cache.clone(),
        state,
    };
    (
        CapabilitiesServer::new(service.clone())
            .max_decoding_message_size(REAPI_MAX_DECODING_MESSAGE_SIZE),
        ActionCacheServer::new(service.clone())
            .max_decoding_message_size(REAPI_MAX_DECODING_MESSAGE_SIZE),
        ContentAddressableStorageServer::new(service.clone())
            .max_decoding_message_size(REAPI_MAX_DECODING_MESSAGE_SIZE),
        ByteStreamServer::new(service).max_decoding_message_size(REAPI_MAX_DECODING_MESSAGE_SIZE),
    )
}

// Build the REAPI services as an `axum`/`tower` router, mounted into the
// co-hosted HTTP+gRPC listener alongside the cache routes. tonic's `Routes` is
// itself an `axum::Router` that mounts each service at `/{service.name}/{*rest}`;
// those paths never collide with the HTTP cache routes, so the co-hosted router
// dispatches gRPC and HTTP unambiguously by path. It carries the
// [`GrpcRequestAccountingLayer`] so gRPC traffic still shows up in inflight and
// latency metrics and counts toward the shutdown drain. Its `unimplemented`
// fallback (gRPC status 12) becomes the co-hosted router's fallback for
// otherwise-unmatched paths.
pub fn routes(state: SharedState) -> axum::Router {
    let (capabilities, action_cache, cas, byte_stream) = reapi_servers(state.clone());
    tonic::service::Routes::new(capabilities)
        .add_service(action_cache)
        .add_service(cas)
        .add_service(byte_stream)
        .into_axum_router()
        .layer(axum::middleware::from_fn_with_state(
            state.clone(),
            reject_overloaded_grpc_writes,
        ))
        .layer(axum::middleware::from_fn_with_state(
            state.clone(),
            admit_bytestream_write_decode,
        ))
        .layer(GrpcRequestAccountingLayer { state })
}

async fn reject_overloaded_grpc_writes(
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

fn is_reapi_write_path(path: &str) -> bool {
    matches!(
        path,
        BYTESTREAM_WRITE_PATH | ACTION_CACHE_UPDATE_PATH | CAS_BATCH_UPDATE_PATH
    )
}

async fn admit_bytestream_write_decode(
    axum::extract::State(state): axum::extract::State<SharedState>,
    mut request: axum::extract::Request,
    next: axum::middleware::Next,
) -> axum::response::Response {
    if request.uri().path() != BYTESTREAM_WRITE_PATH {
        return next.run(request).await;
    }

    let reservation = match state.memory.try_reserve_foreground_stream_decode(0) {
        Ok(reservation) => reservation,
        Err(()) => {
            return grpc_status_response(Status::resource_exhausted(
                "server is limiting concurrent ByteStream decoding; retry the write",
            ));
        }
    };
    let admission = ByteStreamWriteAdmission::new(reservation, state.metrics.clone());
    request.extensions_mut().insert(admission.clone());
    let body = std::mem::take(request.body_mut());
    *request.body_mut() = axum::body::Body::new(ByteStreamAdmissionBody::new(body, admission));
    next.run(request).await
}

fn grpc_status_response(status: Status) -> axum::response::Response {
    status.into_http::<axum::body::Body>()
}

#[derive(Clone)]
struct GrpcRequestAccountingLayer {
    state: SharedState,
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
struct GrpcRequestAccountingService<S> {
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
        let route = request.uri().path().to_owned();
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

impl ReapiService {
    async fn authorize_request<T>(
        &self,
        request: &Request<T>,
        spec: GrpcExtensionSpec<'_>,
    ) -> Result<Option<Principal>, Status> {
        self.authorize_metadata(request.metadata(), spec).await
    }

    // Authorize from already-extracted metadata. ByteStream Write consumes the
    // request into a stream before it learns its namespace (from the first
    // chunk's resource_name), so it captures the metadata up front and authorizes
    // here once the namespace is known.
    async fn authorize_metadata(
        &self,
        metadata: &tonic::metadata::MetadataMap,
        spec: GrpcExtensionSpec<'_>,
    ) -> Result<Option<Principal>, Status> {
        if self.state.runtime.is_draining() {
            return Err(Status::unavailable("server is draining"));
        }
        let Some(extension) = self.state.extension.as_ref() else {
            return Ok(None);
        };
        let context = grpc_extension_context(&self.state.config.tenant_id, &spec, metadata, None);
        match extension.evaluate_access(&context).await {
            AccessDecision::Allow(principal) => Ok(principal),
            AccessDecision::Deny(deny) => {
                Err(grpc_status_from_http_status(deny.status, &deny.message))
            }
        }
    }

    async fn apply_response_headers<T>(
        &self,
        response: &mut Response<T>,
        spec: GrpcExtensionSpec<'_>,
        principal: Option<&Principal>,
    ) -> Result<(), Status> {
        let Some(extension) = self.state.extension.as_ref() else {
            return Ok(());
        };
        let context = grpc_extension_context(
            &self.state.config.tenant_id,
            &spec,
            response.metadata(),
            Some(200),
        );
        let headers = extension.response_headers(&context, principal).await;
        for (name, value) in headers.headers {
            let metadata_key = tonic::metadata::MetadataKey::from_bytes(name.as_bytes())
                .map_err(|_| Status::internal("invalid extension response header name"))?;
            let metadata_value = tonic::metadata::MetadataValue::try_from(value.as_str())
                .map_err(|_| Status::internal("invalid extension response header value"))?;
            response.metadata_mut().insert(metadata_key, metadata_value);
        }
        Ok(())
    }

    // Record a served gRPC download (egress) against the usage rollups so REAPI
    // bandwidth reaches `kura_usage_events` on parity with the HTTP path. A no-op
    // when usage reporting is disabled. Call only on success arms, mirroring how
    // the HTTP handlers record on the `"ok"` metric arm.
    fn record_reapi_download(
        &self,
        metadata: &tonic::metadata::MetadataMap,
        namespace_id: &str,
        bytes: u64,
    ) {
        let Some(usage) = self.state.usage.as_ref() else {
            return;
        };
        usage.record_public_grpc_download(
            &usage_tenant_id(metadata, &self.state.config.tenant_id),
            namespace_id,
            REAPI_USAGE_ARTIFACT_KIND,
            bytes,
        );
    }

    // Record a received gRPC upload (ingress) against the usage rollups. See
    // [`record_reapi_download`] for the parity and call-site conventions.
    fn record_reapi_upload(
        &self,
        metadata: &tonic::metadata::MetadataMap,
        namespace_id: &str,
        bytes: u64,
    ) {
        let Some(usage) = self.state.usage.as_ref() else {
            return;
        };
        usage.record_public_grpc_upload(
            &usage_tenant_id(metadata, &self.state.config.tenant_id),
            namespace_id,
            REAPI_USAGE_ARTIFACT_KIND,
            bytes,
        );
    }

    // Body of ByteStream::write. Every step here is fallible via `?`; the caller
    // (write) removes temp_path on any error this returns, so this never cleans
    // up inline — which is what keeps transport/cancel/write/flush failures from
    // leaking partial temp files.
    async fn write_to_temp(
        &self,
        temp_path: &std::path::Path,
        request: Request<tonic::Streaming<bytestream::WriteRequest>>,
        cleanup: &mut TempFileCleanup,
    ) -> Result<Response<bytestream::WriteResponse>, Status> {
        // ByteStream Write learns its namespace from the first chunk's
        // resource_name, which is not available until we read the stream. Capture
        // the metadata now and authorize below, once the namespace is known, so
        // project-scoped tokens authorize against the real project (not the
        // account) — matching the namespace the blob is ultimately stored under.
        let metadata = request.metadata().clone();
        let memory_admission = request
            .extensions()
            .get::<ByteStreamWriteAdmission>()
            .cloned()
            .ok_or_else(|| Status::internal("ByteStream decode admission was not propagated"))?;
        let mut temp_file = self
            .state
            .io
            .create_file(temp_path)
            .await
            .map_err(Status::internal)?;
        let mut stream = request.into_inner();
        let mut resource_name = None::<String>;
        let mut resource = None::<BlobResource>;
        let mut principal = None::<Principal>;
        let mut file_cache_policy = FileCachePolicy::Adaptive;
        let mut written = 0_u64;
        let mut advised_through = 0_u64;
        let mut hasher = Sha256::new();
        let mut finished = false;

        // Stall deadline keyed on byte *progress*, not message arrival: it only
        // advances when a chunk delivers data. An upload that keeps making
        // progress is never cut, while a stalled or vanished client — or one
        // trickling zero-data keepalive frames to pin the stream open — is
        // reclaimed once the deadline lapses (write removes the temp file when
        // this returns the error). The window also caps how long a single
        // decoded message may take to arrive; it is sized to clear the largest
        // message the server will decode at any realistic upload rate.
        let mut stall_deadline = tokio::time::Instant::now() + REAPI_WRITE_STALL_TIMEOUT;

        loop {
            let chunk = match tokio::time::timeout_at(stall_deadline, stream.message()).await {
                Ok(result) => match result? {
                    Some(chunk) => chunk,
                    None => break,
                },
                Err(_elapsed) => {
                    return Err(Status::deadline_exceeded(format!(
                        "no upload progress within {}s; aborting stalled write",
                        REAPI_WRITE_STALL_TIMEOUT.as_secs()
                    )));
                }
            };
            let chunk_resource_name = if chunk.resource_name.is_empty() {
                resource_name.clone().ok_or_else(|| {
                    Status::invalid_argument("first write request must include resource_name")
                })?
            } else {
                chunk.resource_name.clone()
            };
            if let Some(existing) = &resource_name {
                if existing != &chunk_resource_name {
                    return Err(Status::invalid_argument("resource_name changed mid-stream"));
                }
            } else {
                let parsed_resource = parse_write_resource_name(&chunk_resource_name)?;
                let write_extension = GrpcExtensionSpec {
                    route: "reapi.bytestream.write",
                    operation: "artifact.write",
                    namespace_id: Some(&parsed_resource.namespace_id),
                    producer: Some("reapi"),
                    artifact_key: None,
                    artifact_hash: None,
                };
                principal = self.authorize_metadata(&metadata, write_extension).await?;
                file_cache_policy =
                    memory_admission.try_configure_staging(parsed_resource.size_bytes)?;
                let disk_reservation = self
                    .state
                    .tmp_staging_budget
                    .try_reserve(parsed_resource.size_bytes)
                    .map_err(|error| {
                        Status::resource_exhausted(format!(
                            "temporary storage budget exhausted: {error}"
                        ))
                    })?;
                cleanup.set_reservation(disk_reservation);
                resource = Some(parsed_resource);
                resource_name = Some(chunk_resource_name);
            }
            if chunk.write_offset < 0 || chunk.write_offset as u64 != written {
                return Err(Status::invalid_argument("unexpected write_offset"));
            }
            let expected_size = resource
                .as_ref()
                .expect("resource is initialized with the first chunk")
                .size_bytes;
            if written.saturating_add(chunk.data.len() as u64) > expected_size {
                return Err(Status::invalid_argument(
                    "write data exceeds the declared blob size",
                ));
            }
            if !chunk.data.is_empty() {
                for data in chunk
                    .data
                    .chunks(FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES as usize)
                {
                    tokio::io::AsyncWriteExt::write_all(&mut temp_file, data)
                        .await
                        .map_err(|error| {
                            Status::internal(format!("failed to write temp blob: {error}"))
                        })?;
                    hasher.update(data);
                    written = written.saturating_add(data.len() as u64);
                    if file_cache_policy.should_drop(
                        self.state.memory.pressure(),
                        self.state.memory.transient_reserved_bytes(),
                    ) && written.saturating_sub(advised_through)
                        >= FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES
                    {
                        temp_file = drop_staging_cache_range(
                            temp_file,
                            temp_path,
                            advised_through,
                            written - advised_through,
                            &self.state.io,
                        )
                        .await
                        .map_err(Status::internal)?;
                        advised_through = written;
                    }
                }
                // Only real byte progress extends the deadline, so a client
                // cannot keep a stalled upload alive with empty frames.
                stall_deadline = tokio::time::Instant::now() + REAPI_WRITE_STALL_TIMEOUT;
            }
            // finish_write marks the last chunk: stop reading immediately instead
            // of waiting (up to the stall window) for the client's half-close,
            // and never block another deadline interval on a completed upload.
            if chunk.finish_write {
                finished = true;
                break;
            }
        }

        let resource = resource.ok_or_else(|| Status::invalid_argument("empty write stream"))?;
        if !finished {
            return Err(Status::invalid_argument("write stream did not finish"));
        }
        if written != resource.size_bytes {
            return Err(Status::invalid_argument(
                "uploaded blob size did not match digest",
            ));
        }
        let actual_hash = hex::encode(hasher.finalize());
        if actual_hash != resource.hash {
            return Err(Status::invalid_argument(
                "uploaded blob digest did not match content",
            ));
        }

        // Flush tokio's internal write buffer to the OS and close the write handle before
        // the blob is persisted. persist_artifact_from_path re-opens this path on a
        // separate descriptor to stat and copy it into a segment; without an explicit
        // flush, tokio::fs::File's lazily-flushed writes race that read and the segment
        // append fails with "appended N bytes, expected M" — which silently breaks remote
        // caching of any action that uploads many blobs concurrently (e.g. cargo build
        // scripts' directory outputs). The HTTP upload path flushes for the same reason.
        tokio::io::AsyncWriteExt::flush(&mut temp_file)
            .await
            .map_err(|error| Status::internal(format!("failed to flush temp blob: {error}")))?;
        drop(temp_file);

        let targets = replication_targets(&self.state).await;
        // The persist reports `already_present` from under the store's
        // per-artifact write lock, which decides billing below: a re-uploaded
        // blob (retry, or a client that skips FindMissingBlobs) must not be
        // billed twice — matching the HTTP upload path's `artifact_exists`
        // short-circuit — and concurrent uploads of the same missing blob
        // resolve to exactly one billed writer.
        let persisted = self
            .state
            .store
            .persist_artifact_from_path_and_enqueue(
                ArtifactProducer::Reapi,
                &resource.namespace_id,
                &resource.key,
                "application/octet-stream",
                StagedArtifactPath::new(temp_path, file_cache_policy),
                &targets,
            )
            .await
            .map_err(|error| {
                if is_outbox_full_error(&error) {
                    Status::resource_exhausted(format!(
                        "replication backlog is full while persisting CAS blob: {error}"
                    ))
                } else if is_fd_pool_exhausted_error(&error) {
                    Status::resource_exhausted(format!(
                        "file descriptor pool exhausted while persisting CAS blob: {error}"
                    ))
                } else {
                    Status::internal(format!("failed to persist CAS blob: {error}"))
                }
            })?;
        self.state.notify.notify_one();
        self.state.metrics.record_artifact_write(
            ArtifactProducer::Reapi,
            "ok",
            persisted.manifest.size,
        );

        let mut response = Response::new(bytestream::WriteResponse {
            committed_size: written as i64,
        });
        self.apply_response_headers(
            &mut response,
            GrpcExtensionSpec {
                route: "reapi.bytestream.write",
                operation: "artifact.write",
                namespace_id: Some(&resource.namespace_id),
                producer: Some("reapi"),
                artifact_key: Some(resource.key),
                artifact_hash: Some(resource.hash),
            },
            principal.as_ref(),
        )
        .await?;
        // Book usage only after the response is fully built (headers applied) and
        // only when the blob was newly stored, so a re-upload isn't billed twice.
        if !persisted.already_present {
            self.record_reapi_upload(&metadata, &resource.namespace_id, persisted.manifest.size);
        }
        drop(memory_admission);
        Ok(response)
    }

    /// Serves the namespace's action-cache snapshot from the cached index:
    /// reconcile against the manifest keyspace (one index scan, no stored
    /// ActionResult reads), load only entries that are new or changed,
    /// presence-gate every referenced blob (manifest presence — eviction
    /// removes manifests, so this tracks it exactly), then encode in memory.
    /// `after` > 0 returns a delta of entries written after that watermark.
    async fn serve_actioncache_snapshot(
        &self,
        namespace_id: &str,
        after: u64,
    ) -> Result<Vec<u8>, Status> {
        // Serve the cached index immediately, kicking the reconcile in the
        // background once the view is older than the freshness window: a
        // reconcile costs a namespace scan (tens of seconds on a large
        // namespace), and running it inline made every fetch pay it — 40s
        // measured for a serve whose encode and transfer account for a few
        // seconds. Staleness is bounded by the window plus the client's own
        // delta cadence.
        {
            let mut indexes = self
                .snapshot_cache
                .indexes
                .lock()
                .expect("snapshot cache lock poisoned");
            if let Some(index) = indexes.get_mut(namespace_id) {
                let stale = index.reconciled_at.elapsed() >= SNAPSHOT_RECONCILE_INTERVAL;
                index.last_used = Instant::now();
                let bytes = self.encode_snapshot(index, after)?;
                drop(indexes);
                self.cache_full_view(namespace_id, after, &bytes);
                if stale {
                    let _build = self.ensure_index_build(namespace_id);
                }
                return Ok(bytes);
            }
        }
        // The index is out — either a reconcile has it, or it has never been
        // built. For a full request, serve the last full view (stale) rather
        // than shedding a cold client to UNAVAILABLE while a rebuild runs, and
        // make sure a rebuild is in flight. A delta cannot be replayed this
        // way, so it falls through to the cold path (its client keeps its
        // current snapshot and retries).
        if after == 0 {
            let cached = self
                .snapshot_cache
                .served_full
                .lock()
                .expect("snapshot served_full lock poisoned")
                .get(namespace_id)
                .cloned();
            if let Some(cached) = cached {
                let _permit = self
                    .state
                    .memory
                    .try_acquire_reapi_materialization(cached.len())
                    .map_err(|_| {
                        Status::resource_exhausted(
                            "action-cache snapshot serve declined under memory pressure",
                        )
                    })?;
                let _build = self.ensure_index_build(namespace_id);
                return Ok((*cached).clone());
            }
        }
        // Cold path: wait briefly for the build so small (and already
        // backfilled) namespaces keep their one-round-trip semantics, but
        // never pin the request to it — a first-ever backfill of a large
        // namespace runs for minutes, and holding the RPC open just walks
        // every client into its deadline (production clients timed out on
        // every fetch for as long as the build ran). Past the bound the
        // client gets UNAVAILABLE, stays on the per-key path, and a later
        // fetch is served from the completed index.
        let build = self.ensure_index_build(namespace_id);
        match tokio::time::timeout(SNAPSHOT_COLD_SERVE_WAIT, build).await {
            Ok(result) => result.map_err(|error| {
                Status::internal(format!(
                    "failed to build the action-cache snapshot: {error}"
                ))
            })?,
            Err(_elapsed) => {
                return Err(Status::unavailable(
                    "action-cache snapshot index is building; retry shortly",
                ));
            }
        }
        let mut indexes = self
            .snapshot_cache
            .indexes
            .lock()
            .expect("snapshot cache lock poisoned");
        let Some(index) = indexes.get_mut(namespace_id) else {
            return Err(Status::unavailable(
                "action-cache snapshot index was not retained; use per-key lookup and retry",
            ));
        };
        index.last_used = Instant::now();
        let bytes = self.encode_snapshot(index, after)?;
        drop(indexes);
        self.cache_full_view(namespace_id, after, &bytes);
        Ok(bytes)
    }

    /// Caches a full (`after == 0`) encoded view as the namespace's
    /// `served_full`, so a serve that lands while the index is out for a
    /// reconcile returns it instead of shedding to UNAVAILABLE. A delta is
    /// relative to a client's watermark and cannot be replayed, so it is not
    /// cached.
    fn cache_full_view(&self, namespace_id: &str, after: u64, bytes: &[u8]) {
        if after != 0 {
            return;
        }
        let target_bytes = self
            .state
            .memory
            .snapshot_cache_target_bytes(self.snapshot_cache.max_bytes);
        if bytes.len() > target_bytes {
            self.state
                .metrics
                .record_memory_action("snapshot_full_view_budget_rejected");
            return;
        }
        self.snapshot_cache
            .served_full
            .lock()
            .expect("snapshot served_full lock poisoned")
            .insert(namespace_id.to_owned(), std::sync::Arc::new(bytes.to_vec()));
        self.snapshot_cache
            .trim_to(target_bytes, "capacity", &self.state.metrics);
    }

    fn encode_snapshot(
        &self,
        index: &NamespaceSnapshotIndex,
        after: u64,
    ) -> Result<Vec<u8>, Status> {
        let content_budget = self
            .state
            .memory
            .reapi_response_budget_bytes()
            .min(self.state.memory.reapi_materialization_pool_bytes() / 2);
        if content_budget == 0 {
            return Err(Status::resource_exhausted(
                "action-cache snapshot encode declined under memory pressure",
            ));
        }
        let _permit = self
            .state
            .memory
            .try_acquire_reapi_materialization(content_budget)
            .map_err(|_| {
                Status::resource_exhausted(
                    "action-cache snapshot encode is waiting for memory headroom",
                )
            })?;
        Ok(index.encode_with_budget(after, content_budget))
    }

    /// The namespace's in-flight index build, starting one when none is
    /// running. Requests share a single reconcile; the spawned task takes the
    /// index out for the reconcile and reinserts it (with the LRU bound
    /// applied) whether the reconcile succeeded or failed, so accumulated
    /// progress survives request aborts and transient store errors alike.
    /// While the index is out, serves fall back to the cached full view
    /// (`served_full`) rather than the cold path.
    fn ensure_index_build(&self, namespace_id: &str) -> SharedIndexBuild {
        let mut builds = self
            .snapshot_cache
            .builds
            .lock()
            .expect("snapshot builds lock poisoned");
        if let Some(build) = builds.get(namespace_id) {
            return build.clone();
        }
        if builds.len() >= SNAPSHOT_CACHE_MAX_NAMESPACES {
            self.state
                .metrics
                .record_memory_action("snapshot_build_admission_rejected");
            return futures_util::future::ready(Err(format!(
                "action-cache snapshot build queue is full ({} namespaces)",
                SNAPSHOT_CACHE_MAX_NAMESPACES
            )))
            .boxed()
            .shared();
        }
        let cache = self.snapshot_cache.clone();
        let state = self.state.clone();
        let namespace = namespace_id.to_owned();
        // Spawned while holding the builds lock, so the task's terminal
        // removal (which takes the same lock) cannot run before the insert
        // below — the entry it removes is always its own. The body is
        // panic-guarded and the removal sits OUTSIDE it: a reconcile panic
        // that leaked the entry left a dead shared future in the map, and
        // every later build request for the namespace resolved to that
        // corpse — snapshots stayed bricked until the pod restarted.
        let cleanup_namespace = namespace.clone();
        let cleanup_cache = cache.clone();
        let task = tokio::spawn(async move {
            let outcome = futures_util::FutureExt::catch_unwind(std::panic::AssertUnwindSafe(
                Self::run_index_build(cache, state, namespace),
            ))
            .await;
            cleanup_cache
                .builds
                .lock()
                .expect("snapshot builds lock poisoned")
                .remove(&cleanup_namespace);
            match outcome {
                Ok(result) => result,
                Err(_panic) => {
                    tracing::warn!(
                        namespace_id = cleanup_namespace.as_str(),
                        "action-cache snapshot index build panicked"
                    );
                    Err("snapshot index build panicked".to_owned())
                }
            }
        });
        let build: SharedIndexBuild = async move {
            task.await
                .map_err(|error| format!("snapshot index build panicked: {error}"))?
        }
        .boxed()
        .shared();
        builds.insert(namespace_id.to_owned(), build.clone());
        build
    }

    /// The build task's body: permit, reconcile, reinsert. The caller owns
    /// the builds-map entry cleanup, which must run whether this returns or
    /// panics.
    async fn run_index_build(
        cache: std::sync::Arc<SnapshotCache>,
        state: SharedState,
        namespace: String,
    ) -> Result<(), String> {
        tracing::info!(
            namespace_id = namespace.as_str(),
            "action-cache snapshot index build started"
        );
        if !state.memory.allow_background_admission() {
            tracing::warn!(
                namespace_id = namespace.as_str(),
                pressure = state.memory.pressure().as_str(),
                "action-cache snapshot build skipped under memory pressure"
            );
            state
                .metrics
                .record_memory_action("snapshot_build_pressure_skipped");
            return Err("declined under memory pressure".to_owned());
        }
        let _build_guard = cache.build_lock.lock().await;
        if !state.memory.allow_background_admission() {
            return Err("declined under memory pressure".to_owned());
        }
        let index_max_bytes = cache.index_max_bytes();
        // A build's transient memory rides the response-materialization
        // pool: holding a byte-sized permit for its duration means a node
        // under memory pressure defers the build instead of being
        // OOM-killed. The build WAITS for headroom rather than declining:
        // a stale snapshot is what causes heavy per-key traffic, per-key
        // responses draw on this same pool, and a try-acquire under that
        // load refused every reconcile for exactly the reason one was
        // needed — the index parked stale indefinitely. The bounded wait
        // still fails closed if the pool never frees. The budget adapts
        // to small pools so tests and tiny nodes still build; the
        // streaming reconcile keeps the real peak near it.
        let budget = SNAPSHOT_BUILD_BUDGET_BYTES
            .min(state.memory.reapi_materialization_pool_bytes() / 2)
            .max(1);
        let permit = tokio::time::timeout(
            SNAPSHOT_BUILD_PERMIT_WAIT,
            state
                .memory
                .acquire_background_reapi_materialization(budget),
        )
        .await;
        let Ok(Ok(_permit)) = permit else {
            tracing::warn!(
                namespace_id = namespace.as_str(),
                budget,
                "action-cache snapshot build declined under memory pressure"
            );
            return Err("declined under memory pressure".to_owned());
        };
        // Take the index out for the reconcile (it mutates in place). A serve
        // landing while it is out does NOT fall to the cold path and answer
        // UNAVAILABLE — the fast path's caller serves the last full view from
        // `served_full` instead. Cloning the whole index to keep it in place
        // would copy an unbounded node table (the entry cap does not bound it);
        // the cached full encoding is bounded at the wire ceiling.
        let index = cache
            .indexes
            .lock()
            .expect("snapshot cache lock poisoned")
            .remove(&namespace)
            .unwrap_or_else(NamespaceSnapshotIndex::new);
        cache.trim_to(
            cache.max_bytes.saturating_sub(index_max_bytes),
            "build_headroom",
            &state.metrics,
        );
        let (mut index, result) =
            match reconcile_snapshot_index(&state, &namespace, index, index_max_bytes).await {
                Ok(mut index) => {
                    index.reconciled_at = Instant::now();
                    (index, Ok(()))
                }
                Err((index, error)) => {
                    // The reconcile hands the index back so accumulated progress
                    // survives a transient store error; reinsert it. Background
                    // kicks drop the shared future without awaiting it, so this is
                    // the only place a repeated reconcile failure becomes visible.
                    tracing::warn!(
                        namespace_id = namespace.as_str(),
                        error = error.as_str(),
                        "action-cache snapshot reconcile failed"
                    );
                    (index, Err(error))
                }
            };
        index.last_used = Instant::now();
        if !state.memory.allow_background_admission() {
            cache.trim_to(
                state.memory.snapshot_cache_target_bytes(cache.max_bytes),
                state.memory.pressure().as_str(),
                &state.metrics,
            );
            return Err("snapshot build completed under memory pressure and was discarded".into());
        }
        {
            let mut indexes = cache.indexes.lock().expect("snapshot cache lock poisoned");
            indexes.insert(namespace.clone(), index);
            while indexes.len() > SNAPSHOT_CACHE_MAX_NAMESPACES {
                let oldest = indexes
                    .iter()
                    .min_by_key(|(_, index)| index.last_used)
                    .map(|(namespace, _)| namespace.clone());
                let Some(oldest) = oldest else { break };
                indexes.remove(&oldest);
                // Drop the evicted namespace's cached full view too, so
                // `served_full` stays bounded alongside `indexes`.
                cache
                    .served_full
                    .lock()
                    .expect("snapshot served_full lock poisoned")
                    .remove(&oldest);
            }
        }
        cache.trim_to(cache.max_bytes, "capacity", &state.metrics);
        result
    }
}

/// Reconciles a namespace's snapshot index against the manifest keyspace:
/// one namespace-index scan, action-result reads only for new-or-changed
/// entries, the manifest-existence presence gate with its cascade delete,
/// and node-table compaction. On failure the caller gets the index back so
/// progress survives transient store errors.
async fn reconcile_snapshot_index(
    state: &SharedState,
    namespace_id: &str,
    mut index: NamespaceSnapshotIndex,
    index_max_bytes: usize,
) -> Result<NamespaceSnapshotIndex, (NamespaceSnapshotIndex, String)> {
    let started = Instant::now();
    let manifests = match state
        .store
        .action_cache_manifests(namespace_id, SNAPSHOT_INDEX_MAX_ENTRIES)
    {
        Ok(manifests) => manifests,
        Err(error) => {
            return Err((
                index,
                format!("failed to enumerate the action cache: {error}"),
            ));
        }
    };
    let scan_ms = started.elapsed().as_millis() as u64;
    // Diff the cached entries against the manifest keyspace: load only
    // new-or-changed entries, drop entries whose artifacts are gone.
    // Manifests are MOVED into the map (never cloned), and action results
    // stream through a bounded window below instead of being collected —
    // building the first index for a large namespace with layered full-size
    // copies OOM-killed 2Gi production pods even with the scan capped.
    let mut current: BTreeMap<[u8; 32], (u64, ArtifactManifest)> = BTreeMap::new();
    for manifest in manifests {
        let Some(hash) = manifest
            .key
            .strip_prefix("action_cache/")
            .and_then(|rest| rest.split('/').next())
            .and_then(|hash| hex::decode(hash).ok())
            .and_then(|hash| <[u8; 32]>::try_from(hash.as_slice()).ok())
        else {
            continue;
        };
        let version = manifest.version_ms;
        current.insert(hash, (version, manifest));
    }
    index.entries.retain(|hash, _| current.contains_key(hash));
    index.recompute_estimated_bytes();
    let mut changed: Vec<([u8; 32], u64)> = current
        .iter()
        .filter(|(hash, (version, _))| {
            index
                .entries
                .get(*hash)
                .is_none_or(|entry| entry.version_ms != *version)
        })
        .map(|(hash, (version, _))| (*hash, *version))
        .collect();
    changed.sort_unstable_by(|(_, left), (_, right)| right.cmp(left));
    // Manifests move out for the load and move back with the result, so the
    // stream owns everything it captures (the whole reconcile runs inside a
    // 'static spawned task) without duplicating a single manifest.
    let mut to_load = Vec::with_capacity(changed.len());
    for (hash, _) in changed {
        if let Some((version, manifest)) = current.remove(&hash) {
            to_load.push((hash, version, manifest));
        }
    }
    let changed_count = to_load.len();
    let mut loads_failed = 0_usize;
    let mut invalid = 0_usize;
    let mut budget_rejected = 0_usize;
    let mut loading =
        futures_util::stream::iter(to_load.into_iter().map(|(hash, version, manifest)| {
            let state = state.clone();
            async move {
                let bytes = read_manifest_bytes(&state, &manifest).await.ok();
                let action_result =
                    bytes.and_then(|bytes| reapi::ActionResult::decode(bytes.as_slice()).ok());
                (hash, version, manifest, action_result)
            }
        }))
        .buffered(32);
    while let Some((hash, version_ms, manifest, action_result)) = loading.next().await {
        current.insert(hash, (version_ms, manifest));
        index.remove_entry(&hash);
        let Some(action_result) = action_result else {
            loads_failed += 1;
            continue;
        };
        let entry_bytes = estimated_snapshot_entry_bytes(action_result.output_files.len());
        if index.estimated_bytes().saturating_add(entry_bytes) > index_max_bytes {
            budget_rejected += 1;
            continue;
        }
        let mut nodes = Vec::with_capacity(action_result.output_files.len());
        let mut valid = !action_result.output_files.is_empty();
        for file in &action_result.output_files {
            let (Ok(llcas), Some(digest)) = (hex::decode(&file.path), file.digest.as_ref()) else {
                valid = false;
                break;
            };
            let (Ok(blob_hash), true) = (
                hex::decode(&digest.hash)
                    .map_err(|_| ())
                    .and_then(|hash| <[u8; 32]>::try_from(hash.as_slice()).map_err(|_| ())),
                digest.size_bytes >= 0,
            ) else {
                valid = false;
                break;
            };
            let node_budget = index_max_bytes.saturating_sub(entry_bytes);
            let Some(node) =
                index.try_intern_node(llcas, blob_hash, digest.size_bytes as u64, node_budget)
            else {
                valid = false;
                budget_rejected += 1;
                break;
            };
            nodes.push(node);
        }
        if valid {
            index.insert_entry(hash, SnapshotIndexEntry { version_ms, nodes });
        } else {
            invalid += 1;
        }
        if !state.memory.allow_background_admission() {
            drop(loading);
            index.compact_nodes();
            return Err((
                index,
                "memory pressure interrupted snapshot reconcile".into(),
            ));
        }
    }
    drop(loading);
    let load_ms = started.elapsed().as_millis() as u64 - scan_ms;

    // Presence gate: an entry only stays advertised while every node's
    // blob manifest exists (CAS eviction outlives action-cache entries,
    // and clang fails the build on a missing object). Mostly
    // existence-cache hits; a dead entry is dropped from the cache too —
    // a republish bumps its version and reloads it. The store reads are
    // synchronous, so yield periodically: on a cold cache this loop is
    // hundreds of thousands of point reads, and unbroken it parks a whole
    // runtime worker for their duration.
    let mut dead: Vec<[u8; 32]> = Vec::new();
    for (gated, (hash, entry)) in index.entries.iter().enumerate() {
        if gated % 1024 == 1023 {
            tokio::task::yield_now().await;
        }
        let missing = entry.nodes.iter().any(|&node| {
            !state
                .store
                .artifact_manifest_exists(
                    ArtifactProducer::Reapi,
                    namespace_id,
                    &index.nodes[node as usize].blob_key,
                )
                .unwrap_or(false)
        });
        if missing {
            dead.push(*hash);
        }
    }
    // Cascade: an entry whose blobs were evicted is unserveable by
    // construction (the per-key path would hand out a manifest whose
    // batch_read then misses), so delete it from the store too, not just
    // from the cached index. The grace window keeps this from fighting
    // peer replication that delivers an entry before its blobs finish
    // syncing.
    let now = crate::utils::now_ms();
    let cascade: Vec<ArtifactManifest> = dead
        .iter()
        .filter_map(|hash| current.get(hash))
        .filter(|(version_ms, _)| now.saturating_sub(*version_ms) > SNAPSHOT_CASCADE_GRACE_MS)
        .map(|(_, manifest)| manifest.clone())
        .collect();
    for hash in dead {
        index.remove_entry(&hash);
    }
    if !cascade.is_empty() {
        match state.store.delete_artifact_metadata(&cascade) {
            Ok(()) => tracing::info!(
                deleted = cascade.len(),
                namespace_id,
                "deleted action-cache entries whose blobs were evicted"
            ),
            Err(error) => tracing::warn!("action-cache cascade delete failed: {error}"),
        }
    }
    index.compact_nodes();

    // One line per reconcile: production served a stale snapshot for hours
    // and nothing said whether builds were running, how much they scanned, or
    // what the index held afterwards — this is the Loki breadcrumb that turns
    // that from archaeology into a query.
    // `changed` counts entries whose scanned version differed from the cached
    // index; a load or parse failure there silently retains the entry's OLD
    // version, which is exactly the shape of a frozen watermark — these
    // counters are what distinguish "nothing new was published" from "new
    // versions were published but every reload failed".
    tracing::info!(
        namespace_id,
        entries = index.entries.len(),
        nodes = index.nodes.len(),
        watermark = index
            .entries
            .values()
            .map(|entry| entry.version_ms)
            .max()
            .unwrap_or(0),
        changed = changed_count,
        loads_failed,
        invalid,
        budget_rejected,
        estimated_bytes = index.estimated_bytes(),
        index_max_bytes,
        scan_ms,
        load_ms,
        gate_ms = started.elapsed().as_millis() as u64 - scan_ms - load_ms,
        elapsed_ms = started.elapsed().as_millis() as u64,
        "action-cache snapshot index reconciled"
    );
    Ok(index)
}

#[tonic::async_trait]
impl Capabilities for ReapiService {
    async fn get_capabilities(
        &self,
        request: Request<reapi::GetCapabilitiesRequest>,
    ) -> Result<Response<reapi::ServerCapabilities>, Status> {
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let extension = GrpcExtensionSpec {
            route: "reapi.capabilities.get",
            operation: "capabilities.read",
            namespace_id: Some(namespace_id),
            producer: Some("reapi"),
            artifact_key: None,
            artifact_hash: None,
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        let mut response = Response::new(reapi::ServerCapabilities {
            cache_capabilities: Some(reapi::CacheCapabilities {
                digest_functions: vec![reapi::digest_function::Value::Sha256 as i32],
                action_cache_update_capabilities: Some(reapi::ActionCacheUpdateCapabilities {
                    update_enabled: true,
                }),
                cache_priority_capabilities: None,
                max_batch_total_size_bytes: MAX_MODULE_TOTAL_BYTES as i64,
                symlink_absolute_path_strategy:
                    reapi::symlink_absolute_path_strategy::Value::Disallowed as i32,
                supported_compressors: Vec::new(),
                supported_batch_update_compressors: Vec::new(),
                max_cas_blob_size_bytes: MAX_MODULE_TOTAL_BYTES as i64,
                split_blob_support: false,
                splice_blob_support: false,
                ..Default::default()
            }),
            execution_capabilities: None,
            deprecated_api_version: None,
            low_api_version: Some(SemVer {
                major: 2,
                minor: 0,
                patch: 0,
                prerelease: String::new(),
            }),
            high_api_version: Some(SemVer {
                major: 2,
                minor: 3,
                patch: 0,
                prerelease: String::new(),
            }),
        });
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        Ok(response)
    }
}

#[tonic::async_trait]
impl ActionCache for ReapiService {
    async fn get_action_result(
        &self,
        request: Request<reapi::GetActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let digest = request
            .get_ref()
            .action_digest
            .as_ref()
            .ok_or_else(|| Status::invalid_argument("missing action_digest"))?;
        let key = action_cache_key(&digest_key(digest)?);
        let extension = GrpcExtensionSpec {
            route: "reapi.action_cache.get",
            operation: "artifact.read",
            namespace_id: Some(namespace_id),
            producer: Some("reapi"),
            artifact_key: Some(key.clone()),
            artifact_hash: Some(digest.hash.clone()),
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        // Instance-wide action-cache snapshot: a reserved action key whose
        // "result" is the namespace's complete key→value map (deduplicated
        // node table + per-key node lists), inlined into a single output
        // file. One round trip primes a completely cold client — no per-key
        // lookups and no client-side memoization — after which content flows
        // through ordinary batched blob reads. The client hashes the reserved
        // key bytes exactly like a real key, so interception is a digest
        // comparison, and against an old server the lookup is a plain
        // not-found the client degrades from.
        if digest.hash == snapshot_action_hash()
            && digest.size_bytes == SNAPSHOT_ACTION_KEY.len() as i64
        {
            let after = request
                .get_ref()
                .inline_output_files
                .iter()
                .find_map(|hint| hint.strip_prefix(SNAPSHOT_AFTER_HINT)?.parse::<u64>().ok())
                .unwrap_or(0);
            let snapshot = self.serve_actioncache_snapshot(namespace_id, after).await?;
            let served = snapshot.len() as u64;
            let response_memory = self
                .state
                .memory
                .try_acquire_reapi_materialization(snapshot.len())
                .map_err(|_| {
                    Status::resource_exhausted(
                        "action-cache snapshot response is waiting for memory headroom",
                    )
                })?;
            let action_result = reapi::ActionResult {
                output_files: vec![reapi::OutputFile {
                    path: SNAPSHOT_OUTPUT_PATH.to_owned(),
                    digest: Some(reapi::Digest {
                        hash: hex::encode(Sha256::digest(&snapshot)),
                        size_bytes: snapshot.len() as i64,
                    }),
                    contents: snapshot,
                    ..Default::default()
                }],
                ..Default::default()
            };
            let mut response = Response::new(action_result);
            if let Some(permit) = response_memory {
                response
                    .extensions_mut()
                    .insert(ResponseMemoryGuard::new(vec![permit]));
            }
            self.apply_response_headers(&mut response, extension, principal.as_ref())
                .await?;
            self.state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "ok", served);
            self.record_reapi_download(request.metadata(), namespace_id, served);
            return Ok(response);
        }
        let mut materialization_budget =
            std::sync::Mutex::new(MaterializationBudget::new(&self.state));
        let (size_bytes, mut action_result) = fetch_keyvalue_proto::<reapi::ActionResult>(
            &self.state,
            namespace_id,
            &key,
            "action result",
            Some(
                materialization_budget
                    .get_mut()
                    .expect("action-cache materialization budget lock poisoned"),
            ),
        )
        .await?;
        // Presence gate, the per-key counterpart of the snapshot reconcile's:
        // an entry whose output blobs were evicted is unserveable by
        // construction — the compiler replaying it hard-fails the build on
        // the first missing object (a production cold build died on its very
        // first resolve this way), while a not-found here is an ordinary miss
        // the client recompiles from and republishes with fresh blobs.
        // Entries older than the snapshot index's scan cap are exactly the
        // ones its reconcile-time gate and cascade never examine, so without
        // this they serve dead forever. Mostly existence-cache hits.
        let evicted = action_result.output_files.iter().find_map(|file| {
            let digest = file.digest.as_ref()?;
            let node_key = blob_key(&digest_key(digest).ok()?);
            let exists = self
                .state
                .store
                .artifact_manifest_exists(ArtifactProducer::Reapi, namespace_id, &node_key)
                .unwrap_or(true);
            (!exists).then(|| digest.hash.clone())
        });
        if let Some(missing) = evicted {
            // Delete the dead entry past the replication grace window (a
            // freshly replicated entry's blobs may still be in flight), so
            // the next publish recreates it instead of every reader paying
            // this lookup again.
            if let Ok(Some(manifest)) =
                self.state
                    .store
                    .manifest_for_key(ArtifactProducer::Reapi, namespace_id, &key)
                && crate::utils::now_ms().saturating_sub(manifest.version_ms)
                    > SNAPSHOT_CASCADE_GRACE_MS
            {
                match self.state.store.delete_artifact_metadata(&[manifest]) {
                    Ok(()) => tracing::info!(
                        namespace_id,
                        key,
                        missing,
                        "deleted an action-cache entry whose output blob was evicted"
                    ),
                    Err(error) => {
                        tracing::warn!("dead action-cache entry delete failed: {error}")
                    }
                }
            }
            return Err(Status::not_found(
                "action result references evicted output blobs",
            ));
        }
        // Everything this RPC returns is egress: the stored action result plus
        // any stdout/stderr/output-file blobs inlined below, so all of it is
        // accumulated for the usage rollup.
        let mut served_bytes = size_bytes;

        if request.get_ref().inline_stdout
            && action_result.stdout_raw.is_empty()
            && let Some(digest) = &action_result.stdout_digest
            && let Some(bytes) = maybe_read_cas_bytes(
                &self.state,
                namespace_id,
                digest,
                Some(
                    materialization_budget
                        .get_mut()
                        .expect("action-cache materialization budget lock poisoned"),
                ),
            )
            .await?
        {
            served_bytes = served_bytes.saturating_add(bytes.len() as u64);
            action_result.stdout_raw = bytes;
        }
        if request.get_ref().inline_stderr
            && action_result.stderr_raw.is_empty()
            && let Some(digest) = &action_result.stderr_digest
            && let Some(bytes) = maybe_read_cas_bytes(
                &self.state,
                namespace_id,
                digest,
                Some(
                    materialization_budget
                        .get_mut()
                        .expect("action-cache materialization budget lock poisoned"),
                ),
            )
            .await?
        {
            served_bytes = served_bytes.saturating_add(bytes.len() as u64);
            action_result.stderr_raw = bytes;
        }
        if !request.get_ref().inline_output_files.is_empty() {
            // `"*"` is a Kura extension to the REAPI `inline_output_files`
            // hint: inline the contents of every output file the response
            // budget affords. It exists for clients (the Xcode CAS plugin)
            // whose output-file paths are digests unknown before this
            // response, collapsing the action lookup + blob fetch into one
            // round-trip. Best-effort by design: a file the budget cannot
            // afford stays un-inlined and the client falls back to
            // BatchReadBlobs for it, so mixed client/server versions
            // interoperate unchanged (an old server matches no literal `"*"`
            // path and inlines nothing).
            let inline_all = request
                .get_ref()
                .inline_output_files
                .iter()
                .any(|path| path == "*");
            // Collect the targets first, then read them concurrently: a
            // sequential await per file caps wildcard inlining at per-read
            // latency times manifest size, the same serialization
            // batch_read_blobs buffers to avoid (measured ~4ms per blob
            // serialized).
            // Each target carries whether the client listed its path explicitly
            // (as opposed to only matching via `"*"`): a wildcard match inlines
            // best-effort, but an explicit path keeps the hard budget error even
            // when `"*"` is also present.
            let targets: Vec<(usize, reapi::Digest, bool)> = action_result
                .output_files
                .iter()
                .enumerate()
                .filter_map(|(index, output_file)| {
                    let explicit = request
                        .get_ref()
                        .inline_output_files
                        .iter()
                        .any(|path| path == &output_file.path);
                    if (!inline_all && !explicit) || !output_file.contents.is_empty() {
                        return None;
                    }
                    output_file
                        .digest
                        .clone()
                        .map(|digest| (index, digest, explicit))
                })
                .collect();
            let reads: Vec<(usize, bool, Result<Option<Vec<u8>>, Status>)> =
                futures_util::stream::iter(targets.into_iter().map(|(index, digest, explicit)| {
                    let budget = &materialization_budget;
                    async move {
                        (
                            index,
                            explicit,
                            batch_read_one(&self.state, namespace_id, &digest, budget).await,
                        )
                    }
                }))
                .buffered(16)
                .collect()
                .await;
            for (index, explicit, read) in reads {
                match read {
                    Ok(Some(bytes)) => {
                        served_bytes = served_bytes.saturating_add(bytes.len() as u64);
                        action_result.output_files[index].contents = bytes;
                    }
                    Ok(None) => {}
                    // A wildcard-only match inlines best-effort: on budget
                    // exhaustion it stays un-inlined (a smaller later file may
                    // still fit) and the client falls back to BatchReadBlobs.
                    // A path the client listed explicitly keeps the hard error.
                    Err(status) if !explicit && status.code() == tonic::Code::ResourceExhausted => {
                    }
                    Err(status) => return Err(status),
                }
            }
        }

        let mut response = Response::new(action_result);
        let response_memory = materialization_budget
            .into_inner()
            .expect("action-cache materialization budget lock poisoned")
            .into_response_guard();
        if let Some(response_memory) = response_memory {
            response.extensions_mut().insert(response_memory);
        }
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        self.state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "ok", size_bytes);
        // Book usage only after the response is fully built (headers applied),
        // matching the other handlers' success-arm convention.
        self.record_reapi_download(request.metadata(), namespace_id, served_bytes);
        Ok(response)
    }

    async fn update_action_result(
        &self,
        request: Request<reapi::UpdateActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let digest = request
            .get_ref()
            .action_digest
            .as_ref()
            .ok_or_else(|| Status::invalid_argument("missing action_digest"))?;
        let action_result = request
            .get_ref()
            .action_result
            .clone()
            .ok_or_else(|| Status::invalid_argument("missing action_result"))?;
        let key = action_cache_key(&digest_key(digest)?);
        let extension = GrpcExtensionSpec {
            route: "reapi.action_cache.update",
            operation: "artifact.write",
            namespace_id: Some(namespace_id),
            producer: Some("reapi"),
            artifact_key: Some(key.clone()),
            artifact_hash: Some(digest.hash.clone()),
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        let bytes = action_result.encode_to_vec();
        let targets = replication_targets(&self.state).await;
        let (manifest, applied) = self
            .state
            .store
            .persist_inline_artifact_from_bytes_damped_and_enqueue(
                ArtifactProducer::Reapi,
                namespace_id,
                &key,
                "application/x-protobuf",
                &bytes,
                &targets,
            )
            .await
            .map_err(|error| store_write_status("failed to store action result", error))?;
        self.state.notify.notify_one();
        self.state
            .metrics
            .record_artifact_write(ArtifactProducer::Reapi, "ok", manifest.size);
        let mut response = Response::new(action_result);
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        // Book usage only after the response is fully built. Every applied
        // update is billed: an action result is a mutable entry whose content
        // changes across updates, so there is no CAS-style "already present"
        // dedupe — matching the HTTP key-value path, which bills each put.
        // A damped refresh (identical bytes, fresh version) applies nothing
        // and bills nothing.
        if applied {
            self.record_reapi_upload(request.metadata(), namespace_id, manifest.size);
        }
        Ok(response)
    }
}

#[tonic::async_trait]
impl ContentAddressableStorage for ReapiService {
    type GetTreeStream =
        Pin<Box<dyn tokio_stream::Stream<Item = Result<reapi::GetTreeResponse, Status>> + Send>>;

    async fn find_missing_blobs(
        &self,
        request: Request<reapi::FindMissingBlobsRequest>,
    ) -> Result<Response<reapi::FindMissingBlobsResponse>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let extension = GrpcExtensionSpec {
            route: "reapi.cas.find_missing",
            operation: "artifact.inspect",
            namespace_id: Some(namespace_id),
            producer: Some("reapi"),
            artifact_key: None,
            artifact_hash: None,
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        let mut missing = Vec::new();
        for digest in &request.get_ref().blob_digests {
            let key = blob_key(&digest_key(digest)?);
            let exists = self
                .state
                .store
                .artifact_exists(ArtifactProducer::Reapi, namespace_id, &key)
                .await
                .map_err(|error| {
                    Status::internal(format!("failed to inspect CAS blob: {error}"))
                })?;
            if !exists {
                missing.push(digest.clone());
            }
        }

        let mut response = Response::new(reapi::FindMissingBlobsResponse {
            missing_blob_digests: missing,
        });
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        Ok(response)
    }

    async fn batch_update_blobs(
        &self,
        request: Request<reapi::BatchUpdateBlobsRequest>,
    ) -> Result<Response<reapi::BatchUpdateBlobsResponse>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let extension = GrpcExtensionSpec {
            route: "reapi.cas.batch_update",
            operation: "artifact.write",
            namespace_id: Some(namespace_id),
            producer: Some("reapi"),
            artifact_key: None,
            artifact_hash: None,
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        let mut responses = Vec::with_capacity(request.get_ref().requests.len());
        // Accumulate only the bytes this RPC actually stored so the whole batch
        // books a single usage request (matching how ByteStream/HTTP count one
        // request per call), and so already-present blobs are not billed —
        // mirroring the HTTP upload path's `artifact_exists` short-circuit,
        // with presence decided under the store's write lock.
        let mut stored_bytes = 0_u64;
        let mut stored_any = false;

        for item in &request.get_ref().requests {
            let digest = match &item.digest {
                Some(digest) => digest.clone(),
                None => {
                    responses.push(reapi::batch_update_blobs_response::Response {
                        digest: None,
                        status: Some(rpc_status(3, "missing digest")),
                    });
                    continue;
                }
            };
            if item.compressor != 0 {
                responses.push(reapi::batch_update_blobs_response::Response {
                    digest: Some(digest),
                    status: Some(rpc_status(3, "compressed uploads are not supported")),
                });
                continue;
            }
            match persist_cas_blob(&self.state, namespace_id, &digest, &item.data).await {
                Ok(newly_stored) => {
                    if newly_stored {
                        stored_bytes = stored_bytes.saturating_add(item.data.len() as u64);
                        stored_any = true;
                    }
                    responses.push(reapi::batch_update_blobs_response::Response {
                        digest: Some(digest),
                        status: Some(rpc_status(0, "")),
                    })
                }
                Err(error) => {
                    let code = if is_outbox_full_error(&error) { 8 } else { 13 };
                    responses.push(reapi::batch_update_blobs_response::Response {
                        digest: Some(digest),
                        status: Some(rpc_status(code, error)),
                    })
                }
            }
        }

        let mut response = Response::new(reapi::BatchUpdateBlobsResponse { responses });
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        if stored_any {
            self.record_reapi_upload(request.metadata(), namespace_id, stored_bytes);
        }
        Ok(response)
    }

    async fn batch_read_blobs(
        &self,
        request: Request<reapi::BatchReadBlobsRequest>,
    ) -> Result<Response<reapi::BatchReadBlobsResponse>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let extension = GrpcExtensionSpec {
            route: "reapi.cas.batch_read",
            operation: "artifact.read",
            namespace_id: Some(namespace_id),
            producer: Some("reapi"),
            artifact_key: None,
            artifact_hash: None,
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        // Blobs are read concurrently: a sequential await per blob caps the
        // whole batch at per-read latency times batch size, which dominates
        // large read-heavy clients (measured ~4ms per blob serialized). The
        // budget claim is synchronous and taken under a short lock that is
        // never held across an await; per-blob failure semantics are
        // unchanged and response order matches request order.
        let budget = std::sync::Mutex::new(MaterializationBudget::new(&self.state));
        let digests: Vec<reapi::Digest> = request.get_ref().digests.clone();
        let responses: Vec<reapi::batch_read_blobs_response::Response> =
            futures_util::stream::iter(digests.into_iter().map(|digest| {
                let budget = &budget;
                async move {
                    match batch_read_one(&self.state, namespace_id, &digest, budget).await {
                        Ok(Some(data)) => reapi::batch_read_blobs_response::Response {
                            digest: Some(digest.clone()),
                            data,
                            compressor: 0,
                            status: Some(rpc_status(0, "")),
                        },
                        Ok(None) => reapi::batch_read_blobs_response::Response {
                            digest: Some(digest.clone()),
                            data: Vec::new(),
                            compressor: 0,
                            status: Some(rpc_status(5, "blob not found")),
                        },
                        Err(status) => reapi::batch_read_blobs_response::Response {
                            digest: Some(digest.clone()),
                            data: Vec::new(),
                            compressor: 0,
                            status: Some(rpc_status_from_grpc_status(&status)),
                        },
                    }
                }
            }))
            .buffered(16)
            .collect()
            .await;
        // Sum the bytes served so the whole batch books a single download usage
        // request, matching how ByteStream/HTTP count one request per call. A
        // successful read carries gRPC status code 0.
        let served_bytes: u64 = responses
            .iter()
            .filter(|response| {
                response
                    .status
                    .as_ref()
                    .is_some_and(|status| status.code == 0)
            })
            .map(|response| response.data.len() as u64)
            .sum();
        let served_any = responses.iter().any(|response| {
            response
                .status
                .as_ref()
                .is_some_and(|status| status.code == 0)
        });

        let mut response = Response::new(reapi::BatchReadBlobsResponse { responses });
        let response_memory = budget
            .into_inner()
            .expect("batch-read materialization budget lock poisoned")
            .into_response_guard();
        if let Some(response_memory) = response_memory {
            response.extensions_mut().insert(response_memory);
        }
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        if served_any {
            self.record_reapi_download(request.metadata(), namespace_id, served_bytes);
        }
        Ok(response)
    }

    async fn get_tree(
        &self,
        _request: Request<reapi::GetTreeRequest>,
    ) -> Result<Response<Self::GetTreeStream>, Status> {
        Err(Status::unimplemented("GetTree is not supported"))
    }

    async fn split_blob(
        &self,
        _request: Request<reapi::SplitBlobRequest>,
    ) -> Result<Response<reapi::SplitBlobResponse>, Status> {
        Err(Status::unimplemented("SplitBlob is not supported"))
    }

    async fn splice_blob(
        &self,
        _request: Request<reapi::SpliceBlobRequest>,
    ) -> Result<Response<reapi::SpliceBlobResponse>, Status> {
        Err(Status::unimplemented("SpliceBlob is not supported"))
    }
}

#[tonic::async_trait]
impl ByteStream for ReapiService {
    type ReadStream =
        Pin<Box<dyn tokio_stream::Stream<Item = Result<bytestream::ReadResponse, Status>> + Send>>;

    async fn read(
        &self,
        request: Request<bytestream::ReadRequest>,
    ) -> Result<Response<Self::ReadStream>, Status> {
        let resource = parse_read_resource_name(&request.get_ref().resource_name)?;
        let extension = GrpcExtensionSpec {
            route: "reapi.bytestream.read",
            operation: "artifact.read",
            namespace_id: Some(&resource.namespace_id),
            producer: Some("reapi"),
            artifact_key: Some(resource.key.clone()),
            artifact_hash: Some(resource.hash.clone()),
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        if request.get_ref().read_offset < 0 {
            return Err(Status::invalid_argument("read_offset must be non-negative"));
        }
        if request.get_ref().read_limit < 0 {
            return Err(Status::invalid_argument("read_limit must be non-negative"));
        }
        let manifest = match self
            .state
            .store
            .fetch_artifact_for_serving(
                ArtifactProducer::Reapi,
                &resource.namespace_id,
                &resource.key,
            )
            .await
        {
            Ok(Some(manifest)) => manifest,
            Ok(None) => {
                self.state
                    .metrics
                    .record_artifact_read(ArtifactProducer::Reapi, "not_found", 0);
                return Err(Status::not_found("blob not found"));
            }
            Err(error) => {
                self.state
                    .metrics
                    .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
                return Err(Status::internal(format!(
                    "failed to read CAS blob: {error}"
                )));
            }
        };
        let read_offset = request.get_ref().read_offset as u64;
        if read_offset > manifest.size {
            return Err(Status::out_of_range("read_offset exceeds blob size"));
        }
        let read_limit = if request.get_ref().read_limit == 0 {
            None
        } else {
            Some(request.get_ref().read_limit as u64)
        };
        let bytes_to_read = read_limit
            .unwrap_or_else(|| manifest.size.saturating_sub(read_offset))
            .min(manifest.size.saturating_sub(read_offset));
        // Tolerates a concurrent background promotion relocating the blob
        // between the manifest fetch above and this open (see
        // `Store::open_artifact_reader_range_tolerating_promotion`); a genuine
        // eviction is a NOT_FOUND miss, not an internal error.
        let Some((_, reader)) = self
            .state
            .store
            .open_artifact_reader_range_tolerating_promotion(&manifest, read_offset, read_limit)
            .await
            .map_err(|error| {
                self.state
                    .metrics
                    .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
                Status::internal(format!("failed to stream blob: {error}"))
            })?
        else {
            self.state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "not_found", 0);
            return Err(Status::not_found("blob not found"));
        };
        self.state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "ok", bytes_to_read);
        let stream =
            ReaderStream::with_capacity(reader, REAPI_READ_STREAM_CHUNK_BYTES).map(move |result| {
                match result {
                    Ok(bytes) => Ok(bytestream::ReadResponse {
                        data: bytes.to_vec(),
                    }),
                    Err(error) => Err(Status::internal(format!(
                        "failed to stream blob chunk: {error}"
                    ))),
                }
            });

        let mut response = Response::new(Box::pin(stream) as Self::ReadStream);
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        // Book usage only once the response is fully built (headers applied): a
        // failure above turns into a gRPC error with no payload, so billing must
        // not have fired. Recorded before the body streams, mirroring the "ok"
        // read metric and the HTTP path's optimistic size accounting.
        self.record_reapi_download(request.metadata(), &resource.namespace_id, bytes_to_read);
        Ok(response)
    }

    async fn write(
        &self,
        request: Request<tonic::Streaming<bytestream::WriteRequest>>,
    ) -> Result<Response<bytestream::WriteResponse>, Status> {
        let temp_path = temp_file_path(&self.state.config.tmp_dir.join("uploads"), "reapi-write");
        if let Some(parent) = temp_path.parent() {
            self.state
                .io
                .create_dir_all(parent)
                .await
                .map_err(Status::internal)?;
        }
        let mut cleanup = TempFileCleanup::new_unreserved(temp_path.clone());

        // The owned cleanup guard removes the partial even when transport
        // cancellation drops this future at an await point. On success the
        // persist step already unlinks the temp file, so its drop is a no-op.
        let result = self.write_to_temp(&temp_path, request, &mut cleanup).await;
        cleanup.remove_and_disarm(&self.state.io).await;
        if let Err(status) = &result {
            // The success path records "ok" inside write_to_temp; meter the
            // failure here so stall-timeout, transport, and validation aborts are
            // visible in metrics instead of surfacing only as client retries.
            self.state
                .metrics
                .record_artifact_write(ArtifactProducer::Reapi, "error", 0);
            tracing::warn!("reapi bytestream write failed: {status}");
        }
        result
    }

    async fn query_write_status(
        &self,
        request: Request<bytestream::QueryWriteStatusRequest>,
    ) -> Result<Response<bytestream::QueryWriteStatusResponse>, Status> {
        let resource = parse_write_resource_name(&request.get_ref().resource_name)?;
        let extension = GrpcExtensionSpec {
            route: "reapi.bytestream.query_write_status",
            operation: "artifact.inspect",
            namespace_id: Some(&resource.namespace_id),
            producer: Some("reapi"),
            artifact_key: Some(resource.key.clone()),
            artifact_hash: Some(resource.hash.clone()),
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        let manifest = self
            .state
            .store
            .fetch_artifact(
                ArtifactProducer::Reapi,
                &resource.namespace_id,
                &resource.key,
            )
            .await
            .map_err(|error| Status::internal(format!("failed to inspect blob status: {error}")))?;

        match manifest {
            Some(manifest) => {
                let mut response = Response::new(bytestream::QueryWriteStatusResponse {
                    committed_size: manifest.size as i64,
                    complete: true,
                });
                self.apply_response_headers(&mut response, extension, principal.as_ref())
                    .await?;
                Ok(response)
            }
            None => Err(Status::not_found("blob not found")),
        }
    }
}

async fn fetch_keyvalue_proto<T>(
    state: &SharedState,
    namespace_id: &str,
    key: &str,
    label: &str,
    materialization_budget: Option<&mut MaterializationBudget<'_>>,
) -> Result<(u64, T), Status>
where
    T: Message + Default,
{
    let manifest = match state
        .store
        .fetch_artifact_for_serving(ArtifactProducer::Reapi, namespace_id, key)
        .await
    {
        Ok(Some(manifest)) => manifest,
        Ok(None) => {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "not_found", 0);
            return Err(Status::not_found(format!("{label} not found")));
        }
        Err(error) => {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
            return Err(Status::internal(format!("failed to load {label}: {error}")));
        }
    };
    if let Some(budget) = materialization_budget {
        budget.claim(manifest.size, label)?;
    }
    let bytes = read_manifest_bytes(state, &manifest)
        .await
        .map_err(|error| {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
            Status::internal(format!("failed to load {label}: {error}"))
        })?;
    let decoded = T::decode(bytes.as_slice()).map_err(|error| {
        state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
        Status::internal(format!("failed to decode {label}: {error}"))
    })?;
    Ok((bytes.len() as u64, decoded))
}

/// One blob of a batch read: identical semantics to maybe_read_cas_bytes,
/// with the shared per-request budget claimed under a short synchronous lock
/// so blobs can be read concurrently.
async fn batch_read_one(
    state: &SharedState,
    namespace_id: &str,
    digest: &reapi::Digest,
    budget: &std::sync::Mutex<MaterializationBudget<'_>>,
) -> Result<Option<Vec<u8>>, Status> {
    let key = blob_key(&digest_key(digest)?);
    let Some(manifest) = state
        .store
        .fetch_artifact_for_serving(ArtifactProducer::Reapi, namespace_id, &key)
        .await
        .inspect_err(|_| {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
        })
        .map_err(Status::internal)?
    else {
        state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "not_found", 0);
        return Ok(None);
    };
    budget
        .lock()
        .expect("budget lock")
        .claim(manifest.size, "CAS response materialization")?;
    let Some(bytes) = read_serving_bytes(state, &manifest)
        .await
        .inspect_err(|_| {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
        })
        .map_err(Status::internal)?
    else {
        state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "not_found", 0);
        return Ok(None);
    };
    state
        .metrics
        .record_artifact_read(ArtifactProducer::Reapi, "ok", bytes.len() as u64);
    Ok(Some(bytes))
}

async fn maybe_read_cas_bytes(
    state: &SharedState,
    namespace_id: &str,
    digest: &reapi::Digest,
    materialization_budget: Option<&mut MaterializationBudget<'_>>,
) -> Result<Option<Vec<u8>>, Status> {
    let key = blob_key(&digest_key(digest)?);
    let Some(manifest) = state
        .store
        .fetch_artifact_for_serving(ArtifactProducer::Reapi, namespace_id, &key)
        .await
        .inspect_err(|_| {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
        })
        .map_err(Status::internal)?
    else {
        state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "not_found", 0);
        return Ok(None);
    };
    if let Some(budget) = materialization_budget {
        budget.claim(manifest.size, "CAS response materialization")?;
    }
    let Some(bytes) = read_serving_bytes(state, &manifest)
        .await
        .inspect_err(|_| {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
        })
        .map_err(Status::internal)?
    else {
        state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "not_found", 0);
        return Ok(None);
    };
    state
        .metrics
        .record_artifact_read(ArtifactProducer::Reapi, "ok", bytes.len() as u64);
    Ok(Some(bytes))
}

// Persists a CAS blob and returns whether it was newly stored (`true`) or was
// already present (`false`). Billing uses this to charge only new bytes, the
// same rule as the HTTP upload path's `artifact_exists` short-circuit. The
// presence signal comes from the store's persist, evaluated under the
// per-artifact write lock, so concurrent uploads of the same missing blob
// resolve to exactly one `true` — a version-based `Applied` outcome can't
// stand in for this, because a re-upload that advances the stored version
// still applies over an already-present blob.
async fn persist_cas_blob(
    state: &SharedState,
    namespace_id: &str,
    digest: &reapi::Digest,
    bytes: &[u8],
) -> Result<bool, String> {
    validate_digest_bytes(digest, bytes)?;
    let key = blob_key(&digest_key(digest).map_err(|error| error.message().to_owned())?);
    let targets = replication_targets(state).await;
    let persisted = state
        .store
        .persist_artifact_from_bytes_and_enqueue(
            ArtifactProducer::Reapi,
            namespace_id,
            &key,
            "application/octet-stream",
            bytes,
            &targets,
        )
        .await?;
    state.notify.notify_one();
    state
        .metrics
        .record_artifact_write(ArtifactProducer::Reapi, "ok", persisted.manifest.size);
    Ok(!persisted.already_present)
}

async fn read_manifest_bytes(
    state: &SharedState,
    manifest: &ArtifactManifest,
) -> Result<Vec<u8>, String> {
    state.store.read_artifact_bytes(manifest).await
}

/// Reads a CAS blob served to a client, tolerating a concurrent background
/// segment promotion that may have relocated the artifact and evicted the old
/// segment between the manifest lookup and the read. `Ok(None)` is a genuine
/// miss (the artifact was evicted, not relocated). See
/// `Store::read_artifact_bytes_tolerating_promotion`.
async fn read_serving_bytes(
    state: &SharedState,
    manifest: &ArtifactManifest,
) -> Result<Option<Vec<u8>>, String> {
    state
        .store
        .read_artifact_bytes_tolerating_promotion(manifest)
        .await
}

struct MaterializationBudget<'a> {
    state: &'a SharedState,
    remaining_bytes: usize,
    held_permits: Vec<crate::memory::MemoryPermit>,
}

#[derive(Clone)]
struct ResponseMemoryGuard {
    _permits: std::sync::Arc<Vec<crate::memory::MemoryPermit>>,
}

impl ResponseMemoryGuard {
    fn new(permits: Vec<crate::memory::MemoryPermit>) -> Self {
        Self {
            _permits: std::sync::Arc::new(permits),
        }
    }
}

impl<'a> MaterializationBudget<'a> {
    fn new(state: &'a SharedState) -> Self {
        Self {
            state,
            remaining_bytes: state.memory.reapi_response_budget_bytes(),
            held_permits: Vec::new(),
        }
    }

    fn claim(&mut self, size_bytes: u64, label: &str) -> Result<(), Status> {
        let requested_bytes = usize::try_from(size_bytes).map_err(|_| {
            self.reject(format!(
                "{label} exceeds the maximum addressable REAPI materialization size"
            ))
        })?;
        if requested_bytes > self.remaining_bytes {
            return Err(self.reject(format!(
                "{label} needs {requested_bytes} bytes but only {} bytes remain in the REAPI materialization budget",
                self.remaining_bytes
            )));
        }
        let pool_bytes = self.state.memory.reapi_materialization_pool_bytes();
        if requested_bytes > pool_bytes {
            return Err(self.reject(format!(
                "{label} needs {requested_bytes} bytes but the node only allows {pool_bytes} bytes of concurrent REAPI response materialization"
            )));
        }
        let permit = self
            .state
            .memory
            .try_acquire_reapi_materialization(requested_bytes)
            .map_err(|_| {
                self.reject(format!(
                    "{label} was rejected because the concurrent REAPI response materialization pool is exhausted"
                ))
            })?;
        self.remaining_bytes -= requested_bytes;
        if let Some(permit) = permit {
            self.held_permits.push(permit);
        }
        Ok(())
    }

    fn reject(&self, message: String) -> Status {
        self.state
            .metrics
            .record_memory_action(REAPI_MATERIALIZATION_REJECTED_ACTION);
        Status::resource_exhausted(message)
    }

    fn into_response_guard(self) -> Option<ResponseMemoryGuard> {
        (!self.held_permits.is_empty()).then(|| ResponseMemoryGuard::new(self.held_permits))
    }
}

fn validate_digest_bytes(digest: &reapi::Digest, bytes: &[u8]) -> Result<(), String> {
    if digest.size_bytes < 0 {
        return Err("digest size must be non-negative".to_string());
    }
    if digest.size_bytes as usize != bytes.len() {
        return Err("digest size did not match payload length".to_string());
    }
    let actual_hash = hex::encode(Sha256::digest(bytes));
    if actual_hash != digest.hash {
        return Err("digest hash did not match payload".to_string());
    }
    Ok(())
}

/// Reserved action key whose lookup returns the namespace's action-cache
/// snapshot instead of a stored result. Clients hash these exact bytes the
/// way they hash a real llcas key, so serving it needs no new RPC surface.
/// Bump the version suffix on any change to the snapshot encoding (v2 added
/// the write-time watermark header and delta responses).
pub const SNAPSHOT_ACTION_KEY: &[u8] = b"tuist-actioncache-snapshot/v2";
const SNAPSHOT_OUTPUT_PATH: &str = "tuist-actioncache-snapshot";
/// The floor the compressed path's inclusion budget converges to. A body this
/// size is guaranteed to compress under the wire ceiling, so the shrink
/// retries always terminate at a safe view. Also the size below which no
/// benefit is left on the table: the recency window shed the oldest keys.
const SNAPSHOT_MIN_BUDGET_BYTES: usize = 48 << 20;

/// Ceiling on the COMPRESSED wire size, with headroom under the 64MB message
/// limit REAPI clients configure. Same transfer budget as the pre-compression
/// snapshot, but it now carries several times the content — a shared
/// namespace's snapshot rides the recency window down to a small suffix of
/// oldest keys, and those sheds were the per-key ladder that made the snapshot
/// net-negative over the WAN. Entries are encoded newest-first, so what sheds
/// is the oldest; dropped keys resolve through the per-key path.
const SNAPSHOT_WIRE_MAX_BYTES: usize = 48 << 20;

/// How much UNCOMPRESSED body to include before it stops adding keys. Sized so
/// the zstd output of a full body lands near the wire ceiling for this data's
/// typical ratio; a body that compresses worse is re-encoded smaller (see
/// `encode`). Also bounded in practice by the index's own entry cap.
const SNAPSHOT_CONTENT_BUDGET_BYTES: usize = 144 << 20;

/// Bounded shrink retries when a compressed body overshoots the wire ceiling.
/// Each retry scales the content budget down from the observed ratio and can
/// only fall to `SNAPSHOT_MIN_BUDGET_BYTES` (a provably-safe view), so this
/// bounds the encode work, not the correctness.
const SNAPSHOT_COMPRESS_MAX_ATTEMPTS: usize = 3;

/// zstd level for the snapshot body. Level 3 runs at hundreds of MB/s and
/// lands within a few percent of higher levels on hex-id node tables, so the
/// serve stays CPU-cheap while the wire shrinks ~3x.
const SNAPSHOT_ZSTD_LEVEL: i32 = 3;
/// `inline_output_files` hint carrying the client's write-time watermark:
/// when present, the response includes only entries written after it (a
/// delta), letting a long-lived client refresh without refetching the world.
pub const SNAPSHOT_AFTER_HINT: &str = "tuist-snapshot-after:";
/// Bound on cached per-namespace snapshot indexes (LRU by last use). A kura
/// node serves one tenant, so this comfortably covers every namespace that
/// actually requests snapshots.
const SNAPSHOT_CACHE_MAX_NAMESPACES: usize = 32;

/// The most entries a snapshot index holds, counted from the newest write.
/// This bounds the BUILD's memory the way the wire ceiling bounds the
/// response: reconciling against an unbounded keyspace held every manifest
/// in memory at once, and a namespace with weeks of un-expired CI churn
/// OOM-killed the pod on its first serve. With the cap, the scan buffer
/// (≤2x cap of manifests) plus the moved `current` map dominate the build's
/// transient memory — roughly cap x ~1KB.
const SNAPSHOT_INDEX_MAX_ENTRIES: usize = 100_000;

/// The transient memory a bounded index build is budgeted for, held as a
/// response-materialization-pool permit for the build's duration (adapted
/// down on nodes whose pool is smaller). Matches SNAPSHOT_INDEX_MAX_ENTRIES
/// at ~1KB per entry of scan-buffer + current-map peak, with headroom.
const SNAPSHOT_BUILD_BUDGET_BYTES: usize = 192 << 20;

/// How long a snapshot build waits for its memory-pool permit before
/// declining. Generous: the build is background work, and the pool drains as
/// in-flight responses complete — declining is only right when the node is
/// pinned at capacity for this entire window.
const SNAPSHOT_BUILD_PERMIT_WAIT: Duration = Duration::from_secs(600);

/// How old a cached snapshot index may grow before a serve kicks a
/// background reconcile. Requests never wait on it — they get the cached
/// view — so this bounds staleness, not latency; it composes with the
/// client's ~2-minute delta cadence.
const SNAPSHOT_RECONCILE_INTERVAL: Duration = Duration::from_secs(60);

/// How long a COLD serve (no cached index) waits for the build before
/// answering UNAVAILABLE. Long enough that an already-indexed namespace's
/// reconcile completes inline and small namespaces keep one-round-trip
/// semantics; far shorter than any client deadline, so a first-ever backfill
/// of a large namespace sheds requests fast instead of timing them all out.
const SNAPSHOT_COLD_SERVE_WAIT: Duration = Duration::from_secs(15);

/// Stranded-node floor below which a cached snapshot index skips compacting
/// its node table (the sweep rewrites every entry's index list).
const SNAPSHOT_COMPACT_MIN_GARBAGE: usize = 1024;

/// Minimum age before the presence gate's dead entries are cascade-deleted
/// from the store. Client publication orders blobs before the entry, but peer
/// replication and bootstrap may deliver an entry before its blobs — a young
/// entry with missing blobs is more likely mid-sync than stranded.
const SNAPSHOT_CASCADE_GRACE_MS: u64 = 60 * 60 * 1000;

fn snapshot_action_hash() -> &'static str {
    static HASH: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    HASH.get_or_init(|| hex::encode(Sha256::digest(SNAPSHOT_ACTION_KEY)))
}

struct SnapshotNode {
    llcas: Vec<u8>,
    blob_hash: [u8; 32],
    blob_size: u64,
    /// The blob's keyvalue artifact key, precomputed for the per-serve
    /// presence gate.
    blob_key: String,
}

struct SnapshotIndexEntry {
    version_ms: u64,
    nodes: Vec<u32>,
}

/// Incrementally maintained view of one namespace's action cache, so serving
/// a snapshot is a manifest-index reconcile plus an in-memory encode instead
/// of re-reading every stored ActionResult. Reconciliation (rather than
/// write-path hooks) keeps it correct under peer replication and eviction:
/// whatever wrote or removed an entry, the manifest keyspace is the truth
/// this diffs against.
struct NamespaceSnapshotIndex {
    nodes: Vec<SnapshotNode>,
    node_index: BTreeMap<Vec<u8>, u32>,
    entries: BTreeMap<[u8; 32], SnapshotIndexEntry>,
    estimated_bytes: usize,
    last_used: Instant,
    /// When the last successful reconcile finished. Serving reads this to
    /// decide whether the cached view is fresh enough to return as-is.
    reconciled_at: Instant,
}

impl NamespaceSnapshotIndex {
    fn new() -> Self {
        let mut index = Self {
            nodes: Vec::new(),
            node_index: BTreeMap::new(),
            entries: BTreeMap::new(),
            estimated_bytes: 0,
            last_used: Instant::now(),
            reconciled_at: Instant::now(),
        };
        index.recompute_estimated_bytes();
        index
    }

    #[cfg(test)]
    fn intern_node(&mut self, llcas: Vec<u8>, blob_hash: [u8; 32], blob_size: u64) -> u32 {
        self.try_intern_node(llcas, blob_hash, blob_size, usize::MAX)
            .expect("unbounded snapshot node admission should succeed")
    }

    fn try_intern_node(
        &mut self,
        llcas: Vec<u8>,
        blob_hash: [u8; 32],
        blob_size: u64,
        max_bytes: usize,
    ) -> Option<u32> {
        if let Some(&index) = self.node_index.get(&llcas) {
            return Some(index);
        }
        let blob_key = blob_key(&format!("{}/{}", hex::encode(blob_hash), blob_size));
        let added_bytes = estimated_snapshot_node_bytes(llcas.len(), blob_key.len());
        if self.estimated_bytes.saturating_add(added_bytes) > max_bytes {
            return None;
        }
        let index = self.nodes.len() as u32;
        self.nodes.push(SnapshotNode {
            llcas: llcas.clone(),
            blob_hash,
            blob_size,
            blob_key,
        });
        self.node_index.insert(llcas, index);
        self.estimated_bytes = self.estimated_bytes.saturating_add(added_bytes);
        Some(index)
    }

    fn remove_entry(&mut self, hash: &[u8; 32]) {
        if let Some(entry) = self.entries.remove(hash) {
            self.estimated_bytes = self
                .estimated_bytes
                .saturating_sub(estimated_snapshot_entry_bytes(entry.nodes.len()));
        }
    }

    fn insert_entry(&mut self, hash: [u8; 32], entry: SnapshotIndexEntry) {
        self.remove_entry(&hash);
        self.estimated_bytes = self
            .estimated_bytes
            .saturating_add(estimated_snapshot_entry_bytes(entry.nodes.len()));
        self.entries.insert(hash, entry);
    }

    fn estimated_bytes(&self) -> usize {
        self.estimated_bytes
    }

    fn recompute_estimated_bytes(&mut self) {
        self.estimated_bytes = std::mem::size_of::<Self>()
            .saturating_add(
                self.nodes
                    .iter()
                    .map(|node| {
                        estimated_snapshot_node_bytes(node.llcas.len(), node.blob_key.len())
                    })
                    .sum::<usize>(),
            )
            .saturating_add(
                self.entries
                    .values()
                    .map(|entry| estimated_snapshot_entry_bytes(entry.nodes.len()))
                    .sum::<usize>(),
            );
    }

    /// Rebuilds the node table around the nodes that live entries still
    /// reference. Entry churn (republished keys, evicted action results)
    /// strands nodes nothing references anymore; `intern_node` only ever
    /// appends, so without this sweep a long-cached index for an actively
    /// written namespace would grow its node table for the life of the
    /// process. Skipped while the garbage share is too small to be worth
    /// rewriting every entry's index list.
    fn compact_nodes(&mut self) {
        let mut remap: Vec<Option<u32>> = vec![None; self.nodes.len()];
        let mut live: u32 = 0;
        for entry in self.entries.values() {
            for &node in &entry.nodes {
                if remap[node as usize].is_none() {
                    remap[node as usize] = Some(live);
                    live += 1;
                }
            }
        }
        let garbage = self.nodes.len() - live as usize;
        if garbage < SNAPSHOT_COMPACT_MIN_GARBAGE || garbage * 2 < self.nodes.len() {
            return;
        }
        let old_nodes = std::mem::take(&mut self.nodes);
        let mut new_nodes: Vec<Option<SnapshotNode>> = Vec::new();
        new_nodes.resize_with(live as usize, || None);
        for (old_index, node) in old_nodes.into_iter().enumerate() {
            if let Some(new_index) = remap[old_index] {
                new_nodes[new_index as usize] = Some(node);
            }
        }
        self.nodes = new_nodes.into_iter().flatten().collect();
        self.node_index = self
            .nodes
            .iter()
            .enumerate()
            .map(|(index, node)| (node.llcas.clone(), index as u32))
            .collect();
        for entry in self.entries.values_mut() {
            for node in &mut entry.nodes {
                *node = remap[*node as usize].expect("live entry references a swept node");
            }
        }
        self.recompute_estimated_bytes();
    }

    /// Encodes a view for the wire, always zstd-compressed into the `TSNZ`
    /// envelope. The body is included up to the larger content budget then
    /// compressed; a body that compresses worse than budgeted is re-encoded
    /// with a smaller budget scaled from the observed ratio, bounded to a few
    /// tries that can only converge on the provably-safe minimum budget.
    ///
    /// Every snapshot client decodes `TSNZ`; the plain `TSNP` body still exists
    /// (see `encode_body`) only because a NEW client may hit an OLD server mid
    /// kura-mesh-roll and must read what those pods emit — this server never
    /// emits it. The client falls back to the per-key path on any body it can't
    /// decode, so there is nothing to negotiate.
    #[cfg(test)]
    fn encode(&self, after: u64) -> Vec<u8> {
        self.encode_with_budget(after, SNAPSHOT_CONTENT_BUDGET_BYTES)
    }

    fn encode_with_budget(&self, after: u64, max_content_bytes: usize) -> Vec<u8> {
        let mut budget = SNAPSHOT_CONTENT_BUDGET_BYTES.min(max_content_bytes.max(1));
        let minimum_budget = SNAPSHOT_MIN_BUDGET_BYTES.min(budget);
        let mut wire = Vec::new();
        for attempt in 0..SNAPSHOT_COMPRESS_MAX_ATTEMPTS {
            let body = self.encode_body(after, budget);
            wire = compress_snapshot(&body);
            if wire.len() <= SNAPSHOT_WIRE_MAX_BYTES {
                return wire;
            }
            // Overshot: this batch compressed worse than the budget assumed.
            // Scale the content budget down from the ratio we just measured
            // (strictly shrinks, since the compressed size is over the
            // ceiling) but never below the minimum budget, whose body is
            // guaranteed to compress under the wire ceiling. So the retry
            // converges on a safe view.
            let ratio = (body.len() as f64 / wire.len().max(1) as f64).max(1.0);
            let scaled = (SNAPSHOT_WIRE_MAX_BYTES as f64 * ratio * 0.9) as usize;
            budget = scaled.min(budget * 9 / 10).max(minimum_budget);
            if attempt + 1 == SNAPSHOT_COMPRESS_MAX_ATTEMPTS {
                tracing::warn!(
                    wire_bytes = wire.len(),
                    "action-cache snapshot still over the wire ceiling after compression retries; shipping the trimmed view"
                );
            }
        }
        wire
    }

    /// The uncompressed body, including keys until `budget` bytes of wire are
    /// accounted, with a response-local node table so every view is
    /// self-contained. `after == 0` is a full newest-first recency window (an
    /// oversized namespace degrades to "the most recent keys, the rest
    /// per-key"); a delta (`after > 0`) includes entries with
    /// `version_ms >= after` — inclusive, because millisecond timestamps are
    /// not unique and a write landing in an already-served millisecond must
    /// reappear (re-sent boundary entries merge idempotently client-side) —
    /// assembled oldest-first with the header watermark set to the newest
    /// entry actually included, so an overflowing delta paginates rather than
    /// skipping what it dropped. This is `encode`'s pre-compression input; it
    /// is also the exact `TSNP` layout old kura pods still serve on the wire.
    fn encode_body(&self, after: u64, budget: usize) -> Vec<u8> {
        let full = after == 0;
        let mut included: Vec<(&[u8; 32], &SnapshotIndexEntry)> = self
            .entries
            .iter()
            .filter(|(_, entry)| full || entry.version_ms >= after)
            .collect();
        if full {
            included.sort_by(|a, b| b.1.version_ms.cmp(&a.1.version_ms));
        } else {
            included.sort_by(|a, b| a.1.version_ms.cmp(&b.1.version_ms));
        }

        // Response-local node remap: only nodes the included keys reference.
        let total = included.len();
        let mut remap: BTreeMap<u32, u32> = BTreeMap::new();
        let mut response_nodes: Vec<u32> = Vec::new();
        let mut keys: Vec<(&[u8; 32], Vec<u32>)> = Vec::new();
        let mut estimated = 0usize;
        let mut watermark = after;
        for (hash, entry) in included {
            let mut key_cost = 32 + 4 + entry.nodes.len() * 4;
            for &node in &entry.nodes {
                if !remap.contains_key(&node) {
                    key_cost += 1 + self.nodes[node as usize].llcas.len() + 32 + 8;
                }
            }
            if estimated + key_cost > budget {
                if full {
                    // Recency window: this key is out, smaller older ones may fit.
                    continue;
                }
                // Pagination: everything from here on is newer than the
                // watermark being returned, so it arrives on the next delta.
                break;
            }
            estimated += key_cost;
            watermark = watermark.max(entry.version_ms);
            let indexes = entry
                .nodes
                .iter()
                .map(|&node| {
                    *remap.entry(node).or_insert_with(|| {
                        response_nodes.push(node);
                        (response_nodes.len() - 1) as u32
                    })
                })
                .collect();
            keys.push((hash, indexes));
        }
        let dropped = total - keys.len();
        if dropped > 0 {
            if full {
                tracing::warn!(
                    "action-cache snapshot truncated: {dropped} oldest keys over the size ceiling"
                );
            } else {
                tracing::info!(
                    "action-cache snapshot delta paginated: {dropped} newest keys deferred to the next delta"
                );
            }
        }

        let mut out = Vec::with_capacity(estimated + 32);
        out.extend_from_slice(b"TSNP");
        out.push(2);
        out.extend_from_slice(&watermark.to_le_bytes());
        out.extend_from_slice(&(response_nodes.len() as u32).to_le_bytes());
        for &node in &response_nodes {
            let node = &self.nodes[node as usize];
            out.push(node.llcas.len() as u8);
            out.extend_from_slice(&node.llcas);
            out.extend_from_slice(&node.blob_hash);
            out.extend_from_slice(&node.blob_size.to_le_bytes());
        }
        out.extend_from_slice(&(keys.len() as u32).to_le_bytes());
        for (hash, indexes) in &keys {
            out.extend_from_slice(*hash);
            out.extend_from_slice(&(indexes.len() as u32).to_le_bytes());
            for index in indexes {
                out.extend_from_slice(&index.to_le_bytes());
            }
        }
        out
    }
}

fn estimated_map_item_bytes(payload_bytes: usize) -> usize {
    payload_bytes
        .saturating_add(4 * std::mem::size_of::<usize>())
        .saturating_mul(3)
        / 2
}

fn estimated_snapshot_node_bytes(llcas_bytes: usize, blob_key_bytes: usize) -> usize {
    estimated_map_item_bytes(
        std::mem::size_of::<SnapshotNode>()
            .saturating_add(std::mem::size_of::<(Vec<u8>, u32)>())
            .saturating_add(llcas_bytes.saturating_mul(2))
            .saturating_add(blob_key_bytes),
    )
}

fn estimated_snapshot_entry_bytes(node_count: usize) -> usize {
    estimated_map_item_bytes(
        std::mem::size_of::<([u8; 32], SnapshotIndexEntry)>()
            .saturating_add(node_count.saturating_mul(std::mem::size_of::<u32>())),
    )
}

/// Wraps a `TSNP` body in the `TSNZ` envelope: magic, version, the u64
/// uncompressed length (so the client can size its buffer and reject a torn
/// payload), then the zstd stream. Only clients that advertise zstd support
/// receive this; everyone else gets the raw body.
fn compress_snapshot(body: &[u8]) -> Vec<u8> {
    let compressed = zstd::stream::encode_all(body, SNAPSHOT_ZSTD_LEVEL)
        .expect("zstd encode of an in-memory buffer cannot fail");
    let mut out = Vec::with_capacity(compressed.len() + 13);
    out.extend_from_slice(b"TSNZ");
    out.push(1);
    out.extend_from_slice(&(body.len() as u64).to_le_bytes());
    out.extend_from_slice(&compressed);
    out
}

fn digest_key(digest: &reapi::Digest) -> Result<String, Status> {
    if digest.size_bytes < 0 {
        return Err(Status::invalid_argument("digest size must be non-negative"));
    }
    if digest.hash.is_empty() {
        return Err(Status::invalid_argument("digest hash must be present"));
    }
    Ok(format!("{}/{}", digest.hash, digest.size_bytes))
}

fn require_sha256(digest_function: i32) -> Result<(), Status> {
    if digest_function == 0 || digest_function == reapi::digest_function::Value::Sha256 as i32 {
        return Ok(());
    }
    Err(Status::invalid_argument(
        "only SHA256 digests are supported",
    ))
}

fn namespace_from_instance(instance_name: &str) -> &str {
    if instance_name.is_empty() {
        DEFAULT_INSTANCE_NAME
    } else {
        instance_name
    }
}

fn rpc_status(code: i32, message: impl Into<String>) -> RpcStatus {
    RpcStatus {
        code,
        message: message.into(),
        details: Vec::new(),
    }
}

fn store_write_status(context: &str, error: String) -> Status {
    if is_outbox_full_error(&error) {
        Status::resource_exhausted(format!("{context}: {error}"))
    } else {
        Status::internal(format!("{context}: {error}"))
    }
}

fn rpc_status_from_grpc_status(status: &Status) -> RpcStatus {
    rpc_status(status.code() as i32, status.message())
}

// Metadata headers a gRPC client uses to declare the request account, mirroring
// the HTTP `tenant_id`/`account_handle` query params. The first non-empty match
// wins. This lets the extension enforce the same request-account-matches-server-
// tenant guard the HTTP path already has; the namespace still comes from the
// REAPI `instance_name`/`resource_name`, so it always matches what is stored.
const TENANT_HEADER_KEYS: &[&str] = &["x-kura-tenant-id", "x-tuist-account-handle"];

const REAPI_USAGE_ARTIFACT_KIND: &str = "reapi";

// The request-declared tenant, read straight from the metadata: the first
// non-empty `TENANT_HEADER_KEYS` value, taking the first value of a repeated
// key. Authorization (`grpc_extension_context`) and billing (`usage_tenant_id`)
// both resolve the tenant through this one function so a client that duplicates
// the header can never be authorized as one account and billed to another.
fn tenant_id_from_metadata(metadata: &tonic::metadata::MetadataMap) -> Option<String> {
    TENANT_HEADER_KEYS.iter().find_map(|key| {
        metadata
            .get(*key)
            .and_then(|value| value.to_str().ok())
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
    })
}

// The account a gRPC request is billed to. Mirrors the HTTP path, which keys
// usage off the per-request tenant; over gRPC that arrives as one of the
// `TENANT_HEADER_KEYS` metadata headers (the same headers the extension
// authorizes against, via the shared [`tenant_id_from_metadata`]). Falls back to
// the node's configured tenant when the client omits it, so REAPI bandwidth is
// always attributed rather than silently dropped.
fn usage_tenant_id(metadata: &tonic::metadata::MetadataMap, fallback_tenant_id: &str) -> String {
    tenant_id_from_metadata(metadata).unwrap_or_else(|| fallback_tenant_id.to_owned())
}

fn grpc_extension_context(
    server_tenant_id: &str,
    spec: &GrpcExtensionSpec<'_>,
    metadata: &tonic::metadata::MetadataMap,
    status_code: Option<u16>,
) -> ExtensionContext {
    let headers = metadata_to_btree(metadata);
    let tenant_id = tenant_id_from_metadata(metadata);
    ExtensionContext {
        transport: "grpc".into(),
        route: spec.route.to_owned(),
        method: "RPC".into(),
        operation: spec.operation.to_owned(),
        server_tenant_id: server_tenant_id.to_owned(),
        tenant_id,
        namespace_id: spec.namespace_id.map(ToOwned::to_owned),
        producer: spec.producer.map(ToOwned::to_owned),
        artifact_key: spec.artifact_key.clone(),
        artifact_hash: spec.artifact_hash.clone(),
        headers,
        query: BTreeMap::new(),
        status_code,
    }
}

fn metadata_to_btree(metadata: &tonic::metadata::MetadataMap) -> BTreeMap<String, String> {
    metadata
        .iter()
        .filter_map(|entry| match entry {
            tonic::metadata::KeyAndValueRef::Ascii(key, value) => value
                .to_str()
                .ok()
                .map(|value| (key.as_str().to_ascii_lowercase(), value.to_string())),
            tonic::metadata::KeyAndValueRef::Binary(_, _) => None,
        })
        .collect()
}

fn grpc_status_from_http_status(status: u16, message: &str) -> Status {
    match status {
        401 => Status::unauthenticated(message.to_owned()),
        403 => Status::permission_denied(message.to_owned()),
        404 => Status::not_found(message.to_owned()),
        400 => Status::invalid_argument(message.to_owned()),
        429 => Status::resource_exhausted(message.to_owned()),
        503 => Status::unavailable(message.to_owned()),
        _ if status >= 500 => Status::internal(message.to_owned()),
        _ => Status::permission_denied(message.to_owned()),
    }
}

#[derive(Debug, PartialEq, Eq)]
struct BlobResource {
    namespace_id: String,
    hash: String,
    size_bytes: u64,
    key: String,
}

fn parse_read_resource_name(resource_name: &str) -> Result<BlobResource, Status> {
    parse_blob_resource_name(resource_name, false)
}

fn parse_write_resource_name(resource_name: &str) -> Result<BlobResource, Status> {
    parse_blob_resource_name(resource_name, true)
}

fn parse_blob_resource_name(
    resource_name: &str,
    require_upload_prefix: bool,
) -> Result<BlobResource, Status> {
    let parts = resource_name
        .split('/')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>();
    let Some(blob_index) = parts.iter().rposition(|part| *part == "blobs") else {
        return Err(Status::invalid_argument(
            "resource_name must contain /blobs/",
        ));
    };
    if blob_index + 2 >= parts.len() {
        return Err(Status::invalid_argument(
            "resource_name is missing digest components",
        ));
    }
    let prefix = &parts[..blob_index];
    let namespace_parts = if prefix.len() >= 2 && prefix[prefix.len() - 2] == "uploads" {
        &prefix[..prefix.len() - 2]
    } else {
        if require_upload_prefix {
            return Err(Status::invalid_argument(
                "write resource_name must include uploads/{uuid}/blobs/{hash}/{size}",
            ));
        }
        prefix
    };
    let hash = parts[blob_index + 1].to_owned();
    let size_bytes = parts[blob_index + 2]
        .parse::<u64>()
        .map_err(|error| Status::invalid_argument(format!("invalid blob size: {error}")))?;
    let namespace_id = if namespace_parts.is_empty() {
        DEFAULT_INSTANCE_NAME.to_string()
    } else {
        namespace_parts.join("/")
    };
    // Key CAS blobs the same way as the digest-based paths (FindMissingBlobs,
    // BatchUpdateBlobs, BatchReadBlobs) which use `blob_key(&digest_key(..))` =
    // "blob/{hash}/{size}". Without the `blob/` prefix, blobs uploaded via ByteStream were
    // stored under "{hash}/{size}" and were invisible to FindMissingBlobs, so REAPI clients
    // (e.g. Bazel) treated the produced outputs as missing and re-executed the action.
    let key = blob_key(&format!("{hash}/{size_bytes}"));

    Ok(BlobResource {
        namespace_id,
        hash,
        size_bytes,
        key,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{convert::Infallible, time::Duration};
    use tower::ServiceExt;

    fn grpc_message(encoded_message_bytes: usize, byte: u8) -> Vec<u8> {
        let mut framed = Vec::with_capacity(GRPC_MESSAGE_HEADER_BYTES + encoded_message_bytes);
        framed.push(0);
        framed.extend_from_slice(&(encoded_message_bytes as u32).to_be_bytes());
        framed.extend(std::iter::repeat_n(byte, encoded_message_bytes));
        framed
    }

    #[test]
    fn grpc_write_admission_only_matches_mutating_methods() {
        assert!(is_reapi_write_path(BYTESTREAM_WRITE_PATH));
        assert!(is_reapi_write_path(ACTION_CACHE_UPDATE_PATH));
        assert!(is_reapi_write_path(CAS_BATCH_UPDATE_PATH));
        assert!(!is_reapi_write_path(
            "/build.bazel.remote.execution.v2.ContentAddressableStorage/BatchReadBlobs"
        ));
        assert!(!is_reapi_write_path(
            "/build.bazel.remote.execution.v2.Capabilities/GetCapabilities"
        ));
    }

    #[tokio::test]
    async fn grpc_write_admission_rejects_when_outbox_is_full_but_allows_reads() {
        let context = crate::test_support::test_context(|config| {
            config.outbox_max_depth = 1;
        })
        .await;
        context
            .state
            .store
            .enqueue(crate::replication::outbox_message::OutboxMessage {
                target: "http://peer".into(),
                operation: crate::replication::operation::ReplicationOperation::DeleteNamespace {
                    namespace_id: "ios".into(),
                    version_ms: 1,
                },
            })
            .expect("seed full outbox");
        let app = axum::Router::new()
            .fallback(|| async { axum::http::StatusCode::NO_CONTENT })
            .layer(axum::middleware::from_fn_with_state(
                context.state.clone(),
                reject_overloaded_grpc_writes,
            ));

        let rejected = app
            .clone()
            .oneshot(
                axum::http::Request::builder()
                    .uri(ACTION_CACHE_UPDATE_PATH)
                    .body(axum::body::Body::empty())
                    .expect("write request"),
            )
            .await
            .expect("write response");
        assert_eq!(rejected.status(), axum::http::StatusCode::OK);
        assert_eq!(rejected.headers().get("grpc-status").unwrap(), "8");

        let allowed = app
            .oneshot(
                axum::http::Request::builder()
                    .uri(
                        "/build.bazel.remote.execution.v2.ContentAddressableStorage/BatchReadBlobs",
                    )
                    .body(axum::body::Body::empty())
                    .expect("read request"),
            )
            .await
            .expect("read response");
        assert_eq!(allowed.status(), axum::http::StatusCode::NO_CONTENT);
    }

    fn bytestream_admission(
        hard_limit_bytes: u64,
    ) -> (crate::memory::MemoryController, ByteStreamWriteAdmission) {
        let metrics = crate::metrics::Metrics::new("local".into(), "tenant".into());
        let memory = crate::memory::MemoryController::with_runtime_limit(
            metrics.clone(),
            hard_limit_bytes.saturating_mul(2),
            hard_limit_bytes / 2,
            hard_limit_bytes,
        );
        memory.observe(0);
        let reservation = memory
            .try_reserve_foreground_stream_decode(0)
            .expect("zero-byte initial reservation should fit");
        let admission = ByteStreamWriteAdmission::new(reservation, metrics);
        (memory, admission)
    }

    #[tokio::test]
    async fn bytestream_admission_scans_fragmented_headers_before_forwarding() {
        let (memory, admission) = bytestream_admission(8 * 1024 * 1024);
        let header = grpc_message(1024, 0)[..GRPC_MESSAGE_HEADER_BYTES].to_vec();
        let frames = header
            .into_iter()
            .map(|byte| Ok::<_, Infallible>(Bytes::from(vec![byte])));
        let mut body = ByteStreamAdmissionBody::new(
            axum::body::Body::from_stream(futures_util::stream::iter(frames)),
            admission,
        );

        for _ in 0..GRPC_MESSAGE_HEADER_BYTES - 1 {
            body.frame()
                .await
                .expect("fragmented header frame")
                .expect("fragment should pass");
            assert_eq!(memory.transient_reserved_bytes(), 0);
        }
        body.frame()
            .await
            .expect("final header frame")
            .expect("completed header should pass");
        assert_eq!(memory.transient_reserved_bytes(), 2 * 1024);
        drop(body);
        assert_eq!(memory.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn bytestream_admission_uses_the_largest_message_in_a_shared_frame() {
        let (memory, admission) = bytestream_admission(8 * 1024 * 1024);
        let mut framed = grpc_message(512, 0x11);
        framed.extend_from_slice(&grpc_message(2048, 0x22));
        let mut body = ByteStreamAdmissionBody::new(axum::body::Body::from(framed), admission);

        body.frame()
            .await
            .expect("combined data frame")
            .expect("both messages should fit");

        assert_eq!(memory.transient_reserved_bytes(), 2 * 2048);
    }

    #[tokio::test]
    async fn bytestream_admission_rejects_growth_before_forwarding() {
        let (memory, admission) = bytestream_admission(1024 * 1024);
        let header = grpc_message(1024 * 1024, 0)[..GRPC_MESSAGE_HEADER_BYTES].to_vec();
        let mut body = ByteStreamAdmissionBody::new(axum::body::Body::from(header), admission);

        let error = body
            .frame()
            .await
            .expect("header frame")
            .expect_err("two retained copies exceed the hard limit");

        assert_eq!(error.code(), tonic::Code::ResourceExhausted);
        assert_eq!(memory.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn bytestream_admission_rejects_compressed_messages_before_forwarding() {
        let (memory, admission) = bytestream_admission(8 * 1024 * 1024);
        let mut framed = grpc_message(1024, 0);
        framed[0] = 1;
        let mut body = ByteStreamAdmissionBody::new(axum::body::Body::from(framed), admission);

        let error = body
            .frame()
            .await
            .expect("compressed frame")
            .expect_err("compressed messages must be rejected before decoding");

        assert_eq!(error.code(), tonic::Code::Unimplemented);
        assert_eq!(memory.transient_reserved_bytes(), 0);
    }

    #[test]
    fn actioncache_snapshot_index_encodes_full_and_delta_views() {
        let mut index = NamespaceSnapshotIndex::new();
        let shared = index.intern_node(vec![0xBB], [8; 32], 20);
        let a_root = index.intern_node(vec![0xAA, 0xAA], [7; 32], 10);
        let b_root = index.intern_node(vec![0xCC], [9; 32], 30);
        assert_eq!(index.intern_node(vec![0xBB], [8; 32], 20), shared, "dedup");
        index.entries.insert(
            [1; 32],
            SnapshotIndexEntry {
                version_ms: 100,
                nodes: vec![a_root, shared],
            },
        );
        index.entries.insert(
            [2; 32],
            SnapshotIndexEntry {
                version_ms: 200,
                nodes: vec![b_root, shared],
            },
        );

        let read_u32 = |bytes: &[u8], at: usize| {
            u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap()) as usize
        };

        // Full view: both keys, watermark = newest version, node table deduped.
        let full = index.encode_body(0, SNAPSHOT_MIN_BUDGET_BYTES);
        assert_eq!(&full[..4], b"TSNP");
        assert_eq!(full[4], 2);
        assert_eq!(u64::from_le_bytes(full[5..13].try_into().unwrap()), 200);
        assert_eq!(read_u32(&full, 13), 3, "three unique nodes");

        // Delta view: only the key strictly newer than the cursor, with a
        // self-contained node table (root + the shared node).
        let delta = index.encode_body(150, SNAPSHOT_MIN_BUDGET_BYTES);
        assert_eq!(u64::from_le_bytes(delta[5..13].try_into().unwrap()), 200);
        let node_count = read_u32(&delta, 13);
        assert_eq!(node_count, 2);
        // Walk past the node table to the key section.
        let mut at = 17;
        for _ in 0..node_count {
            let len = delta[at] as usize;
            at += 1 + len + 32 + 8;
        }
        assert_eq!(read_u32(&delta, at), 1, "one delta key");
        assert_eq!(&delta[at + 4..at + 36], &[2u8; 32]);

        // The cursor is INCLUSIVE: millisecond versions are not unique, so a
        // write landing in an already-served millisecond must reappear on the
        // next delta rather than being skipped until the full refresh. The
        // boundary key is re-sent (merge is idempotent client-side).
        let boundary = index.encode_body(200, SNAPSHOT_MIN_BUDGET_BYTES);
        assert_eq!(u64::from_le_bytes(boundary[5..13].try_into().unwrap()), 200);
        let node_count = read_u32(&boundary, 13);
        assert_eq!(node_count, 2, "boundary key re-sent");

        // Nothing at or past the cursor: an empty delta echoes it.
        let empty = index.encode_body(300, SNAPSHOT_MIN_BUDGET_BYTES);
        assert_eq!(u64::from_le_bytes(empty[5..13].try_into().unwrap()), 300);
        let node_count = read_u32(&empty, 13);
        assert_eq!(node_count, 0);
    }

    #[test]
    fn actioncache_snapshot_compressed_envelope_round_trips() {
        let mut index = NamespaceSnapshotIndex::new();
        let root = index.intern_node(vec![0xAA, 0xAA], [7; 32], 10);
        let shared = index.intern_node(vec![0xBB], [8; 32], 20);
        index.entries.insert(
            [1; 32],
            SnapshotIndexEntry {
                version_ms: 100,
                nodes: vec![root, shared],
            },
        );

        // The compressed wire is the TSNZ envelope: magic, version 1, the
        // uncompressed length, then the zstd stream that decodes to exactly
        // the uncompressed body the same view would have produced.
        let wire = index.encode(0);
        assert_eq!(&wire[..4], b"TSNZ");
        assert_eq!(wire[4], 1);
        let declared = u64::from_le_bytes(wire[5..13].try_into().unwrap()) as usize;
        let body = zstd::stream::decode_all(&wire[13..]).expect("zstd body should decode");
        assert_eq!(body.len(), declared, "declared length matches the body");
        assert_eq!(
            body,
            index.encode_body(0, SNAPSHOT_MIN_BUDGET_BYTES),
            "body equals the plain TSNP view"
        );
    }

    #[test]
    fn actioncache_snapshot_index_compacts_stranded_nodes() {
        let mut index = NamespaceSnapshotIndex::new();
        // A churned namespace: interned nodes whose entries are gone.
        for stranded in 0..SNAPSHOT_COMPACT_MIN_GARBAGE as u64 {
            index.intern_node(stranded.to_le_bytes().to_vec(), [3; 32], stranded);
        }
        let live = index.intern_node(vec![0xAA], [7; 32], 10);
        index.entries.insert(
            [1; 32],
            SnapshotIndexEntry {
                version_ms: 100,
                nodes: vec![live],
            },
        );

        index.compact_nodes();

        assert_eq!(index.nodes.len(), 1, "stranded nodes swept");
        assert_eq!(index.node_index.len(), 1);
        let entry = index.entries.get(&[1; 32]).unwrap();
        assert_eq!(entry.nodes, vec![0], "entry remapped onto the new table");
        assert_eq!(index.nodes[0].llcas, vec![0xAA]);
        assert_eq!(index.node_index.get(&vec![0xAA]).copied(), Some(0));
        // The rebuilt table keeps serving: the full view carries the live key.
        let full = index.encode_body(0, SNAPSHOT_MIN_BUDGET_BYTES);
        assert_eq!(u64::from_le_bytes(full[5..13].try_into().unwrap()), 100);
    }

    #[test]
    fn actioncache_snapshot_index_rejects_nodes_before_its_byte_budget() {
        let mut index = NamespaceSnapshotIndex::new();
        let budget = 8 * 1024;
        let mut admitted = 0_u64;

        loop {
            let llcas = vec![admitted as u8; 128];
            if index
                .try_intern_node(llcas, [7; 32], admitted, budget)
                .is_none()
            {
                break;
            }
            admitted += 1;
        }

        assert!(admitted > 0);
        assert!(index.estimated_bytes() <= budget);
        assert!(
            index
                .try_intern_node(vec![0xFF; 128], [8; 32], 1, budget)
                .is_none(),
            "a rejected node must stay rejected without increasing the budget"
        );
        assert!(index.estimated_bytes() <= budget);
    }

    #[test]
    fn actioncache_snapshot_cache_trims_retained_bytes_to_pressure_target() {
        let metrics = crate::metrics::Metrics::new("eu-west".into(), "tenant".into());
        let cache = SnapshotCache::new(16 * 1024);
        for namespace in ["old", "new"] {
            let mut index = NamespaceSnapshotIndex::new();
            let node = index.intern_node(vec![namespace.len() as u8; 512], [7; 32], 1);
            index.insert_entry(
                [namespace.len() as u8; 32],
                SnapshotIndexEntry {
                    version_ms: namespace.len() as u64,
                    nodes: vec![node],
                },
            );
            cache
                .indexes
                .lock()
                .unwrap()
                .insert(namespace.to_owned(), index);
            cache
                .served_full
                .lock()
                .unwrap()
                .insert(namespace.to_owned(), std::sync::Arc::new(vec![0; 2 * 1024]));
        }

        cache.trim_to(3 * 1024, "test", &metrics);

        assert!(cache.stats().bytes <= 3 * 1024);
    }

    /// Marks a cached index stale so the next serve kicks a reconcile
    /// (serves return the cached view and reconcile in the background once
    /// the freshness window lapses).
    fn backdate_snapshot_index(service: &ReapiService, namespace_id: &str) {
        if let Some(index) = service
            .snapshot_cache
            .indexes
            .lock()
            .unwrap()
            .get_mut(namespace_id)
        {
            index.reconciled_at = Instant::now() - 2 * SNAPSHOT_RECONCILE_INTERVAL;
        }
    }

    /// Waits until the namespace's cached index satisfies `done` (background
    /// reconciles land asynchronously after a stale serve).
    async fn wait_for_snapshot_index<F>(service: &ReapiService, namespace_id: &str, done: F)
    where
        F: Fn(&NamespaceSnapshotIndex) -> bool,
    {
        for _ in 0..400 {
            {
                let indexes = service.snapshot_cache.indexes.lock().unwrap();
                if indexes.get(namespace_id).map(&done).unwrap_or(false) {
                    return;
                }
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
        panic!("background reconcile did not reach the expected state");
    }

    #[tokio::test]
    async fn snapshot_serve_cascade_deletes_stranded_entries_past_grace() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let store = &context.state.store;
        let uploads = context.state.config.tmp_dir.join("uploads");
        std::fs::create_dir_all(&uploads).expect("uploads dir should create");

        async fn write_artifact(
            store: &crate::store::Store,
            uploads: &std::path::Path,
            key: &str,
            bytes: &[u8],
            version_ms: u64,
        ) {
            let path = uploads.join(key.replace('/', "-"));
            std::fs::write(&path, bytes).expect("source should write");
            store
                .apply_replicated_artifact_from_path(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    "application/octet-stream",
                    &path,
                    version_ms,
                )
                .await
                .expect("artifact should persist");
        }
        fn entry_bytes(llcas: &[u8], blob_hash: [u8; 32]) -> Vec<u8> {
            reapi::ActionResult {
                output_files: vec![reapi::OutputFile {
                    path: hex::encode(llcas),
                    digest: Some(reapi::Digest {
                        hash: hex::encode(blob_hash),
                        size_bytes: 7,
                    }),
                    ..Default::default()
                }],
                ..Default::default()
            }
            .encode_to_vec()
        }

        let now = crate::utils::now_ms();
        let old = now - 2 * SNAPSHOT_CASCADE_GRACE_MS;
        let evicted_blob = [0x11u8; 32];
        let live_blob = [0x22u8; 32];
        let evicted_blob_key = blob_key(&format!("{}/7", hex::encode(evicted_blob)));
        let live_blob_key = blob_key(&format!("{}/7", hex::encode(live_blob)));
        let stranded_key = format!("action_cache/{}/10", hex::encode([0x44u8; 32]));
        let young_key = format!("action_cache/{}/10", hex::encode([0x55u8; 32]));
        let live_key = format!("action_cache/{}/10", hex::encode([0x66u8; 32]));
        write_artifact(store, &uploads, &evicted_blob_key, b"payload", old).await;
        write_artifact(store, &uploads, &live_blob_key, b"payload", old).await;
        write_artifact(
            store,
            &uploads,
            &stranded_key,
            &entry_bytes(&[0xAB, 0xCD], evicted_blob),
            old,
        )
        .await;
        write_artifact(
            store,
            &uploads,
            &young_key,
            &entry_bytes(&[0xAB, 0xCD], evicted_blob),
            now,
        )
        .await;
        write_artifact(
            store,
            &uploads,
            &live_key,
            &entry_bytes(&[0xEE, 0xFF], live_blob),
            old,
        )
        .await;

        service
            .serve_actioncache_snapshot("ios", 0)
            .await
            .expect("first serve should succeed");
        assert_eq!(
            service.snapshot_cache.indexes.lock().unwrap()["ios"]
                .entries
                .len(),
            3,
            "all three entries advertised while their blobs exist"
        );

        // Evict the shared blob the way segment eviction would: manifest gone.
        let blob_manifest = store
            .manifest(&crate::utils::artifact_storage_id(
                ArtifactProducer::Reapi,
                "test-tenant",
                "ios",
                &evicted_blob_key,
            ))
            .expect("manifest read should succeed")
            .expect("blob manifest should exist");
        store
            .delete_artifact_metadata(&[blob_manifest])
            .expect("blob eviction should succeed");

        backdate_snapshot_index(&service, "ios");
        service
            .serve_actioncache_snapshot("ios", 0)
            .await
            .expect("second serve should succeed");
        wait_for_snapshot_index(&service, "ios", |index| index.entries.len() == 1).await;
        let exists = |key: &str| {
            store
                .artifact_manifest_exists(ArtifactProducer::Reapi, "ios", key)
                .expect("existence check should succeed")
        };
        assert!(
            !exists(&stranded_key),
            "the stranded entry past the grace window is cascade-deleted"
        );
        assert!(
            exists(&young_key),
            "a young stranded entry is kept — its blobs may still be mid-replication"
        );
        assert!(exists(&live_key));
    }

    #[tokio::test]
    async fn per_key_serve_gates_entries_with_evicted_outputs() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let store = &context.state.store;
        let uploads = context.state.config.tmp_dir.join("uploads");
        std::fs::create_dir_all(&uploads).expect("uploads dir should create");

        async fn write_artifact(
            store: &crate::store::Store,
            uploads: &std::path::Path,
            key: &str,
            bytes: &[u8],
            version_ms: u64,
        ) {
            let path = uploads.join(key.replace('/', "-"));
            std::fs::write(&path, bytes).expect("source should write");
            store
                .apply_replicated_artifact_from_path(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    "application/octet-stream",
                    &path,
                    version_ms,
                )
                .await
                .expect("artifact should persist");
        }
        fn entry_bytes(blob_hash: [u8; 32]) -> Vec<u8> {
            reapi::ActionResult {
                output_files: vec![reapi::OutputFile {
                    path: hex::encode([0xAB, 0xCD]),
                    digest: Some(reapi::Digest {
                        hash: hex::encode(blob_hash),
                        size_bytes: 7,
                    }),
                    ..Default::default()
                }],
                ..Default::default()
            }
            .encode_to_vec()
        }
        fn get_request(action_hash: [u8; 32]) -> Request<reapi::GetActionResultRequest> {
            Request::new(reapi::GetActionResultRequest {
                instance_name: "ios".into(),
                action_digest: Some(reapi::Digest {
                    hash: hex::encode(action_hash),
                    size_bytes: 10,
                }),
                ..Default::default()
            })
        }

        let now = crate::utils::now_ms();
        let old = now - 2 * SNAPSHOT_CASCADE_GRACE_MS;
        let live_blob = [0x11u8; 32];
        let missing_blob = [0x22u8; 32];
        let live_blob_key = blob_key(&format!("{}/7", hex::encode(live_blob)));
        let live_action = [0x44u8; 32];
        let dead_action = [0x55u8; 32];
        let young_dead_action = [0x66u8; 32];
        let live_key = format!("action_cache/{}/10", hex::encode(live_action));
        let dead_key = format!("action_cache/{}/10", hex::encode(dead_action));
        let young_dead_key = format!("action_cache/{}/10", hex::encode(young_dead_action));
        write_artifact(store, &uploads, &live_blob_key, b"payload", old).await;
        write_artifact(store, &uploads, &live_key, &entry_bytes(live_blob), old).await;
        write_artifact(store, &uploads, &dead_key, &entry_bytes(missing_blob), old).await;
        write_artifact(
            store,
            &uploads,
            &young_dead_key,
            &entry_bytes(missing_blob),
            now,
        )
        .await;

        service
            .get_action_result(get_request(live_action))
            .await
            .expect("an entry with present outputs serves");

        let status = service
            .get_action_result(get_request(dead_action))
            .await
            .expect_err("an entry with evicted outputs must not serve");
        assert_eq!(status.code(), tonic::Code::NotFound);
        let exists = |key: &str| {
            store
                .artifact_manifest_exists(ArtifactProducer::Reapi, "ios", key)
                .expect("existence check should succeed")
        };
        assert!(
            !exists(&dead_key),
            "a dead entry past the grace window is deleted on serve"
        );

        let status = service
            .get_action_result(get_request(young_dead_action))
            .await
            .expect_err("a young dead entry must not serve either");
        assert_eq!(status.code(), tonic::Code::NotFound);
        assert!(
            exists(&young_dead_key),
            "a young dead entry is kept — its blobs may still be mid-replication"
        );
    }

    #[tokio::test]
    async fn snapshot_index_build_survives_an_aborted_request() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let store = &context.state.store;
        let uploads = context.state.config.tmp_dir.join("uploads");
        std::fs::create_dir_all(&uploads).expect("uploads dir should create");
        let blob_hash = [0x11u8; 32];
        let blob_key_name = blob_key(&format!("{}/7", hex::encode(blob_hash)));
        let entry_key = format!("action_cache/{}/10", hex::encode([0x44u8; 32]));
        let entry_bytes = reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: hex::encode([0xABu8, 0xCD]),
                digest: Some(reapi::Digest {
                    hash: hex::encode(blob_hash),
                    size_bytes: 7,
                }),
                ..Default::default()
            }],
            ..Default::default()
        }
        .encode_to_vec();
        for (key, bytes) in [
            (&blob_key_name, b"payload".to_vec()),
            (&entry_key, entry_bytes.clone()),
        ] {
            let path = uploads.join(key.replace('/', "-"));
            std::fs::write(&path, &bytes).expect("source should write");
            store
                .apply_replicated_artifact_from_path(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    "application/octet-stream",
                    &path,
                    100,
                )
                .await
                .expect("artifact should persist");
        }

        // Abort the request before the build completes: one poll starts the
        // detached build, then the request future is dropped — the build must
        // keep running and cache the index anyway. Dropping it with the
        // request meant every retry rebuilt from scratch, and a gateway
        // timeout made the snapshot permanently unservable.
        let mut serve = Box::pin(service.serve_actioncache_snapshot("ios", 0));
        let first = futures_util::future::poll_immediate(serve.as_mut()).await;
        assert!(first.is_none(), "the first poll leaves the build in flight");
        drop(serve);
        let mut cached = false;
        for _ in 0..400 {
            if service
                .snapshot_cache
                .indexes
                .lock()
                .unwrap()
                .contains_key("ios")
            {
                cached = true;
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
        assert!(
            cached,
            "the detached build cached the index after the abort"
        );
        assert!(
            service.snapshot_cache.builds.lock().unwrap().is_empty(),
            "the finished build removed itself from the in-flight map"
        );
        let bytes = service
            .serve_actioncache_snapshot("ios", 0)
            .await
            .expect("the follow-up request serves from the cached index");
        assert_eq!(&bytes[..4], b"TSNZ");

        // A later publish must reach the next serve: every serve reconciles
        // afresh (a memoized index served forever is the production-staleness
        // failure this guards against).
        let late_key = format!("action_cache/{}/10", hex::encode([0x55u8; 32]));
        let late_path = uploads.join("late");
        std::fs::write(&late_path, &entry_bytes).expect("late entry should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                &late_key,
                "application/octet-stream",
                &late_path,
                2_000,
            )
            .await
            .expect("late entry should persist");
        backdate_snapshot_index(&service, "ios");
        service
            .serve_actioncache_snapshot("ios", 0)
            .await
            .expect("the post-publish serve succeeds");
        wait_for_snapshot_index(&service, "ios", |index| {
            index.entries.len() == 2
                && index
                    .entries
                    .values()
                    .any(|entry| entry.version_ms == 2_000)
        })
        .await;
    }

    // Scale validation for the bounded index build: a namespace more than
    // twice the entry cap exercises the mid-scan shed, the cap, and the
    // streaming loads end to end. Run manually (writes 220k artifacts):
    //   /usr/bin/time -l cargo test --release -- --ignored snapshot_index_build_is_bounded
    // and eyeball the max RSS — the serve must not add hundreds of MB.
    #[tokio::test(flavor = "multi_thread")]
    #[ignore = "scale validation; run manually with --ignored"]
    async fn snapshot_index_build_is_bounded_on_a_large_namespace() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let store = &context.state.store;
        let uploads = context.state.config.tmp_dir.join("uploads");
        std::fs::create_dir_all(&uploads).expect("uploads dir should create");
        let blob_hash = [0x11u8; 32];
        let blob_key_name = blob_key(&format!("{}/7", hex::encode(blob_hash)));
        let blob_path = uploads.join("blob");
        std::fs::write(&blob_path, b"payload").expect("blob should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                &blob_key_name,
                "application/octet-stream",
                &blob_path,
                1,
            )
            .await
            .expect("blob should persist");
        let entry_bytes = reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: hex::encode([0xABu8, 0xCD]),
                digest: Some(reapi::Digest {
                    hash: hex::encode(blob_hash),
                    size_bytes: 7,
                }),
                ..Default::default()
            }],
            ..Default::default()
        }
        .encode_to_vec();
        let entry_path = uploads.join("entry");
        const ENTRIES: u64 = 220_000;
        for version in 1..=ENTRIES {
            std::fs::write(&entry_path, &entry_bytes).expect("entry should write");
            let mut hash = [0u8; 32];
            hash[..8].copy_from_slice(&version.to_be_bytes());
            store
                .apply_replicated_artifact_from_path(
                    ArtifactProducer::Reapi,
                    "ios",
                    &format!("action_cache/{}/10", hex::encode(hash)),
                    "application/octet-stream",
                    &entry_path,
                    version,
                )
                .await
                .expect("entry should persist");
        }

        let bytes = service
            .serve_actioncache_snapshot("ios", 0)
            .await
            .expect("serve should succeed on the large namespace");
        assert_eq!(&bytes[..4], b"TSNZ");
        let indexes = service.snapshot_cache.indexes.lock().unwrap();
        let index = &indexes["ios"];
        assert_eq!(
            index.entries.len(),
            SNAPSHOT_INDEX_MAX_ENTRIES,
            "the index holds exactly the cap"
        );
        assert!(
            index
                .entries
                .values()
                .all(|entry| entry.version_ms > (ENTRIES - SNAPSHOT_INDEX_MAX_ENTRIES as u64)),
            "the cap kept the newest entries"
        );
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn snapshot_build_waits_for_pool_headroom_instead_of_declining() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let store = &context.state.store;
        let uploads = context.state.config.tmp_dir.join("uploads");
        std::fs::create_dir_all(&uploads).expect("uploads dir should create");
        let entry_key = format!("action_cache/{}/10", hex::encode([0x44u8; 32]));
        let entry_path = uploads.join("entry");
        let entry_bytes = reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: hex::encode([0xABu8, 0xCD]),
                digest: Some(reapi::Digest {
                    hash: hex::encode([0x11u8; 32]),
                    size_bytes: 7,
                }),
                ..Default::default()
            }],
            ..Default::default()
        }
        .encode_to_vec();
        std::fs::write(&entry_path, &entry_bytes).expect("entry should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                &entry_key,
                "application/octet-stream",
                &entry_path,
                100,
            )
            .await
            .expect("entry should persist");
        let blob_path = uploads.join("blob");
        std::fs::write(&blob_path, b"payload").expect("blob should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                &blob_key(&format!("{}/7", hex::encode([0x11u8; 32]))),
                "application/octet-stream",
                &blob_path,
                100,
            )
            .await
            .expect("blob should persist");

        // Exhaust the pool: the old try-acquire declined the build here —
        // which, under the per-key load a stale snapshot causes, parked the
        // index stale indefinitely. The build must wait instead.
        let pool = context.state.memory.reapi_materialization_pool_bytes();
        let hog = context
            .state
            .memory
            .try_acquire_reapi_materialization(pool)
            .expect("pool should be acquirable when idle");
        let serve = tokio::spawn({
            let service = service.clone();
            async move { service.serve_actioncache_snapshot("ios", 0).await }
        });
        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
        assert!(
            !serve.is_finished(),
            "the build waits for headroom rather than declining"
        );
        drop(hog);
        let bytes = tokio::time::timeout(std::time::Duration::from_secs(30), serve)
            .await
            .expect("build should complete once the pool frees")
            .expect("serve task should not panic")
            .expect("serve should succeed");
        assert_eq!(&bytes[..4], b"TSNZ");
    }

    #[tokio::test]
    async fn snapshot_serve_returns_the_cached_full_view_while_the_index_is_out_for_reconcile() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let store = &context.state.store;
        let uploads = context.state.config.tmp_dir.join("uploads");
        std::fs::create_dir_all(&uploads).expect("uploads dir should create");
        let entry_key = format!("action_cache/{}/10", hex::encode([0x44u8; 32]));
        let entry_path = uploads.join("entry");
        let entry_bytes = reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: hex::encode([0xABu8, 0xCD]),
                digest: Some(reapi::Digest {
                    hash: hex::encode([0x11u8; 32]),
                    size_bytes: 7,
                }),
                ..Default::default()
            }],
            ..Default::default()
        }
        .encode_to_vec();
        std::fs::write(&entry_path, &entry_bytes).expect("entry should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                &entry_key,
                "application/octet-stream",
                &entry_path,
                100,
            )
            .await
            .expect("entry should persist");
        let blob_path = uploads.join("blob");
        std::fs::write(&blob_path, b"payload").expect("blob should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                &blob_key(&format!("{}/7", hex::encode([0x11u8; 32]))),
                "application/octet-stream",
                &blob_path,
                100,
            )
            .await
            .expect("blob should persist");

        // A full serve builds the index and caches the full view.
        let first = service
            .serve_actioncache_snapshot("ios", 0)
            .await
            .expect("first serve builds the index");
        assert_eq!(&first[..4], b"TSNZ");
        assert!(
            service
                .snapshot_cache
                .served_full
                .lock()
                .unwrap()
                .contains_key("ios"),
            "the full view is cached for the rebuild window"
        );

        // Simulate a reconcile in flight: the index is OUT of the map. Exhaust
        // the pool so the serve's kicked rebuild cannot reinsert it before the
        // assertion.
        service.snapshot_cache.indexes.lock().unwrap().remove("ios");
        let pool = context.state.memory.reapi_materialization_pool_bytes();
        let _hog = context
            .state
            .memory
            .try_acquire_reapi_materialization(pool.saturating_sub(first.len()))
            .expect("pool should be acquirable when idle");

        // A full serve now finds no index but returns the cached full view
        // immediately, rather than shedding a cold client to UNAVAILABLE while
        // the rebuild runs. Before `served_full`, this fell to the cold path.
        let stale = tokio::time::timeout(
            std::time::Duration::from_secs(2),
            service.serve_actioncache_snapshot("ios", 0),
        )
        .await
        .expect("serve must not block on the stalled rebuild")
        .expect("serve returns the cached full view, not UNAVAILABLE");
        assert_eq!(stale, first, "serves the exact cached full view");
    }

    #[tokio::test(start_paused = true)]
    async fn snapshot_cold_serve_sheds_to_unavailable_while_the_build_runs() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        // Stall the build at its memory permit: with no cached index the
        // serve must answer UNAVAILABLE within its bound instead of pinning
        // the request to the build — production builds ran for tens of
        // minutes and walked every client fetch into its deadline.
        let pool = context.state.memory.reapi_materialization_pool_bytes();
        let hog = context
            .state
            .memory
            .try_acquire_reapi_materialization(pool)
            .expect("pool should be acquirable when idle");
        let status = service
            .serve_actioncache_snapshot("ios", 0)
            .await
            .expect_err("cold serve should shed while the build is stuck");
        assert_eq!(status.code(), tonic::Code::Unavailable);
        // Once the pool frees the same build completes in the background and
        // the next fetch is served from the index it produced.
        drop(hog);
        let bytes = tokio::time::timeout(
            std::time::Duration::from_secs(120),
            service.serve_actioncache_snapshot("ios", 0),
        )
        .await
        .expect("serve should not hang once the pool frees")
        .expect("serve should succeed after the build completes");
        assert_eq!(&bytes[..4], b"TSNZ");
    }

    use tokio::net::TcpListener;
    use tonic::body::Body as TonicBody;

    use crate::{
        artifact::producer::ArtifactProducer,
        failpoints::{FailpointAction, FailpointName},
        test_support::{TestContext, test_context, test_context_with_extension},
    };

    // Serves the REAPI routes over a plaintext h2c listener for the tests
    // below. axum::serve's auto builder speaks HTTP/2 prior knowledge, which
    // is what the tonic clients connect with.
    async fn serve_routes(
        listener: TcpListener,
        state: SharedState,
        shutdown: impl std::future::Future<Output = ()> + Send + 'static,
    ) {
        let _ = axum::serve(listener, routes(state).into_make_service())
            .with_graceful_shutdown(shutdown)
            .await;
    }

    #[tokio::test]
    async fn grpc_request_accounting_layer_keeps_guard_until_response_body_drops() {
        let context = test_context(|_| {}).await;
        let layer = GrpcRequestAccountingLayer {
            state: context.state.clone(),
        };
        let mut service = layer.layer(tower::service_fn(
            |_request: http::Request<TonicBody>| async {
                Ok::<_, Infallible>(http::Response::new(TonicBody::empty()))
            },
        ));

        let response = service
            .call(http::Request::new(TonicBody::empty()))
            .await
            .expect("accounting layer should pass through service response");

        assert_eq!(context.state.runtime.grpc_inflight(), 1);
        assert_eq!(context.state.runtime.public_inflight(), 1);

        drop(response);

        assert_eq!(context.state.runtime.grpc_inflight(), 0);
        assert_eq!(context.state.runtime.public_inflight(), 0);
    }

    // Regression test for the missing flush in the ByteStream `write` handler. The
    // handler streams chunks into a temp file with `write_all` and then persists it by
    // re-opening the path on a separate descriptor (stat + copy into a segment).
    // `tokio::fs::File` buffers writes and flushes lazily, so without an explicit flush
    // the persist read races the flush and intermittently fails with
    // "appended N bytes, expected M" — which silently broke remote caching of every
    // action that uploads many blobs concurrently (notably cargo build scripts' directory
    // outputs, e.g. librocksdb-sys). This drives the real gRPC handler with many
    // concurrent multi-chunk uploads and asserts each persists and reads back intact.
    #[tokio::test]
    async fn bytestream_writes_persist_completely_under_concurrency() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

        let context = test_context(|_| {}).await;
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let addr = listener.local_addr().expect("listener addr");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let server_state = context.state.clone();
        let server = tokio::spawn(async move {
            serve_routes(listener, server_state, async move {
                let _ = shutdown_rx.await;
            })
            .await
        });

        let endpoint = format!("http://{addr}");
        let mut channel = None;
        for _ in 0..50 {
            match tonic::transport::Endpoint::from_shared(endpoint.clone())
                .expect("valid endpoint")
                .connect()
                .await
            {
                Ok(connected) => {
                    channel = Some(connected);
                    break;
                }
                Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
            }
        }
        let channel = channel.expect("gRPC server should accept connections");

        let concurrency = 24u32;
        let chunk_size = 32 * 1024;
        let mut writers = Vec::new();
        for index in 0..concurrency {
            let mut client = ByteStreamClient::new(channel.clone());
            writers.push(tokio::spawn(async move {
                // Per-blob-distinct, multi-chunk content so each upload spans many
                // `write_all` calls (leaving buffered bytes for the flush to race).
                let blob: Vec<u8> = (0..384 * 1024u32)
                    .map(|byte| byte.wrapping_mul(31).wrapping_add(index) as u8)
                    .collect();
                let hash = hex::encode(Sha256::digest(&blob));
                let resource = format!("uploads/upload-{index}/blobs/{hash}/{}", blob.len());
                let mut requests = Vec::new();
                let mut offset = 0usize;
                while offset < blob.len() {
                    let end = (offset + chunk_size).min(blob.len());
                    requests.push(bytestream::WriteRequest {
                        resource_name: if offset == 0 {
                            resource.clone()
                        } else {
                            String::new()
                        },
                        write_offset: offset as i64,
                        finish_write: end == blob.len(),
                        data: blob[offset..end].to_vec(),
                    });
                    offset = end;
                }
                let committed = client
                    .write(tokio_stream::iter(requests))
                    .await
                    .expect("concurrent ByteStream write should persist")
                    .into_inner()
                    .committed_size;
                assert_eq!(committed as usize, blob.len());
                (hash, blob)
            }));
        }

        let mut reader = ByteStreamClient::new(channel.clone());
        for writer in writers {
            let (hash, blob) = writer.await.expect("write task should not panic");
            let mut stream = reader
                .read(bytestream::ReadRequest {
                    resource_name: format!("blobs/{hash}/{}", blob.len()),
                    read_offset: 0,
                    read_limit: 0,
                })
                .await
                .expect("blob should be readable back")
                .into_inner();
            let mut roundtrip = Vec::new();
            while let Some(chunk) = stream.message().await.expect("read chunk") {
                roundtrip.extend_from_slice(&chunk.data);
            }
            assert_eq!(roundtrip, blob, "persisted blob must match the upload");
        }

        let _ = shutdown_tx.send(());
        let _ = server.await;
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn bytestream_accepts_messages_larger_than_the_file_cache_window() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

        let context = test_context(|_| {}).await;
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let addr = listener.local_addr().expect("listener addr");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let server_state = context.state.clone();
        let server = tokio::spawn(async move {
            serve_routes(listener, server_state, async move {
                let _ = shutdown_rx.await;
            })
            .await
        });

        let endpoint = format!("http://{addr}");
        let channel = tonic::transport::Endpoint::from_shared(endpoint)
            .expect("valid endpoint")
            .connect()
            .await
            .expect("gRPC server should accept connections");
        let blob = vec![0xA5; 20 * 1024 * 1024];
        let hash = hex::encode(Sha256::digest(&blob));
        let resource = format!("uploads/large-message/blobs/{hash}/{}", blob.len());

        let committed = ByteStreamClient::new(channel)
            .write(tokio_stream::iter([bytestream::WriteRequest {
                resource_name: resource,
                write_offset: 0,
                finish_write: true,
                data: blob,
            }]))
            .await
            .expect("the existing decode limit should remain accepted")
            .into_inner()
            .committed_size;
        assert_eq!(committed, 20 * 1024 * 1024);

        let _ = shutdown_tx.send(());
        let _ = server.await;
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn shared_bytestream_connection_rejects_pressure_without_deadlock() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

        let context = test_context(|config| {
            config.memory_limit_bytes = 512 * 1024 * 1024;
            config.memory_soft_limit_bytes = 128 * 1024 * 1024;
            config.memory_hard_limit_bytes = 256 * 1024 * 1024;
        })
        .await;
        context.state.memory.observe(256 * 1024 * 1024);
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let addr = listener.local_addr().expect("listener addr");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let server_state = context.state.clone();
        let server = tokio::spawn(async move {
            serve_routes(listener, server_state, async move {
                let _ = shutdown_rx.await;
            })
            .await
        });

        let endpoint = format!("http://{addr}");
        let channel = tonic::transport::Endpoint::from_shared(endpoint)
            .expect("valid endpoint")
            .connect()
            .await
            .expect("gRPC server should accept connections");
        let mut rejected_writers = Vec::new();
        for index in 0..24_u8 {
            let mut client = ByteStreamClient::new(channel.clone());
            rejected_writers.push(tokio::spawn(async move {
                let blob = vec![index; 1024 * 1024];
                let hash = hex::encode(Sha256::digest(&blob));
                let resource = format!("uploads/pressure-{index}/blobs/{hash}/{}", blob.len());
                client
                    .write(tokio_stream::iter([bytestream::WriteRequest {
                        resource_name: resource,
                        write_offset: 0,
                        finish_write: true,
                        data: blob,
                    }]))
                    .await
            }));
        }

        tokio::time::timeout(Duration::from_secs(5), async {
            for writer in rejected_writers {
                let error = writer
                    .await
                    .expect("writer task should not panic")
                    .expect_err("hard pressure should reject before decoding");
                assert_eq!(error.code(), tonic::Code::ResourceExhausted);
            }
        })
        .await
        .expect("all streams on the shared connection should reject promptly");

        context.state.memory.observe(0);
        let blob = vec![0xA5; 1024 * 1024];
        let hash = hex::encode(Sha256::digest(&blob));
        let resource = format!("uploads/recovered/blobs/{hash}/{}", blob.len());
        let committed = ByteStreamClient::new(channel)
            .write(tokio_stream::iter([bytestream::WriteRequest {
                resource_name: resource,
                write_offset: 0,
                finish_write: true,
                data: blob,
            }]))
            .await
            .expect("the shared connection should remain usable after rejection")
            .into_inner()
            .committed_size;
        assert_eq!(committed, 1024 * 1024);

        let _ = shutdown_tx.send(());
        let _ = server.await;
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn bytestream_reports_mid_stream_admission_rejection() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;
        use tokio_stream::wrappers::ReceiverStream;

        const MEBIBYTE: u64 = 1024 * 1024;
        let context = test_context(|config| {
            config.memory_limit_bytes = 512 * MEBIBYTE;
            config.memory_soft_limit_bytes = 128 * MEBIBYTE;
            config.memory_hard_limit_bytes = 256 * MEBIBYTE;
        })
        .await;
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let addr = listener.local_addr().expect("listener addr");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let server_state = context.state.clone();
        let server = tokio::spawn(async move {
            serve_routes(listener, server_state, async move {
                let _ = shutdown_rx.await;
            })
            .await
        });

        let endpoint = format!("http://{addr}");
        let channel = tonic::transport::Endpoint::from_shared(endpoint)
            .expect("valid endpoint")
            .connect()
            .await
            .expect("gRPC server should accept connections");
        let (request_tx, request_rx) = tokio::sync::mpsc::channel(2);
        let writer = tokio::spawn({
            let channel = channel.clone();
            async move {
                ByteStreamClient::new(channel)
                    .write(ReceiverStream::new(request_rx))
                    .await
            }
        });

        request_tx
            .send(bytestream::WriteRequest {
                resource_name: format!(
                    "uploads/mid-stream/blobs/{}/{}",
                    "00".repeat(32),
                    2 * MEBIBYTE
                ),
                write_offset: 0,
                finish_write: false,
                data: vec![0xA5],
            })
            .await
            .expect("first message should enter the stream");
        tokio::time::timeout(Duration::from_secs(5), async {
            while context.state.memory.transient_reserved_bytes() < 4 * MEBIBYTE {
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("the first message should be decoded and reserve staging memory");

        context.state.memory.observe(256 * MEBIBYTE);
        request_tx
            .send(bytestream::WriteRequest {
                resource_name: String::new(),
                write_offset: 1,
                finish_write: false,
                data: vec![0x5A; MEBIBYTE as usize],
            })
            .await
            .expect("second message should enter the client transport");
        drop(request_tx);

        let error = tokio::time::timeout(Duration::from_secs(5), writer)
            .await
            .expect("mid-stream rejection should not hang")
            .expect("writer task should not panic")
            .expect_err("the second message should exceed admitted memory");
        assert_eq!(error.code(), tonic::Code::ResourceExhausted);

        context.state.memory.observe(0);
        let blob = vec![0xC3; 1024];
        let hash = hex::encode(Sha256::digest(&blob));
        let committed = ByteStreamClient::new(channel)
            .write(tokio_stream::iter([bytestream::WriteRequest {
                resource_name: format!("uploads/recovered/blobs/{hash}/{}", blob.len()),
                write_offset: 0,
                finish_write: true,
                data: blob,
            }]))
            .await
            .expect("the connection should remain usable after mid-stream rejection")
            .into_inner()
            .committed_size;
        assert_eq!(committed, 1024);

        let _ = shutdown_tx.send(());
        let _ = server.await;
    }

    // Regression: a CAS blob uploaded via the ByteStream `Write` interface must be reported
    // present by `FindMissingBlobs`. ByteStream Write/Read once keyed blobs as "{hash}/{size}"
    // while FindMissingBlobs/BatchUpdateBlobs/BatchReadBlobs use blob_key() = "blob/{hash}/{size}",
    // so ByteStream-uploaded blobs were invisible to FindMissingBlobs and REAPI clients (e.g.
    // Bazel) re-executed the action that produced them. Drives the real gRPC handlers end to end.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn bytestream_uploaded_blob_is_visible_to_find_missing_blobs() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;
        use reapi::content_addressable_storage_client::ContentAddressableStorageClient;

        let context = test_context(|_| {}).await;
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let addr = listener.local_addr().expect("listener addr");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let server_state = context.state.clone();
        let server = tokio::spawn(async move {
            serve_routes(listener, server_state, async move {
                let _ = shutdown_rx.await;
            })
            .await
        });

        let endpoint = format!("http://{addr}");
        let mut channel = None;
        for _ in 0..50 {
            match tonic::transport::Endpoint::from_shared(endpoint.clone())
                .expect("valid endpoint")
                .connect()
                .await
            {
                Ok(connected) => {
                    channel = Some(connected);
                    break;
                }
                Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
            }
        }
        let channel = channel.expect("gRPC server should accept connections");

        let blob = b"kura reapi bytestream blob-key regression payload".to_vec();
        let hash = hex::encode(Sha256::digest(&blob));
        let len = blob.len();

        // Upload via the ByteStream Write interface, exactly as a REAPI client does for CAS.
        let committed = ByteStreamClient::new(channel.clone())
            .write(tokio_stream::iter(vec![bytestream::WriteRequest {
                resource_name: format!("uploads/regression/blobs/{hash}/{len}"),
                write_offset: 0,
                finish_write: true,
                data: blob.clone(),
            }]))
            .await
            .expect("ByteStream write should succeed")
            .into_inner()
            .committed_size;
        assert_eq!(committed as usize, len);

        // FindMissingBlobs must report it PRESENT — it shares blob_key()'s namespace with Write.
        let missing = ContentAddressableStorageClient::new(channel.clone())
            .find_missing_blobs(reapi::FindMissingBlobsRequest {
                instance_name: String::new(),
                blob_digests: vec![reapi::Digest {
                    hash: hash.clone(),
                    size_bytes: len as i64,
                }],
                digest_function: 0,
            })
            .await
            .expect("find_missing_blobs should succeed")
            .into_inner()
            .missing_blob_digests;
        assert!(
            missing.is_empty(),
            "a ByteStream-uploaded blob must be visible to FindMissingBlobs; got {} missing",
            missing.len()
        );

        let _ = shutdown_tx.send(());
        let _ = server.await;
    }

    #[test]
    fn parses_read_resource_names_with_and_without_instance_names() {
        assert_eq!(
            parse_read_resource_name("blobs/abc/10").expect("resource should parse"),
            BlobResource {
                namespace_id: "default".into(),
                hash: "abc".into(),
                size_bytes: 10,
                key: "blob/abc/10".into(),
            }
        );
        assert_eq!(
            parse_read_resource_name("bazel/cache/blobs/abc/10")
                .expect("instance-scoped resource should parse"),
            BlobResource {
                namespace_id: "bazel/cache".into(),
                hash: "abc".into(),
                size_bytes: 10,
                key: "blob/abc/10".into(),
            }
        );
    }

    #[test]
    fn parses_write_resource_names_with_upload_prefix() {
        assert_eq!(
            parse_write_resource_name("buck/cache/uploads/uuid-1/blobs/abc/10")
                .expect("write resource should parse"),
            BlobResource {
                namespace_id: "buck/cache".into(),
                hash: "abc".into(),
                size_bytes: 10,
                key: "blob/abc/10".into(),
            }
        );
    }

    #[test]
    fn rejects_write_resources_without_upload_prefix() {
        let error = parse_write_resource_name("blobs/abc/10")
            .expect_err("write resources should require uploads prefix");
        assert_eq!(error.code(), tonic::Code::InvalidArgument);
    }

    fn grpc_spec() -> GrpcExtensionSpec<'static> {
        GrpcExtensionSpec {
            route: "reapi.capabilities.get",
            operation: "capabilities.read",
            namespace_id: Some("ios"),
            producer: Some("reapi"),
            artifact_key: None,
            artifact_hash: None,
        }
    }

    fn metadata_with(pairs: &[(&'static str, &'static str)]) -> tonic::metadata::MetadataMap {
        let mut metadata = tonic::metadata::MetadataMap::new();
        for (key, value) in pairs {
            metadata.insert(*key, tonic::metadata::MetadataValue::from_static(value));
        }
        metadata
    }

    #[test]
    fn grpc_context_reads_tenant_from_kura_header() {
        let metadata = metadata_with(&[("x-kura-tenant-id", "acme")]);
        let ctx = grpc_extension_context("acme", &grpc_spec(), &metadata, None);
        assert_eq!(ctx.tenant_id.as_deref(), Some("acme"));
        assert_eq!(ctx.namespace_id.as_deref(), Some("ios"));
    }

    #[test]
    fn grpc_context_reads_tenant_from_tuist_account_handle_alias() {
        let metadata = metadata_with(&[("x-tuist-account-handle", "acme")]);
        let ctx = grpc_extension_context("acme", &grpc_spec(), &metadata, None);
        assert_eq!(ctx.tenant_id.as_deref(), Some("acme"));
    }

    #[test]
    fn grpc_context_without_tenant_header_leaves_tenant_unset() {
        let metadata = tonic::metadata::MetadataMap::new();
        let ctx = grpc_extension_context("acme", &grpc_spec(), &metadata, None);
        assert_eq!(ctx.tenant_id, None);
        assert_eq!(ctx.namespace_id.as_deref(), Some("ios"));
    }

    // Minimal policy: any token authenticates; only namespace "ios" is authorized.
    // Used to prove that GetCapabilities and ByteStream Write reach the extension
    // with the request's project namespace (instance_name / resource_name), not
    // the account scope they previously fell back to.
    const NAMESPACE_POLICY_SCRIPT: &str = r#"
function authenticate(ctx)
  return { principal = { id = "test", kind = "subject" }, ttl_seconds = 60 }
end

function authorize(ctx, principal)
  if ctx.namespace_id == "ios" then
    return { allow = true, ttl_seconds = 60 }
  end
  return { deny = { status = 403, message = "forbidden namespace" }, ttl_seconds = 1 }
end
"#;

    async fn namespace_policy_extension() -> crate::extension::SharedExtension {
        let dir = tempfile::tempdir().expect("create policy temp dir");
        let script_path = dir.path().join("policy.lua");
        tokio::fs::write(&script_path, NAMESPACE_POLICY_SCRIPT)
            .await
            .expect("write policy script");
        crate::extension::ExtensionEngine::from_script_for_test(
            script_path,
            crate::metrics::Metrics::new("test".into(), "tenant".into()),
        )
        .await
        .expect("build policy extension")
    }

    #[tokio::test]
    async fn get_capabilities_authorizes_against_instance_namespace() {
        let extension = namespace_policy_extension().await;
        let context = test_context_with_extension(|_| {}, Some(extension)).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };

        service
            .get_capabilities(Request::new(reapi::GetCapabilitiesRequest {
                instance_name: "ios".into(),
            }))
            .await
            .expect("capabilities for a granted instance_name should be allowed");

        let denied = service
            .get_capabilities(Request::new(reapi::GetCapabilitiesRequest {
                instance_name: "forbidden".into(),
            }))
            .await
            .expect_err("capabilities for a non-granted instance_name should be denied");
        assert_eq!(denied.code(), tonic::Code::PermissionDenied);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn bytestream_write_authorizes_against_resource_namespace() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

        let extension = namespace_policy_extension().await;
        let context = test_context_with_extension(|_| {}, Some(extension)).await;
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let addr = listener.local_addr().expect("listener addr");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let server_state = context.state.clone();
        let server = tokio::spawn(async move {
            serve_routes(listener, server_state, async move {
                let _ = shutdown_rx.await;
            })
            .await
        });

        let endpoint = format!("http://{addr}");
        let mut channel = None;
        for _ in 0..50 {
            match tonic::transport::Endpoint::from_shared(endpoint.clone())
                .expect("valid endpoint")
                .connect()
                .await
            {
                Ok(connected) => {
                    channel = Some(connected);
                    break;
                }
                Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
            }
        }
        let channel = channel.expect("gRPC server should accept connections");

        let blob = b"kura reapi project-scoped write payload".to_vec();
        let hash = hex::encode(Sha256::digest(&blob));
        let len = blob.len();

        // Granted namespace ("ios", from the resource_name prefix) authorizes and persists.
        let committed = ByteStreamClient::new(channel.clone())
            .write(tokio_stream::iter(vec![bytestream::WriteRequest {
                resource_name: format!("ios/uploads/write-1/blobs/{hash}/{len}"),
                write_offset: 0,
                finish_write: true,
                data: blob.clone(),
            }]))
            .await
            .expect("write to a granted namespace should be allowed")
            .into_inner()
            .committed_size;
        assert_eq!(committed as usize, len);

        // Non-granted namespace ("forbidden") is rejected before the blob is persisted.
        let denied = ByteStreamClient::new(channel.clone())
            .write(tokio_stream::iter(vec![bytestream::WriteRequest {
                resource_name: format!("forbidden/uploads/write-2/blobs/{hash}/{len}"),
                write_offset: 0,
                finish_write: true,
                data: blob.clone(),
            }]))
            .await
            .expect_err("write to a non-granted namespace should be denied");
        assert_eq!(denied.code(), tonic::Code::PermissionDenied);

        let _ = shutdown_tx.send(());
        let _ = server.await;
    }

    #[tokio::test]
    async fn action_cache_reads_emit_keyvalue_metrics() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let action_result = reapi::ActionResult::default();
        let bytes = action_result.encode_to_vec();
        let digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&bytes)),
            size_bytes: bytes.len() as i64,
        };
        let key = action_cache_key(&digest_key(&digest).expect("digest key should build"));

        context
            .state
            .store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &key,
                "application/x-protobuf",
                &bytes,
            )
            .await
            .expect("action result should persist");

        service
            .get_action_result(Request::new(reapi::GetActionResultRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                action_digest: Some(digest),
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("action result should load");

        let rendered = context.state.metrics.render();
        assert!(rendered.contains("kura_artifact_reads_total"));
        assert!(rendered.contains("producer=\"reapi\""));
        assert!(rendered.contains("result=\"ok\""));
    }

    #[tokio::test]
    async fn cas_batch_reads_emit_module_metrics() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let bytes = b"blob-bytes";
        let digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(bytes)),
            size_bytes: bytes.len() as i64,
        };
        let key = blob_key(&digest_key(&digest).expect("digest key should build"));

        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &key,
                "application/octet-stream",
                bytes,
            )
            .await
            .expect("cas blob should persist");

        let response = service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                digests: vec![digest],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("batch read should succeed");

        assert_eq!(response.get_ref().responses.len(), 1);
        assert_eq!(response.get_ref().responses[0].data, bytes);

        let rendered = context.state.metrics.render();
        assert!(rendered.contains("kura_artifact_reads_total"));
        assert!(rendered.contains("producer=\"reapi\""));
        assert!(rendered.contains("result=\"ok\""));
    }

    #[tokio::test]
    async fn cas_batch_reads_mark_oversized_blobs_resource_exhausted_without_spending_budget() {
        let context = test_context(|config| {
            config.memory_soft_limit_bytes = 32 * 1024 * 1024;
            config.memory_hard_limit_bytes = 64 * 1024 * 1024;
        })
        .await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let oversized_bytes = vec![b'x'; 9 * 1024 * 1024];
        let small_bytes = b"small-bytes";
        let oversized_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&oversized_bytes)),
            size_bytes: oversized_bytes.len() as i64,
        };
        let small_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(small_bytes)),
            size_bytes: small_bytes.len() as i64,
        };
        let oversized_key =
            blob_key(&digest_key(&oversized_digest).expect("digest key should build"));
        let small_key = blob_key(&digest_key(&small_digest).expect("digest key should build"));

        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &oversized_key,
                "application/octet-stream",
                &oversized_bytes,
            )
            .await
            .expect("oversized cas blob should persist");
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &small_key,
                "application/octet-stream",
                small_bytes,
            )
            .await
            .expect("small cas blob should persist");

        let response = service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                digests: vec![oversized_digest, small_digest],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("batch read should succeed");

        assert_eq!(response.get_ref().responses.len(), 2);
        assert_eq!(
            response.get_ref().responses[0]
                .status
                .as_ref()
                .map(|status| status.code),
            Some(tonic::Code::ResourceExhausted as i32)
        );
        assert!(response.get_ref().responses[0].data.is_empty());
        assert_eq!(
            response.get_ref().responses[1]
                .status
                .as_ref()
                .map(|status| status.code),
            Some(0)
        );
        assert_eq!(response.get_ref().responses[1].data, small_bytes);
    }

    #[tokio::test]
    async fn concurrent_cas_batch_reads_respect_shared_materialization_pool() {
        let context = test_context(|config| {
            config.memory_soft_limit_bytes = 64 * 1024 * 1024;
            config.memory_hard_limit_bytes = 128 * 1024 * 1024;
        })
        .await;
        let first_service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let second_service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let third_service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let bytes = vec![b'b'; 16 * 1024 * 1024];
        let digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&bytes)),
            size_bytes: bytes.len() as i64,
        };
        let key = blob_key(&digest_key(&digest).expect("digest key should build"));
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &key,
                "application/octet-stream",
                &bytes,
            )
            .await
            .expect("cas blob should persist");
        context.state.store.failpoints().set_always(
            FailpointName::AfterReadArtifactBytesBeforeReturn,
            FailpointAction::Sleep(Duration::from_millis(250)),
        );

        let first = tokio::spawn({
            let digest = digest.clone();
            async move {
                first_service
                    .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                        instance_name: DEFAULT_INSTANCE_NAME.into(),
                        digests: vec![digest],
                        digest_function: reapi::digest_function::Value::Sha256 as i32,
                        ..Default::default()
                    }))
                    .await
            }
        });
        let second = tokio::spawn({
            let digest = digest.clone();
            async move {
                second_service
                    .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                        instance_name: DEFAULT_INSTANCE_NAME.into(),
                        digests: vec![digest],
                        digest_function: reapi::digest_function::Value::Sha256 as i32,
                        ..Default::default()
                    }))
                    .await
            }
        });

        tokio::time::sleep(Duration::from_millis(50)).await;

        let third = third_service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                digests: vec![digest.clone()],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("third request should get a per-digest response");

        context
            .state
            .store
            .failpoints()
            .clear(FailpointName::AfterReadArtifactBytesBeforeReturn);

        assert_eq!(
            third.get_ref().responses[0]
                .status
                .as_ref()
                .map(|status| status.code),
            Some(tonic::Code::ResourceExhausted as i32)
        );

        for handle in [first, second] {
            let response = handle
                .await
                .expect("concurrent read task should join")
                .expect("concurrent read should succeed");
            assert_eq!(
                response.get_ref().responses[0]
                    .status
                    .as_ref()
                    .map(|status| status.code),
                Some(0)
            );
            assert_eq!(response.get_ref().responses[0].data, bytes);
        }
    }

    #[tokio::test]
    async fn cas_batch_reads_shed_under_critical_memory_pressure() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let bytes = b"blob-bytes";
        let digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(bytes)),
            size_bytes: bytes.len() as i64,
        };
        let key = blob_key(&digest_key(&digest).expect("digest key should build"));

        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &key,
                "application/octet-stream",
                bytes,
            )
            .await
            .expect("cas blob should persist");
        context
            .state
            .memory
            .observe(context.state.config.memory_hard_limit_bytes);

        let response = service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                digests: vec![digest],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("batch read should return per-digest status");

        assert_eq!(
            response.get_ref().responses[0]
                .status
                .as_ref()
                .map(|status| status.code),
            Some(tonic::Code::ResourceExhausted as i32)
        );
    }

    #[tokio::test]
    async fn action_cache_inline_reads_reject_when_inline_expansion_exceeds_budget() {
        let context = test_context(|config| {
            config.memory_soft_limit_bytes = 32 * 1024 * 1024;
            config.memory_hard_limit_bytes = 64 * 1024 * 1024;
        })
        .await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let stdout_bytes = vec![b's'; 9 * 1024 * 1024];
        let stdout_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&stdout_bytes)),
            size_bytes: stdout_bytes.len() as i64,
        };
        let stdout_key = blob_key(&digest_key(&stdout_digest).expect("digest key should build"));
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &stdout_key,
                "application/octet-stream",
                &stdout_bytes,
            )
            .await
            .expect("stdout blob should persist");

        let action_result = reapi::ActionResult {
            stdout_digest: Some(stdout_digest),
            ..Default::default()
        };
        let action_bytes = action_result.encode_to_vec();
        let action_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&action_bytes)),
            size_bytes: action_bytes.len() as i64,
        };
        let action_key =
            action_cache_key(&digest_key(&action_digest).expect("digest key should build"));
        context
            .state
            .store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &action_key,
                "application/x-protobuf",
                &action_bytes,
            )
            .await
            .expect("action result should persist");

        let error = service
            .get_action_result(Request::new(reapi::GetActionResultRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                action_digest: Some(action_digest),
                inline_stdout: true,
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect_err("inline expansion should respect the materialization budget");

        assert_eq!(error.code(), tonic::Code::ResourceExhausted);
    }

    async fn persist_output_file_blob(context: &TestContext, bytes: &[u8]) -> reapi::Digest {
        let digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(bytes)),
            size_bytes: bytes.len() as i64,
        };
        let key = blob_key(&digest_key(&digest).expect("digest key should build"));
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &key,
                "application/octet-stream",
                bytes,
            )
            .await
            .expect("output blob should persist");
        digest
    }

    async fn persist_action_result_with_outputs(
        context: &TestContext,
        output_files: Vec<reapi::OutputFile>,
    ) -> reapi::Digest {
        let action_result = reapi::ActionResult {
            output_files,
            ..Default::default()
        };
        let action_bytes = action_result.encode_to_vec();
        let action_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&action_bytes)),
            size_bytes: action_bytes.len() as i64,
        };
        let action_key =
            action_cache_key(&digest_key(&action_digest).expect("digest key should build"));
        context
            .state
            .store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &action_key,
                "application/x-protobuf",
                &action_bytes,
            )
            .await
            .expect("action result should persist");
        action_digest
    }

    #[tokio::test]
    async fn action_cache_wildcard_inlines_every_output_file() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let first_bytes = b"first output".to_vec();
        let second_bytes = b"second output".to_vec();
        let first_digest = persist_output_file_blob(&context, &first_bytes).await;
        let second_digest = persist_output_file_blob(&context, &second_bytes).await;
        let action_digest = persist_action_result_with_outputs(
            &context,
            vec![
                reapi::OutputFile {
                    path: "aaaa".into(),
                    digest: Some(first_digest),
                    ..Default::default()
                },
                reapi::OutputFile {
                    path: "bbbb".into(),
                    digest: Some(second_digest),
                    ..Default::default()
                },
            ],
        )
        .await;

        let response = service
            .get_action_result(Request::new(reapi::GetActionResultRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                action_digest: Some(action_digest),
                inline_output_files: vec!["*".into()],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("wildcard inline should succeed");

        let output_files = &response.get_ref().output_files;
        assert_eq!(output_files[0].contents, first_bytes);
        assert_eq!(output_files[1].contents, second_bytes);
    }

    #[tokio::test]
    async fn action_cache_wildcard_inline_degrades_to_partial_when_budget_is_exceeded() {
        let context = test_context(|config| {
            config.memory_soft_limit_bytes = 32 * 1024 * 1024;
            config.memory_hard_limit_bytes = 64 * 1024 * 1024;
        })
        .await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        // Larger than the response budget under this memory config (the same
        // sizing the explicit-inline rejection test relies on), listed FIRST
        // to prove a rejected file does not stop later ones from inlining.
        let large_bytes = vec![b'x'; 9 * 1024 * 1024];
        let small_bytes = b"small output".to_vec();
        let large_digest = persist_output_file_blob(&context, &large_bytes).await;
        let small_digest = persist_output_file_blob(&context, &small_bytes).await;
        let action_digest = persist_action_result_with_outputs(
            &context,
            vec![
                reapi::OutputFile {
                    path: "large".into(),
                    digest: Some(large_digest),
                    ..Default::default()
                },
                reapi::OutputFile {
                    path: "small".into(),
                    digest: Some(small_digest),
                    ..Default::default()
                },
            ],
        )
        .await;

        let response = service
            .get_action_result(Request::new(reapi::GetActionResultRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                action_digest: Some(action_digest),
                inline_output_files: vec!["*".into()],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("wildcard inline should degrade to partial, not fail");

        let output_files = &response.get_ref().output_files;
        assert!(output_files[0].contents.is_empty());
        assert_eq!(output_files[1].contents, small_bytes);
    }

    #[tokio::test]
    async fn wildcard_inline_keeps_the_hard_budget_error_for_an_explicitly_listed_path() {
        let context = test_context(|config| {
            config.memory_soft_limit_bytes = 32 * 1024 * 1024;
            config.memory_hard_limit_bytes = 64 * 1024 * 1024;
        })
        .await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        // Larger than the response budget; listed BOTH via "*" and explicitly.
        // The explicit listing must keep the hard error even though "*" would
        // otherwise let it degrade to partial.
        let large_bytes = vec![b'x'; 9 * 1024 * 1024];
        let large_digest = persist_output_file_blob(&context, &large_bytes).await;
        let action_digest = persist_action_result_with_outputs(
            &context,
            vec![reapi::OutputFile {
                path: "required".into(),
                digest: Some(large_digest),
                ..Default::default()
            }],
        )
        .await;

        let error = service
            .get_action_result(Request::new(reapi::GetActionResultRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                action_digest: Some(action_digest),
                inline_output_files: vec!["*".into(), "required".into()],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect_err("an explicitly listed over-budget file must fail the lookup");

        assert_eq!(error.code(), tonic::Code::ResourceExhausted);
    }

    #[tokio::test]
    async fn draining_rejects_new_grpc_requests() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        context.state.enter_draining();

        let error = service
            .get_capabilities(Request::new(reapi::GetCapabilitiesRequest::default()))
            .await
            .expect_err("draining nodes should reject new gRPC requests");

        assert_eq!(error.code(), tonic::Code::Unavailable);
        assert!(error.message().contains("draining"));
    }

    #[test]
    fn usage_tenant_id_prefers_metadata_header_and_falls_back_to_node_tenant() {
        let mut metadata = tonic::metadata::MetadataMap::new();
        assert_eq!(usage_tenant_id(&metadata, "node-tenant"), "node-tenant");

        metadata.insert("x-tuist-account-handle", "  acme  ".parse().unwrap());
        assert_eq!(usage_tenant_id(&metadata, "node-tenant"), "acme");

        let mut kura_metadata = tonic::metadata::MetadataMap::new();
        kura_metadata.insert("x-kura-tenant-id", "globex".parse().unwrap());
        assert_eq!(usage_tenant_id(&kura_metadata, "node-tenant"), "globex");
    }

    // Authorization and billing must resolve the tenant from a duplicated header
    // identically; otherwise a client could be authorized as one account and
    // billed to another. Both go through `tenant_id_from_metadata`, which takes
    // the first value of a repeated key.
    #[test]
    fn tenant_id_from_metadata_takes_first_value_of_a_repeated_header() {
        let mut metadata = tonic::metadata::MetadataMap::new();
        metadata.append("x-tuist-account-handle", "acme".parse().unwrap());
        metadata.append("x-tuist-account-handle", "globex".parse().unwrap());

        // The authorization path (grpc_extension_context) and the billing path
        // (usage_tenant_id) read the same value.
        assert_eq!(tenant_id_from_metadata(&metadata).as_deref(), Some("acme"));
        assert_eq!(usage_tenant_id(&metadata, "node-tenant"), "acme");

        let spec = GrpcExtensionSpec {
            route: "reapi.bytestream.read",
            operation: "artifact.read",
            namespace_id: Some("ios"),
            producer: Some("reapi"),
            artifact_key: None,
            artifact_hash: None,
        };
        let context = grpc_extension_context("acme", &spec, &metadata, None);
        assert_eq!(context.tenant_id.as_deref(), Some("acme"));
    }

    fn test_usage_config() -> crate::config::UsageConfig {
        crate::config::UsageConfig {
            control_plane_url: "http://localhost:0".to_owned(),
            client_id: "kura".to_owned(),
            client_secret: "secret".to_owned(),
            window_secs: 60,
            flush_interval_ms: 1_000,
            delivery_interval_ms: 1_000,
            batch_size: 100,
            max_buckets: 100,
            outbox_max_depth: 100,
        }
    }

    // The CAS batch handlers carry the bulk of small-blob REAPI traffic; both
    // must land in the usage rollups tagged protocol="grpc"/artifact_kind="reapi"
    // and attributed to the tenant declared via the account-handle metadata
    // header (the gRPC analog of the HTTP tenant_id query param). A batch RPC of N
    // blobs counts as ONE request (not N), and re-uploading an already-present
    // blob is not billed a second time — matching the HTTP upload path.
    #[tokio::test]
    async fn cas_batch_transfers_record_grpc_usage_events() {
        let context = test_context(|config| {
            config.usage = Some(test_usage_config());
        })
        .await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };

        let blob_a = b"reapi-cas-blob-a".to_vec();
        let blob_b = b"reapi-cas-blob-bb".to_vec();
        let total_bytes = (blob_a.len() + blob_b.len()) as u64;
        let build_update = || {
            let mut update = Request::new(reapi::BatchUpdateBlobsRequest {
                instance_name: "ios".into(),
                requests: vec![
                    reapi::batch_update_blobs_request::Request {
                        digest: Some(reapi::Digest {
                            hash: hex::encode(Sha256::digest(&blob_a)),
                            size_bytes: blob_a.len() as i64,
                        }),
                        data: blob_a.clone(),
                        ..Default::default()
                    },
                    reapi::batch_update_blobs_request::Request {
                        digest: Some(reapi::Digest {
                            hash: hex::encode(Sha256::digest(&blob_b)),
                            size_bytes: blob_b.len() as i64,
                        }),
                        data: blob_b.clone(),
                        ..Default::default()
                    },
                ],
                ..Default::default()
            });
            update
                .metadata_mut()
                .insert("x-tuist-account-handle", "acme".parse().unwrap());
            update
        };

        // First upload stores both blobs; the second finds both already present
        // (IgnoredStale) and must not bill them again.
        service
            .batch_update_blobs(build_update())
            .await
            .expect("batch update should succeed");
        service
            .batch_update_blobs(build_update())
            .await
            .expect("repeat batch update should succeed");

        let mut read = Request::new(reapi::BatchReadBlobsRequest {
            instance_name: "ios".into(),
            digests: vec![
                reapi::Digest {
                    hash: hex::encode(Sha256::digest(&blob_a)),
                    size_bytes: blob_a.len() as i64,
                },
                reapi::Digest {
                    hash: hex::encode(Sha256::digest(&blob_b)),
                    size_bytes: blob_b.len() as i64,
                },
            ],
            digest_function: reapi::digest_function::Value::Sha256 as i32,
            ..Default::default()
        });
        read.metadata_mut()
            .insert("x-tuist-account-handle", "acme".parse().unwrap());
        service
            .batch_read_blobs(read)
            .await
            .expect("batch read should succeed");

        let rollups = context
            .state
            .usage
            .as_ref()
            .expect("usage should be enabled")
            .current_rollups_for_tests();

        let upload = rollups
            .iter()
            .find(|rollup| rollup.operation == "upload")
            .expect("batch_update_blobs should record an upload rollup");
        assert_eq!(upload.tenant_id, "acme");
        assert_eq!(upload.namespace_id, "ios");
        assert_eq!(upload.traffic_plane, "public");
        assert_eq!(upload.direction, "ingress");
        assert_eq!(upload.protocol, "grpc");
        assert_eq!(upload.artifact_kind, "reapi");
        // Two blobs stored across two RPCs, but only the first RPC stored new
        // bytes and each batch RPC books one request: request_count == 1, and the
        // stale re-upload added nothing.
        assert_eq!(upload.bytes, total_bytes);
        assert_eq!(upload.request_count, 1);

        let download = rollups
            .iter()
            .find(|rollup| rollup.operation == "download")
            .expect("batch_read_blobs should record a download rollup");
        assert_eq!(download.tenant_id, "acme");
        assert_eq!(download.namespace_id, "ios");
        assert_eq!(download.traffic_plane, "public");
        assert_eq!(download.direction, "egress");
        assert_eq!(download.protocol, "grpc");
        assert_eq!(download.artifact_kind, "reapi");
        // One batch read of two blobs is one request carrying both blobs' bytes.
        assert_eq!(download.bytes, total_bytes);
        assert_eq!(download.request_count, 1);
    }

    // The ActionCache methods move real bytes too: UpdateActionResult uploads an
    // encoded action result, and GetActionResult returns it plus any inlined
    // stdout/stderr/output-file blobs. Both must land in the grpc/reapi usage
    // rollups like the ByteStream/CAS handlers, with the download counting the
    // inlined blob bytes as egress.
    #[tokio::test]
    async fn action_cache_transfers_record_grpc_usage_events() {
        let context = test_context(|config| {
            config.usage = Some(test_usage_config());
        })
        .await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };

        let stdout_bytes = b"action stdout".to_vec();
        let stdout_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&stdout_bytes)),
            size_bytes: stdout_bytes.len() as i64,
        };
        let stdout_key = blob_key(&digest_key(&stdout_digest).expect("digest key should build"));
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                &stdout_key,
                "application/octet-stream",
                &stdout_bytes,
            )
            .await
            .expect("stdout blob should persist");

        let action_result = reapi::ActionResult {
            stdout_digest: Some(stdout_digest),
            ..Default::default()
        };
        let encoded_bytes = action_result.encode_to_vec().len() as u64;
        let action_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(b"action")),
            size_bytes: "action".len() as i64,
        };

        let mut update = Request::new(reapi::UpdateActionResultRequest {
            instance_name: "ios".into(),
            action_digest: Some(action_digest.clone()),
            action_result: Some(action_result),
            digest_function: reapi::digest_function::Value::Sha256 as i32,
            ..Default::default()
        });
        update
            .metadata_mut()
            .insert("x-tuist-account-handle", "acme".parse().unwrap());
        service
            .update_action_result(update)
            .await
            .expect("update action result should succeed");

        let mut get = Request::new(reapi::GetActionResultRequest {
            instance_name: "ios".into(),
            action_digest: Some(action_digest),
            inline_stdout: true,
            digest_function: reapi::digest_function::Value::Sha256 as i32,
            ..Default::default()
        });
        get.metadata_mut()
            .insert("x-tuist-account-handle", "acme".parse().unwrap());
        let fetched = service
            .get_action_result(get)
            .await
            .expect("get action result should succeed");
        assert_eq!(
            fetched.get_ref().stdout_raw,
            stdout_bytes,
            "stdout should be inlined into the response"
        );

        let rollups = context
            .state
            .usage
            .as_ref()
            .expect("usage should be enabled")
            .current_rollups_for_tests();

        let upload = rollups
            .iter()
            .find(|rollup| rollup.operation == "upload")
            .expect("update_action_result should record an upload rollup");
        assert_eq!(upload.tenant_id, "acme");
        assert_eq!(upload.namespace_id, "ios");
        assert_eq!(upload.direction, "ingress");
        assert_eq!(upload.protocol, "grpc");
        assert_eq!(upload.artifact_kind, "reapi");
        assert_eq!(upload.bytes, encoded_bytes);
        assert_eq!(upload.request_count, 1);

        let download = rollups
            .iter()
            .find(|rollup| rollup.operation == "download")
            .expect("get_action_result should record a download rollup");
        assert_eq!(download.tenant_id, "acme");
        assert_eq!(download.namespace_id, "ios");
        assert_eq!(download.direction, "egress");
        assert_eq!(download.protocol, "grpc");
        assert_eq!(download.artifact_kind, "reapi");
        // The download egress is the stored action result plus the inlined
        // stdout blob it carried out.
        assert_eq!(download.bytes, encoded_bytes + stdout_bytes.len() as u64);
        assert_eq!(download.request_count, 1);
    }

    // Drives the real ByteStream gRPC handlers (the large-artifact read/write
    // path) end to end and asserts each emits a grpc/reapi usage rollup, so the
    // primary bandwidth carriers are no longer invisible to kura_usage_events.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn bytestream_transfers_record_grpc_usage_events() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

        let context = test_context(|config| {
            config.usage = Some(test_usage_config());
        })
        .await;
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let addr = listener.local_addr().expect("listener addr");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let server_state = context.state.clone();
        let server = tokio::spawn(async move {
            serve_routes(listener, server_state, async move {
                let _ = shutdown_rx.await;
            })
            .await
        });

        let endpoint = format!("http://{addr}");
        let mut channel = None;
        for _ in 0..50 {
            match tonic::transport::Endpoint::from_shared(endpoint.clone())
                .expect("valid endpoint")
                .connect()
                .await
            {
                Ok(connected) => {
                    channel = Some(connected);
                    break;
                }
                Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
            }
        }
        let channel = channel.expect("gRPC server should accept connections");

        let blob: Vec<u8> = (0..200_000u32).map(|byte| byte as u8).collect();
        let hash = hex::encode(Sha256::digest(&blob));
        let resource = format!("ios/uploads/upload-1/blobs/{hash}/{}", blob.len());

        let chunk_size = 64 * 1024;
        let build_write = || {
            let mut requests = Vec::new();
            let mut offset = 0usize;
            while offset < blob.len() {
                let end = (offset + chunk_size).min(blob.len());
                requests.push(bytestream::WriteRequest {
                    resource_name: if offset == 0 {
                        resource.clone()
                    } else {
                        String::new()
                    },
                    write_offset: offset as i64,
                    finish_write: end == blob.len(),
                    data: blob[offset..end].to_vec(),
                });
                offset = end;
            }
            let mut write_request = Request::new(tokio_stream::iter(requests));
            write_request
                .metadata_mut()
                .insert("x-tuist-account-handle", "acme".parse().unwrap());
            write_request
        };

        let mut client = ByteStreamClient::new(channel.clone());
        let committed = client
            .write(build_write())
            .await
            .expect("bytestream write should persist")
            .into_inner()
            .committed_size;
        assert_eq!(committed as usize, blob.len());

        // A second write of the same blob is already present and must not be
        // billed again (parity with the HTTP upload path).
        client
            .write(build_write())
            .await
            .expect("repeat bytestream write should succeed");

        let mut read_request = Request::new(bytestream::ReadRequest {
            resource_name: format!("ios/blobs/{hash}/{}", blob.len()),
            read_offset: 0,
            read_limit: 0,
        });
        read_request
            .metadata_mut()
            .insert("x-tuist-account-handle", "acme".parse().unwrap());
        let mut stream = client
            .read(read_request)
            .await
            .expect("blob should read back")
            .into_inner();
        let mut roundtrip = Vec::new();
        while let Some(chunk) = stream.message().await.expect("read chunk") {
            roundtrip.extend_from_slice(&chunk.data);
        }
        assert_eq!(roundtrip, blob);

        let _ = shutdown_tx.send(());
        let _ = server.await;

        let rollups = context
            .state
            .usage
            .as_ref()
            .expect("usage should be enabled")
            .current_rollups_for_tests();

        let upload = rollups
            .iter()
            .find(|rollup| rollup.operation == "upload")
            .expect("bytestream write should record an upload rollup");
        assert_eq!(upload.tenant_id, "acme");
        assert_eq!(upload.namespace_id, "ios");
        assert_eq!(upload.protocol, "grpc");
        assert_eq!(upload.artifact_kind, "reapi");
        assert_eq!(upload.direction, "ingress");
        // Two writes of the same blob, but the second was already present: exactly
        // one request and one blob's worth of bytes are billed.
        assert_eq!(upload.bytes, blob.len() as u64);
        assert_eq!(upload.request_count, 1);

        let download = rollups
            .iter()
            .find(|rollup| rollup.operation == "download")
            .expect("bytestream read should record a download rollup");
        assert_eq!(download.tenant_id, "acme");
        assert_eq!(download.namespace_id, "ios");
        assert_eq!(download.protocol, "grpc");
        assert_eq!(download.artifact_kind, "reapi");
        assert_eq!(download.direction, "egress");
        assert_eq!(download.bytes, blob.len() as u64);
        assert_eq!(download.request_count, 1);
    }
}
