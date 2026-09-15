use super::*;
use crate::test_support::{TestContext, test_context};
use axum::{Router, response::IntoResponse, routing::get};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use sha2::{Digest as _, Sha256};
use std::{
    sync::atomic::{AtomicUsize, Ordering},
    time::Duration,
};

const PAYLOAD: &[u8] = b"dependency archive bytes";

struct Origin {
    url: String,
    hits: Arc<AtomicUsize>,
    connections: Arc<Mutex<std::collections::HashSet<std::net::SocketAddr>>>,
    task: tokio::task::JoinHandle<()>,
}

impl Drop for Origin {
    fn drop(&mut self) {
        self.task.abort();
    }
}

async fn origin() -> Origin {
    let hits = Arc::new(AtomicUsize::new(0));
    let counter = hits.clone();
    let connections = Arc::new(Mutex::new(std::collections::HashSet::new()));
    let peers = connections.clone();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let router = Router::new()
        .route(
            "/file",
            get(
                move |axum::extract::ConnectInfo(peer): axum::extract::ConnectInfo<
                    std::net::SocketAddr,
                >| {
                    let hits = counter.clone();
                    let peers = peers.clone();
                    async move {
                        peers.lock().unwrap().insert(peer);
                        hits.fetch_add(1, Ordering::SeqCst);
                        PAYLOAD
                    }
                },
            ),
        )
        .route(
            "/missing",
            get(|| async { axum::http::StatusCode::NOT_FOUND }),
        )
        .route(
            "/retry",
            get({
                let hits = hits.clone();
                move || {
                    let hits = hits.clone();
                    async move {
                        if hits.fetch_add(1, Ordering::SeqCst) == 0 {
                            axum::http::StatusCode::INTERNAL_SERVER_ERROR.into_response()
                        } else {
                            PAYLOAD.into_response()
                        }
                    }
                }
            }),
        )
        .route(
            "/slow",
            get(|| async {
                std::future::pending::<()>().await;
                PAYLOAD
            }),
        )
        .route(
            "/metadata",
            get(|| async {
                axum::response::Redirect::temporary("http://169.254.169.254/latest/meta-data/")
            }),
        )
        .route(
            "/same-origin",
            get(|| async { axum::response::Redirect::temporary("/headers") }),
        )
        .route(
            "/other-origin",
            get({
                let target = format!(
                    "http://localhost:{}/headers",
                    listener.local_addr().unwrap().port()
                );
                move || {
                    let target = target.clone();
                    async move { axum::response::Redirect::temporary(&target) }
                }
            }),
        )
        .route(
            "/chunked",
            get(|| async {
                axum::body::Body::from_stream(futures_util::stream::iter([
                    Ok::<_, std::io::Error>(PAYLOAD),
                ]))
            }),
        )
        .route(
            "/headers",
            get(|headers: axum::http::HeaderMap| async move {
                headers
                    .get("authorization")
                    .and_then(|v| v.to_str().ok())
                    .unwrap_or("none")
                    .to_owned()
            }),
        );
    let task = tokio::spawn(async move {
        axum::serve(
            listener,
            router.into_make_service_with_connect_info::<std::net::SocketAddr>(),
        )
        .await
        .unwrap();
    });
    Origin {
        url,
        hits,
        connections,
        task,
    }
}

fn service(context: &TestContext) -> AssetService {
    let mut service = AssetService::new(ReapiService::new(context.state.clone()));
    service.http = super::http::OriginClient::allowing_loopback();
    service
}

fn message(uri: String) -> asset::FetchBlobRequest {
    asset::FetchBlobRequest {
        instance_name: "ios".into(),
        uris: vec![uri],
        qualifiers: vec![asset::Qualifier {
            name: "checksum.sri".into(),
            value: format!("sha256-{}", STANDARD.encode(Sha256::digest(PAYLOAD))),
        }],
        ..Default::default()
    }
}

async fn fetch(
    service: &AssetService,
    message: asset::FetchBlobRequest,
) -> asset::FetchBlobResponse {
    service
        .fetch_blob(Request::new(message))
        .await
        .unwrap()
        .into_inner()
}

#[tokio::test]
async fn cached_asset_survives_service_recreation_and_origin_loss_and_is_readable_via_cas() {
    use bazel_remote_apis::build::bazel::remote::execution::v2::{
        self as reapi, content_addressable_storage_server::ContentAddressableStorage,
    };
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let message = message(format!("{}/file", origin.url));
    let first = fetch(&service(&context), message.clone()).await;
    assert_eq!(first.status.unwrap().code, 0);
    assert_eq!(origin.hits.load(Ordering::SeqCst), 1);
    drop(origin);
    let second = fetch(&service(&context), message).await;
    assert_eq!(second.status.unwrap().code, 0);
    assert_eq!(first.blob_digest, second.blob_digest);
    let result = ReapiService::new(context.state.clone())
        .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
            instance_name: "ios".into(),
            digests: vec![second.blob_digest.unwrap()],
            ..Default::default()
        }))
        .await
        .unwrap()
        .into_inner();
    assert_eq!(result.responses[0].data, PAYLOAD);
}

