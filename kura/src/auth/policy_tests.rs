//! The policy, driven end to end against a stand-in for Tuist's server.
//!
//! Each test builds an engine pointed at a mock and asserts the decision a real
//! request would get, so the fallbacks between verifying a token, introspecting
//! it, and asking the legacy route are exercised as a whole rather than
//! separately. The engine is configured directly rather than through process
//! environment variables, which are shared with every other test in the
//! binary.

use std::collections::BTreeMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use axum::{
    Json, Router,
    http::{HeaderMap, StatusCode},
    routing::{get, post},
};
use jsonwebtoken::Algorithm;
use serde_json::{Map, Value, json};

use super::config::AuthConfig;
use super::tuist::{IntrospectionCredentials, JwtVerifier};
use super::{AccessDecision, AuthEngine, DenyDecision, RequestContext, SharedAuth};
use crate::metrics::Metrics;

const GUARDIAN_SECRET: &str = "tuist-guardian-secret";

use std::sync::Mutex;

async fn spawn_tuist_auth_mock<FIntrospect, FCache>(
    introspect_handler: FIntrospect,
    cache_access_handler: FCache,
) -> String
where
    FIntrospect: Fn(HeaderMap, Value) -> (StatusCode, Value) + Send + Sync + 'static,
    FCache: Fn(HeaderMap) -> (StatusCode, Value) + Send + Sync + 'static,
{
    let introspect_handler = Arc::new(introspect_handler);
    let cache_access_handler = Arc::new(cache_access_handler);
    let app = Router::new()
        .route(
            "/oauth2/introspect",
            post(move |headers: HeaderMap, Json(payload): Json<Value>| {
                let introspect_handler = introspect_handler.clone();
                async move {
                    let (status, payload) = introspect_handler(headers, payload);
                    (status, Json(payload))
                }
            }),
        )
        .route(
            "/api/cache/access",
            get(move |headers: HeaderMap| {
                let cache_access_handler = cache_access_handler.clone();
                async move {
                    let (status, payload) = cache_access_handler(headers);
                    (status, Json(payload))
                }
            }),
        );

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind tuist auth mock");
    let address = listener.local_addr().expect("tuist auth mock addr");
    tokio::spawn(async move {
        axum::serve(listener, app)
            .await
            .expect("tuist auth mock serve");
    });
    format!("http://{address}")
}

fn engine_pointing_at(base_url: &str, introspection_client: bool) -> SharedAuth {
    engine_pointing_at_with_timeout(base_url, introspection_client, 4000)
}

fn engine_pointing_at_with_timeout(
    base_url: &str,
    introspection_client: bool,
    request_timeout_ms: u64,
) -> SharedAuth {
    engine(AuthConfig {
        base_url: base_url.to_owned(),
        connect_timeout: Duration::from_millis(500),
        request_timeout: Duration::from_millis(request_timeout_ms),
        verifier: Some(JwtVerifier {
            algorithm: Algorithm::HS512,
            secret: GUARDIAN_SECRET.into(),
            issuer: Some("tuist".into()),
            audiences: Vec::new(),
        }),
        introspection: introspection_client.then(introspection_credentials),
        cache_max_entries: 1000,
    })
}

// A node holding no verification key has to ask about every token it sees.
fn engine_introspection_only(base_url: &str) -> SharedAuth {
    engine(AuthConfig {
        base_url: base_url.to_owned(),
        connect_timeout: Duration::from_millis(500),
        request_timeout: Duration::from_millis(5000),
        verifier: None,
        introspection: Some(introspection_credentials()),
        cache_max_entries: 1000,
    })
}

fn introspection_credentials() -> IntrospectionCredentials {
    IntrospectionCredentials {
        client_id: "00000000-0000-0000-0000-000000000001".into(),
        client_secret: "kura-secret".into(),
    }
}

fn engine(config: AuthConfig) -> SharedAuth {
    engine_with_metrics(config, Metrics::new("test".into(), "tenant".into()))
}

fn engine_with_metrics(config: AuthConfig, metrics: Metrics) -> SharedAuth {
    Arc::new(AuthEngine::new(config, metrics).expect("build the authorization engine"))
}

fn ctx() -> RequestContext {
    RequestContext {
        transport: "http".into(),
        route: "/api/cache/gradle/{cache_key}".into(),
        method: "GET".into(),
        operation: "artifact.read".into(),
        server_tenant_id: "acme".into(),
        tenant_id: None,
        namespace_id: None,
        producer: Some("gradle".into()),
        artifact_key: None,
        artifact_hash: None,
        headers: BTreeMap::new(),
        query: BTreeMap::new(),
        status_code: None,
    }
}

fn cache_access_payload(accounts: &[&str], projects: &[&str]) -> Value {
    json!({
        "accounts": accounts,
        "projects": projects,
    })
}

