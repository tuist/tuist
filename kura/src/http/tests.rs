
use std::sync::{Arc, Mutex};

use axum::{Router, body::Body, extract::Request, response::IntoResponse, routing::post};
use http_body_util::BodyExt;
use serde_json::Value;
use tokio::time::{Duration, sleep, timeout};
use tower::ServiceExt;

use super::*;
use crate::{
    artifact::producer::ArtifactProducer,
    config::{AnalyticsConfig, UsageConfig},
    test_support::{response_text, test_context},
    utils::blob_key,
};

fn test_usage_config() -> UsageConfig {
    UsageConfig {
        control_plane_url: "http://localhost:0".to_owned(),
        client_id: "kura".to_owned(),
        client_secret: "secret".to_owned(),
        window_secs: 60,
        flush_interval_ms: 1_000,
        delivery_interval_ms: 1_000,
        batch_size: 100,
        max_buckets: 100,
        outbox_max_depth: 100,
    }
}

async fn assert_json_error_response(response: Response, status: StatusCode, message: &str) {
    assert_eq!(response.status(), status);
    assert_eq!(
        response.headers().get(axum::http::header::CONTENT_TYPE),
        Some(&HeaderValue::from_static("application/json"))
    );

    let body: Value = serde_json::from_str(&response_text(response).await)
        .expect("failed to decode error response");
    assert_eq!(body["message"], message);
}

#[tokio::test]
async fn up_includes_current_node_and_known_members() {
    let context = test_context(|config| {
        config.region = "us-east".into();
    })
    .await;
    context
        .state
        .apply_membership_view(
            std::collections::BTreeSet::from(["eu-west".to_string()]),
            std::collections::BTreeMap::from([(
                "http://peer.kura.internal:4000".to_string(),
                "eu-west".to_string(),
            )]),
            true,
        )
        .await;

    let response = router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/up")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("request failed");

    assert_eq!(response.status(), StatusCode::OK);
    let body: Value =
        serde_json::from_str(&response_text(response).await).expect("failed to decode up response");
    assert_eq!(body["ring_members"], 2);
    assert_eq!(body["generation"], 1);
    assert_eq!(body["region"], "us-east");
    assert_eq!(
        body["members"],
        serde_json::json!(["http://127.0.0.1:7443", "http://peer.kura.internal:4000"])
    );
    assert_eq!(body["regions"], serde_json::json!(["eu-west", "us-east"]));
    assert!(
        body["connected_nodes"]
            .to_string()
            .contains("http://peer.kura.internal:4000")
    );
}

#[tokio::test]
async fn up_reports_unique_regions_separately_from_node_members() {
    let context = test_context(|config| {
        config.region = "eu-central".into();
    })
    .await;
    context
        .state
        .apply_membership_view(
            std::collections::BTreeSet::from(["eu-central".to_string()]),
            std::collections::BTreeMap::from([
                (
                    "http://kura-1.kura-headless.kura.svc.cluster.local:7443".to_string(),
                    "eu-central".to_string(),
                ),
                (
                    "http://kura-2.kura-headless.kura.svc.cluster.local:7443".to_string(),
                    "eu-central".to_string(),
                ),
            ]),
            true,
        )
        .await;

    let response = router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/up")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("request failed");

    assert_eq!(response.status(), StatusCode::OK);
    let body: Value =
        serde_json::from_str(&response_text(response).await).expect("failed to decode up response");
    assert_eq!(body["ring_members"], 3);
    assert_eq!(body["regions"], serde_json::json!(["eu-central"]));
    assert_eq!(body["members"].as_array().expect("members array").len(), 3);
    assert_eq!(body["nodes"].as_array().expect("nodes array").len(), 3);
}

#[test]
fn route_template_for_path_stabilizes_cache_paths() {
    assert_eq!(route_template_for_path(ROUTE_UP), ROUTE_UP);
    assert_eq!(
        route_template_for_path("/api/cache/cas/artifact-one"),
        ROUTE_API_CACHE_CAS
    );
    assert_eq!(
        route_template_for_path("/api/cache/keyvalue/cas-one"),
        ROUTE_API_CACHE_KEYVALUE_ID
    );
    assert_eq!(
        route_template_for_path("/api/cache/gradle/cache-key-one"),
        ROUTE_API_CACHE_GRADLE
    );
    assert_eq!(
        route_template_for_path("/_internal/bootstrap/artifacts/artifact-one"),
        ROUTE_INTERNAL_BOOTSTRAP_ARTIFACT
    );
    assert_eq!(
        route_template_for_path("/api/cache/cas/artifact-one/extra"),
        UNMATCHED_ROUTE
    );
    assert_eq!(route_template_for_path("/.docker/.env"), UNMATCHED_ROUTE);
}

#[test]
fn public_load_routes_exclude_probes_internal_and_unmatched_routes() {
    assert!(is_public_load_route(ROUTE_API_CACHE_CAS));
    assert!(is_public_load_route(ROUTE_API_CACHE_MODULE));
    assert!(!is_public_load_route(ROUTE_UP));
    assert!(!is_public_load_route(ROUTE_METRICS));
    assert!(!is_public_load_route(ROUTE_INTERNAL_REPLICATE_ARTIFACT));
    assert!(!is_public_load_route(UNMATCHED_ROUTE));
}

