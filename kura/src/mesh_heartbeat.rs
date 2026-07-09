//! Mesh-membership heartbeat and peer-view sync against the Tuist control
//! plane.
//!
//! Two loops share this module, one per node kind:
//!
//! - **Enrolled (self-hosted) nodes** POST a heartbeat proving they are still
//!   live mesh members. The control plane withholds peers that stop
//!   heartbeating and answers `mesh_member: false` once a node has been
//!   withheld; the node then performs a **recovery re-enrollment** (with
//!   backoff), which restores its membership server-side and — because the
//!   writes it missed while out of the mesh were never enqueued for it —
//!   resets local bootstrap progress so the full dataset is re-pulled.
//! - **Managed pods** don't enroll (Kubernetes owns their liveness), but they
//!   consume the same dynamic peer view through a peers-only fetch, so a
//!   self-hosted peer joining or leaving propagates at heartbeat cadence
//!   instead of through a fleet roll. Serving is gated on the first
//!   successful fetch: a pod booting blind would accept writes without
//!   enqueuing replication for peers it cannot see.
//!
//! In both modes the response carries the current peer list, which hot-swaps
//! `dynamic_peers`; a heartbeat failure keeps the last-known view (never
//! store on failure), so a degraded control plane can never shrink the mesh.
//! Independent from the registration heartbeat (`src/registration.rs`), which
//! advertises the node's client-facing cache endpoint for CLI routing.

use std::time::Duration;

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD;
use reqwest::header::AUTHORIZATION;
use serde::{Deserialize, Serialize};
use tokio::time::Instant;
use tracing::{info, warn};

use crate::state::SharedState;

const HEARTBEAT_PATH: &str = "/_internal/kura/mesh/heartbeat";
const PEERS_PATH: &str = "/_internal/kura/mesh/peers";

const KURA_MESH_PEERS_SYNC: &str = "KURA_MESH_PEERS_SYNC";

const DEFAULT_INTERVAL_MS: u64 = 60_000;
const CONNECT_TIMEOUT: Duration = Duration::from_millis(1_000);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(5);
// Recovery re-enrollments mint fresh certificates; the backoff keeps a
// persistent `mesh_member: false` (control-plane bug, clock skew) from
// becoming a per-minute signing loop while staying well below the sweep
// cadence so genuine recovery is prompt.
const RECOVERY_BACKOFF_INITIAL: Duration = Duration::from_secs(60);
const RECOVERY_BACKOFF_MAX: Duration = Duration::from_secs(300);

pub struct MeshHeartbeatConfig {
    pub heartbeat_url: String,
    pub client_id: String,
    pub client_secret: String,
    pub node_url: String,
    pub interval: Duration,
}

impl MeshHeartbeatConfig {
    /// Builds the enrolled-node heartbeat config from the enrollment outcome,
    /// which already carries the parsed control-plane relationship.
    pub fn from_enrollment(outcome: &crate::enrollment::EnrollmentOutcome) -> Self {
        Self {
            heartbeat_url: format!(
                "{}{HEARTBEAT_PATH}",
                outcome.control_plane_url.trim_end_matches('/')
            ),
            client_id: outcome.client_id.clone(),
            client_secret: outcome.client_secret.clone(),
            node_url: outcome.node_url.clone(),
            interval: Duration::from_millis(DEFAULT_INTERVAL_MS),
        }
    }
}

pub struct MeshPeersSyncConfig {
    pub peers_url: String,
    pub client_id: String,
    pub client_secret: String,
    pub tenant_id: String,
    pub interval: Duration,
}

impl MeshPeersSyncConfig {
    /// Builds the managed-pod peers-sync config, active only when the
    /// controller sets `KURA_MESH_PEERS_SYNC`. Credentials come from the
    /// already-parsed usage/control-plane configuration, so no extra
    /// environment plumbing is needed.
    pub fn from_config(config: &crate::config::Config) -> Option<Self> {
        if !matches!(
            std::env::var(KURA_MESH_PEERS_SYNC).ok().as_deref(),
            Some("1") | Some("true") | Some("TRUE")
        ) {
            return None;
        }

        let usage = config.usage.as_ref()?;
        Some(Self {
            peers_url: format!(
                "{}{PEERS_PATH}",
                usage.control_plane_url.trim_end_matches('/')
            ),
            client_id: usage.client_id.clone(),
            client_secret: usage.client_secret.clone(),
            tenant_id: config.tenant_id.clone(),
            interval: Duration::from_millis(DEFAULT_INTERVAL_MS),
        })
    }
}