fn cache_grants_payload(
    account_read: &[&str],
    account_write: &[&str],
    project_read: &[&str],
    project_write: &[&str],
) -> Value {
    json!({
        "account": {
            "read": account_read,
            "write": account_write,
        },
        "project": {
            "read": project_read,
            "write": project_write,
        },
    })
}

fn introspection_payload(grants: Value) -> Value {
    json!({
        "active": true,
        "sub": "subject-1",
        "principal_kind": "account",
        "cache_grants": grants,
    })
}

fn guardian_jwt(claims: Value) -> String {
    let mut claims = match claims {
        Value::Object(map) => map,
        _ => Map::new(),
    };
    claims.insert("sub".into(), json!("user-1"));
    claims.insert("iss".into(), json!("tuist"));
    claims.insert("exp".into(), json!(4_000_000_000u64));

    jsonwebtoken::encode(
        &jsonwebtoken::Header::new(Algorithm::HS512),
        &Value::Object(claims),
        &jsonwebtoken::EncodingKey::from_secret(GUARDIAN_SECRET.as_bytes()),
    )
    .expect("failed to sign guardian test token")
}

#[tokio::test]
async fn denies_when_authorization_header_is_missing() {
    let engine = engine_pointing_at("http://127.0.0.1:1", true);

    let decision = engine.evaluate_access(&ctx()).await;

    let deny = expect_deny(decision);
    assert_eq!(deny.status, 401);
    assert!(deny.message.contains("Missing Authorization"));
}

#[tokio::test]
async fn self_hosted_introspection_only_loads_and_denies_without_authorization() {
    // A node with no verifier configured still fails closed
    // on an unauthenticated request.
    let engine = engine_introspection_only("http://127.0.0.1:1");

    let deny = expect_deny(engine.evaluate_access(&ctx()).await);
    assert_eq!(deny.status, 401);
    assert!(deny.message.contains("Missing Authorization"));
}

#[tokio::test]
async fn self_hosted_introspection_only_allows_valid_token() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &[], &["acme/ios"], &["acme/ios"])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_introspection_only(&base);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context.namespace_id = Some("ios".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let decision = engine.evaluate_access(&context).await;
    assert!(matches!(decision, AccessDecision::Allow));
}

#[tokio::test]
async fn self_hosted_introspection_only_denies_inactive_token() {
    // A token the tenant-scoped introspection rejects (inactive, e.g. a
    // foreign tenant's token) is denied with no verifier in play.
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| (StatusCode::OK, json!({ "active": false })),
        |_| (StatusCode::UNAUTHORIZED, json!({})),
    )
    .await;
    let engine = engine_introspection_only(&base);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context.namespace_id = Some("ios".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    assert!(matches!(
        engine.evaluate_access(&context).await,
        AccessDecision::Deny(_)
    ));
}

#[tokio::test]
async fn allows_when_introspection_returns_project_grants() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &[], &["acme/ios"], &["acme/ios"])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());
    context.tenant_id = Some("acme".into());
    context.namespace_id = Some("ios".into());

    let decision = engine.evaluate_access(&context).await;
    assert!(matches!(decision, AccessDecision::Allow));
}

#[tokio::test]
async fn allows_namespace_only_grpc_requests_for_bazel() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(
                    &[],
                    &[],
                    &["acme/bazel"],
                    &["acme/bazel"],
                )),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.transport = "grpc".into();
    context.route =
        "build.bazel.remote.execution.v2.ContentAddressableStorage/FindMissingBlobs".into();
    context.method = "RPC".into();
    context.tenant_id = None;
    context.namespace_id = Some("bazel".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let decision = engine.evaluate_access(&context).await;
    assert!(matches!(decision, AccessDecision::Allow));
}

#[tokio::test]
async fn denies_namespace_only_http_project_requests() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &[], &["acme/ios"], &["acme/ios"])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &["acme/ios"])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = None;
    context.namespace_id = Some("ios".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let deny = expect_deny(engine.evaluate_access(&context).await);
    assert_eq!(deny.status, 400);
    assert!(deny.message.contains("Missing tenant_id"));
}

#[tokio::test]
async fn allows_when_introspection_returns_account_grants() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&["acme"], &["acme"], &[], &[])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let decision = engine.evaluate_access(&context).await;
    assert!(matches!(decision, AccessDecision::Allow));
}

#[tokio::test]
async fn allows_account_writes_when_introspection_returns_write_grants() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &["acme"], &[], &[])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.method = "POST".into();
    context.operation = "artifact.write".into();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let decision = engine.evaluate_access(&context).await;
    assert!(matches!(decision, AccessDecision::Allow));
}

#[tokio::test]
async fn denies_project_writes_when_introspection_only_returns_read_grants() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &[], &["acme/ios"], &[])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.method = "POST".into();
    context.operation = "artifact.write".into();
    context.tenant_id = Some("acme".into());
    context.namespace_id = Some("ios".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let deny = expect_deny(engine.evaluate_access(&context).await);
    assert_eq!(deny.status, 403);
    assert!(deny.message.contains("project 'acme/ios'"));
}