#[tokio::test]
async fn dynamic_cache_paths_use_template_route_metric_labels() {
    let context = test_context(|_| {}).await;
    let app = public_router(context.state.clone());

    for artifact_id in ["artifact-one", "artifact-two"] {
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/api/cache/cas/{artifact_id}"))
                    .body(Body::empty())
                    .expect("failed to build request"),
            )
            .await
            .expect("request failed");

        assert_ne!(response.status(), StatusCode::NOT_FOUND);
    }

    let metrics = context.state.metrics.render();
    assert!(metrics.contains(&format!("route=\"{ROUTE_API_CACHE_CAS}\"")));
    assert!(!metrics.contains("artifact-one"));
    assert!(!metrics.contains("artifact-two"));
    assert!(!metrics.contains("route=\"/api/cache/cas/artifact-"));
}

#[tokio::test]
async fn unknown_paths_use_a_stable_unmatched_route_metric_label() {
    let context = test_context(|_| {}).await;

    let response = public_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/.docker/.env")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("request failed");

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    let metrics = context.state.metrics.render();
    assert!(metrics.contains("route=\"/_unmatched\""));
    assert!(!metrics.contains("route=\"/.docker/.env\""));
}

#[tokio::test]
async fn ready_stays_unavailable_until_bootstrap_gate_completes() {
    let context = test_context(|_| {}).await;
    let peer = "http://peer.kura.internal:7443".to_string();
    context
        .state
        .apply_membership_view(
            std::collections::BTreeSet::from(["remote".to_string()]),
            std::collections::BTreeMap::from([(peer.clone(), "remote".to_string())]),
            true,
        )
        .await;
    assert!(context.state.note_bootstrap_started(&peer).await.is_some());

    let response = public_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/ready")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("ready route should respond");
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    let body: Value = serde_json::from_str(&response_text(response).await)
        .expect("ready response should be json");
    assert_eq!(body["state"], "joining");
    assert_eq!(body["ready"], false);
    assert!(
        body["reasons"]
            .to_string()
            .contains("bootstrap in progress")
    );

    context
        .state
        .note_bootstrap_succeeded(&peer, context.state.current_bootstrap_epoch().await)
        .await;
    context.state.maybe_mark_serving().await;

    let response = public_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/ready")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("ready route should respond");
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    let body: Value = serde_json::from_str(&response_text(response).await)
        .expect("ready response should be json");
    assert_eq!(body["state"], "joining");
    assert_eq!(body["ready"], false);
    assert!(body["reasons"].to_string().contains("discovery settling"));

    context.state.expire_readiness_settle_window().await;
    context.state.maybe_mark_serving().await;

    let response = public_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/ready")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("ready route should respond");
    assert_eq!(response.status(), StatusCode::OK);
    let body: Value = serde_json::from_str(&response_text(response).await)
        .expect("ready response should be json");
    assert_eq!(body["state"], "serving");
    assert_eq!(body["ready"], true);
}

#[tokio::test]
async fn up_and_ready_share_the_same_membership_generation() {
    let context = test_context(|_| {}).await;
    let peer = "http://peer.kura.internal:7443".to_string();
    context
        .state
        .apply_membership_view(
            std::collections::BTreeSet::from(["remote".to_string()]),
            std::collections::BTreeMap::from([(peer.clone(), "remote".to_string())]),
            true,
        )
        .await;
    context
        .state
        .note_bootstrap_succeeded(&peer, context.state.current_bootstrap_epoch().await)
        .await;
    context.state.expire_readiness_settle_window().await;
    context.state.maybe_mark_serving().await;

    let up_response = public_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/up")
                .body(Body::empty())
                .expect("failed to build up request"),
        )
        .await
        .expect("up route should respond");
    let up_body: Value =
        serde_json::from_str(&response_text(up_response).await).expect("up response json");

    let ready_response = public_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/ready")
                .body(Body::empty())
                .expect("failed to build ready request"),
        )
        .await
        .expect("ready route should respond");
    let ready_body: Value =
        serde_json::from_str(&response_text(ready_response).await).expect("ready response json");

    assert_eq!(up_body["generation"], ready_body["generation"]);
}

#[tokio::test]
async fn ready_reports_draining_state() {
    let context = test_context(|_| {}).await;
    context
        .state
        .apply_membership_view(
            std::collections::BTreeSet::new(),
            std::collections::BTreeMap::new(),
            true,
        )
        .await;
    context.state.expire_readiness_settle_window().await;
    context.state.maybe_mark_serving().await;
    context.state.enter_draining();

    let response = public_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/ready")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("ready route should respond");
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    let body: Value = serde_json::from_str(&response_text(response).await)
        .expect("ready response should be json");
    assert_eq!(body["state"], "draining");
    assert_eq!(body["draining"], true);
    assert!(body["reasons"].to_string().contains("draining"));
}

#[tokio::test]
async fn rollout_status_reports_rollout_summary_and_stays_available_while_draining() {
    let context = test_context(|_| {}).await;
    let peer = "http://peer.kura.internal:7443".to_string();
    context
        .state
        .apply_membership_view(
            std::collections::BTreeSet::from(["remote".to_string()]),
            std::collections::BTreeMap::from([(peer.clone(), "remote".to_string())]),
            true,
        )
        .await;
    context
        .state
        .note_bootstrap_succeeded(&peer, context.state.current_bootstrap_epoch().await)
        .await;
    context.state.expire_readiness_settle_window().await;
    context.state.maybe_mark_serving().await;
    context.state.metrics.update_outbox_messages(7);
    context
        .state
        .metrics
        .record_file_descriptor_wait("timeout", Duration::from_millis(5));
    context.state.enter_draining();

    let response = public_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/status/rollout")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("rollout status route should respond");
    assert_eq!(response.status(), StatusCode::OK);
    let body: Value = serde_json::from_str(&response_text(response).await)
        .expect("rollout status response should be json");
    assert_eq!(body["generation"], 1);
    assert_eq!(body["state"], "draining");
    assert_eq!(body["ready"], false);
    assert_eq!(body["ring_members"], 2);
    assert_eq!(body["bootstrap_known_peers"], 1);
    assert_eq!(body["bootstrap_completed_peers"], 1);
    assert_eq!(body["bootstrap_inflight_peers"], 0);
    assert_eq!(body["outbox_messages"], 7);
    assert_eq!(body["memory_pressure_state"], 0);
    assert_eq!(body["fd_timeout_count"], 1);
}