#[tokio::test]
async fn concurrent_calls_fetch_once_and_namespaces_are_isolated() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let service = service(&context);
    let message = message(format!("{}/file", origin.url));
    let results =
        futures_util::future::join_all((0..8).map(|_| fetch(&service, message.clone()))).await;
    assert!(results.iter().all(|r| r.status.as_ref().unwrap().code == 0));
    assert_eq!(origin.hits.load(Ordering::SeqCst), 1);
    let mut other = message;
    other.instance_name = "android".into();
    assert_eq!(fetch(&service, other).await.status.unwrap().code, 0);
    assert_eq!(origin.hits.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn same_asset_waiters_do_not_exhaust_origin_admission() {
    let context = test_context(|_| {}).await;
    let service = service(&context);
    let healthy = origin().await;
    let entered = Arc::new(tokio::sync::Notify::new());
    let release = Arc::new(tokio::sync::Notify::new());
    let hits = Arc::new(AtomicUsize::new(0));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let request = message(format!("http://{}/file", listener.local_addr().unwrap()));
    let router = Router::new().route(
        "/file",
        get({
            let entered = entered.clone();
            let release = release.clone();
            let hits = hits.clone();
            move || {
                let entered = entered.clone();
                let release = release.clone();
                let hits = hits.clone();
                async move {
                    hits.fetch_add(1, Ordering::SeqCst);
                    entered.notify_one();
                    release.notified().await;
                    PAYLOAD
                }
            }
        }),
    );
    let origin_task = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
    let spec = FetchSpec::parse(&request).unwrap();
    let flight = service.flight("ios", spec.flight_key());
    let guard = flight.lock().await;
    let mut callers = tokio::task::JoinSet::new();
    for _ in 0..MAX_CONCURRENT_FETCHES {
        let service = service.clone();
        let request = request.clone();
        callers.spawn(async move { fetch(&service, request).await });
    }
    tokio::time::timeout(Duration::from_secs(10), async {
        // Every caller owns its flight reference before the test releases the leader.
        while Arc::strong_count(&flight) != MAX_CONCURRENT_FETCHES + 1 {
            tokio::task::yield_now().await;
        }
        drop(guard);
        entered.notified().await;
        assert_eq!(hits.load(Ordering::SeqCst), 1);
        assert_eq!(
            service.slots.available_permits(),
            MAX_CONCURRENT_FETCHES - 1
        );
        let response = fetch(&service, message(format!("{}/file", healthy.url))).await;
        assert_eq!(response.status.unwrap().code, 0);
        assert_eq!(healthy.hits.load(Ordering::SeqCst), 1);
        release.notify_one();
        while let Some(response) = callers.join_next().await {
            assert_eq!(response.unwrap().status.unwrap().code, 0);
        }
        assert_eq!(hits.load(Ordering::SeqCst), 1);
        assert_eq!(service.slots.available_permits(), MAX_CONCURRENT_FETCHES);
    })
    .await
    .expect("coalesced callers and the independent asset must complete");
    origin_task.abort();
}

#[tokio::test]
async fn retries_transient_errors_and_falls_back_to_mirrors() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let service = service(&context);
    let mut message = message(format!("{}/missing", origin.url));
    message.uris.push(format!("{}/retry", origin.url));
    let response = fetch(&service, message).await;
    assert_eq!(response.status.unwrap().code, 0);
    assert!(response.uri.ends_with("/retry"));
    assert_eq!(origin.hits.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn checksum_mismatch_never_publishes_cas_or_mapping_and_cleans_staging() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let service = service(&context);
    let mut message = message(format!("{}/file", origin.url));
    message.qualifiers[0].value = format!("sha256-{}", STANDARD.encode([0; 32]));
    let spec = FetchSpec::parse(&message).unwrap();
    let response = fetch(&service, message).await;
    assert_eq!(response.status.unwrap().code, tonic::Code::Aborted as i32);
    assert!(response.blob_digest.is_none());
    assert!(service.cached("ios", &spec).await.unwrap().is_none());
    let key = blob_key(&format!(
        "{}/{}",
        hex::encode(Sha256::digest(PAYLOAD)),
        PAYLOAD.len()
    ));
    assert!(
        context
            .state
            .store
            .fetch_artifact(ArtifactProducer::Reapi, "ios", &key)
            .await
            .unwrap()
            .is_none()
    );
    // The RAII cleanup unlinks on a blocking task, keeping its reservation until it finishes.
    tokio::time::timeout(Duration::from_secs(2), async {
        while std::fs::read_dir(&context.state.config.tmp_dir)
            .unwrap()
            .any(|entry| {
                entry
                    .unwrap()
                    .file_name()
                    .to_string_lossy()
                    .starts_with("remote-asset-")
            })
        {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn stale_or_evicted_entries_are_refetched() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let service = service(&context);
    let mut message = message(format!("{}/file", origin.url));
    let first = fetch(&service, message.clone()).await.blob_digest.unwrap();
    let key = blob_key(&format!("{}/{}", first.hash, first.size_bytes));
    let manifest = context
        .state
        .store
        .fetch_artifact(ArtifactProducer::Reapi, "ios", &key)
        .await
        .unwrap()
        .unwrap();
    context
        .state
        .store
        .delete_artifact_metadata(&[manifest])
        .unwrap();
    assert_eq!(
        fetch(&service, message.clone()).await.status.unwrap().code,
        0
    );
    assert_eq!(origin.hits.load(Ordering::SeqCst), 2);
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();
    message.oldest_content_accepted = Some(bazel_remote_apis::google::protobuf::Timestamp {
        seconds: now.as_secs() as i64,
        nanos: now.subsec_nanos() as i32,
    });
    assert_eq!(fetch(&service, message).await.status.unwrap().code, 0);
    assert_eq!(origin.hits.load(Ordering::SeqCst), 3);
}

#[tokio::test]
async fn private_addresses_and_redirects_to_metadata_are_rejected() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let production = AssetService::new(ReapiService::new(context.state.clone()));
    for uri in [
        format!("{}/file", origin.url),
        "http://localhost/file".into(),
        "http://[::ffff:127.0.0.1]/file".into(),
    ] {
        assert_eq!(
            fetch(&production, message(uri)).await.status.unwrap().code,
            tonic::Code::PermissionDenied as i32
        );
    }
    assert_eq!(origin.hits.load(Ordering::SeqCst), 0);
    assert_eq!(
        fetch(
            &service(&context),
            message(format!("{}/metadata", origin.url))
        )
        .await
        .status
        .unwrap()
        .code,
        tonic::Code::PermissionDenied as i32
    );
}

#[tokio::test]
async fn timeout_and_admission_are_bounded() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let service = service(&context);
    let mut message = message(format!("{}/slow", origin.url));
    message.timeout = Some(bazel_remote_apis::google::protobuf::Duration {
        seconds: 0,
        nanos: 20_000_000,
    });
    assert_eq!(
        fetch(&service, message.clone()).await.status.unwrap().code,
        tonic::Code::DeadlineExceeded as i32
    );
    assert_eq!(service.slots.available_permits(), MAX_CONCURRENT_FETCHES);
    let _slots = service
        .slots
        .acquire_many(MAX_CONCURRENT_FETCHES as u32)
        .await
        .unwrap();
    assert_eq!(
        service
            .fetch_blob(Request::new(message))
            .await
            .unwrap_err()
            .code(),
        tonic::Code::ResourceExhausted
    );
}

#[tokio::test]
async fn future_freshness_is_rejected_without_returning_older_content() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let mut message = message(format!("{}/file", origin.url));
    message.oldest_content_accepted = Some(bazel_remote_apis::google::protobuf::Timestamp {
        seconds: 253_402_300_799,
        nanos: 0,
    });
    let response = service(&context).fetch_blob(Request::new(message)).await;
    assert_eq!(response.unwrap_err().code(), tonic::Code::InvalidArgument);
    assert_eq!(origin.hits.load(Ordering::SeqCst), 0);
}

#[test]
fn qualifiers_are_validated_and_canonical_ids_and_credentials_partition_cache_keys() {
    let mut message = message("https://example.com/archive".into());
    let original = FetchSpec::parse(&message).unwrap().keys;
    message.qualifiers.push(asset::Qualifier {
        name: "bazel.canonical_id".into(),
        value: "v2".into(),
    });
    assert_ne!(FetchSpec::parse(&message).unwrap().keys, original);
    message.qualifiers.push(asset::Qualifier {
        name: "http_header_url:0:Authorization".into(),
        value: "Bearer private".into(),
    });
    let spec = FetchSpec::parse(&message).unwrap();
    assert_eq!(spec.headers[0]["authorization"], "Bearer private");
    assert!(!spec.keys[0].contains("private"));
    message.qualifiers.push(asset::Qualifier {
        name: "unknown".into(),
        value: "x".into(),
    });
    assert!(FetchSpec::parse(&message).is_err());
    message.qualifiers.pop();
    message.qualifiers.push(message.qualifiers[0].clone());
    assert!(FetchSpec::parse(&message).is_err());
}

#[tokio::test]
async fn sha512_origin_checksum_is_verified_and_cas_uses_sha256() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let mut message = message(format!("{}/file", origin.url));
    message.qualifiers[0].value =
        format!("sha512-{}", STANDARD.encode(sha2::Sha512::digest(PAYLOAD)));
    let response = fetch(&service(&context), message).await;
    assert_eq!(response.status.unwrap().code, 0);
    assert_eq!(
        response.blob_digest.unwrap().hash,
        hex::encode(Sha256::digest(PAYLOAD))
    );
}

