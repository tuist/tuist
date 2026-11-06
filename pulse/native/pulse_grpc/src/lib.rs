// Pulse OTLP/gRPC listener NIF.
//
// tonic owns the transport: HTTP/2, gRPC framing, gzip/zstd request
// decompression, message-size limits and keepalives. It never decodes
// OTLP: each `Export` call's raw protobuf message is handed to the owning
// BEAM process as a binary backed by the request buffer itself (no copy),
// together with a reply handle. The BEAM authorizes, decodes and stores
// the request through the same path as OTLP/HTTP, then answers through the
// handle. A handle the BEAM drops without answering (a crashed handler)
// completes the call as UNAVAILABLE, so exporters retry instead of hanging.
//
// One small multi-threaded tokio runtime serves every listener; the work
// it does is I/O and decompression only.

use bytes::{Buf, BufMut, Bytes};
use rustler::env::OwnedEnv;
use rustler::{Atom, Binary, Encoder, Env, LocalPid, ResourceArc, Term};
use std::convert::Infallible;
use std::future::Future;
use std::net::{IpAddr, SocketAddr};
use std::pin::Pin;
use std::str::FromStr;
use std::sync::{Arc, Mutex, OnceLock};
use std::task::{Context, Poll};
use std::time::Duration;
use tokio::runtime::Runtime;
use tokio::sync::{oneshot, OwnedSemaphorePermit, Semaphore};
use tokio_stream::StreamExt;
use tonic::body::Body;
use tonic::codec::{
    Codec, CompressionEncoding, DecodeBuf, Decoder, EncodeBuf, Encoder as MessageEncoder,
};
use tonic::server::{Grpc, NamedService};
use tonic::service::Routes;
use tonic::{Code, Status};

mod counting_alloc;

// Bytes this library currently holds on the native heap (see counting_alloc.rs).
#[rustler::nif]
fn native_allocated_bytes() -> i64 {
    counting_alloc::allocated()
}

mod atoms {
    rustler::atoms! { ok, error, logs, metrics, traces, pulse_otlp_grpc, pulse_otlp_grpc_admit, already_replied }
}

// Request metadata the BEAM needs for tenancy, authorization and retries.
const FORWARDED: [&str; 3] = ["authorization", "x-scope-orgid", "idempotency-key"];

fn runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("pulse-otlp-grpc")
            .enable_all()
            .build()
            .expect("tokio runtime for the OTLP/gRPC listener")
    })
}

#[derive(Clone, Copy)]
enum Signal {
    Logs,
    Metrics,
    Traces,
}

impl Signal {
    fn atom(self) -> Atom {
        match self {
            Signal::Logs => atoms::logs(),
            Signal::Metrics => atoms::metrics(),
            Signal::Traces => atoms::traces(),
        }
    }
}

struct Bridge {
    owner: LocalPid,
    permits: Arc<Semaphore>,
    max_message_bytes: usize,
    timeout: Duration,
}

// The raw request message, shared with the BEAM without copying.
struct Payload(Bytes);

#[rustler::resource_impl]
impl rustler::Resource for Payload {}

type Outcome = Result<Bytes, (i32, String, Bytes)>;

struct PendingReply {
    sender: oneshot::Sender<Outcome>,
    // A transport timeout/cancellation must not admit more outstanding BEAM work.
    // Admission replies hold none: the route keeps its permit while it waits.
    _permit: Option<OwnedSemaphorePermit>,
}

pub struct Reply(Mutex<Option<PendingReply>>);

#[rustler::resource_impl]
impl rustler::Resource for Reply {}

pub struct Listener {
    shutdown: Mutex<Option<oneshot::Sender<()>>>,
}

#[rustler::resource_impl]
impl rustler::Resource for Listener {}

impl Drop for Listener {
    fn drop(&mut self) {
        stop(self);
    }
}

fn stop(listener: &Listener) {
    if let Ok(mut guard) = listener.shutdown.lock() {
        if let Some(tx) = guard.take() {
            let _ = tx.send(());
        }
    }
}

// Messages pass through untouched in both directions.
#[derive(Clone, Copy, Default)]
struct RawCodec;

impl Codec for RawCodec {
    type Encode = Bytes;
    type Decode = Bytes;
    type Encoder = RawCodec;
    type Decoder = RawCodec;

