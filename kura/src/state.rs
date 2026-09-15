use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

use arc_swap::ArcSwap;
use axum_server::tls_rustls::RustlsConfig;
use reqwest::Client;
use tokio::{
    sync::Mutex,
    time::{Duration, Instant},
};

use tracing::info;

use crate::{
    analytics::Analytics,
    auth::SharedAuth,
    backfill::claims::ClaimSet,
    bandwidth::BandwidthLimiter,
    bazel_test_artifacts::BazelTestArtifactDelivery,
    config::Config,
    io::IoController,
    memory::MemoryController,
    metrics::Metrics,
    peer_tls::PeerClientFactory,
    reapi::SnapshotCache,
    runtime::{DataDirLock, HttpTrafficClass, InflightGuard, RuntimeState, TrafficState},
    store::Store,
    usage::Usage,
    utils::TmpBudget,
};

const READINESS_SETTLE_WINDOW: Duration = Duration::from_secs(5);

pub struct AppState {
    pub config: Config,
    pub _data_dir_lock: DataDirLock,
    pub store: Arc<Store>,
    pub io: IoController,
    pub memory: MemoryController,
    pub snapshot_cache: Arc<SnapshotCache>,
    pub metrics: Metrics,
    pub runtime: Arc<RuntimeState>,
    pub auth: Option<SharedAuth>,
    pub analytics: Option<Analytics>,
    /// Bounded, post-write delivery of Bazel's conventional test artifacts.
    /// This is separate from aggregate cache analytics because it may read one
    /// small blob under the background memory budget.
    pub bazel_test_artifacts: Option<BazelTestArtifactDelivery>,
    pub usage: Option<Usage>,
    // Outbound peer client, behind an atomic swap so cert rotation can replace
    // it in place. Read it with `state.client()`.
    pub client: ArcSwap<Client>,
    pub peer_client_factory: PeerClientFactory,
    // The inbound internal mTLS server config, retained so cert rotation can
    // hot-reload the leaf via `reload_from_config`. `None` when peer TLS is off.
    pub internal_tls: Option<RustlsConfig>,
    // The control-plane-authoritative volatile peer view, refreshed at mesh
    // heartbeat / peers-sync cadence and merged into the discovery targets
    // on top of the static (platform-stable) `config.peers`.
    pub dynamic_peers: ArcSwap<Vec<String>>,
    pub replication_bandwidth_limiter: Option<Arc<BandwidthLimiter>>,
    pub readiness: Mutex<ReadinessState>,
    /// Process-wide byte budget shared by every transient disk writer.
    pub tmp_staging_budget: Arc<TmpBudget>,
    /// Byte budget for peer catch-up staging: the spool a backfill pass writes
    /// bodies through, and the reservation the serving side charges a bodies
    /// response against. Separate from `tmp_staging_budget` so catch-up traffic
    /// cannot starve in-flight client uploads (or the reverse).
    pub peer_staging_budget: Arc<TmpBudget>,
    /// Serving-side per-peer-identity concurrency gate for the backfill bodies
    /// endpoint (see [`BackfillBodiesPeerSlots`]).
    pub backfill_bodies_peer_slots: Arc<BackfillBodiesPeerSlots>,
    /// The node-wide single-flight set every catch-up pass registers with,
    /// so the replica and region links never fetch one record twice.
    pub backfill_claims: Arc<ClaimSet>,
    /// What every reachable peer's `/_internal/status` last said, refreshed
    /// each membership tick; the role rule's input.
    pub peer_views: ArcSwap<Vec<crate::sync::roles::PeerView>>,
    /// Roles the control plane published beside the peer list.
    pub published_roles: ArcSwap<Vec<crate::sync::roles::PublishedRole>>,
    /// The pull links (design §3, §4), driven by the membership loop.
    pub sync: Arc<crate::sync::coordinator::SyncCoordinator>,
}

