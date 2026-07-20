
use super::*;
use crate::test_support::test_context;

#[tokio::test]
async fn apply_peers_swaps_dynamic_peers_only_on_change() {
    let ctx = test_context(|_| {}).await;
    let peers = vec!["https://peer-1.test:7443".to_string()];

    apply_peers(&ctx.state, peers.clone());
    assert_eq!(**ctx.state.dynamic_peers.load(), peers);

    let same = ctx.state.dynamic_peers.load_full();
    apply_peers(&ctx.state, peers.clone());
    assert!(std::sync::Arc::ptr_eq(
        &same,
        &ctx.state.dynamic_peers.load_full()
    ));

    apply_peers(&ctx.state, Vec::new());
    assert!(ctx.state.dynamic_peers.load().is_empty());
}

#[tokio::test]
async fn apply_peers_ignores_server_side_ordering() {
    let ctx = test_context(|_| {}).await;

    apply_peers(
        &ctx.state,
        vec!["https://b.test:7443".into(), "https://a.test:7443".into()],
    );
    let stored = ctx.state.dynamic_peers.load_full();

    apply_peers(
        &ctx.state,
        vec!["https://a.test:7443".into(), "https://b.test:7443".into()],
    );
    assert!(std::sync::Arc::ptr_eq(
        &stored,
        &ctx.state.dynamic_peers.load_full()
    ));
}

#[test]
fn responses_tolerate_missing_optional_fields() {
    let heartbeat: MeshHeartbeatResponse =
        serde_json::from_str(r#"{"mesh_member": true}"#).expect("should decode");
    assert!(heartbeat.mesh_member);
    assert!(heartbeat.peers.is_empty());
    assert_eq!(heartbeat.heartbeat_interval_seconds, None);

    let peers: MeshPeersResponse = serde_json::from_str("{}").expect("should decode");
    assert!(peers.peers.is_empty());
    assert_eq!(peers.refresh_interval_seconds, None);
}

#[test]
fn a_response_missing_mesh_member_fails_the_decode_instead_of_defaulting_to_false() {
    assert!(serde_json::from_str::<MeshHeartbeatResponse>("{}").is_err());
}

#[tokio::test]
async fn peer_view_gate_withholds_serving_until_first_fetch() {
    let ctx = test_context(|_| {}).await;
    ctx.state.runtime.require_peer_view();

    ctx.state
        .apply_membership_view(
            std::collections::BTreeSet::new(),
            std::collections::BTreeMap::new(),
            true,
        )
        .await;
    ctx.state.expire_readiness_settle_window().await;
    ctx.state.maybe_mark_serving().await;
    assert!(!ctx.state.runtime.is_serving());

    ctx.state.runtime.mark_peer_view_ready();
    ctx.state.maybe_mark_serving().await;
    assert!(ctx.state.runtime.is_serving());
}

#[tokio::test]
async fn recovery_resets_bootstrap_progress_so_peers_are_repulled() {
    let ctx = test_context(|_| {}).await;
    let peer = "https://peer-1.test:7443".to_string();
    ctx.state
        .apply_membership_view(
            std::collections::BTreeSet::from(["remote".to_string()]),
            std::collections::BTreeMap::from([(peer.clone(), "remote".to_string())]),
            true,
        )
        .await;
    ctx.state
        .note_bootstrap_succeeded(&peer, ctx.state.current_bootstrap_epoch().await)
        .await;
    ctx.state.expire_readiness_settle_window().await;
    ctx.state.maybe_mark_serving().await;
    assert!(ctx.state.runtime.is_serving());
    assert!(ctx.state.peers_needing_bootstrap().await.is_empty());

    ctx.state.reset_bootstrap_progress().await;

    // Readiness implies complete data: the node must leave serving for
    // the whole re-bootstrap window, not just re-pull in the background.
    assert!(!ctx.state.runtime.is_serving());
    assert_eq!(
        ctx.state.peers_needing_bootstrap().await,
        vec![peer.clone()]
    );
    ctx.state.maybe_mark_serving().await;
    assert!(
        !ctx.state.runtime.is_serving(),
        "serving must not resume before a clean pass under the new epoch"
    );

    let epoch = ctx
        .state
        .note_bootstrap_started(&peer)
        .await
        .expect("fresh pass should start");
    ctx.state.note_bootstrap_succeeded(&peer, epoch).await;
    ctx.state.expire_readiness_settle_window().await;
    ctx.state.maybe_mark_serving().await;
    assert!(ctx.state.runtime.is_serving());
}

#[test]
fn recovery_backoff_gates_attempts_and_grows() {
    let mut backoff = RecoveryBackoff::new();
    let start = Instant::now();

    assert!(backoff.should_attempt(start));
    assert!(!backoff.should_attempt(start));
    assert!(!backoff.should_attempt(start + RECOVERY_BACKOFF_INITIAL / 2));
    assert!(backoff.should_attempt(start + RECOVERY_BACKOFF_INITIAL));
    // The wait doubles after each attempt.
    assert!(!backoff.should_attempt(start + RECOVERY_BACKOFF_INITIAL + Duration::from_secs(90)));

    backoff.reset();
    assert!(backoff.should_attempt(start + RECOVERY_BACKOFF_INITIAL + Duration::from_secs(90)));
}