#[tokio::test]
async fn draining_public_requests_return_service_unavailable_and_close_http1_connections() {
    let context = test_context(|_| {}).await;
    context
        .state
        .apply_membership_view(
            std::collections::BTreeSet::new(),
            std::collections::BTreeMap::new(),
            true,
        )
        .await;
    context.state.expire_readiness_settle_window().await;
    context.state.maybe_mark_serving().await;
    context.state.enter_draining();

    let response = public_router(context.state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cache/some-hash")
                .version(Version::HTTP_11)
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("public route should respond");
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(
        response.headers().get(axum::http::header::CONNECTION),
        Some(&HeaderValue::from_static("close"))
    );
}

#[tokio::test]
async fn public_router_does_not_serve_internal_routes() {
    let context = test_context(|_| {}).await;

    let response = public_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/_internal/status")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("request failed");

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn internal_status_advertises_gateway_url_for_global_discovery() {
    let context = test_context(|config| {
        config.node_url = "https://kura-eu-0.kura-eu-headless.kura.svc.cluster.local:7443".into();
        config.peer_gateway_url = Some("https://peer.tuist-eu-1.kura.tuist.dev:7443".into());
    })
    .await;

    let local_response = internal_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/_internal/status")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("request failed");
    let local_body: Value = serde_json::from_str(&response_text(local_response).await)
        .expect("failed to decode local status response");
    assert_eq!(
        local_body["node_url"],
        "https://kura-eu-0.kura-eu-headless.kura.svc.cluster.local:7443"
    );

    let global_response = internal_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/_internal/status?scope=global")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("request failed");
    let global_body: Value = serde_json::from_str(&response_text(global_response).await)
        .expect("failed to decode global status response");
    assert_eq!(
        global_body["node_url"],
        "https://peer.tuist-eu-1.kura.tuist.dev:7443"
    );

    // A Local-scope request that arrived via the gateway host (an
    // off-cluster node querying KURA_PEERS) also gets the gateway URL,
    // whether the host is carried as an HTTP/1.1 Host header...
    let via_host_header = internal_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/_internal/status")
                .header("host", "peer.tuist-eu-1.kura.tuist.dev:7443")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("request failed");
    let via_host_body: Value = serde_json::from_str(&response_text(via_host_header).await)
        .expect("failed to decode via-host status response");
    assert_eq!(
        via_host_body["node_url"],
        "https://peer.tuist-eu-1.kura.tuist.dev:7443"
    );

    // ...or as the HTTP/2 :authority on the request URI (no Host header).
    let via_authority = internal_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("https://peer.tuist-eu-1.kura.tuist.dev:7443/_internal/status")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("request failed");
    let via_authority_body: Value = serde_json::from_str(&response_text(via_authority).await)
        .expect("failed to decode via-authority status response");
    assert_eq!(
        via_authority_body["node_url"],
        "https://peer.tuist-eu-1.kura.tuist.dev:7443"
    );
}

#[tokio::test]
async fn keyvalue_round_trip_works_through_router() {
    let context = test_context(|_| {}).await;
    let app = router(context.state.clone());

    let put_response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/api/cache/keyvalue?tenant_id=acme&namespace_id=ios")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"cas_id":"cas-1","entries":[{"value":"hello"},{"value":"world"}]}"#,
                ))
                .expect("failed to build put request"),
        )
        .await
        .expect("put request failed");
    assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

    let get_response = app
        .oneshot(
            Request::builder()
                .uri("/api/cache/keyvalue/cas-1?tenant_id=acme&namespace_id=ios")
                .body(Body::empty())
                .expect("failed to build get request"),
        )
        .await
        .expect("get request failed");
    assert_eq!(get_response.status(), StatusCode::OK);

    let body: Value = serde_json::from_str(&response_text(get_response).await)
        .expect("failed to decode keyvalue response");
    assert!(
        body.get("cas_id").is_none(),
        "stored payload must not include cas_id"
    );
    assert_eq!(body["entries"][0]["value"], "hello");
    assert_eq!(body["entries"][1]["value"], "world");
}

#[tokio::test]
async fn keyvalue_misses_return_json_not_found_errors() {
    let context = test_context(|_| {}).await;

    let response = router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/api/cache/keyvalue/missing-cas?tenant_id=acme&namespace_id=ios")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("request failed");

    assert_json_error_response(response, StatusCode::NOT_FOUND, "Key-value entry not found").await;
}

