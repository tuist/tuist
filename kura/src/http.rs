use std::{
    collections::{BTreeMap, HashMap},
    net::IpAddr,
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
    time::Instant,
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
use serde::Deserialize;
use tokio_util::io::ReaderStream;
use tracing::{Instrument, field};

use crate::{
    artifact::{manifest::ArtifactManifest, producer::ArtifactProducer},
    bandwidth::BandwidthLimiter,
    constants::{
        MAX_GRADLE_BYTES, MAX_MODULE_PART_BYTES, MAX_MODULE_TOTAL_BYTES,
        MAX_REPLICATION_BODY_BYTES, MAX_XCODE_BYTES,
    },
    extension::{AccessDecision, ExtensionContext},
    io::is_fd_pool_exhausted_error,
    memory::MemoryPressure,
    metrics::Metrics,
    multipart::error::MultipartError,
    replication::replication_targets,
    runtime::{HttpTrafficClass, InflightGuard},
    state::SharedState,
    store::is_disk_full_error,
    telemetry::{attach_parent_context, record_trace_context},
    utils::{BodyReadError, action_cache_key, blob_key, module_key, read_request_to_temp},
};

const MMAP_RESPONSE_CHUNK_BYTES: usize = 1024 * 1024;
const READER_RESPONSE_CHUNK_BYTES: usize = 512 * 1024;
const ROUTE_UP: &str = "/up";
const ROUTE_READY: &str = "/ready";
const ROUTE_ROLLOUT_STATUS: &str = "/status/rollout";
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
const ROUTE_INTERNAL_BOOTSTRAP_MANIFESTS: &str = "/_internal/bootstrap/manifests";
const ROUTE_INTERNAL_BOOTSTRAP_NAMESPACE_TOMBSTONES: &str =
    "/_internal/bootstrap/namespace_tombstones";
const ROUTE_INTERNAL_BOOTSTRAP_ARTIFACT: &str = "/_internal/bootstrap/artifacts/{artifact_id}";
const ROUTE_INTERNAL_REPLICATE_ARTIFACT: &str = "/_internal/replicate/artifact";
const ROUTE_INTERNAL_REPLICATE_NAMESPACE: &str = "/_internal/replicate/namespace";
const UNMATCHED_ROUTE: &str = "/_unmatched";

const EXACT_ROUTE_TEMPLATES: [&str; 14] = [
    ROUTE_UP,
    ROUTE_READY,
    ROUTE_ROLLOUT_STATUS,
    ROUTE_METRICS,
    ROUTE_API_CACHE_KEYVALUE,
    ROUTE_API_CACHE_MODULE_START,
    ROUTE_API_CACHE_MODULE_PART,
    ROUTE_API_CACHE_MODULE_COMPLETE,
    ROUTE_API_CACHE_CLEAN,
    ROUTE_INTERNAL_STATUS,
    ROUTE_INTERNAL_BOOTSTRAP_MANIFESTS,
    ROUTE_INTERNAL_BOOTSTRAP_NAMESPACE_TOMBSTONES,
    ROUTE_INTERNAL_REPLICATE_ARTIFACT,
    ROUTE_INTERNAL_REPLICATE_NAMESPACE,
];

const DYNAMIC_ROUTE_TEMPLATES: [&str; 7] = [
    ROUTE_V1_CACHE,
    ROUTE_API_METRO_CACHE,
    ROUTE_API_CACHE_KEYVALUE_ID,
    ROUTE_API_CACHE_CAS,
    ROUTE_API_CACHE_MODULE,
    ROUTE_API_CACHE_GRADLE,
    ROUTE_INTERNAL_BOOTSTRAP_ARTIFACT,
];

pub fn public_router(state: SharedState) -> Router {
    public_routes()
        .layer(middleware::from_fn_with_state(
            state.clone(),
            apply_extensions,
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
        .with_state(state)
}

pub fn internal_router(state: SharedState) -> Router {
    internal_routes()
        .layer(middleware::from_fn_with_state(
            state.clone(),
            track_http_metrics,
        ))
        .with_state(state)
}

#[cfg(test)]
pub fn combined_router(state: SharedState) -> Router {
    public_routes()
        .merge(internal_routes())
        .layer(middleware::from_fn_with_state(
            state.clone(),
            apply_extensions,
        ))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            track_http_metrics,
        ))
        .with_state(state)
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
            ROUTE_INTERNAL_BOOTSTRAP_MANIFESTS,
            get(internal_bootstrap_manifests),
        )
        .route(
            ROUTE_INTERNAL_BOOTSTRAP_NAMESPACE_TOMBSTONES,
            get(internal_bootstrap_namespace_tombstones),
        )
        .route(
            ROUTE_INTERNAL_BOOTSTRAP_ARTIFACT,
            get(internal_bootstrap_artifact),
        )
        .route(
            ROUTE_INTERNAL_REPLICATE_ARTIFACT,
            put(internal_replicate_artifact),
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
}

#[derive(Debug, PartialEq, Eq)]
struct PageQuery {
    after: Option<String>,
    limit: usize,
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

impl PageQuery {
    fn from_params(params: &HashMap<String, String>) -> Result<Self, String> {
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
            return Err("Invalid limit: must be greater than 0".to_string());
        }

        Ok(Self {
            after: params
                .get("after")
                .cloned()
                .filter(|value| !value.is_empty()),
            limit,
        })
    }
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
    req: Request,
    next: Next,
) -> Response {
    let start = std::time::Instant::now();
    let route = request_route(&req);
    let traffic_class = if is_public_load_route(&route) {
        HttpTrafficClass::Public
    } else {
        HttpTrafficClass::Background
    };
    let _request_guard = state.start_http_request(traffic_class);
    let method = req.method().to_string();
    let uri_path = req.uri().path().to_owned();
    let client_location = state
        .geoip
        .as_ref()
        .and_then(|geoip| client_ip_from_headers(req.headers()).and_then(|ip| geoip.locate(ip)));
    let client_country = client_location
        .as_ref()
        .and_then(|location| location.country.clone());
    let client_subdivision = client_location
        .as_ref()
        .and_then(|location| location.subdivision.clone());

    let request_span = tracing::info_span!(
        "http.request",
        otel.name = %format!("{method} {route}"),
        otel.kind = "server",
        http.request.method = %method,
        http.route = %route,
        url.path = %uri_path,
        geo.country.iso_code = field::Empty,
        geo.region.iso_code = field::Empty,
        http.response.status_code = field::Empty,
        otel.status_code = field::Empty,
        trace_id = field::Empty,
        span_id = field::Empty,
    );
    if let Some(country) = client_country.as_deref() {
        request_span.record("geo.country.iso_code", country);
    }
    if let Some(subdivision) = client_subdivision.as_deref() {
        request_span.record("geo.region.iso_code", subdivision);
    }
    attach_parent_context(&request_span, req.headers());
    record_trace_context(&request_span);

    let response = next.run(req).instrument(request_span.clone()).await;
    request_span.record("http.response.status_code", response.status().as_u16());
    if response.status().is_server_error() {
        request_span.record("otel.status_code", "ERROR");
    }

    let elapsed = start.elapsed();
    if traffic_class == HttpTrafficClass::Public {
        state
            .runtime
            .record_public_request_latency(&state.metrics, "http", &route, elapsed);
    }
    state
        .metrics
        .record_http(route, response.status(), client_country, elapsed);

    response
}

fn is_public_load_route(route: &str) -> bool {
    !is_probe_route(route) && !route.starts_with("/_internal/") && route != UNMATCHED_ROUTE
}

fn client_ip_from_headers(headers: &axum::http::HeaderMap) -> Option<IpAddr> {
    if let Some(value) = headers.get("x-forwarded-for")
        && let Ok(text) = value.to_str()
        && let Some(first) = text.split(',').next()
        && let Ok(ip) = first.trim().parse::<IpAddr>()
    {
        return Some(ip);
    }
    if let Some(value) = headers.get("x-real-ip")
        && let Ok(text) = value.to_str()
        && let Ok(ip) = text.trim().parse::<IpAddr>()
    {
        return Some(ip);
    }
    None
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
            return overloaded_response("server is shedding writes due to memory pressure");
        }
        if state.runtime.outbox_depth() >= state.config.outbox_max_depth {
            state.metrics.record_memory_action("write_rejected_outbox");
            return overloaded_response("server is shedding writes while replication catches up");
        }
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

fn overloaded_response(message: &str) -> Response {
    let mut response = error_response(StatusCode::SERVICE_UNAVAILABLE, message);
    response.headers_mut().insert(
        axum::http::header::RETRY_AFTER,
        HeaderValue::from_static("1"),
    );
    response
}

async fn apply_extensions(State(state): State<SharedState>, req: Request, next: Next) -> Response {
    let Some(extension) = state.extension.as_ref() else {
        return next.run(req).await;
    };

    let mut req = req;
    let route = request_route(&req);
    let path = req.uri().path().to_owned();
    if should_skip_extension_route(&route) {
        return next.run(req).await;
    }

    let method = req.method().to_string();
    let mut query = parse_query_map(req.uri().query());
    let request_headers = header_map_to_btree(req.headers());
    let mut request_body = None;

    if route == ROUTE_API_CACHE_KEYVALUE && !query.contains_key("cas_id") {
        let (parts, body) = req.into_parts();
        match to_bytes(body, state.config.max_keyvalue_bytes).await {
            Ok(body_bytes) => {
                if let Some(cas_id) = keyvalue_cas_id_from_body(&body_bytes) {
                    query.insert("cas_id".to_owned(), cas_id);
                }
                request_body = Some(body_bytes.to_vec());
                req = Request::from_parts(parts, Body::from(body_bytes));
            }
            Err(_) => {
                return error_response(
                    StatusCode::PAYLOAD_TOO_LARGE,
                    "Failed to read key-value request body",
                );
            }
        }
    }

    let context = extension_context_from_http(
        &state,
        HttpExtensionRequest {
            route: &route,
            method: &method,
            path: &path,
            query: &query,
            headers: &request_headers,
            body: request_body.as_deref(),
            status_code: None,
        },
    )
    .await;

    let principal = match extension.evaluate_access(&context).await {
        AccessDecision::Allow(principal) => principal,
        AccessDecision::Deny(deny) => {
            return error_response(status_from_u16(deny.status), deny.message);
        }
    };

    let mut response = next.run(req).await;

    let response_context = extension_context_from_http(
        &state,
        HttpExtensionRequest {
            route: &route,
            method: &method,
            path: &path,
            query: &query,
            headers: &request_headers,
            body: request_body.as_deref(),
            status_code: Some(response.status().as_u16()),
        },
    )
    .await;
    let headers = extension
        .response_headers(&response_context, principal.as_ref())
        .await;
    for (name, value) in headers.headers {
        if let (Ok(name), Ok(value)) = (
            axum::http::header::HeaderName::try_from(name),
            HeaderValue::from_str(&value),
        ) {
            response.headers_mut().insert(name, value);
        }
    }

    response
}

fn should_skip_extension_route(route: &str) -> bool {
    is_probe_route(route) || route.starts_with("/_internal/")
}

fn is_probe_route(route: &str) -> bool {
    matches!(
        route,
        ROUTE_UP | ROUTE_READY | ROUTE_ROLLOUT_STATUS | ROUTE_METRICS
    )
}

fn is_http1(version: Version) -> bool {
    matches!(version, Version::HTTP_10 | Version::HTTP_11)
}

async fn extension_context_from_http(
    state: &SharedState,
    request: HttpExtensionRequest<'_>,
) -> ExtensionContext {
    let metadata = http_extension_metadata(
        state,
        request.route,
        request.method,
        request.path,
        request.query,
        request.body,
    )
    .await;
    ExtensionContext {
        transport: "http".into(),
        route: request.route.to_owned(),
        method: request.method.to_owned(),
        operation: metadata.operation,
        server_tenant_id: state.config.tenant_id.clone(),
        tenant_id: metadata.tenant_id,
        namespace_id: metadata.namespace_id,
        producer: metadata.producer,
        artifact_key: metadata.artifact_key,
        artifact_hash: metadata.artifact_hash,
        headers: request.headers.clone(),
        query: request
            .query
            .iter()
            .map(|(key, value)| (key.clone(), value.clone()))
            .collect(),
        status_code: request.status_code,
    }
}

struct HttpExtensionRequest<'a> {
    route: &'a str,
    method: &'a str,
    path: &'a str,
    query: &'a HashMap<String, String>,
    headers: &'a BTreeMap<String, String>,
    body: Option<&'a [u8]>,
    status_code: Option<u16>,
}