    fn encoder(&mut self) -> RawCodec {
        RawCodec
    }

    fn decoder(&mut self) -> RawCodec {
        RawCodec
    }
}

impl MessageEncoder for RawCodec {
    type Item = Bytes;
    type Error = Status;

    fn encode(&mut self, item: Bytes, dst: &mut EncodeBuf<'_>) -> Result<(), Status> {
        dst.put(item);
        Ok(())
    }
}

impl Decoder for RawCodec {
    type Item = Bytes;
    type Error = Status;

    fn decode(&mut self, src: &mut DecodeBuf<'_>) -> Result<Option<Bytes>, Status> {
        Ok(Some(src.copy_to_bytes(src.remaining())))
    }
}

// One `Export` call: forward to the BEAM and await its answer.
struct Export {
    bridge: Arc<Bridge>,
    signal: Signal,
    permit: Option<OwnedSemaphorePermit>,
}

type BoxFuture<T> = Pin<Box<dyn Future<Output = T> + Send>>;

impl tower_service::Service<tonic::Request<Bytes>> for Export {
    type Response = tonic::Response<Bytes>;
    type Error = Status;
    type Future = BoxFuture<Result<tonic::Response<Bytes>, Status>>;

    fn poll_ready(&mut self, _cx: &mut Context<'_>) -> Poll<Result<(), Status>> {
        Poll::Ready(Ok(()))
    }

    fn call(&mut self, request: tonic::Request<Bytes>) -> Self::Future {
        let (bridge, signal) = (Arc::clone(&self.bridge), self.signal);
        let permit = self.permit.take().expect("one call per unary service");
        Box::pin(async move { forward(bridge, signal, request, permit).await })
    }
}

fn forwarded(metadata: &http::HeaderMap) -> Result<Vec<(String, String)>, Status> {
    let mut headers = Vec::new();
    for name in FORWARDED {
        for value in metadata.get_all(name).iter() {
            // Never turn malformed tenancy or idempotency into an omitted
            // header, or conceal an invalid duplicate from the shared receiver.
            let value = value
                .to_str()
                .map_err(|_| Status::invalid_argument("invalid forwarded text metadata"))?;
            headers.push((name.to_owned(), value.to_owned()));
        }
    }
    Ok(headers)
}

// Ask the BEAM to authorize the call from its metadata alone, before tonic
// buffers or decompresses the message, so unauthenticated callers cannot
// spend decompression work or message memory.
async fn admit(bridge: &Bridge, signal: Signal, metadata: &http::HeaderMap) -> Result<(), Status> {
    let headers = forwarded(metadata)?;
    let (tx, rx) = oneshot::channel();
    let reply = ResourceArc::new(Reply(Mutex::new(Some(PendingReply {
        sender: tx,
        _permit: None,
    }))));

    let mut env = OwnedEnv::new();
    let sent = env.send_and_clear(&bridge.owner, |env| {
        let headers: Vec<(&str, &str)> = headers
            .iter()
            .map(|(n, v)| (n.as_str(), v.as_str()))
            .collect();
        (
            atoms::pulse_otlp_grpc_admit(),
            reply.clone(),
            signal.atom(),
            headers,
        )
            .encode(env)
    });
    drop(reply);
    if sent.is_err() {
        return Err(Status::unavailable("ingest handler is not running"));
    }

    match rx.await {
        Ok(Ok(_)) => Ok(()),
        Ok(Err((code, message, details))) => {
            Err(Status::with_details(Code::from_i32(code), message, details))
        }
        Err(_) => Err(Status::unavailable("ingest handler exited")),
    }
}

