//! Per-connection handling.
//!
//! Flow:
//!
//! 1. Accept a redirected TCP connection on the proxy's listen port.
//! 2. Recover the original destination via `SO_ORIGINAL_DST`.
//! 3. Peek the first bytes from the client to identify the hostname
//!    (TLS SNI for port 443, `Host:` header for port 80; falls back
//!    to the destination IP).
//! 4. Build a `Request`, evaluate it against the policy. On deny,
//!    emit `RequestDenied` and shutdown.
//! 5. On allow, MITM:
//!    - Port 443: TLS termination with the per-session CA, h2 or h1
//!      depending on ALPN. Method/path/headers + bytes captured into
//!      the event.
//!    - Port 80: cleartext h1 head capture + forward.
//!
//! A request that was allowed but never completed cleanly emits a
//! `RequestFailed` event carrying a failure label in `reason`
//! (`tls_client_rejected_ca`, `upstream_unreachable: ...`, etc.).
//! There is no byte-splice fallback: a workspace that doesn't trust
//! the session CA is a misconfiguration the operator must fix. The
//! K8s sandbox injects CA trust into the pod, so this should not
//! happen with a stock image.

use crate::proxy::control::ControlChannel;
use crate::proxy::event::{DecisionAction, Event, Kind, Request};
use crate::proxy::h2;
use crate::proxy::http1;
use crate::proxy::orig_dst;
use crate::proxy::policy::{Decision, Policy};
use crate::proxy::sni;
use crate::proxy::tls::CaContext;
use rustls::pki_types::ServerName;
use rustls::{ClientConfig, RootCertStore};
use std::sync::{Arc, OnceLock};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::{TlsAcceptor, TlsConnector};

pub async fn handle(
    mut client: TcpStream,
    policy: Arc<Policy>,
    control: Arc<ControlChannel>,
    ca: Arc<CaContext>,
    session_id: Option<String>,
) {
    let remote = client.peer_addr().ok();
    let dst = match orig_dst::original_dst(&client) {
        Ok(addr) => addr,
        Err(err) => {
            eprintln!("condukt-egress conn: SO_ORIGINAL_DST failed: {err}");
            return;
        }
    };

    let mut peek_buf = [0u8; 1024];
    let peeked = match client.peek(&mut peek_buf).await {
        Ok(n) => n,
        Err(err) => {
            eprintln!("condukt-egress conn: peek failed: {err}");
            return;
        }
    };
    let peeked_bytes = &peek_buf[..peeked];

    let host = identify_host(peeked_bytes, dst.port(), dst.ip().to_string());

    let mut request = Request::new(host.clone(), dst.port(), remote, session_id);
    request.scheme = if dst.port() == 443 {
        "https".into()
    } else {
        "http".into()
    };

    control.emit(Event::new(Kind::RequestOpened, request.clone()));

    let (decision, matched_rule) = policy.evaluate(&host);
    let denial_reason: Option<String> = match decision {
        Decision::Allow => None,
        Decision::Deny(reason) => Some(reason.as_str().to_string()),
        Decision::Decide => {
            let timeout = Duration::from_millis(policy.decide_timeout_ms);
            match control
                .request_decision(
                    request.id.clone(),
                    request.session_id.clone(),
                    host.clone(),
                    dst.port(),
                    request.scheme.clone(),
                    timeout,
                )
                .await
            {
                Some(d) if d.action == DecisionAction::Allow => None,
                Some(d) => Some(match d.reason {
                    Some(r) if !r.is_empty() => format!("decider: {r}"),
                    _ => "decider_deny".into(),
                }),
                None => Some("decider_timeout".into()),
            }
        }
    };

    if let Some(reason) = denial_reason {
        let mut event = Event::new(Kind::RequestDenied, request.clone()).with_reason(reason);
        if let Some(rule) = matched_rule.clone() {
            event = event.with_matched_rule(rule);
        }
        control.emit(event);
        let _ = client.shutdown().await;
        return;
    }

    let mut allowed = Event::new(Kind::RequestAllowed, request.clone());
    if let Some(rule) = matched_rule {
        allowed = allowed.with_matched_rule(rule);
    }
    control.emit(allowed);

    let outcome = if dst.port() == 443 {
        https_mitm(client, &host, dst, ca, &mut request, Arc::clone(&control)).await
    } else {
        http_forward(client, &host, dst, &mut request).await
    };

    match outcome {
        Ok(()) => {
            control.emit(Event::new(Kind::RequestClosed, request));
        }
        Err(err) => {
            let event = Event::new(Kind::RequestFailed, request).with_reason(err);
            control.emit(event);
        }
    }
}

