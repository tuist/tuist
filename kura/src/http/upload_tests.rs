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
async fn upload_body_errors_are_consistent_across_staging_routes() {
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
    ] {
        for (kind, status, result) in [
            (ErrorKind::ConnectionReset, 499, "client_aborted"),
            (ErrorKind::InvalidData, 400, "invalid_request_body"),
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

#[tokio::test]
async fn upload_body_length_mismatch_is_not_committed() {
    let context = test_context(|_| {}).await;
    for length in ["2", "20"] {
        let response = router(context.state.clone())
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/cas/wrong-length?tenant_id=test-tenant&namespace_id=ios")
                    .header("content-length", length)
                    .body(Body::from("hello"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert!(response_text(response).await.contains("Content-Length"));
        assert!(
            !context
                .state
                .store
                .artifact_exists(ArtifactProducer::Xcode, "ios", &blob_key("wrong-length"))
                .await
                .unwrap()
        );
        assert!(
            std::fs::read_dir(context.state.config.tmp_dir.join("uploads"))
                .unwrap()
                .next()
                .is_none()
        );
    }
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
        let logs = Arc::new(Mutex::new(Vec::new()));
        let writer = LogBuffer(logs.clone());
        let subscriber = tracing_subscriber::fmt()
            .json()
            .flatten_event(true)
            .with_writer(move || writer.clone())
            .finish();
        // Keep the dispatcher installed across awaits on this single-thread runtime.
        let _subscriber = tracing::subscriber::set_default(subscriber);
        let (mut client, server) = tokio::io::duplex(4096);
        let (completed, mut responses) = tokio::sync::mpsc::channel(1);
        let service =
            hyper::service::service_fn(move |request: hyper::Request<hyper::body::Incoming>| {
                let app = app.clone();
                let completed = completed.clone();
                async move {
                    let response = app.oneshot(request.map(Body::new)).await.unwrap();
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
        client.write_all(format!("POST /api/cache/cas/wire-fault?tenant_id=test-tenant&namespace_id=ios HTTP/1.1\r\nHost: localhost\r\nX-Request-Id: upload-wire-fault\r\n{framing}\r\n{payload}").as_bytes()).await.unwrap();
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
            .find(|event| event["event.name"] == "kura.http.request.completed")
            .expect(&logs);
        assert_eq!(event["kura.response.result"], expected_result);
        assert_eq!(event["http.request.id"], "upload-wire-fault");
        let error = event["error"].as_str().unwrap();
        assert!(error.contains("Failed to read request body"), "{error}");
        assert!(
            error.contains("connection") && error.contains(": "),
            "{error}"
        );
    }
}