#[tokio::test]
async fn redirects_keep_headers_only_on_the_same_origin() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let service = service(&context);
    for (path, expected) in [("same-origin", "Bearer private"), ("other-origin", "none")] {
        let mut message = message(format!("{}/{path}", origin.url));
        message.qualifiers = vec![asset::Qualifier {
            name: "http_header:Authorization".into(),
            value: "Bearer private".into(),
        }];
        let response = fetch(&service, message).await;
        assert_eq!(response.status.unwrap().code, 0);
        assert_eq!(
            response.blob_digest.unwrap().hash,
            hex::encode(Sha256::digest(expected))
        );
    }
}

#[tokio::test]
async fn unknown_length_downloads_respect_the_disk_budget() {
    let context = test_context(|config| config.tmp_dir_max_bytes = 10).await;
    let origin = origin().await;
    let service = service(&context);
    let message = message(format!("{}/chunked", origin.url));
    let spec = FetchSpec::parse(&message).unwrap();
    let response = fetch(&service, message).await;
    assert_eq!(
        response.status.unwrap().code,
        tonic::Code::ResourceExhausted as i32
    );
    assert!(service.cached("ios", &spec).await.unwrap().is_none());
    assert_eq!(service.slots.available_permits(), MAX_CONCURRENT_FETCHES);
}

