//! The network-trusted cache policy over gRPC. kura-node's auth policy tests cover the same policy
//! over HTTP; this crate owns the gRPC routes.

use std::{
    collections::BTreeMap,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use axum::{
    Json, Router,
    body::Body,
    http::{HeaderMap, Request},
    routing::get,
};
use http_body_util::BodyExt;
use serde_json::json;
use tower::ServiceExt;

use crate::{
    auth::{
        AccessDecision, AuthEngine, RequestContext, config::AuthConfig,
        tuist::IntrospectionCredentials,
    },
    metrics::Metrics,
};

#[tokio::test]
async fn network_cache_policy_authorizes_grpc_without_credentials_and_rejects_malformed_ones() {
    let calls = Arc::new(AtomicUsize::new(0));
    let policy = Router::new().route(
        "/_internal/kura/cache-policy",
        get({
            let calls = calls.clone();
            move |_: HeaderMap,
                  axum::extract::Query(query): axum::extract::Query<BTreeMap<String, String>>| {
                let calls = calls.clone();
                async move {
                    assert_eq!(query["tenant_id"], "acme");
                    calls.fetch_add(1, Ordering::SeqCst);
                    Json(json!({"tenant_id": "acme", "network_trusted_cache_access": true}))
                }
            }
        }),
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base_url = format!("http://{}", listener.local_addr().unwrap());
    let server = tokio::spawn(async move { axum::serve(listener, policy).await.unwrap() });
    let engine = Arc::new(
        AuthEngine::new(
            AuthConfig {
                base_url,
                connect_timeout: Duration::from_millis(500),
                request_timeout: Duration::from_millis(5000),
                verifier: None,
                introspection: Some(IntrospectionCredentials {
                    client_id: "00000000-0000-0000-0000-000000000001".into(),
                    client_secret: "kura-secret".into(),
                }),
                cache_max_entries: 1000,
            },
            Metrics::new("test".into(), "tenant".into()),
        )
        .expect("build the authorization engine"),
    );
    let request = RequestContext {
        transport: "http".into(),
        method: "GET".into(),
        operation: "artifact.read".into(),
        server_tenant_id: "acme".into(),
        tenant_id: Some("acme".into()),
        namespace_id: None,
        authorization: None,
        headers: BTreeMap::new(),
    };
    assert!(matches!(
        engine.evaluate_access(&request).await,
        AccessDecision::Allow
    ));
    let context = crate::test_support::test_context_with_auth(
        |config| config.tenant_id = "acme".into(),
        Some(engine),
    )
    .await;

    let grpc = crate::routes(context.state.clone());
    let path = "/build.bazel.remote.execution.v2.Capabilities/GetCapabilities";
    for (headers, expected) in [(vec![], "0"), (vec![""], "16"), (vec!["one", "two"], "16")] {
        let mut request = Request::builder()
            .method("POST")
            .uri(path)
            .header("content-type", "application/grpc")
            .header("te", "trailers");
        for header in headers {
            request = request.header("authorization", header);
        }
        let response = grpc
            .clone()
            .oneshot(request.body(Body::from(vec![0u8; 5])).unwrap())
            .await
            .unwrap();
        let status = response.headers().get("grpc-status").cloned();
        let body = response.into_body().collect().await.unwrap();
        let status = status.or_else(|| {
            body.trailers()
                .and_then(|trailers| trailers.get("grpc-status").cloned())
        });
        assert_eq!(status.unwrap().to_str().unwrap(), expected);
    }
    // The policy decision is cached, so the gRPC requests did not ask the server again.
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    server.abort();
}
