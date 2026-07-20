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
    replication::replication_targets,
    state::SharedState,
    utils::{action_cache_key, blob_key, ensure_tmp_dir_capacity, temp_file_path},
};

const DEFAULT_INSTANCE_NAME: &str = "default";
const REAPI_READ_STREAM_CHUNK_BYTES: usize = 512 * 1024;
const REAPI_MATERIALIZATION_REJECTED_ACTION: &str = "reapi_materialization_rejected";

// Abort a ByteStream upload only when no chunk arrives within this window. The
// timer resets on every chunk received, so an actively transferring upload is
// never interrupted, while a stalled or vanished client is reclaimed promptly.
const REAPI_WRITE_STALL_TIMEOUT: Duration = Duration::from_secs(60);
type BoxError = Box<dyn Error + Send + Sync + 'static>;
type GrpcAccountingBody = UnsyncBoxBody<Bytes, BoxError>;

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
#[derive(Default)]
struct SnapshotCache {
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
        state,
        snapshot_cache: Default::default(),
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
        .layer(GrpcRequestAccountingLayer { state })
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
    ) -> Result<Response<bytestream::WriteResponse>, Status> {
        // ByteStream Write learns its namespace from the first chunk's
        // resource_name, which is not available until we read the stream. Capture
        // the metadata now and authorize below, once the namespace is known, so
        // project-scoped tokens authorize against the real project (not the
        // account) — matching the namespace the blob is ultimately stored under.
        let metadata = request.metadata().clone();
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
        let mut written = 0_u64;
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
                ensure_tmp_dir_capacity(
                    &self.state.config.tmp_dir,
                    parsed_resource.size_bytes,
                    self.state.config.tmp_dir_max_bytes,
                )
                .await
                .map_err(|error| {
                    Status::resource_exhausted(format!(
                        "temporary storage budget exhausted: {error}"
                    ))
                })?;
                resource = Some(parsed_resource);
                resource_name = Some(chunk_resource_name);
            }
            if chunk.write_offset < 0 || chunk.write_offset as u64 != written {
                return Err(Status::invalid_argument("unexpected write_offset"));
            }
            if !chunk.data.is_empty() {
                tokio::io::AsyncWriteExt::write_all(&mut temp_file, &chunk.data)
                    .await
                    .map_err(|error| {
                        Status::internal(format!("failed to write temp blob: {error}"))
                    })?;
                hasher.update(&chunk.data);
                written = written.saturating_add(chunk.data.len() as u64);
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
                temp_path,
                &targets,
            )
            .await
            .map_err(|error| {
                if is_fd_pool_exhausted_error(&error) {
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
                let bytes = index.encode(after);
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
            return Err(Status::internal("snapshot index missing after build"));
        };
        index.last_used = Instant::now();
        let bytes = index.encode(after);
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
        self.snapshot_cache
            .served_full
            .lock()
            .expect("snapshot served_full lock poisoned")
            .insert(namespace_id.to_owned(), std::sync::Arc::new(bytes.to_vec()));
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
            state.memory.acquire_reapi_materialization(budget),
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
        let (mut index, result) = match reconcile_snapshot_index(&state, &namespace, index).await {
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
    let changed: Vec<[u8; 32]> = current
        .iter()
        .filter(|(hash, (version, _))| {
            index
                .entries
                .get(*hash)
                .is_none_or(|entry| entry.version_ms != *version)
        })
        .map(|(hash, _)| *hash)
        .collect();
    // Manifests move out for the load and move back with the result, so the
    // stream owns everything it captures (the whole reconcile runs inside a
    // 'static spawned task) without duplicating a single manifest.
    let mut to_load = Vec::with_capacity(changed.len());
    for hash in changed {
        if let Some((version, manifest)) = current.remove(&hash) {
            to_load.push((hash, version, manifest));
        }
    }
    let changed_count = to_load.len();
    let mut loads_failed = 0_usize;
    let mut invalid = 0_usize;
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
        let Some(action_result) = action_result else {
            loads_failed += 1;
            continue;
        };
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
            nodes.push(index.intern_node(llcas, blob_hash, digest.size_bytes as u64));
        }
        if valid {
            index
                .entries
                .insert(hash, SnapshotIndexEntry { version_ms, nodes });
        } else {
            invalid += 1;
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
        index.entries.remove(&hash);
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
            self.apply_response_headers(&mut response, extension, principal.as_ref())
                .await?;
            self.state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "ok", served);
            self.record_reapi_download(request.metadata(), namespace_id, served);
            return Ok(response);
        }
        let mut materialization_budget = MaterializationBudget::new(&self.state);
        let (size_bytes, mut action_result) = fetch_keyvalue_proto::<reapi::ActionResult>(
            &self.state,
            namespace_id,
            &key,
            "action result",
            Some(&mut materialization_budget),
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
                Some(&mut materialization_budget),
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
                Some(&mut materialization_budget),
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
            let budget = std::sync::Mutex::new(materialization_budget);
            let reads: Vec<(usize, bool, Result<Option<Vec<u8>>, Status>)> =
                futures_util::stream::iter(targets.into_iter().map(|(index, digest, explicit)| {
                    let budget = &budget;
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
            .map_err(|error| Status::internal(format!("failed to store action result: {error}")))?;
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
                Err(error) => responses.push(reapi::batch_update_blobs_response::Response {
                    digest: Some(digest),
                    status: Some(rpc_status(13, error)),
                }),
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

        // Funnel everything that touches the temp file through write_to_temp so a
        // single place reclaims the partial file on ANY error. A cancelled or
        // RST'd upload (transport error, mid-stream stall, write/flush failure)
        // would otherwise leak a partial that counts against the tmp dir budget
        // forever — there is no janitor for reapi uploads. On success the persist
        // step already unlinks the temp file, so this cleanup is a no-op there.
        let result = self.write_to_temp(&temp_path, request).await;
        if let Err(status) = &result {
            self.state.io.remove_file_if_exists(&temp_path).await;
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
    held_permits: Vec<tokio::sync::OwnedSemaphorePermit>,
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
    last_used: Instant,
    /// When the last successful reconcile finished. Serving reads this to
    /// decide whether the cached view is fresh enough to return as-is.
    reconciled_at: Instant,
}

impl NamespaceSnapshotIndex {
    fn new() -> Self {
        Self {
            nodes: Vec::new(),
            node_index: BTreeMap::new(),
            entries: BTreeMap::new(),
            last_used: Instant::now(),
            reconciled_at: Instant::now(),
        }
    }

    fn intern_node(&mut self, llcas: Vec<u8>, blob_hash: [u8; 32], blob_size: u64) -> u32 {
        if let Some(&index) = self.node_index.get(&llcas) {
            return index;
        }
        let blob_key = blob_key(&format!("{}/{}", hex::encode(blob_hash), blob_size));
        let index = self.nodes.len() as u32;
        self.nodes.push(SnapshotNode {
            llcas: llcas.clone(),
            blob_hash,
            blob_size,
            blob_key,
        });
        self.node_index.insert(llcas, index);
        index
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
    fn encode(&self, after: u64) -> Vec<u8> {
        let mut budget = SNAPSHOT_CONTENT_BUDGET_BYTES;
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
            budget = scaled.min(budget * 9 / 10).max(SNAPSHOT_MIN_BUDGET_BYTES);
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
mod tests;