#[derive(Serialize)]
struct MeshHeartbeat<'a> {
    node_url: &'a str,
}

#[derive(Deserialize)]
struct MeshHeartbeatResponse {
    #[serde(default)]
    mesh_member: bool,
    #[serde(default)]
    peers: Vec<String>,
    #[serde(default)]
    heartbeat_interval_seconds: Option<u64>,
}

#[derive(Deserialize)]
struct MeshPeersResponse {
    #[serde(default)]
    peers: Vec<String>,
    #[serde(default)]
    refresh_interval_seconds: Option<u64>,
}

pub fn spawn(state: SharedState, config: MeshHeartbeatConfig) {
    info!(
        "sending mesh heartbeats to control plane at {}",
        config.heartbeat_url
    );
    tokio::spawn(async move { run(state, config).await });
}

pub fn spawn_peers_sync(state: SharedState, config: MeshPeersSyncConfig) {
    info!(
        "syncing mesh peer view from control plane at {}",
        config.peers_url
    );
    tokio::spawn(async move { run_peers_sync(state, config).await });
}

async fn run(state: SharedState, mut config: MeshHeartbeatConfig) {
    let client = http_client();
    let mut recovery = RecoveryBackoff::new();

    loop {
        match send_heartbeat(&client, &state, &config).await {
            Ok(payload) => {
                if !payload.mesh_member {
                    maybe_recover_membership(&state, &mut recovery).await;
                } else {
                    recovery.reset();
                }
                // The cadence is control-plane advertised, like the
                // registration lease, so the server can retune it without a
                // node release.
                if let Some(seconds) = payload.heartbeat_interval_seconds
                    && seconds > 0
                {
                    config.interval = Duration::from_secs(seconds);
                }
            }
            Err(error) => warn!("mesh heartbeat failed: {error}"),
        }
        tokio::time::sleep(config.interval).await;
    }
}

async fn run_peers_sync(state: SharedState, mut config: MeshPeersSyncConfig) {
    let client = http_client();

    loop {
        match fetch_peers(&client, &config).await {
            Ok(payload) => {
                apply_peers(&state, payload.peers);
                // First successful fetch lifts the boot serving gate.
                state.runtime.mark_peer_view_ready();
                state.maybe_mark_serving().await;
                if let Some(seconds) = payload.refresh_interval_seconds
                    && seconds > 0
                {
                    config.interval = Duration::from_secs(seconds);
                }
            }
            Err(error) => warn!("mesh peer view sync failed: {error}"),
        }
        tokio::time::sleep(config.interval).await;
    }
}

async fn send_heartbeat(
    client: &reqwest::Client,
    state: &SharedState,
    config: &MeshHeartbeatConfig,
) -> Result<MeshHeartbeatResponse, String> {
    let response = client
        .post(&config.heartbeat_url)
        .header(
            AUTHORIZATION.as_str(),
            basic_auth(&config.client_id, &config.client_secret),
        )
        .json(&MeshHeartbeat {
            node_url: &config.node_url,
        })
        .send()
        .await
        .map_err(|error| format!("request failed: {error}"))?;

    if !response.status().is_success() {
        return Err(format!("control plane returned {}", response.status()));
    }

    let payload = response
        .json::<MeshHeartbeatResponse>()
        .await
        .map_err(|error| format!("failed to decode response: {error}"))?;

    apply_peers(state, payload.peers.clone());

    Ok(payload)
}

async fn fetch_peers(
    client: &reqwest::Client,
    config: &MeshPeersSyncConfig,
) -> Result<MeshPeersResponse, String> {
    let response = client
        .get(&config.peers_url)
        .query(&[("tenant_id", config.tenant_id.as_str())])
        .header(
            AUTHORIZATION.as_str(),
            basic_auth(&config.client_id, &config.client_secret),
        )
        .send()
        .await
        .map_err(|error| format!("request failed: {error}"))?;

    if !response.status().is_success() {
        return Err(format!("control plane returned {}", response.status()));
    }

    response
        .json::<MeshPeersResponse>()
        .await
        .map_err(|error| format!("failed to decode response: {error}"))
}

