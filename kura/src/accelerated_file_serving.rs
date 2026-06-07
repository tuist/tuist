use std::{
    collections::BTreeMap,
    io::Write,
    net::SocketAddr,
    sync::Arc,
    time::{Duration, Instant},
};

use axum::{
    Router,
    body::Body,
    http::{Request, StatusCode},
};
use hyper::{body::Incoming, service::service_fn};
use hyper_util::{
    rt::{TokioExecutor, TokioIo, TokioTimer},
    server::conn::auto::Builder as HttpBuilder,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    sync::{Semaphore, watch},
};
use tower::ServiceExt;
use tracing::{Instrument, info};

use crate::{
    analytics::Analytics,
    artifact::producer::ArtifactProducer,
    config::{AcceleratedFileServingConfig, AcceleratedFileServingMode},
    extension::{AccessDecision, ExtensionContext},
    runtime::HttpTrafficClass,
    state::SharedState,
    store::AcceleratedArtifactFile,
    usage::Usage,
    utils::{blob_key, module_key},
};

const MAX_HEADER_BYTES: usize = 16 * 1024;
const HEADER_TIMEOUT: Duration = Duration::from_secs(30);
const IO_TIMEOUT: Duration = Duration::from_secs(120);
const KEEP_ALIVE_IDLE_TIMEOUT: Duration = Duration::from_secs(60);
const HTTP2_MAX_CONCURRENT_STREAMS: u32 = 128;
const HTTP2_INITIAL_STREAM_WINDOW_BYTES: u32 = 1024 * 1024;
const HTTP2_INITIAL_CONNECTION_WINDOW_BYTES: u32 = 16 * 1024 * 1024;
const HTTP2_MAX_FRAME_SIZE: u32 = 64 * 1024;
const HTTP2_MAX_SEND_BUFFER_BYTES: usize = 512 * 1024;
const HTTP2_KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(30);
const HTTP2_KEEP_ALIVE_TIMEOUT: Duration = Duration::from_secs(20);
const NX_NAMESPACE_ID: &str = "nx";
const METRO_NAMESPACE_ID: &str = "metro";
const TENANT_SCOPE_NAMESPACE_ID: &str = "";

pub async fn serve_public_http(
    address: SocketAddr,
    router: Router,
    state: SharedState,
    config: AcceleratedFileServingConfig,
    mut shutdown_rx: watch::Receiver<bool>,
) -> Result<(), String> {
    let listener = TcpListener::bind(address)
        .await
        .map_err(|error| format!("failed to bind public HTTP listener: {error}"))?;
    let semaphore = Arc::new(Semaphore::new(config.max_concurrent));
    info!(
        mode = config.mode.as_str(),
        max_concurrent = config.max_concurrent,
        chunk_bytes = config.chunk_bytes,
        "Kura public HTTP listener using accelerated artifact serving on {address}"
    );

    loop {
        tokio::select! {
            result = listener.accept() => {
                let (stream, _) = match result {
                    Ok(stream) => stream,
                    Err(error) => {
                        tracing::warn!("public HTTP accept failed: {error}");
                        continue;
                    }
                };
                let router = router.clone();
                let state = state.clone();
                let config = config.clone();
                let semaphore = semaphore.clone();
                tokio::spawn(
                    async move {
                        if let Err(error) = serve_connection(stream, router, state, config, semaphore).await {
                            tracing::debug!("public HTTP connection failed: {error}");
                        }
                    }
                    .in_current_span(),
                );
            }
            changed = shutdown_rx.changed() => {
                if changed.is_err() || *shutdown_rx.borrow() {
                    return Ok(());
                }
            }
        }
    }
}