struct HttpExtensionMetadata {
    operation: String,
    tenant_id: Option<String>,
    namespace_id: Option<String>,
    producer: Option<String>,
    artifact_key: Option<String>,
    artifact_hash: Option<String>,
}

async fn http_extension_metadata(
    state: &SharedState,
    route: &str,
    method: &str,
    path: &str,
    query: &HashMap<String, String>,
    request_body: Option<&[u8]>,
) -> HttpExtensionMetadata {
    let tenant_id = param_value(query, "tenant_id").cloned();
    let mut namespace_id = param_value(query, "namespace_id").cloned();
    let last_path_segment = path.rsplit('/').next().map(str::to_owned);

    match route {
        ROUTE_API_CACHE_KEYVALUE_ID => HttpExtensionMetadata {
            operation: "artifact.read".into(),
            tenant_id,
            namespace_id,
            producer: Some("xcode".into()),
            artifact_key: last_path_segment.as_deref().map(action_cache_key),
            artifact_hash: None,
        },
        ROUTE_API_CACHE_KEYVALUE => HttpExtensionMetadata {
            operation: "artifact.write".into(),
            tenant_id,
            namespace_id,
            producer: Some("xcode".into()),
            artifact_key: query
                .get("cas_id")
                .cloned()
                .or_else(|| request_body.and_then(keyvalue_cas_id_from_body))
                .as_deref()
                .map(action_cache_key),
            artifact_hash: None,
        },
        ROUTE_API_CACHE_CAS => HttpExtensionMetadata {
            operation: if method.eq_ignore_ascii_case("GET") {
                "artifact.read"
            } else {
                "artifact.write"
            }
            .into(),
            tenant_id,
            namespace_id,
            producer: Some("xcode".into()),
            artifact_key: last_path_segment.as_deref().map(blob_key),
            artifact_hash: last_path_segment.clone(),
        },
        ROUTE_API_CACHE_GRADLE => HttpExtensionMetadata {
            operation: if method.eq_ignore_ascii_case("GET") {
                "artifact.read"
            } else {
                "artifact.write"
            }
            .into(),
            tenant_id,
            namespace_id,
            producer: Some("gradle".into()),
            artifact_key: last_path_segment.clone(),
            artifact_hash: last_path_segment.clone(),
        },
        ROUTE_API_CACHE_MODULE => HttpExtensionMetadata {
            operation: if method.eq_ignore_ascii_case("HEAD") || method.eq_ignore_ascii_case("GET")
            {
                "artifact.read"
            } else {
                "artifact.write"
            }
            .into(),
            tenant_id,
            namespace_id,
            producer: Some("module".into()),
            artifact_key: Some(module_key_from_query(query)),
            artifact_hash: query.get("hash").cloned(),
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
            let artifact_key = multipart_upload
                .as_ref()
                .map(|upload| module_key(&upload.category, &upload.hash, &upload.name))
                .or_else(|| Some(module_key_from_query(query)));
            let artifact_hash = query
                .get("hash")
                .cloned()
                .or_else(|| multipart_upload.map(|u| u.hash));

            HttpExtensionMetadata {
                operation: "artifact.write".into(),
                tenant_id,
                namespace_id,
                producer: Some("module".into()),
                artifact_key,
                artifact_hash,
            }
        }
        ROUTE_API_CACHE_CLEAN => HttpExtensionMetadata {
            operation: "namespace.delete".into(),
            tenant_id,
            namespace_id,
            producer: None,
            artifact_key: None,
            artifact_hash: None,
        },
        ROUTE_V1_CACHE => {
            namespace_id = Some(NX_NAMESPACE_ID.into());
            HttpExtensionMetadata {
                operation: if method.eq_ignore_ascii_case("GET") {
                    "artifact.read"
                } else {
                    "artifact.write"
                }
                .into(),
                tenant_id: Some("default".into()),
                namespace_id,
                producer: Some("nx".into()),
                artifact_key: last_path_segment.clone(),
                artifact_hash: last_path_segment,
            }
        }
        ROUTE_API_METRO_CACHE => {
            namespace_id = Some(METRO_NAMESPACE_ID.into());
            HttpExtensionMetadata {
                operation: if method.eq_ignore_ascii_case("GET") {
                    "artifact.read"
                } else {
                    "artifact.write"
                }
                .into(),
                tenant_id: Some("default".into()),
                namespace_id,
                producer: Some("metro".into()),
                artifact_key: last_path_segment.clone(),
                artifact_hash: last_path_segment,
            }
        }
        _ => HttpExtensionMetadata {
            operation: "request".into(),
            tenant_id,
            namespace_id,
            producer: None,
            artifact_key: None,
            artifact_hash: None,
        },
    }
}

