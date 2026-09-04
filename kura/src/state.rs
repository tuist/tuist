use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    sync::Arc,
};

use arc_swap::ArcSwap;
use axum_server::tls_rustls::RustlsConfig;
use reqwest::Client;
use tokio::{
    sync::{Mutex, Notify},
    time::{Duration, Instant},
};

use tracing::info;

use crate::{
    analytics::Analytics,
    auth::SharedAuth,
    backfill::lifecycle::{BackfillInitialCycleMode, BackfillLifecycle},
    bandwidth::BandwidthLimiter,
    bazel_test_artifacts::BazelTestArtifactDelivery,
    config::Config,
    constants::{REPLICATION_BACKOFF_BASE_SECS, REPLICATION_BACKOFF_MAX_SECS},
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
    /// Peer client for streaming request bodies (outbox artifact PUTs): no
    /// read timeout, paired with the caller's byte-progress stall watchdog.
    pub upload_client: ArcSwap<Client>,
    pub peer_client_factory: PeerClientFactory,
    // The inbound internal mTLS server config, retained so cert rotation can
    // hot-reload the leaf via `reload_from_config`. `None` when peer TLS is off.
    pub internal_tls: Option<RustlsConfig>,
    // The control-plane-authoritative volatile peer view, refreshed at mesh
    // heartbeat / peers-sync cadence and merged into discovery/replication
    // targets on top of the static (platform-stable) `config.peers`.
    pub dynamic_peers: ArcSwap<Vec<String>>,
    /// The replication target list as of the last membership pass, for the
    /// pre-body write gates: they run on every write and must not re-derive
    /// it under the readiness lock. Staleness is bounded by the pass
    /// interval, and the reservation behind the gate is exact.
    pub outbox_gate_targets: ArcSwap<Vec<String>>,
    pub replication_bandwidth_limiter: Option<Arc<BandwidthLimiter>>,
    pub notify: Notify,
    pub readiness: Mutex<ReadinessState>,
    /// Process-wide byte budget shared by every transient disk writer.
    pub tmp_staging_budget: Arc<TmpBudget>,
    /// Byte budget for peer catch-up staging: the spool a backfill pass writes
    /// bodies through, and the reservation the serving side charges a bodies
    /// response against. Separate from `tmp_staging_budget` so catch-up traffic
    /// cannot starve in-flight client uploads (or the reverse).
    pub peer_staging_budget: Arc<TmpBudget>,
    pub replication_backoff: Mutex<HashMap<String, ReplicationBackoff>>,
    /// Targets known not to serve the batched replication route, learned from a
    /// 404 or 405 on the first attempt. A peer that predates the route must not
    /// cost a wasted round trip per batch for the life of a backlog, so the
    /// answer is remembered; it is process-scoped, so an upgraded peer is
    /// retried after the next restart rather than staying downgraded forever.
    pub replication_batch_unsupported: Mutex<BTreeSet<String>>,
    /// Serving-side per-peer-identity concurrency gate for the backfill bodies
    /// endpoint (see [`BackfillBodiesPeerSlots`]).
    pub backfill_bodies_peer_slots: Arc<BackfillBodiesPeerSlots>,
    /// The backfill walker's node-side state machine, driven by the
    /// membership loop.
    pub backfill: Arc<BackfillLifecycle>,
}

/// One-in-flight-per-identity gate for `POST /_internal/backfill/bodies`.
///
/// The requester side already limits itself to one in-flight bodies request
/// per peer, but that bound is politeness: self-hosted peers hold account-CA
/// client certificates on customer infrastructure, and a hostile or buggy
/// peer must not be able to pin the shared tmp budget and bandwidth limiter
/// with parallel bulk requests. Identities come from the internal mTLS
/// listener's verified client certificate
/// ([`crate::peer_tls::InternalPeerIdentity`]).
#[derive(Debug, Default)]
pub struct BackfillBodiesPeerSlots {
    active: std::sync::Mutex<BTreeSet<Arc<str>>>,
}

