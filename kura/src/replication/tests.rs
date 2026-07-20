use axum::{Json, Router, extract::Path as AxumPath, http::StatusCode, routing::get};
use tokio::net::TcpListener;

use super::*;
use crate::{
    artifact::producer::ArtifactProducer,
    failpoints::{FailpointAction, FailpointName},
    http::router,
    test_support::{TestContext, test_context},
    utils::artifact_storage_id,
};

fn bucket(prefix: &str, count: u64, hash: &str) -> ManifestBucketDigest {
    ManifestBucketDigest {
        prefix: prefix.to_string(),
        count,
        hash: hash.to_string(),
    }
}

#[test]
fn divergent_prefixes_are_empty_when_digests_match() {
    let local = vec![bucket("00a", 3, "h1"), bucket("0f2", 1, "h2")];
    let peer = local.clone();
    assert!(
        divergent_prefixes(&local, &peer).is_empty(),
        "matching digests must walk zero ranges"
    );
}

#[test]
fn divergent_prefixes_flags_changed_and_peer_only_but_not_local_only() {
    let local = vec![
        bucket("00a", 3, "match"),
        bucket("0f2", 1, "old"),
        bucket("aaa", 5, "local-only"),
    ];
    let peer = vec![
        bucket("00a", 3, "match"),
        bucket("0f2", 1, "new"),
        bucket("bbb", 2, "peer-only"),
    ];
    let mut divergent = divergent_prefixes(&local, &peer);
    divergent.sort();
    assert_eq!(
        divergent,
        vec!["0f2".to_string(), "bbb".to_string()],
        "walk changed and peer-only buckets; ignore matched and local-only"
    );
}

#[test]
fn divergent_prefixes_flags_count_mismatch_with_colliding_hash() {
    let local = vec![bucket("00a", 3, "h")];
    let peer = vec![bucket("00a", 4, "h")];
    assert_eq!(
        divergent_prefixes(&local, &peer),
        vec!["00a".to_string()],
        "count is a discriminator even when the hash matches"
    );
}

fn cursor_manifest(id: &str) -> ArtifactManifest {
    ArtifactManifest {
        artifact_id: id.to_string(),
        producer: ArtifactProducer::Xcode,
        namespace_id: "ios".to_string(),
        key: id.to_string(),
        content_type: "application/octet-stream".to_string(),
        inline: false,
        blob_path: None,
        segment_id: None,
        segment_offset: None,
        size: 0,
        version_ms: 0,
        created_at_ms: 0,
    }
}

fn manifest_page(next_after: Option<&str>, manifests: Vec<ArtifactManifest>) -> ManifestPage {
    ManifestPage {
        manifests,
        next_after: next_after.map(str::to_string),
    }
}

#[test]
fn ensure_cursor_advances_accepts_forward_and_terminal_pages() {
    // Terminal page (no cursor) always ends the walk cleanly.
    assert!(ensure_cursor_advances("peer", Some("m"), &manifest_page(None, vec![])).is_ok());
    // First page (no prior cursor) that returns a cursor advances from nothing.
    assert!(
        ensure_cursor_advances(
            "peer",
            None,
            &manifest_page(Some("b"), vec![cursor_manifest("b")])
        )
        .is_ok()
    );
    // Strictly forward cursor.
    assert!(
        ensure_cursor_advances(
            "peer",
            Some("b"),
            &manifest_page(Some("c"), vec![cursor_manifest("c")])
        )
        .is_ok()
    );
}

#[test]
fn ensure_cursor_advances_rejects_stale_backward_or_empty_pages() {
    // Same cursor as requested → would loop forever without the guard.
    assert!(
        ensure_cursor_advances(
            "peer",
            Some("b"),
            &manifest_page(Some("b"), vec![cursor_manifest("b")])
        )
        .is_err()
    );
    // Cursor moving backwards.
    assert!(
        ensure_cursor_advances(
            "peer",
            Some("c"),
            &manifest_page(Some("b"), vec![cursor_manifest("b")])
        )
        .is_err()
    );
    // Empty page that still claims there is more to fetch.
    assert!(ensure_cursor_advances("peer", Some("b"), &manifest_page(Some("c"), vec![])).is_err());
}

#[test]
fn skips_self_and_own_gateway_but_adopts_other_peers() {
    let own = "https://kura-eu-0.kura-eu-headless.kura.svc.cluster.local:7443";
    let gateway = "https://peer.tuist-eu-1.kura.tuist.dev:7443";

    // Our own in-cluster URL and our own gateway are both skipped.
    assert!(is_self_or_own_gateway(own, own, Some(gateway)));
    assert!(is_self_or_own_gateway(gateway, own, Some(gateway)));

    // A different peer (another instance, or a self-hosted node) is adopted.
    assert!(!is_self_or_own_gateway(
        "https://kura-eu-1.kura-eu-headless.kura.svc.cluster.local:7443",
        own,
        Some(gateway),
    ));

    // With no gateway of our own, an external node adopting the managed
    // gateway URL must not skip it.
    assert!(!is_self_or_own_gateway(gateway, own, None));
}

async fn spawn_server(app: Router) -> (String, tokio::task::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("failed to bind test listener");
    let address = listener
        .local_addr()
        .expect("failed to read listener address");
    let handle = tokio::spawn(async move {
        axum::serve(listener, app)
            .await
            .expect("test server should run");
    });
    (format!("http://{address}"), handle)
}

fn bootstrap_test_manifest(
    producer: ArtifactProducer,
    inline: bool,
    namespace_id: &str,
    key: &str,
    content_type: &str,
    size: u64,
    version_ms: u64,
) -> ArtifactManifest {
    ArtifactManifest {
        artifact_id: artifact_storage_id(producer, "test-tenant", namespace_id, key),
        producer,
        namespace_id: namespace_id.to_owned(),
        key: key.to_owned(),
        content_type: content_type.to_owned(),
        inline,
        blob_path: None,
        segment_id: None,
        segment_offset: None,
        size,
        version_ms,
        created_at_ms: version_ms,
    }
}

#[tokio::test]
async fn enqueue_replication_skips_current_node() {
    let ctx = test_context(|config| {
        config.node_url = "http://127.0.0.1:4100".into();
        config.peers = vec![
            "http://127.0.0.1:4100".into(),
            "http://127.0.0.1:4101".into(),
        ];
    })
    .await;
    let manifest = ctx
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "namespace",
            "artifact",
            "application/octet-stream",
            b"hello",
        )
        .await
        .expect("artifact should persist");

    enqueue_replication_for_artifact(&ctx.state, &manifest).await;

    let queued = ctx
        .state
        .store
        .outbox_messages()
        .expect("outbox should load");
    assert_eq!(queued.len(), 1);
    assert_eq!(queued[0].1.target, "http://127.0.0.1:4101");
}