/// Serving-side concurrency gate for `POST /_internal/backfill/bodies`
/// (design §11.1): a per-identity slot count and a node-wide aggregate.
///
/// The requester side already limits itself to one in-flight bodies request
/// per peer, but that bound is politeness: self-hosted peers hold account-CA
/// client certificates on customer infrastructure, and a hostile or buggy
/// peer must not be able to pin the shared tmp budget and bandwidth limiter
/// with parallel bulk requests. The aggregate covers the case the per-peer
/// count cannot: many well-behaved peers converging on one gateway. Identities
/// come from the internal mTLS listener's verified client certificate
/// ([`crate::peer_tls::InternalPeerIdentity`]).
#[derive(Debug)]
pub struct BackfillBodiesPeerSlots {
    active: std::sync::Mutex<BTreeMap<Arc<str>, u64>>,
    slots_per_peer: u64,
    /// The aggregate in force; derived from the membership view unless
    /// `pinned`.
    max_inflight: std::sync::atomic::AtomicU64,
    pinned: bool,
}

/// Which limit refused a bodies request, so the metric can tell "this peer is
/// greedy" from "this node is saturated".
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BackfillBodiesSlotRejection {
    PeerBusy,
    NodeBusy,
}

impl BackfillBodiesPeerSlots {
    /// `max_inflight` pins the aggregate; `None` derives it from the
    /// membership view through [`Self::observe_peer_count`], starting at the
    /// floor until the first view arrives.
    pub fn new(slots_per_peer: u64, max_inflight: Option<u64>) -> Self {
        Self {
            active: std::sync::Mutex::new(BTreeMap::new()),
            slots_per_peer: slots_per_peer.max(1),
            max_inflight: std::sync::atomic::AtomicU64::new(
                max_inflight
                    .unwrap_or(crate::constants::SYNC_PEER_SERVING_MIN_INFLIGHT)
                    .max(1),
            ),
            pinned: max_inflight.is_some(),
        }
    }

    /// Re-derives the aggregate from the number of peers in the membership
    /// view: `max(floor, peers × slots per peer)`, so every counted peer can
    /// hold its slots and the floor covers the ones the view does not count.
    pub fn observe_peer_count(&self, peers: usize) {
        if self.pinned {
            return;
        }
        let derived = (peers as u64)
            .saturating_mul(self.slots_per_peer)
            .max(crate::constants::SYNC_PEER_SERVING_MIN_INFLIGHT);
        self.max_inflight
            .store(derived, std::sync::atomic::Ordering::Relaxed);
    }

    pub fn max_inflight(&self) -> u64 {
        self.max_inflight.load(std::sync::atomic::Ordering::Relaxed)
    }

    /// Claims a slot for the identity, or names the limit that refused it.
    /// The returned guard must live for the whole request, response streaming
    /// included.
    pub fn try_acquire(
        self: &Arc<Self>,
        identity: Arc<str>,
    ) -> Result<BackfillBodiesPeerSlot, BackfillBodiesSlotRejection> {
        let mut active = self.active.lock().expect("backfill peer slots lock");
        let held = active.get(&identity).copied().unwrap_or(0);
        if held >= self.slots_per_peer {
            return Err(BackfillBodiesSlotRejection::PeerBusy);
        }
        if active.values().sum::<u64>() >= self.max_inflight() {
            return Err(BackfillBodiesSlotRejection::NodeBusy);
        }
        active.insert(identity.clone(), held + 1);
        drop(active);
        Ok(BackfillBodiesPeerSlot {
            slots: self.clone(),
            identity,
        })
    }
}

#[derive(Debug)]
pub struct BackfillBodiesPeerSlot {
    slots: Arc<BackfillBodiesPeerSlots>,
    identity: Arc<str>,
}

impl Drop for BackfillBodiesPeerSlot {
    fn drop(&mut self) {
        let mut active = self.slots.active.lock().expect("backfill peer slots lock");
        if let Some(held) = active.get_mut(&self.identity) {
            *held -= 1;
            if *held == 0 {
                active.remove(&self.identity);
            }
        }
    }
}

impl AppState {
    /// The current outbound peer HTTP client (picks up rotated certs).
    pub fn client(&self) -> arc_swap::Guard<Arc<Client>> {
        self.client.load()
    }
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
    pub http_inflight: usize,
    pub grpc_inflight: usize,
    pub memory_pressure_state: i64,
    pub fd_timeout_count: u64,
    pub peer_connection_failure_count: u64,
    pub ring_fingerprint: String,
    pub backfill: BackfillRolloutStatus,
}