async fn serve_connection(
    mut stream: TcpStream,
    router: Router,
    state: SharedState,
    config: AcceleratedFileServingConfig,
    semaphore: Arc<Semaphore>,
) -> std::io::Result<()> {
    loop {
        // Bound the wait for the next request so idle keep-alive connections do
        // not pin a task and file descriptor forever.
        let classified =
            match tokio::time::timeout(KEEP_ALIVE_IDLE_TIMEOUT, classify_route(&stream, &state))
                .await
            {
                Ok(classified) => classified,
                Err(_) => return Ok(()),
            };

        // Match the route from a non-destructive peek before doing any access or
        // store work. Anything that is not an accelerable artifact GET, including
        // a pipelined follow-up on a reused connection, or anything that arrives
        // once the accelerator is at capacity, falls through to the normal
        // Axum/Hyper path before request bytes are consumed and without
        // re-evaluating access twice. The peek does not consume bytes, so Hyper
        // re-reads the request from the start.
        let Some((parsed, artifact)) = classified else {
            return serve_hyper(stream, router).await;
        };
        let keep_alive = request_wants_keep_alive(&parsed);
        let request_started_at = Instant::now();
        let Ok(permit) = semaphore.clone().try_acquire_owned() else {
            return serve_hyper(stream, router).await;
        };
        match authorize_and_open(&state, parsed, artifact).await {
            ClassifiedRequest::Accelerate(candidate) => {
                consume_headers(&mut stream, candidate.header_len).await?;
                let reuse = serve_accelerated(
                    stream,
                    &state,
                    &config,
                    candidate,
                    request_started_at,
                    keep_alive,
                )
                .await;
                drop(permit);
                match reuse? {
                    Some(reused) => {
                        stream = reused;
                        continue;
                    }
                    None => return Ok(()),
                }
            }
            ClassifiedRequest::Deny(denial) => {
                drop(permit);
                consume_headers(&mut stream, denial.header_len).await?;
                let headers = BTreeMap::new();
                let result = write_response(
                    &mut stream,
                    denial.status,
                    denial.reason,
                    "text/plain",
                    &headers,
                    denial.body.as_bytes(),
                )
                .await;
                state.metrics.record_http(
                    denial.route.to_owned(),
                    StatusCode::from_u16(denial.status)
                        .unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
                    None,
                    Duration::ZERO,
                );
                return result;
            }
            ClassifiedRequest::Fallback => {
                drop(permit);
                return serve_hyper(stream, router).await;
            }
        }
    }
}

fn request_wants_keep_alive(parsed: &ParsedRequest) -> bool {
    // Only HTTP/1.1 GETs reach here. Default to keep-alive unless the client
    // asked to close, or the request carries a body we did not consume, which
    // would desync a reused connection.
    if parsed
        .headers
        .get("connection")
        .map(|value| {
            value
                .split(',')
                .any(|token| token.trim().eq_ignore_ascii_case("close"))
        })
        .unwrap_or(false)
    {
        return false;
    }
    if parsed.headers.contains_key("transfer-encoding") {
        return false;
    }
    if let Some(length) = parsed.headers.get("content-length")
        && length.trim() != "0"
    {
        return false;
    }
    true
}

async fn serve_hyper(stream: TcpStream, router: Router) -> std::io::Result<()> {
    let mut builder = HttpBuilder::new(TokioExecutor::new());
    configure_public_http_builder(&mut builder);
    let service = service_fn(move |request: Request<Incoming>| {
        let router = router.clone();
        async move {
            router
                .oneshot(request.map(Body::new))
                .await
                .map_err(std::io::Error::other)
        }
    });
    builder
        .serve_connection(TokioIo::new(stream), service)
        .await
        .map_err(std::io::Error::other)
}

fn configure_public_http_builder(builder: &mut HttpBuilder<TokioExecutor>) {
    builder
        .http1()
        .keep_alive(true)
        .timer(TokioTimer::new())
        .header_read_timeout(Some(HEADER_TIMEOUT));
    builder
        .http2()
        .initial_stream_window_size(Some(HTTP2_INITIAL_STREAM_WINDOW_BYTES))
        .initial_connection_window_size(Some(HTTP2_INITIAL_CONNECTION_WINDOW_BYTES))
        .adaptive_window(true)
        .max_concurrent_streams(Some(HTTP2_MAX_CONCURRENT_STREAMS))
        .max_frame_size(Some(HTTP2_MAX_FRAME_SIZE))
        .max_send_buf_size(HTTP2_MAX_SEND_BUFFER_BYTES)
        .keep_alive_interval(Some(HTTP2_KEEP_ALIVE_INTERVAL))
        .keep_alive_timeout(HTTP2_KEEP_ALIVE_TIMEOUT)
        .timer(TokioTimer::new());
}

enum ClassifiedRequest {
    Accelerate(AcceleratedCandidate),
    Deny(Denial),
    Fallback,
}

