use std::{
    collections::{BTreeMap, HashMap},
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
    time::{Duration, Instant},
};

use axum::{
    Json, Router,
    body::{Body, to_bytes},
    extract::{MatchedPath, Path as AxumPath, Query, Request, State},
    http::{HeaderMap, HeaderValue, StatusCode, Uri, Version},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{delete, get, head, post, put},
};
use bytes::Bytes;
use futures_util::{Stream, StreamExt};
use http_body::{Body as HttpBody, Frame, SizeHint};
use serde::{Deserialize, Serialize};
use tokio::io::AsyncWriteExt;
use tracing::{Instrument, field};

use crate::{
    artifact::{
        manifest::ArtifactManifest,
        producer::ArtifactProducer,
        range::{RangeOutcome, RangeRequest, ServedRange, entity_tag, resolve_conditional_range},
    },
    auth::{AccessDecision, RequestContext as AuthRequestContext},
    backpressure,
    bandwidth::BandwidthLimiter,
    constants::{
        BACKFILL_BODIES_BATCH_BYTES, MAX_BACKFILL_BODIES_ENTRIES,
        MAX_BACKFILL_BODIES_REQUEST_BYTES, MAX_GRADLE_BYTES, MAX_INLINE_REPLICATION_BODY_BYTES,
        MAX_MODULE_PART_BYTES, MAX_MODULE_TOTAL_BYTES, MAX_PEER_PAGE_ITEMS,
        MAX_REPLICATION_BODY_BYTES, MAX_XCODE_BYTES, REPLICATION_BATCH_MAX_BYTES,
        REPLICATION_BATCH_MAX_ITEMS, RESPONSE_STREAM_MIN_CHUNK_BYTES,
        RESPONSE_STREAM_SEND_BUFFER_BYTES, response_stream_chunk_bytes,
    },
    io::is_fd_pool_exhausted_error,
    memory::{
        MemoryController, MemoryPressure, ResponseStreamAdmissionPatience,
        ResponseStreamMemoryPermit, ResponseTransportGuard,
    },
    metrics::{Metrics, shed_kind},
    multipart::error::MultipartError,
    peer_tls::InternalPeerIdentity,
    replication::replication_targets,
    request_observability::{
        REQUEST_ID_HEADER, RequestCompletion, RequestContext, RequestLogPolicy, current_request,
        log_request_completion, request_id, scope_request,
    },
    runtime::{HttpTrafficClass, InflightGuard},
    state::SharedState,
    store::{
        ArtifactReader, BACKFILL_STALE_RETIRE_BATCH, BackfillIndexPage, StagedArtifactPath,
        backfill_record_kind, is_disk_full_error, is_multipart_capacity_error,
        is_outbox_full_error, manifest_version_ms,
    },
    telemetry::{attach_parent_context, record_trace_context, trace_export_active},
    utils::{
        BACKFILL_IDX_PREFIX, BackfillRecordKind, BodyReadError, RequestBodyStaging,
        TempFileCleanup, TmpReservation, action_cache_key, blob_key, module_key,
        read_request_to_temp, temp_file_path,
    },
};

const MMAP_RESPONSE_CHUNK_BYTES: usize = 1024 * 1024;
const FILE_RESPONSE_LIVE_BUFFER_COUNT: usize = 3;
const INLINE_RESPONSE_LIVE_BUFFER_COUNT: usize = 2;
#[cfg(test)]
const HTTP_RESPONSE_STREAM_RESERVATION_BYTES: usize =
    crate::constants::RESPONSE_STREAM_CHUNK_BYTES * FILE_RESPONSE_LIVE_BUFFER_COUNT;
const ROUTE_UP: &str = "/up";
const ROUTE_READY: &str = "/ready";
const ROUTE_ROLLOUT_STATUS: &str = "/status/rollout";
const ROUTE_STATUS_CLUSTER: &str = "/status/cluster";
const ROUTE_METRICS: &str = "/metrics";
const ROUTE_V1_CACHE: &str = "/v1/cache/{hash}";
const ROUTE_API_METRO_CACHE: &str = "/api/metro/cache/{cache_key}";
const ROUTE_API_CACHE_KEYVALUE_ID: &str = "/api/cache/keyvalue/{cas_id}";
const ROUTE_API_CACHE_KEYVALUE: &str = "/api/cache/keyvalue";
const ROUTE_API_CACHE_CAS: &str = "/api/cache/cas/{id}";
const ROUTE_API_CACHE_MODULE: &str = "/api/cache/module/{id}";
const ROUTE_API_CACHE_MODULE_START: &str = "/api/cache/module/start";
const ROUTE_API_CACHE_MODULE_PART: &str = "/api/cache/module/part";
const ROUTE_API_CACHE_MODULE_COMPLETE: &str = "/api/cache/module/complete";
const ROUTE_API_CACHE_CLEAN: &str = "/api/cache/clean";
const ROUTE_API_CACHE_GRADLE: &str = "/api/cache/gradle/{cache_key}";
const ROUTE_INTERNAL_STATUS: &str = "/_internal/status";
const ROUTE_INTERNAL_BACKFILL_ENTRIES: &str = "/_internal/backfill/entries";
const ROUTE_INTERNAL_BACKFILL_BODIES: &str = "/_internal/backfill/bodies";
// The oversized-entry path of the backfill protocol.
const ROUTE_INTERNAL_BACKFILL_ARTIFACT: &str = "/_internal/backfill/artifacts/{artifact_id}";
const ROUTE_INTERNAL_REPLICATE_ARTIFACT: &str = "/_internal/replicate/artifact";
const ROUTE_INTERNAL_REPLICATE_ARTIFACTS: &str = "/_internal/replicate/artifacts";
const ROUTE_INTERNAL_REPLICATE_NAMESPACE: &str = "/_internal/replicate/namespace";
const UNMATCHED_ROUTE: &str = "/_unmatched";

const EXACT_ROUTE_TEMPLATES: [&str; 16] = [
    ROUTE_UP,
    ROUTE_READY,
    ROUTE_ROLLOUT_STATUS,
    ROUTE_STATUS_CLUSTER,
    ROUTE_METRICS,
    ROUTE_API_CACHE_KEYVALUE,
    ROUTE_API_CACHE_MODULE_START,
    ROUTE_API_CACHE_MODULE_PART,
    ROUTE_API_CACHE_MODULE_COMPLETE,
    ROUTE_API_CACHE_CLEAN,
    ROUTE_INTERNAL_STATUS,
    ROUTE_INTERNAL_BACKFILL_ENTRIES,
    ROUTE_INTERNAL_BACKFILL_BODIES,
    ROUTE_INTERNAL_REPLICATE_ARTIFACT,
    ROUTE_INTERNAL_REPLICATE_ARTIFACTS,
    ROUTE_INTERNAL_REPLICATE_NAMESPACE,
];

const DYNAMIC_ROUTE_TEMPLATES: [&str; 7] = [
    ROUTE_V1_CACHE,
    ROUTE_API_METRO_CACHE,
    ROUTE_API_CACHE_KEYVALUE_ID,
    ROUTE_API_CACHE_CAS,
    ROUTE_API_CACHE_MODULE,
    ROUTE_API_CACHE_GRADLE,
    ROUTE_INTERNAL_BACKFILL_ARTIFACT,
];

pub fn public_router(state: SharedState) -> Router {
    public_routes()
        .layer(middleware::from_fn_with_state(
            state.clone(),
            authorize_request,
        ))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            reject_overloaded_public_writes,
        ))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            reject_draining_public_requests,
        ))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            track_http_metrics,
        ))
        .layer(middleware::map_response(guard_response_stream_transport))
        .with_state(state)
}

pub fn internal_router(state: SharedState) -> Router {
    internal_routes()
        .layer(middleware::from_fn_with_state(
            state.clone(),
            reject_overloaded_internal_writes,
        ))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            track_http_metrics,
        ))
        .layer(middleware::map_response(guard_response_stream_transport))
        .with_state(state)
}

#[cfg(test)]
pub fn combined_router(state: SharedState) -> Router {
    public_routes()
        .merge(internal_routes())
        .layer(middleware::from_fn_with_state(
            state.clone(),
            authorize_request,
        ))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            track_http_metrics,
        ))
        .layer(middleware::map_response(guard_response_stream_transport))
        .with_state(state)
}

pub(crate) async fn guard_response_stream_transport(mut response: Response) -> Response {
    let Some(guard) = response.extensions_mut().remove::<ResponseTransportGuard>() else {
        return response;
    };
    let body = std::mem::take(response.body_mut());
    *response.body_mut() = Body::new(ResponseStreamTransportBody { body, guard });
    response
}

struct ResponseStreamTransportBody {
    body: Body,
    guard: ResponseTransportGuard,
}

impl HttpBody for ResponseStreamTransportBody {
    type Data = Bytes;
    type Error = axum::Error;

    fn poll_frame(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Self::Data>, Self::Error>>> {
        match Pin::new(&mut self.body).poll_frame(cx) {
            Poll::Ready(Some(Ok(frame))) => {
                let guard = self.guard.clone();
                Poll::Ready(Some(Ok(frame.map_data(|bytes| {
                    Bytes::from_owner(ResponseStreamTransportBytes {
                        bytes,
                        _guard: guard,
                    })
                }))))
            }
            other => other,
        }
    }

    fn is_end_stream(&self) -> bool {
        self.body.is_end_stream()
    }

    fn size_hint(&self) -> SizeHint {
        self.body.size_hint()
    }
}

struct ResponseStreamTransportBytes {
    bytes: Bytes,
    _guard: ResponseTransportGuard,
}

impl AsRef<[u8]> for ResponseStreamTransportBytes {
    fn as_ref(&self) -> &[u8] {
        self.bytes.as_ref()
    }
}

fn attach_response_stream_permit(response: &mut Response, permit: ResponseStreamMemoryPermit) {
    response
        .extensions_mut()
        .insert(permit.into_transport_guard());
}

fn attach_materialized_response_permit(
    response: &mut Response,
    permit: crate::memory::MemoryPermit,
) {
    response
        .extensions_mut()
        .insert(ResponseTransportGuard::from_materialization_permits(vec![
            permit,
        ]));
}

#[cfg(test)]
pub(crate) fn router(state: SharedState) -> Router {
    combined_router(state)
}

fn public_routes() -> Router<SharedState> {
    Router::new()
        .route(ROUTE_UP, get(up))
        .route(ROUTE_READY, get(ready))
        .route(ROUTE_ROLLOUT_STATUS, get(rollout_status))
        .route(ROUTE_STATUS_CLUSTER, get(cluster_status))
        .route(ROUTE_METRICS, get(metrics_handler))
        .route(ROUTE_V1_CACHE, get(get_nx).put(put_nx))
        .route(ROUTE_API_METRO_CACHE, get(get_metro).put(put_metro))
        .route(ROUTE_API_CACHE_KEYVALUE_ID, get(get_keyvalue))
        .route(ROUTE_API_CACHE_KEYVALUE, put(put_keyvalue))
        .route(ROUTE_API_CACHE_CAS, get(get_xcode).post(put_xcode))
        .route(ROUTE_API_CACHE_MODULE, head(head_module).get(get_module))
        .route(ROUTE_API_CACHE_MODULE_START, post(start_module_upload))
        .route(ROUTE_API_CACHE_MODULE_PART, post(upload_module_part))
        .route(
            ROUTE_API_CACHE_MODULE_COMPLETE,
            post(complete_module_upload),
        )
        .route(ROUTE_API_CACHE_CLEAN, delete(clean_namespace))
        .route(ROUTE_API_CACHE_GRADLE, get(get_gradle).put(put_gradle))
}

fn internal_routes() -> Router<SharedState> {
    Router::new()
        .route(ROUTE_INTERNAL_STATUS, get(internal_status))
        .route(
            ROUTE_INTERNAL_BACKFILL_ENTRIES,
            get(internal_backfill_entries),
        )
        .route(
            ROUTE_INTERNAL_BACKFILL_BODIES,
            post(internal_backfill_bodies),
        )
        .route(
            ROUTE_INTERNAL_BACKFILL_ARTIFACT,
            get(internal_backfill_artifact),
        )
        .route(
            ROUTE_INTERNAL_REPLICATE_ARTIFACT,
            put(internal_replicate_artifact),
        )
        .route(
            ROUTE_INTERNAL_REPLICATE_ARTIFACTS,
            put(internal_replicate_artifacts),
        )
        .route(
            ROUTE_INTERNAL_REPLICATE_NAMESPACE,
            delete(internal_delete_namespace),
        )
}

const NX_NAMESPACE_ID: &str = "nx";
const METRO_NAMESPACE_ID: &str = "metro";
const TENANT_SCOPE_NAMESPACE_ID: &str = "";

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
enum NamespaceScope {
    Account,
    Project,
}

#[derive(Debug, PartialEq, Eq)]
struct NamespaceQuery {
    tenant_id: String,
    namespace_id: String,
    scope: NamespaceScope,
}

impl NamespaceQuery {
    fn from_params(params: &HashMap<String, String>) -> Result<Self, String> {
        let namespace_id = param_value(params, "namespace_id")
            .cloned()
            .unwrap_or_else(|| TENANT_SCOPE_NAMESPACE_ID.to_owned());
        Ok(Self {
            tenant_id: required_param(params, "tenant_id")?,
            scope: if namespace_id.is_empty() {
                NamespaceScope::Account
            } else {
                NamespaceScope::Project
            },
            namespace_id,
        })
    }

    fn project_analytics_context(&self) -> Option<ProjectAnalyticsContext<'_>> {
        match self.scope {
            NamespaceScope::Account => None,
            NamespaceScope::Project => Some(ProjectAnalyticsContext {
                tenant_id: &self.tenant_id,
                namespace_id: &self.namespace_id,
            }),
        }
    }

    fn usage_context(&self) -> UsageContext {
        UsageContext {
            tenant_id: self.tenant_id.clone(),
            namespace_id: self.namespace_id.clone(),
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
struct ModuleQuery {
    namespace: NamespaceQuery,
    cache_category: String,
    hash: String,
    name: String,
}

impl ModuleQuery {
    fn from_params(params: &HashMap<String, String>) -> Result<Self, String> {
        Ok(Self {
            namespace: NamespaceQuery::from_params(params)?,
            cache_category: params
                .get("cache_category")
                .cloned()
                .unwrap_or_else(|| "builds".into()),
            hash: required_param(params, "hash")?,
            name: required_param(params, "name")?,
        })
    }

    fn artifact_key(&self) -> String {
        module_key(&self.cache_category, &self.hash, &self.name)
    }
}

#[derive(Debug, PartialEq, Eq)]
struct UploadPartQuery {
    upload_id: String,
    part_number: u32,
}

impl UploadPartQuery {
    fn from_params(params: &HashMap<String, String>) -> Result<Self, String> {
        let upload_id = required_param(params, "upload_id")?;
        let part_number = params
            .get("part_number")
            .and_then(|value| value.parse::<u32>().ok())
            .ok_or_else(|| "Invalid part_number".to_string())?;

        Ok(Self {
            upload_id,
            part_number,
        })
    }
}

#[derive(Debug, Deserialize)]
struct CompleteMultipartRequest {
    parts: Vec<u32>,
}

#[derive(Debug, Deserialize)]
struct KeyValuePutRequest {
    cas_id: String,
    entries: Vec<KeyValueEntry>,
}

#[derive(Debug, Deserialize)]
struct KeyValueEntry {
    value: String,
}

#[derive(Debug, PartialEq, Eq)]
struct UploadIdQuery {
    upload_id: String,
}

impl UploadIdQuery {
    fn from_params(params: &HashMap<String, String>) -> Result<Self, String> {
        Ok(Self {
            upload_id: required_param(params, "upload_id")?,
        })
    }
}

#[derive(Debug, PartialEq, Eq)]
struct ReplicateArtifactQuery {
    producer: String,
    inline: bool,
    namespace_id: String,
    key: String,
    content_type: String,
    version_ms: u64,
    /// The origin's branch tag and the publishing build's trunk. Both optional:
    /// a peer that predates them (or any untagged publish) omits them and the
    /// entry applies untagged, which is what this node did for every replicated
    /// entry before.
    branch: Option<String>,
    trunk: Option<String>,
}

#[derive(Clone, Copy)]
struct ProjectAnalyticsContext<'a> {
    tenant_id: &'a str,
    namespace_id: &'a str,
}

#[derive(Clone)]
struct UsageContext {
    tenant_id: String,
    namespace_id: String,
}

#[derive(Clone)]
struct BlobPutSpec<'a> {
    namespace_id: &'a str,
    key: &'a str,
    analytics_key: Option<&'a str>,
    max_bytes: u64,
    success_status: StatusCode,
    existing_status: StatusCode,
    analytics: Option<ProjectAnalyticsContext<'a>>,
    usage: Option<UsageContext>,
}

#[derive(Debug, PartialEq, Eq)]
struct BackfillEntriesQuery {
    after: Option<Vec<u8>>,
    limit: usize,
}

impl BackfillEntriesQuery {
    fn from_params(params: &HashMap<String, String>) -> Result<Self, String> {
        let after = params
            .get("after")
            .filter(|value| !value.is_empty())
            .map(|value| {
                let key = hex::decode(value).map_err(|error| format!("Invalid after: {error}"))?;
                if !key.starts_with(BACKFILL_IDX_PREFIX.as_bytes()) {
                    return Err("Invalid after: not a backfill index cursor".to_owned());
                }
                Ok(key)
            })
            .transpose()?;
        let limit = params
            .get("limit")
            .map(|value| {
                value
                    .parse::<usize>()
                    .map_err(|error| format!("Invalid limit: {error}"))
            })
            .transpose()?
            .unwrap_or(256);
        if limit == 0 {
            return Err("Invalid limit: must be greater than 0".to_owned());
        }
        // Clamped rather than rejected: the ceiling bounds one response's
        // work, and a requester asking for more just pages more often.
        Ok(Self {
            after,
            limit: limit.min(MAX_PEER_PAGE_ITEMS),
        })
    }
}

/// Wire page of the backfill listing endpoint (the `ManifestPage` shape).
/// `next_after` is the hex-encoded raw index key of the last returned row,
/// opaque to requesters and fed back as the next request's `after`; `None`
/// means the index is exhausted.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BackfillEntriesPage {
    pub entries: Vec<BackfillEntry>,
    pub next_after: Option<String>,
}

/// One backfill index tuple on the wire. `record_kind` is a
/// [`crate::utils::BackfillRecordKind::as_str`] name; `size` is absent for
/// namespace tombstones (no body to fetch).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BackfillEntry {
    pub record_kind: String,
    pub record_id: String,
    pub version_ms: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub size: Option<u64>,
}

impl From<BackfillIndexPage> for BackfillEntriesPage {
    fn from(page: BackfillIndexPage) -> Self {
        Self {
            entries: page
                .entries
                .into_iter()
                .map(|row| BackfillEntry {
                    record_kind: row.kind.as_str().to_owned(),
                    record_id: row.record_id,
                    version_ms: row.version_ms,
                    size: row.size,
                })
                .collect(),
            next_after: page.next_after.map(hex::encode),
        }
    }
}

/// The `error` discriminant of [`BackfillUnavailable`] while the per-entry
/// index build has not yet covered the pre-existing dataset.
pub const BACKFILL_ERROR_INDEX_BUILDING: &str = "index_building";

/// Typed 503 body of the backfill listing endpoint. Requesters match `error`
/// against [`BACKFILL_ERROR_INDEX_BUILDING`] to treat the peer as not yet
/// capable (retry later) rather than failing, distinct from the generic
/// `{"message": ...}` error shape.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BackfillUnavailable {
    pub error: String,
    pub message: String,
}

/// The [`BackfillUnavailable`] discriminant for a bodies request rejected by
/// the serving-side per-peer-identity concurrency cap: another request from
/// the same client-certificate identity is still in flight.
pub const BACKFILL_ERROR_PEER_BUSY: &str = "peer_busy";

/// The [`BackfillUnavailable`] discriminant for a bodies request shed because
/// the serving node's shared tmp spool budget has no room. Backpressure, not
/// failure: requesters retry with backoff without charging their failure
/// budget.
pub const BACKFILL_ERROR_TMP_BUDGET_EXHAUSTED: &str = "tmp_budget_exhausted";

/// Request body of `POST /_internal/backfill/bodies`: the explicit tuples to
/// fetch, composed byte-bounded by the requester from listed sizes against
/// [`crate::constants::BACKFILL_BODIES_BATCH_BYTES`]. Entries reuse the
/// listing tuple shape; a listed `size` is accepted and ignored (the serving
/// side re-resolves sizes from current manifests). Tombstone kinds are
/// rejected — tombstones are metadata-only and never fetched here.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BackfillBodiesRequest {
    pub entries: Vec<BackfillEntry>,
}

/// How a requested tuple resolved in a bodies response frame.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BackfillBodyDisposition {
    /// The record's current body follows the header.
    Present,
    /// The record has no current body (deleted/evicted since listing, or the
    /// requested row was dangling). Never an error: the requester marks the
    /// tuple and moves on.
    Absent,
    /// The record's current body exceeds the batch byte ceiling; fetch it via
    /// `GET /_internal/backfill/artifacts/{id}`. A defensive backstop — the
    /// requester already routes oversized entries there using listed sizes,
    /// so this only fires when an entry grew past the ceiling (or past the
    /// batch's remaining room) between listing and fetch.
    FetchIndividually,
}

impl BackfillBodyDisposition {
    pub fn as_byte(self) -> u8 {
        match self {
            Self::Present => 0,
            Self::Absent => 1,
            Self::FetchIndividually => 2,
        }
    }

    // Decode-side half of the frame codec.
    pub fn from_byte(byte: u8) -> Option<Self> {
        match byte {
            0 => Some(Self::Present),
            1 => Some(Self::Absent),
            2 => Some(Self::FetchIndividually),
            _ => None,
        }
    }
}

/// Fixed header length of one bodies-stream frame; see
/// [`encode_backfill_body_frame_header`] for the layout.
pub const BACKFILL_BODY_FRAME_HEADER_BYTES: usize = 1 + 1 + 2 + 8 + 2 + 8;

/// Manifest identity of a `Present` frame's body, resolved from the CURRENT
/// manifest together with the body (the same read that stamps the frame's
/// `version_ms`). The live apply paths key artifacts by
/// (producer, namespace, key) — `artifact_id` is an irreversible hash of them
/// — so the requester cannot apply a body without this block.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BackfillBodyManifestMeta {
    pub producer: String,
    pub namespace_id: String,
    pub key: String,
    pub content_type: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
}

impl BackfillBodyManifestMeta {
    pub fn from_manifest(manifest: &ArtifactManifest) -> Self {
        Self {
            producer: manifest.producer.as_str().to_owned(),
            namespace_id: manifest.namespace_id.clone(),
            key: manifest.key.clone(),
            content_type: manifest.content_type.clone(),
            branch: manifest.branch.clone(),
        }
    }

    pub fn to_wire_bytes(&self) -> Result<Vec<u8>, String> {
        serde_json::to_vec(self)
            .map_err(|error| format!("failed to encode backfill manifest meta: {error}"))
    }
}

/// One item of a batched replication request. The batch carries only inline
/// artifacts (the metadata lane), so there is no `inline` flag and no segment
/// path: every body is present in the frame.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReplicateBatchItemMeta {
    pub producer: String,
    pub namespace_id: String,
    pub key: String,
    pub content_type: String,
    pub version_ms: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trunk: Option<String>,
}

/// Per-item result of a batched replication request, in request order. An
/// entry that is not `error` means the peer is done with that item (it applied
/// it, or ignored it as not newer), so the sender may clear its outbox
/// message; `error` leaves the message queued for retry. Reporting per item is
/// what keeps one poison item from stranding everything batched with it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReplicateBatchOutcomes {
    pub outcomes: Vec<String>,
}

/// Fixed header of one batched replication frame: `meta_len` then `body_len`,
/// both big-endian. Bodies are inline artifacts, bounded by
/// `MAX_INLINE_REPLICATION_BODY_BYTES`, so a u32 length is sufficient.
pub const REPLICATE_BATCH_FRAME_HEADER_BYTES: usize = 4 + 4;

pub fn encode_replicate_batch_frame(meta: &[u8], body: &[u8]) -> Result<Vec<u8>, String> {
    let meta_len = u32::try_from(meta.len()).map_err(|_| {
        format!(
            "replication batch meta of {} bytes is too large",
            meta.len()
        )
    })?;
    let body_len = u32::try_from(body.len()).map_err(|_| {
        format!(
            "replication batch body of {} bytes is too large",
            body.len()
        )
    })?;
    let mut frame =
        Vec::with_capacity(REPLICATE_BATCH_FRAME_HEADER_BYTES + meta.len() + body.len());
    frame.extend_from_slice(&meta_len.to_be_bytes());
    frame.extend_from_slice(&body_len.to_be_bytes());
    frame.extend_from_slice(meta);
    frame.extend_from_slice(body);
    Ok(frame)
}

/// Splits a batched replication body into its frames. Returns an error rather
/// than a partial list when the buffer is truncated or a length overruns it, so
/// a malformed request is rejected whole instead of silently applying a prefix.
pub fn decode_replicate_batch_frames(
    mut buffer: &[u8],
) -> Result<Vec<(ReplicateBatchItemMeta, Vec<u8>)>, String> {
    let mut items = Vec::new();
    while !buffer.is_empty() {
        if buffer.len() < REPLICATE_BATCH_FRAME_HEADER_BYTES {
            return Err("replication batch frame header is truncated".to_owned());
        }
        let meta_len = u32::from_be_bytes(buffer[0..4].try_into().expect("fixed slice")) as usize;
        let body_len = u32::from_be_bytes(buffer[4..8].try_into().expect("fixed slice")) as usize;
        let rest = &buffer[REPLICATE_BATCH_FRAME_HEADER_BYTES..];
        let payload_len = meta_len
            .checked_add(body_len)
            .ok_or_else(|| "replication batch frame lengths overflow".to_owned())?;
        if rest.len() < payload_len {
            return Err("replication batch frame payload is truncated".to_owned());
        }
        let meta: ReplicateBatchItemMeta = serde_json::from_slice(&rest[..meta_len])
            .map_err(|error| format!("failed to decode replication batch meta: {error}"))?;
        items.push((meta, rest[meta_len..payload_len].to_vec()));
        buffer = &rest[payload_len..];
    }
    Ok(items)
}

/// Encodes one frame header of the bodies response stream. This function and
/// [`read_backfill_body_frame_prelude`] are the single definition of the wire
/// layout — the requester decodes with the same code, so the two can never
/// skew.
///
/// Frame layout (integers big-endian):
///
/// | field        | width          | contents                                   |
/// |--------------|----------------|--------------------------------------------|
/// | `kind`       | 1 byte         | [`BackfillRecordKind::as_byte`]            |
/// | `disposition`| 1 byte         | [`BackfillBodyDisposition::as_byte`]       |
/// | `id_len`     | 2 bytes        | length of `record_id`                      |
/// | `version_ms` | 8 bytes        | see below                                  |
/// | `meta_len`   | 2 bytes        | manifest meta bytes; 0 unless `Present`    |
/// | `body_len`   | 8 bytes        | body bytes following; 0 unless `Present`   |
/// | `record_id`  | `id_len` bytes | UTF-8 record id                            |
/// | meta         | `meta_len`     | [`BackfillBodyManifestMeta`] JSON          |
/// | body         | `body_len`     | raw body bytes (`Present` frames only)     |
///
/// `version_ms` (and meta) semantics are load-bearing:
/// - `Present`: the effective version of the CURRENT manifest at body-read
///   time, resolved together with the body — NEVER echoed from the request.
///   Echoing would let a mid-flight LWW overwrite persist v2 bytes under a v1
///   stamp on the requester, whose presence check would then suppress the
///   correcting re-fetch. `kind` and the manifest meta likewise describe the
///   current manifest (a record can flip inline<->segment across versions).
/// - `Absent` / `FetchIndividually`: the REQUESTED tuple's version and kind,
///   echoed to identify which tuple resolved that way (one batch can carry
///   the same record id under two listed versions when a dangling row
///   coexists with the live one). No meta: there is no body to apply.
pub fn encode_backfill_body_frame_header(
    kind: BackfillRecordKind,
    disposition: BackfillBodyDisposition,
    version_ms: u64,
    record_id: &str,
    meta: &[u8],
    body_len: u64,
) -> Result<Vec<u8>, String> {
    let id_len = u16::try_from(record_id.len()).map_err(|_| {
        format!(
            "record id length {} exceeds the frame limit",
            record_id.len()
        )
    })?;
    let meta_len = u16::try_from(meta.len()).map_err(|_| {
        format!(
            "manifest meta length {} exceeds the frame limit",
            meta.len()
        )
    })?;
    let mut header =
        Vec::with_capacity(BACKFILL_BODY_FRAME_HEADER_BYTES + record_id.len() + meta.len());
    header.push(kind.as_byte());
    header.push(disposition.as_byte());
    header.extend_from_slice(&id_len.to_be_bytes());
    header.extend_from_slice(&version_ms.to_be_bytes());
    header.extend_from_slice(&meta_len.to_be_bytes());
    header.extend_from_slice(&body_len.to_be_bytes());
    header.extend_from_slice(record_id.as_bytes());
    header.extend_from_slice(meta);
    Ok(header)
}

/// One decoded frame of the bodies response stream.
// The pass driver decodes preludes and streams bodies; the whole-frame
// decode exists for codec and endpoint tests.
#[allow(dead_code)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackfillBodyFrame {
    pub kind: BackfillRecordKind,
    pub disposition: BackfillBodyDisposition,
    pub record_id: String,
    pub version_ms: u64,
    pub meta: Option<BackfillBodyManifestMeta>,
    pub body: Vec<u8>,
}

/// Everything of one frame except the body bytes, which follow on the reader
/// (`body_len` of them). Lets the requester stream large `Present` bodies to
/// disk instead of buffering them.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackfillBodyFramePrelude {
    pub kind: BackfillRecordKind,
    pub disposition: BackfillBodyDisposition,
    pub record_id: String,
    pub version_ms: u64,
    pub meta: Option<BackfillBodyManifestMeta>,
    pub body_len: u64,
}