/// The catch-up gate contract `/status/rollout` consumers (gate.sh, the
/// kura-controller's evacuation check) read: pending | complete | degraded.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CatchUpMode {
    /// A link readiness waits on is still bootstrapping.
    Pending,
    /// Every gating link settled with its bootstrap done.
    Complete,
    /// Every gating link settled, but at least one spent its bootstrap
    /// budget and is serving cold while it retries.
    Degraded,
}

impl CatchUpMode {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Complete => "complete",
            Self::Degraded => "degraded",
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub struct BackfillRolloutStatus {
    pub initial_cycle: CatchUpMode,
    /// Links still bootstrapping.
    pub backfilling_peers: usize,
    /// Links that spent their bootstrap budget on real failures.
    pub budget_exhausted_real: usize,
    /// Links whose peer predates pull: settled cold, never degraded.
    pub budget_exhausted_capability: usize,
    pub ring_fullness_percent: u64,
}

#[derive(Debug, PartialEq, Eq)]
pub struct ClusterStatusReport {
    pub generation: u64,
    pub peer_regions: Vec<String>,
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
    // Every peer ever seen through discovery only (not in the static or
    // dynamic peer config): in-cluster siblings and cross-region pods. Outbox
    // pruning never drops their messages — the re-join backfill reaches back
    // only to the backfill window, so dropping would be silent
    // under-replication for anything older. Monotone and in-memory:
    // bounded by the peers a process ever meets, reset by restart.
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ReadinessSnapshot {
    generation: u64,
    initial_discovery_completed: bool,
    readiness_settled: bool,
    members: Vec<String>,
    known_peers: Vec<String>,
}

impl ReadinessState {
    pub(crate) fn new(now: Instant) -> Self {
        Self {
            generation: 0,
            initial_discovery_completed: false,
            settle_until: now,
            members: BTreeSet::new(),
            known_peers: BTreeSet::new(),
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

        MembershipUpdate {
            discovered_peers,
            lost_peers,
            known_peer_count: self.known_peers.len(),
            initial_discovery_completed: self.initial_discovery_completed,
            generation_changed,
        }
    }

    fn snapshot(&self, now: Instant) -> ReadinessSnapshot {
        ReadinessSnapshot {
            generation: self.generation,
            initial_discovery_completed: self.initial_discovery_completed,
            readiness_settled: now >= self.settle_until,
            members: self.members.iter().cloned().collect(),
            known_peers: self.known_peers.iter().cloned().collect(),
        }
    }
}

impl AppState {
    pub fn start_http_request(&self, traffic_class: HttpTrafficClass) -> InflightGuard {
        self.runtime
            .start_http_request(&self.metrics, traffic_class)
    }

    pub fn start_grpc_request(&self) -> InflightGuard {
        self.runtime.start_grpc_request(&self.metrics)
    }

    pub fn enter_draining(&self) -> bool {
        let entered = self.runtime.request_drain();
        if entered {
            // Wake every long-poll so the sibling reads the tail now and
            // reports its cursor for the drain gate (design §3.5).
            self.store.sync_feed().notify_commit();
        }
        entered
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

        let membership_update = {
            let mut readiness = self.readiness.lock().await;
            readiness.apply_membership(members, known_peers, discovery_observed, Instant::now())
        };
        // Lost peers are routine on rolling deploys and scale-downs, so this
        // logs at info and the
        // kura_membership_peer_changes_total{change="lost"} counter carries the
        // alerting signal.
        if !membership_update.lost_peers.is_empty() {
            info!(
                "membership changed: lost peers {:?} (discovered {:?})",
                membership_update.lost_peers, membership_update.discovered_peers
            );
        } else if !membership_update.discovered_peers.is_empty() {
            info!(
                "membership changed: discovered peers {:?}",
                membership_update.discovered_peers
            );
        }
        self.metrics
            .record_membership_peer_changes("discovered", membership_update.discovered_peers.len());
        self.metrics
            .record_membership_peer_changes("lost", membership_update.lost_peers.len());
        membership_update
    }