#[tokio::test]
async fn discover_targets_keeps_dns_names_for_https_peers() {
    let ctx = test_context(|config| {
        config.node_url = "https://kura-us.kura.internal:7443".into();
        config.peers = vec!["https://seed.kura.internal:7443".into()];
        config.discovery_dns_name = Some("localhost".into());
        config.global_discovery_dns_name = Some("localhost".into());
    })
    .await;

    let targets = discovery_targets(&ctx.state.config, &ctx.state.dynamic_peers.load()).await;

    assert!(targets.iter().any(|target| {
        target.url == "https://seed.kura.internal:7443" && target.resolved.is_none()
    }));
    assert!(targets.iter().any(|target| {
        target.url == "https://localhost:7443"
            && target.scope == DiscoveryScope::Local
            && target.resolved.is_some()
    }));
    assert!(targets.iter().any(|target| {
        target.url == "https://localhost:7443"
            && target.scope == DiscoveryScope::Global
            && target.resolved.is_some()
    }));
    assert!(!targets.iter().any(|target| {
        target.url.starts_with("https://127.") || target.url.starts_with("https://[::1]")
    }));
}

#[tokio::test]
async fn process_outbox_replicates_artifacts_and_namespace_deletes() {
    let remote = test_context(|_| {}).await;
    let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

    let local = test_context(|_| {}).await;
    local
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
        )
        .await
        .expect("artifact should persist");

    local
        .state
        .store
        .enqueue(OutboxMessage {
            target: remote_url.clone(),
            operation: ReplicationOperation::UpsertArtifact {
                producer: ArtifactProducer::Gradle,
                namespace_id: "ios".into(),
                key: "artifact".into(),
                content_type: "application/octet-stream".into(),
                artifact_id: local
                    .state
                    .store
                    .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
                    .await
                    .expect("artifact fetch should succeed")
                    .expect("artifact should exist")
                    .artifact_id,
                version_ms: local
                    .state
                    .store
                    .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
                    .await
                    .expect("artifact fetch should succeed")
                    .expect("artifact should exist")
                    .version_ms,
                inline: false,
            },
        })
        .expect("upsert should enqueue");

    local
        .state
        .store
        .enqueue(OutboxMessage {
            target: remote_url,
            operation: ReplicationOperation::DeleteNamespace {
                namespace_id: "android".into(),
                version_ms: 123,
            },
        })
        .expect("delete should enqueue");

    process_outbox(&local.state)
        .await
        .expect("outbox processing should succeed");

    let replicated = remote
        .state
        .store
        .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
        .await
        .expect("artifact fetch should succeed")
        .expect("replicated artifact should exist");
    let mut reader = remote
        .state
        .store
        .open_artifact_reader(&replicated)
        .await
        .expect("replicated artifact reader should open");
    let mut bytes = Vec::new();
    use tokio::io::AsyncReadExt;
    reader
        .read_to_end(&mut bytes)
        .await
        .expect("replicated bytes should read");
    assert_eq!(bytes, b"payload");

    let queued = local
        .state
        .store
        .outbox_messages()
        .expect("outbox should load");
    assert!(
        queued.is_empty(),
        "successful replication should clear outbox"
    );
}

fn stale_target_message(target: &str) -> OutboxMessage {
    OutboxMessage {
        target: target.into(),
        operation: ReplicationOperation::DeleteNamespace {
            namespace_id: "ios".into(),
            version_ms: 1,
        },
    }
}

async fn complete_initial_discovery(state: &SharedState) {
    state
        .apply_membership_view(
            std::collections::BTreeSet::new(),
            std::collections::BTreeMap::new(),
            true,
        )
        .await;
}

#[tokio::test]
async fn process_outbox_drops_messages_for_targets_that_left_the_mesh() {
    let local = test_context(|config| {
        config.peers = vec!["https://live-peer.test:7443".into()];
    })
    .await;
    complete_initial_discovery(&local.state).await;
    local
        .state
        .store
        .enqueue(stale_target_message("https://gone-peer.test:7443"))
        .expect("enqueue should succeed");

    process_outbox(&local.state)
        .await
        .expect("outbox processing should succeed");

    let queued = local
        .state
        .store
        .outbox_messages()
        .expect("outbox should load");
    assert!(
        queued.is_empty(),
        "messages for a target that left the mesh should be dropped"
    );
}

#[tokio::test]
async fn process_outbox_defers_pruning_until_a_membership_pass_completes() {
    // The outbox is persistent while every pruning protection is
    // process-scoped: a fresh process restarting with a backlog must not
    // prune before its first membership pass, or messages for live peers
    // whose exemptions have not refilled yet would be destroyed.
    let local = test_context(|config| {
        config.peers = vec!["https://live-peer.test:7443".into()];
    })
    .await;
    local
        .state
        .store
        .enqueue(stale_target_message("https://gone-peer.test:7443"))
        .expect("enqueue should succeed");

    process_outbox(&local.state)
        .await
        .expect("outbox processing should succeed");
    assert_eq!(
        local.state.store.outbox_messages().expect("load").len(),
        1,
        "nothing may be pruned before the first completed membership pass"
    );

    complete_initial_discovery(&local.state).await;
    process_outbox(&local.state)
        .await
        .expect("outbox processing should succeed");
    assert!(
        local
            .state
            .store
            .outbox_messages()
            .expect("load")
            .is_empty(),
        "pruning should proceed once the peer view has arrived"
    );
}

#[tokio::test]
async fn process_outbox_defers_pruning_while_the_first_peers_sync_is_pending() {
    let local = test_context(|config| {
        config.peers = vec!["https://live-peer.test:7443".into()];
    })
    .await;
    local.state.runtime.require_peer_view();
    complete_initial_discovery(&local.state).await;
    local
        .state
        .store
        .enqueue(stale_target_message("https://gone-peer.test:7443"))
        .expect("enqueue should succeed");

    process_outbox(&local.state)
        .await
        .expect("outbox processing should succeed");
    assert_eq!(
        local.state.store.outbox_messages().expect("load").len(),
        1,
        "nothing may be pruned while the first peers sync is pending"
    );

    local.state.runtime.mark_peer_view_ready();
    process_outbox(&local.state)
        .await
        .expect("outbox processing should succeed");
    assert!(
        local
            .state
            .store
            .outbox_messages()
            .expect("load")
            .is_empty(),
        "pruning should proceed once the sync has landed"
    );
}

