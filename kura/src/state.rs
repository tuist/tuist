use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

use reqwest::Client;
use tokio::{
    sync::{Mutex, Notify},
    time::{Duration, Instant},
};

use crate::{
    analytics::Analytics,
    config::Config,
    extension::SharedExtension,
    io::IoController,
    memory::MemoryController,
    metrics::Metrics,
    runtime::{DataDirLock, InflightGuard, RuntimeState, TrafficState},
    store::Store,
};

const READINESS_SETTLE_WINDOW: Duration = Duration::from_secs(5);

pub struct AppState {
    pub config: Config,
    pub _data_dir_lock: DataDirLock,
    pub store: Store,
    pub io: IoController,
    pub memory: MemoryController,
    pub metrics: Metrics,
    pub runtime: Arc<RuntimeState>,
    pub extension: Option<SharedExtension>,
    pub analytics: Option<Analytics>,
    pub client: Client,
    pub notify: Notify,
    pub readiness: Mutex<ReadinessState>,
}

pub type SharedState = Arc<AppState>;

#[derive(Debug, PartialEq, Eq)]
pub struct ReadinessReport {
    pub generation: u64,
    pub ready: bool,
    pub state: TrafficState,
    pub reasons: Vec<String>,
    pub draining: bool,
    pub writer_lock_owned: bool,
    pub initial_discovery_completed: bool,
    pub known_peers: Vec<String>,
    pub bootstrapped_peers: Vec<String>,
    pub bootstrap_inflight_peers: Vec<String>,
    pub http_inflight: usize,
    pub grpc_inflight: usize,
}

#[derive(Debug, PartialEq, Eq)]
pub struct RolloutStatusReport {
    pub generation: u64,
    pub ready: bool,
    pub state: TrafficState,
    pub ring_members: usize,
    pub initial_discovery_completed: bool,
    pub writer_lock_owned: bool,
    pub bootstrap_known_peers: usize,
    pub bootstrap_completed_peers: usize,
    pub bootstrap_inflight_peers: usize,
    pub http_inflight: usize,
    pub grpc_inflight: usize,
    pub outbox_messages: u64,
    pub memory_pressure_state: i64,
    pub fd_timeout_count: u64,
}

#[derive(Debug, PartialEq, Eq)]
pub struct ClusterStatusReport {
    pub generation: u64,
    pub members: Vec<String>,
    pub connected_nodes: Vec<String>,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub(crate) struct MembershipUpdate {
    pub discovered_peers: Vec<String>,
    pub lost_peers: Vec<String>,
    pub known_peer_count: usize,
    pub initial_discovery_completed: bool,
    pub generation_changed: bool,
}

#[derive(Debug)]
pub(crate) struct ReadinessState {
    generation: u64,
    initial_discovery_completed: bool,
    settle_until: Instant,
    members: BTreeSet<String>,
    known_peers: BTreeSet<String>,
    bootstrapped_peers: BTreeSet<String>,
    bootstrap_inflight_peers: BTreeSet<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ReadinessSnapshot {
    generation: u64,
    initial_discovery_completed: bool,
    readiness_settled: bool,
    members: Vec<String>,
    known_peers: Vec<String>,
    bootstrapped_peers: Vec<String>,
    bootstrap_inflight_peers: Vec<String>,
}

impl ReadinessState {
    pub(crate) fn new(now: Instant) -> Self {
        Self {
            generation: 0,
            initial_discovery_completed: false,
            settle_until: now,
            members: BTreeSet::new(),
            known_peers: BTreeSet::new(),
            bootstrapped_peers: BTreeSet::new(),
            bootstrap_inflight_peers: BTreeSet::new(),
        }
    }

    fn apply_membership(
        &mut self,
        members: BTreeSet<String>,
        known_peers: BTreeSet<String>,
        discovery_observed: bool,
        now: Instant,
    ) -> MembershipUpdate {
        let discovered_peers = known_peers
            .difference(&self.known_peers)
            .cloned()
            .collect::<Vec<_>>();
        let lost_peers = self
            .known_peers
            .difference(&known_peers)
            .cloned()
            .collect::<Vec<_>>();
        let topology_changed = !discovered_peers.is_empty() || !lost_peers.is_empty();
        let generation_changed;
        if !self.initial_discovery_completed {
            if discovery_observed {
                self.initial_discovery_completed = true;
                self.generation += 1;
                self.settle_until = now + READINESS_SETTLE_WINDOW;
                generation_changed = true;
            } else {
                generation_changed = false;
            }
        } else if topology_changed {
            self.generation += 1;
            self.settle_until = now + READINESS_SETTLE_WINDOW;
            generation_changed = true;
        } else {
            generation_changed = false;
        }

        self.members = members;
        self.known_peers = known_peers;
        self.bootstrapped_peers
            .retain(|peer| self.known_peers.contains(peer));
        self.bootstrap_inflight_peers
            .retain(|peer| self.known_peers.contains(peer));

        MembershipUpdate {
            discovered_peers,
            lost_peers,
            known_peer_count: self.known_peers.len(),
            initial_discovery_completed: self.initial_discovery_completed,
            generation_changed,
        }
    }

