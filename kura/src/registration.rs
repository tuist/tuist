//! Generic control-plane registration heartbeats.
//!
//! When `KURA_REGISTRATION_URL` and `KURA_ADVERTISED_HTTP_URL` are configured,
//! the node periodically POSTs a heartbeat advertising its client-facing HTTP
//! cache endpoint and runtime state to the configured control plane. The control
//! plane leases the registration and stops advertising the endpoint when the
//! heartbeats stop, so a dead node disappears without the control plane probing
//! it.
//!
//! The payload is intentionally control-plane agnostic: generic field names, no
//! Tuist-specific route or types. The registration URL is absolute so the node
//! never derives a control-plane route.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use reqwest::Client;
use reqwest::header::AUTHORIZATION;
use serde::Serialize;
use tokio::time::{MissedTickBehavior, interval};
use tracing::{info, warn};

use crate::state::SharedState;

const KURA_REGISTRATION_URL: &str = "KURA_REGISTRATION_URL";
const KURA_ADVERTISED_HTTP_URL: &str = "KURA_ADVERTISED_HTTP_URL";
const KURA_CONTROL_PLANE_CLIENT_ID: &str = "KURA_CONTROL_PLANE_CLIENT_ID";
const KURA_CONTROL_PLANE_CLIENT_SECRET: &str = "KURA_CONTROL_PLANE_CLIENT_SECRET";
const KURA_TENANT_ID: &str = "KURA_TENANT_ID";
const KURA_REGION: &str = "KURA_REGION";
const KURA_REGISTRATION_INTERVAL_MS: &str = "KURA_REGISTRATION_INTERVAL_MS";

const DEFAULT_INTERVAL_MS: u64 = 60_000;
const SCHEMA_VERSION: u32 = 1;

#[derive(Clone, Debug)]
pub struct RegistrationConfig {
    pub registration_url: String,
    pub advertised_http_url: String,
    pub client_id: String,
    pub client_secret: String,
    pub tenant_id: String,
    pub region: Option<String>,
    pub node_id: String,
    pub interval: Duration,
}

impl RegistrationConfig {
    /// Builds a registration config from the environment, or `None` when the
    /// node is not configured to register (the registration URL or advertised
    /// HTTP URL is unset). `node_id` is derived from the node's peer URL host so
    /// it is stable across restarts of the same node.
    pub fn from_env(node_url: &str) -> Option<Self> {
        let registration_url = non_empty(KURA_REGISTRATION_URL)?;
        let advertised_http_url = non_empty(KURA_ADVERTISED_HTTP_URL)?;
        let client_id = non_empty(KURA_CONTROL_PLANE_CLIENT_ID)?;
        let client_secret = non_empty(KURA_CONTROL_PLANE_CLIENT_SECRET)?;
        let tenant_id = non_empty(KURA_TENANT_ID)?;

        let interval_ms = non_empty(KURA_REGISTRATION_INTERVAL_MS)
            .and_then(|value| value.parse::<u64>().ok())
            .filter(|ms| *ms > 0)
            .unwrap_or(DEFAULT_INTERVAL_MS);

        Some(Self {
            registration_url,
            advertised_http_url,
            client_id,
            client_secret,
            tenant_id,
            region: non_empty(KURA_REGION),
            node_id: node_id_from_url(node_url),
            interval: Duration::from_millis(interval_ms),
        })
    }
}

#[derive(Serialize)]
struct RegistrationHeartbeat<'a> {
    schema_version: u32,
    node_id: &'a str,
    tenant_id: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    region: Option<&'a str>,
    advertised_http_url: &'a str,
    ready: bool,
    version: &'a str,
    traffic_state: &'a str,
    ring_members: usize,
    writer_lock_owned: bool,
    observed_at_unix_seconds: u64,
}

pub fn spawn(state: SharedState, config: RegistrationConfig) {
    info!(
        "registering with control plane at {} (advertising {})",
        config.registration_url, config.advertised_http_url
    );
    tokio::spawn(async move { run(state, config).await });
}

async fn run(state: SharedState, config: RegistrationConfig) {
    let client = Client::new();
    let mut ticker = interval(config.interval);
    ticker.set_missed_tick_behavior(MissedTickBehavior::Skip);

    loop {
        ticker.tick().await;
        if let Err(error) = send_heartbeat(&client, &state, &config).await {
            warn!("registration heartbeat failed: {error}");
        }
    }
}

async fn send_heartbeat(
    client: &Client,
    state: &SharedState,
    config: &RegistrationConfig,
) -> Result<(), String> {
    let report = state.readiness_report().await;

    let payload = RegistrationHeartbeat {
        schema_version: SCHEMA_VERSION,
        node_id: &config.node_id,
        tenant_id: &config.tenant_id,
        region: config.region.as_deref(),
        advertised_http_url: &config.advertised_http_url,
        ready: report.ready,
        version: env!("CARGO_PKG_VERSION"),
        traffic_state: report.state.as_str(),
        ring_members: report.known_peers.len() + 1,
        writer_lock_owned: report.writer_lock_owned,
        observed_at_unix_seconds: now_unix_seconds(),
    };

    let auth = STANDARD.encode(format!("{}:{}", config.client_id, config.client_secret));

    let response = client
        .post(&config.registration_url)
        .header(AUTHORIZATION.as_str(), format!("Basic {auth}"))
        .json(&payload)
        .send()
        .await
        .map_err(|error| format!("request failed: {error}"))?;

    if response.status().is_success() {
        Ok(())
    } else {
        Err(format!("control plane returned {}", response.status()))
    }
}

fn node_id_from_url(node_url: &str) -> String {
    reqwest::Url::parse(node_url)
        .ok()
        .and_then(|url| url.host_str().map(str::to_owned))
        .unwrap_or_else(|| node_url.to_owned())
}

fn non_empty(key: &str) -> Option<String> {
    std::env::var(key).ok().filter(|value| !value.is_empty())
}

fn now_unix_seconds() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn node_id_uses_host_when_url_is_parseable() {
        assert_eq!(
            node_id_from_url("https://kura-0.acme.internal:7443"),
            "kura-0.acme.internal"
        );
    }

    #[test]
    fn node_id_falls_back_to_raw_string_for_unparseable_url() {
        assert_eq!(node_id_from_url("not a url"), "not a url");
    }

    #[test]
    fn heartbeat_serializes_generic_fields_only() {
        let payload = RegistrationHeartbeat {
            schema_version: SCHEMA_VERSION,
            node_id: "kura-0",
            tenant_id: "acme",
            region: Some("us-office"),
            advertised_http_url: "https://cache.acme.internal",
            ready: true,
            version: "0.0.0",
            traffic_state: "serving",
            ring_members: 3,
            writer_lock_owned: true,
            observed_at_unix_seconds: 1,
        };

        let json = serde_json::to_string(&payload).expect("serializes");
        assert!(json.contains("\"advertised_http_url\":\"https://cache.acme.internal\""));
        assert!(json.contains("\"tenant_id\":\"acme\""));
        assert!(!json.to_lowercase().contains("tuist"));
    }
}
