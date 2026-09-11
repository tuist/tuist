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
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let router = Router::new()
        .route(
            "/file",
            get(move || {
                let hits = counter.clone();
                async move {
                    hits.fetch_add(1, Ordering::SeqCst);
                    PAYLOAD
                }
            }),
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
        axum::serve(listener, router).await.unwrap();
    });
    Origin { url, hits, task }
}

fn service(context: &TestContext) -> AssetService {
    let mut service = AssetService::new(ReapiService::new(context.state.clone()));
    service.allow_loopback = true;
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
    let response = client.fetch_blob(message).await.unwrap().into_inner();
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