/// Reads one frame's prelude off a bodies (or per-artifact) response stream;
/// `Ok(None)` on clean end of stream. The caller must consume exactly
/// `body_len` following bytes before reading the next frame.
/// `max_body_bytes` bounds a declared body so a mismatched peer cannot make
/// the receiver stage more than the caller accounted:
/// [`crate::constants::BACKFILL_BODIES_BATCH_BYTES`] for batch streams,
/// [`crate::constants::MAX_REPLICATION_BODY_BYTES`] for individual fetches.
pub async fn read_backfill_body_frame_prelude<R>(
    reader: &mut R,
    max_body_bytes: u64,
) -> Result<Option<BackfillBodyFramePrelude>, String>
where
    R: tokio::io::AsyncRead + Unpin,
{
    use tokio::io::AsyncReadExt;

    let mut header = [0u8; BACKFILL_BODY_FRAME_HEADER_BYTES];
    let mut filled = 0;
    while filled < header.len() {
        let read = reader
            .read(&mut header[filled..])
            .await
            .map_err(|error| format!("failed to read backfill body frame header: {error}"))?;
        if read == 0 {
            if filled == 0 {
                return Ok(None);
            }
            return Err("truncated backfill body frame header".to_owned());
        }
        filled += read;
    }

    let kind = BackfillRecordKind::from_byte(header[0])
        .ok_or_else(|| format!("unknown backfill record kind byte {}", header[0]))?;
    let disposition = BackfillBodyDisposition::from_byte(header[1])
        .ok_or_else(|| format!("unknown backfill body disposition byte {}", header[1]))?;
    let id_len = u16::from_be_bytes(header[2..4].try_into().expect("fixed slice"));
    let version_ms = u64::from_be_bytes(header[4..12].try_into().expect("fixed slice"));
    let meta_len = u16::from_be_bytes(header[12..14].try_into().expect("fixed slice"));
    let body_len = u64::from_be_bytes(header[14..22].try_into().expect("fixed slice"));
    if id_len == 0 {
        return Err("backfill body frame carries an empty record id".to_owned());
    }
    if disposition != BackfillBodyDisposition::Present && (body_len != 0 || meta_len != 0) {
        return Err(format!(
            "backfill body frame with disposition byte {} carries a body or manifest meta",
            header[1]
        ));
    }
    if disposition == BackfillBodyDisposition::Present && meta_len == 0 {
        return Err("backfill present frame is missing its manifest meta".to_owned());
    }
    if body_len > max_body_bytes {
        return Err(format!(
            "backfill body frame length {body_len} exceeds the ceiling {max_body_bytes}"
        ));
    }

    let mut record_id = vec![0u8; id_len as usize];
    reader
        .read_exact(&mut record_id)
        .await
        .map_err(|error| format!("failed to read backfill body frame record id: {error}"))?;
    let record_id = String::from_utf8(record_id)
        .map_err(|error| format!("invalid backfill body frame record id: {error}"))?;
    let meta = if meta_len > 0 {
        let mut meta = vec![0u8; meta_len as usize];
        reader
            .read_exact(&mut meta)
            .await
            .map_err(|error| format!("failed to read backfill body frame meta: {error}"))?;
        Some(
            serde_json::from_slice::<BackfillBodyManifestMeta>(&meta)
                .map_err(|error| format!("invalid backfill body frame meta: {error}"))?,
        )
    } else {
        None
    };

    Ok(Some(BackfillBodyFramePrelude {
        kind,
        disposition,
        record_id,
        version_ms,
        meta,
        body_len,
    }))
}

/// Reads one whole frame — body buffered in memory — off a bodies response
/// stream; `Ok(None)` on clean end of stream. Enforces the same
/// [`crate::constants::BACKFILL_BODIES_BATCH_BYTES`] ceiling the sender
/// spools under, so a mismatched peer cannot make the receiver buffer more
/// than the shared bound.
// See BackfillBodyFrame: kept for codec and endpoint tests.
#[allow(dead_code)]
pub async fn read_backfill_body_frame<R>(
    reader: &mut R,
) -> Result<Option<BackfillBodyFrame>, String>
where
    R: tokio::io::AsyncRead + Unpin,
{
    use tokio::io::AsyncReadExt;

    let Some(prelude) =
        read_backfill_body_frame_prelude(reader, BACKFILL_BODIES_BATCH_BYTES).await?
    else {
        return Ok(None);
    };
    let mut body = vec![0u8; prelude.body_len as usize];
    reader
        .read_exact(&mut body)
        .await
        .map_err(|error| format!("failed to read backfill body frame body: {error}"))?;

    Ok(Some(BackfillBodyFrame {
        kind: prelude.kind,
        disposition: prelude.disposition,
        record_id: prelude.record_id,
        version_ms: prelude.version_ms,
        meta: prelude.meta,
        body,
    }))
}

impl ReplicateArtifactQuery {
    fn from_params(params: &HashMap<String, String>) -> Result<Self, String> {
        Ok(Self {
            producer: required_param(params, "producer")?,
            inline: params
                .get("inline")
                .map(|value| {
                    value
                        .parse::<bool>()
                        .map_err(|error| format!("Invalid inline: {error}"))
                })
                .transpose()?
                .unwrap_or(false),
            namespace_id: required_raw_param(params, "namespace_id")?,
            key: required_param(params, "key")?,
            content_type: required_param(params, "content_type")?,
            version_ms: optional_u64_param(params, "version_ms")?.unwrap_or_default(),
            branch: param_value(params, "branch").cloned(),
            trunk: param_value(params, "trunk").cloned(),
        })
    }
}

fn alias_keys(key: &str) -> &'static [&'static str] {
    match key {
        "tenant_id" => &["account_handle"],
        "namespace_id" => &["project_handle"],
        _ => &[],
    }
}

fn raw_param_value<'a>(params: &'a HashMap<String, String>, key: &str) -> Option<&'a String> {
    params
        .get(key)
        .or_else(|| alias_keys(key).iter().find_map(|alias| params.get(*alias)))
}

fn param_value<'a>(params: &'a HashMap<String, String>, key: &str) -> Option<&'a String> {
    raw_param_value(params, key).filter(|value| !value.is_empty())
}

fn required_param(params: &HashMap<String, String>, key: &str) -> Result<String, String> {
    param_value(params, key)
        .cloned()
        .ok_or_else(|| format!("Missing {key}"))
}

fn required_raw_param(params: &HashMap<String, String>, key: &str) -> Result<String, String> {
    raw_param_value(params, key)
        .cloned()
        .ok_or_else(|| format!("Missing {key}"))
}

fn optional_u64_param(params: &HashMap<String, String>, key: &str) -> Result<Option<u64>, String> {
    params
        .get(key)
        .map(|value| {
            value
                .parse::<u64>()
                .map_err(|error| format!("Invalid {key}: {error}"))
        })
        .transpose()
}

fn request_route(req: &Request) -> String {
    req.extensions()
        .get::<MatchedPath>()
        .map(|path| path.as_str().to_owned())
        .unwrap_or_else(|| route_template_for_path(req.uri().path()).to_owned())
}

fn route_template_for_path(path: &str) -> &'static str {
    if let Some(route) = EXACT_ROUTE_TEMPLATES
        .iter()
        .copied()
        .find(|route| *route == path)
    {
        return route;
    }

    DYNAMIC_ROUTE_TEMPLATES
        .iter()
        .copied()
        .find(|route| one_segment_after_route_prefix(path, route))
        .unwrap_or(UNMATCHED_ROUTE)
}

fn one_segment_after_route_prefix(path: &str, route: &str) -> bool {
    route
        .find('{')
        .is_some_and(|parameter_start| one_segment_after_prefix(path, &route[..parameter_start]))
}

fn one_segment_after_prefix(path: &str, prefix: &str) -> bool {
    path.strip_prefix(prefix)
        .is_some_and(|segment| !segment.is_empty() && !segment.contains('/'))
}

async fn track_http_metrics(
    State(state): State<SharedState>,
    mut req: Request,
    next: Next,
) -> Response {
    let started_at = Instant::now();
    let route = request_route(&req);
    let traffic_class = if is_public_load_route(&route) {
        HttpTrafficClass::Public
    } else {
        HttpTrafficClass::Background
    };
    let _request_guard = state.start_http_request(traffic_class);
    let method = req.method().to_string();
    let request_id = request_id(
        req.headers()
            .get(REQUEST_ID_HEADER)
            .and_then(|value| value.to_str().ok()),
    );
    let request_id_header = HeaderValue::from_str(&request_id)
        .expect("generated or validated request id should be a valid header value");
    req.headers_mut()
        .insert(REQUEST_ID_HEADER, request_id_header.clone());
    let uri_path = req.uri().path().to_owned();

    let request_span = tracing::info_span!(
        "http.request",
        otel.name = %format!("{method} {route}"),
        otel.kind = "server",
        http.request.method = %method,
        http.request.id = %request_id,
        http.route = %route,
        url.path = %uri_path,
        http.response.status_code = field::Empty,
        otel.status_code = field::Empty,
        trace_id = field::Empty,
        span_id = field::Empty,
    );
    attach_parent_context(&request_span, req.headers());
    record_trace_context(&request_span);

    let request_context = RequestContext::new(
        started_at,
        request_id,
        method,
        route.clone(),
        RequestLogPolicy {
            sample_rate: state.config.request_log_sample_rate,
            slow_request_threshold: Duration::from_millis(state.config.slow_request_threshold_ms),
            warning_log_interval: Duration::from_millis(state.config.warning_log_interval_ms),
        },
        request_span.clone(),
    );
    let mut response = scope_request(
        request_context.clone(),
        next.run(req).instrument(request_span.clone()),
    )
    .await;
    request_span.record("http.response.status_code", response.status().as_u16());
    if response.status().is_server_error() {
        request_span.record("otel.status_code", "ERROR");
    }
    response
        .headers_mut()
        .insert(REQUEST_ID_HEADER, request_id_header);

    let elapsed = request_context.started_at().elapsed();
    if traffic_class == HttpTrafficClass::Public {
        state
            .runtime
            .record_public_request_latency(&state.metrics, "http", &route, elapsed);
    }
    state.metrics.record_http(route, response.status(), elapsed);

    if response
        .extensions()
        .get::<ObservedStreamingResponse>()
        .is_none()
    {
        let response_bytes = response
            .headers()
            .get(axum::http::header::CONTENT_LENGTH)
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(0);
        let result = if response.status().is_server_error() {
            "server_error"
        } else {
            "ok"
        };
        log_request_completion(
            &request_context,
            RequestCompletion {
                status: response.status().as_u16(),
                response_bytes,
                time_to_first_byte: elapsed,
                total_duration: elapsed,
                serving_path: "handler",
                result,
                error: None,
            },
        );
    }

    response
}

#[derive(Clone, Copy)]
struct ObservedStreamingResponse;

fn is_public_load_route(route: &str) -> bool {
    !is_probe_route(route) && !route.starts_with("/_internal/") && route != UNMATCHED_ROUTE
}

async fn reject_draining_public_requests(
    State(state): State<SharedState>,
    req: Request,
    next: Next,
) -> Response {
    let route = request_route(&req);
    let version = req.version();

    if !is_probe_route(&route) && state.runtime.is_draining() {
        return draining_response(version);
    }

    let mut response = next.run(req).await;
    if state.runtime.is_draining() && is_http1(version) {
        response.headers_mut().insert(
            axum::http::header::CONNECTION,
            HeaderValue::from_static("close"),
        );
    }
    response
}

/// Turns away public writes at the door when the node is already known to be
/// out of room, so a saturated pod spends nothing on a body it will not keep.
///
/// This is a fast path, **not** an admission guarantee. The outbox arm compares
/// the current depth against the cap as a single slot, while each store write
/// then reserves one slot per replication target atomically
/// (`Store::reserve_outbox_slots`). A write admitted here still loses when the
/// remaining room is smaller than the target count, or when another write wins
/// the race. Every persistence path therefore has to map `is_outbox_full_error`
/// to a shed of its own; leaving one on 503 puts a healthy saturated node back
/// on the 5xx alert.
async fn reject_overloaded_public_writes(
    State(state): State<SharedState>,
    req: Request,
    next: Next,
) -> Response {
    let method = req.method().clone();
    let route = request_route(&req);

    if is_write_method(&method) && !is_probe_route(&route) {
        if state.memory.pressure() == MemoryPressure::Critical {
            state
                .metrics
                .record_memory_action("write_rejected_critical");
            return capacity_shed_response(
                &state.metrics,
                "memory_pressure_write",
                "server is shedding writes due to memory pressure",
            );
        }
        if state.store.outbox_depth() >= state.config.outbox_max_depth {
            state.metrics.record_memory_action("write_rejected_outbox");
            return capacity_shed_response(
                &state.metrics,
                "outbox",
                "server is shedding writes while replication catches up",
            );
        }
    }

    next.run(req).await
}

/// Fast-fails peer replication writes (PUT /_internal/replicate/artifact,
/// DELETE /_internal/replicate/namespace) when the pod is under Critical
/// memory pressure. Without this guard the pod accepts the TCP connection but
/// stalls while processing the body, so the source peer sees no progress and
/// abandons the attempt only when its upload stall watchdog expires
/// (`KURA_REPLICATION_UPLOAD_STALL_MS`, 60 s by default) — one stalled
/// receiver holding up a drain loop that is serial and node-wide. Returning
/// 503 lets the source retry immediately with its normal 2-second backoff.
/// Reads (backfill, status) are unaffected.
async fn reject_overloaded_internal_writes(
    State(state): State<SharedState>,
    req: Request,
    next: Next,
) -> Response {
    if is_write_method(req.method()) && state.memory.pressure() == MemoryPressure::Critical {
        state
            .metrics
            .record_memory_action("internal_write_rejected_critical");
        return overloaded_response("server is shedding replication writes due to memory pressure");
    }

    next.run(req).await
}

fn is_write_method(method: &axum::http::Method) -> bool {
    matches!(
        method,
        &axum::http::Method::POST
            | &axum::http::Method::PUT
            | &axum::http::Method::DELETE
            | &axum::http::Method::PATCH
    )
}

/// Sheds a public request the node is declining because one of its capacity
/// limits is full: active multipart uploads, incomplete multipart storage,
/// upload memory, or the replication outbox.
///
/// The node is healthy and the same request succeeds once the limit drains, so
/// this is 429 rather than a 5xx. A 5xx here is indistinguishable from a store
/// fault on the same route, and pages as one: on 2026-08-24 a single container
/// life on `kura-tuist-scw-fr-par-0` answered 568 module-route requests with
/// the multipart shed and 218 with a success, and the shed was read as a
/// broken store.
fn capacity_shed_response(metrics: &Metrics, kind: &str, message: &str) -> Response {
    metrics.record_capacity_shed(kind);
    let mut response = error_response(StatusCode::TOO_MANY_REQUESTS, message);
    retry_after(
        &mut response,
        backpressure::retry_after_seconds(backpressure::IDLE_RETRY_AFTER_CEILING_SECONDS),
    );
    response
}

/// The 503 counterpart, for the two cases 429 would misdescribe: peer
/// replication writes, which carry no client-facing error signal and whose
/// source already treats 503 plus `Retry-After` as backpressure, and genuine
/// resource exhaustion (file descriptors, disk), which is a fault a responder
/// has to be paged for rather than backpressure a client should retry through.
fn overloaded_response(message: &str) -> Response {
    let mut response = error_response(StatusCode::SERVICE_UNAVAILABLE, message);
    retry_after(
        &mut response,
        backpressure::retry_after_seconds(backpressure::IDLE_RETRY_AFTER_CEILING_SECONDS),
    );
    response
}

fn retry_after(response: &mut Response, seconds: u64) {
    if let Ok(value) = HeaderValue::from_str(&seconds.to_string()) {
        response
            .headers_mut()
            .insert(axum::http::header::RETRY_AFTER, value);
    }
}

async fn authorize_request(State(state): State<SharedState>, req: Request, next: Next) -> Response {
    let Some(auth) = state.auth.as_ref() else {
        return next.run(req).await;
    };

    let route = request_route(&req);
    if skips_authorization(&route) {
        return next.run(req).await;
    }

    let method = req.method().to_string();
    let query = parse_query_map(req.uri().query());
    let authorization = req
        .headers()
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .map(ToOwned::to_owned);
    let context = request_context_from_http(
        &state,
        HttpRequestFacts {
            route: &route,
            method: &method,
            query: &query,
            authorization,
        },
    )
    .await;

    let access_span = if trace_export_active() {
        tracing::info_span!(
            "kura.auth.access",
            kura.auth.transport = "http",
            kura.auth.route = %route,
            kura.auth.result = field::Empty,
        )
    } else {
        tracing::Span::none()
    };
    let access = auth
        .evaluate_access(&context)
        .instrument(access_span.clone())
        .await;
    match access {
        AccessDecision::Allow => {
            access_span.record("kura.auth.result", "allow");
        }
        AccessDecision::Deny(deny) => {
            access_span.record("kura.auth.result", "deny");
            return error_response(status_from_u16(deny.status), deny.message);
        }
    }

    next.run(req).await
}

fn skips_authorization(route: &str) -> bool {
    is_probe_route(route) || route.starts_with("/_internal/")
}

fn is_probe_route(route: &str) -> bool {
    matches!(
        route,
        ROUTE_UP | ROUTE_READY | ROUTE_ROLLOUT_STATUS | ROUTE_STATUS_CLUSTER | ROUTE_METRICS
    )
}

fn is_http1(version: Version) -> bool {
    matches!(version, Version::HTTP_10 | Version::HTTP_11)
}

async fn request_context_from_http(
    state: &SharedState,
    request: HttpRequestFacts<'_>,
) -> AuthRequestContext {
    let metadata = http_request_metadata(state, request.route, request.method, request.query).await;
    AuthRequestContext {
        transport: "http".into(),
        method: request.method.to_owned(),
        operation: metadata.operation,
        server_tenant_id: state.config.tenant_id.clone(),
        tenant_id: metadata.tenant_id,
        namespace_id: metadata.namespace_id,
        authorization: request.authorization,
        headers: BTreeMap::new(),
        query: BTreeMap::new(),
    }
}

struct HttpRequestFacts<'a> {
    route: &'a str,
    method: &'a str,
    query: &'a HashMap<String, String>,
    authorization: Option<String>,
}

struct HttpRequestMetadata {
    operation: String,
    tenant_id: Option<String>,
    namespace_id: Option<String>,
}

async fn http_request_metadata(
    state: &SharedState,
    route: &str,
    method: &str,
    query: &HashMap<String, String>,
) -> HttpRequestMetadata {
    let tenant_id = param_value(query, "tenant_id").cloned();
    let mut namespace_id = param_value(query, "namespace_id").cloned();

    match route {
        ROUTE_API_CACHE_KEYVALUE_ID => HttpRequestMetadata {
            operation: "artifact.read".into(),
            tenant_id,
            namespace_id,
        },
        ROUTE_API_CACHE_KEYVALUE => HttpRequestMetadata {
            operation: "artifact.write".into(),
            tenant_id,
            namespace_id,
        },
        ROUTE_API_CACHE_CAS => HttpRequestMetadata {
            operation: if method.eq_ignore_ascii_case("GET") {
                "artifact.read"
            } else {
                "artifact.write"
            }
            .into(),
            tenant_id,
            namespace_id,
        },
        ROUTE_API_CACHE_GRADLE => HttpRequestMetadata {
            operation: if method.eq_ignore_ascii_case("GET") {
                "artifact.read"
            } else {
                "artifact.write"
            }
            .into(),
            tenant_id,
            namespace_id,
        },
        ROUTE_API_CACHE_MODULE => HttpRequestMetadata {
            operation: if method.eq_ignore_ascii_case("HEAD") || method.eq_ignore_ascii_case("GET")
            {
                "artifact.read"
            } else {
                "artifact.write"
            }
            .into(),
            tenant_id,
            namespace_id,
        },
        ROUTE_API_CACHE_MODULE_START
        | ROUTE_API_CACHE_MODULE_PART
        | ROUTE_API_CACHE_MODULE_COMPLETE => {
            let multipart_upload = query
                .get("upload_id")
                .and_then(|upload_id| state.store.multipart_upload(upload_id).ok().flatten());
            let tenant_id = multipart_upload
                .as_ref()
                .map(|upload| upload.tenant_id.clone())
                .or(tenant_id);
            if let Some(upload) = multipart_upload.as_ref() {
                namespace_id = if upload.namespace_id.is_empty() {
                    None
                } else {
                    Some(upload.namespace_id.clone())
                };
            }
            HttpRequestMetadata {
                operation: "artifact.write".into(),
                tenant_id,
                namespace_id,
            }
        }
        ROUTE_API_CACHE_CLEAN => HttpRequestMetadata {
            operation: "namespace.delete".into(),
            tenant_id,
            namespace_id,
        },
        ROUTE_V1_CACHE => {
            namespace_id = Some(NX_NAMESPACE_ID.into());
            HttpRequestMetadata {
                operation: if method.eq_ignore_ascii_case("GET") {
                    "artifact.read"
                } else {
                    "artifact.write"
                }
                .into(),
                tenant_id: Some("default".into()),
                namespace_id,
            }
        }
        ROUTE_API_METRO_CACHE => {
            namespace_id = Some(METRO_NAMESPACE_ID.into());
            HttpRequestMetadata {
                operation: if method.eq_ignore_ascii_case("GET") {
                    "artifact.read"
                } else {
                    "artifact.write"
                }
                .into(),
                tenant_id: Some("default".into()),
                namespace_id,
            }
        }
        _ => HttpRequestMetadata {
            operation: "request".into(),
            tenant_id,
            namespace_id,
        },
    }
}

fn parse_query_map(query: Option<&str>) -> HashMap<String, String> {
    query
        .unwrap_or_default()
        .split('&')
        .filter(|pair| !pair.is_empty())
        .map(|pair| match pair.split_once('=') {
            Some((key, value)) => (key.to_string(), value.to_string()),
            None => (pair.to_string(), String::new()),
        })
        .collect()
}

fn status_from_u16(status: u16) -> StatusCode {
    StatusCode::from_u16(status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR)
}

// Liveness. Answers from process-local configuration only: no peer
// round-trips, no cluster aggregation, and no lock a loaded request path can
// hold. A failed probe here restarts the pod, so anything the handler waits
// on turns "this node is busy" into "this node is dead". This route has no
// variant that relaxes that: the node's view of the cluster lives on
// ROUTE_STATUS_CLUSTER, where request classification (which keys off the path
// template, never the query) can tell the two costs apart.
async fn up(State(state): State<SharedState>) -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "ok",
        "tenant_id": state.config.tenant_id.clone(),
        "region": state.config.region.clone(),
        "node": state.config.region.clone(),
        "node_url": state.config.node_url.clone(),
    }))
}

// The node's own view of the cluster. Aggregates under the readiness lock, so
// it is deliberately off the liveness path.
async fn cluster_status(State(state): State<SharedState>) -> impl IntoResponse {
    let cluster = state.cluster_status_report().await;
    let mut regions = cluster.peer_regions;
    regions.push(state.config.region.clone());
    regions.sort();
    regions.dedup();
    let mut nodes = cluster.connected_nodes.clone();
    nodes.push(state.config.node_url.clone());
    nodes.sort();

    Json(serde_json::json!({
        "status": "ok",
        "generation": cluster.generation,
        "tenant_id": state.config.tenant_id.clone(),
        "region": state.config.region.clone(),
        "node": state.config.region.clone(),
        "node_url": state.config.node_url.clone(),
        "connected_nodes": cluster.connected_nodes,
        "ring_members": nodes.len(),
        "members": nodes.clone(),
        "regions": regions,
        "nodes": nodes,
    }))
}

async fn ready(State(state): State<SharedState>) -> impl IntoResponse {
    let readiness = state.readiness_report().await;
    let status = if readiness.ready {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };

    (
        status,
        Json(serde_json::json!({
            "status": if readiness.ready { "ok" } else { "not_ready" },
            "generation": readiness.generation,
            "state": readiness.state.as_str(),
            "ready": readiness.ready,
            "draining": readiness.draining,
            "writer_lock_owned": readiness.writer_lock_owned,
            "initial_discovery_completed": readiness.initial_discovery_completed,
            "known_peers": readiness.known_peers,
            "http_inflight_requests": readiness.http_inflight,
            "grpc_inflight_requests": readiness.grpc_inflight,
            "reasons": readiness.reasons,
        })),
    )
        .into_response()
}

async fn rollout_status(State(state): State<SharedState>) -> impl IntoResponse {
    let status = state.rollout_status_report().await;
    // `backfill_initial_cycle` is the catch-up gate contract consumers
    // (gate.sh, the kura-controller) read: pending | complete | degraded.
    Json(serde_json::json!({
        "generation": status.generation,
        "ready": status.ready,
        "state": status.state.as_str(),
        "ring_members": status.ring_members,
        "ring_fingerprint": status.ring_fingerprint,
        "initial_discovery_completed": status.initial_discovery_completed,
        "writer_lock_owned": status.writer_lock_owned,
        "http_inflight_requests": status.http_inflight,
        "grpc_inflight_requests": status.grpc_inflight,
        "outbox_messages": status.outbox_messages,
        "memory_pressure_state": status.memory_pressure_state,
        "fd_timeout_count": status.fd_timeout_count,
        "peer_connection_failure_count": status.peer_connection_failure_count,
        "backfill_initial_cycle": status.backfill.initial_cycle.as_str(),
        "backfill_backfilling_peers": status.backfill.backfilling_peers,
        "backfill_budget_exhausted_real_peers": status.backfill.budget_exhausted_real,
        "backfill_budget_exhausted_capability_peers": status.backfill.budget_exhausted_capability,
        "backfill_ring_fullness_percent": status.backfill.ring_fullness_percent,
    }))
}

async fn metrics_handler(State(state): State<SharedState>) -> impl IntoResponse {
    (
        [(
            axum::http::header::CONTENT_TYPE,
            HeaderValue::from_static("text/plain; version=0.0.4"),
        )],
        state.metrics.render(),
    )
}

async fn get_keyvalue(
    AxumPath(cas_id): AxumPath<String>,
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
) -> Response {
    let namespace = match NamespaceQuery::from_params(&params) {
        Ok(namespace) => namespace,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };
    let usage = namespace.usage_context();

    let key = action_cache_key(&cas_id);
    match state.store.fetch_inline_artifact_bytes(
        ArtifactProducer::Xcode,
        &namespace.namespace_id,
        &key,
    ) {
        Ok(Some(bytes)) => {
            let permit = match state
                .memory
                .try_acquire_response_materialization(bytes.len())
            {
                Ok(permit) => permit,
                Err(()) => {
                    state
                        .metrics
                        .record_memory_action("keyvalue_response_materialization_rejected");
                    return response_stream_shed(&state.metrics, &state.memory);
                }
            };
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Xcode, "ok", bytes.len() as u64);
            record_usage_event(
                &state,
                ArtifactProducer::Xcode,
                "download",
                Some(&usage),
                bytes.len() as u64,
            );
            let mut response = (
                [(
                    axum::http::header::CONTENT_TYPE,
                    HeaderValue::from_static("application/json"),
                )],
                bytes,
            )
                .into_response();
            if let Some(permit) = permit {
                attach_materialized_response_permit(&mut response, permit);
            }
            response
        }
        Ok(None) => {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Xcode, "not_found", 0);
            error_response(StatusCode::NOT_FOUND, "Key-value entry not found")
        }
        Err(error) => {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Xcode, "error", 0);
            error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                format!("Failed to fetch artifact: {error}"),
            )
        }
    }
}

async fn get_nx(
    AxumPath(hash): AxumPath<String>,
    State(state): State<SharedState>,
    headers: HeaderMap,
) -> Response {
    let usage = UsageContext {
        tenant_id: state.config.tenant_id.clone(),
        namespace_id: NX_NAMESPACE_ID.to_owned(),
    };

    get_artifact(
        state,
        ArtifactProducer::Nx,
        NX_NAMESPACE_ID,
        &hash,
        None,
        None,
        Some(usage),
        request_range(&headers),
    )
    .await
}

async fn put_nx(
    AxumPath(hash): AxumPath<String>,
    State(state): State<SharedState>,
    request: Request,
) -> Response {
    let usage = UsageContext {
        tenant_id: state.config.tenant_id.clone(),
        namespace_id: NX_NAMESPACE_ID.to_owned(),
    };

    put_blob_artifact(
        state,
        ArtifactProducer::Nx,
        request,
        BlobPutSpec {
            namespace_id: NX_NAMESPACE_ID,
            key: &hash,
            analytics_key: None,
            max_bytes: MAX_MODULE_TOTAL_BYTES,
            success_status: StatusCode::OK,
            existing_status: StatusCode::OK,
            analytics: None,
            usage: Some(usage),
        },
    )
    .await
}

async fn get_metro(
    AxumPath(cache_key): AxumPath<String>,
    State(state): State<SharedState>,
    headers: HeaderMap,
) -> Response {
    let usage = UsageContext {
        tenant_id: state.config.tenant_id.clone(),
        namespace_id: METRO_NAMESPACE_ID.to_owned(),
    };

    get_artifact(
        state,
        ArtifactProducer::Metro,
        METRO_NAMESPACE_ID,
        &cache_key,
        None,
        None,
        Some(usage),
        request_range(&headers),
    )
    .await
}

async fn put_metro(
    AxumPath(cache_key): AxumPath<String>,
    State(state): State<SharedState>,
    request: Request,
) -> Response {
    let usage = UsageContext {
        tenant_id: state.config.tenant_id.clone(),
        namespace_id: METRO_NAMESPACE_ID.to_owned(),
    };

    put_blob_artifact(
        state,
        ArtifactProducer::Metro,
        request,
        BlobPutSpec {
            namespace_id: METRO_NAMESPACE_ID,
            key: &cache_key,
            analytics_key: None,
            max_bytes: MAX_MODULE_TOTAL_BYTES,
            success_status: StatusCode::OK,
            existing_status: StatusCode::OK,
            analytics: None,
            usage: Some(usage),
        },
    )
    .await
}

async fn put_keyvalue(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
    request: Request,
) -> Response {
    let namespace = match NamespaceQuery::from_params(&params) {
        Ok(namespace) => namespace,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };
    let usage = namespace.usage_context();

    let body = match to_bytes(request.into_body(), state.config.max_keyvalue_bytes).await {
        Ok(body) => body,
        Err(error) => {
            state
                .metrics
                .record_memory_action("keyvalue_payload_rejected");
            return error_response(
                StatusCode::PAYLOAD_TOO_LARGE,
                format!("Failed to read key-value request body: {error}"),
            );
        }
    };
    let body = match serde_json::from_slice::<KeyValuePutRequest>(&body) {
        Ok(body) => body,
        Err(error) => {
            return error_response(
                StatusCode::BAD_REQUEST,
                format!("Invalid key-value payload: {error}"),
            );
        }
    };

    let key = action_cache_key(&body.cas_id);
    let payload = serde_json::json!({
        "entries": body.entries.into_iter().map(|entry| serde_json::json!({ "value": entry.value })).collect::<Vec<_>>()
    });
    let payload_bytes = match serde_json::to_vec(&payload) {
        Ok(payload_bytes) => payload_bytes,
        Err(error) => {
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to encode key-value payload: {error}"),
            );
        }
    };
    let targets = replication_targets(&state).await;

    match state
        .store
        .persist_inline_artifact_from_bytes_and_enqueue(
            ArtifactProducer::Xcode,
            &namespace.namespace_id,
            &key,
            "application/json",
            &payload_bytes,
            &targets,
            None,
            None,
        )
        .await
    {
        Ok(manifest) => {
            state.notify.notify_one();
            state
                .metrics
                .record_artifact_write(ArtifactProducer::Xcode, "ok", manifest.size);
            record_usage_event(
                &state,
                ArtifactProducer::Xcode,
                "upload",
                Some(&usage),
                manifest.size,
            );
            StatusCode::NO_CONTENT.into_response()
        }
        Err(error) if is_outbox_full_error(&error) => {
            state
                .metrics
                .record_artifact_write(ArtifactProducer::Xcode, "error", 0);
            capacity_shed_response(
                &state.metrics,
                "outbox",
                "server is shedding writes while replication catches up",
            )
        }
        Err(error) => {
            state
                .metrics
                .record_artifact_write(ArtifactProducer::Xcode, "error", 0);
            io_error_response(
                format!("Failed to persist key-value entry: {error}"),
                StatusCode::SERVICE_UNAVAILABLE,
            )
        }
    }
}