struct Denial {
    header_len: usize,
    route: &'static str,
    status: u16,
    reason: &'static str,
    body: String,
}

struct AcceleratedCandidate {
    header_len: usize,
    artifact: ArtifactRequest,
    file: AcceleratedArtifactFile,
    extension_response_headers: BTreeMap<String, String>,
}

#[derive(Debug, PartialEq, Eq)]
struct ParsedRequest {
    method: String,
    target: String,
    version: u8,
    header_len: usize,
    headers: BTreeMap<String, String>,
}

#[derive(Debug, PartialEq, Eq)]
struct ArtifactRequest {
    producer: ArtifactProducer,
    tenant_id: String,
    namespace_id: String,
    key: String,
    analytics_key: Option<String>,
    artifact_hash: Option<String>,
    route: &'static str,
    path: String,
    query: BTreeMap<String, String>,
}

async fn classify_route(
    stream: &TcpStream,
    state: &SharedState,
) -> Option<(ParsedRequest, ArtifactRequest)> {
    if !cfg!(target_os = "linux") || state.runtime.is_draining() {
        return None;
    }
    let parsed = match peek_request(stream).await {
        Ok(Some(parsed)) => parsed,
        Ok(None) => return None,
        Err(error) => {
            tracing::debug!("failed to classify request for acceleration: {error}");
            return None;
        }
    };
    if parsed.version != 1 || parsed.method != "GET" {
        return None;
    }
    let artifact = artifact_request(&parsed.target, &state.config.tenant_id)?;
    Some((parsed, artifact))
}

async fn authorize_and_open(
    state: &SharedState,
    parsed: ParsedRequest,
    artifact: ArtifactRequest,
) -> ClassifiedRequest {
    let access_context = extension_context(state, &parsed, &artifact, None);
    let principal = if let Some(extension) = state.extension.as_ref() {
        match extension.evaluate_access(&access_context).await {
            AccessDecision::Allow(principal) => principal,
            AccessDecision::Deny(deny) => {
                return ClassifiedRequest::Deny(Denial {
                    header_len: parsed.header_len,
                    route: artifact.route,
                    status: deny.status,
                    reason: reason_for_status(deny.status),
                    body: deny.message,
                });
            }
        }
    } else {
        None
    };

    let manifest = match state
        .store
        .fetch_artifact_for_serving(artifact.producer, &artifact.namespace_id, &artifact.key)
        .await
    {
        Ok(Some(manifest)) => manifest,
        _ => return ClassifiedRequest::Fallback,
    };
    let file = match state.store.open_accelerated_artifact_file(&manifest).await {
        Ok(Some(file)) => file,
        _ => return ClassifiedRequest::Fallback,
    };
    let extension_response_headers = if let Some(extension) = state.extension.as_ref() {
        extension
            .response_headers(
                &extension_context(state, &parsed, &artifact, Some(StatusCode::OK.as_u16())),
                principal.as_ref(),
            )
            .await
            .headers
    } else {
        BTreeMap::new()
    };

    ClassifiedRequest::Accelerate(AcceleratedCandidate {
        header_len: parsed.header_len,
        artifact,
        file,
        extension_response_headers,
    })
}

async fn peek_request(stream: &TcpStream) -> std::io::Result<Option<ParsedRequest>> {
    let started_at = Instant::now();
    let mut bytes = vec![0_u8; MAX_HEADER_BYTES];
    loop {
        if started_at.elapsed() > HEADER_TIMEOUT {
            return Ok(None);
        }
        stream.readable().await?;
        let read = stream.peek(&mut bytes).await?;
        if read == 0 {
            return Ok(None);
        }
        match parse_request(&bytes[..read]) {
            Ok(Some(request)) => return Ok(Some(request)),
            Ok(None) if read == MAX_HEADER_BYTES => return Ok(None),
            Ok(None) => continue,
            Err(_) => return Ok(None),
        }
    }
}

