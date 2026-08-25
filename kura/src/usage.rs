use std::{
    collections::{HashMap, VecDeque},
    sync::{Arc, Mutex},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use axum::http::header::AUTHORIZATION;
use base64::{Engine, engine::general_purpose::STANDARD};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tokio::time::{MissedTickBehavior, interval, sleep};
use tracing::warn;

use crate::{
    config::UsageConfig,
    metrics::Metrics,
    state::SharedState,
    store::{CapacityEviction, StorageSnapshotData},
};

const USAGE_PATH: &str = "/_internal/kura/usage";
const USAGE_CONNECT_TIMEOUT: Duration = Duration::from_secs(1);
const USAGE_REQUEST_TIMEOUT: Duration = Duration::from_secs(5);
// Eviction reports awaiting a successful delivery. In memory only: the claim
// sizing policy reads weeks of aggregates, so reports lost to a restart are
// noise, and keeping them off the durable outbox keeps the on-disk format
// untouched.
const MAX_UNDELIVERED_EVICTIONS: usize = 8_192;
// Per-delivery ceiling, well under the control plane's 5,000-events-per-array
// cap. The queue can legally hold more than the server accepts in one request
// (its cap is above this), so an uncapped delivery after a few failed cycles
// would be refused as too large forever, wedging the whole usage channel.
const MAX_EVICTIONS_PER_DELIVERY: usize = 1_000;
const STORAGE_SNAPSHOT_INTERVAL: Duration = Duration::from_secs(900);

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
    undelivered_evictions: Mutex<VecDeque<SegmentEvictionEvent>>,
    last_snapshot_at: Mutex<Option<Instant>>,
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

/// One ring-rotation eviction as it crosses the wire. `reason` is always
/// `"capacity"` today; it exists so a future non-capacity eviction cannot be
/// mistaken for churn by an older control plane.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct SegmentEvictionEvent {
    pub event_id: String,
    pub tenant_id: String,
    pub node_id: String,
    pub region: String,
    pub segment_id: String,
    pub reason: String,
    pub evicted_at_unix_ms: u64,
    pub segment_created_at_unix_ms: u64,
    pub newest_content_at_unix_ms: u64,
    pub artifact_count: u64,
    pub bytes: u64,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct StorageSnapshot {
    pub event_id: String,
    pub tenant_id: String,
    pub node_id: String,
    pub region: String,
    pub captured_at_unix_ms: u64,
    pub ring_budget_bytes: u64,
    pub desired_segment_count: u64,
    pub live_segment_count: u64,
    pub live_segment_bytes: u64,
    pub oldest_segment_created_at_unix_ms: Option<u64>,
    pub newest_content_at_unix_ms: Option<u64>,
}

// The eviction and snapshot fields are additive: skipping them when empty
// keeps the payload byte-identical to the pre-existing shape, and a control
// plane that predates them ignores unknown keys.
#[derive(Clone, Debug, Serialize)]
struct UsageBatch {
    schema_version: u8,
    node_id: String,
    region: String,
    events: Vec<UsageRollup>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    evictions: Vec<SegmentEvictionEvent>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    storage_snapshots: Vec<StorageSnapshot>,
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
                undelivered_evictions: Mutex::new(VecDeque::new()),
                last_snapshot_at: Mutex::new(None),
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

    pub fn record_public_grpc_download(
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
            "grpc",
            artifact_kind,
            bytes,
        );
    }

    pub fn record_public_grpc_upload(
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
            "grpc",
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
                buckets
                    .get(&key)
                    .map(|bucket| (key.clone(), self.rollup_for_bucket(&key, bucket)))
            })
            .collect()
    }

    fn rollup_for_bucket(&self, key: &UsageBucketKey, bucket: &UsageBucket) -> UsageRollup {
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

        UsageRollup {
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
        }
    }

    fn remove_buckets(&self, keys: &[UsageBucketKey]) {
        let mut buckets = self.inner.buckets.lock().expect("usage buckets poisoned");
        for key in keys {
            buckets.remove(key);
        }
    }

    fn stash_evictions(&self, tenant_id: &str, evictions: Vec<CapacityEviction>) {
        if evictions.is_empty() {
            return;
        }
        let mut undelivered = self
            .inner
            .undelivered_evictions
            .lock()
            .expect("undelivered evictions poisoned");
        for eviction in evictions {
            while undelivered.len() >= MAX_UNDELIVERED_EVICTIONS {
                undelivered.pop_front();
                self.inner.metrics.record_capacity_eviction_report_dropped();
            }
            undelivered.push_back(eviction_event(
                tenant_id,
                &self.inner.node_id,
                &self.inner.region,
                eviction,
            ));
        }
    }

    /// The front of the queue, at most `limit` reports: what one delivery may
    /// carry. The remainder waits for the next delivery cycle rather than
    /// growing a request past what the control plane accepts.
    fn undelivered_evictions(&self, limit: usize) -> Vec<SegmentEvictionEvent> {
        self.inner
            .undelivered_evictions
            .lock()
            .expect("undelivered evictions poisoned")
            .iter()
            .take(limit)
            .cloned()
            .collect()
    }

    /// Drops the front `count` reports after a delivery covering them
    /// succeeded. Reports stashed since the covered batch was built sit behind
    /// them and survive for the next delivery.
    fn discard_delivered_evictions(&self, count: usize) {
        let mut undelivered = self
            .inner
            .undelivered_evictions
            .lock()
            .expect("undelivered evictions poisoned");
        let covered = count.min(undelivered.len());
        undelivered.drain(..covered);
    }

    fn storage_snapshot_due(&self) -> bool {
        self.inner
            .last_snapshot_at
            .lock()
            .expect("last snapshot poisoned")
            .is_none_or(|at| at.elapsed() >= STORAGE_SNAPSHOT_INTERVAL)
    }

    fn mark_snapshot_delivered(&self) {
        *self
            .inner
            .last_snapshot_at
            .lock()
            .expect("last snapshot poisoned") = Some(Instant::now());
    }

    fn storage_snapshot_event(
        &self,
        tenant_id: &str,
        data: StorageSnapshotData,
        captured_at_unix_seconds: u64,
    ) -> StorageSnapshot {
        let window = captured_at_unix_seconds / STORAGE_SNAPSHOT_INTERVAL.as_secs().max(1);
        StorageSnapshot {
            event_id: format!("snapshot:{}:{}", self.inner.node_id, window),
            tenant_id: tenant_id.to_owned(),
            node_id: self.inner.node_id.clone(),
            region: self.inner.region.clone(),
            captured_at_unix_ms: captured_at_unix_seconds * 1_000,
            ring_budget_bytes: data.ring_budget_bytes,
            desired_segment_count: data.desired_segment_count,
            live_segment_count: data.live_segment_count,
            live_segment_bytes: data.live_segment_bytes,
            oldest_segment_created_at_unix_ms: data.oldest_segment_created_at_ms,
            newest_content_at_unix_ms: data.newest_content_at_ms,
        }
    }

    #[cfg(test)]
    pub(crate) fn current_rollups_for_tests(&self) -> Vec<UsageRollup> {
        let buckets = self.inner.buckets.lock().expect("usage buckets poisoned");

        buckets
            .iter()
            .map(|(key, bucket)| self.rollup_for_bucket(key, bucket))
            .collect()
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
        .connect_timeout(USAGE_CONNECT_TIMEOUT)
        .timeout(USAGE_REQUEST_TIMEOUT)
        .build()
    {
        Ok(client) => client,
        Err(error) => {
            warn!("failed to build usage delivery client: {error}");
            return;
        }
    };

    loop {
        if state.memory.pause_usage_outbox() {
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
    let usage = state.usage.as_ref().expect("usage should exist");
    usage.stash_evictions(
        &state.config.tenant_id,
        state.store.take_pending_capacity_evictions(),
    );

    let rollups = state.store.next_usage_rollups(config.batch_size)?;
    let evictions = usage.undelivered_evictions(MAX_EVICTIONS_PER_DELIVERY);
    let storage_snapshots = if usage.storage_snapshot_due() {
        vec![usage.storage_snapshot_event(
            &state.config.tenant_id,
            state.store.storage_snapshot(),
            unix_seconds(),
        )]
    } else {
        Vec::new()
    };

    if rollups.is_empty() && evictions.is_empty() && storage_snapshots.is_empty() {
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
    let delivered_evictions = evictions.len();
    let delivered_snapshot = !storage_snapshots.is_empty();
    let response = client
        .post(url)
        .header(AUTHORIZATION.as_str(), format!("Basic {auth}"))
        .json(&UsageBatch {
            schema_version: 1,
            node_id: usage.inner.node_id.clone(),
            region: state.config.region.clone(),
            events,
            evictions,
            storage_snapshots,
        })
        .send()
        .await
        .map_err(|error| format!("request failed: {error:?}"))?;

    if response.status().is_success() {
        state.store.delete_usage_rollups(&keys)?;
        usage.discard_delivered_evictions(delivered_evictions);
        if delivered_snapshot {
            usage.mark_snapshot_delivered();
        }
        Ok(())
    } else {
        Err(format!("server returned {}", response.status()))
    }
}

fn eviction_event(
    tenant_id: &str,
    node_id: &str,
    region: &str,
    eviction: CapacityEviction,
) -> SegmentEvictionEvent {
    SegmentEvictionEvent {
        // A segment evicts once, so node + segment is a natural idempotency
        // key: a redelivered batch collapses in the control plane's
        // ReplacingMergeTree exactly like a retried usage rollup.
        event_id: format!("evict:{node_id}:{}", eviction.segment_id),
        tenant_id: tenant_id.to_owned(),
        node_id: node_id.to_owned(),
        region: region.to_owned(),
        segment_id: eviction.segment_id,
        reason: "capacity".to_owned(),
        evicted_at_unix_ms: eviction.evicted_at_ms,
        segment_created_at_unix_ms: eviction.segment_created_at_ms,
        newest_content_at_unix_ms: eviction.newest_content_at_ms,
        artifact_count: eviction.artifact_count,
        bytes: eviction.bytes,
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

    fn capacity_eviction(segment_id: &str) -> CapacityEviction {
        CapacityEviction {
            segment_id: segment_id.to_owned(),
            segment_created_at_ms: 1_000,
            newest_content_at_ms: 2_000,
            evicted_at_ms: 90_000,
            artifact_count: 3,
            bytes: 512,
        }
    }

    #[test]
    fn eviction_event_maps_fields_and_derives_a_stable_id() {
        let event = eviction_event(
            "acme",
            "node-1.kura.local",
            "eu-central",
            capacity_eviction("segment-1"),
        );

        assert_eq!(event.event_id, "evict:node-1.kura.local:segment-1");
        assert_eq!(event.tenant_id, "acme");
        assert_eq!(event.node_id, "node-1.kura.local");
        assert_eq!(event.region, "eu-central");
        assert_eq!(event.segment_id, "segment-1");
        assert_eq!(event.reason, "capacity");
        assert_eq!(event.evicted_at_unix_ms, 90_000);
        assert_eq!(event.segment_created_at_unix_ms, 1_000);
        assert_eq!(event.newest_content_at_unix_ms, 2_000);
        assert_eq!(event.artifact_count, 3);
        assert_eq!(event.bytes, 512);
    }

    #[test]
    fn stashed_evictions_survive_a_failed_delivery_and_leave_after_a_covered_one() {
        let usage = test_usage(60, 100);

        usage.stash_evictions(
            "acme",
            vec![
                capacity_eviction("segment-1"),
                capacity_eviction("segment-2"),
            ],
        );
        let first_batch = usage.undelivered_evictions(MAX_EVICTIONS_PER_DELIVERY);
        assert_eq!(first_batch.len(), 2);

        // Stashed after the batch was built: a covering delivery must not
        // discard it.
        usage.stash_evictions("acme", vec![capacity_eviction("segment-3")]);

        usage.discard_delivered_evictions(first_batch.len());

        let remaining = usage.undelivered_evictions(MAX_EVICTIONS_PER_DELIVERY);
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].segment_id, "segment-3");
    }

    #[test]
    fn stash_evictions_caps_the_queue_by_dropping_oldest() {
        let usage = test_usage(60, 100);

        let evictions = (0..(MAX_UNDELIVERED_EVICTIONS + 3))
            .map(|index| capacity_eviction(&format!("segment-{index}")))
            .collect();
        usage.stash_evictions("acme", evictions);

        let undelivered = usage.undelivered_evictions(MAX_UNDELIVERED_EVICTIONS);
        assert_eq!(undelivered.len(), MAX_UNDELIVERED_EVICTIONS);
        assert_eq!(undelivered[0].segment_id, "segment-3");
    }

    #[test]
    fn one_delivery_carries_at_most_the_cap_and_discards_only_its_prefix() {
        let usage = test_usage(60, 100);
        let evictions = (0..(MAX_EVICTIONS_PER_DELIVERY + 50))
            .map(|index| capacity_eviction(&format!("segment-{index}")))
            .collect();
        usage.stash_evictions("acme", evictions);

        let batch = usage.undelivered_evictions(MAX_EVICTIONS_PER_DELIVERY);
        assert_eq!(batch.len(), MAX_EVICTIONS_PER_DELIVERY);
        assert_eq!(batch[0].segment_id, "segment-0");

        usage.discard_delivered_evictions(batch.len());

        let remaining = usage.undelivered_evictions(MAX_EVICTIONS_PER_DELIVERY);
        assert_eq!(remaining.len(), 50);
        assert_eq!(
            remaining[0].segment_id,
            format!("segment-{MAX_EVICTIONS_PER_DELIVERY}")
        );
    }

    #[test]
    fn storage_snapshot_is_due_initially_and_backs_off_after_a_delivery() {
        let usage = test_usage(60, 100);

        assert!(usage.storage_snapshot_due());
        usage.mark_snapshot_delivered();
        assert!(!usage.storage_snapshot_due());
    }

    #[test]
    fn storage_snapshot_event_ids_are_stable_within_an_interval_window() {
        let usage = test_usage(60, 100);
        let data = StorageSnapshotData {
            ring_budget_bytes: 5 * 512 * 1024 * 1024,
            desired_segment_count: 5,
            live_segment_count: 3,
            live_segment_bytes: 1024,
            oldest_segment_created_at_ms: Some(1_000),
            newest_content_at_ms: Some(2_000),
        };
        let interval_secs = STORAGE_SNAPSHOT_INTERVAL.as_secs();

        let first = usage.storage_snapshot_event("acme", data.clone(), interval_secs * 7);
        let same_window = usage.storage_snapshot_event("acme", data.clone(), interval_secs * 7 + 1);
        let next_window = usage.storage_snapshot_event("acme", data.clone(), interval_secs * 8);

        assert_eq!(first.event_id, "snapshot:node-1.kura.local:7");
        assert_eq!(first.event_id, same_window.event_id);
        assert_ne!(first.event_id, next_window.event_id);
        assert_eq!(first.tenant_id, "acme");
        assert_eq!(first.region, "test-region");
        assert_eq!(first.captured_at_unix_ms, interval_secs * 7 * 1_000);
        assert_eq!(first.ring_budget_bytes, data.ring_budget_bytes);
        assert_eq!(first.live_segment_bytes, 1024);
        assert_eq!(first.oldest_segment_created_at_unix_ms, Some(1_000));
        assert_eq!(first.newest_content_at_unix_ms, Some(2_000));
    }

    #[test]
    fn usage_batch_omits_storage_fields_when_empty() {
        let batch = UsageBatch {
            schema_version: 1,
            node_id: "node-1.kura.local".to_owned(),
            region: "test-region".to_owned(),
            events: Vec::new(),
            evictions: Vec::new(),
            storage_snapshots: Vec::new(),
        };

        let json = serde_json::to_string(&batch).expect("batch should serialize");
        assert!(!json.contains("evictions"));
        assert!(!json.contains("storage_snapshots"));

        let populated = UsageBatch {
            evictions: vec![eviction_event(
                "acme",
                "node-1.kura.local",
                "test-region",
                capacity_eviction("segment-1"),
            )],
            ..batch
        };
        let json = serde_json::to_string(&populated).expect("batch should serialize");
        assert!(json.contains("\"evictions\""));
        assert!(json.contains("evict:node-1.kura.local:segment-1"));
    }
}