#[tokio::test]
async fn authorizes_from_local_jwt_cache_grants_without_introspection() {
    let engine = engine_pointing_at("http://127.0.0.1:1", false);
    let token = guardian_jwt(json!({
        "type": "account",
        "cache_grants": cache_grants_payload(&[], &[], &["acme/ios"], &["acme/ios"]),
        "scopes": ["project:cache:read"],
    }));

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), format!("Bearer {token}"));
    context.namespace_id = Some("ios".into());

    let decision = engine.evaluate_access(&context).await;
    assert!(matches!(decision, AccessDecision::Allow));
}

#[tokio::test]
async fn falls_back_to_introspection_when_jwt_cache_grants_do_not_cover_requested_project() {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            *calls_for_handler.lock().unwrap() += 1;
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &[], &["acme/ios"], &["acme/ios"])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);
    let token = guardian_jwt(json!({
        "type": "account",
        "cache_grants": cache_grants_payload(&[], &[], &["acme/android"], &["acme/android"]),
        "scopes": ["project:cache:read"],
    }));

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), format!("Bearer {token}"));
    context.namespace_id = Some("ios".into());

    let decision = engine.evaluate_access(&context).await;
    assert!(matches!(decision, AccessDecision::Allow));
    assert_eq!(*calls.lock().unwrap(), 1);
}

#[tokio::test]
async fn falls_back_to_legacy_cache_access_when_active_introspection_grants_do_not_cover_project() {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(
                    &[],
                    &[],
                    &["acme/android"],
                    &["acme/android"],
                )),
            )
        },
        move |_| {
            *calls_for_handler.lock().unwrap() += 1;
            (StatusCode::OK, cache_access_payload(&[], &["acme/ios"]))
        },
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());
    context.namespace_id = Some("ios".into());

    let decision = engine.evaluate_access(&context).await;
    assert!(matches!(decision, AccessDecision::Allow));
    assert_eq!(*calls.lock().unwrap(), 1);
}

// The first attempt is failed by dropping the connection rather than by
// letting a timeout expire, so the retry is proven without racing the clock.
async fn spawn_introspection_mock_that_drops_its_first_connection(
    body: Value,
) -> (String, Arc<Mutex<usize>>) {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind introspection mock");
    let address = listener.local_addr().expect("introspection mock addr");
    let connections = Arc::new(Mutex::new(0usize));
    let connections_for_server = connections.clone();

    tokio::spawn(async move {
        loop {
            let Ok((mut stream, _)) = listener.accept().await else {
                return;
            };
            let attempt = {
                let mut connections = connections_for_server.lock().expect("mock counter");
                *connections += 1;
                *connections
            };
            if attempt == 1 {
                drop(stream);
                continue;
            }

            let mut request = vec![0_u8; 8192];
            let _ = stream.read(&mut request).await;
            let payload = serde_json::to_vec(&body).expect("encode mock body");
            let head = format!(
                "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n",
                payload.len()
            );
            let _ = stream.write_all(head.as_bytes()).await;
            let _ = stream.write_all(&payload).await;
            let _ = stream.shutdown().await;
        }
    });

    (format!("http://{address}"), connections)
}

#[tokio::test]
async fn retries_introspection_transport_failures_once() {
    let (base, connections) = spawn_introspection_mock_that_drops_its_first_connection(
        introspection_payload(cache_grants_payload(&[], &[], &["acme/ios"], &["acme/ios"])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context.namespace_id = Some("ios".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let decision = engine.evaluate_access(&context).await;

    assert!(matches!(decision, AccessDecision::Allow));
    assert_eq!(*connections.lock().expect("mock counter"), 2);
}

#[tokio::test]
async fn falls_back_to_legacy_cache_access_for_project_requests_when_introspection_client_is_missing()
 {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &[], &[], &[])),
            )
        },
        move |_| {
            *calls_for_handler.lock().unwrap() += 1;
            (StatusCode::OK, cache_access_payload(&[], &["acme/ios"]))
        },
    )
    .await;
    let engine = engine_pointing_at(&base, false);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());
    context.namespace_id = Some("ios".into());

    let decision = engine.evaluate_access(&context).await;
    assert!(matches!(decision, AccessDecision::Allow));
    assert_eq!(*calls.lock().unwrap(), 1);
}

// A burst of requests carrying the same credentials must cost one
// introspection, not one per request. The requests are polled on a
// single task, so the leader reaches its backend call and yields before
// the rest join as followers.
#[tokio::test]
async fn concurrent_requests_with_the_same_credentials_introspect_once() {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            *calls_for_handler.lock().unwrap() += 1;
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&["acme"], &["acme"], &[], &[])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let requests = (0..25).map(|_| {
        let engine = engine.clone();
        async move {
            let mut context = ctx();
            context.tenant_id = Some("acme".into());
            context
                .headers
                .insert("authorization".into(), "Bearer opaque-token".into());
            engine.evaluate_access(&context).await
        }
    });
    let decisions = futures_util::future::join_all(requests).await;

    assert_eq!(decisions.len(), 25);
    for decision in decisions {
        assert!(matches!(decision, AccessDecision::Allow));
    }
    assert_eq!(*calls.lock().unwrap(), 1);
}