fn parse_request(bytes: &[u8]) -> Result<Option<ParsedRequest>, httparse::Error> {
    let mut headers = [httparse::EMPTY_HEADER; 64];
    let mut request = httparse::Request::new(&mut headers);
    let status = request.parse(bytes)?;
    let header_len = match status {
        httparse::Status::Complete(header_len) => header_len,
        httparse::Status::Partial => return Ok(None),
    };
    let Some(method) = request.method else {
        return Ok(None);
    };
    let Some(target) = request.path else {
        return Ok(None);
    };
    let Some(version) = request.version else {
        return Ok(None);
    };
    let headers = request
        .headers
        .iter()
        .filter(|header| !header.name.is_empty())
        .filter_map(|header| {
            std::str::from_utf8(header.value)
                .ok()
                .map(|value| (header.name.to_ascii_lowercase(), value.trim().to_string()))
        })
        .collect();
    Ok(Some(ParsedRequest {
        method: method.to_owned(),
        target: target.to_owned(),
        version,
        header_len,
        headers,
    }))
}

async fn consume_headers(stream: &mut TcpStream, header_len: usize) -> std::io::Result<()> {
    let mut discard = vec![0_u8; header_len];
    stream.read_exact(&mut discard).await.map(|_| ())
}

async fn serve_accelerated(
    stream: TcpStream,
    state: &SharedState,
    config: &AcceleratedFileServingConfig,
    candidate: AcceleratedCandidate,
    request_started_at: Instant,
    keep_alive: bool,
) -> std::io::Result<Option<TcpStream>> {
    let transfer_started_at = Instant::now();
    let _request_guard = state.start_http_request(HttpTrafficClass::Public);
    let file = candidate.file.clone();
    let producer = candidate.artifact.producer;
    // Accelerated requests are always for this node's tenant: cross-tenant
    // requests fall back to the Axum path during classification. Attribute
    // usage and analytics to the configured tenant so the numbers match the
    // Axum handlers, which key off the node tenant rather than the per-request
    // namespace tenant alias.
    let tenant_id = state.config.tenant_id.clone();
    let namespace_id = candidate.artifact.namespace_id.clone();
    let analytics_key = candidate.artifact.analytics_key.clone();
    let route = candidate.artifact.route.to_owned();
    let extension_headers = candidate.extension_response_headers.clone();
    let content_type = sanitized_content_type(&file.content_type);
    let mode = config.mode;
    let chunk_bytes = config.chunk_bytes;
    let result = tokio::task::spawn_blocking(
        move || -> std::io::Result<(std::net::TcpStream, u64, Duration)> {
            let mut stream = stream.into_std()?;
            stream.set_nonblocking(false)?;
            stream.set_write_timeout(Some(IO_TIMEOUT))?;
            write_headers(
                &mut stream,
                200,
                "OK",
                &content_type,
                file.size,
                &extension_headers,
                keep_alive,
            )?;
            // Time to first byte is measured once the headers are on the wire,
            // before the body transfer, so large downloads do not inflate the
            // responsiveness signal.
            let time_to_first_byte = request_started_at.elapsed();
            let bytes = transfer_file(&mut stream, &file, mode, chunk_bytes)?;
            Ok((stream, bytes, time_to_first_byte))
        },
    )
    .await
    .map_err(std::io::Error::other)?;

    match result {
        Ok((std_stream, bytes, time_to_first_byte)) => {
            state.runtime.record_public_request_latency(
                &state.metrics,
                "http",
                &route,
                time_to_first_byte,
            );
            state
                .metrics
                .record_http(route, StatusCode::OK, None, time_to_first_byte);
            state.metrics.record_artifact_read(producer, "ok", bytes);
            state.metrics.record_artifact_egress(
                producer,
                "ok",
                bytes,
                transfer_started_at.elapsed(),
            );
            record_usage(
                state.usage.as_ref(),
                producer,
                &tenant_id,
                &namespace_id,
                bytes,
            );
            record_analytics(
                state.analytics.as_ref(),
                producer,
                &tenant_id,
                &namespace_id,
                analytics_key.as_deref(),
                bytes,
            );
            if keep_alive {
                std_stream.set_nonblocking(true)?;
                Ok(Some(TcpStream::from_std(std_stream)?))
            } else {
                Ok(None)
            }
        }
        Err(error) => {
            state.metrics.record_http(
                route,
                StatusCode::INTERNAL_SERVER_ERROR,
                None,
                transfer_started_at.elapsed(),
            );
            state.metrics.record_artifact_read(producer, "error", 0);
            state
                .metrics
                .record_artifact_egress(producer, "error", 0, transfer_started_at.elapsed());
            Err(error)
        }
    }
}