async fn forward(
    bridge: Arc<Bridge>,
    signal: Signal,
    request: tonic::Request<Bytes>,
    permit: OwnedSemaphorePermit,
) -> Result<tonic::Response<Bytes>, Status> {
    let headers = forwarded(request.metadata().as_ref())?;
    let payload = ResourceArc::new(Payload(request.into_inner()));
    let (tx, rx) = oneshot::channel();
    let reply = ResourceArc::new(Reply(Mutex::new(Some(PendingReply {
        sender: tx,
        _permit: Some(permit),
    }))));

    let mut env = OwnedEnv::new();
    let sent = env.send_and_clear(&bridge.owner, |env| {
        let body = payload.make_binary(env, |p| &p.0[..]);
        let headers: Vec<(&str, &str)> = headers
            .iter()
            .map(|(n, v)| (n.as_str(), v.as_str()))
            .collect();
        (
            atoms::pulse_otlp_grpc(),
            reply.clone(),
            signal.atom(),
            headers,
            body,
        )
            .encode(env)
    });
    drop(reply);
    if sent.is_err() {
        return Err(Status::unavailable("ingest handler is not running"));
    }

    // The route owns the one end-to-end deadline. Once it stops waiting,
    // BEAM still owns the reply and admission until completion/drop.
    match rx.await {
        Ok(Ok(body)) => Ok(tonic::Response::new(body)),
        Ok(Err((code, message, details))) => {
            Err(Status::with_details(Code::from_i32(code), message, details))
        }
        Err(_) => Err(Status::unavailable("ingest handler exited")),
    }
}

async fn route(
    bridge: Arc<Bridge>,
    signal: Signal,
    service: &'static str,
    req: http::Request<Body>,
) -> Result<http::Response<Body>, Infallible> {
    // Cover waiting for admission and incomplete unary bodies too. Once
    // handed to BEAM, cancelling this future cannot release the reply-owned
    // permit: outstanding ingestion still owns it until reply/drop.
    match tokio::time::timeout(bridge.timeout, route_admitted(bridge, signal, service, req)).await {
        Ok(response) => response,
        Err(_) => Ok(Status::unavailable("ingest timed out").into_http()),
    }
}

async fn route_admitted(
    bridge: Arc<Bridge>,
    signal: Signal,
    service: &'static str,
    req: http::Request<Body>,
) -> Result<http::Response<Body>, Infallible> {
    if req
        .uri()
        .path()
        .strip_prefix('/')
        .and_then(|p| p.strip_prefix(service))
        != Some("/Export")
    {
        return Ok(Status::unimplemented("only Export is supported").into_http());
    }
    // Admit before tonic buffers/decompresses the message. Pending streams stay
    // under HTTP/2 flow control rather than retaining a complete decoded body.
    let permit = match Arc::clone(&bridge.permits).acquire_owned().await {
        Ok(permit) => permit,
        Err(_) => return Ok(Status::unavailable("listener is shutting down").into_http()),
    };
    if let Err(status) = admit(&bridge, signal, req.headers()).await {
        return Ok(status.into_http());
    }
    let mut grpc = Grpc::new(RawCodec)
        .accept_compressed(CompressionEncoding::Gzip)
        .accept_compressed(CompressionEncoding::Zstd)
        .send_compressed(CompressionEncoding::Gzip)
        .max_decoding_message_size(bridge.max_message_bytes);
    let mut response = grpc
        .unary(
            Export {
                bridge,
                signal,
                permit: Some(permit),
            },
            req,
        )
        .await;
    // tonic rejects oversized messages as OUT_OF_RANGE, which OTLP exporters
    // retry. Like gRPC's own servers, answer RESOURCE_EXHAUSTED without
    // RetryInfo: the same message can never succeed.
    let headers = response.headers_mut();
    if headers.get("grpc-status").is_some_and(|code| code == "11") {
        headers.insert("grpc-status", http::HeaderValue::from_static("8"));
    }
    Ok(response)
}

macro_rules! otlp_service {
    ($name:ident, $signal:expr, $path:literal) => {
        #[derive(Clone)]
        struct $name(Arc<Bridge>);

        impl NamedService for $name {
            const NAME: &'static str = $path;
        }

        impl tower_service::Service<http::Request<Body>> for $name {
            type Response = http::Response<Body>;
            type Error = Infallible;
            type Future = BoxFuture<Result<http::Response<Body>, Infallible>>;

            fn poll_ready(&mut self, _cx: &mut Context<'_>) -> Poll<Result<(), Infallible>> {
                Poll::Ready(Ok(()))
            }

            fn call(&mut self, req: http::Request<Body>) -> Self::Future {
                Box::pin(route(Arc::clone(&self.0), $signal, $path, req))
            }
        }
    };
}

