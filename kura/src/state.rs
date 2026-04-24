use std::{
    collections::{BTreeMap, BTreeSet},
    io::ErrorKind,
    path::PathBuf,
    sync::Arc,
};

use reqwest::Client;
use tokio::{
    fs,
    sync::{Mutex, Notify, RwLock},
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
    pub members: RwLock<BTreeSet<String>>,
    pub peer_nodes: RwLock<BTreeMap<String, String>>,
    pub bootstrapped_peers: Mutex<BTreeSet<String>>,
    pub bootstrap_inflight_peers: Mutex<BTreeSet<String>>,
    pub readiness_settle_until: Mutex<Instant>,
}

pub type SharedState = Arc<AppState>;

#[derive(Debug, PartialEq, Eq)]
pub struct ReadinessReport {
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

impl AppState {
    pub fn drain_marker_path(&self) -> PathBuf {
        self.config.tmp_dir.join("drain")
    }

    pub fn start_http_request(&self) -> InflightGuard {
        self.runtime.start_http_request(&self.metrics)
    }

    pub fn start_grpc_request(&self) -> InflightGuard {
        self.runtime.start_grpc_request(&self.metrics)
    }

    pub fn enter_draining(&self) {
        self.runtime.request_drain();
    }

    pub async fn mark_initial_discovery_completed(&self) {
        self.runtime.mark_initial_discovery_completed();
        self.extend_readiness_settle_window().await;
    }

    pub async fn clear_stale_drain_marker(&self) -> Result<bool, String> {
        let drain_marker_path = self.drain_marker_path();
        match fs::remove_file(&drain_marker_path).await {
            Ok(()) => Ok(true),
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(false),
            Err(error) => Err(format!(
                "failed to clear stale drain marker {}: {error}",
                drain_marker_path.display()
            )),
        }
    }

    pub async fn extend_readiness_settle_window(&self) {
        if self.runtime.is_serving() {
            return;
        }
        *self.readiness_settle_until.lock().await = Instant::now() + READINESS_SETTLE_WINDOW;
    }

    async fn readiness_settle_window_elapsed(&self) -> bool {
        Instant::now() >= *self.readiness_settle_until.lock().await
    }

    #[cfg(test)]
    pub async fn expire_readiness_settle_window(&self) {
        *self.readiness_settle_until.lock().await = Instant::now();
    }

    pub async fn refresh_drain_marker(&self) -> Result<(), String> {
        if self.runtime.is_draining() {
            return Ok(());
        }
        match fs::try_exists(self.drain_marker_path())
            .await
            .map_err(|error| format!("failed to inspect drain marker: {error}"))?
        {
            true => {
                self.enter_draining();
                Ok(())
            }
            false => Ok(()),
        }
    }

    pub async fn forget_peers(&self, peers: &[String]) {
        if peers.is_empty() {
            return;
        }
        let peer_set = peers.iter().cloned().collect::<BTreeSet<_>>();
        {
            let mut bootstrapped = self.bootstrapped_peers.lock().await;
            bootstrapped.retain(|peer| !peer_set.contains(peer));
        }
        {
            let mut inflight = self.bootstrap_inflight_peers.lock().await;
            inflight.retain(|peer| !peer_set.contains(peer));
        }
    }

    pub async fn note_bootstrap_started(&self, peer: &str) -> bool {
        {
            let bootstrapped = self.bootstrapped_peers.lock().await;
            if bootstrapped.contains(peer) {
                return false;
            }
        }
        let mut inflight = self.bootstrap_inflight_peers.lock().await;
        if inflight.contains(peer) {
            return false;
        }
        inflight.insert(peer.to_string());
        true
    }

    pub async fn note_bootstrap_succeeded(&self, peer: &str) {
        self.bootstrap_inflight_peers.lock().await.remove(peer);
        self.bootstrapped_peers
            .lock()
            .await
            .insert(peer.to_string());
    }

    pub async fn note_bootstrap_failed(&self, peer: &str) {
        self.bootstrap_inflight_peers.lock().await.remove(peer);
    }

    async fn bootstrap_gate_satisfied(&self, known_peers: &[String]) -> bool {
        let inflight = self.bootstrap_inflight_peers.lock().await;
        if known_peers.iter().any(|peer| inflight.contains(peer)) {
            return false;
        }
        drop(inflight);
        let bootstrapped = self.bootstrapped_peers.lock().await;
        known_peers.iter().all(|peer| bootstrapped.contains(peer))
    }

    pub async fn maybe_mark_serving(&self) {
        if self.runtime.is_draining()
            || self.runtime.is_serving()
            || !self.runtime.initial_discovery_completed()
            || !self.readiness_settle_window_elapsed().await
        {
            return;
        }
        let known_peers = self
            .peer_nodes
            .read()
            .await
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        if self.bootstrap_gate_satisfied(&known_peers).await {
            self.runtime.mark_serving();
        }
    }

    pub async fn readiness_report(&self) -> ReadinessReport {
        self.maybe_mark_serving().await;

        let draining = self.runtime.is_draining();
        let state = self.runtime.traffic_state();
        let writer_lock_owned = self.runtime.writer_lock_owned();
        let initial_discovery_completed = self.runtime.initial_discovery_completed();
        let readiness_settled = self.readiness_settle_window_elapsed().await;
        let known_peers = self
            .peer_nodes
            .read()
            .await
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        let bootstrapped_peers = self
            .bootstrapped_peers
            .lock()
            .await
            .iter()
            .cloned()
            .collect::<Vec<_>>();
        let bootstrap_inflight_peers = self
            .bootstrap_inflight_peers
            .lock()
            .await
            .iter()
            .cloned()
            .collect::<Vec<_>>();
        let mut reasons = Vec::new();
        if !writer_lock_owned {
            reasons.push("writer lock not held".to_string());
        }
        if draining {
            reasons.push("draining".to_string());
        }
        if !initial_discovery_completed {
            reasons.push("initial discovery incomplete".to_string());
        }
        if !self.runtime.is_serving() && initial_discovery_completed && !readiness_settled {
            reasons.push("discovery settling".to_string());
        }
        if !self.runtime.is_serving() && !bootstrap_inflight_peers.is_empty() {
            reasons.push("bootstrap in progress".to_string());
        }
        if !self.runtime.is_serving() {
            let bootstrapped = bootstrapped_peers.iter().cloned().collect::<BTreeSet<_>>();
            let missing = known_peers
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
            ready,
            state,
            reasons,
            draining,
            writer_lock_owned,
            initial_discovery_completed,
            known_peers,
            bootstrapped_peers,
            bootstrap_inflight_peers,
            http_inflight: self.runtime.http_inflight(),
            grpc_inflight: self.runtime.grpc_inflight(),
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