fn record_usage(
    usage: Option<&Usage>,
    producer: ArtifactProducer,
    tenant_id: &str,
    namespace_id: &str,
    bytes: u64,
) {
    let Some(usage) = usage else {
        return;
    };
    usage.record_public_download(
        tenant_id,
        namespace_id,
        artifact_kind_for_usage(producer),
        bytes,
    );
}

fn record_analytics(
    analytics: Option<&Analytics>,
    producer: ArtifactProducer,
    tenant_id: &str,
    namespace_id: &str,
    key: Option<&str>,
    bytes: u64,
) {
    let (Some(analytics), Some(key)) = (analytics, key) else {
        return;
    };
    if namespace_id.is_empty() {
        return;
    }
    match producer {
        ArtifactProducer::Xcode => {
            analytics.enqueue_xcode_download(tenant_id, namespace_id, key, bytes)
        }
        ArtifactProducer::Gradle => {
            analytics.enqueue_gradle_download(tenant_id, namespace_id, key, bytes)
        }
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

fn artifact_request(target: &str, tenant_id: &str) -> Option<ArtifactRequest> {
    let (path, query) = target.split_once('?').unwrap_or((target, ""));
    let params = parse_query_map(query);
    if let Some(hash) = one_segment_after(path, "/v1/cache/") {
        return Some(ArtifactRequest {
            producer: ArtifactProducer::Nx,
            tenant_id: "default".to_owned(),
            namespace_id: NX_NAMESPACE_ID.to_owned(),
            key: hash.to_owned(),
            analytics_key: None,
            artifact_hash: Some(hash.to_owned()),
            route: "/v1/cache/{hash}",
            path: path.to_owned(),
            query: params,
        });
    }
    if let Some(cache_key) = one_segment_after(path, "/api/metro/cache/") {
        return Some(ArtifactRequest {
            producer: ArtifactProducer::Metro,
            tenant_id: "default".to_owned(),
            namespace_id: METRO_NAMESPACE_ID.to_owned(),
            key: cache_key.to_owned(),
            analytics_key: None,
            artifact_hash: Some(cache_key.to_owned()),
            route: "/api/metro/cache/{cache_key}",
            path: path.to_owned(),
            query: params,
        });
    }
    if let Some(id) = one_segment_after(path, "/api/cache/cas/") {
        let (request_tenant_id, namespace_id) = namespace_from_params(&params, tenant_id)?;
        return Some(ArtifactRequest {
            producer: ArtifactProducer::Xcode,
            tenant_id: request_tenant_id,
            namespace_id,
            key: blob_key(id),
            analytics_key: Some(id.to_owned()),
            artifact_hash: Some(id.to_owned()),
            route: "/api/cache/cas/{id}",
            path: path.to_owned(),
            query: params,
        });
    }
    if let Some(cache_key) = one_segment_after(path, "/api/cache/gradle/") {
        let (request_tenant_id, namespace_id) = namespace_from_params(&params, tenant_id)?;
        return Some(ArtifactRequest {
            producer: ArtifactProducer::Gradle,
            tenant_id: request_tenant_id,
            namespace_id,
            key: cache_key.to_owned(),
            analytics_key: Some(cache_key.to_owned()),
            artifact_hash: Some(cache_key.to_owned()),
            route: "/api/cache/gradle/{cache_key}",
            path: path.to_owned(),
            query: params,
        });
    }
    if one_segment_after(path, "/api/cache/module/").is_some() {
        let (request_tenant_id, namespace_id) = namespace_from_params(&params, tenant_id)?;
        let category = params
            .get("cache_category")
            .cloned()
            .unwrap_or_else(|| "builds".to_owned());
        let hash = non_empty_param(&params, "hash")?;
        let name = non_empty_param(&params, "name")?;
        return Some(ArtifactRequest {
            producer: ArtifactProducer::Module,
            tenant_id: request_tenant_id,
            namespace_id,
            key: module_key(&category, hash, name),
            analytics_key: None,
            artifact_hash: Some(hash.to_owned()),
            route: "/api/cache/module/{id}",
            path: path.to_owned(),
            query: params,
        });
    }
    None
}

fn extension_context(
    state: &SharedState,
    parsed: &ParsedRequest,
    artifact: &ArtifactRequest,
    status_code: Option<u16>,
) -> ExtensionContext {
    ExtensionContext {
        transport: "http".into(),
        route: artifact.route.to_owned(),
        method: parsed.method.clone(),
        operation: "artifact.read".into(),
        server_tenant_id: state.config.tenant_id.clone(),
        tenant_id: Some(artifact.tenant_id.clone()),
        namespace_id: if artifact.namespace_id.is_empty() {
            None
        } else {
            Some(artifact.namespace_id.clone())
        },
        producer: Some(artifact.producer.as_str().to_owned()),
        artifact_key: Some(artifact.key.clone()),
        artifact_hash: artifact.artifact_hash.clone(),
        headers: parsed.headers.clone(),
        query: artifact.query.clone(),
        status_code,
    }
}

fn one_segment_after<'a>(path: &'a str, prefix: &str) -> Option<&'a str> {
    path.strip_prefix(prefix)
        .filter(|segment| !segment.is_empty() && !segment.contains('/'))
}

