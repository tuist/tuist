
use tokio::sync::Barrier;

use crate::test_support::test_context;

use super::*;

#[test]
fn readiness_state_advances_generation_and_reconciles_peer_sets() {
    let now = Instant::now();
    let mut readiness = ReadinessState::new(now);

    let initial = readiness.apply_membership(
        BTreeSet::from(["remote-a".to_string(), "remote-b".to_string()]),
        BTreeSet::from([
            "http://peer-a.kura.internal:7443".to_string(),
            "http://peer-b.kura.internal:7443".to_string(),
        ]),
        true,
        now,
    );
    assert_eq!(readiness.generation, 1);
    assert!(initial.initial_discovery_completed);
    assert!(initial.lost_peers.is_empty());
    assert_eq!(initial.known_peer_count, 2);
    assert_eq!(
        initial.discovered_peers,
        vec![
            "http://peer-a.kura.internal:7443".to_string(),
            "http://peer-b.kura.internal:7443".to_string()
        ]
    );

    assert!(readiness.note_bootstrap_started("http://peer-a.kura.internal:7443"));
    readiness.note_bootstrap_succeeded(
        "http://peer-a.kura.internal:7443",
        readiness.bootstrap_epoch,
    );
    assert!(
        readiness
            .bootstrapped_peers
            .contains("http://peer-a.kura.internal:7443")
    );

    let topology_change = readiness.apply_membership(
        BTreeSet::from(["remote-a".to_string(), "remote-c".to_string()]),
        BTreeSet::from([
            "http://peer-a.kura.internal:7443".to_string(),
            "http://peer-c.kura.internal:7443".to_string(),
        ]),
        true,
        now + Duration::from_secs(1),
    );
    assert_eq!(readiness.generation, 2);
    assert_eq!(
        topology_change.discovered_peers,
        vec!["http://peer-c.kura.internal:7443".to_string()]
    );
    assert_eq!(
        topology_change.lost_peers,
        vec!["http://peer-b.kura.internal:7443".to_string()]
    );
    assert!(
        readiness
            .bootstrapped_peers
            .contains("http://peer-a.kura.internal:7443")
    );
    assert!(
        !readiness
            .bootstrapped_peers
            .contains("http://peer-b.kura.internal:7443")
    );
}

#[test]
fn stale_epoch_bootstrap_completion_does_not_count() {
    let now = Instant::now();
    let mut readiness = ReadinessState::new(now);
    let peer = "http://peer-a.kura.internal:7443".to_string();
    readiness.apply_membership(
        BTreeSet::from(["remote".to_string()]),
        BTreeSet::from([peer.clone()]),
        true,
        now,
    );

    assert!(readiness.note_bootstrap_started(&peer));
    // A recovery re-enrollment resets progress while the pass is in
    // flight: the pass may straddle the absence window, so its completion
    // must not mark the peer bootstrapped.
    let stale_epoch = readiness.bootstrap_epoch;
    readiness.reset_bootstrap_progress(now);
    readiness.note_bootstrap_succeeded(&peer, stale_epoch);

    assert_eq!(readiness.peers_needing_bootstrap(), vec![peer.clone()]);

    // A fresh pass under the current epoch counts.
    assert!(readiness.note_bootstrap_started(&peer));
    readiness.note_bootstrap_succeeded(&peer, readiness.bootstrap_epoch);
    assert!(readiness.peers_needing_bootstrap().is_empty());
}

#[test]
fn readiness_state_deduplicates_bootstrap_start_per_peer() {
    let now = Instant::now();
    let mut readiness = ReadinessState::new(now);
    readiness.apply_membership(
        BTreeSet::from(["remote".to_string()]),
        BTreeSet::from(["http://peer.kura.internal:7443".to_string()]),
        true,
        now,
    );

    assert!(readiness.note_bootstrap_started("http://peer.kura.internal:7443"));
    assert!(!readiness.note_bootstrap_started("http://peer.kura.internal:7443"));
    readiness.note_bootstrap_failed("http://peer.kura.internal:7443");
    assert!(readiness.note_bootstrap_started("http://peer.kura.internal:7443"));
}