#[tokio::test]
async fn keyvalue_routes_emit_usage_events() {
    let context = test_context(|config| {
        config.usage = Some(test_usage_config());
    })
    .await;
    let app = router(context.state.clone());

    let put_response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/api/cache/keyvalue?tenant_id=acme&namespace_id=ios")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"cas_id":"cas-1","entries":[{"value":"x"}]}"#,
                ))
                .expect("failed to build put request"),
        )
        .await
        .expect("put request failed");
    assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

    let get_response = app
        .oneshot(
            Request::builder()
                .uri("/api/cache/keyvalue/cas-1?tenant_id=acme&namespace_id=ios")
                .body(Body::empty())
                .expect("failed to build get request"),
        )
        .await
        .expect("get request failed");
    assert_eq!(get_response.status(), StatusCode::OK);
    let body = response_text(get_response).await;
    assert_eq!(body, r#"{"entries":[{"value":"x"}]}"#);

    let rollups = context
        .state
        .usage
        .as_ref()
        .expect("usage should be enabled")
        .current_rollups_for_tests();

    assert!(rollups.iter().any(|rollup| {
        rollup.tenant_id == "acme"
            && rollup.namespace_id == "ios"
            && rollup.direction == "ingress"
            && rollup.operation == "upload"
            && rollup.artifact_kind == "xcode"
            && rollup.bytes == 27
            && rollup.request_count == 1
    }));
    assert!(rollups.iter().any(|rollup| {
        rollup.tenant_id == "acme"
            && rollup.namespace_id == "ios"
            && rollup.direction == "egress"
            && rollup.operation == "download"
            && rollup.artifact_kind == "xcode"
            && rollup.bytes == 27
            && rollup.request_count == 1
    }));
}

#[tokio::test]
async fn account_and_project_handle_aliases_work_through_router() {
    let context = test_context(|_| {}).await;
    let app = router(context.state.clone());

    let put_response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/cache/cas/artifact-1?account_handle=acme&project_handle=ios")
                .header("content-type", "application/octet-stream")
                .body(Body::from("xcode-binary"))
                .expect("failed to build put request"),
        )
        .await
        .expect("put request failed");
    assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

    let get_response = app
        .oneshot(
            Request::builder()
                .uri("/api/cache/cas/artifact-1?account_handle=acme&project_handle=ios")
                .body(Body::empty())
                .expect("failed to build get request"),
        )
        .await
        .expect("get request failed");
    assert_eq!(get_response.status(), StatusCode::OK);
    assert_eq!(response_text(get_response).await, "xcode-binary");
}

#[tokio::test]
async fn bytes_chunks_reassembles_multi_chunk_payloads() {
    use futures_util::StreamExt;

    let len = MMAP_RESPONSE_CHUNK_BYTES * 2 + 7;
    let payload = Bytes::from(
        (0..len)
            .map(|index| (index % 251) as u8)
            .collect::<Vec<u8>>(),
    );

    let mut stream = Box::pin(bytes_chunks(payload.clone()));
    let mut chunks = Vec::new();
    while let Some(chunk) = stream.next().await {
        chunks.push(chunk.expect("chunk should be produced"));
    }

    assert_eq!(chunks.len(), 3);
    assert_eq!(chunks[0].len(), MMAP_RESPONSE_CHUNK_BYTES);
    assert_eq!(chunks[1].len(), MMAP_RESPONSE_CHUNK_BYTES);
    assert_eq!(chunks[2].len(), 7);
    assert_eq!(chunks.concat(), payload.to_vec());
}

#[tokio::test]
async fn artifact_get_serves_multi_chunk_payloads_via_mmap_and_reader_fallback() {
    let context = test_context(|_| {}).await;
    let app = router(context.state.clone());

    let len = MMAP_RESPONSE_CHUNK_BYTES * 2 + 7;
    let payload: Vec<u8> = (0..len).map(|index| (index % 251) as u8).collect();

    let put_response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/cache/cas/multi-chunk?tenant_id=acme&namespace_id=ios")
                .header("content-type", "application/octet-stream")
                .body(Body::from(payload.clone()))
                .expect("failed to build put request"),
        )
        .await
        .expect("put request failed");
    assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

    let get_request = || {
        Request::builder()
            .uri("/api/cache/cas/multi-chunk?tenant_id=acme&namespace_id=ios")
            .body(Body::empty())
            .expect("failed to build get request")
    };

    let mmap_response = app
        .clone()
        .oneshot(get_request())
        .await
        .expect("mmap get request failed");
    assert_eq!(mmap_response.status(), StatusCode::OK);
    let mmap_body = mmap_response
        .into_body()
        .collect()
        .await
        .expect("failed to collect mmap body")
        .to_bytes();
    assert_eq!(mmap_body.as_ref(), payload.as_slice());

    // Force memory pressure so mmap serving is skipped and the streaming
    // reader path serves the same artifact; the bytes must be identical.
    context.state.memory.observe(u64::MAX);

    let reader_response = app
        .oneshot(get_request())
        .await
        .expect("reader get request failed");
    assert_eq!(reader_response.status(), StatusCode::OK);
    let reader_body = reader_response
        .into_body()
        .collect()
        .await
        .expect("failed to collect reader body")
        .to_bytes();
    assert_eq!(reader_body.as_ref(), payload.as_slice());

    let metrics = context.state.metrics.render();
    assert!(metrics.contains("kura_artifact_egress_completions_total"));
    assert!(metrics.contains("producer=\"xcode\""));
    assert!(metrics.contains("result=\"ok\""));
    assert!(metrics.contains(&format!("{}", payload.len() * 2)));
}

#[tokio::test]
async fn artifact_get_misses_return_json_not_found_errors() {
    let context = test_context(|_| {}).await;
    let app = router(context.state.clone());

    let cas_response = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/cache/cas/missing-cas?tenant_id=acme&namespace_id=ios")
                .body(Body::empty())
                .expect("failed to build CAS request"),
        )
        .await
        .expect("CAS request failed");
    assert_json_error_response(cas_response, StatusCode::NOT_FOUND, "Artifact not found").await;

    let module_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/cache/module/missing-module?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build module request"),
            )
            .await
            .expect("module request failed");
    assert_json_error_response(module_response, StatusCode::NOT_FOUND, "Artifact not found").await;

    let gradle_response = app
        .oneshot(
            Request::builder()
                .uri("/api/cache/gradle/missing-gradle?tenant_id=acme&namespace_id=android")
                .body(Body::empty())
                .expect("failed to build Gradle request"),
        )
        .await
        .expect("Gradle request failed");
    assert_json_error_response(gradle_response, StatusCode::NOT_FOUND, "Artifact not found").await;
}