#[tokio::test]
async fn process_outbox_drops_messages_for_boot_time_peers_that_left_the_mesh() {
    // The static seed is managed/stable peers only, so a self-hosted peer
    // present at boot lives in the dynamic view — its departure arrives
    // via a later heartbeat and must be prunable without a restart.
    let local = test_context(|_| {}).await;
    complete_initial_discovery(&local.state).await;
    local.state.dynamic_peers.store(std::sync::Arc::new(vec![
        "https://gone-peer.test:7443".to_string(),
        "https://live-peer.test:7443".to_string(),
    ]));
    local
        .state
        .store
        .enqueue(stale_target_message("https://gone-peer.test:7443"))
        .expect("enqueue should succeed");

    // The next heartbeat's peer view no longer contains the departed peer.
    local.state.dynamic_peers.store(std::sync::Arc::new(vec![
        "https://live-peer.test:7443".to_string(),
    ]));

    process_outbox(&local.state)
        .await
        .expect("outbox processing should succeed");

    let queued = local
        .state
        .store
        .outbox_messages()
        .expect("outbox should load");
    assert!(
        queued.is_empty(),
        "boot-time peers must be prunable once the dynamic view drops them"
    );
}

#[tokio::test]
async fn process_outbox_never_drops_messages_for_discovered_peers() {
    // An in-cluster sibling known only through discovery flaps out of the
    // membership view. Unlike an enrolled peer, nothing re-bootstraps it
    // after the flap, so its messages must never be dropped.
    let local = test_context(|_| {}).await;
    local.state.dynamic_peers.store(std::sync::Arc::new(vec![
        "https://live-peer.test:7443".to_string(),
    ]));
    local
        .state
        .note_discovered_only_peers(vec!["https://sibling-0.test:7443".to_string()])
        .await;
    local
        .state
        .store
        .enqueue(stale_target_message("https://sibling-0.test:7443"))
        .expect("enqueue should succeed");

    process_outbox(&local.state)
        .await
        .expect("outbox processing should succeed");

    let queued = local
        .state
        .store
        .outbox_messages()
        .expect("outbox should load");
    assert_eq!(
        queued.len(),
        1,
        "a discovered sibling's flap must not destroy its queued messages"
    );
}

#[tokio::test]
async fn process_outbox_never_drops_when_the_node_has_no_peer_view() {
    // The default test config's only peer is the node itself, so the
    // current target set is empty — the control-plane-unreachable shape.
    let local = test_context(|_| {}).await;
    local
        .state
        .store
        .enqueue(stale_target_message("https://gone-peer.test:7443"))
        .expect("enqueue should succeed");

    process_outbox(&local.state)
        .await
        .expect("outbox processing should succeed");

    let queued = local
        .state
        .store
        .outbox_messages()
        .expect("outbox should load");
    assert_eq!(
        queued.len(),
        1,
        "an empty peer view must never be treated as every peer having left"
    );
}

#[tokio::test]
async fn process_outbox_backs_off_unreachable_target() {
    let local = test_context(|_| {}).await;
    let unreachable = "http://127.0.0.1:1".to_string();
    local
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
        )
        .await
        .expect("artifact should persist");
    let artifact = local
        .state
        .store
        .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
        .await
        .expect("artifact fetch should succeed")
        .expect("artifact should exist");
    local
        .state
        .store
        .enqueue(OutboxMessage {
            target: unreachable.clone(),
            operation: ReplicationOperation::UpsertArtifact {
                producer: ArtifactProducer::Gradle,
                namespace_id: "ios".into(),
                key: "artifact".into(),
                content_type: "application/octet-stream".into(),
                artifact_id: artifact.artifact_id,
                version_ms: artifact.version_ms,
                inline: false,
            },
        })
        .expect("upsert should enqueue");

    assert!(
        !local
            .state
            .replication_target_backed_off(&unreachable, Instant::now())
            .await
    );

    process_outbox(&local.state)
        .await
        .expect("outbox processing should not error on a failed peer");

    assert!(
        local
            .state
            .replication_target_backed_off(&unreachable, Instant::now())
            .await,
        "a failed replication target should be backed off"
    );
    assert_eq!(
        local
            .state
            .store
            .outbox_messages()
            .expect("outbox should load")
            .len(),
        1,
        "a failed message must stay in the outbox"
    );
}

#[tokio::test]
async fn process_outbox_skips_backed_off_target() {
    let remote = test_context(|_| {}).await;
    let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

    let local = test_context(|_| {}).await;
    local
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
        )
        .await
        .expect("artifact should persist");
    let artifact = local
        .state
        .store
        .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
        .await
        .expect("artifact fetch should succeed")
        .expect("artifact should exist");
    local
        .state
        .store
        .enqueue(OutboxMessage {
            target: remote_url.clone(),
            operation: ReplicationOperation::UpsertArtifact {
                producer: ArtifactProducer::Gradle,
                namespace_id: "ios".into(),
                key: "artifact".into(),
                content_type: "application/octet-stream".into(),
                artifact_id: artifact.artifact_id,
                version_ms: artifact.version_ms,
                inline: false,
            },
        })
        .expect("upsert should enqueue");

    local
        .state
        .note_replication_failure(&remote_url, Instant::now())
        .await;

    process_outbox(&local.state)
        .await
        .expect("outbox processing should succeed");

    assert!(
        remote
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .is_none(),
        "a backed-off target must not be contacted"
    );
    assert_eq!(
        local
            .state
            .store
            .outbox_messages()
            .expect("outbox should load")
            .len(),
        1,
        "a skipped message must remain in the outbox"
    );

    local.state.note_replication_success(&remote_url).await;

    process_outbox(&local.state)
        .await
        .expect("outbox processing should succeed");

    assert!(
        remote
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .is_some(),
        "after backoff clears, replication should proceed"
    );
    assert!(
        local
            .state
            .store
            .outbox_messages()
            .expect("outbox should load")
            .is_empty(),
        "successful replication should clear the outbox"
    );
}

#[tokio::test]
async fn process_outbox_retries_after_success_before_outbox_delete() {
    let remote = test_context(|_| {}).await;
    let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;
    let local = test_context(|_| {}).await;

    let manifest = local
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
        )
        .await
        .expect("artifact should persist");

    local
        .state
        .store
        .enqueue(OutboxMessage {
            target: remote_url,
            operation: ReplicationOperation::UpsertArtifact {
                producer: ArtifactProducer::Gradle,
                namespace_id: "ios".into(),
                key: "artifact".into(),
                content_type: "application/octet-stream".into(),
                artifact_id: manifest.artifact_id.clone(),
                version_ms: manifest.version_ms,
                inline: false,
            },
        })
        .expect("outbox message should enqueue");

    local.state.store.failpoints().set_once(
        FailpointName::BeforeDeleteOutboxMessageAfterSuccess,
        FailpointAction::Error("delete interrupted".into()),
    );

    process_outbox(&local.state)
        .await
        .expect("outbox processing should complete");

    assert_eq!(
        local
            .state
            .store
            .outbox_message_count()
            .expect("outbox count should load"),
        1
    );

    process_outbox(&local.state)
        .await
        .expect("outbox retry should complete");

    assert_eq!(
        local
            .state
            .store
            .outbox_message_count()
            .expect("outbox count should load"),
        0
    );
    let replicated = remote
        .state
        .store
        .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
        .await
        .expect("artifact fetch should succeed")
        .expect("replicated artifact should exist");
    let mut reader = remote
        .state
        .store
        .open_artifact_reader(&replicated)
        .await
        .expect("artifact reader should open");
    let mut bytes = Vec::new();
    use tokio::io::AsyncReadExt;
    reader
        .read_to_end(&mut bytes)
        .await
        .expect("artifact bytes should read");
    assert_eq!(bytes, b"payload");
}