fn namespace_from_params(
    params: &BTreeMap<String, String>,
    tenant_id: &str,
) -> Option<(String, String)> {
    let request_tenant_id = param_with_aliases(params, "tenant_id", &["account_handle"])?;
    if request_tenant_id != tenant_id {
        return None;
    }
    Some((
        request_tenant_id.clone(),
        param_with_aliases(params, "namespace_id", &["project_handle"])
            .cloned()
            .unwrap_or_else(|| TENANT_SCOPE_NAMESPACE_ID.to_owned()),
    ))
}

fn non_empty_param<'a>(params: &'a BTreeMap<String, String>, key: &str) -> Option<&'a String> {
    params.get(key).filter(|value| !value.is_empty())
}

fn param_with_aliases<'a>(
    params: &'a BTreeMap<String, String>,
    key: &str,
    aliases: &[&str],
) -> Option<&'a String> {
    params
        .get(key)
        .or_else(|| aliases.iter().find_map(|alias| params.get(*alias)))
        .filter(|value| !value.is_empty())
}

fn parse_query_map(query: &str) -> BTreeMap<String, String> {
    query
        .split('&')
        .filter(|pair| !pair.is_empty())
        .map(|pair| match pair.split_once('=') {
            Some((key, value)) => (key.to_owned(), value.to_owned()),
            None => (pair.to_owned(), String::new()),
        })
        .collect()
}

async fn write_response(
    stream: &mut TcpStream,
    status: u16,
    reason: &str,
    content_type: &str,
    headers: &BTreeMap<String, String>,
    body: &[u8],
) -> std::io::Result<()> {
    let mut response = Vec::new();
    write!(
        response,
        "HTTP/1.1 {status} {reason}\r\ncontent-length: {}\r\ncontent-type: {content_type}\r\nconnection: close\r\n",
        body.len()
    )?;
    append_headers(&mut response, headers)?;
    response.extend_from_slice(b"\r\n");
    response.extend_from_slice(body);
    stream.write_all(&response).await
}

fn write_headers(
    stream: &mut std::net::TcpStream,
    status: u16,
    reason: &str,
    content_type: &str,
    content_length: u64,
    headers: &BTreeMap<String, String>,
    keep_alive: bool,
) -> std::io::Result<()> {
    let connection = if keep_alive { "keep-alive" } else { "close" };
    write!(
        stream,
        "HTTP/1.1 {status} {reason}\r\ncontent-length: {content_length}\r\ncontent-type: {content_type}\r\nconnection: {connection}\r\n"
    )?;
    append_headers(stream, headers)?;
    stream.write_all(b"\r\n")
}

fn append_headers(
    output: &mut impl Write,
    headers: &BTreeMap<String, String>,
) -> std::io::Result<()> {
    for (name, value) in headers {
        if name.contains(['\r', '\n', ':']) || value.contains(['\r', '\n']) {
            continue;
        }
        write!(output, "{name}: {value}\r\n")?;
    }
    Ok(())
}

fn sanitized_content_type(content_type: &str) -> String {
    if axum::http::HeaderValue::from_str(content_type).is_ok() {
        content_type.to_owned()
    } else {
        "application/octet-stream".to_owned()
    }
}