otlp_service!(
    TraceService,
    Signal::Traces,
    "opentelemetry.proto.collector.trace.v1.TraceService"
);
otlp_service!(
    LogsService,
    Signal::Logs,
    "opentelemetry.proto.collector.logs.v1.LogsService"
);
otlp_service!(
    MetricsService,
    Signal::Metrics,
    "opentelemetry.proto.collector.metrics.v1.MetricsService"
);

#[rustler::nif]
fn otlp_grpc_api_version() -> u32 {
    // 3: every call is admitted from its metadata before the message is read.
    3
}

/// Bind `ip:port` (port 0 picks one) and serve until stopped or until the
/// returned listener resource is garbage collected. Requests are sent to
/// `owner`. Returns `{:ok, listener, bound_port}` or `{:error, reason}`.
#[rustler::nif]
fn otlp_grpc_start<'a>(
    env: Env<'a>,
    ip: &str,
    port: u16,
    owner: LocalPid,
    max_message_bytes: usize,
    max_in_flight: usize,
    timeout_ms: u64,
) -> Term<'a> {
    let start = || -> Result<(ResourceArc<Listener>, u16), String> {
        if max_message_bytes == 0 || max_in_flight == 0 || timeout_ms == 0 {
            return Err("limits must be positive".into());
        }
        let ip = IpAddr::from_str(ip).map_err(|e| e.to_string())?;
        let std_listener =
            std::net::TcpListener::bind(SocketAddr::new(ip, port)).map_err(|e| e.to_string())?;
        std_listener
            .set_nonblocking(true)
            .map_err(|e| e.to_string())?;
        let bound = std_listener.local_addr().map_err(|e| e.to_string())?.port();
        let rt = runtime();
        let listener = {
            let _guard = rt.enter();
            tokio::net::TcpListener::from_std(std_listener).map_err(|e| e.to_string())?
        };
        let bridge = Arc::new(Bridge {
            owner,
            permits: Arc::new(Semaphore::new(max_in_flight)),
            max_message_bytes,
            timeout: Duration::from_millis(timeout_ms),
        });
        let routes = Routes::new(TraceService(Arc::clone(&bridge)))
            .add_service(LogsService(Arc::clone(&bridge)))
            .add_service(MetricsService(Arc::clone(&bridge)));
        let (shutdown, signal) = oneshot::channel::<()>();
        let incoming = tokio_stream::wrappers::TcpListenerStream::new(listener).map(|stream| {
            stream.inspect(|s| {
                let _ = s.set_nodelay(true);
            })
        });
        rt.spawn(async move {
            let _ = tonic::transport::Server::builder()
                .http2_keepalive_interval(Some(Duration::from_secs(30)))
                .http2_keepalive_timeout(Some(Duration::from_secs(10)))
                .add_routes(routes)
                .serve_with_incoming_shutdown(incoming, async {
                    let _ = signal.await;
                })
                .await;
        });
        Ok((
            ResourceArc::new(Listener {
                shutdown: Mutex::new(Some(shutdown)),
            }),
            bound,
        ))
    };
    match start() {
        Ok((listener, bound)) => (atoms::ok(), listener, bound).encode(env),
        Err(reason) => (atoms::error(), reason).encode(env),
    }
}

/// Stop accepting connections and finish in-flight calls.
#[rustler::nif]
fn otlp_grpc_stop(listener: ResourceArc<Listener>) -> Atom {
    stop(&listener);
    atoms::ok()
}

/// Answer one call: code 0 sends `body` as the response message; any other
/// gRPC status code fails the call with `message` and `body` as encoded
/// `google.rpc.Status` details (possibly empty).
#[rustler::nif]
fn otlp_grpc_reply<'a>(
    env: Env<'a>,
    reply: ResourceArc<Reply>,
    code: i32,
    message: String,
    body: Binary<'a>,
) -> Term<'a> {
    let sender = reply.0.lock().ok().and_then(|mut guard| guard.take());
    match sender {
        Some(pending) => {
            let bytes = Bytes::copy_from_slice(body.as_slice());
            let outcome = if code == 0 {
                Ok(bytes)
            } else {
                Err((code, message, bytes))
            };
            // A cancelled call has no receiver; the answer is moot.
            let _ = pending.sender.send(outcome);
            atoms::ok().encode(env)
        }
        None => (atoms::error(), atoms::already_replied()).encode(env),
    }
}

rustler::init!("Elixir.Pulse.OTLP.GRPC.NIF");