#[tokio::test]
async fn bootstrap_respects_local_newer_winner() {
    let remote = test_context(|_| {}).await;
    let remote_manifest = remote
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"remote-v1",
        )
        .await
        .expect("remote artifact should persist");
    let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

    let local = test_context(|_| {}).await;
    local
        .state
        .store
        .apply_replicated_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"local-v2",
            remote_manifest.version_ms + 100,
        )
        .await
        .expect("local newer artifact should apply");

    let outcome = bootstrap_artifact_from_peer(&local.state, &remote_url, &remote_manifest)
        .await
        .expect("bootstrap should complete");
    assert_eq!(outcome, ArtifactApplyOutcome::IgnoredStale);

    let manifest = local
        .state
        .store
        .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
        .await
        .expect("artifact fetch should succeed")
        .expect("artifact should remain");
    let mut reader = local
        .state
        .store
        .open_artifact_reader(&manifest)
        .await
        .expect("artifact reader should open");
    let mut bytes = Vec::new();
    use tokio::io::AsyncReadExt;
    reader
        .read_to_end(&mut bytes)
        .await
        .expect("artifact bytes should read");
    assert_eq!(bytes, b"local-v2");
}

#[tokio::test]
async fn bootstrap_continues_past_a_failing_artifact_and_reports_partial() {
    use axum::{
        body::Body,
        extract::Request,
        middleware::{self, Next},
        response::Response,
    };

    let remote = test_context(|_| {}).await;
    remote
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "ios",
            "good",
            "application/octet-stream",
            b"good-data",
        )
        .await
        .expect("good artifact should persist");
    let bad = remote
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "ios",
            "bad",
            "application/octet-stream",
            b"bad-data",
        )
        .await
        .expect("bad artifact should persist");

    // Serve the real bootstrap endpoints, but 500 the "bad" artifact the way
    // a peer that hasn't finished bootstrapping it yet would.
    let poison_path = format!(
        "/_internal/bootstrap/artifacts/{}",
        url_encode(&bad.artifact_id)
    );
    let app = router(remote.state.clone()).layer(middleware::from_fn(
        move |request: Request, next: Next| {
            let poison_path = poison_path.clone();
            async move {
                if request.uri().path() == poison_path {
                    return Response::builder()
                        .status(StatusCode::INTERNAL_SERVER_ERROR)
                        .body(Body::from("incomplete"))
                        .unwrap();
                }
                next.run(request).await
            }
        },
    ));
    let (remote_url, _server) = spawn_server(app).await;

    let local = test_context(|_| {}).await;
    let result = bootstrap_manifests_from_peer(&local.state, &remote_url, &AtomicU64::new(0)).await;

    // The peer bootstrap surfaces failure so it gets retried ...
    assert!(
        result.is_err(),
        "a failed artifact must surface as a retryable bootstrap failure"
    );
    // ... but the good artifact was still applied — forward progress, not an
    // abort at the first failure (which is what deadlocks a mutually
    // bootstrapping mesh).
    assert!(
        local
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "good")
            .await
            .expect("good fetch should succeed")
            .is_some(),
        "the good artifact must apply even though another failed"
    );
    assert!(
        local
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "bad")
            .await
            .expect("bad fetch should succeed")
            .is_none(),
        "the failed artifact must not be applied"
    );
}

#[tokio::test]
async fn bootstrap_tombstones_prevent_stale_manifest_resurrection() {
    let stale_manifest = bootstrap_test_manifest(
        ArtifactProducer::Xcode,
        true,
        "ios",
        "cas-1",
        "application/json",
        br#"{"value":"stale"}"#.len() as u64,
        100,
    );
    let tombstones = NamespaceTombstonePage {
        tombstones: vec![crate::store::NamespaceTombstoneRecord {
            namespace_id: "ios".into(),
            version_ms: 200,
        }],
        next_after: None,
    };
    let manifests = ManifestPage {
        manifests: vec![stale_manifest.clone()],
        next_after: None,
    };
    let artifact_payload = br#"{"value":"stale"}"#.to_vec();
    let app = Router::new()
        .route(
            "/_internal/bootstrap/namespace_tombstones",
            get({
                let tombstones = tombstones.clone();
                move || {
                    let tombstones = tombstones.clone();
                    async move { Json(tombstones) }
                }
            }),
        )
        .route(
            "/_internal/bootstrap/manifests",
            get({
                let manifests = manifests.clone();
                move || {
                    let manifests = manifests.clone();
                    async move { Json(manifests) }
                }
            }),
        )
        .route(
            "/_internal/bootstrap/artifacts/{artifact_id}",
            get(move |AxumPath(_artifact_id): AxumPath<String>| {
                let artifact_payload = artifact_payload.clone();
                async move { (StatusCode::OK, artifact_payload) }
            }),
        );
    let (remote_url, _server) = spawn_server(app).await;
    let local = test_context(|_| {}).await;

    let stats = bootstrap_from_peer(&local.state, &remote_url, &AtomicU64::new(0))
        .await
        .expect("bootstrap should complete");
    assert_eq!(stats.tombstones_applied, 1);
    assert_eq!(stats.artifacts_applied, 0);
    assert!(
        local
            .state
            .store
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "cas-1")
            .await
            .expect("artifact fetch should succeed")
            .is_none()
    );
}