fn identify_host(bytes: &[u8], port: u16, dst_ip: String) -> String {
    if port == 443 || sni::looks_like_tls(bytes) {
        sni::extract(bytes).unwrap_or(dst_ip)
    } else {
        parse_http_host(bytes).unwrap_or(dst_ip)
    }
}

fn parse_http_host(bytes: &[u8]) -> Option<String> {
    let text = std::str::from_utf8(bytes).ok()?;
    for line in text.lines() {
        if let Some(rest) = line
            .strip_prefix("Host:")
            .or_else(|| line.strip_prefix("host:"))
            .or_else(|| line.strip_prefix("HOST:"))
        {
            return Some(rest.trim().to_string());
        }
    }
    None
}

async fn https_mitm(
    client: TcpStream,
    host: &str,
    dst: std::net::SocketAddr,
    ca: Arc<CaContext>,
    request: &mut Request,
    control: Arc<ControlChannel>,
) -> Result<(), String> {
    let server_cfg = ca
        .server_config_for(host)
        .await
        .map_err(|e| format!("server_config: {e}"))?;
    let acceptor = TlsAcceptor::from(server_cfg);

    let tls_client = acceptor
        .accept(client)
        .await
        .map_err(|_| "tls_client_rejected_ca".to_string())?;

    let client_alpn = tls_client
        .get_ref()
        .1
        .alpn_protocol()
        .map(|p| p.to_vec())
        .unwrap_or_default();

    let connector = build_tls_connector().map_err(|e| format!("tls_connector: {e}"))?;
    let server_name = ServerName::try_from(host.to_string()).map_err(|e| format!("sni: {e}"))?;

    let upstream_tcp = TcpStream::connect(dst)
        .await
        .map_err(|e| format!("upstream_unreachable: {e}"))?;

    let tls_upstream = connector
        .connect(server_name, upstream_tcp)
        .await
        .map_err(|e| format!("upstream_tls: {e}"))?;

    let upstream_alpn = tls_upstream
        .get_ref()
        .1
        .alpn_protocol()
        .map(|p| p.to_vec())
        .unwrap_or_default();

    if client_alpn == b"h2" && upstream_alpn == b"h2" {
        return h2::handle(tls_client, tls_upstream, control, request.clone()).await;
    }

    https_h1(tls_client, tls_upstream, request).await
}

async fn https_h1(
    tls_client: tokio_rustls::server::TlsStream<TcpStream>,
    tls_upstream: tokio_rustls::client::TlsStream<TcpStream>,
    request: &mut Request,
) -> Result<(), String> {
    let (mut cr, mut cw) = tokio::io::split(tls_client);
    let (mut ur, mut uw) = tokio::io::split(tls_upstream);

    let mut head_buf = Vec::with_capacity(8 * 1024);
    let mut tmp = [0u8; 4096];

    let head = loop {
        let n = cr
            .read(&mut tmp)
            .await
            .map_err(|e| format!("read_head: {e}"))?;
        if n == 0 {
            break None;
        }
        head_buf.extend_from_slice(&tmp[..n]);
        match http1::parse(&head_buf) {
            Ok(Some(head)) => break Some(head),
            Ok(None) => continue,
            Err(_) => break None,
        }
    };

    if let Some(head) = head {
        request.method = Some(head.method);
        request.path = Some(head.path);
        request.request_headers = Some(head.headers);
    }

    uw.write_all(&head_buf)
        .await
        .map_err(|e| format!("forward_head: {e}"))?;

    let (bytes_in, bytes_out) = splice_pairs(&mut cr, &mut cw, &mut ur, &mut uw).await;
    request.bytes_out = head_buf.len() as u64 + bytes_out;
    request.bytes_in = bytes_in;
    request.finished_at = Some(chrono::Utc::now());
    Ok(())
}

async fn http_forward(
    client: TcpStream,
    _host: &str,
    dst: std::net::SocketAddr,
    request: &mut Request,
) -> Result<(), String> {
    let upstream = TcpStream::connect(dst)
        .await
        .map_err(|e| format!("upstream_unreachable: {e}"))?;

    let (mut cr, mut cw) = client.into_split();
    let (mut ur, mut uw) = upstream.into_split();

    let mut head_buf = Vec::with_capacity(8 * 1024);
    let mut tmp = [0u8; 4096];

    let head = loop {
        let n = cr
            .read(&mut tmp)
            .await
            .map_err(|e| format!("read_head: {e}"))?;
        if n == 0 {
            break None;
        }
        head_buf.extend_from_slice(&tmp[..n]);
        match http1::parse(&head_buf) {
            Ok(Some(head)) => break Some(head),
            Ok(None) => continue,
            Err(_) => break None,
        }
    };

    if let Some(head) = head {
        request.method = Some(head.method);
        request.path = Some(head.path);
        request.request_headers = Some(head.headers);
    }

    uw.write_all(&head_buf)
        .await
        .map_err(|e| format!("forward_head: {e}"))?;

    let (bytes_in, bytes_out) = splice_owned(&mut cr, &mut cw, &mut ur, &mut uw).await;
    request.bytes_out = head_buf.len() as u64 + bytes_out;
    request.bytes_in = bytes_in;
    request.finished_at = Some(chrono::Utc::now());
    Ok(())
}