    fn note_bootstrap_started(&mut self, peer: &str) -> bool {
        if !self.known_peers.contains(peer)
            || self.bootstrapped_peers.contains(peer)
            || self.bootstrap_inflight_peers.contains(peer)
        {
            return false;
        }
        self.bootstrap_inflight_peers.insert(peer.to_string());
        true
    }

    fn note_bootstrap_succeeded(&mut self, peer: &str) {
        self.bootstrap_inflight_peers.remove(peer);
        if self.known_peers.contains(peer) {
            self.bootstrapped_peers.insert(peer.to_string());
        }
    }

    fn note_bootstrap_failed(&mut self, peer: &str) {
        self.bootstrap_inflight_peers.remove(peer);
    }

    fn peers_needing_bootstrap(&self) -> Vec<String> {
        self.known_peers
            .iter()
            .filter(|peer| {
                !self.bootstrapped_peers.contains(*peer)
                    && !self.bootstrap_inflight_peers.contains(*peer)
            })
            .cloned()
            .collect()
    }

    fn snapshot(&self, now: Instant) -> ReadinessSnapshot {
        ReadinessSnapshot {
            generation: self.generation,
            initial_discovery_completed: self.initial_discovery_completed,
            readiness_settled: now >= self.settle_until,
            members: self.members.iter().cloned().collect(),
            known_peers: self.known_peers.iter().cloned().collect(),
            bootstrapped_peers: self.bootstrapped_peers.iter().cloned().collect(),
            bootstrap_inflight_peers: self.bootstrap_inflight_peers.iter().cloned().collect(),
        }
    }
}

impl AppState {
    pub fn start_http_request(&self) -> InflightGuard {
        self.runtime.start_http_request(&self.metrics)
    }

    pub fn start_grpc_request(&self) -> InflightGuard {
        self.runtime.start_grpc_request(&self.metrics)
    }

    pub fn enter_draining(&self) -> bool {
        self.runtime.request_drain()
    }

    #[cfg(test)]
    pub async fn expire_readiness_settle_window(&self) {
        self.readiness.lock().await.settle_until = Instant::now();
    }

    pub async fn apply_membership_view(
        &self,
        members: BTreeSet<String>,
        peer_nodes: BTreeMap<String, String>,
        discovery_observed: bool,
    ) -> MembershipUpdate {
        let known_peers = peer_nodes.keys().cloned().collect::<BTreeSet<_>>();

        {
            let mut readiness = self.readiness.lock().await;
            let membership_update = readiness.apply_membership(
                members,
                known_peers,
                discovery_observed,
                Instant::now(),
            );
            if membership_update.generation_changed {
                self.runtime.clear_serving();
            }
            membership_update
        }
    }

    pub async fn peers_needing_bootstrap(&self) -> Vec<String> {
        self.readiness.lock().await.peers_needing_bootstrap()
    }

    pub async fn note_bootstrap_started(&self, peer: &str) -> bool {
        self.readiness.lock().await.note_bootstrap_started(peer)
    }

    pub async fn note_bootstrap_succeeded(&self, peer: &str) {
        self.readiness.lock().await.note_bootstrap_succeeded(peer);
    }

    pub async fn note_bootstrap_failed(&self, peer: &str) {
        self.readiness.lock().await.note_bootstrap_failed(peer);
    }

    async fn readiness_snapshot(&self) -> ReadinessSnapshot {
        self.readiness.lock().await.snapshot(Instant::now())
    }

    pub async fn cluster_status_report(&self) -> ClusterStatusReport {
        let snapshot = self.readiness_snapshot().await;
        ClusterStatusReport {
            generation: snapshot.generation,
            members: snapshot.members,
            connected_nodes: snapshot.known_peers,
        }
    }

    pub async fn replication_targets(&self) -> Vec<String> {
        let snapshot = self.readiness_snapshot().await;
        let mut targets = self.config.peers.iter().cloned().collect::<BTreeSet<_>>();
        targets.extend(snapshot.known_peers);
        targets.remove(&self.config.node_url);
        targets.into_iter().collect()
    }