#[tokio::test]
async fn bootstrap_stale_manifest_then_tombstone_converges_to_delete() {
    let stale_manifest = bootstrap_test_manifest(
        ArtifactProducer::Xcode,
        true,
        "ios",
        "cas-1",
        "application/json",
        br#"{"value":"stale"}"#.len() as u64,
        100,
    );
    let tombstones = NamespaceTombstonePage {
        tombstones: vec![crate::store::NamespaceTombstoneRecord {
            namespace_id: "ios".into(),
            version_ms: 200,
        }],
        next_after: None,
    };
    let artifact_payload = br#"{"value":"stale"}"#.to_vec();
    let app = Router::new()
        .route(
            "/_internal/bootstrap/namespace_tombstones",
            get({
                let tombstones = tombstones.clone();
                move || {
                    let tombstones = tombstones.clone();
                    async move { Json(tombstones) }
                }
            }),
        )
        .route(
            "/_internal/bootstrap/artifacts/{artifact_id}",
            get(move |AxumPath(_artifact_id): AxumPath<String>| {
                let artifact_payload = artifact_payload.clone();
                async move { (StatusCode::OK, artifact_payload) }
            }),
        );
    let (remote_url, _server) = spawn_server(app).await;
    let local = test_context(|_| {}).await;

    let outcome = bootstrap_artifact_from_peer(&local.state, &remote_url, &stale_manifest)
        .await
        .expect("artifact bootstrap should complete");
    assert_eq!(outcome, ArtifactApplyOutcome::Applied);
    assert!(
        local
            .state
            .store
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "cas-1")
            .await
            .expect("artifact fetch should succeed")
            .is_some()
    );

    let applied =
        bootstrap_namespace_tombstones_from_peer(&local.state, &remote_url, &AtomicU64::new(0))
            .await
            .expect("tombstone bootstrap should complete");
    assert_eq!(applied, 1);
    assert!(
        local
            .state
            .store
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "cas-1")
            .await
            .expect("artifact fetch should succeed")
            .is_none()
    );
}

#[tokio::test]
async fn bootstrap_fetch_failpoint_prevents_partial_visibility() {
    let remote = test_context(|_| {}).await;
    let remote_manifest = remote
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
        )
        .await
        .expect("remote artifact should persist");
    let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;
    let local = test_context(|_| {}).await;
    local.state.store.failpoints().set_once(
        FailpointName::AfterBootstrapArtifactFetchBeforePersist,
        FailpointAction::Error("bootstrap interrupted".into()),
    );

    let error = bootstrap_artifact_from_peer(&local.state, &remote_url, &remote_manifest)
        .await
        .expect_err("bootstrap should fail before persist");
    assert!(error.contains("bootstrap interrupted"));
    assert!(
        local
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .is_none()
    );
}

#[tokio::test]
async fn bootstrap_skips_all_ranges_when_digests_match() {
    let remote = test_context(|_| {}).await;
    let remote_manifest = remote
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
        )
        .await
        .expect("remote artifact should persist");
    let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

    // Local already holds the identical artifact (same id and version_ms), so
    // the digest exchange must match every bucket.
    let local = test_context(|_| {}).await;
    local
        .state
        .store
        .apply_replicated_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
            remote_manifest.version_ms,
        )
        .await
        .expect("local applies the identical replicated artifact");

    // Arm the page-walk failpoint: a matching digest must skip every bucket,
    // so no manifest page is ever fetched and this never fires. If the digest
    // path regressed into a full walk, this would error the bootstrap.
    local.state.store.failpoints().set_once(
        FailpointName::AfterBootstrapManifestPageFetchBeforeApply,
        FailpointAction::Error("no range should be walked for an in-sync pair".into()),
    );

    let applied = bootstrap_manifests_from_peer(&local.state, &remote_url, &AtomicU64::new(0))
        .await
        .expect("bootstrap should succeed without walking any range");
    assert_eq!(applied, 0, "an in-sync pair applies nothing");
}

#[tokio::test]
async fn bootstrap_falls_back_to_full_walk_when_peer_lacks_digest_endpoint() {
    use axum::{
        extract::Request,
        middleware::{self, Next},
        response::IntoResponse,
    };

    let remote = test_context(|_| {}).await;
    remote
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
        )
        .await
        .expect("remote artifact should persist");

    // Model a peer one version behind, before the digest endpoint existed: it
    // 404s the digest so the joining node must fall back to the full walk.
    async fn deny_digest(request: Request, next: Next) -> axum::response::Response {
        if request.uri().path() == "/_internal/bootstrap/digest" {
            return StatusCode::NOT_FOUND.into_response();
        }
        next.run(request).await
    }
    let peer_router = router(remote.state.clone()).layer(middleware::from_fn(deny_digest));
    let (remote_url, _server) = spawn_server(peer_router).await;

    let local = test_context(|_| {}).await;
    let applied = bootstrap_manifests_from_peer(&local.state, &remote_url, &AtomicU64::new(0))
        .await
        .expect("bootstrap should fall back to a full walk");
    assert_eq!(
        applied, 1,
        "the peer's artifact should replicate via the fallback walk"
    );
    assert!(
        local
            .state
            .store
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .is_some()
    );
}