#[tokio::test]
async fn tenant_only_xcode_routes_work_through_router() {
    let context = test_context(|_| {}).await;
    let app = router(context.state.clone());

    let put_response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/cache/cas/account-artifact?account_handle=acme")
                .header("content-type", "application/octet-stream")
                .body(Body::from("account-binary"))
                .expect("failed to build put request"),
        )
        .await
        .expect("put request failed");
    assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

    let get_response = app
        .oneshot(
            Request::builder()
                .uri("/api/cache/cas/account-artifact?account_handle=acme")
                .body(Body::empty())
                .expect("failed to build get request"),
        )
        .await
        .expect("get request failed");

    assert_eq!(get_response.status(), StatusCode::OK);
    assert_eq!(response_text(get_response).await, "account-binary");
}

#[tokio::test]
async fn xcode_routes_emit_project_scoped_analytics_events() {
    let captured = Arc::new(Mutex::new(Vec::<CapturedRequest>::new()));
    let (base_url, _handle) = spawn_capture_server(captured.clone()).await;
    let context = test_context(|config| {
        config.analytics = Some(AnalyticsConfig {
            server_url: base_url,
            signing_key: "secret-key".into(),
            batch_size: 1,
            batch_timeout_ms: 5_000,
            queue_capacity: 8,
            request_timeout_ms: 5_000,
            circuit_breaker_failure_threshold: 2,
            circuit_breaker_open_ms: 5_000,
        });
    })
    .await;
    let app = router(context.state.clone());

    let put_response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios")
                .header("content-type", "application/octet-stream")
                .body(Body::from("xcode-binary"))
                .expect("failed to build put request"),
        )
        .await
        .expect("put request failed");
    assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

    let get_response = app
        .oneshot(
            Request::builder()
                .uri("/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios")
                .body(Body::empty())
                .expect("failed to build get request"),
        )
        .await
        .expect("get request failed");
    assert_eq!(get_response.status(), StatusCode::OK);
    assert_eq!(response_text(get_response).await, "xcode-binary");

    timeout(Duration::from_secs(2), async {
        loop {
            if captured.lock().expect("captured requests lock").len() >= 2 {
                break;
            }
            sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("analytics requests should be delivered");

    let requests = captured.lock().expect("captured requests lock");
    let payloads = requests
        .iter()
        .map(|request| {
            serde_json::from_slice::<Value>(&request.body)
                .expect("analytics request body should decode")
        })
        .collect::<Vec<_>>();

    assert!(payloads.iter().any(|payload| {
        payload
            == &serde_json::json!({
                "events": [{
                    "account_handle": "acme",
                    "project_handle": "ios",
                    "action": "upload",
                    "size": 12,
                    "cas_id": "artifact-1"
                }]
            })
    }));
    assert!(payloads.iter().any(|payload| {
        payload
            == &serde_json::json!({
                "events": [{
                    "account_handle": "acme",
                    "project_handle": "ios",
                    "action": "download",
                    "size": 12,
                    "cas_id": "artifact-1"
                }]
            })
    }));
}

#[tokio::test]
async fn tenant_only_xcode_routes_skip_project_scoped_analytics_events() {
    let captured = Arc::new(Mutex::new(Vec::<CapturedRequest>::new()));
    let (base_url, _handle) = spawn_capture_server(captured.clone()).await;
    let context = test_context(|config| {
        config.analytics = Some(AnalyticsConfig {
            server_url: base_url,
            signing_key: "secret-key".into(),
            batch_size: 1,
            batch_timeout_ms: 5_000,
            queue_capacity: 8,
            request_timeout_ms: 5_000,
            circuit_breaker_failure_threshold: 2,
            circuit_breaker_open_ms: 5_000,
        });
    })
    .await;
    let app = router(context.state.clone());

    let put_response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/cache/cas/account-artifact?tenant_id=acme")
                .header("content-type", "application/octet-stream")
                .body(Body::from("account-binary"))
                .expect("failed to build put request"),
        )
        .await
        .expect("put request failed");
    assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

    let get_response = app
        .oneshot(
            Request::builder()
                .uri("/api/cache/cas/account-artifact?tenant_id=acme")
                .body(Body::empty())
                .expect("failed to build get request"),
        )
        .await
        .expect("get request failed");
    assert_eq!(get_response.status(), StatusCode::OK);
    assert_eq!(response_text(get_response).await, "account-binary");

    sleep(Duration::from_millis(200)).await;
    assert!(captured.lock().expect("captured requests lock").is_empty());
}

#[tokio::test]
async fn tenant_only_xcode_routes_emit_usage_events() {
    let context = test_context(|config| {
        config.usage = Some(test_usage_config());
    })
    .await;
    let app = router(context.state.clone());

    let put_response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/cache/cas/account-artifact?tenant_id=acme")
                .header("content-type", "application/octet-stream")
                .body(Body::from("account-binary"))
                .expect("failed to build put request"),
        )
        .await
        .expect("put request failed");
    assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

    let get_response = app
        .oneshot(
            Request::builder()
                .uri("/api/cache/cas/account-artifact?tenant_id=acme")
                .body(Body::empty())
                .expect("failed to build get request"),
        )
        .await
        .expect("get request failed");
    assert_eq!(get_response.status(), StatusCode::OK);
    assert_eq!(response_text(get_response).await, "account-binary");

    let rollups = context
        .state
        .usage
        .as_ref()
        .expect("usage should be enabled")
        .current_rollups_for_tests();

    assert!(rollups.iter().any(|rollup| {
        rollup.tenant_id == "acme"
            && rollup.namespace_id.is_empty()
            && rollup.direction == "ingress"
            && rollup.operation == "upload"
            && rollup.artifact_kind == "xcode"
            && rollup.bytes == 14
            && rollup.request_count == 1
    }));
    assert!(rollups.iter().any(|rollup| {
        rollup.tenant_id == "acme"
            && rollup.namespace_id.is_empty()
            && rollup.direction == "egress"
            && rollup.operation == "download"
            && rollup.artifact_kind == "xcode"
            && rollup.bytes == 14
            && rollup.request_count == 1
    }));
}

