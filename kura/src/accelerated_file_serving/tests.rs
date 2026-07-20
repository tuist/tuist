
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

    let metro =
        artifact_request("/api/metro/cache/metro-key", "acme").expect("metro request should parse");
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
