use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use axum::http::header::AUTHORIZATION;
use base64::{Engine, engine::general_purpose::STANDARD};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tokio::time::{MissedTickBehavior, interval, sleep};
use tracing::warn;

use crate::{config::UsageConfig, metrics::Metrics, state::SharedState};

const USAGE_PATH: &str = "/_internal/kura/usage";

#[derive(Clone)]
pub struct Usage {
    inner: Arc<UsageInner>,
}

struct UsageInner {
    config: UsageConfig,
    node_id: String,
    region: String,
    metrics: Metrics,
    buckets: Mutex<HashMap<UsageBucketKey, UsageBucket>>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct UsageRollup {
    pub event_id: String,
    pub tenant_id: String,
    pub namespace_id: String,
    pub window_start_unix_seconds: u64,
    pub window_seconds: u64,
    pub node_id: String,
    pub region: String,
    pub traffic_plane: String,
    pub direction: String,
    pub operation: String,
    pub protocol: String,
    pub artifact_kind: String,
    pub bytes: u64,
    pub request_count: u64,
}

#[derive(Clone, Debug, Serialize)]
struct UsageBatch {
    schema_version: u8,
    node_id: String,
    region: String,
    events: Vec<UsageRollup>,
}

#[derive(Clone, Debug, Hash, PartialEq, Eq)]
struct UsageBucketKey {
    tenant_id: String,
    namespace_id: String,
    window_start_unix_seconds: u64,
    traffic_plane: &'static str,
    direction: &'static str,
    operation: &'static str,
    protocol: &'static str,
    artifact_kind: &'static str,
}

#[derive(Clone, Debug, Default)]
struct UsageBucket {
    bytes: u64,
    request_count: u64,
}

impl Usage {
    pub fn from_config(
        config: Option<&UsageConfig>,
        node_url: &str,
        metrics: Metrics,
    ) -> Result<Option<Self>, String> {
        let Some(config) = config.cloned() else {
            return Ok(None);
        };

        Ok(Some(Self {
            inner: Arc::new(UsageInner {
                config,
                node_id: usage_node_id(node_url),
                region: metrics.region().to_owned(),
                metrics,
                buckets: Mutex::new(HashMap::new()),
            }),
        }))
    }

    pub fn spawn_tasks(state: SharedState) {
        if state.usage.is_none() {
            return;
        }

        tokio::spawn(flush_loop(state.clone()));
        tokio::spawn(delivery_loop(state));
    }

    pub fn record_public_download(
        &self,
        tenant_id: &str,
        namespace_id: &str,
        artifact_kind: &'static str,
        bytes: u64,
    ) {
        self.record(
            tenant_id,
            namespace_id,
            "public",
            "egress",
            "download",
            "http",
            artifact_kind,
            bytes,
        );
    }

    pub fn record_public_upload(
        &self,
        tenant_id: &str,
        namespace_id: &str,
        artifact_kind: &'static str,
        bytes: u64,
    ) {
        self.record(
            tenant_id,
            namespace_id,
            "public",
            "ingress",
            "upload",
            "http",
            artifact_kind,
            bytes,
        );
    }

    #[allow(clippy::too_many_arguments)]
    fn record(
        &self,
        tenant_id: &str,
        namespace_id: &str,
        traffic_plane: &'static str,
        direction: &'static str,
        operation: &'static str,
        protocol: &'static str,
        artifact_kind: &'static str,
        bytes: u64,
    ) {
        let now = unix_seconds();
        let window_start_unix_seconds = now - (now % self.inner.config.window_secs.max(1));
        let key = UsageBucketKey {
            tenant_id: tenant_id.to_owned(),
            namespace_id: namespace_id.to_owned(),
            window_start_unix_seconds,
            traffic_plane,
            direction,
            operation,
            protocol,
            artifact_kind,
        };

        let mut buckets = self.inner.buckets.lock().expect("usage buckets poisoned");
        if buckets.len() >= self.inner.config.max_buckets && !buckets.contains_key(&key) {
            self.inner
                .metrics
                .record_memory_action("usage_bucket_rejected");
            return;
        }

        let bucket = buckets.entry(key).or_default();
        bucket.bytes = bucket.bytes.saturating_add(bytes);
        bucket.request_count = bucket.request_count.saturating_add(1);
    }