// `mesh_member: false` means the node was withheld from the mesh (deactivated
// as stale, or its row was purged). Heartbeats never create membership —
// enrollment is the only door — so recovery is a re-enrollment: the server's
// enrollment upsert reactivates or recreates the row, and locally the node
// must forget its bootstrap progress, because whatever was written while it
// was out of the mesh was never enqueued for it.
async fn maybe_recover_membership(state: &SharedState, recovery: &mut RecoveryBackoff) {
    if !recovery.should_attempt(Instant::now()) {
        return;
    }

    warn!("control plane reports this node is not a mesh member; re-enrolling to recover");
    match crate::enrollment::renew().await {
        Ok(outcome) => match crate::app::apply_renewed_enrollment(state, &outcome).await {
            Ok(()) => {
                state.reset_bootstrap_progress().await;
                // The backoff is deliberately NOT reset here: recovery is
                // only proven by a later heartbeat answering
                // `mesh_member: true` (which resets it in the run loop). A
                // successful re-enrollment that the server still answers
                // `false` to must keep backing off, or it becomes an
                // enroll/bootstrap-clear loop at heartbeat cadence.
                info!("re-enrolled to recover mesh membership; re-bootstrapping from peers");
            }
            Err(error) => warn!("recovery re-enrollment: failed to apply: {error}"),
        },
        Err(error) => warn!("recovery re-enrollment failed: {error}"),
    }
}

struct RecoveryBackoff {
    next_attempt: Option<Instant>,
    delay: Duration,
}

impl RecoveryBackoff {
    fn new() -> Self {
        Self {
            next_attempt: None,
            delay: RECOVERY_BACKOFF_INITIAL,
        }
    }

    fn should_attempt(&mut self, now: Instant) -> bool {
        match self.next_attempt {
            Some(next) if now < next => false,
            _ => {
                self.next_attempt = Some(now + self.delay);
                self.delay = (self.delay * 2).min(RECOVERY_BACKOFF_MAX);
                true
            }
        }
    }

    fn reset(&mut self) {
        self.next_attempt = None;
        self.delay = RECOVERY_BACKOFF_INITIAL;
    }
}

fn apply_peers(state: &SharedState, mut peers: Vec<String>) {
    // The server's row order is incidental; compare and store sorted so an
    // unchanged membership never registers as an update.
    peers.sort();
    peers.dedup();
    let current = state.dynamic_peers.load();
    if **current != peers {
        info!(
            "mesh peer list updated via heartbeat: {} peer(s)",
            peers.len()
        );
        state.dynamic_peers.store(std::sync::Arc::new(peers));
    }
}

fn basic_auth(client_id: &str, client_secret: &str) -> String {
    format!(
        "Basic {}",
        STANDARD.encode(format!("{client_id}:{client_secret}"))
    )
}

fn http_client() -> reqwest::Client {
    reqwest::Client::builder()
        .connect_timeout(CONNECT_TIMEOUT)
        .timeout(REQUEST_TIMEOUT)
        .build()
        .expect("mesh heartbeat HTTP client should build")
}

#[cfg(test)]
mod tests {
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
        let heartbeat: MeshHeartbeatResponse = serde_json::from_str("{}").expect("should decode");
        assert!(!heartbeat.mesh_member);
        assert!(heartbeat.peers.is_empty());
        assert_eq!(heartbeat.heartbeat_interval_seconds, None);

        let peers: MeshPeersResponse = serde_json::from_str("{}").expect("should decode");
        assert!(peers.peers.is_empty());
        assert_eq!(peers.refresh_interval_seconds, None);
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
        ctx.state.note_bootstrap_succeeded(&peer).await;
        assert!(ctx.state.peers_needing_bootstrap().await.is_empty());

        ctx.state.reset_bootstrap_progress().await;
        assert_eq!(ctx.state.peers_needing_bootstrap().await, vec![peer]);
    }

    #[test]
    fn recovery_backoff_gates_attempts_and_grows() {
        let mut backoff = RecoveryBackoff::new();
        let start = Instant::now();

        assert!(backoff.should_attempt(start));
        assert!(!backoff.should_attempt(start));
        assert!(!backoff.should_attempt(start + RECOVERY_BACKOFF_INITIAL / 2));
        assert!(backoff.should_attempt(start + RECOVERY_BACKOFF_INITIAL));
        // Second success window doubles.
        assert!(
            !backoff.should_attempt(start + RECOVERY_BACKOFF_INITIAL + Duration::from_secs(90))
        );

        backoff.reset();
        assert!(backoff.should_attempt(start + RECOVERY_BACKOFF_INITIAL + Duration::from_secs(90)));
    }
}
