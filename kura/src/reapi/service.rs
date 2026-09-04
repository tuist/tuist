use std::{
    collections::BTreeMap,
    pin::Pin,
    sync::Arc,
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
use super::{admission::*, snapshot::*};

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
    io::is_fd_pool_exhausted_error,
    replication::replication_targets,
    state::SharedState,
    store::{
        ArtifactReader, RefreshTrigger, SEGMENT_COPY_BUFFER_BYTES, StagedArtifactPath,
        is_outbox_full_error, try_allocate_exact_vec,
    },
    utils::{
        TempFileCleanup, action_cache_key, blob_key, drop_staging_cache_range, temp_file_path,
    },
};

const DEFAULT_INSTANCE_NAME: &str = "default";
// ByteStream downloads can keep the response vector and Tonic's encoded frame
// live while Hyper retains up to its separately capped per-stream send buffer.
// The reader fills the response vector directly, so there is no intermediate
// reader buffer.
const BYTESTREAM_RESPONSE_LIVE_CHUNK_COUNT: usize = 2;
const REAPI_MATERIALIZATION_REJECTED_ACTION: &str = "reapi_materialization_rejected";
// Abort a ByteStream upload only when no chunk arrives within this window. The
// timer resets on every chunk received, so an actively transferring upload is
// never interrupted, while a stalled or vanished client is reclaimed promptly.
const REAPI_WRITE_STALL_TIMEOUT: Duration = Duration::from_secs(60);
const REAPI_REQUEST_METADATA_HEADER: &str = "build.bazel.remote.execution.v2.requestmetadata-bin";
#[derive(Clone)]
pub struct ReapiService {
    state: SharedState,
    // Per-namespace action-cache snapshot indexes and their in-flight
    // builds, shared across the service clones tonic hands each server.
    snapshot_cache: std::sync::Arc<SnapshotCache>,
}

#[derive(Clone, Copy)]
struct GrpcRequestSpec<'a> {
    operation: &'a str,
    namespace_id: Option<&'a str>,
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
    let service = ReapiService {
        snapshot_cache: state.snapshot_cache.clone(),
        state: state.clone(),
    };
    spawn_snapshot_refresh_task(service.clone());
    let (capabilities, action_cache, cas, byte_stream, build_events) = reapi_servers(service);
    tonic::service::Routes::new(capabilities)
        .add_service(action_cache)
        .add_service(cas)
        .add_service(byte_stream)
        .add_service(build_events)
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

impl ReapiService {
    async fn authorize_request<T>(
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
    async fn authorize_metadata(
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
        let context = grpc_request_context(&self.state.config.tenant_id, &spec, metadata);
        match auth.evaluate_access(&context).await {
            AccessDecision::Allow => Ok(()),
            AccessDecision::Deny(deny) => {
                Err(grpc_status_from_http_status(deny.status, &deny.message))
            }
        }
    }

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
                self.state
                    .metrics
                    .record_memory_action(REAPI_MATERIALIZATION_REJECTED_ACTION);
                self.state
                    .metrics
                    .record_capacity_shed(crate::metrics::shed_kind::REAPI_MATERIALIZATION);
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
        reapi_cache_event_context(metadata, namespace_id, &self.state.config.tenant_id)
    }

