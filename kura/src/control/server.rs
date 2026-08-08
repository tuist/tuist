//! Serves the control surface over a Unix socket in the data directory.

use std::{path::Path, sync::Arc};

use axum::{
    Json, Router,
    extract::{Request, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{delete, get, post},
};
use hyper::{body::Incoming, service::service_fn};
use hyper_util::rt::TokioIo;
use tokio::{net::UnixListener, sync::watch, task::JoinHandle};
use tower::ServiceExt as _;
use tracing::{Instrument, info, warn};

use crate::{
    control::{
        report::{ConfigReport, PeerListReport, RuntimeReport, StoreReport, TrafficReport},
        runtime_file::RuntimeInfo,
    },
    state::SharedState,
};

#[derive(Clone)]
struct ControlState {
    state: SharedState,
    info: Arc<RuntimeInfo>,
}

/// The control routes, versioned from the first release. The data directory is
/// a persistent volume that outlives any single pod, and rolling updates run
/// mixed versions side by side, so a CLI from one image may well talk to a node
/// from another. Routes are additive within `/v1`.
pub fn router(state: SharedState, info: Arc<RuntimeInfo>) -> Router {
    let control = ControlState { state, info };
    Router::new()
        .route("/v1/runtime", get(runtime))
        .route("/v1/config", get(config))
        .route("/v1/store", get(store))
        .route("/v1/status", get(status))
        .route("/v1/peers", get(peers))
        .route("/v1/outbox", get(outbox))
        .route("/v1/cache/trim", post(trim_cache))
        .route("/v1/namespaces/{namespace_id}", delete(delete_namespace))
        .route("/v1/uploads/{upload_id}", delete(abort_upload))
        .with_state(control)
}

// Referential integrity
// ---------------------
// The store is not a flat key-value map. A manifest is referenced by the
// namespace index and the segment index; an action-cache entry references the
// CAS blobs it was built from (and the reverse map that drives the eviction
// cascade); a multipart upload owns staged part files on disk. Every one of
// those relationships is maintained by composite `Store` operations that write
// their whole set of keys in a single atomic `WriteBatch`.
//
// So the rule for this surface is: **mutating handlers call composite `Store`
// operations, never raw key writes.** A handler that reached past them could
// leave a manifest whose segment index entry still points at it, or an
// action-cache entry whose blobs are gone, and the eviction cascade and the
// serve-side presence gates are built on the assumption that never happens.
//
// The second rule is about convergence, which is integrity across the mesh
// rather than within a node. A node-local delete does not converge: anti-entropy
// copies the data back from a peer on the next bootstrap pass. Only operations
// with a replicating path (a tombstone plus an outbox enqueue) are durable
// mesh-wide. That is why `namespace delete` is offered and a per-artifact delete
// is not: there is no artifact tombstone, so deleting one would appear to work
// and then silently undo itself.

/// The header a mutating request carries its grant in.
pub const GRANT_HEADER: &str = "x-kura-grant";

/// The gate every mutating handler goes through.
///
/// Reads need no grant: reaching the socket already required host or container
/// access. Writes need proof of *who* is asking and that they were elevated,
/// which that access cannot express on its own, so they carry a signed grant.
/// See `control::grant` for what is checked and why.
fn authorize_write(
    control: &ControlState,
    headers: &axum::http::HeaderMap,
    operation: &str,
    detail: &str,
) -> Result<crate::control::grant::GrantClaims, Box<Response>> {
    let token = headers
        .get(GRANT_HEADER)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs() as i64)
        .unwrap_or(0);

    match crate::control::grant::verify(token, control.state.config.control_grant.as_ref(), now) {
        Ok(claims) => {
            crate::control::grant::audit(&claims, operation, detail);
            Ok(claims)
        }
        Err(error) => {
            // Denials are logged too. A rejected elevation attempt is exactly
            // the kind of thing an audit trail should not be missing.
            warn!(
                operation,
                detail,
                reason = ?error,
                "refused an unauthorized mutation"
            );
            Err(Box::new(
                (
                    StatusCode::FORBIDDEN,
                    Json(serde_json::json!({ "error": error.message() })),
                )
                    .into_response(),
            ))
        }
    }
}

#[derive(serde::Deserialize)]
struct TrimCacheRequest {
    cache: String,
    target: usize,
}