#[tokio::test]
async fn range_digest_reconciles_a_mostly_in_sync_pair_by_walking_only_the_delta() {
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };

    use axum::{
        extract::Request,
        middleware::{self, Next},
        response::IntoResponse,
    };

    // Reproduces the production wedge: a large peer dataset that the joining
    // node already holds almost all of. Prod is ~1.4M artifacts / 4096
    // buckets, ~99% in sync; a thousand here spans many buckets and forces
    // the legacy full walk into several pages while staying fast.
    const TOTAL: usize = 1024;
    const MISSING: usize = 2;

    let remote = test_context(|_| {}).await;
    let mut keys = Vec::with_capacity(TOTAL);
    for i in 0..TOTAL {
        let key = format!("artifact-{i:05}");
        remote
            .state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                &key,
                "application/octet-stream",
                b"payload",
                100,
            )
            .await
            .expect("remote applies artifact");
        keys.push(key);
    }

    // Build a fresh local that already holds all but the first MISSING keys
    // (identical id + version_ms, exactly as a replicated peer would), i.e.
    // ~99% in sync.
    async fn build_local_holding_all_but_missing(keys: &[String]) -> TestContext {
        let local = test_context(|_| {}).await;
        for key in &keys[MISSING..] {
            local
                .state
                .store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    key,
                    "application/octet-stream",
                    b"payload",
                    100,
                )
                .await
                .expect("local applies artifact");
        }
        local
    }

    // --- New path: peer serves the digest endpoint ---
    let digest_pages = Arc::new(AtomicUsize::new(0));
    let dp = digest_pages.clone();
    let digest_router = router(remote.state.clone()).layer(middleware::from_fn(
        move |request: Request, next: Next| {
            let dp = dp.clone();
            async move {
                if request.uri().path() == "/_internal/bootstrap/manifests" {
                    dp.fetch_add(1, Ordering::SeqCst);
                }
                next.run(request).await
            }
        },
    ));
    let (digest_url, _digest_server) = spawn_server(digest_router).await;

    let local_new = build_local_holding_all_but_missing(&keys).await;
    let applied_new =
        bootstrap_manifests_from_peer(&local_new.state, &digest_url, &AtomicU64::new(0))
            .await
            .expect("digest-path bootstrap converges");
    assert_eq!(applied_new, MISSING as u64, "only the delta is applied");
    for key in &keys[..MISSING] {
        assert!(
            local_new
                .state
                .store
                .fetch_artifact(ArtifactProducer::Xcode, "ios", key)
                .await
                .expect("fetch")
                .is_some(),
            "the missing artifact must be pulled"
        );
    }

    // O(delta) proof, independent of dataset size: the digest matched almost
    // every bucket and only the diverging ones were walked.
    let rendered = local_new.state.metrics.render();
    let bucket_counter = |result: &str| -> u64 {
        rendered
            .lines()
            .find(|line| {
                line.starts_with("kura_bootstrap_digest_buckets_total")
                    && line.contains(&format!("result=\"{result}\""))
            })
            .and_then(|line| line.rsplit(' ').next())
            .and_then(|value| value.trim().parse::<u64>().ok())
            .unwrap_or(0)
    };
    let matched = bucket_counter("matched");
    let walked = bucket_counter("walked");
    assert!(
        walked >= 1 && walked <= MISSING as u64,
        "walked ~= delta, got {walked}"
    );
    assert!(
        matched >= 100,
        "matched must dwarf walked (skipped ~all buckets), got matched={matched} walked={walked}"
    );
    let digest_page_count = digest_pages.load(Ordering::SeqCst);
    assert!(
        digest_page_count <= MISSING,
        "digest path walks only diverging buckets, got {digest_page_count} pages"
    );

    // --- Old path (A/B control): identical peer, but the digest endpoint
    // 404s so the joining node takes the legacy full walk. Same ~99%-in-sync
    // local, yet it must page the entire keyspace to apply the same delta. ---
    let full_pages = Arc::new(AtomicUsize::new(0));
    let fp = full_pages.clone();
    let fallback_router = router(remote.state.clone()).layer(middleware::from_fn(
        move |request: Request, next: Next| {
            let fp = fp.clone();
            async move {
                let path = request.uri().path().to_owned();
                if path == "/_internal/bootstrap/digest" {
                    return StatusCode::NOT_FOUND.into_response();
                }
                if path == "/_internal/bootstrap/manifests" {
                    fp.fetch_add(1, Ordering::SeqCst);
                }
                next.run(request).await
            }
        },
    ));
    let (fallback_url, _fallback_server) = spawn_server(fallback_router).await;

    let local_old = build_local_holding_all_but_missing(&keys).await;
    let applied_old =
        bootstrap_manifests_from_peer(&local_old.state, &fallback_url, &AtomicU64::new(0))
            .await
            .expect("fallback bootstrap converges");
    assert_eq!(
        applied_old, MISSING as u64,
        "fallback applies the same delta"
    );

    let full_page_count = full_pages.load(Ordering::SeqCst);
    let expected_full_walk = TOTAL.div_ceil(BOOTSTRAP_PAGE_LIMIT);
    assert_eq!(
        full_page_count, expected_full_walk,
        "legacy walk pages the entire keyspace"
    );
    assert!(
        digest_page_count < full_page_count,
        "range digest walks fewer pages than the full walk ({digest_page_count} < {full_page_count}); at prod scale (1.4M) the full walk is ~5652 pages while the digest path stays == delta"
    );
}

#[tokio::test]
async fn bootstrap_completes_a_slow_but_progressing_pull() {
    use axum::{
        extract::Request,
        middleware::{self, Next},
        response::IntoResponse,
    };

    // A dataset whose full pull takes far longer than one watchdog window.
    let remote = test_context(|_| {}).await;
    for i in 0..800 {
        let key = format!("artifact-{i:05}");
        remote
            .state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                &key,
                "application/octet-stream",
                b"payload",
                100,
            )
            .await
            .expect("remote applies artifact");
    }

    // Peer takes the linear full walk (digest 404s) and delays every manifest
    // page, so wall-clock runtime spans many windows while each step lands
    // well inside one.
    async fn slow_manifests(request: Request, next: Next) -> axum::response::Response {
        let path = request.uri().path().to_owned();
        if path == "/_internal/bootstrap/digest" {
            return StatusCode::NOT_FOUND.into_response();
        }
        if path == "/_internal/bootstrap/manifests" {
            sleep(Duration::from_millis(120)).await;
        }
        next.run(request).await
    }
    let peer = router(remote.state.clone()).layer(middleware::from_fn(slow_manifests));
    let (peer_url, _server) = spawn_server(peer).await;

    // A single wall-clock cap of 300ms — the old behavior — would kill this
    // multi-second pull mid-walk and restart it forever. The no-progress
    // watchdog lets it run to completion because every page and artifact is
    // forward progress.
    let local = test_context(|_| {}).await;
    let stats =
        bootstrap_from_peer_with_watchdog(&local.state, &peer_url, Duration::from_millis(300))
            .await
            .expect("a steadily-progressing bootstrap must complete, not time out");
    assert_eq!(
        stats.artifacts_applied, 800,
        "the whole dataset must be pulled despite the runtime exceeding many windows"
    );
}

#[tokio::test]
async fn bootstrap_is_abandoned_when_it_stops_making_progress() {
    use axum::{
        extract::Request,
        middleware::{self, Next},
        response::IntoResponse,
    };

    let remote = test_context(|_| {}).await;
    remote
        .state
        .store
        .apply_replicated_inline_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
            100,
        )
        .await
        .expect("remote applies artifact");

    // The peer hangs indefinitely on manifest pages: once the walk reaches
    // manifests the bootstrap makes no further progress.
    async fn hang_manifests(request: Request, next: Next) -> axum::response::Response {
        let path = request.uri().path().to_owned();
        if path == "/_internal/bootstrap/digest" {
            return StatusCode::NOT_FOUND.into_response();
        }
        if path == "/_internal/bootstrap/manifests" {
            sleep(Duration::from_secs(30)).await;
        }
        next.run(request).await
    }
    let peer = router(remote.state.clone()).layer(middleware::from_fn(hang_manifests));
    let (peer_url, _server) = spawn_server(peer).await;

    let local = test_context(|_| {}).await;
    let error =
        bootstrap_from_peer_with_watchdog(&local.state, &peer_url, Duration::from_millis(150))
            .await
            .expect_err("a stalled bootstrap must be abandoned, not hang forever");
    assert!(
        error.contains("made no progress"),
        "unexpected error: {error}"
    );
}

