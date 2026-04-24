use std::collections::{BTreeMap, HashMap};

use axum::{
    Json, Router,
    body::{Body, to_bytes},
    extract::{MatchedPath, Path as AxumPath, Query, Request, State},
    http::{HeaderValue, StatusCode, Version},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{delete, get, head, post, put},
};
use serde::Deserialize;
use tokio_util::io::ReaderStream;
use tracing::{Instrument, field};

use crate::{
    artifact::{manifest::ArtifactManifest, producer::ArtifactProducer},
    constants::{MAX_GRADLE_BYTES, MAX_MODULE_PART_BYTES, MAX_MODULE_TOTAL_BYTES, MAX_XCODE_BYTES},
    extension::{AccessDecision, ExtensionContext},
    multipart::error::MultipartError,
    replication::replication_targets,
    state::SharedState,
    telemetry::attach_parent_context,
    utils::{BodyReadError, action_cache_key, blob_key, module_key, read_request_to_temp},
};

pub fn public_router(state: SharedState) -> Router {
    public_routes()
        .layer(middleware::from_fn_with_state(
            state.clone(),
            apply_extensions,
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
        .route("/up", get(up))
        .route("/ready", get(ready))
        .route("/metrics", get(metrics_handler))
        .route("/v1/cache/{hash}", get(get_nx).put(put_nx))
        .route(
            "/api/metro/cache/{cache_key}",
            get(get_metro).put(put_metro),
        )
        .route("/api/cache/keyvalue/{cas_id}", get(get_keyvalue))
        .route("/api/cache/keyvalue", put(put_keyvalue))
        .route("/api/cache/cas/{id}", get(get_xcode).post(put_xcode))
        .route("/api/cache/module/{id}", head(head_module).get(get_module))
        .route("/api/cache/module/start", post(start_module_upload))
        .route("/api/cache/module/part", post(upload_module_part))
        .route("/api/cache/module/complete", post(complete_module_upload))
        .route("/api/cache/clean", delete(clean_namespace))
        .route(
            "/api/cache/gradle/{cache_key}",
            get(get_gradle).put(put_gradle),
        )
}

fn internal_routes() -> Router<SharedState> {
    Router::new()
        .route("/_internal/status", get(internal_status))
        .route(
            "/_internal/bootstrap/manifests",
            get(internal_bootstrap_manifests),
        )
        .route(
            "/_internal/bootstrap/namespace_tombstones",
            get(internal_bootstrap_namespace_tombstones),
        )
        .route(
            "/_internal/bootstrap/artifacts/{artifact_id}",
            get(internal_bootstrap_artifact),
        )
        .route(
            "/_internal/replicate/artifact",
            put(internal_replicate_artifact),
        )
        .route(
            "/_internal/replicate/namespace",
            delete(internal_delete_namespace),
        )
}

const NX_NAMESPACE_ID: &str = "nx";
const METRO_NAMESPACE_ID: &str = "metro";

#[derive(Debug, PartialEq, Eq)]
struct NamespaceQuery {
    tenant_id: String,
    namespace_id: String,
}

impl NamespaceQuery {
    fn from_params(params: &HashMap<String, String>) -> Result<Self, String> {
        Ok(Self {
            tenant_id: required_param(params, "tenant_id")?,
            namespace_id: required_param(params, "namespace_id")?,
        })
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
struct LegacyAnalyticsContext<'a> {
    tenant_id: &'a str,
    namespace_id: &'a str,
}

#[derive(Clone, Copy)]
struct BlobPutSpec<'a> {
    namespace_id: &'a str,
    key: &'a str,
    analytics_key: Option<&'a str>,
    max_bytes: u64,
    success_status: StatusCode,
    analytics: Option<LegacyAnalyticsContext<'a>>,
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
            namespace_id: required_param(params, "namespace_id")?,
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

fn param_value<'a>(params: &'a HashMap<String, String>, key: &str) -> Option<&'a String> {
    params
        .get(key)
        .or_else(|| alias_keys(key).iter().find_map(|alias| params.get(*alias)))
}

fn required_param(params: &HashMap<String, String>, key: &str) -> Result<String, String> {
    param_value(params, key)
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

async fn track_http_metrics(
    State(state): State<SharedState>,
    req: Request,
    next: Next,
) -> Response {
    let _request_guard = state.start_http_request();
    let start = std::time::Instant::now();
    let route = req
        .extensions()
        .get::<MatchedPath>()
        .map(|path| path.as_str().to_owned())
        .unwrap_or_else(|| req.uri().path().to_owned());
    let method = req.method().to_string();
    let uri_path = req.uri().path().to_owned();

    let request_span = tracing::info_span!(
        "http.request",
        otel.name = %format!("{method} {route}"),
        otel.kind = "server",
        http.request.method = %method,
        http.route = %route,
        url.path = %uri_path,
        http.response.status_code = field::Empty,
        otel.status_code = field::Empty,
    );
    attach_parent_context(&request_span, req.headers());

    let response = next.run(req).instrument(request_span.clone()).await;
    request_span.record("http.response.status_code", response.status().as_u16());
    if response.status().is_server_error() {
        request_span.record("otel.status_code", "ERROR");
    }

    state
        .metrics
        .record_http(route, method, response.status(), start.elapsed());

    response
}

async fn reject_draining_public_requests(
    State(state): State<SharedState>,
    req: Request,
    next: Next,
) -> Response {
    let route = req
        .extensions()
        .get::<MatchedPath>()
        .map(|path| path.as_str().to_owned())
        .unwrap_or_else(|| req.uri().path().to_owned());
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

async fn apply_extensions(State(state): State<SharedState>, req: Request, next: Next) -> Response {
    let Some(extension) = state.extension.as_ref() else {
        return next.run(req).await;
    };

    let route = req
        .extensions()
        .get::<MatchedPath>()
        .map(|path| path.as_str().to_owned())
        .unwrap_or_else(|| req.uri().path().to_owned());
    let path = req.uri().path().to_owned();
    if should_skip_extension_route(&route) {
        return next.run(req).await;
    }

    let method = req.method().to_string();
    let query = parse_query_map(req.uri().query());
    let request_headers = header_map_to_btree(req.headers());
    let context = extension_context_from_http(
        &state,
        &route,
        &method,
        &path,
        &query,
        &request_headers,
        None,
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
        &route,
        &method,
        &path,
        &query,
        &request_headers,
        Some(response.status().as_u16()),
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
    route == "/up" || route == "/ready" || route == "/metrics"
}

fn is_http1(version: Version) -> bool {
    matches!(version, Version::HTTP_10 | Version::HTTP_11)
}

async fn extension_context_from_http(
    state: &SharedState,
    route: &str,
    method: &str,
    path: &str,
    query: &HashMap<String, String>,
    headers: &BTreeMap<String, String>,
    status_code: Option<u16>,
) -> ExtensionContext {
    let metadata = http_extension_metadata(state, route, method, path, query).await;
    ExtensionContext {
        transport: "http".into(),
        route: route.to_owned(),
        method: method.to_owned(),
        operation: metadata.operation,
        tenant_id: metadata.tenant_id,
        namespace_id: metadata.namespace_id,
        producer: metadata.producer,
        artifact_key: metadata.artifact_key,
        artifact_hash: metadata.artifact_hash,
        headers: headers.clone(),
        query: query
            .iter()
            .map(|(key, value)| (key.clone(), value.clone()))
            .collect(),
        status_code,
    }
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
) -> HttpExtensionMetadata {
    let tenant_id = param_value(query, "tenant_id").cloned();
    let mut namespace_id = param_value(query, "namespace_id").cloned();
    let last_path_segment = path.rsplit('/').next().map(str::to_owned);

    match route {
        "/api/cache/keyvalue/{cas_id}" => HttpExtensionMetadata {
            operation: "artifact.read".into(),
            tenant_id,
            namespace_id,
            producer: Some("xcode".into()),
            artifact_key: last_path_segment.as_deref().map(action_cache_key),
            artifact_hash: None,
        },
        "/api/cache/keyvalue" => HttpExtensionMetadata {
            operation: "artifact.write".into(),
            tenant_id,
            namespace_id,
            producer: Some("xcode".into()),
            artifact_key: query.get("cas_id").map(|cas_id| action_cache_key(cas_id)),
            artifact_hash: None,
        },
        "/api/cache/cas/{id}" => HttpExtensionMetadata {
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
        "/api/cache/gradle/{cache_key}" => HttpExtensionMetadata {
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
        "/api/cache/module/{id}" => HttpExtensionMetadata {
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
        "/api/cache/module/start" | "/api/cache/module/part" | "/api/cache/module/complete" => {
            let multipart_upload = query
                .get("upload_id")
                .and_then(|upload_id| state.store.multipart_upload(upload_id).ok().flatten());
            let tenant_id =
                tenant_id.or_else(|| multipart_upload.as_ref().map(|u| u.tenant_id.clone()));
            let namespace_id =
                namespace_id.or_else(|| multipart_upload.as_ref().map(|u| u.namespace_id.clone()));
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
        "/api/cache/clean" => HttpExtensionMetadata {
            operation: "namespace.delete".into(),
            tenant_id,
            namespace_id,
            producer: None,
            artifact_key: None,
            artifact_hash: None,
        },
        "/v1/cache/{hash}" => {
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
        "/api/metro/cache/{cache_key}" => {
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
    let mut all_members = cluster.members;
    all_members.push(state.config.region.clone());
    all_members.sort();
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
        "members": all_members.into_iter().collect::<Vec<_>>(),
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

    get_artifact(
        state,
        ArtifactProducer::Xcode,
        &namespace.namespace_id,
        &action_cache_key(&cas_id),
        None,
        None,
    )
    .await
}

async fn get_nx(AxumPath(hash): AxumPath<String>, State(state): State<SharedState>) -> Response {
    get_artifact(
        state,
        ArtifactProducer::Nx,
        NX_NAMESPACE_ID,
        &hash,
        None,
        None,
    )
    .await
}

async fn put_nx(
    AxumPath(hash): AxumPath<String>,
    State(state): State<SharedState>,
    request: Request,
) -> Response {
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
            analytics: None,
        },
    )
    .await
}

async fn get_metro(
    AxumPath(cache_key): AxumPath<String>,
    State(state): State<SharedState>,
) -> Response {
    get_artifact(
        state,
        ArtifactProducer::Metro,
        METRO_NAMESPACE_ID,
        &cache_key,
        None,
        None,
    )
    .await
}

async fn put_metro(
    AxumPath(cache_key): AxumPath<String>,
    State(state): State<SharedState>,
    request: Request,
) -> Response {
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
            analytics: None,
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

    let cas_id = body.cas_id.clone();
    let key = action_cache_key(&cas_id);
    let payload = serde_json::json!({
        "cas_id": body.cas_id,
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
            StatusCode::NO_CONTENT.into_response()
        }
        Err(error) => {
            state
                .metrics
                .record_artifact_write(ArtifactProducer::Xcode, "error", 0);
            error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                format!("Failed to persist key-value entry: {error}"),
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

    get_artifact(
        state,
        ArtifactProducer::Xcode,
        &namespace.namespace_id,
        &blob_key(&id),
        Some(&id),
        Some(LegacyAnalyticsContext {
            tenant_id: &namespace.tenant_id,
            namespace_id: &namespace.namespace_id,
        }),
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
            analytics: Some(LegacyAnalyticsContext {
                tenant_id: &namespace.tenant_id,
                namespace_id: &namespace.namespace_id,
            }),
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

    get_artifact(
        state,
        ArtifactProducer::Gradle,
        &namespace.namespace_id,
        &cache_key,
        Some(&cache_key),
        Some(LegacyAnalyticsContext {
            tenant_id: &namespace.tenant_id,
            namespace_id: &namespace.namespace_id,
        }),
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
            analytics: Some(LegacyAnalyticsContext {
                tenant_id: &namespace.tenant_id,
                namespace_id: &namespace.namespace_id,
            }),
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

    get_artifact(
        state,
        ArtifactProducer::Module,
        &query.namespace.namespace_id,
        &query.artifact_key(),
        None,
        None,
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

    let temp = match read_request_to_temp(
        request,
        &state.config.tmp_dir.join("parts"),
        MAX_MODULE_PART_BYTES,
        &state.io,
    )
    .await
    {
        Ok(temp) => temp,
        Err(BodyReadError::TooLarge) => {
            return error_response(StatusCode::PAYLOAD_TOO_LARGE, "Part exceeds 10MB limit");
        }
        Err(BodyReadError::Io(error)) => {
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to persist multipart upload part: {error}"),
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
        Err(MultipartError::Other(error)) => error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to complete multipart upload: {error}"),
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

async fn internal_status(State(state): State<SharedState>) -> impl IntoResponse {
    Json(serde_json::json!({
        "region": state.config.region.clone(),
        "tenant_id": state.config.tenant_id.clone(),
        "node_url": state.config.node_url.clone(),
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
    match state.store.manifest(&artifact_id) {
        Ok(Some(manifest)) => serve_file(&state, StatusCode::OK, &manifest).await,
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
                error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    format!("Failed to persist replicated artifact: {error}"),
                )
            }
        };
    }

    let temp = match read_request_to_temp(
        request,
        &state.config.tmp_dir.join("uploads"),
        u64::MAX,
        &state.io,
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
        Err(BodyReadError::Io(error)) => {
            state
                .metrics
                .record_replication_apply("replication", "artifact", "error");
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to read replication body: {error}"),
            );
        }
    };

    match state
        .store
        .apply_replicated_artifact_from_path(
            producer,
            &query.namespace_id,
            &query.key,
            &query.content_type,
            &temp.path,
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
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to persist replicated artifact: {error}"),
            )
        }
    }
}

async fn internal_delete_namespace(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
) -> Response {
    let namespace_id = match required_param(&params, "namespace_id") {
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
    analytics: Option<LegacyAnalyticsContext<'_>>,
) -> Response {
    match state
        .store
        .fetch_artifact(producer, namespace_id, key)
        .await
    {
        Ok(Some(manifest)) => {
            state
                .metrics
                .record_artifact_read(producer, "ok", manifest.size);
            let response = serve_file(&state, StatusCode::OK, &manifest).await;
            if response.status().is_success() {
                record_legacy_cache_event(
                    &state,
                    producer,
                    "download",
                    analytics,
                    analytics_key.unwrap_or(key),
                    manifest.size,
                );
            }
            response
        }
        Ok(None) => {
            state.metrics.record_artifact_read(producer, "not_found", 0);
            StatusCode::NOT_FOUND.into_response()
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
        Ok(true) => return spec.success_status.into_response(),
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
        &state.io,
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
        Err(BodyReadError::Io(error)) => {
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to persist artifact: {error}"),
            );
        }
    };

    let targets = replication_targets(&state).await;
    match state
        .store
        .persist_artifact_from_path_and_enqueue(
            producer,
            spec.namespace_id,
            spec.key,
            "application/octet-stream",
            &temp.path,
            &targets,
        )
        .await
    {
        Ok(manifest) => {
            state.notify.notify_one();
            state
                .metrics
                .record_artifact_write(producer, "ok", manifest.size);
            record_legacy_cache_event(
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
            error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                format!("Failed to persist artifact: {error}"),
            )
        }
    }
}

fn record_legacy_cache_event(
    state: &SharedState,
    producer: ArtifactProducer,
    action: &str,
    analytics: Option<LegacyAnalyticsContext<'_>>,
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
    match state.store.open_artifact_reader(manifest).await {
        Ok(reader) => {
            let stream = ReaderStream::new(reader);
            let mut response = Response::new(Body::from_stream(stream));
            *response.status_mut() = status;
            response.headers_mut().insert(
                axum::http::header::CONTENT_TYPE,
                HeaderValue::from_str(&manifest.content_type)
                    .unwrap_or_else(|_| HeaderValue::from_static("application/octet-stream")),
            );
            response
        }
        Err(error) => error_response(
            StatusCode::NOT_FOUND,
            format!("Artifact bytes are missing from local storage: {error}"),
        ),
    }
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
        config::AnalyticsConfig,
        test_support::{response_text, test_context},
        utils::blob_key,
    };

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
        assert!(body["members"].to_string().contains("eu-west"));
        assert!(
            body["connected_nodes"]
                .to_string()
                .contains("http://peer.kura.internal:4000")
        );
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
    async fn draining_public_requests_return_service_unavailable_and_close_http1_connections() {
        let context = test_context(|_| {}).await;
        context
            .state
            .apply_membership_view(
                std::collections::BTreeSet::new(),
                std::collections::BTreeMap::new(),
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
        assert_eq!(body["cas_id"], "cas-1");
        assert_eq!(body["entries"][0]["value"], "hello");
        assert_eq!(body["entries"][1]["value"], "world");
    }

    #[tokio::test]
    async fn legacy_account_and_project_handles_work_through_router() {
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
    async fn xcode_routes_emit_legacy_analytics_events() {
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
        assert_eq!(response_text(get).await, "part-one-part-two");
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
            "/api/cache/module/part",
            "POST",
            "/api/cache/module/part",
            &query,
            &headers,
            None,
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
    async fn extension_context_uses_legacy_handle_aliases() {
        let context = test_context(|_| {}).await;
        let query = parse_query_map(Some("account_handle=acme&project_handle=ios&hash=hash-1"));
        let extension_context = extension_context_from_http(
            &context.state,
            "/api/cache/cas/{id}",
            "GET",
            "/api/cache/cas/artifact-1",
            &query,
            &BTreeMap::new(),
            None,
        )
        .await;

        assert_eq!(extension_context.tenant_id.as_deref(), Some("acme"));
        assert_eq!(extension_context.namespace_id.as_deref(), Some("ios"));
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
}
