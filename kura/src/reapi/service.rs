use std::{
    collections::{BTreeMap, VecDeque},
    pin::Pin,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
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
use futures_util::{FutureExt, StreamExt};
use prost::Message;
use sha2::{Digest as _, Sha256};
use tonic::{Request, Response, Status};
use tracing::Instrument;

#[cfg(test)]
use super::protobuf_shape::*;
use super::{
    admission::*,
    chunking::{
        ChunkedBlobRecipe, FAST_CDC_AVERAGE_CHUNK_BYTES, PresenceBudget, fetch_chunk_manifests,
        fetch_recipe, is_presence_budget_error, manifest_presence_keys, presence_keys,
        push_recipe_key, recipe_key, recipe_presence_keys,
    },
    snapshot::*,
};

use crate::{
    analytics::{ReapiCacheAnalyticsContext, ReapiCacheAnalyticsEvent},
    artifact::{manifest::ArtifactManifest, producer::ArtifactProducer},
    auth::{AccessDecision, RequestContext},
    constants::{
        MAX_INLINE_REPLICATION_BODY_BYTES, MAX_MODULE_TOTAL_BYTES,
        RESPONSE_STREAM_SEND_BUFFER_BYTES, encoded_response_stream_chunk_bytes,
        response_stream_chunk_bytes,
    },
    file_cache::{FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES, FileCachePolicy},
    io::{PersistentFile, is_fd_pool_exhausted_error, run_blocking_file_operation},
    memory::MemoryPressure,
    metrics::shed_kind,
    state::SharedState,
    store::{
        ArtifactReader, RefreshTrigger, SEGMENT_COPY_BUFFER_BYTES, StagedArtifactPath,
        try_allocate_exact_vec,
    },
    utils::{TempFileCleanup, action_cache_key, blob_key, temp_file_path},
};

const DEFAULT_INSTANCE_NAME: &str = "default";
// ByteStream downloads can keep the response vector and Tonic's encoded frame
// live while Hyper retains up to its separately capped per-stream send buffer.
// The reader fills the response vector directly, so there is no intermediate
// reader buffer.
const BYTESTREAM_RESPONSE_LIVE_CHUNK_COUNT: usize = 2;
const REAPI_MATERIALIZATION_REJECTED_ACTION: &str = "reapi_materialization_rejected";

fn record_materialization_rejection(state: &SharedState, kind: &'static str) {
    state
        .metrics
        .record_memory_action(REAPI_MATERIALIZATION_REJECTED_ACTION);
    state.metrics.record_capacity_shed(kind);
}

/// A request that outgrows its own response budget is refused for its size,
/// not for the pool, unless memory pressure is what shrank the budget.
fn over_budget_shed_kind(state: &SharedState) -> &'static str {
    if state.memory.pressure() == MemoryPressure::Normal {
        shed_kind::REAPI_REQUEST_BUDGET
    } else {
        shed_kind::REAPI_MATERIALIZATION
    }
}
// Abort a ByteStream upload only when no chunk arrives within this window. The
// timer resets on every chunk received, so an actively transferring upload is
// never interrupted, while a stalled or vanished client is reclaimed promptly.
const REAPI_WRITE_STALL_TIMEOUT: Duration = Duration::from_secs(60);
/// Blobs of one BatchUpdateBlobs request persisted concurrently; matches the
/// store's positioned segment write slots.
const BATCH_UPDATE_PERSIST_CONCURRENCY: usize = 32;
/// Staged ByteStream uploads coalesce wire chunks up to this many bytes per
/// temp-file write.
pub(super) const REAPI_STAGING_WRITE_BUFFER_BYTES: u64 = 1024 * 1024;
const REAPI_REQUEST_METADATA_HEADER: &str = "build.bazel.remote.execution.v2.requestmetadata-bin";
const MAX_CONCURRENT_SPLICE_VERIFICATIONS: usize = 4;
static ACTIVE_SPLICE_VERIFICATIONS: AtomicUsize = AtomicUsize::new(0);

struct SpliceVerificationSlot;

impl SpliceVerificationSlot {
    fn try_acquire() -> Option<Self> {
        ACTIVE_SPLICE_VERIFICATIONS
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |active| {
                (active < MAX_CONCURRENT_SPLICE_VERIFICATIONS).then_some(active + 1)
            })
            .ok()
            .map(|_| Self)
    }
}

impl Drop for SpliceVerificationSlot {
    fn drop(&mut self) {
        ACTIVE_SPLICE_VERIFICATIONS.fetch_sub(1, Ordering::Release);
    }
}
#[derive(Clone)]
pub struct ReapiService {
    pub(super) state: SharedState,
    // Per-namespace action-cache snapshot indexes and their in-flight
    // builds, shared across the service clones tonic hands each server.
    snapshot_cache: std::sync::Arc<SnapshotCache>,
}

#[derive(Clone, Copy)]
pub(super) struct GrpcRequestSpec<'a> {
    pub(super) operation: &'a str,
    pub(super) namespace_id: Option<&'a str>,
}

struct ReapiCacheObservation<'a> {
    operation: &'static str,
    outcome: &'static str,
    digest: &'a str,
    size: u64,
    duration: Duration,
}

pub(super) const REAPI_MAX_DECODING_MESSAGE_SIZE: usize = 64 << 20;

type ReapiServers = (
    CapabilitiesServer<ReapiService>,
    ActionCacheServer<ReapiService>,
    ContentAddressableStorageServer<ReapiService>,
    ByteStreamServer<ReapiService>,
    super::bep::PublishBuildEventServer,
);