#[tokio::test]
async fn fixed_namespace_cache_routes_emit_usage_events() {
    let context = test_context(|config| {
        config.tenant_id = "acme".into();
        config.usage = Some(test_usage_config());
    })
    .await;
    let app = router(context.state.clone());

    let nx_put = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/cache/nx-key")
                .body(Body::from("nx-bytes"))
                .expect("failed to build nx put request"),
        )
        .await
        .expect("nx put request failed");
    assert_eq!(nx_put.status(), StatusCode::OK);

    let nx_get = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/v1/cache/nx-key")
                .body(Body::empty())
                .expect("failed to build nx get request"),
        )
        .await
        .expect("nx get request failed");
    assert_eq!(nx_get.status(), StatusCode::OK);
    assert_eq!(response_text(nx_get).await, "nx-bytes");

    let metro_put = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/api/metro/cache/metro-key")
                .body(Body::from("metro-bytes"))
                .expect("failed to build metro put request"),
        )
        .await
        .expect("metro put request failed");
    assert_eq!(metro_put.status(), StatusCode::OK);

    let metro_get = app
        .oneshot(
            Request::builder()
                .uri("/api/metro/cache/metro-key")
                .body(Body::empty())
                .expect("failed to build metro get request"),
        )
        .await
        .expect("metro get request failed");
    assert_eq!(metro_get.status(), StatusCode::OK);
    assert_eq!(response_text(metro_get).await, "metro-bytes");

    let rollups = context
        .state
        .usage
        .as_ref()
        .expect("usage should be enabled")
        .current_rollups_for_tests();

    assert!(rollups.iter().any(|rollup| {
        rollup.tenant_id == "acme"
            && rollup.namespace_id == "nx"
            && rollup.direction == "ingress"
            && rollup.artifact_kind == "nx"
            && rollup.bytes == 8
    }));
    assert!(rollups.iter().any(|rollup| {
        rollup.tenant_id == "acme"
            && rollup.namespace_id == "nx"
            && rollup.direction == "egress"
            && rollup.artifact_kind == "nx"
            && rollup.bytes == 8
    }));
    assert!(rollups.iter().any(|rollup| {
        rollup.tenant_id == "acme"
            && rollup.namespace_id == "metro"
            && rollup.direction == "ingress"
            && rollup.artifact_kind == "metro"
            && rollup.bytes == 11
    }));
    assert!(rollups.iter().any(|rollup| {
        rollup.tenant_id == "acme"
            && rollup.namespace_id == "metro"
            && rollup.direction == "egress"
            && rollup.artifact_kind == "metro"
            && rollup.bytes == 11
    }));
}

#[tokio::test]
async fn multipart_module_round_trip_works_through_router() {
    let context = test_context(|_| {}).await;
    let app = router(context.state.clone());

    let start = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build start request"),
            )
            .await
            .expect("start request failed");
    let payload: Value =
        serde_json::from_str(&response_text(start).await).expect("failed to decode start payload");
    let upload_id = payload["upload_id"]
        .as_str()
        .expect("upload id should be present");

    let upload_part = |part_number, body| {
        Request::builder()
            .method("POST")
            .uri(format!(
                "/api/cache/module/part?upload_id={upload_id}&part_number={part_number}"
            ))
            .body(Body::from(body))
            .expect("failed to build part request")
    };

    let response = app
        .clone()
        .oneshot(upload_part(1, "part-one-"))
        .await
        .expect("part 1 request failed");
    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    let response = app
        .clone()
        .oneshot(upload_part(2, "part-two"))
        .await
        .expect("part 2 request failed");
    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/cache/module/complete?upload_id={upload_id}"))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"parts":[1,2]}"#))
                .expect("failed to build complete request"),
        )
        .await
        .expect("complete request failed");
    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    let head = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("HEAD")
                    .uri("/api/cache/module/module-1?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build head request"),
            )
            .await
            .expect("head request failed");
    assert_eq!(head.status(), StatusCode::NO_CONTENT);

    let get = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/module/module-1?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
    assert_eq!(get.status(), StatusCode::OK);
    assert_eq!(
        get.headers()
            .get(axum::http::header::CONTENT_LENGTH)
            .and_then(|value| value.to_str().ok()),
        Some("17")
    );
    assert_eq!(response_text(get).await, "part-one-part-two");
}