#[test]
fn readiness_state_keeps_joining_until_discovery_succeeds() {
    let now = Instant::now();
    let mut readiness = ReadinessState::new(now);

    let unobserved = readiness.apply_membership(BTreeSet::new(), BTreeSet::new(), false, now);
    assert!(!unobserved.initial_discovery_completed);
    assert!(!unobserved.generation_changed);
    assert_eq!(readiness.generation, 0);

    let observed = readiness.apply_membership(
        BTreeSet::new(),
        BTreeSet::new(),
        true,
        now + Duration::from_secs(1),
    );
    assert!(observed.initial_discovery_completed);
    assert!(observed.generation_changed);
    assert_eq!(readiness.generation, 1);
}

#[test]
fn peers_needing_bootstrap_excludes_completed_and_inflight_entries() {
    let now = Instant::now();
    let mut readiness = ReadinessState::new(now);
    let peer_a = "http://peer-a.kura.internal:7443".to_string();
    let peer_b = "http://peer-b.kura.internal:7443".to_string();
    let peer_c = "http://peer-c.kura.internal:7443".to_string();
    readiness.apply_membership(
        BTreeSet::from(["a".to_string(), "b".to_string(), "c".to_string()]),
        BTreeSet::from([peer_a.clone(), peer_b.clone(), peer_c.clone()]),
        true,
        now,
    );

    readiness.note_bootstrap_succeeded(&peer_a, readiness.bootstrap_epoch);
    assert!(readiness.note_bootstrap_started(&peer_b));

    let pending = readiness.peers_needing_bootstrap();
    assert_eq!(pending, vec![peer_c.clone()]);

    readiness.note_bootstrap_failed(&peer_b);
    let mut after_failure = readiness.peers_needing_bootstrap();
    after_failure.sort();
    assert_eq!(after_failure, vec![peer_b, peer_c]);
}

#[tokio::test]
async fn app_state_serializes_concurrent_bootstrap_start_requests() {
    let context = test_context(|_| {}).await;
    let peer = "http://peer.kura.internal:7443".to_string();
    context
        .state
        .apply_membership_view(
            BTreeSet::from(["remote".to_string()]),
            BTreeMap::from([(peer.clone(), "remote".to_string())]),
            true,
        )
        .await;

    let barrier = Arc::new(Barrier::new(3));
    let state_one = context.state.clone();
    let barrier_one = barrier.clone();
    let peer_one = peer.clone();
    let first = tokio::spawn(async move {
        barrier_one.wait().await;
        state_one.note_bootstrap_started(&peer_one).await
    });
    let state_two = context.state.clone();
    let barrier_two = barrier.clone();
    let second = tokio::spawn(async move {
        barrier_two.wait().await;
        state_two.note_bootstrap_started(&peer).await
    });

    barrier.wait().await;
    let first_started = first.await.expect("first bootstrap task should finish");
    let second_started = second.await.expect("second bootstrap task should finish");
    assert_eq!(
        [first_started, second_started]
            .into_iter()
            .filter(|started| started.is_some())
            .count(),
        1
    );
}

#[tokio::test]
async fn app_state_returns_to_joining_when_membership_generation_advances() {
    let context = test_context(|_| {}).await;
    let peer_a = "http://peer-a.kura.internal:7443".to_string();
    let peer_b = "http://peer-b.kura.internal:7443".to_string();
    context
        .state
        .apply_membership_view(
            BTreeSet::from(["remote-a".to_string()]),
            BTreeMap::from([(peer_a.clone(), "remote-a".to_string())]),
            true,
        )
        .await;
    context
        .state
        .note_bootstrap_succeeded(&peer_a, context.state.current_bootstrap_epoch().await)
        .await;
    context.state.expire_readiness_settle_window().await;
    context.state.maybe_mark_serving().await;

    let serving = context.state.readiness_report().await;
    assert!(serving.ready);
    assert_eq!(serving.state, TrafficState::Serving);

    context
        .state
        .apply_membership_view(
            BTreeSet::from(["remote-a".to_string(), "remote-b".to_string()]),
            BTreeMap::from([
                (peer_a.clone(), "remote-a".to_string()),
                (peer_b.clone(), "remote-b".to_string()),
            ]),
            true,
        )
        .await;

    let joining = context.state.readiness_report().await;
    assert!(!joining.ready);
    assert_eq!(joining.state, TrafficState::Joining);
    assert!(
        joining
            .reasons
            .iter()
            .any(|reason| reason.contains("discovery settling"))
    );
}
