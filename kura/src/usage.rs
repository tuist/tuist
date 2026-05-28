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

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config(window_secs: u64, max_buckets: usize) -> UsageConfig {
        UsageConfig {
            control_plane_url: "http://localhost:0".to_owned(),
            client_id: "kura".to_owned(),
            client_secret: "secret".to_owned(),
            window_secs,
            flush_interval_ms: 1_000,
            delivery_interval_ms: 1_000,
            batch_size: 100,
            max_buckets,
            outbox_max_depth: 100,
        }
    }

    fn test_usage(window_secs: u64, max_buckets: usize) -> Usage {
        let metrics = Metrics::new("test-region".to_owned(), "test-tenant".to_owned());
        Usage::from_config(
            Some(&test_config(window_secs, max_buckets)),
            "http://node-1.kura.local",
            metrics,
        )
        .expect("usage config valid")
        .expect("usage enabled when config present")
    }

    fn bucket_key(tenant: &str, namespace: &str, window_start: u64) -> UsageBucketKey {
        UsageBucketKey {
            tenant_id: tenant.to_owned(),
            namespace_id: namespace.to_owned(),
            window_start_unix_seconds: window_start,
            traffic_plane: "public",
            direction: "egress",
            operation: "download",
            protocol: "http",
            artifact_kind: "xcframework",
        }
    }

    #[test]
    fn from_config_returns_none_when_unconfigured() {
        let metrics = Metrics::new("region".into(), "tenant".into());
        let usage = Usage::from_config(None, "http://node.kura.local", metrics).unwrap();
        assert!(usage.is_none());
    }

    #[test]
    fn usage_node_id_uses_host_when_url_is_parseable() {
        assert_eq!(
            usage_node_id("http://node-1.kura.local"),
            "node-1.kura.local"
        );
        assert_eq!(
            usage_node_id("https://node-2.kura.local:8443/path"),
            "node-2.kura.local"
        );
    }

    #[test]
    fn usage_node_id_falls_back_to_raw_string_for_unparseable_url() {
        assert_eq!(usage_node_id("not a url"), "not a url");
    }

    #[test]
    fn record_accumulates_bytes_and_request_count_into_existing_bucket() {
        let usage = test_usage(60, 100);

        usage.record_public_download("acme", "ios", "xcframework", 100);
        usage.record_public_download("acme", "ios", "xcframework", 250);
        usage.record_public_download("acme", "ios", "xcframework", 50);

        let buckets = usage.inner.buckets.lock().unwrap();
        assert_eq!(buckets.len(), 1);
        let bucket = buckets.values().next().unwrap();
        assert_eq!(bucket.bytes, 400);
        assert_eq!(bucket.request_count, 3);
    }

    #[test]
    fn record_keeps_separate_buckets_per_tenant_namespace() {
        let usage = test_usage(60, 100);

        usage.record_public_download("acme", "ios", "xcframework", 100);
        usage.record_public_download("acme", "android", "xcframework", 200);
        usage.record_public_upload("acme", "ios", "xcframework", 300);

        let buckets = usage.inner.buckets.lock().unwrap();
        assert_eq!(buckets.len(), 3);
    }

    #[test]
    fn record_rejects_new_keys_once_max_buckets_reached() {
        let usage = test_usage(60, 2);

        usage.record_public_download("acme", "ios", "xcframework", 1);
        usage.record_public_download("acme", "android", "xcframework", 1);
        // Third unique key — rejected.
        usage.record_public_download("globex", "ios", "xcframework", 1);
        // Existing keys still accumulate.
        usage.record_public_download("acme", "ios", "xcframework", 9);

        let buckets = usage.inner.buckets.lock().unwrap();
        assert_eq!(buckets.len(), 2);
        let key = bucket_key(
            "acme",
            "ios",
            buckets.keys().next().unwrap().window_start_unix_seconds,
        );
        let acme_ios = buckets.get(&key).unwrap();
        assert_eq!(acme_ios.bytes, 10);
        assert!(!buckets.keys().any(|k| k.tenant_id == "globex"));
    }

    #[test]
    fn record_uses_saturating_add_on_overflow() {
        let usage = test_usage(60, 100);

        usage.record_public_download("acme", "ios", "xcframework", u64::MAX - 5);
        usage.record_public_download("acme", "ios", "xcframework", 100);

        let buckets = usage.inner.buckets.lock().unwrap();
        let bucket = buckets.values().next().unwrap();
        assert_eq!(bucket.bytes, u64::MAX);
        assert_eq!(bucket.request_count, 2);
    }

    #[test]
    fn closed_rollups_only_returns_buckets_for_past_windows() {
        let usage = test_usage(60, 100);
        let now = unix_seconds();
        let current_window = now - (now % 60);
        let past_window = current_window - 60;

        {
            let mut buckets = usage.inner.buckets.lock().unwrap();
            buckets.insert(
                bucket_key("acme", "ios", past_window),
                UsageBucket {
                    bytes: 1_000,
                    request_count: 5,
                },
            );
            buckets.insert(
                bucket_key("acme", "android", current_window),
                UsageBucket {
                    bytes: 2_000,
                    request_count: 7,
                },
            );
        }

        let rollups = usage.closed_rollups();
        assert_eq!(rollups.len(), 1);
        let (_, rollup) = &rollups[0];
        assert_eq!(rollup.namespace_id, "ios");
        assert_eq!(rollup.bytes, 1_000);
        assert_eq!(rollup.request_count, 5);
        assert_eq!(rollup.window_start_unix_seconds, past_window);
        assert_eq!(rollup.window_seconds, 60);
        assert_eq!(rollup.region, "test-region");
        assert_eq!(rollup.node_id, "node-1.kura.local");
    }

    #[test]
    fn closed_rollups_event_id_is_deterministic() {
        let usage = test_usage(60, 100);
        let past_window = (unix_seconds() / 60 - 1) * 60;
        let key = bucket_key("acme", "ios", past_window);

        {
            let mut buckets = usage.inner.buckets.lock().unwrap();
            buckets.insert(
                key.clone(),
                UsageBucket {
                    bytes: 10,
                    request_count: 1,
                },
            );
        }

        let first = usage.closed_rollups();
        let second = usage.closed_rollups();

        assert_eq!(first.len(), 1);
        assert_eq!(second.len(), 1);
        assert_eq!(first[0].1.event_id, second[0].1.event_id);
        let expected = format!(
            "node-1.kura.local:{past_window}:acme:ios:public:egress:download:http:xcframework"
        );
        assert_eq!(first[0].1.event_id, expected);
    }

    #[test]
    fn remove_buckets_drops_only_the_specified_keys() {
        let usage = test_usage(60, 100);
        let now = unix_seconds();
        let past_window = now - (now % 60) - 60;

        let acme_key = bucket_key("acme", "ios", past_window);
        let globex_key = bucket_key("globex", "ios", past_window);

        {
            let mut buckets = usage.inner.buckets.lock().unwrap();
            buckets.insert(
                acme_key.clone(),
                UsageBucket {
                    bytes: 1,
                    request_count: 1,
                },
            );
            buckets.insert(
                globex_key.clone(),
                UsageBucket {
                    bytes: 1,
                    request_count: 1,
                },
            );
        }

        usage.remove_buckets(std::slice::from_ref(&acme_key));

        let buckets = usage.inner.buckets.lock().unwrap();
        assert!(!buckets.contains_key(&acme_key));
        assert!(buckets.contains_key(&globex_key));
    }
}