#[tokio::test]
async fn multipart_module_routes_emit_usage_events() {
    let context = test_context(|config| {
        config.usage = Some(test_usage_config());
    })
    .await;
    let app = router(context.state.clone());

    let start = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build start request"),
            )
            .await
            .expect("start request failed");
    let payload: Value =
        serde_json::from_str(&response_text(start).await).expect("failed to decode start payload");
    let upload_id = payload["upload_id"]
        .as_str()
        .expect("upload id should be present");

    let part_response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/api/cache/module/part?upload_id={upload_id}&part_number=1"
                ))
                .body(Body::from("module-bytes"))
                .expect("failed to build part request"),
        )
        .await
        .expect("part request failed");
    assert_eq!(part_response.status(), StatusCode::NO_CONTENT);

    let complete_response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/cache/module/complete?upload_id={upload_id}"))
                .header("content-type", "application/json")
                .body(Body::from(r#"{"parts":[1]}"#))
                .expect("failed to build complete request"),
        )
        .await
        .expect("complete request failed");
    assert_eq!(complete_response.status(), StatusCode::NO_CONTENT);

    let get_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/cache/module/module-1?tenant_id=acme&namespace_id=ios&hash=hash-1&name=Module.framework&cache_category=builds")
                    .body(Body::empty())
                    .expect("failed to build get request"),
            )
            .await
            .expect("get request failed");
    assert_eq!(get_response.status(), StatusCode::OK);
    assert_eq!(response_text(get_response).await, "module-bytes");

    let rollups = context
        .state
        .usage
        .as_ref()
        .expect("usage should be enabled")
        .current_rollups_for_tests();

    assert!(rollups.iter().any(|rollup| {
        rollup.tenant_id == "acme"
            && rollup.namespace_id == "ios"
            && rollup.direction == "ingress"
            && rollup.operation == "upload"
            && rollup.artifact_kind == "module"
            && rollup.bytes == 12
            && rollup.request_count == 1
    }));
    assert!(rollups.iter().any(|rollup| {
        rollup.tenant_id == "acme"
            && rollup.namespace_id == "ios"
            && rollup.direction == "egress"
            && rollup.operation == "download"
            && rollup.artifact_kind == "module"
            && rollup.bytes == 12
            && rollup.request_count == 1
    }));
}

#[tokio::test]
async fn extension_context_resolves_namespace_from_multipart_upload() {
    let context = test_context(|_| {}).await;
    let upload_id = context
        .state
        .store
        .start_multipart_upload("acme", "ios", "builds", "hash-1", "Module.framework")
        .expect("failed to start multipart upload");
    let query = parse_query_map(Some(&format!("upload_id={upload_id}&part_number=1")));
    let headers = BTreeMap::new();

    let extension_context = extension_context_from_http(
        &context.state,
        HttpExtensionRequest {
            route: ROUTE_API_CACHE_MODULE_PART,
            method: "POST",
            path: ROUTE_API_CACHE_MODULE_PART,
            query: &query,
            headers: &headers,
            body: None,
            status_code: None,
        },
    )
    .await;

    assert_eq!(extension_context.tenant_id.as_deref(), Some("acme"));
    assert_eq!(extension_context.namespace_id.as_deref(), Some("ios"));
    assert_eq!(extension_context.artifact_hash.as_deref(), Some("hash-1"));
    assert_eq!(
        extension_context.artifact_key.as_deref(),
        Some("builds/hash-1/Module.framework")
    );
}

#[tokio::test]
async fn extension_context_uses_handle_aliases() {
    let context = test_context(|_| {}).await;
    let query = parse_query_map(Some("account_handle=acme&project_handle=ios&hash=hash-1"));
    let extension_context = extension_context_from_http(
        &context.state,
        HttpExtensionRequest {
            route: ROUTE_API_CACHE_CAS,
            method: "GET",
            path: "/api/cache/cas/artifact-1",
            query: &query,
            headers: &BTreeMap::new(),
            body: None,
            status_code: None,
        },
    )
    .await;

    assert_eq!(extension_context.tenant_id.as_deref(), Some("acme"));
    assert_eq!(extension_context.namespace_id.as_deref(), Some("ios"));
}

#[tokio::test]
async fn extension_context_omits_namespace_for_tenant_scoped_requests() {
    let context = test_context(|_| {}).await;
    let query = parse_query_map(Some("tenant_id=acme&hash=hash-1"));
    let extension_context = extension_context_from_http(
        &context.state,
        HttpExtensionRequest {
            route: ROUTE_API_CACHE_CAS,
            method: "GET",
            path: "/api/cache/cas/account-artifact",
            query: &query,
            headers: &BTreeMap::new(),
            body: None,
            status_code: None,
        },
    )
    .await;

    assert_eq!(extension_context.tenant_id.as_deref(), Some("acme"));
    assert_eq!(extension_context.namespace_id, None);
}

#[tokio::test]
async fn extension_context_uses_keyvalue_cas_id_from_request_body() {
    let context = test_context(|_| {}).await;
    let query = parse_query_map(Some("tenant_id=acme&namespace_id=ios"));
    let request_body = br#"{"cas_id":"cas-1","entries":[{"value":"hello"},{"value":"world"}]}"#;
    let extension_context = extension_context_from_http(
        &context.state,
        HttpExtensionRequest {
            route: ROUTE_API_CACHE_KEYVALUE,
            method: "PUT",
            path: ROUTE_API_CACHE_KEYVALUE,
            query: &query,
            headers: &BTreeMap::new(),
            body: Some(request_body),
            status_code: None,
        },
    )
    .await;

    assert_eq!(
        extension_context.artifact_key.as_deref(),
        Some("action_cache/cas-1")
    );
}

#[tokio::test]
async fn missing_required_query_returns_json_error() {
    let context = test_context(|_| {}).await;

    let response = router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/api/cache/keyvalue/cas-1?namespace_id=ios")
                .body(Body::empty())
                .expect("failed to build request"),
        )
        .await
        .expect("request failed");

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert_eq!(
        serde_json::from_str::<Value>(&response_text(response).await)
            .expect("failed to decode error response")["message"],
        "Missing tenant_id"
    );
}