/// Trims an in-memory cache. Node-local, reversible, and touches no artifact
/// bytes: the caches refill from the store on the next lookup. It is a real
/// pressure-relief lever and, being the least destructive write there is, it is
/// what proves the authorization path end to end.
async fn trim_cache(
    State(control): State<ControlState>,
    headers: axum::http::HeaderMap,
    Json(request): Json<TrimCacheRequest>,
) -> Response {
    let detail = format!("cache={} target={}", request.cache, request.target);
    let claims = match authorize_write(&control, &headers, "cache.trim", &detail) {
        Ok(claims) => claims,
        Err(response) => return *response,
    };

    let store = &control.state.store;
    let evicted = match request.cache.as_str() {
        "manifest" => store.trim_manifest_cache_to(request.target, "operator"),
        "existence" => store.trim_existence_cache_to(request.target),
        "segment-handle" => {
            store
                .trim_segment_handle_cache_to(request.target, "operator")
                .await
        }
        other => {
            return bad_request(format!(
                "unknown cache {other}: expected one of manifest, existence, segment-handle"
            ));
        }
    };

    Json(serde_json::json!({
        "cache": request.cache,
        "evicted": evicted,
        "authorized_by": claims.sub,
    }))
    .into_response()
}

/// Deletes a namespace across the mesh.
///
/// Delegates to `delete_namespace_and_enqueue`, which in one atomic batch drops
/// the namespace's manifests, its namespace-index entries, and its segment-index
/// entries, writes a tombstone, and enqueues the delete to every replication
/// target. The tombstone is what makes it converge: without it a peer would
/// re-seed the namespace on its next bootstrap pass.
async fn delete_namespace(
    State(control): State<ControlState>,
    axum::extract::Path(namespace_id): axum::extract::Path<String>,
    headers: axum::http::HeaderMap,
) -> Response {
    if namespace_id.trim().is_empty() {
        return bad_request("namespace id must not be empty".to_string());
    }

    let detail = format!("namespace={namespace_id}");
    let claims = match authorize_write(&control, &headers, "namespace.delete", &detail) {
        Ok(claims) => claims,
        Err(response) => return *response,
    };

    let targets = control.state.replication_targets().await;
    match control
        .state
        .store
        .delete_namespace_and_enqueue(&namespace_id, &targets)
        .await
    {
        Ok(version_ms) => {
            // Wake the outbox so the tombstone starts replicating now rather
            // than at the next tick.
            control.state.notify.notify_one();
            Json(serde_json::json!({
                "namespace_id": namespace_id,
                "version_ms": version_ms,
                "replication_targets": targets.len(),
                "authorized_by": claims.sub,
            }))
            .into_response()
        }
        Err(error) if crate::store::is_outbox_full_error(&error) => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({
                "error": "the outbox is full, so this delete cannot be replicated yet. \
                          Deleting without enqueuing would not converge, so it was refused."
            })),
        )
            .into_response(),
        Err(error) => internal_error(format!("failed to delete namespace: {error}")),
    }
}

/// Aborts a multipart upload, releasing both its record and the part files it
/// staged on disk. `abort_multipart_upload` owns that pairing; dropping the
/// record alone would orphan the parts with nothing left to reclaim them.
async fn abort_upload(
    State(control): State<ControlState>,
    axum::extract::Path(upload_id): axum::extract::Path<String>,
    headers: axum::http::HeaderMap,
) -> Response {
    let detail = format!("upload={upload_id}");
    let claims = match authorize_write(&control, &headers, "upload.abort", &detail) {
        Ok(claims) => claims,
        Err(response) => return *response,
    };

    match control.state.store.multipart_upload(&upload_id) {
        Ok(None) => bad_request(format!("no multipart upload {upload_id}")),
        Err(error) => internal_error(format!("failed to look up upload: {error}")),
        Ok(Some(_)) => match control.state.store.abort_multipart_upload(&upload_id).await {
            Ok(()) => Json(serde_json::json!({
                "upload_id": upload_id,
                "authorized_by": claims.sub,
            }))
            .into_response(),
            Err(error) => internal_error(format!("failed to abort upload: {error}")),
        },
    }
}