fn keyvalue_cas_id_from_body(body: &[u8]) -> Option<String> {
    serde_json::from_slice::<KeyValuePutRequest>(body)
        .ok()
        .map(|request| request.cas_id)
}

fn module_key_from_query(query: &HashMap<String, String>) -> String {
    let category = query
        .get("cache_category")
        .cloned()
        .unwrap_or_else(|| "builds".into());
    let hash = query.get("hash").cloned().unwrap_or_default();
    let name = query.get("name").cloned().unwrap_or_default();
    module_key(&category, &hash, &name)
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

fn header_map_to_btree(headers: &axum::http::HeaderMap) -> BTreeMap<String, String> {
    headers
        .iter()
        .filter_map(|(name, value)| {
            value
                .to_str()
                .ok()
                .map(|value| (name.as_str().to_ascii_lowercase(), value.to_string()))
        })
        .collect()
}

fn status_from_u16(status: u16) -> StatusCode {
    StatusCode::from_u16(status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR)
}

async fn up(State(state): State<SharedState>) -> impl IntoResponse {
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
            "bootstrapped_peers": readiness.bootstrapped_peers,
            "bootstrap_inflight_peers": readiness.bootstrap_inflight_peers,
            "http_inflight_requests": readiness.http_inflight,
            "grpc_inflight_requests": readiness.grpc_inflight,
            "reasons": readiness.reasons,
        })),
    )
        .into_response()
}