    fn closed_rollups(&self) -> Vec<(UsageBucketKey, UsageRollup)> {
        let now = unix_seconds();
        let current_window = now - (now % self.inner.config.window_secs.max(1));
        let buckets = self.inner.buckets.lock().expect("usage buckets poisoned");
        let closed_keys = buckets
            .keys()
            .filter(|key| key.window_start_unix_seconds < current_window)
            .cloned()
            .collect::<Vec<_>>();

        closed_keys
            .into_iter()
            .filter_map(|key| {
                buckets.get(&key).map(|bucket| {
                    let event_id = format!(
                        "{}:{}:{}:{}:{}:{}:{}:{}:{}",
                        self.inner.node_id,
                        key.window_start_unix_seconds,
                        key.tenant_id,
                        key.namespace_id,
                        key.traffic_plane,
                        key.direction,
                        key.operation,
                        key.protocol,
                        key.artifact_kind
                    );
                    let rollup = UsageRollup {
                        event_id,
                        tenant_id: key.tenant_id.clone(),
                        namespace_id: key.namespace_id.clone(),
                        window_start_unix_seconds: key.window_start_unix_seconds,
                        window_seconds: self.inner.config.window_secs,
                        node_id: self.inner.node_id.clone(),
                        region: self.inner.region.clone(),
                        traffic_plane: key.traffic_plane.to_owned(),
                        direction: key.direction.to_owned(),
                        operation: key.operation.to_owned(),
                        protocol: key.protocol.to_owned(),
                        artifact_kind: key.artifact_kind.to_owned(),
                        bytes: bucket.bytes,
                        request_count: bucket.request_count,
                    };
                    (key, rollup)
                })
            })
            .collect()
    }

    fn remove_buckets(&self, keys: &[UsageBucketKey]) {
        let mut buckets = self.inner.buckets.lock().expect("usage buckets poisoned");
        for key in keys {
            buckets.remove(key);
        }
    }
}

async fn flush_loop(state: SharedState) {
    let mut ticker = interval(Duration::from_millis(
        state
            .config
            .usage
            .as_ref()
            .expect("usage config should exist")
            .flush_interval_ms,
    ));
    ticker.set_missed_tick_behavior(MissedTickBehavior::Delay);

    loop {
        ticker.tick().await;
        let Some(usage) = state.usage.as_ref() else {
            return;
        };

        match state.store.usage_outbox_message_count() {
            Ok(depth) if depth >= usage.inner.config.outbox_max_depth => {
                state.metrics.record_memory_action("usage_outbox_full");
                continue;
            }
            Err(error) => {
                warn!("failed to inspect usage outbox depth: {error}");
                continue;
            }
            _ => {}
        }

        let closed_rollups = usage.closed_rollups();
        if closed_rollups.is_empty() {
            continue;
        }

        let keys = closed_rollups
            .iter()
            .map(|(key, _)| key.clone())
            .collect::<Vec<_>>();
        let rollups = closed_rollups
            .into_iter()
            .map(|(_, rollup)| rollup)
            .collect::<Vec<_>>();

        if let Err(error) = state.store.append_usage_rollups(&rollups) {
            warn!("failed to persist usage rollups: {error}");
        } else {
            usage.remove_buckets(&keys);
        }
    }
}

async fn delivery_loop(state: SharedState) {
    let client = match Client::builder()
        .connect_timeout(Duration::from_millis(500))
        .timeout(Duration::from_millis(5_000))
        .build()
    {
        Ok(client) => client,
        Err(error) => {
            warn!("failed to build usage delivery client: {error}");
            return;
        }
    };

    loop {
        if state.memory.pause_outbox() {
            state
                .metrics
                .update_background_work_paused("usage_outbox", true);
            sleep(Duration::from_millis(
                state
                    .config
                    .usage
                    .as_ref()
                    .expect("usage config should exist")
                    .delivery_interval_ms,
            ))
            .await;
            continue;
        }
        state
            .metrics
            .update_background_work_paused("usage_outbox", false);

        if let Err(error) = deliver_once(&state, &client).await {
            warn!("usage delivery failed: {error}");
        }

        sleep(Duration::from_millis(
            state
                .config
                .usage
                .as_ref()
                .expect("usage config should exist")
                .delivery_interval_ms,
        ))
        .await;
    }
}

async fn deliver_once(state: &SharedState, client: &Client) -> Result<(), String> {
    let config = state
        .config
        .usage
        .as_ref()
        .ok_or_else(|| "usage config missing".to_string())?;
    let rollups = state.store.next_usage_rollups(config.batch_size)?;
    if rollups.is_empty() {
        return Ok(());
    }

    let keys = rollups
        .iter()
        .map(|(key, _)| key.clone())
        .collect::<Vec<_>>();
    let events = rollups
        .into_iter()
        .map(|(_, rollup)| rollup)
        .collect::<Vec<_>>();
    let url = format!("{}{}", config.control_plane_url, USAGE_PATH);
    let auth = STANDARD.encode(format!("{}:{}", config.client_id, config.client_secret));
    let response = client
        .post(url)
        .header(AUTHORIZATION.as_str(), format!("Basic {auth}"))
        .json(&UsageBatch {
            schema_version: 1,
            node_id: state
                .usage
                .as_ref()
                .expect("usage should exist")
                .inner
                .node_id
                .clone(),
            region: state.config.region.clone(),
            events,
        })
        .send()
        .await
        .map_err(|error| format!("request failed: {error}"))?;

    if response.status().is_success() {
        state.store.delete_usage_rollups(&keys)?;
        Ok(())
    } else {
        Err(format!("server returned {}", response.status()))
    }
}

fn usage_node_id(node_url: &str) -> String {
    reqwest::Url::parse(node_url)
        .ok()
        .and_then(|url| url.host_str().map(ToOwned::to_owned))
        .unwrap_or_else(|| node_url.to_owned())
}

fn unix_seconds() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