async fn runtime(State(control): State<ControlState>) -> Response {
    match RuntimeReport::capture(&control.state, &control.info).await {
        Ok(report) => Json(report).into_response(),
        Err(error) => internal_error(error),
    }
}

async fn config(State(control): State<ControlState>) -> Response {
    Json(ConfigReport::capture(&control.state)).into_response()
}

async fn store(State(control): State<ControlState>) -> Response {
    match control.state.store.snapshot() {
        Ok(snapshot) => Json(StoreReport::from(snapshot)).into_response(),
        Err(error) => internal_error(error),
    }
}

async fn status(State(control): State<ControlState>) -> Response {
    Json(TrafficReport::capture(&control.state).await).into_response()
}

async fn peers(State(control): State<ControlState>) -> Response {
    Json(PeerListReport::capture(&control.state).await).into_response()
}

async fn outbox(State(control): State<ControlState>) -> Response {
    match crate::control::report::ReplicationReport::capture(&control.state).await {
        Ok(report) => Json(report).into_response(),
        Err(error) => internal_error(error),
    }
}

fn bad_request(error: String) -> Response {
    (
        StatusCode::BAD_REQUEST,
        Json(serde_json::json!({ "error": error })),
    )
        .into_response()
}

fn internal_error(error: String) -> Response {
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(serde_json::json!({ "error": error })),
    )
        .into_response()
}

/// Binds the control socket and serves it until shutdown is signalled.
///
/// A socket left behind by a crashed process is removed first. That is safe
/// because the caller already holds the exclusive writer lock on the data
/// directory, so no live node can be listening on it.
pub fn spawn(
    state: SharedState,
    info: Arc<RuntimeInfo>,
    shutdown: watch::Receiver<bool>,
) -> Result<JoinHandle<()>, String> {
    let path = info.control_socket_path.clone();
    remove_stale_socket(&path)?;

    let listener = UnixListener::bind(&path)
        .map_err(|error| format!("failed to bind control socket {}: {error}", path.display()))?;
    restrict_socket_permissions(&path)?;

    info!("Kura control socket listening on {}", path.display());
    let router = router(state, info);

    Ok(tokio::spawn(
        async move {
            serve(listener, router, shutdown).await;
            if let Err(error) = std::fs::remove_file(&path)
                && error.kind() != std::io::ErrorKind::NotFound
            {
                warn!(
                    "failed to remove control socket {}: {error}",
                    path.display()
                );
            }
        }
        .in_current_span(),
    ))
}

async fn serve(listener: UnixListener, router: Router, mut shutdown: watch::Receiver<bool>) {
    loop {
        if *shutdown.borrow() {
            return;
        }
        tokio::select! {
            _ = shutdown.changed() => return,
            accepted = listener.accept() => {
                let stream = match accepted {
                    Ok((stream, _)) => stream,
                    Err(error) => {
                        warn!("control socket accept failed: {error}");
                        continue;
                    }
                };
                let router = router.clone();
                tokio::spawn(
                    async move {
                        let service = service_fn(move |request: Request<Incoming>| {
                            let router = router.clone();
                            async move {
                                router
                                    .oneshot(request.map(axum::body::Body::new))
                                    .await
                                    .map_err(std::io::Error::other)
                            }
                        });
                        if let Err(error) = hyper::server::conn::http1::Builder::new()
                            .serve_connection(TokioIo::new(stream), service)
                            .await
                        {
                            tracing::debug!("control connection ended: {error}");
                        }
                    }
                    .in_current_span(),
                );
            }
        }
    }
}

fn remove_stale_socket(path: &Path) -> Result<(), String> {
    match std::fs::remove_file(path) {
        Ok(()) => {
            warn!(
                "removed stale control socket {} left by a previous process",
                path.display()
            );
            Ok(())
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(format!(
            "failed to remove stale control socket {}: {error}",
            path.display()
        )),
    }
}

#[cfg(unix)]
fn restrict_socket_permissions(path: &Path) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt as _;

    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600)).map_err(|error| {
        format!(
            "failed to restrict control socket permissions on {}: {error}",
            path.display()
        )
    })
}

