//! HTTP/2 termination + forwarding for the TLS-terminating MITM path.
//!
//! Hyper handles the protocol mechanics; we own the per-stream
//! metadata capture and the upstream forwarding. One HTTP/2 connection
//! from the client maps to one HTTP/2 connection to the upstream; each
//! request stream the client opens is forwarded to a new request
//! stream on the upstream connection, and the response is streamed
//! back.
//!
//! We emit one pair of `request_opened` / `request_closed` events per
//! HTTP/2 stream so the BEAM sees each logical HTTP request as a
//! separate entity. Stream ids are generated as UUIDs at the time of
//! capture, mirroring the passthrough / HTTP/1 paths.

use crate::proxy::control::ControlChannel;
use crate::proxy::event::{Event, Kind, Request as EventRequest};
use bytes::Bytes;
use http_body_util::combinators::BoxBody;
use http_body_util::{BodyExt, Empty, Full};
use hyper::body::Incoming;
use hyper::service::service_fn;
use hyper::{Request, Response};
use hyper_util::rt::{TokioExecutor, TokioIo};
use std::sync::Arc;
use tokio_rustls::client::TlsStream as ClientTls;
use tokio_rustls::server::TlsStream as ServerTls;

type BoxError = Box<dyn std::error::Error + Send + Sync>;
type BoxedBody = BoxBody<Bytes, BoxError>;

/// Drive an HTTP/2 MITM connection.
///
/// hyper's HTTP/2 server `serve_connection` future is non-Send for
/// HRTB reasons: `&tokio::io::Registration` would have to be Send for
/// any lifetime, but the impl only provides Send for specific
/// lifetimes. That makes the future un-spawnable via `tokio::spawn`
/// from the multi-thread runtime that drives the outer accept loop.
///
/// We isolate the non-Send work to a dedicated thread with its own
/// current-thread runtime and a `LocalSet`. The caller's future stays
/// Send (it only awaits the `tokio::sync::oneshot` completion
/// channel). The cost is one OS thread per h2 connection, which is
/// acceptable given how few concurrent h2 connections a single
/// sandbox session opens.
pub async fn handle(
    client_tls: ServerTls<tokio::net::TcpStream>,
    upstream_tls: ClientTls<tokio::net::TcpStream>,
    control: Arc<ControlChannel>,
    base: EventRequest,
) -> Result<(), String> {
    let (done_tx, done_rx) = tokio::sync::oneshot::channel::<Result<(), String>>();

    std::thread::Builder::new()
        .name("condukt-egress-h2".into())
        .spawn(move || {
            let rt = match tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            {
                Ok(rt) => rt,
                Err(err) => {
                    let _ = done_tx.send(Err(format!("h2 thread rt: {err}")));
                    return;
                }
            };

            let local = tokio::task::LocalSet::new();
            let result = local.block_on(&rt, drive(client_tls, upstream_tls, control, base));
            let _ = done_tx.send(result);
        })
        .map_err(|e| format!("h2 thread spawn: {e}"))?;

    done_rx
        .await
        .map_err(|_| "h2 thread terminated without completing".to_string())?
}

async fn drive(
    client_tls: ServerTls<tokio::net::TcpStream>,
    upstream_tls: ClientTls<tokio::net::TcpStream>,
    control: Arc<ControlChannel>,
    base: EventRequest,
) -> Result<(), String> {
    let (sender, conn) =
        hyper::client::conn::http2::handshake(TokioExecutor::new(), TokioIo::new(upstream_tls))
            .await
            .map_err(|e| format!("upstream h2 handshake: {e}"))?;

    let sender = Arc::new(tokio::sync::Mutex::new(sender));

    tokio::task::spawn_local(async move {
        if let Err(err) = conn.await {
            eprintln!("condukt-egress h2: upstream driver: {err}");
        }
    });

    let service = service_fn(move |req: Request<Incoming>| {
        let sender = Arc::clone(&sender);
        let control = Arc::clone(&control);
        let base = base.clone();
        async move { Ok::<_, BoxError>(proxy_stream(req, sender, control, base).await) }
    });

    hyper::server::conn::http2::Builder::new(TokioExecutor::new())
        .serve_connection(TokioIo::new(client_tls), service)
        .await
        .map_err(|e| format!("client h2 serve: {e}"))?;

    Ok(())
}

async fn proxy_stream(
    req: Request<Incoming>,
    sender: Arc<tokio::sync::Mutex<hyper::client::conn::http2::SendRequest<BoxedBody>>>,
    control: Arc<ControlChannel>,
    base: EventRequest,
) -> Response<BoxedBody> {
    let mut event_req = base.clone();
    event_req.id = uuid::Uuid::new_v4().to_string();
    event_req.method = Some(req.method().to_string());
    event_req.path = Some(
        req.uri()
            .path_and_query()
            .map(|p| p.to_string())
            .unwrap_or_else(|| "/".to_string()),
    );
    event_req.request_headers = Some(
        req.headers()
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_str().unwrap_or("").to_string()))
            .collect(),
    );
    event_req.started_at = chrono::Utc::now();

    control.emit(Event::new(Kind::RequestOpened, event_req.clone()));

    let (parts, body) = req.into_parts();
    let body = body.map_err(|e| -> BoxError { Box::new(e) }).boxed();
    let outbound = Request::from_parts(parts, body);

    let mut guard = sender.lock().await;
    let result = guard.send_request(outbound).await;
    drop(guard);

    match result {
        Ok(upstream_resp) => {
            let mut closed = event_req;
            closed.response_status = Some(upstream_resp.status().as_u16() as i32);
            closed.finished_at = Some(chrono::Utc::now());
            control.emit(Event::new(Kind::RequestClosed, closed));

            let (parts, body) = upstream_resp.into_parts();
            let body = body.map_err(|e| -> BoxError { Box::new(e) }).boxed();
            Response::from_parts(parts, body)
        }
        Err(err) => {
            let mut closed = event_req;
            closed.finished_at = Some(chrono::Utc::now());
            let event = Event::new(Kind::RequestClosed, closed)
                .with_reason(format!("upstream_h2_send: {err}"));
            control.emit(event);
            error_response(format!("upstream send failed: {err}"))
        }
    }
}

fn error_response(message: String) -> Response<BoxedBody> {
    let body: BoxedBody = Full::new(Bytes::from(message))
        .map_err(|never| -> BoxError { match never {} })
        .boxed();

    Response::builder()
        .status(502)
        .body(body)
        .unwrap_or_else(|_| {
            Response::builder()
                .status(500)
                .body(empty_body())
                .expect("hard-coded response always builds")
        })
}

fn empty_body() -> BoxedBody {
    Empty::<Bytes>::new()
        .map_err(|never| -> BoxError { match never {} })
        .boxed()
}

#[cfg(test)]
mod tests {
    use super::*;
    use http_body_util::BodyExt;

    #[tokio::test]
    async fn error_response_is_502_carrying_the_message() {
        let resp = error_response("upstream blew up".into());
        assert_eq!(resp.status(), 502);

        let body = resp.into_body().collect().await.unwrap().to_bytes();
        assert_eq!(&body[..], b"upstream blew up");
    }

    #[tokio::test]
    async fn empty_body_yields_no_bytes() {
        let collected = empty_body().collect().await.unwrap().to_bytes();
        assert!(collected.is_empty());
    }
}