impl BackfillBodiesPeerSlots {
    /// Claims the identity's slot, or `None` while another request from the
    /// same identity is still in flight. The returned guard must live for the
    /// whole request, response streaming included.
    pub fn try_acquire(self: &Arc<Self>, identity: Arc<str>) -> Option<BackfillBodiesPeerSlot> {
        let mut active = self.active.lock().expect("backfill peer slots lock");
        if !active.insert(identity.clone()) {
            return None;
        }
        Some(BackfillBodiesPeerSlot {
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
        self.slots
            .active
            .lock()
            .expect("backfill peer slots lock")
            .remove(&self.identity);
    }
}

pub struct ReplicationBackoff {
    next_attempt: Instant,
    failures: u32,
}

impl AppState {
    /// The current outbound peer HTTP client (picks up rotated certs).
    pub fn client(&self) -> arc_swap::Guard<Arc<Client>> {
        self.client.load()
    }

    /// The current outbound peer upload client (picks up rotated certs).
    pub fn upload_client(&self) -> arc_swap::Guard<Arc<Client>> {
        self.upload_client.load()
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
    pub outbox_messages: u64,
    pub outbox_capacity: u64,
    pub memory_pressure_state: i64,
    pub fd_timeout_count: u64,
    pub peer_connection_failure_count: u64,
    pub ring_fingerprint: String,
    pub backfill: BackfillRolloutStatus,
}

#[derive(Debug, PartialEq, Eq)]
pub struct BackfillRolloutStatus {
    pub initial_cycle: BackfillInitialCycleMode,
    pub backfilling_peers: usize,
    pub budget_exhausted_real: usize,
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
    ever_discovered_only_peers: BTreeSet<String>,
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
            ever_discovered_only_peers: BTreeSet::new(),
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
        self.runtime.request_drain()
    }

    pub async fn replication_target_backed_off(&self, target: &str, now: Instant) -> bool {
        self.replication_backoff
            .lock()
            .await
            .get(target)
            .is_some_and(|backoff| backoff.next_attempt > now)
    }

    pub async fn note_replication_success(&self, target: &str) {
        self.replication_backoff.lock().await.remove(target);
    }

    pub async fn replication_batch_unsupported(&self, target: &str) -> bool {
        self.replication_batch_unsupported
            .lock()
            .await
            .contains(target)
    }

    pub async fn note_replication_batch_unsupported(&self, target: &str) {
        self.replication_batch_unsupported
            .lock()
            .await
            .insert(target.to_owned());
    }

    pub async fn note_replication_failure(&self, target: &str, now: Instant) {
        let mut backoffs = self.replication_backoff.lock().await;
        let backoff = backoffs
            .entry(target.to_string())
            .or_insert(ReplicationBackoff {
                next_attempt: now,
                failures: 0,
            });
        backoff.failures = backoff.failures.saturating_add(1);
        let delay_secs = REPLICATION_BACKOFF_BASE_SECS
            .saturating_mul(2u64.saturating_pow(backoff.failures - 1))
            .min(REPLICATION_BACKOFF_MAX_SECS);
        backoff.next_attempt = now + Duration::from_secs(delay_secs);
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
        self.refresh_outbox_capacity(discovery_observed).await;
        membership_update
    }

    /// Re-derives the outbox cap from every peer whose messages may occupy
    /// the queue: the current replication targets (what a write enqueues for)
    /// plus the discovered-only history, whose messages `process_outbox`
    /// never prunes within a process lifetime. Counting that history keeps a
    /// departed sibling's share — and a sibling's share through a status-probe
    /// blip, which empties the discovered set the same way — for as long as
    /// its messages can sit in the queue, so the cap only shrinks behind a
    /// departure whose messages are actually dropped.
    ///
    /// `observed` says whether the view behind an empty set was actually
    /// seen: every discovery target answered, or there were none to ask. An
    /// unobserved empty set means the node has no peer view (control plane or
    /// discovery unreachable), not that every peer left — the same reading
    /// `process_outbox` gives it when it declines to prune — so the last
    /// derived total holds rather than collapsing to one share under a
    /// backlog that is not going anywhere. An observed empty set is a mesh
    /// that really has no peers, and the total returns to one share.
    pub async fn refresh_outbox_capacity(&self, observed: bool) {
        let targets = self.replication_targets().await;
        let mut peers: BTreeSet<String> = targets.iter().cloned().collect();
        peers.extend(self.discovered_only_peer_history().await);
        self.outbox_gate_targets.store(Arc::new(targets));
        if peers.is_empty() && !observed {
            return;
        }
        self.store.set_replication_peer_count(peers.len());
        self.store.retain_outbox_targets(&peers);
    }

    pub async fn initial_discovery_completed(&self) -> bool {
        self.readiness.lock().await.initial_discovery_completed
    }

    pub async fn note_discovered_only_peers(&self, peers: Vec<String>) {
        if peers.is_empty() {
            return;
        }
        let mut readiness = self.readiness.lock().await;
        readiness.ever_discovered_only_peers.extend(peers);
    }

    pub async fn discovered_only_peer_history(&self) -> BTreeSet<String> {
        self.readiness
            .lock()
            .await
            .ever_discovered_only_peers
            .clone()
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

    pub async fn replication_targets(&self) -> Vec<String> {
        let snapshot = self.readiness_snapshot().await;
        let mut targets = self.config.peers.iter().cloned().collect::<BTreeSet<_>>();
        targets.extend(self.dynamic_peers.load().iter().cloned());
        targets.extend(snapshot.known_peers);
        targets.remove(&self.config.node_url);
        targets.into_iter().collect()
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
        // is at least the configured percent full OR it is no longer
        // backfilling — where "backfilling" covers only the initial join
        // cycle, whose membership is fixed at (initial discovery ∪ first
        // control-plane view); later discoveries never gate. An empty cycle
        // settles immediately (zero peers ⇒ ready here), and a cycle whose
        // peers all exhausted their budgets settles too (ready-but-cold is
        // intended; background retries continue, metered). Serving then
        // LATCHES for the process lifetime: this function only runs while not
        // serving, and no backfill path clears the flag — only the orthogonal
        // /ready inputs (writer lock, draining) can take the node out of
        // rotation.
        if !self.backfill.cycle_snapshot().is_backfilling()
            || self.ring_fullness_percent() >= self.config.backfill_ready_ring_percent
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
        if self.runtime.peer_view_pending() {
            reasons.push("awaiting control-plane peer view".to_string());
        }
        if !self.runtime.is_serving()
            && snapshot.initial_discovery_completed
            && !snapshot.readiness_settled
        {
            reasons.push("discovery settling".to_string());
        }
        if !self.runtime.is_serving() && self.backfill.cycle_snapshot().is_backfilling() {
            let fullness = self.ring_fullness_percent();
            reasons.push(format!(
                "initial backfill cycle in progress (ring {fullness}% < {}%)",
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
        let cycle = self.backfill.cycle_snapshot();
        let backfill = BackfillRolloutStatus {
            initial_cycle: cycle.initial_cycle_mode(),
            backfilling_peers: cycle.backfilling_peers,
            budget_exhausted_real: cycle.budget_exhausted_real,
            budget_exhausted_capability: cycle.budget_exhausted_capability,
            ring_fullness_percent: self.ring_fullness_percent(),
        };

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
            outbox_messages: metrics.outbox_messages,
            outbox_capacity: self.store.outbox_max_depth() as u64,
            memory_pressure_state: self.memory.pressure().as_i64(),
            fd_timeout_count: metrics.fd_timeout_count,
            peer_connection_failure_count: metrics.peer_connection_failure_count,
            backfill,
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
        self.metrics.set_backfill_initial_cycle_mode(
            self.backfill.cycle_snapshot().initial_cycle_mode().as_i64(),
        );
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
    use crate::{
        artifact::producer::ArtifactProducer,
        backfill::lifecycle::{BudgetChargeKind, MembershipTick, PassResolution},
        constants::{
            BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET, BACKFILL_PASS_RETRY_BACKOFF_MAX_MS,
            BACKFILL_SEAM_FOLLOWUP_DELAY_MS,
        },
        test_support::test_context,
    };

    use super::*;

    fn backfill_tick<'a>(discovered: &'a [String], lost: &'a [String]) -> MembershipTick<'a> {
        MembershipTick {
            discovered,
            lost,
            view_settled: true,
            control_plane_peers: &[],
            admission: true,
        }
    }

    /// Charges the peer's whole initial-cycle failure budget with the given
    /// kind, leaving the peer budget-exhausted (it stops gating readiness).
    fn exhaust_backfill_budget_over(
        state: &AppState,
        peer: &str,
        kind: BudgetChargeKind,
        mut now: Instant,
    ) -> Instant {
        let discovered = vec![peer.to_string()];
        state
            .backfill
            .test_evaluate(&backfill_tick(&discovered, &[]), now);
        for _ in 0..BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET {
            state.backfill.test_finish_pass(
                peer,
                PassResolution::Cancelled {
                    budget_charge: Some(kind),
                },
                now,
            );
            now += Duration::from_millis(BACKFILL_PASS_RETRY_BACKOFF_MAX_MS + 1);
            state.backfill.test_evaluate(&backfill_tick(&[], &[]), now);
        }
        now
    }

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
    async fn membership_view_rederives_the_outbox_capacity() {
        let context = test_context(|config| {
            config.outbox_max_depth = None;
            config.outbox_max_depth_per_peer = 10;
            // Only the node itself is a static seed: one share to start.
            config.peers = vec![config.node_url.clone()];
        })
        .await;
        assert_eq!(context.state.store.outbox_max_depth(), 10);

        context
            .state
            .dynamic_peers
            .store(std::sync::Arc::new(vec!["http://peer-c:7443".to_string()]));
        context
            .state
            .apply_membership_view(
                BTreeSet::from(["remote".to_string()]),
                BTreeMap::from([
                    ("http://peer-a:7443".to_string(), "remote".to_string()),
                    ("http://peer-b:7443".to_string(), "remote".to_string()),
                ]),
                true,
            )
            .await;
        assert_eq!(
            context.state.store.outbox_max_depth(),
            30,
            "two discovered peers plus one dynamic peer"
        );

        context
            .state
            .apply_membership_view(
                BTreeSet::from(["remote".to_string()]),
                BTreeMap::from([("http://peer-a:7443".to_string(), "remote".to_string())]),
                true,
            )
            .await;
        assert_eq!(
            context.state.store.outbox_max_depth(),
            20,
            "a lost peer gives its share back"
        );

        // A discovered-only peer's messages are never pruned, so its share
        // survives its absence from the view — whether it left or its status
        // probe merely failed this pass.
        context
            .state
            .note_discovered_only_peers(vec!["http://peer-a:7443".to_string()])
            .await;
        context
            .state
            .apply_membership_view(BTreeSet::new(), BTreeMap::new(), false)
            .await;
        assert_eq!(
            context.state.store.outbox_max_depth(),
            20,
            "an empty view keeps the discovered-only share and the dynamic peer"
        );
    }

    /// An empty derived set is "no peer view", the reading the prune path
    /// gives it, so the capacity holds instead of collapsing to one share.
    #[tokio::test]
    async fn an_empty_peer_view_holds_the_outbox_capacity() {
        let context = test_context(|config| {
            config.outbox_max_depth = None;
            config.outbox_max_depth_per_peer = 10;
            config.peers = vec![config.node_url.clone()];
        })
        .await;
        context
            .state
            .apply_membership_view(
                BTreeSet::from(["remote".to_string()]),
                BTreeMap::from([
                    ("http://peer-a:7443".to_string(), "remote".to_string()),
                    ("http://peer-b:7443".to_string(), "remote".to_string()),
                ]),
                true,
            )
            .await;
        assert_eq!(context.state.store.outbox_max_depth(), 20);

        context
            .state
            .apply_membership_view(BTreeSet::new(), BTreeMap::new(), false)
            .await;
        assert_eq!(
            context.state.store.outbox_max_depth(),
            20,
            "a lost view keeps the last derived capacity"
        );

        // F6: an OBSERVED empty view (every discovery target answered, or
        // there are none) is a mesh that really has no peers, and the
        // capacity returns to one share instead of freezing.
        context
            .state
            .apply_membership_view(BTreeSet::new(), BTreeMap::new(), true)
            .await;
        assert_eq!(
            context.state.store.outbox_max_depth(),
            10,
            "an observed empty mesh drops to the single-share floor"
        );
    }

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
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&[], &[]), Instant::now());
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
    async fn backfill_readiness_latches_at_ring_fullness_while_still_backfilling() {
        let context = test_context(|config| {
            // Clamp the ring to the 5-segment legacy floor so one persisted
            // segment reads as 20% full.
            config.cas_capacity_bytes = Some(1);
            config.backfill_ready_ring_percent = 20;
        })
        .await;
        context
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
            .expect("local artifact should persist");
        assert_eq!(context.state.ring_fullness_percent(), 20);

        let peer = "http://peer.kura.internal:7443".to_string();
        context
            .state
            .apply_membership_view(
                BTreeSet::from(["remote".to_string()]),
                BTreeMap::from([(peer.clone(), "remote".to_string())]),
                true,
            )
            .await;
        // The peer's pass is in flight: the node is still backfilling.
        let discovered = vec![peer.clone()];
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&discovered, &[]), Instant::now());
        assert!(context.state.backfill.cycle_snapshot().is_backfilling());

        context.state.expire_readiness_settle_window().await;
        context.state.maybe_mark_serving().await;

        let report = context.state.readiness_report().await;
        assert!(report.ready, "ring at threshold latches ready mid-backfill");
        assert!(context.state.backfill.cycle_snapshot().is_backfilling());

        context.state.sync_runtime_metrics().await;
        let rendered = context.state.metrics.render();
        assert_eq!(
            rendered_metric_value(&rendered, "kura_backfill_ring_fullness_percent"),
            Some(20)
        );
        assert_eq!(
            rendered_metric_value(&rendered, "kura_backfill_initial_cycle_mode"),
            Some(0),
            "the cycle is still pending"
        );
    }

    #[tokio::test]
    async fn backfill_readiness_latches_when_no_longer_backfilling_below_ring_threshold() {
        let context = test_context(|_| {}).await;
        assert_eq!(context.state.ring_fullness_percent(), 0);

        let peer = "http://peer.kura.internal:7443".to_string();
        context
            .state
            .apply_membership_view(
                BTreeSet::from(["remote".to_string()]),
                BTreeMap::from([(peer.clone(), "remote".to_string())]),
                true,
            )
            .await;
        context.state.expire_readiness_settle_window().await;

        // Mid-cycle (pass in flight) the small-dataset node is not ready.
        let discovered = vec![peer.clone()];
        let now = Instant::now();
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&discovered, &[]), now);
        context.state.maybe_mark_serving().await;
        let report = context.state.readiness_report().await;
        assert!(!report.ready);
        assert!(
            report
                .reasons
                .iter()
                .any(|reason| reason.contains("initial backfill cycle in progress"))
        );

        // The cycle settles (first pass + seam follow-up complete): ready
        // latches even though the ring never reached the threshold.
        context
            .state
            .backfill
            .test_finish_pass(&peer, PassResolution::Completed, now);
        let seam = now + Duration::from_millis(BACKFILL_SEAM_FOLLOWUP_DELAY_MS);
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&[], &[]), seam);
        context
            .state
            .backfill
            .test_finish_pass(&peer, PassResolution::Completed, seam);
        context.state.maybe_mark_serving().await;
        assert!(context.state.readiness_report().await.ready);
    }

    #[tokio::test]
    async fn backfill_readiness_latches_when_all_in_cycle_budgets_exhaust_below_threshold() {
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
        exhaust_backfill_budget_over(
            &context.state,
            &peer,
            BudgetChargeKind::Real,
            Instant::now(),
        );

        let cycle = context.state.backfill.cycle_snapshot();
        assert!(!cycle.is_backfilling());
        assert_eq!(cycle.budget_exhausted_real, 1);

        context.state.expire_readiness_settle_window().await;
        context.state.maybe_mark_serving().await;
        assert!(
            context.state.readiness_report().await.ready,
            "ready-but-cold is intended when every in-cycle budget exhausts"
        );
        let report = context.state.rollout_status_report().await;
        let backfill = report.backfill;
        assert_eq!(backfill.initial_cycle, BackfillInitialCycleMode::Degraded);
    }

    #[tokio::test]
    async fn backfill_readiness_with_zero_peers_requires_only_the_discovery_gates() {
        let context = test_context(|_| {}).await;
        context.state.runtime.require_peer_view();
        context
            .state
            .apply_membership_view(BTreeSet::new(), BTreeMap::new(), true)
            .await;
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&[], &[]), Instant::now());
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

    #[tokio::test]
    async fn backfill_peer_discovered_after_cycle_fixed_does_not_gate_readiness() {
        let context = test_context(|_| {}).await;
        context
            .state
            .apply_membership_view(BTreeSet::new(), BTreeMap::new(), true)
            .await;
        // The first settled tick fixes an empty cycle.
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&[], &[]), Instant::now());

        // A peer discovered after the fix runs an ordinary re-join backfill.
        let late_peer = vec!["http://late-peer.kura.internal:7443".to_string()];
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&late_peer, &[]), Instant::now());
        assert!(!context.state.backfill.cycle_snapshot().is_backfilling());

        context.state.expire_readiness_settle_window().await;
        context.state.maybe_mark_serving().await;
        assert!(
            context.state.runtime.is_serving(),
            "a post-fix discovery must not gate first readiness"
        );
    }

    #[tokio::test]
    async fn rollout_status_report_advances_backfill_mode_from_pending_through_degraded_to_complete()
     {
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

        // Pending: the peer's pass is in flight and gates the cycle.
        let discovered = vec![peer.clone()];
        let now = Instant::now();
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&discovered, &[]), now);
        let report = context.state.rollout_status_report().await;
        let backfill = report.backfill;
        assert_eq!(backfill.initial_cycle, BackfillInitialCycleMode::Pending);
        assert_eq!(backfill.backfilling_peers, 1);

        // Degraded: the budget exhausts on real failures and the cycle settles.
        let now = exhaust_backfill_budget_over(&context.state, &peer, BudgetChargeKind::Real, {
            // The pending pass above must terminate before the budget
            // loop restarts passes over the same slot.
            context
                .state
                .backfill
                .test_finish_pass(&peer, PassResolution::Failed, now);
            now + Duration::from_millis(BACKFILL_PASS_RETRY_BACKOFF_MAX_MS + 1)
        });
        let report = context.state.rollout_status_report().await;
        let backfill = report.backfill;
        assert_eq!(backfill.initial_cycle, BackfillInitialCycleMode::Degraded);
        assert_eq!(backfill.backfilling_peers, 0);
        assert_eq!(backfill.budget_exhausted_real, 1);
        context.state.sync_runtime_metrics().await;
        assert_eq!(
            rendered_metric_value(
                &context.state.metrics.render(),
                "kura_backfill_initial_cycle_mode"
            ),
            Some(2)
        );

        // Degraded is not terminal: the background retry (and its seam
        // follow-up) completing advances the mode to complete.
        context
            .state
            .backfill
            .test_finish_pass(&peer, PassResolution::Completed, now);
        let seam = now + Duration::from_millis(BACKFILL_SEAM_FOLLOWUP_DELAY_MS);
        context
            .state
            .backfill
            .test_evaluate(&backfill_tick(&[], &[]), seam);
        context
            .state
            .backfill
            .test_finish_pass(&peer, PassResolution::Completed, seam);
        let report = context.state.rollout_status_report().await;
        let backfill = report.backfill;
        assert_eq!(backfill.initial_cycle, BackfillInitialCycleMode::Complete);
        assert_eq!(backfill.budget_exhausted_real, 0);
    }

    #[tokio::test]
    async fn rollout_status_report_counts_capability_excluded_peers_as_complete() {
        let context = test_context(|_| {}).await;
        let peer = "http://pre-ab-peer.kura.internal:7443".to_string();
        context
            .state
            .apply_membership_view(
                BTreeSet::from(["remote".to_string()]),
                BTreeMap::from([(peer.clone(), "remote".to_string())]),
                true,
            )
            .await;
        exhaust_backfill_budget_over(
            &context.state,
            &peer,
            BudgetChargeKind::Capability,
            Instant::now(),
        );

        let report = context.state.rollout_status_report().await;
        let backfill = report.backfill;
        assert_eq!(
            backfill.initial_cycle,
            BackfillInitialCycleMode::Complete,
            "a capability-excluded bystander must not degrade the cycle"
        );
        assert_eq!(backfill.budget_exhausted_capability, 1);
        assert_eq!(backfill.budget_exhausted_real, 0);
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