    pub async fn maybe_mark_serving(&self) {
        if self.runtime.is_draining() || self.runtime.is_serving() {
            return;
        }
        let snapshot = self.readiness_snapshot().await;
        if !snapshot.initial_discovery_completed || !snapshot.readiness_settled {
            return;
        }

        let bootstrapped = snapshot
            .bootstrapped_peers
            .iter()
            .cloned()
            .collect::<BTreeSet<_>>();
        let bootstrap_inflight = snapshot
            .bootstrap_inflight_peers
            .iter()
            .cloned()
            .collect::<BTreeSet<_>>();
        if snapshot
            .known_peers
            .iter()
            .any(|peer| bootstrap_inflight.contains(peer))
        {
            return;
        }
        if snapshot
            .known_peers
            .iter()
            .all(|peer| bootstrapped.contains(peer))
        {
            self.runtime.mark_serving();
        }
    }

    pub async fn readiness_report(&self) -> ReadinessReport {
        self.maybe_mark_serving().await;

        let snapshot = self.readiness_snapshot().await;
        let draining = self.runtime.is_draining();
        let state = self.runtime.traffic_state();
        let writer_lock_owned = self.runtime.writer_lock_owned();
        let mut reasons = Vec::new();
        if !writer_lock_owned {
            reasons.push("writer lock not held".to_string());
        }
        if draining {
            reasons.push("draining".to_string());
        }
        if !snapshot.initial_discovery_completed {
            reasons.push("initial discovery incomplete".to_string());
        }
        if !self.runtime.is_serving()
            && snapshot.initial_discovery_completed
            && !snapshot.readiness_settled
        {
            reasons.push("discovery settling".to_string());
        }
        if !self.runtime.is_serving() && !snapshot.bootstrap_inflight_peers.is_empty() {
            reasons.push("bootstrap in progress".to_string());
        }
        if !self.runtime.is_serving() {
            let bootstrapped = snapshot
                .bootstrapped_peers
                .iter()
                .cloned()
                .collect::<BTreeSet<_>>();
            let missing = snapshot
                .known_peers
                .iter()
                .filter(|peer| !bootstrapped.contains(*peer))
                .cloned()
                .collect::<Vec<_>>();
            if !missing.is_empty() {
                reasons.push(format!("bootstrap incomplete for {}", missing.join(", ")));
            }
        }

        let ready = writer_lock_owned && !draining && self.runtime.is_serving();
        ReadinessReport {
            generation: snapshot.generation,
            ready,
            state,
            reasons,
            draining,
            writer_lock_owned,
            initial_discovery_completed: snapshot.initial_discovery_completed,
            known_peers: snapshot.known_peers,
            bootstrapped_peers: snapshot.bootstrapped_peers,
            bootstrap_inflight_peers: snapshot.bootstrap_inflight_peers,
            http_inflight: self.runtime.http_inflight(),
            grpc_inflight: self.runtime.grpc_inflight(),
        }
    }

    pub async fn rollout_status_report(&self) -> RolloutStatusReport {
        self.maybe_mark_serving().await;

        let snapshot = self.readiness_snapshot().await;
        let draining = self.runtime.is_draining();
        let writer_lock_owned = self.runtime.writer_lock_owned();
        let ready = writer_lock_owned && !draining && self.runtime.is_serving();
        let metrics = self.metrics.rollout_metrics_snapshot();

        RolloutStatusReport {
            generation: snapshot.generation,
            ready,
            state: self.runtime.traffic_state(),
            ring_members: snapshot.known_peers.len() + 1,
            initial_discovery_completed: snapshot.initial_discovery_completed,
            writer_lock_owned,
            bootstrap_known_peers: snapshot.known_peers.len(),
            bootstrap_completed_peers: snapshot.bootstrapped_peers.len(),
            bootstrap_inflight_peers: snapshot.bootstrap_inflight_peers.len(),
            http_inflight: self.runtime.http_inflight(),
            grpc_inflight: self.runtime.grpc_inflight(),
            outbox_messages: metrics.outbox_messages,
            memory_pressure_state: self.memory.pressure().as_i64(),
            fd_timeout_count: metrics.fd_timeout_count,
        }
    }

    pub async fn sync_runtime_metrics(&self) {
        let report = self.readiness_report().await;
        self.metrics.update_runtime_state(
            report.state.as_i64(),
            report.ready,
            report.draining,
            report.initial_discovery_completed,
            report.writer_lock_owned,
        );
        self.metrics.update_bootstrap_peers(
            report.known_peers.len(),
            report.bootstrapped_peers.len(),
            report.bootstrap_inflight_peers.len(),
        );
    }
}

#[cfg(test)]
mod tests {
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
        readiness.note_bootstrap_succeeded("http://peer-a.kura.internal:7443");
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

        let unobserved = readiness.apply_membership(
            BTreeSet::new(),
            BTreeSet::new(),
            false,
            now,
        );
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

        readiness.note_bootstrap_succeeded(&peer_a);
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
                .filter(|started| *started)
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
        context.state.note_bootstrap_succeeded(&peer_a).await;
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
}
