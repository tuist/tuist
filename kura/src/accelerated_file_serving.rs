use std::{
    collections::BTreeMap,
    io::Write,
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
    rt::{TokioExecutor, TokioIo},
    server::conn::auto::Builder as HttpBuilder,
};
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    sync::{Semaphore, watch},
};
use tokio_rustls::TlsAcceptor;
use tower::ServiceExt;
use tracing::{Instrument, debug, info, warn};

use crate::{
    analytics::Analytics,
    artifact::{
        producer::ArtifactProducer,
        range::{RangeOutcome, RangeRequest, ServedRange, entity_tag, resolve_conditional_range},
    },
    auth::{AccessDecision, RequestContext},
    config::{AcceleratedFileServingConfig, AcceleratedFileServingMode},
    constants::response_stream_chunk_bytes,
    memory::{MemoryController, ResponseStreamAdmissionPatience},
    runtime::HttpTrafficClass,
    state::SharedState,
    store::AcceleratedArtifactFile,
    usage::Usage,
    utils::{blob_key, module_key},
};

const MAX_HEADER_BYTES: usize = 16 * 1024;
const HEADER_TIMEOUT: Duration = Duration::from_secs(30);
// A connection on the hyper fallback path is recycled after this age: the
// server sends GOAWAY (stop opening new streams) and gives in-flight streams
// the grace period to finish before the connection is severed. Without
// recycling, long-lived Bazel/Buck2 channels pin to a demoted-but-alive
// NodePort primary indefinitely after failover. The grace is generous because
// a single ByteStream write of a large blob legitimately runs for minutes;
// idle streams are reclaimed much sooner by REAPI_WRITE_STALL_TIMEOUT. Drain
// (shutdown) triggers the same graceful path immediately.
const CONNECTION_MAX_AGE: Duration = Duration::from_secs(300);
const CONNECTION_MAX_AGE_GRACE: Duration = Duration::from_secs(900);
const IO_TIMEOUT: Duration = Duration::from_secs(120);
const KEEP_ALIVE_IDLE_TIMEOUT: Duration = Duration::from_secs(60);
const TLS_HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);
const NX_NAMESPACE_ID: &str = "nx";
const METRO_NAMESPACE_ID: &str = "metro";
const TENANT_SCOPE_NAMESPACE_ID: &str = "";

// Applies each listener's HTTP/1 + HTTP/2 settings to the fallback hyper
// builder that serves everything the sendfile fast path does not. Passed in per
// listener so the co-hosted HTTP+gRPC port can advertise the fixed gRPC-sized
// HTTP/2 windows (so co-hosted REAPI uploads are not throttled) while the plain
// public port keeps its own tuning.
type Http2BuilderConfig = fn(&mut HttpBuilder<TokioExecutor>);

