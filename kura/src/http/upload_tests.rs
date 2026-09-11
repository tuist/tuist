use std::{io::ErrorKind, sync::Mutex};

use tokio::io::AsyncWriteExt;
use tower::ServiceExt;

use super::*;
use crate::test_support::{response_text, test_context};

fn failed_body(kind: ErrorKind) -> Body {
    Body::from_stream(futures_util::stream::iter([
        Ok(Bytes::from_static(b"partial")),
        Err(std::io::Error::new(kind, "upload regression cause")),
    ]))
}

#[tokio::test]
async fn upload_body_errors_are_consistent_across_staging_and_inline_routes() {
    let context = test_context(|_| {}).await;
    let app = router(context.state.clone());
    for (method, uri) in [
        (
            "POST",
            "/api/cache/cas/upload-fault?tenant_id=test-tenant&namespace_id=ios",
        ),
        (
            "PUT",
            "/api/cache/gradle/upload-fault?tenant_id=test-tenant&namespace_id=ios",
        ),
        ("PUT", "/v1/cache/upload-fault"),
        ("PUT", "/api/metro/cache/upload-fault"),
        (
            "POST",
            "/api/cache/module/part?upload_id=missing&part_number=1",
        ),
        (
            "PUT",
            "/_internal/replicate/artifact?producer=xcode&namespace_id=ios&key=upload-fault&content_type=application/octet-stream&version_ms=1",
        ),
        (
            "PUT",
            "/_internal/replicate/artifact?producer=xcode&namespace_id=ios&key=upload-fault&content_type=application/octet-stream&version_ms=1&inline=true",
        ),
        (
            "PUT",
            "/api/cache/keyvalue?tenant_id=test-tenant&namespace_id=ios",
        ),
    ] {
        for (kind, status, result) in [
            (ErrorKind::ConnectionReset, 499, "client_aborted"),
            (ErrorKind::InvalidData, 400, "invalid_request_body"),
            (ErrorKind::TimedOut, 408, "request_timeout"),
            (ErrorKind::Other, 500, "request_body_error"),
        ] {
            let response = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method(method)
                        .uri(uri)
                        .body(failed_body(kind))
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(
                response.status().as_u16(),
                status,
                "{method} {uri}: {}",
                response_text(response).await
            );
            let details = response.extensions().get::<ObservedHandlerError>().unwrap();
            assert_eq!(details.result, result);
            assert!(details.message.contains("upload regression cause"));
        }
    }
    assert!(
        !context
            .state
            .store
            .artifact_exists(ArtifactProducer::Xcode, "ios", &blob_key("upload-fault"))
            .await
            .unwrap()
    );
    assert_eq!(context.state.memory.transient_reserved_bytes(), 0);
    let metrics = context.state.metrics.render();
    for (name, label, count) in [
        ("kura_artifact_writes_total_total", "result", 20),
        ("kura_multipart_parts_total_total", "result", 4),
        ("kura_replication_apply_results_total_total", "outcome", 8),
    ] {
        let failures: u64 = metrics
            .lines()
            .filter(|line| {
                line.starts_with(&format!("{name}{{"))
                    && line.contains(&format!("{label}=\"error\""))
            })
            .map(|line| line.rsplit(' ').next().unwrap().parse::<u64>().unwrap())
            .sum();
        assert_eq!(failures, count, "{name}");
    }
    assert!(!metrics.contains("action=\"keyvalue_payload_rejected\""));
}

