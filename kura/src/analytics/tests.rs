
use std::sync::{Arc, Mutex};

use axum::{
    Router, body::Bytes, extract::Request, http::StatusCode, response::IntoResponse, routing::post,
};
use http_body_util::BodyExt;
use serde_json::Value;
use tokio::time::{Duration, Instant, sleep, timeout};

use crate::{config::AnalyticsConfig, metrics::Metrics};

use super::{Analytics, CircuitBreaker, CircuitState, analytics_endpoint, sign};

#[derive(Clone, Debug)]
struct CapturedRequest {
    path: String,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
}

#[tokio::test]
async fn batches_and_signs_xcode_and_gradle_events() {
    let captured = Arc::new(Mutex::new(Vec::<CapturedRequest>::new()));
    let (base_url, _handle) = spawn_capture_server(captured.clone()).await;
    let analytics = Analytics::from_config(
        Some(&AnalyticsConfig {
            server_url: base_url,
            signing_key: "secret-key".into(),
            batch_size: 1,
            batch_timeout_ms: 5_000,
            queue_capacity: 8,
            request_timeout_ms: 5_000,
            circuit_breaker_failure_threshold: 2,
            circuit_breaker_open_ms: 5_000,
        }),
        "https://cache-us-east-3.example.com:7443",
        Metrics::new("us-east".into(), "tenant".into()),
    )
    .expect("analytics should initialize")
    .expect("analytics should be enabled");

    analytics.enqueue_xcode_upload("acme", "ios", "cas-1", 42);
    analytics.enqueue_gradle_download("acme", "android", "gradle-key", 64);

    timeout(Duration::from_secs(2), async {
        loop {
            if captured.lock().expect("captured requests lock").len() >= 2 {
                break;
            }
            sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("analytics batches should be delivered");

    let requests = captured.lock().expect("captured requests lock");
    assert_eq!(requests.len(), 2);

    let xcode = requests
        .iter()
        .find(|request| request.path == "/webhooks/cache")
        .expect("xcode analytics request should be present");
    assert_signed(xcode, "secret-key", "cache-us-east-3.example.com:7443");
    let xcode_body: Value =
        serde_json::from_slice(&xcode.body).expect("xcode payload should decode");
    assert_eq!(
        xcode_body,
        serde_json::json!({
            "events": [{
                "account_handle": "acme",
                "project_handle": "ios",
                "action": "upload",
                "size": 42,
                "cas_id": "cas-1"
            }]
        })
    );

    let gradle = requests
        .iter()
        .find(|request| request.path == "/webhooks/gradle-cache")
        .expect("gradle analytics request should be present");
    assert_signed(gradle, "secret-key", "cache-us-east-3.example.com:7443");
    let gradle_body: Value =
        serde_json::from_slice(&gradle.body).expect("gradle payload should decode");
    assert_eq!(
        gradle_body,
        serde_json::json!({
            "events": [{
                "account_handle": "acme",
                "project_handle": "android",
                "action": "download",
                "size": 64,
                "cache_key": "gradle-key"
            }]
        })
    );
}

#[tokio::test]
async fn circuit_breaker_stops_delivery_after_repeated_failures() {
    let captured = Arc::new(Mutex::new(Vec::<CapturedRequest>::new()));
    let (base_url, _handle) =
        spawn_capture_server_with_status(captured.clone(), StatusCode::INTERNAL_SERVER_ERROR).await;
    let analytics = Analytics::from_config(
        Some(&AnalyticsConfig {
            server_url: base_url,
            signing_key: "secret-key".into(),
            batch_size: 1,
            batch_timeout_ms: 5_000,
            queue_capacity: 8,
            request_timeout_ms: 1_000,
            circuit_breaker_failure_threshold: 2,
            circuit_breaker_open_ms: 60_000,
        }),
        "https://cache-us-east-3.example.com:7443",
        Metrics::new("us-east".into(), "tenant".into()),
    )
    .expect("analytics should initialize")
    .expect("analytics should be enabled");

    analytics.enqueue_xcode_upload("acme", "ios", "cas-1", 1);
    analytics.enqueue_xcode_upload("acme", "ios", "cas-2", 1);
    analytics.enqueue_xcode_upload("acme", "ios", "cas-3", 1);
    analytics.enqueue_xcode_upload("acme", "ios", "cas-4", 1);

    timeout(Duration::from_secs(2), async {
        loop {
            if analytics.pending.load(std::sync::atomic::Ordering::Relaxed) == 0 {
                break;
            }
            sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("analytics queue should drain");

    let requests = captured.lock().expect("captured requests lock");
    assert_eq!(
        requests.len(),
        2,
        "only the first two failures should reach the upstream before the breaker opens"
    );
}

#[test]
fn derives_cache_endpoint_header_from_node_url() {
    assert_eq!(
        analytics_endpoint("https://cache-eu.example.com:7443"),
        "cache-eu.example.com:7443"
    );
    assert_eq!(
        analytics_endpoint("https://cache-eu.example.com"),
        "cache-eu.example.com"
    );
}

#[test]
fn circuit_breaker_opens_and_recovers() {
    let mut breaker = CircuitBreaker::new();
    let open_duration = Duration::from_secs(30);
    let now = Instant::now();

    assert!(breaker.allow_request(now, open_duration));
    assert_eq!(breaker.on_failure(now, 2, open_duration), None);
    assert_eq!(breaker.state, CircuitState::Closed);

    assert!(breaker.allow_request(now, open_duration));
    assert_eq!(
        breaker.on_failure(now, 2, open_duration),
        Some((CircuitState::Closed, CircuitState::Open))
    );
    assert_eq!(breaker.state, CircuitState::Open);
    assert!(!breaker.allow_request(now + Duration::from_secs(5), open_duration));

    assert!(breaker.allow_request(now + open_duration, open_duration));
    assert_eq!(breaker.state, CircuitState::HalfOpen);
    assert_eq!(
        breaker.on_success(),
        Some((CircuitState::HalfOpen, CircuitState::Closed))
    );
    assert_eq!(breaker.state, CircuitState::Closed);
}

fn assert_signed(request: &CapturedRequest, secret: &str, endpoint: &str) {
    let signature = request
        .headers
        .iter()
        .find(|(key, _)| key == "x-cache-signature")
        .map(|(_, value)| value.as_str())
        .expect("signature header should be present");
    assert_eq!(signature, sign(secret, &request.body));

    let cache_endpoint = request
        .headers
        .iter()
        .find(|(key, _)| key == "x-cache-endpoint")
        .map(|(_, value)| value.as_str())
        .expect("cache endpoint header should be present");
    assert_eq!(cache_endpoint, endpoint);
}

async fn spawn_capture_server(
    captured: Arc<Mutex<Vec<CapturedRequest>>>,
) -> (String, tokio::task::JoinHandle<()>) {
    spawn_capture_server_with_status(captured, StatusCode::ACCEPTED).await
}

async fn spawn_capture_server_with_status(
    captured: Arc<Mutex<Vec<CapturedRequest>>>,
    status: StatusCode,
) -> (String, tokio::task::JoinHandle<()>) {
    let router = Router::new()
        .route(
            "/webhooks/cache",
            post({
                let captured = captured.clone();
                move |request| capture_request(captured.clone(), request, status)
            }),
        )
        .route(
            "/webhooks/gradle-cache",
            post({
                let captured = captured.clone();
                move |request| capture_request(captured.clone(), request, status)
            }),
        );

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("test listener should bind");
    let address = listener
        .local_addr()
        .expect("test listener should expose local address");
    let handle = tokio::spawn(async move {
        axum::serve(listener, router)
            .await
            .expect("capture server should run");
    });

    (format!("http://{}", address), handle)
}

async fn capture_request(
    captured: Arc<Mutex<Vec<CapturedRequest>>>,
    request: Request,
    status: StatusCode,
) -> impl IntoResponse {
    let (parts, body) = request.into_parts();
    let body = body
        .collect()
        .await
        .expect("request body should collect")
        .to_bytes();
    let headers = parts
        .headers
        .iter()
        .map(|(key, value)| {
            (
                key.as_str().to_owned(),
                value.to_str().unwrap_or_default().to_owned(),
            )
        })
        .collect::<Vec<_>>();
    captured
        .lock()
        .expect("captured requests lock")
        .push(CapturedRequest {
            path: parts.uri.path().to_owned(),
            headers,
            body: Bytes::copy_from_slice(&body).to_vec(),
        });
    status
}