async fn rollout_status(State(state): State<SharedState>) -> impl IntoResponse {
    let status = state.rollout_status_report().await;
    Json(serde_json::json!({
        "generation": status.generation,
        "ready": status.ready,
        "state": status.state.as_str(),
        "ring_members": status.ring_members,
        "initial_discovery_completed": status.initial_discovery_completed,
        "writer_lock_owned": status.writer_lock_owned,
        "bootstrap_known_peers": status.bootstrap_known_peers,
        "bootstrap_completed_peers": status.bootstrap_completed_peers,
        "bootstrap_inflight_peers": status.bootstrap_inflight_peers,
        "http_inflight_requests": status.http_inflight,
        "grpc_inflight_requests": status.grpc_inflight,
        "outbox_messages": status.outbox_messages,
        "memory_pressure_state": status.memory_pressure_state,
        "fd_timeout_count": status.fd_timeout_count,
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
            (
                [(
                    axum::http::header::CONTENT_TYPE,
                    HeaderValue::from_static("application/json"),
                )],
                bytes,
            )
                .into_response()
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

async fn get_nx(AxumPath(hash): AxumPath<String>, State(state): State<SharedState>) -> Response {
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
        Ok(true) => StatusCode::NO_CONTENT.into_response(),
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
    )
    .await
}

/// First CLI version that understands a 204 on module upload start as "already
/// cached, skip the upload". Older clients only know the legacy 200 + null
/// `upload_id`, so they keep getting that. The `x-tuist-cli-version` header is
/// sent only by clients that carry this change; the floor is a conservative
/// lower bound (latest released CLI is 4.200.5).
const MIN_CLI_VERSION_FOR_NO_CONTENT: (u64, u64, u64) = (4, 200, 6);

fn cli_supports_no_content(headers: &HeaderMap) -> bool {
    headers
        .get("x-tuist-cli-version")
        .and_then(|value| value.to_str().ok())
        .and_then(parse_semver)
        .is_some_and(|version| version >= MIN_CLI_VERSION_FOR_NO_CONTENT)
}

fn parse_semver(value: &str) -> Option<(u64, u64, u64)> {
    // Parse a leading `major.minor.patch`, ignoring any pre-release/build suffix.
    let core = value.split(|c| c == '-' || c == '+').next().unwrap_or(value);
    let mut parts = core.split('.');
    let major = parts.next()?.parse().ok()?;
    let minor = parts.next()?.parse().ok()?;
    let patch = parts.next()?.parse().ok()?;
    if parts.next().is_some() {
        return None;
    }
    Some((major, minor, patch))
}

async fn start_module_upload(
    headers: HeaderMap,
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
        // A 204 No Content is the contract for "the artifact is already cached,
        // skip the upload" — not a failure. A distinct status (rather than a 200
        // with a null `upload_id`) lets clients and operators tell a cache hit
        // apart from a genuine failure that returns an empty body, so a write
        // that never lands can't masquerade as success. It is gated on the CLI
        // version: clients that predate the 204 signal keep getting the legacy
        // 200 + null `upload_id` so the change stays backward compatible. The
        // metric records the cache hit either way.
        Ok(true) => {
            state.metrics.record_multipart_start("already_exists");
            if cli_supports_no_content(&headers) {
                StatusCode::NO_CONTENT.into_response()
            } else {
                Json(serde_json::json!({ "upload_id": serde_json::Value::Null })).into_response()
            }
        }
        Ok(false) => match state.store.start_multipart_upload(
            &query.namespace.tenant_id,
            &query.namespace.namespace_id,
            &query.cache_category,
            &query.hash,
            &query.name,
        ) {
            Ok(upload_id) => {
                state.metrics.record_multipart_start("started");
                Json(serde_json::json!({ "upload_id": upload_id })).into_response()
            }
            Err(error) => {
                state.metrics.record_multipart_start("start_failed");
                tracing::warn!(
                    namespace_id = %query.namespace.namespace_id,
                    hash = %query.hash,
                    name = %query.name,
                    "failed to start module cache multipart upload: {error}"
                );
                error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Failed to start upload: {error}"),
                )
            }
        },
        Err(error) => {
            state.metrics.record_multipart_start("exists_check_failed");
            tracing::warn!(
                namespace_id = %query.namespace.namespace_id,
                hash = %query.hash,
                name = %query.name,
                "failed to inspect module cache artifact before upload: {error}"
            );
            error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                format!("Failed to inspect artifact: {error}"),
            )
        }
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

    let temp = match read_request_to_temp(
        request,
        &state.config.tmp_dir.join("parts"),
        MAX_MODULE_PART_BYTES,
        &state.config.tmp_dir,
        state.config.tmp_dir_max_bytes,
        &state.io,
        None,
    )
    .await
    {
        Ok(temp) => temp,
        Err(BodyReadError::TooLarge) => {
            return error_response(StatusCode::PAYLOAD_TOO_LARGE, "Part exceeds 10MB limit");
        }
        Err(BodyReadError::TmpDirFull(error)) => {
            return error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                format!("Temporary storage budget exhausted: {error}"),
            );
        }
        Err(BodyReadError::Io(error)) => {
            return io_error_response(
                format!("Failed to persist multipart upload part: {error}"),
                StatusCode::INTERNAL_SERVER_ERROR,
            );
        }
    };

    match state
        .store
        .add_multipart_part(&query.upload_id, query.part_number, &temp.path, temp.size)
        .await
    {
        Ok(()) => {
            state.metrics.record_multipart_part("ok");
            StatusCode::NO_CONTENT.into_response()
        }
        Err(MultipartError::NotFound) => {
            state.io.remove_file_if_exists(&temp.path).await;
            state.metrics.record_multipart_part("not_found");
            error_response(StatusCode::NOT_FOUND, "Upload not found")
        }
        Err(MultipartError::TotalSizeExceeded) => {
            state.io.remove_file_if_exists(&temp.path).await;
            state.metrics.record_multipart_part("too_large");
            error_response(
                StatusCode::UNPROCESSABLE_ENTITY,
                "Total upload size exceeds 2GB limit",
            )
        }
        Err(MultipartError::Other(error)) => {
            state.io.remove_file_if_exists(&temp.path).await;
            state.metrics.record_multipart_part("error");
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to store multipart upload part: {error}"),
            )
        }
        Err(MultipartError::PartsMismatch) => {
            state.io.remove_file_if_exists(&temp.path).await;
            state.metrics.record_multipart_part("parts_mismatch");
            error_response(StatusCode::BAD_REQUEST, "Parts mismatch")
        }
    }
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