fn reason_for_status(status: u16) -> &'static str {
    match status {
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        413 => "Payload Too Large",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        503 => "Service Unavailable",
        _ => "Error",
    }
}

#[cfg(target_os = "linux")]
fn transfer_file(
    stream: &mut std::net::TcpStream,
    file: &AcceleratedArtifactFile,
    mode: AcceleratedFileServingMode,
    chunk_bytes: usize,
) -> std::io::Result<u64> {
    match mode {
        AcceleratedFileServingMode::Sendfile => transfer_sendfile(stream, file, chunk_bytes),
        AcceleratedFileServingMode::Splice => transfer_splice(stream, file, chunk_bytes),
    }
}

#[cfg(not(target_os = "linux"))]
fn transfer_file(
    _stream: &mut std::net::TcpStream,
    _file: &AcceleratedArtifactFile,
    _mode: AcceleratedFileServingMode,
    _chunk_bytes: usize,
) -> std::io::Result<u64> {
    Err(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "accelerated file serving requires Linux",
    ))
}

#[cfg(target_os = "linux")]
fn transfer_sendfile(
    stream: &mut std::net::TcpStream,
    file: &AcceleratedArtifactFile,
    chunk_bytes: usize,
) -> std::io::Result<u64> {
    use std::os::fd::AsRawFd;

    let in_fd = file.handle.as_std().as_raw_fd();
    let out_fd = stream.as_raw_fd();
    let mut offset = file.offset as libc::off_t;
    let end = file.offset.saturating_add(file.size);
    let mut sent_total = 0_u64;
    while (offset as u64) < end {
        let remaining = end - offset as u64;
        let chunk = remaining.min(chunk_bytes as u64) as usize;
        let sent = unsafe { libc::sendfile(out_fd, in_fd, &mut offset, chunk) };
        if sent < 0 {
            let error = std::io::Error::last_os_error();
            if error.kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return Err(error);
        }
        if sent == 0 {
            break;
        }
        sent_total += sent as u64;
    }
    ensure_complete_transfer("sendfile", sent_total, file.size)
}

#[cfg(target_os = "linux")]
fn transfer_splice(
    stream: &mut std::net::TcpStream,
    file: &AcceleratedArtifactFile,
    chunk_bytes: usize,
) -> std::io::Result<u64> {
    use std::os::fd::AsRawFd;

    let in_fd = file.handle.as_std().as_raw_fd();
    let out_fd = stream.as_raw_fd();
    let mut pipe_fds = [0_i32; 2];
    if unsafe { libc::pipe(pipe_fds.as_mut_ptr()) } != 0 {
        return Err(std::io::Error::last_os_error());
    }

    let result = (|| {
        let mut offset = file.offset as libc::off_t;
        let end = file.offset.saturating_add(file.size);
        let mut sent_total = 0_u64;
        while (offset as u64) < end {
            let remaining = end - offset as u64;
            let chunk = remaining.min(chunk_bytes as u64) as usize;
            let spliced_in = unsafe {
                libc::splice(
                    in_fd,
                    &mut offset,
                    pipe_fds[1],
                    std::ptr::null_mut(),
                    chunk,
                    0,
                )
            };
            if spliced_in < 0 {
                let error = std::io::Error::last_os_error();
                if error.kind() == std::io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(error);
            }
            if spliced_in == 0 {
                break;
            }

            let mut pending = spliced_in as usize;
            while pending > 0 {
                let spliced_out = unsafe {
                    libc::splice(
                        pipe_fds[0],
                        std::ptr::null_mut(),
                        out_fd,
                        std::ptr::null_mut(),
                        pending,
                        0,
                    )
                };
                if spliced_out < 0 {
                    let error = std::io::Error::last_os_error();
                    if error.kind() == std::io::ErrorKind::Interrupted {
                        continue;
                    }
                    return Err(error);
                }
                if spliced_out == 0 {
                    break;
                }
                pending -= spliced_out as usize;
                sent_total += spliced_out as u64;
            }
        }
        ensure_complete_transfer("splice", sent_total, file.size)
    })();

    unsafe {
        libc::close(pipe_fds[0]);
        libc::close(pipe_fds[1]);
    }
    result
}