#[tokio::test]
async fn bootstrap_ticks_progress_per_artifact_within_a_slow_page() {
    use axum::{
        extract::Request,
        middleware::{self, Next},
        response::IntoResponse,
    };

    // Exactly one page (limit=256) of segment-backed artifacts, each body
    // fetch delayed. At concurrency 16 the single page takes ~16*40ms to
    // drain — many watchdog windows — with no page boundary in between.
    let remote = test_context(|_| {}).await;
    for i in 0..256 {
        let key = format!("artifact-{i:05}");
        remote
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                &key,
                "application/octet-stream",
                &vec![0_u8; 1024],
            )
            .await
            .expect("remote persists artifact");
    }

    async fn slow_bodies(request: Request, next: Next) -> axum::response::Response {
        let path = request.uri().path().to_owned();
        if path == "/_internal/bootstrap/digest" {
            return StatusCode::NOT_FOUND.into_response();
        }
        if path.starts_with("/_internal/bootstrap/artifacts/") {
            sleep(Duration::from_millis(40)).await;
        }
        next.run(request).await
    }
    let peer = router(remote.state.clone()).layer(middleware::from_fn(slow_bodies));
    let (peer_url, _server) = spawn_server(peer).await;

    // Batching the progress bump to page end (the pre-fix behavior) leaves
    // the counter flat for the whole ~640ms drain and the 200ms watchdog
    // cancels mid-page; per-artifact ticks keep it alive to completion.
    let local = test_context(|_| {}).await;
    let stats =
        bootstrap_from_peer_with_watchdog(&local.state, &peer_url, Duration::from_millis(200))
            .await
            .expect("per-artifact progress must keep a slow single page alive");
    assert_eq!(stats.artifacts_applied, 256);
}

#[tokio::test]
async fn bootstrap_succeeds_when_total_artifacts_exceed_tmp_budget() {
    // A large account whose cached artifacts dwarf the tmp budget must still
    // bootstrap from a single peer: peak tmp staging is bounded by the
    // per-artifact reservation, so the budget is never exhausted regardless
    // of total account size.
    let artifact_bytes = vec![7_u8; 256 * 1024];
    let artifact_count = 24_usize;
    let tmp_budget = (artifact_bytes.len() as u64) * 2;

    let remote = test_context(|_| {}).await;
    for index in 0..artifact_count {
        remote
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                &format!("artifact-{index}"),
                "application/octet-stream",
                &artifact_bytes,
            )
            .await
            .expect("remote artifact should persist");
    }
    let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

    let local = test_context(move |config| {
        config.tmp_dir_max_bytes = tmp_budget;
    })
    .await;
    assert!(
        (artifact_bytes.len() as u64) * (artifact_count as u64) > tmp_budget,
        "test should stage far more than the tmp budget allows at once"
    );

    let stats = bootstrap_from_peer(&local.state, &remote_url, &AtomicU64::new(0))
        .await
        .expect("bootstrap should converge under a fixed tmp budget");
    assert_eq!(stats.artifacts_applied, artifact_count as u64);

    for index in 0..artifact_count {
        let manifest = local
            .state
            .store
            .fetch_artifact(
                ArtifactProducer::Gradle,
                "ios",
                &format!("artifact-{index}"),
            )
            .await
            .expect("artifact fetch should succeed")
            .expect("every bootstrapped artifact should be present");
        assert_eq!(manifest.size, artifact_bytes.len() as u64);
    }

    // The reservation is fully released once bootstrap drains.
    let drained = local
        .state
        .bootstrap_staging_budget
        .reserve(tmp_budget)
        .await;
    drop(drained);
}

#[tokio::test]
async fn concurrent_peer_bootstraps_converge_and_bound_peak_tmp() {
    // Reproduces the production failure mode: many peers bootstrap
    // concurrently into the shared tmp dir while their network fetches are
    // slow, so each holds a partially-written temp file open at the same
    // time. The peer streams every body in small chunks with a delay between
    // them, so absent the reservation all stagers would pass the racy
    // point-in-time capacity check at once and pile far more than the budget
    // into the tmp dir. The reservation bounds how many stage concurrently,
    // so peak tmp usage stays within the budget while every artifact still
    // applies. A watcher samples the on-disk tmp size throughout.
    let peer_count = 8_usize;
    let artifact_len = 256 * 1024_usize;
    let tmp_budget = (artifact_len as u64) * 2;
    let chunk = vec![3_u8; 32 * 1024];
    let chunks_per_artifact = artifact_len / chunk.len();

    let app = Router::new().route(
        "/_internal/bootstrap/artifacts/{artifact_id}",
        get({
            let chunk = chunk.clone();
            move |AxumPath(_artifact_id): AxumPath<String>| {
                let chunk = chunk.clone();
                async move {
                    let stream =
                        futures_util::stream::iter(0..chunks_per_artifact).then(move |_| {
                            let chunk = chunk.clone();
                            async move {
                                sleep(Duration::from_millis(5)).await;
                                Ok::<_, std::io::Error>(chunk)
                            }
                        });
                    axum::body::Body::from_stream(stream)
                }
            }
        }),
    );
    let (remote_url, _server) = spawn_server(app).await;

    let local = test_context(move |config| {
        config.tmp_dir_max_bytes = tmp_budget;
    })
    .await;
    let tmp_dir = local.state.config.tmp_dir.clone();

    let stop = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let peak = std::sync::Arc::new(std::sync::atomic::AtomicU64::new(0));
    let watcher = {
        let tmp_dir = tmp_dir.clone();
        let stop = stop.clone();
        let peak = peak.clone();
        tokio::spawn(async move {
            while !stop.load(std::sync::atomic::Ordering::Relaxed) {
                let staged = crate::utils::directory_size_bytes(&tmp_dir);
                peak.fetch_max(staged, std::sync::atomic::Ordering::Relaxed);
                sleep(Duration::from_millis(1)).await;
            }
        })
    };

    let tasks: Vec<_> = (0..peer_count)
        .map(|index| {
            let manifest = bootstrap_test_manifest(
                ArtifactProducer::Gradle,
                false,
                "ios",
                &format!("artifact-{index}"),
                "application/octet-stream",
                artifact_len as u64,
                100 + index as u64,
            );
            let state = local.state.clone();
            let remote_url = remote_url.clone();
            tokio::spawn(async move {
                bootstrap_artifact_from_peer(&state, &remote_url, &manifest).await
            })
        })
        .collect();

    for task in tasks {
        let outcome = task
            .await
            .expect("bootstrap task should not panic")
            .expect("concurrent bootstrap staging should stay within the budget");
        assert_eq!(outcome, ArtifactApplyOutcome::Applied);
    }

    stop.store(true, std::sync::atomic::Ordering::Relaxed);
    watcher.await.expect("watcher task should finish");

    let observed_peak = peak.load(std::sync::atomic::Ordering::Relaxed);
    assert!(
        observed_peak <= tmp_budget,
        "peak staged tmp bytes {observed_peak} exceeded budget {tmp_budget}"
    );

    for index in 0..peer_count {
        assert!(
            local
                .state
                .store
                .fetch_artifact(
                    ArtifactProducer::Gradle,
                    "ios",
                    &format!("artifact-{index}")
                )
                .await
                .expect("artifact fetch should succeed")
                .is_some(),
            "every concurrently bootstrapped artifact should be present"
        );
    }
}