// The four Remote Execution API services and the Build Event Service share the
// same listener and decoding limits.
fn reapi_servers(service: ReapiService) -> ReapiServers {
    (
        CapabilitiesServer::new(service.clone())
            .max_decoding_message_size(REAPI_MAX_DECODING_MESSAGE_SIZE),
        ActionCacheServer::new(service.clone())
            .max_decoding_message_size(REAPI_MAX_DECODING_MESSAGE_SIZE),
        ContentAddressableStorageServer::new(service.clone())
            .max_decoding_message_size(REAPI_MAX_DECODING_MESSAGE_SIZE),
        ByteStreamServer::new(service.clone())
            .max_decoding_message_size(REAPI_MAX_DECODING_MESSAGE_SIZE),
        super::bep::server(service.state.clone()),
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
    let service = ReapiService::new(state.clone());
    spawn_snapshot_refresh_task(service.clone());
    let assets = super::asset::server(service.clone());
    let (capabilities, action_cache, cas, byte_stream, build_events) = reapi_servers(service);
    tonic::service::Routes::new(capabilities)
        .add_service(action_cache)
        .add_service(cas)
        .add_service(byte_stream)
        .add_service(build_events)
        .add_service(assets)
        .into_axum_router()
        .layer(axum::middleware::from_fn_with_state(
            state.clone(),
            reject_overloaded_grpc_writes,
        ))
        .layer(axum::middleware::from_fn_with_state(
            state.clone(),
            admit_grpc_write_decode,
        ))
        .layer(GrpcRequestAccountingLayer { state })
        .layer(axum::middleware::map_response(
            crate::http::guard_response_stream_transport,
        ))
}

fn spawn_snapshot_refresh_task(service: ReapiService) {
    tokio::spawn(
        async move {
            loop {
                tokio::time::sleep(SNAPSHOT_REFRESH_TICK).await;
                service.refresh_snapshot_indexes();
            }
        }
        .in_current_span(),
    );
}

fn ref_metadata<T>(request: &Request<T>, header: &str, binary_header: &str) -> Option<String> {
    request
        .metadata()
        .get_bin(binary_header)
        .and_then(|value| value.to_bytes().ok())
        .and_then(|bytes| String::from_utf8(bytes.to_vec()).ok())
        .or_else(|| {
            request
                .metadata()
                .get(header)
                .and_then(|value| value.to_str().ok())
                .map(str::to_owned)
        })
        .filter(|value| !value.is_empty())
}

/// A compressed ByteStream write is expected to weigh at most this much per
/// declared-size byte: the largest valid zstd encoding of `declared`
/// uncompressed bytes plus a small slack for framing overhead. Skippable
/// frames decode to zero bytes and would otherwise let a client hold a
/// compressed write open indefinitely — bounding `wire_received` here is what
/// gates that.
fn compressed_wire_ceiling(declared_uncompressed: u64) -> u64 {
    // 64 KiB slack absorbs skippable-frame headers and multi-frame framing
    // overhead legitimate encoders may add, without giving an attacker useful
    // room. Falls back to a large but finite ceiling when the declared size
    // saturates zstd's usize input bound so the check remains meaningful.
    const WIRE_CEILING_SLACK_BYTES: u64 = 64 * 1024;
    let compressed_bound = usize::try_from(declared_uncompressed)
        .map(zstd::zstd_safe::compress_bound)
        .map(|bound| bound as u64)
        .unwrap_or(u64::MAX);
    compressed_bound.saturating_add(WIRE_CEILING_SLACK_BYTES)
}

/// Sink handed to the streaming zstd `write::Decoder` on the ByteStream upload
/// path. `remaining` is the largest number of additional decoded bytes the
/// sink will accept in the current chunk; the write loop refreshes it before
/// every `write_all` to `expected_size - stored_written`. That bounds the
/// decoder's inner buffer at exactly what the declared size still allows, so
/// a compression bomb cannot materialize a full chunk of expansion before the
/// per-chunk size check runs — the pattern `SnapshotWireWriter` already uses.
#[derive(Default)]
struct BoundedZstdDecoderSink {
    bytes: Vec<u8>,
    remaining: u64,
}

impl std::io::Write for BoundedZstdDecoderSink {
    fn write(&mut self, buffer: &[u8]) -> std::io::Result<usize> {
        if buffer.len() as u64 > self.remaining {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "compressed write decompressed past the declared blob size (possible bomb)",
            ));
        }
        self.remaining -= buffer.len() as u64;
        self.bytes.extend_from_slice(buffer);
        Ok(buffer.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn fill_staging_window(buffer: &mut Vec<u8>, window: usize, data: &[u8]) -> usize {
    let consumed = data.len().min(window - buffer.len());
    buffer.extend_from_slice(&data[..consumed]);
    consumed
}

impl ReapiService {
    pub(super) fn new(state: SharedState) -> Self {
        Self {
            snapshot_cache: state.snapshot_cache.clone(),
            state,
        }
    }

    pub(super) async fn authorize_request<T>(
        &self,
        request: &Request<T>,
        spec: GrpcRequestSpec<'_>,
    ) -> Result<(), Status> {
        self.authorize_metadata(request.metadata(), spec).await
    }

    // Authorize from already-extracted metadata. ByteStream Write consumes the
    // request into a stream before it learns its namespace (from the first
    // chunk's resource_name), so it captures the metadata up front and authorizes
    // here once the namespace is known.
    pub(super) async fn authorize_metadata(
        &self,
        metadata: &tonic::metadata::MetadataMap,
        spec: GrpcRequestSpec<'_>,
    ) -> Result<(), Status> {
        if self.state.runtime.is_draining() {
            return Err(Status::unavailable("server is draining"));
        }
        let Some(auth) = self.state.auth.as_ref() else {
            return Ok(());
        };
        let mut context = grpc_request_context(&self.state.config.tenant_id, &spec, metadata);
        self.state.canonicalize_auth_context(&mut context);
        match auth.evaluate_access(&context).await {
            AccessDecision::Allow => Ok(()),
            AccessDecision::Deny(deny) => {
                Err(grpc_status_from_http_status(deny.status, &deny.message))
            }
        }
    }

    /// Try-only, deliberately. Every caller reaches here holding admission from
    /// another path -- the action-result handler holds its materialization
    /// budget, the write handlers their gRPC decode reservation -- and all of it
    /// draws on the same transient pool. Waiting for that pool while holding
    /// part of it is hold-and-wait. `AtomicMaterializationBudget::reserve` is
    /// the shape that can wait: one acquisition, taken before anything is held.
    fn retain_unary_response_materialization<T: Message>(
        &self,
        response: &mut Response<T>,
        label: &str,
    ) -> Result<(), Status> {
        let encoded_bytes = response.get_ref().encoded_len();
        let permit = self
            .state
            .memory
            .try_acquire_response_materialization(encoded_bytes)
            .map_err(|_| {
                let kind = if encoded_bytes.saturating_mul(2)
                    > self.state.memory.reapi_materialization_limit_bytes()
                {
                    shed_kind::REAPI_REQUEST_BUDGET
                } else {
                    shed_kind::REAPI_MATERIALIZATION
                };
                record_materialization_rejection(&self.state, kind);
                Status::resource_exhausted(format!(
                    "{label} was rejected because the concurrent REAPI response materialization pool is exhausted"
                ))
            })?;
        if let Some(permit) = permit {
            response.extensions_mut().insert(
                crate::memory::ResponseTransportGuard::from_materialization_permits(vec![permit]),
            );
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
            reapi_usage_artifact_kind(metadata),
            bytes,
        );
    }

    // Record a received gRPC upload (ingress) against the usage rollups. See
    // [`record_reapi_download`] for the parity and call-site conventions.
    pub(super) fn record_reapi_upload(
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
            reapi_usage_artifact_kind(metadata),
            bytes,
        );
    }

    fn record_reapi_cache_event(
        &self,
        metadata: &tonic::metadata::MetadataMap,
        namespace_id: &str,
        observation: ReapiCacheObservation<'_>,
    ) {
        let context = self.reapi_cache_event_context(metadata, namespace_id);
        self.record_reapi_cache_event_with_context(context.as_ref(), observation);
    }

    fn reapi_cache_event_context(
        &self,
        metadata: &tonic::metadata::MetadataMap,
        namespace_id: &str,
    ) -> Option<Arc<ReapiCacheAnalyticsContext>> {
        self.state.analytics.as_ref()?;
        let context =
            reapi_cache_event_context(metadata, namespace_id, &self.state.config.tenant_id);
        if context.is_none() {
            // Analytics is configured but this request carries no usable Bazel
            // RequestMetadata, so every cache observation on it is discarded.
            // Counting the discard keeps it apart from "no traffic at all":
            // without this, a fleet serving cache hits and a fleet dropping
            // every one of them both report zero reapi_cache events.
            self.state.metrics.record_analytics_event(
                "reapi_cache",
                "skipped_no_bazel_metadata",
                1,
            );
        }
        context
    }

    fn record_reapi_cache_event_with_context(
        &self,
        context: Option<&Arc<ReapiCacheAnalyticsContext>>,
        observation: ReapiCacheObservation<'_>,
    ) {
        self.enqueue_reapi_cache_event(context, observation, None);
    }

    fn record_reapi_cache_event_with_output(
        &self,
        metadata: &tonic::metadata::MetadataMap,
        namespace_id: &str,
        observation: ReapiCacheObservation<'_>,
        result: &reapi::ActionResult,
    ) {
        let context = self.reapi_cache_event_context(metadata, namespace_id);
        self.enqueue_reapi_cache_event(context.as_ref(), observation, Some(result));
    }

    fn enqueue_reapi_cache_event(
        &self,
        context: Option<&Arc<ReapiCacheAnalyticsContext>>,
        observation: ReapiCacheObservation<'_>,
        result: Option<&reapi::ActionResult>,
    ) {
        let (Some(analytics), Some(context)) = (self.state.analytics.as_ref(), context) else {
            return;
        };

        analytics.enqueue_reapi_cache_event(|| ReapiCacheAnalyticsEvent {
            event_id: uuid::Uuid::now_v7(),
            context: Arc::clone(context),
            operation: observation.operation,
            outcome: observation.outcome,
            action_digest: observation.digest.to_owned(),
            output_path: result.map(action_result_output_path).unwrap_or_default(),
            size: observation.size,
            duration_us: observation
                .duration
                .as_micros()
                .try_into()
                .unwrap_or(u64::MAX),
            observed_at_ms: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis()
                .try_into()
                .unwrap_or(u64::MAX),
        });
    }

    // Direct-blob presence with FindMissingBlobs' lifetime extension: the client
    // stops uploading and relies on the blob staying. Composite blobs are not
    // consulted, because decoding a recipe runs before staging admission and is
    // not charged to it; such writes, and failed lookups, upload normally.
    async fn write_target_already_present(&self, resource: &BlobResource) -> bool {
        let store = &self.state.store;
        let present = if store.segment_ring_is_aging() {
            store
                .artifact_exists_extending_lifetime(
                    ArtifactProducer::Reapi,
                    &resource.namespace_id,
                    &resource.key,
                    RefreshTrigger::FindMissing,
                )
                .await
        } else {
            store
                .artifact_exists(
                    ArtifactProducer::Reapi,
                    &resource.namespace_id,
                    &resource.key,
                )
                .await
        };
        present.unwrap_or_else(|error| {
            tracing::debug!("bytestream write presence check failed: {error}");
            false
        })
    }

    // Reads a write of an already stored blob to completion without staging,
    // decoding, hashing, or persisting it, and answers as a full write does.
    // Answering early instead would make the server reset a stream the client
    // is still sending on; h2 counts the resulting errors toward its per-
    // connection rapid-reset limit and then closes the whole connection.
    async fn discard_stored_write(
        &self,
        stream: &mut tonic::Streaming<bytestream::WriteRequest>,
        mut first_chunk: bytestream::WriteRequest,
        resource: BlobResource,
    ) -> Result<Response<bytestream::WriteResponse>, Status> {
        let wire_limit = match resource.compressor {
            BlobCompressor::Identity => resource.size_bytes,
            BlobCompressor::Zstd => compressed_wire_ceiling(resource.size_bytes),
        };
        let resource_name = std::mem::take(&mut first_chunk.resource_name);
        let mut wire_received = 0_u64;
        let mut stall_deadline = tokio::time::Instant::now() + REAPI_WRITE_STALL_TIMEOUT;
        let mut next = Some(first_chunk);
        let finished = loop {
            let chunk = match next.take() {
                Some(chunk) => chunk,
                None => match tokio::time::timeout_at(stall_deadline, stream.message()).await {
                    Ok(result) => match result? {
                        Some(chunk) => chunk,
                        None => break false,
                    },
                    Err(_elapsed) => {
                        return Err(Status::deadline_exceeded(format!(
                            "no upload progress within {}s; aborting stalled write",
                            REAPI_WRITE_STALL_TIMEOUT.as_secs()
                        )));
                    }
                },
            };
            if !chunk.resource_name.is_empty() && chunk.resource_name != resource_name {
                // The first chunk's name was taken above, so it compares empty.
                return Err(Status::invalid_argument("resource_name changed mid-stream"));
            }
            if chunk.write_offset < 0 || chunk.write_offset as u64 != wire_received {
                return Err(Status::invalid_argument("unexpected write_offset"));
            }
            wire_received = wire_received.saturating_add(chunk.data.len() as u64);
            if wire_received > wire_limit {
                return Err(Status::invalid_argument(
                    "write data exceeds the declared blob size",
                ));
            }
            if !chunk.data.is_empty() {
                stall_deadline = tokio::time::Instant::now() + REAPI_WRITE_STALL_TIMEOUT;
            }
            if chunk.finish_write {
                break true;
            }
        };
        if !finished {
            return Err(Status::invalid_argument("write stream did not finish"));
        }
        if resource.compressor == BlobCompressor::Identity && wire_received != resource.size_bytes {
            return Err(Status::invalid_argument(
                "uploaded blob size did not match digest",
            ));
        }
        // The discarded bytes were the client's only copy in this request, so
        // a blob evicted while they streamed must not be acknowledged. The
        // retry restarts through the staging path.
        if !self.write_target_already_present(&resource).await {
            return Err(Status::unavailable(
                "blob was evicted during the upload; restart the write from offset zero",
            ));
        }
        self.state
            .store
            .acknowledge_existing_client_manifest()
            .await
            .map_err(Status::internal)?;
        self.state
            .metrics
            .record_artifact_write(ArtifactProducer::Reapi, "already_present", 0);
        Ok(Response::new(bytestream::WriteResponse {
            committed_size: wire_received as i64,
        }))
    }

    #[allow(clippy::too_many_arguments)]
    fn coalesce_staging(
        &self,
        mut data: &[u8],
        buffer: &mut Vec<u8>,
        window: usize,
        temp_file: &PersistentFile,
        file_cache_policy: FileCachePolicy,
        cache_drop_interval: u64,
        staged_on_disk: &mut u64,
        advised_through: &mut u64,
    ) -> Result<(), Status> {
        while !data.is_empty() {
            if buffer.is_empty() && data.len() >= window {
                return self.write_staging(
                    data,
                    temp_file,
                    file_cache_policy,
                    cache_drop_interval,
                    staged_on_disk,
                    advised_through,
                );
            }
            let consumed = fill_staging_window(buffer, window, data);
            data = &data[consumed..];
            if buffer.len() == window {
                self.write_staging(
                    buffer,
                    temp_file,
                    file_cache_policy,
                    cache_drop_interval,
                    staged_on_disk,
                    advised_through,
                )?;
                buffer.clear();
            }
        }
        Ok(())
    }

    /// Writes the coalesced staging bytes at the staged length with positioned
    /// writes straight from the caller's buffer: no second copy is queued on a
    /// detached writer, so the bytes never outlive the upload's admission. In
    /// page-cache drop intervals, completed ranges are synced and released
    /// through the same handle so a bounded staging window stays bounded.
    #[allow(clippy::too_many_arguments)]
    fn write_staging(
        &self,
        staged: &[u8],
        temp_file: &PersistentFile,
        file_cache_policy: FileCachePolicy,
        cache_drop_interval: u64,
        staged_on_disk: &mut u64,
        advised_through: &mut u64,
    ) -> Result<(), Status> {
        let mut remaining = staged;
        while !remaining.is_empty() {
            let to_boundary = cache_drop_interval - *staged_on_disk % cache_drop_interval;
            let count = remaining.len().min(to_boundary as usize);
            let (data, rest) = remaining.split_at(count);
            remaining = rest;
            let offset = *staged_on_disk;
            run_blocking_file_operation(|| temp_file.write_all_at(data, offset))
                .map_err(|error| Status::internal(format!("failed to write temp blob: {error}")))?;
            *staged_on_disk = staged_on_disk.saturating_add(data.len() as u64);
            if file_cache_policy.should_drop(
                self.state.memory.should_reclaim_file_cache(),
                self.state.memory.foreground_transient_reserved_bytes(),
            ) && staged_on_disk.saturating_sub(*advised_through) >= cache_drop_interval
            {
                let (offset, length) = (*advised_through, *staged_on_disk - *advised_through);
                run_blocking_file_operation(|| {
                    temp_file.sync_data()?;
                    temp_file.drop_cached_pages(offset, length)
                })
                .map_err(|error| {
                    Status::internal(format!("failed to release temp blob file cache: {error}"))
                })?;
                self.state
                    .io
                    .metrics()
                    .record_memory_action("staging_file_cache_drop");
                *advised_through = *staged_on_disk;
            }
        }
        Ok(())
    }

    // Body of ByteStream::write. Every step here is fallible via `?`; the caller
    // (write) removes a staged path on any error this returns. Small uploads stay
    // in their admitted memory and disarm that cleanup before any suspension can
    // observe them as file-backed.
    async fn write_stream(
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
        let (metadata, mut extensions, mut stream) = request.into_parts();
        let analytics_started_at = Instant::now();
        let memory_admission = extensions
            .remove::<GrpcWriteAdmission>()
            .ok_or_else(|| Status::internal("ByteStream decode admission was not propagated"))?;
        let mut temp_file = None::<PersistentFile>;
        let mut memory_payload = None;
        let mut resource_name = None::<String>;
        let mut resource = None::<BlobResource>;
        let mut file_cache_policy = FileCachePolicy::Adaptive;
        // `stored_written` counts decoded bytes on disk / in the memory
        // payload; it always equals the declared uncompressed size at the end.
        // `wire_received` counts bytes the client sent (equals `stored_written`
        // for identity, is the compressed byte count for zstd) and is what
        // `chunk.write_offset` and `committed_size` are compared against.
        let mut stored_written = 0_u64;
        let mut wire_received = 0_u64;
        let mut advised_through = 0_u64;
        let mut staged_on_disk = 0_u64;
        let mut staging_buffer = Vec::new();
        let mut staging_buffer_bytes = 0_usize;
        let mut cache_drop_interval = FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES;
        let mut hasher = Sha256::new();
        let mut finished = false;
        // Set after the first chunk once the resource is parsed; a compressed
        // stream owns a streaming decoder whose scratch buffer is bounded to
        // what the declared uncompressed size still allows and drained per
        // chunk. Bomb protection is enforced by the sink itself, one write
        // ahead of the per-chunk size check below.
        let mut zstd_decoder: Option<zstd::stream::write::Decoder<'_, BoundedZstdDecoderSink>> =
            None;

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
            if let Some(existing) = &resource_name {
                if !chunk.resource_name.is_empty() && existing != &chunk.resource_name {
                    return Err(Status::invalid_argument("resource_name changed mid-stream"));
                }
            } else {
                if chunk.resource_name.is_empty() {
                    return Err(Status::invalid_argument(
                        "first write request must include resource_name",
                    ));
                }
                let parsed_resource = parse_write_resource_name(&chunk.resource_name)?;
                let write_spec = GrpcRequestSpec {
                    operation: "artifact.write",
                    namespace_id: Some(&parsed_resource.namespace_id),
                };
                self.authorize_metadata(&metadata, write_spec).await?;
                if self.write_target_already_present(&parsed_resource).await {
                    cleanup.disarm();
                    return self
                        .discard_stored_write(&mut stream, chunk, parsed_resource)
                        .await;
                }
                let (policy, admitted_window) =
                    memory_admission.try_configure_staging(parsed_resource.size_bytes)?;
                file_cache_policy = policy;
                cache_drop_interval =
                    admitted_window.clamp(1, FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES);
                memory_payload = (parsed_resource.size_bytes <= SEGMENT_COPY_BUFFER_BYTES as u64
                    && matches!(file_cache_policy, FileCachePolicy::Foreground { .. })
                    && self.state.store.direct_small_uploads_enabled())
                .then(|| {
                    usize::try_from(parsed_resource.size_bytes)
                        .ok()
                        .and_then(try_allocate_exact_vec)
                })
                .flatten();
                if memory_payload.is_some() {
                    cleanup.disarm();
                } else {
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
                    if let Some(parent) = temp_path.parent() {
                        self.state
                            .io
                            .create_dir_all(parent)
                            .await
                            .map_err(Status::internal)?;
                    }
                    temp_file = Some(
                        self.state
                            .io
                            .create_new_persistent_file(temp_path)
                            .await
                            .map_err(Status::internal)?,
                    );
                    // Bounded by the staging window admitted above, which
                    // already charges the staged bytes as resident. Staging
                    // writes go straight from this buffer to the file, so it
                    // is the upload's only heap copy of staged bytes.
                    staging_buffer_bytes =
                        admitted_window.min(REAPI_STAGING_WRITE_BUFFER_BYTES) as usize;
                    staging_buffer = Vec::with_capacity(staging_buffer_bytes);
                }
                if parsed_resource.compressor == BlobCompressor::Zstd {
                    zstd_decoder = Some(
                        zstd::stream::write::Decoder::new(BoundedZstdDecoderSink::default())
                            .map_err(|error| {
                                Status::internal(format!(
                                    "failed to build zstd decoder for compressed write: {error}"
                                ))
                            })?,
                    );
                }
                resource = Some(parsed_resource);
                resource_name = Some(chunk.resource_name);
            }
            if chunk.write_offset < 0 || chunk.write_offset as u64 != wire_received {
                return Err(Status::invalid_argument("unexpected write_offset"));
            }
            let expected_size = resource
                .as_ref()
                .expect("resource is initialized with the first chunk")
                .size_bytes;
            let is_compressed = zstd_decoder.is_some();
            if !is_compressed
                && stored_written.saturating_add(chunk.data.len() as u64) > expected_size
            {
                return Err(Status::invalid_argument(
                    "write data exceeds the declared blob size",
                ));
            }
            if !chunk.data.is_empty() {
                // Feed the chunk into the decoder (identity is a straight
                // borrow) and get a `&[u8]` view of the decoded bytes for the
                // downstream copy loop. For zstd, refresh the sink's per-chunk
                // budget to whatever the declared size still allows so a
                // compression bomb aborts inside `write_all` at the first
                // overflowing byte, without materializing a full chunk of
                // expansion into the sink first.
                let decoded_owned;
                let decoded: &[u8] = if let Some(decoder) = zstd_decoder.as_mut() {
                    decoder.get_mut().remaining = expected_size.saturating_sub(stored_written);
                    std::io::Write::write_all(decoder, &chunk.data).map_err(|error| {
                        Status::invalid_argument(format!(
                            "failed to decode zstd upload chunk: {error}"
                        ))
                    })?;
                    // The `write::Decoder` may hold decoded bytes in its
                    // internal scratch buffer until the next write pushes them
                    // to the inner writer; flush forces them through so the
                    // per-chunk drain sees every decoded byte.
                    std::io::Write::flush(decoder).map_err(|error| {
                        Status::invalid_argument(format!("failed to flush zstd decoder: {error}"))
                    })?;
                    // Take the sink's bytes buffer so we can process it
                    // without holding a mutable borrow across the write path;
                    // the sink stays in place with its `remaining` budget
                    // refreshed on the next round.
                    decoded_owned = std::mem::take(&mut decoder.get_mut().bytes);
                    &decoded_owned[..]
                } else {
                    &chunk.data[..]
                };
                if is_compressed
                    && stored_written.saturating_add(decoded.len() as u64) > expected_size
                {
                    return Err(Status::invalid_argument(
                        "compressed write decompressed past the declared blob size (possible bomb)",
                    ));
                }
                if !decoded.is_empty() {
                    hasher.update(decoded);
                    stored_written = stored_written.saturating_add(decoded.len() as u64);
                    if let Some(payload) = memory_payload.as_mut() {
                        payload.extend_from_slice(decoded);
                    } else {
                        // Coalesce wire chunks (Bazel sends 16 KiB) into one
                        // staging write per buffer: each write leaves the
                        // worker for a blocking file operation, and one per
                        // wire chunk would pay that hand-off per 16 KiB.
                        if decoded.len() < staging_buffer_bytes - staging_buffer.len() {
                            fill_staging_window(&mut staging_buffer, staging_buffer_bytes, decoded);
                        } else {
                            self.coalesce_staging(
                                decoded,
                                &mut staging_buffer,
                                staging_buffer_bytes,
                                temp_file
                                    .as_ref()
                                    .expect("file-backed uploads initialize their staging file"),
                                file_cache_policy,
                                cache_drop_interval,
                                &mut staged_on_disk,
                                &mut advised_through,
                            )?;
                        }
                    }
                }
                wire_received = wire_received.saturating_add(chunk.data.len() as u64);
                if is_compressed && wire_received > compressed_wire_ceiling(expected_size) {
                    // zstd skippable frames decode to zero bytes, so a client
                    // could otherwise keep a compressed write open with
                    // unbounded wire bytes while `stored_written` sits under
                    // the declared cap. Refuse anything past the largest
                    // valid compressed form of the declared size.
                    return Err(Status::invalid_argument(
                        "compressed write exceeds the largest valid zstd-encoded form of the declared blob size",
                    ));
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
        // Flush any bytes the decoder was still holding onto (final zstd
        // frame bytes) into the running hasher / staged output. Every
        // in-loop write already flushed the scratch through mem::take, so
        // this is a belt-and-braces path for the last partial chunk. Refresh
        // the sink budget for the trailing bytes with the same rule the
        // in-loop step uses.
        if let Some(mut decoder) = zstd_decoder.take() {
            decoder.get_mut().remaining = resource.size_bytes.saturating_sub(stored_written);
            std::io::Write::flush(&mut decoder).map_err(|error| {
                Status::invalid_argument(format!(
                    "failed to flush zstd decoder at end of stream: {error}"
                ))
            })?;
            let mut trailing = decoder.into_inner().bytes;
            if !trailing.is_empty() {
                if stored_written.saturating_add(trailing.len() as u64) > resource.size_bytes {
                    return Err(Status::invalid_argument(
                        "compressed write decompressed past the declared blob size (possible bomb)",
                    ));
                }
                hasher.update(&trailing);
                stored_written = stored_written.saturating_add(trailing.len() as u64);
                if let Some(payload) = memory_payload.as_mut() {
                    payload.extend_from_slice(&trailing);
                } else {
                    self.coalesce_staging(
                        &trailing,
                        &mut staging_buffer,
                        staging_buffer_bytes,
                        temp_file
                            .as_ref()
                            .expect("file-backed uploads initialize their staging file"),
                        file_cache_policy,
                        cache_drop_interval,
                        &mut staged_on_disk,
                        &mut advised_through,
                    )?;
                }
            }
            trailing.clear();
        }
        if let Some(file) = temp_file.as_ref()
            && !staging_buffer.is_empty()
        {
            self.write_staging(
                &staging_buffer,
                file,
                file_cache_policy,
                cache_drop_interval,
                &mut staged_on_disk,
                &mut advised_through,
            )?;
        }
        drop(staging_buffer);
        if stored_written != resource.size_bytes {
            return Err(Status::invalid_argument(
                "uploaded blob size did not match digest",
            ));
        }
        if !digest_matches_hex(hasher.finalize().as_ref(), resource.hash()) {
            return Err(Status::invalid_argument(
                "uploaded blob digest did not match content",
            ));
        }

        // Staging writes completed synchronously, so the file already holds
        // every byte; release its descriptor before the store opens the path.
        drop(temp_file.take());

        // The persist reports `already_present` from under the store's
        // per-artifact write lock, which decides billing below: a re-uploaded
        // blob (retry, or a client that skips FindMissingBlobs) must not be
        // billed twice — matching the HTTP upload path's `artifact_exists`
        // short-circuit — and concurrent uploads of the same missing blob
        // resolve to exactly one billed writer.
        let persisted = if let Some(payload) = memory_payload.as_deref() {
            self.state
                .store
                .persist_admitted_artifact_from_bytes_and_replicate(
                    ArtifactProducer::Reapi,
                    &resource.namespace_id,
                    &resource.key,
                    "application/octet-stream",
                    payload,
                    file_cache_policy,
                )
                .await
        } else {
            self.state
                .store
                .persist_artifact_from_path_and_replicate(
                    ArtifactProducer::Reapi,
                    &resource.namespace_id,
                    &resource.key,
                    "application/octet-stream",
                    StagedArtifactPath::new(temp_path, file_cache_policy),
                    None,
                )
                .await
        }
        .map_err(|error| {
            if is_fd_pool_exhausted_error(&error) {
                Status::resource_exhausted(format!(
                    "file descriptor pool exhausted while persisting CAS blob: {error}"
                ))
            } else {
                Status::internal(format!("failed to persist CAS blob: {error}"))
            }
        })?;
        if persisted.already_present {
            self.state
                .store
                .acknowledge_existing_client_manifest()
                .await
                .map_err(Status::internal)?;
        }
        self.state.metrics.record_artifact_write(
            ArtifactProducer::Reapi,
            "ok",
            persisted.manifest.size,
        );

        // `committed_size` reports the wire-side count (compressed bytes for a
        // zstd upload) so it matches the `write_offset` the client tracked.
        let response = Response::new(bytestream::WriteResponse {
            committed_size: wire_received as i64,
        });
        // Book usage only after the response is fully built (headers applied) and
        // only when the blob was newly stored, so a re-upload isn't billed twice.
        if !persisted.already_present {
            self.record_reapi_upload(&metadata, &resource.namespace_id, persisted.manifest.size);
            self.record_reapi_cache_event(
                &metadata,
                &resource.namespace_id,
                ReapiCacheObservation {
                    operation: "cas",
                    outcome: "write",
                    digest: resource.hash(),
                    size: persisted.manifest.size,
                    duration: analytics_started_at.elapsed(),
                },
            );
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
        trunk: Option<&str>,
    ) -> Result<MaterializedSnapshot, Status> {
        let cache_key = snapshot_cache_key(namespace_id, trunk);
        let generation = self.state.store.action_cache_generation(namespace_id);
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
            // Drop what the store removed since the index was built before
            // anything is served from it: a view still listing a cascaded entry
            // hands the client a candidate it cannot restore, and it misses
            // without the per-key lookup that would have answered not-found. An
            // index the removal log no longer covers is rebuilt instead.
            let behind_removals = indexes.get_mut(&cache_key).is_some_and(|index| {
                match self
                    .state
                    .store
                    .action_cache_removals_since(namespace_id, index.applied_removal_seq)
                {
                    Some(removals) => {
                        index.apply_removals(&removals);
                        false
                    }
                    None => true,
                }
            });
            if behind_removals {
                indexes.remove(&cache_key);
            }
            let unchanged = indexes
                .get(&cache_key)
                .is_some_and(|index| index.built_at_generation == generation);
            if let Some(index) = indexes.get_mut(&cache_key)
                && (!index.entries.is_empty() || unchanged)
            {
                let stale = index.reconciled_at.elapsed() >= SNAPSHOT_RECONCILE_INTERVAL;
                index.last_used = Instant::now();
                let entries = index.entries.len();
                let removal_seq = index.applied_removal_seq;
                let mut snapshot = self.encode_snapshot(index, after)?;
                drop(indexes);
                self.cache_full_view(&cache_key, after, entries, removal_seq, &snapshot);
                snapshot.retain_response_memory()?;
                if stale {
                    let _build =
                        self.ensure_index_build(namespace_id, trunk, IndexBuildTrigger::Serve);
                }
                return Ok(snapshot);
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
                .get(&cache_key)
                .cloned()
                .filter(|view| self.nothing_removed_since(namespace_id, view.removal_seq));
            if let Some(cached) = cached {
                let permit = self
                    .state
                    .memory
                    .try_acquire_response_materialization(cached.bytes.len())
                    .map_err(|_| {
                        Status::resource_exhausted(
                            "action-cache snapshot serve declined under memory pressure",
                        )
                    })?;
                let _build = self.ensure_index_build(namespace_id, trunk, IndexBuildTrigger::Serve);
                return Ok(MaterializedSnapshot::new((*cached.bytes).clone(), permit));
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
        let build = self.ensure_index_build(namespace_id, trunk, IndexBuildTrigger::Serve);
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
        let Some(index) = indexes.get_mut(&cache_key) else {
            return Err(Status::unavailable(
                "action-cache snapshot index was not retained; use per-key lookup and retry",
            ));
        };
        match self
            .state
            .store
            .action_cache_removals_since(namespace_id, index.applied_removal_seq)
        {
            Some(removals) => {
                index.apply_removals(&removals);
            }
            None => {
                return Err(Status::unavailable(
                    "action-cache snapshot index fell behind its removals; use per-key lookup and retry",
                ));
            }
        }
        index.last_used = Instant::now();
        let entries = index.entries.len();
        let removal_seq = index.applied_removal_seq;
        let mut snapshot = self.encode_snapshot(index, after)?;
        drop(indexes);
        self.cache_full_view(&cache_key, after, entries, removal_seq, &snapshot);
        snapshot.retain_response_memory()?;
        Ok(snapshot)
    }

    /// Whether the cached full view still describes the store: nothing it could
    /// advertise was removed since it was encoded. A stale one is not served,
    /// and the request waits for the rebuild like a cold one.
    #[cfg(test)]
    fn served_full_is_current(&self, namespace_id: &str, cache_key: &str) -> bool {
        let view = self
            .snapshot_cache
            .served_full
            .lock()
            .expect("snapshot served_full lock poisoned")
            .get(cache_key)
            .cloned();
        view.is_some_and(|view| self.nothing_removed_since(namespace_id, view.removal_seq))
    }

    fn nothing_removed_since(&self, namespace_id: &str, removal_seq: u64) -> bool {
        self.state
            .store
            .action_cache_removals_since(namespace_id, removal_seq)
            .is_some_and(|removals| removals.is_empty())
    }

    /// Caches a full (`after == 0`) encoded view as the namespace's
    /// `served_full`, so a serve that lands while the index is out for a
    /// reconcile returns it instead of shedding to UNAVAILABLE. A delta is
    /// relative to a client's watermark and cannot be replayed, so it is not
    /// cached.
    fn cache_full_view(
        &self,
        cache_key: &str,
        after: u64,
        entries: usize,
        removal_seq: u64,
        bytes: &[u8],
    ) {
        if after != 0 {
            return;
        }
        if entries == 0 {
            self.snapshot_cache
                .served_full
                .lock()
                .expect("snapshot served_full lock poisoned")
                .remove(cache_key);
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
        {
            let mut served_full = self
                .snapshot_cache
                .served_full
                .lock()
                .expect("snapshot served_full lock poisoned");
            // Concurrent serves finish in any order; one encoded before a later
            // removal must not replace a view that already reflects it.
            if served_full
                .get(cache_key)
                .is_some_and(|view| view.removal_seq > removal_seq)
            {
                return;
            }
            served_full.insert(
                cache_key.to_owned(),
                ServedFullView {
                    bytes: std::sync::Arc::new(bytes.to_vec()),
                    removal_seq,
                },
            );
        }
        self.snapshot_cache
            .trim_to(target_bytes, "capacity", &self.state.metrics);
    }

    fn encode_snapshot(
        &self,
        index: &NamespaceSnapshotIndex,
        after: u64,
    ) -> Result<MaterializedSnapshot, Status> {
        let response_budget = self.state.memory.reapi_response_budget_bytes();
        let materialization_limit = self.state.memory.reapi_materialization_limit_bytes();
        let mut content_budget = response_budget.min(SNAPSHOT_CONTENT_BUDGET_BYTES).min(
            materialization_limit
                .saturating_sub(SNAPSHOT_COMPRESSION_SCRATCH_BYTES)
                .saturating_div(2),
        );
        while content_budget > 0 {
            let peak_bytes = snapshot_encode_peak_bytes(content_budget);
            if peak_bytes <= materialization_limit {
                break;
            }
            let excess = peak_bytes - materialization_limit;
            content_budget = content_budget.saturating_sub(excess.div_ceil(2).max(1));
        }
        if content_budget == 0 {
            return Err(Status::resource_exhausted(
                "action-cache snapshot encode declined under memory pressure",
            ));
        }
        let peak_bytes = snapshot_encode_peak_bytes(content_budget);
        let permit = self
            .state
            .memory
            .try_acquire_reapi_materialization(peak_bytes)
            .map_err(|_| {
                Status::resource_exhausted(
                    "action-cache snapshot encode is waiting for memory headroom",
                )
            })?;
        let bytes = index.encode_with_budget(after, content_budget).map_err(
            |SnapshotEncodeError::WireLimitExceeded| {
                Status::resource_exhausted(
                    "action-cache snapshot could not fit the response wire ceiling",
                )
            },
        )?;
        Ok(MaterializedSnapshot::new(bytes, permit))
    }

    /// The namespace's in-flight index build, starting one when none is
    /// running. Requests share a single reconcile; the spawned task takes the
    /// index out for the reconcile and reinserts it (with the LRU bound
    /// applied) whether the reconcile succeeded or failed, so accumulated
    /// progress survives request aborts and transient store errors alike.
    /// While the index is out, serves fall back to the cached full view
    /// (`served_full`) rather than the cold path.
    fn ensure_index_build(
        &self,
        namespace_id: &str,
        trunk: Option<&str>,
        trigger: IndexBuildTrigger,
    ) -> SharedIndexBuild {
        let cache_key = snapshot_cache_key(namespace_id, trunk);
        let mut builds = self
            .snapshot_cache
            .builds
            .lock()
            .expect("snapshot builds lock poisoned");
        if let Some(build) = builds.get(&cache_key) {
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
        let trunk = trunk.map(str::to_owned);
        let build_key = cache_key.clone();
        // Spawned while holding the builds lock, so the task's terminal
        // removal (which takes the same lock) cannot run before the insert
        // below — the entry it removes is always its own. The body is
        // panic-guarded and the removal sits OUTSIDE it: a reconcile panic
        // that leaked the entry left a dead shared future in the map, and
        // every later build request for the namespace resolved to that
        // corpse — snapshots stayed bricked until the pod restarted.
        let cleanup_key = cache_key.clone();
        let cleanup_namespace = namespace.clone();
        let cleanup_cache = cache.clone();
        let task = tokio::spawn(async move {
            let outcome = futures_util::FutureExt::catch_unwind(std::panic::AssertUnwindSafe(
                Self::run_index_build(cache, state, namespace, trunk, build_key, trigger),
            ))
            .await;
            cleanup_cache
                .builds
                .lock()
                .expect("snapshot builds lock poisoned")
                .remove(&cleanup_key);
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
        builds.insert(cache_key, build.clone());
        build
    }

    fn refreshable_snapshot_indexes(&self) -> Vec<(String, Option<String>)> {
        let indexes = self
            .snapshot_cache
            .indexes
            .lock()
            .expect("snapshot cache lock poisoned");
        indexes
            .iter()
            .filter(|(_, index)| {
                should_refresh_snapshot_index(
                    index.reconciled_at.elapsed(),
                    index.last_used.elapsed(),
                )
            })
            .map(|(cache_key, _)| {
                let (namespace_id, trunk) = snapshot_cache_key_parts(cache_key);
                (namespace_id.to_owned(), trunk.map(str::to_owned))
            })
            .collect()
    }

    fn refresh_snapshot_indexes(&self) {
        for (namespace_id, trunk) in self.refreshable_snapshot_indexes() {
            let _build = self.ensure_index_build(
                &namespace_id,
                trunk.as_deref(),
                IndexBuildTrigger::Refresh,
            );
        }
    }

    /// The build task's body: permit, reconcile, reinsert. The caller owns
    /// the builds-map entry cleanup, which must run whether this returns or
    /// panics.
    async fn run_index_build(
        cache: std::sync::Arc<SnapshotCache>,
        state: SharedState,
        namespace: String,
        trunk: Option<String>,
        cache_key: String,
        trigger: IndexBuildTrigger,
    ) -> Result<(), String> {
        tracing::info!(
            namespace_id = namespace.as_str(),
            "action-cache snapshot index build started"
        );
        // Sustained memory pressure denies the expensive reconcile (manifest
        // scan + action-result load) as background work, but the presence gate
        // is correctness: a frozen index keeps advertising blobs that CAS
        // eviction removes, and the build it gates dies on the first missing
        // object. Run a gate-only pass over the existing index so the served
        // view stays honest while the load is deferred — this is also how a
        // frozen index recovers after a long pressure window.
        if !state.memory.allow_background_admission() {
            return Self::run_snapshot_pressure_gate(cache, state, namespace, cache_key, trigger)
                .await;
        }
        let _build_guard = cache.build_lock.lock().await;
        if !state.memory.allow_background_admission() {
            drop(_build_guard);
            return Self::run_snapshot_pressure_gate(cache, state, namespace, cache_key, trigger)
                .await;
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
            .min(state.memory.reapi_materialization_limit_bytes() / 2)
            .max(1);
        let build_budgets = SnapshotBuildBudgets::new(budget, index_max_bytes);
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
        let generation = state.store.action_cache_generation(&namespace);
        // Read before the scan: every removal up to here is already out of the
        // store it reads, and later ones are applied on the next serve.
        let removal_seq = state.store.action_cache_removal_seq();
        let index = cache
            .indexes
            .lock()
            .expect("snapshot cache lock poisoned")
            .remove(&cache_key)
            .unwrap_or_else(NamespaceSnapshotIndex::new);
        cache.trim_to(
            cache.max_bytes.saturating_sub(build_budgets.index_bytes),
            "build_headroom",
            &state.metrics,
        );
        let (mut index, result) = match reconcile_snapshot_index(
            &state,
            &namespace,
            trunk.as_deref(),
            index,
            build_budgets,
        )
        .await
        {
            Ok(mut index) => {
                index.reconciled_at = Instant::now();
                index.built_at_generation = generation;
                index.applied_removal_seq = removal_seq;
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
        if trigger == IndexBuildTrigger::Serve {
            index.last_used = Instant::now();
        }
        // The reconcile always presence-gates (it breaks out of the load under
        // pressure rather than skipping the gate), so the index is honest and
        // must be reinserted. Discarding it under pressure froze the served
        // view: serves then fell back to a stale `served_full` that advertised
        // blobs CAS eviction had since removed. The load only ran because
        // pressure was Normal when the build started, so the index is already
        // bounded by its build budget; the trim below keeps the cache in limit.
        Self::reinsert_index(&cache, cache_key.clone(), index);
        cache.trim_to(cache.max_bytes, "capacity", &state.metrics);
        result
    }

    /// Reinserts a reconciled index under the namespace-count bound, evicting
    /// the least-recently-used namespace (and its cached full view) when full.
    fn reinsert_index(cache: &SnapshotCache, cache_key: String, index: NamespaceSnapshotIndex) {
        let mut indexes = cache.indexes.lock().expect("snapshot cache lock poisoned");
        indexes.insert(cache_key, index);
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

    /// Pressure-only build: presence-gates the existing index without the
    /// manifest scan or action-result load (the background work pressure
    /// denies). The gate is what stops a served snapshot from advertising a
    /// blob CAS eviction has removed, so it runs regardless of pressure; the
    /// bounded index is reinserted (not discarded) so serves keep an honest
    /// view instead of falling back to a stale `served_full`.
    async fn run_snapshot_pressure_gate(
        cache: std::sync::Arc<SnapshotCache>,
        state: SharedState,
        namespace: String,
        cache_key: String,
        trigger: IndexBuildTrigger,
    ) -> Result<(), String> {
        let _build_guard = cache.build_lock.lock().await;
        let generation = state.store.action_cache_generation(&namespace);
        let removal_seq = state.store.action_cache_removal_seq();
        let index = cache
            .indexes
            .lock()
            .expect("snapshot cache lock poisoned")
            .remove(&cache_key)
            .unwrap_or_else(NamespaceSnapshotIndex::new);
        let mut index = gate_snapshot_index(&state, &namespace, index).await;
        index.reconciled_at = Instant::now();
        index.built_at_generation = generation;
        index.applied_removal_seq = removal_seq;
        if trigger == IndexBuildTrigger::Serve {
            index.last_used = Instant::now();
        }
        Self::reinsert_index(&cache, cache_key, index);
        state
            .metrics
            .record_memory_action("snapshot_build_pressure_gated");
        cache.trim_to(cache.max_bytes, "capacity", &state.metrics);
        Ok(())
    }
}

#[tonic::async_trait]
impl Capabilities for ReapiService {
    async fn get_capabilities(
        &self,
        request: Request<reapi::GetCapabilitiesRequest>,
    ) -> Result<Response<reapi::ServerCapabilities>, Status> {
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let auth = GrpcRequestSpec {
            operation: "capabilities.read",
            namespace_id: Some(namespace_id),
        };
        self.authorize_request(&request, auth).await?;
        let response = Response::new(reapi::ServerCapabilities {
            cache_capabilities: Some(reapi::CacheCapabilities {
                digest_functions: vec![reapi::digest_function::Value::Sha256 as i32],
                action_cache_update_capabilities: Some(reapi::ActionCacheUpdateCapabilities {
                    update_enabled: true,
                }),
                cache_priority_capabilities: None,
                max_batch_total_size_bytes: MAX_MODULE_TOTAL_BYTES as i64,
                symlink_absolute_path_strategy:
                    reapi::symlink_absolute_path_strategy::Value::Disallowed as i32,
                // Advertise zstd on both the ByteStream/BatchReadBlobs axis
                // and the BatchUpdateBlobs axis so Bazel opts into
                // `compressed-blobs/zstd/...` resource names and sends
                // `compressor: ZSTD` in batch writes. Blobs are still stored
                // uncompressed on disk; compression is a wire-only concern
                // handled in the handlers.
                supported_compressors: vec![reapi::compressor::Value::Zstd as i32],
                supported_batch_update_compressors: vec![reapi::compressor::Value::Zstd as i32],
                max_cas_blob_size_bytes: MAX_MODULE_TOTAL_BYTES as i64,
                split_blob_support: true,
                splice_blob_support: true,
                fast_cdc_2020_params: Some(reapi::FastCdc2020Params {
                    avg_chunk_size_bytes: FAST_CDC_AVERAGE_CHUNK_BYTES,
                    seed: 0,
                }),
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
        let auth = GrpcRequestSpec {
            operation: "artifact.read",
            namespace_id: Some(namespace_id),
        };
        self.authorize_request(&request, auth).await?;
        let analytics_started_at = Instant::now();
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
            let trunk = ref_metadata(&request, "x-tuist-trunk-branch", "x-tuist-trunk-branch-bin");
            let snapshot = self
                .serve_actioncache_snapshot(namespace_id, after, trunk.as_deref())
                .await?;
            let served = snapshot.len() as u64;
            let (snapshot, response_memory) = snapshot.into_parts();
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
                response.extensions_mut().insert(
                    crate::memory::ResponseTransportGuard::from_materialization_permits(vec![
                        permit,
                    ]),
                );
            }
            self.state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "ok", served);
            self.record_reapi_download(request.metadata(), namespace_id, served);
            return Ok(response);
        }
        let presence_lookup = is_presence_lookup(request.metadata());
        let mut materialization_budget =
            std::sync::Mutex::new(MaterializationBudget::new(&self.state));
        let (size_bytes, mut action_result) = match fetch_keyvalue_proto::<reapi::ActionResult>(
            &self.state,
            namespace_id,
            &key,
            "action result",
            !presence_lookup,
            Some(
                materialization_budget
                    .get_mut()
                    .expect("action-cache materialization budget lock poisoned"),
            ),
        )
        .await
        {
            Ok(result) => result,
            Err(status) => {
                if status.code() == tonic::Code::NotFound {
                    self.record_reapi_cache_event(
                        request.metadata(),
                        namespace_id,
                        ReapiCacheObservation {
                            operation: "action_cache",
                            outcome: "miss",
                            digest: &digest.hash,
                            size: 0,
                            duration: analytics_started_at.elapsed(),
                        },
                    );
                }
                return Err(status);
            }
        };
        // Presence gate, the per-key counterpart of the snapshot reconcile's:
        // an entry whose output blobs were evicted is unserveable by
        // construction — the client replaying it hard-fails the build on the
        // first missing object (a production cold build died on its very first
        // resolve this way), while a not-found here is an ordinary miss the
        // client recompiles from and republishes with fresh blobs. Entries
        // older than the snapshot index's scan cap are exactly the ones its
        // reconcile-time gate and cascade never examine, so without this they
        // serve dead forever. This checks every blob a replay fetches — output
        // files, stdout/stderr, and each output directory's tree plus the files
        // it lists — not just output files, so an REAPI client with tree
        // artifacts is covered as well. Mostly existence-cache hits.
        let presence = first_evicted_output(
            &self.state,
            namespace_id,
            &action_result,
            self.state.store.segment_ring_is_aging(),
            !presence_lookup,
            materialization_budget
                .get_mut()
                .expect("action-cache materialization budget lock poisoned"),
        )
        .await
        .map_err(|error| {
            chunk_presence_status(
                &self.state,
                "get_action_result",
                "failed to inspect action-result blobs",
                error,
            )
        })?;
        if let Some(missing) = presence.evicted {
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
            self.record_reapi_cache_event(
                request.metadata(),
                namespace_id,
                ReapiCacheObservation {
                    operation: "action_cache",
                    outcome: "miss",
                    digest: &digest.hash,
                    size: 0,
                    duration: analytics_started_at.elapsed(),
                },
            );
            return Err(Status::not_found(
                "action result references evicted output blobs",
            ));
        }
        // The gate passed, so this response vouches for every blob it
        // references. REAPI asks that those blobs be available "at the time of
        // returning the ActionResult and will be for some period of time
        // afterwards", with their lifetimes increased where applicable. The
        // gate above answers from metadata alone, so nothing on this path has
        // kept them alive. Without this, eviction between here and the
        // client's BatchReadBlobs hands it a missing object, which clang treats
        // as a hard build failure rather than a recompile. A presence lookup
        // reads no outputs, so it vouches for nothing.
        if !presence_lookup {
            self.state.store.extend_artifact_lifetimes(
                ArtifactProducer::Reapi,
                namespace_id,
                &presence.present,
                RefreshTrigger::ActionCache,
            );
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
                !presence_lookup,
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
                !presence_lookup,
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
            // `"*"` is a Kura auth to the REAPI `inline_output_files`
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
            let inline_limit = request
                .get_ref()
                .inline_output_files
                .iter()
                .filter_map(|hint| {
                    hint.strip_prefix("tuist-inline-max-bytes:")?
                        .parse::<i64>()
                        .ok()
                })
                .filter(|limit| *limit >= 0)
                .min();
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
                    if !explicit
                        && inline_limit.is_some_and(|limit| {
                            output_file
                                .digest
                                .as_ref()
                                .is_some_and(|digest| digest.size_bytes > limit)
                        })
                    {
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
                            batch_read_one(&self.state, namespace_id, &digest, budget, explicit)
                                .await,
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
                        self.state.metrics.record_reapi_inline_fallback();
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
        self.state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "ok", size_bytes);
        // Book usage only after the response is fully built (headers applied),
        // matching the other handlers' success-arm convention.
        self.record_reapi_download(request.metadata(), namespace_id, served_bytes);
        self.record_reapi_cache_event_with_output(
            request.metadata(),
            namespace_id,
            ReapiCacheObservation {
                operation: "action_cache",
                outcome: "hit",
                digest: &digest.hash,
                size: served_bytes,
                duration: analytics_started_at.elapsed(),
            },
            response.get_ref(),
        );
        Ok(response)
    }

    async fn update_action_result(
        &self,
        request: Request<reapi::UpdateActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        if request.extensions().get::<GrpcWriteAdmission>().is_none() {
            return Err(Status::internal(
                "write decode admission was not propagated",
            ));
        }
        require_sha256(request.get_ref().digest_function)?;
        let authorization_namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let digest = request
            .get_ref()
            .action_digest
            .as_ref()
            .ok_or_else(|| Status::invalid_argument("missing action_digest"))?;
        if request.get_ref().action_result.is_none() {
            return Err(Status::invalid_argument("missing action_result"));
        }
        let key = action_cache_key(&digest_key(digest)?);
        let auth = GrpcRequestSpec {
            operation: "artifact.write",
            namespace_id: Some(authorization_namespace_id),
        };
        self.authorize_request(&request, auth).await?;
        let analytics_started_at = Instant::now();
        let action_digest = digest.hash.clone();
        let branch = ref_metadata(&request, "x-tuist-branch", "x-tuist-branch-bin");
        let trunk = ref_metadata(&request, "x-tuist-trunk-branch", "x-tuist-trunk-branch-bin");
        let (metadata, mut extensions, mut message) = request.into_parts();
        let _memory_admission = extensions
            .remove::<GrpcWriteAdmission>()
            .expect("write decode admission was checked before authorization");
        let namespace_id = namespace_from_instance(&message.instance_name);
        let action_result = message
            .action_result
            .take()
            .expect("action result was checked before authorization");
        let bytes = action_result.encode_to_vec();
        // Reject an action result we could never replicate. Entries are stored
        // inline and fetched by peers inline, and the inline catch-up path
        // buffers the whole body in RAM, so it is bounded by
        // MAX_INLINE_REPLICATION_BODY_BYTES. Accepting a larger entry would
        // strand it on this node, where no peer could ever fetch it.
        // failed_precondition is non-retriable, so Bazel records the miss and
        // moves on instead of retrying the doomed write.
        if bytes.len() as u64 > MAX_INLINE_REPLICATION_BODY_BYTES {
            // Count the rejection but report 0 written bytes, matching the other
            // failed-write sites, so a rejected write never inflates
            // artifact_write_bytes throughput.
            self.state
                .metrics
                .record_artifact_write(ArtifactProducer::Reapi, "too_large", 0);
            return Err(Status::failed_precondition(format!(
                "action result is {} bytes, exceeds the {} byte limit",
                bytes.len(),
                MAX_INLINE_REPLICATION_BODY_BYTES
            )));
        }
        let (manifest, applied) = self
            .state
            .store
            .persist_inline_artifact_from_bytes_damped_and_replicate(
                ArtifactProducer::Reapi,
                namespace_id,
                &key,
                "application/x-protobuf",
                &bytes,
                branch.as_deref(),
                trunk.as_deref(),
            )
            .await
            .map_err(|error| store_write_status("failed to store action result", error))?;
        // A damped refresh (identical bytes, fresh version) counts under its own
        // result and books no bytes: it stored nothing and wrote no replication
        // feed row, so folding it into "ok" both overstates ingest and makes the
        // write counter incomparable with every counter that only sees applied
        // changes -- a shortfall that reads exactly like replication losing
        // entries. Separating them also makes the damping rate measurable.
        if applied {
            self.state
                .metrics
                .record_artifact_write(ArtifactProducer::Reapi, "ok", manifest.size);
        } else {
            self.state
                .metrics
                .record_artifact_write(ArtifactProducer::Reapi, "damped", 0);
        }
        let mut response = Response::new(action_result);
        self.retain_unary_response_materialization(&mut response, "action result response")?;
        // Book usage only after the response is fully built. Every applied
        // update is billed: an action result is a mutable entry whose content
        // changes across updates, so there is no CAS-style "already present"
        // dedupe — matching the HTTP key-value path, which bills each put.
        // A damped refresh (identical bytes, fresh version) applies nothing
        // and bills nothing.
        if applied {
            self.record_reapi_upload(&metadata, namespace_id, manifest.size);
            self.record_reapi_cache_event_with_output(
                &metadata,
                namespace_id,
                ReapiCacheObservation {
                    operation: "action_cache",
                    outcome: "write",
                    digest: &action_digest,
                    size: manifest.size,
                    duration: analytics_started_at.elapsed(),
                },
                response.get_ref(),
            );
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
        let auth = GrpcRequestSpec {
            operation: "artifact.inspect",
            namespace_id: Some(namespace_id),
        };
        self.authorize_request(&request, auth).await?;
        let message = request.into_inner();
        let namespace_id = namespace_from_instance(&message.instance_name);
        let mut digests = message.blob_digests;
        let mut is_missing = vec![false; digests.len()];
        let mut presence_budget = PresenceBudget::for_request();
        // The digest count is client-controlled up to the 64 MiB decode
        // ceiling, and a batch of segment-backed blobs is answered without an
        // await point, so yield between batches rather than hold a runtime
        // worker for the whole request.
        for (batch, (digests, is_missing)) in digests
            .chunks(FIND_MISSING_BATCH_DIGESTS)
            .zip(is_missing.chunks_mut(FIND_MISSING_BATCH_DIGESTS))
            .enumerate()
        {
            if batch > 0 {
                tokio::task::yield_now().await;
            }
            find_missing_in_batch(
                &self.state,
                namespace_id,
                digests,
                is_missing,
                &mut presence_budget,
            )
            .await?;
        }
        let mut is_missing = is_missing.into_iter();
        digests.retain(|_| is_missing.next().unwrap_or(false));
        let missing = digests;

        let mut response = Response::new(reapi::FindMissingBlobsResponse {
            missing_blob_digests: missing,
        });
        self.retain_unary_response_materialization(&mut response, "missing blobs response")?;
        Ok(response)
    }

    async fn batch_update_blobs(
        &self,
        request: Request<reapi::BatchUpdateBlobsRequest>,
    ) -> Result<Response<reapi::BatchUpdateBlobsResponse>, Status> {
        if request.extensions().get::<GrpcWriteAdmission>().is_none() {
            return Err(Status::internal(
                "write decode admission was not propagated",
            ));
        }
        require_sha256(request.get_ref().digest_function)?;
        let authorization_namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let auth = GrpcRequestSpec {
            operation: "artifact.write",
            namespace_id: Some(authorization_namespace_id),
        };
        self.authorize_request(&request, auth).await?;
        let (metadata, mut extensions, message) = request.into_parts();
        let _memory_admission = extensions
            .remove::<GrpcWriteAdmission>()
            .expect("write decode admission was checked before authorization");
        let namespace_id = namespace_from_instance(&message.instance_name);
        let analytics_context = self.reapi_cache_event_context(&metadata, namespace_id);
        // Accumulate only the bytes this RPC actually stored so the whole batch
        // books a single usage request (matching how ByteStream/HTTP count one
        // request per call), and so already-present blobs are not billed —
        // mirroring the HTTP upload path's `artifact_exists` short-circuit,
        // with presence decided under the store's write lock.
        let mut stored_bytes = 0_u64;
        let mut stored_any = false;

        // Items decode and persist concurrently: each blob still returns only
        // once its own bytes and manifest are durable, but a sequential await
        // per blob made the batch pay one group-commit round per blob. An item
        // future does nothing until the bounded window first polls it, so
        // decoded bytes are only ever held by in-flight items. Response order
        // matches request order.
        let pending: Vec<_> = message
            .requests
            .iter()
            .map(|item| update_batch_blob(&self.state, namespace_id, item))
            .collect();
        let items: Vec<BatchUpdateItem> = futures_util::stream::iter(pending)
            .buffered(BATCH_UPDATE_PERSIST_CONCURRENCY)
            .collect()
            .await;

        let mut responses = Vec::with_capacity(items.len());
        for item in items {
            if let (Some((size, duration)), Some(digest)) =
                (item.stored, item.response.digest.as_ref())
            {
                // Bill the uncompressed size (what the store holds and what an
                // identity read of the same blob transfers), so usage
                // accounting does not change when a client turns wire
                // compression on.
                stored_bytes = stored_bytes.saturating_add(size);
                stored_any = true;
                self.record_reapi_cache_event_with_context(
                    analytics_context.as_ref(),
                    ReapiCacheObservation {
                        operation: "cas",
                        outcome: "write",
                        digest: &digest.hash,
                        size,
                        duration,
                    },
                );
            }
            responses.push(item.response);
        }

        let mut response = Response::new(reapi::BatchUpdateBlobsResponse { responses });
        self.retain_unary_response_materialization(&mut response, "batch update response")?;
        if stored_any {
            self.record_reapi_upload(&metadata, namespace_id, stored_bytes);
        }
        Ok(response)
    }

    async fn batch_read_blobs(
        &self,
        request: Request<reapi::BatchReadBlobsRequest>,
    ) -> Result<Response<reapi::BatchReadBlobsResponse>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let authorization_namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let auth = GrpcRequestSpec {
            operation: "artifact.read",
            namespace_id: Some(authorization_namespace_id),
        };
        self.authorize_request(&request, auth).await?;
        let (metadata, _extensions, message) = request.into_parts();
        let namespace_id = namespace_from_instance(&message.instance_name);
        let analytics_context = self.reapi_cache_event_context(&metadata, namespace_id);
        // Blobs are read concurrently: a sequential await per blob caps the
        // whole batch at per-read latency times batch size, which dominates
        // large read-heavy clients (measured ~4ms per blob serialized). The
        // budget claim is a lock-free atomic subtraction; per-blob failure
        // semantics are unchanged and response order matches request order.
        let digests = message.digests;
        // A client that lists ZSTD among `acceptable_compressors` allows the
        // server to compress the response payload. The server picks; identity
        // stays valid, and we fall back to it for anything that would not
        // actually shrink on the wire.
        let compress_with_zstd = message
            .acceptable_compressors
            .contains(&(reapi::compressor::Value::Zstd as i32));
        // Reserve the whole batch's response memory once, before any blob is
        // read, waiting for a momentarily full pool. The client's digests carry
        // the sizes, so the request can be admitted as a unit; claiming per blob
        // while blobs read concurrently would mean waiting for the pool while
        // already holding part of it.
        let mut budget = AtomicMaterializationBudget::reserve(
            &self.state,
            digests
                .iter()
                .map(|digest| u64::try_from(digest.size_bytes).unwrap_or(0))
                .fold(0_u64, |total, size| total.saturating_add(size)),
        )
        .await?;
        let budget_ref = &budget;
        let read_results: Vec<(reapi::batch_read_blobs_response::Response, Duration)> =
            futures_util::stream::iter(digests.into_iter().map(|digest| {
                let budget = budget_ref;
                async move {
                    let analytics_started_at = Instant::now();
                    let response =
                        match batch_read_one_atomic(&self.state, namespace_id, &digest, budget)
                            .await
                        {
                            Ok(Some(data)) => {
                                let (data, compressor) = if compress_with_zstd {
                                    maybe_compress_zstd_batch_response(data)
                                } else {
                                    (data, 0)
                                };
                                reapi::batch_read_blobs_response::Response {
                                    digest: Some(digest),
                                    data,
                                    compressor,
                                    status: Some(rpc_status(0, "")),
                                }
                            }
                            Ok(None) => reapi::batch_read_blobs_response::Response {
                                digest: Some(digest),
                                data: Vec::new(),
                                compressor: 0,
                                status: Some(rpc_status(5, "blob not found")),
                            },
                            Err(status) => reapi::batch_read_blobs_response::Response {
                                digest: Some(digest),
                                data: Vec::new(),
                                compressor: 0,
                                status: Some(rpc_status_from_grpc_status(&status)),
                            },
                        };

                    (response, analytics_started_at.elapsed())
                }
            }))
            .buffered(16)
            .collect()
            .await;
        let mut responses = Vec::with_capacity(read_results.len());

        for (response, duration) in read_results {
            let outcome = response
                .status
                .as_ref()
                .and_then(|status| match status.code {
                    0 => Some("hit"),
                    5 => Some("miss"),
                    _ => None,
                });

            if let (Some(outcome), Some(digest)) = (outcome, response.digest.as_ref()) {
                // Bill the uncompressed size: this is what the client
                // ultimately consumes and matches identity-path accounting,
                // regardless of whether the wire payload was compressed.
                let uncompressed_size = if outcome == "hit" {
                    u64::try_from(digest.size_bytes).unwrap_or(0)
                } else {
                    0
                };
                self.record_reapi_cache_event_with_context(
                    analytics_context.as_ref(),
                    ReapiCacheObservation {
                        operation: "cas",
                        outcome,
                        digest: &digest.hash,
                        size: uncompressed_size,
                        duration,
                    },
                );
            }

            responses.push(response);
        }
        // Sum the uncompressed bytes served so the whole batch books a single
        // download usage request, matching how ByteStream/HTTP count one
        // request per call. A successful read carries gRPC status code 0; its
        // digest's `size_bytes` is authoritative (the response's `data` length
        // is the compressed length under a zstd-accepting client).
        let served_bytes: u64 = responses
            .iter()
            .filter(|response| {
                response
                    .status
                    .as_ref()
                    .is_some_and(|status| status.code == 0)
            })
            .map(|response| {
                response
                    .digest
                    .as_ref()
                    .and_then(|digest| u64::try_from(digest.size_bytes).ok())
                    .unwrap_or(0)
            })
            .sum();
        let served_any = responses.iter().any(|response| {
            response
                .status
                .as_ref()
                .is_some_and(|status| status.code == 0)
        });

        let mut response = Response::new(reapi::BatchReadBlobsResponse { responses });
        // The single up-front reservation rides with the response, so the bytes
        // stay admitted for as long as the client is reading them.
        let response_memory = budget.take_permit().map(|permit| {
            crate::memory::ResponseTransportGuard::from_materialization_permits(vec![permit])
        });
        if let Some(response_memory) = response_memory {
            response.extensions_mut().insert(response_memory);
        }
        if served_any {
            self.record_reapi_download(&metadata, namespace_id, served_bytes);
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
        request: Request<reapi::SplitBlobRequest>,
    ) -> Result<Response<reapi::SplitBlobResponse>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        self.authorize_request(
            &request,
            GrpcRequestSpec {
                operation: "artifact.read",
                namespace_id: Some(namespace_id),
            },
        )
        .await?;
        let digest = request
            .get_ref()
            .blob_digest
            .as_ref()
            .ok_or_else(|| Status::invalid_argument("missing blob_digest"))?;
        digest_key(digest)?;
        let Some((_manifest, recipe)) = fetch_recipe(&self.state, namespace_id, digest)
            .await
            .map_err(|error| Status::internal(format!("failed to read blob recipe: {error}")))?
        else {
            return Err(Status::not_found("blob has no chunk recipe"));
        };
        if fetch_chunk_manifests(&self.state, namespace_id, &recipe, true)
            .await
            .map_err(|error| Status::internal(format!("failed to inspect blob chunks: {error}")))?
            .is_none()
        {
            return Err(Status::not_found("one or more blob chunks are missing"));
        }
        let mut response = Response::new(reapi::SplitBlobResponse {
            chunk_digests: recipe.chunks().to_vec(),
            chunking_function: recipe.chunking_function_value(),
        });
        self.retain_unary_response_materialization(&mut response, "split blob response")?;
        Ok(response)
    }

    async fn splice_blob(
        &self,
        request: Request<reapi::SpliceBlobRequest>,
    ) -> Result<Response<reapi::SpliceBlobResponse>, Status> {
        if request.extensions().get::<GrpcWriteAdmission>().is_none() {
            return Err(Status::internal(
                "write decode admission was not propagated",
            ));
        }
        require_sha256(request.get_ref().digest_function)?;
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        self.authorize_request(
            &request,
            GrpcRequestSpec {
                operation: "artifact.write",
                namespace_id: Some(namespace_id),
            },
        )
        .await?;
        let (metadata, mut extensions, mut message) = request.into_parts();
        let _memory_admission = extensions
            .remove::<GrpcWriteAdmission>()
            .expect("splice decode admission was checked before authorization");
        let namespace_id = namespace_from_instance(&message.instance_name);
        let blob_digest = message
            .blob_digest
            .take()
            .ok_or_else(|| Status::invalid_argument("missing blob_digest"))?;
        digest_key(&blob_digest)?;
        if blob_digest.size_bytes > MAX_MODULE_TOTAL_BYTES as i64 {
            return Err(Status::out_of_range(format!(
                "blob size exceeds the {} byte limit",
                MAX_MODULE_TOTAL_BYTES
            )));
        }
        let mut presence_budget = PresenceBudget::for_request();
        if presence_keys(
            &self.state,
            namespace_id,
            &blob_digest,
            RefreshTrigger::FindMissing,
            self.state.store.segment_ring_is_aging(),
            &mut presence_budget,
        )
        .await
        .map_err(|error| {
            chunk_presence_status(&self.state, "splice", "failed to inspect blob", error)
        })?
        .is_some()
        {
            let mut response = Response::new(reapi::SpliceBlobResponse {
                blob_digest: Some(blob_digest),
            });
            self.retain_unary_response_materialization(&mut response, "splice blob response")?;
            return Ok(response);
        }
        if message.chunking_function != reapi::chunking_function::Value::FastCdc2020 as i32 {
            self.state
                .metrics
                .record_reapi_chunking_event("splice", "rejected_function");
            return Err(Status::invalid_argument(
                "new blob recipes require the FastCDC 2020 chunking function",
            ));
        }
        let recipe = ChunkedBlobRecipe::new(
            &blob_digest,
            std::mem::take(&mut message.chunk_digests),
            message.chunking_function,
        )
        .map_err(Status::invalid_argument)?;
        let recipe_bytes = recipe.encode();
        if recipe_bytes.len() as u64 > MAX_INLINE_REPLICATION_BODY_BYTES {
            return Err(Status::out_of_range(format!(
                "chunk recipe exceeds the {} byte inline replication limit",
                MAX_INLINE_REPLICATION_BODY_BYTES
            )));
        }
        let _verification_slot = SpliceVerificationSlot::try_acquire().ok_or_else(|| {
            self.state
                .metrics
                .record_reapi_chunking_event("splice", "shed");
            Status::resource_exhausted(
                "server is limiting concurrent blob splice verification; retry shortly",
            )
        })?;
        if let Err(status) = verify_spliced_blob(&self.state, namespace_id, &recipe).await {
            let outcome = match status.code() {
                tonic::Code::NotFound => "chunk_missing",
                tonic::Code::InvalidArgument => "digest_mismatch",
                _ => "error",
            };
            self.state
                .metrics
                .record_reapi_chunking_event("splice", outcome);
            return Err(status);
        }
        // Keep the recipe at its creation time so a newly spliced logical
        // blob always stays ahead of an absent peer's completed-pass
        // watermark, even when it reuses old chunks. Backfill can encounter
        // the recipe before those chunks; the composite presence and read
        // gates keep it unavailable until every dependency arrives.
        let key = recipe_key(&digest_key(&blob_digest)?);
        let manifest = self
            .state
            .store
            .persist_inline_artifact_from_bytes_and_replicate(
                ArtifactProducer::Reapi,
                namespace_id,
                &key,
                "application/x-protobuf; message=tuist.kura.ChunkedBlobRecipe",
                &recipe_bytes,
                None,
                None,
            )
            .await
            .map_err(|error| store_write_status("failed to store blob recipe", error))?;
        self.state
            .metrics
            .record_artifact_write(ArtifactProducer::Reapi, "ok", manifest.size);
        self.state
            .metrics
            .record_reapi_chunking_event("splice", "ok");
        self.state
            .metrics
            .record_reapi_chunking_bytes("logical", blob_digest.size_bytes as u64);
        self.state
            .metrics
            .record_reapi_chunking_bytes("recipe", manifest.size);
        self.record_reapi_upload(&metadata, namespace_id, manifest.size);
        let mut response = Response::new(reapi::SpliceBlobResponse {
            blob_digest: Some(blob_digest),
        });
        self.retain_unary_response_materialization(&mut response, "splice blob response")?;
        Ok(response)
    }
}

async fn verify_spliced_blob(
    state: &SharedState,
    namespace_id: &str,
    recipe: &ChunkedBlobRecipe,
) -> Result<(), Status> {
    let manifests = fetch_chunk_manifests(state, namespace_id, recipe, true)
        .await
        .map_err(|error| Status::internal(format!("failed to inspect blob chunks: {error}")))?
        .ok_or_else(|| Status::not_found("one or more blob chunks are missing"))?;
    let mut hasher = Sha256::new();
    let mut total = 0_u64;
    for manifest in manifests {
        let Some(mut reader) = state
            .store
            .open_artifact_reader_range_tolerating_promotion_reader_only(&manifest, 0, None)
            .await
            .map_err(|error| Status::internal(format!("failed to verify blob chunk: {error}")))?
        else {
            return Err(Status::not_found("one or more blob chunks are missing"));
        };
        loop {
            let bytes = reader
                .read_chunk_owned(SEGMENT_COPY_BUFFER_BYTES)
                .await
                .map_err(|error| {
                    Status::internal(format!("failed to verify blob chunk: {error}"))
                })?;
            if bytes.is_empty() {
                break;
            }
            total = total.saturating_add(bytes.len() as u64);
            hasher.update(&bytes);
        }
    }
    let digest = recipe.blob_digest();
    if total != recipe.blob_size() || hex::encode(hasher.finalize()) != digest.hash {
        return Err(Status::invalid_argument(
            "chunk contents do not match the declared blob digest",
        ));
    }
    Ok(())
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
        let auth = GrpcRequestSpec {
            operation: "artifact.read",
            namespace_id: Some(&resource.namespace_id),
        };
        self.authorize_request(&request, auth).await?;
        let analytics_started_at = Instant::now();
        if request.get_ref().read_offset < 0 {
            return Err(Status::invalid_argument("read_offset must be non-negative"));
        }
        if request.get_ref().read_limit < 0 {
            return Err(Status::invalid_argument("read_limit must be non-negative"));
        }
        // REAPI mandates INVALID_ARGUMENT (not UNIMPLEMENTED) for a non-zero
        // `read_limit` on a compressed-blobs read: the byte count the limit
        // would name has no defined meaning against a compressed stream, and
        // the client is expected to pass 0 and consume the response.
        // `read_offset` on a compressed-blobs read is defined as the offset
        // in the *uncompressed* form, so it is served by seeking the
        // uncompressed reader (`open_artifact_reader_range_tolerating_promotion_reader_only`
        // below) and starting the encoder at that point — no compressed
        // byte-offset index is needed.
        if resource.compressor == BlobCompressor::Zstd && request.get_ref().read_limit != 0 {
            return Err(Status::invalid_argument(
                "read_limit is not supported on compressed-blobs; leave it at 0 and consume the response stream",
            ));
        }
        if resource.size_bytes == 0 && resource.hash() == EMPTY_BLOB_SHA256 {
            return Ok(Response::new(Box::pin(tokio_stream::empty())));
        }
        let manifest = match self
            .state
            .store
            .fetch_artifact_for_serving_retained(
                ArtifactProducer::Reapi,
                &resource.namespace_id,
                &resource.key,
            )
            .await
        {
            Ok(Some(manifest)) => manifest,
            Ok(None) => {
                let digest = reapi::Digest {
                    hash: resource.hash().to_owned(),
                    size_bytes: resource.size_bytes as i64,
                };
                let Some((_recipe_manifest, recipe)) =
                    fetch_recipe(&self.state, &resource.namespace_id, &digest)
                        .await
                        .map_err(|error| {
                            Status::internal(format!("failed to read blob recipe: {error}"))
                        })?
                else {
                    self.state.metrics.record_artifact_read(
                        ArtifactProducer::Reapi,
                        "not_found",
                        0,
                    );
                    self.record_reapi_cache_event(
                        request.metadata(),
                        &resource.namespace_id,
                        ReapiCacheObservation {
                            operation: "cas",
                            outcome: "miss",
                            digest: resource.hash(),
                            size: 0,
                            duration: analytics_started_at.elapsed(),
                        },
                    );
                    return Err(Status::not_found("blob not found"));
                };
                // Compressed reads of Kura's internal chunked (SplitBlob) recipes
                // are not currently supported: composite reads assemble
                // decoded bytes from many manifests and the encoder wrapper
                // above assumes a single reader. Bazel does not use split
                // blobs, so this codepath is unreachable in production;
                // failing closed is safer than silently corrupting a serve.
                // The guard runs after the recipe lookup so a plain miss on a
                // compressed read still answers NOT_FOUND (which Bazel maps
                // to CacheNotFoundException and treats as a normal miss)
                // rather than UNIMPLEMENTED (which becomes an IOException and
                // breaks the AC-hit-then-CAS-evicted graceful fallback).
                if resource.compressor == BlobCompressor::Zstd {
                    return Err(Status::unimplemented(
                        "compressed reads of chunked blobs are not supported",
                    ));
                }
                let manifests =
                    match fetch_chunk_manifests(&self.state, &resource.namespace_id, &recipe, true)
                        .await
                        .map_err(|error| {
                            Status::internal(format!("failed to inspect blob chunks: {error}"))
                        })? {
                        Some(manifests) => manifests,
                        None => {
                            self.state
                                .metrics
                                .record_reapi_chunking_event("composite_read", "chunk_missing");
                            return Err(Status::not_found("one or more blob chunks are missing"));
                        }
                    };
                let read_offset = request.get_ref().read_offset as u64;
                if read_offset > recipe.blob_size() {
                    return Err(Status::out_of_range("read_offset exceeds blob size"));
                }
                let requested_limit = if request.get_ref().read_limit == 0 {
                    None
                } else {
                    Some(request.get_ref().read_limit as u64)
                };
                let bytes_to_read = requested_limit
                    .unwrap_or_else(|| recipe.blob_size().saturating_sub(read_offset))
                    .min(recipe.blob_size().saturating_sub(read_offset));
                let stream_chunk_bytes = response_stream_chunk_bytes(bytes_to_read);
                let encoded_chunk_bytes = encoded_response_stream_chunk_bytes(bytes_to_read);
                let inline_bytes = manifests
                    .iter()
                    .filter(|manifest| manifest.inline)
                    .map(|manifest| manifest.size)
                    .max()
                    .unwrap_or(0);
                let requested_bytes = u64::try_from(
                    encoded_chunk_bytes
                        .saturating_mul(BYTESTREAM_RESPONSE_LIVE_CHUNK_COUNT)
                        .saturating_add(RESPONSE_STREAM_SEND_BUFFER_BYTES),
                )
                .unwrap_or(u64::MAX)
                .saturating_add(inline_bytes);
                let permit = self
                    .state
                    .memory
                    .acquire_response_stream_memory(
                        usize::try_from(requested_bytes).map_err(|_| {
                            Status::resource_exhausted(
                                "blob stream memory requirement is too large",
                            )
                        })?,
                        "bytestream",
                        crate::memory::ResponseStreamAdmissionPatience::Blocking,
                    )
                    .await
                    .map_err(|_| {
                        Status::resource_exhausted(
                            "server is limiting concurrent ByteStream reads; retry shortly",
                        )
                    })?;
                let slices =
                    composite_read_slices(recipe.chunks(), manifests, read_offset, bytes_to_read);
                let stream = composite_bytestream_read_response_stream(
                    self.state.clone(),
                    slices,
                    stream_chunk_bytes,
                );
                self.state.metrics.record_artifact_read(
                    ArtifactProducer::Reapi,
                    "ok",
                    bytes_to_read,
                );
                self.state.metrics.record_artifact_serving_path("streaming");
                self.state
                    .metrics
                    .record_reapi_chunking_event("composite_read", "ok");
                self.state
                    .metrics
                    .record_reapi_chunking_bytes("served", bytes_to_read);
                let mut response = Response::new(Box::pin(stream) as Self::ReadStream);
                response
                    .extensions_mut()
                    .insert(permit.into_transport_guard());
                self.record_reapi_download(
                    request.metadata(),
                    &resource.namespace_id,
                    bytes_to_read,
                );
                self.record_reapi_cache_event(
                    request.metadata(),
                    &resource.namespace_id,
                    ReapiCacheObservation {
                        operation: "cas",
                        outcome: "hit",
                        digest: resource.hash(),
                        size: bytes_to_read,
                        duration: analytics_started_at.elapsed(),
                    },
                );
                return Ok(response);
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
        let inline_bytes = if manifest.inline { manifest.size } else { 0 };
        let stream_chunk_bytes = response_stream_chunk_bytes(bytes_to_read);
        let encoded_chunk_bytes = encoded_response_stream_chunk_bytes(bytes_to_read);
        let requested_bytes = u64::try_from(
            encoded_chunk_bytes
                .saturating_mul(BYTESTREAM_RESPONSE_LIVE_CHUNK_COUNT)
                .saturating_add(RESPONSE_STREAM_SEND_BUFFER_BYTES),
        )
        .unwrap_or(u64::MAX)
        .saturating_add(inline_bytes);
        let requested_bytes = usize::try_from(requested_bytes).map_err(|_| {
            Status::resource_exhausted("blob stream memory requirement is too large")
        })?;
        // The compressed serve path holds a level-3 zstd encoder alongside
        // the chunk buffers; account for its resident bytes so it counts
        // against the same admission pool that gates concurrent reads.
        let requested_bytes = if resource.compressor == BlobCompressor::Zstd {
            requested_bytes.saturating_add(BYTESTREAM_ZSTD_ENCODER_FOOTPRINT_BYTES)
        } else {
            requested_bytes
        };
        let permit = self
            .state
            .memory
            .acquire_response_stream_memory(
                requested_bytes,
                "bytestream",
                crate::memory::ResponseStreamAdmissionPatience::Blocking,
            )
            .await
            .map_err(|_| {
                Status::resource_exhausted(
                    "server is limiting concurrent ByteStream reads; retry shortly",
                )
            })?;
        // Page-cache-resident whole-blob identity reads are served from a
        // mapping of the artifact, the way the HTTP path serves them: copying
        // out of the mapping on the async worker avoids a blocking-pool
        // hand-off per chunk. The residency gate keeps disk faults off the
        // workers, and any miss falls back to the streaming reader with
        // identical bytes. A ranged read streams only its range instead of
        // mapping and charging the whole blob.
        let whole_blob = read_offset == 0 && bytes_to_read == manifest.size;
        let mapped = if resource.compressor == BlobCompressor::Zstd || !whole_blob {
            None
        } else {
            match self.state.store.try_mmap_artifact_bytes(&manifest).await {
                Ok(Some(bytes)) if bytes.len() as u64 == manifest.size => Some(bytes),
                _ => None,
            }
        };
        let stream: Self::ReadStream = if let Some(bytes) = mapped {
            self.state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "ok", bytes_to_read);
            self.state.metrics.record_artifact_serving_path("mmap");
            Box::pin(mapped_bytestream_read_response_stream(
                bytes,
                stream_chunk_bytes,
            ))
        } else {
            // Tolerates a concurrent background promotion relocating the blob
            // between the manifest fetch above and this open (see
            // `Store::open_artifact_reader_range_tolerating_promotion_reader_only`);
            // a genuine eviction is a NOT_FOUND miss, not an internal error.
            let Some(reader) = self
                .state
                .store
                .open_artifact_reader_range_tolerating_promotion_reader_only(
                    &manifest,
                    read_offset,
                    read_limit,
                )
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
                self.record_reapi_cache_event(
                    request.metadata(),
                    &resource.namespace_id,
                    ReapiCacheObservation {
                        operation: "cas",
                        outcome: "miss",
                        digest: resource.hash(),
                        size: 0,
                        duration: analytics_started_at.elapsed(),
                    },
                );
                return Err(Status::not_found("blob not found"));
            };
            self.state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "ok", bytes_to_read);
            self.state.metrics.record_artifact_serving_path("streaming");
            if resource.compressor == BlobCompressor::Zstd {
                Box::pin(compressed_bytestream_read_response_stream(
                    reader,
                    stream_chunk_bytes,
                ))
            } else {
                Box::pin(bytestream_read_response_stream(reader, stream_chunk_bytes))
            }
        };

        let mut response = Response::new(stream);
        response
            .extensions_mut()
            .insert(permit.into_transport_guard());
        // Book usage only once the response is fully built (headers applied): a
        // failure above turns into a gRPC error with no payload, so billing must
        // not have fired. Recorded before the body streams, mirroring the "ok"
        // read metric and the HTTP path's optimistic size accounting.
        self.record_reapi_download(request.metadata(), &resource.namespace_id, bytes_to_read);
        self.record_reapi_cache_event(
            request.metadata(),
            &resource.namespace_id,
            ReapiCacheObservation {
                operation: "cas",
                outcome: "hit",
                digest: resource.hash(),
                size: bytes_to_read,
                duration: analytics_started_at.elapsed(),
            },
        );
        Ok(response)
    }

    async fn write(
        &self,
        request: Request<tonic::Streaming<bytestream::WriteRequest>>,
    ) -> Result<Response<bytestream::WriteResponse>, Status> {
        let temp_path = temp_file_path(&self.state.config.tmp_dir.join("uploads"), "reapi-write");
        let mut cleanup = TempFileCleanup::new_unreserved(temp_path.clone());

        // The owned cleanup guard removes the partial even when transport
        // cancellation drops this future at an await point. On success the
        // persist step already unlinks the temp file, so its drop is a no-op.
        let result = self.write_stream(&temp_path, request, &mut cleanup).await;
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
        let auth = GrpcRequestSpec {
            operation: "artifact.inspect",
            namespace_id: Some(&resource.namespace_id),
        };
        self.authorize_request(&request, auth).await?;
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
                self.state
                    .store
                    .acknowledge_existing_client_manifest()
                    .await
                    .map_err(Status::internal)?;
                let response = Response::new(bytestream::QueryWriteStatusResponse {
                    committed_size: manifest.size as i64,
                    complete: true,
                });
                Ok(response)
            }
            None => {
                let digest = reapi::Digest {
                    hash: resource.hash().to_owned(),
                    size_bytes: resource.size_bytes as i64,
                };
                let mut presence_budget = PresenceBudget::for_request();
                if presence_keys(
                    &self.state,
                    &resource.namespace_id,
                    &digest,
                    RefreshTrigger::FindMissing,
                    self.state.store.segment_ring_is_aging(),
                    &mut presence_budget,
                )
                .await
                .map_err(|error| {
                    chunk_presence_status(
                        &self.state,
                        "query_write_status",
                        "failed to inspect blob status",
                        error,
                    )
                })?
                .is_some()
                {
                    self.state
                        .store
                        .acknowledge_existing_client_manifest()
                        .await
                        .map_err(Status::internal)?;
                    Ok(Response::new(bytestream::QueryWriteStatusResponse {
                        committed_size: resource.size_bytes as i64,
                        complete: true,
                    }))
                } else {
                    // Partial staging is discarded on failure, so no resumable
                    // offset exists. Bazel treats NOT_FOUND as terminal here;
                    // UNIMPLEMENTED tells it to restart the Write from zero.
                    Err(Status::unimplemented(
                        "incomplete upload status is not supported; restart the write from offset zero",
                    ))
                }
            }
        }
    }
}

fn mapped_bytestream_read_response_stream(
    bytes: bytes::Bytes,
    chunk_bytes: usize,
) -> impl tokio_stream::Stream<Item = Result<bytestream::ReadResponse, Status>> + Send {
    let chunk_bytes = chunk_bytes.max(1);
    futures_util::stream::unfold((bytes, 0_usize), move |(bytes, position)| async move {
        if position >= bytes.len() {
            return None;
        }
        let end = position.saturating_add(chunk_bytes).min(bytes.len());
        let data = bytes[position..end].to_vec();
        Some((Ok(bytestream::ReadResponse { data }), (bytes, end)))
    })
}

fn bytestream_read_response_stream(
    reader: ArtifactReader,
    chunk_bytes: usize,
) -> impl tokio_stream::Stream<Item = Result<bytestream::ReadResponse, Status>> + Send {
    futures_util::stream::try_unfold(reader, move |mut reader| async move {
        let data = reader
            .read_chunk_owned(chunk_bytes)
            .await
            .map_err(|error| Status::internal(format!("failed to stream blob chunk: {error}")))?;
        if data.is_empty() {
            Ok(None)
        } else {
            Ok(Some((bytestream::ReadResponse { data }, reader)))
        }
    })
}

/// zstd level for on-the-fly ByteStream compression. Matches the snapshot
/// serve and BatchRead compression: hundreds of MB/s per core, within a few
/// percent of higher levels on typical Bazel action outputs, so the serve
/// stays CPU-cheap while the wire shrinks meaningfully.
const BYTESTREAM_ZSTD_LEVEL: i32 = 3;

/// Resident footprint of a level-3 `zstd::stream::write::Encoder` per live
/// compressed ByteStream read (measured at ~0.82 MiB; a bit of slack absorbs
/// per-allocator variance). Added to the response-stream memory reservation
/// so concurrent compressed reads are actually gated by the same controller
/// that gates identity reads, rather than accumulating outside its view.
const BYTESTREAM_ZSTD_ENCODER_FOOTPRINT_BYTES: usize = 900 * 1024;

/// Wraps an ArtifactReader chunk stream with a streaming zstd encoder. Each
/// input chunk of decoded bytes is pushed into the encoder; the encoder's
/// scratch Vec is drained per input chunk and split into `chunk_bytes`-sized
/// ReadResponses. The encoder's internal state plus one input chunk cap the
/// per-stream memory footprint.
///
/// The encoder is flushed at EOF (`Encoder::finish`) so the trailing frame
/// bytes reach the client; the client's decoder rejects a truncated stream.
fn compressed_bytestream_read_response_stream(
    reader: ArtifactReader,
    chunk_bytes: usize,
) -> impl tokio_stream::Stream<Item = Result<bytestream::ReadResponse, Status>> + Send {
    struct ReadState {
        reader: Option<ArtifactReader>,
        // None once `finish()` was called; the encoder cannot be reused after.
        encoder: Option<zstd::stream::write::Encoder<'static, Vec<u8>>>,
        pending: Vec<u8>,
        chunk_bytes: usize,
    }

    let encoder = zstd::stream::write::Encoder::new(Vec::new(), BYTESTREAM_ZSTD_LEVEL)
        .expect("zstd encoder construction should succeed for a fixed level");
    let state = ReadState {
        reader: Some(reader),
        encoder: Some(encoder),
        pending: Vec::new(),
        chunk_bytes,
    };

    // Splits the first `take` bytes off the front of `pending` into an owned
    // Vec, leaving the tail in `pending`. Cheaper than draining byte-by-byte
    // out of a VecDeque: one memcpy of the tail into a fresh allocation
    // instead of `take` per-byte pops, which dominated compressed serve CPU
    // on incompressible content.
    fn take_front(pending: &mut Vec<u8>, take: usize) -> Vec<u8> {
        let tail = pending.split_off(take);
        std::mem::replace(pending, tail)
    }

    futures_util::stream::try_unfold(state, move |mut state| async move {
        loop {
            // Emit a wire-sized chunk of compressed output as soon as one is
            // ready, so a slow decode-loop client still receives frames.
            if state.pending.len() >= state.chunk_bytes {
                let data = take_front(&mut state.pending, state.chunk_bytes);
                return Ok(Some((bytestream::ReadResponse { data }, state)));
            }

            // Feed the encoder another input chunk, or finalize it if we are
            // out of input. `finish()` writes the closing frame bytes into the
            // encoder's sink, which then joins the pending queue.
            if let Some(reader) = state.reader.as_mut() {
                let input = reader
                    .read_chunk_owned(state.chunk_bytes)
                    .await
                    .map_err(|error| {
                        Status::internal(format!("failed to stream blob chunk: {error}"))
                    })?;
                if input.is_empty() {
                    state.reader = None;
                } else {
                    let encoder = state
                        .encoder
                        .as_mut()
                        .expect("encoder is only taken at EOF");
                    std::io::Write::write_all(encoder, &input).map_err(|error| {
                        Status::internal(format!(
                            "failed to compress ByteStream chunk with zstd: {error}"
                        ))
                    })?;
                    let mut scratch = std::mem::take(encoder.get_mut());
                    state.pending.append(&mut scratch);
                    continue;
                }
            }

            // Reader is drained: finalize the encoder (once), then emit any
            // remaining bytes and end the stream.
            if let Some(encoder) = state.encoder.take() {
                let mut scratch = encoder.finish().map_err(|error| {
                    Status::internal(format!("failed to finish zstd stream: {error}"))
                })?;
                state.pending.append(&mut scratch);
            }

            if state.pending.is_empty() {
                return Ok(None);
            }
            let take = state.chunk_bytes.min(state.pending.len());
            let data = take_front(&mut state.pending, take);
            return Ok(Some((bytestream::ReadResponse { data }, state)));
        }
    })
}

fn composite_read_slices(
    digests: &[reapi::Digest],
    manifests: Vec<ArtifactManifest>,
    mut skip: u64,
    mut remaining: u64,
) -> VecDeque<(ArtifactManifest, u64, u64)> {
    let mut slices = VecDeque::new();
    for (digest, manifest) in digests.iter().zip(manifests) {
        if remaining == 0 {
            break;
        }
        let chunk_size = digest.size_bytes as u64;
        if skip >= chunk_size {
            skip -= chunk_size;
            continue;
        }
        let take = remaining.min(chunk_size - skip);
        slices.push_back((manifest, skip, take));
        remaining -= take;
        skip = 0;
    }
    slices
}

fn composite_bytestream_read_response_stream(
    state: SharedState,
    slices: VecDeque<(ArtifactManifest, u64, u64)>,
    chunk_bytes: usize,
) -> impl tokio_stream::Stream<Item = Result<bytestream::ReadResponse, Status>> + Send {
    futures_util::stream::try_unfold(
        (state, slices, None::<ArtifactReader>),
        move |(state, mut slices, mut reader)| async move {
            loop {
                if let Some(mut current) = reader.take() {
                    let data = current
                        .read_chunk_owned(chunk_bytes)
                        .await
                        .map_err(|error| {
                            Status::internal(format!("failed to stream blob chunk: {error}"))
                        })?;
                    if !data.is_empty() {
                        return Ok(Some((
                            bytestream::ReadResponse { data },
                            (state, slices, Some(current)),
                        )));
                    }
                }
                let Some((manifest, offset, limit)) = slices.pop_front() else {
                    return Ok(None);
                };
                reader = state
                    .store
                    .open_artifact_reader_range_tolerating_promotion_reader_only(
                        &manifest,
                        offset,
                        Some(limit),
                    )
                    .await
                    .map_err(|error| {
                        Status::internal(format!("failed to stream blob chunk: {error}"))
                    })?;
                if reader.is_none() {
                    return Err(Status::not_found("one or more blob chunks are missing"));
                }
            }
        },
    )
}

#[cfg(test)]
fn direct_bytestream_read_response_stream<R>(
    reader: R,
    chunk_bytes: usize,
) -> impl tokio_stream::Stream<Item = Result<bytestream::ReadResponse, Status>> + Send
where
    R: tokio::io::AsyncRead + Unpin + Send,
{
    futures_util::stream::try_unfold(reader, move |mut reader| async move {
        let mut data = Vec::with_capacity(chunk_bytes);
        match tokio::io::AsyncReadExt::read_buf(&mut reader, &mut data).await {
            Ok(0) => Ok(None),
            Ok(_) => Ok(Some((bytestream::ReadResponse { data }, reader))),
            Err(error) => Err(Status::internal(format!(
                "failed to stream blob chunk: {error}"
            ))),
        }
    })
}

#[cfg(test)]
fn copying_bytestream_read_response_stream<R>(
    reader: R,
    chunk_bytes: usize,
) -> impl tokio_stream::Stream<Item = Result<bytestream::ReadResponse, Status>> + Send
where
    R: tokio::io::AsyncRead + Send,
{
    tokio_util::io::ReaderStream::with_capacity(reader, chunk_bytes).map(|result| match result {
        Ok(bytes) => Ok(bytestream::ReadResponse {
            data: bytes.to_vec(),
        }),
        Err(error) => Err(Status::internal(format!(
            "failed to stream blob chunk: {error}"
        ))),
    })
}

async fn fetch_keyvalue_proto<T>(
    state: &SharedState,
    namespace_id: &str,
    key: &str,
    label: &str,
    refresh: bool,
    materialization_budget: Option<&mut MaterializationBudget<'_>>,
) -> Result<(u64, T), Status>
where
    T: Message + Default,
{
    let lookup = if refresh {
        state
            .store
            .fetch_artifact_for_serving(ArtifactProducer::Reapi, namespace_id, key)
            .await
    } else {
        state
            .store
            .manifest_for_key(ArtifactProducer::Reapi, namespace_id, key)
    };
    let manifest = match lookup {
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

/// One blob of an action-result inline read. This existing helper shares the
/// action response's mutable materialization budget across concurrent files.
async fn batch_read_one(
    state: &SharedState,
    namespace_id: &str,
    digest: &reapi::Digest,
    budget: &std::sync::Mutex<MaterializationBudget<'_>>,
    required: bool,
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
    {
        let mut budget = budget.lock().expect("budget lock");
        if required {
            budget.claim(manifest.size, "CAS response materialization")?;
        } else {
            budget.try_claim(manifest.size, "CAS response materialization")?;
        }
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

/// Lock-free batch-read path. The memory permit travels with the returned bytes
/// and is retained by the response, while an atomic request counter bounds the
/// aggregate before any materialization starts.
async fn batch_read_one_atomic(
    state: &SharedState,
    namespace_id: &str,
    digest: &reapi::Digest,
    budget: &AtomicMaterializationBudget<'_>,
) -> Result<Option<Vec<u8>>, Status> {
    // FindMissingBlobs reports the empty blob present without it ever being
    // stored, so it has to be served here too.
    if is_empty_blob(digest) {
        return Ok(Some(Vec::new()));
    }
    let key = blob_key(&digest_key(digest)?);
    let manifest = state
        .store
        .fetch_artifact_for_serving(ArtifactProducer::Reapi, namespace_id, &key)
        .await
        .inspect_err(|_| {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
        })
        .map_err(Status::internal)?;
    if manifest.is_none() {
        let Some((_recipe_manifest, recipe)) = fetch_recipe(state, namespace_id, digest)
            .await
            .map_err(Status::internal)?
        else {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "not_found", 0);
            return Ok(None);
        };
        budget.claim(recipe.blob_size(), "CAS response materialization")?;
        let bytes = read_composite_bytes(state, namespace_id, &recipe, true).await?;
        state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "ok", bytes.len() as u64);
        return Ok(Some(bytes));
    }
    let manifest = manifest.expect("checked above");
    budget.claim(manifest.size, "CAS response materialization")?;
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
    refresh: bool,
    materialization_budget: Option<&mut MaterializationBudget<'_>>,
) -> Result<Option<Vec<u8>>, Status> {
    let key = blob_key(&digest_key(digest)?);
    let manifest = if refresh {
        state
            .store
            .fetch_artifact_for_serving(ArtifactProducer::Reapi, namespace_id, &key)
            .await
    } else {
        state
            .store
            .manifest_for_key(ArtifactProducer::Reapi, namespace_id, &key)
    }
    .inspect_err(|_| {
        state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
    })
    .map_err(Status::internal)?;
    if manifest.is_none() {
        let Some((_recipe_manifest, recipe)) = fetch_recipe(state, namespace_id, digest)
            .await
            .map_err(Status::internal)?
        else {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "not_found", 0);
            return Ok(None);
        };
        if let Some(budget) = materialization_budget {
            budget.claim(recipe.blob_size(), "CAS response materialization")?;
        }
        let bytes = read_composite_bytes(state, namespace_id, &recipe, refresh).await?;
        state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "ok", bytes.len() as u64);
        return Ok(Some(bytes));
    }
    let manifest = manifest.expect("checked above");
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

async fn read_composite_bytes(
    state: &SharedState,
    namespace_id: &str,
    recipe: &ChunkedBlobRecipe,
    refresh: bool,
) -> Result<Vec<u8>, Status> {
    let manifests = match fetch_chunk_manifests(state, namespace_id, recipe, refresh)
        .await
        .map_err(Status::internal)?
    {
        Some(manifests) => manifests,
        None => {
            state
                .metrics
                .record_reapi_chunking_event("composite_read", "chunk_missing");
            return Err(Status::not_found("one or more blob chunks are missing"));
        }
    };
    let size = usize::try_from(recipe.blob_size())
        .map_err(|_| Status::resource_exhausted("blob is too large to materialize"))?;
    let mut result = try_allocate_exact_vec(size)
        .ok_or_else(|| Status::resource_exhausted("failed to reserve blob response memory"))?;
    for manifest in manifests {
        let Some(mut reader) = state
            .store
            .open_artifact_reader_range_tolerating_promotion_reader_only(&manifest, 0, None)
            .await
            .map_err(Status::internal)?
        else {
            state
                .metrics
                .record_reapi_chunking_event("composite_read", "chunk_missing");
            return Err(Status::not_found("one or more blob chunks are missing"));
        };
        loop {
            let bytes = reader
                .read_chunk_owned(SEGMENT_COPY_BUFFER_BYTES)
                .await
                .map_err(|error| Status::internal(error.to_string()))?;
            if bytes.is_empty() {
                break;
            }
            result.extend_from_slice(&bytes);
        }
    }
    if result.len() != size {
        state
            .metrics
            .record_reapi_chunking_event("composite_read", "data_loss");
        return Err(Status::data_loss(
            "blob chunks do not match the stored recipe",
        ));
    }
    state
        .metrics
        .record_reapi_chunking_event("composite_read", "ok");
    state
        .metrics
        .record_reapi_chunking_bytes("served", result.len() as u64);
    Ok(result)
}

/// Whether every blob this action result references is still present, and, when
/// `collecting`, the keys of the ones confirmed present so their lifetimes can
/// be extended. Callers pass [`Store::segment_ring_is_aging`]: with nothing aged
/// into the Old generation nothing is promotable, so the keys are not retained.
///
/// The original per-key gate (PR #11793) checked `output_files` only; this
/// covers the rest of what a client fetches when it replays a hit: `stdout` and
/// `stderr`, and each output directory's `Tree` blob together with the file
/// blobs the tree lists. Any one of them missing hard-fails the replay on the
/// first missing object exactly as an evicted output file does, so all of them
/// must gate the serve — an REAPI client emitting tree artifacts would otherwise
/// keep hitting the same "Lost inputs"/missing-object failure this fix targets.
/// The checks are manifest lookups (mostly existence-cache hits); only an entry
/// that actually carries directory outputs pays the extra tree read, and only
/// once its cheap checks pass. That read claims the request's
/// `MaterializationBudget` like every other read on this path, so a large tree
/// cannot pull unbounded bytes into a pressured node — a failed claim surfaces
/// as an error the loop treats as "present", degrading the gate to serving
/// unchecked rather than adding load. Read or decode failures are treated as
/// "present" throughout, and the canonical empty blob is always present (REAPI
/// convention), so a transient blip or a zero-byte reference never turns a live
/// entry into a spurious miss — the same bias as the `unwrap_or(true)` manifest
/// checks.
async fn first_evicted_output(
    state: &SharedState,
    namespace_id: &str,
    action_result: &reapi::ActionResult,
    collecting: bool,
    refresh: bool,
    materialization_budget: &mut MaterializationBudget<'_>,
) -> Result<OutputPresence, String> {
    let mut present = Vec::new();
    let mut presence_budget = PresenceBudget::for_request();

    for digest in action_result
        .output_files
        .iter()
        .filter_map(|file| file.digest.as_ref())
        .chain(action_result.stdout_digest.as_ref())
        .chain(action_result.stderr_digest.as_ref())
    {
        if blob_evicted(
            state,
            namespace_id,
            digest,
            collecting,
            &mut present,
            &mut presence_budget,
        )
        .await?
        {
            return Ok(OutputPresence::evicted(&digest.hash));
        }
    }

    for directory in &action_result.output_directories {
        let Some(tree_digest) = directory.tree_digest.as_ref() else {
            continue;
        };
        if blob_evicted(
            state,
            namespace_id,
            tree_digest,
            collecting,
            &mut present,
            &mut presence_budget,
        )
        .await?
        {
            return Ok(OutputPresence::evicted(&tree_digest.hash));
        }
        // The tree blob survives; a client next fetches every file it lists, so
        // an evicted leaf poisons the replay just as a missing tree would. This
        // read is the one non-manifest cost, paid only by directory-output
        // entries and only after their tree passed the cheap check above, and it
        // claims the shared budget so a large tree can't materialize unbounded.
        let Ok(Some(bytes)) = maybe_read_cas_bytes(
            state,
            namespace_id,
            tree_digest,
            refresh,
            Some(&mut *materialization_budget),
        )
        .await
        else {
            continue;
        };
        let Ok(tree) = reapi::Tree::decode(bytes.as_slice()) else {
            continue;
        };
        for digest in tree
            .root
            .iter()
            .chain(&tree.children)
            .flat_map(|directory| &directory.files)
            .filter_map(|file| file.digest.as_ref())
        {
            if blob_evicted(
                state,
                namespace_id,
                digest,
                collecting,
                &mut present,
                &mut presence_budget,
            )
            .await?
            {
                return Ok(OutputPresence::evicted(&digest.hash));
            }
        }
    }

    Ok(OutputPresence {
        evicted: None,
        present,
    })
}

/// The presence gate's verdict for one action result.
struct OutputPresence {
    /// The hash of the first referenced blob found evicted, if any.
    evicted: Option<String>,
    /// Blob keys confirmed present while checking, collected so a served entry
    /// can extend their lifetimes. Left empty when `evicted` is set: that entry
    /// is not served and is usually deleted, so refreshing its surviving blobs
    /// on its behalf would be pure write amplification.
    present: Vec<String>,
}

impl OutputPresence {
    fn evicted(hash: &str) -> Self {
        Self {
            evicted: Some(hash.to_owned()),
            present: Vec::new(),
        }
    }
}

/// Whether one referenced blob has been evicted, recording its key when it is
/// still present and `collecting` says a promotable segment exists. A digest
/// with no stored artifact of its own (the canonical empty blob, or one whose
/// key cannot be derived) is neither evicted nor worth refreshing, so it is
/// skipped on both counts.
async fn blob_evicted(
    state: &SharedState,
    namespace_id: &str,
    digest: &reapi::Digest,
    collecting: bool,
    present: &mut Vec<String>,
    presence_budget: &mut PresenceBudget,
) -> Result<bool, String> {
    if is_empty_blob(digest) {
        return Ok(false);
    }
    if digest_key(digest).is_err() {
        return Ok(false);
    }
    let keys = manifest_presence_keys(state, namespace_id, digest, presence_budget).await?;
    if let Some(keys) = keys {
        if collecting {
            present.extend(keys);
        }
        return Ok(false);
    }
    Ok(true)
}

/// Digests per `FindMissingBlobs` store pass. Large enough to amortize the
/// manifest-cache lock and RocksDB multi-get, small enough that the pass holds
/// that lock, shared with every serving read, for well under a millisecond.
const FIND_MISSING_BATCH_DIGESTS: usize = 1024;
/// Room for `blob/<64 hex>/<size>` or its recipe counterpart without regrowing.
const BLOB_KEY_CAPACITY: usize = 96;

/// Marks the digests `FindMissingBlobs` must report missing. Direct blobs are
/// resolved for the whole batch in one store pass, which also extends the
/// lifetime of present blobs sitting in an aged segment: "Servers SHOULD
/// increase the lifetimes of the referenced blobs if necessary and
/// applicable", since a client told a blob is present skips uploading it and
/// relies on it staying. Composite blobs then cost one batched recipe probe,
/// and only digests that have a recipe take the per-digest chunk walk.
async fn find_missing_in_batch(
    state: &SharedState,
    namespace_id: &str,
    digests: &[reapi::Digest],
    is_missing: &mut [bool],
    presence_budget: &mut PresenceBudget,
) -> Result<(), Status> {
    use std::fmt::Write as _;

    let presence_status = |error| {
        chunk_presence_status(
            state,
            "find_missing_blobs",
            "failed to inspect CAS blob",
            error,
        )
    };
    let mut keys = String::with_capacity(digests.len() * BLOB_KEY_CAPACITY);
    let mut lookups = Vec::with_capacity(digests.len());
    for (index, digest) in digests.iter().enumerate() {
        // The empty blob is present by REAPI convention even when it was never
        // uploaded; reporting it missing would push clients to upload a
        // zero-byte blob they otherwise synthesize.
        if is_empty_blob(digest) {
            continue;
        }
        validate_digest(digest)?;
        let start = keys.len();
        write!(keys, "blob/{}/{}", digest.hash, digest.size_bytes)
            .expect("writing to a String cannot fail");
        lookups.push((index, start..keys.len()));
    }
    let direct_keys: Vec<&str> = lookups
        .iter()
        .map(|(_, range)| &keys[range.clone()])
        .collect();
    let present = state
        .store
        .artifacts_exist_extending_lifetime(
            ArtifactProducer::Reapi,
            namespace_id,
            &direct_keys,
            RefreshTrigger::FindMissing,
        )
        .await
        .map_err(presence_status)?;
    let absent: Vec<usize> = lookups
        .iter()
        .zip(present)
        .filter_map(|((index, _), present)| (!present).then_some(*index))
        .collect();
    if absent.is_empty() {
        return Ok(());
    }

    let mut recipe_keys = String::with_capacity(absent.len() * BLOB_KEY_CAPACITY);
    let mut recipe_ranges = Vec::with_capacity(absent.len());
    for &index in &absent {
        let start = recipe_keys.len();
        push_recipe_key(&mut recipe_keys, &digests[index]);
        recipe_ranges.push(start..recipe_keys.len());
    }
    let recipe_keys: Vec<&str> = recipe_ranges
        .into_iter()
        .map(|range| &recipe_keys[range])
        .collect();
    let has_recipe = state
        .store
        .manifests_stored(ArtifactProducer::Reapi, namespace_id, &recipe_keys)
        .map_err(presence_status)?;
    let mut aging = None;
    for (index, has_recipe) in absent.into_iter().zip(has_recipe) {
        if has_recipe {
            let aging = *aging.get_or_insert_with(|| state.store.segment_ring_is_aging());
            if recipe_presence_keys(
                state,
                namespace_id,
                &digests[index],
                RefreshTrigger::FindMissing,
                aging,
                presence_budget,
            )
            .await
            .map_err(presence_status)?
            .is_some()
            {
                continue;
            }
        }
        is_missing[index] = true;
    }
    Ok(())
}
fn chunk_presence_status(state: &SharedState, route: &str, context: &str, error: String) -> Status {
    if is_presence_budget_error(&error) {
        state
            .metrics
            .record_reapi_chunking_event("probe_budget_exhausted", route);
        Status::resource_exhausted(error)
    } else {
        Status::internal(format!("{context}: {error}"))
    }
}

// Persists a CAS blob and returns whether it was newly stored (`true`) or was
// already present (`false`). Billing uses this to charge only new bytes, the
// same rule as the HTTP upload path's `artifact_exists` short-circuit. The
// presence signal comes from the store's persist, evaluated under the
// per-artifact write lock, so concurrent uploads of the same missing blob
// resolve to exactly one `true` — a version-based `Applied` outcome can't
// stand in for this, because a re-upload that advances the stored version
// still applies over an already-present blob.
/// Streaming-decode a zstd-compressed BatchUpdate item into a Vec bounded by
/// the declared uncompressed size.
///
/// Memory grows with actually-decoded bytes, not the declared size, so a
/// small compressed payload that declares a large uncompressed size never
/// commits heap it will not fill. The loop stops feeding the decoder once the
/// declared cap is reached, and a final one-byte probe rejects any stream
/// that would still yield more — the two together enforce the bomb bound at
/// the first byte past the cap.
fn decompress_zstd_batch_item(
    compressed: &[u8],
    declared_uncompressed_size: i64,
) -> Result<Vec<u8>, Status> {
    let declared = i64_to_usize_bounded(declared_uncompressed_size)?;
    let mut decoder = zstd::stream::read::Decoder::with_buffer(compressed)
        .map_err(|error| Status::internal(format!("failed to build zstd decoder: {error}")))?;
    // 64 KiB per read keeps syscall overhead low while capping the largest
    // single allocation the growing Vec can request. Growth stays geometric
    // but never reserves past `declared`, which the batch admission has
    // already accepted, so the allocation stays within that admission.
    const READ_CHUNK_BYTES: usize = 64 * 1024;
    let mut decoded: Vec<u8> = Vec::new();
    let mut buffer = [0_u8; READ_CHUNK_BYTES];
    while decoded.len() < declared {
        let take = buffer.len().min(declared - decoded.len());
        match std::io::Read::read(&mut decoder, &mut buffer[..take]) {
            Ok(0) => return Ok(decoded),
            Ok(count) => {
                if decoded.capacity() - decoded.len() < count {
                    let capacity = decoded
                        .capacity()
                        .saturating_mul(2)
                        .max(decoded.len() + count)
                        .min(declared);
                    decoded.reserve_exact(capacity - decoded.len());
                }
                decoded.extend_from_slice(&buffer[..count]);
            }
            Err(error) => {
                return Err(Status::invalid_argument(format!(
                    "failed to decode zstd payload: {error}"
                )));
            }
        }
    }
    // We stopped exactly at `declared`; if the decoder can still produce a
    // byte, the payload's uncompressed length exceeded what the digest
    // declared.
    let mut probe = [0_u8; 1];
    match std::io::Read::read(&mut decoder, &mut probe) {
        Ok(0) => Ok(decoded),
        Ok(_) => Err(Status::invalid_argument(
            "zstd payload decompressed past the declared blob size (possible bomb)",
        )),
        Err(error) => Err(Status::invalid_argument(format!(
            "failed to decode zstd payload: {error}"
        ))),
    }
}

/// Best-effort zstd compression of a BatchRead response's data. Returns
/// `(payload, compressor)` where compressor is 1 (ZSTD) when compression
/// actually shrunk the payload, or 0 (IDENTITY) when it would grow it or the
/// encoder failed. The response's materialization budget already covers the
/// uncompressed bytes; compressed output is always shorter than or equal to
/// the fallback identity size (we discard the encoder's output otherwise), so
/// no additional pool reservation is required.
fn maybe_compress_zstd_batch_response(uncompressed: Vec<u8>) -> (Vec<u8>, i32) {
    // Small blobs (below the fixed zstd frame overhead) never shrink; fall
    // back to identity without touching the encoder.
    const ZSTD_MIN_PROFITABLE_BYTES: usize = 64;
    if uncompressed.len() < ZSTD_MIN_PROFITABLE_BYTES {
        return (uncompressed, 0);
    }
    // Level 3 is the same level the actioncache snapshot serves with —
    // hundreds of MB/s per core, within a few percent of higher levels on the
    // opaque byte content Bazel typically caches.
    match zstd::stream::encode_all(uncompressed.as_slice(), BATCH_RESPONSE_ZSTD_LEVEL) {
        Ok(compressed) if compressed.len() < uncompressed.len() => {
            (compressed, reapi::compressor::Value::Zstd as i32)
        }
        Ok(_) | Err(_) => (uncompressed, 0),
    }
}

const BATCH_RESPONSE_ZSTD_LEVEL: i32 = 3;

fn i64_to_usize_bounded(value: i64) -> Result<usize, Status> {
    if value < 0 {
        return Err(Status::invalid_argument(
            "declared blob size cannot be negative",
        ));
    }
    if value as u64 > MAX_MODULE_TOTAL_BYTES {
        return Err(Status::out_of_range(format!(
            "declared blob size {value} exceeds max_cas_blob_size_bytes {MAX_MODULE_TOTAL_BYTES}"
        )));
    }
    usize::try_from(value)
        .map_err(|_| Status::out_of_range("declared blob size does not fit in usize"))
}

/// One BatchUpdateBlobs item's response, and the uncompressed bytes it newly
/// stored together with how long the item took.
struct BatchUpdateItem {
    response: reapi::batch_update_blobs_response::Response,
    stored: Option<(u64, Duration)>,
}

/// Decodes and persists one BatchUpdateBlobs item.
///
/// A compressed item admits its declared decoded length before decoding and
/// keeps that permit until its persist returns, so the batch never holds more
/// decoded bytes than the transient pool admitted. Admission is try-only: the
/// request already holds its decode reservation from the same pool, so waiting
/// here would be hold-and-wait. An item that cannot be admitted fails alone
/// with RESOURCE_EXHAUSTED; identity items borrow the admitted request.
async fn update_batch_blob(
    state: &SharedState,
    namespace_id: &str,
    item: &reapi::batch_update_blobs_request::Request,
) -> BatchUpdateItem {
    let started_at = Instant::now();
    let rejected = |digest: Option<reapi::Digest>, status: RpcStatus| BatchUpdateItem {
        response: reapi::batch_update_blobs_response::Response {
            digest,
            status: Some(status),
        },
        stored: None,
    };
    let Some(digest) = item.digest.clone() else {
        return rejected(None, rpc_status(3, "missing digest"));
    };
    // The digest is always the uncompressed content's digest, so decompression
    // bounds are the same as an identity upload: the decoder never grows past
    // `digest.size_bytes`, whatever the compressed input.
    let (decoded, _decoded_admission) = match item.compressor {
        0 => (std::borrow::Cow::Borrowed(item.data.as_slice()), None),
        c if c == reapi::compressor::Value::Zstd as i32 => {
            let declared = match i64_to_usize_bounded(digest.size_bytes) {
                Ok(declared) => declared,
                Err(status) => {
                    return rejected(Some(digest), rpc_status_from_grpc_status(&status));
                }
            };
            let admission = match state.memory.try_acquire_reapi_materialization(declared) {
                Ok(admission) => admission,
                Err(()) => {
                    let kind = if declared > state.memory.reapi_materialization_limit_bytes() {
                        shed_kind::REAPI_REQUEST_BUDGET
                    } else {
                        shed_kind::REAPI_MATERIALIZATION
                    };
                    record_materialization_rejection(state, kind);
                    return rejected(
                        Some(digest),
                        rpc_status(
                            8,
                            "compressed blob was rejected because the concurrent REAPI materialization pool cannot hold its decoded size",
                        ),
                    );
                }
            };
            match decompress_zstd_batch_item(&item.data, digest.size_bytes) {
                Ok(bytes) => (std::borrow::Cow::Owned(bytes), admission),
                Err(status) => {
                    return rejected(Some(digest), rpc_status_from_grpc_status(&status));
                }
            }
        }
        other => {
            return rejected(
                Some(digest),
                rpc_status(
                    12,
                    format!(
                        "compressor {other} is not supported; only IDENTITY and ZSTD are advertised"
                    ),
                ),
            );
        }
    };
    match persist_cas_blob(state, namespace_id, &digest, decoded.as_ref()).await {
        Ok(newly_stored) => BatchUpdateItem {
            stored: newly_stored.then(|| (decoded.len() as u64, started_at.elapsed())),
            response: reapi::batch_update_blobs_response::Response {
                digest: Some(digest),
                status: Some(rpc_status(0, "")),
            },
        },
        Err(error) => rejected(Some(digest), rpc_status(13, error)),
    }
}

async fn persist_cas_blob(
    state: &SharedState,
    namespace_id: &str,
    digest: &reapi::Digest,
    bytes: &[u8],
) -> Result<bool, String> {
    validate_digest_bytes(digest, bytes)?;
    let key = blob_key(&digest_key(digest).map_err(|error| error.message().to_owned())?);
    let persisted = state
        .store
        .persist_artifact_from_bytes_and_replicate(
            ArtifactProducer::Reapi,
            namespace_id,
            &key,
            "application/octet-stream",
            bytes,
        )
        .await?;
    if persisted.already_present {
        state.store.acknowledge_existing_client_manifest().await?;
    }
    state
        .metrics
        .record_artifact_write(ArtifactProducer::Reapi, "ok", persisted.manifest.size);
    Ok(!persisted.already_present)
}

pub(super) async fn read_manifest_bytes(
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
    over_budget_kind: &'static str,
    held_permits: Vec<crate::memory::MemoryPermit>,
}

/// One request's response-materialization budget, reserved up front.
///
/// The reservation is taken once, for the whole batch, and drawn down by
/// arithmetic. Claiming per blob against the memory controller would mean
/// waiting for the pool while already holding part of it, and a batch reads its
/// blobs concurrently, so that is hold-and-wait between the blobs of one request
/// as well as between requests. One acquisition per request removes it.
struct AtomicMaterializationBudget<'a> {
    state: &'a SharedState,
    remaining_bytes: AtomicUsize,
    over_budget_kind: &'static str,
    /// Covers every claim below. Handed to the response so the bytes stay
    /// reserved for as long as the client is reading them.
    permit: Option<crate::memory::MemoryPermit>,
}

struct MaterializedSnapshot {
    bytes: Vec<u8>,
    response_memory: Option<crate::memory::MemoryPermit>,
}

impl MaterializedSnapshot {
    fn new(bytes: Vec<u8>, response_memory: Option<crate::memory::MemoryPermit>) -> Self {
        Self {
            bytes,
            response_memory,
        }
    }

    fn retain_response_memory(&mut self) -> Result<(), Status> {
        if let Some(permit) = self.response_memory.as_mut() {
            let retained_bytes = self
                .bytes
                .len()
                .checked_mul(2)
                .ok_or_else(|| Status::resource_exhausted("snapshot response size overflow"))?;
            permit.shrink_to(retained_bytes).map_err(|_| {
                Status::internal("failed to retain snapshot response memory reservation")
            })?;
        }
        Ok(())
    }

    fn into_parts(self) -> (Vec<u8>, Option<crate::memory::MemoryPermit>) {
        (self.bytes, self.response_memory)
    }
}

impl std::ops::Deref for MaterializedSnapshot {
    type Target = [u8];

    fn deref(&self) -> &Self::Target {
        &self.bytes
    }
}

impl std::fmt::Debug for MaterializedSnapshot {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("MaterializedSnapshot")
            .field("bytes", &self.bytes)
            .finish_non_exhaustive()
    }
}

impl PartialEq for MaterializedSnapshot {
    fn eq(&self, other: &Self) -> bool {
        self.bytes == other.bytes
    }
}

fn snapshot_encode_peak_bytes(content_bytes: usize) -> usize {
    let output_bytes = zstd::zstd_safe::compress_bound(content_bytes)
        .saturating_add(SNAPSHOT_WIRE_HEADER_BYTES)
        .min(SNAPSHOT_WIRE_MAX_BYTES);
    content_bytes
        .saturating_add(output_bytes)
        .saturating_add(SNAPSHOT_COMPRESSION_SCRATCH_BYTES)
}

impl<'a> AtomicMaterializationBudget<'a> {
    /// Reserves what the request asked for, bounded by the per-request budget,
    /// waiting for a momentarily full pool rather than shedding against it.
    ///
    /// `wanted_bytes` comes from the client's own digests, so a batch whose
    /// blobs are missing reserves for bytes it never serves. That over-reserve
    /// is bounded by the per-request budget and released with the response; the
    /// alternative is to learn each size only after a store lookup, which is
    /// what forced the per-blob claims this replaces.
    async fn reserve(state: &'a SharedState, wanted_bytes: u64) -> Result<Self, Status> {
        let budget_bytes = state.memory.reapi_response_budget_bytes();
        let over_budget_kind = over_budget_shed_kind(state);
        let reserved_bytes = usize::try_from(wanted_bytes)
            .unwrap_or(usize::MAX)
            .min(budget_bytes);
        let permit = state
            .memory
            .reserve_response_materialization(reserved_bytes)
            .await
            .map_err(|()| {
                record_materialization_rejection(state, shed_kind::REAPI_MATERIALIZATION);
                Status::resource_exhausted(
                    "batch read response was rejected because the REAPI response materialization pool did not free in time",
                )
            })?;
        Ok(Self {
            state,
            remaining_bytes: AtomicUsize::new(reserved_bytes),
            over_budget_kind,
            permit,
        })
    }

    fn take_permit(&mut self) -> Option<crate::memory::MemoryPermit> {
        self.permit.take()
    }

    /// Draws one response down from the reservation. Pure arithmetic: the memory
    /// was admitted in `reserve`, so this never touches the controller and never
    /// waits while holding part of the pool.
    fn claim(&self, size_bytes: u64, label: &str) -> Result<(), Status> {
        let requested_bytes = usize::try_from(size_bytes).map_err(|_| {
            self.reject(
                shed_kind::REAPI_REQUEST_BUDGET,
                format!("{label} exceeds the maximum addressable REAPI materialization size"),
            )
        })?;
        let limit_bytes = self.state.memory.reapi_materialization_limit_bytes();
        if requested_bytes > limit_bytes {
            return Err(self.reject(
                shed_kind::REAPI_REQUEST_BUDGET,
                format!(
                    "{label} needs {requested_bytes} bytes but the node allows at most {limit_bytes} bytes of response materialization per request"
                ),
            ));
        }
        // A blob larger than its declared digest, or one the request never
        // declared, lands here: the reservation was sized from what the client
        // asked for, so anything beyond it is refused rather than served out of
        // memory nobody admitted.
        self.remaining_bytes
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |remaining| {
                remaining.checked_sub(requested_bytes)
            })
            .map(|_| ())
            .map_err(|remaining_bytes| {
                self.reject(
                    self.over_budget_kind,
                    format!(
                        "{label} needs {requested_bytes} bytes but only {remaining_bytes} bytes remain in the REAPI materialization budget"
                    ),
                )
            })
    }

    fn reject(&self, kind: &'static str, message: String) -> Status {
        record_materialization_rejection(self.state, kind);
        Status::resource_exhausted(message)
    }
}

impl<'a> MaterializationBudget<'a> {
    fn new(state: &'a SharedState) -> Self {
        Self {
            state,
            remaining_bytes: state.memory.reapi_response_budget_bytes(),
            over_budget_kind: over_budget_shed_kind(state),
            held_permits: Vec::new(),
        }
    }

    fn claim(&mut self, size_bytes: u64, label: &str) -> Result<(), Status> {
        self.admit(size_bytes, label).map_err(|(kind, status)| {
            record_materialization_rejection(self.state, kind);
            status
        })
    }

    // Optional inlining uses the same admission without recording a request failure.
    fn try_claim(&mut self, size_bytes: u64, label: &str) -> Result<(), Status> {
        self.admit(size_bytes, label).map_err(|(_, status)| status)
    }

    fn admit(&mut self, size_bytes: u64, label: &str) -> Result<(), (&'static str, Status)> {
        let requested_bytes = usize::try_from(size_bytes).map_err(|_| {
            (
                shed_kind::REAPI_REQUEST_BUDGET,
                Status::resource_exhausted(format!(
                    "{label} exceeds the maximum addressable REAPI materialization size"
                )),
            )
        })?;
        if requested_bytes > self.remaining_bytes {
            return Err((
                self.over_budget_kind,
                Status::resource_exhausted(format!(
                    "{label} needs {requested_bytes} bytes but only {} bytes remain in the REAPI materialization budget",
                    self.remaining_bytes
                )),
            ));
        }
        let limit_bytes = self.state.memory.reapi_materialization_limit_bytes();
        if requested_bytes > limit_bytes {
            return Err((
                shed_kind::REAPI_REQUEST_BUDGET,
                Status::resource_exhausted(format!(
                    "{label} needs {requested_bytes} bytes but the node allows at most {limit_bytes} bytes of response materialization per request"
                )),
            ));
        }
        let permit = self
            .state
            .memory
            .try_acquire_response_materialization(requested_bytes)
            .map_err(|_| {
                (
                    shed_kind::REAPI_MATERIALIZATION,
                    Status::resource_exhausted(format!(
                        "{label} was rejected because the concurrent REAPI response materialization pool is exhausted"
                    )),
                )
            })?;
        self.remaining_bytes -= requested_bytes;
        if let Some(permit) = permit {
            self.held_permits.push(permit);
        }
        Ok(())
    }

    fn into_response_guard(self) -> Option<crate::memory::ResponseTransportGuard> {
        (!self.held_permits.is_empty()).then(|| {
            crate::memory::ResponseTransportGuard::from_materialization_permits(self.held_permits)
        })
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

/// The canonical SHA-256 of the empty byte string. REAPI clients assume the
/// empty blob always exists and never fetch it (Bazel synthesizes it
/// client-side), so a server must report it present regardless of whether a
/// zero-byte blob was ever uploaded — otherwise a result referencing an empty
/// file, empty stdout, or empty stderr would be treated as evicted even though
/// a replay succeeds.
const EMPTY_BLOB_SHA256: &str = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

fn is_empty_blob(digest: &reapi::Digest) -> bool {
    digest.size_bytes == 0 && digest.hash == EMPTY_BLOB_SHA256
}

fn digest_key(digest: &reapi::Digest) -> Result<String, Status> {
    validate_digest(digest)?;
    Ok(format!("{}/{}", digest.hash, digest.size_bytes))
}

fn validate_digest(digest: &reapi::Digest) -> Result<(), Status> {
    if digest.size_bytes < 0 {
        return Err(Status::invalid_argument("digest size must be non-negative"));
    }
    // The hash becomes the manifest key, and a SHA-256 digest is always 32 bytes
    // = 64 hex chars. The CAS write paths bound it implicitly by verifying the
    // uploaded bytes against it, but update_action_result stores the digest as a
    // key with no body to check against — so without this an authenticated client
    // could persist an arbitrarily long "hash", inflating the manifest key until a
    // backfill index page overflows the receiver's MAX_PEER_PAGE_BYTES ceiling and
    // wedges a joining node. Pin it to the fixed width a conforming client sends.
    if digest.hash.len() != 64 || !digest.hash.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(Status::invalid_argument(
            "digest hash must be a 64-character hex SHA-256",
        ));
    }
    Ok(())
}

pub(super) fn require_sha256(digest_function: i32) -> Result<(), Status> {
    if digest_function == 0 || digest_function == reapi::digest_function::Value::Sha256 as i32 {
        return Ok(());
    }
    Err(Status::invalid_argument(
        "only SHA256 digests are supported",
    ))
}

pub(super) fn namespace_from_instance(instance_name: &str) -> &str {
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
    Status::internal(format!("{context}: {error}"))
}

fn rpc_status_from_grpc_status(status: &Status) -> RpcStatus {
    rpc_status(status.code() as i32, status.message())
}

// Metadata headers a gRPC client uses to declare the request account, mirroring
// the HTTP `tenant_id`/`account_handle` query params. The first non-empty match
// wins. This lets the auth enforce the same request-account-matches-server-
// tenant guard the HTTP path already has; the namespace still comes from the
// REAPI `instance_name`/`resource_name`, so it always matches what is stored.
const TENANT_HEADER_KEYS: &[&str] = &["x-kura-tenant-id", "x-tuist-account-handle"];

const REAPI_USAGE_ARTIFACT_KIND: &str = "reapi";

/// A `GetActionResult` carrying `x-tuist-lookup: presence` only asks whether
/// the entry is still stored: the client will not read its outputs, so the
/// lookup neither promotes the entry nor extends the lifetime of the blobs it
/// references. Tuist module warms use it to republish what was evicted without
/// keeping alive entries that only their own local cache serves.
const LOOKUP_HEADER: &str = "x-tuist-lookup";
const PRESENCE_LOOKUP: &str = "presence";

fn is_presence_lookup(metadata: &tonic::metadata::MetadataMap) -> bool {
    metadata
        .get(LOOKUP_HEADER)
        .and_then(|value| value.to_str().ok())
        == Some(PRESENCE_LOOKUP)
}

fn reapi_usage_artifact_kind(metadata: &tonic::metadata::MetadataMap) -> &'static str {
    match metadata
        .get("x-tuist-artifact-kind")
        .and_then(|value| value.to_str().ok())
    {
        Some("module") => "module",
        _ => REAPI_USAGE_ARTIFACT_KIND,
    }
}

// One bounded output identifier is sufficient for optional profile correlation.
// Never scan or clone all outputs on the cache-serving path.
fn action_result_output_path(result: &reapi::ActionResult) -> String {
    result
        .output_files
        .first()
        .map(|file| &file.path)
        .or_else(|| {
            result
                .output_directories
                .first()
                .map(|directory| &directory.path)
        })
        .filter(|path| path.len() <= 1024)
        .cloned()
        .unwrap_or_default()
}

#[derive(Default)]
struct ReapiRequestMetadata {
    client_kind: String,
    invocation_id: String,
    action_mnemonic: String,
    target_label: String,
    configuration_id: String,
}

fn reapi_request_metadata(metadata: &tonic::metadata::MetadataMap) -> ReapiRequestMetadata {
    let Some(value) = metadata
        .get_bin(REAPI_REQUEST_METADATA_HEADER)
        .and_then(|value| value.to_bytes().ok())
    else {
        return ReapiRequestMetadata {
            client_kind: "unknown".into(),
            ..Default::default()
        };
    };

    let Ok(metadata) = reapi::RequestMetadata::decode(value) else {
        return ReapiRequestMetadata {
            client_kind: "unknown".into(),
            ..Default::default()
        };
    };

    let client_kind = metadata
        .tool_details
        .map(|details| details.tool_name)
        .filter(|name| name == "bazel")
        .unwrap_or_else(|| "other".into());

    ReapiRequestMetadata {
        client_kind,
        invocation_id: metadata.tool_invocation_id,
        action_mnemonic: metadata.action_mnemonic,
        target_label: metadata.target_id,
        configuration_id: metadata.configuration_id,
    }
}

fn reapi_cache_event_context(
    metadata: &tonic::metadata::MetadataMap,
    namespace_id: &str,
    fallback_tenant_id: &str,
) -> Option<Arc<ReapiCacheAnalyticsContext>> {
    let attribution = reapi_request_metadata(metadata);
    if attribution.client_kind != "bazel" {
        return None;
    }

    Some(Arc::new(ReapiCacheAnalyticsContext {
        account_handle: usage_tenant_id(metadata, fallback_tenant_id),
        project_handle: namespace_id.to_owned(),
        client_kind: "bazel",
        invocation_id: attribution.invocation_id,
        action_mnemonic: attribution.action_mnemonic,
        target_label: attribution.target_label,
        configuration_id: attribution.configuration_id,
    }))
}

// The request-declared tenant, read straight from the metadata: the first
// non-empty `TENANT_HEADER_KEYS` value, taking the first value of a repeated
// key. Authorization (`grpc_request_context`) and billing (`usage_tenant_id`)
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
// `TENANT_HEADER_KEYS` metadata headers (the same headers the auth
// authorizes against, via the shared [`tenant_id_from_metadata`]). Falls back to
// the node's configured tenant when the client omits it, so REAPI bandwidth is
// always attributed rather than silently dropped.
fn usage_tenant_id(metadata: &tonic::metadata::MetadataMap, fallback_tenant_id: &str) -> String {
    tenant_id_from_metadata(metadata).unwrap_or_else(|| fallback_tenant_id.to_owned())
}

pub(super) struct BuildEventPublication {
    pub account_handle: String,
    pub network_trusted: bool,
}

pub(super) fn network_build_event_request(
    metadata: &tonic::metadata::MetadataMap,
) -> Result<bool, Status> {
    if metadata.contains_key("authorization") {
        return Ok(false);
    }
    let count = metadata
        .get_all("x-tuist-network-trusted-publishing")
        .iter()
        .count();
    if count == 0 {
        return Ok(false);
    }
    if count != 1
        || metadata
            .get("x-tuist-network-trusted-publishing")
            .and_then(|value| value.to_str().ok())
            != Some("true")
    {
        return Err(Status::invalid_argument(
            "Invalid network publishing metadata",
        ));
    }
    Ok(true)
}

pub(super) async fn authorize_build_event_request(
    state: &SharedState,
    metadata: &tonic::metadata::MetadataMap,
    project_handle: &str,
    _route: &str,
) -> Result<BuildEventPublication, Status> {
    if state.runtime.is_draining() {
        return Err(Status::unavailable("server is draining"));
    }

    let account_handle = usage_tenant_id(metadata, &state.account_identity.load().handle);
    let supplied_credentials = metadata.get_all("authorization").iter().count();
    if supplied_credentials > 1
        || (supplied_credentials == 1
            && metadata
                .get("authorization")
                .and_then(|value| value.to_str().ok())
                .is_none_or(|value| value.trim().is_empty()))
    {
        return Err(Status::unauthenticated("Invalid authorization metadata"));
    }
    let network_trusted = network_build_event_request(metadata)?;
    let Some(auth) = state.auth.as_ref() else {
        if network_trusted {
            return Err(Status::permission_denied(
                "Network reporting requires a configured control plane",
            ));
        }
        return Ok(BuildEventPublication {
            account_handle,
            network_trusted: false,
        });
    };

    let spec = GrpcRequestSpec {
        operation: "build_event_stream",
        namespace_id: Some(project_handle),
    };
    let mut context = grpc_request_context(&state.config.tenant_id, &spec, metadata);
    state.canonicalize_auth_context(&mut context);

    let decision = if network_trusted {
        auth.network_build_event_access(&context.server_tenant_id, project_handle)
            .await
    } else {
        auth.evaluate_access(&context).await
    };
    match decision {
        AccessDecision::Allow => Ok(BuildEventPublication {
            account_handle: context.server_tenant_id,
            network_trusted,
        }),
        AccessDecision::Deny(deny) => Err(grpc_status_from_http_status(deny.status, &deny.message)),
    }
}

fn grpc_request_context(
    server_tenant_id: &str,
    spec: &GrpcRequestSpec<'_>,
    metadata: &tonic::metadata::MetadataMap,
) -> RequestContext {
    let authorization = metadata
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        .map(ToOwned::to_owned);
    let tenant_id = tenant_id_from_metadata(metadata);
    RequestContext {
        transport: "grpc".into(),
        method: "RPC".into(),
        operation: spec.operation.to_owned(),
        server_tenant_id: server_tenant_id.to_owned(),
        tenant_id,
        namespace_id: spec.namespace_id.map(ToOwned::to_owned),
        authorization,
        headers: BTreeMap::new(),
    }
}

/// gRPC has no code for payment required, so an exhausted plan would arrive as
/// an ordinary permission denial. Clients that must keep working through a
/// refusal, the Xcode cache plugin above all, need to tell the two apart
/// without matching on message text, so the reason rides in metadata.
pub const REFUSAL_REASON_KEY: &str = "tuist-refusal-reason";
pub const REFUSAL_REASON_PAYMENT_REQUIRED: &str = "payment_required";

fn grpc_status_from_http_status(status: u16, message: &str) -> Status {
    match status {
        402 => {
            let mut status = Status::permission_denied(message.to_owned());
            status.metadata_mut().insert(
                REFUSAL_REASON_KEY,
                tonic::metadata::MetadataValue::from_static(REFUSAL_REASON_PAYMENT_REQUIRED),
            );
            status
        }
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
    hash_range: std::ops::Range<usize>,
    size_bytes: u64,
    key: String,
    // Wire compressor negotiated on the resource_name. The store key is always
    // built from the uncompressed digest, so compressed and identity variants
    // resolve to the same on-disk blob; only the wire encoding differs.
    compressor: BlobCompressor,
}

impl BlobResource {
    fn hash(&self) -> &str {
        &self.key[self.hash_range.clone()]
    }
}

/// Wire compressor a client requested on a `blobs/` or `compressed-blobs/{c}/`
/// resource. Kura only implements zstd; anything else the parser rejects up
/// front so no request-time codepath ever has to handle it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BlobCompressor {
    Identity,
    Zstd,
}

fn digest_matches_hex(actual: &[u8], expected_hex: &str) -> bool {
    if expected_hex.len() != 64
        || !expected_hex
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return false;
    }
    let mut expected = [0_u8; 32];
    hex::decode_to_slice(expected_hex, &mut expected).is_ok() && actual == expected
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
    let mut blob_index = None;
    // For `compressed-blobs/{compressor}/{hash}/{size}` the compressor segment
    // is the first captured slot after the blob marker; for plain `blobs/` it
    // stays `Some(Identity)` and never consumes a segment.
    let mut compressor: Option<BlobCompressor> = None;
    let mut awaiting_compressor = false;
    let mut hash = None;
    let mut encoded_size = None;
    let mut has_upload_prefix = false;
    let mut namespace_capacity = 0;
    let mut previous = None;
    let mut second_previous = None;
    let mut normalized_prefix_len = 0_usize;
    for (index, part) in resource_name
        .split('/')
        .filter(|part| !part.is_empty())
        .enumerate()
    {
        let is_blob_marker = part == "blobs" || part == "compressed-blobs";
        if is_blob_marker {
            blob_index = Some(index);
            hash = None;
            encoded_size = None;
            if part == "compressed-blobs" {
                compressor = None;
                awaiting_compressor = true;
            } else {
                compressor = Some(BlobCompressor::Identity);
                awaiting_compressor = false;
            }
            has_upload_prefix = index >= 2 && second_previous == Some("uploads");
            namespace_capacity = if has_upload_prefix {
                let upload_bytes = second_previous.map_or(0, str::len);
                let upload_id_bytes = previous.map_or(0, str::len);
                let separators = if index == 2 { 1 } else { 2 };
                normalized_prefix_len
                    .saturating_sub(upload_bytes)
                    .saturating_sub(upload_id_bytes)
                    .saturating_sub(separators)
            } else {
                normalized_prefix_len
            };
        } else if blob_index.is_some() {
            if awaiting_compressor {
                compressor = Some(parse_wire_compressor(part)?);
                awaiting_compressor = false;
            } else if hash.is_none() {
                hash = Some(part);
            } else if encoded_size.is_none() {
                encoded_size = Some(part);
            }
        }

        if index > 0 {
            normalized_prefix_len = normalized_prefix_len.saturating_add(1);
        }
        normalized_prefix_len = normalized_prefix_len.saturating_add(part.len());
        second_previous = previous;
        previous = Some(part);
    }

    let Some(blob_index) = blob_index else {
        return Err(Status::invalid_argument(
            "resource_name must contain /blobs/ or /compressed-blobs/",
        ));
    };
    let Some(compressor) = compressor else {
        return Err(Status::invalid_argument(
            "compressed-blobs resource_name is missing the compressor",
        ));
    };
    let Some(hash) = hash else {
        return Err(Status::invalid_argument(
            "resource_name is missing digest components",
        ));
    };
    let Some(encoded_size) = encoded_size else {
        return Err(Status::invalid_argument(
            "resource_name is missing digest components",
        ));
    };

    let namespace_len = if has_upload_prefix {
        blob_index - 2
    } else {
        if require_upload_prefix {
            return Err(Status::invalid_argument(
                "write resource_name must include uploads/{uuid}/blobs/{hash}/{size} or uploads/{uuid}/compressed-blobs/{compressor}/{hash}/{size}",
            ));
        }
        blob_index
    };
    let size_bytes = encoded_size
        .parse::<u64>()
        .map_err(|error| Status::invalid_argument(format!("invalid blob size: {error}")))?;
    let namespace_id = if namespace_len == 0 {
        DEFAULT_INSTANCE_NAME.to_string()
    } else {
        let mut namespace_id = String::with_capacity(namespace_capacity);
        for part in resource_name
            .split('/')
            .filter(|part| !part.is_empty())
            .take(namespace_len)
        {
            if !namespace_id.is_empty() {
                namespace_id.push('/');
            }
            namespace_id.push_str(part);
        }
        namespace_id
    };
    // Key CAS blobs the same way as the digest-based paths (FindMissingBlobs,
    // BatchUpdateBlobs, BatchReadBlobs) which use `blob_key(&digest_key(..))` =
    // "blob/{hash}/{size}". Without the `blob/` prefix, blobs uploaded via ByteStream were
    // stored under "{hash}/{size}" and were invisible to FindMissingBlobs, so REAPI clients
    // (e.g. Bazel) treated the produced outputs as missing and re-executed the action.
    let mut key = String::with_capacity("blob/".len() + hash.len() + 1 + encoded_size.len());
    key.push_str("blob/");
    key.push_str(hash);
    key.push('/');
    use std::fmt::Write as _;
    write!(&mut key, "{size_bytes}").expect("writing to a string cannot fail");

    Ok(BlobResource {
        namespace_id,
        hash_range: "blob/".len().."blob/".len() + hash.len(),
        size_bytes,
        key,
        compressor,
    })
}

fn parse_wire_compressor(part: &str) -> Result<BlobCompressor, Status> {
    // REAPI leaves the compressor segment case-sensitive but Bazel and Buck
    // both send lowercase names, matching the enum names in
    // `Compressor.Value.as_str_name()` lowercased. Accept only what we
    // actually implement; anything else is UNIMPLEMENTED so clients fall back
    // to identity rather than sending bytes we cannot decode.
    match part {
        "identity" => Ok(BlobCompressor::Identity),
        "zstd" => Ok(BlobCompressor::Zstd),
        "deflate" | "brotli" => Err(Status::unimplemented(format!(
            "compressor '{part}' is not supported; only 'zstd' and 'identity' are available"
        ))),
        other => Err(Status::invalid_argument(format!(
            "unknown compressor '{other}' in resource_name"
        ))),
    }
}

#[cfg(test)]
fn parse_blob_resource_name_allocating(
    resource_name: &str,
    require_upload_prefix: bool,
) -> Result<BlobResource, Status> {
    let parts = resource_name
        .split('/')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>();
    let (blob_index, compressor, hash_offset) = match parts
        .iter()
        .rposition(|part| *part == "blobs" || *part == "compressed-blobs")
    {
        Some(index) if parts[index] == "compressed-blobs" => {
            let Some(name) = parts.get(index + 1) else {
                return Err(Status::invalid_argument(
                    "compressed-blobs resource_name is missing the compressor",
                ));
            };
            (index, parse_wire_compressor(name)?, index + 2)
        }
        Some(index) => (index, BlobCompressor::Identity, index + 1),
        None => {
            return Err(Status::invalid_argument(
                "resource_name must contain /blobs/ or /compressed-blobs/",
            ));
        }
    };
    if hash_offset + 1 >= parts.len() {
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
                "write resource_name must include uploads/{uuid}/blobs/{hash}/{size} or uploads/{uuid}/compressed-blobs/{compressor}/{hash}/{size}",
            ));
        }
        prefix
    };
    let hash = parts[hash_offset].to_owned();
    let size_bytes = parts[hash_offset + 1]
        .parse::<u64>()
        .map_err(|error| Status::invalid_argument(format!("invalid blob size: {error}")))?;
    let namespace_id = if namespace_parts.is_empty() {
        DEFAULT_INSTANCE_NAME.to_string()
    } else {
        namespace_parts.join("/")
    };
    let key = blob_key(&format!("{hash}/{size_bytes}"));

    Ok(BlobResource {
        namespace_id,
        hash_range: "blob/".len().."blob/".len() + hash.len(),
        size_bytes,
        key,
        compressor,
    })
}

#[cfg(test)]
#[path = "bytestream_recovery_tests.rs"]
mod bytestream_recovery_tests;

#[cfg(test)]
mod tests {

    // gRPC has no payment-required code, so the refusal arrives as an ordinary
    // permission denial. Clients that keep working through it need the reason
    // without matching on message text.
    #[test]
    fn an_exhausted_plan_carries_a_machine_readable_reason() {
        let status = grpc_status_from_http_status(402, "upgrade to Tuist Pro");

        assert_eq!(status.code(), tonic::Code::PermissionDenied);
        assert_eq!(status.message(), "upgrade to Tuist Pro");
        assert_eq!(
            status
                .metadata()
                .get(REFUSAL_REASON_KEY)
                .and_then(|reason| reason.to_str().ok()),
            Some(REFUSAL_REASON_PAYMENT_REQUIRED)
        );
    }

    #[test]
    fn an_ordinary_refusal_carries_no_reason() {
        let status = grpc_status_from_http_status(403, "nope");

        assert_eq!(status.code(), tonic::Code::PermissionDenied);
        assert!(status.metadata().get(REFUSAL_REASON_KEY).is_none());
    }
    use super::*;
    use bytes::Bytes;
    use http_body_util::BodyExt;
    use std::{convert::Infallible, time::Duration};
    use tonic::codegen::{Service, http};
    use tower::{Layer, ServiceExt};

    #[test]
    fn staging_prefix_fill_never_grows_the_admitted_window() {
        let window = 1024;
        let mut buffer = Vec::with_capacity(window);
        buffer.extend_from_slice(&vec![0xa5; window - 7]);
        let data = vec![0x5a; 16 * window];
        assert_eq!(fill_staging_window(&mut buffer, window, &data), 7);
        assert_eq!(buffer.len(), window);
        assert_eq!(buffer.capacity(), window);
        assert_eq!(&buffer[..window - 7], &vec![0xa5; window - 7]);
        assert_eq!(&buffer[window - 7..], &[0x5a; 7]);
        buffer.clear();
        assert_eq!(fill_staging_window(&mut buffer, window, &data), window);
        assert_eq!(buffer.capacity(), window);
    }

    // Current-thread runtimes take the direct file-operation fallback.
    #[tokio::test]
    async fn staging_coalescer_preserves_ragged_bytes_without_growing_its_window() {
        assert_staging_coalescer_preserves_ragged_bytes(FileCachePolicy::Foreground {
            reservation_bytes: u64::MAX,
        })
        .await;
    }

    // The multithreaded runtime isolates each write, sync and cache release
    // with `block_in_place`; a bounded policy releases completed ranges
    // through the same staging handle as it goes.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn bounded_staging_releases_completed_ranges_through_its_handle() {
        assert_staging_coalescer_preserves_ragged_bytes(FileCachePolicy::Bounded).await;
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn clamped_staging_bounds_both_coalescing_and_file_cache_windows() {
        assert_staging_coalescer_with_window(
            FileCachePolicy::Bounded,
            REAPI_STAGING_WRITE_BUFFER_BYTES as usize,
            REAPI_STAGING_WRITE_BUFFER_BYTES,
        )
        .await;
    }

    async fn assert_staging_coalescer_preserves_ragged_bytes(policy: FileCachePolicy) {
        assert_staging_coalescer_with_window(
            policy,
            REAPI_STAGING_WRITE_BUFFER_BYTES as usize,
            FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES,
        )
        .await;
    }

    async fn assert_staging_coalescer_with_window(
        policy: FileCachePolicy,
        window: usize,
        cache_drop_interval: u64,
    ) {
        let context = test_context(|_| {}).await;
        let service = ReapiService::new(context.state.clone());
        let blob: Vec<_> = (0..9 * window + 19).map(|i| (i * 31) as u8).collect();
        let path = context.state.config.tmp_dir.join("bounded-coalescer");
        let file = context
            .state
            .io
            .create_new_persistent_file(&path)
            .await
            .unwrap();
        let mut buffer = Vec::with_capacity(window);
        let mut staged = 0;
        let mut advised = 0;
        let mut offset = 0;
        for size in [window - 7, 3 * window + 17, 1, window - 1, 9, 4 * window] {
            let end = (offset + size).min(blob.len());
            service
                .coalesce_staging(
                    &blob[offset..end],
                    &mut buffer,
                    window,
                    &file,
                    policy,
                    cache_drop_interval,
                    &mut staged,
                    &mut advised,
                )
                .unwrap();
            offset = end;
            assert!(buffer.len() < window);
            assert_eq!(buffer.capacity(), window);
            if policy == FileCachePolicy::Bounded {
                assert!(staged - advised < cache_drop_interval);
            }
            assert_eq!(
                std::fs::metadata(&path).unwrap().len(),
                staged,
                "every flushed byte is in the file at its staged offset"
            );
        }
        assert_eq!(offset, blob.len());
        service
            .write_staging(
                &buffer,
                &file,
                policy,
                cache_drop_interval,
                &mut staged,
                &mut advised,
            )
            .unwrap();
        assert_eq!(staged as usize, blob.len());
        if policy == FileCachePolicy::Bounded {
            assert!(advised >= cache_drop_interval);
        } else {
            assert_eq!(advised, 0);
        }
        assert_eq!(tokio::fs::read(&path).await.unwrap(), blob);
    }

    fn grpc_message(encoded_message_bytes: usize, byte: u8) -> Vec<u8> {
        let mut framed = Vec::with_capacity(GRPC_MESSAGE_HEADER_BYTES + encoded_message_bytes);
        framed.push(0);
        framed.extend_from_slice(&(encoded_message_bytes as u32).to_be_bytes());
        framed.extend(std::iter::repeat_n(byte, encoded_message_bytes));
        framed
    }

    #[tokio::test]
    async fn bytestream_read_response_stream_preserves_bytes_and_chunk_bound() {
        let reader = ArtifactReader::Inline {
            bytes: bytes::Bytes::from(vec![0x5a; 10_001]),
            offset: 0,
        };
        let responses = bytestream_read_response_stream(reader, 1_024)
            .collect::<Vec<_>>()
            .await;

        assert_eq!(responses.len(), 10);
        let data = responses
            .into_iter()
            .flat_map(|response| response.expect("stream response").data)
            .collect::<Vec<_>>();
        assert_eq!(data, vec![0x5a; 10_001]);
    }

    #[tokio::test]
    async fn segment_reader_owned_chunks_preserve_file_range_and_chunk_bound() {
        let context = test_context(|_| {}).await;
        let path = context
            .state
            .config
            .tmp_dir
            .join("owned-segment-reader-test");
        let contents = (0..10_001)
            .map(|index| (index % 251) as u8)
            .collect::<Vec<_>>();
        std::fs::write(&path, &contents).expect("write segment reader fixture");
        let handle = std::sync::Arc::new(
            context
                .state
                .io
                .open_persistent_read_file(&path)
                .await
                .expect("open segment reader fixture"),
        );
        let offset = 17_usize;
        let length = 9_001_usize;
        let reader = ArtifactReader::FileRange(crate::segment::reader::SegmentReader::new(
            handle,
            offset as u64,
            length as u64,
        ));
        let responses = bytestream_read_response_stream(reader, 1_024)
            .collect::<Vec<_>>()
            .await;

        assert!(
            responses
                .iter()
                .all(|response| response.as_ref().expect("stream response").data.len() <= 1_024)
        );
        let data = responses
            .into_iter()
            .flat_map(|response| response.expect("stream response").data)
            .collect::<Vec<_>>();
        assert_eq!(data, contents[offset..offset + length]);
    }

    #[tokio::test]
    async fn artifact_reader_inline_bytes_stream_reuses_the_source_allocation() {
        let bytes = Bytes::from(vec![0x5a; 2_048]);
        let source = bytes.as_ptr();
        let stream = ArtifactReader::Inline { bytes, offset: 0 }.into_bytes_stream(1_024);
        tokio::pin!(stream);

        let chunk = stream
            .next()
            .await
            .expect("one inline chunk")
            .expect("successful inline chunk");

        assert_eq!(chunk.as_ptr(), source);
        assert_eq!(chunk.len(), 1_024);
    }

    #[tokio::test]
    async fn bytestream_read_response_owns_the_buffer_filled_by_the_reader() {
        use std::sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        };
        use std::task::Poll;

        struct PointerRecordingReader {
            destination: Arc<AtomicUsize>,
            remaining: usize,
        }

        impl tokio::io::AsyncRead for PointerRecordingReader {
            fn poll_read(
                mut self: std::pin::Pin<&mut Self>,
                _context: &mut std::task::Context<'_>,
                buffer: &mut tokio::io::ReadBuf<'_>,
            ) -> Poll<std::io::Result<()>> {
                if self.remaining == 0 {
                    return Poll::Ready(Ok(()));
                }
                let length = self.remaining.min(buffer.remaining());
                let destination = buffer.initialize_unfilled_to(length);
                self.destination
                    .store(destination.as_ptr() as usize, Ordering::Relaxed);
                destination.fill(0x5a);
                buffer.advance(length);
                self.remaining -= length;
                Poll::Ready(Ok(()))
            }
        }

        let destination = Arc::new(AtomicUsize::new(0));
        let reader = PointerRecordingReader {
            destination: destination.clone(),
            remaining: 1_024,
        };
        let stream = direct_bytestream_read_response_stream(reader, 1_024);
        tokio::pin!(stream);
        let response = stream
            .next()
            .await
            .expect("one response")
            .expect("successful response");

        assert_eq!(
            response.data.as_ptr() as usize,
            destination.load(Ordering::Relaxed)
        );
    }

    #[tokio::test]
    #[ignore = "performance benchmark run manually"]
    async fn bytestream_read_chunk_materialization_benchmark() {
        use tokio::io::AsyncReadExt as _;

        const SAMPLE_BYTES: u64 = 4 * 1_024 * 1_024 * 1_024;
        const CHUNK_BYTES: usize = 512 * 1_024;
        const SAMPLE_COUNT: usize = 8;

        async fn measure<S>(stream: S) -> Duration
        where
            S: tokio_stream::Stream<Item = Result<bytestream::ReadResponse, Status>>,
        {
            tokio::pin!(stream);
            let started_at = Instant::now();
            let mut read_bytes = 0_u64;
            while let Some(response) = stream.next().await {
                let response = response.expect("benchmark stream response");
                std::hint::black_box(response.data.as_ptr());
                read_bytes = read_bytes.saturating_add(response.data.len() as u64);
            }
            assert_eq!(read_bytes, SAMPLE_BYTES);
            started_at.elapsed()
        }

        let mut speedups = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut baseline_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut candidate_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        for sample in 0..SAMPLE_COUNT {
            let baseline = copying_bytestream_read_response_stream(
                tokio::io::repeat(0x5a).take(SAMPLE_BYTES),
                CHUNK_BYTES,
            );
            let candidate = direct_bytestream_read_response_stream(
                tokio::io::repeat(0x5a).take(SAMPLE_BYTES),
                CHUNK_BYTES,
            );
            let (baseline_elapsed, candidate_elapsed) = if sample % 2 == 0 {
                (measure(baseline).await, measure(candidate).await)
            } else {
                let candidate_elapsed = measure(candidate).await;
                let baseline_elapsed = measure(baseline).await;
                (baseline_elapsed, candidate_elapsed)
            };
            if sample > 0 {
                let mebibytes = SAMPLE_BYTES as f64 / (1_024.0 * 1_024.0);
                baseline_throughputs.push(mebibytes / baseline_elapsed.as_secs_f64());
                candidate_throughputs.push(mebibytes / candidate_elapsed.as_secs_f64());
                speedups.push(baseline_elapsed.as_secs_f64() / candidate_elapsed.as_secs_f64());
            }
        }
        speedups.sort_by(f64::total_cmp);
        baseline_throughputs.sort_by(f64::total_cmp);
        candidate_throughputs.sort_by(f64::total_cmp);
        println!(
            "METRIC bytestream_read_speedup_ratio={:.6}",
            speedups[speedups.len() / 2]
        );
        println!(
            "METRIC baseline_mebibytes_per_second={:.3}",
            baseline_throughputs[baseline_throughputs.len() / 2]
        );
        println!(
            "METRIC candidate_mebibytes_per_second={:.3}",
            candidate_throughputs[candidate_throughputs.len() / 2]
        );
    }

    #[tokio::test]
    #[ignore = "performance benchmark run manually"]
    async fn segment_reader_owned_chunk_benchmark() {
        const SAMPLE_BYTES: u64 = 512 * 1_024 * 1_024;
        const CHUNK_BYTES: usize = 512 * 1_024;
        const SAMPLE_COUNT: usize = 8;

        async fn measure<S>(stream: S) -> Duration
        where
            S: tokio_stream::Stream<Item = Result<bytestream::ReadResponse, Status>>,
        {
            tokio::pin!(stream);
            let started_at = Instant::now();
            let mut read_bytes = 0_u64;
            while let Some(response) = stream.next().await {
                let response = response.expect("benchmark stream response");
                std::hint::black_box(response.data.as_ptr());
                read_bytes = read_bytes.saturating_add(response.data.len() as u64);
            }
            assert_eq!(read_bytes, SAMPLE_BYTES);
            started_at.elapsed()
        }

        let context = test_context(|config| {
            config.file_descriptor_pool_size = 4;
        })
        .await;
        let path = context
            .state
            .config
            .tmp_dir
            .join("owned-segment-reader-benchmark");
        let file = std::fs::File::create(&path).expect("create sparse benchmark file");
        file.set_len(SAMPLE_BYTES)
            .expect("size sparse benchmark file");
        drop(file);
        let handle = std::sync::Arc::new(
            context
                .state
                .io
                .open_persistent_read_file(&path)
                .await
                .expect("open benchmark file"),
        );
        let reader = || {
            ArtifactReader::FileRange(crate::segment::reader::SegmentReader::new(
                handle.clone(),
                0,
                SAMPLE_BYTES,
            ))
        };

        let mut speedups = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut baseline_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut candidate_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        for sample in 0..SAMPLE_COUNT {
            let baseline = direct_bytestream_read_response_stream(reader(), CHUNK_BYTES);
            let candidate = bytestream_read_response_stream(reader(), CHUNK_BYTES);
            let (baseline_elapsed, candidate_elapsed) = if sample % 2 == 0 {
                (measure(baseline).await, measure(candidate).await)
            } else {
                let candidate_elapsed = measure(candidate).await;
                let baseline_elapsed = measure(baseline).await;
                (baseline_elapsed, candidate_elapsed)
            };
            if sample > 0 {
                let mebibytes = SAMPLE_BYTES as f64 / (1_024.0 * 1_024.0);
                baseline_throughputs.push(mebibytes / baseline_elapsed.as_secs_f64());
                candidate_throughputs.push(mebibytes / candidate_elapsed.as_secs_f64());
                speedups.push(baseline_elapsed.as_secs_f64() / candidate_elapsed.as_secs_f64());
            }
        }
        speedups.sort_by(f64::total_cmp);
        baseline_throughputs.sort_by(f64::total_cmp);
        candidate_throughputs.sort_by(f64::total_cmp);
        println!(
            "METRIC segment_reader_owned_speedup_ratio={:.6}",
            speedups[speedups.len() / 2]
        );
        println!(
            "METRIC baseline_mebibytes_per_second={:.3}",
            baseline_throughputs[baseline_throughputs.len() / 2]
        );
        println!(
            "METRIC candidate_mebibytes_per_second={:.3}",
            candidate_throughputs[candidate_throughputs.len() / 2]
        );
    }

    #[tokio::test]
    #[ignore = "performance benchmark run manually"]
    async fn artifact_reader_inline_bytes_stream_benchmark() {
        const ARTIFACT_BYTES: usize = 4 * 1_024 * 1_024;
        const CHUNK_BYTES: usize = 512 * 1_024;
        const REPETITIONS: usize = 256;
        const SAMPLE_COUNT: usize = 8;

        async fn measure_copying(bytes: &Bytes) -> Duration {
            let started_at = Instant::now();
            let mut read_bytes = 0_u64;
            for _ in 0..REPETITIONS {
                let mut reader = ArtifactReader::Inline {
                    bytes: bytes.clone(),
                    offset: 0,
                };
                loop {
                    let chunk = reader
                        .read_chunk_owned(CHUNK_BYTES)
                        .await
                        .expect("benchmark copied inline chunk");
                    if chunk.is_empty() {
                        break;
                    }
                    std::hint::black_box(chunk.as_ptr());
                    read_bytes = read_bytes.saturating_add(chunk.len() as u64);
                }
            }
            assert_eq!(read_bytes, (ARTIFACT_BYTES * REPETITIONS) as u64);
            started_at.elapsed()
        }

        async fn measure_owned(bytes: &Bytes) -> Duration {
            let started_at = Instant::now();
            let mut read_bytes = 0_u64;
            for _ in 0..REPETITIONS {
                let stream = ArtifactReader::Inline {
                    bytes: bytes.clone(),
                    offset: 0,
                }
                .into_bytes_stream(CHUNK_BYTES);
                tokio::pin!(stream);
                while let Some(chunk) = stream.next().await {
                    let chunk = chunk.expect("benchmark owned inline chunk");
                    std::hint::black_box(chunk.as_ptr());
                    read_bytes = read_bytes.saturating_add(chunk.len() as u64);
                }
            }
            assert_eq!(read_bytes, (ARTIFACT_BYTES * REPETITIONS) as u64);
            started_at.elapsed()
        }

        let bytes = Bytes::from(vec![0x5a; ARTIFACT_BYTES]);
        let mut speedups = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut baseline_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut candidate_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        for sample in 0..SAMPLE_COUNT {
            let (baseline_elapsed, candidate_elapsed) = if sample % 2 == 0 {
                (measure_copying(&bytes).await, measure_owned(&bytes).await)
            } else {
                let candidate_elapsed = measure_owned(&bytes).await;
                let baseline_elapsed = measure_copying(&bytes).await;
                (baseline_elapsed, candidate_elapsed)
            };
            if sample > 0 {
                let mebibytes = (ARTIFACT_BYTES * REPETITIONS) as f64 / (1_024.0 * 1_024.0);
                baseline_throughputs.push(mebibytes / baseline_elapsed.as_secs_f64());
                candidate_throughputs.push(mebibytes / candidate_elapsed.as_secs_f64());
                speedups.push(baseline_elapsed.as_secs_f64() / candidate_elapsed.as_secs_f64());
            }
        }
        speedups.sort_by(f64::total_cmp);
        baseline_throughputs.sort_by(f64::total_cmp);
        candidate_throughputs.sort_by(f64::total_cmp);
        println!(
            "METRIC inline_bytes_stream_speedup_ratio={:.6}",
            speedups[speedups.len() / 2]
        );
        println!(
            "METRIC baseline_mebibytes_per_second={:.3}",
            baseline_throughputs[baseline_throughputs.len() / 2]
        );
        println!(
            "METRIC candidate_mebibytes_per_second={:.3}",
            candidate_throughputs[candidate_throughputs.len() / 2]
        );
    }

    fn grpc_request<T: Message>(path: &str, message: &T) -> http::Request<axum::body::Body> {
        let encoded = message.encode_to_vec();
        let mut framed = Vec::with_capacity(GRPC_MESSAGE_HEADER_BYTES + encoded.len());
        framed.push(0);
        framed.extend_from_slice(
            &u32::try_from(encoded.len())
                .expect("test message should fit in a gRPC frame")
                .to_be_bytes(),
        );
        framed.extend_from_slice(&encoded);
        http::Request::builder()
            .method("POST")
            .uri(path)
            .header("content-type", "application/grpc")
            .header("te", "trailers")
            .body(axum::body::Body::from(framed))
            .expect("gRPC request should build")
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

    fn bytestream_admission(
        hard_limit_bytes: u64,
    ) -> (crate::memory::MemoryController, GrpcWriteAdmission) {
        grpc_write_admission(hard_limit_bytes, BYTESTREAM_WRITE_DECODE_COPIES)
    }

    fn grpc_write_admission(
        hard_limit_bytes: u64,
        decode_copy_multiplier: u64,
    ) -> (crate::memory::MemoryController, GrpcWriteAdmission) {
        let metrics = crate::metrics::Metrics::new("local".into(), "tenant".into());
        let memory = crate::memory::MemoryController::with_runtime_limit(
            metrics.clone(),
            hard_limit_bytes.saturating_mul(2),
            hard_limit_bytes / 2,
            hard_limit_bytes,
        );
        memory.observe(0);
        let admission = GrpcWriteAdmission::new(
            &memory,
            decode_copy_multiplier,
            metrics.grpc_write_admission_metrics(),
        )
        .expect("zero-byte initial reservation should fit");
        (memory, admission)
    }

    fn add_direct_write_admission<T>(
        state: &SharedState,
        request: &mut Request<T>,
        decode_copy_multiplier: u64,
    ) {
        request.extensions_mut().insert(
            GrpcWriteAdmission::new(
                &state.memory,
                decode_copy_multiplier,
                state.metrics.grpc_write_admission_metrics(),
            )
            .expect("test write admission should fit"),
        );
    }

    #[tokio::test]
    async fn bytestream_admission_scans_fragmented_headers_before_forwarding() {
        let (memory, admission) = bytestream_admission(8 * 1024 * 1024);
        let header = grpc_message(1024, 0)[..GRPC_MESSAGE_HEADER_BYTES].to_vec();
        let frames = header
            .into_iter()
            .map(|byte| Ok::<_, Infallible>(Bytes::from(vec![byte])));
        let mut body = GrpcWriteAdmissionBody::new(
            axum::body::Body::from_stream(futures_util::stream::iter(frames)),
            admission,
            GrpcWriteShapePolicy::ByteStream,
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
        let mut body = GrpcWriteAdmissionBody::new(
            axum::body::Body::from(framed),
            admission,
            GrpcWriteShapePolicy::ByteStream,
        );

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
        let mut body = GrpcWriteAdmissionBody::new(
            axum::body::Body::from(header),
            admission,
            GrpcWriteShapePolicy::ByteStream,
        );

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
        let mut body = GrpcWriteAdmissionBody::new(
            axum::body::Body::from(framed),
            admission,
            GrpcWriteShapePolicy::ByteStream,
        );

        let error = body
            .frame()
            .await
            .expect("compressed frame")
            .expect_err("compressed messages must be rejected before decoding");

        assert_eq!(error.code(), tonic::Code::Unimplemented);
        assert_eq!(memory.transient_reserved_bytes(), 0);
    }

    #[test]
    fn every_remote_execution_write_path_has_decode_admission() {
        assert_eq!(
            grpc_write_shape_policy(BYTESTREAM_WRITE_PATH),
            Some(GrpcWriteShapePolicy::ByteStream)
        );
        assert_eq!(
            grpc_write_shape_policy(CAS_BATCH_UPDATE_PATH),
            Some(GrpcWriteShapePolicy::BatchUpdate)
        );
        assert_eq!(
            grpc_write_shape_policy(ACTION_CACHE_UPDATE_PATH),
            Some(GrpcWriteShapePolicy::ActionUpdate)
        );
        assert_eq!(grpc_write_shape_policy("/read"), None);
    }

    #[test]
    fn batch_update_wire_shape_charges_request_cardinality() {
        let request_count = 4_096;
        let encoded = reapi::BatchUpdateBlobsRequest {
            requests: vec![reapi::batch_update_blobs_request::Request::default(); request_count],
            ..Default::default()
        }
        .encode_to_vec();
        let shape =
            inspect_batch_update_wire(&encoded).expect("valid structure should be admitted");
        assert_eq!(
            shape.structural_bytes,
            request_count as u64 * REAPI_BATCH_REQUEST_STRUCTURAL_BYTES
        );
    }

    #[test]
    fn action_result_wire_shape_charges_output_cardinality() {
        let output_count = 16_384;
        let encoded = reapi::ActionResult {
            output_files: vec![reapi::OutputFile::default(); output_count],
            ..Default::default()
        }
        .encode_to_vec();
        let shape =
            inspect_action_result_wire(&encoded).expect("valid structure should be admitted");
        assert_eq!(
            shape.structural_bytes,
            output_count as u64 * REAPI_ACTION_OUTPUT_STRUCTURAL_BYTES
        );
    }

    #[test]
    fn protobuf_scanner_matches_decoder_for_balanced_unknown_groups() {
        use prost::encoding::{WireType, encode_key, encode_varint};

        let request = reapi::BatchUpdateBlobsRequest {
            instance_name: "ios".into(),
            requests: vec![reapi::batch_update_blobs_request::Request::default()],
            ..Default::default()
        };
        let mut encoded = request.encode_to_vec();
        encode_key(99, WireType::StartGroup, &mut encoded);
        encode_key(1, WireType::Varint, &mut encoded);
        encode_varint(42, &mut encoded);
        encode_key(100, WireType::StartGroup, &mut encoded);
        encode_key(2, WireType::LengthDelimited, &mut encoded);
        encode_varint(3, &mut encoded);
        encoded.extend_from_slice(b"abc");
        encode_key(100, WireType::EndGroup, &mut encoded);
        encode_key(99, WireType::EndGroup, &mut encoded);

        assert_eq!(
            reapi::BatchUpdateBlobsRequest::decode(encoded.as_slice())
                .expect("Prost should accept balanced unknown groups"),
            request
        );
        inspect_batch_update_wire(&encoded)
            .expect("the admission scanner should accept what Prost accepts");
    }

    #[tokio::test]
    async fn unary_admission_validates_a_fragmented_payload_before_forwarding_the_last_frame() {
        let request = reapi::BatchUpdateBlobsRequest {
            requests: vec![reapi::batch_update_blobs_request::Request::default(); 2],
            ..Default::default()
        }
        .encode_to_vec();
        let mut framed = grpc_message(0, 0);
        framed.truncate(GRPC_MESSAGE_HEADER_BYTES);
        framed[1..].copy_from_slice(&(request.len() as u32).to_be_bytes());
        framed.extend_from_slice(&request);
        let frames = framed
            .chunks(3)
            .map(|chunk| Ok::<_, Infallible>(Bytes::copy_from_slice(chunk)))
            .collect::<Vec<_>>();
        let (memory, admission) =
            grpc_write_admission(8 * 1024 * 1024, CAS_BATCH_UPDATE_DECODE_COPIES);
        let mut body = GrpcWriteAdmissionBody::new(
            axum::body::Body::from_stream(futures_util::stream::iter(frames)),
            admission,
            GrpcWriteShapePolicy::BatchUpdate,
        );

        while let Some(frame) = body.frame().await {
            frame.expect("fragment should pass validation");
        }
        assert_eq!(
            memory.transient_reserved_bytes(),
            request.len() as u64 * CAS_BATCH_UPDATE_DECODE_COPIES
                + 2 * REAPI_BATCH_REQUEST_STRUCTURAL_BYTES
        );
        drop(body);
        assert_eq!(memory.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn unary_admission_rejects_dense_structure_and_releases_its_reservation() {
        let request_count = 20_000;
        let request = reapi::BatchUpdateBlobsRequest {
            requests: vec![reapi::batch_update_blobs_request::Request::default(); request_count],
            ..Default::default()
        }
        .encode_to_vec();
        let mut framed = grpc_message(0, 0);
        framed.truncate(GRPC_MESSAGE_HEADER_BYTES);
        framed[1..].copy_from_slice(&(request.len() as u32).to_be_bytes());
        framed.extend_from_slice(&request);
        let (memory, admission) =
            grpc_write_admission(8 * 1024 * 1024, CAS_BATCH_UPDATE_DECODE_COPIES);
        let mut body = GrpcWriteAdmissionBody::new(
            axum::body::Body::from(framed),
            admission,
            GrpcWriteShapePolicy::BatchUpdate,
        );

        let error = body
            .frame()
            .await
            .expect("request frame")
            .expect_err("dense structure must be rejected before decoding");
        assert_eq!(error.code(), tonic::Code::ResourceExhausted);
        drop(body);
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
            cache.served_full.lock().unwrap().insert(
                namespace.to_owned(),
                ServedFullView {
                    bytes: std::sync::Arc::new(vec![0; 2 * 1024]),
                    removal_seq: 0,
                },
            );
        }

        cache.trim_to(3 * 1024, "test", &metrics);

        assert!(cache.stats().bytes <= 3 * 1024);
    }

    #[test]
    fn digest_key_requires_a_fixed_width_sha256_hash() {
        let valid = reapi::Digest {
            hash: hex::encode([0xabu8; 32]),
            size_bytes: 10,
        };
        assert_eq!(
            digest_key(&valid).expect("a 64-hex hash must be accepted"),
            format!("{}/10", hex::encode([0xabu8; 32]))
        );

        // An unbounded hash is what inflates the manifest key past the backfill
        // index page ceiling; update_action_result has no body to verify it against, so
        // the width check is the only thing keeping the key fixed-size.
        for bad in [
            String::new(),
            "abc".to_string(),
            "z".repeat(64),
            "a".repeat(63),
            "a".repeat(65),
            "a".repeat(16 * 1024),
        ] {
            let digest = reapi::Digest {
                hash: bad,
                size_bytes: 10,
            };
            let status = digest_key(&digest).expect_err("a non-64-hex hash must be rejected");
            assert_eq!(status.code(), tonic::Code::InvalidArgument);
        }
    }

    #[test]
    fn snapshot_cache_keys_round_trip_through_their_parts() {
        for (namespace_id, trunk) in [
            ("ios", None),
            ("ios", Some("main")),
            ("ios", Some("release/4.2.x")),
        ] {
            let key = snapshot_cache_key(namespace_id, trunk);
            assert_eq!(snapshot_cache_key_parts(&key), (namespace_id, trunk));
        }
    }

    #[test]
    fn only_stale_and_still_served_indexes_are_refreshed() {
        let fresh = SNAPSHOT_RECONCILE_INTERVAL / 2;
        let stale = SNAPSHOT_RECONCILE_INTERVAL * 2;
        let served = SNAPSHOT_REFRESH_IDLE_AFTER / 2;
        let idle = SNAPSHOT_REFRESH_IDLE_AFTER * 2;

        assert!(should_refresh_snapshot_index(stale, served));
        assert!(!should_refresh_snapshot_index(fresh, served));
        assert!(!should_refresh_snapshot_index(stale, idle));
        assert!(!should_refresh_snapshot_index(fresh, idle));
    }

    #[tokio::test]
    async fn an_empty_index_answers_only_while_its_namespace_has_not_moved() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let insert = |generation: u64| {
            let mut index = NamespaceSnapshotIndex::new();
            index.reconciled_at = Instant::now();
            index.built_at_generation = generation;
            service
                .snapshot_cache
                .indexes
                .lock()
                .unwrap()
                .insert(snapshot_cache_key("ios", None), index);
            Instant::now()
        };
        let reconciled_at = || {
            service
                .snapshot_cache
                .indexes
                .lock()
                .unwrap()
                .get(&snapshot_cache_key("ios", None))
                .map(|index| index.reconciled_at)
        };

        let stamped = insert(context.state.store.action_cache_generation("ios"));
        service
            .serve_actioncache_snapshot("ios", 0, None)
            .await
            .expect("serve should succeed");
        assert!(reconciled_at().is_some_and(|at| at < stamped));

        let stamped = insert(context.state.store.action_cache_generation("ios") + 1);
        service
            .serve_actioncache_snapshot("ios", 0, None)
            .await
            .expect("serve should succeed");
        assert!(reconciled_at().is_some_and(|at| at > stamped));
    }

    #[test]
    fn a_ref_carrying_unicode_survives_the_metadata() {
        let mut request = Request::new(());
        request.metadata_mut().insert_bin(
            "x-tuist-branch-bin",
            tonic::metadata::MetadataValue::from_bytes("feature/café-au-lait".as_bytes()),
        );
        assert_eq!(
            ref_metadata(&request, "x-tuist-branch", "x-tuist-branch-bin").as_deref(),
            Some("feature/café-au-lait")
        );
    }

    #[test]
    fn an_ascii_only_client_is_still_understood() {
        let mut request = Request::new(());
        request.metadata_mut().insert(
            "x-tuist-branch",
            tonic::metadata::MetadataValue::from_static("main"),
        );
        assert_eq!(
            ref_metadata(&request, "x-tuist-branch", "x-tuist-branch-bin").as_deref(),
            Some("main")
        );
        let empty: Request<()> = Request::new(());
        assert_eq!(
            ref_metadata(&empty, "x-tuist-branch", "x-tuist-branch-bin"),
            None
        );
    }

    #[test]
    fn extracts_request_metadata_for_cache_analytics() {
        let mut request = Request::new(());
        let metadata = reapi::RequestMetadata {
            tool_details: Some(reapi::ToolDetails {
                tool_name: "bazel".into(),
                tool_version: "8.0.0".into(),
            }),
            action_id: "action-1".into(),
            tool_invocation_id: "invocation-1".into(),
            correlated_invocations_id: "".into(),
            action_mnemonic: "SwiftCompile".into(),
            target_id: "//app:app".into(),
            configuration_id: "config-1".into(),
        };
        request.metadata_mut().insert_bin(
            REAPI_REQUEST_METADATA_HEADER,
            tonic::metadata::MetadataValue::from_bytes(&metadata.encode_to_vec()),
        );

        let extracted = reapi_request_metadata(request.metadata());

        assert_eq!(extracted.client_kind, "bazel");
        assert_eq!(extracted.invocation_id, "invocation-1");
        assert_eq!(extracted.action_mnemonic, "SwiftCompile");
        assert_eq!(extracted.target_label, "//app:app");
        assert_eq!(extracted.configuration_id, "config-1");
    }

    #[test]
    fn normalizes_non_bazel_request_metadata() {
        let mut request = Request::new(());
        let metadata = reapi::RequestMetadata {
            tool_details: Some(reapi::ToolDetails {
                tool_name: "xcode-compilation-cache".into(),
                tool_version: "1.0.0".into(),
            }),
            ..Default::default()
        };
        request.metadata_mut().insert_bin(
            REAPI_REQUEST_METADATA_HEADER,
            tonic::metadata::MetadataValue::from_bytes(&metadata.encode_to_vec()),
        );

        assert_eq!(
            reapi_request_metadata(request.metadata()).client_kind,
            "other"
        );
    }

    #[test]
    fn drops_cache_analytics_context_without_bazel_metadata() {
        // Both of these discard every cache observation on the request. The
        // service counts the discard (reapi_cache/skipped_no_bazel_metadata)
        // so it is distinguishable from a node serving no cache traffic.
        let bare = Request::new(());
        assert!(
            reapi_cache_event_context(bare.metadata(), "ios", "fallback").is_none(),
            "a request without RequestMetadata carries no cache attribution"
        );

        let mut other = Request::new(());
        let metadata = reapi::RequestMetadata {
            tool_details: Some(reapi::ToolDetails {
                tool_name: "xcode-compilation-cache".into(),
                tool_version: "1.0.0".into(),
            }),
            ..Default::default()
        };
        other.metadata_mut().insert_bin(
            REAPI_REQUEST_METADATA_HEADER,
            tonic::metadata::MetadataValue::from_bytes(&metadata.encode_to_vec()),
        );
        assert!(
            reapi_cache_event_context(other.metadata(), "ios", "fallback").is_none(),
            "a non-Bazel client carries no cache attribution"
        );
    }

    #[test]
    fn cache_analytics_events_share_batch_request_context() {
        let mut request = Request::new(());
        request.metadata_mut().insert(
            "x-tuist-account-handle",
            tonic::metadata::MetadataValue::from_static("acme"),
        );
        let metadata = reapi::RequestMetadata {
            tool_details: Some(reapi::ToolDetails {
                tool_name: "bazel".into(),
                tool_version: "8.0.0".into(),
            }),
            tool_invocation_id: "invocation-1".into(),
            action_mnemonic: "SwiftCompile".into(),
            target_id: "//app:app".into(),
            configuration_id: "config-1".into(),
            ..Default::default()
        };
        request.metadata_mut().insert_bin(
            REAPI_REQUEST_METADATA_HEADER,
            tonic::metadata::MetadataValue::from_bytes(&metadata.encode_to_vec()),
        );

        let context = reapi_cache_event_context(request.metadata(), "ios", "fallback")
            .expect("Bazel metadata should produce analytics context");
        let first = ReapiCacheAnalyticsEvent {
            event_id: uuid::Uuid::now_v7(),
            context: Arc::clone(&context),
            operation: "cas",
            outcome: "hit",
            action_digest: "digest-a".into(),
            output_path: String::new(),
            size: 1,
            duration_us: 2_000,
            observed_at_ms: 3,
        };
        let second = ReapiCacheAnalyticsEvent {
            event_id: uuid::Uuid::now_v7(),
            context,
            operation: "cas",
            outcome: "miss",
            action_digest: "digest-b".into(),
            output_path: String::new(),
            size: 0,
            duration_us: 4_000,
            observed_at_ms: 5,
        };

        assert!(Arc::ptr_eq(&first.context, &second.context));
        assert_eq!(first.context.account_handle, "acme");
        assert_eq!(first.context.project_handle, "ios");
        assert_eq!(first.context.invocation_id, "invocation-1");
        let legacy = serde_json::to_value(&first).unwrap();
        assert!(legacy.get("output_path").is_none());
        let mut enriched = first.clone();
        enriched.operation = "action_cache";
        enriched.output_path = "bazel-out/bin/main.o".into();
        let enriched = serde_json::to_value(&enriched).unwrap();
        assert_eq!(enriched["output_path"], "bazel-out/bin/main.o");
        assert_eq!(enriched["event_id"], legacy["event_id"]);
    }

    #[test]
    fn action_result_output_identifier_is_bounded_and_optional() {
        let mut result = reapi::ActionResult::default();
        assert_eq!(action_result_output_path(&result), "");
        result.output_files.push(reapi::OutputFile {
            path: "bazel-out/bin/main.o".into(),
            ..Default::default()
        });
        assert_eq!(action_result_output_path(&result), "bazel-out/bin/main.o");
        result.output_files[0].path = "x".repeat(1025);
        assert_eq!(action_result_output_path(&result), "");
        result.output_files.clear();
        result.output_directories.push(reapi::OutputDirectory {
            path: "bazel-out/bin/resources".into(),
            ..Default::default()
        });
        assert_eq!(
            action_result_output_path(&result),
            "bazel-out/bin/resources"
        );
    }

    #[test]
    #[ignore = "performance benchmark run manually"]
    fn reapi_batch_analytics_context_benchmark() {
        const EVENTS_PER_BATCH: usize = 4_096;
        const BATCHES: usize = 32;
        const SAMPLES: usize = 7;

        fn measure_baseline(
            metadata: &tonic::metadata::MetadataMap,
            namespace_id: &str,
            digest: &str,
        ) -> f64 {
            let started_at = Instant::now();
            for _ in 0..BATCHES {
                for _ in 0..EVENTS_PER_BATCH {
                    let attribution = reapi_request_metadata(std::hint::black_box(metadata));
                    assert_eq!(attribution.client_kind, "bazel");
                    std::hint::black_box((
                        usage_tenant_id(metadata, "fallback"),
                        namespace_id.to_owned(),
                        attribution.client_kind,
                        "cas".to_owned(),
                        "hit".to_owned(),
                        digest.to_owned(),
                        attribution.invocation_id,
                        attribution.action_mnemonic,
                        attribution.target_label,
                        attribution.configuration_id,
                    ));
                }
            }
            (EVENTS_PER_BATCH * BATCHES) as f64 / started_at.elapsed().as_secs_f64()
        }

        fn measure_candidate(
            metadata: &tonic::metadata::MetadataMap,
            namespace_id: &str,
            digest: &str,
        ) -> f64 {
            let started_at = Instant::now();
            for _ in 0..BATCHES {
                let context = reapi_cache_event_context(metadata, namespace_id, "fallback")
                    .expect("Bazel metadata should produce analytics context");
                for _ in 0..EVENTS_PER_BATCH {
                    std::hint::black_box(ReapiCacheAnalyticsEvent {
                        event_id: uuid::Uuid::now_v7(),
                        context: Arc::clone(&context),
                        operation: "cas",
                        outcome: "hit",
                        action_digest: digest.to_owned(),
                        output_path: String::new(),
                        size: 4_096,
                        duration_us: 1_000,
                        observed_at_ms: 1,
                    });
                }
            }
            (EVENTS_PER_BATCH * BATCHES) as f64 / started_at.elapsed().as_secs_f64()
        }

        let mut request = Request::new(());
        request.metadata_mut().insert(
            "x-tuist-account-handle",
            tonic::metadata::MetadataValue::from_static("acme"),
        );
        let metadata = reapi::RequestMetadata {
            tool_details: Some(reapi::ToolDetails {
                tool_name: "bazel".into(),
                tool_version: "8.0.0".into(),
            }),
            tool_invocation_id: "550e8400-e29b-41d4-a716-446655440000".into(),
            action_mnemonic: "SwiftCompile".into(),
            target_id: "//Sources/App:App".into(),
            configuration_id: "darwin-arm64-fastbuild".into(),
            ..Default::default()
        };
        request.metadata_mut().insert_bin(
            REAPI_REQUEST_METADATA_HEADER,
            tonic::metadata::MetadataValue::from_bytes(&metadata.encode_to_vec()),
        );
        let digest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        let mut baseline_rates = Vec::with_capacity(SAMPLES - 1);
        let mut candidate_rates = Vec::with_capacity(SAMPLES - 1);
        let mut speedups = Vec::with_capacity(SAMPLES - 1);

        for sample in 0..SAMPLES {
            let baseline_first = sample % 2 == 0;
            let first = if baseline_first {
                measure_baseline(request.metadata(), "ios", digest)
            } else {
                measure_candidate(request.metadata(), "ios", digest)
            };
            let second = if baseline_first {
                measure_candidate(request.metadata(), "ios", digest)
            } else {
                measure_baseline(request.metadata(), "ios", digest)
            };
            if sample > 0 {
                let (baseline, candidate) = if baseline_first {
                    (first, second)
                } else {
                    (second, first)
                };
                baseline_rates.push(baseline);
                candidate_rates.push(candidate);
                speedups.push(candidate / baseline);
            }
        }

        baseline_rates.sort_by(f64::total_cmp);
        candidate_rates.sort_by(f64::total_cmp);
        speedups.sort_by(f64::total_cmp);
        println!(
            "METRIC reapi_batch_analytics_speedup_ratio={:.6}",
            speedups[0]
        );
        println!(
            "METRIC baseline_events_per_second={:.3}",
            baseline_rates[baseline_rates.len() / 2]
        );
        println!(
            "METRIC shared_context_events_per_second={:.3}",
            candidate_rates[candidate_rates.len() / 2]
        );
        println!(
            "METRIC maximum_paired_speedup_ratio={:.6}",
            speedups[speedups.len() - 1]
        );
    }

    #[tokio::test]
    async fn the_refresh_pass_picks_stale_indexes_out_of_the_cache_only() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let insert = |cache_key: String, reconciled_at: Instant| {
            let mut index = NamespaceSnapshotIndex::new();
            index.reconciled_at = reconciled_at;
            service
                .snapshot_cache
                .indexes
                .lock()
                .unwrap()
                .insert(cache_key, index);
        };
        insert(
            snapshot_cache_key("ios", Some("main")),
            Instant::now() - 2 * SNAPSHOT_RECONCILE_INTERVAL,
        );
        insert(snapshot_cache_key("android", None), Instant::now());

        assert_eq!(
            service.refreshable_snapshot_indexes(),
            vec![("ios".to_owned(), Some("main".to_owned()))]
        );
        assert!(
            !service
                .refreshable_snapshot_indexes()
                .iter()
                .any(|(namespace_id, _)| namespace_id == "watch")
        );
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
            .serve_actioncache_snapshot("ios", 0, None)
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
            .serve_actioncache_snapshot("ios", 0, None)
            .await
            .expect("second serve should succeed");
        // The serve itself already dropped both stranded entries from the index;
        // deleting them from the store is the background reconcile's job.
        let exists = |key: &str| {
            store
                .artifact_manifest_exists(ArtifactProducer::Reapi, "ios", key)
                .expect("existence check should succeed")
        };
        for _ in 0..400 {
            if !exists(&stranded_key) {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
        wait_for_snapshot_index(&service, "ios", |index| index.entries.len() == 1).await;
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
    async fn snapshot_serve_drops_entries_whose_blobs_were_removed_after_the_index_was_built() {
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
                    crate::utils::now_ms(),
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
        let blob_manifest = |key: &str| {
            store
                .manifest(&crate::utils::artifact_storage_id(
                    ArtifactProducer::Reapi,
                    "test-tenant",
                    "ios",
                    key,
                ))
                .expect("manifest read should succeed")
                .expect("blob manifest should exist")
        };

        let evicted_blob = [0x11u8; 32];
        let live_blob = [0x22u8; 32];
        let evicted_blob_key = blob_key(&format!("{}/7", hex::encode(evicted_blob)));
        let live_blob_key = blob_key(&format!("{}/7", hex::encode(live_blob)));
        let stranded_hash = [0x44u8; 32];
        let live_hash = [0x66u8; 32];
        write_artifact(store, &uploads, &evicted_blob_key, b"payload").await;
        write_artifact(store, &uploads, &live_blob_key, b"payload").await;
        write_artifact(
            store,
            &uploads,
            &format!("action_cache/{}/10", hex::encode(stranded_hash)),
            &entry_bytes(&[0xAB, 0xCD], evicted_blob),
        )
        .await;
        write_artifact(
            store,
            &uploads,
            &format!("action_cache/{}/10", hex::encode(live_hash)),
            &entry_bytes(&[0xEE, 0xFF], live_blob),
        )
        .await;
        service
            .serve_actioncache_snapshot("ios", 0, None)
            .await
            .expect("first serve should succeed");

        store
            .delete_artifact_metadata(&[blob_manifest(&evicted_blob_key)])
            .expect("blob eviction should succeed");
        // The index was just reconciled, so nothing rebuilds it before this
        // serve: the removal has to be applied on the way out.
        service
            .serve_actioncache_snapshot("ios", 0, None)
            .await
            .expect("second serve should succeed");

        let advertised: Vec<[u8; 32]> = service.snapshot_cache.indexes.lock().unwrap()["ios"]
            .entries
            .keys()
            .copied()
            .collect();
        assert_eq!(
            advertised,
            vec![live_hash],
            "an entry whose blob was removed must not be served again"
        );
        assert!(service.served_full_is_current("ios", "ios"));

        // A cached full view encoded before a removal is not served while the
        // index is out for a rebuild.
        store
            .delete_artifact_metadata(&[blob_manifest(&live_blob_key)])
            .expect("blob eviction should succeed");
        assert!(!service.served_full_is_current("ios", "ios"));
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
    async fn a_served_entry_reports_every_blob_whose_lifetime_must_be_extended() {
        let context = test_context(|_| {}).await;
        let store = &context.state.store;
        let uploads = context.state.config.tmp_dir.join("uploads");
        std::fs::create_dir_all(&uploads).expect("uploads dir should create");

        async fn write_artifact(
            store: &crate::store::Store,
            uploads: &std::path::Path,
            key: &str,
            bytes: &[u8],
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
                    crate::utils::now_ms(),
                )
                .await
                .expect("artifact should persist");
        }
        fn digest(hash: [u8; 32], size_bytes: i64) -> reapi::Digest {
            reapi::Digest {
                hash: hex::encode(hash),
                size_bytes,
            }
        }

        let out_file = [0x11u8; 32];
        let stdout = [0x12u8; 32];
        let stderr = [0x13u8; 32];
        let tree_hash = [0x14u8; 32];
        let leaf = [0x15u8; 32];
        let tree = reapi::Tree {
            root: Some(reapi::Directory {
                files: vec![reapi::FileNode {
                    name: "out".into(),
                    digest: Some(digest(leaf, 7)),
                    ..Default::default()
                }],
                ..Default::default()
            }),
            ..Default::default()
        }
        .encode_to_vec();

        for hash in [out_file, stdout, stderr, leaf] {
            write_artifact(
                store,
                &uploads,
                &blob_key(&format!("{}/7", hex::encode(hash))),
                b"payload",
            )
            .await;
        }
        write_artifact(
            store,
            &uploads,
            &blob_key(&format!("{}/{}", hex::encode(tree_hash), tree.len())),
            &tree,
        )
        .await;

        let serveable = reapi::ActionResult {
            output_files: vec![
                reapi::OutputFile {
                    path: "out".into(),
                    digest: Some(digest(out_file, 7)),
                    ..Default::default()
                },
                reapi::OutputFile {
                    path: "empty".into(),
                    digest: Some(reapi::Digest {
                        hash: EMPTY_BLOB_SHA256.to_string(),
                        size_bytes: 0,
                    }),
                    ..Default::default()
                },
            ],
            stdout_digest: Some(digest(stdout, 7)),
            stderr_digest: Some(digest(stderr, 7)),
            output_directories: vec![reapi::OutputDirectory {
                path: "outdir".into(),
                tree_digest: Some(digest(tree_hash, tree.len() as i64)),
                ..Default::default()
            }],
            ..Default::default()
        };

        let mut budget = MaterializationBudget::new(&context.state);
        let presence =
            first_evicted_output(&context.state, "ios", &serveable, true, true, &mut budget)
                .await
                .expect("presence gate should succeed");

        assert!(
            presence.evicted.is_none(),
            "every referenced blob is present"
        );
        let mut extended = presence.present.clone();
        extended.sort();
        let mut expected = vec![
            blob_key(&format!("{}/7", hex::encode(out_file))),
            blob_key(&format!("{}/7", hex::encode(stdout))),
            blob_key(&format!("{}/7", hex::encode(stderr))),
            blob_key(&format!("{}/{}", hex::encode(tree_hash), tree.len())),
            blob_key(&format!("{}/7", hex::encode(leaf))),
        ];
        expected.sort();
        assert_eq!(
            extended, expected,
            "a replay fetches the streams and the tree's leaves too, so the whole set \
             needs its lifetime extended, while the canonical empty blob, which is \
             never stored, is not part of it"
        );

        // An entry that fails the gate is not served and is usually deleted, so
        // its surviving blobs are not refreshed on its behalf.
        let doomed = reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: "out".into(),
                digest: Some(digest(out_file, 7)),
                ..Default::default()
            }],
            stderr_digest: Some(digest([0x99u8; 32], 7)),
            ..Default::default()
        };
        let presence =
            first_evicted_output(&context.state, "ios", &doomed, true, true, &mut budget)
                .await
                .expect("presence gate should succeed");
        assert_eq!(
            presence.evicted.as_deref(),
            Some(hex::encode([0x99u8; 32]).as_str())
        );
        assert!(
            presence.present.is_empty(),
            "nothing is refreshed for an entry that will not be served"
        );
    }

    #[tokio::test]
    async fn per_key_serve_gates_evicted_streams_and_tree_blobs() {
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
        fn digest(hash: [u8; 32], size_bytes: i64) -> reapi::Digest {
            reapi::Digest {
                hash: hex::encode(hash),
                size_bytes,
            }
        }
        fn tree_bytes(leaf: [u8; 32]) -> Vec<u8> {
            reapi::Tree {
                root: Some(reapi::Directory {
                    files: vec![reapi::FileNode {
                        name: "out".into(),
                        digest: Some(digest(leaf, 7)),
                        ..Default::default()
                    }],
                    ..Default::default()
                }),
                ..Default::default()
            }
            .encode_to_vec()
        }
        fn get_request(action_hash: [u8; 32]) -> Request<reapi::GetActionResultRequest> {
            Request::new(reapi::GetActionResultRequest {
                instance_name: "ios".into(),
                action_digest: Some(digest(action_hash, 10)),
                ..Default::default()
            })
        }

        let now = crate::utils::now_ms();
        let live_blob = [0x11u8; 32];
        let missing_blob = [0x22u8; 32];
        write_artifact(
            store,
            &uploads,
            &blob_key(&format!("{}/7", hex::encode(live_blob))),
            b"payload",
            now,
        )
        .await;

        let live_tree = tree_bytes(live_blob);
        let dead_leaf_tree = tree_bytes(missing_blob);
        let live_tree_hash = [0x33u8; 32];
        let dead_leaf_tree_hash = [0x34u8; 32];
        let missing_tree_hash = [0x35u8; 32];
        write_artifact(
            store,
            &uploads,
            &blob_key(&format!(
                "{}/{}",
                hex::encode(live_tree_hash),
                live_tree.len()
            )),
            &live_tree,
            now,
        )
        .await;
        write_artifact(
            store,
            &uploads,
            &blob_key(&format!(
                "{}/{}",
                hex::encode(dead_leaf_tree_hash),
                dead_leaf_tree.len()
            )),
            &dead_leaf_tree,
            now,
        )
        .await;

        let live_file = || reapi::OutputFile {
            path: hex::encode([0xAB, 0xCD]),
            digest: Some(digest(live_blob, 7)),
            ..Default::default()
        };
        let with_tree = |tree_hash: [u8; 32], tree_len: usize| reapi::OutputDirectory {
            path: "outdir".into(),
            tree_digest: Some(digest(tree_hash, tree_len as i64)),
            ..Default::default()
        };

        let cases = [
            (
                [0x41u8; 32],
                reapi::ActionResult {
                    output_files: vec![live_file()],
                    stdout_digest: Some(digest(missing_blob, 7)),
                    ..Default::default()
                },
                "an evicted stdout blob",
            ),
            (
                [0x42u8; 32],
                reapi::ActionResult {
                    output_files: vec![live_file()],
                    output_directories: vec![with_tree(missing_tree_hash, 5)],
                    ..Default::default()
                },
                "an evicted output-directory tree",
            ),
            (
                [0x43u8; 32],
                reapi::ActionResult {
                    output_files: vec![live_file()],
                    output_directories: vec![with_tree(dead_leaf_tree_hash, dead_leaf_tree.len())],
                    ..Default::default()
                },
                "a present tree that lists an evicted file",
            ),
            (
                [0x46u8; 32],
                reapi::ActionResult {
                    output_files: vec![live_file()],
                    stderr_digest: Some(digest(missing_blob, 7)),
                    ..Default::default()
                },
                "an evicted stderr blob",
            ),
        ];
        for (action, result, label) in &cases {
            write_artifact(
                store,
                &uploads,
                &format!("action_cache/{}/10", hex::encode(action)),
                &result.encode_to_vec(),
                now,
            )
            .await;
            let status = service
                .get_action_result(get_request(*action))
                .await
                .expect_err(label);
            assert_eq!(
                status.code(),
                tonic::Code::NotFound,
                "{label} must gate the serve"
            );
        }

        let all_live_action = [0x44u8; 32];
        let all_live = reapi::ActionResult {
            output_files: vec![live_file()],
            stdout_digest: Some(digest(live_blob, 7)),
            output_directories: vec![with_tree(live_tree_hash, live_tree.len())],
            ..Default::default()
        };
        write_artifact(
            store,
            &uploads,
            &format!("action_cache/{}/10", hex::encode(all_live_action)),
            &all_live.encode_to_vec(),
            now,
        )
        .await;
        service
            .get_action_result(get_request(all_live_action))
            .await
            .expect("an entry whose stream and tree blobs are all present serves");

        let empty_digest = reapi::Digest {
            hash: EMPTY_BLOB_SHA256.to_string(),
            size_bytes: 0,
        };
        let empty_leaf_tree = reapi::Tree {
            root: Some(reapi::Directory {
                files: vec![reapi::FileNode {
                    name: "empty".into(),
                    digest: Some(empty_digest.clone()),
                    ..Default::default()
                }],
                ..Default::default()
            }),
            ..Default::default()
        }
        .encode_to_vec();
        let empty_leaf_tree_hash = [0x37u8; 32];
        write_artifact(
            store,
            &uploads,
            &blob_key(&format!(
                "{}/{}",
                hex::encode(empty_leaf_tree_hash),
                empty_leaf_tree.len()
            )),
            &empty_leaf_tree,
            now,
        )
        .await;
        let empty_ref_action = [0x45u8; 32];
        let empty_ref = reapi::ActionResult {
            output_files: vec![live_file()],
            stdout_digest: Some(empty_digest),
            output_directories: vec![with_tree(empty_leaf_tree_hash, empty_leaf_tree.len())],
            ..Default::default()
        };
        write_artifact(
            store,
            &uploads,
            &format!("action_cache/{}/10", hex::encode(empty_ref_action)),
            &empty_ref.encode_to_vec(),
            now,
        )
        .await;
        service
            .get_action_result(get_request(empty_ref_action))
            .await
            .expect("an entry referencing the empty blob for stdout and a tree leaf still serves");
    }

    #[tokio::test]
    async fn the_empty_blob_is_served_without_being_stored() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let empty = reapi::Digest {
            hash: EMPTY_BLOB_SHA256.to_string(),
            size_bytes: 0,
        };
        let batch = service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: "ios".into(),
                digests: vec![empty.clone()],
                acceptable_compressors: vec![reapi::compressor::Value::Zstd as i32],
                digest_function: 0,
            }))
            .await
            .expect("batch_read_blobs should succeed")
            .into_inner();
        assert_eq!(batch.responses.len(), 1);
        let response = &batch.responses[0];
        assert_eq!(response.status.as_ref().map(|status| status.code), Some(0));
        assert_eq!(response.digest.as_ref(), Some(&empty));
        assert!(response.data.is_empty());

        let mut stream = service
            .read(Request::new(bytestream::ReadRequest {
                resource_name: format!("ios/blobs/{EMPTY_BLOB_SHA256}/0"),
                read_offset: 0,
                read_limit: 0,
            }))
            .await
            .expect("reading the empty blob should succeed")
            .into_inner();
        let mut data = Vec::new();
        while let Some(response) = stream.next().await {
            data.extend(response.expect("stream response").data);
        }
        assert!(data.is_empty());
    }

    #[tokio::test]
    async fn find_missing_blobs_treats_the_empty_blob_as_present() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let empty = reapi::Digest {
            hash: EMPTY_BLOB_SHA256.to_string(),
            size_bytes: 0,
        };
        let absent = reapi::Digest {
            hash: hex::encode([0x77u8; 32]),
            size_bytes: 5,
        };
        let missing = service
            .find_missing_blobs(Request::new(reapi::FindMissingBlobsRequest {
                instance_name: "ios".into(),
                blob_digests: vec![empty, absent.clone()],
                digest_function: 0,
            }))
            .await
            .expect("find_missing_blobs should succeed")
            .into_inner()
            .missing_blob_digests;
        assert_eq!(
            missing,
            vec![absent],
            "the empty blob is always present; only the genuinely absent blob is reported"
        );
    }

    #[tokio::test]
    async fn splice_keeps_a_composite_blob_recoverable_without_materializing_it_in_the_store() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let first = vec![0x11; 1024 * 1024];
        let second = vec![0x22; 1024 * 1024];
        let digest = |bytes: &[u8]| reapi::Digest {
            hash: hex::encode(Sha256::digest(bytes)),
            size_bytes: bytes.len() as i64,
        };
        let first_digest = digest(&first);
        let second_digest = digest(&second);
        let mut blob = first.clone();
        blob.extend_from_slice(&second);
        let blob_digest = digest(&blob);
        let recovery_watermark_ms = 1_000;
        let uploads = context.state.config.tmp_dir.join("splice-recovery");
        std::fs::create_dir_all(&uploads).expect("uploads directory should be created");
        for (name, chunk_digest, bytes) in [
            ("first", &first_digest, first.as_slice()),
            ("second", &second_digest, second.as_slice()),
        ] {
            let path = uploads.join(name);
            std::fs::write(&path, bytes).expect("chunk should be staged");
            context
                .state
                .store
                .apply_replicated_artifact_from_path(
                    ArtifactProducer::Reapi,
                    "ios",
                    &blob_key(&digest_key(chunk_digest).unwrap()),
                    "application/octet-stream",
                    &path,
                    recovery_watermark_ms,
                )
                .await
                .expect("old chunk should persist");
        }
        let recipe_created_not_before_ms = crate::utils::now_ms();

        let mut splice_request = Request::new(reapi::SpliceBlobRequest {
            instance_name: "ios".into(),
            blob_digest: Some(blob_digest.clone()),
            chunk_digests: vec![first_digest.clone(), second_digest.clone()],
            digest_function: 0,
            chunking_function: reapi::chunking_function::Value::FastCdc2020 as i32,
        });
        splice_request.extensions_mut().insert(
            GrpcWriteAdmission::new(
                &context.state.memory,
                CAS_SPLICE_DECODE_COPIES,
                context.state.metrics.grpc_write_admission_metrics(),
            )
            .expect("splice request should be admitted"),
        );
        let spliced = service
            .splice_blob(splice_request)
            .await
            .expect("splice should succeed")
            .into_inner();
        assert_eq!(spliced.blob_digest, Some(blob_digest.clone()));
        let recipe_manifest = context
            .state
            .store
            .manifest_for_key(
                ArtifactProducer::Reapi,
                "ios",
                &recipe_key(&digest_key(&blob_digest).unwrap()),
            )
            .unwrap()
            .expect("recipe manifest should exist");
        assert!(
            recipe_manifest.version_ms >= recipe_created_not_before_ms,
            "the recipe must retain its creation time"
        );
        assert!(
            recipe_manifest.version_ms > recovery_watermark_ms,
            "a returning peer must discover the recipe above its completed-pass watermark"
        );
        for chunk_digest in [&first_digest, &second_digest] {
            let chunk_manifest = context
                .state
                .store
                .manifest_for_key(
                    ArtifactProducer::Reapi,
                    "ios",
                    &blob_key(&digest_key(chunk_digest).unwrap()),
                )
                .unwrap()
                .expect("chunk manifest should exist");
            assert_eq!(chunk_manifest.version_ms, recovery_watermark_ms);
        }
        assert_eq!(
            crate::store::backfill_record_kind(&recipe_manifest),
            crate::utils::BackfillRecordKind::SegmentArtifact,
            "capacity-completed backfill must skip the recipe with its chunks"
        );
        assert!(
            !context
                .state
                .store
                .artifact_exists(
                    ArtifactProducer::Reapi,
                    "ios",
                    &blob_key(&digest_key(&blob_digest).unwrap()),
                )
                .await
                .unwrap(),
            "the logical blob must remain a recipe instead of a duplicated materialization"
        );

        let split = service
            .split_blob(Request::new(reapi::SplitBlobRequest {
                instance_name: "ios".into(),
                blob_digest: Some(blob_digest.clone()),
                digest_function: 0,
                chunking_function: reapi::chunking_function::Value::FastCdc2020 as i32,
            }))
            .await
            .expect("split should return the stored recipe")
            .into_inner();
        assert_eq!(split.chunk_digests, vec![first_digest, second_digest]);

        let missing = service
            .find_missing_blobs(Request::new(reapi::FindMissingBlobsRequest {
                instance_name: "ios".into(),
                blob_digests: vec![blob_digest.clone()],
                digest_function: 0,
            }))
            .await
            .expect("composite presence should resolve")
            .into_inner();
        assert!(missing.missing_blob_digests.is_empty());

        let mut stream = service
            .read(Request::new(bytestream::ReadRequest {
                resource_name: format!("ios/blobs/{}/{}", blob_digest.hash, blob_digest.size_bytes),
                read_offset: (1024 * 1024 - 11) as i64,
                read_limit: 22,
            }))
            .await
            .expect("range read should succeed")
            .into_inner();
        let mut range = Vec::new();
        while let Some(response) = stream.next().await {
            range.extend(response.expect("stream response").data);
        }
        assert_eq!(range, [vec![0x11; 11], vec![0x22; 11]].concat());

        let batch = service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: "ios".into(),
                digests: vec![blob_digest],
                acceptable_compressors: Vec::new(),
                digest_function: 0,
            }))
            .await
            .expect("batch read should reconstruct the composite")
            .into_inner();
        assert_eq!(batch.responses.len(), 1);
        assert_eq!(batch.responses[0].status.as_ref().unwrap().code, 0);
        assert_eq!(batch.responses[0].data, blob);
    }

    #[tokio::test]
    async fn find_missing_blobs_batches_match_the_per_digest_answer() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let store = &context.state.store;
        let digest = |bytes: &[u8]| reapi::Digest {
            hash: hex::encode(Sha256::digest(bytes)),
            size_bytes: bytes.len() as i64,
        };
        let mut version = 0;
        let mut store_blob = async |bytes: &[u8]| {
            version += 1;
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    "ios",
                    &blob_key(&digest_key(&digest(bytes)).unwrap()),
                    "application/octet-stream",
                    bytes,
                    version,
                )
                .await
                .expect("blob should be stored");
        };
        let present = b"present".to_vec();
        store_blob(&present).await;

        // A composite whose chunks are all stored, and one missing a chunk.
        let mut composites = Vec::new();
        for (fill, store_last_chunk) in [(0x31, true), (0x51, false)] {
            let first = vec![fill; FAST_CDC_AVERAGE_CHUNK_BYTES as usize];
            let last = vec![fill + 1; 17];
            store_blob(&first).await;
            if store_last_chunk {
                store_blob(&last).await;
            }
            let composite = digest(&[first.clone(), last.clone()].concat());
            let recipe = ChunkedBlobRecipe::new(
                &composite,
                vec![digest(&first), digest(&last)],
                reapi::chunking_function::Value::FastCdc2020 as i32,
            )
            .expect("recipe should be valid");
            store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    "ios",
                    &recipe_key(&digest_key(&composite).unwrap()),
                    "application/x-protobuf",
                    &recipe.encode(),
                    100 + composites.len() as u64,
                    None,
                    None,
                )
                .await
                .expect("recipe should be stored");
            composites.push(composite);
        }
        let [complete, incomplete] = <[reapi::Digest; 2]>::try_from(composites).unwrap();
        let empty = reapi::Digest {
            hash: EMPTY_BLOB_SHA256.to_string(),
            size_bytes: 0,
        };
        let absent = |index: usize| digest(format!("absent-{index}").as_bytes());

        // Span several store passes, with duplicates on both sides of a
        // batch boundary.
        let mut request = vec![
            empty.clone(),
            digest(&present),
            absent(0),
            complete.clone(),
            incomplete.clone(),
            absent(0),
            digest(&present),
        ];
        for index in 1..2 * FIND_MISSING_BATCH_DIGESTS {
            request.push(if index % 7 == 0 {
                digest(&present)
            } else {
                absent(index)
            });
        }
        request.extend([complete.clone(), incomplete.clone(), empty, absent(0)]);

        let mut expected = Vec::new();
        let mut presence_budget = PresenceBudget::for_request();
        for blob in &request {
            if is_empty_blob(blob) {
                continue;
            }
            if presence_keys(
                &context.state,
                "ios",
                blob,
                RefreshTrigger::FindMissing,
                false,
                &mut presence_budget,
            )
            .await
            .expect("per-digest presence should succeed")
            .is_none()
            {
                expected.push(blob.clone());
            }
        }
        assert!(expected.contains(&incomplete) && !expected.contains(&complete));
        assert_eq!(
            expected.iter().filter(|blob| **blob == absent(0)).count(),
            3,
            "duplicates are reported once per occurrence"
        );

        let missing = service
            .find_missing_blobs(Request::new(reapi::FindMissingBlobsRequest {
                instance_name: "ios".into(),
                blob_digests: request,
                digest_function: 0,
            }))
            .await
            .expect("find_missing_blobs should succeed")
            .into_inner()
            .missing_blob_digests;
        assert_eq!(missing, expected);
    }

    #[tokio::test]
    async fn find_missing_blobs_extends_aged_direct_and_chunk_lifetimes() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let store = &context.state.store;
        let digest = |bytes: &[u8]| reapi::Digest {
            hash: hex::encode(Sha256::digest(bytes)),
            size_bytes: bytes.len() as i64,
        };
        let artifact_id = |key: &str| {
            store
                .manifest_for_key(ArtifactProducer::Reapi, "ios", key)
                .unwrap()
                .expect("manifest should exist")
                .artifact_id
        };
        let direct = b"direct".to_vec();
        let first = vec![0x61; FAST_CDC_AVERAGE_CHUNK_BYTES as usize];
        let last = vec![0x62; 17];
        for (version, bytes) in [&direct, &first, &last].into_iter().enumerate() {
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    "ios",
                    &blob_key(&digest_key(&digest(bytes)).unwrap()),
                    "application/octet-stream",
                    bytes,
                    version as u64 + 1,
                )
                .await
                .expect("blob should be stored");
        }
        let composite = digest(&[first.clone(), last.clone()].concat());
        let recipe = ChunkedBlobRecipe::new(
            &composite,
            vec![digest(&first), digest(&last)],
            reapi::chunking_function::Value::FastCdc2020 as i32,
        )
        .expect("recipe should be valid");
        store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                &recipe_key(&digest_key(&composite).unwrap()),
                "application/x-protobuf",
                &recipe.encode(),
                10,
                None,
                None,
            )
            .await
            .expect("recipe should be stored");
        store.age_every_segment_for_test();
        assert!(store.segment_ring_is_aging());
        let absent = digest(b"absent");

        let missing = service
            .find_missing_blobs(Request::new(reapi::FindMissingBlobsRequest {
                instance_name: "ios".into(),
                blob_digests: vec![digest(&direct), composite, absent.clone()],
                digest_function: 0,
            }))
            .await
            .expect("find_missing_blobs should succeed")
            .into_inner()
            .missing_blob_digests;

        assert_eq!(missing, vec![absent]);
        for bytes in [&direct, &first, &last] {
            let key = blob_key(&digest_key(&digest(bytes)).unwrap());
            assert_eq!(
                store.pending_promotion_for_test(&artifact_id(&key)),
                Some(RefreshTrigger::FindMissing),
                "a blob reported present from an Old segment is queued for copy-forward"
            );
        }
    }

    #[tokio::test]
    async fn get_action_result_presence_lookup_leaves_aged_lifetimes_alone() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let store = &context.state.store;
        let blob = b"payload".to_vec();
        let blob_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&blob)),
            size_bytes: blob.len() as i64,
        };
        let leaf_key = blob_key(&digest_key(&blob_digest).unwrap());
        let tree = reapi::Tree {
            root: Some(reapi::Directory {
                files: vec![reapi::FileNode {
                    name: "leaf".into(),
                    digest: Some(blob_digest.clone()),
                    ..Default::default()
                }],
                ..Default::default()
            }),
            ..Default::default()
        }
        .encode_to_vec();
        let tree_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&tree)),
            size_bytes: tree.len() as i64,
        };
        let tree_key = blob_key(&digest_key(&tree_digest).unwrap());
        let action_hash = hex::encode([0x44u8; 32]);
        let action_key = action_cache_key(&format!("{action_hash}/10"));
        let entry = reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: "output".into(),
                digest: Some(blob_digest),
                ..Default::default()
            }],
            output_directories: vec![reapi::OutputDirectory {
                path: "outputs".into(),
                tree_digest: Some(tree_digest),
                ..Default::default()
            }],
            ..Default::default()
        }
        .encode_to_vec();
        for (version, (key, bytes)) in [
            (&leaf_key, &blob),
            (&tree_key, &tree),
            (&action_key, &entry),
        ]
        .into_iter()
        .enumerate()
        {
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    "application/octet-stream",
                    bytes,
                    version as u64 + 1,
                )
                .await
                .expect("artifact should be stored");
        }
        store.age_every_segment_for_test();
        let artifact_id = |key: &str| {
            store
                .manifest_for_key(ArtifactProducer::Reapi, "ios", key)
                .unwrap()
                .expect("manifest should exist")
                .artifact_id
        };
        let request = |presence: bool| {
            let mut request = Request::new(reapi::GetActionResultRequest {
                instance_name: "ios".into(),
                action_digest: Some(reapi::Digest {
                    hash: action_hash.clone(),
                    size_bytes: 10,
                }),
                ..Default::default()
            });
            if presence {
                request
                    .metadata_mut()
                    .insert(LOOKUP_HEADER, PRESENCE_LOOKUP.parse().unwrap());
            }
            request
        };

        service
            .get_action_result(request(true))
            .await
            .expect("a presence lookup serves a present entry");

        for key in [&action_key, &leaf_key, &tree_key] {
            assert_eq!(
                store.pending_promotion_for_test(&artifact_id(key)),
                None,
                "a presence lookup must not extend {key}"
            );
        }

        service
            .get_action_result(request(false))
            .await
            .expect("a read serves a present entry");

        assert_eq!(
            store.pending_promotion_for_test(&artifact_id(&action_key)),
            Some(RefreshTrigger::Serve)
        );
        for key in [&leaf_key, &tree_key] {
            assert_eq!(
                store.pending_promotion_for_test(&artifact_id(key)),
                Some(RefreshTrigger::ActionCache)
            );
        }
    }

    #[tokio::test]
    async fn find_missing_blobs_rejects_an_invalid_digest_in_any_batch() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let mut blob_digests: Vec<reapi::Digest> = (0..FIND_MISSING_BATCH_DIGESTS + 1)
            .map(|index| reapi::Digest {
                hash: hex::encode(Sha256::digest(index.to_le_bytes())),
                size_bytes: 8,
            })
            .collect();
        blob_digests.push(reapi::Digest {
            hash: "not-a-sha256".into(),
            size_bytes: 8,
        });

        let status = service
            .find_missing_blobs(Request::new(reapi::FindMissingBlobsRequest {
                instance_name: "ios".into(),
                blob_digests,
                digest_function: 0,
            }))
            .await
            .expect_err("an invalid digest must fail the request");
        assert_eq!(status.code(), tonic::Code::InvalidArgument);
    }

    #[tokio::test]
    async fn replicated_recipe_waits_for_every_chunk() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let first = vec![0x31; FAST_CDC_AVERAGE_CHUNK_BYTES as usize];
        let second = vec![0x42; 17];
        let digest = |bytes: &[u8]| reapi::Digest {
            hash: hex::encode(Sha256::digest(bytes)),
            size_bytes: bytes.len() as i64,
        };
        let first_digest = digest(&first);
        let second_digest = digest(&second);
        let mut blob = first.clone();
        blob.extend_from_slice(&second);
        let blob_digest = digest(&blob);
        let recipe = ChunkedBlobRecipe::new(
            &blob_digest,
            vec![first_digest.clone(), second_digest.clone()],
            reapi::chunking_function::Value::FastCdc2020 as i32,
        )
        .expect("recipe should be valid");
        let recipe_key =
            recipe_key(&digest_key(&blob_digest).expect("blob digest should be valid"));

        context
            .state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                &recipe_key,
                "application/x-protobuf",
                &recipe.encode(),
                1,
                None,
                None,
            )
            .await
            .expect("recipe should replicate before its chunks");

        let missing = |digest: reapi::Digest| {
            service.find_missing_blobs(Request::new(reapi::FindMissingBlobsRequest {
                instance_name: "ios".into(),
                blob_digests: vec![digest],
                digest_function: 0,
            }))
        };
        assert_eq!(
            missing(blob_digest.clone())
                .await
                .expect("presence check should succeed")
                .into_inner()
                .missing_blob_digests,
            vec![blob_digest.clone()],
            "a recipe must not make a partially replicated blob visible"
        );

        context
            .state
            .store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                &blob_key(&digest_key(&first_digest).expect("first digest should be valid")),
                "application/octet-stream",
                &first,
                2,
            )
            .await
            .expect("first chunk should replicate");
        assert_eq!(
            missing(blob_digest.clone())
                .await
                .expect("presence check should succeed")
                .into_inner()
                .missing_blob_digests,
            vec![blob_digest.clone()],
            "every chunk is required before the logical blob is visible"
        );

        context
            .state
            .store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                &blob_key(&digest_key(&second_digest).expect("second digest should be valid")),
                "application/octet-stream",
                &second,
                3,
            )
            .await
            .expect("second chunk should replicate");
        assert!(
            missing(blob_digest.clone())
                .await
                .expect("presence check should succeed")
                .into_inner()
                .missing_blob_digests
                .is_empty(),
            "the logical blob becomes visible after its final chunk arrives"
        );

        let split = service
            .split_blob(Request::new(reapi::SplitBlobRequest {
                instance_name: "ios".into(),
                blob_digest: Some(blob_digest.clone()),
                digest_function: 0,
                chunking_function: reapi::chunking_function::Value::FastCdc2020 as i32,
            }))
            .await
            .expect("a recipe must be readable once every chunk has arrived")
            .into_inner();
        assert_eq!(split.chunk_digests, vec![first_digest, second_digest]);
    }

    #[tokio::test]
    async fn splice_rejects_mismatched_content_without_persisting_a_recipe() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let chunk = b"hello";
        let chunk_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(chunk)),
            size_bytes: chunk.len() as i64,
        };
        let declared_blob = reapi::Digest {
            hash: hex::encode(Sha256::digest(b"world")),
            size_bytes: chunk.len() as i64,
        };
        persist_cas_blob(&context.state, "ios", &chunk_digest, chunk)
            .await
            .expect("chunk should persist");

        let mut request = Request::new(reapi::SpliceBlobRequest {
            instance_name: "ios".into(),
            blob_digest: Some(declared_blob.clone()),
            chunk_digests: vec![chunk_digest],
            digest_function: 0,
            chunking_function: reapi::chunking_function::Value::FastCdc2020 as i32,
        });
        request.extensions_mut().insert(
            GrpcWriteAdmission::new(
                &context.state.memory,
                CAS_SPLICE_DECODE_COPIES,
                context.state.metrics.grpc_write_admission_metrics(),
            )
            .expect("splice request should be admitted"),
        );
        let error = service
            .splice_blob(request)
            .await
            .expect_err("mismatched content must be rejected");
        assert_eq!(error.code(), tonic::Code::InvalidArgument);

        let split_error = service
            .split_blob(Request::new(reapi::SplitBlobRequest {
                instance_name: "ios".into(),
                blob_digest: Some(declared_blob),
                digest_function: 0,
                chunking_function: reapi::chunking_function::Value::FastCdc2020 as i32,
            }))
            .await
            .expect_err("a failed verification must not publish a recipe");
        assert_eq!(split_error.code(), tonic::Code::NotFound);
    }

    #[tokio::test]
    async fn snapshot_reconcile_rejects_a_decode_larger_than_its_working_budget() {
        let context = test_context(|_| {}).await;
        let blob_hash = [0x31u8; 32];
        let blob_key_name = blob_key(&format!("{}/7", hex::encode(blob_hash)));
        context
            .state
            .store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                &blob_key_name,
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("blob should persist");
        let action_hash = [0x42u8; 32];
        let action_key = format!("action_cache/{}/10", hex::encode(action_hash));
        let action_result = reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: hex::encode([0xAAu8]),
                digest: Some(reapi::Digest {
                    hash: hex::encode(blob_hash),
                    size_bytes: 7,
                }),
                ..Default::default()
            }],
            ..Default::default()
        }
        .encode_to_vec();
        context
            .state
            .store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "ios",
                &action_key,
                "application/x-protobuf",
                &action_result,
            )
            .await
            .expect("action result should persist");

        let rejected = match reconcile_snapshot_index(
            &context.state,
            "ios",
            None,
            NamespaceSnapshotIndex::new(),
            SnapshotBuildBudgets {
                metadata_bytes: 1024 * 1024,
                index_bytes: 1024 * 1024,
                encoded_bytes: 1,
                decoded_bytes: 1,
            },
        )
        .await
        {
            Ok(index) => index,
            Err((_, error)) => panic!("budget rejection should not fail the reconcile: {error}"),
        };
        assert!(rejected.entries.is_empty());

        let admitted = match reconcile_snapshot_index(
            &context.state,
            "ios",
            None,
            NamespaceSnapshotIndex::new(),
            SnapshotBuildBudgets {
                metadata_bytes: 1024 * 1024,
                index_bytes: 1024 * 1024,
                encoded_bytes: 1024 * 1024,
                decoded_bytes: 1024 * 1024,
            },
        )
        .await
        {
            Ok(index) => index,
            Err((_, error)) => {
                panic!("the same entry should load with enough working memory: {error}")
            }
        };
        assert!(admitted.entries.contains_key(&action_hash));
    }

    #[tokio::test]
    async fn snapshot_presence_gate_runs_even_when_the_load_is_interrupted_by_pressure() {
        let context = test_context(|_| {}).await;
        let blob_hash_a = [0x11u8; 32];
        let blob_key_a = blob_key(&format!("{}/7", hex::encode(blob_hash_a)));
        let action_hash_a = [0x42u8; 32];
        let action_key_a = format!("action_cache/{}/10", hex::encode(action_hash_a));
        let action_result_a = reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: hex::encode([0xAA]),
                digest: Some(reapi::Digest {
                    hash: hex::encode(blob_hash_a),
                    size_bytes: 7,
                }),
                ..Default::default()
            }],
            ..Default::default()
        }
        .encode_to_vec();
        for (key, bytes) in [
            (&blob_key_a, b"payload".to_vec()),
            (&action_key_a, action_result_a),
        ] {
            context
                .state
                .store
                .persist_inline_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    if bytes == b"payload" {
                        "application/octet-stream"
                    } else {
                        "application/x-protobuf"
                    },
                    &bytes,
                )
                .await
                .expect("artifact should persist");
        }

        let budgets = SnapshotBuildBudgets {
            metadata_bytes: 1024 * 1024,
            index_bytes: 1024 * 1024,
            encoded_bytes: 1024 * 1024,
            decoded_bytes: 1024 * 1024,
        };
        let index = match reconcile_snapshot_index(
            &context.state,
            "ios",
            None,
            NamespaceSnapshotIndex::new(),
            budgets,
        )
        .await
        {
            Ok(index) => index,
            Err((_, error)) => panic!("initial reconcile should load entry a: {error}"),
        };
        assert!(
            index.entries.contains_key(&action_hash_a),
            "entry a loads while its blob exists"
        );

        // Evict blob a (CAS eviction outlives the action-cache entry), pin the
        // node to critical pressure, and publish a fresh entry so the reconcile
        // has a load to do. The old code returned early from the load on
        // pressure before reaching the presence gate, so entry a stayed
        // advertised and the snapshot served a missing object.
        let blob_manifest_a = context
            .state
            .store
            .manifest_for_key(ArtifactProducer::Reapi, "ios", &blob_key_a)
            .expect("manifest lookup")
            .expect("blob a present");
        context
            .state
            .store
            .delete_artifact_metadata(&[blob_manifest_a])
            .expect("blob a eviction");
        context
            .state
            .memory
            .observe(context.state.config.memory_hard_limit_bytes);

        let blob_hash_b = [0x22u8; 32];
        let blob_key_b = blob_key(&format!("{}/8", hex::encode(blob_hash_b)));
        let action_hash_b = [0x43u8; 32];
        let action_key_b = format!("action_cache/{}/11", hex::encode(action_hash_b));
        let action_result_b = reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: hex::encode([0xBB]),
                digest: Some(reapi::Digest {
                    hash: hex::encode(blob_hash_b),
                    size_bytes: 8,
                }),
                ..Default::default()
            }],
            ..Default::default()
        }
        .encode_to_vec();
        for (key, bytes) in [
            (&blob_key_b, b"payload-b".to_vec()),
            (&action_key_b, action_result_b),
        ] {
            context
                .state
                .store
                .persist_inline_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    if bytes == b"payload-b" {
                        "application/octet-stream"
                    } else {
                        "application/x-protobuf"
                    },
                    &bytes,
                )
                .await
                .expect("artifact should persist");
        }

        let index =
            match reconcile_snapshot_index(&context.state, "ios", None, index, budgets).await {
                Ok(index) => index,
                // An interrupted reconcile now still presence-gates: it breaks
                // out of the load, not out of the gate.
                Err((_, error)) => {
                    panic!("pressure-interrupted reconcile should still gate: {error}")
                }
            };
        assert!(
            !index.entries.contains_key(&action_hash_a),
            "the evicted-blob entry is gated out despite the pressure interruption"
        );
        assert!(
            index.entries.contains_key(&action_hash_b),
            "the fresh entry loaded before the interruption is retained"
        );
    }

    #[tokio::test]
    async fn run_index_build_presence_gates_under_sustained_memory_pressure() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let blob_hash = [0x11u8; 32];
        let blob_key_name = blob_key(&format!("{}/7", hex::encode(blob_hash)));
        let action_hash = [0x42u8; 32];
        let action_key = format!("action_cache/{}/10", hex::encode(action_hash));
        let action_result = reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: hex::encode([0xAA]),
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
            (&action_key, action_result),
        ] {
            context
                .state
                .store
                .persist_inline_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    "ios",
                    key,
                    if bytes == b"payload" {
                        "application/octet-stream"
                    } else {
                        "application/x-protobuf"
                    },
                    &bytes,
                )
                .await
                .expect("artifact should persist");
        }

        // Build the index under normal pressure so the entry is cached.
        let _ = service
            .serve_actioncache_snapshot("ios", 0, None)
            .await
            .expect("initial serve builds the index");
        assert!(
            service
                .snapshot_cache
                .indexes
                .lock()
                .unwrap()
                .get("ios")
                .unwrap()
                .entries
                .contains_key(&action_hash),
            "the entry is cached before eviction"
        );

        // Evict the blob, then pin the node to critical pressure. Under
        // sustained pressure the full reconcile (scan + load) is denied as
        // background work; without the gate-only pass the cached index would
        // freeze stale and keep advertising the evicted blob.
        let blob_manifest = context
            .state
            .store
            .manifest_for_key(ArtifactProducer::Reapi, "ios", &blob_key_name)
            .expect("manifest lookup")
            .expect("blob present");
        context
            .state
            .store
            .delete_artifact_metadata(&[blob_manifest])
            .expect("blob eviction");
        context
            .state
            .memory
            .observe(context.state.config.memory_hard_limit_bytes);

        ReapiService::run_index_build(
            service.snapshot_cache.clone(),
            context.state.clone(),
            "ios".to_owned(),
            None,
            "ios".to_owned(),
            IndexBuildTrigger::Serve,
        )
        .await
        .expect("pressure build gates the index");

        let entry_still_advertised = service
            .snapshot_cache
            .indexes
            .lock()
            .unwrap()
            .get("ios")
            .expect("the gated index is reinserted, not discarded")
            .entries
            .contains_key(&action_hash);
        assert!(
            !entry_still_advertised,
            "the evicted-blob entry is gated out under sustained pressure"
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
        let mut serve = Box::pin(service.serve_actioncache_snapshot("ios", 0, None));
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
            .serve_actioncache_snapshot("ios", 0, None)
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
            .serve_actioncache_snapshot("ios", 0, None)
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
            .serve_actioncache_snapshot("ios", 0, None)
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

        // Exhaust the transient budget: the old try-acquire declined the build here —
        // which, under the per-key load a stale snapshot causes, parked the
        // index stale indefinitely. The build must wait instead.
        let limit = context.state.memory.reapi_materialization_limit_bytes();
        let first_hog = context
            .state
            .memory
            .try_acquire_reapi_materialization(limit)
            .expect("the per-request limit should be acquirable when idle");
        let second_hog = context
            .state
            .memory
            .try_acquire_reapi_materialization(limit)
            .expect("the remaining transient budget should be acquirable when idle");
        let serve = tokio::spawn({
            let service = service.clone();
            async move { service.serve_actioncache_snapshot("ios", 0, None).await }
        });
        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
        assert!(
            !serve.is_finished(),
            "the build waits for headroom rather than declining"
        );
        drop((first_hog, second_hog));
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
            .serve_actioncache_snapshot("ios", 0, None)
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
        // the transient budget so the serve's kicked rebuild cannot reinsert it before the
        // assertion.
        service.snapshot_cache.indexes.lock().unwrap().remove("ios");
        let limit = context.state.memory.reapi_materialization_limit_bytes();
        let _hog = context
            .state
            .memory
            .try_acquire_reapi_materialization(limit.saturating_sub(first.len()))
            .expect("the requested transient bytes should be acquirable when idle");

        // A full serve now finds no index but returns the cached full view
        // immediately, rather than shedding a cold client to UNAVAILABLE while
        // the rebuild runs. Before `served_full`, this fell to the cold path.
        let stale = tokio::time::timeout(
            std::time::Duration::from_secs(2),
            service.serve_actioncache_snapshot("ios", 0, None),
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
        let limit = context.state.memory.reapi_materialization_limit_bytes();
        let first_hog = context
            .state
            .memory
            .try_acquire_reapi_materialization(limit)
            .expect("the per-request limit should be acquirable when idle");
        let second_hog = context
            .state
            .memory
            .try_acquire_reapi_materialization(limit)
            .expect("the remaining transient budget should be acquirable when idle");
        let status = service
            .serve_actioncache_snapshot("ios", 0, None)
            .await
            .expect_err("cold serve should shed while the build is stuck");
        assert_eq!(status.code(), tonic::Code::Unavailable);
        // Once the pool frees the same build completes in the background and
        // the next fetch is served from the index it produced.
        drop((first_hog, second_hog));
        let bytes = tokio::time::timeout(
            std::time::Duration::from_secs(120),
            service.serve_actioncache_snapshot("ios", 0, None),
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
        test_support::{TestContext, test_context, test_context_with_auth},
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

    #[tokio::test(flavor = "multi_thread", worker_threads = 8)]
    #[ignore = "performance benchmark run manually"]
    async fn direct_memory_bytestream_write_benchmark() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

        const CONNECTIONS: usize = 4;
        const CONCURRENCY: usize = 64;
        const WRITES: usize = 512;
        const SAMPLES: usize = 4;
        const BLOB_BYTES: usize = SEGMENT_COPY_BUFFER_BYTES;
        const CHUNK_BYTES: usize = 64 * 1024;

        struct BenchmarkServer {
            _context: TestContext,
            channels: std::sync::Arc<Vec<tonic::transport::Channel>>,
            shutdown: tokio::sync::oneshot::Sender<()>,
            task: tokio::task::JoinHandle<()>,
        }

        async fn start_server(direct: bool) -> BenchmarkServer {
            let context = test_context(|_| {}).await;
            context.state.store.set_direct_small_uploads_enabled(direct);
            let listener = TcpListener::bind("127.0.0.1:0")
                .await
                .expect("bind benchmark listener");
            let address = listener.local_addr().expect("benchmark listener address");
            let (shutdown, stopped) = tokio::sync::oneshot::channel();
            let state = context.state.clone();
            let task = tokio::spawn(async move {
                serve_routes(listener, state, async move {
                    let _ = stopped.await;
                })
                .await;
            });
            let endpoint = format!("http://{address}");
            let mut channels = Vec::with_capacity(CONNECTIONS);
            for _ in 0..CONNECTIONS {
                let mut channel = None;
                for _ in 0..50 {
                    match tonic::transport::Endpoint::from_shared(endpoint.clone())
                        .expect("valid benchmark endpoint")
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
                channels.push(channel.expect("benchmark server should accept connections"));
            }
            BenchmarkServer {
                _context: context,
                channels: std::sync::Arc::new(channels),
                shutdown,
                task,
            }
        }

        async fn stop_server(server: BenchmarkServer) {
            let BenchmarkServer {
                _context,
                channels,
                shutdown,
                task,
            } = server;
            drop(channels);
            let _ = shutdown.send(());
            tokio::time::timeout(Duration::from_secs(10), task)
                .await
                .expect("benchmark server should stop")
                .expect("benchmark server should not panic");
        }

        async fn measure(
            server: &BenchmarkServer,
            sample: usize,
            label: &'static str,
        ) -> (f64, u128, u128, u128) {
            fn spawn_write(
                writes: &mut tokio::task::JoinSet<std::time::Duration>,
                channels: std::sync::Arc<Vec<tonic::transport::Channel>>,
                sample: usize,
                index: usize,
                label: &'static str,
            ) {
                writes.spawn(async move {
                    let mut blob = vec![0x5a; BLOB_BYTES];
                    blob[..8].copy_from_slice(&((sample * WRITES + index) as u64).to_le_bytes());
                    let hash = hex::encode(Sha256::digest(&blob));
                    let resource = format!(
                        "ios/uploads/{label}-{sample}-{index}/blobs/{hash}/{}",
                        blob.len()
                    );
                    let mut requests = Vec::with_capacity(blob.len().div_ceil(CHUNK_BYTES));
                    for (chunk_index, data) in blob.chunks(CHUNK_BYTES).enumerate() {
                        let offset = chunk_index * CHUNK_BYTES;
                        requests.push(bytestream::WriteRequest {
                            resource_name: if offset == 0 {
                                resource.clone()
                            } else {
                                String::new()
                            },
                            write_offset: offset as i64,
                            finish_write: offset + data.len() == blob.len(),
                            data: data.to_vec(),
                        });
                    }
                    drop(blob);
                    let request = Request::new(tokio_stream::iter(requests));
                    let mut client =
                        ByteStreamClient::new(channels[index % channels.len()].clone());
                    let started_at = std::time::Instant::now();
                    let committed = client
                        .write(request)
                        .await
                        .expect("benchmark ByteStream write should persist")
                        .into_inner()
                        .committed_size;
                    assert_eq!(committed as usize, BLOB_BYTES);
                    started_at.elapsed()
                });
            }

            let started_at = std::time::Instant::now();
            let mut writes = tokio::task::JoinSet::new();
            let mut next = 0;
            while next < CONCURRENCY {
                spawn_write(&mut writes, server.channels.clone(), sample, next, label);
                next += 1;
            }
            let mut latencies = Vec::with_capacity(WRITES);
            while let Some(result) = writes.join_next().await {
                latencies.push(result.expect("benchmark writer should finish"));
                if next < WRITES {
                    spawn_write(&mut writes, server.channels.clone(), sample, next, label);
                    next += 1;
                }
            }
            let elapsed = started_at.elapsed().as_secs_f64();
            latencies.sort_unstable();
            let percentile =
                |percent: usize| latencies[(latencies.len() - 1) * percent / 100].as_micros();
            (
                WRITES as f64 / elapsed,
                percentile(50),
                percentile(95),
                percentile(99),
            )
        }

        let staged = start_server(false).await;
        let direct = start_server(true).await;
        let mut staged_samples = Vec::with_capacity(SAMPLES - 1);
        let mut direct_samples = Vec::with_capacity(SAMPLES - 1);
        let mut speedups = Vec::with_capacity(SAMPLES - 1);
        for sample in 0..SAMPLES {
            let (staged_result, direct_result) = if sample % 2 == 0 {
                (
                    measure(&staged, sample, "staged").await,
                    measure(&direct, sample, "direct").await,
                )
            } else {
                let direct_result = measure(&direct, sample, "direct").await;
                (measure(&staged, sample, "staged").await, direct_result)
            };
            if sample > 0 {
                speedups.push(direct_result.0 / staged_result.0);
                staged_samples.push(staged_result);
                direct_samples.push(direct_result);
            }
        }
        stop_server(staged).await;
        stop_server(direct).await;

        staged_samples.sort_by(|left, right| left.0.total_cmp(&right.0));
        direct_samples.sort_by(|left, right| left.0.total_cmp(&right.0));
        speedups.sort_by(f64::total_cmp);
        let median = speedups.len() / 2;
        let staged_median = staged_samples[median];
        let direct_median = direct_samples[median];
        println!(
            "METRIC direct_memory_bytestream_write_speedup_ratio={:.6}",
            speedups[median]
        );
        println!(
            "METRIC staged_bytestream_writes_per_second={:.3}",
            staged_median.0
        );
        println!(
            "METRIC direct_memory_bytestream_writes_per_second={:.3}",
            direct_median.0
        );
        println!(
            "METRIC staged_bytestream_write_p50_microseconds={}",
            staged_median.1
        );
        println!(
            "METRIC staged_bytestream_write_p95_microseconds={}",
            staged_median.2
        );
        println!(
            "METRIC staged_bytestream_write_p99_microseconds={}",
            staged_median.3
        );
        println!(
            "METRIC direct_memory_bytestream_write_p50_microseconds={}",
            direct_median.1
        );
        println!(
            "METRIC direct_memory_bytestream_write_p95_microseconds={}",
            direct_median.2
        );
        println!(
            "METRIC direct_memory_bytestream_write_p99_microseconds={}",
            direct_median.3
        );
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

    #[tokio::test]
    async fn response_transport_keeps_materialization_memory_until_body_drops() {
        let context = test_context(|_| {}).await;
        let materialization_limit = context.state.memory.reapi_materialization_limit_bytes();
        let first_permit = context
            .state
            .memory
            .try_acquire_reapi_materialization(materialization_limit)
            .expect("the response should reserve the materialization pool")
            .expect("a non-zero reservation should return a permit");
        let second_permit = context
            .state
            .memory
            .try_acquire_reapi_materialization(materialization_limit)
            .expect("the response should reserve the rest of the materialization pool")
            .expect("a non-zero reservation should return a permit");
        let mut response = axum::response::Response::new(axum::body::Body::empty());
        response.extensions_mut().insert(
            crate::memory::ResponseTransportGuard::from_materialization_permits(vec![
                first_permit,
                second_permit,
            ]),
        );
        let response = crate::http::guard_response_stream_transport(response).await;

        assert!(
            context
                .state
                .memory
                .try_acquire_reapi_materialization(1)
                .is_err(),
            "an unconsumed response body must retain its materialization permit"
        );

        drop(response);

        assert!(
            context
                .state
                .memory
                .try_acquire_reapi_materialization(1)
                .is_ok(),
            "dropping the response body must release its materialization permit"
        );
    }

    #[tokio::test]
    async fn bytestream_read_burst_waits_without_shedding() {
        for compressed in [false, true] {
            let context = test_context(|config| {
                config.memory_limit_bytes = 128 * 1024 * 1024;
                config.memory_soft_limit_bytes = 64 * 1024 * 1024;
                config.memory_hard_limit_bytes = 96 * 1024 * 1024;
            })
            .await;
            let blob = vec![0xA5; 1024 * 1024];
            let hash = hex::encode(Sha256::digest(&blob));
            context
                .state
                .store
                .persist_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    DEFAULT_INSTANCE_NAME,
                    &blob_key(&format!("{hash}/{}", blob.len())),
                    "application/octet-stream",
                    &blob,
                )
                .await
                .expect("seed blob");
            let resource = format!(
                "{}/{hash}/{}",
                if compressed {
                    "compressed-blobs/zstd"
                } else {
                    "blobs"
                },
                blob.len()
            );
            let completed_admission = Arc::new(std::sync::atomic::AtomicUsize::new(0));
            let (release, released) = tokio::sync::watch::channel(false);
            let mut tasks = tokio::task::JoinSet::new();
            let reads = if compressed { 24 } else { 32 };
            for _ in 0..reads {
                let service = ReapiService {
                    state: context.state.clone(),
                    snapshot_cache: Default::default(),
                };
                let resource_name = resource.clone();
                let completed = completed_admission.clone();
                let mut released = released.clone();
                tasks.spawn(async move {
                    let response = service
                        .read(Request::new(bytestream::ReadRequest {
                            resource_name,
                            read_offset: 0,
                            read_limit: 0,
                        }))
                        .await;
                    completed.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                    let response = response?;
                    released
                        .wait_for(|released| *released)
                        .await
                        .expect("release readers");
                    let (_, mut stream, guard) = response.into_parts();
                    let mut bytes = Vec::new();
                    while let Some(chunk) = stream.next().await {
                        bytes.extend(chunk?.data);
                    }
                    drop(guard);
                    if compressed {
                        bytes = zstd::stream::decode_all(bytes.as_slice()).expect("decode read");
                    }
                    assert_eq!(bytes, vec![0xA5; 1024 * 1024]);
                    Ok::<_, Status>(())
                });
            }
            // Hold admitted bodies until every read is either queued or admitted.
            // This reproduces a burst without depending on scheduler timing.
            tokio::time::timeout(Duration::from_secs(10), async {
                loop {
                    let waiting = context.state.memory.response_stream_waiter_count();
                    if waiting + completed_admission.load(std::sync::atomic::Ordering::SeqCst)
                        == reads
                    {
                        assert!(waiting > 0, "the burst must exercise queued admission");
                        break;
                    }
                    tokio::task::yield_now().await;
                }
            })
            .await
            .expect("all reads should reach admission");
            release.send(true).expect("release burst");
            let mut rejected = Vec::new();
            while let Some(result) = tasks.join_next().await {
                if let Err(error) = result.expect("read task") {
                    rejected.push(error);
                }
            }
            assert!(rejected.is_empty(), "compressed={compressed}: {rejected:?}");
            assert_eq!(context.state.memory.transient_reserved_bytes(), 0);
        }
    }

    #[tokio::test]
    async fn bytestream_route_keeps_stream_memory_until_encoded_bytes_drop() {
        let context = test_context(|_| {}).await;
        let blob = vec![0xA5; 64 * 1024];
        let hash = hex::encode(Sha256::digest(&blob));
        let manifest = context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &blob_key(&format!("{hash}/{}", blob.len())),
                "application/octet-stream",
                &blob,
            )
            .await
            .expect("CAS blob should persist");
        assert!(!manifest.inline);

        let mut response = routes(context.state.clone())
            .oneshot(grpc_request(
                "/google.bytestream.ByteStream/Read",
                &bytestream::ReadRequest {
                    resource_name: format!("blobs/{hash}/{}", blob.len()),
                    read_offset: 0,
                    read_limit: 0,
                },
            ))
            .await
            .expect("ByteStream route should respond");
        assert_eq!(response.status(), http::StatusCode::OK);
        let reserved_bytes = context.state.memory.transient_reserved_bytes();
        assert_eq!(
            reserved_bytes,
            encoded_response_stream_chunk_bytes(blob.len() as u64)
                .saturating_mul(BYTESTREAM_RESPONSE_LIVE_CHUNK_COUNT)
                .saturating_add(RESPONSE_STREAM_SEND_BUFFER_BYTES) as u64,
            "ByteStream admission should charge two chunks plus the capped send buffer"
        );

        let frame = response
            .body_mut()
            .frame()
            .await
            .expect("ByteStream response should yield a frame")
            .expect("ByteStream response frame should be valid");
        let encoded = frame
            .into_data()
            .expect("ByteStream response frame should contain encoded data");
        drop(response);
        assert_eq!(
            context.state.memory.transient_reserved_bytes(),
            reserved_bytes,
            "the encoded transport bytes must retain the stream reservation"
        );

        drop(encoded);
        #[cfg(target_os = "linux")]
        context.state.memory.observe(0);
        assert_eq!(context.state.memory.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn batch_read_route_keeps_materialization_memory_until_encoded_bytes_drop() {
        let context = test_context(|_| {}).await;
        let blob = vec![0x5A; 64 * 1024];
        let digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&blob)),
            size_bytes: blob.len() as i64,
        };
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &blob_key(&digest_key(&digest).expect("digest key should build")),
                "application/octet-stream",
                &blob,
            )
            .await
            .expect("CAS blob should persist");

        let mut response = routes(context.state.clone())
            .oneshot(grpc_request(
                "/build.bazel.remote.execution.v2.ContentAddressableStorage/BatchReadBlobs",
                &reapi::BatchReadBlobsRequest {
                    instance_name: DEFAULT_INSTANCE_NAME.into(),
                    digests: vec![digest],
                    digest_function: reapi::digest_function::Value::Sha256 as i32,
                    ..Default::default()
                },
            ))
            .await
            .expect("BatchReadBlobs route should respond");
        assert_eq!(response.status(), http::StatusCode::OK);
        let reserved_bytes = context.state.memory.transient_reserved_bytes();
        assert_eq!(reserved_bytes, (blob.len() * 2) as u64);

        let frame = response
            .body_mut()
            .frame()
            .await
            .expect("BatchReadBlobs response should yield a frame")
            .expect("BatchReadBlobs response frame should be valid");
        let encoded = frame
            .into_data()
            .expect("BatchReadBlobs response frame should contain encoded data");
        drop(response);
        assert_eq!(
            context.state.memory.transient_reserved_bytes(),
            reserved_bytes,
            "the encoded transport bytes must retain the materialization reservation"
        );

        drop(encoded);
        #[cfg(target_os = "linux")]
        context.state.memory.observe(0);
        assert_eq!(context.state.memory.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn unary_response_keeps_materialization_memory_until_encoded_bytes_drop() {
        let context = test_context(|_| {}).await;
        let digests = (0..128)
            .map(|index| reapi::Digest {
                hash: format!("{index:064x}"),
                size_bytes: index,
            })
            .collect::<Vec<_>>();
        let expected = reapi::FindMissingBlobsResponse {
            missing_blob_digests: digests.clone(),
        };

        let mut response = routes(context.state.clone())
            .oneshot(grpc_request(
                "/build.bazel.remote.execution.v2.ContentAddressableStorage/FindMissingBlobs",
                &reapi::FindMissingBlobsRequest {
                    instance_name: DEFAULT_INSTANCE_NAME.into(),
                    blob_digests: digests,
                    digest_function: reapi::digest_function::Value::Sha256 as i32,
                },
            ))
            .await
            .expect("FindMissingBlobs route should respond");
        assert_eq!(response.status(), http::StatusCode::OK);
        let reserved_bytes = context.state.memory.transient_reserved_bytes();
        assert_eq!(reserved_bytes, (expected.encoded_len() * 2) as u64);

        let frame = response
            .body_mut()
            .frame()
            .await
            .expect("FindMissingBlobs response should yield a frame")
            .expect("FindMissingBlobs response frame should be valid");
        let encoded = frame
            .into_data()
            .expect("FindMissingBlobs response frame should contain encoded data");
        drop(response);
        assert_eq!(
            context.state.memory.transient_reserved_bytes(),
            reserved_bytes
        );

        drop(encoded);
        #[cfg(target_os = "linux")]
        context.state.memory.observe(0);
        assert_eq!(context.state.memory.transient_reserved_bytes(), 0);
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
        assert_concurrent_bytestream_writes_persist(false).await;
    }

    // Wire chunks that straddle the staging window, including one larger than
    // the window after a partial fill, must reach the staged file in order.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn ragged_bytestream_writes_cross_staging_windows() {
        assert_concurrent_bytestream_writes_persist(true).await;
    }

    async fn assert_concurrent_bytestream_writes_persist(ragged: bool) {
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

        let concurrency = if ragged { 2u32 } else { 24u32 };
        let chunk_size = 32 * 1024;
        let mut writers = Vec::new();
        for index in 0..concurrency {
            let mut client = ByteStreamClient::new(channel.clone());
            writers.push(tokio::spawn(async move {
                // Per-blob-distinct, multi-chunk content so each upload spans many
                // `write_all` calls (leaving buffered bytes for the flush to race).
                let blob_size = if ragged {
                    3 * REAPI_STAGING_WRITE_BUFFER_BYTES as u32 + 17
                } else {
                    384 * 1024u32
                };
                let blob: Vec<u8> = (0..blob_size)
                    .map(|byte| byte.wrapping_mul(31).wrapping_add(index) as u8)
                    .collect();
                let hash = hex::encode(Sha256::digest(&blob));
                let resource = format!("uploads/upload-{index}/blobs/{hash}/{}", blob.len());
                let mut requests = Vec::new();
                let mut offset = 0usize;
                while offset < blob.len() {
                    let next_size = if ragged {
                        let window = REAPI_STAGING_WRITE_BUFFER_BYTES as usize;
                        match requests.len() {
                            0 => window - 7,
                            1 => 2 * window + 17,
                            _ => chunk_size,
                        }
                    } else {
                        chunk_size
                    };
                    let end = (offset + next_size).min(blob.len());
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

    fn chunked_write_requests(
        resource: &str,
        data: &[u8],
        finish_write: bool,
    ) -> Vec<bytestream::WriteRequest> {
        let chunk_size = 64 * 1024;
        let chunk_count = data.len().div_ceil(chunk_size);
        data.chunks(chunk_size)
            .enumerate()
            .map(|(index, chunk)| bytestream::WriteRequest {
                resource_name: if index == 0 {
                    resource.to_owned()
                } else {
                    String::new()
                },
                write_offset: (index * chunk_size) as i64,
                finish_write: finish_write && index + 1 == chunk_count,
                data: chunk.to_vec(),
            })
            .collect()
    }

    // Rejected, unfinished and cancelled uploads end before anything is
    // appended: they consume no live segment space and return their staging
    // budget, while a valid upload of the same blob afterwards appends once.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn rejected_bytestream_uploads_never_consume_segment_space() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

        let context = test_context(|_| {}).await;
        let (channel, shutdown_tx, server) = connect_test_routes(context.state.clone()).await;
        let mut client = ByteStreamClient::new(channel);

        // Larger than the in-memory upload limit, so every attempt stages to
        // a budgeted temporary file.
        let blob: Vec<u8> = (0..3 * REAPI_STAGING_WRITE_BUFFER_BYTES as u32 + 17)
            .map(|byte| byte.wrapping_mul(31) as u8)
            .collect();
        assert!(blob.len() > SEGMENT_COPY_BUFFER_BYTES);
        let hash = hex::encode(Sha256::digest(&blob));
        let resource = format!("uploads/rejected/blobs/{hash}/{}", blob.len());
        let budget = context.state.tmp_staging_budget.clone();
        let ring_bytes = context.state.store.storage_snapshot().live_segment_bytes;

        let mut corrupted = blob.clone();
        corrupted[0] ^= 0xff;
        let mut oversized = blob.clone();
        oversized.push(0);
        let rejected = [
            (
                "wrong digest",
                chunked_write_requests(&resource, &corrupted, true),
            ),
            (
                "oversized",
                chunked_write_requests(&resource, &oversized, true),
            ),
            (
                "unfinished",
                chunked_write_requests(&resource, &blob[..blob.len() / 2], false),
            ),
        ];
        for (case, requests) in rejected {
            let status = client
                .write(tokio_stream::iter(requests))
                .await
                .expect_err("a rejected upload must fail");
            assert_eq!(status.code(), tonic::Code::InvalidArgument, "{case}");
            assert_eq!(budget.reserved_bytes(), 0, "{case}");
            assert_eq!(
                context.state.store.storage_snapshot().live_segment_bytes,
                ring_bytes,
                "{case}"
            );
        }

        // Cancel mid-stream once the server has admitted and started staging
        // the upload.
        let (sender, receiver) = tokio::sync::mpsc::channel(4);
        let requests = futures_util::stream::unfold(receiver, |mut receiver| async move {
            receiver.recv().await.map(|request| (request, receiver))
        });
        let mut cancelled_client = client.clone();
        let cancelled = tokio::spawn(async move { cancelled_client.write(requests).await });
        sender
            .send(chunked_write_requests(&resource, &blob, true).remove(0))
            .await
            .expect("cancelled upload should accept its first chunk");
        tokio::time::timeout(Duration::from_secs(10), async {
            while budget.reserved_bytes() == 0 {
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await
        .expect("the server should start staging the cancelled upload");
        cancelled.abort();
        let _ = cancelled.await;
        drop(sender);
        tokio::time::timeout(Duration::from_secs(10), async {
            while budget.reserved_bytes() != 0 {
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await
        .expect("a cancelled upload should release its staging budget");
        assert_eq!(
            context.state.store.storage_snapshot().live_segment_bytes,
            ring_bytes
        );

        let status = client
            .read(bytestream::ReadRequest {
                resource_name: format!("blobs/{hash}/{}", blob.len()),
                read_offset: 0,
                read_limit: 0,
            })
            .await
            .expect_err("no rejected upload may publish the blob");
        assert_eq!(status.code(), tonic::Code::NotFound);

        let committed = client
            .write(tokio_stream::iter(chunked_write_requests(
                &resource, &blob, true,
            )))
            .await
            .expect("a valid upload should persist")
            .into_inner()
            .committed_size;
        assert_eq!(committed as usize, blob.len());
        assert_eq!(budget.reserved_bytes(), 0);
        assert_eq!(
            context.state.store.storage_snapshot().live_segment_bytes,
            ring_bytes + blob.len() as u64
        );

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
        let details = RpcStatus::decode(error.details())
            .expect("admission retry details must survive the HTTP/2 and Tonic body-error path");
        assert_eq!(details.code, tonic::Code::ResourceExhausted as i32);
        assert_eq!(details.details.len(), 1);
        assert_eq!(
            details.details[0].type_url,
            "type.googleapis.com/google.rpc.RetryInfo"
        );

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
                hash_range: 5..8,
                size_bytes: 10,
                key: "blob/abc/10".into(),
                compressor: BlobCompressor::Identity,
            }
        );
        assert_eq!(
            parse_read_resource_name("bazel/cache/blobs/abc/10")
                .expect("instance-scoped resource should parse"),
            BlobResource {
                namespace_id: "bazel/cache".into(),
                hash_range: 5..8,
                size_bytes: 10,
                key: "blob/abc/10".into(),
                compressor: BlobCompressor::Identity,
            }
        );
    }

    #[test]
    fn digest_comparison_accepts_exact_bytes_and_rejects_invalid_hashes() {
        let actual = [0xAB_u8; 32];
        let expected = "ab".repeat(32);
        assert!(digest_matches_hex(&actual, &expected));
        assert!(!digest_matches_hex(&[0xAC; 32], &expected));
        assert!(!digest_matches_hex(&actual, "not-a-digest"));
        assert!(!digest_matches_hex(&actual, &"ab".repeat(31)));
        assert!(!digest_matches_hex(&actual, &"AB".repeat(32)));
    }

    #[test]
    #[ignore = "performance benchmark run manually"]
    fn digest_comparison_without_hex_allocation_benchmark() {
        const ITERATIONS: usize = 1_000_000;
        const SAMPLES: usize = 8;

        let actual = [0xAB_u8; 32];
        let expected = "ab".repeat(32);
        let measure = |candidate| {
            let started_at = std::time::Instant::now();
            for _ in 0..ITERATIONS {
                let matches = if candidate {
                    digest_matches_hex(std::hint::black_box(&actual), &expected)
                } else {
                    hex::encode(std::hint::black_box(actual)) == expected
                };
                std::hint::black_box(matches);
            }
            ITERATIONS as f64 / started_at.elapsed().as_secs_f64()
        };

        let mut baseline_rates = Vec::with_capacity(SAMPLES - 1);
        let mut candidate_rates = Vec::with_capacity(SAMPLES - 1);
        let mut speedups = Vec::with_capacity(SAMPLES - 1);
        for sample in 0..SAMPLES {
            let (baseline, candidate) = if sample % 2 == 0 {
                (measure(false), measure(true))
            } else {
                let candidate = measure(true);
                (measure(false), candidate)
            };
            if sample > 0 {
                baseline_rates.push(baseline);
                candidate_rates.push(candidate);
                speedups.push(candidate / baseline);
            }
        }
        baseline_rates.sort_by(f64::total_cmp);
        candidate_rates.sort_by(f64::total_cmp);
        speedups.sort_by(f64::total_cmp);
        let median = speedups.len() / 2;

        println!(
            "METRIC digest_comparison_baseline_per_second={:.3}",
            baseline_rates[median]
        );
        println!(
            "METRIC digest_comparison_candidate_per_second={:.3}",
            candidate_rates[median]
        );
        println!(
            "METRIC digest_comparison_speedup_ratio={:.6}",
            speedups[median]
        );
    }

    #[test]
    fn allocation_free_resource_scan_preserves_normalization_and_last_blob_marker() {
        for (resource_name, require_upload_prefix) in [
            ("//bazel///cache/blobs/abc/00010/trailing", false),
            ("first/blobs/ignored/buck/uploads/uuid-1/blobs/abc/10", true),
            ("blobs/abc", false),
            ("buck/cache/blobs/abc/invalid", false),
            ("bazel/cache/compressed-blobs/zstd/abc/10", false),
            (
                "bazel/cache/uploads/uuid-1/compressed-blobs/zstd/abc/10",
                true,
            ),
            ("bazel/cache/compressed-blobs/deflate/abc/10", false),
            ("bazel/cache/compressed-blobs/bogus/abc/10", false),
            ("bazel/cache/compressed-blobs", false),
        ] {
            let candidate = parse_blob_resource_name(resource_name, require_upload_prefix);
            let baseline =
                parse_blob_resource_name_allocating(resource_name, require_upload_prefix);
            match (candidate, baseline) {
                (Ok(candidate), Ok(baseline)) => assert_eq!(candidate, baseline),
                (Err(candidate), Err(baseline)) => {
                    assert_eq!(candidate.code(), baseline.code());
                    assert_eq!(candidate.message(), baseline.message());
                }
                (candidate, baseline) => {
                    panic!("parser results differ: candidate={candidate:?}, baseline={baseline:?}")
                }
            }
        }
    }

    #[test]
    #[ignore = "performance benchmark run manually"]
    fn blob_resource_name_parser_benchmark() {
        const ITERATIONS: usize = 500_000;
        const SAMPLES: usize = 8;
        const RESOURCE_NAME: &str = concat!(
            "bazel/cache/uploads/018f5f8d-7f2b-7ee5-8c42-6b62475558a3/blobs/",
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/262144"
        );

        let measure = |allocating| {
            let started_at = std::time::Instant::now();
            for _ in 0..ITERATIONS {
                let resource = if allocating {
                    parse_blob_resource_name_allocating(RESOURCE_NAME, true)
                } else {
                    parse_blob_resource_name(RESOURCE_NAME, true)
                }
                .expect("benchmark resource should parse");
                std::hint::black_box(resource);
            }
            ITERATIONS as f64 / started_at.elapsed().as_secs_f64()
        };

        let mut baseline_rates = Vec::with_capacity(SAMPLES - 1);
        let mut candidate_rates = Vec::with_capacity(SAMPLES - 1);
        let mut speedups = Vec::with_capacity(SAMPLES - 1);
        for sample in 0..SAMPLES {
            let (baseline, candidate) = if sample % 2 == 0 {
                (measure(true), measure(false))
            } else {
                let candidate = measure(false);
                (measure(true), candidate)
            };
            if sample > 0 {
                baseline_rates.push(baseline);
                candidate_rates.push(candidate);
                speedups.push(candidate / baseline);
            }
        }
        baseline_rates.sort_by(f64::total_cmp);
        candidate_rates.sort_by(f64::total_cmp);
        speedups.sort_by(f64::total_cmp);
        let median = speedups.len() / 2;

        println!(
            "METRIC blob_resource_parse_baseline_per_second={:.3}",
            baseline_rates[median]
        );
        println!(
            "METRIC blob_resource_parse_candidate_per_second={:.3}",
            candidate_rates[median]
        );
        println!(
            "METRIC blob_resource_parse_speedup_ratio={:.6}",
            speedups[median]
        );
    }

    #[test]
    #[ignore = "performance benchmark run manually"]
    fn blob_resource_construction_without_duplicate_hash_benchmark() {
        const ITERATIONS: usize = 1_000_000;
        const SAMPLES: usize = 8;
        const HASH: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        const ENCODED_SIZE: &str = "262144";

        let measure = |duplicate_hash: bool| {
            let started_at = std::time::Instant::now();
            for _ in 0..ITERATIONS {
                let hash = duplicate_hash.then(|| HASH.to_owned());
                let mut key =
                    String::with_capacity("blob/".len() + HASH.len() + 1 + ENCODED_SIZE.len());
                key.push_str("blob/");
                key.push_str(HASH);
                key.push('/');
                key.push_str(ENCODED_SIZE);
                let hash_range = "blob/".len().."blob/".len() + HASH.len();
                std::hint::black_box((hash, hash_range, key));
            }
            ITERATIONS as f64 / started_at.elapsed().as_secs_f64()
        };

        let mut baseline_rates = Vec::with_capacity(SAMPLES - 1);
        let mut candidate_rates = Vec::with_capacity(SAMPLES - 1);
        let mut speedups = Vec::with_capacity(SAMPLES - 1);
        for sample in 0..SAMPLES {
            let (baseline, candidate) = if sample % 2 == 0 {
                (measure(true), measure(false))
            } else {
                let candidate = measure(false);
                (measure(true), candidate)
            };
            if sample > 0 {
                baseline_rates.push(baseline);
                candidate_rates.push(candidate);
                speedups.push(candidate / baseline);
            }
        }
        baseline_rates.sort_by(f64::total_cmp);
        candidate_rates.sort_by(f64::total_cmp);
        speedups.sort_by(f64::total_cmp);
        let median = speedups.len() / 2;

        println!(
            "METRIC blob_resource_construction_baseline_per_second={:.3}",
            baseline_rates[median]
        );
        println!(
            "METRIC blob_resource_construction_candidate_per_second={:.3}",
            candidate_rates[median]
        );
        println!(
            "METRIC blob_resource_construction_speedup_ratio={:.6}",
            speedups[median]
        );
    }

    #[test]
    fn parses_write_resource_names_with_upload_prefix() {
        assert_eq!(
            parse_write_resource_name("buck/cache/uploads/uuid-1/blobs/abc/10")
                .expect("write resource should parse"),
            BlobResource {
                namespace_id: "buck/cache".into(),
                hash_range: 5..8,
                size_bytes: 10,
                key: "blob/abc/10".into(),
                compressor: BlobCompressor::Identity,
            }
        );
    }

    #[test]
    fn rejects_write_resources_without_upload_prefix() {
        let error = parse_write_resource_name("blobs/abc/10")
            .expect_err("write resources should require uploads prefix");
        assert_eq!(error.code(), tonic::Code::InvalidArgument);
    }

    #[test]
    fn parses_zstd_compressed_read_and_write_resource_names() {
        let read = parse_read_resource_name("bazel/cache/compressed-blobs/zstd/abc/10")
            .expect("compressed read resource should parse");
        assert_eq!(read.compressor, BlobCompressor::Zstd);
        assert_eq!(read.namespace_id, "bazel/cache");
        assert_eq!(read.size_bytes, 10);
        assert_eq!(read.hash(), "abc");
        // The store key is built from the uncompressed digest, so a compressed
        // read resolves to the same on-disk blob as an identity read.
        assert_eq!(read.key, "blob/abc/10");

        let write =
            parse_write_resource_name("bazel/cache/uploads/uuid-1/compressed-blobs/zstd/abc/10")
                .expect("compressed write resource should parse");
        assert_eq!(write.compressor, BlobCompressor::Zstd);
        assert_eq!(write.namespace_id, "bazel/cache");
        assert_eq!(write.size_bytes, 10);
        assert_eq!(write.key, "blob/abc/10");
    }

    #[test]
    fn rejects_unknown_compressor_in_resource_name() {
        let unimplemented = parse_read_resource_name("compressed-blobs/deflate/abc/10")
            .expect_err("deflate is not supported");
        assert_eq!(unimplemented.code(), tonic::Code::Unimplemented);

        let invalid = parse_read_resource_name("compressed-blobs/bogus/abc/10")
            .expect_err("unknown compressor names must be rejected");
        assert_eq!(invalid.code(), tonic::Code::InvalidArgument);
    }

    fn grpc_spec() -> GrpcRequestSpec<'static> {
        GrpcRequestSpec {
            operation: "capabilities.read",
            namespace_id: Some("ios"),
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
        let ctx = grpc_request_context("acme", &grpc_spec(), &metadata);
        assert_eq!(ctx.tenant_id.as_deref(), Some("acme"));
        assert_eq!(ctx.namespace_id.as_deref(), Some("ios"));
    }

    #[test]
    fn grpc_context_reads_tenant_from_tuist_account_handle_alias() {
        let metadata = metadata_with(&[("x-tuist-account-handle", "acme")]);
        let ctx = grpc_request_context("acme", &grpc_spec(), &metadata);
        assert_eq!(ctx.tenant_id.as_deref(), Some("acme"));
    }

    #[test]
    fn grpc_context_without_tenant_header_leaves_tenant_unset() {
        let metadata = tonic::metadata::MetadataMap::new();
        let ctx = grpc_request_context("acme", &grpc_spec(), &metadata);
        assert_eq!(ctx.tenant_id, None);
        assert_eq!(ctx.namespace_id.as_deref(), Some("ios"));
    }

    // A token granting exactly one project. Both tests below use it to prove
    // that GetCapabilities and ByteStream Write authorize the request's project
    // namespace (instance_name / resource_name), not the account scope they
    // previously fell back to.
    const NAMESPACE_POLICY_SECRET: &str = "namespace-policy-secret";

    fn namespace_policy_token() -> String {
        jsonwebtoken::encode(
            &jsonwebtoken::Header::new(jsonwebtoken::Algorithm::HS256),
            &serde_json::json!({
                "sub": "test",
                "type": "subject",
                "scopes": ["project_cache_write"],
                "cache_grants": { "project": { "write": ["test-tenant/ios"] } },
                "exp": 4_102_444_800_u64,
            }),
            &jsonwebtoken::EncodingKey::from_secret(NAMESPACE_POLICY_SECRET.as_bytes()),
        )
        .expect("mint a policy token")
    }

    // A server is configured, but its base URL refuses connections on purpose.
    // A namespace the token's own grants name is answered from those grants and
    // never reaches it; one they do not name has to, and cannot.
    fn namespace_policy_auth() -> crate::auth::SharedAuth {
        std::sync::Arc::new(
            crate::auth::AuthEngine::new(
                crate::auth::config::AuthConfig {
                    base_url: "http://127.0.0.1:1".into(),
                    connect_timeout: Duration::from_millis(50),
                    request_timeout: Duration::from_millis(50),
                    verifier: Some(crate::auth::tuist::JwtVerifier {
                        algorithm: jsonwebtoken::Algorithm::HS256,
                        keys: crate::auth::tuist::JwtVerifier::secret_keys(NAMESPACE_POLICY_SECRET),
                        issuer: None,
                        audiences: Vec::new(),
                    }),
                    introspection: None,
                    cache_max_entries: 128,
                },
                crate::metrics::Metrics::new("test".into(), "tenant".into()),
            )
            .expect("build the policy engine"),
        )
    }

    fn bearing_policy_token<T>(message: T) -> Request<T> {
        let mut request = Request::new(message);
        request.metadata_mut().insert(
            "authorization",
            format!("Bearer {}", namespace_policy_token())
                .parse()
                .expect("bearer metadata"),
        );
        request
    }

    #[tokio::test]
    async fn get_capabilities_authorizes_against_instance_namespace() {
        let auth = namespace_policy_auth();
        let context = test_context_with_auth(|_| {}, Some(auth)).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };

        service
            .get_capabilities(bearing_policy_token(reapi::GetCapabilitiesRequest {
                instance_name: "ios".into(),
            }))
            .await
            .expect("capabilities for a granted instance_name should be allowed");

        // Grants that do not name the instance do not settle it: they are a
        // snapshot from when the token was minted, and the server can still
        // return wider ones. Only the server can say, and this one refuses
        // connections, so the node reports that rather than deciding on its
        // own. Authentication is resolved per target, so the answer for `ios`
        // above is not reused here.
        let denied = service
            .get_capabilities(bearing_policy_token(reapi::GetCapabilitiesRequest {
                instance_name: "forbidden".into(),
            }))
            .await
            .expect_err("capabilities for a non-granted instance_name should be denied");
        assert_eq!(denied.code(), tonic::Code::Unavailable);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn bytestream_write_authorizes_against_resource_namespace() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

        let auth = namespace_policy_auth();
        let context = test_context_with_auth(|_| {}, Some(auth)).await;
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
            .write(bearing_policy_token(tokio_stream::iter(vec![
                bytestream::WriteRequest {
                    resource_name: format!("ios/uploads/write-1/blobs/{hash}/{len}"),
                    write_offset: 0,
                    finish_write: true,
                    data: blob.clone(),
                },
            ])))
            .await
            .expect("write to a granted namespace should be allowed")
            .into_inner()
            .committed_size;
        assert_eq!(committed as usize, len);

        // Non-granted namespace ("forbidden") is rejected before the blob is
        // persisted. Grants that do not name it do not settle it — they are a
        // snapshot from minting time and the server can still return wider ones
        // — and this server refuses connections, so the node reports that
        // rather than deciding on its own.
        let denied = ByteStreamClient::new(channel.clone())
            .write(bearing_policy_token(tokio_stream::iter(vec![
                bytestream::WriteRequest {
                    resource_name: format!("forbidden/uploads/write-2/blobs/{hash}/{len}"),
                    write_offset: 0,
                    finish_write: true,
                    data: blob.clone(),
                },
            ])))
            .await
            .expect_err("write to a non-granted namespace should be denied");
        assert_eq!(denied.code(), tonic::Code::Unavailable);

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
    async fn cas_batch_reads_declaring_more_than_the_budget_are_served_on_an_idle_pod() {
        let context = test_context(|config| {
            config.memory_soft_limit_bytes = 512 * 1024 * 1024;
            config.memory_hard_limit_bytes = 640 * 1024 * 1024;
        })
        .await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let bytes = b"present-bytes";
        let present_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(bytes)),
            size_bytes: bytes.len() as i64,
        };
        let missing_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(b"missing-bytes")),
            size_bytes: 40 * 1024 * 1024,
        };
        let key = blob_key(&digest_key(&present_digest).expect("digest key should build"));
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
                digests: vec![present_digest, missing_digest],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("a batch larger than the budget should be admitted up to the budget");

        let codes: Vec<_> = response
            .get_ref()
            .responses
            .iter()
            .map(|response| response.status.as_ref().map(|status| status.code))
            .collect();
        assert_eq!(codes, vec![Some(0), Some(tonic::Code::NotFound as i32)]);
        assert_eq!(response.get_ref().responses[0].data, bytes);
        assert_materialization_metrics(&context, 0, 0, 0);
    }

    #[tokio::test]
    async fn cas_batch_reads_beyond_one_requests_budget_are_not_counted_as_pool_sheds() {
        let context = test_context(|config| {
            config.memory_soft_limit_bytes = 32 * 1024 * 1024;
            config.memory_hard_limit_bytes = 64 * 1024 * 1024;
        })
        .await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let budget_bytes = context.state.memory.reapi_response_budget_bytes();
        let blob_bytes = 1024 * 1024;
        let blob_count = budget_bytes / blob_bytes + 4;
        let mut digests = Vec::with_capacity(blob_count);
        for index in 0..blob_count {
            let mut bytes = vec![b'x'; blob_bytes];
            bytes[..8].copy_from_slice(&(index as u64).to_le_bytes());
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
            digests.push(digest);
        }

        let response = service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                digests,
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("batch read should return per-digest status");

        let refused = response
            .get_ref()
            .responses
            .iter()
            .filter(|response| {
                response.status.as_ref().map(|status| status.code)
                    == Some(tonic::Code::ResourceExhausted as i32)
            })
            .count();
        assert_eq!(refused, 4);
        assert_materialization_metrics(&context, 0, 4, 0);
    }

    #[tokio::test]
    async fn a_third_concurrent_batch_read_waits_for_the_budget_instead_of_shedding() {
        let context = test_context(|config| {
            config.memory_soft_limit_bytes = 64 * 1024 * 1024;
            config.memory_hard_limit_bytes = 96 * 1024 * 1024;
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
        let bytes = vec![b'b'; 8 * 1024 * 1024];
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

        // Each holder drops its response inside the task, which is where the
        // reservation is released -- the permit rides the response, so a task
        // that parks a `Response` in its JoinHandle would hold the pool for the
        // whole test rather than for the read.
        let read_and_release = |service: ReapiService, digest: reapi::Digest| async move {
            let response = service
                .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                    instance_name: DEFAULT_INSTANCE_NAME.into(),
                    digests: vec![digest],
                    digest_function: reapi::digest_function::Value::Sha256 as i32,
                    ..Default::default()
                }))
                .await
                .expect("concurrent read should succeed");
            let served = response.get_ref().responses[0].data.len();
            let code = response.get_ref().responses[0]
                .status
                .as_ref()
                .map(|status| status.code);
            (code, served)
        };
        let first = tokio::spawn(read_and_release(first_service, digest.clone()));
        let second = tokio::spawn(read_and_release(second_service, digest.clone()));

        tokio::time::sleep(Duration::from_millis(50)).await;

        // The pool is full and the two holders release in ~250ms. Before, this
        // third read was answered RESOURCE_EXHAUSTED on the spot and the blob
        // became a cache miss the client refetched. It now waits out the
        // contention and serves, which is what the pool being *momentarily* full
        // should cost: latency, not a miss.
        let waited_from = Instant::now();
        let third = third_service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                digests: vec![digest.clone()],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("third request should be served after waiting");
        let waited = waited_from.elapsed();

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
            Some(0)
        );
        assert_eq!(third.get_ref().responses[0].data, bytes);
        assert!(
            waited >= Duration::from_millis(100),
            "the third read should have queued behind the holders, waited {waited:?}"
        );

        for handle in [first, second] {
            let (code, served) = handle.await.expect("concurrent read task should join");
            assert_eq!(code, Some(0));
            assert_eq!(served, bytes.len());
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
        assert_materialization_metrics(&context, 1, 0, 0);
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
        assert_materialization_metrics(&context, 0, 1, 0);
    }

    fn assert_materialization_metrics(
        context: &TestContext,
        pool_sheds: u64,
        request_budget_sheds: u64,
        fallbacks: u64,
    ) {
        let rendered = context.state.metrics.render();
        for (series, expected) in [
            (
                "kura_capacity_sheds_total_total{kind=\"reapi_materialization\"}",
                pool_sheds,
            ),
            (
                "kura_capacity_sheds_total_total{kind=\"reapi_request_budget\"}",
                request_budget_sheds,
            ),
            (
                "kura_memory_actions_total_total{action=\"reapi_materialization_rejected\"}",
                pool_sheds + request_budget_sheds,
            ),
            ("kura_reapi_inline_fallbacks_total_total", fallbacks),
        ] {
            let value = rendered
                .lines()
                .find_map(|line| {
                    line.strip_prefix(series)
                        .and_then(|value| value.trim().parse::<u64>().ok())
                })
                .unwrap_or(0);
            assert_eq!(value, expected, "unexpected {series}");
        }
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
        assert_materialization_metrics(&context, 0, 0, 0);
    }

    #[tokio::test]
    async fn wildcard_inline_limit_preserves_small_and_explicit_outputs() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let small = b"small".to_vec();
        let large = vec![b'x'; 4096];
        let small_digest = persist_output_file_blob(&context, &small).await;
        let large_digest = persist_output_file_blob(&context, &large).await;
        let action = persist_action_result_with_outputs(
            &context,
            vec![
                reapi::OutputFile {
                    path: "small".into(),
                    digest: Some(small_digest),
                    ..Default::default()
                },
                reapi::OutputFile {
                    path: "large".into(),
                    digest: Some(large_digest),
                    ..Default::default()
                },
            ],
        )
        .await;
        for explicit in [false, true] {
            let mut hints = vec!["*".into(), "tuist-inline-max-bytes:1024".into()];
            if explicit {
                hints.push("large".into());
            }
            let response = service
                .get_action_result(Request::new(reapi::GetActionResultRequest {
                    instance_name: DEFAULT_INSTANCE_NAME.into(),
                    action_digest: Some(action.clone()),
                    inline_output_files: hints,
                    ..Default::default()
                }))
                .await
                .unwrap()
                .into_inner();
            assert_eq!(response.output_files[0].contents, small);
            assert_eq!(
                response.output_files[1].contents,
                if explicit { large.clone() } else { Vec::new() }
            );
        }
        assert_materialization_metrics(&context, 0, 0, 0);
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
                    digest: Some(large_digest.clone()),
                    ..Default::default()
                },
                reapi::OutputFile {
                    path: "another-large".into(),
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
        assert!(output_files[1].contents.is_empty());
        assert_eq!(output_files[2].contents, small_bytes);
        assert_materialization_metrics(&context, 0, 0, 2);
    }

    #[tokio::test]
    async fn wildcard_inline_pool_contention_counts_fallbacks_separately_from_required_reads() {
        let context = test_context(|config| {
            config.memory_soft_limit_bytes = 32 * 1024 * 1024;
            config.memory_hard_limit_bytes = 64 * 1024 * 1024;
        })
        .await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let bytes = vec![b'x'; 2 * 1024 * 1024];
        let digest = persist_output_file_blob(&context, &bytes).await;
        let action = persist_action_result_with_outputs(
            &context,
            vec![reapi::OutputFile {
                path: "output".into(),
                digest: Some(digest.clone()),
                ..Default::default()
            }],
        )
        .await;
        // Leave room for the action result but not the optional output file.
        let limit = context.state.memory.reapi_materialization_limit_bytes();
        let first = context
            .state
            .memory
            .try_acquire_reapi_materialization(limit)
            .unwrap();
        let second = context
            .state
            .memory
            .try_acquire_reapi_materialization(limit - 1024 * 1024)
            .unwrap();
        let request = |paths| {
            Request::new(reapi::GetActionResultRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                action_digest: Some(action.clone()),
                inline_output_files: paths,
                ..Default::default()
            })
        };

        let response = service
            .get_action_result(request(vec!["*".into()]))
            .await
            .unwrap();
        assert!(response.get_ref().output_files[0].contents.is_empty());
        assert_materialization_metrics(&context, 0, 0, 1);
        drop(response);

        let error = service
            .get_action_result(request(vec!["*".into(), "output".into()]))
            .await
            .unwrap_err();
        assert_eq!(error.code(), tonic::Code::ResourceExhausted);
        assert_materialization_metrics(&context, 1, 0, 1);
        drop((first, second));

        let response = service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                digests: vec![digest],
                ..Default::default()
            }))
            .await
            .unwrap();
        assert_eq!(response.get_ref().responses[0].data, bytes);
        assert_eq!(
            response.get_ref().responses[0]
                .status
                .as_ref()
                .unwrap()
                .code,
            0
        );
        assert_materialization_metrics(&context, 1, 0, 1);
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
        assert_materialization_metrics(&context, 0, 1, 0);
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
        metadata.insert("authorization", "Bearer credential".parse().unwrap());
        metadata.insert("x-unrelated", "not copied".parse().unwrap());

        // The authorization path (grpc_request_context) and the billing path
        // (usage_tenant_id) read the same value.
        assert_eq!(tenant_id_from_metadata(&metadata).as_deref(), Some("acme"));
        assert_eq!(usage_tenant_id(&metadata, "node-tenant"), "acme");

        let spec = GrpcRequestSpec {
            operation: "artifact.read",
            namespace_id: Some("ios"),
        };
        let context = grpc_request_context("acme", &spec, &metadata);
        assert_eq!(context.tenant_id.as_deref(), Some("acme"));
        assert_eq!(context.authorization.as_deref(), Some("Bearer credential"));
        assert!(context.headers.is_empty());
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
        for (hint, expected) in [
            (None, "reapi"),
            (Some("module"), "module"),
            (Some("unbounded-kind"), "reapi"),
        ] {
            check_cas_batch_usage(hint, expected).await;
        }
    }

    async fn check_cas_batch_usage(hint: Option<&str>, expected: &str) {
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
            if let Some(hint) = hint {
                update
                    .metadata_mut()
                    .insert("x-tuist-artifact-kind", hint.parse().unwrap());
            }
            add_direct_write_admission(&context.state, &mut update, CAS_BATCH_UPDATE_DECODE_COPIES);
            update
        };

        // First upload stores both blobs; the second finds both already present
        // and must not bill them again.
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
        if let Some(hint) = hint {
            read.metadata_mut()
                .insert("x-tuist-artifact-kind", hint.parse().unwrap());
        }
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
        assert_eq!(upload.artifact_kind, expected);
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
        assert_eq!(download.artifact_kind, expected);
        // One batch read of two blobs is one request carrying both blobs' bytes.
        assert_eq!(download.bytes, total_bytes);
        assert_eq!(download.request_count, 1);
    }

    // A byte-identical re-publish inside the damping window stores nothing,
    // bumps no version and writes no replication feed row. Counting it as an
    // ordinary successful write made kura_artifact_writes_total incomparable
    // with every counter that only sees applied changes -- the gap reads like
    // replication dropping entries -- and inflated write_bytes with bytes that
    // never landed. It gets its own result label and no bytes.
    #[tokio::test]
    async fn damped_action_cache_refresh_counts_separately_from_an_applied_write() {
        let context = test_context(|config| {
            config.usage = Some(test_usage_config());
        })
        .await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };

        // Carry a payload: an all-default ActionResult encodes to zero bytes,
        // and the byte assertions below would then match the pre-created,
        // still-zero `result="ok"` series no matter what this path recorded.
        let action_result = reapi::ActionResult {
            stdout_raw: b"damped action stdout".to_vec(),
            exit_code: 3,
            ..Default::default()
        };
        let encoded_bytes = action_result.encode_to_vec().len() as u64;
        let action_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(b"damped-action")),
            size_bytes: "damped-action".len() as i64,
        };

        let publish = |action_result: reapi::ActionResult| {
            let context = &context;
            let service = &service;
            let action_digest = action_digest.clone();
            async move {
                let mut update = Request::new(reapi::UpdateActionResultRequest {
                    instance_name: "ios".into(),
                    action_digest: Some(action_digest),
                    action_result: Some(action_result),
                    digest_function: reapi::digest_function::Value::Sha256 as i32,
                    ..Default::default()
                });
                update
                    .metadata_mut()
                    .insert("x-tuist-account-handle", "acme".parse().unwrap());
                add_direct_write_admission(
                    &context.state,
                    &mut update,
                    ACTION_CACHE_UPDATE_DECODE_COPIES,
                );
                service
                    .update_action_result(update)
                    .await
                    .expect("update action result should succeed");
            }
        };

        publish(action_result.clone()).await;
        let key = action_cache_key(&digest_key(&action_digest).expect("digest key should build"));
        let first = context
            .state
            .store
            .manifest_for_key(ArtifactProducer::Reapi, "ios", &key)
            .expect("manifest lookup should succeed")
            .expect("the first publish should store the entry");

        publish(action_result).await;
        let second = context
            .state
            .store
            .manifest_for_key(ArtifactProducer::Reapi, "ios", &key)
            .expect("manifest lookup should succeed")
            .expect("the damped refresh should leave the entry in place");
        assert_eq!(
            first.version_ms, second.version_ms,
            "the refresh must be damped for this test to mean anything"
        );

        let metrics = context.state.metrics.render();
        let counter = |result: &str| {
            metrics
                .lines()
                .find(|line| {
                    line.starts_with("kura_artifact_writes_total")
                        && line.contains("producer=\"reapi\"")
                        && line.contains(&format!("result=\"{result}\""))
                })
                .and_then(|line| line.rsplit(' ').next())
                .and_then(|value| value.parse::<u64>().ok())
                .unwrap_or_default()
        };
        assert_eq!(counter("ok"), 1, "only the applied write counts as ok");
        assert_eq!(counter("damped"), 1, "the damped refresh is counted apart");

        let write_bytes = metrics
            .lines()
            .filter(|line| line.starts_with("kura_artifact_write_bytes_total"))
            .filter(|line| line.contains("producer=\"reapi\""))
            .collect::<Vec<_>>();
        assert!(
            !write_bytes.iter().any(|line| line.contains("damped")),
            "a damped refresh stores nothing, so it books no write bytes: {write_bytes:?}"
        );
        assert!(
            write_bytes.iter().any(|line| line.contains("result=\"ok\"")
                && line.ends_with(&format!(" {encoded_bytes}"))),
            "write bytes should hold only the applied write's payload: {write_bytes:?}"
        );

        // Billing already respected the flag; assert it stays that way, so the
        // metric and the rollup keep telling the same story.
        let uploads = context
            .state
            .usage
            .as_ref()
            .expect("usage should be enabled")
            .current_rollups_for_tests()
            .into_iter()
            .filter(|rollup| rollup.operation == "upload")
            .collect::<Vec<_>>();
        assert_eq!(uploads.len(), 1, "one rollup for the one applied write");
        assert_eq!(uploads[0].request_count, 1);
        assert_eq!(uploads[0].bytes, encoded_bytes);
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
        add_direct_write_admission(
            &context.state,
            &mut update,
            ACTION_CACHE_UPDATE_DECODE_COPIES,
        );
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

    // An action result larger than the inline replication ceiling can never be
    // fetched by a peer, so we reject the write with a non-retriable status
    // instead of storing an entry that would strand on this node.
    #[tokio::test]
    async fn update_action_result_rejects_oversized_action_result() {
        let context = test_context(|config| {
            config.usage = Some(test_usage_config());
        })
        .await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };

        let action_result = reapi::ActionResult {
            stdout_raw: vec![0u8; MAX_INLINE_REPLICATION_BODY_BYTES as usize + 1],
            ..Default::default()
        };
        assert!(
            action_result.encode_to_vec().len() as u64 > MAX_INLINE_REPLICATION_BODY_BYTES,
            "test fixture must exceed the inline replication ceiling"
        );
        let action_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(b"oversized-action")),
            size_bytes: "oversized-action".len() as i64,
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
        add_direct_write_admission(
            &context.state,
            &mut update,
            ACTION_CACHE_UPDATE_DECODE_COPIES,
        );
        let status = service
            .update_action_result(update)
            .await
            .expect_err("oversized action result should be rejected");
        assert_eq!(status.code(), tonic::Code::FailedPrecondition);

        // Nothing was stored.
        let key = action_cache_key(&digest_key(&action_digest).expect("digest key should build"));
        assert!(
            context
                .state
                .store
                .manifest_for_key(ArtifactProducer::Reapi, "ios", &key)
                .expect("manifest lookup should succeed")
                .is_none(),
            "rejected action result must not be persisted"
        );

        // The rejection is counted, but as a failed write it books no bytes and
        // bills nothing. The size check returns before the upload rollup.
        let metrics = context.state.metrics.render();
        assert!(
            metrics
                .lines()
                .any(|line| line.contains("kura_artifact_writes_total")
                    && line.contains("too_large")),
            "rejection should increment the too_large write counter"
        );
        assert!(
            !metrics
                .lines()
                .any(|line| line.contains("kura_artifact_write_bytes_total")
                    && line.contains("too_large")),
            "a rejected write must not add to write-bytes throughput"
        );
        assert!(
            context
                .state
                .usage
                .as_ref()
                .expect("usage should be enabled")
                .current_rollups_for_tests()
                .is_empty(),
            "a rejected write must not be billed"
        );
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

    #[test]
    fn zstd_batch_item_decoder_rejects_bombs_and_truncated_payloads() {
        // A payload whose decompressed length exceeds the declared size is
        // refused with InvalidArgument, without allocating past the cap.
        let payload = zstd::stream::encode_all(vec![0xAB; 1024].as_slice(), 3)
            .expect("bomb source should compress");
        let bomb = decompress_zstd_batch_item(&payload, 8).expect_err("bomb must be rejected");
        assert_eq!(bomb.code(), tonic::Code::InvalidArgument);
        assert!(
            bomb.message().contains("declared blob size"),
            "message should name the ceiling that refused it: {bomb:?}"
        );

        // A truncated zstd payload trips the decoder mid-frame and comes back
        // as InvalidArgument, not Internal.
        let truncated = &payload[..payload.len() / 2];
        let error = decompress_zstd_batch_item(truncated, 1024)
            .expect_err("a truncated frame must not decode");
        assert_eq!(error.code(), tonic::Code::InvalidArgument);

        // A valid round-trip returns exactly the original bytes.
        let source = b"hello, zstd batch update".to_vec();
        let compressed = zstd::stream::encode_all(source.as_slice(), 3).unwrap();
        let decoded =
            decompress_zstd_batch_item(&compressed, source.len() as i64).expect("round-trip");
        assert_eq!(decoded, source);
    }

    #[test]
    fn bounded_zstd_decoder_sink_rejects_bytes_past_its_budget() {
        let mut sink = BoundedZstdDecoderSink {
            remaining: 4,
            ..Default::default()
        };
        std::io::Write::write_all(&mut sink, &[1, 2, 3, 4])
            .expect("bytes inside the budget should be accepted");
        assert_eq!(sink.bytes, vec![1, 2, 3, 4]);
        assert_eq!(sink.remaining, 0);
        let overflow = std::io::Write::write_all(&mut sink, &[5]);
        assert!(overflow.is_err(), "a byte past the budget must be refused");
    }

    #[test]
    fn compressed_wire_ceiling_grows_with_declared_size() {
        // A large legitimate compressed encoding of `declared` uncompressed
        // bytes is always shorter than or close to the source size — the
        // ceiling should sit comfortably above it and grow with `declared`.
        let small = compressed_wire_ceiling(1);
        let large = compressed_wire_ceiling(1024 * 1024);
        assert!(small < large, "ceiling must scale with declared size");
        assert!(
            compressed_wire_ceiling(0) >= 64 * 1024,
            "even a zero-byte blob keeps the slack for framing overhead",
        );
    }

    #[test]
    fn zstd_batch_item_decoder_does_not_preallocate_to_the_declared_size() {
        // A small compressed payload that declares a huge uncompressed size
        // used to allocate the full declaration up front and then zero-fill
        // it, so a 17-byte item declaring 2 GiB would move RSS by 2 GiB
        // regardless of how many bytes actually decoded. The streaming
        // version grows the decoded Vec with actually-decoded bytes and
        // stops feeding the decoder once the declared cap is reached: the
        // returned Vec's capacity must be within a small factor of the
        // decoded length, not the declaration.
        let source = b"actual eight bytes: 42".to_vec();
        let compressed = zstd::stream::encode_all(source.as_slice(), 3).unwrap();
        let declared_gib: i64 = 2 * 1024 * 1024 * 1024;
        let decoded = decompress_zstd_batch_item(&compressed, declared_gib)
            .expect("a small payload with a huge declared size must decode without OOM");
        assert_eq!(decoded, source);
        assert!(
            decoded.capacity() < 16 * 1024 * 1024,
            "capacity must track decoded length ({} bytes), not the declaration ({}); got capacity {}",
            decoded.len(),
            declared_gib,
            decoded.capacity(),
        );
    }

    #[test]
    fn zstd_batch_read_compression_falls_back_to_identity_when_it_would_grow() {
        // A short payload never shrinks below the ~10-byte zstd frame overhead,
        // so the helper must hand back identity.
        let short = b"hi".to_vec();
        let (payload, compressor) = maybe_compress_zstd_batch_response(short.clone());
        assert_eq!(payload, short);
        assert_eq!(compressor, 0);

        // A highly compressible payload shrinks and comes back with ZSTD (=1).
        let long = vec![0xEEu8; 4096];
        let (payload, compressor) = maybe_compress_zstd_batch_response(long.clone());
        assert_eq!(compressor, reapi::compressor::Value::Zstd as i32);
        assert!(payload.len() < long.len(), "compression should shrink");
        let decoded = zstd::stream::decode_all(payload.as_slice()).expect("decompress");
        assert_eq!(decoded, long);
    }

    #[tokio::test]
    async fn capabilities_advertise_zstd_for_bytestream_and_batch_update() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        let capabilities = service
            .get_capabilities(Request::new(reapi::GetCapabilitiesRequest {
                instance_name: "ios".into(),
            }))
            .await
            .expect("capabilities should load")
            .into_inner()
            .cache_capabilities
            .expect("cache capabilities should be present");
        let zstd = reapi::compressor::Value::Zstd as i32;
        assert!(
            capabilities.supported_compressors.contains(&zstd),
            "supported_compressors should include ZSTD"
        );
        assert!(
            capabilities
                .supported_batch_update_compressors
                .contains(&zstd),
            "supported_batch_update_compressors should include ZSTD"
        );
    }

    #[tokio::test]
    async fn cas_batch_round_trips_a_zstd_compressed_blob() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            snapshot_cache: Default::default(),
            state: context.state.clone(),
        };
        // A highly redundant payload so the wire size shrinks visibly; the
        // test would still be correct at any size, but exercising the
        // compression benefit keeps the fallback branch honest.
        let blob = vec![0xC0u8; 8_192];
        let digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&blob)),
            size_bytes: blob.len() as i64,
        };
        let compressed = zstd::stream::encode_all(blob.as_slice(), 3).expect("encode");
        assert!(
            compressed.len() < blob.len(),
            "wire payload should shrink for a redundant blob"
        );

        let mut update = Request::new(reapi::BatchUpdateBlobsRequest {
            instance_name: "ios".into(),
            requests: vec![reapi::batch_update_blobs_request::Request {
                digest: Some(digest.clone()),
                data: compressed,
                compressor: reapi::compressor::Value::Zstd as i32,
            }],
            digest_function: reapi::digest_function::Value::Sha256 as i32,
        });
        add_direct_write_admission(&context.state, &mut update, CAS_BATCH_UPDATE_DECODE_COPIES);
        let update_response = service
            .batch_update_blobs(update)
            .await
            .expect("compressed batch update should succeed")
            .into_inner();
        assert_eq!(update_response.responses.len(), 1);
        assert_eq!(
            update_response.responses[0].status.as_ref().unwrap().code,
            0
        );

        let read = service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: "ios".into(),
                digests: vec![digest.clone()],
                acceptable_compressors: vec![reapi::compressor::Value::Zstd as i32],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
            }))
            .await
            .expect("batch read with zstd should succeed")
            .into_inner();
        assert_eq!(read.responses.len(), 1);
        let item = &read.responses[0];
        assert_eq!(item.status.as_ref().unwrap().code, 0);
        assert_eq!(item.compressor, reapi::compressor::Value::Zstd as i32);
        let decoded = zstd::stream::decode_all(item.data.as_slice()).expect("decode response");
        assert_eq!(decoded, blob, "the compressed response must round-trip");

        // A client that does not advertise zstd still gets identity bytes.
        let plain = service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: "ios".into(),
                digests: vec![digest],
                acceptable_compressors: Vec::new(),
                digest_function: reapi::digest_function::Value::Sha256 as i32,
            }))
            .await
            .expect("plain batch read should still succeed")
            .into_inner();
        assert_eq!(plain.responses[0].compressor, 0);
        assert_eq!(plain.responses[0].data, blob);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn bytestream_round_trips_a_zstd_compressed_blob() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

        let context = test_context(|_| {}).await;
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let address = listener.local_addr().expect("listener address");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let state = context.state.clone();
        let server = tokio::spawn(async move {
            serve_routes(listener, state, async move {
                let _ = shutdown_rx.await;
            })
            .await;
        });
        let mut client = None;
        let endpoint = format!("http://{address}");
        for _ in 0..50 {
            match tonic::transport::Endpoint::from_shared(endpoint.clone())
                .expect("valid endpoint")
                .connect()
                .await
            {
                Ok(channel) => {
                    client = Some(ByteStreamClient::new(channel));
                    break;
                }
                Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
            }
        }
        let mut client = client.expect("client should connect to test server");

        let blob = vec![0x5Au8; 32_768];
        let digest_hash = hex::encode(Sha256::digest(&blob));
        let uncompressed_size = blob.len() as i64;
        let compressed = zstd::stream::encode_all(blob.as_slice(), 3).expect("encode");
        let write_resource = format!(
            "ios/uploads/{}/compressed-blobs/zstd/{}/{}",
            uuid::Uuid::new_v4(),
            digest_hash,
            uncompressed_size,
        );
        let write_requests: Vec<bytestream::WriteRequest> = {
            let mut out = Vec::new();
            let mut offset = 0_usize;
            for (index, chunk) in compressed.chunks(4096).enumerate() {
                let finish = offset + chunk.len() == compressed.len();
                out.push(bytestream::WriteRequest {
                    resource_name: if index == 0 {
                        write_resource.clone()
                    } else {
                        String::new()
                    },
                    write_offset: offset as i64,
                    finish_write: finish,
                    data: chunk.to_vec(),
                });
                offset += chunk.len();
            }
            out
        };
        let write_response = client
            .write(tokio_stream::iter(write_requests))
            .await
            .expect("compressed bytestream write should succeed")
            .into_inner();
        assert_eq!(write_response.committed_size as usize, compressed.len());

        let read_resource = format!(
            "ios/compressed-blobs/zstd/{}/{}",
            digest_hash, uncompressed_size
        );
        let mut stream = client
            .read(Request::new(bytestream::ReadRequest {
                resource_name: read_resource,
                read_offset: 0,
                read_limit: 0,
            }))
            .await
            .expect("compressed bytestream read should succeed")
            .into_inner();
        let mut received = Vec::new();
        while let Some(response) = stream.next().await {
            received.extend(response.expect("stream response").data);
        }
        let decoded = zstd::stream::decode_all(received.as_slice()).expect("decode stream");
        assert_eq!(decoded, blob, "the compressed read must round-trip");

        // REAPI defines read_offset on a compressed-blobs resource as the
        // offset in the *uncompressed* form; Kura seeks the uncompressed
        // reader and starts the encoder there, so a partial compressed read
        // decodes to the tail of the original blob.
        let mut tail_stream = client
            .read(Request::new(bytestream::ReadRequest {
                resource_name: format!(
                    "ios/compressed-blobs/zstd/{}/{}",
                    digest_hash, uncompressed_size
                ),
                read_offset: 1,
                read_limit: 0,
            }))
            .await
            .expect("a compressed read with a non-zero offset must succeed")
            .into_inner();
        let mut tail_bytes = Vec::new();
        while let Some(response) = tail_stream.next().await {
            tail_bytes.extend(response.expect("tail stream response").data);
        }
        let tail_decoded = zstd::stream::decode_all(tail_bytes.as_slice()).expect("tail decode");
        assert_eq!(
            tail_decoded,
            blob[1..],
            "a compressed read with read_offset=1 must decode to the blob's tail",
        );

        // The spec requires INVALID_ARGUMENT for a non-zero read_limit on a
        // compressed-blobs resource; UNIMPLEMENTED would turn into a hard
        // IOException on Bazel instead of the retryable client error the
        // spec expects.
        let limit_error = client
            .read(Request::new(bytestream::ReadRequest {
                resource_name: format!(
                    "ios/compressed-blobs/zstd/{}/{}",
                    digest_hash, uncompressed_size
                ),
                read_offset: 0,
                read_limit: 1,
            }))
            .await
            .expect_err("read_limit is not supported on compressed-blobs");
        assert_eq!(limit_error.code(), tonic::Code::InvalidArgument);

        let _ = shutdown_tx.send(());
        let _ = server.await;
    }

    async fn connect_test_routes(
        state: SharedState,
    ) -> (
        tonic::transport::Channel,
        tokio::sync::oneshot::Sender<()>,
        tokio::task::JoinHandle<()>,
    ) {
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let addr = listener.local_addr().expect("listener addr");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let server = tokio::spawn(serve_routes(listener, state, async move {
            let _ = shutdown_rx.await;
        }));
        let channel = tonic::transport::Endpoint::from_shared(format!("http://{addr}"))
            .expect("valid endpoint")
            .connect_lazy();
        (channel, shutdown_tx, server)
    }

    fn digest_of(bytes: &[u8]) -> reapi::Digest {
        reapi::Digest {
            hash: hex::encode(Sha256::digest(bytes)),
            size_bytes: bytes.len() as i64,
        }
    }

    // Compressed BatchUpdateBlobs items admit their declared decoded size
    // before decoding. An item no request may materialize is refused alone,
    // before its payload is decoded, while every other item keeps its own
    // status in request order and every permit is returned afterwards.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn batch_update_admits_decoded_size_per_item_in_request_order() {
        use reapi::content_addressable_storage_client::ContentAddressableStorageClient;

        let context = test_context(|_| {}).await;
        let (channel, shutdown_tx, server) = connect_test_routes(context.state.clone()).await;
        let mut client = ContentAddressableStorageClient::new(channel);
        let memory = &context.state.memory;
        let reserved_before = memory.transient_reserved_bytes();

        let identity = b"identity batch blob".to_vec();
        let compressed = vec![0x42_u8; 64 * 1024];
        let encoded = zstd::stream::encode_all(compressed.as_slice(), 3).expect("encode");
        let unadmittable = reapi::Digest {
            hash: hex::encode(Sha256::digest(b"never decoded")),
            size_bytes: memory.reapi_materialization_limit_bytes() as i64 + 1,
        };
        let mut mismatched = digest_of(&compressed);
        mismatched.hash = hex::encode(Sha256::digest(b"other content"));
        let zstd = reapi::compressor::Value::Zstd as i32;
        let item = |digest: Option<reapi::Digest>, data: &[u8], compressor: i32| {
            reapi::batch_update_blobs_request::Request {
                digest,
                data: data.to_vec(),
                compressor,
            }
        };
        let response = client
            .batch_update_blobs(reapi::BatchUpdateBlobsRequest {
                instance_name: "ios".into(),
                requests: vec![
                    item(Some(digest_of(&identity)), &identity, 0),
                    item(Some(unadmittable.clone()), &encoded, zstd),
                    item(None, &identity, 0),
                    item(Some(digest_of(&compressed)), &encoded, zstd),
                    item(Some(mismatched.clone()), &encoded, zstd),
                    item(Some(digest_of(&identity)), &identity, 99),
                    item(Some(digest_of(&compressed)), &encoded, zstd),
                ],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
            })
            .await
            .expect("batch update should answer per item")
            .into_inner();
        let outcomes: Vec<_> = response
            .responses
            .iter()
            .map(|response| {
                (
                    response.digest.as_ref().map(|digest| digest.hash.clone()),
                    response.status.as_ref().map(|status| status.code),
                )
            })
            .collect();
        assert_eq!(
            outcomes,
            vec![
                (Some(digest_of(&identity).hash), Some(0)),
                (
                    Some(unadmittable.hash),
                    Some(tonic::Code::ResourceExhausted as i32)
                ),
                (None, Some(tonic::Code::InvalidArgument as i32)),
                (Some(digest_of(&compressed).hash), Some(0)),
                (Some(mismatched.hash), Some(tonic::Code::Internal as i32)),
                (
                    Some(digest_of(&identity).hash),
                    Some(tonic::Code::Unimplemented as i32)
                ),
                (Some(digest_of(&compressed).hash), Some(0)),
            ]
        );
        for blob in [&identity, &compressed] {
            let key = blob_key(&digest_key(&digest_of(blob)).expect("digest key"));
            assert!(
                context
                    .state
                    .store
                    .manifest_for_key(ArtifactProducer::Reapi, "ios", &key)
                    .expect("manifest lookup")
                    .is_some()
            );
        }
        assert!(
            context
                .state
                .metrics
                .render()
                .contains(REAPI_MATERIALIZATION_REJECTED_ACTION)
        );
        tokio::time::timeout(Duration::from_secs(5), async {
            while memory.transient_reserved_bytes() != reserved_before {
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await
        .expect("every decode permit should be released with the response");

        let _ = shutdown_tx.send(());
        let _ = server.await;
    }

    #[test]
    fn zstd_batch_item_decoder_never_reserves_past_the_declared_size() {
        let source = vec![0x17_u8; 3 * 64 * 1024 + 5];
        let compressed = zstd::stream::encode_all(source.as_slice(), 3).unwrap();
        let decoded = decompress_zstd_batch_item(&compressed, source.len() as i64)
            .expect("a payload of exactly the declared size decodes");
        assert_eq!(decoded, source);
        assert!(
            decoded.capacity() <= source.len(),
            "capacity {} must stay within the admitted {} bytes",
            decoded.capacity(),
            source.len()
        );
    }

    async fn read_bytestream(
        client: &mut bytestream::byte_stream_client::ByteStreamClient<tonic::transport::Channel>,
        resource_name: &str,
        read_offset: i64,
        read_limit: i64,
    ) -> Vec<u8> {
        let mut stream = client
            .read(bytestream::ReadRequest {
                resource_name: resource_name.to_owned(),
                read_offset,
                read_limit,
            })
            .await
            .expect("blob should be readable")
            .into_inner();
        let mut received = Vec::new();
        while let Some(chunk) = stream.message().await.expect("read chunk") {
            received.extend_from_slice(&chunk.data);
        }
        received
    }

    // A ranged identity read streams only its range: it must not map, and
    // charge the mapped pool for, the whole blob. Full reads may map.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn bytestream_ranged_identity_reads_stream_only_their_range() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

        let context = test_context(|_| {}).await;
        let (channel, shutdown_tx, server) = connect_test_routes(context.state.clone()).await;
        let mut client = ByteStreamClient::new(channel);
        let blob: Vec<u8> = (0..200_000_u32)
            .map(|byte| byte.wrapping_mul(17) as u8)
            .collect();
        let hash = hex::encode(Sha256::digest(&blob));
        client
            .write(tokio_stream::iter(chunked_write_requests(
                &format!("uploads/ranged/blobs/{hash}/{}", blob.len()),
                &blob,
                true,
            )))
            .await
            .expect("upload should persist");
        let resource = format!("blobs/{hash}/{}", blob.len());

        assert_eq!(
            read_bytestream(&mut client, &resource, 5, 100).await,
            blob[5..105]
        );
        assert_eq!(
            read_bytestream(&mut client, &resource, 150_000, 0).await,
            blob[150_000..]
        );
        assert_eq!(
            read_bytestream(&mut client, &resource, 0, 1_000).await,
            blob[..1_000]
        );
        assert!(
            !context.state.metrics.render().contains("path=\"mmap\""),
            "ranged reads must take the streaming reader"
        );
        assert_eq!(read_bytestream(&mut client, &resource, 0, 0).await, blob);

        let _ = shutdown_tx.send(());
        let _ = server.await;
    }
}