// The legacy route only speaks about projects, so the principal it returns
// cannot answer an account request. It must not answer one just because a
// project request carrying the same token resolved first: this node has no
// introspection credentials, and that is the answer either way.
#[tokio::test]
async fn does_not_reuse_legacy_project_fallback_for_account_requests() {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &[], &[], &[])),
            )
        },
        move |_| {
            *calls_for_handler.lock().unwrap() += 1;
            (
                StatusCode::OK,
                cache_access_payload(&["acme"], &["acme/ios"]),
            )
        },
    )
    .await;
    let engine = engine_pointing_at(&base, false);

    let mut project_context = ctx();
    project_context.tenant_id = Some("acme".into());
    project_context.namespace_id = Some("ios".into());
    project_context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let project_decision = engine.evaluate_access(&project_context).await;
    assert!(matches!(project_decision, AccessDecision::Allow));

    let mut account_context = ctx();
    account_context.tenant_id = Some("acme".into());
    account_context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let deny = expect_deny(engine.evaluate_access(&account_context).await);
    assert_eq!(deny.status, 503);
    assert!(deny.message.contains("account-scoped"));
    assert_eq!(*calls.lock().unwrap(), 1);
}

#[tokio::test]
async fn denies_account_scoped_requests_when_introspection_client_is_missing() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&["acme"], &["acme"], &[], &[])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&["acme"], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, false);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let deny = expect_deny(engine.evaluate_access(&context).await);
    assert_eq!(deny.status, 503);
}

#[tokio::test]
async fn forwards_introspection_credentials_and_token() {
    let captured = Arc::new(Mutex::new(None::<Value>));
    let captured_for_handler = captured.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, payload| {
            *captured_for_handler.lock().unwrap() = Some(payload);
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &[], &["acme/ios"], &["acme/ios"])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());
    context.namespace_id = Some("ios".into());

    let _ = engine.evaluate_access(&context).await;

    assert_eq!(
        *captured.lock().unwrap(),
        Some(json!({
            "client_id": "00000000-0000-0000-0000-000000000001",
            "client_secret": "kura-secret",
            "token": "opaque-token",
        }))
    );
}

#[tokio::test]
async fn falls_back_to_legacy_cache_access_when_introspection_marks_project_token_inactive() {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| (StatusCode::OK, json!({ "active": false })),
        move |_| {
            *calls_for_handler.lock().unwrap() += 1;
            (StatusCode::OK, cache_access_payload(&[], &["acme/ios"]))
        },
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer legacy-token".into());
    context.namespace_id = Some("ios".into());

    let decision = engine.evaluate_access(&context).await;
    assert!(matches!(decision, AccessDecision::Allow));
    assert_eq!(*calls.lock().unwrap(), 1);
}

#[tokio::test]
async fn denies_when_introspection_returns_inactive() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| (StatusCode::OK, json!({ "active": false })),
        |_| {
            (
                StatusCode::UNAUTHORIZED,
                json!({ "message": "Invalid or expired token" }),
            )
        },
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer bad-token".into());
    context.namespace_id = Some("ios".into());

    let deny = expect_deny(engine.evaluate_access(&context).await);
    assert_eq!(deny.status, 401);
}

#[tokio::test]
async fn denies_when_introspection_backend_is_unavailable() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| (StatusCode::INTERNAL_SERVER_ERROR, json!({})),
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer bad-token".into());
    context.namespace_id = Some("ios".into());

    let deny = expect_deny(engine.evaluate_access(&context).await);
    assert_eq!(deny.status, 503);
}

#[tokio::test]
async fn authorizes_case_insensitively_like_current_cache_nodes() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &[], &["Acme/iOS"], &["Acme/iOS"])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());
    context.query.insert("account_handle".into(), "ACME".into());
    context.query.insert("project_handle".into(), "IOS".into());

    let decision = engine.evaluate_access(&context).await;
    assert!(matches!(decision, AccessDecision::Allow));
}

#[tokio::test]
async fn denies_when_request_tenant_does_not_match_server_tenant() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(
                    &["someone-else"],
                    &["someone-else"],
                    &["someone-else/ios"],
                    &["someone-else/ios"],
                )),
            )
        },
        |_| {
            (
                StatusCode::OK,
                cache_access_payload(&["someone-else"], &["someone-else/ios"]),
            )
        },
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());
    context
        .query
        .insert("account_handle".into(), "someone-else".into());
    context.query.insert("project_handle".into(), "ios".into());

    let deny = expect_deny(engine.evaluate_access(&context).await);
    assert_eq!(deny.status, 403);
    assert!(deny.message.contains("server for"));
}