async fn internal_bootstrap_manifests(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
) -> Response {
    let query = match PageQuery::from_params(&params) {
        Ok(query) => query,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    match state
        .store
        .manifests_page(query.after.as_deref(), query.limit)
    {
        Ok(page) => Json(page).into_response(),
        Err(error) => error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to list bootstrap manifests: {error}"),
        ),
    }
}

async fn internal_bootstrap_namespace_tombstones(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
) -> Response {
    let query = match PageQuery::from_params(&params) {
        Ok(query) => query,
        Err(message) => return error_response(StatusCode::BAD_REQUEST, message),
    };

    match state
        .store
        .namespace_tombstones_page(query.after.as_deref(), query.limit)
    {
        Ok(page) => Json(page).into_response(),
        Err(error) => error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to list bootstrap tombstones: {error}"),
        ),
    }
}

async fn internal_bootstrap_artifact(
    AxumPath(artifact_id): AxumPath<String>,
    State(state): State<SharedState>,
) -> Response {
    match state
        .store
        .fetch_artifact_by_id_for_serving(&artifact_id)
        .await
    {
        Ok(Some(manifest)) => {
            serve_file_reader(
                &state,
                StatusCode::OK,
                &manifest,
                state.replication_bandwidth_limiter.clone(),
                false,
            )
            .await
        }
        Ok(None) => StatusCode::NOT_FOUND.into_response(),
        Err(error) => error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to load bootstrap artifact: {error}"),
        ),
    }
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
        let bytes = match to_bytes(request.into_body(), state.config.max_keyvalue_bytes).await {
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

    let temp = match read_request_to_temp(
        request,
        &state.config.tmp_dir.join("uploads"),
        MAX_REPLICATION_BODY_BYTES,
        &state.config.tmp_dir,
        state.config.tmp_dir_max_bytes,
        &state.io,
        state.replication_bandwidth_limiter.clone(),
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
            &temp.path,
            query.version_ms,
        )
        .await;
    state.io.remove_file_if_exists(&temp.path).await;
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

async fn get_artifact(
    state: SharedState,
    producer: ArtifactProducer,
    namespace_id: &str,
    key: &str,
    analytics_key: Option<&str>,
    analytics: Option<ProjectAnalyticsContext<'_>>,
    usage: Option<UsageContext>,
) -> Response {
    match state
        .store
        .fetch_artifact_for_serving(producer, namespace_id, key)
        .await
    {
        Ok(Some(manifest)) => {
            let response = serve_file(&state, StatusCode::OK, &manifest).await;
            if response.status().is_success() {
                state
                    .metrics
                    .record_artifact_read(producer, "ok", manifest.size);
                record_usage_event(&state, producer, "download", usage.as_ref(), manifest.size);
                record_project_scoped_cache_event(
                    &state,
                    producer,
                    "download",
                    analytics,
                    analytics_key.unwrap_or(key),
                    manifest.size,
                );
            } else if response.status() == StatusCode::NOT_FOUND {
                state.metrics.record_artifact_read(producer, "not_found", 0);
            } else {
                state.metrics.record_artifact_read(producer, "error", 0);
            }
            response
        }
        Ok(None) => {
            state.metrics.record_artifact_read(producer, "not_found", 0);
            error_response(StatusCode::NOT_FOUND, "Artifact not found")
        }
        Err(error) => {
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

    let temp = match read_request_to_temp(
        request,
        &state.config.tmp_dir.join("uploads"),
        spec.max_bytes,
        &state.config.tmp_dir,
        state.config.tmp_dir_max_bytes,
        &state.io,
        None,
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
            return error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                format!("Temporary storage budget exhausted: {error}"),
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
            &temp.path,
            &targets,
        )
        .await;
    state.io.remove_file_if_exists(&temp.path).await;
    match result {
        Ok(manifest) => {
            state.notify.notify_one();
            state
                .metrics
                .record_artifact_write(producer, "ok", manifest.size);
            record_usage_event(
                &state,
                producer,
                "upload",
                spec.usage.as_ref(),
                manifest.size,
            );
            record_project_scoped_cache_event(
                &state,
                producer,
                "upload",
                spec.analytics,
                spec.analytics_key.unwrap_or(spec.key),
                manifest.size,
            );
            spec.success_status.into_response()
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
    status: StatusCode,
    manifest: &ArtifactManifest,
) -> Response {
    match state.store.try_mmap_artifact_bytes(manifest).await {
        Ok(Some(bytes)) => {
            let stream = instrument_artifact_stream(state, manifest, bytes_chunks(bytes), true);
            let mut response = Response::new(Body::from_stream(stream));
            *response.status_mut() = status;
            apply_artifact_response_headers(&mut response, manifest);
            response
        }
        Ok(None) => serve_file_reader(state, status, manifest, None, true).await,
        Err(error) => {
            tracing::warn!(
                artifact_id = %manifest.artifact_id,
                %error,
                "mmap artifact serving failed; falling back to streaming reader"
            );
            serve_file_reader(state, status, manifest, None, true).await
        }
    }
}

async fn serve_file_reader(
    state: &SharedState,
    status: StatusCode,
    manifest: &ArtifactManifest,
    bandwidth_limiter: Option<Arc<BandwidthLimiter>>,
    hold_public_inflight: bool,
) -> Response {
    match state.store.open_artifact_reader(manifest).await {
        Ok(reader) => {
            let stream = ReaderStream::with_capacity(reader, READER_RESPONSE_CHUNK_BYTES);
            let stream = throttle_body_stream(stream, bandwidth_limiter);
            let stream = instrument_artifact_stream(state, manifest, stream, hold_public_inflight);
            let mut response = Response::new(Body::from_stream(stream));
            *response.status_mut() = status;
            apply_artifact_response_headers(&mut response, manifest);
            response
        }
        Err(error) => error_response(
            StatusCode::NOT_FOUND,
            format!("Artifact bytes are missing from local storage: {error}"),
        ),
    }
}

fn instrument_artifact_stream<S>(
    state: &SharedState,
    manifest: &ArtifactManifest,
    stream: S,
    hold_public_inflight: bool,
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
    )
}

struct InstrumentedArtifactStream<S> {
    inner: S,
    metrics: Metrics,
    producer: ArtifactProducer,
    _request_guard: Option<InflightGuard>,
    started_at: Instant,
    yielded_bytes: u64,
    recorded: bool,
}

impl<S> InstrumentedArtifactStream<S> {
    fn new(
        metrics: Metrics,
        producer: ArtifactProducer,
        stream: S,
        request_guard: Option<InflightGuard>,
    ) -> Self {
        Self {
            inner: stream,
            metrics,
            producer,
            _request_guard: request_guard,
            started_at: Instant::now(),
            yielded_bytes: 0,
            recorded: false,
        }
    }

    fn record_once(&mut self, result: &str) {
        if self.recorded {
            return;
        }

        self.recorded = true;
        self.metrics.record_artifact_egress(
            self.producer,
            result,
            self.yielded_bytes,
            self.started_at.elapsed(),
        );
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
                this.yielded_bytes = this.yielded_bytes.saturating_add(bytes.len() as u64);
                Poll::Ready(Some(Ok(bytes)))
            }
            Poll::Ready(Some(Err(error))) => {
                this.record_once("error");
                Poll::Ready(Some(Err(error)))
            }
            Poll::Ready(None) => {
                this.record_once("ok");
                Poll::Ready(None)
            }
            Poll::Pending => Poll::Pending,
        }
    }
}

impl<S> Drop for InstrumentedArtifactStream<S> {
    fn drop(&mut self) {
        self.record_once("aborted");
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

fn apply_artifact_response_headers(response: &mut Response, manifest: &ArtifactManifest) {
    response.headers_mut().insert(
        axum::http::header::CONTENT_TYPE,
        HeaderValue::from_str(&manifest.content_type)
            .unwrap_or_else(|_| HeaderValue::from_static("application/octet-stream")),
    );
    response.headers_mut().insert(
        axum::http::header::CONTENT_LENGTH,
        HeaderValue::from_str(&manifest.size.to_string())
            .unwrap_or_else(|_| HeaderValue::from_static("0")),
    );
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
    use std::sync::{Arc, Mutex};

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
        utils::blob_key,
    };

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
    async fn up_includes_current_node_and_known_members() {
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
                    .uri("/up")
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
    async fn up_reports_unique_regions_separately_from_node_members() {
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
                    .uri("/up")
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

    #[test]
    fn route_template_for_path_stabilizes_cache_paths() {
        assert_eq!(route_template_for_path(ROUTE_UP), ROUTE_UP);
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
            route_template_for_path("/_internal/bootstrap/artifacts/artifact-one"),
            ROUTE_INTERNAL_BOOTSTRAP_ARTIFACT
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
    async fn ready_stays_unavailable_until_bootstrap_gate_completes() {
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
        assert!(context.state.note_bootstrap_started(&peer).await);

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
        assert_eq!(body["state"], "joining");
        assert_eq!(body["ready"], false);
        assert!(
            body["reasons"]
                .to_string()
                .contains("bootstrap in progress")
        );

        context.state.note_bootstrap_succeeded(&peer).await;
        context.state.maybe_mark_serving().await;

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
        assert_eq!(body["state"], "joining");
        assert_eq!(body["ready"], false);
        assert!(body["reasons"].to_string().contains("discovery settling"));

        context.state.expire_readiness_settle_window().await;
        context.state.maybe_mark_serving().await;

        let response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/ready")
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("ready route should respond");
        assert_eq!(response.status(), StatusCode::OK);
        let body: Value = serde_json::from_str(&response_text(response).await)
            .expect("ready response should be json");
        assert_eq!(body["state"], "serving");
        assert_eq!(body["ready"], true);
    }

    #[tokio::test]
    async fn up_and_ready_share_the_same_membership_generation() {
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
        context.state.note_bootstrap_succeeded(&peer).await;
        context.state.expire_readiness_settle_window().await;
        context.state.maybe_mark_serving().await;

        let up_response = public_router(context.state.clone())
            .oneshot(
                Request::builder()
                    .uri("/up")
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
        context.state.note_bootstrap_succeeded(&peer).await;
        context.state.expire_readiness_settle_window().await;
        context.state.maybe_mark_serving().await;
        context.state.metrics.update_outbox_messages(7);
        context
            .state
            .metrics
            .record_file_descriptor_wait("timeout", Duration::from_millis(5));
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
        assert_eq!(body["bootstrap_known_peers"], 1);
        assert_eq!(body["bootstrap_completed_peers"], 1);
        assert_eq!(body["bootstrap_inflight_peers"], 0);
        assert_eq!(body["outbox_messages"], 7);
        assert_eq!(body["memory_pressure_state"], 0);
        assert_eq!(body["fd_timeout_count"], 1);
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

        // Force memory pressure so mmap serving is skipped and the streaming
        // reader path serves the same artifact; the bytes must be identical.
        context.state.memory.observe(u64::MAX);

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
        assert_eq!(start.status(), StatusCode::OK);
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
            .clone()
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

        // Starting an upload for an already-cached artifact returns 204 No Content
        // to a CLI new enough to understand it (advertised via x-tuist-cli-version),
        // so a cache hit can't be confused with a failure that returns an empty body.
        let restart = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .header("x-tuist-cli-version", "4.200.6")
                    .body(Body::empty())
                    .expect("failed to build restart request"),
            )
            .await
            .expect("restart request failed");
        assert_eq!(restart.status(), StatusCode::NO_CONTENT);

        // A CLI that predates the 204 signal (no x-tuist-cli-version header) still
        // gets the legacy 200 with a null upload id, keeping the change backward
        // compatible.
        let legacy_restart = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build legacy restart request"),
            )
            .await
            .expect("legacy restart request failed");
        assert_eq!(legacy_restart.status(), StatusCode::OK);
        let legacy_payload: Value = serde_json::from_str(&response_text(legacy_restart).await)
            .expect("failed to decode legacy restart payload");
        assert_eq!(legacy_payload["upload_id"], Value::Null);
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
    async fn extension_context_resolves_namespace_from_multipart_upload() {
        let context = test_context(|_| {}).await;
        let upload_id = context
            .state
            .store
            .start_multipart_upload("acme", "ios", "builds", "hash-1", "Module.framework")
            .expect("failed to start multipart upload");
        let query = parse_query_map(Some(&format!("upload_id={upload_id}&part_number=1")));
        let headers = BTreeMap::new();

        let extension_context = extension_context_from_http(
            &context.state,
            HttpExtensionRequest {
                route: ROUTE_API_CACHE_MODULE_PART,
                method: "POST",
                path: ROUTE_API_CACHE_MODULE_PART,
                query: &query,
                headers: &headers,
                body: None,
                status_code: None,
            },
        )
        .await;

        assert_eq!(extension_context.tenant_id.as_deref(), Some("acme"));
        assert_eq!(extension_context.namespace_id.as_deref(), Some("ios"));
        assert_eq!(extension_context.artifact_hash.as_deref(), Some("hash-1"));
        assert_eq!(
            extension_context.artifact_key.as_deref(),
            Some("builds/hash-1/Module.framework")
        );
    }

    #[tokio::test]
    async fn extension_context_uses_handle_aliases() {
        let context = test_context(|_| {}).await;
        let query = parse_query_map(Some("account_handle=acme&project_handle=ios&hash=hash-1"));
        let extension_context = extension_context_from_http(
            &context.state,
            HttpExtensionRequest {
                route: ROUTE_API_CACHE_CAS,
                method: "GET",
                path: "/api/cache/cas/artifact-1",
                query: &query,
                headers: &BTreeMap::new(),
                body: None,
                status_code: None,
            },
        )
        .await;

        assert_eq!(extension_context.tenant_id.as_deref(), Some("acme"));
        assert_eq!(extension_context.namespace_id.as_deref(), Some("ios"));
    }

    #[tokio::test]
    async fn extension_context_omits_namespace_for_tenant_scoped_requests() {
        let context = test_context(|_| {}).await;
        let query = parse_query_map(Some("tenant_id=acme&hash=hash-1"));
        let extension_context = extension_context_from_http(
            &context.state,
            HttpExtensionRequest {
                route: ROUTE_API_CACHE_CAS,
                method: "GET",
                path: "/api/cache/cas/account-artifact",
                query: &query,
                headers: &BTreeMap::new(),
                body: None,
                status_code: None,
            },
        )
        .await;

        assert_eq!(extension_context.tenant_id.as_deref(), Some("acme"));
        assert_eq!(extension_context.namespace_id, None);
    }

    #[tokio::test]
    async fn extension_context_uses_keyvalue_cas_id_from_request_body() {
        let context = test_context(|_| {}).await;
        let query = parse_query_map(Some("tenant_id=acme&namespace_id=ios"));
        let request_body = br#"{"cas_id":"cas-1","entries":[{"value":"hello"},{"value":"world"}]}"#;
        let extension_context = extension_context_from_http(
            &context.state,
            HttpExtensionRequest {
                route: ROUTE_API_CACHE_KEYVALUE,
                method: "PUT",
                path: ROUTE_API_CACHE_KEYVALUE,
                query: &query,
                headers: &BTreeMap::new(),
                body: Some(request_body),
                status_code: None,
            },
        )
        .await;

        assert_eq!(
            extension_context.artifact_key.as_deref(),
            Some("action_cache/cas-1")
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
        );

        assert_eq!(context.state.runtime.public_http_inflight(), 1);
        drop(instrumented);
        assert_eq!(context.state.runtime.public_http_inflight(), 0);
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

    mod client_ip {
        use axum::http::{HeaderMap, HeaderValue};

        use super::super::client_ip_from_headers;

        #[test]
        fn returns_first_hop_from_x_forwarded_for() {
            let mut headers = HeaderMap::new();
            headers.insert(
                "x-forwarded-for",
                HeaderValue::from_static("203.0.113.5, 10.0.0.1, 198.51.100.7"),
            );
            assert_eq!(
                client_ip_from_headers(&headers)
                    .expect("first hop should parse")
                    .to_string(),
                "203.0.113.5"
            );
        }

        #[test]
        fn trims_surrounding_whitespace_in_x_forwarded_for() {
            let mut headers = HeaderMap::new();
            headers.insert(
                "x-forwarded-for",
                HeaderValue::from_static("  203.0.113.5  , 10.0.0.1"),
            );
            assert_eq!(
                client_ip_from_headers(&headers)
                    .expect("trimmed first hop should parse")
                    .to_string(),
                "203.0.113.5"
            );
        }

        #[test]
        fn falls_back_to_x_real_ip_when_x_forwarded_for_is_missing() {
            let mut headers = HeaderMap::new();
            headers.insert("x-real-ip", HeaderValue::from_static("198.51.100.7"));
            assert_eq!(
                client_ip_from_headers(&headers)
                    .expect("x-real-ip should parse")
                    .to_string(),
                "198.51.100.7"
            );
        }

        #[test]
        fn returns_none_when_no_address_headers_are_present() {
            let headers = HeaderMap::new();
            assert!(client_ip_from_headers(&headers).is_none());
        }

        #[test]
        fn returns_none_when_first_hop_is_malformed() {
            let mut headers = HeaderMap::new();
            headers.insert("x-forwarded-for", HeaderValue::from_static("not-an-ip"));
            assert!(client_ip_from_headers(&headers).is_none());
        }
    }
}