async fn get_xcode(
    AxumPath(id): AxumPath<String>,
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
    headers: HeaderMap,
) -> Response {
    let namespace = match NamespaceQuery::from_params(&params) {
        Ok(namespace) => namespace,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    let analytics = namespace.project_analytics_context();
    let usage = namespace.usage_context();

    get_artifact(
        state,
        ArtifactProducer::Xcode,
        &namespace.namespace_id,
        &blob_key(&id),
        Some(&id),
        analytics,
        Some(usage),
        request_range(&headers),
    )
    .await
}

async fn put_xcode(
    AxumPath(id): AxumPath<String>,
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
    request: Request,
) -> Response {
    let namespace = match NamespaceQuery::from_params(&params) {
        Ok(namespace) => namespace,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    let analytics = namespace.project_analytics_context();
    let usage = namespace.usage_context();

    put_blob_artifact(
        state,
        ArtifactProducer::Xcode,
        request,
        BlobPutSpec {
            namespace_id: &namespace.namespace_id,
            key: &blob_key(&id),
            analytics_key: Some(&id),
            max_bytes: MAX_XCODE_BYTES,
            success_status: StatusCode::NO_CONTENT,
            existing_status: StatusCode::NO_CONTENT,
            analytics,
            usage: Some(usage),
        },
    )
    .await
}

async fn get_gradle(
    AxumPath(cache_key): AxumPath<String>,
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
    headers: HeaderMap,
) -> Response {
    let namespace = match NamespaceQuery::from_params(&params) {
        Ok(namespace) => namespace,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    let analytics = namespace.project_analytics_context();
    let usage = namespace.usage_context();

    get_artifact(
        state,
        ArtifactProducer::Gradle,
        &namespace.namespace_id,
        &cache_key,
        Some(&cache_key),
        analytics,
        Some(usage),
        request_range(&headers),
    )
    .await
}

async fn put_gradle(
    AxumPath(cache_key): AxumPath<String>,
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
    request: Request,
) -> Response {
    let namespace = match NamespaceQuery::from_params(&params) {
        Ok(namespace) => namespace,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    let analytics = namespace.project_analytics_context();
    let usage = namespace.usage_context();

    put_blob_artifact(
        state,
        ArtifactProducer::Gradle,
        request,
        BlobPutSpec {
            namespace_id: &namespace.namespace_id,
            key: &cache_key,
            analytics_key: Some(&cache_key),
            max_bytes: MAX_GRADLE_BYTES,
            success_status: StatusCode::CREATED,
            existing_status: StatusCode::OK,
            analytics,
            usage: Some(usage),
        },
    )
    .await
}

async fn head_module(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
) -> Response {
    let query = match ModuleQuery::from_params(&params) {
        Ok(query) => query,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    match state
        .store
        .artifact_exists(
            ArtifactProducer::Module,
            &query.namespace.namespace_id,
            &query.artifact_key(),
        )
        .await
    {
        Ok(true) => {
            let mut response = StatusCode::NO_CONTENT.into_response();
            response.headers_mut().insert(
                axum::http::header::ACCEPT_RANGES,
                HeaderValue::from_static("bytes"),
            );
            response
        }
        Ok(false) => StatusCode::NOT_FOUND.into_response(),
        Err(error) => error_response(
            StatusCode::SERVICE_UNAVAILABLE,
            format!("Failed to inspect artifact: {error}"),
        ),
    }
}

async fn get_module(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
    headers: HeaderMap,
) -> Response {
    let query = match ModuleQuery::from_params(&params) {
        Ok(query) => query,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };
    let usage = query.namespace.usage_context();

    get_artifact(
        state,
        ArtifactProducer::Module,
        &query.namespace.namespace_id,
        &query.artifact_key(),
        None,
        None,
        Some(usage),
        request_range(&headers),
    )
    .await
}

async fn start_module_upload(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
) -> Response {
    let query = match ModuleQuery::from_params(&params) {
        Ok(query) => query,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    match state
        .store
        .artifact_exists(
            ArtifactProducer::Module,
            &query.namespace.namespace_id,
            &query.artifact_key(),
        )
        .await
    {
        Ok(true) => {
            Json(serde_json::json!({ "upload_id": serde_json::Value::Null })).into_response()
        }
        Ok(false) => match state.store.start_multipart_upload(
            &query.namespace.tenant_id,
            &query.namespace.namespace_id,
            &query.cache_category,
            &query.hash,
            &query.name,
        ) {
            Ok(upload_id) => Json(serde_json::json!({ "upload_id": upload_id })).into_response(),
            Err(error) if is_multipart_capacity_error(&error) => capacity_shed_response(
                &state.metrics,
                "multipart_uploads",
                "server is limiting active multipart uploads",
            ),
            Err(error) => error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to start upload: {error}"),
            ),
        },
        Err(error) => error_response(
            StatusCode::SERVICE_UNAVAILABLE,
            format!("Failed to inspect artifact: {error}"),
        ),
    }
}

async fn upload_module_part(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
    request: Request,
) -> Response {
    let query = match UploadPartQuery::from_params(&params) {
        Ok(query) => query,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    let mut temp = match read_request_to_temp(
        request,
        &state.config.tmp_dir.join("parts"),
        MAX_MODULE_PART_BYTES,
        RequestBodyStaging {
            tmp_budget: &state.tmp_staging_budget,
            io: &state.io,
            memory: &state.memory,
            bandwidth_limiter: None,
        },
    )
    .await
    {
        Ok(temp) => temp,
        Err(BodyReadError::TooLarge) => {
            return error_response(StatusCode::PAYLOAD_TOO_LARGE, "Part exceeds 10MB limit");
        }
        Err(BodyReadError::TmpDirFull(error)) => {
            return capacity_shed_response(
                &state.metrics,
                "tmp_staging",
                &format!("Temporary storage budget exhausted: {error}"),
            );
        }
        Err(BodyReadError::MemoryPressure) => {
            return capacity_shed_response(
                &state.metrics,
                "upload_memory",
                "server is applying upload memory backpressure",
            );
        }
        Err(BodyReadError::Io(error)) => {
            return io_error_response(
                format!("Failed to persist multipart upload part: {error}"),
                StatusCode::INTERNAL_SERVER_ERROR,
            );
        }
    };

    let response = match state
        .store
        .add_multipart_part(&query.upload_id, query.part_number, &temp.path, temp.size)
        .await
    {
        Ok(()) => {
            state.metrics.record_multipart_part("ok");
            StatusCode::NO_CONTENT.into_response()
        }
        Err(MultipartError::NotFound) => {
            state.metrics.record_multipart_part("not_found");
            error_response(StatusCode::NOT_FOUND, "Upload not found")
        }
        Err(MultipartError::TotalSizeExceeded) => {
            state.metrics.record_multipart_part("too_large");
            error_response(
                StatusCode::UNPROCESSABLE_ENTITY,
                "Total upload size exceeds 2GB limit",
            )
        }
        Err(MultipartError::CapacityExceeded) => {
            state.metrics.record_multipart_part("capacity_exceeded");
            capacity_shed_response(
                &state.metrics,
                "multipart_storage",
                "server is limiting incomplete multipart storage",
            )
        }
        Err(MultipartError::Other(error)) => {
            state.metrics.record_multipart_part("error");
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to store multipart upload part: {error}"),
            )
        }
        Err(MultipartError::PartsMismatch) => {
            state.metrics.record_multipart_part("parts_mismatch");
            error_response(StatusCode::BAD_REQUEST, "Parts mismatch")
        }
        Err(MultipartError::MemoryPressure) => capacity_shed_response(
            &state.metrics,
            "upload_memory",
            "server is applying upload memory backpressure",
        ),
    };
    temp.remove_and_disarm(&state.io).await;
    response
}

async fn complete_module_upload(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
    Json(body): Json<CompleteMultipartRequest>,
) -> Response {
    let query = match UploadIdQuery::from_params(&params) {
        Ok(query) => query,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };
    let usage = state
        .store
        .multipart_upload(&query.upload_id)
        .ok()
        .flatten()
        .map(|upload| UsageContext {
            tenant_id: upload.tenant_id,
            namespace_id: upload.namespace_id,
        });

    let targets = replication_targets(&state).await;
    match state
        .store
        .complete_multipart_upload_and_enqueue(&query.upload_id, &body.parts, &targets)
        .await
    {
        Ok(manifest) => {
            state.notify.notify_one();
            state
                .metrics
                .record_artifact_write(ArtifactProducer::Module, "ok", manifest.size);
            record_usage_event(
                &state,
                ArtifactProducer::Module,
                "upload",
                usage.as_ref(),
                manifest.size,
            );
            StatusCode::NO_CONTENT.into_response()
        }
        Err(MultipartError::NotFound) => error_response(StatusCode::NOT_FOUND, "Upload not found"),
        Err(MultipartError::PartsMismatch) => {
            error_response(StatusCode::BAD_REQUEST, "Parts mismatch or missing parts")
        }
        Err(MultipartError::TotalSizeExceeded) => error_response(
            StatusCode::UNPROCESSABLE_ENTITY,
            "Total upload size exceeds 2GB limit",
        ),
        Err(MultipartError::CapacityExceeded) => capacity_shed_response(
            &state.metrics,
            "multipart_storage",
            "server is limiting incomplete multipart storage",
        ),
        Err(MultipartError::MemoryPressure) => capacity_shed_response(
            &state.metrics,
            "upload_memory",
            "server is applying upload memory backpressure",
        ),
        Err(MultipartError::Other(error)) if is_outbox_full_error(&error) => {
            capacity_shed_response(
                &state.metrics,
                "outbox",
                "server is shedding writes while replication catches up",
            )
        }
        Err(MultipartError::Other(error)) => io_error_response(
            format!("Failed to complete multipart upload: {error}"),
            StatusCode::INTERNAL_SERVER_ERROR,
        ),
    }
}

async fn clean_namespace(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
) -> Response {
    let namespace = match NamespaceQuery::from_params(&params) {
        Ok(namespace) => namespace,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    let targets = replication_targets(&state).await;
    match state
        .store
        .delete_namespace_and_enqueue(&namespace.namespace_id, &targets)
        .await
    {
        Ok(_version_ms) => {
            state.notify.notify_one();
            StatusCode::NO_CONTENT.into_response()
        }
        Err(error) if is_outbox_full_error(&error) => capacity_shed_response(
            &state.metrics,
            "outbox",
            "server is shedding writes while replication catches up",
        ),
        Err(error) => error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to clean cache: {error}"),
        ),
    }
}

/// Whether a status request arrived through the public peer gateway (the host it
/// was addressed to matches the gateway URL's host). An off-cluster node reaches
/// a managed peer only via the gateway, so this is how a peer knows to advertise
/// the gateway URL (which the caller can reach) rather than its in-cluster
/// `node_url` (which it can't) — regardless of discovery scope.
///
/// The addressed host comes from the HTTP/2 `:authority` (carried on the request
/// URI) or, on HTTP/1.1, the `Host` header — peer connections negotiate h2, so
/// both must be handled.
fn request_reached_via_gateway(uri: &Uri, headers: &HeaderMap, gateway_url: &str) -> bool {
    let Some(gateway_host) = reqwest::Url::parse(gateway_url)
        .ok()
        .and_then(|url| url.host_str().map(str::to_owned))
    else {
        return false;
    };
    let request_host = uri.host().map(str::to_owned).or_else(|| {
        headers
            .get(axum::http::header::HOST)
            .and_then(|value| value.to_str().ok())
            .map(|host| host.split(':').next().unwrap_or(host).to_owned())
    });
    request_host.is_some_and(|host| host.eq_ignore_ascii_case(&gateway_host))
}

async fn internal_status(
    uri: Uri,
    headers: HeaderMap,
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
) -> impl IntoResponse {
    let advertise_gateway = state
        .config
        .peer_gateway_url
        .as_deref()
        .is_some_and(|gateway| {
            params.get("scope").map(String::as_str) == Some("global")
                || request_reached_via_gateway(&uri, &headers, gateway)
        });
    let node_url = match (&state.config.peer_gateway_url, advertise_gateway) {
        (Some(gateway), true) => gateway.clone(),
        _ => state.config.node_url.clone(),
    };

    Json(serde_json::json!({
        "region": state.config.region.clone(),
        "tenant_id": state.config.tenant_id.clone(),
        "node_url": node_url,
    }))
}

/// The per-artifact backfill endpoint (R11's oversized path). The response is
/// a single bodies-stream frame: the requester needs the manifest meta to
/// apply, and framing it with the same codec keeps one wire definition and the
/// same resolved-with-the-body guarantee as the batch endpoint. A record that
/// no longer resolves is a 404 (the requester's absent case).
async fn internal_backfill_artifact(
    AxumPath(artifact_id): AxumPath<String>,
    State(state): State<SharedState>,
) -> Response {
    let manifest = match state
        .store
        .fetch_artifact_by_id_for_serving(&artifact_id)
        .await
    {
        Ok(Some(manifest)) => manifest,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(error) => {
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to load backfill artifact: {error}"),
            );
        }
    };

    let stream_chunk_bytes = response_stream_chunk_bytes(manifest.size);
    let live_buffer_count = if manifest.inline {
        INLINE_RESPONSE_LIVE_BUFFER_COUNT
    } else {
        FILE_RESPONSE_LIVE_BUFFER_COUNT
    };
    let inline_bytes = if manifest.inline {
        usize::try_from(manifest.size).unwrap_or(usize::MAX)
    } else {
        0
    };
    let requested_bytes = stream_chunk_bytes
        .saturating_mul(live_buffer_count)
        .saturating_add(inline_bytes);
    let permit = match state
        .memory
        .try_acquire_background_response_stream_memory(requested_bytes, "backfill")
    {
        Ok(permit) => permit,
        Err(_) => return peer_response_stream_unavailable(&state.memory),
    };

    match state
        .store
        .open_artifact_reader_range_tolerating_promotion(&manifest, 0, None)
        .await
    {
        Ok(Some((manifest, reader))) => {
            // Frame identity comes from the manifest the bytes were opened
            // from, exactly like the batch endpoint.
            let header = BackfillBodyManifestMeta::from_manifest(&manifest)
                .to_wire_bytes()
                .and_then(|meta| {
                    encode_backfill_body_frame_header(
                        backfill_record_kind(&manifest),
                        BackfillBodyDisposition::Present,
                        manifest_version_ms(&manifest),
                        &manifest.artifact_id,
                        &meta,
                        manifest.size,
                    )
                });
            let header = match header {
                Ok(header) => header,
                Err(error) => return error_response(StatusCode::INTERNAL_SERVER_ERROR, error),
            };
            let content_length = (header.len() as u64).saturating_add(manifest.size);
            let stream = futures_util::stream::once(async move {
                Ok::<Bytes, std::io::Error>(Bytes::from(header))
            })
            .chain(reader.into_bytes_stream(stream_chunk_bytes));
            let stream = throttle_body_stream(stream, state.replication_bandwidth_limiter.clone());
            let mut response = Response::new(Body::from_stream(stream));
            response.headers_mut().insert(
                axum::http::header::CONTENT_TYPE,
                HeaderValue::from_static("application/octet-stream"),
            );
            if let Ok(value) = HeaderValue::from_str(&content_length.to_string()) {
                response
                    .headers_mut()
                    .insert(axum::http::header::CONTENT_LENGTH, value);
            }
            attach_response_stream_permit(&mut response, permit);
            response
        }
        // Bytes gone between manifest read and open (eviction or reclaim
        // race): the requester resolves 404 as absent.
        Ok(None) => StatusCode::NOT_FOUND.into_response(),
        Err(error) => error_response(
            StatusCode::NOT_FOUND,
            format!("Artifact bytes are missing from local storage: {error}"),
        ),
    }
}

async fn internal_backfill_entries(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
) -> Response {
    let query = match BackfillEntriesQuery::from_params(&params) {
        Ok(query) => query,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    if !state.store.backfill_index_built() {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(BackfillUnavailable {
                error: BACKFILL_ERROR_INDEX_BUILDING.to_owned(),
                message: "backfill index is building; retry later".to_owned(),
            }),
        )
            .into_response();
    }

    match state
        .store
        .backfill_index_page(query.after.as_deref(), query.limit)
    {
        Ok(page) => Json(BackfillEntriesPage::from(page)).into_response(),
        Err(error) => error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to list backfill entries: {error}"),
        ),
    }
}

/// Metric label for bodies requests arriving without a client-certificate
/// identity (the plain-HTTP internal listener inside the trusted cluster
/// network). Such requests are not concurrency-capped: the cap exists to
/// contain certificate-holding self-hosted peers on customer infrastructure,
/// and the plain listener is unreachable from outside the cluster.
const BACKFILL_BODIES_PEER_UNIDENTIFIED: &str = "unidentified";

fn backfill_unavailable_response(error: &str, message: &str) -> Response {
    let mut response = (
        StatusCode::SERVICE_UNAVAILABLE,
        Json(BackfillUnavailable {
            error: error.to_owned(),
            message: message.to_owned(),
        }),
    )
        .into_response();
    // Retry-After marks the response as retryable backpressure to the peer
    // pass's response classifier (`classify_backfill_response`).
    retry_after(
        &mut response,
        backpressure::retry_after_seconds(backpressure::IDLE_RETRY_AFTER_CEILING_SECONDS),
    );
    response
}

async fn internal_backfill_bodies(State(state): State<SharedState>, request: Request) -> Response {
    let identity = request.extensions().get::<InternalPeerIdentity>().cloned();
    let peer_label = identity
        .as_ref()
        .map(|identity| identity.0.to_string())
        .unwrap_or_else(|| BACKFILL_BODIES_PEER_UNIDENTIFIED.to_owned());

    let body = match to_bytes(
        request.into_body(),
        MAX_BACKFILL_BODIES_REQUEST_BYTES as usize,
    )
    .await
    {
        Ok(body) => body,
        Err(error) => {
            state
                .metrics
                .record_backfill_bodies_peer_request(&peer_label, "invalid");
            return error_response(
                StatusCode::PAYLOAD_TOO_LARGE,
                format!("Failed to read backfill bodies request: {error}"),
            );
        }
    };
    let request_body: BackfillBodiesRequest = match serde_json::from_slice(&body) {
        Ok(request_body) => request_body,
        Err(error) => {
            state
                .metrics
                .record_backfill_bodies_peer_request(&peer_label, "invalid");
            return error_response(
                StatusCode::BAD_REQUEST,
                format!("Invalid backfill bodies request: {error}"),
            );
        }
    };
    let tuples = match validate_backfill_bodies_entries(&request_body.entries) {
        Ok(tuples) => tuples,
        Err(message) => {
            state
                .metrics
                .record_backfill_bodies_peer_request(&peer_label, "invalid");
            return error_response(StatusCode::BAD_REQUEST, message);
        }
    };

    let slot = match &identity {
        Some(identity) => {
            match state
                .backfill_bodies_peer_slots
                .try_acquire(identity.0.clone())
            {
                Some(slot) => Some(slot),
                None => {
                    state
                        .metrics
                        .record_backfill_bodies_peer_request(&peer_label, "rejected_busy");
                    return backfill_unavailable_response(
                        BACKFILL_ERROR_PEER_BUSY,
                        "another bodies request from this peer identity is in flight; retry shortly",
                    );
                }
            }
        }
        None => None,
    };

    let spool = match spool_backfill_bodies(&state, &tuples).await {
        Ok(spool) => spool,
        Err(BackfillSpoolError::TmpBudget(message)) => {
            state
                .metrics
                .record_backfill_bodies_peer_request(&peer_label, "backpressure");
            return backfill_unavailable_response(BACKFILL_ERROR_TMP_BUDGET_EXHAUSTED, &message);
        }
        Err(BackfillSpoolError::Internal(message)) => {
            state
                .metrics
                .record_backfill_bodies_peer_request(&peer_label, "error");
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, message);
        }
    };

    // Stream the spooled file under the same background admission and
    // bandwidth shaping as the per-artifact backfill endpoint.
    let requested_bytes =
        response_stream_chunk_bytes(spool.file_len).saturating_mul(FILE_RESPONSE_LIVE_BUFFER_COUNT);
    let permit = match state
        .memory
        .try_acquire_background_response_stream_memory(requested_bytes, "backfill")
    {
        Ok(permit) => permit,
        Err(_) => {
            state
                .metrics
                .record_backfill_bodies_peer_request(&peer_label, "backpressure");
            return peer_response_stream_unavailable(&state.memory);
        }
    };
    let file = match state.io.open_persistent_read_file(&spool.path).await {
        Ok(file) => file,
        Err(error) => {
            state
                .metrics
                .record_backfill_bodies_peer_request(&peer_label, "error");
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to open backfill bodies spool: {error}"),
            );
        }
    };
    let file_len = spool.file_len;
    let reader = ArtifactReader::FileRange(crate::segment::reader::SegmentReader::new(
        Arc::new(file),
        0,
        file_len,
    ));
    let stream = reader.into_bytes_stream(response_stream_chunk_bytes(file_len));
    let stream = throttle_body_stream(stream, state.replication_bandwidth_limiter.clone());
    // The spool guards (file cleanup + tmp reservations) and the per-peer slot
    // must live for the whole transfer, so the stream closure owns them.
    let guards = Arc::new((spool, slot));
    let stream = stream.map(move |item| {
        let _guards = &guards;
        item
    });
    state
        .metrics
        .record_backfill_bodies_peer_request(&peer_label, "ok");
    let mut response = Response::new(Body::from_stream(stream));
    response.headers_mut().insert(
        axum::http::header::CONTENT_TYPE,
        HeaderValue::from_static("application/octet-stream"),
    );
    if let Ok(value) = HeaderValue::from_str(&file_len.to_string()) {
        response
            .headers_mut()
            .insert(axum::http::header::CONTENT_LENGTH, value);
    }
    attach_response_stream_permit(&mut response, permit);
    response
}

fn validate_backfill_bodies_entries(
    entries: &[BackfillEntry],
) -> Result<Vec<(BackfillRecordKind, String, u64)>, String> {
    if entries.len() > MAX_BACKFILL_BODIES_ENTRIES {
        return Err(format!(
            "Backfill bodies request carries {} entries; at most {MAX_BACKFILL_BODIES_ENTRIES} are allowed",
            entries.len()
        ));
    }
    entries
        .iter()
        .map(|entry| {
            let kind = BackfillRecordKind::from_wire_name(&entry.record_kind)
                .ok_or_else(|| format!("Unknown record kind: {}", entry.record_kind))?;
            if kind == BackfillRecordKind::NamespaceTombstone {
                return Err(
                    "Tombstones are metadata-only and cannot be fetched as bodies".to_owned(),
                );
            }
            if entry.record_id.is_empty() {
                return Err("Backfill bodies entry carries an empty record id".to_owned());
            }
            Ok((kind, entry.record_id.clone(), entry.version_ms))
        })
        .collect()
}

enum BackfillSpoolError {
    TmpBudget(String),
    Internal(String),
}

struct BackfillBodiesSpool {
    path: std::path::PathBuf,
    file_len: u64,
    // Queues the spool file's unlink on drop; the reservations release
    // alongside it. Boot-time clearing of tmp/backfill sweeps anything a
    // crash leaves behind.
    _cleanup: TempFileCleanup,
    _reservations: Vec<TmpReservation>,
}

/// Spools the whole bodies response to a temp file before any byte is sent:
/// resolution work (manifest reads, retirement writes, body copies) happens
/// off the wire, and the response itself is a plain bounded file stream.
///
/// Stale index rows the resolution discovers are retired batched — flushed
/// every [`BACKFILL_STALE_RETIRE_BATCH`] rows and once when spooling finishes
/// (on every path) — so a request full of dangling rows costs a handful of
/// WAL fsyncs, not one per row.
async fn spool_backfill_bodies(
    state: &SharedState,
    tuples: &[(BackfillRecordKind, String, u64)],
) -> Result<BackfillBodiesSpool, BackfillSpoolError> {
    let mut stale_rows: Vec<Vec<u8>> = Vec::new();
    let result = spool_backfill_bodies_inner(state, tuples, &mut stale_rows).await;
    if let Err(error) = state.store.retire_backfill_index_rows(&mut stale_rows) {
        tracing::warn!(error, "failed to retire stale backfill index rows");
    }
    result
}

async fn spool_backfill_bodies_inner(
    state: &SharedState,
    tuples: &[(BackfillRecordKind, String, u64)],
    stale_rows: &mut Vec<Vec<u8>>,
) -> Result<BackfillBodiesSpool, BackfillSpoolError> {
    let directory = state.config.tmp_dir.join("backfill");
    state
        .io
        .create_dir_all(&directory)
        .await
        .map_err(BackfillSpoolError::Internal)?;
    let path = temp_file_path(&directory, "bodies");
    let cleanup = TempFileCleanup::new_unreserved(path.clone());
    let mut file = state
        .io
        .create_file(&path)
        .await
        .map_err(BackfillSpoolError::Internal)?;

    let mut reservations = Vec::new();
    let mut file_len = 0_u64;
    let mut body_bytes = 0_u64;
    for (requested_kind, record_id, requested_version_ms) in tuples {
        // Resolves against the CURRENT manifest and collects index rows that
        // no longer match it for batched retirement (the read-side half of
        // the eventually-exact index).
        let record = state
            .store
            .resolve_backfill_body(
                *requested_kind,
                record_id,
                *requested_version_ms,
                stale_rows,
            )
            .map_err(BackfillSpoolError::Internal)?;
        if stale_rows.len() >= BACKFILL_STALE_RETIRE_BATCH {
            state
                .store
                .retire_backfill_index_rows(stale_rows)
                .map_err(BackfillSpoolError::Internal)?;
        }
        let absent_header = || {
            encode_backfill_body_frame_header(
                *requested_kind,
                BackfillBodyDisposition::Absent,
                *requested_version_ms,
                record_id,
                &[],
                0,
            )
        };
        let (header, body) = match record {
            None => (absent_header(), None),
            Some(current) => {
                match state
                    .store
                    .open_artifact_reader_range_tolerating_promotion(&current, 0, None)
                    .await
                {
                    Ok(Some((manifest, reader))) => {
                        let size = manifest.size;
                        if size > BACKFILL_BODIES_BATCH_BYTES
                            || body_bytes.saturating_add(size) > BACKFILL_BODIES_BATCH_BYTES
                        {
                            (
                                encode_backfill_body_frame_header(
                                    *requested_kind,
                                    BackfillBodyDisposition::FetchIndividually,
                                    *requested_version_ms,
                                    record_id,
                                    &[],
                                    0,
                                ),
                                None,
                            )
                        } else {
                            // Version, kind, and manifest meta come from the
                            // manifest the bytes were actually opened from —
                            // current at body-read time, never the requested
                            // tuple.
                            (
                                BackfillBodyManifestMeta::from_manifest(&manifest)
                                    .to_wire_bytes()
                                    .and_then(|meta| {
                                        encode_backfill_body_frame_header(
                                            backfill_record_kind(&manifest),
                                            BackfillBodyDisposition::Present,
                                            manifest_version_ms(&manifest),
                                            record_id,
                                            &meta,
                                            size,
                                        )
                                    }),
                                Some((size, reader)),
                            )
                        }
                    }
                    // Bytes gone between manifest read and open (eviction or
                    // reclaim race): framed absent, never an error (R13).
                    Ok(None) => (absent_header(), None),
                    Err(error) => {
                        tracing::warn!(
                            record_id,
                            error,
                            "backfill body open failed; framing entry absent"
                        );
                        (absent_header(), None)
                    }
                }
            }
        };
        let header = header.map_err(BackfillSpoolError::Internal)?;

        let frame_len =
            (header.len() as u64).saturating_add(body.as_ref().map_or(0, |(size, _)| *size));
        reservations.push(
            state
                .peer_staging_budget
                .try_reserve(frame_len)
                .map_err(BackfillSpoolError::TmpBudget)?,
        );
        file.write_all(&header).await.map_err(|error| {
            BackfillSpoolError::Internal(format!("failed to write backfill spool: {error}"))
        })?;
        file_len += header.len() as u64;
        if let Some((size, mut reader)) = body {
            let copied = copy_artifact_reader_owned(
                &mut reader,
                &mut file,
                response_stream_chunk_bytes(size),
            )
            .await
            .map_err(|error| {
                BackfillSpoolError::Internal(format!("failed to spool backfill body: {error}"))
            })?;
            if copied != size {
                return Err(BackfillSpoolError::Internal(format!(
                    "backfill body for {record_id} yielded {copied} bytes, expected {size}"
                )));
            }
            file_len += size;
            body_bytes += size;
        }
    }

    file.flush().await.map_err(|error| {
        BackfillSpoolError::Internal(format!("failed to flush backfill spool: {error}"))
    })?;

    Ok(BackfillBodiesSpool {
        path,
        file_len,
        _cleanup: cleanup,
        _reservations: reservations,
    })
}

async fn copy_artifact_reader_owned<W>(
    reader: &mut ArtifactReader,
    writer: &mut W,
    chunk_bytes: usize,
) -> std::io::Result<u64>
where
    W: tokio::io::AsyncWrite + Unpin,
{
    let mut copied = 0_u64;
    loop {
        let chunk = reader.read_bytes_chunk(chunk_bytes).await?;
        if chunk.is_empty() {
            return Ok(copied);
        }
        writer.write_all(&chunk).await?;
        copied = copied.saturating_add(chunk.len() as u64);
    }
}

/// Batched sibling of `internal_replicate_artifact`, for the metadata lane.
/// Applies every framed inline artifact and answers one outcome per item in
/// request order, so the sender can clear exactly the messages the peer is done
/// with. A peer that predates this route answers 404 and the sender falls back
/// to the per-artifact endpoint, which is what keeps a mixed-version mesh
/// working during a rollout.
async fn internal_replicate_artifacts(
    State(state): State<SharedState>,
    request: Request,
) -> Response {
    let bytes = match to_bytes(request.into_body(), REPLICATION_BATCH_MAX_BYTES as usize).await {
        Ok(bytes) => bytes,
        Err(error) => {
            state
                .metrics
                .record_replication_apply("replication", "artifact", "error");
            return error_response(
                StatusCode::PAYLOAD_TOO_LARGE,
                format!("Failed to read replication batch: {error}"),
            );
        }
    };

    let items = match decode_replicate_batch_frames(&bytes) {
        Ok(items) => items,
        Err(error) => return error_response(StatusCode::BAD_REQUEST, error),
    };
    if items.len() > REPLICATION_BATCH_MAX_ITEMS {
        return error_response(
            StatusCode::PAYLOAD_TOO_LARGE,
            format!(
                "replication batch carries {} items, above the {REPLICATION_BATCH_MAX_ITEMS} limit",
                items.len()
            ),
        );
    }

    let mut outcomes = Vec::with_capacity(items.len());
    for (meta, body) in items {
        let Some(producer) = ArtifactProducer::from_str(&meta.producer) else {
            state
                .metrics
                .record_replication_apply("replication", "artifact", "error");
            outcomes.push("error".to_owned());
            continue;
        };

        // Same version gate the per-artifact route applies, so a batched item
        // that lost the last-writer-wins race costs no write.
        match state.store.artifact_apply_outcome(
            producer,
            &meta.namespace_id,
            &meta.key,
            meta.version_ms,
        ) {
            Ok(outcome) if !outcome.applied() => {
                state
                    .metrics
                    .record_replication_apply("replication", "artifact", outcome.as_str());
                outcomes.push(outcome.as_str().to_owned());
                continue;
            }
            Ok(_) => {}
            Err(_) => {
                state
                    .metrics
                    .record_replication_apply("replication", "artifact", "error");
                outcomes.push("error".to_owned());
                continue;
            }
        }

        match state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                producer,
                &meta.namespace_id,
                &meta.key,
                &meta.content_type,
                &body,
                meta.version_ms,
                meta.branch.as_deref(),
                meta.trunk.as_deref(),
            )
            .await
        {
            Ok(outcome) => {
                state
                    .metrics
                    .record_replication_apply("replication", "artifact", outcome.as_str());
                outcomes.push(outcome.as_str().to_owned());
            }
            Err(_) => {
                state
                    .metrics
                    .record_replication_apply("replication", "artifact", "error");
                outcomes.push("error".to_owned());
            }
        }
    }

    (StatusCode::OK, Json(ReplicateBatchOutcomes { outcomes })).into_response()
}