// A control-plane blip must not become a cache outage. Revalidation asks the
// backend again; a backend that cannot answer knows nothing new about the
// credential, so the principal it did confirm keeps serving. Without this the
// deny is cached for DENY_TTL and re-derived every few seconds for as long as
// the outage lasts, and every client sharing the token 5xxes for all of it.
#[tokio::test]
async fn an_unreachable_backend_keeps_serving_the_principal_it_last_confirmed() {
    let reachable = Arc::new(AtomicBool::new(true));
    let reachable_for_handler = reachable.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            if reachable_for_handler.load(Ordering::SeqCst) {
                (
                    StatusCode::OK,
                    introspection_payload(cache_grants_payload(&["acme"], &["acme"], &[], &[])),
                )
            } else {
                (StatusCode::INTERNAL_SERVER_ERROR, json!({}))
            }
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    assert!(matches!(
        engine.evaluate_access(&context).await,
        AccessDecision::Allow
    ));

    engine.expire_serving_deadline(&context).await;
    reachable.store(false, Ordering::SeqCst);

    assert!(matches!(
        engine.evaluate_access(&context).await,
        AccessDecision::Allow
    ));
}

// The reuse above covers a backend that did not answer. One that did — even to
// reject the token — is taken at its word, and the entry goes with it.
#[tokio::test]
async fn a_backend_that_rejects_the_token_is_taken_at_its_word() {
    let active = Arc::new(AtomicBool::new(true));
    let active_for_handler = active.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            if active_for_handler.load(Ordering::SeqCst) {
                (
                    StatusCode::OK,
                    introspection_payload(cache_grants_payload(&["acme"], &["acme"], &[], &[])),
                )
            } else {
                (StatusCode::OK, json!({ "active": false }))
            }
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    assert!(matches!(
        engine.evaluate_access(&context).await,
        AccessDecision::Allow
    ));

    engine.expire_serving_deadline(&context).await;
    active.store(false, Ordering::SeqCst);

    let deny = expect_deny(engine.evaluate_access(&context).await);
    assert_eq!(deny.status, 401);

    // And it stays rejected: the entry the reuse would have drawn on is gone.
    let deny = expect_deny(engine.evaluate_access(&context).await);
    assert_eq!(deny.status, 401);
}

// Revalidation happens off a cache hit, which moka's own coalescing does not
// cover. One request asks the backend and the rest take its answer, or a
// control plane that is already struggling gets a burst at the moment the
// serving deadline passes.
#[tokio::test]
async fn concurrent_revalidations_of_the_same_credentials_introspect_once() {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            *calls_for_handler.lock().unwrap() += 1;
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&["acme"], &["acme"], &[], &[])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    assert!(matches!(
        engine.evaluate_access(&context).await,
        AccessDecision::Allow
    ));
    assert_eq!(*calls.lock().unwrap(), 1);

    engine.expire_serving_deadline(&context).await;

    let requests = (0..25).map(|_| {
        let engine = engine.clone();
        let context = context.clone();
        async move { engine.evaluate_access(&context).await }
    });
    for decision in futures_util::future::join_all(requests).await {
        assert!(matches!(decision, AccessDecision::Allow));
    }

    assert_eq!(*calls.lock().unwrap(), 2);
}

// A principal is about the credential, not about one target. A second project
// its grants already cover is answered from it, without a second call — and
// that is what lets a build's first write mid-outage be served from the read it
// did a minute earlier.
#[tokio::test]
async fn a_second_project_the_grants_cover_is_answered_from_the_same_principal() {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            *calls_for_handler.lock().unwrap() += 1;
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(
                    &[],
                    &[],
                    &["acme/ios", "acme/android"],
                    &["acme/ios", "acme/android"],
                )),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut ios = ctx();
    ios.tenant_id = Some("acme".into());
    ios.namespace_id = Some("ios".into());
    ios.headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let mut android = ios.clone();
    android.namespace_id = Some("android".into());

    let mut ios_write = ios.clone();
    ios_write.method = "PUT".into();
    ios_write.operation = "artifact.write".into();

    assert!(matches!(
        engine.evaluate_access(&ios).await,
        AccessDecision::Allow
    ));
    assert_eq!(*calls.lock().unwrap(), 1);

    for context in [&android, &ios_write] {
        assert!(matches!(
            engine.evaluate_access(context).await,
            AccessDecision::Allow
        ));
    }
    assert_eq!(*calls.lock().unwrap(), 1);
}