    fn record_reapi_cache_event_with_context(
        &self,
        context: Option<&Arc<ReapiCacheAnalyticsContext>>,
        observation: ReapiCacheObservation<'_>,
    ) {
        let (Some(analytics), Some(context)) = (self.state.analytics.as_ref(), context) else {
            return;
        };

        analytics.enqueue_reapi_cache_event(|| ReapiCacheAnalyticsEvent {
            context: Arc::clone(context),
            operation: observation.operation,
            outcome: observation.outcome,
            action_digest: observation.digest.to_owned(),
            size: observation.size,
            duration_ms: observation
                .duration
                .as_millis()
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
        let mut temp_file = None;
        let mut memory_payload = None;
        let mut resource_name = None::<String>;
        let mut resource = None::<BlobResource>;
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
                file_cache_policy =
                    memory_admission.try_configure_staging(parsed_resource.size_bytes)?;
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
                            .create_file(temp_path)
                            .await
                            .map_err(Status::internal)?,
                    );
                }
                resource = Some(parsed_resource);
                resource_name = Some(chunk.resource_name);
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
                if let Some(payload) = memory_payload.as_mut() {
                    payload.extend_from_slice(&chunk.data);
                    hasher.update(&chunk.data);
                    written = written.saturating_add(chunk.data.len() as u64);
                } else {
                    for data in chunk
                        .data
                        .chunks(FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES as usize)
                    {
                        let file = temp_file
                            .as_mut()
                            .expect("file-backed uploads initialize their staging file");
                        tokio::io::AsyncWriteExt::write_all(file, data)
                            .await
                            .map_err(|error| {
                                Status::internal(format!("failed to write temp blob: {error}"))
                            })?;
                        hasher.update(data);
                        written = written.saturating_add(data.len() as u64);
                        if file_cache_policy.should_drop(
                            self.state.memory.should_reclaim_file_cache(),
                            self.state.memory.transient_reserved_bytes(),
                        ) && written.saturating_sub(advised_through)
                            >= FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES
                        {
                            temp_file = Some(
                                drop_staging_cache_range(
                                    temp_file.take().expect(
                                        "file-backed uploads initialize their staging file",
                                    ),
                                    temp_path,
                                    advised_through,
                                    written - advised_through,
                                    &self.state.io,
                                )
                                .await
                                .map_err(Status::internal)?,
                            );
                            advised_through = written;
                        }
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
        if !digest_matches_hex(hasher.finalize().as_ref(), resource.hash()) {
            return Err(Status::invalid_argument(
                "uploaded blob digest did not match content",
            ));
        }

        // Flush a file-backed upload before the store opens that path on another
        // descriptor. Memory-backed uploads already expose their complete bytes.
        if let Some(mut file) = temp_file.take() {
            tokio::io::AsyncWriteExt::flush(&mut file)
                .await
                .map_err(|error| Status::internal(format!("failed to flush temp blob: {error}")))?;
            drop(file);
        }

        let targets = replication_targets(&self.state).await;
        // The persist reports `already_present` from under the store's
        // per-artifact write lock, which decides billing below: a re-uploaded
        // blob (retry, or a client that skips FindMissingBlobs) must not be
        // billed twice — matching the HTTP upload path's `artifact_exists`
        // short-circuit — and concurrent uploads of the same missing blob
        // resolve to exactly one billed writer.
        let persisted = if let Some(payload) = memory_payload.as_deref() {
            self.state
                .store
                .persist_admitted_artifact_from_bytes_and_enqueue(
                    ArtifactProducer::Reapi,
                    &resource.namespace_id,
                    &resource.key,
                    "application/octet-stream",
                    payload,
                    file_cache_policy,
                    &targets,
                )
                .await
        } else {
            self.state
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
        }
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

        let response = Response::new(bytestream::WriteResponse {
            committed_size: written as i64,
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
            let unchanged = indexes
                .get(&cache_key)
                .is_some_and(|index| index.built_at_generation == generation);
            if let Some(index) = indexes.get_mut(&cache_key)
                && (!index.entries.is_empty() || unchanged)
            {
                let stale = index.reconciled_at.elapsed() >= SNAPSHOT_RECONCILE_INTERVAL;
                index.last_used = Instant::now();
                let entries = index.entries.len();
                let mut snapshot = self.encode_snapshot(index, after)?;
                drop(indexes);
                self.cache_full_view(&cache_key, after, entries, &snapshot);
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
                .cloned();
            if let Some(cached) = cached {
                let permit = self
                    .state
                    .memory
                    .try_acquire_response_materialization(cached.len())
                    .map_err(|_| {
                        Status::resource_exhausted(
                            "action-cache snapshot serve declined under memory pressure",
                        )
                    })?;
                let _build = self.ensure_index_build(namespace_id, trunk, IndexBuildTrigger::Serve);
                return Ok(MaterializedSnapshot::new((*cached).clone(), permit));
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
        index.last_used = Instant::now();
        let entries = index.entries.len();
        let mut snapshot = self.encode_snapshot(index, after)?;
        drop(indexes);
        self.cache_full_view(&cache_key, after, entries, &snapshot);
        snapshot.retain_response_memory()?;
        Ok(snapshot)
    }

    /// Caches a full (`after == 0`) encoded view as the namespace's
    /// `served_full`, so a serve that lands while the index is out for a
    /// reconcile returns it instead of shedding to UNAVAILABLE. A delta is
    /// relative to a client's watermark and cannot be replayed, so it is not
    /// cached.
    fn cache_full_view(&self, cache_key: &str, after: u64, entries: usize, bytes: &[u8]) {
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
        self.snapshot_cache
            .served_full
            .lock()
            .expect("snapshot served_full lock poisoned")
            .insert(cache_key.to_owned(), std::sync::Arc::new(bytes.to_vec()));
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
        let index = cache
            .indexes
            .lock()
            .expect("snapshot cache lock poisoned")
            .remove(&cache_key)
            .unwrap_or_else(NamespaceSnapshotIndex::new);
        let mut index = gate_snapshot_index(&state, &namespace, index).await;
        index.reconciled_at = Instant::now();
        index.built_at_generation = generation;
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
        let mut materialization_budget =
            std::sync::Mutex::new(MaterializationBudget::new(&self.state));
        let (size_bytes, mut action_result) = match fetch_keyvalue_proto::<reapi::ActionResult>(
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
            materialization_budget
                .get_mut()
                .expect("action-cache materialization budget lock poisoned"),
        )
        .await;
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
        // as a hard build failure rather than a recompile.
        self.state.store.extend_artifact_lifetimes(
            ArtifactProducer::Reapi,
            namespace_id,
            &presence.present,
            RefreshTrigger::ActionCache,
        );
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
        self.state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "ok", size_bytes);
        // Book usage only after the response is fully built (headers applied),
        // matching the other handlers' success-arm convention.
        self.record_reapi_download(request.metadata(), namespace_id, served_bytes);
        self.record_reapi_cache_event(
            request.metadata(),
            namespace_id,
            ReapiCacheObservation {
                operation: "action_cache",
                outcome: "hit",
                digest: &digest.hash,
                size: served_bytes,
                duration: analytics_started_at.elapsed(),
            },
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
        // inline and pushed to peers inline, and the inline replication path
        // buffers the whole body in RAM, so it is bounded by
        // MAX_INLINE_REPLICATION_BODY_BYTES. Accepting a larger entry would
        // strand it on this node (peers 413 the oversized inline push) and
        // churn a poison outbox message forever. failed_precondition is
        // non-retriable, so Bazel records the miss and moves on instead of
        // retrying the doomed write.
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
                branch.as_deref(),
                trunk.as_deref(),
            )
            .await
            .map_err(|error| store_write_status("failed to store action result", error))?;
        self.state.notify.notify_one();
        self.state
            .metrics
            .record_artifact_write(ArtifactProducer::Reapi, "ok", manifest.size);
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
            self.record_reapi_cache_event(
                &metadata,
                namespace_id,
                ReapiCacheObservation {
                    operation: "action_cache",
                    outcome: "write",
                    digest: &action_digest,
                    size: manifest.size,
                    duration: analytics_started_at.elapsed(),
                },
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
        let mut missing = Vec::new();
        // "Servers SHOULD increase the lifetimes of the referenced blobs if
        // necessary and applicable": a client told a blob is present skips
        // uploading it and relies on it staying present, so the answer has to
        // keep it alive the same way a served action result does. The request's
        // digest count is client-controlled up to the 64 MiB decode ceiling, so
        // extension happens inside the presence lookup rather than over a
        // collected key set: no per-digest allocation is retained, and a
        // present blob costs one manifest lookup rather than two. When no
        // segment has aged there is nothing to promote, so the plain existence
        // check keeps its existence-cache short-circuit.
        let aging = self.state.store.segment_ring_is_aging();
        for digest in message.blob_digests {
            // The empty blob is present by REAPI convention even when it was
            // never uploaded; reporting it missing would push clients to upload
            // a zero-byte blob they otherwise synthesize.
            if is_empty_blob(&digest) {
                continue;
            }
            let key = blob_key(&digest_key(&digest)?);
            let exists = if aging {
                self.state
                    .store
                    .artifact_exists_extending_lifetime(
                        ArtifactProducer::Reapi,
                        namespace_id,
                        &key,
                        RefreshTrigger::FindMissing,
                    )
                    .await
            } else {
                self.state
                    .store
                    .artifact_exists(ArtifactProducer::Reapi, namespace_id, &key)
                    .await
            }
            .map_err(|error| Status::internal(format!("failed to inspect CAS blob: {error}")))?;
            if !exists {
                missing.push(digest);
            }
        }

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
        let mut responses = Vec::with_capacity(message.requests.len());
        // Accumulate only the bytes this RPC actually stored so the whole batch
        // books a single usage request (matching how ByteStream/HTTP count one
        // request per call), and so already-present blobs are not billed —
        // mirroring the HTTP upload path's `artifact_exists` short-circuit,
        // with presence decided under the store's write lock.
        let mut stored_bytes = 0_u64;
        let mut stored_any = false;

        for item in message.requests {
            let analytics_started_at = Instant::now();
            let digest = match item.digest {
                Some(digest) => digest,
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
                        self.record_reapi_cache_event_with_context(
                            analytics_context.as_ref(),
                            ReapiCacheObservation {
                                operation: "cas",
                                outcome: "write",
                                digest: &digest.hash,
                                size: item.data.len() as u64,
                                duration: analytics_started_at.elapsed(),
                            },
                        );
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
        // budget claim is synchronous and taken under a short lock that is
        // never held across an await; per-blob failure semantics are
        // unchanged and response order matches request order.
        let budget = std::sync::Mutex::new(MaterializationBudget::new(&self.state));
        let digests = message.digests;
        let read_results: Vec<(reapi::batch_read_blobs_response::Response, Duration)> =
            futures_util::stream::iter(digests.into_iter().map(|digest| {
                let budget = &budget;
                async move {
                    let analytics_started_at = Instant::now();
                    let response =
                        match batch_read_one(&self.state, namespace_id, &digest, budget).await {
                            Ok(Some(data)) => reapi::batch_read_blobs_response::Response {
                                digest: Some(digest),
                                data,
                                compressor: 0,
                                status: Some(rpc_status(0, "")),
                            },
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
                self.record_reapi_cache_event_with_context(
                    analytics_context.as_ref(),
                    ReapiCacheObservation {
                        operation: "cas",
                        outcome,
                        digest: &digest.hash,
                        size: response.data.len() as u64,
                        duration,
                    },
                );
            }

            responses.push(response);
        }
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
        let stream = bytestream_read_response_stream(reader, stream_chunk_bytes);

        let mut response = Response::new(Box::pin(stream) as Self::ReadStream);
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
                let response = Response::new(bytestream::QueryWriteStatusResponse {
                    committed_size: manifest.size as i64,
                    complete: true,
                });
                Ok(response)
            }
            None => Err(Status::not_found("blob not found")),
        }
    }
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
    materialization_budget: &mut MaterializationBudget<'_>,
) -> OutputPresence {
    let mut present = Vec::new();

    for digest in action_result
        .output_files
        .iter()
        .filter_map(|file| file.digest.as_ref())
        .chain(action_result.stdout_digest.as_ref())
        .chain(action_result.stderr_digest.as_ref())
    {
        if blob_evicted(state, namespace_id, digest, collecting, &mut present) {
            return OutputPresence::evicted(&digest.hash);
        }
    }

    for directory in &action_result.output_directories {
        let Some(tree_digest) = directory.tree_digest.as_ref() else {
            continue;
        };
        if blob_evicted(state, namespace_id, tree_digest, collecting, &mut present) {
            return OutputPresence::evicted(&tree_digest.hash);
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
            if blob_evicted(state, namespace_id, digest, collecting, &mut present) {
                return OutputPresence::evicted(&digest.hash);
            }
        }
    }

    OutputPresence {
        evicted: None,
        present,
    }
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
fn blob_evicted(
    state: &SharedState,
    namespace_id: &str,
    digest: &reapi::Digest,
    collecting: bool,
    present: &mut Vec<String>,
) -> bool {
    if is_empty_blob(digest) {
        return false;
    }
    let Ok(key) = digest_key(digest) else {
        return false;
    };
    let key = blob_key(&key);
    let exists = state
        .store
        .artifact_manifest_exists(ArtifactProducer::Reapi, namespace_id, &key)
        .unwrap_or(true);
    if exists {
        if collecting {
            present.push(key);
        }
        return false;
    }
    true
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
    held_permits: Vec<crate::memory::MemoryPermit>,
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
        let limit_bytes = self.state.memory.reapi_materialization_limit_bytes();
        if requested_bytes > limit_bytes {
            return Err(self.reject(format!(
                "{label} needs {requested_bytes} bytes but the node allows at most {limit_bytes} bytes of response materialization per request"
            )));
        }
        let permit = self
            .state
            .memory
            .try_acquire_response_materialization(requested_bytes)
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
        self.state
            .metrics
            .record_capacity_shed(crate::metrics::shed_kind::REAPI_MATERIALIZATION);
        Status::resource_exhausted(message)
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
// wins. This lets the auth enforce the same request-account-matches-server-
// tenant guard the HTTP path already has; the namespace still comes from the
// REAPI `instance_name`/`resource_name`, so it always matches what is stored.
const TENANT_HEADER_KEYS: &[&str] = &["x-kura-tenant-id", "x-tuist-account-handle"];

const REAPI_USAGE_ARTIFACT_KIND: &str = "reapi";

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

pub(super) async fn authorize_build_event_request(
    state: &SharedState,
    metadata: &tonic::metadata::MetadataMap,
    project_handle: &str,
    _route: &str,
) -> Result<String, Status> {
    if state.runtime.is_draining() {
        return Err(Status::unavailable("server is draining"));
    }

    let account_handle = usage_tenant_id(metadata, &state.config.tenant_id);
    let Some(auth) = state.auth.as_ref() else {
        return Ok(account_handle);
    };

    let spec = GrpcRequestSpec {
        operation: "build_event_stream",
        namespace_id: Some(project_handle),
    };
    let context = grpc_request_context(&state.config.tenant_id, &spec, metadata);

    match auth.evaluate_access(&context).await {
        AccessDecision::Allow => Ok(account_handle),
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
}

impl BlobResource {
    fn hash(&self) -> &str {
        &self.key[self.hash_range.clone()]
    }
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
        if part == "blobs" {
            blob_index = Some(index);
            hash = None;
            encoded_size = None;
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
            if hash.is_none() {
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
            "resource_name must contain /blobs/",
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
                "write resource_name must include uploads/{uuid}/blobs/{hash}/{size}",
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
    })
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
    let key = blob_key(&format!("{hash}/{size_bytes}"));

    Ok(BlobResource {
        namespace_id,
        hash_range: "blob/".len().."blob/".len() + hash.len(),
        size_bytes,
        key,
    })
}

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
            cache
                .served_full
                .lock()
                .unwrap()
                .insert(namespace.to_owned(), std::sync::Arc::new(vec![0; 2 * 1024]));
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
            context: Arc::clone(&context),
            operation: "cas",
            outcome: "hit",
            action_digest: "digest-a".into(),
            size: 1,
            duration_ms: 2,
            observed_at_ms: 3,
        };
        let second = ReapiCacheAnalyticsEvent {
            context,
            operation: "cas",
            outcome: "miss",
            action_digest: "digest-b".into(),
            size: 0,
            duration_ms: 4,
            observed_at_ms: 5,
        };

        assert!(Arc::ptr_eq(&first.context, &second.context));
        assert_eq!(first.context.account_handle, "acme");
        assert_eq!(first.context.project_handle, "ios");
        assert_eq!(first.context.invocation_id, "invocation-1");
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
                        context: Arc::clone(&context),
                        operation: "cas",
                        outcome: "hit",
                        action_digest: digest.to_owned(),
                        size: 4_096,
                        duration_ms: 1,
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
            first_evicted_output(&context.state, "ios", &serveable, true, &mut budget).await;

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
            first_evicted_output(&context.state, "ios", &doomed, true, &mut budget).await;
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
                hash_range: 5..8,
                size_bytes: 10,
                key: "blob/abc/10".into(),
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
            }
        );
    }

    #[test]
    fn rejects_write_resources_without_upload_prefix() {
        let error = parse_write_resource_name("blobs/abc/10")
            .expect_err("write resources should require uploads prefix");
        assert_eq!(error.code(), tonic::Code::InvalidArgument);
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
    async fn concurrent_cas_batch_reads_respect_the_shared_transient_budget() {
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
    // pushed to peers (the inline replicate path 413s it), so we reject the
    // write with a non-retriable status instead of storing an entry that would
    // strand on this node and churn a poison outbox message forever.
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

        // Nothing was stored, so no poison outbox message can exist.
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
}