async fn internal_replicate_artifact(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
    request: Request,
) -> Response {
    let query = match ReplicateArtifactQuery::from_params(&params) {
        Ok(query) => query,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    let producer = match ArtifactProducer::from_str(&query.producer) {
        Some(producer) => producer,
        None => return error_response(StatusCode::BAD_REQUEST, "Invalid artifact producer"),
    };

    match state.store.artifact_apply_outcome(
        producer,
        &query.namespace_id,
        &query.key,
        query.version_ms,
    ) {
        Ok(outcome) if !outcome.applied() => {
            state
                .metrics
                .record_replication_apply("replication", "artifact", outcome.as_str());
            return StatusCode::NO_CONTENT.into_response();
        }
        Ok(_) => {}
        Err(error) => {
            state
                .metrics
                .record_replication_apply("replication", "artifact", "error");
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to evaluate replication version: {error}"),
            );
        }
    }

    if query.inline {
        // Bound the inline body by the same ceiling the sender and the
        // backfill body-fetch path use (MAX_INLINE_REPLICATION_BODY_BYTES), not
        // by the client-facing key-value limit. The latter defaults to 1 MiB
        // while inline artifacts (notably large REAPI action results) may be
        // up to 4 MiB, so keying off it here rejected every 1–4 MiB entry with
        // a 413 and left it replicating forever from a poison outbox message.
        let bytes = match to_bytes(
            request.into_body(),
            MAX_INLINE_REPLICATION_BODY_BYTES as usize,
        )
        .await
        {
            Ok(bytes) => bytes,
            Err(error) => {
                state
                    .metrics
                    .record_memory_action("keyvalue_payload_rejected");
                state
                    .metrics
                    .record_replication_apply("replication", "artifact", "error");
                return error_response(
                    StatusCode::PAYLOAD_TOO_LARGE,
                    format!("Failed to read replication body: {error}"),
                );
            }
        };

        return match state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                producer,
                &query.namespace_id,
                &query.key,
                &query.content_type,
                &bytes,
                query.version_ms,
                query.branch.as_deref(),
                query.trunk.as_deref(),
            )
            .await
        {
            Ok(outcome) => {
                state
                    .metrics
                    .record_replication_apply("replication", "artifact", outcome.as_str());
                StatusCode::NO_CONTENT.into_response()
            }
            Err(error) => {
                state
                    .metrics
                    .record_replication_apply("replication", "artifact", "error");
                io_error_response(
                    format!("Failed to persist replicated artifact: {error}"),
                    StatusCode::INTERNAL_SERVER_ERROR,
                )
            }
        };
    }

    let mut temp = match read_request_to_temp(
        request,
        &state.config.tmp_dir.join("uploads"),
        MAX_REPLICATION_BODY_BYTES,
        RequestBodyStaging {
            tmp_budget: &state.tmp_staging_budget,
            io: &state.io,
            memory: &state.memory,
            bandwidth_limiter: state.replication_bandwidth_limiter.as_deref(),
        },
    )
    .await
    {
        Ok(temp) => temp,
        Err(BodyReadError::TooLarge) => {
            state
                .metrics
                .record_replication_apply("replication", "artifact", "error");
            return error_response(
                StatusCode::PAYLOAD_TOO_LARGE,
                "Request body exceeded allowed size",
            );
        }
        Err(BodyReadError::TmpDirFull(error)) => {
            state
                .metrics
                .record_replication_apply("replication", "artifact", "error");
            return error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                format!("Temporary storage budget exhausted: {error}"),
            );
        }
        Err(BodyReadError::MemoryPressure) => {
            state
                .metrics
                .record_replication_apply("replication", "artifact", "error");
            return overloaded_response("server is applying upload memory backpressure");
        }
        Err(BodyReadError::Io(error)) => {
            state
                .metrics
                .record_replication_apply("replication", "artifact", "error");
            return io_error_response(
                format!("Failed to read replication body: {error}"),
                StatusCode::INTERNAL_SERVER_ERROR,
            );
        }
    };

    let result = state
        .store
        .apply_replicated_artifact_from_path(
            producer,
            &query.namespace_id,
            &query.key,
            &query.content_type,
            StagedArtifactPath::new(&temp.path, temp.file_cache_policy),
            query.version_ms,
        )
        .await;
    temp.remove_and_disarm(&state.io).await;
    match result {
        Ok(outcome) => {
            state
                .metrics
                .record_replication_apply("replication", "artifact", outcome.as_str());
            StatusCode::NO_CONTENT.into_response()
        }
        Err(error) => {
            state
                .metrics
                .record_replication_apply("replication", "artifact", "error");
            io_error_response(
                format!("Failed to persist replicated artifact: {error}"),
                StatusCode::INTERNAL_SERVER_ERROR,
            )
        }
    }
}

async fn internal_delete_namespace(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
) -> Response {
    let namespace_id = match required_raw_param(&params, "namespace_id") {
        Ok(namespace_id) => namespace_id,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };
    let version_ms = match optional_u64_param(&params, "version_ms") {
        Ok(Some(version_ms)) => version_ms,
        Ok(None) => 0,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    match state
        .store
        .apply_replicated_namespace_delete(&namespace_id, version_ms)
        .await
    {
        Ok(outcome) => {
            state.metrics.record_replication_apply(
                "replication",
                "namespace_delete",
                outcome.as_str(),
            );
            StatusCode::NO_CONTENT.into_response()
        }
        Err(error) => {
            state
                .metrics
                .record_replication_apply("replication", "namespace_delete", "error");
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to delete replicated namespace: {error}"),
            )
        }
    }
}

#[allow(clippy::too_many_arguments)]
async fn get_artifact(
    state: SharedState,
    producer: ArtifactProducer,
    namespace_id: &str,
    key: &str,
    analytics_key: Option<&str>,
    analytics: Option<ProjectAnalyticsContext<'_>>,
    usage: Option<UsageContext>,
    range_request: RangeRequest<'_>,
) -> Response {
    let lookup_span = if trace_export_active() {
        tracing::info_span!(
            "kura.store.manifest_lookup",
            kura.artifact.producer = producer.as_str(),
            kura.store.result = field::Empty,
        )
    } else {
        tracing::Span::none()
    };
    let lookup = state
        .store
        .fetch_artifact_for_serving(producer, namespace_id, key)
        .instrument(lookup_span.clone())
        .await;
    match lookup {
        Ok(Some(manifest)) => {
            lookup_span.record("kura.store.result", "hit");
            // Resolved after the fetch so a 416's `Content-Range` only ever
            // discloses the size of an artifact the caller is already allowed
            // to read.
            let etag = entity_tag(manifest.version_ms, manifest.size);
            let range = match resolve_conditional_range(range_request, &etag, manifest.size) {
                RangeOutcome::Full => ServedRange::full(manifest.size),
                RangeOutcome::Partial(range) => range,
                RangeOutcome::Unsatisfiable => {
                    state
                        .metrics
                        .record_artifact_read(producer, "range_not_satisfiable", 0);
                    return range_not_satisfiable_response(manifest.size);
                }
            };
            // A streaming response's status is decided when the stream is
            // built, long before a byte reaches the client, so metering here
            // would book an artifact the client may never receive and book it
            // again when the client returns for the part it missed. The
            // attribution rides on the body instead and is committed once the
            // bytes have actually been delivered, which is what the
            // accelerated plane has always done.
            let attribution = DownloadAttribution {
                state: state.clone(),
                producer,
                usage: usage.clone(),
                analytics: analytics.as_ref().map(|context| {
                    (
                        context.tenant_id.to_owned(),
                        context.namespace_id.to_owned(),
                    )
                }),
                analytics_key: analytics_key.unwrap_or(key).to_owned(),
            };
            let response = serve_file(&state, &manifest, range, attribution).await;
            if response.status().is_success() {
                // Nothing to record: the body commits the read, usage and
                // analytics when it completes.
            } else if response.status() == StatusCode::NOT_FOUND {
                state.metrics.record_artifact_read(producer, "not_found", 0);
            } else if response.status() != StatusCode::TOO_MANY_REQUESTS {
                // A shed is admission, not a read outcome: no read was attempted,
                // and counting it as an error puts capacity back into the signal
                // this route's error rate is read from. The accelerated path
                // records nothing for the same reason.
                state.metrics.record_artifact_read(producer, "error", 0);
            }
            response
        }
        Ok(None) => {
            lookup_span.record("kura.store.result", "miss");
            state.metrics.record_artifact_read(producer, "not_found", 0);
            error_response(StatusCode::NOT_FOUND, "Artifact not found")
        }
        Err(error) => {
            lookup_span.record("kura.store.result", "error");
            state.metrics.record_artifact_read(producer, "error", 0);
            error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                format!("Failed to fetch artifact: {error}"),
            )
        }
    }
}

async fn put_blob_artifact(
    state: SharedState,
    producer: ArtifactProducer,
    request: Request,
    spec: BlobPutSpec<'_>,
) -> Response {
    match state
        .store
        .artifact_exists(producer, spec.namespace_id, spec.key)
        .await
    {
        Ok(true) => return spec.existing_status.into_response(),
        Ok(false) => {}
        Err(error) => {
            return error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                format!("Failed to inspect artifact: {error}"),
            );
        }
    }

    let mut temp = match read_request_to_temp(
        request,
        &state.config.tmp_dir.join("uploads"),
        spec.max_bytes,
        RequestBodyStaging {
            tmp_budget: &state.tmp_staging_budget,
            io: &state.io,
            memory: &state.memory,
            bandwidth_limiter: None,
        },
    )
    .await
    {
        Ok(temp) => temp,
        Err(BodyReadError::TooLarge) => {
            return error_response(
                StatusCode::PAYLOAD_TOO_LARGE,
                "Request body exceeded allowed size",
            );
        }
        Err(BodyReadError::TmpDirFull(error)) => {
            return capacity_shed_response(
                &state.metrics,
                "tmp_staging",
                &format!("Temporary storage budget exhausted: {error}"),
            );
        }
        Err(BodyReadError::MemoryPressure) => {
            return capacity_shed_response(
                &state.metrics,
                "upload_memory",
                "server is applying upload memory backpressure",
            );
        }
        Err(BodyReadError::Io(error)) => {
            return io_error_response(
                format!("Failed to persist artifact: {error}"),
                StatusCode::INTERNAL_SERVER_ERROR,
            );
        }
    };

    let targets = replication_targets(&state).await;
    let result = state
        .store
        .persist_artifact_from_path_and_enqueue(
            producer,
            spec.namespace_id,
            spec.key,
            "application/octet-stream",
            StagedArtifactPath::new(&temp.path, temp.file_cache_policy),
            &targets,
        )
        .await;
    temp.remove_and_disarm(&state.io).await;
    match result {
        Ok(persisted) => {
            state.notify.notify_one();
            state
                .metrics
                .record_artifact_write(producer, "ok", persisted.manifest.size);
            // The `artifact_exists` early return above keeps the common
            // re-upload from reading the body at all; billing still relies on
            // the store's under-lock presence so concurrent uploads of the
            // same missing artifact (which all pass that pre-check) resolve
            // to exactly one billed writer.
            if !persisted.already_present {
                record_usage_event(
                    &state,
                    producer,
                    "upload",
                    spec.usage.as_ref(),
                    persisted.manifest.size,
                );
            }
            record_project_scoped_cache_event(
                &state,
                producer,
                "upload",
                spec.analytics,
                spec.analytics_key.unwrap_or(spec.key),
                persisted.manifest.size,
            );
            spec.success_status.into_response()
        }
        Err(error) if is_outbox_full_error(&error) => {
            state.metrics.record_artifact_write(producer, "error", 0);
            capacity_shed_response(
                &state.metrics,
                "outbox",
                "server is shedding writes while replication catches up",
            )
        }
        Err(error) => {
            state.metrics.record_artifact_write(producer, "error", 0);
            io_error_response(
                format!("Failed to persist artifact: {error}"),
                StatusCode::SERVICE_UNAVAILABLE,
            )
        }
    }
}

/// What a download books once its body has actually delivered its bytes.
///
/// Carried by the response stream rather than recorded when the response is
/// constructed, because on the streaming plane those two moments are far
/// apart: the status is set as soon as the stream exists, and the transfer can
/// still die at any point after that.
struct DownloadAttribution {
    state: SharedState,
    producer: ArtifactProducer,
    usage: Option<UsageContext>,
    analytics: Option<(String, String)>,
    analytics_key: String,
}

impl DownloadAttribution {
    fn commit(&self, bytes: u64) {
        self.state
            .metrics
            .record_artifact_read(self.producer, "ok", bytes);
        record_usage_event(
            &self.state,
            self.producer,
            "download",
            self.usage.as_ref(),
            bytes,
        );
        let analytics =
            self.analytics
                .as_ref()
                .map(|(tenant_id, namespace_id)| ProjectAnalyticsContext {
                    tenant_id,
                    namespace_id,
                });
        record_project_scoped_cache_event(
            &self.state,
            self.producer,
            "download",
            analytics,
            &self.analytics_key,
            bytes,
        );
    }
}

fn record_usage_event(
    state: &SharedState,
    producer: ArtifactProducer,
    action: &str,
    usage_context: Option<&UsageContext>,
    size: u64,
) {
    let Some(context) = usage_context else {
        return;
    };
    let Some(usage) = state.usage.as_ref() else {
        return;
    };
    let artifact_kind = artifact_kind_for_usage(producer);

    match action {
        "download" => usage.record_public_download(
            &context.tenant_id,
            &context.namespace_id,
            artifact_kind,
            size,
        ),
        "upload" => usage.record_public_upload(
            &context.tenant_id,
            &context.namespace_id,
            artifact_kind,
            size,
        ),
        _ => {}
    }
}

fn artifact_kind_for_usage(producer: ArtifactProducer) -> &'static str {
    match producer {
        ArtifactProducer::Xcode => "xcode",
        ArtifactProducer::Gradle => "gradle",
        ArtifactProducer::Nx => "nx",
        ArtifactProducer::Metro => "metro",
        ArtifactProducer::Module => "module",
        ArtifactProducer::Reapi => "reapi",
    }
}

fn record_project_scoped_cache_event(
    state: &SharedState,
    producer: ArtifactProducer,
    action: &str,
    analytics: Option<ProjectAnalyticsContext<'_>>,
    key: &str,
    size: u64,
) {
    let Some(context) = analytics else {
        return;
    };
    let Some(analytics) = state.analytics.as_ref() else {
        return;
    };

    match (producer, action) {
        (ArtifactProducer::Xcode, "download") => {
            analytics.enqueue_xcode_download(context.tenant_id, context.namespace_id, key, size)
        }
        (ArtifactProducer::Xcode, "upload") => {
            analytics.enqueue_xcode_upload(context.tenant_id, context.namespace_id, key, size)
        }
        (ArtifactProducer::Gradle, "download") => {
            analytics.enqueue_gradle_download(context.tenant_id, context.namespace_id, key, size)
        }
        (ArtifactProducer::Gradle, "upload") => {
            analytics.enqueue_gradle_upload(context.tenant_id, context.namespace_id, key, size)
        }
        _ => {}
    }
}

async fn serve_file(
    state: &SharedState,
    manifest: &ArtifactManifest,
    range: ServedRange,
    attribution: DownloadAttribution,
) -> Response {
    let open_span = if trace_export_active() {
        tracing::info_span!(
            "kura.store.artifact_open",
            kura.artifact.producer = manifest.producer.as_str(),
            kura.store.serving_path = field::Empty,
            kura.store.result = field::Empty,
        )
    } else {
        tracing::Span::none()
    };
    let mmap_result = state
        .store
        .try_mmap_artifact_bytes(manifest)
        .instrument(open_span.clone())
        .await;
    match mmap_result {
        Ok(Some(bytes)) => {
            open_span.record("kura.store.serving_path", "mmap");
            open_span.record("kura.store.result", "ok");
            state.metrics.record_artifact_serving_path("mmap");
            let requested_bytes = response_stream_chunk_bytes(range.length).saturating_mul(4);
            let permit = match state
                .memory
                .try_acquire_mmap_response_stream_memory(requested_bytes, "http")
            {
                Some(permit) => permit,
                // mmap serving is an optimization; hand a budget-constrained
                // read straight to the streaming path, which can use the
                // smaller degraded pool. Waiting here first would only delay
                // that fallback by a full admission timeout.
                None => {
                    return serve_file_reader(state, manifest, range, attribution).await;
                }
            };
            // The mapping covers the whole artifact; the response carries only
            // the requested window of it. `Bytes::slice` is a view, so no copy
            // and no second mapping.
            let start = (range.start as usize).min(bytes.len());
            let end = start.saturating_add(range.length as usize).min(bytes.len());
            let status = artifact_response_status(range);
            let stream = instrument_artifact_stream(
                state,
                manifest,
                bytes_chunks(bytes.slice(start..end)),
                true,
                ArtifactStreamObservation {
                    status,
                    serving_path: "mmap",
                    expected_bytes: range.length,
                    attribution: Some(attribution),
                },
            );
            let mut response = Response::new(Body::from_stream(stream));
            *response.status_mut() = status;
            response.extensions_mut().insert(ObservedStreamingResponse);
            apply_artifact_response_headers(&mut response, manifest, range);
            attach_response_stream_permit(&mut response, permit);
            response
        }
        Ok(None) => {
            open_span.record("kura.store.serving_path", "reader");
            open_span.record("kura.store.result", "fallback");
            serve_file_reader(state, manifest, range, attribution).await
        }
        Err(error) => {
            open_span.record("kura.store.serving_path", "reader_fallback");
            open_span.record("kura.store.result", "error");
            tracing::warn!(
                artifact_id = %manifest.artifact_id,
                %error,
                "mmap artifact serving failed; falling back to streaming reader"
            );
            serve_file_reader(state, manifest, range, attribution).await
        }
    }
}

/// Streams an artifact from a reader to a public cache response.
///
/// Public-only since the legacy bootstrap serving plane was retired: peer
/// catch-up no longer streams artifacts through here, so there is no second
/// admission class and no bandwidth limiter on this path. Backfill's own
/// serving (`internal_backfill_bodies`) reserves from the background pool
/// instead, and is shed there rather than degraded — internal peer traffic
/// retries on its own schedule.
async fn serve_file_reader(
    state: &SharedState,
    manifest: &ArtifactManifest,
    range: ServedRange,
    attribution: DownloadAttribution,
) -> Response {
    state.metrics.record_artifact_serving_path("streaming");
    // An inline artifact is materialized into the reader, but only the
    // requested window of it, so a resume reserves its tail rather than the
    // whole body. That is what keeps a large artifact's resume admissible
    // under a budget its from-scratch re-send would be shed under.
    let inline_bytes = if manifest.inline { range.length } else { 0 };
    let live_buffer_count = if manifest.inline {
        INLINE_RESPONSE_LIVE_BUFFER_COUNT
    } else {
        FILE_RESPONSE_LIVE_BUFFER_COUNT
    };
    let stream_chunk_bytes = response_stream_chunk_bytes(range.length);
    let requested_bytes = usize::try_from(
        u64::try_from(stream_chunk_bytes.saturating_mul(live_buffer_count))
            .unwrap_or(u64::MAX)
            .saturating_add(inline_bytes),
    )
    .unwrap_or(usize::MAX);
    // A public read first degrades to the minimum chunk. If even that bounded
    // path has no slot or live headroom, shed it with a retryable response
    // rather than opening an unaccounted stream.
    let (permit, stream_chunk_bytes) = match state
        .memory
        .acquire_response_stream_memory(
            requested_bytes,
            "http",
            ResponseStreamAdmissionPatience::Degradable,
        )
        .await
    {
        Ok(permit) => (permit, stream_chunk_bytes),
        Err(_) => {
            let degraded_bytes = usize::try_from(
                u64::try_from(
                    RESPONSE_STREAM_MIN_CHUNK_BYTES
                        .saturating_mul(live_buffer_count.saturating_sub(1))
                        .saturating_add(RESPONSE_STREAM_SEND_BUFFER_BYTES),
                )
                .unwrap_or(u64::MAX)
                .saturating_add(inline_bytes),
            )
            .unwrap_or(usize::MAX);
            match state
                .memory
                .acquire_degraded_response_stream_memory(degraded_bytes, "http")
                .await
            {
                Ok(permit) => (permit, RESPONSE_STREAM_MIN_CHUNK_BYTES),
                Err(_) => return response_stream_shed(&state.metrics, &state.memory),
            }
        }
    };
    // Tolerates a concurrent background promotion relocating the artifact
    // between the caller's manifest fetch and this open (see
    // `Store::open_artifact_reader_range_tolerating_promotion`); response
    // metadata comes from the manifest that was actually opened so headers
    // always describe the bytes being streamed.
    let open_span = if trace_export_active() {
        tracing::info_span!(
            "kura.store.artifact_reader_open",
            kura.artifact.producer = manifest.producer.as_str(),
            kura.store.result = field::Empty,
        )
    } else {
        tracing::Span::none()
    };
    let open_result = state
        .store
        .open_artifact_reader_range_tolerating_promotion(manifest, range.start, Some(range.length))
        .instrument(open_span.clone())
        .await;
    match open_result {
        Ok(Some((manifest, reader))) => {
            open_span.record("kura.store.result", "ok");
            let stream = reader.into_bytes_stream(stream_chunk_bytes);
            let status = artifact_response_status(range);
            let stream = instrument_artifact_stream(
                state,
                &manifest,
                stream,
                true,
                ArtifactStreamObservation {
                    status,
                    serving_path: "reader",
                    expected_bytes: range.length,
                    attribution: Some(attribution),
                },
            );
            let mut response = Response::new(Body::from_stream(stream));
            *response.status_mut() = status;
            response.extensions_mut().insert(ObservedStreamingResponse);
            apply_artifact_response_headers(&mut response, &manifest, range);
            attach_response_stream_permit(&mut response, permit);
            response
        }
        Ok(None) => {
            open_span.record("kura.store.result", "missing");
            error_response(
                StatusCode::NOT_FOUND,
                "Artifact bytes are missing from local storage".to_string(),
            )
        }
        Err(error) => {
            open_span.record("kura.store.result", "error");
            error_response(
                StatusCode::NOT_FOUND,
                format!("Artifact bytes are missing from local storage: {error}"),
            )
        }
    }
}

/// Sheds a public read that could not be admitted a response stream.
///
/// Backpressure rather than a fault: the node is healthy and the same request
/// succeeds once a permit frees, so a 5xx here would be indistinguishable from
/// an unreachable auth backend or a failed transfer. Both admission outcomes
/// land here, including the queue-full one that gives up before waiting at
/// all, which is another reason not to describe it as the service being
/// unavailable.
fn response_stream_shed(metrics: &Metrics, memory: &MemoryController) -> Response {
    metrics.record_capacity_shed(shed_kind::RESPONSE_STREAM);
    let mut response = error_response(
        StatusCode::TOO_MANY_REQUESTS,
        "The server is limiting concurrent artifact response streams; retry shortly".to_string(),
    );
    retry_after(&mut response, memory.response_stream_retry_after_seconds());
    response
}

/// The peer counterpart, on the background pool. It stays 503: internal routes
/// are outside the public error signal this split exists to clean up, and the
/// requester already treats a 503 carrying `Retry-After` as budget-exempt
/// backpressure (`classify_backfill_response`).
fn peer_response_stream_unavailable(memory: &MemoryController) -> Response {
    let mut response = error_response(
        StatusCode::SERVICE_UNAVAILABLE,
        "The server is limiting concurrent artifact response streams; retry shortly".to_string(),
    );
    retry_after(&mut response, memory.response_stream_retry_after_seconds());
    response
}

fn instrument_artifact_stream<S>(
    state: &SharedState,
    manifest: &ArtifactManifest,
    stream: S,
    hold_public_inflight: bool,
    observation: ArtifactStreamObservation,
) -> InstrumentedArtifactStream<S>
where
    S: Stream<Item = Result<Bytes, std::io::Error>> + Send + 'static,
{
    let request_guard =
        hold_public_inflight.then(|| state.start_http_request(HttpTrafficClass::Public));
    InstrumentedArtifactStream::new(
        state.metrics.clone(),
        manifest.producer,
        stream,
        request_guard,
        observation,
    )
}

struct ArtifactStreamObservation {
    status: StatusCode,
    serving_path: &'static str,
    expected_bytes: u64,
    attribution: Option<DownloadAttribution>,
}

struct InstrumentedArtifactStream<S> {
    inner: S,
    metrics: Metrics,
    producer: ArtifactProducer,
    status: StatusCode,
    _request_guard: Option<InflightGuard>,
    started_at: Instant,
    yielded_bytes: u64,
    first_byte_at: Option<Duration>,
    request_context: Option<Arc<RequestContext>>,
    body_span: tracing::Span,
    serving_path: &'static str,
    // What the response promised in its `Content-Length`. A body is complete
    // when it has yielded this much, whether or not anything polls it again:
    // Hyper stops polling once the promised length is on the wire, so the
    // terminal `None` that would otherwise mark completion never arrives.
    expected_bytes: u64,
    recorded: bool,
    // Booked only on a body that delivered in full, so an abandoned transfer
    // meters nothing and the client's follow-up meters only what it receives.
    attribution: Option<DownloadAttribution>,
}

impl<S> InstrumentedArtifactStream<S> {
    fn new(
        metrics: Metrics,
        producer: ArtifactProducer,
        stream: S,
        request_guard: Option<InflightGuard>,
        observation: ArtifactStreamObservation,
    ) -> Self {
        let ArtifactStreamObservation {
            status,
            serving_path,
            expected_bytes,
            attribution,
        } = observation;
        let request_context = current_request();
        let body_span = if !trace_export_active() {
            tracing::Span::none()
        } else if let Some(context) = request_context.as_ref() {
            tracing::info_span!(
                parent: context.request_span(),
                "kura.http.response_body",
                http.request.id = %context.request_id(),
                http.response.status_code = status.as_u16(),
                kura.artifact.producer = producer.as_str(),
                kura.response.serving_path = serving_path,
                http.response.body.size = field::Empty,
                kura.request.time_to_first_byte_ms = field::Empty,
                kura.request.duration_ms = field::Empty,
                kura.response.result = field::Empty,
                trace_id = field::Empty,
                span_id = field::Empty,
            )
        } else {
            tracing::info_span!(
                "kura.http.response_body",
                http.request.id = field::Empty,
                http.response.status_code = status.as_u16(),
                kura.artifact.producer = producer.as_str(),
                kura.response.serving_path = serving_path,
                http.response.body.size = field::Empty,
                kura.request.time_to_first_byte_ms = field::Empty,
                kura.request.duration_ms = field::Empty,
                kura.response.result = field::Empty,
                trace_id = field::Empty,
                span_id = field::Empty,
            )
        };
        if trace_export_active() {
            record_trace_context(&body_span);
        }
        Self {
            inner: stream,
            metrics,
            producer,
            status,
            _request_guard: request_guard,
            started_at: Instant::now(),
            yielded_bytes: 0,
            first_byte_at: None,
            request_context,
            body_span,
            serving_path,
            expected_bytes,
            recorded: false,
            attribution,
        }
    }

    /// Whether every promised byte reached the response body.
    fn delivered_in_full(&self) -> bool {
        self.yielded_bytes >= self.expected_bytes
    }

    fn record_once(&mut self, result: &str, error: Option<&str>) {
        if self.recorded {
            return;
        }

        self.recorded = true;
        let transfer_duration = self.started_at.elapsed();
        self.metrics.record_artifact_egress(
            self.producer,
            result,
            self.yielded_bytes,
            transfer_duration,
        );
        if result == "ok"
            && let Some(attribution) = self.attribution.take()
        {
            attribution.commit(self.yielded_bytes);
        }
        let total_duration = self
            .request_context
            .as_ref()
            .map(|context| context.started_at().elapsed())
            .unwrap_or(transfer_duration);
        let time_to_first_byte = self.first_byte_at.unwrap_or(total_duration);
        self.body_span
            .record("http.response.body.size", self.yielded_bytes);
        self.body_span.record(
            "kura.request.time_to_first_byte_ms",
            time_to_first_byte.as_secs_f64() * 1_000.0,
        );
        self.body_span.record(
            "kura.request.duration_ms",
            total_duration.as_secs_f64() * 1_000.0,
        );
        self.body_span.record("kura.response.result", result);
        if let Some(context) = self.request_context.as_ref() {
            log_request_completion(
                context,
                RequestCompletion {
                    status: self.status.as_u16(),
                    response_bytes: self.yielded_bytes,
                    time_to_first_byte,
                    total_duration,
                    serving_path: self.serving_path,
                    result,
                    error,
                },
            );
        }
    }
}

fn throttle_body_stream<S, E>(
    stream: S,
    bandwidth_limiter: Option<Arc<BandwidthLimiter>>,
) -> impl futures_util::Stream<Item = Result<Bytes, E>>
where
    S: futures_util::Stream<Item = Result<Bytes, E>>,
{
    stream.then(move |item| {
        let bandwidth_limiter = bandwidth_limiter.clone();
        async move {
            if let (Some(limiter), Ok(chunk)) = (bandwidth_limiter.as_ref(), item.as_ref()) {
                limiter.acquire(chunk.len()).await;
            }
            item
        }
    })
}

