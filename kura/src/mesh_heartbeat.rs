//! Mesh-membership heartbeat against the Tuist control plane.
//!
//! Enrolled nodes periodically prove they are still live mesh members: the
//! control plane withholds peers that stop heartbeating from the mesh and
//! reactivates them on their next heartbeat, so this loop is what keeps the
//! node receiving replication traffic. The response carries the current peer
//! list, so peer discovery refreshes at heartbeat cadence instead of at
//! certificate renewal. Independent from the registration heartbeat
//! (`src/registration.rs`), which advertises the node's client-facing cache
//! endpoint for CLI routing — a node can do either without the other.
//!
//! The URL is derived from `KURA_CONTROL_PLANE_URL` like enrollment's,
//! because the heartbeat only exists inside a control-plane relationship:
//! it maintains the membership that enrollment created.

use std::time::Duration;

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD;
use reqwest::header::AUTHORIZATION;
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

use crate::state::SharedState;

const HEARTBEAT_PATH: &str = "/_internal/kura/mesh/heartbeat";

const KURA_CONTROL_PLANE_URL: &str = "KURA_CONTROL_PLANE_URL";
const KURA_CONTROL_PLANE_CLIENT_ID: &str = "KURA_CONTROL_PLANE_CLIENT_ID";
const KURA_CONTROL_PLANE_CLIENT_SECRET: &str = "KURA_CONTROL_PLANE_CLIENT_SECRET";

const DEFAULT_INTERVAL_MS: u64 = 60_000;

pub struct MeshHeartbeatConfig {
    pub heartbeat_url: String,
    pub client_id: String,
    pub client_secret: String,
    pub node_url: String,
    pub interval: Duration,
}

impl MeshHeartbeatConfig {
    /// Builds the config from the environment, or `None` when the
    /// control-plane settings are unset. The loop is only spawned for nodes
    /// that enrolled on boot, and enrollment requires the same variables, so
    /// an enrolled node always heartbeats.
    pub fn from_env(node_url: &str) -> Option<Self> {
        let control_plane_url = non_empty(KURA_CONTROL_PLANE_URL)?;
        let client_id = non_empty(KURA_CONTROL_PLANE_CLIENT_ID)?;
        let client_secret = non_empty(KURA_CONTROL_PLANE_CLIENT_SECRET)?;

        Some(Self {
            heartbeat_url: format!(
                "{}{HEARTBEAT_PATH}",
                control_plane_url.trim_end_matches('/')
            ),
            client_id,
            client_secret,
            node_url: node_url.to_owned(),
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

pub fn spawn(state: SharedState, config: MeshHeartbeatConfig) {
    info!(
        "sending mesh heartbeats to control plane at {}",
        config.heartbeat_url
    );
    tokio::spawn(async move { run(state, config).await });
}

async fn run(state: SharedState, mut config: MeshHeartbeatConfig) {
    let client = reqwest::Client::new();

    loop {
        match send_heartbeat(&client, &state, &config).await {
            // The cadence is control-plane advertised, like the registration
            // lease, so the server can retune it without a node release.
            Ok(Some(seconds)) if seconds > 0 => {
                config.interval = Duration::from_secs(seconds);
            }
            Ok(_) => {}
            Err(error) => warn!("mesh heartbeat failed: {error}"),
        }
        tokio::time::sleep(config.interval).await;
    }
}

async fn send_heartbeat(
    client: &reqwest::Client,
    state: &SharedState,
    config: &MeshHeartbeatConfig,
) -> Result<Option<u64>, String> {
    let auth = STANDARD.encode(format!("{}:{}", config.client_id, config.client_secret));

    let response = client
        .post(&config.heartbeat_url)
        .header(AUTHORIZATION.as_str(), format!("Basic {auth}"))
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

    if !payload.mesh_member {
        // Heartbeats never create membership; only enrollment does. The
        // renewal task (or a reboot) re-enrolls and recreates it.
        warn!(
            "control plane reports this node is not a mesh member; membership is restored at the next enrollment"
        );
    }

    apply_peers(state, payload.peers);

    Ok(payload.heartbeat_interval_seconds)
}

fn apply_peers(state: &SharedState, peers: Vec<String>) {
    let current = state.dynamic_peers.load();
    if **current != peers {
        info!(
            "mesh peer list updated via heartbeat: {} peer(s)",
            peers.len()
        );
        state.dynamic_peers.store(std::sync::Arc::new(peers));
    }
}

fn non_empty(name: &str) -> Option<String> {
    std::env::var(name)
        .ok()
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
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

    #[test]
    fn response_tolerates_missing_optional_fields() {
        let payload: MeshHeartbeatResponse = serde_json::from_str("{}").expect("should decode");
        assert!(!payload.mesh_member);
        assert!(payload.peers.is_empty());
        assert_eq!(payload.heartbeat_interval_seconds, None);
    }
}