// A project the grants do not cover is a different question, and the principal
// settles nothing about it: the legacy route may still allow it. So it costs a
// call, and its refusal is held against that project alone.
#[tokio::test]
async fn a_project_the_grants_do_not_cover_is_asked_about_on_its_own() {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            *calls_for_handler.lock().unwrap() += 1;
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &[], &["acme/ios"], &["acme/ios"])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut ios = ctx();
    ios.tenant_id = Some("acme".into());
    ios.namespace_id = Some("ios".into());
    ios.headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let mut android = ios.clone();
    android.namespace_id = Some("android".into());

    assert!(matches!(
        engine.evaluate_access(&ios).await,
        AccessDecision::Allow
    ));
    assert_eq!(*calls.lock().unwrap(), 1);

    let deny = expect_deny(engine.evaluate_access(&android).await);
    assert_eq!(deny.status, 403);
    assert_eq!(*calls.lock().unwrap(), 2);

    // And the refusal did not cost the project that was allowed.
    assert!(matches!(
        engine.evaluate_access(&ios).await,
        AccessDecision::Allow
    ));
    assert_eq!(*calls.lock().unwrap(), 2);
}

// Nothing to fall back to means the node still fails closed.
#[tokio::test]
async fn counts_and_denies_when_the_backend_is_unavailable_and_nothing_is_known_yet() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| (StatusCode::INTERNAL_SERVER_ERROR, json!({})),
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let metrics = Metrics::new("test".into(), "tenant".into());
    let engine = engine_with_metrics(
        AuthConfig {
            base_url: base.clone(),
            connect_timeout: Duration::from_millis(500),
            request_timeout: Duration::from_millis(4000),
            verifier: Some(JwtVerifier {
                algorithm: Algorithm::HS512,
                secret: GUARDIAN_SECRET.into(),
                issuer: Some("tuist".into()),
                audiences: Vec::new(),
            }),
            introspection: Some(introspection_credentials()),
            cache_max_entries: 1000,
        },
        metrics.clone(),
    );

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context.namespace_id = Some("ios".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let deny = expect_deny(engine.evaluate_access(&context).await);
    assert_eq!(deny.status, 503);

    let rendered = metrics.render();
    assert!(
        rendered
            .lines()
            .any(|line| line.starts_with("kura_auth_decisions_total")
                && line.contains("stage=\"authenticate\"")
                && line.contains("result=\"unavailable\"")),
        "expected an unavailable authenticate decision, got:\n{rendered}"
    );
}

fn expect_deny(decision: AccessDecision) -> DenyDecision {
    match decision {
        AccessDecision::Deny(deny) => deny,
        AccessDecision::Allow => panic!("expected deny, got allow"),
    }
}

// The headline of the outage story. A build reads a project for its whole
// serving window, then issues its first upload while the control plane is
// down. The principal confirmed for the read covers the write, so the upload
// is served from it instead of being refused for being shaped differently
// from the traffic that came before it.
#[tokio::test]
async fn an_outage_serves_a_write_from_the_principal_confirmed_for_a_read() {
    let reachable = Arc::new(AtomicBool::new(true));
    let reachable_for_handler = reachable.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            if reachable_for_handler.load(Ordering::SeqCst) {
                (
                    StatusCode::OK,
                    introspection_payload(cache_grants_payload(
                        &[],
                        &[],
                        &["acme/ios"],
                        &["acme/ios"],
                    )),
                )
            } else {
                (StatusCode::INTERNAL_SERVER_ERROR, json!({}))
            }
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut read = ctx();
    read.tenant_id = Some("acme".into());
    read.namespace_id = Some("ios".into());
    read.headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    let mut write = read.clone();
    write.method = "PUT".into();
    write.operation = "artifact.write".into();

    assert!(matches!(
        engine.evaluate_access(&read).await,
        AccessDecision::Allow
    ));

    engine.expire_serving_deadline(&read).await;
    reachable.store(false, Ordering::SeqCst);

    assert!(matches!(
        engine.evaluate_access(&write).await,
        AccessDecision::Allow
    ));
}

// A request that cannot take the consultation lock must not queue behind the
// probe that holds it. Against a control plane that black holes rather than
// refuses, that probe runs for as long as the timeouts allow, and parking every
// request for it to learn something the node is already holding helps nobody.
// It is served from what the node holds, and it asks nothing of the backend.
#[tokio::test]
async fn a_request_is_served_from_what_the_node_holds_rather_than_queueing_behind_a_probe() {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            *calls_for_handler.lock().unwrap() += 1;
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&["acme"], &["acme"], &[], &[])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    assert!(matches!(
        engine.evaluate_access(&context).await,
        AccessDecision::Allow
    ));
    assert_eq!(*calls.lock().unwrap(), 1);

    engine.expire_serving_deadline(&context).await;
    let probing = engine.hold_consultation(&context).await;

    assert!(matches!(
        engine.evaluate_access(&context).await,
        AccessDecision::Allow
    ));
    assert_eq!(*calls.lock().unwrap(), 1);

    drop(probing);
}