impl<S> Stream for InstrumentedArtifactStream<S>
where
    S: Stream<Item = Result<Bytes, std::io::Error>>,
{
    type Item = Result<Bytes, std::io::Error>;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        // The wrapper never moves `inner` after being pinned; this only projects
        // the pinned field so non-`Unpin` streams can stay unboxed.
        let this = unsafe { self.as_mut().get_unchecked_mut() };
        let inner = unsafe { Pin::new_unchecked(&mut this.inner) };
        match inner.poll_next(cx) {
            Poll::Ready(Some(Ok(bytes))) => {
                if this.first_byte_at.is_none() {
                    this.first_byte_at = Some(
                        this.request_context
                            .as_ref()
                            .map(|context| context.started_at().elapsed())
                            .unwrap_or_else(|| this.started_at.elapsed()),
                    );
                }
                this.yielded_bytes = this.yielded_bytes.saturating_add(bytes.len() as u64);
                Poll::Ready(Some(Ok(bytes)))
            }
            Poll::Ready(Some(Err(error))) => {
                let error_message = error.to_string();
                this.record_once("error", Some(&error_message));
                Poll::Ready(Some(Err(error)))
            }
            Poll::Ready(None) => {
                this.record_once("ok", None);
                Poll::Ready(None)
            }
            Poll::Pending => Poll::Pending,
        }
    }
}

impl<S> Drop for InstrumentedArtifactStream<S> {
    fn drop(&mut self) {
        // Reached without a terminal `None` in two very different situations:
        // the body delivered everything and Hyper simply stopped polling, or
        // the peer went away mid-transfer. Only the second is waste, and
        // conflating them made `result="aborted"` a label for "served by the
        // streaming path" rather than for a transfer nobody received.
        let result = if self.delivered_in_full() {
            "ok"
        } else {
            "aborted"
        };
        self.record_once(result, None);
    }
}

struct BytesChunks {
    bytes: Bytes,
    offset: usize,
}

impl Stream for BytesChunks {
    type Item = Result<Bytes, std::io::Error>;

    fn poll_next(mut self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        if self.offset >= self.bytes.len() {
            return Poll::Ready(None);
        }

        let end = self
            .offset
            .saturating_add(MMAP_RESPONSE_CHUNK_BYTES)
            .min(self.bytes.len());
        let chunk = self.bytes.slice(self.offset..end);
        self.offset = end;
        Poll::Ready(Some(Ok(chunk)))
    }
}

fn bytes_chunks(bytes: Bytes) -> BytesChunks {
    BytesChunks { bytes, offset: 0 }
}

fn request_range(headers: &HeaderMap) -> RangeRequest<'_> {
    RangeRequest::new(
        header_str(headers, axum::http::header::RANGE),
        header_str(headers, axum::http::header::IF_RANGE),
    )
}

fn header_str(headers: &HeaderMap, name: axum::http::header::HeaderName) -> Option<&str> {
    headers.get(name).and_then(|value| value.to_str().ok())
}

fn artifact_response_status(range: ServedRange) -> StatusCode {
    if range.partial {
        StatusCode::PARTIAL_CONTENT
    } else {
        StatusCode::OK
    }
}

fn apply_artifact_response_headers(
    response: &mut Response,
    manifest: &ArtifactManifest,
    range: ServedRange,
) {
    // The validator a resume echoes back in `If-Range`. On the full response
    // as well as the partial one: a client can only name the representation it
    // started from if the server told it before the transfer died.
    if let Ok(etag) = HeaderValue::from_str(&entity_tag(manifest.version_ms, manifest.size)) {
        response
            .headers_mut()
            .insert(axum::http::header::ETAG, etag);
    }
    response.headers_mut().insert(
        axum::http::header::CONTENT_TYPE,
        HeaderValue::from_str(&manifest.content_type)
            .unwrap_or_else(|_| HeaderValue::from_static("application/octet-stream")),
    );
    response.headers_mut().insert(
        axum::http::header::CONTENT_LENGTH,
        HeaderValue::from_str(&range.length.to_string())
            .unwrap_or_else(|_| HeaderValue::from_static("0")),
    );
    // Advertised on the full response as well, so a client that has to retry
    // knows resume is on offer before it needs it.
    response.headers_mut().insert(
        axum::http::header::ACCEPT_RANGES,
        HeaderValue::from_static("bytes"),
    );
    if let Some(content_range) = range
        .content_range(manifest.size)
        .and_then(|value| HeaderValue::from_str(&value).ok())
    {
        response
            .headers_mut()
            .insert(axum::http::header::CONTENT_RANGE, content_range);
    }
}

fn range_not_satisfiable_response(size: u64) -> Response {
    let mut response = error_response(
        StatusCode::RANGE_NOT_SATISFIABLE,
        format!("Requested range is not satisfiable for a {size}-byte artifact"),
    );
    response.headers_mut().insert(
        axum::http::header::ACCEPT_RANGES,
        HeaderValue::from_static("bytes"),
    );
    if let Ok(content_range) = HeaderValue::from_str(&format!("bytes */{size}")) {
        response
            .headers_mut()
            .insert(axum::http::header::CONTENT_RANGE, content_range);
    }
    response
}

fn draining_response(version: Version) -> Response {
    let mut response = error_response(StatusCode::SERVICE_UNAVAILABLE, "server is draining");
    if is_http1(version) {
        response.headers_mut().insert(
            axum::http::header::CONNECTION,
            HeaderValue::from_static("close"),
        );
    }
    response
}

fn error_response(status: StatusCode, message: impl Into<String>) -> Response {
    let body = Json(serde_json::json!({ "message": message.into() }));
    (status, body).into_response()
}

fn io_error_response(error: String, fallback_status: StatusCode) -> Response {
    if is_fd_pool_exhausted_error(&error) {
        return overloaded_response("server is at file descriptor capacity");
    }
    if is_disk_full_error(&error) {
        return overloaded_response("server has insufficient free disk space");
    }
    error_response(fallback_status, error)
}

#[cfg(test)]
mod tests {
    use std::{
        convert::Infallible,
        sync::{Arc, Mutex},
    };

    use axum::{Router, body::Body, extract::Request, response::IntoResponse, routing::post};
    use http_body_util::BodyExt;
    use serde_json::Value;
    use tokio::time::{Duration, sleep, timeout};
    use tower::ServiceExt;

    use super::*;
    use crate::{
        artifact::producer::ArtifactProducer,
        config::{AnalyticsConfig, UsageConfig},
        test_support::{response_text, test_context},
        utils::{artifact_storage_id, blob_key},
    };

    fn retry_after_hint(response: &Response) -> u64 {
        response
            .headers()
            .get(axum::http::header::RETRY_AFTER)
            .expect("backpressure must be marked retryable")
            .to_str()
            .expect("ascii retry-after")
            .parse()
            .expect("numeric retry-after")
    }

    fn assert_retryable_hint(response: &Response, ceiling_seconds: u64) {
        let seconds = retry_after_hint(response);
        assert!(
            (backpressure::MIN_RETRY_AFTER_SECONDS..=ceiling_seconds).contains(&seconds),
            "retry-after {seconds} outside 1..={ceiling_seconds}"
        );
    }

    fn test_usage_config() -> UsageConfig {
        UsageConfig {
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

    async fn assert_json_error_response(response: Response, status: StatusCode, message: &str) {
        assert_eq!(response.status(), status);
        assert_eq!(
            response.headers().get(axum::http::header::CONTENT_TYPE),
            Some(&HeaderValue::from_static("application/json"))
        );

        let body: Value = serde_json::from_str(&response_text(response).await)
            .expect("failed to decode error response");
        assert_eq!(body["message"], message);
    }

    #[tokio::test]
    async fn cluster_status_includes_current_node_and_known_members() {
        let context = test_context(|config| {
            config.region = "us-east".into();
        })
        .await;
        context
            .state
            .apply_membership_view(
                std::collections::BTreeSet::from(["eu-west".to_string()]),
                std::collections::BTreeMap::from([(
                    "http://peer.kura.internal:4000".to_string(),
                    "eu-west".to_string(),
                )]),
                true,
            )
            .await;

        let response = router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/status/cluster")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_eq!(response.status(), StatusCode::OK);
        let body: Value = serde_json::from_str(&response_text(response).await)
            .expect("failed to decode up response");
        assert_eq!(body["ring_members"], 2);
        assert_eq!(body["generation"], 1);
        assert_eq!(body["region"], "us-east");
        assert_eq!(
            body["members"],
            serde_json::json!(["http://127.0.0.1:7443", "http://peer.kura.internal:4000"])
        );
        assert_eq!(body["regions"], serde_json::json!(["eu-west", "us-east"]));
        assert!(
            body["connected_nodes"]
                .to_string()
                .contains("http://peer.kura.internal:4000")
        );
    }

    #[tokio::test]
    async fn cluster_status_reports_unique_regions_separately_from_node_members() {
        let context = test_context(|config| {
            config.region = "eu-central".into();
        })
        .await;
        context
            .state
            .apply_membership_view(
                std::collections::BTreeSet::from(["eu-central".to_string()]),
                std::collections::BTreeMap::from([
                    (
                        "http://kura-1.kura-headless.kura.svc.cluster.local:7443".to_string(),
                        "eu-central".to_string(),
                    ),
                    (
                        "http://kura-2.kura-headless.kura.svc.cluster.local:7443".to_string(),
                        "eu-central".to_string(),
                    ),
                ]),
                true,
            )
            .await;

        let response = router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/status/cluster")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_eq!(response.status(), StatusCode::OK);
        let body: Value = serde_json::from_str(&response_text(response).await)
            .expect("failed to decode up response");
        assert_eq!(body["ring_members"], 3);
        assert_eq!(body["regions"], serde_json::json!(["eu-central"]));
        assert_eq!(body["members"].as_array().expect("members array").len(), 3);
        assert_eq!(body["nodes"].as_array().expect("nodes array").len(), 3);
    }

    #[tokio::test]
    async fn up_answers_liveness_while_the_readiness_lock_is_held() {
        let context = test_context(|config| {
            config.region = "us-east".into();
        })
        .await;

        let readiness_guard = context.state.readiness.lock().await;

        let response = tokio::time::timeout(
            std::time::Duration::from_secs(5),
            public_router(context.state.clone()).oneshot(
                Request::builder()
                    .uri("/up")
                    .body(Body::empty())
                    .expect("failed to build request"),
            ),
        )
        .await
        .expect("liveness must not wait on cluster state")
        .expect("request failed");

        drop(readiness_guard);

        assert_eq!(response.status(), StatusCode::OK);
        let body: Value = serde_json::from_str(&response_text(response).await)
            .expect("failed to decode up response");
        assert_eq!(body["status"], "ok");
        assert_eq!(body["region"], "us-east");
        for field in [
            "generation",
            "connected_nodes",
            "ring_members",
            "members",
            "regions",
            "nodes",
        ] {
            assert!(
                body.get(field).is_none(),
                "liveness payload must not carry cluster field {field}"
            );
        }
    }

    #[tokio::test]
    async fn up_serves_only_the_liveness_payload_whatever_the_query() {
        let context = test_context(|_| {}).await;
        context
            .state
            .apply_membership_view(
                std::collections::BTreeSet::from(["remote".to_string()]),
                std::collections::BTreeMap::from([(
                    "http://peer.kura.internal:7443".to_string(),
                    "remote".to_string(),
                )]),
                true,
            )
            .await;

        for query in ["", "?cluster=true", "?verbose=1"] {
            let response = public_router(context.state.clone())
                .oneshot(
                    Request::builder()
                        .uri(format!("/up{query}"))
                        .body(Body::empty())
                        .expect("failed to build request"),
                )
                .await
                .expect("request failed");

            assert_eq!(response.status(), StatusCode::OK, "query {query}");
            let body: Value = serde_json::from_str(&response_text(response).await)
                .expect("failed to decode up response");
            assert_eq!(body["status"], "ok", "query {query}");
            assert!(
                body.get("ring_members").is_none(),
                "liveness must have no cluster variant (query {query})"
            );
        }
    }

    #[tokio::test]
    async fn cluster_status_is_metered_apart_from_the_liveness_probe() {
        let context = test_context(|_| {}).await;
        let app = public_router(context.state.clone());

        for uri in ["/up", "/status/cluster"] {
            let response = app
                .clone()
                .oneshot(
                    Request::builder()
                        .uri(uri)
                        .body(Body::empty())
                        .expect("failed to build request"),
                )
                .await
                .expect("request failed");
            assert_eq!(response.status(), StatusCode::OK, "{uri}");
        }

        // Classification keys off the path template, so the aggregating route
        // has to be its own template or its latency lands on the probe's series.
        let metrics = context.state.metrics.render();
        assert!(metrics.contains("route=\"/up\""));
        assert!(metrics.contains("route=\"/status/cluster\""));
    }

    #[tokio::test]
    async fn up_stays_ok_while_draining_and_before_discovery() {
        let context = test_context(|_| {}).await;

        for stage in ["before discovery", "draining"] {
            let response = public_router(context.state.clone())
                .oneshot(
                    Request::builder()
                        .uri("/up")
                        .body(Body::empty())
                        .expect("failed to build request"),
                )
                .await
                .expect("up route should respond");

            assert_eq!(response.status(), StatusCode::OK, "{stage}");
            let body: Value = serde_json::from_str(&response_text(response).await)
                .expect("failed to decode up response");
            assert_eq!(body["status"], "ok", "{stage}");

            context.state.enter_draining();
        }

        let ready_response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/ready")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("ready route should respond");
        assert_eq!(ready_response.status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[test]
    fn route_template_for_path_stabilizes_cache_paths() {
        assert_eq!(route_template_for_path(ROUTE_UP), ROUTE_UP);
        assert_eq!(
            route_template_for_path(ROUTE_STATUS_CLUSTER),
            ROUTE_STATUS_CLUSTER
        );
        assert_eq!(
            route_template_for_path("/api/cache/cas/artifact-one"),
            ROUTE_API_CACHE_CAS
        );
        assert_eq!(
            route_template_for_path("/api/cache/keyvalue/cas-one"),
            ROUTE_API_CACHE_KEYVALUE_ID
        );
        assert_eq!(
            route_template_for_path("/api/cache/gradle/cache-key-one"),
            ROUTE_API_CACHE_GRADLE
        );
        assert_eq!(
            route_template_for_path("/_internal/backfill/artifacts/artifact-one"),
            ROUTE_INTERNAL_BACKFILL_ARTIFACT
        );
        assert_eq!(
            route_template_for_path("/_internal/bootstrap/artifacts/artifact-one"),
            UNMATCHED_ROUTE,
            "the retired legacy bootstrap route must not resolve to a template"
        );
        assert_eq!(
            route_template_for_path("/api/cache/cas/artifact-one/extra"),
            UNMATCHED_ROUTE
        );
        assert_eq!(route_template_for_path("/.docker/.env"), UNMATCHED_ROUTE);
    }

    #[test]
    fn public_load_routes_exclude_probes_internal_and_unmatched_routes() {
        assert!(is_public_load_route(ROUTE_API_CACHE_CAS));
        assert!(is_public_load_route(ROUTE_API_CACHE_MODULE));
        assert!(!is_public_load_route(ROUTE_UP));
        assert!(!is_public_load_route(ROUTE_STATUS_CLUSTER));
        assert!(!is_public_load_route(ROUTE_METRICS));
        assert!(!is_public_load_route(ROUTE_INTERNAL_REPLICATE_ARTIFACT));
        assert!(!is_public_load_route(UNMATCHED_ROUTE));
    }

    #[tokio::test]
    async fn dynamic_cache_paths_use_template_route_metric_labels() {
        let context = test_context(|_| {}).await;
        let app = public_router(context.state.clone());

        for artifact_id in ["artifact-one", "artifact-two"] {
            let response = app
                .clone()
                .oneshot(
                    Request::builder()
                        .uri(format!("/api/cache/cas/{artifact_id}"))
                        .body(Body::empty())
                        .expect("failed to build request"),
                )
                .await
                .expect("request failed");

            assert_ne!(response.status(), StatusCode::NOT_FOUND);
        }

        let metrics = context.state.metrics.render();
        assert!(metrics.contains(&format!("route=\"{ROUTE_API_CACHE_CAS}\"")));
        assert!(!metrics.contains("artifact-one"));
        assert!(!metrics.contains("artifact-two"));
        assert!(!metrics.contains("route=\"/api/cache/cas/artifact-"));
    }

    // Regression test: inline artifact replication used to bound the body by
    // the client-facing key-value limit (1 MiB), which 413'd every 1–4 MiB
    // action result the sender pushed inline. The receive limit must track the
    // inline replication ceiling instead, so a body in that range applies.
    #[tokio::test]
    async fn inline_artifact_replication_accepts_bodies_above_the_keyvalue_limit() {
        let context = test_context(|_| {}).await;
        let body_len = MAX_INLINE_REPLICATION_BODY_BYTES as usize / 2;
        assert!(
            body_len > context.state.config.max_keyvalue_bytes,
            "fixture must exceed the key-value limit to exercise the regression"
        );

        let response = internal_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(
                        "/_internal/replicate/artifact?producer=reapi&inline=true\
                         &namespace_id=tuist&key=action_cache%2Fdeadbeef%2F65\
                         &content_type=application%2Fx-protobuf&version_ms=1000",
                    )
                    .body(Body::from(vec![0u8; body_len]))
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_eq!(response.status(), StatusCode::NO_CONTENT);

        let stored = context
            .state
            .store
            .fetch_inline_artifact_bytes(
                ArtifactProducer::Reapi,
                "tuist",
                "action_cache/deadbeef/65",
            )
            .expect("inline fetch should succeed")
            .expect("replicated artifact should be persisted");
        assert_eq!(stored.len(), body_len);
    }

    // Pins the exact inline replication ceiling so a future limit or comparison
    // tweak can't silently reintroduce an off-by-one strand: a body of exactly
    // MAX_INLINE_REPLICATION_BODY_BYTES applies, one byte more is rejected.
    #[tokio::test]
    async fn inline_artifact_replication_enforces_the_inline_ceiling_boundary() {
        let context = test_context(|_| {}).await;

        let put = |key: &'static str, len: usize| {
            internal_router(context.state.clone()).oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!(
                        "/_internal/replicate/artifact?producer=reapi&inline=true\
                         &namespace_id=tuist&key={key}\
                         &content_type=application%2Fx-protobuf&version_ms=1000"
                    ))
                    .body(Body::from(vec![0u8; len]))
                    .expect("failed to build request"),
            )
        };

        let at_limit = put(
            "action_cache%2Faaaa%2F1",
            MAX_INLINE_REPLICATION_BODY_BYTES as usize,
        )
        .await
        .expect("request failed");
        assert_eq!(at_limit.status(), StatusCode::NO_CONTENT);

        let over_limit = put(
            "action_cache%2Fbbbb%2F1",
            MAX_INLINE_REPLICATION_BODY_BYTES as usize + 1,
        )
        .await
        .expect("request failed");
        assert_eq!(over_limit.status(), StatusCode::PAYLOAD_TOO_LARGE);
    }

    #[tokio::test]
    async fn internal_replicate_artifact_fast_fails_under_critical_memory_pressure() {
        let context = test_context(|_| {}).await;
        context
            .state
            .memory
            .observe(context.state.memory.hard_limit_bytes() + 1);

        let response = internal_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(
                        "/_internal/replicate/artifact?producer=reapi&inline=true\
                         &namespace_id=tuist&key=action_cache%2Fdeadbeef%2F65\
                         &content_type=application%2Fx-protobuf&version_ms=1000",
                    )
                    .body(Body::from(vec![0u8; 1024]))
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_retryable_hint(&response, backpressure::IDLE_RETRY_AFTER_CEILING_SECONDS);
    }

    #[tokio::test]
    async fn internal_reads_are_not_rejected_under_critical_memory_pressure() {
        let context = test_context(|_| {}).await;
        context
            .state
            .memory
            .observe(context.state.memory.hard_limit_bytes() + 1);

        let response = internal_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/_internal/status")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_ne!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[tokio::test]
    async fn unknown_paths_use_a_stable_unmatched_route_metric_label() {
        let context = test_context(|_| {}).await;

        let response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/.docker/.env")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_eq!(response.status(), StatusCode::NOT_FOUND);

        let metrics = context.state.metrics.render();
        assert!(metrics.contains("route=\"/_unmatched\""));
        assert!(!metrics.contains("route=\"/.docker/.env\""));
    }

    #[tokio::test]
    async fn cluster_status_and_ready_share_the_same_membership_generation() {
        let context = test_context(|_| {}).await;
        let peer = "http://peer.kura.internal:7443".to_string();
        context
            .state
            .apply_membership_view(
                std::collections::BTreeSet::from(["remote".to_string()]),
                std::collections::BTreeMap::from([(peer.clone(), "remote".to_string())]),
                true,
            )
            .await;
        settle_backfill_cycle_over(&context.state, &peer, tokio::time::Instant::now());
        context.state.expire_readiness_settle_window().await;
        context.state.maybe_mark_serving().await;

        let up_response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/status/cluster")
                    .body(Body::empty())
                    .expect("failed to build up request"),
            )
            .await
            .expect("up route should respond");
        let up_body: Value =
            serde_json::from_str(&response_text(up_response).await).expect("up response json");

        let ready_response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/ready")
                    .body(Body::empty())
                    .expect("failed to build ready request"),
            )
            .await
            .expect("ready route should respond");
        let ready_body: Value = serde_json::from_str(&response_text(ready_response).await)
            .expect("ready response json");

        assert_eq!(up_body["generation"], ready_body["generation"]);
    }

    #[tokio::test]
    async fn ready_reports_draining_state() {
        let context = test_context(|_| {}).await;
        context
            .state
            .apply_membership_view(
                std::collections::BTreeSet::new(),
                std::collections::BTreeMap::new(),
                true,
            )
            .await;
        context.state.expire_readiness_settle_window().await;
        context.state.maybe_mark_serving().await;
        context.state.enter_draining();

        let response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/ready")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("ready route should respond");
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        let body: Value = serde_json::from_str(&response_text(response).await)
            .expect("ready response should be json");
        assert_eq!(body["state"], "draining");
        assert_eq!(body["draining"], true);
        assert!(body["reasons"].to_string().contains("draining"));
    }

    #[tokio::test]
    async fn rollout_status_reports_rollout_summary_and_stays_available_while_draining() {
        let context = test_context(|_| {}).await;
        let peer = "http://peer.kura.internal:7443".to_string();
        context
            .state
            .apply_membership_view(
                std::collections::BTreeSet::from(["remote".to_string()]),
                std::collections::BTreeMap::from([(peer.clone(), "remote".to_string())]),
                true,
            )
            .await;
        settle_backfill_cycle_over(&context.state, &peer, tokio::time::Instant::now());
        context.state.expire_readiness_settle_window().await;
        context.state.maybe_mark_serving().await;
        context.state.metrics.update_outbox_messages(7);
        context
            .state
            .metrics
            .record_file_descriptor_wait("timeout", Duration::from_millis(5));
        context.state.metrics.record_replication(
            &peer,
            "upsert_artifact",
            "error",
            Duration::from_millis(3),
        );
        context.state.enter_draining();

        let response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/status/rollout")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("rollout status route should respond");
        assert_eq!(response.status(), StatusCode::OK);
        let body: Value = serde_json::from_str(&response_text(response).await)
            .expect("rollout status response should be json");
        assert_eq!(body["generation"], 1);
        assert_eq!(body["state"], "draining");
        assert_eq!(body["ready"], false);
        assert_eq!(body["ring_members"], 2);
        assert_eq!(body["outbox_messages"], 7);
        assert_eq!(body["memory_pressure_state"], 0);
        assert_eq!(body["fd_timeout_count"], 1);
        assert_eq!(body["peer_connection_failure_count"], 1);
        let fingerprint = body["ring_fingerprint"]
            .as_str()
            .expect("ring fingerprint should be a string");
        assert_eq!(fingerprint.len(), 16);
        assert!(fingerprint.chars().all(|c| c.is_ascii_hexdigit()));
        assert_eq!(body["backfill_initial_cycle"], "complete");
    }