#[tokio::test]
async fn clean_namespace_removes_existing_artifacts() {
    let context = test_context(|_| {}).await;
    context
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            &blob_key("artifact-1"),
            "application/octet-stream",
            b"xcode-binary",
        )
        .await
        .expect("failed to seed store");

    let app = router(context.state.clone());

    let delete = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri("/api/cache/clean?tenant_id=acme&namespace_id=ios")
                .body(Body::empty())
                .expect("failed to build delete request"),
        )
        .await
        .expect("delete request failed");
    assert_eq!(delete.status(), StatusCode::NO_CONTENT);

    let get = app
        .oneshot(
            Request::builder()
                .uri("/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios")
                .body(Body::empty())
                .expect("failed to build get request"),
        )
        .await
        .expect("get request failed");
    assert_eq!(get.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn clean_namespace_removes_existing_tenant_scoped_artifacts() {
    let context = test_context(|_| {}).await;
    context
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "",
            &blob_key("account-artifact"),
            "application/octet-stream",
            b"account-binary",
        )
        .await
        .expect("failed to seed store");

    let app = router(context.state.clone());

    let delete = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri("/api/cache/clean?tenant_id=acme")
                .body(Body::empty())
                .expect("failed to build delete request"),
        )
        .await
        .expect("delete request failed");
    assert_eq!(delete.status(), StatusCode::NO_CONTENT);

    let get = app
        .oneshot(
            Request::builder()
                .uri("/api/cache/cas/account-artifact?tenant_id=acme")
                .body(Body::empty())
                .expect("failed to build get request"),
        )
        .await
        .expect("get request failed");
    assert_eq!(get.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn instrumented_artifact_stream_holds_public_inflight_until_body_drops() {
    let context = test_context(|_| {}).await;
    assert_eq!(context.state.runtime.public_http_inflight(), 0);

    let stream = futures_util::stream::pending::<Result<Bytes, std::io::Error>>();
    let instrumented = InstrumentedArtifactStream::new(
        context.state.metrics.clone(),
        ArtifactProducer::Xcode,
        stream,
        Some(context.state.start_http_request(HttpTrafficClass::Public)),
    );

    assert_eq!(context.state.runtime.public_http_inflight(), 1);
    drop(instrumented);
    assert_eq!(context.state.runtime.public_http_inflight(), 0);
}

#[derive(Clone, Debug)]
struct CapturedRequest {
    body: Vec<u8>,
}

async fn spawn_capture_server(
    captured: Arc<Mutex<Vec<CapturedRequest>>>,
) -> (String, tokio::task::JoinHandle<()>) {
    let router = Router::new()
        .route(
            "/webhooks/cache",
            post({
                let captured = captured.clone();
                move |request| capture_request(captured.clone(), request)
            }),
        )
        .route(
            "/webhooks/gradle-cache",
            post({
                let captured = captured.clone();
                move |request| capture_request(captured.clone(), request)
            }),
        );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("capture listener should bind");
    let address = listener
        .local_addr()
        .expect("capture listener should have a local address");
    let handle = tokio::spawn(async move {
        axum::serve(listener, router)
            .await
            .expect("capture server should run");
    });

    (format!("http://{address}"), handle)
}

async fn capture_request(
    captured: Arc<Mutex<Vec<CapturedRequest>>>,
    request: Request,
) -> impl IntoResponse {
    let (_parts, body) = request.into_parts();
    let body = body
        .collect()
        .await
        .expect("request body should collect")
        .to_bytes();
    captured
        .lock()
        .expect("captured requests lock")
        .push(CapturedRequest {
            body: body.to_vec(),
        });
    StatusCode::ACCEPTED
}

mod client_ip {
    use axum::http::{HeaderMap, HeaderValue};

    use super::super::client_ip_from_headers;

    #[test]
    fn returns_first_hop_from_x_forwarded_for() {
        let mut headers = HeaderMap::new();
        headers.insert(
            "x-forwarded-for",
            HeaderValue::from_static("203.0.113.5, 10.0.0.1, 198.51.100.7"),
        );
        assert_eq!(
            client_ip_from_headers(&headers)
                .expect("first hop should parse")
                .to_string(),
            "203.0.113.5"
        );
    }

    #[test]
    fn trims_surrounding_whitespace_in_x_forwarded_for() {
        let mut headers = HeaderMap::new();
        headers.insert(
            "x-forwarded-for",
            HeaderValue::from_static("  203.0.113.5  , 10.0.0.1"),
        );
        assert_eq!(
            client_ip_from_headers(&headers)
                .expect("trimmed first hop should parse")
                .to_string(),
            "203.0.113.5"
        );
    }

    #[test]
    fn falls_back_to_x_real_ip_when_x_forwarded_for_is_missing() {
        let mut headers = HeaderMap::new();
        headers.insert("x-real-ip", HeaderValue::from_static("198.51.100.7"));
        assert_eq!(
            client_ip_from_headers(&headers)
                .expect("x-real-ip should parse")
                .to_string(),
            "198.51.100.7"
        );
    }

    #[test]
    fn returns_none_when_no_address_headers_are_present() {
        let headers = HeaderMap::new();
        assert!(client_ip_from_headers(&headers).is_none());
    }

    #[test]
    fn returns_none_when_first_hop_is_malformed() {
        let mut headers = HeaderMap::new();
        headers.insert("x-forwarded-for", HeaderValue::from_static("not-an-ip"));
        assert!(client_ip_from_headers(&headers).is_none());
    }
}