#[cfg(not(unix))]
fn restrict_socket_permissions(_path: &Path) -> Result<(), String> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use crate::{
        control::{
            client::{self, Target},
            report::{PeerListReport, RuntimeReport, StoreReport, TrafficReport},
            runtime_file::{RuntimeInfo, SCHEMA_VERSION, now_unix_ms},
        },
        test_support::test_context,
    };

    /// Publishes the control surface for a test node the same way `app::run`
    /// does, so these exercise the real socket rather than the router alone.
    async fn published(
        state: &crate::state::SharedState,
    ) -> (Arc<RuntimeInfo>, tokio::sync::watch::Sender<bool>) {
        let info = Arc::new(RuntimeInfo {
            schema_version: SCHEMA_VERSION,
            pid: std::process::id(),
            version: "test".into(),
            started_at_unix_ms: now_unix_ms(),
            data_dir: state.config.data_dir.clone(),
            control_socket_path: RuntimeInfo::control_socket_path(&state.config.data_dir),
            port: state.config.port,
            internal_port: state.config.internal_port,
            node_url: state.config.node_url.clone(),
            region: state.config.region.clone(),
            tenant_id: state.config.tenant_id.clone(),
        });
        let (shutdown_tx, shutdown_rx) = tokio::sync::watch::channel(false);
        super::spawn(state.clone(), info.clone(), shutdown_rx).expect("spawn control socket");
        info.write().expect("publish runtime info");
        (info, shutdown_tx)
    }

    #[tokio::test]
    async fn cli_reaches_the_node_from_the_data_directory_alone() {
        let context = test_context(|_| {}).await;
        let (_info, _shutdown) = published(&context.state).await;

        // This is the whole point of the runtime file: the data directory is the
        // only input, exactly as `kubectl exec` would have it from the pod spec.
        let target =
            Target::resolve(Some(&context.state.config.data_dir)).expect("resolve from data dir");
        let report: RuntimeReport = client::get(&target, "/v1/runtime")
            .await
            .expect("fetch runtime report");

        assert_eq!(report.node.pid, std::process::id());
        assert_eq!(report.node.tenant_id, context.state.config.tenant_id);
        assert_eq!(report.node.region, context.state.config.region);
    }

    #[tokio::test]
    async fn every_route_answers() {
        let context = test_context(|_| {}).await;
        let (_info, _shutdown) = published(&context.state).await;
        let target = Target::resolve(Some(&context.state.config.data_dir)).expect("resolve target");

        let _: TrafficReport = client::get(&target, "/v1/status").await.expect("status");
        let _: StoreReport = client::get(&target, "/v1/store").await.expect("store");
        let _: PeerListReport = client::get(&target, "/v1/peers").await.expect("peers");
        let _: crate::control::report::ReplicationReport =
            client::get(&target, "/v1/outbox").await.expect("outbox");
        let config: serde_json::Value = client::get(&target, "/v1/config").await.expect("config");
        assert!(config.get("config").is_some(), "{config}");
    }

    #[tokio::test]
    async fn resolved_configuration_never_carries_credentials() {
        let context = test_context(|config| {
            config.sentry_dsn = Some("https://public@sentry.example/42".into());
            config.analytics = Some(crate::config::AnalyticsConfig {
                server_url: "https://analytics.example".into(),
                signing_key: "super-secret-signing-key".into(),
                batch_size: 1,
                batch_timeout_ms: 1,
                queue_capacity: 1,
                request_timeout_ms: 1,
                circuit_breaker_failure_threshold: 1,
                circuit_breaker_open_ms: 1,
            });
        })
        .await;
        let (_info, _shutdown) = published(&context.state).await;
        let target = Target::resolve(Some(&context.state.config.data_dir)).expect("resolve target");

        let config: serde_json::Value = client::get(&target, "/v1/config").await.expect("config");
        let rendered = config.to_string();

        assert!(
            !rendered.contains("super-secret-signing-key"),
            "signing key leaked into the config report: {rendered}"
        );
        assert!(
            !rendered.contains("public@sentry.example"),
            "sentry dsn leaked into the config report: {rendered}"
        );
        assert!(rendered.contains(crate::config::REDACTED), "{rendered}");
        // The non-secret shape is still there, which is the point of the command.
        assert!(rendered.contains("analytics.example"), "{rendered}");
    }

    #[tokio::test]
    async fn unknown_route_reports_a_version_skew_rather_than_a_bare_404() {
        let context = test_context(|_| {}).await;
        let (_info, _shutdown) = published(&context.state).await;
        let target = Target::resolve(Some(&context.state.config.data_dir)).expect("resolve target");

        let error = client::get::<serde_json::Value>(&target, "/v1/not-a-route")
            .await
            .expect_err("unknown route should fail");
        assert!(error.contains("newer than the node"), "{error}");
    }

    #[tokio::test]
    async fn a_socket_left_by_a_dead_process_is_replaced_on_startup() {
        let context = test_context(|_| {}).await;
        let path = RuntimeInfo::control_socket_path(&context.state.config.data_dir);
        std::fs::write(&path, b"stale").expect("write stale socket file");

        let (_info, _shutdown) = published(&context.state).await;
        let target = Target::resolve(Some(&context.state.config.data_dir)).expect("resolve target");
        let _: TrafficReport = client::get(&target, "/v1/status")
            .await
            .expect("status should answer after replacing the stale socket");
    }

    /// Ed25519 test pair, matching the one in `control::grant`.
    const TEST_PRIVATE_KEY: &str = "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIEw0VgZ6qDz6frcjXUxn1UmbhH6PjatJ82aq4WHHwypa\n-----END PRIVATE KEY-----\n";
    const TEST_PUBLIC_KEY: &str = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAZ26hfh68Bvdeuq95ilrLWlen0eMOI8l1mZbwMECoeV8=\n-----END PUBLIC KEY-----\n";

    fn grant_config() -> crate::config::ControlGrantConfig {
        crate::config::ControlGrantConfig {
            public_key_pem: TEST_PUBLIC_KEY.to_string(),
            issuer: "grants.example".to_string(),
            audience: "kura.test".to_string(),
            max_ttl_seconds: 3_600,
        }
    }

    fn write_grant() -> String {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_secs() as i64;
        let claims = crate::control::grant::GrantClaims {
            iss: "grants.example".to_string(),
            aud: "kura.test".to_string(),
            sub: "operator@example.com".to_string(),
            tier: "write".to_string(),
            reason: Some("test".to_string()),
            jti: Some("1".to_string()),
            iat: now,
            exp: now + 300,
        };
        jsonwebtoken::encode(
            &jsonwebtoken::Header::new(jsonwebtoken::Algorithm::EdDSA),
            &claims,
            &jsonwebtoken::EncodingKey::from_ed_pem(TEST_PRIVATE_KEY.as_bytes()).expect("key"),
        )
        .expect("sign")
    }

    #[tokio::test]
    async fn a_write_without_a_grant_is_refused() {
        let context = test_context(|config| config.control_grant = Some(grant_config())).await;
        let (_info, _shutdown) = published(&context.state).await;
        let target = Target::resolve(Some(&context.state.config.data_dir)).expect("resolve target");

        let error = client::mutate::<serde_json::Value>(
            &target,
            "POST",
            "/v1/cache/trim",
            None,
            Some(serde_json::json!({"cache": "manifest", "target": 0})),
        )
        .await
        .expect_err("a write with no grant must be refused");
        assert!(error.contains("needs a grant"), "{error}");
    }

    #[tokio::test]
    async fn a_write_with_an_invalid_grant_is_refused_by_the_node() {
        let context = test_context(|config| config.control_grant = Some(grant_config())).await;
        let (_info, _shutdown) = published(&context.state).await;
        let target = Target::resolve(Some(&context.state.config.data_dir)).expect("resolve target");

        let error = client::mutate::<serde_json::Value>(
            &target,
            "POST",
            "/v1/cache/trim",
            Some("not.a.token"),
            Some(serde_json::json!({"cache": "manifest", "target": 0})),
        )
        .await
        .expect_err("a forged grant must be refused");
        assert!(error.contains("403"), "{error}");
    }

    /// A node with no grant configuration refuses writes rather than allowing
    /// them, which is the behaviour that matters for a deployment that never
    /// opts in.
    #[tokio::test]
    async fn a_node_without_grant_configuration_refuses_writes() {
        let context = test_context(|_| {}).await;
        let (_info, _shutdown) = published(&context.state).await;
        let target = Target::resolve(Some(&context.state.config.data_dir)).expect("resolve target");

        let error = client::mutate::<serde_json::Value>(
            &target,
            "POST",
            "/v1/cache/trim",
            Some(&write_grant()),
            Some(serde_json::json!({"cache": "manifest", "target": 0})),
        )
        .await
        .expect_err("an unconfigured node must refuse writes");
        assert!(error.contains("403"), "{error}");
    }

    #[tokio::test]
    async fn a_valid_grant_authorizes_a_cache_trim() {
        let context = test_context(|config| config.control_grant = Some(grant_config())).await;
        let (_info, _shutdown) = published(&context.state).await;
        let target = Target::resolve(Some(&context.state.config.data_dir)).expect("resolve target");

        let result: serde_json::Value = client::mutate(
            &target,
            "POST",
            "/v1/cache/trim",
            Some(&write_grant()),
            Some(serde_json::json!({"cache": "manifest", "target": 0})),
        )
        .await
        .expect("a valid grant should authorize the trim");

        assert_eq!(result["authorized_by"], "operator@example.com");
    }

    /// The integrity property: deleting a namespace must remove the artifact
    /// and every index that referenced it, and must leave a replicating
    /// tombstone. A delete that dropped the manifest but left the namespace or
    /// segment index pointing at it, or that did not enqueue, would look like
    /// it worked and then be undone by the next bootstrap pass.
    #[tokio::test]
    async fn deleting_a_namespace_removes_its_references_and_enqueues_a_tombstone() {
        let context = test_context(|config| {
            config.control_grant = Some(grant_config());
            config.peers = vec!["http://peer-a.example:7443".to_string()];
        })
        .await;
        let store = &context.state.store;

        store
            .persist_artifact_from_bytes(
                crate::artifact::producer::ArtifactProducer::Xcode,
                "doomed",
                "key-one",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("persist artifact");
        assert!(
            store
                .manifest_for_key(
                    crate::artifact::producer::ArtifactProducer::Xcode,
                    "doomed",
                    "key-one"
                )
                .expect("lookup")
                .is_some(),
            "the artifact should exist before the delete"
        );

        let (_info, _shutdown) = published(&context.state).await;
        let target = Target::resolve(Some(&context.state.config.data_dir)).expect("resolve target");

        let result: serde_json::Value = client::mutate(
            &target,
            "DELETE",
            "/v1/namespaces/doomed",
            Some(&write_grant()),
            None,
        )
        .await
        .expect("delete should be authorized");
        assert_eq!(result["authorized_by"], "operator@example.com");

        assert!(
            store
                .manifest_for_key(
                    crate::artifact::producer::ArtifactProducer::Xcode,
                    "doomed",
                    "key-one"
                )
                .expect("lookup")
                .is_none(),
            "the manifest must be gone"
        );

        let tombstones = store
            .namespace_tombstones_page(None, 100)
            .expect("tombstones");
        assert!(
            format!("{tombstones:?}").contains("doomed"),
            "a tombstone must remain so the delete converges instead of being \
             re-seeded by a peer: {tombstones:?}"
        );

        let outbox = store.outbox_messages().expect("outbox");
        assert!(
            !outbox.is_empty(),
            "the delete must be enqueued for replication, or it only applies locally"
        );
    }

    #[tokio::test]
    async fn aborting_an_unknown_upload_is_rejected_rather_than_silently_succeeding() {
        let context = test_context(|config| config.control_grant = Some(grant_config())).await;
        let (_info, _shutdown) = published(&context.state).await;
        let target = Target::resolve(Some(&context.state.config.data_dir)).expect("resolve target");

        let error = client::mutate::<serde_json::Value>(
            &target,
            "DELETE",
            "/v1/uploads/does-not-exist",
            Some(&write_grant()),
            None,
        )
        .await
        .expect_err("aborting a missing upload should fail");
        assert!(error.contains("no multipart upload"), "{error}");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn the_socket_is_not_readable_by_other_users() {
        use std::os::unix::fs::PermissionsExt as _;

        let context = test_context(|_| {}).await;
        let (info, _shutdown) = published(&context.state).await;

        let mode = std::fs::metadata(&info.control_socket_path)
            .expect("socket metadata")
            .permissions()
            .mode();
        assert_eq!(
            mode & 0o777,
            0o600,
            "the control surface carries resolved configuration, so it must stay owner-only"
        );
    }
}