    fn backfill_tick<'a>(
        discovered: &'a [String],
        lost: &'a [String],
    ) -> crate::backfill::lifecycle::MembershipTick<'a> {
        crate::backfill::lifecycle::MembershipTick {
            discovered,
            lost,
            view_settled: true,
            control_plane_peers: &[],
            admission: true,
        }
    }

    /// Settles the initial backfill cycle over one peer: first pass plus the
    /// seam follow-up, driven through the machine without pass tasks.
    fn settle_backfill_cycle_over(state: &SharedState, peer: &str, now: tokio::time::Instant) {
        use crate::backfill::lifecycle::PassResolution;
        let discovered = vec![peer.to_string()];
        state
            .backfill
            .test_evaluate(&backfill_tick(&discovered, &[]), now);
        state
            .backfill
            .test_finish_pass(peer, PassResolution::Completed, now);
        let seam = now + Duration::from_millis(crate::constants::BACKFILL_SEAM_FOLLOWUP_DELAY_MS);
        state.backfill.test_evaluate(&backfill_tick(&[], &[]), seam);
        state
            .backfill
            .test_finish_pass(peer, PassResolution::Completed, seam);
    }

    async fn get_ready_status(state: &SharedState) -> (StatusCode, Value) {
        let response = public_router(state.clone())
            .oneshot(
                Request::builder()
                    .uri("/ready")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("ready route should respond");
        let status = response.status();
        let body: Value = serde_json::from_str(&response_text(response).await)
            .expect("ready response should be json");
        (status, body)
    }

    #[tokio::test]
    async fn ready_latches_under_backfill_and_survives_a_peer_flap() {
        let context = test_context(|_| {}).await;
        let peer = "http://peer.kura.internal:7443".to_string();
        context
            .state
            .apply_membership_view(
                std::collections::BTreeSet::from(["remote".to_string()]),
                std::collections::BTreeMap::from([(peer.clone(), "remote".to_string())]),
                true,
            )
            .await;
        settle_backfill_cycle_over(&context.state, &peer, tokio::time::Instant::now());
        context.state.expire_readiness_settle_window().await;

        let (status, body) = get_ready_status(&context.state).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(body["state"], "serving");

        // The 2026-07-24 class: the peer flaps out and back, so its re-join
        // backfill makes the node "backfilling" again. Readiness must not
        // regress.
        let flapped = vec![peer.clone()];
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&[], &flapped), tokio::time::Instant::now());
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&flapped, &[]), tokio::time::Instant::now());
        assert!(context.state.backfill.cycle_snapshot().is_backfilling());
        context
            .state
            .apply_membership_view(
                std::collections::BTreeSet::from(["remote".to_string()]),
                std::collections::BTreeMap::from([(peer.clone(), "remote".to_string())]),
                true,
            )
            .await;

        let (status, body) = get_ready_status(&context.state).await;
        assert_eq!(status, StatusCode::OK, "readiness never regresses");
        assert_eq!(body["state"], "serving");
        assert_eq!(body["ready"], true);
    }

    #[tokio::test]
    async fn ready_reports_draining_after_the_backfill_latch() {
        let context = test_context(|_| {}).await;
        context
            .state
            .apply_membership_view(
                std::collections::BTreeSet::new(),
                std::collections::BTreeMap::new(),
                true,
            )
            .await;
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&[], &[]), tokio::time::Instant::now());
        context.state.expire_readiness_settle_window().await;
        let (status, _) = get_ready_status(&context.state).await;
        assert_eq!(status, StatusCode::OK);

        // The orthogonal /ready inputs survive the latch: draining still
        // takes the node out of rotation.
        context.state.enter_draining();
        let (status, body) = get_ready_status(&context.state).await;
        assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(body["state"], "draining");
        assert_eq!(body["ready"], false);
        assert!(body["reasons"].to_string().contains("draining"));
    }

    #[tokio::test]
    async fn rollout_status_reports_the_backfill_cycle_through_to_completion() {
        let context = test_context(|_| {}).await;
        let peer = "http://peer.kura.internal:7443".to_string();
        context
            .state
            .apply_membership_view(
                std::collections::BTreeSet::from(["remote".to_string()]),
                std::collections::BTreeMap::from([(peer.clone(), "remote".to_string())]),
                true,
            )
            .await;

        // Mid-cycle: the mode is pending while a peer still gates.
        let discovered = vec![peer.clone()];
        let now = tokio::time::Instant::now();
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&discovered, &[]), now);
        let response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/status/rollout")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("rollout status route should respond");
        assert_eq!(response.status(), StatusCode::OK);
        let body: Value = serde_json::from_str(&response_text(response).await)
            .expect("rollout status response should be json");
        assert_eq!(body["backfill_initial_cycle"], "pending");
        assert_eq!(body["backfill_backfilling_peers"], 1);
        assert_eq!(body["backfill_budget_exhausted_real_peers"], 0);
        assert_eq!(body["backfill_budget_exhausted_capability_peers"], 0);
        assert_eq!(body["backfill_ring_fullness_percent"], 0);

        // Settled: the mode reads complete, which is what gate.sh and the
        // fleet-rollout flow act on.
        {
            use crate::backfill::lifecycle::PassResolution;
            context
                .state
                .backfill
                .test_finish_pass(&peer, PassResolution::Completed, now);
            let seam =
                now + Duration::from_millis(crate::constants::BACKFILL_SEAM_FOLLOWUP_DELAY_MS);
            context
                .state
                .backfill
                .test_evaluate(&backfill_tick(&[], &[]), seam);
            context
                .state
                .backfill
                .test_finish_pass(&peer, PassResolution::Completed, seam);
        }
        context.state.expire_readiness_settle_window().await;
        let response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/status/rollout")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("rollout status route should respond");
        let body: Value = serde_json::from_str(&response_text(response).await)
            .expect("rollout status response should be json");
        assert_eq!(body["backfill_initial_cycle"], "complete");
        assert_eq!(body["backfill_backfilling_peers"], 0);
        assert_eq!(body["ready"], true, "the settled node latched serving");
        assert_eq!(body["state"], "serving");
    }

    #[tokio::test]
    async fn draining_public_requests_return_service_unavailable_and_close_http1_connections() {
        let context = test_context(|_| {}).await;
        context
            .state
            .apply_membership_view(
                std::collections::BTreeSet::new(),
                std::collections::BTreeMap::new(),
                true,
            )
            .await;
        context.state.expire_readiness_settle_window().await;
        context.state.maybe_mark_serving().await;
        context.state.enter_draining();

        let response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/v1/cache/some-hash")
                    .version(Version::HTTP_11)
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("public route should respond");
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(
            response.headers().get(axum::http::header::CONNECTION),
            Some(&HeaderValue::from_static("close"))
        );
    }

    #[tokio::test]
    async fn public_router_does_not_serve_internal_routes() {
        let context = test_context(|_| {}).await;

        let response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/_internal/status")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }

    async fn put_backfill_inline(
        state: &SharedState,
        namespace_id: &str,
        key: &str,
        version_ms: u64,
    ) {
        state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                namespace_id,
                key,
                "application/octet-stream",
                b"payload",
                version_ms,
                None,
                None,
            )
            .await
            .expect("inline artifact should apply");
    }

    async fn backfill_entries_response(state: &SharedState, uri: &str) -> Response {
        internal_router(state.clone())
            .oneshot(
                Request::builder()
                    .uri(uri)
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed")
    }

    async fn backfill_entries_page(
        state: &SharedState,
        after: Option<&str>,
        limit: usize,
    ) -> BackfillEntriesPage {
        let mut uri = format!("/_internal/backfill/entries?limit={limit}");
        if let Some(after) = after {
            uri.push_str(&format!("&after={after}"));
        }
        let response = backfill_entries_response(state, &uri).await;
        assert_eq!(response.status(), StatusCode::OK);
        serde_json::from_str(&response_text(response).await)
            .expect("failed to decode backfill entries page")
    }

    /// Walks the listing to exhaustion through the real router, bounded so a
    /// cursor regression can never hang the test.
    async fn walk_backfill_entries(state: &SharedState, limit: usize) -> Vec<BackfillEntry> {
        let mut entries = Vec::new();
        let mut after: Option<String> = None;
        for _ in 0..32 {
            let page = backfill_entries_page(state, after.as_deref(), limit).await;
            entries.extend(page.entries);
            match page.next_after {
                Some(cursor) => after = Some(cursor),
                None => return entries,
            }
        }
        panic!("backfill entries pagination did not terminate");
    }

    #[tokio::test]
    async fn backfill_entries_list_tuples_newest_first_with_kinds_and_sizes() {
        let context = test_context(|_| {}).await;
        let store = &context.state.store;
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "segmented",
                "application/octet-stream",
                b"segmented-body",
                600,
            )
            .await
            .expect("segmented artifact should apply");
        put_backfill_inline(&context.state, "ios", "inline", 500).await;
        store
            .apply_replicated_namespace_delete("android", 250)
            .await
            .expect("tombstone should apply");
        store
            .run_backfill_index_build()
            .expect("index build should succeed");

        let response =
            backfill_entries_response(&context.state, "/_internal/backfill/entries").await;
        assert_eq!(response.status(), StatusCode::OK);
        let body: Value = serde_json::from_str(&response_text(response).await)
            .expect("failed to decode backfill entries response");

        assert_eq!(
            body["entries"],
            serde_json::json!([
                {
                    "record_kind": "segment_artifact",
                    "record_id":
                        artifact_storage_id(ArtifactProducer::Gradle, "test-tenant", "ios", "segmented"),
                    "version_ms": 600,
                    "size": 14,
                },
                {
                    "record_kind": "inline_artifact",
                    "record_id":
                        artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "inline"),
                    "version_ms": 500,
                    "size": 7,
                },
                {
                    "record_kind": "namespace_tombstone",
                    "record_id": "android",
                    "version_ms": 250,
                },
            ]),
            "tuples list newest-first; tombstones carry no size field"
        );
        assert_eq!(body["next_after"], Value::Null);
    }

    #[tokio::test]
    async fn backfill_entries_paginate_to_exhaustion_with_stable_cursors() {
        let context = test_context(|_| {}).await;
        for version_ms in [100_u64, 200, 300, 400, 500] {
            put_backfill_inline(&context.state, "ios", &format!("k{version_ms}"), version_ms).await;
        }
        context
            .state
            .store
            .run_backfill_index_build()
            .expect("index build should succeed");

        let first = backfill_entries_page(&context.state, None, 2).await;
        assert_eq!(
            first
                .entries
                .iter()
                .map(|entry| entry.version_ms)
                .collect::<Vec<_>>(),
            vec![500, 400]
        );
        let cursor = first.next_after.clone().expect("more pages should remain");

        // Writes between pages must not disturb an already-issued cursor.
        put_backfill_inline(&context.state, "ios", "k250", 250).await;

        let entries = walk_backfill_entries(&context.state, 2).await;
        assert_eq!(
            entries
                .iter()
                .map(|entry| entry.version_ms)
                .collect::<Vec<_>>(),
            vec![500, 400, 300, 250, 200, 100]
        );

        // The pre-write cursor resumes exactly where it left off and sees the
        // interleaved row.
        let resumed = backfill_entries_page(&context.state, Some(&cursor), 100).await;
        assert_eq!(
            resumed
                .entries
                .iter()
                .map(|entry| entry.version_ms)
                .collect::<Vec<_>>(),
            vec![300, 250, 200, 100]
        );
        assert_eq!(resumed.next_after, None);
    }

    #[tokio::test]
    async fn backfill_entries_cursor_never_repeats_or_skips_across_deletions() {
        let context = test_context(|_| {}).await;
        for version_ms in [100_u64, 200, 300, 400, 500, 600] {
            put_backfill_inline(&context.state, "ios", &format!("k{version_ms}"), version_ms).await;
        }
        context
            .state
            .store
            .run_backfill_index_build()
            .expect("index build should succeed");

        let first = backfill_entries_page(&context.state, None, 2).await;
        assert_eq!(
            first
                .entries
                .iter()
                .map(|entry| entry.version_ms)
                .collect::<Vec<_>>(),
            vec![600, 500]
        );
        let mut after = first.next_after.clone();

        // Between pages: two upcoming rows are LWW-overwritten (their index
        // rows move ahead of the cursor) and a brand-new row lands behind it.
        put_backfill_inline(&context.state, "ios", "k300", 700).await;
        put_backfill_inline(&context.state, "ios", "k400", 800).await;
        put_backfill_inline(&context.state, "ios", "k450", 450).await;

        let mut entries = first.entries;
        for _ in 0..32 {
            let Some(cursor) = after else { break };
            let page = backfill_entries_page(&context.state, Some(&cursor), 2).await;
            entries.extend(page.entries);
            after = page.next_after;
        }
        assert!(after.is_none(), "pagination did not terminate");

        assert_eq!(
            entries
                .iter()
                .map(|entry| entry.version_ms)
                .collect::<Vec<_>>(),
            vec![600, 500, 450, 200, 100],
            "surviving rows appear exactly once; moved rows are neither repeated nor resurrected"
        );
        let mut record_ids: Vec<_> = entries.iter().map(|entry| &entry.record_id).collect();
        record_ids.sort();
        record_ids.dedup();
        assert_eq!(record_ids.len(), entries.len(), "no record listed twice");
    }

    #[tokio::test]
    async fn backfill_entries_empty_index_returns_empty_page_without_cursor() {
        let context = test_context(|_| {}).await;
        context
            .state
            .store
            .run_backfill_index_build()
            .expect("index build should succeed");

        let page = backfill_entries_page(&context.state, None, 10).await;
        assert_eq!(page.entries, vec![]);
        assert_eq!(page.next_after, None);
    }

    #[tokio::test]
    async fn backfill_entries_reject_malformed_cursors() {
        let context = test_context(|_| {}).await;
        context
            .state
            .store
            .run_backfill_index_build()
            .expect("index build should succeed");

        for after in ["not-hex".to_owned(), hex::encode("some/other/key")] {
            let response = backfill_entries_response(
                &context.state,
                &format!("/_internal/backfill/entries?after={after}"),
            )
            .await;
            assert_eq!(response.status(), StatusCode::BAD_REQUEST);
            let body: Value = serde_json::from_str(&response_text(response).await)
                .expect("failed to decode error response");
            assert!(
                body["message"]
                    .as_str()
                    .expect("message should be a string")
                    .starts_with("Invalid after"),
                "unexpected message: {}",
                body["message"]
            );
        }
    }

    #[test]
    fn backfill_entries_query_clamps_oversized_limits() {
        let oversized = HashMap::from([("limit".to_owned(), usize::MAX.to_string())]);
        assert_eq!(
            BackfillEntriesQuery::from_params(&oversized)
                .expect("oversized limit should be clamped")
                .limit,
            MAX_PEER_PAGE_ITEMS
        );
        assert_eq!(
            BackfillEntriesQuery::from_params(&HashMap::new())
                .expect("defaults should be accepted"),
            BackfillEntriesQuery {
                after: None,
                limit: 256
            }
        );
        BackfillEntriesQuery::from_params(&HashMap::from([("limit".to_owned(), "0".to_owned())]))
            .expect_err("zero limit must be rejected");
        BackfillEntriesQuery::from_params(&HashMap::from([("limit".to_owned(), "abc".to_owned())]))
            .expect_err("non-numeric limit must be rejected");
    }

    #[tokio::test]
    async fn backfill_entries_clamp_oversized_limits_through_the_router() {
        let context = test_context(|_| {}).await;
        put_backfill_inline(&context.state, "ios", "artifact", 100).await;
        context
            .state
            .store
            .run_backfill_index_build()
            .expect("index build should succeed");

        let page = backfill_entries_page(&context.state, None, usize::MAX).await;
        assert_eq!(page.entries.len(), 1);
        assert_eq!(page.next_after, None);
    }

    #[tokio::test]
    async fn backfill_entries_report_index_building_with_a_typed_retryable_body() {
        let context = test_context(|_| {}).await;
        assert!(!context.state.store.backfill_index_built());

        let response =
            backfill_entries_response(&context.state, "/_internal/backfill/entries").await;
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        let body: BackfillUnavailable = serde_json::from_str(&response_text(response).await)
            .expect("failed to decode index-building response");
        assert_eq!(body.error, BACKFILL_ERROR_INDEX_BUILDING);

        // The internal route is counted and timed under its route label even
        // while the node answers "index building".
        let rendered = context.state.metrics.render();
        assert!(rendered.lines().any(|line| {
            line.starts_with("kura_http_requests_total")
                && line.contains("route=\"/_internal/backfill/entries\"")
                && line.contains("status=\"503\"")
        }));
        assert!(rendered.lines().any(|line| {
            line.starts_with("kura_internal_backfill_http_request_duration_seconds_count")
                && line.contains("route=\"/_internal/backfill/entries\"")
        }));
    }

    #[tokio::test]
    async fn public_router_does_not_serve_backfill_entries() {
        let context = test_context(|_| {}).await;

        let response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/_internal/backfill/entries")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }

    async fn put_backfill_inline_body(
        state: &SharedState,
        namespace_id: &str,
        key: &str,
        body: &[u8],
        version_ms: u64,
    ) {
        state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                namespace_id,
                key,
                "application/octet-stream",
                body,
                version_ms,
                None,
                None,
            )
            .await
            .expect("inline artifact should apply");
    }

    fn bodies_entry(record_kind: &str, record_id: &str, version_ms: u64) -> BackfillEntry {
        BackfillEntry {
            record_kind: record_kind.to_owned(),
            record_id: record_id.to_owned(),
            version_ms,
            size: None,
        }
    }

    async fn post_backfill_bodies(
        state: &SharedState,
        entries: &[BackfillEntry],
        identity: Option<&str>,
    ) -> Response {
        let body = serde_json::to_vec(&BackfillBodiesRequest {
            entries: entries.to_vec(),
        })
        .expect("encode bodies request");
        let mut request = Request::builder()
            .method("POST")
            .uri("/_internal/backfill/bodies")
            .header("content-type", "application/json")
            .body(Body::from(body))
            .expect("failed to build request");
        if let Some(identity) = identity {
            request
                .extensions_mut()
                .insert(InternalPeerIdentity(identity.into()));
        }
        internal_router(state.clone())
            .oneshot(request)
            .await
            .expect("request failed")
    }

    async fn response_bytes(response: Response) -> Vec<u8> {
        response
            .into_body()
            .collect()
            .await
            .expect("failed to collect response body")
            .to_bytes()
            .to_vec()
    }

    async fn decode_backfill_frames(bytes: &[u8]) -> Vec<BackfillBodyFrame> {
        let mut reader = bytes;
        let mut frames = Vec::new();
        while let Some(frame) = read_backfill_body_frame(&mut reader)
            .await
            .expect("decode backfill body frame")
        {
            frames.push(frame);
        }
        frames
    }

    fn backfill_index_versions_for(state: &SharedState, record_id: &str) -> Vec<u64> {
        state
            .store
            .backfill_index_page(None, MAX_PEER_PAGE_ITEMS)
            .expect("scan backfill index")
            .entries
            .into_iter()
            .filter(|row| row.record_id == record_id)
            .map(|row| row.version_ms)
            .collect()
    }

    #[tokio::test]
    async fn backfill_bodies_round_trip_mixed_segmented_and_inline_batches() {
        let context = test_context(|_| {}).await;
        let segmented_body = vec![7u8; 100_000];
        context
            .state
            .store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "segmented",
                "application/octet-stream",
                &segmented_body,
                600,
            )
            .await
            .expect("segmented artifact should apply");
        put_backfill_inline_body(&context.state, "ios", "inline", b"inline-body", 500).await;
        let segmented_id =
            artifact_storage_id(ArtifactProducer::Gradle, "test-tenant", "ios", "segmented");
        let inline_id =
            artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "inline");

        let response = post_backfill_bodies(
            &context.state,
            &[
                bodies_entry("segment_artifact", &segmented_id, 600),
                bodies_entry("inline_artifact", &inline_id, 500),
            ],
            None,
        )
        .await;
        assert_eq!(response.status(), StatusCode::OK);
        let declared_len = response
            .headers()
            .get(axum::http::header::CONTENT_LENGTH)
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse::<usize>().ok())
            .expect("bodies response should declare its length");
        let bytes = response_bytes(response).await;
        assert_eq!(bytes.len(), declared_len);

        let frames = decode_backfill_frames(&bytes).await;
        assert_eq!(frames.len(), 2);
        assert_eq!(frames[0].kind, BackfillRecordKind::SegmentArtifact);
        assert_eq!(frames[0].disposition, BackfillBodyDisposition::Present);
        assert_eq!(frames[0].record_id, segmented_id);
        assert_eq!(frames[0].version_ms, 600);
        assert_eq!(frames[0].body, segmented_body);
        assert_eq!(frames[1].kind, BackfillRecordKind::InlineArtifact);
        assert_eq!(frames[1].disposition, BackfillBodyDisposition::Present);
        assert_eq!(frames[1].record_id, inline_id);
        assert_eq!(frames[1].version_ms, 500);
        assert_eq!(frames[1].body, b"inline-body");
    }

    #[tokio::test]
    async fn backfill_bodies_reject_tombstone_kinds() {
        let context = test_context(|_| {}).await;

        let response = post_backfill_bodies(
            &context.state,
            &[bodies_entry("namespace_tombstone", "android", 250)],
            None,
        )
        .await;

        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        let body = response_text(response).await;
        assert!(body.contains("metadata-only"), "unexpected body: {body}");

        let unknown = post_backfill_bodies(
            &context.state,
            &[bodies_entry("mystery_kind", "whatever", 1)],
            None,
        )
        .await;
        assert_eq!(unknown.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn backfill_bodies_frame_deleted_entries_absent_without_failing_the_batch() {
        let context = test_context(|_| {}).await;
        put_backfill_inline_body(&context.state, "ios", "doomed", b"doomed-body", 500).await;
        put_backfill_inline_body(&context.state, "android", "survivor", b"survivor-body", 400)
            .await;
        let doomed_id =
            artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "doomed");
        let survivor_id = artifact_storage_id(
            ArtifactProducer::Xcode,
            "test-tenant",
            "android",
            "survivor",
        );

        // Deletes every "ios" manifest between listing and fetch.
        context
            .state
            .store
            .apply_replicated_namespace_delete("ios", 900)
            .await
            .expect("tombstone should apply");

        let response = post_backfill_bodies(
            &context.state,
            &[
                bodies_entry("inline_artifact", &doomed_id, 500),
                bodies_entry("inline_artifact", &survivor_id, 400),
            ],
            None,
        )
        .await;
        assert_eq!(response.status(), StatusCode::OK);
        let frames = decode_backfill_frames(&response_bytes(response).await).await;
        assert_eq!(frames.len(), 2);
        assert_eq!(frames[0].disposition, BackfillBodyDisposition::Absent);
        assert_eq!(frames[0].record_id, doomed_id);
        // Absent frames echo the requested tuple to identify it.
        assert_eq!(frames[0].version_ms, 500);
        assert!(frames[0].body.is_empty());
        assert_eq!(frames[1].disposition, BackfillBodyDisposition::Present);
        assert_eq!(frames[1].body, b"survivor-body");
    }

    #[tokio::test]
    async fn backfill_bodies_serve_current_version_and_body_after_lww_overwrite() {
        let context = test_context(|_| {}).await;
        put_backfill_inline_body(&context.state, "ios", "k", b"body-v1", 500).await;
        let record_id = artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "k");
        // Overwrite between listing and fetch; the writer replaces the v500
        // index row with the v800 one.
        put_backfill_inline_body(&context.state, "ios", "k", b"body-v2-longer", 800).await;
        // Plant the stale v500 row back, as a build/live race would leave it.
        context
            .state
            .store
            .insert_backfill_index_row_for_testing(
                500,
                BackfillRecordKind::InlineArtifact,
                &record_id,
                Some(7),
            )
            .expect("plant stale row");
        assert_eq!(
            backfill_index_versions_for(&context.state, &record_id),
            vec![800, 500]
        );

        let response = post_backfill_bodies(
            &context.state,
            &[bodies_entry("inline_artifact", &record_id, 500)],
            None,
        )
        .await;
        assert_eq!(response.status(), StatusCode::OK);
        let frames = decode_backfill_frames(&response_bytes(response).await).await;
        assert_eq!(frames.len(), 1);
        // Current version and current body — never v2 bytes under a v1 stamp.
        assert_eq!(frames[0].disposition, BackfillBodyDisposition::Present);
        assert_eq!(frames[0].version_ms, 800);
        assert_eq!(frames[0].body, b"body-v2-longer");
        // The mismatched requested row was retired during serve.
        assert_eq!(
            backfill_index_versions_for(&context.state, &record_id),
            vec![800]
        );
    }

    #[tokio::test]
    async fn backfill_bodies_retire_dangling_rows_and_frame_them_absent() {
        let context = test_context(|_| {}).await;
        // Two dangling rows in one request: retirement is collected across
        // the request and flushed as one batched write, so both must be gone
        // after the response.
        let first_record_id = "0000000000000000000000000000000000000000000000000000000000000000";
        let second_record_id = "1111111111111111111111111111111111111111111111111111111111111111";
        for (record_id, version_ms) in [(first_record_id, 700), (second_record_id, 800)] {
            context
                .state
                .store
                .insert_backfill_index_row_for_testing(
                    version_ms,
                    BackfillRecordKind::InlineArtifact,
                    record_id,
                    Some(9),
                )
                .expect("plant dangling row");
        }
        assert_eq!(
            backfill_index_versions_for(&context.state, first_record_id),
            vec![700]
        );
        assert_eq!(
            backfill_index_versions_for(&context.state, second_record_id),
            vec![800]
        );

        let response = post_backfill_bodies(
            &context.state,
            &[
                bodies_entry("inline_artifact", first_record_id, 700),
                bodies_entry("inline_artifact", second_record_id, 800),
            ],
            None,
        )
        .await;
        assert_eq!(response.status(), StatusCode::OK);
        let frames = decode_backfill_frames(&response_bytes(response).await).await;
        assert_eq!(frames.len(), 2);
        assert_eq!(frames[0].disposition, BackfillBodyDisposition::Absent);
        assert_eq!(frames[0].version_ms, 700);
        assert_eq!(frames[1].disposition, BackfillBodyDisposition::Absent);
        assert_eq!(frames[1].version_ms, 800);
        assert!(
            backfill_index_versions_for(&context.state, first_record_id).is_empty()
                && backfill_index_versions_for(&context.state, second_record_id).is_empty(),
            "dangling rows must be retired during serve"
        );
    }

    #[tokio::test]
    async fn backfill_bodies_boundary_at_the_shared_byte_ceiling() {
        let context = test_context(|_| {}).await;
        let exact_body = vec![1u8; BACKFILL_BODIES_BATCH_BYTES as usize];
        let over_body = vec![2u8; BACKFILL_BODIES_BATCH_BYTES as usize + 1];
        for (key, body, version_ms) in [
            ("exact", &exact_body, 600_u64),
            ("over", &over_body, 700_u64),
        ] {
            context
                .state
                .store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    key,
                    "application/octet-stream",
                    body,
                    version_ms,
                )
                .await
                .expect("segmented artifact should apply");
        }
        put_backfill_inline_body(&context.state, "ios", "small", b"small-body", 800).await;
        let exact_id = artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "exact");
        let over_id = artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "over");
        let small_id = artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "small");

        let response = post_backfill_bodies(
            &context.state,
            &[
                bodies_entry("segment_artifact", &exact_id, 600),
                bodies_entry("segment_artifact", &over_id, 700),
                bodies_entry("inline_artifact", &small_id, 800),
            ],
            None,
        )
        .await;
        assert_eq!(response.status(), StatusCode::OK);
        let frames = decode_backfill_frames(&response_bytes(response).await).await;
        assert_eq!(frames.len(), 3);
        // A batch whose bodies sum to exactly the ceiling passes.
        assert_eq!(frames[0].disposition, BackfillBodyDisposition::Present);
        assert_eq!(frames[0].body, exact_body);
        // One byte over the per-entry cutoff routes to the per-artifact
        // endpoint.
        assert_eq!(
            frames[1].disposition,
            BackfillBodyDisposition::FetchIndividually
        );
        assert_eq!(frames[1].version_ms, 700);
        assert!(frames[1].body.is_empty());
        // The batch is already at the ceiling, so a within-bounds entry with
        // no remaining room also defers to the per-artifact endpoint rather
        // than overflowing the shared bound.
        assert_eq!(
            frames[2].disposition,
            BackfillBodyDisposition::FetchIndividually
        );
    }

    #[tokio::test]
    async fn backfill_bodies_report_tmp_budget_exhaustion_as_retryable_backpressure() {
        let context = test_context(|_| {}).await;
        put_backfill_inline_body(&context.state, "ios", "artifact", b"artifact-body", 500).await;
        let record_id =
            artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "artifact");
        let entries = [bodies_entry("inline_artifact", &record_id, 500)];

        let capacity = context
            .state
            .config
            .tmp_dir_max_bytes
            .min(context.state.memory.peer_staging_budget_bytes());
        let hold = context
            .state
            .peer_staging_budget
            .try_reserve(capacity)
            .expect("reserve the whole staging budget");

        let response = post_backfill_bodies(&context.state, &entries, None).await;
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert!(
            response
                .headers()
                .contains_key(axum::http::header::RETRY_AFTER),
            "backpressure must be marked retryable"
        );
        let unavailable: BackfillUnavailable =
            serde_json::from_str(&response_text(response).await).expect("typed backpressure body");
        assert_eq!(unavailable.error, BACKFILL_ERROR_TMP_BUDGET_EXHAUSTED);

        drop(hold);
        let retried = post_backfill_bodies(&context.state, &entries, None).await;
        assert_eq!(retried.status(), StatusCode::OK);
        let frames = decode_backfill_frames(&response_bytes(retried).await).await;
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].disposition, BackfillBodyDisposition::Present);
    }

    #[tokio::test]
    async fn backfill_bodies_cap_concurrent_requests_per_peer_identity() {
        let context = test_context(|_| {}).await;
        put_backfill_inline_body(&context.state, "ios", "artifact", b"artifact-body", 500).await;
        let record_id =
            artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "artifact");
        let entries = [bodies_entry("inline_artifact", &record_id, 500)];

        // First request from peer-a: admitted; its slot is held while the
        // response body (and the guards it owns) is alive.
        let in_flight = post_backfill_bodies(&context.state, &entries, Some("peer-a")).await;
        assert_eq!(in_flight.status(), StatusCode::OK);

        // Second concurrent request from the same identity is rejected with a
        // retryable typed response.
        let busy = post_backfill_bodies(&context.state, &entries, Some("peer-a")).await;
        assert_eq!(busy.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert!(
            busy.headers().contains_key(axum::http::header::RETRY_AFTER),
            "cap rejection must be marked retryable"
        );
        let unavailable: BackfillUnavailable =
            serde_json::from_str(&response_text(busy).await).expect("typed busy body");
        assert_eq!(unavailable.error, BACKFILL_ERROR_PEER_BUSY);

        // A different identity proceeds while peer-a's slot is held.
        let other = post_backfill_bodies(&context.state, &entries, Some("peer-b")).await;
        assert_eq!(other.status(), StatusCode::OK);
        drop(other);

        // Releasing the first response frees the slot.
        drop(in_flight);
        let after_release = post_backfill_bodies(&context.state, &entries, Some("peer-a")).await;
        assert_eq!(after_release.status(), StatusCode::OK);

        let rendered = context.state.metrics.render();
        assert!(rendered.lines().any(|line| {
            line.starts_with("kura_backfill_bodies_peer_requests_total")
                && line.contains("peer=\"peer-a\"")
                && line.contains("outcome=\"rejected_busy\"")
        }));
        assert!(rendered.lines().any(|line| {
            line.starts_with("kura_backfill_bodies_peer_requests_total")
                && line.contains("peer=\"peer-b\"")
                && line.contains("outcome=\"ok\"")
        }));
    }

    #[tokio::test]
    async fn backfill_bodies_reclaim_spool_files_after_the_response_completes() {
        let context = test_context(|_| {}).await;
        put_backfill_inline_body(&context.state, "ios", "artifact", b"artifact-body", 500).await;
        let record_id =
            artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "artifact");
        let spool_dir = context.state.config.tmp_dir.join("backfill");
        let spool_files = |directory: &std::path::Path| {
            std::fs::read_dir(directory)
                .map(|entries| entries.count())
                .unwrap_or(0)
        };

        let response = post_backfill_bodies(
            &context.state,
            &[bodies_entry("inline_artifact", &record_id, 500)],
            None,
        )
        .await;
        assert_eq!(response.status(), StatusCode::OK);
        assert!(
            spool_files(&spool_dir) > 0,
            "the spool file must exist while the response is in flight"
        );
        let frames = decode_backfill_frames(&response_bytes(response).await).await;
        assert_eq!(frames.len(), 1);

        // The unlink is queued on drop; wait for it rather than racing it.
        for _ in 0..200 {
            if spool_files(&spool_dir) == 0 {
                return;
            }
            sleep(Duration::from_millis(10)).await;
        }
        panic!("spool files were not reclaimed after response completion");
    }

    #[tokio::test]
    async fn backfill_spool_owned_chunks_preserve_bytes() {
        let context = test_context(|_| {}).await;
        let contents = (0..(512 * 1_024 + 37))
            .map(|index| (index % 251) as u8)
            .collect::<Vec<_>>();
        let source = context.state.config.tmp_dir.join("backfill-spool-source");
        let destination = context
            .state
            .config
            .tmp_dir
            .join("backfill-spool-destination");
        std::fs::write(&source, &contents).expect("write backfill spool source");
        let handle = Arc::new(
            context
                .state
                .io
                .open_persistent_read_file(&source)
                .await
                .expect("open backfill spool source"),
        );
        let mut reader = ArtifactReader::FileRange(crate::segment::reader::SegmentReader::new(
            handle,
            0,
            contents.len() as u64,
        ));
        let mut writer = context
            .state
            .io
            .create_file(&destination)
            .await
            .expect("create backfill spool destination");

        let copied = copy_artifact_reader_owned(&mut reader, &mut writer, 64 * 1_024)
            .await
            .expect("copy backfill spool body");
        writer.flush().await.expect("flush backfill spool body");
        drop(writer);

        assert_eq!(copied, contents.len() as u64);
        assert_eq!(
            std::fs::read(destination).expect("read backfill spool destination"),
            contents
        );
    }

    #[tokio::test]
    #[ignore = "performance benchmark run by autoresearch.sh"]
    async fn backfill_spool_owned_chunk_benchmark() {
        const SAMPLE_BYTES: u64 = 512 * 1_024 * 1_024;
        const CHUNK_BYTES: usize = 512 * 1_024;
        const SAMPLE_COUNT: usize = 8;

        async fn measure(handle: Arc<crate::io::PersistentFile>, owned: bool) -> Duration {
            let mut reader = ArtifactReader::FileRange(crate::segment::reader::SegmentReader::new(
                handle,
                0,
                SAMPLE_BYTES,
            ));
            let mut sink = tokio::io::sink();
            let started_at = Instant::now();
            let copied = if owned {
                copy_artifact_reader_owned(&mut reader, &mut sink, CHUNK_BYTES)
                    .await
                    .expect("benchmark owned copy")
            } else {
                tokio::io::copy(&mut reader, &mut sink)
                    .await
                    .expect("benchmark asynchronous-reader copy")
            };
            assert_eq!(copied, SAMPLE_BYTES);
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
            .join("backfill-spool-owned-benchmark");
        let file = std::fs::File::create(&path).expect("create sparse benchmark file");
        file.set_len(SAMPLE_BYTES)
            .expect("size sparse benchmark file");
        drop(file);
        let handle = Arc::new(
            context
                .state
                .io
                .open_persistent_read_file(&path)
                .await
                .expect("open benchmark file"),
        );

        let mut speedups = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut baseline_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut candidate_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        for sample in 0..SAMPLE_COUNT {
            let (baseline_elapsed, candidate_elapsed) = if sample % 2 == 0 {
                (
                    measure(handle.clone(), false).await,
                    measure(handle.clone(), true).await,
                )
            } else {
                let candidate_elapsed = measure(handle.clone(), true).await;
                let baseline_elapsed = measure(handle.clone(), false).await;
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
            "METRIC backfill_spool_owned_speedup_ratio={:.6}",
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
    #[ignore = "performance benchmark run by autoresearch.sh"]
    async fn backfill_spool_response_owned_chunk_benchmark() {
        const SAMPLE_BYTES: u64 = 512 * 1_024 * 1_024;
        const CHUNK_BYTES: usize = 512 * 1_024;
        const SAMPLE_COUNT: usize = 8;

        async fn measure<S>(stream: S) -> Duration
        where
            S: futures_util::Stream<Item = std::io::Result<Bytes>>,
        {
            tokio::pin!(stream);
            let started_at = Instant::now();
            let mut read_bytes = 0_u64;
            while let Some(chunk) = stream.next().await {
                let chunk = chunk.expect("benchmark response chunk");
                std::hint::black_box(chunk.as_ptr());
                read_bytes = read_bytes.saturating_add(chunk.len() as u64);
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
            .join("backfill-spool-response-benchmark");
        let file = std::fs::File::create(&path).expect("create sparse benchmark file");
        file.set_len(SAMPLE_BYTES)
            .expect("size sparse benchmark file");
        drop(file);
        let handle = Arc::new(
            context
                .state
                .io
                .open_persistent_read_file(&path)
                .await
                .expect("open benchmark file"),
        );

        let mut speedups = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut baseline_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        let mut candidate_throughputs = Vec::with_capacity(SAMPLE_COUNT - 1);
        for sample in 0..SAMPLE_COUNT {
            let baseline_file = tokio::fs::File::open(&path)
                .await
                .expect("open baseline benchmark file");
            let baseline = tokio_util::io::ReaderStream::with_capacity(baseline_file, CHUNK_BYTES);
            let candidate = ArtifactReader::FileRange(crate::segment::reader::SegmentReader::new(
                handle.clone(),
                0,
                SAMPLE_BYTES,
            ))
            .into_bytes_stream(CHUNK_BYTES);
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
            "METRIC backfill_spool_response_speedup_ratio={:.6}",
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
    async fn backfill_artifact_endpoint_frames_the_body_and_the_legacy_route_is_gone() {
        let context = test_context(|_| {}).await;
        put_backfill_inline_body(&context.state, "ios", "artifact", b"artifact-body", 500).await;
        let record_id =
            artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "artifact");

        // The re-homed backfill route answers with a single frame carrying
        // the manifest meta the requester's apply path needs.
        let response = internal_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri(format!("/_internal/backfill/artifacts/{record_id}"))
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");
        assert_eq!(response.status(), StatusCode::OK);
        let frames = decode_backfill_frames(&response_bytes(response).await).await;
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].disposition, BackfillBodyDisposition::Present);
        assert_eq!(frames[0].kind, BackfillRecordKind::InlineArtifact);
        assert_eq!(frames[0].record_id, record_id);
        assert_eq!(frames[0].version_ms, 500);
        assert_eq!(frames[0].body, b"artifact-body");
        let meta = frames[0].meta.as_ref().expect("present frame carries meta");
        assert_eq!(meta.producer, "xcode");
        assert_eq!(meta.namespace_id, "ios");
        assert_eq!(meta.key, "artifact");

        // A missing record is a 404 (the requester's absent case).
        let missing = internal_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/_internal/backfill/artifacts/does-not-exist")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");
        assert_eq!(missing.status(), StatusCode::NOT_FOUND);

        // The retired legacy route is gone, not merely unrouted.
        let legacy = internal_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri(format!("/_internal/bootstrap/artifacts/{record_id}"))
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");
        assert_eq!(legacy.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn public_router_does_not_serve_backfill_bodies_or_artifact_alias() {
        let context = test_context(|_| {}).await;

        for (method, uri) in [
            ("POST", "/_internal/backfill/bodies"),
            ("GET", "/_internal/backfill/artifacts/some-artifact"),
        ] {
            let response = public_router(context.state.clone())
                .oneshot(
                    Request::builder()
                        .method(method)
                        .uri(uri)
                        .body(Body::empty())
                        .expect("failed to build request"),
                )
                .await
                .expect("request failed");
            assert_eq!(response.status(), StatusCode::NOT_FOUND, "{method} {uri}");
        }
    }

    #[tokio::test]
    async fn internal_backfill_artifact_sheds_under_critical_memory_pressure() {
        let context = test_context(|_| {}).await;
        put_backfill_inline_body(&context.state, "ios", "artifact", b"artifact-body", 500).await;
        let record_id =
            artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "artifact");
        // Critical pressure fails the background response-stream admission
        // the handler takes before streaming (internal reads pass the write
        // middleware, so this exercises the handler's own shed path).
        context
            .state
            .memory
            .observe(context.state.memory.hard_limit_bytes() + 1);

        let response = internal_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri(format!("/_internal/backfill/artifacts/{record_id}"))
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_retryable_hint(&response, backpressure::IDLE_RETRY_AFTER_CEILING_SECONDS);
    }

    #[tokio::test]
    async fn internal_backfill_bodies_shed_under_critical_memory_pressure() {
        let context = test_context(|_| {}).await;
        let record_id = "0000000000000000000000000000000000000000000000000000000000000000";
        context
            .state
            .memory
            .observe(context.state.memory.hard_limit_bytes() + 1);

        // The combined test router carries no internal write-shed middleware,
        // so the POST reaches the handler and fails its own background
        // response-stream admission after spooling — the shed path under
        // test (behind the real internal router the middleware sheds the
        // write earlier with the same retryable 503).
        let body = serde_json::to_vec(&BackfillBodiesRequest {
            entries: vec![bodies_entry("inline_artifact", record_id, 700)],
        })
        .expect("encode bodies request");
        let response = router(context.state.clone())
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/_internal/backfill/bodies")
                    .header("content-type", "application/json")
                    .body(Body::from(body))
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_retryable_hint(&response, backpressure::IDLE_RETRY_AFTER_CEILING_SECONDS);
        let rendered = context.state.metrics.render();
        assert!(rendered.lines().any(|line| {
            line.starts_with("kura_backfill_bodies_peer_requests_total")
                && line.contains("outcome=\"backpressure\"")
        }));
    }

    #[tokio::test]
    async fn backfill_body_frame_codec_round_trips_and_rejects_malformed_streams() {
        let record_id = "abc123";
        let meta = BackfillBodyManifestMeta {
            producer: "xcode".to_owned(),
            namespace_id: "ios".to_owned(),
            key: "artifact".to_owned(),
            content_type: "application/octet-stream".to_owned(),
            branch: Some("feature".to_owned()),
        };
        let meta_bytes = meta.to_wire_bytes().expect("encode meta");
        let mut stream = encode_backfill_body_frame_header(
            BackfillRecordKind::SegmentArtifact,
            BackfillBodyDisposition::Present,
            1_234,
            record_id,
            &meta_bytes,
            5,
        )
        .expect("encode present header");
        stream.extend_from_slice(b"hello");
        stream.extend_from_slice(
            &encode_backfill_body_frame_header(
                BackfillRecordKind::InlineArtifact,
                BackfillBodyDisposition::Absent,
                777,
                record_id,
                &[],
                0,
            )
            .expect("encode absent header"),
        );

        let mut reader = stream.as_slice();
        let first = read_backfill_body_frame(&mut reader)
            .await
            .expect("decode first frame")
            .expect("first frame present");
        assert_eq!(first.kind, BackfillRecordKind::SegmentArtifact);
        assert_eq!(first.disposition, BackfillBodyDisposition::Present);
        assert_eq!(first.record_id, record_id);
        assert_eq!(first.version_ms, 1_234);
        assert_eq!(first.meta, Some(meta));
        assert_eq!(first.body, b"hello");
        let second = read_backfill_body_frame(&mut reader)
            .await
            .expect("decode second frame")
            .expect("second frame present");
        assert_eq!(second.disposition, BackfillBodyDisposition::Absent);
        assert_eq!(second.meta, None);
        assert!(second.body.is_empty());
        assert!(
            read_backfill_body_frame(&mut reader)
                .await
                .expect("clean end of stream")
                .is_none()
        );

        // Truncated header: some bytes, then EOF.
        let mut truncated = &stream[..BACKFILL_BODY_FRAME_HEADER_BYTES / 2];
        assert!(read_backfill_body_frame(&mut truncated).await.is_err());

        // A frame declaring a body beyond the shared ceiling is rejected by
        // the decoder — the receiver enforces the same constant the sender
        // spools under.
        let oversized = encode_backfill_body_frame_header(
            BackfillRecordKind::SegmentArtifact,
            BackfillBodyDisposition::Present,
            1,
            record_id,
            &meta_bytes,
            BACKFILL_BODIES_BATCH_BYTES + 1,
        )
        .expect("encode oversized header");
        let mut reader = oversized.as_slice();
        let error = read_backfill_body_frame(&mut reader)
            .await
            .expect_err("over-ceiling body length must be rejected");
        assert!(error.contains("ceiling"), "unexpected error: {error}");

        // The per-artifact fetch path decodes the same frame under its own
        // larger ceiling.
        let mut reader = oversized.as_slice();
        let prelude = read_backfill_body_frame_prelude(&mut reader, MAX_REPLICATION_BODY_BYTES)
            .await
            .expect("decode oversized prelude")
            .expect("oversized prelude present");
        assert_eq!(prelude.body_len, BACKFILL_BODIES_BATCH_BYTES + 1);
        assert_eq!(
            prelude.meta.as_ref().map(|meta| meta.key.as_str()),
            Some("artifact")
        );

        // Non-present frames must not carry bodies.
        let mut absent_with_body = encode_backfill_body_frame_header(
            BackfillRecordKind::InlineArtifact,
            BackfillBodyDisposition::Absent,
            1,
            record_id,
            &[],
            3,
        )
        .expect("encode malformed header");
        absent_with_body.extend_from_slice(b"abc");
        let mut reader = absent_with_body.as_slice();
        assert!(read_backfill_body_frame(&mut reader).await.is_err());

        // Present frames must carry the manifest meta the apply path needs.
        let missing_meta = encode_backfill_body_frame_header(
            BackfillRecordKind::InlineArtifact,
            BackfillBodyDisposition::Present,
            1,
            record_id,
            &[],
            0,
        )
        .expect("encode meta-less present header");
        let mut reader = missing_meta.as_slice();
        let error = read_backfill_body_frame(&mut reader)
            .await
            .expect_err("a present frame without meta must be rejected");
        assert!(error.contains("manifest meta"), "unexpected error: {error}");
    }

    #[tokio::test]
    async fn internal_status_advertises_gateway_url_for_global_discovery() {
        let context = test_context(|config| {
            config.node_url =
                "https://kura-eu-0.kura-eu-headless.kura.svc.cluster.local:7443".into();
            config.peer_gateway_url = Some("https://peer.tuist-eu-1.kura.tuist.dev:7443".into());
        })
        .await;

        let local_response = internal_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/_internal/status")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");
        let local_body: Value = serde_json::from_str(&response_text(local_response).await)
            .expect("failed to decode local status response");
        assert_eq!(
            local_body["node_url"],
            "https://kura-eu-0.kura-eu-headless.kura.svc.cluster.local:7443"
        );

        let global_response = internal_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/_internal/status?scope=global")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");
        let global_body: Value = serde_json::from_str(&response_text(global_response).await)
            .expect("failed to decode global status response");
        assert_eq!(
            global_body["node_url"],
            "https://peer.tuist-eu-1.kura.tuist.dev:7443"
        );

        // A Local-scope request that arrived via the gateway host (an
        // off-cluster node querying KURA_PEERS) also gets the gateway URL,
        // whether the host is carried as an HTTP/1.1 Host header...
        let via_host_header = internal_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/_internal/status")
                    .header("host", "peer.tuist-eu-1.kura.tuist.dev:7443")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");
        let via_host_body: Value = serde_json::from_str(&response_text(via_host_header).await)
            .expect("failed to decode via-host status response");
        assert_eq!(
            via_host_body["node_url"],
            "https://peer.tuist-eu-1.kura.tuist.dev:7443"
        );

        // ...or as the HTTP/2 :authority on the request URI (no Host header).
        let via_authority = internal_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("https://peer.tuist-eu-1.kura.tuist.dev:7443/_internal/status")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");
        let via_authority_body: Value = serde_json::from_str(&response_text(via_authority).await)
            .expect("failed to decode via-authority status response");
        assert_eq!(
            via_authority_body["node_url"],
            "https://peer.tuist-eu-1.kura.tuist.dev:7443"
        );
    }

    #[tokio::test]
    async fn keyvalue_round_trip_works_through_router() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());

        let put_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri("/api/cache/keyvalue?tenant_id=acme&namespace_id=ios")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"cas_id":"cas-1","entries":[{"value":"hello"},{"value":"world"}]}"#,
                    ))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

        let get_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/keyvalue/cas-1?tenant_id=acme&namespace_id=ios")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(get_response.status(), StatusCode::OK);

        let body: Value = serde_json::from_str(&response_text(get_response).await)
            .expect("failed to decode keyvalue response");
        assert!(
            body.get("cas_id").is_none(),
            "stored payload must not include cas_id"
        );
        assert_eq!(body["entries"][0]["value"], "hello");
        assert_eq!(body["entries"][1]["value"], "world");
    }

    #[tokio::test]
    async fn keyvalue_response_holds_materialization_memory_until_transport_drops() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());

        let put_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri("/api/cache/keyvalue?tenant_id=acme&namespace_id=ios")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"cas_id":"cas-1","entries":[{"value":"hello"}]}"#,
                    ))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/keyvalue/cas-1?tenant_id=acme&namespace_id=ios")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(response.status(), StatusCode::OK);
        assert!(context.state.memory.transient_reserved_bytes() > 0);

        drop(response);
        assert_eq!(context.state.memory.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn keyvalue_misses_return_json_not_found_errors() {
        let context = test_context(|_| {}).await;

        let response = router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/api/cache/keyvalue/missing-cas?tenant_id=acme&namespace_id=ios")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_json_error_response(response, StatusCode::NOT_FOUND, "Key-value entry not found")
            .await;
    }

    #[tokio::test]
    async fn keyvalue_routes_emit_usage_events() {
        let context = test_context(|config| {
            config.usage = Some(test_usage_config());
        })
        .await;
        let app = router(context.state.clone());

        let put_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri("/api/cache/keyvalue?tenant_id=acme&namespace_id=ios")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"cas_id":"cas-1","entries":[{"value":"x"}]}"#,
                    ))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

        let get_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/keyvalue/cas-1?tenant_id=acme&namespace_id=ios")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(get_response.status(), StatusCode::OK);
        let body = response_text(get_response).await;
        assert_eq!(body, r#"{"entries":[{"value":"x"}]}"#);

        let rollups = context
            .state
            .usage
            .as_ref()
            .expect("usage should be enabled")
            .current_rollups_for_tests();

        assert!(rollups.iter().any(|rollup| {
            rollup.tenant_id == "acme"
                && rollup.namespace_id == "ios"
                && rollup.direction == "ingress"
                && rollup.operation == "upload"
                && rollup.artifact_kind == "xcode"
                && rollup.bytes == 27
                && rollup.request_count == 1
        }));
        assert!(rollups.iter().any(|rollup| {
            rollup.tenant_id == "acme"
                && rollup.namespace_id == "ios"
                && rollup.direction == "egress"
                && rollup.operation == "download"
                && rollup.artifact_kind == "xcode"
                && rollup.bytes == 27
                && rollup.request_count == 1
        }));
    }

    #[tokio::test]
    async fn account_and_project_handle_aliases_work_through_router() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());

        let put_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/cas/artifact-1?account_handle=acme&project_handle=ios")
                    .header("content-type", "application/octet-stream")
                    .body(Body::from("xcode-binary"))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

        let get_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/cas/artifact-1?account_handle=acme&project_handle=ios")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(get_response.status(), StatusCode::OK);
        assert_eq!(response_text(get_response).await, "xcode-binary");
    }

    #[tokio::test]
    async fn response_stream_reservation_follows_bytes_into_the_transport() {
        let context = test_context(|_| {}).await;
        let requested_bytes = HTTP_RESPONSE_STREAM_RESERVATION_BYTES;
        let permit = context
            .state
            .memory
            .acquire_response_stream_memory(
                requested_bytes,
                "http",
                ResponseStreamAdmissionPatience::Degradable,
            )
            .await
            .expect("response stream should be admitted");
        let mut response = Response::new(Body::from("payload"));
        attach_response_stream_permit(&mut response, permit);
        let mut response = guard_response_stream_transport(response).await;

        let frame = response
            .body_mut()
            .frame()
            .await
            .expect("body should yield a frame")
            .expect("frame should be valid");
        let bytes = frame.into_data().expect("frame should contain data");
        drop(response);

        assert_eq!(
            context.state.memory.transient_reserved_bytes(),
            requested_bytes as u64,
            "transport-owned bytes must keep the complete bounded reservation"
        );
        drop(bytes);
        assert_eq!(context.state.memory.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn materialized_response_reservation_follows_encoded_transport_bytes() {
        let context = test_context(|_| {}).await;
        let content_bytes = 64 * 1024;
        let permit = context
            .state
            .memory
            .try_acquire_response_materialization(content_bytes)
            .expect("materialized response should be admitted")
            .expect("non-empty response should return a permit");
        let mut response = Response::new(Body::from(vec![0_u8; content_bytes]));
        response.extensions_mut().insert(
            crate::memory::ResponseTransportGuard::from_materialization_permits(vec![permit]),
        );
        let mut response = guard_response_stream_transport(response).await;

        let frame = response
            .body_mut()
            .frame()
            .await
            .expect("body should yield a frame")
            .expect("frame should be valid");
        let bytes = frame.into_data().expect("frame should contain data");
        drop(response);
        assert_eq!(
            context.state.memory.transient_reserved_bytes(),
            (content_bytes * 2) as u64
        );
        drop(bytes);
        assert_eq!(context.state.memory.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn bytes_chunks_reassembles_multi_chunk_payloads() {
        use futures_util::StreamExt;

        let len = MMAP_RESPONSE_CHUNK_BYTES * 2 + 7;
        let payload = Bytes::from(
            (0..len)
                .map(|index| (index % 251) as u8)
                .collect::<Vec<u8>>(),
        );

        let mut stream = Box::pin(bytes_chunks(payload.clone()));
        let mut chunks = Vec::new();
        while let Some(chunk) = stream.next().await {
            chunks.push(chunk.expect("chunk should be produced"));
        }

        assert_eq!(chunks.len(), 3);
        assert_eq!(chunks[0].len(), MMAP_RESPONSE_CHUNK_BYTES);
        assert_eq!(chunks[1].len(), MMAP_RESPONSE_CHUNK_BYTES);
        assert_eq!(chunks[2].len(), 7);
        assert_eq!(chunks.concat(), payload.to_vec());
    }

    #[tokio::test]
    async fn artifact_get_serves_multi_chunk_payloads_via_mmap_and_reader_fallback() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());

        let len = MMAP_RESPONSE_CHUNK_BYTES * 2 + 7;
        let payload: Vec<u8> = (0..len).map(|index| (index % 251) as u8).collect();

        let put_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/cas/multi-chunk?tenant_id=acme&namespace_id=ios")
                    .header("content-type", "application/octet-stream")
                    .body(Body::from(payload.clone()))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

        let get_request = || {
            Request::builder()
                .uri("/api/cache/cas/multi-chunk?tenant_id=acme&namespace_id=ios")
                .body(Body::empty())
                .expect("failed to build get request")
        };

        let mmap_response = app
            .clone()
            .oneshot(get_request())
            .await
            .expect("mmap get request failed");
        assert_eq!(mmap_response.status(), StatusCode::OK);
        let mmap_body = mmap_response
            .into_body()
            .collect()
            .await
            .expect("failed to collect mmap body")
            .to_bytes();
        assert_eq!(mmap_body.as_ref(), payload.as_slice());

        // Force constrained memory pressure so mmap serving is skipped while
        // leaving exactly one bounded streaming reservation available; the
        // reader fallback must serve identical bytes.
        context.state.memory.observe(
            context
                .state
                .memory
                .hard_limit_bytes()
                .saturating_sub(HTTP_RESPONSE_STREAM_RESERVATION_BYTES as u64),
        );

        let reader_response = app
            .oneshot(get_request())
            .await
            .expect("reader get request failed");
        assert_eq!(reader_response.status(), StatusCode::OK);
        let reader_body = reader_response
            .into_body()
            .collect()
            .await
            .expect("failed to collect reader body")
            .to_bytes();
        assert_eq!(reader_body.as_ref(), payload.as_slice());

        let metrics = context.state.metrics.render();
        assert!(metrics.contains("kura_artifact_egress_completions_total"));
        assert!(metrics.contains("producer=\"xcode\""));
        assert!(metrics.contains("result=\"ok\""));
        assert!(metrics.contains(&format!("{}", payload.len() * 2)));
    }

    #[tokio::test]
    async fn a_public_read_sheds_when_no_bounded_stream_reservation_remains() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());
        let payload: Vec<u8> = (0..(512 * 1024 + 13))
            .map(|index| (index % 251) as u8)
            .collect();

        let put_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/cas/degraded-read?tenant_id=acme&namespace_id=ios")
                    .header("content-type", "application/octet-stream")
                    .body(Body::from(payload.clone()))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

        // Leave no transient headroom at all, so both the weighted pool and the
        // ledger refuse the full three-buffer reservation.
        context
            .state
            .memory
            .observe(context.state.memory.hard_limit_bytes());

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/cas/degraded-read?tenant_id=acme&namespace_id=ios")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");

        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
        assert_retryable_hint(
            &response,
            backpressure::SATURATED_RETRY_AFTER_CEILING_SECONDS,
        );
        let metrics = context.state.metrics.render();
        assert!(metrics.contains("outcome=\"degraded_memory_unavailable\""));
        assert!(
            metrics.lines().any(|line| {
                line.starts_with("kura_http_requests_total")
                    && line.contains("route=\"/api/cache/cas/{id}\"")
                    && line.contains("status=\"429\"")
            }),
            "the shed must be counted as backpressure on the read route"
        );
        assert!(
            !metrics.lines().any(|line| {
                line.starts_with("kura_http_exceptions_total") && line.contains("server_error")
            }),
            "a capacity shed must not be counted as a server error"
        );
    }

    #[tokio::test]
    async fn a_public_read_uses_the_bounded_degraded_pool_when_full_size_admission_is_exhausted() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());
        let payload: Vec<u8> = (0..(512 * 1024 + 13))
            .map(|index| (index % 251) as u8)
            .collect();

        let put_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/cas/degraded-read?tenant_id=acme&namespace_id=ios")
                    .header("content-type", "application/octet-stream")
                    .body(Body::from(payload.clone()))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

        let _fixed = context
            .state
            .memory
            .acquire_response_stream_memory(
                context
                    .state
                    .memory
                    .foreground_response_streaming_pool_bytes(),
                "test",
                ResponseStreamAdmissionPatience::Blocking,
            )
            .await
            .expect("the full-size response pool should start available");
        let _elastic = context
            .state
            .memory
            .acquire_response_stream_memory(
                context
                    .state
                    .memory
                    .elastic_foreground_response_streaming_pool_bytes(),
                "test",
                ResponseStreamAdmissionPatience::Blocking,
            )
            .await
            .expect("the elastic response pool should start available");

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/cas/degraded-read?tenant_id=acme&namespace_id=ios")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");

        assert_eq!(response.status(), StatusCode::OK);
        let body = response
            .into_body()
            .collect()
            .await
            .expect("failed to collect degraded body")
            .to_bytes();
        assert_eq!(body.as_ref(), payload.as_slice());
        assert!(
            context
                .state
                .metrics
                .render()
                .contains("outcome=\"degraded\"")
        );
    }

    #[tokio::test]
    async fn bounded_staging_preserves_every_streamed_request_byte() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());
        let payload = Bytes::from(vec![0xA5; 17 * 1024 * 1024]);
        let chunks = payload
            .chunks(256 * 1024)
            .map(|chunk| Ok::<_, Infallible>(Bytes::copy_from_slice(chunk)))
            .collect::<Vec<_>>();

        let put_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/cas/bounded-stream?tenant_id=acme&namespace_id=ios")
                    .header("content-type", "application/octet-stream")
                    .header(axum::http::header::CONTENT_LENGTH, payload.len())
                    .body(Body::from_stream(tokio_stream::iter(chunks)))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

        let get_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/cas/bounded-stream?tenant_id=acme&namespace_id=ios")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(get_response.status(), StatusCode::OK);
        let stored = get_response
            .into_body()
            .collect()
            .await
            .expect("failed to collect stored artifact")
            .to_bytes();
        assert_eq!(stored, payload);
    }

    #[tokio::test]
    async fn artifact_get_misses_return_json_not_found_errors() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());

        let cas_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/cache/cas/missing-cas?tenant_id=acme&namespace_id=ios")
                    .body(Body::empty())
                    .expect("failed to build CAS request"),
            )
            .await
            .expect("CAS request failed");
        assert_json_error_response(cas_response, StatusCode::NOT_FOUND, "Artifact not found").await;

        let module_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/cache/module/missing-module?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build module request"),
            )
            .await
            .expect("module request failed");
        assert_json_error_response(module_response, StatusCode::NOT_FOUND, "Artifact not found")
            .await;

        let gradle_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/gradle/missing-gradle?tenant_id=acme&namespace_id=android")
                    .body(Body::empty())
                    .expect("failed to build Gradle request"),
            )
            .await
            .expect("Gradle request failed");
        assert_json_error_response(gradle_response, StatusCode::NOT_FOUND, "Artifact not found")
            .await;
    }

    #[tokio::test]
    async fn tenant_only_xcode_routes_work_through_router() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());

        let put_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/cas/account-artifact?account_handle=acme")
                    .header("content-type", "application/octet-stream")
                    .body(Body::from("account-binary"))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

        let get_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/cas/account-artifact?account_handle=acme")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");

        assert_eq!(get_response.status(), StatusCode::OK);
        assert_eq!(response_text(get_response).await, "account-binary");
    }

    #[tokio::test]
    async fn xcode_routes_emit_project_scoped_analytics_events() {
        let captured = Arc::new(Mutex::new(Vec::<CapturedRequest>::new()));
        let (base_url, _handle) = spawn_capture_server(captured.clone()).await;
        let context = test_context(|config| {
            config.analytics = Some(AnalyticsConfig {
                server_url: base_url,
                signing_key: "secret-key".into(),
                batch_size: 1,
                batch_timeout_ms: 5_000,
                queue_capacity: 8,
                request_timeout_ms: 5_000,
                circuit_breaker_failure_threshold: 2,
                circuit_breaker_open_ms: 5_000,
            });
        })
        .await;
        let app = router(context.state.clone());

        let put_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios")
                    .header("content-type", "application/octet-stream")
                    .body(Body::from("xcode-binary"))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

        let get_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(get_response.status(), StatusCode::OK);
        assert_eq!(response_text(get_response).await, "xcode-binary");

        timeout(Duration::from_secs(2), async {
            loop {
                if captured.lock().expect("captured requests lock").len() >= 2 {
                    break;
                }
                sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .expect("analytics requests should be delivered");

        let requests = captured.lock().expect("captured requests lock");
        let payloads = requests
            .iter()
            .map(|request| {
                serde_json::from_slice::<Value>(&request.body)
                    .expect("analytics request body should decode")
            })
            .collect::<Vec<_>>();

        assert!(payloads.iter().any(|payload| {
            payload
                == &serde_json::json!({
                    "events": [{
                        "account_handle": "acme",
                        "project_handle": "ios",
                        "action": "upload",
                        "size": 12,
                        "cas_id": "artifact-1"
                    }]
                })
        }));
        assert!(payloads.iter().any(|payload| {
            payload
                == &serde_json::json!({
                    "events": [{
                        "account_handle": "acme",
                        "project_handle": "ios",
                        "action": "download",
                        "size": 12,
                        "cas_id": "artifact-1"
                    }]
                })
        }));
    }

    #[tokio::test]
    async fn tenant_only_xcode_routes_skip_project_scoped_analytics_events() {
        let captured = Arc::new(Mutex::new(Vec::<CapturedRequest>::new()));
        let (base_url, _handle) = spawn_capture_server(captured.clone()).await;
        let context = test_context(|config| {
            config.analytics = Some(AnalyticsConfig {
                server_url: base_url,
                signing_key: "secret-key".into(),
                batch_size: 1,
                batch_timeout_ms: 5_000,
                queue_capacity: 8,
                request_timeout_ms: 5_000,
                circuit_breaker_failure_threshold: 2,
                circuit_breaker_open_ms: 5_000,
            });
        })
        .await;
        let app = router(context.state.clone());

        let put_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/cas/account-artifact?tenant_id=acme")
                    .header("content-type", "application/octet-stream")
                    .body(Body::from("account-binary"))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

        let get_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/cas/account-artifact?tenant_id=acme")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(get_response.status(), StatusCode::OK);
        assert_eq!(response_text(get_response).await, "account-binary");

        sleep(Duration::from_millis(200)).await;
        assert!(captured.lock().expect("captured requests lock").is_empty());
    }

    #[tokio::test]
    async fn tenant_only_xcode_routes_emit_usage_events() {
        let context = test_context(|config| {
            config.usage = Some(test_usage_config());
        })
        .await;
        let app = router(context.state.clone());

        let put_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/cas/account-artifact?tenant_id=acme")
                    .header("content-type", "application/octet-stream")
                    .body(Body::from("account-binary"))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

        let get_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/cas/account-artifact?tenant_id=acme")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(get_response.status(), StatusCode::OK);
        assert_eq!(response_text(get_response).await, "account-binary");

        let rollups = context
            .state
            .usage
            .as_ref()
            .expect("usage should be enabled")
            .current_rollups_for_tests();

        assert!(rollups.iter().any(|rollup| {
            rollup.tenant_id == "acme"
                && rollup.namespace_id.is_empty()
                && rollup.direction == "ingress"
                && rollup.operation == "upload"
                && rollup.artifact_kind == "xcode"
                && rollup.bytes == 14
                && rollup.request_count == 1
        }));
        assert!(rollups.iter().any(|rollup| {
            rollup.tenant_id == "acme"
                && rollup.namespace_id.is_empty()
                && rollup.direction == "egress"
                && rollup.operation == "download"
                && rollup.artifact_kind == "xcode"
                && rollup.bytes == 14
                && rollup.request_count == 1
        }));
    }

    #[tokio::test]
    async fn fixed_namespace_cache_routes_emit_usage_events() {
        let context = test_context(|config| {
            config.tenant_id = "acme".into();
            config.usage = Some(test_usage_config());
        })
        .await;
        let app = router(context.state.clone());

        let nx_put = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri("/v1/cache/nx-key")
                    .body(Body::from("nx-bytes"))
                    .expect("failed to build nx put request"),
            )
            .await
            .expect("nx put request failed");
        assert_eq!(nx_put.status(), StatusCode::OK);

        let nx_get = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/v1/cache/nx-key")
                    .body(Body::empty())
                    .expect("failed to build nx get request"),
            )
            .await
            .expect("nx get request failed");
        assert_eq!(nx_get.status(), StatusCode::OK);
        assert_eq!(response_text(nx_get).await, "nx-bytes");

        let metro_put = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri("/api/metro/cache/metro-key")
                    .body(Body::from("metro-bytes"))
                    .expect("failed to build metro put request"),
            )
            .await
            .expect("metro put request failed");
        assert_eq!(metro_put.status(), StatusCode::OK);

        let metro_get = app
            .oneshot(
                Request::builder()
                    .uri("/api/metro/cache/metro-key")
                    .body(Body::empty())
                    .expect("failed to build metro get request"),
            )
            .await
            .expect("metro get request failed");
        assert_eq!(metro_get.status(), StatusCode::OK);
        assert_eq!(response_text(metro_get).await, "metro-bytes");

        let rollups = context
            .state
            .usage
            .as_ref()
            .expect("usage should be enabled")
            .current_rollups_for_tests();

        assert!(rollups.iter().any(|rollup| {
            rollup.tenant_id == "acme"
                && rollup.namespace_id == "nx"
                && rollup.direction == "ingress"
                && rollup.artifact_kind == "nx"
                && rollup.bytes == 8
        }));
        assert!(rollups.iter().any(|rollup| {
            rollup.tenant_id == "acme"
                && rollup.namespace_id == "nx"
                && rollup.direction == "egress"
                && rollup.artifact_kind == "nx"
                && rollup.bytes == 8
        }));
        assert!(rollups.iter().any(|rollup| {
            rollup.tenant_id == "acme"
                && rollup.namespace_id == "metro"
                && rollup.direction == "ingress"
                && rollup.artifact_kind == "metro"
                && rollup.bytes == 11
        }));
        assert!(rollups.iter().any(|rollup| {
            rollup.tenant_id == "acme"
                && rollup.namespace_id == "metro"
                && rollup.direction == "egress"
                && rollup.artifact_kind == "metro"
                && rollup.bytes == 11
        }));
    }

    #[tokio::test]
    async fn multipart_module_round_trip_works_through_router() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());

        let start = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build start request"),
            )
            .await
            .expect("start request failed");
        let payload: Value = serde_json::from_str(&response_text(start).await)
            .expect("failed to decode start payload");
        let upload_id = payload["upload_id"]
            .as_str()
            .expect("upload id should be present");

        let upload_part = |part_number, body| {
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/cache/module/part?upload_id={upload_id}&part_number={part_number}"
                ))
                .body(Body::from(body))
                .expect("failed to build part request")
        };

        let response = app
            .clone()
            .oneshot(upload_part(1, "part-one-"))
            .await
            .expect("part 1 request failed");
        assert_eq!(response.status(), StatusCode::NO_CONTENT);

        let response = app
            .clone()
            .oneshot(upload_part(2, "part-two"))
            .await
            .expect("part 2 request failed");
        assert_eq!(response.status(), StatusCode::NO_CONTENT);

        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/api/cache/module/complete?upload_id={upload_id}"))
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"parts":[1,2]}"#))
                    .expect("failed to build complete request"),
            )
            .await
            .expect("complete request failed");
        assert_eq!(response.status(), StatusCode::NO_CONTENT);

        let head = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("HEAD")
                    .uri("/api/cache/module/module-1?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build head request"),
            )
            .await
            .expect("head request failed");
        assert_eq!(head.status(), StatusCode::NO_CONTENT);

        let get = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/module/module-1?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(get.status(), StatusCode::OK);
        assert_eq!(
            get.headers()
                .get(axum::http::header::CONTENT_LENGTH)
                .and_then(|value| value.to_str().ok()),
            Some("17")
        );
        assert_eq!(response_text(get).await, "part-one-part-two");
    }

    #[tokio::test]
    async fn the_multipart_upload_cap_sheds_with_backpressure_not_a_server_error() {
        let context = test_context(|config| config.multipart_max_active_uploads = 1).await;
        let app = router(context.state.clone());

        let start = |hash: &str| {
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash={hash}\
                     &name=Module.framework&cache_category=builds"
                ))
                .body(Body::empty())
                .expect("failed to build start request")
        };

        let admitted = app
            .clone()
            .oneshot(start("hash-1"))
            .await
            .expect("first start request failed");
        assert_eq!(admitted.status(), StatusCode::OK);

        let shed = app
            .oneshot(start("hash-2"))
            .await
            .expect("second start request failed");

        assert_eq!(shed.status(), StatusCode::TOO_MANY_REQUESTS);
        assert_retryable_hint(&shed, backpressure::IDLE_RETRY_AFTER_CEILING_SECONDS);

        let metrics = context.state.metrics.render();
        assert!(
            metrics.lines().any(|line| {
                line.starts_with("kura_http_requests_total")
                    && line.contains("route=\"/api/cache/module/start\"")
                    && line.contains("status=\"429\"")
            }),
            "the shed must be counted as backpressure on the upload route: {metrics}"
        );
        assert!(
            !metrics.lines().any(|line| {
                line.starts_with("kura_http_exceptions_total")
                    && line.contains("route=\"/api/cache/module/start\"")
            }),
            "a full upload cap is not a server fault: {metrics}"
        );
    }

    #[tokio::test]
    async fn an_outbox_that_cannot_seat_every_target_sheds_rather_than_faulting() {
        // The public-write middleware only checks that the outbox is not
        // already at its cap. Each store write then atomically reserves one
        // slot *per replication target*, so a write admitted by the pre-check
        // still loses when the remaining room is smaller than the target
        // count. Two targets against a cap of one reproduces that gap
        // deterministically; concurrency reaches the same branch by racing.
        //
        // `public_router`, not `router`: the gap only exists downstream of
        // `reject_overloaded_public_writes`, and `combined_router` does not
        // layer it. Going through the middleware is what makes this a test of
        // the persistence branches rather than of the handlers in isolation --
        // on `router` it would stay green even if the middleware regressed to
        // answering 503.
        let context = test_context(|config| {
            config.outbox_max_depth = 1;
            config.peers = vec![
                "http://127.0.0.1:7101".into(),
                "http://127.0.0.1:7102".into(),
            ];
        })
        .await;
        let app = public_router(context.state.clone());

        assert!(
            context.state.store.outbox_depth() < context.state.config.outbox_max_depth,
            "the pre-check must admit this write, or the test is not exercising the gap"
        );

        let keyvalue = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri("/api/cache/keyvalue?tenant_id=acme&namespace_id=ios")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"cas_id":"cas-outbox","entries":[{"value":"hello"}]}"#,
                    ))
                    .expect("failed to build put request"),
            )
            .await
            .expect("keyvalue put failed");

        assert_eq!(keyvalue.status(), StatusCode::TOO_MANY_REQUESTS);
        assert_retryable_hint(&keyvalue, backpressure::IDLE_RETRY_AFTER_CEILING_SECONDS);

        let blob = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/cas/outbox-blob?tenant_id=acme&namespace_id=ios")
                    .header("content-type", "application/octet-stream")
                    .body(Body::from("payload"))
                    .expect("failed to build post request"),
            )
            .await
            .expect("blob post failed");

        assert_eq!(blob.status(), StatusCode::TOO_MANY_REQUESTS);
        assert_retryable_hint(&blob, backpressure::IDLE_RETRY_AFTER_CEILING_SECONDS);

        let metrics = context.state.metrics.render();
        assert!(
            metrics
                .lines()
                .any(|line| line.starts_with("kura_capacity_sheds_total")
                    && line.contains("kind=\"outbox\"")),
            "the shed must be attributable to the outbox, not to egress pressure: {metrics}"
        );
        assert!(
            !metrics.lines().any(|line| {
                line.starts_with("kura_http_exceptions_total") && line.contains("server_error")
            }),
            "a full outbox is not a server fault: {metrics}"
        );
    }

    #[tokio::test]
    async fn public_writes_shed_with_backpressure_under_critical_memory_pressure() {
        let context = test_context(|_| {}).await;
        context
            .state
            .memory
            .observe(context.state.memory.hard_limit_bytes() + 1);

        let response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(
                        "/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=hash-1\
                         &name=Module.framework&cache_category=builds",
                    )
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
        assert_retryable_hint(&response, backpressure::IDLE_RETRY_AFTER_CEILING_SECONDS);
    }

    #[tokio::test]
    async fn multipart_module_routes_emit_usage_events() {
        let context = test_context(|config| {
            config.usage = Some(test_usage_config());
        })
        .await;
        let app = router(context.state.clone());

        let start = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build start request"),
            )
            .await
            .expect("start request failed");
        let payload: Value = serde_json::from_str(&response_text(start).await)
            .expect("failed to decode start payload");
        let upload_id = payload["upload_id"]
            .as_str()
            .expect("upload id should be present");

        let part_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!(
                        "/api/cache/module/part?upload_id={upload_id}&part_number=1"
                    ))
                    .body(Body::from("module-bytes"))
                    .expect("failed to build part request"),
            )
            .await
            .expect("part request failed");
        assert_eq!(part_response.status(), StatusCode::NO_CONTENT);

        let complete_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/api/cache/module/complete?upload_id={upload_id}"))
                    .header("content-type", "application/json")
                    .body(Body::from(r#"{"parts":[1]}"#))
                    .expect("failed to build complete request"),
            )
            .await
            .expect("complete request failed");
        assert_eq!(complete_response.status(), StatusCode::NO_CONTENT);

        let get_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/module/module-1?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(get_response.status(), StatusCode::OK);
        assert_eq!(response_text(get_response).await, "module-bytes");

        let rollups = context
            .state
            .usage
            .as_ref()
            .expect("usage should be enabled")
            .current_rollups_for_tests();

        assert!(rollups.iter().any(|rollup| {
            rollup.tenant_id == "acme"
                && rollup.namespace_id == "ios"
                && rollup.direction == "ingress"
                && rollup.operation == "upload"
                && rollup.artifact_kind == "module"
                && rollup.bytes == 12
                && rollup.request_count == 1
        }));
        assert!(rollups.iter().any(|rollup| {
            rollup.tenant_id == "acme"
                && rollup.namespace_id == "ios"
                && rollup.direction == "egress"
                && rollup.operation == "download"
                && rollup.artifact_kind == "module"
                && rollup.bytes == 12
                && rollup.request_count == 1
        }));
    }

    #[tokio::test]
    async fn request_context_resolves_namespace_from_multipart_upload() {
        let context = test_context(|_| {}).await;
        let upload_id = context
            .state
            .store
            .start_multipart_upload("acme", "ios", "builds", "hash-1", "Module.framework")
            .expect("failed to start multipart upload");
        let query = parse_query_map(Some(&format!("upload_id={upload_id}&part_number=1")));

        let request_context = request_context_from_http(
            &context.state,
            HttpRequestFacts {
                route: ROUTE_API_CACHE_MODULE_PART,
                method: "POST",
                query: &query,
                authorization: None,
            },
        )
        .await;

        assert_eq!(request_context.tenant_id.as_deref(), Some("acme"));
        assert_eq!(request_context.namespace_id.as_deref(), Some("ios"));
    }

    #[tokio::test]
    async fn request_context_uses_handle_aliases() {
        let context = test_context(|_| {}).await;
        let query = parse_query_map(Some("account_handle=acme&project_handle=ios&hash=hash-1"));
        let authorization = "Bearer credential".to_owned();
        let authorization_allocation = authorization.as_ptr();
        let request_context = request_context_from_http(
            &context.state,
            HttpRequestFacts {
                route: ROUTE_API_CACHE_CAS,
                method: "GET",
                query: &query,
                authorization: Some(authorization),
            },
        )
        .await;

        assert_eq!(request_context.tenant_id.as_deref(), Some("acme"));
        assert_eq!(request_context.namespace_id.as_deref(), Some("ios"));
        assert_eq!(
            request_context.authorization.as_deref(),
            Some("Bearer credential")
        );
        assert_eq!(
            request_context
                .authorization
                .as_ref()
                .map(|value| value.as_ptr()),
            Some(authorization_allocation)
        );
        assert!(request_context.headers.is_empty());
        assert!(request_context.query.is_empty());
    }

    #[tokio::test]
    async fn request_context_omits_namespace_for_tenant_scoped_requests() {
        let context = test_context(|_| {}).await;
        let query = parse_query_map(Some("tenant_id=acme&hash=hash-1"));
        let request_context = request_context_from_http(
            &context.state,
            HttpRequestFacts {
                route: ROUTE_API_CACHE_CAS,
                method: "GET",
                query: &query,
                authorization: None,
            },
        )
        .await;

        assert_eq!(request_context.tenant_id.as_deref(), Some("acme"));
        assert_eq!(request_context.namespace_id, None);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 8)]
    #[ignore = "performance benchmark run by autoresearch.sh"]
    async fn lean_keyvalue_authorization_context_benchmark() {
        const WORKERS: usize = 8;
        const ITERATIONS_PER_WORKER: usize = 10_000;
        const SAMPLES: usize = 6;

        let context = test_context(|_| {}).await;
        let state = context.state;
        let query = Arc::new(parse_query_map(Some(
            "tenant_id=test-tenant&namespace_id=ios",
        )));
        let body = Arc::new(
            serde_json::to_vec(&serde_json::json!({
                "cas_id": "cas-1",
                "entries": [{"value": "x".repeat(4 * 1024)}]
            }))
            .expect("encode benchmark body"),
        );

        let measure = |lean: bool| {
            let state = state.clone();
            let query = query.clone();
            let body = body.clone();
            async move {
                let barrier = Arc::new(tokio::sync::Barrier::new(WORKERS + 1));
                let mut workers = tokio::task::JoinSet::new();
                for _ in 0..WORKERS {
                    let state = state.clone();
                    let query = query.clone();
                    let body = body.clone();
                    let barrier = barrier.clone();
                    workers.spawn(async move {
                        barrier.wait().await;
                        for _ in 0..ITERATIONS_PER_WORKER {
                            if lean {
                                let request = HttpRequestFacts {
                                    route: ROUTE_API_CACHE_KEYVALUE,
                                    method: "PUT",
                                    query: &query,
                                    authorization: Some("Bearer credential".to_owned()),
                                };
                                std::hint::black_box(
                                    request_context_from_http(&state, request).await,
                                );
                            } else {
                                let buffered_body = body.as_ref().clone();
                                let parsed =
                                    serde_json::from_slice::<KeyValuePutRequest>(&buffered_body)
                                        .expect("parse benchmark body");
                                let tenant_id = param_value(&query, "tenant_id").cloned();
                                let namespace_id = param_value(&query, "namespace_id").cloned();
                                std::hint::black_box((
                                    "http".to_owned(),
                                    ROUTE_API_CACHE_KEYVALUE.to_owned(),
                                    "PUT".to_owned(),
                                    "artifact.write".to_owned(),
                                    state.config.tenant_id.clone(),
                                    tenant_id,
                                    namespace_id,
                                    "xcode".to_owned(),
                                    action_cache_key(&parsed.cas_id),
                                    Some("Bearer credential".to_owned()),
                                    buffered_body,
                                ));
                            }
                        }
                    });
                }

                barrier.wait().await;
                let started_at = Instant::now();
                while let Some(result) = workers.join_next().await {
                    result.expect("authorization context worker");
                }
                (WORKERS * ITERATIONS_PER_WORKER) as f64 / started_at.elapsed().as_secs_f64()
            }
        };

        let mut baseline_rates = Vec::with_capacity(SAMPLES - 1);
        let mut candidate_rates = Vec::with_capacity(SAMPLES - 1);
        let mut speedups = Vec::with_capacity(SAMPLES - 1);
        for sample in 0..SAMPLES {
            let (baseline, candidate) = if sample % 2 == 0 {
                (measure(false).await, measure(true).await)
            } else {
                let candidate = measure(true).await;
                (measure(false).await, candidate)
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
            "METRIC keyvalue_auth_context_baseline_per_second={:.3}",
            baseline_rates[median]
        );
        println!(
            "METRIC keyvalue_auth_context_candidate_per_second={:.3}",
            candidate_rates[median]
        );
        println!(
            "METRIC keyvalue_auth_context_speedup_ratio={:.6}",
            speedups[median]
        );
    }

    #[tokio::test]
    async fn missing_required_query_returns_json_error() {
        let context = test_context(|_| {}).await;

        let response = router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/api/cache/keyvalue/cas-1?namespace_id=ios")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            serde_json::from_str::<Value>(&response_text(response).await)
                .expect("failed to decode error response")["message"],
            "Missing tenant_id"
        );
    }

    #[tokio::test]
    async fn responses_preserve_or_generate_a_bounded_request_id() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());

        let preserved = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/up")
                    .header(REQUEST_ID_HEADER, "client-request-123")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");
        assert_eq!(
            preserved.headers().get(REQUEST_ID_HEADER),
            Some(&HeaderValue::from_static("client-request-123"))
        );

        let generated = app
            .oneshot(
                Request::builder()
                    .uri("/up")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");
        let generated = generated
            .headers()
            .get(REQUEST_ID_HEADER)
            .and_then(|value| value.to_str().ok())
            .expect("generated request id");
        assert!(!generated.is_empty());
        assert!(generated.len() <= 128);
    }

    #[tokio::test]
    async fn clean_namespace_removes_existing_artifacts() {
        let context = test_context(|_| {}).await;
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                &blob_key("artifact-1"),
                "application/octet-stream",
                b"xcode-binary",
            )
            .await
            .expect("failed to seed store");

        let app = router(context.state.clone());

        let delete = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("DELETE")
                    .uri("/api/cache/clean?tenant_id=acme&namespace_id=ios")
                    .body(Body::empty())
                    .expect("failed to build delete request"),
            )
            .await
            .expect("delete request failed");
        assert_eq!(delete.status(), StatusCode::NO_CONTENT);

        let get = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(get.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn clean_namespace_removes_existing_tenant_scoped_artifacts() {
        let context = test_context(|_| {}).await;
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "",
                &blob_key("account-artifact"),
                "application/octet-stream",
                b"account-binary",
            )
            .await
            .expect("failed to seed store");

        let app = router(context.state.clone());

        let delete = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("DELETE")
                    .uri("/api/cache/clean?tenant_id=acme")
                    .body(Body::empty())
                    .expect("failed to build delete request"),
            )
            .await
            .expect("delete request failed");
        assert_eq!(delete.status(), StatusCode::NO_CONTENT);

        let get = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/cas/account-artifact?tenant_id=acme")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(get.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn instrumented_artifact_stream_holds_public_inflight_until_body_drops() {
        let context = test_context(|_| {}).await;
        assert_eq!(context.state.runtime.public_http_inflight(), 0);

        let stream = futures_util::stream::pending::<Result<Bytes, std::io::Error>>();
        let instrumented = InstrumentedArtifactStream::new(
            context.state.metrics.clone(),
            ArtifactProducer::Xcode,
            stream,
            Some(context.state.start_http_request(HttpTrafficClass::Public)),
            ArtifactStreamObservation {
                status: StatusCode::OK,
                serving_path: "reader",
                expected_bytes: 1,
                attribution: None,
            },
        );

        assert_eq!(context.state.runtime.public_http_inflight(), 1);
        drop(instrumented);
        assert_eq!(context.state.runtime.public_http_inflight(), 0);
    }

    #[test]
    fn response_stream_admission_failure_spreads_retry_after() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let memory = MemoryController::new(metrics.clone(), 100, 200);
        let values: std::collections::HashSet<u64> = (0..64)
            .map(|_| retry_after_hint(&response_stream_shed(&metrics, &memory)))
            .collect();

        assert!(
            values.len() > 1,
            "a constant retry-after wakes every shed client on the same instant: {values:?}"
        );
        assert!(
            values
                .iter()
                .all(|seconds| (backpressure::MIN_RETRY_AFTER_SECONDS
                    ..=backpressure::SATURATED_RETRY_AFTER_CEILING_SECONDS)
                    .contains(seconds)),
            "{values:?}"
        );
    }

    #[test]
    fn public_response_stream_admission_failure_is_rate_limited() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let memory = MemoryController::new(metrics.clone(), 100, 200);
        let response = response_stream_shed(&metrics, &memory);

        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
        assert!(!response.status().is_server_error());
        assert_retryable_hint(
            &response,
            backpressure::SATURATED_RETRY_AFTER_CEILING_SECONDS,
        );
    }

    #[test]
    fn peer_response_stream_admission_failure_is_retryable() {
        let memory =
            MemoryController::new(Metrics::new("eu-west".into(), "tenant".into()), 100, 200);
        let response = peer_response_stream_unavailable(&memory);

        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_retryable_hint(
            &response,
            backpressure::SATURATED_RETRY_AFTER_CEILING_SECONDS,
        );
    }

    #[derive(Clone, Debug)]
    struct CapturedRequest {
        body: Vec<u8>,
    }

    async fn spawn_capture_server(
        captured: Arc<Mutex<Vec<CapturedRequest>>>,
    ) -> (String, tokio::task::JoinHandle<()>) {
        let router = Router::new()
            .route(
                "/webhooks/cache",
                post({
                    let captured = captured.clone();
                    move |request| capture_request(captured.clone(), request)
                }),
            )
            .route(
                "/webhooks/gradle-cache",
                post({
                    let captured = captured.clone();
                    move |request| capture_request(captured.clone(), request)
                }),
            );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("capture listener should bind");
        let address = listener
            .local_addr()
            .expect("capture listener should have a local address");
        let handle = tokio::spawn(async move {
            axum::serve(listener, router)
                .await
                .expect("capture server should run");
        });

        (format!("http://{address}"), handle)
    }

    /// A response body that hyper stops polling once `Content-Length` is
    /// satisfied never yields the terminal `None`, so the only record comes
    /// from `Drop`. It has still delivered every byte it promised, and calling
    /// that an abort makes `result="aborted"` mean "served by the streaming
    /// path" rather than "the client did not get its artifact".
    #[tokio::test]
    async fn a_body_dropped_after_delivering_every_byte_is_recorded_as_ok() {
        let context = test_context(|_| {}).await;
        let chunks = vec![
            Ok(Bytes::from_static(b"0123")),
            Ok(Bytes::from_static(b"456789")),
        ];
        let mut stream = InstrumentedArtifactStream::new(
            context.state.metrics.clone(),
            ArtifactProducer::Module,
            futures_util::stream::iter(chunks),
            None,
            ArtifactStreamObservation {
                status: StatusCode::OK,
                serving_path: "reader",
                expected_bytes: 10,
                attribution: None,
            },
        );

        // Drain exactly the promised bytes, then drop without polling again.
        assert!(stream.next().await.is_some());
        assert!(stream.next().await.is_some());
        drop(stream);

        let rendered = context.state.metrics.render();
        assert!(
            rendered.contains(r#"producer="module",result="ok""#),
            "a fully delivered body must record ok, got:\n{rendered}"
        );
        assert!(
            !rendered.contains(r#"producer="module",result="aborted""#),
            "a fully delivered body must not record aborted, got:\n{rendered}"
        );
    }

    #[tokio::test]
    async fn a_body_dropped_before_delivering_every_byte_is_recorded_as_aborted() {
        let context = test_context(|_| {}).await;
        let chunks = vec![
            Ok(Bytes::from_static(b"0123")),
            Ok(Bytes::from_static(b"456789")),
        ];
        let mut stream = InstrumentedArtifactStream::new(
            context.state.metrics.clone(),
            ArtifactProducer::Module,
            futures_util::stream::iter(chunks),
            None,
            ArtifactStreamObservation {
                status: StatusCode::OK,
                serving_path: "reader",
                expected_bytes: 10,
                attribution: None,
            },
        );

        // The client goes away after the first chunk.
        assert!(stream.next().await.is_some());
        drop(stream);

        let rendered = context.state.metrics.render();
        assert!(
            rendered.contains(r#"producer="module",result="aborted""#),
            "a short body must record aborted, got:\n{rendered}"
        );
        // Only the bytes that were actually put on the wire count as waste.
        assert!(
            rendered.contains(
                r#"kura_artifact_egress_bytes_total_total{producer="module",result="aborted"} 4"#
            ),
            "aborted egress must report the 4 bytes it yielded, got:\n{rendered}"
        );
    }

    fn download_attribution(context: &crate::test_support::TestContext) -> DownloadAttribution {
        DownloadAttribution {
            state: context.state.clone(),
            producer: ArtifactProducer::Module,
            usage: Some(UsageContext {
                tenant_id: context.state.config.tenant_id.clone(),
                namespace_id: "ios".to_owned(),
            }),
            analytics: None,
            analytics_key: "builds/hash/Module.framework".to_owned(),
        }
    }

    fn metered_download_bytes(context: &crate::test_support::TestContext) -> u64 {
        context
            .state
            .usage
            .as_ref()
            .expect("usage should be enabled")
            .current_rollups_for_tests()
            .iter()
            .filter(|rollup| rollup.operation == "download")
            .map(|rollup| rollup.bytes)
            .sum()
    }

    /// A response's status is set when its stream is built, so metering there
    /// books an artifact the client may never receive. It must be booked from
    /// the body instead.
    #[tokio::test]
    async fn a_body_that_dies_mid_transfer_meters_no_download() {
        let context = test_context(|config| {
            config.usage = Some(test_usage_config());
        })
        .await;
        let chunks = vec![
            Ok(Bytes::from_static(b"0123")),
            Ok(Bytes::from_static(b"456789")),
        ];
        let mut stream = InstrumentedArtifactStream::new(
            context.state.metrics.clone(),
            ArtifactProducer::Module,
            futures_util::stream::iter(chunks),
            None,
            ArtifactStreamObservation {
                status: StatusCode::OK,
                serving_path: "reader",
                expected_bytes: 10,
                attribution: Some(download_attribution(&context)),
            },
        );

        assert!(stream.next().await.is_some());
        drop(stream);

        assert_eq!(
            metered_download_bytes(&context),
            0,
            "an abandoned transfer must not be metered"
        );
    }

    #[tokio::test]
    async fn a_completed_body_meters_exactly_the_bytes_it_delivered() {
        let context = test_context(|config| {
            config.usage = Some(test_usage_config());
        })
        .await;
        // The tail a resumed download asks for, not the whole artifact.
        let chunks = vec![Ok(Bytes::from_static(b"6789"))];
        let mut stream = InstrumentedArtifactStream::new(
            context.state.metrics.clone(),
            ArtifactProducer::Module,
            futures_util::stream::iter(chunks),
            None,
            ArtifactStreamObservation {
                status: StatusCode::OK,
                serving_path: "reader",
                expected_bytes: 4,
                attribution: Some(download_attribution(&context)),
            },
        );

        assert!(stream.next().await.is_some());
        drop(stream);

        assert_eq!(metered_download_bytes(&context), 4);
    }

    /// Puts an artifact and reads it back with `Range`. At this size the
    /// response comes back through the mapped-file path; `serve_file_reader`'s
    /// own ranged open is covered by the store's segment-offset test.
    async fn seed_ranged_artifact(app: &Router, body: &[u8]) {
        let put = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri("/v1/cache/ranged-key")
                    .body(Body::from(body.to_vec()))
                    .expect("failed to build put request"),
            )
            .await
            .expect("put request failed");
        assert_eq!(put.status(), StatusCode::OK);
    }

    async fn ranged_get(app: &Router, range: &str) -> Response {
        app.clone()
            .oneshot(
                Request::builder()
                    .uri("/v1/cache/ranged-key")
                    .header("range", range)
                    .body(Body::empty())
                    .expect("failed to build ranged get request"),
            )
            .await
            .expect("ranged get request failed")
    }

    #[tokio::test]
    async fn a_ranged_artifact_read_returns_only_the_requested_tail() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());
        let body: Vec<u8> = (0..4096_u32).map(|index| index as u8).collect();
        seed_ranged_artifact(&app, &body).await;

        let response = ranged_get(&app, "bytes=4000-").await;
        assert_eq!(response.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(
            response
                .headers()
                .get("content-range")
                .and_then(|value| value.to_str().ok()),
            Some("bytes 4000-4095/4096")
        );
        assert_eq!(
            response
                .headers()
                .get("content-length")
                .and_then(|value| value.to_str().ok()),
            Some("96")
        );
        assert_eq!(
            response
                .headers()
                .get("accept-ranges")
                .and_then(|value| value.to_str().ok()),
            Some("bytes")
        );
        assert_eq!(response_bytes(response).await, body[4000..].to_vec());
    }

    #[tokio::test]
    async fn a_closed_range_returns_exactly_that_window() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());
        let body: Vec<u8> = (0..4096_u32).map(|index| index as u8).collect();
        seed_ranged_artifact(&app, &body).await;

        let response = ranged_get(&app, "bytes=10-19").await;
        assert_eq!(response.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(
            response
                .headers()
                .get("content-range")
                .and_then(|value| value.to_str().ok()),
            Some("bytes 10-19/4096")
        );
        assert_eq!(response_bytes(response).await, body[10..20].to_vec());
    }

    #[tokio::test]
    async fn an_unranged_artifact_read_still_advertises_resume() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());
        let body: Vec<u8> = (0..4096_u32).map(|index| index as u8).collect();
        seed_ranged_artifact(&app, &body).await;

        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/v1/cache/ranged-key")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(
            response
                .headers()
                .get("accept-ranges")
                .and_then(|value| value.to_str().ok()),
            Some("bytes")
        );
        // A full response must not claim to be partial.
        assert!(response.headers().get("content-range").is_none());
        assert_eq!(response_bytes(response).await, body);
    }

    #[tokio::test]
    async fn a_range_past_the_end_is_refused_so_a_resume_cannot_corrupt_the_file() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());
        let body: Vec<u8> = (0..4096_u32).map(|index| index as u8).collect();
        seed_ranged_artifact(&app, &body).await;

        let response = ranged_get(&app, "bytes=99999-").await;
        assert_eq!(response.status(), StatusCode::RANGE_NOT_SATISFIABLE);
        assert_eq!(
            response
                .headers()
                .get("content-range")
                .and_then(|value| value.to_str().ok()),
            Some("bytes */4096")
        );
    }

    #[tokio::test]
    async fn resuming_from_a_partial_download_reassembles_the_whole_artifact() {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());
        let body: Vec<u8> = (0..4096_u32).map(|index| index as u8).collect();
        seed_ranged_artifact(&app, &body).await;

        // What a client that lost its connection at 1500 bytes does next.
        let head = ranged_get(&app, "bytes=0-1499").await;
        assert_eq!(head.status(), StatusCode::PARTIAL_CONTENT);
        let mut assembled = response_bytes(head).await;
        assert_eq!(assembled.len(), 1500);

        let tail = ranged_get(&app, &format!("bytes={}-", assembled.len())).await;
        assert_eq!(tail.status(), StatusCode::PARTIAL_CONTENT);
        assembled.extend(response_bytes(tail).await);

        assert_eq!(assembled, body);
    }

    async fn capture_request(
        captured: Arc<Mutex<Vec<CapturedRequest>>>,
        request: Request,
    ) -> impl IntoResponse {
        let (_parts, body) = request.into_parts();
        let body = body
            .collect()
            .await
            .expect("request body should collect")
            .to_bytes();
        captured
            .lock()
            .expect("captured requests lock")
            .push(CapturedRequest {
                body: body.to_vec(),
            });
        StatusCode::ACCEPTED
    }

    #[test]
    fn replicate_batch_frames_round_trip() {
        let first = ReplicateBatchItemMeta {
            producer: "xcode".to_owned(),
            namespace_id: "ios".to_owned(),
            key: "entry-1".to_owned(),
            content_type: "application/octet-stream".to_owned(),
            version_ms: 200,
            branch: Some("main".to_owned()),
            trunk: None,
        };
        let second = ReplicateBatchItemMeta {
            key: "entry-2".to_owned(),
            version_ms: 300,
            branch: None,
            ..first.clone()
        };

        let mut body = Vec::new();
        for (meta, payload) in [(&first, b"one".as_slice()), (&second, b"".as_slice())] {
            let meta_bytes = serde_json::to_vec(meta).expect("meta should encode");
            body.extend_from_slice(
                &encode_replicate_batch_frame(&meta_bytes, payload).expect("frame should encode"),
            );
        }

        let decoded = decode_replicate_batch_frames(&body).expect("frames should decode");
        assert_eq!(decoded.len(), 2);
        assert_eq!(decoded[0].0, first);
        assert_eq!(decoded[0].1, b"one".to_vec());
        // An empty body is a legitimate frame, not a terminator.
        assert_eq!(decoded[1].0, second);
        assert!(decoded[1].1.is_empty());
    }

    #[test]
    fn a_truncated_replicate_batch_is_rejected_whole() {
        // Applying a prefix would silently drop the tail while the sender
        // clears every message it sent, so a short read must fail the request.
        let meta = ReplicateBatchItemMeta {
            producer: "xcode".to_owned(),
            namespace_id: "ios".to_owned(),
            key: "entry".to_owned(),
            content_type: "application/octet-stream".to_owned(),
            version_ms: 1,
            branch: None,
            trunk: None,
        };
        let meta_bytes = serde_json::to_vec(&meta).expect("meta should encode");
        let frame =
            encode_replicate_batch_frame(&meta_bytes, b"payload").expect("frame should encode");

        let error = decode_replicate_batch_frames(&frame[..frame.len() - 2])
            .expect_err("a truncated payload must be rejected");
        assert!(
            error.contains("truncated"),
            "expected a truncation error, got: {error}"
        );

        let error = decode_replicate_batch_frames(&frame[..4])
            .expect_err("a truncated header must be rejected");
        assert!(
            error.contains("truncated"),
            "expected a truncation error, got: {error}"
        );
    }
}
