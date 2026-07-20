use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    sync::Arc,
};

use arc_swap::ArcSwap;
use axum_server::tls_rustls::RustlsConfig;
use reqwest::Client;
use tokio::{
    sync::{Mutex, Notify, Semaphore},
    time::{Duration, Instant},
};

use crate::{
    analytics::Analytics,
    bandwidth::BandwidthLimiter,
    config::Config,
    constants::{REPLICATION_BACKOFF_BASE_SECS, REPLICATION_BACKOFF_MAX_SECS},
    extension::SharedExtension,
    geoip::GeoIp,
    io::IoController,
    memory::MemoryController,
    metrics::Metrics,
    peer_tls::PeerClientFactory,
    runtime::{DataDirLock, HttpTrafficClass, InflightGuard, RuntimeState, TrafficState},
    store::Store,
    usage::Usage,
    utils::TmpBudget,
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
    pub usage: Option<Usage>,
    pub geoip: Option<GeoIp>,
    // Outbound peer client, behind an atomic swap so cert rotation can replace
    // it in place. Read it with `state.client()`.
    pub client: ArcSwap<Client>,
    pub peer_client_factory: PeerClientFactory,
    // The inbound internal mTLS server config, retained so cert rotation can
    // hot-reload the leaf via `reload_from_config`. `None` when peer TLS is off.
    pub internal_tls: Option<RustlsConfig>,
    // The control-plane-authoritative volatile peer view, refreshed at mesh
    // heartbeat / peers-sync cadence and merged into discovery/replication
    // targets on top of the static (platform-stable) `config.peers`.
    pub dynamic_peers: ArcSwap<Vec<String>>,
    pub replication_bandwidth_limiter: Option<Arc<BandwidthLimiter>>,
    pub notify: Notify,
    pub readiness: Mutex<ReadinessState>,
    pub bootstrap_semaphore: Arc<Semaphore>,
    pub bootstrap_staging_budget: Arc<TmpBudget>,
    // Per-artifact gate that single-flights the bootstrap body download across
    // peers: only the first peer-task to claim a key fetches it, and the rest
    // observe it already applied and skip the network. Striped (see
    // `bootstrap_fetch_lock`). Bootstrap-scoped so it never blocks the
    // live-replication apply path, which the node still serves while joining.
    pub bootstrap_fetch_locks: Vec<Mutex<()>>,
    pub replication_backoff: Mutex<HashMap<String, ReplicationBackoff>>,
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

    /// The bootstrap fetch gate for an artifact. Striped by artifact id so
    /// distinct keys fetch concurrently; same-key fetches across peers serialize
    /// onto one stripe and single-flight via the caller's presence recheck.
    pub fn bootstrap_fetch_lock(&self, artifact_id: &str) -> &Mutex<()> {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        std::hash::Hash::hash(artifact_id, &mut hasher);
        let index =
            (std::hash::Hasher::finish(&hasher) as usize) % self.bootstrap_fetch_locks.len();
        &self.bootstrap_fetch_locks[index]
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
    bootstrapped_peers: BTreeSet<String>,
    bootstrap_inflight_peers: BTreeSet<String>,
    // Bumped by reset_bootstrap_progress. A bootstrap pass captures the epoch
    // when it starts and its completion only counts under the same epoch, so
    // a pass already in flight when a recovery re-enrollment resets progress
    // cannot re-mark its peer bootstrapped — the pass may straddle the
    // absence window and miss writes behind its cursor.
    bootstrap_epoch: u64,
    // Every peer ever seen through discovery only (not in the static or
    // dynamic peer config): in-cluster siblings and cross-region pods. Outbox
    // pruning never drops their messages — unlike control-plane-managed
    // peers, nothing re-bootstraps them after a network flap, so dropping
    // would be silent under-replication. Monotone and in-memory: bounded by
    // the peers a process ever meets, reset by restart (which also
    // re-bootstraps).
    ever_discovered_only_peers: BTreeSet<String>,
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
            bootstrap_epoch: 0,
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

    fn note_bootstrap_succeeded(&mut self, peer: &str, epoch: u64) {
        self.bootstrap_inflight_peers.remove(peer);
        // A completion from a pass started before the last progress reset does
        // not count as bootstrapped; the peer re-enters peers_needing_bootstrap
        // and gets a fresh pass.
        if epoch == self.bootstrap_epoch && self.known_peers.contains(peer) {
            self.bootstrapped_peers.insert(peer.to_string());
        }
    }

    fn reset_bootstrap_progress(&mut self, now: Instant) {
        self.bootstrapped_peers.clear();
        self.bootstrap_epoch = self.bootstrap_epoch.wrapping_add(1);
        // Re-arm the settle window (like a generation change does) so
        // maybe_mark_serving cannot re-mark the node before the gate is
        // genuinely re-evaluated — e.g. while known_peers is momentarily
        // empty, which would make "all known peers bootstrapped" trivially
        // true.
        self.settle_until = now + READINESS_SETTLE_WINDOW;
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

    pub async fn initial_discovery_completed(&self) -> bool {
        self.readiness.lock().await.initial_discovery_completed
    }

    /// Forgets all bootstrap progress so the membership loop re-pulls the full
    /// dataset from every known peer, and takes the node out of serving until
    /// the gate re-passes. Called on a *recovery* re-enrollment — the node was
    /// out of the mesh for an unknown window, and the writes it missed were
    /// never enqueued for it (replication targets are computed at write time),
    /// so only a full re-bootstrap can reconcile the gap, including namespace
    /// delete tombstones. Readiness implies complete data, so the node must
    /// not keep advertising ready while it knows its data is incomplete —
    /// every *other* node already re-enters the gate when this node rejoins
    /// (their membership generation changes); this keeps the one node whose
    /// data actually is incomplete from being the only one that skips it.
    /// Bumps the bootstrap epoch so passes already in flight cannot re-mark
    /// their peer bootstrapped.
    pub async fn reset_bootstrap_progress(&self) {
        self.readiness
            .lock()
            .await
            .reset_bootstrap_progress(Instant::now());
        self.runtime.clear_serving();
    }

    /// Claims a bootstrap slot for `peer`, returning the epoch the pass runs
    /// under (to be handed back to `note_bootstrap_succeeded`), or `None` when
    /// the peer is unknown, already bootstrapped, or already in flight.
    pub async fn note_bootstrap_started(&self, peer: &str) -> Option<u64> {
        let mut readiness = self.readiness.lock().await;
        readiness
            .note_bootstrap_started(peer)
            .then_some(readiness.bootstrap_epoch)
    }

    pub async fn note_bootstrap_succeeded(&self, peer: &str, epoch: u64) {
        self.readiness
            .lock()
            .await
            .note_bootstrap_succeeded(peer, epoch);
    }

    #[cfg(test)]
    pub async fn current_bootstrap_epoch(&self) -> u64 {
        self.readiness.lock().await.bootstrap_epoch
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
        if self.runtime.peer_view_pending() {
            reasons.push("awaiting control-plane peer view".to_string());
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
        self.metrics.update_replication_bandwidth_limits(
            self.config.replication_bandwidth_limit_bytes_per_second,
            self.replication_bandwidth_limiter
                .as_ref()
                .map_or(0, |limiter| limiter.effective_bytes_per_second()),
            self.config.replication_public_latency_target_ms,
        );
    }
}

#[cfg(test)]
mod tests;