#[tokio::test]
async fn concurrent_cross_peer_bootstrap_fetches_and_writes_each_artifact_once() {
    // A fresh node bootstraps the SAME artifacts from several peers at once:
    // every peer serves an identical manifest page (same ids and versions)
    // and identical bodies, as the near-fully-overlapping mesh does. The
    // per-artifact fetch gate single-flights each key, so exactly one peer
    // downloads each body and writes it once. Two invariants are asserted
    // together: the segment store holds ~1x the dataset (not peer_count x —
    // the production ENOSPC), and the peers serve each artifact body once
    // total (not once per peer — the redundant WAN transfer). A sleep
    // failpoint between the durable append and the metadata commit holds the
    // gate's owner busy so waiters genuinely contend; without the gate they
    // would all fetch, and without the apply lock they would all write.
    use std::collections::HashMap;
    use std::sync::atomic::{AtomicU64, Ordering};

    use crate::failpoints::{FailpointAction, FailpointName};

    let peer_count = 4_usize;
    let artifact_count = 6_usize;
    let artifact_len = 128 * 1024_usize;
    let dataset_bytes = (artifact_count * artifact_len) as u64;

    let mut manifests = Vec::new();
    let mut bodies = HashMap::new();
    for index in 0..artifact_count {
        let manifest = bootstrap_test_manifest(
            ArtifactProducer::Gradle,
            false,
            "ios",
            &format!("artifact-{index}"),
            "application/octet-stream",
            artifact_len as u64,
            100 + index as u64,
        );
        bodies.insert(
            manifest.artifact_id.clone(),
            vec![index as u8; artifact_len],
        );
        manifests.push(manifest);
    }
    let manifest_page = ManifestPage {
        manifests,
        next_after: None,
    };
    let bodies = std::sync::Arc::new(bodies);
    // Shared across every peer router: counts total artifact-body requests so
    // the test can assert the fetch was single-flighted across peers.
    let body_requests = std::sync::Arc::new(AtomicU64::new(0));

    let mut peer_urls = Vec::new();
    let mut servers = Vec::new();
    for _ in 0..peer_count {
        let manifest_page = manifest_page.clone();
        let bodies = bodies.clone();
        let body_requests = body_requests.clone();
        let app = Router::new()
            .route(
                "/_internal/bootstrap/namespace_tombstones",
                get(|| async {
                    Json(NamespaceTombstonePage {
                        tombstones: Vec::new(),
                        next_after: None,
                    })
                }),
            )
            .route(
                "/_internal/bootstrap/manifests",
                get(move || {
                    let manifest_page = manifest_page.clone();
                    async move { Json(manifest_page) }
                }),
            )
            .route(
                "/_internal/bootstrap/artifacts/{artifact_id}",
                get(move |AxumPath(artifact_id): AxumPath<String>| {
                    let bodies = bodies.clone();
                    let body_requests = body_requests.clone();
                    async move {
                        body_requests.fetch_add(1, Ordering::Relaxed);
                        match bodies.get(&artifact_id) {
                            Some(body) => (StatusCode::OK, body.clone()),
                            None => (StatusCode::NOT_FOUND, Vec::new()),
                        }
                    }
                }),
            );
        let (url, server) = spawn_server(app).await;
        peer_urls.push(url);
        servers.push(server);
    }

    let local = test_context(|_| {}).await;
    local.state.store.failpoints().set_always(
        FailpointName::AfterArtifactBytesDurableBeforeMetadata,
        FailpointAction::Sleep(Duration::from_millis(150)),
    );

    let tasks: Vec<_> = peer_urls
        .iter()
        .map(|peer| {
            let state = local.state.clone();
            let peer = peer.clone();
            tokio::spawn(
                async move { bootstrap_from_peer(&state, &peer, &AtomicU64::new(0)).await },
            )
        })
        .collect();
    for task in tasks {
        task.await
            .expect("bootstrap task should not panic")
            .expect("each concurrent peer bootstrap should converge");
    }

    // Written once: the segment store holds ~1x the dataset, not peer_count x.
    let segments_bytes =
        crate::utils::directory_size_bytes(&local.state.config.data_dir.join("segments"));
    assert!(
        segments_bytes <= dataset_bytes + artifact_len as u64,
        "segment store held {segments_bytes} bytes, expected ~{dataset_bytes} (1x the \
             dataset); cross-peer bootstrap amplified on-disk data"
    );

    // Fetched once: the peers served each body a single time across the whole
    // mesh, not once per peer.
    let observed_requests = body_requests.load(Ordering::Relaxed);
    assert_eq!(
        observed_requests, artifact_count as u64,
        "expected {artifact_count} artifact-body requests (one per key); observed \
             {observed_requests} — the cross-peer fetch was not single-flighted"
    );

    for index in 0..artifact_count {
        assert!(
            local
                .state
                .store
                .fetch_artifact(
                    ArtifactProducer::Gradle,
                    "ios",
                    &format!("artifact-{index}")
                )
                .await
                .expect("artifact fetch should succeed")
                .is_some(),
            "every concurrently bootstrapped artifact should be present"
        );
    }
}

#[tokio::test]
async fn bootstrap_rejects_body_larger_than_reserved() {
    // An inconsistent peer streams a chunked body larger than its manifest
    // advertised (no Content-Length). The staged file is capped at the
    // reservation, so it is rejected instead of overrunning the tmp budget.
    let declared_len = 64 * 1024_u64;
    let chunk = vec![7_u8; declared_len as usize];
    let app = Router::new().route(
        "/_internal/bootstrap/artifacts/{artifact_id}",
        get({
            let chunk = chunk.clone();
            move |AxumPath(_artifact_id): AxumPath<String>| {
                let chunk = chunk.clone();
                async move {
                    let stream = futures_util::stream::iter(0..4).then(move |_| {
                        let chunk = chunk.clone();
                        async move { Ok::<_, std::io::Error>(chunk) }
                    });
                    axum::body::Body::from_stream(stream)
                }
            }
        }),
    );
    let (remote_url, _server) = spawn_server(app).await;

    let local = test_context(|_config| {}).await;
    let manifest = bootstrap_test_manifest(
        ArtifactProducer::Gradle,
        false,
        "ios",
        "oversized",
        "application/octet-stream",
        declared_len,
        100,
    );

    let error = bootstrap_artifact_from_peer(&local.state, &remote_url, &manifest)
        .await
        .expect_err("a body larger than the manifest must be rejected");
    assert!(
        error.contains("exceeded reserved"),
        "expected a reservation-overflow rejection, got: {error}"
    );
    assert!(
        local
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "oversized")
            .await
            .expect("artifact fetch should succeed")
            .is_none(),
        "the rejected artifact must not be persisted"
    );
}