#[tokio::test]
async fn upload_body_storage_failure_remains_a_server_error_and_retry_succeeds() {
    let context = test_context(|_| {}).await;
    let app = router(context.state.clone());
    let uploads = context.state.config.tmp_dir.join("uploads");
    std::fs::create_dir_all(uploads.parent().unwrap()).unwrap();
    std::fs::remove_dir(&uploads).unwrap();
    std::fs::write(&uploads, b"blocks staging directory").unwrap();
    let uri = "/api/cache/cas/disk-failure?tenant_id=test-tenant&namespace_id=ios";
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(uri)
                .body(Body::from("complete body"))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
    let details = response.extensions().get::<ObservedHandlerError>().unwrap();
    assert_eq!(details.result, "server_error");
    assert!(details.message.contains("Failed to persist artifact"));
    assert!(
        !context
            .state
            .store
            .artifact_exists(ArtifactProducer::Xcode, "ios", &blob_key("disk-failure"))
            .await
            .unwrap()
    );
    std::fs::remove_file(uploads).unwrap();
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(uri)
                .body(Body::from("complete body"))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
    let response = app
        .oneshot(Request::builder().uri(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(response_text(response).await, "complete body");
}

#[derive(Clone)]
struct LogBuffer(Arc<Mutex<Vec<u8>>>);

impl std::io::Write for LogBuffer {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

// A process-wide subscriber keeps callsite interest stable while other tests
// install scoped subscribers. Never clear shared capture; select our request ID.
fn upload_log_capture() -> &'static Arc<Mutex<Vec<u8>>> {
    static LOGS: std::sync::OnceLock<Arc<Mutex<Vec<u8>>>> = std::sync::OnceLock::new();
    LOGS.get_or_init(|| {
        let logs = Arc::new(Mutex::new(Vec::new()));
        let writer = LogBuffer(logs.clone());
        tracing::subscriber::set_global_default(
            tracing_subscriber::fmt()
                .json()
                .flatten_event(true)
                .with_writer(move || writer.clone())
                .finish(),
        )
        .unwrap();
        logs
    })
}

#[tokio::test(flavor = "current_thread")]
async fn upload_body_real_http1_errors_keep_causes_in_logs_and_metrics() {
    for (framing, payload, expected_status, expected_result) in [
        ("Content-Length: 100\r\n", "partial", 499, "client_aborted"),
        (
            "Transfer-Encoding: chunked\r\n",
            "7\r\npartial\r\nZ\r\n",
            400,
            "invalid_request_body",
        ),
    ] {
        let context = test_context(|config| {
            config.request_log_sample_rate = 1.0;
            config.warning_log_interval_ms = 0;
        })
        .await;
        let app = router(context.state.clone());
        let logs = upload_log_capture();
        let request_id = format!("upload-wire-fault-{expected_status}");
        let (mut client, server) = tokio::io::duplex(4096);
        let (completed, mut responses) = tokio::sync::mpsc::channel(1);
        let service =
            hyper::service::service_fn(move |request: hyper::Request<hyper::body::Incoming>| {
                let app = app.clone();
                let completed = completed.clone();
                async move {
                    let response = app
                        .oneshot(crate::utils::guard_incoming_request(request))
                        .await
                        .unwrap();
                    completed.send(response.status()).await.unwrap();
                    Ok::<_, std::convert::Infallible>(response)
                }
            });
        let server = tokio::spawn(async move {
            let _ = hyper::server::conn::http1::Builder::new()
                .half_close(true)
                .serve_connection(hyper_util::rt::TokioIo::new(server), service)
                .await;
        });
        client.write_all(format!("POST /api/cache/cas/wire-fault?tenant_id=test-tenant&namespace_id=ios HTTP/1.1\r\nHost: localhost\r\nX-Request-Id: {request_id}\r\n{framing}\r\n{payload}").as_bytes()).await.unwrap();
        client.shutdown().await.unwrap();
        let status = tokio::time::timeout(Duration::from_secs(5), responses.recv())
            .await
            .unwrap()
            .unwrap();
        server.abort();
        assert_eq!(status.as_u16(), expected_status);
        assert!(
            !context
                .state
                .store
                .artifact_exists(ArtifactProducer::Xcode, "ios", &blob_key("wire-fault"))
                .await
                .unwrap()
        );
        assert!(
            std::fs::read_dir(context.state.config.tmp_dir.join("uploads"))
                .unwrap()
                .next()
                .is_none()
        );
        let metrics = context.state.metrics.render();
        assert!(
            metrics
                .lines()
                .any(|line| line.starts_with("kura_http_requests_total_total{")
                    && line.contains("route=\"/api/cache/cas/{id}\"")
                    && line.contains(&format!("status=\"{expected_status}\""))
                    && line.ends_with(" 1")),
            "{metrics}"
        );
        let logs = String::from_utf8(logs.lock().unwrap().clone()).unwrap();
        let event: serde_json::Value = logs
            .lines()
            .map(|line| serde_json::from_str::<serde_json::Value>(line).unwrap())
            .find(|event| {
                event["event.name"] == "kura.http.request.completed"
                    && event["http.request.id"] == request_id
            })
            .expect(&logs);
        assert_eq!(event["kura.response.result"], expected_result);
        assert_eq!(event["http.request.id"], request_id);
        let error = event["error"].as_str().unwrap();
        assert!(error.contains("Failed to read request body"), "{error}");
        assert!(
            error.contains("connection") && error.contains(": "),
            "{error}"
        );
    }
}

#[tokio::test]
async fn upload_body_inline_size_limits_remain_413() {
    let context = test_context(|config| config.max_keyvalue_bytes = 4).await;
    for (uri, size) in [
        (
            "/api/cache/keyvalue?tenant_id=test-tenant&namespace_id=ios",
            5,
        ),
        (
            "/_internal/replicate/artifact?producer=xcode&namespace_id=ios&key=limit&content_type=application/octet-stream&version_ms=1&inline=true",
            MAX_INLINE_REPLICATION_BODY_BYTES as usize + 1,
        ),
    ] {
        let response = router(context.state.clone())
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(uri)
                    .body(Body::from(vec![0; size]))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
        assert!(
            response
                .extensions()
                .get::<ObservedHandlerError>()
                .is_none()
        );
    }
    assert!(
        context
            .state
            .metrics
            .render()
            .lines()
            .any(|line| line.contains("action=\"keyvalue_payload_rejected\"")
                && line.ends_with(" 2"))
    );
}

#[test]
fn upload_body_observation_does_not_tag_ordinary_errors() {
    for status in [
        StatusCode::NOT_FOUND,
        StatusCode::BAD_REQUEST,
        StatusCode::INTERNAL_SERVER_ERROR,
    ] {
        assert!(
            error_response(status, "ordinary response")
                .extensions()
                .get::<ObservedHandlerError>()
                .is_none()
        );
    }
    let response = upload_io_error_response(
        "disk write timed out".into(),
        StatusCode::INTERNAL_SERVER_ERROR,
    );
    assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
    assert_eq!(
        response
            .extensions()
            .get::<ObservedHandlerError>()
            .unwrap()
            .result,
        "server_error"
    );
}

#[tokio::test]
async fn upload_body_real_hyper_http2_requires_clean_end_stream() {
    // Frame type 3 is RST_STREAM; type 7 is GOAWAY. Send frames directly so
    // the error under test is always constructed by Hyper's own h2 dependency.
    for (frame_type, reason) in [
        (3, 8_u32),
        (3, 0),
        (3, 5),
        (3, 7),
        (7, 8),
        (0, 0),
        (0, 1),
        (1, 0),
    ] {
        let context = test_context(|_| {}).await;
        let app = router(context.state.clone());
        let (mut client, server_io) = tokio::io::duplex(4096);
        let (accepted, mut ready) = tokio::sync::mpsc::channel(1);
        let (completed, mut responses) = tokio::sync::mpsc::channel(1);
        let service =
            hyper::service::service_fn(move |request: hyper::Request<hyper::body::Incoming>| {
                let app = app.clone();
                let accepted = accepted.clone();
                let completed = completed.clone();
                async move {
                    // Hyper may cancel its service future on RST_STREAM. Keep the
                    // router's body reader alive independently to inspect the real
                    // Incoming error chain, including Hyper's resolved h2 version.
                    let handler = tokio::spawn(async move {
                        accepted.send(()).await.unwrap();
                        let response = app
                            .oneshot(crate::utils::guard_incoming_request(request))
                            .await
                            .unwrap();
                        completed.send(response.status()).await.unwrap();
                        response
                    });
                    Ok::<_, std::convert::Infallible>(handler.await.unwrap())
                }
            });
        let server = tokio::spawn(async move {
            let _ = hyper::server::conn::http2::Builder::new(hyper_util::rt::TokioExecutor::new())
                .serve_connection(hyper_util::rt::TokioIo::new(server_io), service)
                .await;
        });
        client
            .write_all(b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
            .await
            .unwrap();
        write_h2_frame(&mut client, 4, 0, 0, &[]).await; // SETTINGS
        let path = b"/api/cache/cas/h2-fault?tenant_id=test-tenant&namespace_id=ios";
        // HPACK: indexed POST and https, literal :path and :authority.
        let mut headers = vec![0x83, 0x87, 0x04, path.len() as u8];
        headers.extend_from_slice(path);
        headers.extend_from_slice(b"\x01\x09localhost");
        write_h2_frame(&mut client, 1, 4, 1, &headers).await; // END_HEADERS, body open
        tokio::time::timeout(Duration::from_secs(5), ready.recv())
            .await
            .unwrap()
            .unwrap();
        let mut payload = Vec::new();
        if frame_type == 7 {
            payload.extend_from_slice(&0_u32.to_be_bytes()); // last server-initiated stream
        }
        if frame_type == 1 {
            write_h2_frame(&mut client, 0, 0, 1, b"complete body").await;
            payload.extend_from_slice(b"\x00\x06finish\x03yes"); // literal trailer
        } else if frame_type == 0 {
            if reason == 0 {
                payload.extend_from_slice(b"complete body");
            }
        } else {
            payload.extend_from_slice(&reason.to_be_bytes());
        }
        write_h2_frame(
            &mut client,
            frame_type,
            match frame_type {
                0 => 1, // END_STREAM on DATA
                1 => 5, // END_HEADERS + END_STREAM on trailers
                _ => 0,
            },
            if frame_type == 7 { 0 } else { 1 },
            &payload,
        )
        .await;
        if frame_type == 7 {
            // GOAWAY alone permits in-flight streams to finish; closing the
            // write half makes this an interrupted body, not a graceful drain.
            client.shutdown().await.unwrap();
        }
        let status = tokio::time::timeout(Duration::from_secs(5), responses.recv())
            .await
            .unwrap_or_else(|_| panic!("no completion: frame={frame_type} reason={reason}"))
            .unwrap();
        server.abort();
        let succeeded = frame_type <= 1;
        assert_eq!(
            status.as_u16(),
            if succeeded { 204 } else { 499 },
            "frame={frame_type} reason={reason}"
        );
        assert_eq!(
            context
                .state
                .store
                .artifact_exists(ArtifactProducer::Xcode, "ios", &blob_key("h2-fault"))
                .await
                .unwrap(),
            succeeded
        );
        assert_eq!(context.state.memory.transient_reserved_bytes(), 0);
        assert!(
            std::fs::read_dir(context.state.config.tmp_dir.join("uploads"))
                .unwrap()
                .next()
                .is_none()
        );
    }
}

async fn write_h2_frame(
    client: &mut tokio::io::DuplexStream,
    kind: u8,
    flags: u8,
    stream: u32,
    payload: &[u8],
) {
    let mut frame = Vec::new();
    frame.extend_from_slice(&(payload.len() as u32).to_be_bytes()[1..]);
    frame.extend_from_slice(&[kind, flags]);
    frame.extend_from_slice(&stream.to_be_bytes());
    frame.extend_from_slice(payload);
    client.write_all(&frame).await.unwrap();
}