#[tokio::test]
async fn registered_grpc_fetch_service_returns_a_cached_blob() {
    use bazel_remote_apis::build::bazel::remote::asset::v1::fetch_client::FetchClient;
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let message = message(format!("{}/file", origin.url));
    let expected = fetch(&service(&context), message.clone()).await.blob_digest;
    drop(origin);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = format!("http://{}", listener.local_addr().unwrap());
    let router = super::super::service::routes(context.state.clone());
    let server = tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    let mut client = FetchClient::connect(address).await.unwrap();
    let response = client
        .fetch_blob(message.clone())
        .await
        .unwrap()
        .into_inner();
    let mut oversized = message;
    oversized.qualifiers.push(asset::Qualifier {
        name: "bazel.canonical_id".into(),
        value: "x".repeat(MAX_REQUEST_BYTES),
    });
    let error = client.fetch_blob(oversized).await.unwrap_err();
    assert!(matches!(
        error.code(),
        tonic::Code::OutOfRange | tonic::Code::ResourceExhausted
    ));
    server.abort();
    assert_eq!(response.status.unwrap().code, 0);
    assert_eq!(response.blob_digest, expected);
}

#[tokio::test]
async fn fetch_requires_authentication_before_contacting_origins() {
    use crate::auth::{AuthEngine, config::AuthConfig};
    let auth = Arc::new(
        AuthEngine::new(
            AuthConfig {
                base_url: "http://127.0.0.1:1".into(),
                connect_timeout: Duration::from_millis(50),
                request_timeout: Duration::from_millis(50),
                verifier: None,
                introspection: None,
                cache_max_entries: 128,
            },
            crate::metrics::Metrics::new("test".into(), "tenant".into()),
        )
        .unwrap(),
    );
    let context = crate::test_support::test_context_with_auth(|_| {}, Some(auth)).await;
    let origin = origin().await;
    let response = service(&context)
        .fetch_blob(Request::new(message(format!("{}/file", origin.url))))
        .await;
    assert_eq!(response.unwrap_err().code(), tonic::Code::Unauthenticated);
    assert_eq!(origin.hits.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn cache_hits_bypass_full_download_admission_and_busy_flights() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let service = service(&context);
    let message = message(format!("{}/file", origin.url));
    let expected = fetch(&service, message.clone()).await.blob_digest;
    let spec = FetchSpec::parse(&message).unwrap();
    let _slots = service
        .slots
        .acquire_many(MAX_CONCURRENT_FETCHES as u32)
        .await
        .unwrap();
    let flight = service.flight("ios", spec.flight_key());
    let _flight = flight.lock().await;
    let response = tokio::time::timeout(Duration::from_secs(2), fetch(&service, message))
        .await
        .unwrap();
    assert_eq!(response.status.unwrap().code, 0);
    assert_eq!(response.blob_digest, expected);
    assert_eq!(origin.hits.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn different_lookup_keys_reuse_the_origin_connection_and_record_deduplication() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let service = service(&context);
    for key in ["first", "second"] {
        assert_eq!(
            fetch(&service, message(format!("{}/file?{key}", origin.url)))
                .await
                .status
                .unwrap()
                .code,
            0
        );
    }
    assert_eq!(origin.hits.load(Ordering::SeqCst), 2);
    assert_eq!(origin.connections.lock().unwrap().len(), 1);
    let rendered = context.state.metrics.render();
    assert!(
        rendered
            .lines()
            .any(|line| line.starts_with("kura_artifact_write_bytes_total")
                && line.contains("producer=\"reapi\"")
                && line.contains("result=\"ok\"")
                && line.ends_with(&format!(" {}", PAYLOAD.len())))
    );
    assert!(
        rendered
            .lines()
            .any(|line| line.starts_with("kura_artifact_writes_total")
                && line.contains("producer=\"reapi\"")
                && line.contains("result=\"damped\"")
                && line.ends_with(" 1"))
    );
}

async fn assert_asset_staging_empty(context: &TestContext) {
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let files = std::fs::read_dir(&context.state.config.tmp_dir).unwrap();
            if !files.into_iter().any(|entry| {
                entry
                    .unwrap()
                    .file_name()
                    .to_string_lossy()
                    .starts_with("remote-asset-")
            }) {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn truncated_content_length_without_checksum_never_publishes_an_asset() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let context = test_context(|_| {}).await;
    let service = service(&context);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let uri = format!("http://{}/short", listener.local_addr().unwrap());
    let connections = Arc::new(AtomicUsize::new(0));
    let count = connections.clone();
    let server = tokio::spawn(async move {
        loop {
            let (mut stream, _) = listener.accept().await.unwrap();
            count.fetch_add(1, Ordering::SeqCst);
            let mut request = [0; 4096];
            let read = stream.read(&mut request).await.unwrap();
            assert!(read > 0, "origin connection closed before sending a request");
            stream
                .write_all(
                    b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\nConnection: close\r\n\r\nshort",
                )
                .await
                .unwrap();
            stream.shutdown().await.unwrap();
        }
    });
    let mut message = message(uri);
    message.qualifiers.clear();
    let spec = FetchSpec::parse(&message).unwrap();
    let response = fetch(&service, message.clone()).await;
    assert_eq!(response.status.unwrap().code, tonic::Code::Aborted as i32);
    assert!(response.blob_digest.is_none());
    assert!(service.cached("ios", &spec).await.unwrap().is_none());
    let key = blob_key(&format!("{}/5", hex::encode(Sha256::digest(b"short"))));
    assert!(
        context
            .state
            .store
            .fetch_artifact(ArtifactProducer::Reapi, "ios", &key)
            .await
            .unwrap()
            .is_none()
    );
    assert_asset_staging_empty(&context).await;
    let rendered = context.state.metrics.render();
    assert!(
        rendered
            .lines()
            .any(|line| line.starts_with("kura_artifact_writes_total")
                && line.contains("producer=\"reapi\"")
                && line.contains("result=\"error\"")
                && line.ends_with(" 1"))
    );
    assert_eq!(connections.load(Ordering::SeqCst), 1);
    let healthy = origin().await;
    message.uris.push(format!("{}/file", healthy.url));
    let response = fetch(&service, message).await;
    assert_eq!(response.status.unwrap().code, 0);
    assert_eq!(connections.load(Ordering::SeqCst), 2);
    assert_eq!(healthy.hits.load(Ordering::SeqCst), 1);
    server.abort();
}

#[tokio::test]
async fn draining_cancels_a_stalled_grpc_fetch_and_releases_admission_and_staging() {
    use bazel_remote_apis::build::bazel::remote::asset::v1::fetch_client::FetchClient;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let context = test_context(|config| config.drain_completion_timeout_ms = 5_000).await;
    let service = service(&context);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let uri = format!("http://{}/stalled", listener.local_addr().unwrap());
    let origin = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        let mut request = [0; 4096];
        let read = stream.read(&mut request).await.unwrap();
        assert!(read > 0, "origin connection closed before sending a request");
        stream
            .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\nx")
            .await
            .unwrap();
        std::future::pending::<()>().await;
    });
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = format!("http://{}", listener.local_addr().unwrap());
    let router = tonic::service::Routes::new(FetchServer::new(service.clone()))
        .into_axum_router()
        .layer(super::super::admission::GrpcRequestAccountingLayer {
            state: context.state.clone(),
        });
    let server = tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    let mut client = FetchClient::connect(address).await.unwrap();
    let call = tokio::spawn(async move { client.fetch_blob(message(uri)).await });
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            if let Ok(files) = std::fs::read_dir(&context.state.config.tmp_dir)
                && files.filter_map(Result::ok).any(|entry| {
                    entry
                        .file_name()
                        .to_string_lossy()
                        .starts_with("remote-asset-")
                        && entry.metadata().unwrap().len() > 0
                })
            {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(context.state.runtime.total_inflight(), 1);
    context.state.enter_draining();
    let result = tokio::time::timeout(
        Duration::from_millis(context.state.config.drain_completion_timeout_ms),
        call,
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(result.unwrap_err().code(), tonic::Code::Unavailable);
    assert_eq!(service.slots.available_permits(), MAX_CONCURRENT_FETCHES);
    assert_asset_staging_empty(&context).await;
    assert_eq!(context.state.runtime.total_inflight(), 0);
    // Late subscribers must observe an already-started drain without waiting for another notification.
    tokio::time::timeout(
        Duration::from_secs(1),
        context.state.runtime.wait_for_drain(),
    )
    .await
    .unwrap();
    origin.abort();
    server.abort();
}

#[tokio::test]
async fn untrusted_tls_is_not_retried_and_another_mirror_can_succeed() {
    let context = test_context(|_| {}).await;
    let service = service(&context);
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".to_owned()]).unwrap();
    let cert_path = context.state.config.tmp_dir.join("origin.crt");
    let key_path = context.state.config.tmp_dir.join("origin.key");
    std::fs::create_dir_all(&context.state.config.tmp_dir).unwrap();
    std::fs::write(&cert_path, cert.cert.pem()).unwrap();
    std::fs::write(&key_path, cert.signing_key.serialize_pem()).unwrap();
    let tls = crate::peer_tls::build_public_rustls_config(&crate::config::PublicTlsConfig {
        cert_path,
        key_path,
    })
    .await
    .unwrap()
    .get_inner();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let uri = format!(
        "https://localhost:{}/file",
        listener.local_addr().unwrap().port()
    );
    let connections = Arc::new(AtomicUsize::new(0));
    let counter = connections.clone();
    let server = tokio::spawn(async move {
        let acceptor = tokio_rustls::TlsAcceptor::from(tls);
        loop {
            let (socket, _) = listener.accept().await.unwrap();
            counter.fetch_add(1, Ordering::SeqCst);
            let _ = acceptor.accept(socket).await;
        }
    });
    let response = fetch(&service, message(uri.clone())).await;
    assert_eq!(
        response.status.unwrap().code,
        tonic::Code::FailedPrecondition as i32
    );
    assert_eq!(connections.load(Ordering::SeqCst), 1);
    let mirror = origin().await;
    let mut message = message(uri);
    message.uris.push(format!("{}/file", mirror.url));
    let response = fetch(&service, message).await;
    server.abort();
    assert_eq!(response.status.unwrap().code, 0);
    assert_eq!(connections.load(Ordering::SeqCst), 2);
    assert_eq!(mirror.hits.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn reordered_mirrors_share_a_flight_without_losing_header_identity() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let service = service(&context);
    let mut first = message(format!("{}/file?a", origin.url));
    first.uris.push(format!("{}/file?b", origin.url));
    first.qualifiers.push(asset::Qualifier {
        name: "http_header_url:0:Authorization".into(),
        value: "Bearer a".into(),
    });
    let mut second = first.clone();
    second.uris.reverse();
    second.qualifiers[1].name = "http_header_url:1:Authorization".into();
    let spec = FetchSpec::parse(&first).unwrap();
    let other = FetchSpec::parse(&second).unwrap();
    assert_eq!(spec.flight_key(), other.flight_key());
    let flight = service.flight("ios", spec.flight_key());
    let guard = flight.lock().await;
    let mut calls = tokio::task::JoinSet::new();
    for message in [first, second] {
        let service = service.clone();
        calls.spawn(async move { fetch(&service, message).await });
    }
    tokio::time::timeout(Duration::from_secs(5), async {
        while Arc::strong_count(&flight) != 3 {
            tokio::task::yield_now().await;
        }
        drop(guard);
        while let Some(result) = calls.join_next().await {
            assert_eq!(result.unwrap().status.unwrap().code, 0);
        }
    })
    .await
    .unwrap();
    assert_eq!(origin.hits.load(Ordering::SeqCst), 1);
    let mut different = message(format!("{}/file?a", origin.url));
    different.qualifiers.push(asset::Qualifier {
        name: "http_header_url:0:Authorization".into(),
        value: "Bearer different".into(),
    });
    assert_ne!(FetchSpec::parse(&different).unwrap().keys[0], spec.keys[0]);
}

#[tokio::test]
async fn mapping_failure_returns_cas_and_shares_it_with_waiters() {
    use crate::failpoints::{FailpointAction, FailpointName};
    use bazel_remote_apis::build::bazel::remote::execution::v2::{
        self as reapi, content_addressable_storage_server::ContentAddressableStorage,
    };
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let service = service(&context);
    let request = message(format!("{}/file", origin.url));
    let spec = FetchSpec::parse(&request).unwrap();
    let flight = service.flight("ios", spec.flight_key());
    let guard = flight.lock().await;
    context.state.store.failpoints().set_always(
        FailpointName::AfterInlineManifestReadBeforeCommit,
        FailpointAction::Error("lookup write unavailable".into()),
    );
    let mut callers = tokio::task::JoinSet::new();
    for _ in 0..32 {
        let service = service.clone();
        let request = request.clone();
        callers.spawn(async move { fetch(&service, request).await });
    }
    let mut digest = None;
    tokio::time::timeout(Duration::from_secs(5), async {
        while Arc::strong_count(&flight) != 33 {
            tokio::task::yield_now().await;
        }
        drop(guard);
        while let Some(response) = callers.join_next().await {
            let response = response.unwrap();
            assert_eq!(response.status.unwrap().code, 0);
            if let Some(expected) = &digest {
                assert_eq!(response.blob_digest.as_ref(), Some(expected));
            }
            digest = response.blob_digest;
        }
    })
    .await
    .unwrap();
    assert_eq!(origin.hits.load(Ordering::SeqCst), 1);
    assert!(service.cached("ios", &spec).await.unwrap().is_none());
    let response = ReapiService::new(context.state.clone())
        .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
            instance_name: "ios".into(),
            digests: vec![digest.unwrap()],
            ..Default::default()
        }))
        .await
        .unwrap()
        .into_inner();
    assert_eq!(response.responses[0].data, PAYLOAD);
    drop(flight);
    assert!(
        service
            .flights
            .lock()
            .unwrap()
            .values()
            .all(|flight| flight.strong_count() == 0)
    );
}

#[tokio::test]
async fn slow_mirror_exhausts_its_budget_and_leaves_time_for_the_next() {
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let mut service = service(&context);
    service.mirror_timeout = Duration::from_secs(1);
    let mut request = message(format!("{}/slow", origin.url));
    request.uris.push(format!("{}/file", origin.url));
    let response = tokio::time::timeout(Duration::from_secs(5), fetch(&service, request))
        .await
        .unwrap();
    assert_eq!(response.status.unwrap().code, 0);
    assert!(response.uri.ends_with("/file"));
    assert_eq!(origin.hits.load(Ordering::SeqCst), 1);
    assert_eq!(service.slots.available_permits(), MAX_CONCURRENT_FETCHES);
    assert_asset_staging_empty(&context).await;
}

#[test]
fn hashing_only_computes_cas_and_the_requested_integrity_algorithm() {
    use super::request::{Checksum, IntegrityHasher};
    let algorithms = [
        None,
        Some(Checksum::Sha256(Sha256::digest(PAYLOAD).to_vec())),
        Some(Checksum::Sha384(sha2::Sha384::digest(PAYLOAD).to_vec())),
        Some(Checksum::Sha512(sha2::Sha512::digest(PAYLOAD).to_vec())),
    ];
    for (index, checksum) in algorithms.iter().enumerate() {
        let mut integrity = IntegrityHasher::new(checksum.as_ref());
        assert!(match index {
            0 | 1 => matches!(integrity, IntegrityHasher::None),
            2 => matches!(integrity, IntegrityHasher::Sha384(_)),
            _ => matches!(integrity, IntegrityHasher::Sha512(_)),
        });
        let mut cas = Sha256::new();
        for chunk in PAYLOAD.chunks(3) {
            cas.update(chunk);
            integrity.update(chunk);
        }
        if let Some(checksum) = checksum {
            assert!(checksum.matches(&cas, &integrity));
        }
        assert_eq!(
            cas.finalize().as_slice(),
            Sha256::digest(PAYLOAD).as_slice()
        );
    }
}

#[tokio::test]
async fn exactly_one_accept_encoding_is_sent_with_and_without_a_qualifier() {
    let context = test_context(|_| {}).await;
    let service = service(&context);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let uri = format!("http://{}/headers", listener.local_addr().unwrap());
    let seen = Arc::new(Mutex::new(Vec::new()));
    let capture = seen.clone();
    let router = Router::new().route(
        "/headers",
        get(move |headers: axum::http::HeaderMap| {
            capture.lock().unwrap().push(
                headers
                    .get_all("accept-encoding")
                    .iter()
                    .map(|v| v.to_str().unwrap().to_owned())
                    .collect::<Vec<_>>(),
            );
            async { PAYLOAD }
        }),
    );
    let task = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
    for explicit in [false, true] {
        let mut request = message(uri.clone());
        if explicit {
            request.qualifiers.push(asset::Qualifier {
                name: "http_header:accept-encoding".into(),
                value: "identity".into(),
            });
        }
        assert_eq!(fetch(&service, request).await.status.unwrap().code, 0);
    }
    assert_eq!(
        *seen.lock().unwrap(),
        vec![vec!["identity"], vec!["identity"]]
    );
    task.abort();
}

#[test]
fn reqwest_accepts_the_rustls_version_used_by_the_typed_error_classifier() {
    let tls = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::aws_lc_rs::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .unwrap()
    .with_root_certificates(rustls::RootCertStore::empty())
    .with_no_client_auth();
    reqwest::Client::builder()
        .tls_backend_preconfigured(tls)
        .build()
        .expect("reqwest and Kura must share a rustls version for typed TLS error classification");
    assert!(
        reqwest::Client::builder()
            .tls_backend_preconfigured(())
            .build()
            .is_err()
    );
}

#[derive(Clone)]
struct AssetLogBuffer(Arc<Mutex<Vec<u8>>>);
impl std::io::Write for AssetLogBuffer {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[tokio::test]
async fn invalid_lookup_records_are_reported_without_credentials_and_repaired() {
    use tracing::instrument::WithSubscriber;
    let context = test_context(|_| {}).await;
    let origin = origin().await;
    let service = service(&context);
    let logs = Arc::new(Mutex::new(Vec::new()));
    let writer = AssetLogBuffer(logs.clone());
    let subscriber = tracing_subscriber::fmt()
        .with_ansi(false)
        .without_time()
        .with_writer(move || writer.clone())
        .finish();
    async {
        for (index, bytes) in [
            vec![b'x'; 1025],
            b"not json".to_vec(),
            br#"{"hash":"bad","size":3,"fetched_at_nanos":0}"#.to_vec(),
        ]
        .into_iter()
        .enumerate()
        {
            let mut request = message(format!("{}/file?secret=never-log-{index}", origin.url));
            request.qualifiers.push(asset::Qualifier {
                name: "http_header:authorization".into(),
                value: "Bearer never-log".into(),
            });
            let spec = FetchSpec::parse(&request).unwrap();
            context
                .state
                .store
                .persist_inline_artifact_from_bytes_and_replicate(
                    ArtifactProducer::Reapi,
                    "ios",
                    &spec.keys[0],
                    "application/json",
                    &bytes,
                    None,
                    None,
                )
                .await
                .unwrap();
            assert_eq!(
                fetch(&service, request.clone()).await.status.unwrap().code,
                0
            );
            assert!(service.cached("ios", &spec).await.unwrap().is_some());
            assert_eq!(fetch(&service, request).await.status.unwrap().code, 0);
        }
    }
    .with_subscriber(subscriber)
    .await;
    let output = String::from_utf8(logs.lock().unwrap().clone()).unwrap();
    for reason in ["oversized", "invalid_json", "invalid_digest"] {
        assert!(output.contains(reason), "{output}");
    }
    assert!(!output.contains("never-log"));
    assert_eq!(origin.hits.load(Ordering::SeqCst), 3);
}

#[test]
fn requested_fetch_timeout_is_capped_at_three_minutes() {
    let mut request = message("https://example.com/archive".into());
    assert_eq!(
        FetchSpec::parse(&request).unwrap().timeout,
        Duration::from_secs(180)
    );
    request.timeout = Some(bazel_remote_apis::google::protobuf::Duration {
        seconds: 600,
        nanos: 0,
    });
    assert_eq!(
        FetchSpec::parse(&request).unwrap().timeout,
        Duration::from_secs(180)
    );
    request.timeout.as_mut().unwrap().seconds = 10;
    assert_eq!(
        FetchSpec::parse(&request).unwrap().timeout,
        Duration::from_secs(10)
    );
}

#[test]
#[ignore = "manual hashing resource comparison"]
fn hashing_resource_comparison() {
    use super::request::IntegrityHasher;
    let chunk = vec![17_u8; 64 * 1024];
    for legacy in [true, false] {
        let start = std::time::Instant::now();
        let mut cas = Sha256::new();
        let mut extra = IntegrityHasher::new(None);
        let mut sha384 = sha2::Sha384::new();
        let mut sha512 = sha2::Sha512::new();
        for _ in 0..16384 {
            cas.update(std::hint::black_box(&chunk));
            if legacy {
                sha384.update(&chunk);
                sha512.update(&chunk);
            } else {
                extra.update(&chunk);
            }
        }
        std::hint::black_box((cas.finalize(), sha384.finalize(), sha512.finalize(), extra));
        println!(
            "hashing legacy={legacy} bytes=1073741824 seconds={:.6}",
            start.elapsed().as_secs_f64()
        );
    }
}
