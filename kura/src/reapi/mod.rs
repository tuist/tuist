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
use tracing::Instrument;

use crate::{
    artifact::{manifest::ArtifactManifest, producer::ArtifactProducer},
    constants::{MAX_INLINE_REPLICATION_BODY_BYTES, MAX_MODULE_TOTAL_BYTES},
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

/// What asked for an index build. Only a serve counts as USE: the background
/// refresh must not renew an index's LRU standing, or a namespace served once
/// would keep itself alive — and keep paying for a scan every window — for the
/// life of the process, and never age out behind the namespaces still in use.
#[derive(Clone, Copy, PartialEq, Eq)]
enum IndexBuildTrigger {
    Serve,
    Refresh,
}

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

// The four REAPI gRPC services with their shared decoding limits, all backed by
// the one service (and so the one snapshot cache).
fn reapi_servers(service: ReapiService) -> ReapiServers {
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
    let service = ReapiService {
        state: state.clone(),
        snapshot_cache: Default::default(),
    };
    spawn_snapshot_refresh_task(service.clone());
    let (capabilities, action_cache, cas, byte_stream) = reapi_servers(service);
    tonic::service::Routes::new(capabilities)
        .add_service(action_cache)
        .add_service(cas)
        .add_service(byte_stream)
        .into_axum_router()
        .layer(GrpcRequestAccountingLayer { state })
}

/// Keeps the snapshot indexes this node is already serving fresh, instead of
/// waiting for a fetch to notice they are stale.
///
/// Reconciling only on demand made staleness a function of fetch arrivals, not
/// of the window: a client fetches the full snapshot about once per session and
/// keeps that view for its whole build, so on a namespace CI publishes to
/// continuously the first fetch of a session was answered from a view minutes
/// behind — and every miss it caused was recompiled work the cache already
/// held. Refreshing on a tick makes the freshness window mean what it says.
///
/// Bounded by construction: it only reconciles indexes the cache already holds
/// (LRU-capped at SNAPSHOT_CACHE_MAX_NAMESPACES) and only while they are still
/// being served, so it never enumerates namespaces nobody asked for and a node
/// serving nothing does no work. The existing dedup owns the rest — a refresh
/// joins an in-flight build rather than starting a second one.
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

/// A git ref carried as request metadata, preferring the binary header.
///
/// Git allows any UTF-8 in a ref name, and an ASCII metadata value takes visible
/// ASCII only, so a client cannot send `feature/café` that way at all. It sends
/// the bytes in the `-bin` header and, when the ref happens to be ASCII, the
/// plain one as well, which is what a node too old to read this understands.
/// Preferring the binary one costs nothing and is the only one that can be
/// trusted to carry what the client actually meant.
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
        trunk: Option<&str>,
    ) -> Result<Vec<u8>, Status> {
        // A trunk filter keeps its own cached index and full view under a
        // compound key so a scoped snapshot and the unscoped one never collide;
        // with no filter the key is just the namespace, preserving today's
        // behavior exactly.
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
            // An index that built EMPTY only answers while the namespace has not
            // moved under it. The freshness window trades staleness for round
            // trips, and that trade only makes sense when there is something to
            // serve: a populated index 60s out of date costs its client a few
            // keys, an empty one costs it every key it came for, and it does not
            // come back to find out, because it fetches once per session.
            //
            // The generation is what makes that affordable. Rebuilding every
            // empty index instead would be a namespace scan per build for every
            // namespace whose trunk view is legitimately empty, which is all of
            // them until the fleet re-tags. Equal generation means nothing has
            // been published since the build, so empty is the answer, not a
            // stale one.
            let unchanged = indexes
                .get(&cache_key)
                .is_some_and(|index| index.built_at_generation == generation);
            if let Some(index) = indexes.get_mut(&cache_key)
                && (!index.entries.is_empty() || unchanged)
            {
                let stale = index.reconciled_at.elapsed() >= SNAPSHOT_RECONCILE_INTERVAL;
                index.last_used = Instant::now();
                let entries = index.entries.len();
                let bytes = index.encode(after);
                drop(indexes);
                self.cache_full_view(&cache_key, after, entries, &bytes);
                if stale {
                    let _build =
                        self.ensure_index_build(namespace_id, trunk, IndexBuildTrigger::Serve);
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
                .get(&cache_key)
                .cloned();
            if let Some(cached) = cached {
                let _build = self.ensure_index_build(namespace_id, trunk, IndexBuildTrigger::Serve);
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
            return Err(Status::internal("snapshot index missing after build"));
        };
        index.last_used = Instant::now();
        let entries = index.entries.len();
        let bytes = index.encode(after);
        drop(indexes);
        self.cache_full_view(&cache_key, after, entries, &bytes);
        Ok(bytes)
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
        // Never cache an empty view as stale-servable: a namespace's first
        // request often lands before anything is published (a client's startup
        // prefetch), and serving that cached emptiness to later cold clients
        // starves them of a real index that finished building moments later —
        // the client fetches once per session, so an empty answer sticks for
        // its whole build.
        //
        // Dropping any view already cached under this key is part of that:
        // leaving it would serve an obsolete non-empty view to a request landing
        // during a later reconcile, long after the namespace emptied.
        if entries == 0 {
            self.snapshot_cache
                .served_full
                .lock()
                .expect("snapshot served_full lock poisoned")
                .remove(cache_key);
            return;
        }
        self.snapshot_cache
            .served_full
            .lock()
            .expect("snapshot served_full lock poisoned")
            .insert(cache_key.to_owned(), std::sync::Arc::new(bytes.to_vec()));
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
        // Builds are keyed by the same compound cache key as the indexes they
        // produce, so a trunk-scoped build and the unscoped one run and cache
        // independently.
        let cache_key = snapshot_cache_key(namespace_id, trunk);
        let mut builds = self
            .snapshot_cache
            .builds
            .lock()
            .expect("snapshot builds lock poisoned");
        if let Some(build) = builds.get(&cache_key) {
            return build.clone();
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

    /// The cached indexes a background refresh should reconcile: stale by the
    /// same window a serve applies, and still being served. Only indexes that
    /// already exist are candidates — nothing here enumerates the store, so a
    /// namespace nobody fetches is never built. An index currently being built
    /// is not in the map at all (the build takes it out), so an in-flight
    /// reconcile is naturally skipped rather than raced.
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

    /// Reconciles every stale-but-live cached index once. Kicks the shared
    /// build and drops it: the build is detached and caches its own result, and
    /// awaiting them here would serialize a slow namespace's scan in front of
    /// the rest.
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
        // Sampled BEFORE the scan: a publish landing mid-reconcile must leave the
        // index looking out of date, not be stamped as included by a generation
        // read after it.
        let generation = state.store.action_cache_generation(&namespace);
        let index = cache
            .indexes
            .lock()
            .expect("snapshot cache lock poisoned")
            .remove(&cache_key)
            .unwrap_or_else(NamespaceSnapshotIndex::new);
        let (mut index, result) =
            match reconcile_snapshot_index(&state, &namespace, trunk.as_deref(), index).await {
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
        // A background refresh leaves `last_used` alone so it keeps meaning
        // "last served": the refresh selects on it, and the LRU evicts on it.
        if trigger == IndexBuildTrigger::Serve {
            index.last_used = Instant::now();
        }
        {
            let mut indexes = cache.indexes.lock().expect("snapshot cache lock poisoned");
            indexes.insert(cache_key.clone(), index);
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
    trunk: Option<&str>,
    mut index: NamespaceSnapshotIndex,
) -> Result<NamespaceSnapshotIndex, (NamespaceSnapshotIndex, String)> {
    let started = Instant::now();
    let manifests =
        match state
            .store
            .action_cache_manifests(namespace_id, snapshot_index_max_entries(), trunk)
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
            // A trunk-branch filter scopes the snapshot to the trunk baseline:
            // entries tagged with this branch, and only those. Absent or empty
            // means the unfiltered snapshot of every branch in the namespace.
            let trunk = ref_metadata(&request, "x-tuist-trunk-branch", "x-tuist-trunk-branch-bin");
            let trunk = trunk.as_deref();
            let snapshot = self
                .serve_actioncache_snapshot(namespace_id, after, trunk)
                .await?;
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
        if let Some(missing) = first_evicted_output(
            &self.state,
            namespace_id,
            &action_result,
            &mut materialization_budget,
        )
        .await
        {
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
        // The publishing client tags the entry with its git branch so a
        // trunk-scoped snapshot can later exclude feature-branch results.
        let branch = ref_metadata(&request, "x-tuist-branch", "x-tuist-branch-bin");
        // The trunk rides the write too so the store can keep trunk-baseline
        // keys sticky against feature republishes (see the damped persist).
        let trunk = ref_metadata(&request, "x-tuist-trunk-branch", "x-tuist-trunk-branch-bin");
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
            // The empty blob is present by REAPI convention even when it was
            // never uploaded; reporting it missing would push clients to upload
            // a zero-byte blob they otherwise synthesize.
            if is_empty_blob(digest) {
                continue;
            }
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

/// The hash of the first blob this action result references that is no longer
/// present in the CAS, or `None` when every referenced blob is present.
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
    materialization_budget: &mut MaterializationBudget<'_>,
) -> Option<String> {
    let missing = |digest: &reapi::Digest| {
        !is_empty_blob(digest)
            && digest_key(digest).is_ok_and(|key| {
                !state
                    .store
                    .artifact_manifest_exists(
                        ArtifactProducer::Reapi,
                        namespace_id,
                        &blob_key(&key),
                    )
                    .unwrap_or(true)
            })
    };

    let stream_evicted = action_result
        .output_files
        .iter()
        .filter_map(|file| file.digest.as_ref())
        .chain(action_result.stdout_digest.as_ref())
        .chain(action_result.stderr_digest.as_ref())
        .find(|&digest| missing(digest));
    if let Some(digest) = stream_evicted {
        return Some(digest.hash.clone());
    }

    for directory in &action_result.output_directories {
        let Some(tree_digest) = directory.tree_digest.as_ref() else {
            continue;
        };
        if missing(tree_digest) {
            return Some(tree_digest.hash.clone());
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
        let leaf_evicted = tree
            .root
            .iter()
            .chain(&tree.children)
            .flat_map(|directory| &directory.files)
            .filter_map(|file| file.digest.as_ref())
            .find(|&digest| missing(digest));
        if let Some(digest) = leaf_evicted {
            return Some(digest.hash.clone());
        }
    }
    None
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
/// transient memory — roughly cap x ~1KB. The default; a local bench can lower
/// it through `KURA_SNAPSHOT_INDEX_MAX_ENTRIES` to force the cap to bind.
const SNAPSHOT_INDEX_MAX_ENTRIES: usize = 100_000;

/// The snapshot index cap, `KURA_SNAPSHOT_INDEX_MAX_ENTRIES` when it parses and
/// `SNAPSHOT_INDEX_MAX_ENTRIES` otherwise.
fn snapshot_index_max_entries() -> usize {
    std::env::var("KURA_SNAPSHOT_INDEX_MAX_ENTRIES")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(SNAPSHOT_INDEX_MAX_ENTRIES)
}

/// The snapshot-cache key for a namespace and optional trunk filter. With no
/// filter it is the bare namespace id, so the unscoped snapshot keeps today's
/// cache entries; a trunk filter appends the branch behind a NUL separator so a
/// scoped snapshot never collides with the unscoped one.
fn snapshot_cache_key(namespace_id: &str, trunk: Option<&str>) -> String {
    match trunk {
        Some(trunk) => format!("{namespace_id}\u{0}{trunk}"),
        None => namespace_id.to_owned(),
    }
}

/// Whether the background refresh should reconcile a cached index, given how
/// long ago it was reconciled and how long ago it was last served. Stale by the
/// same window a serve applies, and not yet idle: refreshing a namespace whose
/// clients have all gone home buys nothing and costs a scan every window.
fn should_refresh_snapshot_index(reconciled_ago: Duration, idle_for: Duration) -> bool {
    reconciled_ago >= SNAPSHOT_RECONCILE_INTERVAL && idle_for < SNAPSHOT_REFRESH_IDLE_AFTER
}

/// The inverse of [`snapshot_cache_key`], for callers that hold a cached key
/// and need the namespace and trunk it was built from. Exact: a namespace id is
/// NUL-free (the store already uses NUL to terminate it in its own index key
/// prefixes), so the first NUL is always the separator this wrote.
fn snapshot_cache_key_parts(cache_key: &str) -> (&str, Option<&str>) {
    match cache_key.split_once('\u{0}') {
        Some((namespace_id, trunk)) => (namespace_id, Some(trunk)),
        None => (cache_key, None),
    }
}

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

/// How old a cached snapshot index may grow before it is reconciled. Requests
/// never wait on it — they get the cached view — so this bounds staleness, not
/// latency; it composes with the client's delta cadence.
const SNAPSHOT_RECONCILE_INTERVAL: Duration = Duration::from_secs(60);

/// How often the background refresh looks for cached indexes that have gone
/// stale. Shorter than the freshness window so a stale index is picked up
/// within it rather than a window later; a tick that finds nothing is a lock,
/// a walk of at most SNAPSHOT_CACHE_MAX_NAMESPACES entries, and an instant
/// comparison each.
const SNAPSHOT_REFRESH_TICK: Duration = Duration::from_secs(15);

/// How long after its last serve an index stops being refreshed in the
/// background. Reconciling costs a namespace scan, so it is only worth paying
/// on a namespace something is actually building against; past this the index
/// simply goes cold and is served (and reconciled on demand) by the next fetch
/// exactly as before. Generously above any client's delta cadence, so an idle
/// gap between a session's fetches never drops it out of the refresh.
const SNAPSHOT_REFRESH_IDLE_AFTER: Duration = Duration::from_secs(30 * 60);

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
    /// The namespace's action-cache generation when this index was built. An
    /// empty index is only worth serving while this still matches: equal means
    /// nothing has been published since, so empty is the truth rather than a
    /// stale answer.
    built_at_generation: u64,
}

impl NamespaceSnapshotIndex {
    fn new() -> Self {
        Self {
            nodes: Vec::new(),
            node_index: BTreeMap::new(),
            entries: BTreeMap::new(),
            last_used: Instant::now(),
            reconciled_at: Instant::now(),
            built_at_generation: 0,
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
mod tests {
    use super::*;
    use std::{convert::Infallible, time::Duration};

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
    fn snapshot_cache_keys_round_trip_through_their_parts() {
        for (namespace_id, trunk) in [
            ("ios", None),
            ("ios", Some("main")),
            // A branch name carries slashes and dots; only NUL is reserved.
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

        assert!(
            should_refresh_snapshot_index(stale, served),
            "a stale index a client is still fetching is exactly what this exists for"
        );
        assert!(
            !should_refresh_snapshot_index(fresh, served),
            "a fresh index costs nothing to leave alone"
        );
        assert!(
            !should_refresh_snapshot_index(stale, idle),
            "a namespace nobody fetches must not keep paying for a scan every window"
        );
        assert!(!should_refresh_snapshot_index(fresh, idle));
    }

    /// An empty index is ambiguous: "nothing to show" and "built before anything
    /// was published" look identical. The generation is what tells them apart,
    /// and both answers matter. Serving a stale-empty view costs a client every
    /// key it came for and it does not ask twice; rebuilding a correctly-empty
    /// one costs a namespace scan per build, on every namespace whose trunk view
    /// is empty, which is all of them until the fleet re-tags.
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

        // Nothing published, so the store's generation is 0 and the index agrees:
        // empty is the truth and answering costs nothing.
        let stamped = insert(context.state.store.action_cache_generation("ios"));
        service
            .serve_actioncache_snapshot("ios", 0, None)
            .await
            .expect("serve should succeed");
        assert!(
            reconciled_at().is_some_and(|at| at < stamped),
            "a correctly-empty index answers without rescanning the namespace"
        );

        // A generation the store has moved past: the index was built before
        // something was published, so it has to go back and look.
        let stamped = insert(context.state.store.action_cache_generation("ios") + 1);
        service
            .serve_actioncache_snapshot("ios", 0, None)
            .await
            .expect("serve should succeed");
        assert!(
            reconciled_at().is_some_and(|at| at > stamped),
            "an index built before a publish is rebuilt rather than served empty"
        );
    }

    /// Git allows any UTF-8 in a ref name, and an ASCII metadata value takes
    /// visible ASCII only, so a client cannot send one that way. It could not
    /// even report the failure usefully: the publish just went out untagged and
    /// the entry sat outside a trunk view nobody could see it was excluded from.
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

    /// The header a node too old to send the binary one uses. Dropping it would
    /// untag every ASCII ref through a rolling deploy.
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
        // And an absent ref stays absent rather than becoming an empty tag.
        let empty: Request<()> = Request::new(());
        assert_eq!(
            ref_metadata(&empty, "x-tuist-branch", "x-tuist-branch-bin"),
            None
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
            vec![("ios".to_owned(), Some("main".to_owned()))],
            "the stale index is selected, split back into its namespace and trunk"
        );
        // A namespace with no cached index is never a candidate: the refresh
        // keeps what is being served warm, it does not go looking for work.
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

        // A tree whose one file is present, and one whose file is evicted. Both
        // tree blobs themselves exist; the missing tree hash is never written.
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

        // The output file is present in every entry, so each rejection is
        // attributable to the stream/tree blob under test, not the file.
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

        // The canonical empty blob is present by REAPI convention even though it
        // was never uploaded, so an entry referencing it for stdout and as a
        // tree leaf must still serve rather than gate as evicted.
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
            async move { service.serve_actioncache_snapshot("ios", 0, None).await }
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
        // the pool so the serve's kicked rebuild cannot reinsert it before the
        // assertion.
        service.snapshot_cache.indexes.lock().unwrap().remove("ios");
        let pool = context.state.memory.reapi_materialization_pool_bytes();
        let _hog = context
            .state
            .memory
            .try_acquire_reapi_materialization(pool)
            .expect("pool should be acquirable when idle");

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
        let pool = context.state.memory.reapi_materialization_pool_bytes();
        let hog = context
            .state
            .memory
            .try_acquire_reapi_materialization(pool)
            .expect("pool should be acquirable when idle");
        let status = service
            .serve_actioncache_snapshot("ios", 0, None)
            .await
            .expect_err("cold serve should shed while the build is stuck");
        assert_eq!(status.code(), tonic::Code::Unavailable);
        // Once the pool frees the same build completes in the background and
        // the next fetch is served from the index it produced.
        drop(hog);
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
        // bills nothing — the size check returns before the upload rollup.
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