pub async fn serve_public_http(
    listener: TcpListener,
    router: Router,
    state: SharedState,
    config: AcceleratedFileServingConfig,
    mut shutdown_rx: watch::Receiver<bool>,
    configure_http2: Http2BuilderConfig,
) -> Result<(), String> {
    let semaphore = Arc::new(Semaphore::new(config.max_concurrent));
    let address = listener
        .local_addr()
        .map_err(|error| format!("failed to read public HTTP listener address: {error}"))?;
    if config.enabled {
        info!(
            mode = config.mode.as_str(),
            max_concurrent = config.max_concurrent,
            chunk_bytes = config.chunk_bytes,
            "Kura public HTTP listener using accelerated artifact serving on {address}"
        );
    } else {
        info!("Kura public HTTP listener on {address} (accelerated artifact serving disabled)");
    }

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
                // Unary REAPI calls (FindMissingBlobs, GetActionResult) are
                // small and latency-bound; Nagle + delayed ACK stalls them.
                if let Err(error) = stream.set_nodelay(true) {
                    tracing::debug!("failed to set TCP_NODELAY: {error}");
                }
                let accepted_at = tokio::time::Instant::now();
                let router = router.clone();
                let state = state.clone();
                let config = config.clone();
                let semaphore = semaphore.clone();
                let shutdown = shutdown_rx.clone();
                tokio::spawn(
                    async move {
                        if let Err(error) = serve_connection(stream, router, state, config, semaphore, configure_http2, accepted_at, shutdown).await {
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

#[allow(clippy::too_many_arguments)]
async fn serve_connection(
    mut stream: TcpStream,
    router: Router,
    state: SharedState,
    config: AcceleratedFileServingConfig,
    semaphore: Arc<Semaphore>,
    configure_http2: Http2BuilderConfig,
    accepted_at: tokio::time::Instant,
    mut shutdown: watch::Receiver<bool>,
) -> std::io::Result<()> {
    // With acceleration disabled every connection goes straight to the hyper
    // path, keeping the same nodelay/aging/drain semantics without peeking.
    if !config.enabled {
        return serve_hyper(stream, router, configure_http2, accepted_at, shutdown).await;
    }
    loop {
        // Bound the wait for the next request so idle keep-alive connections do
        // not pin a task and file descriptor forever, and close idle fast-path
        // connections promptly when the node drains.
        let classified = tokio::select! {
            classified = tokio::time::timeout(KEEP_ALIVE_IDLE_TIMEOUT, classify_route(&stream, &state)) => {
                match classified {
                    Ok(classified) => classified,
                    Err(_) => return Ok(()),
                }
            }
            _ = shutdown.changed() => return Ok(()),
        };

        // Match the route from a non-destructive peek before doing any access or
        // store work. Anything that is not an accelerable artifact GET, including
        // a pipelined follow-up on a reused connection, or anything that arrives
        // once the accelerator is at capacity, falls through to the normal
        // Axum/Hyper path before request bytes are consumed and without
        // re-evaluating access twice. The peek does not consume bytes, so Hyper
        // re-reads the request from the start.
        let Some((parsed, artifact)) = classified else {
            return serve_hyper(stream, router, configure_http2, accepted_at, shutdown).await;
        };
        let keep_alive = request_wants_keep_alive(&parsed);
        let request_started_at = Instant::now();
        let Ok(permit) = semaphore.clone().try_acquire_owned() else {
            return serve_hyper(stream, router, configure_http2, accepted_at, shutdown).await;
        };
        match open_and_authorize(&state, parsed, artifact).await {
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
                    // Stop reusing the connection once the node is draining;
                    // the response just written completes the in-flight work.
                    Some(reused) if !*shutdown.borrow() => {
                        stream = reused;
                        continue;
                    }
                    _ => return Ok(()),
                }
            }
            ClassifiedRequest::Deny(denial) => {
                drop(permit);
                consume_headers(&mut stream, denial.header_len).await?;
                // The JSON body from main, with this denial's own headers: a
                // 416 has to carry `Content-Range` so the client learns the
                // artifact's real length rather than guessing at a new range.
                let body = json_error_body(&denial.body);
                let result = write_response(
                    &mut stream,
                    denial.status,
                    denial.reason,
                    JSON_CONTENT_TYPE,
                    &denial.headers,
                    body.as_bytes(),
                )
                .await;
                state.metrics.record_http(
                    denial.route.to_owned(),
                    StatusCode::from_u16(denial.status)
                        .unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
                    Duration::ZERO,
                );
                return result;
            }
            ClassifiedRequest::Fallback => {
                drop(permit);
                return serve_hyper(stream, router, configure_http2, accepted_at, shutdown).await;
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

async fn serve_hyper<I>(
    stream: I,
    router: Router,
    configure_http2: Http2BuilderConfig,
    accepted_at: tokio::time::Instant,
    mut shutdown: watch::Receiver<bool>,
) -> std::io::Result<()>
where
    I: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let mut builder = HttpBuilder::new(TokioExecutor::new());
    configure_http2(&mut builder);
    let service = service_fn(move |request: Request<Incoming>| {
        let router = router.clone();
        async move {
            router
                .oneshot(request.map(Body::new))
                .await
                .map_err(std::io::Error::other)
        }
    });
    let connection = builder.serve_connection(TokioIo::new(stream), service);
    let mut connection = std::pin::pin!(connection);

    // Serve until the connection ends on its own, ages out, or the node
    // starts draining — the latter two recycle it gracefully: GOAWAY for
    // HTTP/2 (gRPC channels finish in-flight streams and reconnect
    // elsewhere), keep-alive off for HTTP/1.
    if !*shutdown.borrow() {
        tokio::select! {
            result = connection.as_mut() => return result.map_err(std::io::Error::other),
            _ = tokio::time::sleep_until(accepted_at + CONNECTION_MAX_AGE) => {}
            _ = shutdown.changed() => {}
        }
    }
    connection.as_mut().graceful_shutdown();
    match tokio::time::timeout(CONNECTION_MAX_AGE_GRACE, connection).await {
        Ok(result) => result.map_err(std::io::Error::other),
        // Grace expired with streams still open; dropping the connection
        // severs it.
        Err(_) => Ok(()),
    }
}

// The TLS twin of `serve_public_http`: same accept loop, same per-connection
// hyper serving (nodelay, connection aging, drain GOAWAY), with a rustls
// handshake in between. TLS is incompatible with the sendfile accelerator, so
// every connection takes the hyper path directly.
pub async fn serve_public_tls(
    listener: TcpListener,
    router: Router,
    tls_config: Arc<rustls::ServerConfig>,
    mut shutdown_rx: watch::Receiver<bool>,
    configure_http2: Http2BuilderConfig,
) -> Result<(), String> {
    let acceptor = TlsAcceptor::from(tls_config);
    let address = listener
        .local_addr()
        .map_err(|error| format!("failed to read public HTTPS listener address: {error}"))?;
    info!("Kura public HTTPS listener on {address}");

    loop {
        tokio::select! {
            result = listener.accept() => {
                let (stream, _) = match result {
                    Ok(stream) => stream,
                    Err(error) => {
                        tracing::warn!("public HTTPS accept failed: {error}");
                        continue;
                    }
                };
                if let Err(error) = stream.set_nodelay(true) {
                    tracing::debug!("failed to set TCP_NODELAY: {error}");
                }
                let accepted_at = tokio::time::Instant::now();
                let acceptor = acceptor.clone();
                let router = router.clone();
                let shutdown = shutdown_rx.clone();
                tokio::spawn(
                    async move {
                        let stream = match tokio::time::timeout(
                            TLS_HANDSHAKE_TIMEOUT,
                            acceptor.accept(stream),
                        )
                        .await
                        {
                            Ok(Ok(stream)) => stream,
                            Ok(Err(error)) => {
                                tracing::debug!("public TLS handshake failed: {error}");
                                return;
                            }
                            Err(_) => {
                                tracing::debug!("public TLS handshake timed out");
                                return;
                            }
                        };
                        if let Err(error) =
                            serve_hyper(stream, router, configure_http2, accepted_at, shutdown)
                                .await
                        {
                            tracing::debug!("public HTTPS connection failed: {error}");
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
    headers: BTreeMap<String, String>,
    body: String,
}

struct AcceleratedCandidate {
    header_len: usize,
    artifact: ArtifactRequest,
    file: AcceleratedArtifactFile,
    range: ServedRange,
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

async fn open_and_authorize(
    state: &SharedState,
    parsed: ParsedRequest,
    artifact: ArtifactRequest,
) -> ClassifiedRequest {
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
    let access_context = request_context(state, &parsed, &artifact, None);
    if let Some(auth) = state.auth.as_ref() {
        match auth.evaluate_access(&access_context).await {
            AccessDecision::Allow => {}
            AccessDecision::Deny(deny) => {
                return ClassifiedRequest::Deny(Denial {
                    header_len: parsed.header_len,
                    route: artifact.route,
                    status: deny.status,
                    reason: reason_for_status(deny.status),
                    headers: BTreeMap::new(),
                    body: deny.message,
                });
            }
        }
    }

    // Resolved after access, so an unauthorized caller cannot learn an
    // artifact's size from a 416's `Content-Range`.
    let etag = entity_tag(file.version_ms, file.size);
    let range = match resolve_conditional_range(
        RangeRequest::new(
            parsed.headers.get("range").map(String::as_str),
            parsed.headers.get("if-range").map(String::as_str),
        ),
        &etag,
        file.size,
    ) {
        RangeOutcome::Full => ServedRange::full(file.size),
        RangeOutcome::Partial(range) => range,
        RangeOutcome::Unsatisfiable => {
            // Counted here rather than in the Deny branch, which only knows
            // about HTTP and would report this plane's 416s as an
            // `kura_http_requests_total` entry with no matching artifact read.
            // This is the plane that carries plain-HTTP artifact GETs on Linux,
            // so leaving it out would hide the 416s most likely to happen.
            state
                .metrics
                .record_artifact_read(artifact.producer, "range_not_satisfiable", 0);
            return ClassifiedRequest::Deny(Denial {
                header_len: parsed.header_len,
                route: artifact.route,
                status: 416,
                reason: reason_for_status(416),
                headers: BTreeMap::from([
                    ("accept-ranges".to_owned(), "bytes".to_owned()),
                    ("content-range".to_owned(), format!("bytes */{}", file.size)),
                ]),
                body: format!(
                    "Requested range is not satisfiable for a {}-byte artifact",
                    file.size
                ),
            });
        }
    };

    ClassifiedRequest::Accelerate(AcceleratedCandidate {
        header_len: parsed.header_len,
        artifact,
        file,
        range,
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
    let content_type = sanitized_content_type(&file.content_type);
    let mode = config.mode;
    let chunk_bytes = config.chunk_bytes;
    let memory = state.memory.clone();
    let metrics = state.metrics.clone();
    let range = candidate.range;
    // Sized from the bytes this response will actually send, not the whole
    // artifact: a resume asks for the tail it is missing and should reserve
    // only that, so it is admitted under a budget a full re-send would be
    // shed under.
    let response_stream_bytes = response_stream_chunk_bytes(range.length);
    let response_stream_permit = match memory
        .acquire_response_stream_memory(
            response_stream_bytes,
            "http",
            ResponseStreamAdmissionPatience::Blocking,
        )
        .await
    {
        Ok(permit) => permit,
        // Shedding for want of a response-stream permit is capacity
        // backpressure, not a fault: the node is healthy and the same request
        // succeeds once a permit frees. It is 429 so a 5xx on an artifact read
        // keeps meaning a real server fault (an unreachable auth backend, or a
        // transfer that failed for a reason other than the client going away).
        Err(_) => {
            let mut stream = stream;
            let headers = BTreeMap::from([(
                "retry-after".to_owned(),
                memory.response_stream_retry_after_seconds().to_string(),
            )]);
            let body = json_error_body(
                "The server is limiting concurrent artifact response streams; retry shortly",
            );
            write_response(
                &mut stream,
                429,
                "Too Many Requests",
                JSON_CONTENT_TYPE,
                &headers,
                body.as_bytes(),
            )
            .await?;
            state
                .metrics
                .record_capacity_shed(crate::metrics::shed_kind::RESPONSE_STREAM);
            state.metrics.record_http(
                route,
                StatusCode::TOO_MANY_REQUESTS,
                transfer_started_at.elapsed(),
            );
            return Ok(None);
        }
    };
    let artifact_size = file.size;
    let etag = entity_tag(file.version_ms, file.size);
    let result = tokio::task::spawn_blocking(
        move || -> Result<(std::net::TcpStream, u64, Duration), (u64, std::io::Error)> {
            let _response_stream_permit = response_stream_permit;
            let mut stream = stream.into_std().map_err(|error| (0, error))?;
            let mut setup = || -> std::io::Result<Duration> {
                stream.set_nonblocking(false)?;
                stream.set_write_timeout(Some(IO_TIMEOUT))?;
                let (status, reason) = range.status();
                write_headers(
                    &mut stream,
                    status,
                    reason,
                    &content_type,
                    range.length,
                    range.content_range(artifact_size).as_deref(),
                    Some(etag.as_str()),
                    keep_alive,
                )?;
                // Time to first byte is measured once the headers are on the
                // wire, before the body transfer, so large downloads do not
                // inflate the responsiveness signal.
                Ok(request_started_at.elapsed())
            };
            let time_to_first_byte = match setup() {
                Ok(time_to_first_byte) => time_to_first_byte,
                Err(error) => return Err((0, error)),
            };
            let mut cache_drop = AcceleratedReadCacheDrop::new(chunk_bytes, &file, range);
            // `sent` is written through even when the transfer fails, so a
            // response that dies mid-body still reports how much of the link
            // it consumed for nothing.
            let mut sent = 0_u64;
            let transfer = transfer_file(
                &mut stream,
                &file,
                mode,
                chunk_bytes,
                range,
                &memory,
                &mut cache_drop,
                &mut sent,
            );
            cache_drop.finish(&file, &memory);
            cache_drop.record(&metrics);
            match transfer {
                Ok(()) => Ok((stream, sent, time_to_first_byte)),
                Err(error) => Err((sent, error)),
            }
        },
    )
    .await
    .map_err(std::io::Error::other)?;

    match result {
        Ok((std_stream, bytes, time_to_first_byte)) => {
            state.metrics.record_artifact_serving_path("accelerated");
            state.runtime.record_public_request_latency(
                &state.metrics,
                "http",
                &route,
                time_to_first_byte,
            );
            state.metrics.record_http(
                route,
                StatusCode::from_u16(range.status().0).unwrap_or(StatusCode::OK),
                time_to_first_byte,
            );
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
        Err((bytes, error)) => {
            let failure = TransferFailure::classify(&error);
            if failure == TransferFailure::ClientAborted {
                debug!(route = %route, wasted_bytes = bytes, "artifact transfer aborted by client: {error}");
            } else {
                warn!(
                    route = %route,
                    result = failure.result(),
                    wasted_bytes = bytes,
                    "artifact transfer failed: {error}"
                );
            }
            state
                .metrics
                .record_http(route, failure.status(), transfer_started_at.elapsed());
            // Carrying the byte count onto the failure result is what makes the
            // waste measurable: `kura_artifact_egress_bytes_total` split by
            // `result` separates link capacity that delivered an artifact from
            // capacity spent on a transfer the client threw away and will ask
            // for again. Usage and analytics stay unrecorded, so the tenant
            // is not billed for bytes that never landed.
            state
                .metrics
                .record_artifact_read(producer, failure.result(), bytes);
            state.metrics.record_artifact_egress(
                producer,
                failure.result(),
                bytes,
                transfer_started_at.elapsed(),
            );
            Err(error)
        }
    }
}

struct AcceleratedReadCacheDrop {
    interval_bytes: u64,
    page_bytes: u64,
    // Where in the backing file this response's first byte lives, and how many
    // bytes follow it. A ranged response starts partway into the artifact, so
    // the pages it touches are offset from the artifact's own start and the
    // prefix it never reads must not be advised away.
    base_offset: u64,
    length: u64,
    advised_through: u64,
    sent_through: u64,
    next_advice_at: u64,
    pressure_active: bool,
    advised_bytes: u64,
    failed: bool,
}

impl AcceleratedReadCacheDrop {
    fn new(chunk_bytes: usize, file: &AcceleratedArtifactFile, range: ServedRange) -> Self {
        Self {
            interval_bytes: chunk_bytes.max(1) as u64,
            page_bytes: system_page_bytes(),
            base_offset: file.offset.saturating_add(range.start),
            length: range.length,
            advised_through: 0,
            sent_through: 0,
            next_advice_at: 0,
            pressure_active: false,
            advised_bytes: 0,
            failed: false,
        }
    }

    fn observe_progress(
        &mut self,
        file: &AcceleratedArtifactFile,
        memory: &MemoryController,
        sent_through: u64,
        finish: bool,
    ) {
        self.sent_through = self.sent_through.max(sent_through.min(self.length));
        if !memory.should_reclaim_file_cache() {
            self.pressure_active = false;
            self.advised_through = align_up(
                self.base_offset.saturating_add(self.sent_through),
                self.page_bytes,
            );
            self.next_advice_at = self.sent_through.saturating_add(self.interval_bytes);
            return;
        }
        if !self.pressure_active {
            self.pressure_active = true;
            // Skip the older prefix rather than walking an arbitrarily large
            // range while holding an accelerator permit. Those pages are the
            // first to age into the inactive list; the most recently touched
            // transfer window is what keeps the working set elevated.
            self.advised_through = align_up(
                self.base_offset
                    .saturating_add(self.sent_through.saturating_sub(self.interval_bytes)),
                self.page_bytes,
            );
            self.next_advice_at = self.sent_through.saturating_add(self.interval_bytes);
        } else if !finish && self.sent_through < self.next_advice_at {
            return;
        }

        let completed_through = align_down(
            self.base_offset.saturating_add(self.sent_through),
            self.page_bytes,
        );
        let bytes = completed_through.saturating_sub(self.advised_through);
        if bytes == 0 {
            return;
        }
        if let Err(error) = file.handle.drop_cached_pages(self.advised_through, bytes) {
            if !self.failed {
                tracing::warn!(
                    error = %error,
                    "failed to release accelerated read file cache under memory pressure"
                );
            }
            self.failed = true;
        } else {
            self.advised_bytes = self.advised_bytes.saturating_add(bytes);
        }
        self.advised_through = completed_through;
        self.next_advice_at = self.sent_through.saturating_add(self.interval_bytes);
    }

    fn finish(&mut self, file: &AcceleratedArtifactFile, memory: &MemoryController) {
        self.observe_progress(file, memory, self.sent_through, true);
    }

    fn record(&self, metrics: &crate::metrics::Metrics) {
        if self.advised_bytes > 0 {
            metrics.record_memory_action("accelerated_read_file_cache_drop");
            metrics
                .record_memory_action_bytes("accelerated_read_file_cache_drop", self.advised_bytes);
        }
        if self.failed {
            metrics.record_memory_action("accelerated_read_file_cache_drop_failed");
        }
    }
}

fn align_up(value: u64, alignment: u64) -> u64 {
    value
        .saturating_add(alignment.saturating_sub(1))
        .saturating_div(alignment)
        .saturating_mul(alignment)
}

fn align_down(value: u64, alignment: u64) -> u64 {
    value.saturating_div(alignment).saturating_mul(alignment)
}

fn system_page_bytes() -> u64 {
    static PAGE_BYTES: std::sync::OnceLock<u64> = std::sync::OnceLock::new();
    *PAGE_BYTES.get_or_init(|| {
        #[cfg(unix)]
        {
            let page_bytes = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
            if page_bytes > 0 {
                return page_bytes as u64;
            }
        }
        4096
    })
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

fn request_context(
    state: &SharedState,
    parsed: &ParsedRequest,
    artifact: &ArtifactRequest,
    status_code: Option<u16>,
) -> RequestContext {
    RequestContext {
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

#[allow(clippy::too_many_arguments)]
fn write_headers(
    stream: &mut std::net::TcpStream,
    status: u16,
    reason: &str,
    content_type: &str,
    content_length: u64,
    content_range: Option<&str>,
    etag: Option<&str>,
    keep_alive: bool,
) -> std::io::Result<()> {
    let connection = if keep_alive { "keep-alive" } else { "close" };
    // `accept-ranges` rides on the full response too: a client only knows it
    // may resume a download if the server said so before the download died.
    write!(
        stream,
        "HTTP/1.1 {status} {reason}\r\ncontent-length: {content_length}\r\ncontent-type: {content_type}\r\naccept-ranges: bytes\r\nconnection: {connection}\r\n"
    )?;
    if let Some(content_range) = content_range {
        write!(stream, "content-range: {content_range}\r\n")?;
    }
    // Paired with `accept-ranges`: the validator the client echoes in
    // `If-Range` so a resume can be refused when the artifact moved on.
    if let Some(etag) = etag {
        write!(stream, "etag: {etag}\r\n")?;
    }
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

/// The accelerated path answers the same routes as the Axum handlers, so its
/// errors have to be the same bytes: the published contract declares
/// `application/json` for them, and a generated client rejects a mismatched
/// content type before it can decode the status into its typed case. A shed
/// answered as `text/plain` here reached clients as an undecodable response
/// rather than as backpressure.
const JSON_CONTENT_TYPE: &str = "application/json";

/// Mirrors `error_response` in `http.rs`: `{"message": "..."}`.
fn json_error_body(message: &str) -> String {
    serde_json::json!({ "message": message }).to_string()
}

fn reason_for_status(status: u16) -> &'static str {
    match status {
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        413 => "Payload Too Large",
        416 => "Range Not Satisfiable",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        503 => "Service Unavailable",
        _ => "Error",
    }
}

#[allow(clippy::too_many_arguments)]
#[cfg(target_os = "linux")]
fn transfer_file(
    stream: &mut std::net::TcpStream,
    file: &AcceleratedArtifactFile,
    mode: AcceleratedFileServingMode,
    chunk_bytes: usize,
    range: ServedRange,
    memory: &MemoryController,
    cache_drop: &mut AcceleratedReadCacheDrop,
    sent: &mut u64,
) -> std::io::Result<()> {
    match mode {
        AcceleratedFileServingMode::Sendfile => {
            transfer_sendfile(stream, file, chunk_bytes, range, memory, cache_drop, sent)
        }
        AcceleratedFileServingMode::Splice => {
            transfer_splice(stream, file, chunk_bytes, range, memory, cache_drop, sent)
        }
    }
}

#[allow(clippy::too_many_arguments)]
#[cfg(not(target_os = "linux"))]
fn transfer_file(
    _stream: &mut std::net::TcpStream,
    _file: &AcceleratedArtifactFile,
    _mode: AcceleratedFileServingMode,
    _chunk_bytes: usize,
    _range: ServedRange,
    _memory: &MemoryController,
    _cache_drop: &mut AcceleratedReadCacheDrop,
    _sent: &mut u64,
) -> std::io::Result<()> {
    Err(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "accelerated file serving requires Linux",
    ))
}

#[allow(clippy::too_many_arguments)]
#[cfg(target_os = "linux")]
fn transfer_sendfile(
    stream: &mut std::net::TcpStream,
    file: &AcceleratedArtifactFile,
    chunk_bytes: usize,
    range: ServedRange,
    memory: &MemoryController,
    cache_drop: &mut AcceleratedReadCacheDrop,
    sent_total: &mut u64,
) -> std::io::Result<()> {
    use std::os::fd::AsRawFd;

    let in_fd = file.handle.as_std().as_raw_fd();
    let out_fd = stream.as_raw_fd();
    let start = file.offset.saturating_add(range.start);
    let mut offset = start as libc::off_t;
    let end = start.saturating_add(range.length);
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
        // Unlike the splice counterpart below, a zero here is the input file
        // hitting EOF: the destination is a blocking socket, so it would move a
        // byte, park, or fail rather than accept nothing. Breaking to
        // `ensure_complete_transfer` reports the short file, which is right.
        if sent == 0 {
            break;
        }
        *sent_total += sent as u64;
        cache_drop.observe_progress(file, memory, *sent_total, false);
    }
    ensure_complete_transfer("sendfile", *sent_total, range.length)
}

#[allow(clippy::too_many_arguments)]
#[cfg(target_os = "linux")]
fn transfer_splice(
    stream: &mut std::net::TcpStream,
    file: &AcceleratedArtifactFile,
    chunk_bytes: usize,
    range: ServedRange,
    memory: &MemoryController,
    cache_drop: &mut AcceleratedReadCacheDrop,
    sent_total: &mut u64,
) -> std::io::Result<()> {
    use std::os::fd::AsRawFd;

    let in_fd = file.handle.as_std().as_raw_fd();
    let out_fd = stream.as_raw_fd();
    let mut pipe_fds = [0_i32; 2];
    if unsafe { libc::pipe(pipe_fds.as_mut_ptr()) } != 0 {
        return Err(std::io::Error::last_os_error());
    }

    let result = (|| {
        let start = file.offset.saturating_add(range.start);
        let mut offset = start as libc::off_t;
        let end = start.saturating_add(range.length);
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
                // Zero out of the pipe means the socket will take nothing more,
                // which is the peer going away rather than the input running
                // short. Saying so keeps it out of `ensure_complete_transfer`,
                // whose UnexpectedEof is reserved for a file that disagrees
                // with the record describing it. The pipe provably holds
                // `pending` bytes and the socket is blocking, so the kernel
                // should move a byte, park, or fail: this is not expected to be
                // reachable, hence the message, which separates it from an
                // ordinary peer reset once both are classified as aborts.
                if spliced_out == 0 {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::ConnectionAborted,
                        "splice to socket returned 0",
                    ));
                }
                pending -= spliced_out as usize;
                *sent_total += spliced_out as u64;
            }
            cache_drop.observe_progress(file, memory, *sent_total, false);
        }
        ensure_complete_transfer("splice", *sent_total, range.length)
    })();

    unsafe {
        libc::close(pipe_fds[0]);
        libc::close(pipe_fds[1]);
    }
    result
}

// The status recorded for a body the peer stopped reading. Borrowed from
// nginx so it reads the same way in dashboards, and deliberately not a 5xx:
// the response line already went out as 200, and a client that hung up is not
// a server fault. It exists only in metrics; nothing writes it to the wire.
const CLIENT_CLOSED_REQUEST: u16 = 499;

/// Why an in-flight accelerated transfer ended early.
///
/// `serve_accelerated` writes the `200 OK` response line before the body, so by
/// the time any of these happen the status is already committed. Classifying
/// them keeps a peer hanging up out of the server-error budget while leaving
/// the failures that are genuinely ours visible.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TransferFailure {
    /// The peer went away mid-body.
    ClientAborted,
    /// The socket accepted nothing for `IO_TIMEOUT`.
    WriteTimeout,
    /// The file yielded fewer bytes than the store's metadata promised, so the
    /// artifact on disk disagrees with the record describing it.
    Incomplete,
    Failed,
}

impl TransferFailure {
    fn classify(error: &std::io::Error) -> Self {
        match error.kind() {
            std::io::ErrorKind::BrokenPipe
            | std::io::ErrorKind::ConnectionReset
            | std::io::ErrorKind::ConnectionAborted => Self::ClientAborted,
            // A blocking socket carrying SO_SNDTIMEO reports the expired write
            // as EAGAIN, which maps to WouldBlock rather than TimedOut.
            std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut => Self::WriteTimeout,
            std::io::ErrorKind::UnexpectedEof => Self::Incomplete,
            _ => Self::Failed,
        }
    }

    fn status(self) -> StatusCode {
        match self {
            Self::ClientAborted => {
                StatusCode::from_u16(CLIENT_CLOSED_REQUEST).expect("499 is a valid status code")
            }
            Self::WriteTimeout | Self::Incomplete | Self::Failed => {
                StatusCode::INTERNAL_SERVER_ERROR
            }
        }
    }

    fn result(self) -> &'static str {
        match self {
            Self::ClientAborted => "client_aborted",
            Self::WriteTimeout => "write_timeout",
            Self::Incomplete => "incomplete",
            Self::Failed => "error",
        }
    }
}

/// Confirms a transfer moved every byte the response promised.
///
/// `expected` is the length of the range being served, not the artifact's
/// size, so a satisfied partial response is complete at its own last byte
/// while a file that runs short of the range still reports `UnexpectedEof`.
/// That keeps `Incomplete` meaning what it has always meant: the bytes on disk
/// disagree with the record describing them.
#[cfg(target_os = "linux")]
fn ensure_complete_transfer(operation: &str, sent: u64, expected: u64) -> std::io::Result<()> {
    if sent == expected {
        Ok(())
    } else {
        Err(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            format!("{operation} transferred {sent} bytes but expected {expected}"),
        ))
    }
}

#[cfg(test)]
mod tests {
    use std::{
        collections::BTreeMap,
        sync::Arc,
        time::{Duration, Instant},
    };

    use crate::artifact::producer::ArtifactProducer;
    use crate::{
        io::IoController,
        memory::{MemoryController, ResponseStreamAdmissionPatience},
        metrics::Metrics,
        store::AcceleratedArtifactFile,
    };
    use tempfile::tempdir;

    use crate::artifact::range::ServedRange;

    use super::{
        AcceleratedCandidate, AcceleratedReadCacheDrop, ArtifactRequest, ParsedRequest,
        TransferFailure, artifact_request, json_error_body, parse_request,
        request_wants_keep_alive, sanitized_content_type, serve_accelerated, system_page_bytes,
    };

    #[test]
    fn client_hangups_are_not_server_errors() {
        for kind in [
            std::io::ErrorKind::BrokenPipe,
            std::io::ErrorKind::ConnectionReset,
            std::io::ErrorKind::ConnectionAborted,
        ] {
            let failure = TransferFailure::classify(&std::io::Error::from(kind));
            assert_eq!(failure, TransferFailure::ClientAborted, "{kind:?}");
            assert_eq!(failure.result(), "client_aborted");
            assert!(
                !failure.status().is_server_error(),
                "{kind:?} must not be counted as a 5xx"
            );
            assert_eq!(failure.status().as_u16(), 499);
        }
    }

    #[test]
    fn write_stalls_and_short_transfers_stay_server_errors() {
        for kind in [std::io::ErrorKind::WouldBlock, std::io::ErrorKind::TimedOut] {
            let failure = TransferFailure::classify(&std::io::Error::from(kind));
            assert_eq!(failure, TransferFailure::WriteTimeout, "{kind:?}");
            assert_eq!(failure.result(), "write_timeout");
            assert!(failure.status().is_server_error(), "{kind:?}");
        }

        let incomplete = TransferFailure::classify(&std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "sendfile transferred 1 bytes but expected 2",
        ));
        assert_eq!(incomplete, TransferFailure::Incomplete);
        assert_eq!(incomplete.result(), "incomplete");
        assert!(incomplete.status().is_server_error());

        let other = TransferFailure::classify(&std::io::Error::other("disk fell over"));
        assert_eq!(other, TransferFailure::Failed);
        assert_eq!(other.result(), "error");
        assert!(other.status().is_server_error());
    }

    // Accelerated transfers are sendfile/splice, so the body path only exists on
    // Linux; off it `transfer_file` refuses up front and never reaches the peer.
    #[cfg(target_os = "linux")]
    #[tokio::test]
    async fn client_that_hangs_up_mid_transfer_is_not_recorded_as_a_5xx() {
        let context = crate::test_support::test_context(|_| {}).await;
        // Comfortably past the socket send buffer, so the transfer cannot land
        // entirely in kernel buffers before the peer is gone.
        let size = 64 * 1024 * 1024;
        let path = context.state.config.tmp_dir.join("aborted-artifact");
        let artifact = std::fs::File::create(&path).expect("create artifact");
        artifact.set_len(size).expect("size artifact");
        drop(artifact);
        let file = AcceleratedArtifactFile {
            handle: Arc::new(
                context
                    .state
                    .io
                    .open_persistent_read_file(&path)
                    .await
                    .expect("open accelerated artifact"),
            ),
            offset: 0,
            size,
            content_type: "application/octet-stream".into(),
            version_ms: 1,
        };
        let candidate = AcceleratedCandidate {
            header_len: 0,
            artifact: ArtifactRequest {
                producer: ArtifactProducer::Module,
                tenant_id: context.state.config.tenant_id.clone(),
                namespace_id: "ios".into(),
                key: "builds/hash/Module.framework".into(),
                analytics_key: None,
                artifact_hash: Some("hash".into()),
                route: "/api/cache/module/{id}",
                path: "/api/cache/module/hash".into(),
                query: BTreeMap::new(),
            },
            file,
            range: ServedRange::full(size),
        };

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let address = listener.local_addr().expect("test listener address");
        let client = tokio::net::TcpStream::connect(address)
            .await
            .expect("connect test client");
        let (server, _) = listener.accept().await.expect("accept test client");
        drop(client);

        let result = serve_accelerated(
            server,
            &context.state,
            &context.state.config.accelerated_file_serving,
            candidate,
            Instant::now(),
            false,
        )
        .await;
        assert!(result.is_err(), "aborted transfer should surface an error");

        let rendered = context.state.metrics.render();
        assert!(
            rendered.contains(r#"result="client_aborted""#),
            "expected a client_aborted artifact read, got:\n{rendered}"
        );
        assert!(
            !rendered.contains(r#"status="500""#),
            "client hangup must not be recorded as a 500, got:\n{rendered}"
        );
    }

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
    fn module_nx_and_metro_requests_carry_auth_artifact_hash() {
        let nx = artifact_request("/v1/cache/nx-hash", "acme").expect("nx request should parse");
        assert_eq!(nx.artifact_hash.as_deref(), Some("nx-hash"));

        let metro = artifact_request("/api/metro/cache/metro-key", "acme")
            .expect("metro request should parse");
        assert_eq!(metro.artifact_hash.as_deref(), Some("metro-key"));
    }

    #[test]
    fn error_bodies_match_the_axum_error_shape() {
        // Auth denials share this helper with the shed above, so both answer the
        // `application/json` the routes publish rather than the plain text the
        // accelerated path used to write.
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&json_error_body("nope"))
                .expect("body should be JSON"),
            serde_json::json!({ "message": "nope" })
        );
    }

    #[test]
    fn sanitizes_content_type_with_unsafe_characters() {
        assert_eq!(sanitized_content_type("application/zip"), "application/zip");
        assert_eq!(
            sanitized_content_type("text/plain\r\nset-cookie: x=y"),
            "application/octet-stream"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn accelerator_sends_retryable_error_before_success_when_memory_is_exhausted() {
        let context = crate::test_support::test_context(|_| {}).await;
        let response_pool_bytes = context
            .state
            .memory
            .foreground_response_streaming_pool_bytes();
        let pool_hog = context
            .state
            .memory
            .acquire_response_stream_memory(
                response_pool_bytes,
                "http",
                ResponseStreamAdmissionPatience::Blocking,
            )
            .await
            .expect("response pool should be available before the test");
        let elastic_pool_hog = context
            .state
            .memory
            .acquire_response_stream_memory(
                context
                    .state
                    .memory
                    .elastic_foreground_response_streaming_pool_bytes(),
                "http",
                ResponseStreamAdmissionPatience::Blocking,
            )
            .await
            .expect("elastic response pool should be available before the test");

        let path = context.state.config.tmp_dir.join("accelerated-artifact");
        std::fs::write(&path, b"artifact").expect("write accelerated artifact");
        let file = AcceleratedArtifactFile {
            handle: Arc::new(
                context
                    .state
                    .io
                    .open_persistent_read_file(&path)
                    .await
                    .expect("open accelerated artifact"),
            ),
            offset: 0,
            size: 8,
            content_type: "application/octet-stream".into(),
            version_ms: 1,
        };
        let range = ServedRange::full(file.size);
        let candidate = AcceleratedCandidate {
            header_len: 0,
            artifact: ArtifactRequest {
                producer: ArtifactProducer::Xcode,
                tenant_id: context.state.config.tenant_id.clone(),
                namespace_id: "ios".into(),
                key: "blob/hash".into(),
                analytics_key: None,
                artifact_hash: Some("hash".into()),
                route: "/api/cache/cas/{id}",
                path: "/api/cache/cas/hash".into(),
                query: BTreeMap::new(),
            },
            file,
            range,
        };
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let address = listener.local_addr().expect("test listener address");
        let mut client = tokio::net::TcpStream::connect(address)
            .await
            .expect("connect test client");
        let (server, _) = listener.accept().await.expect("accept test client");

        let reuse = serve_accelerated(
            server,
            &context.state,
            &context.state.config.accelerated_file_serving,
            candidate,
            Instant::now(),
            false,
        )
        .await
        .expect("accelerated response should complete");
        assert!(reuse.is_none());
        let mut response = Vec::new();
        tokio::io::AsyncReadExt::read_to_end(&mut client, &mut response)
            .await
            .expect("read accelerated response");
        let response = String::from_utf8(response).expect("response should be valid UTF-8");
        assert!(response.starts_with("HTTP/1.1 429 Too Many Requests\r\n"));
        // The published contract declares `application/json` for this status, and a
        // generated client checks the content type before it decodes the status, so
        // these bytes have to match what the Axum path writes.
        assert!(response.contains("content-type: application/json\r\n"));
        let body = response
            .split_once("\r\n\r\n")
            .expect("response should have a body")
            .1;
        let body: serde_json::Value = serde_json::from_str(body).expect("body should be JSON");
        assert_eq!(
            body,
            serde_json::json!({
                "message": "The server is limiting concurrent artifact response streams; retry shortly"
            })
        );
        let retry_after: u64 = response
            .lines()
            .find_map(|line| line.strip_prefix("retry-after: "))
            .expect("shed must be retryable")
            .trim()
            .parse()
            .expect("numeric retry-after");
        assert!(
            (crate::backpressure::MIN_RETRY_AFTER_SECONDS
                ..=crate::backpressure::SATURATED_RETRY_AFTER_CEILING_SECONDS)
                .contains(&retry_after),
            "retry-after {retry_after} outside the jittered window"
        );
        assert!(!response.contains("200 OK"));

        drop((elastic_pool_hog, pool_hog));
    }

    /// The sendfile/splice body path only exists on Linux, so the 206 wire
    /// format is asserted where it actually runs.
    #[cfg(target_os = "linux")]
    #[tokio::test]
    async fn an_accelerated_ranged_read_writes_a_206_and_only_the_requested_tail() {
        let context = crate::test_support::test_context(|_| {}).await;
        let path = context.state.config.tmp_dir.join("ranged-artifact");
        std::fs::write(&path, b"0123456789").expect("write accelerated artifact");
        let file = AcceleratedArtifactFile {
            handle: Arc::new(
                context
                    .state
                    .io
                    .open_persistent_read_file(&path)
                    .await
                    .expect("open accelerated artifact"),
            ),
            offset: 0,
            size: 10,
            content_type: "application/octet-stream".into(),
            version_ms: 1,
        };
        let crate::artifact::range::RangeOutcome::Partial(range) =
            crate::artifact::range::resolve_range(Some("bytes=6-"), file.size)
        else {
            panic!("expected a partial range");
        };
        let candidate = AcceleratedCandidate {
            header_len: 0,
            artifact: ArtifactRequest {
                producer: ArtifactProducer::Module,
                tenant_id: context.state.config.tenant_id.clone(),
                namespace_id: "ios".into(),
                key: "builds/hash/Module.framework".into(),
                analytics_key: None,
                artifact_hash: Some("hash".into()),
                route: "/api/cache/module/{id}",
                path: "/api/cache/module/hash".into(),
                query: BTreeMap::new(),
            },
            file,
            range,
        };

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let address = listener.local_addr().expect("test listener address");
        let mut client = tokio::net::TcpStream::connect(address)
            .await
            .expect("connect test client");
        let (server, _) = listener.accept().await.expect("accept test client");

        serve_accelerated(
            server,
            &context.state,
            &context.state.config.accelerated_file_serving,
            candidate,
            Instant::now(),
            false,
        )
        .await
        .expect("ranged accelerated transfer should succeed");

        let mut response = Vec::new();
        tokio::io::AsyncReadExt::read_to_end(&mut client, &mut response)
            .await
            .expect("read accelerated response");
        let response = String::from_utf8(response).expect("response should be valid UTF-8");
        assert!(
            response.starts_with("HTTP/1.1 206 Partial Content\r\n"),
            "got: {response}"
        );
        assert!(
            response.contains("content-range: bytes 6-9/10\r\n"),
            "got: {response}"
        );
        assert!(
            response.contains("content-length: 4\r\n"),
            "got: {response}"
        );
        assert!(
            response.contains("accept-ranges: bytes\r\n"),
            "got: {response}"
        );
        assert!(response.ends_with("\r\n\r\n6789"), "got: {response}");
    }

    /// A full accelerated response must still say resume is on offer, or a
    /// client has no reason to try one after a transfer dies.
    #[cfg(target_os = "linux")]
    #[tokio::test]
    async fn an_accelerated_full_read_advertises_accept_ranges_without_claiming_partial() {
        let context = crate::test_support::test_context(|_| {}).await;
        let path = context.state.config.tmp_dir.join("full-artifact");
        std::fs::write(&path, b"0123456789").expect("write accelerated artifact");
        let file = AcceleratedArtifactFile {
            handle: Arc::new(
                context
                    .state
                    .io
                    .open_persistent_read_file(&path)
                    .await
                    .expect("open accelerated artifact"),
            ),
            offset: 0,
            size: 10,
            content_type: "application/octet-stream".into(),
            version_ms: 1,
        };
        let range = ServedRange::full(file.size);
        let candidate = AcceleratedCandidate {
            header_len: 0,
            artifact: ArtifactRequest {
                producer: ArtifactProducer::Module,
                tenant_id: context.state.config.tenant_id.clone(),
                namespace_id: "ios".into(),
                key: "builds/hash/Module.framework".into(),
                analytics_key: None,
                artifact_hash: Some("hash".into()),
                route: "/api/cache/module/{id}",
                path: "/api/cache/module/hash".into(),
                query: BTreeMap::new(),
            },
            file,
            range,
        };

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let address = listener.local_addr().expect("test listener address");
        let mut client = tokio::net::TcpStream::connect(address)
            .await
            .expect("connect test client");
        let (server, _) = listener.accept().await.expect("accept test client");

        serve_accelerated(
            server,
            &context.state,
            &context.state.config.accelerated_file_serving,
            candidate,
            Instant::now(),
            false,
        )
        .await
        .expect("full accelerated transfer should succeed");

        let mut response = Vec::new();
        tokio::io::AsyncReadExt::read_to_end(&mut client, &mut response)
            .await
            .expect("read accelerated response");
        let response = String::from_utf8(response).expect("response should be valid UTF-8");
        assert!(
            response.starts_with("HTTP/1.1 200 OK\r\n"),
            "got: {response}"
        );
        assert!(
            response.contains("accept-ranges: bytes\r\n"),
            "got: {response}"
        );
        assert!(!response.contains("content-range:"), "got: {response}");
        assert!(response.ends_with("\r\n\r\n0123456789"), "got: {response}");
    }

    #[tokio::test]
    async fn accelerated_reads_release_file_cache_only_under_memory_pressure() {
        let directory = tempdir().expect("temporary directory");
        let path = directory.path().join("artifact");
        let size = system_page_bytes();
        let artifact = std::fs::File::create(&path).expect("create artifact");
        artifact.set_len(size).expect("size artifact");
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let io = IoController::new(
            metrics.clone(),
            4,
            Duration::from_secs(1),
            vec![directory.path().to_path_buf()],
        )
        .expect("create input-output controller");
        let file = AcceleratedArtifactFile {
            handle: Arc::new(
                io.open_persistent_read_file(&path)
                    .await
                    .expect("open artifact"),
            ),
            offset: 0,
            size,
            content_type: "application/octet-stream".into(),
            version_ms: 1,
        };
        let memory = MemoryController::new(metrics, 100, 200);

        let mut cache_drop =
            AcceleratedReadCacheDrop::new(1024 * 1024, &file, ServedRange::full(size));
        cache_drop.observe_progress(&file, &memory, file.size, false);
        assert_eq!(cache_drop.advised_bytes, 0);
        memory.observe(100);
        cache_drop.observe_progress(&file, &memory, file.size, false);
        assert_eq!(cache_drop.advised_bytes, size);
    }

    #[tokio::test]
    async fn accelerated_reads_release_file_cache_incrementally() {
        let directory = tempdir().expect("temporary directory");
        let path = directory.path().join("large-artifact");
        let chunk_bytes = 1024 * 1024;
        let size = 2 * chunk_bytes as u64;
        let offset = 100;
        let artifact = std::fs::File::create(&path).expect("create artifact");
        artifact.set_len(size + offset).expect("size artifact");
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let io = IoController::new(
            metrics.clone(),
            4,
            Duration::from_secs(1),
            vec![directory.path().to_path_buf()],
        )
        .expect("create input-output controller");
        let file = AcceleratedArtifactFile {
            handle: Arc::new(
                io.open_persistent_read_file(&path)
                    .await
                    .expect("open artifact"),
            ),
            offset,
            size,
            content_type: "application/octet-stream".into(),
            version_ms: 1,
        };
        let memory = MemoryController::new(metrics, 100, 200);
        memory.observe(100);
        let mut cache_drop =
            AcceleratedReadCacheDrop::new(chunk_bytes, &file, ServedRange::full(size));

        cache_drop.observe_progress(&file, &memory, chunk_bytes as u64, false);
        assert_eq!(
            cache_drop.advised_bytes,
            chunk_bytes as u64 - cache_drop.page_bytes
        );
        cache_drop.observe_progress(
            &file,
            &memory,
            chunk_bytes as u64 + cache_drop.page_bytes,
            false,
        );
        assert_eq!(
            cache_drop.advised_bytes,
            chunk_bytes as u64 - cache_drop.page_bytes
        );
        cache_drop.observe_progress(&file, &memory, size, false);
        assert_eq!(cache_drop.advised_bytes, size - cache_drop.page_bytes);
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

    #[tokio::test]
    async fn serve_hyper_recycles_connections_gracefully_on_drain() {
        use std::time::Duration;

        use axum::{
            Router,
            body::Body,
            http::{Request, StatusCode},
            routing::get,
        };
        use hyper_util::rt::{TokioExecutor, TokioIo};
        use tokio::sync::watch;

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let (shutdown_tx, shutdown_rx) = watch::channel(false);
        let router = Router::new().route("/ping", get(|| async { "pong" }));
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            super::serve_hyper(
                stream,
                router,
                |_| {},
                tokio::time::Instant::now(),
                shutdown_rx,
            )
            .await
        });

        // A raw HTTP/2 prior-knowledge client, the transport shape gRPC
        // channels use on the co-hosted plaintext port.
        let stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        let (mut send_request, connection) =
            hyper::client::conn::http2::handshake(TokioExecutor::new(), TokioIo::new(stream))
                .await
                .expect("h2c handshake");
        let client_connection = tokio::spawn(connection);

        let response = send_request
            .send_request(
                Request::builder()
                    .uri(format!("http://{addr}/ping"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .expect("request before drain succeeds");
        assert_eq!(response.status(), StatusCode::OK);

        shutdown_tx.send(true).unwrap();

        // Drain must recycle the connection gracefully: the server sends
        // GOAWAY and both ends resolve cleanly well within the grace period,
        // instead of the client hanging until the connection is severed.
        let server_result = tokio::time::timeout(Duration::from_secs(5), server)
            .await
            .expect("server connection should close after drain GOAWAY")
            .unwrap();
        assert!(
            server_result.is_ok(),
            "server side should close cleanly: {server_result:?}"
        );
        let client_result = tokio::time::timeout(Duration::from_secs(5), client_connection)
            .await
            .expect("client connection should observe the GOAWAY close")
            .unwrap();
        assert!(
            client_result.is_ok(),
            "client should see a clean GOAWAY close: {client_result:?}"
        );
    }
}