async fn splice_pairs<C1, C2, U1, U2>(
    cr: &mut C1,
    cw: &mut C2,
    ur: &mut U1,
    uw: &mut U2,
) -> (u64, u64)
where
    C1: tokio::io::AsyncRead + Unpin,
    C2: tokio::io::AsyncWrite + Unpin,
    U1: tokio::io::AsyncRead + Unpin,
    U2: tokio::io::AsyncWrite + Unpin,
{
    let client_to_up = async {
        let mut buf = [0u8; 16 * 1024];
        let mut total = 0u64;
        loop {
            match cr.read(&mut buf).await {
                Ok(0) => break,
                Ok(n) => {
                    total += n as u64;
                    if uw.write_all(&buf[..n]).await.is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
        let _ = uw.shutdown().await;
        total
    };

    let up_to_client = async {
        let mut buf = [0u8; 16 * 1024];
        let mut total = 0u64;
        loop {
            match ur.read(&mut buf).await {
                Ok(0) => break,
                Ok(n) => {
                    total += n as u64;
                    if cw.write_all(&buf[..n]).await.is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
        let _ = cw.shutdown().await;
        total
    };

    tokio::join!(client_to_up, up_to_client)
}

async fn splice_owned(
    cr: &mut tokio::net::tcp::OwnedReadHalf,
    cw: &mut tokio::net::tcp::OwnedWriteHalf,
    ur: &mut tokio::net::tcp::OwnedReadHalf,
    uw: &mut tokio::net::tcp::OwnedWriteHalf,
) -> (u64, u64) {
    splice_pairs(cr, cw, ur, uw).await
}

fn build_tls_connector() -> Result<TlsConnector, String> {
    static CONFIG: OnceLock<Arc<ClientConfig>> = OnceLock::new();

    let cfg = CONFIG
        .get_or_init(|| {
            let mut roots = RootCertStore::empty();
            for cert in load_system_roots() {
                let _ = roots.add(cert);
            }
            let mut cfg = ClientConfig::builder()
                .with_root_certificates(roots)
                .with_no_client_auth();
            cfg.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];
            Arc::new(cfg)
        })
        .clone();
    Ok(TlsConnector::from(cfg))
}

fn load_system_roots() -> Vec<rustls::pki_types::CertificateDer<'static>> {
    let path = "/etc/ssl/certs/ca-certificates.crt";
    let Ok(bytes) = std::fs::read(path) else {
        return Vec::new();
    };
    let mut cursor = std::io::Cursor::new(bytes);
    let mut out = Vec::new();
    while let Ok(Some(item)) = rustls_pemfile::read_one(&mut cursor) {
        if let rustls_pemfile::Item::X509Certificate(der) = item {
            out.push(der);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_http_host_reads_the_host_header_case_insensitively() {
        let req = b"GET / HTTP/1.1\r\nHost: api.github.com\r\nAccept: */*\r\n\r\n";
        assert_eq!(parse_http_host(req), Some("api.github.com".to_string()));

        let lower = b"GET / HTTP/1.1\r\nhost:  lower.example.com \r\n\r\n";
        assert_eq!(
            parse_http_host(lower),
            Some("lower.example.com".to_string())
        );
    }

    #[test]
    fn parse_http_host_is_none_without_a_host_header() {
        assert_eq!(parse_http_host(b"GET / HTTP/1.1\r\n\r\n"), None);
        // Non-UTF8 must not panic.
        assert_eq!(parse_http_host(&[0xff, 0xfe, 0x00]), None);
    }

    #[test]
    fn identify_host_uses_the_http_host_on_plain_ports() {
        let req = b"GET / HTTP/1.1\r\nHost: plain.example.com\r\n\r\n";
        assert_eq!(
            identify_host(req, 80, "10.0.0.1".into()),
            "plain.example.com"
        );
    }

    #[test]
    fn identify_host_falls_back_to_the_destination_ip() {
        // Port 443 but no parseable ClientHello: fall back to dst ip
        // rather than leak a bogus host into the policy decision.
        assert_eq!(
            identify_host(b"not tls at all", 443, "203.0.113.5".into()),
            "203.0.113.5"
        );
        // Plain port, garbage request: same fallback.
        assert_eq!(
            identify_host(b"\x00\x01\x02", 80, "203.0.113.9".into()),
            "203.0.113.9"
        );
    }
}