// A credential past its own expiry has nothing to gain from the server: it
// validates `exp` too and would answer inactive. Refusing here keeps a client
// looping on a stale token off the control plane.
#[tokio::test]
async fn an_expired_credential_is_refused_without_asking_the_backend() {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            *calls_for_handler.lock().unwrap() += 1;
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&["acme"], &["acme"], &[], &[])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let expired = jsonwebtoken::encode(
        &jsonwebtoken::Header::new(Algorithm::HS512),
        &json!({
            "sub": "user-1",
            "iss": "tuist",
            "exp": seconds_since_epoch() - 3600,
        }),
        &jsonwebtoken::EncodingKey::from_secret(GUARDIAN_SECRET.as_bytes()),
    )
    .expect("sign an expired token");

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), format!("Bearer {expired}"));

    let deny = expect_deny(engine.evaluate_access(&context).await);
    assert_eq!(deny.status, 401);
    assert_eq!(*calls.lock().unwrap(), 0);
}

fn seconds_since_epoch() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("a clock after the epoch")
        .as_secs()
}

// Folding one answer into the next must not overrule a refusal. A server that
// narrows a token reports it still active with the project gone from its
// grants, so the request that triggers the consultation is refused while the
// node still holds a principal that grants it. Folding that back in would
// re-grant exactly what was just taken away, for every request after the first.
#[tokio::test]
async fn a_grant_the_server_has_withdrawn_is_not_folded_back_in() {
    let narrowed = Arc::new(AtomicBool::new(false));
    let narrowed_for_handler = narrowed.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            let grants = if narrowed_for_handler.load(Ordering::SeqCst) {
                cache_grants_payload(&[], &[], &[], &[])
            } else {
                cache_grants_payload(&[], &[], &["acme/ios"], &["acme/ios"])
            };
            (StatusCode::OK, introspection_payload(grants))
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context.namespace_id = Some("ios".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    assert!(matches!(
        engine.evaluate_access(&context).await,
        AccessDecision::Allow
    ));
    engine.expire_serving_deadline(&context).await;
    narrowed.store(true, Ordering::SeqCst);

    // The first refusal is judged on the server's answer; the ones after it are
    // judged on whatever the fold wrote back.
    for _ in 0..3 {
        let deny = expect_deny(engine.evaluate_access(&context).await);
        assert_eq!(deny.status, 403);
    }
}

// A token can be withdrawn entirely, and the server says so with a 401 rather
// than by narrowing. That is not about one project, so the principal goes with
// it — otherwise every other project it covers keeps being served.
#[tokio::test]
async fn a_revoked_credential_stops_serving_the_projects_it_still_covers() {
    let revoked = Arc::new(AtomicBool::new(false));
    let revoked_for_introspect = revoked.clone();
    let revoked_for_cache = revoked.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            if revoked_for_introspect.load(Ordering::SeqCst) {
                (StatusCode::OK, json!({ "active": false }))
            } else {
                (
                    StatusCode::OK,
                    introspection_payload(cache_grants_payload(
                        &[],
                        &[],
                        &["acme/ios"],
                        &["acme/ios"],
                    )),
                )
            }
        },
        move |_| {
            if revoked_for_cache.load(Ordering::SeqCst) {
                (StatusCode::UNAUTHORIZED, json!({}))
            } else {
                (StatusCode::OK, cache_access_payload(&[], &[]))
            }
        },
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let project = |name: &str| {
        let mut context = ctx();
        context.tenant_id = Some("acme".into());
        context.namespace_id = Some(name.into());
        context
            .headers
            .insert("authorization".into(), "Bearer opaque-token".into());
        context
    };

    assert!(matches!(
        engine.evaluate_access(&project("ios")).await,
        AccessDecision::Allow
    ));
    revoked.store(true, Ordering::SeqCst);

    assert_eq!(
        expect_deny(engine.evaluate_access(&project("android")).await).status,
        401
    );

    // The decision already worked out for `ios` stands for its few seconds;
    // what must not survive it is the principal behind it.
    engine.expire_decisions().await;
    assert_eq!(
        expect_deny(engine.evaluate_access(&project("ios")).await).status,
        401
    );
}

// The verifier reads a credential for a minute past its own expiry, so the
// refusal in front of the backend has to hold off for exactly as long. Inside
// that window the two disagreeing meant a credential was read from its own
// grants and refused everything they did not cover, without the server ever
// being asked whether the legacy route would have allowed it.
#[tokio::test]
async fn a_credential_inside_the_verifier_leeway_still_reaches_the_backend() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &[], &["acme/ios"], &["acme/ios"])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &["acme/android"])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let token = jsonwebtoken::encode(
        &jsonwebtoken::Header::new(Algorithm::HS512),
        &json!({
            "sub": "user-1",
            "iss": "tuist",
            "exp": seconds_since_epoch() - 30,
            "cache_grants": cache_grants_payload(&[], &[], &["acme/ios"], &["acme/ios"]),
        }),
        &jsonwebtoken::EncodingKey::from_secret(GUARDIAN_SECRET.as_bytes()),
    )
    .expect("sign a just-expired token");

    let project = |name: &str| {
        let mut context = ctx();
        context.tenant_id = Some("acme".into());
        context.namespace_id = Some(name.into());
        context
            .headers
            .insert("authorization".into(), format!("Bearer {token}"));
        context
    };

    for name in ["ios", "android"] {
        assert!(
            matches!(
                engine.evaluate_access(&project(name)).await,
                AccessDecision::Allow
            ),
            "{name} should be allowed inside the verifier's leeway"
        );
    }
}