    async fn readiness_snapshot(&self) -> ReadinessSnapshot {
        self.readiness.lock().await.snapshot(Instant::now())
    }

    pub async fn cluster_status_report(&self) -> ClusterStatusReport {
        let snapshot = self.readiness_snapshot().await;
        ClusterStatusReport {
            generation: snapshot.generation,
            peer_regions: snapshot.members,
            connected_nodes: snapshot.known_peers,
        }
    }

    /// Stores what the membership loop saw: the role rule's input.
    pub fn apply_peer_views(&self, views: Vec<crate::sync::roles::PeerView>) {
        self.backfill_bodies_peer_slots
            .observe_peer_count(views.len());
        self.peer_views.store(Arc::new(views));
    }

    /// Segment count as a percentage of the ring's desired total, the ring
    /// term of the backfill readiness gate.
    pub(crate) fn ring_fullness_percent(&self) -> u64 {
        let inputs = self.store.backfill_capacity_inputs();
        if inputs.ring_total_segments == 0 {
            return 100;
        }
        (inputs.segment_count as u64).saturating_mul(100) / inputs.ring_total_segments as u64
    }

    pub async fn maybe_mark_serving(&self) {
        if self.runtime.is_draining() || self.runtime.is_serving() {
            return;
        }
        if self.runtime.peer_view_pending() {
            return;
        }
        let snapshot = self.readiness_snapshot().await;
        if !snapshot.initial_discovery_completed || !snapshot.readiness_settled {
            return;
        }

        // R8: past the discovery gates above, the node is ready when its ring
        // is at least the configured percent full OR its pull links settled
        // (design §3.6): the sibling bootstrap, or for a region of one the
        // initial region passes. No links (zero peers) settles immediately,
        // and a link that spent its bootstrap budget settles too
        // (ready-but-cold is intended; background retries continue,
        // metered). Serving then LATCHES for the process lifetime: this
        // function only runs while not serving, and no catch-up path clears
        // the flag — only the orthogonal /ready inputs (writer lock,
        // draining) can take the node out of rotation.
        let settled = self.sync.bootstrap_settled();
        if settled || self.ring_fullness_percent() >= self.config.backfill_ready_ring_percent {
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
        if self.runtime.peer_view_pending() {
            reasons.push("awaiting control-plane peer view".to_string());
        }
        if !self.runtime.is_serving()
            && snapshot.initial_discovery_completed
            && !snapshot.readiness_settled
        {
            reasons.push("discovery settling".to_string());
        }
        if !self.runtime.is_serving() && !self.sync.bootstrap_settled() {
            let fullness = self.ring_fullness_percent();
            reasons.push(format!(
                "replica bootstrap in progress (ring {fullness}% < {}%)",
                self.config.backfill_ready_ring_percent
            ));
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

        let mut ring: Vec<String> = snapshot.known_peers.clone();
        ring.push(self.config.node_url.clone());
        ring.sort();
        let backfill = self.catch_up_status();

        RolloutStatusReport {
            generation: snapshot.generation,
            ready,
            state: self.runtime.traffic_state(),
            ring_members: ring.len(),
            ring_fingerprint: ring_fingerprint(&ring),
            initial_discovery_completed: snapshot.initial_discovery_completed,
            writer_lock_owned,
            http_inflight: self.runtime.http_inflight(),
            grpc_inflight: self.runtime.grpc_inflight(),
            memory_pressure_state: self.memory.pressure().as_i64(),
            fd_timeout_count: metrics.fd_timeout_count,
            peer_connection_failure_count: metrics.peer_connection_failure_count,
            backfill,
        }
    }

    /// The pull links' bootstrap state in the shape the rollout gate reads.
    pub fn catch_up_status(&self) -> BackfillRolloutStatus {
        let catch_up = self.sync.catch_up();
        let initial_cycle = if !catch_up.settled() {
            CatchUpMode::Pending
        } else if catch_up.abandoned > 0 {
            CatchUpMode::Degraded
        } else {
            CatchUpMode::Complete
        };
        BackfillRolloutStatus {
            initial_cycle,
            backfilling_peers: catch_up.in_progress,
            budget_exhausted_real: catch_up.abandoned,
            budget_exhausted_capability: catch_up.unsupported,
            ring_fullness_percent: self.ring_fullness_percent(),
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
        self.metrics.update_membership_generation(report.generation);
        self.metrics
            .set_backfill_ring_fullness_percent(self.ring_fullness_percent());
        self.metrics.update_replication_bandwidth_limits(
            self.config.replication_bandwidth_limit_bytes_per_second,
            self.replication_bandwidth_limiter
                .as_ref()
                .map_or(0, |limiter| limiter.effective_bytes_per_second()),
            self.config.replication_public_latency_target_ms,
        );
    }
}

/// Stable digest of the sorted ring member identities. Two pods can report
/// equal ring sizes while seeing different peer subsets, so the controller's
/// cross-pod consistency check compares fingerprints, not counts.
pub fn ring_fingerprint(sorted_members: &[String]) -> String {
    use sha2::{Digest, Sha256};

    let mut hasher = Sha256::new();
    for member in sorted_members {
        hasher.update(member.as_bytes());
        hasher.update([0u8]);
    }
    let digest = hasher.finalize();
    hex::encode(&digest[..8])
}

#[cfg(test)]
mod tests {
    use crate::test_support::test_context;

    use super::*;

    #[test]
    fn ring_fingerprint_distinguishes_equal_sized_rings() {
        let ring_a = vec!["https://a:7443".to_string(), "https://b:7443".to_string()];
        let ring_b = vec!["https://a:7443".to_string(), "https://c:7443".to_string()];

        assert_eq!(ring_fingerprint(&ring_a), ring_fingerprint(&ring_a));
        assert_ne!(ring_fingerprint(&ring_a), ring_fingerprint(&ring_b));
        assert_eq!(ring_fingerprint(&ring_a).len(), 16);
    }

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

    /// The membership pass is what re-derives the outbox cap: the store
    /// cannot see the peer set, and the cap has to count every target a write
    /// would enqueue for, so it is read from `replication_targets` rather
    /// than from the discovered set alone.
    #[tokio::test]
    async fn app_state_keeps_serving_when_membership_generation_advances() {
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

        let still_serving = context.state.readiness_report().await;
        assert!(still_serving.ready);
        assert_eq!(
            still_serving.state,
            TrafficState::Serving,
            "the newly discovered peer reconciles in the background"
        );
    }

    #[tokio::test]
    async fn backfill_readiness_with_zero_peers_requires_only_the_discovery_gates() {
        let context = test_context(|_| {}).await;
        context.state.runtime.require_peer_view();
        context
            .state
            .apply_membership_view(BTreeSet::new(), BTreeMap::new(), true)
            .await;
        context.state.expire_readiness_settle_window().await;

        // Gate two (first control-plane peer view) still withholds serving.
        context.state.maybe_mark_serving().await;
        assert!(!context.state.runtime.is_serving());

        context.state.runtime.mark_peer_view_ready();
        context.state.maybe_mark_serving().await;
        assert!(
            context.state.runtime.is_serving(),
            "an empty cycle settles immediately: zero peers ⇒ ready"
        );
    }

    fn rendered_metric_value(rendered: &str, selector: &str) -> Option<u64> {
        rendered
            .lines()
            .filter(|line| !line.starts_with('#'))
            .find(|line| line.contains(selector))
            .and_then(|line| line.split_whitespace().last())
            .and_then(|value| value.parse().ok())
    }

    #[tokio::test]
    async fn app_state_records_membership_peer_change_metrics() {
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
            .apply_membership_view(
                BTreeSet::from(["remote-b".to_string()]),
                BTreeMap::from([(peer_b.clone(), "remote-b".to_string())]),
                true,
            )
            .await;

        let rendered = context.state.metrics.render();
        assert_eq!(
            rendered_metric_value(&rendered, "change=\"discovered\"}"),
            Some(2)
        );
        assert_eq!(
            rendered_metric_value(&rendered, "change=\"lost\"}"),
            Some(1)
        );
    }
}