#[cfg(target_os = "linux")]
fn ensure_complete_transfer(operation: &str, sent: u64, expected: u64) -> std::io::Result<u64> {
    if sent == expected {
        Ok(sent)
    } else {
        Err(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            format!("{operation} transferred {sent} bytes but expected {expected}"),
        ))
    }
}

#[cfg(test)]
mod tests {
    use crate::artifact::producer::ArtifactProducer;

    use super::{
        ParsedRequest, artifact_request, parse_request, request_wants_keep_alive,
        sanitized_content_type,
    };

    fn parsed_with_headers(headers: &[(&str, &str)]) -> ParsedRequest {
        ParsedRequest {
            method: "GET".to_owned(),
            target: "/api/cache/cas/hash".to_owned(),
            version: 1,
            header_len: 0,
            headers: headers
                .iter()
                .map(|(name, value)| ((*name).to_owned(), (*value).to_owned()))
                .collect(),
        }
    }

    #[test]
    fn keep_alive_defaults_on_and_disables_for_close_or_unconsumed_body() {
        assert!(request_wants_keep_alive(&parsed_with_headers(&[(
            "host",
            "localhost"
        )])));
        assert!(request_wants_keep_alive(&parsed_with_headers(&[(
            "connection",
            "keep-alive"
        )])));
        assert!(request_wants_keep_alive(&parsed_with_headers(&[(
            "content-length",
            "0"
        )])));

        assert!(!request_wants_keep_alive(&parsed_with_headers(&[(
            "connection",
            "close"
        )])));
        assert!(!request_wants_keep_alive(&parsed_with_headers(&[(
            "connection",
            "keep-alive, close"
        )])));
        assert!(!request_wants_keep_alive(&parsed_with_headers(&[(
            "content-length",
            "10"
        )])));
        assert!(!request_wants_keep_alive(&parsed_with_headers(&[(
            "transfer-encoding",
            "chunked"
        )])));
    }

    #[test]
    fn parses_xcode_artifact_request() {
        let request = artifact_request(
            "/api/cache/cas/hash?account_handle=acme&project_handle=ios",
            "acme",
        )
        .expect("request should parse");

        assert_eq!(request.producer, ArtifactProducer::Xcode);
        assert_eq!(request.namespace_id, "ios");
        assert_eq!(request.key, "blob/hash");
        assert_eq!(request.artifact_hash.as_deref(), Some("hash"));
    }

    #[test]
    fn parses_module_artifact_request() {
        let request = artifact_request(
            "/api/cache/module/cache?tenant_id=acme&namespace_id=ios&cache_category=builds&hash=abc&name=App",
            "acme",
        )
        .expect("request should parse");

        assert_eq!(request.producer, ArtifactProducer::Module);
        assert_eq!(request.namespace_id, "ios");
        assert_eq!(request.key, "builds/abc/App");
        assert_eq!(request.artifact_hash.as_deref(), Some("abc"));
    }

    #[test]
    fn module_nx_and_metro_requests_carry_extension_artifact_hash() {
        let nx = artifact_request("/v1/cache/nx-hash", "acme").expect("nx request should parse");
        assert_eq!(nx.artifact_hash.as_deref(), Some("nx-hash"));

        let metro = artifact_request("/api/metro/cache/metro-key", "acme")
            .expect("metro request should parse");
        assert_eq!(metro.artifact_hash.as_deref(), Some("metro-key"));
    }

    #[test]
    fn sanitizes_content_type_with_unsafe_characters() {
        assert_eq!(sanitized_content_type("application/zip"), "application/zip");
        assert_eq!(
            sanitized_content_type("text/plain\r\nset-cookie: x=y"),
            "application/octet-stream"
        );
    }

    #[test]
    fn rejects_cross_tenant_requests() {
        assert!(artifact_request("/api/cache/gradle/cache?tenant_id=other", "acme").is_none());
    }

    #[test]
    fn parses_http_request_without_consuming_body() {
        let parsed = parse_request(
            b"GET /api/cache/cas/hash?tenant_id=acme HTTP/1.1\r\nHost: localhost\r\n\r\n",
        )
        .expect("request should parse")
        .expect("request should be complete");

        assert_eq!(parsed.method, "GET");
        assert_eq!(parsed.version, 1);
        assert_eq!(parsed.header_len, 68);
        assert_eq!(parsed.headers.get("host"), Some(&"localhost".to_owned()));
    }
}