// Some routes name their target in the query rather than the path, which is
// the form the README documents. Both have to reach the same answer: keyed on
// the raw context fields the query form left them unset, so two projects
// looked identical and the first one's answer served the second.
#[tokio::test]
async fn a_target_named_in_the_query_is_authorized_like_one_named_in_the_path() {
    let base = spawn_tuist_auth_mock(
        |_headers, _payload| {
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&[], &[], &[], &[])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &["acme/ios"])),
    )
    .await;

    let query_form = |project: &str| {
        let mut context = ctx();
        context
            .headers
            .insert("authorization".into(), "Bearer opaque-token".into());
        context.query.insert("account_handle".into(), "acme".into());
        context
            .query
            .insert("project_handle".into(), project.into());
        context
    };
    let path_form = |project: &str| {
        let mut context = ctx();
        context
            .headers
            .insert("authorization".into(), "Bearer opaque-token".into());
        context.tenant_id = Some("acme".into());
        context.namespace_id = Some(project.into());
        context
    };

    for form in [
        &query_form as &dyn Fn(&str) -> RequestContext,
        &path_form as &dyn Fn(&str) -> RequestContext,
    ] {
        let engine = engine_pointing_at(&base, false);

        assert!(matches!(
            engine.evaluate_access(&form("ios")).await,
            AccessDecision::Allow
        ));

        let deny = expect_deny(engine.evaluate_access(&form("android")).await);
        assert_eq!(deny.status, 403);
        assert!(deny.message.contains("acme/android"));
    }
}

// The fast path is one lookup. A request shaped like one the node has already
// answered is answered from that, without reading the principal behind it or
// working out what it allows again.
#[tokio::test]
async fn a_repeat_of_a_request_already_answered_is_answered_from_that() {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            *calls_for_handler.lock().unwrap() += 1;
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(&["acme"], &["acme"], &[], &[])),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let metrics = Metrics::new("test".into(), "tenant".into());
    let engine = engine_with_metrics(
        AuthConfig {
            base_url: base.clone(),
            connect_timeout: Duration::from_millis(500),
            request_timeout: Duration::from_millis(4000),
            verifier: None,
            introspection: Some(introspection_credentials()),
            cache_max_entries: 1000,
        },
        metrics.clone(),
    );

    let mut context = ctx();
    context.tenant_id = Some("acme".into());
    context
        .headers
        .insert("authorization".into(), "Bearer opaque-token".into());

    for _ in 0..3 {
        assert!(matches!(
            engine.evaluate_access(&context).await,
            AccessDecision::Allow
        ));
    }
    assert_eq!(*calls.lock().unwrap(), 1);

    let rendered = metrics.render();
    assert!(
        rendered
            .lines()
            .any(|line| line.starts_with("kura_auth_cache_total")
                && line.contains("cache=\"decide\"")
                && line.contains("result=\"hit\"")),
        "expected the repeats to be answered from the decision cache, got:\n{rendered}"
    );
}

// A burst that spreads over several targets and actions is several questions,
// but it is still one credential. The requests coalesce per question, and the
// questions queue behind one consultation, so the whole burst costs one call
// rather than one per question.
#[tokio::test]
async fn a_burst_spread_over_targets_and_actions_costs_one_call() {
    let calls = Arc::new(Mutex::new(0usize));
    let calls_for_handler = calls.clone();
    let base = spawn_tuist_auth_mock(
        move |_headers, _payload| {
            *calls_for_handler.lock().unwrap() += 1;
            (
                StatusCode::OK,
                introspection_payload(cache_grants_payload(
                    &[],
                    &[],
                    &["acme/ios", "acme/android"],
                    &["acme/ios", "acme/android"],
                )),
            )
        },
        |_| (StatusCode::OK, cache_access_payload(&[], &[])),
    )
    .await;
    let engine = engine_pointing_at(&base, true);

    let request = |project: &str, write: bool| {
        let mut context = ctx();
        context.tenant_id = Some("acme".into());
        context.namespace_id = Some(project.into());
        context
            .headers
            .insert("authorization".into(), "Bearer opaque-token".into());
        if write {
            context.method = "PUT".into();
            context.operation = "artifact.write".into();
        }
        context
    };

    let contexts = [
        request("ios", false),
        request("ios", true),
        request("android", false),
        request("android", true),
    ];
    let requests = (0..40).map(|index| {
        let engine = engine.clone();
        let context = contexts[index % contexts.len()].clone();
        async move { engine.evaluate_access(&context).await }
    });

    let decisions = futures_util::future::join_all(requests).await;
    assert_eq!(decisions.len(), 40);
    for decision in decisions {
        assert!(matches!(decision, AccessDecision::Allow));
    }
    assert_eq!(*calls.lock().unwrap(), 1);
}
